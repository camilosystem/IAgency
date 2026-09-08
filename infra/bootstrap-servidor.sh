#!/usr/bin/env bash
# bootstrap-servidor.sh — Prepara un servidor Ubuntu 24.04 limpio como nodo de la
# fábrica de agentes IAgency.
#
# Ejecutar UNA vez, como root, en un servidor recién aprovisionado y dedicado.
# Después de esto NO se vuelve a entrar como root: todo corre como el usuario 'fabrica'.
#
#   bash bootstrap-servidor.sh
#
# Qué deja montado:
#   - usuario no root 'fabrica' (Claude Code se niega a correr sin permisos como root)
#   - Docker con rootless para el usuario 'fabrica'
#   - proxy de egress con allowlist por dominio (Squid con filtrado por SNI/CONNECT)
#   - cortafuegos: el contenedor solo puede salir a través del proxy
#   - directorios de estado, auditoría y worktrees
#   - Node LTS, .NET SDK, Python y Claude Code

set -euo pipefail

USUARIO="${IAGENCY_USUARIO:-fabrica}"
BASE="/opt/iagency"

echo "==> 1/9  Base del sistema"
apt-get update
apt-get upgrade -y
apt-get install -y \
  curl wget git jq ripgrep build-essential ca-certificates gnupg unzip \
  uidmap dbus-user-session slirp4netns fuse-overlayfs \
  squid nftables fail2ban unattended-upgrades tmux htop

echo "==> 2/9  Usuario no root"
if ! id "$USUARIO" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$USUARIO"
fi
loginctl enable-linger "$USUARIO"

echo "==> 3/9  Directorios de la fábrica"
mkdir -p "$BASE"/{repos,worktrees,estado,contratos,entregas}
mkdir -p /var/log/iagency /var/lib/iagency
chown -R "$USUARIO:$USUARIO" "$BASE" /var/log/iagency /var/lib/iagency

echo "==> 4/9  Docker (rootless para $USUARIO)"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl disable --now docker.service docker.socket 2>/dev/null || true
sudo -iu "$USUARIO" dockerd-rootless-setuptool.sh install || true

echo "==> 5/9  Runtimes"
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs
apt-get install -y dotnet-sdk-8.0 || echo "AVISO: instala el SDK de .NET manualmente si tu proyecto lo necesita"
apt-get install -y python3 python3-pip python3-venv

echo "==> 6/9  Claude Code"
npm install -g @anthropic-ai/claude-code
# El sandbox-runtime de Anthropic: aislamiento del proceso completo + allowlist de red.
npm install -g @anthropic-ai/sandbox-runtime || echo "AVISO: sandbox-runtime no instalado"

echo "==> 7/9  Proxy de egress con allowlist por dominio"
# El cortafuegos del proveedor de nube (Hetzner, DigitalOcean) es L3/L4 y NO filtra por
# dominio. Los dominios que necesitan los agentes están detrás de CDN con IP rotatoria,
# así que la allowlist tiene que hacerse en un proxy, no por IP.
install -d -m 0755 /etc/squid
cat > /etc/squid/dominios-permitidos.txt <<'EOF'
.anthropic.com
.claude.com
.github.com
.githubusercontent.com
.npmjs.org
.npmjs.com
.nuget.org
.pypi.org
.pythonhosted.org
.microsoft.com
.mozilla.org
.nodesource.com
.docker.io
.docker.com
EOF

cat > /etc/squid/squid.conf <<'EOF'
http_port 3128
acl red_agentes src 172.20.0.0/16
acl dominios_permitidos dstdomain "/etc/squid/dominios-permitidos.txt"
acl puertos_ssl port 443
acl CONNECT method CONNECT

http_access deny !red_agentes
http_access allow CONNECT dominios_permitidos puertos_ssl
http_access allow dominios_permitidos
http_access deny all

access_log /var/log/iagency/proxy.log
cache deny all
forwarded_for delete
via off
EOF
systemctl enable --now squid
systemctl restart squid

echo "==> 8/9  Cortafuegos"
cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iif lo accept
    tcp dport 22 accept
    ip saddr 172.20.0.0/16 tcp dport 3128 accept
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    # La red de los agentes NO sale a internet directamente: solo por el proxy.
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}
EOF
systemctl enable --now nftables
nft -f /etc/nftables.conf

echo "==> 9/9  Endurecimiento básico"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh
systemctl enable --now fail2ban
dpkg-reconfigure -f noninteractive unattended-upgrades

cat <<FIN

===========================================================================
Nodo de la fábrica listo.

Siguientes pasos, uno por uno:

  1) Entra como el usuario de la fábrica:
       su - $USUARIO

  2) Deja la clave de API en el entorno del usuario (NUNCA en el repositorio):
       echo 'export ANTHROPIC_API_KEY=...' >> ~/.bashrc

  3) Crea la red docker de los agentes:
       docker network create --subnet 172.20.0.0/16 iagency

  4) Construye la imagen del agente:
       docker build -t iagency/agente:1 -f $BASE/infra/Dockerfile.agente $BASE/infra

  5) Verifica que el egress está cerrado (esto DEBE fallar):
       docker run --rm --network iagency iagency/agente:1 curl -s -m 5 https://example.com

  6) Verifica que el proxy sí deja pasar lo permitido (esto DEBE funcionar):
       docker run --rm --network iagency -e HTTPS_PROXY=http://172.20.0.1:3128 \\
         iagency/agente:1 curl -s -o /dev/null -w '%{http_code}' https://api.anthropic.com

Registro del proxy (revísalo en la auditoría diaria):
  /var/log/iagency/proxy.log
===========================================================================
FIN
