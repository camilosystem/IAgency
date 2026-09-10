#!/usr/bin/env bash
# integrar-tronco-wms.sh — Llevar main hasta el tip de la rama de trabajo.
#
# Por qué existe. En cuatro de los ocho repositorios el trabajo real vive en una
# rama y el tronco quedó atrás: dashboard en el contrato v0.36.0 y las tres apps
# iOS en v0.29.0, mientras las ramas están en v0.99.5. Un agente que clone y
# trabaje sobre main construiría contra un contrato de julio sin enterarse.
#
# Qué hace. Para cada repositorio comprueba que la rama sea un avance limpio del
# tronco (fast-forward) y que contenga el commit del congelamiento, y solo entonces
# mueve main hasta el tip. No hay merge ni commit nuevo: main pasa a apuntar al
# mismo commit que la rama.
#
# Uso, en el nodo. Primero SIEMPRE sin argumentos — analiza y no cambia nada:
#     bash /opt/iagency/fabrica/infra/integrar-tronco-wms.sh
#
# Y solo si el análisis sale limpio:
#     bash /opt/iagency/fabrica/infra/integrar-tronco-wms.sh --aplicar

set -uo pipefail

BASE="${IAGENCY_BASE:-/opt/iagency}"
ESPEJO="$BASE/auditoria/wms"
APLICAR=0
[ "${1:-}" = "--aplicar" ] && APLICAR=1

# shellcheck source=lib-git-credenciales.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-git-credenciales.sh"

[ -d "$ESPEJO/dinas-wms-contracts" ] || {
  echo "No existe el espejo. Corre primero: bash $BASE/fabrica/infra/auditar-wms.sh"
  exit 1
}

# repositorio|rama de trabajo|commit del congelamiento del 28-ago-2026
#
# El hash del congelamiento se usa como prueba de identidad: si la rama que vamos
# a convertir en tronco NO contiene el commit con el que se hizo la demostración,
# es la rama equivocada y el script se detiene.
OBJETIVO=(
"dinas-wms-dashboard|feat/dashboard-carrito-ventana-unica|453c9b6f87fd2c3afe7ea8eefc815e004fbbb2a1"
"dinas-wms-app-sales|feat/settings-backup|488c61610ccc53abc30e3c2e1dc8694acc83b534"
"dinas-wms-app-bodega|feat/app-shortages|eee11896ad20947542c80ae365940d4b744deed7"
"dinas-wms-app-driver|feat/app-payments|1ade7fe5822d8f05afa534164bf046611bb7329f"
)

printf '\n%s\n' "==================================================================="
if [ "$APLICAR" -eq 1 ]; then
  printf '%s\n'   "  INTEGRACIÓN AL TRONCO — modo APLICAR (se va a empujar)"
else
  printf '%s\n'   "  INTEGRACIÓN AL TRONCO — modo análisis (no cambia nada)"
fi
printf '%s\n\n' "==================================================================="

LISTOS=0
BLOQUEADOS=0
HECHOS=0

