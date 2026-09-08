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

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"
LOG="${IAGENCY_AUDIT_LOG:-/var/log/iagency/comandos.log}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
printf '%s\t%s\t%s\n' "$(date -Is)" "${IAGENCY_TAREA:-sin-tarea}" "$CMD" >> "$LOG" 2>/dev/null || true

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
case "$CMD" in
  *"rm -rf /"*|*"rm -fr /"*|*"rm -rf ~"*|*"rm -rf \$HOME"*)
    denegar "Borrado masivo bloqueado. Si necesitas limpiar, borra rutas concretas dentro del worktree." ;;
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
case "$CMD" in
  *".git/hooks"*|*".claude/agents"*|*".claude/settings"*|*".mcp.json"*|*"crontab"*|*"systemctl enable"*)
    case "$CMD" in
      *cat*|*ls*|*grep*|*head*|*tail*|*diff*) : ;;  # leer está bien
      *) denegar "Escritura sobre un punto de persistencia (hooks de git, .claude, .mcp.json, cron, systemd). Prohibido para agentes." ;;
    esac ;;
  *">>"*".bashrc"*|*">>"*".zshrc"*|*">>"*".profile"*|*">"*".bashrc"*)
    denegar "No modifiques los archivos de arranque del shell." ;;
esac

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
