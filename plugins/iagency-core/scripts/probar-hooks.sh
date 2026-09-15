#!/usr/bin/env bash
# probar-hooks.sh — Prueba de humo de los guardarraíles, en la máquina donde corren.
#
# POR QUÉ EXISTE. Tres defectos seguidos del plugin llegaron a una máquina de
# trabajo sin que nadie los detectara antes, y los tres eran del mismo tipo: el
# guardarraíl no llegaba a evaluar un solo comando.
#
#   1. La ruta del script iba sin comillas en hooks.json. En un perfil de usuario
#      con un espacio ("C:\Users\Financial advisor\") el shell la leía como dos
#      palabras y el hook moría con error de sintaxis.
#   2. El arreglo no subía la versión en plugin.json, así que `claude plugin
#      update` decía "already at the latest version" y no bajaba nada.
#   3. La caché del plugin no preservaba el bit de ejecución que git sí registra,
#      y en macOS los cuatro hooks fallaban con "Permission denied".
#
# Ninguno se veía desde el repositorio: los tres solo aparecían en el destino. Y
# el modo de fallo era el peor posible — el guardarraíl no protegía Y empujaba el
# trabajo por otra vía que tampoco miraba.
#
# QUÉ COMPRUEBA. Solo que cada hook DISPARA: que se ejecuta de verdad en esta
# máquina, que devuelve algo que el harness pueda parsear, y que no rompe el turno.
#
# NO comprueba qué decide. Esa es la otra pregunta y vive en probar-guard.sh, que
# corre la batería de casos con el veredicto esperado al lado de cada comando. Los
# dos se corren juntos y ninguno sustituye al otro: este archivo puede salir entero
# en verde con un guardarraíl que bloquea el trabajo legítimo o que deja pasar un
# borrado de la raíz.
#
# USO. En cada máquina, después de instalar o actualizar el plugin, los dos:
#
#     bash probar-hooks.sh     # ¿dispara?
#     bash probar-guard.sh     # ¿decide bien?
#
# Sin argumentos busca los scripts junto a sí mismo; con uno, en esa carpeta.

set -uo pipefail

DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
OK=0
MAL=0

verde()  { printf '  \033[32mOK\033[0m    %s\n' "$1"; OK=$((OK+1)); }
rojo()   { printf '  \033[31mFALLA\033[0m %s\n' "$1"; MAL=$((MAL+1)); }

printf '\n%s\n' "==================================================="
printf '%s\n'   "  Prueba de humo de los guardarraíles"
printf '%s\n'   "  carpeta: $DIR"
printf '%s\n\n' "==================================================="

# --- 0. Lo que los hooks necesitan para funcionar ---------------------------
printf '%s\n' "Requisitos del entorno"
command -v bash >/dev/null 2>&1 && verde "bash disponible" || rojo "bash NO disponible"
if command -v jq >/dev/null 2>&1; then
  verde "jq disponible ($(jq --version 2>/dev/null))"
else
  rojo "jq NO disponible — los guardarraíles no pueden leer el evento ni responder"
fi
printf '\n'

# --- 1. Que cada script exista y se pueda ejecutar ---------------------------
printf '%s\n' "Los cuatro scripts"
for s in guard-bash.sh guard-escritura.sh presupuesto.sh auditar-sesion.sh; do
  if [ ! -f "$DIR/$s" ]; then
    rojo "$s no existe"
    continue
  fi
  # Se invocan con `bash <ruta>` a propósito: así funcionan con o sin bit de
  # ejecución, que es como están declarados en hooks.json. Comprobar el bit aquí
  # mediría algo que ya no importa.
  if bash -n "$DIR/$s" 2>/dev/null; then
    verde "$s existe y su sintaxis es válida"
  else
    rojo "$s tiene error de sintaxis"
  fi
done
printf '\n'

