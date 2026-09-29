#!/usr/bin/env bash
# presupuesto.sh — Control de gasto y de bucles.
# Hook PostToolUse (matcher "*"): cuenta llamadas de herramienta por SESIÓN y corta
# cuando se pasa del techo. Es el freno de mano contra el agente que se atasca de
# madrugada y consume presupuesto en círculos.
#
# POR QUÉ LA CLAVE ES LA SESIÓN. Hasta la 1.2.0 la clave era IAGENCY_TAREA, que nadie
# fijaba nunca. El contador era uno solo para toda la máquina (sin-tarea.contador),
# solo subía, y al pasar el techo bloqueaba todas las sesiones de todos los proyectos
# hasta que alguien lo borraba a mano. El evento trae `session_id` — leído de un
# evento real, no supuesto — y cada sesión empieza en 0.
#
# Sin session_id (una prueba a mano, un evento que no viene del harness) NO se cuenta.
# Contar bajo una clave fija es exactamente el defecto que esto arregla.

set -uo pipefail

TECHO="${IAGENCY_MAX_HERRAMIENTAS:-400}"
DIR="${IAGENCY_ESTADO:-${HOME:-/tmp}/.iagency/estado}"
# Minutos sin actividad tras los que un contador se considera de una sesión muerta.
# Una sesión viva toca su archivo en cada llamada, así que nunca envejece.
RETENCION_MIN="${IAGENCY_RETENCION_MIN:-1440}"

command -v jq >/dev/null 2>&1 || exit 0

SESION="$(jq -r '.session_id // ""' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
[ -n "$SESION" ] || exit 0

CONT="$DIR/$SESION.contador"
mkdir -p "$DIR" 2>/dev/null || exit 0

# Limpieza de contadores viejos. Solo al abrir un contador nuevo — una vez por sesión,
# no en cada llamada — para que el directorio no crezca sin límite.
if [ ! -e "$CONT" ]; then
  find "$DIR" -maxdepth 1 -name '*.contador' -mmin +"$RETENCION_MIN" -delete 2>/dev/null || true
fi

# Un byte por llamada: el anexado es atómico, así que dos herramientas en paralelo de
# la misma sesión no se pisan la cuenta como con leer-sumar-escribir.
printf '.' >> "$CONT" 2>/dev/null || exit 0
N=$(( $(wc -c < "$CONT" 2>/dev/null || echo 0) ))

if [ "$N" -gt "$TECHO" ]; then
  jq -nc --arg r "Presupuesto de la sesión agotado ($N llamadas de herramienta, techo $TECHO). Detente ahora: escribe el informe de entrega con estado BLOQUEADO, explica dónde te atascaste, y devuélvelo al Arquitecto. No sigas intentando." '{
    decision: "block",
    reason: $r
  }'
  exit 0
fi

# Aviso al 80 %
if [ "$N" -eq $(( TECHO * 8 / 10 )) ]; then
  jq -nc --arg r "Aviso: llevas el 80 % del presupuesto de esta sesión. Cierra lo que tengas y prepara el informe de entrega." '{
    hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: $r }
  }'
fi

exit 0