for LINEA in "${OBJETIVO[@]}"; do
  IFS='|' read -r REPO RAMA CONGELADO <<< "$LINEA"
  DIR="$ESPEJO/$REPO"

  printf '%s\n' "-------------------------------------------------------------------"
  printf '%-28s %s\n' "$REPO" "$RAMA"

  if [ ! -d "$DIR/.git" ]; then
    printf '  BLOQUEADO — no está en el espejo\n\n'
    BLOQUEADOS=$((BLOQUEADOS+1)); continue
  fi

  git -C "$DIR" fetch --all --tags --quiet 2>/dev/null || true

  VIEJO="$(git -C "$DIR" rev-parse origin/main 2>/dev/null)"
  NUEVO="$(git -C "$DIR" rev-parse "origin/$RAMA" 2>/dev/null)"

  if [ -z "$VIEJO" ] || [ -z "$NUEVO" ]; then
    printf '  BLOQUEADO — falta main o la rama en el servidor\n\n'
    BLOQUEADOS=$((BLOQUEADOS+1)); continue
  fi

  if [ "$VIEJO" = "$NUEVO" ]; then
    printf '  YA INTEGRADO — main y la rama son el mismo commit (%s)\n\n' "${NUEVO:0:12}"
    continue
  fi

  # Prueba 1: ¿la rama contiene el commit de la demostración?
  if ! git -C "$DIR" merge-base --is-ancestor "$CONGELADO" "$NUEVO" 2>/dev/null; then
    printf '  BLOQUEADO — la rama NO contiene el commit del congelamiento %s\n' "${CONGELADO:0:12}"
    printf '  Es la rama equivocada, o hubo reescritura. Revisar a mano.\n\n'
    BLOQUEADOS=$((BLOQUEADOS+1)); continue
  fi

  # Prueba 2: ¿es un avance limpio? main tiene que ser ancestro de la rama.
  if ! git -C "$DIR" merge-base --is-ancestor "$VIEJO" "$NUEVO" 2>/dev/null; then
    ADELANTE="$(git -C "$DIR" rev-list --count "$NUEVO..$VIEJO")"
    printf '  BLOQUEADO — NO es fast-forward: main tiene %s commits que la rama no.\n' "$ADELANTE"
    printf '  Integrar esto perdería trabajo. Hace falta un merge decidido a mano.\n\n'
    BLOQUEADOS=$((BLOQUEADOS+1)); continue
  fi

  N="$(git -C "$DIR" rev-list --count "$VIEJO..$NUEVO")"
  printf '  main   %s  %s\n' "${VIEJO:0:12}" "$(git -C "$DIR" log -1 --format='%cd' --date=short "$VIEJO")"
  printf '  rama   %s  %s\n' "${NUEVO:0:12}" "$(git -C "$DIR" log -1 --format='%cd' --date=short "$NUEVO")"
  printf '  avance limpio de %s commits\n' "$N"

  # A qué versión del contrato pasa el tronco, que es el motivo de todo esto.
  PUNTERO="$(git -C "$DIR" ls-tree "$NUEVO" contracts 2>/dev/null | awk '{print $3}')"
  if [ -n "$PUNTERO" ]; then
    CDIR="$ESPEJO/dinas-wms-contracts"
    TAG="$(git -C "$CDIR" describe --tags --exact-match "$PUNTERO" 2>/dev/null || echo "${PUNTERO:0:12}")"
    ANTES="$(git -C "$DIR" ls-tree "$VIEJO" contracts 2>/dev/null | awk '{print $3}')"
    TAGANTES="$(git -C "$CDIR" describe --tags --exact-match "$ANTES" 2>/dev/null || echo "${ANTES:0:12}")"
    printf '  contrato: %s  ->  %s\n' "$TAGANTES" "$TAG"
  fi

  if [ "$APLICAR" -eq 1 ]; then
    if git -C "$DIR" push origin "$NUEVO:refs/heads/main" 2>&1 | sed 's/^/    /'; then
      CONFIRMA="$(git -C "$DIR" ls-remote origin refs/heads/main | awk '{print $1}')"
      if [ "$CONFIRMA" = "$NUEVO" ]; then
        printf '  HECHO — main en el servidor confirmado en %s\n\n' "${CONFIRMA:0:12}"
        HECHOS=$((HECHOS+1))
      else
        printf '  ATENCIÓN — el push no falló pero el servidor reporta %s\n\n' "${CONFIRMA:0:12}"
        BLOQUEADOS=$((BLOQUEADOS+1))
      fi
    else
      printf '  FALLÓ el push. Si dice 403 o "permission denied", el token no tiene\n'
      printf '  permiso de escritura sobre este repositorio.\n\n'
      BLOQUEADOS=$((BLOQUEADOS+1))
    fi
  else
    # Sin --aplicar, comprobamos permisos sin cambiar nada. --dry-run contacta al
    # servidor y valida credenciales, pero no escribe.
    if git -C "$DIR" push --dry-run origin "$NUEVO:refs/heads/main" >/dev/null 2>&1; then
      printf '  LISTO — fast-forward válido y el token puede escribir.\n\n'
    else
      printf '  LISTO para integrar, PERO el token no puede escribir en este repo.\n'
      printf '  Hace falta un token con permiso de escritura (Contents: read and write).\n\n'
    fi
    LISTOS=$((LISTOS+1))
  fi
done

printf '%s\n' "==================================================================="
if [ "$APLICAR" -eq 1 ]; then
  printf '  Integrados: %s   ·   Bloqueados: %s\n' "$HECHOS" "$BLOQUEADOS"
else
  printf '  Listos para integrar: %s   ·   Bloqueados: %s\n' "$LISTOS" "$BLOQUEADOS"
  printf '%s\n' "==================================================================="
  printf '\n%s\n' "Esto no cambió nada. Si el análisis está limpio, para aplicarlo:"
  printf '%s\n'   "  bash $BASE/fabrica/infra/integrar-tronco-wms.sh --aplicar"
fi
printf '%s\n' "==================================================================="
if [ "$BLOQUEADOS" -gt 0 ]; then
  printf '\n%s\n' "Hay repositorios bloqueados. No fuerces ninguno: un bloqueo aquí"
  printf '%s\n'   "significa que integrar perdería trabajo o que la rama no es la que"
  printf '%s\n'   "creemos. Revísalo antes de volver a correr esto."
fi
