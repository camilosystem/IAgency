#!/usr/bin/env bash
# reparar-nodo.sh — Arregla el arranque de Squid y completa los pasos 9 y 10 del
# bootstrap, que quedaron sin ejecutar cuando el paso 8 falló.
#
# Ejecutar como root en el nodo:
#   bash /root/reparar-nodo.sh
#
# Qué corrige respecto del bootstrap original:
#   - quita 'dns_v4_first', eliminada en Squid 6 (la que trae Ubuntu 24.04)
#   - deja el registro del proxy en /var/log/squid, donde el usuario 'proxy' SÍ
#     tiene permiso de escritura, y lo enlaza a /var/log/iagency/proxy.log para
#     que la auditoría lo siga encontrando donde lo espera
#   - valida la configuración con 'squid -k parse' ANTES de arrancar, para que un
#     error de sintaxis se vea en claro en lugar de un "control process exited"
#   - aplica el cortafuegos y el endurecimiento que no llegaron a correr

set -uo pipefail

RED_AGENTES="172.20.0.0/16"
GW_AGENTES="172.20.0.1"
USUARIO="${IAGENCY_USUARIO:-fabrica}"

[ "$(id -u)" -eq 0 ] || { echo "Ejecuta esto como root."; exit 1; }

echo "==================================================================="
echo "  DIAGNÓSTICO PREVIO"
echo "==================================================================="
systemctl status squid --no-pager -l 2>&1 | head -20 || true
echo "--- últimas líneas del journal de squid ---"
journalctl -u squid --no-pager -n 20 2>&1 | tail -20 || true
echo

echo "==================================================================="
echo "  1/5  Reescribiendo la configuración de Squid"
echo "==================================================================="
mkdir -p /var/log/squid /var/log/iagency
chown proxy:proxy /var/log/squid 2>/dev/null || true

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

echo "==================================================================="
echo "  2/5  Validando la configuración"
echo "==================================================================="
if ! squid -k parse 2>&1 | tee /tmp/squid-parse.txt; then
  echo
  echo "!!! La configuración de Squid sigue siendo inválida."
  echo "!!! El error exacto está arriba y en /tmp/squid-parse.txt."
  echo "!!! NO se aplicó el cortafuegos. Pega esa salida y lo resolvemos."
  exit 1
fi
if grep -qiE 'ERROR|FATAL' /tmp/squid-parse.txt; then
  echo
  echo "!!! Squid reportó errores al analizar la configuración. Revisa arriba."
  exit 1
fi
echo "Configuración válida."

echo "==================================================================="
echo "  3/5  Arrancando Squid"
echo "==================================================================="
squid -z 2>/dev/null || true
sleep 2
systemctl enable squid
systemctl restart squid
sleep 3
if ! systemctl is-active --quiet squid; then
  echo "!!! Squid sigue sin arrancar. Estado:"
  systemctl status squid --no-pager -l | head -30
  journalctl -u squid --no-pager -n 30
  exit 1
fi
echo "Squid activo y escuchando:"
ss -lntp | grep 3128 || echo "AVISO: no se ve el puerto 3128 escuchando"

# Enlace para que la auditoría encuentre el registro donde lo espera
ln -sf /var/log/squid/access.log /var/log/iagency/proxy.log

echo "==================================================================="
echo "  4/5  Cortafuegos (el paso 9 que no llegó a correr)"
echo "==================================================================="
# INPUT       -> tráfico del contenedor HACIA el host (el proxy en :3128)
# DOCKER-USER -> tráfico del contenedor HACIA fuera (lo que hay que cortar)
docker network inspect iagency >/dev/null 2>&1 || \
  docker network create --subnet "$RED_AGENTES" --gateway "$GW_AGENTES" iagency

iptables -C INPUT -s "$RED_AGENTES" -p tcp --dport 3128 -j ACCEPT 2>/dev/null || \
  iptables -I INPUT 1 -s "$RED_AGENTES" -p tcp --dport 3128 -j ACCEPT

