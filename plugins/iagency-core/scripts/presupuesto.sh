#!/usr/bin/env bash
# presupuesto.sh — Control de gasto y de bucles.
# Hook PostToolUse (matcher "*"): cuenta llamadas de herramienta por SESIÓN y por
# AGENTE, avisa según crece el gasto y, solo en modo desatendido, corta al agente que
# pasa su techo, o a cualquiera si la sesión pasa el suyo. Es el
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
#   desatendido  bloquea cada llamada del agente que pasó su techo, y cualquier
#                llamada si la sesión pasó el techo de sesión. Es para cuando nadie
#                mira, que es el caso para el que este control existe — y NO se da
#                por bueno todavía: ver el LÍMITE DECLARADO más abajo.
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
# CÓMO SE CUENTA, desde la 1.6.0 (opción B, aprobada por el PM). Hasta la 1.5.0
# principal y subagentes sumaban a UN contador con UN techo, y eso castigaba justo la
# conducta que se quiere: una sola tarea del analista gastó 217 llamadas a cuenta del
# Arquitecto que delegó. Ahora:
#   - cada agente tiene su contador y su techo (IAGENCY_MAX_HERRAMIENTAS): el
#     principal, y cada subagente por su agent_id. Un bucle es cosa de un agente, y
#     el techo corta a ESE agente, no a los demás;
#   - el total de la sesión se sigue contando y aparece en cada aviso;
#   - en modo desatendido hay además un techo de SESIÓN, más alto
#     (IAGENCY_MAX_SESION, por defecto 5 veces el techo por agente), para el caso
#     que el techo por agente no ve: muchos agentes que se quedan bajo el suyo y
#     entre todos suman sin freno. En atendido no existe: el freno es el PM.
#
# ===========================================================================
# LÍMITE DECLARADO — EL MODO DESATENDIDO NO SE DA POR BUENO TODAVÍA
# ===========================================================================
# El techo por agente depende de que cada llamada traiga el agent_id del agente que
# la hace. Eso está MEDIDO para un subagente lanzado por el principal y esperado en
# primer plano. NO está medido para:
#   1. subagentes lanzados por otro subagente (anidados), y
#   2. subagentes en segundo plano (run_in_background).
# Si en cualquiera de los dos el agent_id no se propaga —llega vacío, o llega el del
# padre— el techo por agente no ve a ese agente: sus llamadas se cargan a otro, y un
# bucle ahí dentro no se corta por agente. Solo lo pararía el techo de sesión.
#
# Quien construya el modo desatendido: NO lo pongas en marcha hasta medir esos dos
# casos con sesiones reales, como se midió el primero (una clave única inyectada por
# un hook de sonda y buscada en las transcripciones en disco, no en lo que responde
# el modelo). Hasta entonces, cada sesión desatendida lo recuerda con un
# systemMessage al arrancar, y probar-hooks.sh lo lista como LÍMITE.
# ===========================================================================

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
TECHO_SESION="${IAGENCY_MAX_SESION:-$(( TECHO * 5 ))}"
case "$TECHO_SESION" in ''|*[!0-9]*|0) TECHO_SESION=$(( TECHO * 5 )) ;; esac

EVENTO="$(cat)"
SESION="$(printf '%s' "$EVENTO" | jq -r '.session_id // ""' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
[ -n "$SESION" ] || exit 0
AGENTE="$(printf '%s' "$EVENTO" | jq -r '.agent_id // ""' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
if [ -n "$AGENTE" ]; then
  QUIEN="el subagente $(printf '%s' "$EVENTO" | jq -r '.agent_type // "sin tipo"' 2>/dev/null) ($AGENTE)"
else
  QUIEN="el agente principal"
fi

BASE="$DIR/$SESION"
CONT="$BASE.contador"
CONT_AGENTE="$BASE.agente-${AGENTE:-principal}.contador"
mkdir -p "$DIR" 2>/dev/null || exit 0

# Limpieza de lo viejo. Solo al abrir un contador nuevo — una vez por sesión, no en
# cada llamada — para que el directorio no crezca sin límite. '*.contador' incluye
# los contadores por agente.
if [ ! -e "$CONT" ]; then
  find "$DIR" -maxdepth 1 \( -name '*.contador' -o -name '*.aviso-*' -o -name '*.pendiente' \
       -o -name '*.desatendido-sin-validar' \) -mmin +"$RETENCION_MIN" -delete 2>/dev/null || true
fi

# Un byte por llamada: el anexado es atómico, así que dos herramientas en paralelo de
# la misma sesión no se pisan la cuenta como con leer-sumar-escribir. Cada llamada
# suma al total de la sesión Y al contador de su agente.
printf '.' >> "$CONT" 2>/dev/null || exit 0
printf '.' >> "$CONT_AGENTE" 2>/dev/null || exit 0
N=$(( $(wc -c < "$CONT" 2>/dev/null || echo 0) ))
A=$(( $(wc -c < "$CONT_AGENTE" 2>/dev/null || echo 0) ))

# nivel <cuenta> <techo>: 0 bajo el 80 %; 1 desde el 80 %; 2 desde el techo; y uno
# más por cada 25 % del techo por encima.
nivel() {
  local n="$1" t="$2" paso=$(( $2 / 4 ))
  [ "$paso" -ge 1 ] || paso=1
  if   [ "$n" -ge "$t" ];              then echo $(( 2 + (n - t) / paso ))
  elif [ "$n" -ge $(( t * 8 / 10 )) ]; then echo 1
  else                                      echo 0
  fi
}
# marcar <archivo>: crea la marca "ya avisé" si no existía. noclobber es atómico: de
# dos llamadas que cruzan a la vez, gana una.
marcar() { ( set -o noclobber; : > "$1" ) 2>/dev/null; }

