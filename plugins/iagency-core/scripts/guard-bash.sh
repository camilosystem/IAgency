#!/usr/bin/env bash
# guard-bash.sh — Guardarraíl de comandos para la fábrica de agentes IAgency.
#
# Se ejecuta como hook PreToolUse sobre la herramienta Bash. Recibe por stdin el
# JSON del evento y decide si el comando se ejecuta.
#
# Salida:
#   exit 0            -> el flujo de permisos normal continúa
#   JSON deny + exit 0 -> se bloquea con una razón que el agente puede leer
#
# Este guardarraíl es la ÚLTIMA línea de defensa, no la primera. La primera es el
# aislamiento del contenedor. Nunca dependas solo de esto.

set -uo pipefail

# Sin jq no se puede leer el evento ni construir la respuesta. Un control que no
# puede comprobar nada NO aprueba: se detiene y dice por qué. En Windows con Git
# Bash jq no viene de fábrica, y eso hacía que el guardarraíl dejara pasar TODO.
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Guardarrail inoperante: falta jq en esta maquina, asi que no puede evaluar nada. Se deniega por seguridad. Instalalo y reintenta: scoop install jq (Windows), brew install jq (Mac), apt install jq (Linux)."}}'
  exit 0
fi

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"
LOG="${IAGENCY_AUDIT_LOG:-${IAGENCY_LOG_DIR:-${HOME:-/tmp}/.iagency/logs}/comandos.log}"

{ mkdir -p "$(dirname "$LOG")" && printf '%s\t%s\t%s\n' "$(date -Is)" "${IAGENCY_TAREA:-sin-tarea}" "$CMD" >> "$LOG"; } 2>/dev/null || true

denegar() {
  jq -nc --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# ---------------------------------------------------------------------------
# 1. Destrucción del sistema o del área de trabajo
# ---------------------------------------------------------------------------
# Ojo con el patrón: "rm -rf /" a secas hace match con "rm -rf /tmp/x", que es
# una limpieza legítima. Se bloquea la raíz desnuda, el home, y los directorios
# del sistema — no cualquier ruta absoluta.
if printf '%s' "$CMD" | grep -Eq 'rm[[:space:]]+(-[a-zA-Z]*[rf][a-zA-Z]*[[:space:]]+)+(/|/\*|~|~/\*|\$HOME|\.)[[:space:]]*$'; then
  denegar "Borrado de la raíz o del directorio personal bloqueado. Borra rutas concretas."
fi
# Directorios del sistema: se bloquean ellos y todo lo que cuelgue de ellos.
if printf '%s' "$CMD" | grep -Eq 'rm[[:space:]]+-[a-zA-Z]*[rf][a-zA-Z]*[[:space:]]+/(etc|usr|var|bin|sbin|lib|lib64|boot|dev|sys|proc|root)(/|[[:space:]]|$)'; then
  denegar "Borrado dentro de un directorio del sistema bloqueado."
fi
# Directorios de trabajo: se bloquea borrar el directorio raíz, pero NO lo que
# cuelga de él — ahí viven los worktrees y los repos, y limpiarlos es legítimo.
if printf '%s' "$CMD" | grep -Eq 'rm[[:space:]]+-[a-zA-Z]*[rf][a-zA-Z]*[[:space:]]+/(opt|home|srv|mnt|media)/?[[:space:]]*$'; then
  denegar "Borrado de un directorio raíz de trabajo bloqueado. Borra la subcarpeta concreta."
fi
case "$CMD" in
  *"mkfs"*|*"dd if="*"of=/dev/"*|*":(){"*)
    denegar "Comando destructivo de disco o fork bomb bloqueado." ;;
  *"chmod -R 777"*|*"chown -R root"*)
    denegar "Cambio masivo de permisos bloqueado." ;;
esac

# ---------------------------------------------------------------------------
# 2. Historia de git y ramas protegidas
# ---------------------------------------------------------------------------
case "$CMD" in
  *"git push"*"--force"*|*"git push -f"*)
    denegar "git push --force está prohibido. Si de verdad hace falta, lo hace un humano." ;;
  *"git push"*" main"*|*"git push"*" master"*|*"git push origin main"*|*"git push origin master"*)
    denegar "No se empuja a main/master. Trabaja en tu rama y deja la integración al humano." ;;
  *"git reset --hard"*"origin"*|*"git filter-branch"*|*"git filter-repo"*)
    denegar "Reescritura de historia bloqueada." ;;
  *"git config --global"*)
    denegar "No modifiques la configuración global de git." ;;
esac