# --- 2. Que un comando inocente PASE ----------------------------------------
# Un guardarraíl que bloquea todo se ve igual que uno que funciona, hasta que
# alguien intenta trabajar. Este es el caso que los tres defectos rompieron.
printf '%s\n' "Un comando inocente tiene que pasar"
ENTRADA='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
SALIDA="$(printf '%s' "$ENTRADA" | bash "$DIR/guard-bash.sh" 2>&1)"
CODIGO=$?
# El criterio es la AUSENCIA de salida, no la presencia de un error conocido.
# Buscar cadenas como "not found" solo caza los fallos que alguien anticipó: el
# defecto de /var/log decía "No such file or directory" y se colaba por el hueco.
# Un comando que pasa no imprime NADA — ni JSON, ni avisos, ni ruido del shell —
# y cualquier byte que se escape contamina el JSON que el harness debe parsear.
if [ $CODIGO -ne 0 ]; then
  rojo "guard-bash.sh salió con código $CODIGO — no llegó a evaluar nada"
  printf '        %s\n' "$SALIDA"
elif printf '%s' "$SALIDA" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
  rojo "guard-bash.sh DENEGÓ 'git status' — bloquearía el trabajo normal"
elif [ -n "$SALIDA" ]; then
  rojo "guard-bash.sh dejó salida cuando debía callar:"
  printf '        %s\n' "$SALIDA"
else
  verde "'git status' pasa sin producir salida"
fi

# --- 3. Que un comando destructivo SE BLOQUEE --------------------------------
printf '\n%s\n' "Un comando destructivo tiene que bloquearse"
ENTRADA='{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
SALIDA="$(printf '%s' "$ENTRADA" | bash "$DIR/guard-bash.sh" 2>&1)"
if printf '%s' "$SALIDA" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
  verde "'rm -rf /' se bloquea"
else
  rojo "'rm -rf /' NO se bloqueó — el guardarraíl no está protegiendo"
  printf '        %s\n' "$SALIDA"
fi

# --- 4. Que la respuesta sea JSON legible ------------------------------------
# Un deny que el harness no puede parsear es un deny que no ocurre.
printf '\n%s\n' "La respuesta de bloqueo tiene que ser JSON válido"
if command -v jq >/dev/null 2>&1; then
  if printf '%s' "$SALIDA" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1; then
    verde "el JSON de denegación se parsea y trae permissionDecision"
  else
    rojo "la salida no es JSON válido con permissionDecision"
  fi
else
  printf '  %s\n' "(omitido: sin jq)"
fi

# --- 5. Que el hook de escritura responda ------------------------------------
printf '\n%s\n' "El guardarraíl de escritura"
ENTRADA='{"tool_name":"Write","tool_input":{"file_path":"/tmp/prueba-humo.txt","content":"hola"}}'
SALIDA="$(printf '%s' "$ENTRADA" | bash "$DIR/guard-escritura.sh" 2>&1)"
CODIGO=$?
# Mismo criterio que arriba: una escritura corriente se aprueba en silencio.
if [ $CODIGO -ne 0 ]; then
  rojo "guard-escritura.sh salió con código $CODIGO"
  printf '        %s\n' "$SALIDA"
elif [ -n "$SALIDA" ]; then
  rojo "guard-escritura.sh dejó salida cuando debía callar:"
  printf '        %s\n' "$SALIDA"
else
  verde "una escritura corriente pasa sin producir salida"
fi

# --- 6. Que los hooks de after no rompan el turno ----------------------------
printf '\n%s\n' "Los hooks posteriores no deben romper nada"
for s in presupuesto.sh auditar-sesion.sh; do
  SALIDA="$(printf '%s' '{"tool_name":"Bash"}' | bash "$DIR/$s" 2>&1)"
  CODIGO=$?
  if [ $CODIGO -ne 0 ]; then
    rojo "$s salió con código $CODIGO"
    printf '        %s\n' "$(printf '%s' "$SALIDA" | head -3)"
  else
    verde "$s se ejecuta sin fallar"
  fi
done

# --- Resultado ---------------------------------------------------------------
printf '\n%s\n' "==================================================="
printf '  Bien: %s   ·   Mal: %s\n' "$OK" "$MAL"
printf '%s\n' "==================================================="
if [ "$MAL" -gt 0 ]; then
  printf '\n%s\n' "Hay guardarraíles que no están funcionando en esta máquina."
  printf '%s\n'   "Mientras esto falle, los agentes trabajan SIN la protección que"
  printf '%s\n'   "el plugin promete — y eso es peor que no tenerla, porque nadie lo sabe."
  exit 1
fi
printf '\n%s\n' "Los guardarraíles están en pie en esta máquina."