TOTAL="Total de la sesión: $N llamadas"
[ "$MODO" = "desatendido" ] && TOTAL="$TOTAL, techo de sesión $TECHO_SESION"
TOTAL="$TOTAL."

AVISO=""
NIVEL=$(nivel "$A" "$TECHO")
if [ "$NIVEL" -ge 1 ] && marcar "$BASE.agente-${AGENTE:-principal}.aviso-$NIVEL"; then
  PCT=$(( A * 100 / TECHO ))
  ESTADO_TECHO=""
  [ "$A" -ge "$TECHO" ] && ESTADO_TECHO=": techo alcanzado"
  [ "$A" -gt "$TECHO" ] && ESTADO_TECHO=": techo superado"
  CABEZA="Presupuesto: $QUIEN lleva $A llamadas de herramienta, el $PCT % de su techo ($TECHO)$ESTADO_TECHO. $TOTAL"
  if [ "$MODO" = "desatendido" ]; then
    AVISO="$CABEZA Modo desatendido: al pasar su techo, este agente se corta. Cierra lo que tengas y prepara el informe de entrega."
  elif [ "$NIVEL" -eq 1 ]; then
    AVISO="$CABEZA Modo atendido: no se corta; tú decides si seguir, y el PM ve este número."
  else
    AVISO="$CABEZA Modo atendido: no se corta. Si estás dando vueltas, detente y díselo al PM; si el trabajo lo justifica, sigue."
  fi
fi
# En desatendido, el techo de sesión también avisa antes de cortar, una vez.
if [ "$MODO" = "desatendido" ] && [ "$(nivel "$N" "$TECHO_SESION")" -ge 1 ] && marcar "$BASE.sesion.aviso-1"; then
  AVISO="$(printf '%s\n%s' "$AVISO" "Presupuesto: la sesión lleva $N llamadas entre todos los agentes, el $(( N * 100 / TECHO_SESION )) % del techo de sesión ($TECHO_SESION). Modo desatendido: al pasarlo se corta a cualquier agente." | sed '/^$/d')"
fi

# Recordatorio del límite declarado, una vez por sesión desatendida. Ver la cabecera.
RECORDATORIO=""
if [ "$MODO" = "desatendido" ] && marcar "$BASE.desatendido-sin-validar"; then
  RECORDATORIO="iagency: modo desatendido SIN VALIDAR. El techo por agente no está medido para subagentes anidados ni en segundo plano; un bucle ahí solo lo para el techo de sesión. Ver la cabecera de presupuesto.sh."
fi

# El corte, solo en desatendido: al agente que pasó su techo, o a cualquiera si la
# sesión pasó el suyo.
CORTE=""
if [ "$MODO" = "desatendido" ]; then
  if [ "$A" -gt "$TECHO" ]; then
    CORTE="Presupuesto agotado para $QUIEN: $A llamadas de herramienta, techo por agente $TECHO. $TOTAL"
  elif [ "$N" -gt "$TECHO_SESION" ]; then
    CORTE="Presupuesto de la SESIÓN agotado: $N llamadas entre todos los agentes, techo de sesión $TECHO_SESION. Se corta a cualquier agente, aunque ninguno haya llegado a su techo ($QUIEN lleva $A de $TECHO)."
  fi
fi

# Un aviso o un corte que cae en un subagente entra en el contexto del SUBAGENTE y el
# principal no lo ve nunca: medido con una sesión real. Se deja pendiente para él.
# Uno que llega al principal recoge lo pendiente; mv es atómico, así que se entrega
# una sola vez aunque el principal haga dos llamadas a la vez.
PENDIENTE=""
if [ -n "$AGENTE" ]; then
  for T in "$AVISO" "$CORTE"; do
    [ -n "$T" ] && printf '%s (Llegó durante el trabajo d%s.)\n' "$T" "$QUIEN" >> "$BASE.pendiente" 2>/dev/null
  done
elif [ -e "$BASE.pendiente" ] && mv "$BASE.pendiente" "$BASE.pendiente.$$" 2>/dev/null; then
  PENDIENTE="$(cat "$BASE.pendiente.$$" 2>/dev/null)"
  rm -f "$BASE.pendiente.$$"
fi

TEXTO="$(printf '%s\n%s' "$PENDIENTE" "$AVISO" | sed '/^$/d')"
MENSAJE="$(printf '%s\n%s' "$RECORDATORIO" "$TEXTO" | sed '/^$/d')"

if [ -n "$CORTE" ]; then
  jq -nc --arg r "$CORTE Detente ahora: escribe el informe de entrega con estado BLOQUEADO, explica dónde te atascaste, y devuélvelo al Arquitecto. No sigas intentando." \
         --arg c "$TEXTO" --arg m "$(printf '%s\n%s' "$MENSAJE" "$CORTE" | sed '/^$/d')" '{
    decision: "block",
    reason: (if $c == "" then $r else $c + "\n" + $r end),
    systemMessage: $m
  }'
  exit 0
fi

if [ -n "$MENSAJE" ]; then
  jq -nc --arg c "$TEXTO" --arg m "$MENSAJE" '{ systemMessage: $m }
    + (if $c == "" then {} else { hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: $c } } end)'
fi

exit 0