# ---------------------------------------------------------------------------
# 3. Persistencia: la vía por la que un repositorio hostil sobrevive a la sesión
# ---------------------------------------------------------------------------
# Las dos reglas de esta sección cortan con criterios DISTINTOS. No las leas como
# una sola, porque no lo son:
#
#   3a NO distingue lectura de escritura, y es a propósito. Bloquea CUALQUIER
#      invocación de crontab en posición de comando —incluida `crontab -l`, que solo
#      lee— y systemctl enable/disable/mask. Separar aquí lectura de escritura
#      obligaría a interpretar banderas, y una bandera mal entendida deja pasar una
#      escritura. Un agente no tiene por qué consultar el crontab; si lo necesita,
#      lo pide. `systemctl status` sí pasa: no está en la lista.
#
#   3b sí es un criterio de escritura: bloquea las redirecciones y los comandos que
#      modifican las rutas de persistencia, y deja pasar leerlas. `cat ~/.bashrc`
#      pasa; la misma ruta con una redirección de anexado, no.
#
# Lo que las dos comparten es que miran la POSICIÓN, no la mera aparición del texto:
# `echo "crontab -l" > notas.txt` pasa, porque ahí la cadena es un argumento.
#
# PERO ojo con el alcance de esa afirmación, porque tiene un hueco medido: grep
# evalúa LÍNEA A LÍNEA, así que el ancla `^` es el principio de CADA línea, no del
# comando. Un heredoc cuya línea empiece por `systemctl enable` se bloquea aunque
# solo se esté escribiendo un archivo para que lo ejecute un humano después. Es un
# falso positivo conocido y se acepta: el error cae del lado seguro, y la salida se
# consigue igual escribiendo esa línea de otra forma. No aflojes el ancla sin
# sustituirla por algo que distinga de verdad escribir un texto de ejecutarlo.

# 3a. crontab y systemctl como comando ejecutado (al inicio o tras un separador)
if printf '%s' "$CMD" | grep -Eq '(^|[;&|(]|&&|\|\|)[[:space:]]*(crontab|systemctl[[:space:]]+(enable|disable|mask))([[:space:]]|$)'; then
  denegar "Un agente no programa tareas ni habilita servicios. Si el trabajo lo necesita, entrégalo como script para que lo ejecute un humano."
fi

# 3b. escritura sobre rutas de persistencia
RUTAS_PERSIST='(\.git/hooks|\.git/config|\.claude/|\.mcp\.json|\.bashrc|\.zshrc|\.profile|\.bash_profile|authorized_keys)'
if printf '%s' "$CMD" | grep -Eq "(>>?[[:space:]]*[^|;&]*$RUTAS_PERSIST)"; then
  denegar "Redirección de escritura sobre un punto de persistencia. Prohibido para agentes."
fi
if printf '%s' "$CMD" | grep -Eq "(^|[;&|(]|&&|\|\|)[[:space:]]*(tee|sed[[:space:]]+-i|install|chmod|chown|ln)[[:space:]][^|;&]*$RUTAS_PERSIST"; then
  denegar "Modificación de un punto de persistencia (hooks de git, .claude, .mcp.json, arranque del shell, claves SSH). Prohibido para agentes."
fi

# ---------------------------------------------------------------------------
# 4. Secretos y credenciales
# ---------------------------------------------------------------------------
case "$CMD" in
  *".ssh/id_"*|*".aws/credentials"*|*".config/gcloud"*|*"kubeconfig"*)
    denegar "Acceso a credenciales bloqueado. Los agentes no necesitan llaves de larga vida." ;;
  *"env"*"|"*"curl"*|*"printenv"*"|"*"curl"*|*"cat"*".env"*"|"*"curl"*)
    denegar "Envío de variables de entorno por red bloqueado (posible exfiltración de secretos)." ;;
esac

# ---------------------------------------------------------------------------
# 5. Descargar y ejecutar en un paso
# ---------------------------------------------------------------------------
case "$CMD" in
  *"curl"*"|"*"sh"*|*"curl"*"|"*"bash"*|*"wget"*"|"*"sh"*|*"wget"*"|"*"bash"*|*"iwr"*"iex"*)
    denegar "Descargar y ejecutar en un solo paso está prohibido. Descarga, revisa el archivo, y ejecútalo aparte." ;;
esac

# ---------------------------------------------------------------------------
# 6. Escrituras contra bases de datos y sistemas del cliente
# ---------------------------------------------------------------------------
UPPER="$(printf '%s' "$CMD" | tr '[:lower:]' '[:upper:]')"
case "$UPPER" in
  *"DROP TABLE"*|*"DROP DATABASE"*|*"TRUNCATE "*|*"DELETE FROM"*|*"UPDATE "*" SET "*)
    if [ "${IAGENCY_ENTORNO:-pruebas}" != "pruebas" ]; then
      denegar "Escritura SQL fuera del entorno de pruebas. Entrega un script de migración para que lo ejecute un humano."
    fi ;;
esac
case "$CMD" in
  *"PROD"*|*"produccion"*|*"production"*)
    case "$CMD" in
      *sqlcmd*|*psql*|*mysql*|*mongosh*)
        denegar "Conexión aparentemente dirigida a producción. Usa la réplica o el entorno de pruebas." ;;
    esac ;;
esac

# ---------------------------------------------------------------------------
# 7. Desactivar las propias defensas
# ---------------------------------------------------------------------------
case "$CMD" in
  *"--dangerously-skip-permissions"*|*"dangerouslyDisableSandbox"*|*"iptables -F"*|*"nft flush"*|*"ufw disable"*)
    denegar "Un agente no puede desactivar los controles de la fábrica." ;;
  *"--no-verify"*)
    denegar "No se saltan los ganchos de verificación de git." ;;
esac

exit 0
