#!/usr/bin/env bash
# bootstrap-servidor.sh — Prepara un servidor Ubuntu 24.04 limpio como nodo de la
# fábrica de agentes IAgency.
#
# Ejecutar UNA vez, como root, en un servidor recién aprovisionado y dedicado:
#
#   bash bootstrap-servidor.sh
#
# Después de esto NO se vuelve a entrar como root para trabajar: todo corre como
# el usuario 'fabrica'.
#
# Qué deja montado:
#   - usuario no root 'fabrica' (Claude Code se niega a correr con permisos
#     amplios si es root)
#   - Docker con el daemon del sistema, y 'fabrica' en el grupo docker
#   - proxy Squid con allowlist POR DOMINIO (el firewall de un proveedor de nube
#     es capa 3/4 y no puede filtrar dominios detrás de CDN)
#   - cortafuegos que obliga a todo contenedor a salir SOLO por ese proxy
#   - Node LTS, .NET 8 SDK, Python y Claude Code
#   - directorios de estado, auditoría y worktrees
#
# NOTA SOBRE EL MODELO DE AISLAMIENTO
# Se usa Docker con daemon de sistema, no rootless. Rootless añade una capa
# contra el escape de contenedor, pero rompe el control de salida a internet:
# el contenedor deja de ver la puerta de enlace del host de forma predecible y
# el filtrado por proxy se vuelve frágil. Entre un anillo 1 marginalmente mejor
# con el anillo 2 roto, y un anillo 1 estándar con el anillo 2 sólido, esto
# segundo protege más: la exfiltración de código de clientes es el riesgo real,
# no el escape de contenedor. Los agentes siguen corriendo como usuario NO root
# dentro del contenedor, con capacidades eliminadas y sistema de archivos de
# solo lectura salvo su worktree.
#
# Pertenecer al grupo docker equivale a root en el host. Por eso 'fabrica' es un
# usuario de servicio de esta máquina y nada más: no guardes ahí credenciales de
# clientes ni llaves que sirvan en otro sitio.

set -euo pipefail

USUARIO="${IAGENCY_USUARIO:-fabrica}"
BASE="/opt/iagency"
RED_AGENTES="172.20.0.0/16"
GW_AGENTES="172.20.0.1"

[ "$(id -u)" -eq 0 ] || { echo "Ejecuta esto como root."; exit 1; }

echo "==> 1/10  Base del sistema"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y
apt-get install -y \
  curl wget git jq ripgrep build-essential ca-certificates gnupg unzip \
  squid iptables iptables-persistent netfilter-persistent \
  fail2ban unattended-upgrades tmux htop dnsutils

echo "==> 2/10  Usuario no root"
if ! id "$USUARIO" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$USUARIO"
fi

echo "==> 3/10  Directorios de la fábrica"
mkdir -p "$BASE"/{repos,worktrees,estado,contratos,entregas,logs,infra}
mkdir -p /var/log/iagency /var/lib/iagency
chown -R "$USUARIO:$USUARIO" "$BASE" /var/log/iagency /var/lib/iagency

echo "==> 4/10  Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
  rm -f /tmp/get-docker.sh
fi
systemctl enable --now docker
usermod -aG docker "$USUARIO"

echo "==> 5/10  Red de los agentes"
docker network inspect iagency >/dev/null 2>&1 || \
  docker network create --subnet "$RED_AGENTES" --gateway "$GW_AGENTES" iagency

echo "==> 6/10  Runtimes"
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs
apt-get install -y dotnet-sdk-8.0 || echo "AVISO: instala el SDK de .NET a mano si tu proyecto lo necesita"
apt-get install -y python3 python3-pip python3-venv
pip3 install --break-system-packages pyyaml || true

echo "==> 7/10  Claude Code"
npm install -g @anthropic-ai/claude-code

echo "==> 8/10  Proxy de egress con allowlist por dominio"
cat > /etc/squid/dominios-permitidos.txt <<'EOF'
.anthropic.com
.claude.com
.github.com
.githubusercontent.com
.npmjs.org
.npmjs.com
.nodesource.com
.nuget.org
.pypi.org
.pythonhosted.org
.microsoft.com
.mozilla.org
.docker.io
.docker.com
.ubuntu.com
.debian.org
EOF

