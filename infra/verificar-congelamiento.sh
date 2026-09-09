#!/usr/bin/env bash
# verificar-congelamiento.sh — ¿Sigue cada referencia en el commit congelado?
#
# Los tres RECONSTRUIR.md advierten: si la rama avanzó después del congelamiento,
# manda el hash de la lista, no el tip de la rama. Este script responde cuál es
# cuál, sin tener que confiar en la memoria de nadie.
#
# Uso, en el nodo, después de auditar-wms.sh:
#   bash /opt/iagency/fabrica/infra/verificar-congelamiento.sh

set -uo pipefail

BASE="${IAGENCY_BASE:-/opt/iagency}"
ESPEJO="$BASE/auditoria/wms"

[ -d "$ESPEJO/dinas-wms-contracts" ] || {
  echo "No existe el espejo. Corre primero: bash $BASE/fabrica/infra/auditar-wms.sh"
  exit 1
}

# repositorio|referencia|hash del congelamiento (28-ago-2026)
CONGELADO=(
"dinas-wms-contracts|main|f65c5e8c91622ade283de0f19f06af3a0347a380"
"dinas-wms-middleware|main|ca97d206b09793187f7717d452e870190da72aed"
"dinas-wms-sap-sync|main|97627de894e5dc0c780358479b3595e7fc9f1fc2"
"dinas-wms-dashboard|feat/dashboard-carrito-ventana-unica|453c9b6f87fd2c3afe7ea8eefc815e004fbbb2a1"
"dinas-wms-app-sales|feat/settings-backup|488c61610ccc53abc30e3c2e1dc8694acc83b534"
"dinas-wms-app-bodega|feat/app-shortages|eee11896ad20947542c80ae365940d4b744deed7"
"dinas-wms-app-driver|feat/app-payments|1ade7fe5822d8f05afa534164bf046611bb7329f"
)

printf '\n%s\n' "==================================================================="
printf '%s\n'   "  Verificación contra la lista de congelamiento del 28-ago-2026"
printf '%s\n\n' "==================================================================="

IGUALES=0
AVANZARON=0
PROBLEMAS=0

for LINEA in "${CONGELADO[@]}"; do
  IFS='|' read -r REPO REF HASH <<< "$LINEA"
  DIR="$ESPEJO/$REPO"

  printf '%-28s %s\n' "$REPO" "$REF"

  if [ ! -d "$DIR/.git" ]; then
    printf '  %s\n\n' "NO ACCESIBLE — no está en el espejo"
    PROBLEMAS=$((PROBLEMAS+1))
    continue
  fi

  git -C "$DIR" fetch --all --tags --quiet 2>/dev/null || true
  ACTUAL="$(git -C "$DIR" rev-parse "origin/$REF" 2>/dev/null)"

  if [ -z "$ACTUAL" ]; then
    printf '  %s\n\n' "LA REFERENCIA YA NO EXISTE en el servidor — ¿se borró la rama?"
    PROBLEMAS=$((PROBLEMAS+1))
    continue
  fi

  # ¿Existe todavía el commit congelado?
  if ! git -C "$DIR" cat-file -e "$HASH^{commit}" 2>/dev/null; then
    printf '  %s\n' "EL COMMIT CONGELADO NO EXISTE en este repositorio."
    printf '  %s\n\n' "Reescritura de historia, o el hash pertenece a otro repositorio. Revisar a mano."
    PROBLEMAS=$((PROBLEMAS+1))
    continue
  fi

  if [ "$ACTUAL" = "$HASH" ]; then
    printf '  %s\n' "IGUAL al congelamiento — ${HASH:0:12}"
    printf '  %s\n\n' "$(git -C "$DIR" log -1 --format='%cd  %s' --date=short "$HASH")"
    IGUALES=$((IGUALES+1))
  elif git -C "$DIR" merge-base --is-ancestor "$HASH" "origin/$REF" 2>/dev/null; then
    N="$(git -C "$DIR" rev-list --count "$HASH..origin/$REF")"
    printf '  %s\n' "AVANZÓ $N commits desde el congelamiento"
    printf '  %s\n' "  congelado: ${HASH:0:12}  $(git -C "$DIR" log -1 --format='%cd' --date=short "$HASH")"
    printf '  %s\n' "  actual:    ${ACTUAL:0:12}  $(git -C "$DIR" log -1 --format='%cd' --date=short "origin/$REF")"
    printf '  %s\n' "  lo nuevo:"
    git -C "$DIR" log --format='    %h %cd %s' --date=short "$HASH..origin/$REF" | head -12
    [ "$N" -gt 12 ] && printf '    %s\n' "... y $((N-12)) más"
    printf '\n'
    AVANZARON=$((AVANZARON+1))
  else
    printf '  %s\n' "DIVERGIÓ — el commit congelado NO es ancestro del tip actual."
    printf '  %s\n\n' "Hubo reescritura o la rama se rehizo. Revisar a mano antes de tocar nada."
    PROBLEMAS=$((PROBLEMAS+1))
  fi
done

printf '%s\n' "==================================================================="
printf '  En el congelamiento: %s   ·   Avanzaron: %s   ·   Problemas: %s\n' "$IGUALES" "$AVANZARON" "$PROBLEMAS"
printf '%s\n' "==================================================================="
if [ "$AVANZARON" -gt 0 ]; then
  printf '\n%s\n' "Para las que avanzaron: los RECONSTRUIR.md dicen que manda el hash de la"
  printf '%s\n'   "lista, no el tip. Antes de integrar, decide si esos commits posteriores"
  printf '%s\n'   "entran o no — y escríbelo."
fi
if [ "$PROBLEMAS" -gt 0 ]; then
  printf '\n%s\n' "Hay referencias con problema. No integres nada hasta resolverlas."
fi
