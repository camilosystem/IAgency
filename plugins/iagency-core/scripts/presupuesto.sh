#!/usr/bin/env bash
# presupuesto.sh — Control de gasto y de bucles.
# Hook PostToolUse (matcher "*"): cuenta llamadas de herramienta por SESIÓN, avisa
# según crece el gasto y, solo en modo desatendido, corta al pasar el techo. Es el
# freno de mano contra el agente que se atasca de madrugada y consume presupuesto en
# círculos.
#
# POR QUÉ LA CLAVE ES LA SESIÓN. Hasta la 1.2.0 la clave era IAGENCY_TAREA, que nadie
# fijaba nunca. El contador era uno solo para toda la máquina (sin-tarea.contador),
# solo subía, y al pasar el techo bloqueaba todas las sesiones de todos los proyectos
# hasta que alguien lo borraba a mano. El evento trae `session_id` — leído de un
# evento real, no supuesto — y cada sesión empieza en 0.
#
# Sin session_id (una prueba a mano, un evento que no viene del harness) NO se cuenta.
# Contar bajo una clave fija es exactamente el defecto que esto arregla.
#
# DOS MODOS (IAGENCY_MODO), desde la 1.5.0:
#   atendido     (por defecto) NUNCA bloquea. Avisa al 80 % del techo, al llegar al
#                techo, y de nuevo cada 25 % más. Hay un humano mirando cada paso: él
#                es el freno, y el corte duro solo estorbaba trabajo legítimo.
#   desatendido  bloquea en cada llamada por encima del techo. Es para cuando nadie
#                mira, que es el caso para el que este control existe.
# Cualquier valor que no sea "desatendido" se trata como atendido. El error cae del
# lado de no cortar, a propósito: el modo desatendido se declara, no se supone.
#
# LOS AVISOS SE DAN UNA VEZ, PERO NO SE PUEDEN SALTAR. Hasta la 1.4.0 el aviso del 80 %
# comparaba con -eq contra un valor exacto, y con llamadas en paralelo el contador
# pasaba por encima: medido, en 19 de 20 rondas de 6 llamadas en paralelo el aviso no
# salió nunca. Ahora cada nivel se compara con -ge y deja una marca "ya avisé"
# creada con noclobber, que es atómica: de dos llamadas que cruzan a la vez, avisa una.
#
# LOS AVISOS DE UN SUBAGENTE SE REENVÍAN AL PRINCIPAL. Medido con una sesión real que
# delegaba: el additionalContext de la llamada de un subagente entra en el contexto
# del SUBAGENTE, y el principal no lo ve nunca. El evento de un subagente trae
# agent_id y el del principal no; así que el aviso que cae en un subagente queda
# además pendiente, y se entrega en la siguiente llamada del principal — que llega
# como mucho cuando el subagente termina, porque la propia herramienta Agent dispara
# un PostToolUse en el contexto del principal. Límite que queda: si el principal ya no
# hace ninguna llamada más en la sesión, el pendiente no se entrega.
#
# El número del aviso es el real, y va también en systemMessage, que ve la persona y
# no solo el modelo: el techo se calibra con datos, no con una corazonada.
#
# Los subagentes SUMAN al mismo contador que el principal. Es deliberado por ahora:
# cómo contarlos por separado es una decisión pendiente del PM.

set -uo pipefail

TECHO="${IAGENCY_MAX_HERRAMIENTAS:-400}"
MODO="${IAGENCY_MODO:-atendido}"
[ "$MODO" = "desatendido" ] || MODO="atendido"
DIR="${IAGENCY_ESTADO:-${HOME:-/tmp}/.iagency/estado}"
# Minutos sin actividad tras los que un contador se considera de una sesión muerta.
# Una sesión viva toca su archivo en cada llamada, así que nunca envejece.
RETENCION_MIN="${IAGENCY_RETENCION_MIN:-1440}"

command -v jq >/dev/null 2>&1 || exit 0
case "$TECHO" in ''|*[!0-9]*|0) TECHO=400 ;; esac

EVENTO="$(cat)"
SESION="$(printf '%s' "$EVENTO" | jq -r '.session_id // ""' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
[ -n "$SESION" ] || exit 0
AGENTE="$(printf '%s' "$EVENTO" | jq -r '.agent_id // ""' 2>/dev/null)"