cat > /etc/squid/squid.conf <<EOF
http_port 3128

acl red_agentes src $RED_AGENTES
acl dominios_permitidos dstdomain "/etc/squid/dominios-permitidos.txt"
acl puertos_ssl port 443
acl CONNECT method CONNECT

http_access deny !red_agentes
http_access allow CONNECT dominios_permitidos puertos_ssl
http_access allow dominios_permitidos
http_access deny all

access_log /var/log/squid/access.log squid
cache deny all
forwarded_for delete
via off
EOF

mkdir -p /var/log/squid
chown proxy:proxy /var/log/squid || true
# Validar ANTES de arrancar: un error de sintaxis se ve en claro aquí, mientras
# que al arrancar solo deja un "control process exited" que no dice nada.
squid -k parse || { echo "Configuracion de Squid invalida. Revisa el error de arriba."; exit 1; }
systemctl enable squid
systemctl restart squid
ln -sf /var/log/squid/access.log /var/log/iagency/proxy.log

echo "==> 9/10  Cortafuegos"
# El contenedor solo puede hablar con el proxy del host. Todo lo demás se corta.
#
# Dos cadenas distintas, y confundirlas es el error clásico:
#   INPUT       -> tráfico del contenedor HACIA el host (el proxy en :3128)
#   DOCKER-USER -> tráfico del contenedor HACIA fuera (lo que hay que cortar).
# Docker inserta sus propias reglas de reenvío al arrancar; DOCKER-USER es la
# única cadena que Docker respeta y no sobrescribe.

iptables -C INPUT -s "$RED_AGENTES" -p tcp --dport 3128 -j ACCEPT 2>/dev/null || \
  iptables -I INPUT 1 -s "$RED_AGENTES" -p tcp --dport 3128 -j ACCEPT

iptables -C INPUT -s "$RED_AGENTES" -p udp --dport 53 -j ACCEPT 2>/dev/null || \
  iptables -I INPUT 2 -s "$RED_AGENTES" -p udp --dport 53 -j ACCEPT

iptables -C DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN 2>/dev/null || \
  iptables -I DOCKER-USER 1 -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

iptables -C DOCKER-USER -s "$RED_AGENTES" -j DROP 2>/dev/null || \
  iptables -A DOCKER-USER -s "$RED_AGENTES" -j DROP

netfilter-persistent save

echo "==> 10/10  Endurecimiento básico"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh
systemctl enable --now fail2ban
echo 'APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades
echo 'APT::Periodic::Update-Package-Lists "1";' >> /etc/apt/apt.conf.d/20auto-upgrades

# La clave de root sirve para el usuario de trabajo
if [ -f /root/.ssh/authorized_keys ]; then
  mkdir -p "/home/$USUARIO/.ssh"
  cp /root/.ssh/authorized_keys "/home/$USUARIO/.ssh/authorized_keys"
  chown -R "$USUARIO:$USUARIO" "/home/$USUARIO/.ssh"
  chmod 700 "/home/$USUARIO/.ssh"
  chmod 600 "/home/$USUARIO/.ssh/authorized_keys"
fi

cat <<FIN

===========================================================================
Nodo de la fábrica listo.

Entra como el usuario de trabajo (desde tu máquina, no desde aquí):

    ssh $USUARIO@<IP>

Y sigue con la lista de VERIFICACION.md. Las dos pruebas que deciden si el
perímetro está bien:

  1) Esta DEBE fallar (sin salida directa a internet):
       docker run --rm --network iagency curlimages/curl:latest \\
         curl -s -m 8 https://example.com

  2) Esta DEBE responder un código HTTP:
       docker run --rm --network iagency -e HTTPS_PROXY=http://$GW_AGENTES:3128 \\
         curlimages/curl:latest \\
         curl -s -o /dev/null -w '%{http_code}\\n' -m 15 https://api.anthropic.com

Si la 1 devuelve HTML o la 2 no responde, NO sigas: el perímetro no está.

Registro del proxy, para la auditoría diaria:
    /var/log/iagency/proxy.log
===========================================================================
FIN
