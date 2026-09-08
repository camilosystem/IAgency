#!/usr/bin/env bash
# guard-escritura.sh — Guardarraíl de escritura de archivos.
# Hook PreToolUse sobre Write|Edit|NotebookEdit.
#
# Impide que un agente escriba fuera de su worktree o toque puntos de persistencia
# y archivos de configuración de la propia fábrica.

set -uo pipefail

INPUT="$(cat)"
RUTA="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')"
AREA="${IAGENCY_WORKTREE:-$PWD}"
LOG="${IAGENCY_AUDIT_LOG:-/var/log/iagency/escrituras.log}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
printf '%s\t%s\t%s\n' "$(date -Is)" "${IAGENCY_TAREA:-sin-tarea}" "$RUTA" >> "$LOG" 2>/dev/null || true

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

[ -z "$RUTA" ] && exit 0

# Normaliza a ruta absoluta sin resolver enlaces inexistentes
case "$RUTA" in
  /*) ABS="$RUTA" ;;
  *)  ABS="$PWD/$RUTA" ;;
esac

# 1. Fuera del área de trabajo asignada
case "$ABS" in
  "$AREA"/*|"$AREA") : ;;
  /tmp/*) : ;;
  *) denegar "Escritura fuera del área de trabajo asignada ($AREA). Si necesitas tocar otro componente, pídeselo al supervisor." ;;
esac

# 2. Puntos de persistencia
case "$ABS" in
  */.git/hooks/*|*/.git/config|*/.claude/*|*/.mcp.json|*/.vscode/tasks.json|*/.devcontainer/*)
    denegar "Ese archivo controla el comportamiento de la fábrica o del entorno. Los agentes no lo modifican." ;;
  */.bashrc|*/.zshrc|*/.profile|*/.bash_profile)
    denegar "No se modifican archivos de arranque del shell." ;;
esac

# 3. Secretos
case "$ABS" in
  *.pem|*.key|*/.env|*/.env.*|*/id_rsa*|*/credentials)
    case "$ABS" in
      */.env.example|*/.env.plantilla) : ;;
      *) denegar "No se escriben archivos de secretos. Usa .env.example con valores vacíos y documenta la variable." ;;
    esac ;;
esac

# 4. Aviso sobre archivos de bloqueo de dependencias (no se bloquea, se registra)
case "$ABS" in
  */package-lock.json|*/yarn.lock|*/pnpm-lock.yaml|*/packages.lock.json)
    printf '%s\tAVISO: modificación de archivo de bloqueo de dependencias: %s\n' "$(date -Is)" "$ABS" >> "$LOG" 2>/dev/null || true ;;
esac

exit 0