BASE="$DIR/$SESION"
CONT="$BASE.contador"
mkdir -p "$DIR" 2>/dev/null || exit 0

# Limpieza de lo viejo. Solo al abrir un contador nuevo — una vez por sesión, no en
# cada llamada — para que el directorio no crezca sin límite.
if [ ! -e "$CONT" ]; then
  find "$DIR" -maxdepth 1 \( -name '*.contador' -o -name '*.aviso-*' -o -name '*.pendiente' \) \
       -mmin +"$RETENCION_MIN" -delete 2>/dev/null || true
fi

# Un byte por llamada: el anexado es atómico, así que dos herramientas en paralelo de
# la misma sesión no se pisan la cuenta como con leer-sumar-escribir.
printf '.' >> "$CONT" 2>/dev/null || exit 0
N=$(( $(wc -c < "$CONT" 2>/dev/null || echo 0) ))

# Nivel de gasto: 0 bajo el 80 %; 1 desde el 80 %; 2 desde el techo; y uno más por
# cada 25 % del techo por encima.
UMBRAL=$(( TECHO * 8 / 10 ))
PASO=$(( TECHO / 4 )); [ "$PASO" -ge 1 ] || PASO=1
if   [ "$N" -ge "$TECHO" ];  then NIVEL=$(( 2 + (N - TECHO) / PASO ))
elif [ "$N" -ge "$UMBRAL" ]; then NIVEL=1
else                              NIVEL=0
fi

AVISO=""
if [ "$NIVEL" -ge 1 ] && ( set -o noclobber; : > "$BASE.aviso-$NIVEL" ) 2>/dev/null; then
  PCT=$(( N * 100 / TECHO ))
  if [ "$MODO" = "desatendido" ]; then
    AVISO="Presupuesto: $N llamadas de herramienta en esta sesión, el $PCT % del techo ($TECHO). Modo desatendido: al pasar el techo se corta. Cierra lo que tengas y prepara el informe de entrega."
  elif [ "$NIVEL" -eq 1 ]; then
    AVISO="Presupuesto: $N llamadas de herramienta en esta sesión, el $PCT % del techo ($TECHO). Modo atendido: no se corta; tú decides si seguir, y el PM ve este número."
  else
    ESTADO_TECHO="techo alcanzado"; [ "$N" -gt "$TECHO" ] && ESTADO_TECHO="techo superado"
    AVISO="Presupuesto: $N llamadas de herramienta en esta sesión, el $PCT % del techo ($TECHO): $ESTADO_TECHO. Modo atendido: no se corta. Si estás dando vueltas, detente y díselo al PM; si el trabajo lo justifica, sigue."
  fi
fi

# Un aviso que cae en un subagente no llega al principal: se deja pendiente para él.
# Uno que llega al principal recoge lo pendiente; mv es atómico, así que se entrega
# una sola vez aunque el principal haga dos llamadas a la vez.
PENDIENTE=""
if [ -n "$AGENTE" ]; then
  [ -n "$AVISO" ] && printf '%s (Llegó durante el trabajo del subagente %s.)\n' "$AVISO" \
    "$(printf '%s' "$EVENTO" | jq -r '.agent_type // "sin tipo"')" >> "$BASE.pendiente" 2>/dev/null
elif [ -e "$BASE.pendiente" ] && mv "$BASE.pendiente" "$BASE.pendiente.$$" 2>/dev/null; then
  PENDIENTE="$(cat "$BASE.pendiente.$$" 2>/dev/null)"
  rm -f "$BASE.pendiente.$$"
fi

TEXTO="$(printf '%s\n%s' "$PENDIENTE" "$AVISO" | sed '/^$/d')"

if [ "$MODO" = "desatendido" ] && [ "$N" -gt "$TECHO" ]; then
  jq -nc --arg r "Presupuesto de la sesión agotado ($N llamadas de herramienta, techo $TECHO, modo desatendido). Detente ahora: escribe el informe de entrega con estado BLOQUEADO, explica dónde te atascaste, y devuélvelo al Arquitecto. No sigas intentando." \
         --arg m "Presupuesto agotado: $N llamadas, techo $TECHO (desatendido)." '{
    decision: "block",
    reason: $r,
    systemMessage: $m
  }'
  exit 0
fi

if [ -n "$TEXTO" ]; then
  jq -nc --arg r "$TEXTO" '{
    systemMessage: $r,
    hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: $r }
  }'
fi

exit 0
