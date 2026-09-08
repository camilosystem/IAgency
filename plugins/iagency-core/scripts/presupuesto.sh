#!/usr/bin/env bash
# presupuesto.sh — Control de gasto y de bucles.
# Hook PostToolUse (matcher "*"): cuenta llamadas de herramienta por tarea y corta
# cuando se pasa del techo. Es el freno de mano contra el agente que se atasca de
# madrugada y consume presupuesto en círculos.

set -uo pipefail

TAREA="${IAGENCY_TAREA:-sin-tarea}"
TECHO="${IAGENCY_MAX_HERRAMIENTAS:-400}"
DIR="${IAGENCY_ESTADO:-/var/lib/iagency}"
CONT="$DIR/$TAREA.contador"

mkdir -p "$DIR" 2>/dev/null || true
N=$(( $(cat "$CONT" 2>/dev/null || echo 0) + 1 ))
echo "$N" > "$CONT"

if [ "$N" -gt "$TECHO" ]; then
  jq -nc --arg r "Presupuesto de la tarea agotado ($N llamadas de herramienta, techo $TECHO). Detente ahora: escribe el informe de entrega con estado BLOQUEADO, explica dónde te atascaste, y devuélvelo al supervisor. No sigas intentando." '{
    decision: "block",
    reason: $r
  }'
  exit 0
fi

# Aviso al 80 %
if [ "$N" -eq $(( TECHO * 8 / 10 )) ]; then
  jq -nc --arg r "Aviso: llevas el 80 % del presupuesto de esta tarea. Cierra lo que tengas y prepara el informe de entrega." '{
    hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: $r }
  }'
fi

exit 0