iptables -C INPUT -s "$RED_AGENTES" -p udp --dport 53 -j ACCEPT 2>/dev/null || \
  iptables -I INPUT 2 -s "$RED_AGENTES" -p udp --dport 53 -j ACCEPT

iptables -C DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN 2>/dev/null || \
  iptables -I DOCKER-USER 1 -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

iptables -C DOCKER-USER -s "$RED_AGENTES" -j DROP 2>/dev/null || \
  iptables -A DOCKER-USER -s "$RED_AGENTES" -j DROP

netfilter-persistent save
echo "Reglas aplicadas:"
iptables -S DOCKER-USER

echo "==================================================================="
echo "  5/5  Endurecimiento (el paso 10)"
echo "==================================================================="
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh
systemctl enable --now fail2ban
echo 'APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades
echo 'APT::Periodic::Update-Package-Lists "1";' >> /etc/apt/apt.conf.d/20auto-upgrades

if [ -f /root/.ssh/authorized_keys ] && id "$USUARIO" >/dev/null 2>&1; then
  mkdir -p "/home/$USUARIO/.ssh"
  cp /root/.ssh/authorized_keys "/home/$USUARIO/.ssh/authorized_keys"
  chown -R "$USUARIO:$USUARIO" "/home/$USUARIO/.ssh"
  chmod 700 "/home/$USUARIO/.ssh"
  chmod 600 "/home/$USUARIO/.ssh/authorized_keys"
  echo "Clave SSH copiada al usuario $USUARIO."
fi

echo
echo "==================================================================="
echo "  VERIFICACIÓN DEL PERÍMETRO"
echo "==================================================================="
echo
echo "--- Prueba 1: salida directa a internet.  DEBE FALLAR ---"
if docker run --rm --network iagency curlimages/curl:latest \
     curl -s -m 8 -o /dev/null -w '%{http_code}\n' https://example.com 2>/dev/null; then
  echo ">>> FALLO DE SEGURIDAD: el contenedor salió a internet sin el proxy."
  echo ">>> NO uses este nodo hasta resolverlo."
  RES1=MAL
else
  echo "OK — la salida directa está bloqueada (así debe ser)."
  RES1=BIEN
fi

echo
echo "--- Prueba 2: salida por el proxy.  DEBE RESPONDER UN CÓDIGO HTTP ---"
COD=$(docker run --rm --network iagency -e HTTPS_PROXY=http://$GW_AGENTES:3128 \
        curlimages/curl:latest \
        curl -s -o /dev/null -w '%{http_code}' -m 20 https://api.anthropic.com 2>/dev/null || echo "000")
echo "Código recibido: $COD"
if [ "$COD" != "000" ] && [ -n "$COD" ]; then
  echo "OK — el proxy deja pasar lo permitido."
  RES2=BIEN
else
  echo ">>> El proxy no dejó pasar. Revisa /var/log/squid/access.log"
  RES2=MAL
fi

echo
echo "--- Prueba 3: dominio NO permitido por el proxy.  DEBE DAR 403 ---"
COD3=$(docker run --rm --network iagency -e HTTPS_PROXY=http://$GW_AGENTES:3128 \
         curlimages/curl:latest \
         curl -s -o /dev/null -w '%{http_code}' -m 15 https://pastebin.com 2>/dev/null || echo "bloqueado")
echo "Resultado: $COD3"

echo
echo "==================================================================="
echo "  RESUMEN:  prueba1=$RES1   prueba2=$RES2"
if [ "$RES1" = "BIEN" ] && [ "$RES2" = "BIEN" ]; then
  echo "  PERÍMETRO VERIFICADO. Se puede continuar."
else
  echo "  PERÍMETRO INCOMPLETO. No corras agentes todavía."
fi
echo "==================================================================="
