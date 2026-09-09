#!/usr/bin/env bash
# auditar-wms.sh — Radiografía del estado REAL de los repositorios del WMS en GitHub.
#
# Responde tres preguntas con evidencia, no con memoria:
#   1. ¿Qué commit tiene cada repo en su rama por defecto, en el SERVIDOR?
#   2. ¿A qué versión del contrato apunta el submódulo de cada repo?
#   3. ¿Están todos apuntando a la MISMA versión, o hay repos rezagados?
#
# Se ejecuta en el nodo, como el usuario 'fabrica':
#   bash /opt/iagency/fabrica/infra/auditar-wms.sh
#
# Los repos del WMS son públicos, así que no hace falta credencial.
#
# POR QUÉ EL BLOB ID Y NO EL sha256: el sha256 del archivo openapi.yaml difiere
# entre Windows y Mac por los finales de línea (CRLF contra LF). El blob id de git
# es idéntico en toda máquina porque git normaliza a LF al commitear. Comparar
# sha256 entre máquinas entrena a descartar discrepancias como "cosa de CRLF", y la
# única vez que la discrepancia sea real, es la vez que importa.

set -uo pipefail

ORG="${WMS_ORG:-camilosystem}"
BASE="${IAGENCY_BASE:-/opt/iagency}"
ESPEJO="$BASE/auditoria/wms"
SALIDA="${1:-$BASE/auditoria/wms-$(date +%Y%m%d-%H%M%S).md}"

REPOS=(
  dinas-wms-contracts
  dinas-wms-middleware
  dinas-wms-dashboard
  dinas-wms-app-sales
  dinas-wms-app-bodega
  dinas-wms-app-driver
  dinas-wms-sql
  dinas-wms-sap-sync
)

# Los que consumen el contrato como submódulo. sap-sync NO: habla con SAP
# Service Layer, no con el middleware.
CONSUMEN_CONTRATO=(
  dinas-wms-middleware
  dinas-wms-dashboard
  dinas-wms-app-sales
  dinas-wms-app-bodega
  dinas-wms-app-driver
)

mkdir -p "$ESPEJO" "$(dirname "$SALIDA")"

echo "Auditando $((${#REPOS[@]})) repositorios de $ORG..."

{
  echo "# Auditoría de repositorios del WMS Dinas"
  echo
  echo "Generada: $(date -Is)  ·  Organización: \`$ORG\`"
  echo
  echo "> Estado leído del SERVIDOR (origin), no de ninguna copia local."
  echo "> El blob id de git es la verificación primaria del contrato: es idéntico en"
  echo "> toda máquina, a diferencia del sha256 del archivo, que cambia con CRLF."
  echo
} > "$SALIDA"

# --------------------------------------------------------------------------
# 1. Estado de cada repositorio en el servidor
# --------------------------------------------------------------------------
{
  echo "## 1. Estado de cada repositorio"
  echo
  echo "| Repositorio | Rama por defecto | Commit | Fecha del último commit |"
  echo "|---|---|---|---|"
} >> "$SALIDA"

declare -A COMMIT_DE
declare -A RAMA_DE

for R in "${REPOS[@]}"; do
  URL="https://github.com/$ORG/$R.git"
  DIR="$ESPEJO/$R"

  if [ -d "$DIR/.git" ]; then
    git -C "$DIR" fetch --all --tags --quiet 2>/dev/null || true
  else
    git clone --quiet "$URL" "$DIR" 2>/dev/null || {
      echo "| \`$R\` | — | **NO ACCESIBLE** | — |" >> "$SALIDA"
      echo "  $R: no accesible"
      continue
    }
  fi

  RAMA="$(git -C "$DIR" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  [ -z "$RAMA" ] && RAMA="$(git -C "$DIR" remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')"
  [ -z "$RAMA" ] && RAMA="main"

  COMMIT="$(git -C "$DIR" rev-parse --short "origin/$RAMA" 2>/dev/null || echo '—')"
  FECHA="$(git -C "$DIR" log -1 --format=%cd --date=short "origin/$RAMA" 2>/dev/null || echo '—')"

  COMMIT_DE[$R]="$COMMIT"
  RAMA_DE[$R]="$RAMA"

  echo "| \`$R\` | $RAMA | \`$COMMIT\` | $FECHA |" >> "$SALIDA"
  echo "  $R: $RAMA @ $COMMIT"
done

# --------------------------------------------------------------------------
# 2. El contrato: qué versión existe y a cuál apunta cada consumidor
# --------------------------------------------------------------------------
CDIR="$ESPEJO/dinas-wms-contracts"
{
  echo
  echo "## 2. El contrato"
  echo
} >> "$SALIDA"

if [ -d "$CDIR/.git" ]; then
  ULTIMO_TAG="$(git -C "$CDIR" tag --sort=-v:refname | head -1)"
  BLOB_ULTIMO="$(git -C "$CDIR" rev-parse "$ULTIMO_TAG:openapi.yaml" 2>/dev/null || echo '—')"
  VERSION_INFO="$(git -C "$CDIR" show "$ULTIMO_TAG:openapi.yaml" 2>/dev/null | grep -m1 -E '^\s+version:' | tr -d ' ' | cut -d: -f2)"

  {
    echo "Última versión publicada en \`dinas-wms-contracts\`: **$ULTIMO_TAG**"
    echo
    echo "- \`info.version\` dentro del YAML: \`$VERSION_INFO\`"
    echo "- Blob id del contrato: \`$BLOB_ULTIMO\`"
    echo
    echo "Últimos diez tags publicados:"
    echo
    echo '```'
    git -C "$CDIR" tag --sort=-v:refname | head -10
    echo '```'
    echo
  } >> "$SALIDA"

  if [ "$VERSION_INFO" != "${ULTIMO_TAG#v}" ] && [ -n "$VERSION_INFO" ]; then
    {
      echo "> **DISCREPANCIA:** el tag dice \`$ULTIMO_TAG\` pero \`info.version\` dentro"
      echo "> del YAML dice \`$VERSION_INFO\`. Uno de los dos está mal y hay que resolverlo"
      echo "> antes de que ningún agente trabaje contra este contrato."
      echo
    } >> "$SALIDA"
  fi

  # ------------------------------------------------------------------------
  {
    echo "### A qué versión apunta cada consumidor"
    echo
    echo "| Repositorio | Puntero del submódulo | Tag que le corresponde | ¿Al día? |"
    echo "|---|---|---|---|"
  } >> "$SALIDA"

  REZAGADOS=""
  for R in "${CONSUMEN_CONTRATO[@]}"; do
    DIR="$ESPEJO/$R"
    [ -d "$DIR/.git" ] || { echo "| \`$R\` | — | — | no accesible |" >> "$SALIDA"; continue; }

    RAMA="${RAMA_DE[$R]:-main}"
    GITLINK="$(git -C "$DIR" ls-tree "origin/$RAMA" contracts 2>/dev/null | awk '{print $3}')"

    if [ -z "$GITLINK" ]; then
      echo "| \`$R\` | **sin submódulo** | — | revisar |" >> "$SALIDA"
      REZAGADOS="$REZAGADOS $R(sin-submodulo)"
      continue
    fi

    TAG_CORRESP="$(git -C "$CDIR" tag --points-at "$GITLINK" 2>/dev/null | head -1)"
    [ -z "$TAG_CORRESP" ] && TAG_CORRESP="(commit sin tag)"

    if [ "$TAG_CORRESP" = "$ULTIMO_TAG" ]; then
      ESTADO="sí"
    else
      ESTADO="**NO — rezagado**"
      REZAGADOS="$REZAGADOS $R($TAG_CORRESP)"
    fi

    echo "| \`$R\` | \`${GITLINK:0:12}\` | $TAG_CORRESP | $ESTADO |" >> "$SALIDA"
  done

  {
    echo
    if [ -n "$REZAGADOS" ]; then
      echo "> **Repos que NO están en la última versión del contrato:**$REZAGADOS"
      echo ">"
      echo "> Esto no es necesariamente un error: un repo puede estar deliberadamente"
      echo "> en una versión anterior si su bloque no requiere lo nuevo. Pero tiene que"
      echo "> ser una decisión escrita, no un olvido. Cada rezagado necesita una línea"
      echo "> que diga por qué."
    else
      echo "> Los cinco consumidores apuntan a **$ULTIMO_TAG**. No hay rezagados."
    fi
    echo
  } >> "$SALIDA"
else
  echo "No se pudo acceder a \`dinas-wms-contracts\`. Sin él no se puede auditar el contrato." >> "$SALIDA"
fi

# --------------------------------------------------------------------------
# 3. Ramas que no están integradas en la rama por defecto
# --------------------------------------------------------------------------
{
  echo "## 3. Trabajo que existe en ramas y no está en el tronco"
  echo
  echo "Ramas remotas cuyo tip NO es ancestro de la rama por defecto. Cada una es"
  echo "trabajo que existe pero que un agente que clone el tronco no va a ver."
  echo
} >> "$SALIDA"

for R in "${REPOS[@]}"; do
  DIR="$ESPEJO/$R"
  [ -d "$DIR/.git" ] || continue
  RAMA="${RAMA_DE[$R]:-main}"

  SUELTAS=""
  while read -r REF; do
    [ -z "$REF" ] && continue
    B="${REF#origin/}"
    [ "$B" = "$RAMA" ] && continue
    [ "$B" = "HEAD" ] && continue
    if ! git -C "$DIR" merge-base --is-ancestor "$REF" "origin/$RAMA" 2>/dev/null; then
      ADELANTE="$(git -C "$DIR" rev-list --count "origin/$RAMA..$REF" 2>/dev/null || echo '?')"
      SUELTAS="$SUELTAS\n  - \`$B\` — $ADELANTE commits fuera del tronco"
    fi
  done < <(git -C "$DIR" for-each-ref --format='%(refname:short)' refs/remotes/origin 2>/dev/null)

  if [ -n "$SUELTAS" ]; then
    echo "**\`$R\`**" >> "$SALIDA"
    printf "$SUELTAS\n\n" >> "$SALIDA"
  fi
done

# --------------------------------------------------------------------------
# 4. Qué documentación de contexto ya existe en cada repo
# --------------------------------------------------------------------------
{
  echo "## 4. Contexto que ya vive en los repositorios"
  echo
  echo "Lo que un agente encontraría hoy al clonar. Un repo sin \`CLAUDE.md\` obliga"
  echo "a re-explicar su contexto en cada tarea."
  echo
  echo "| Repositorio | CLAUDE.md | README | docs/ | ADR |"
  echo "|---|---|---|---|---|"
} >> "$SALIDA"

for R in "${REPOS[@]}"; do
  DIR="$ESPEJO/$R"
  [ -d "$DIR/.git" ] || continue
  RAMA="${RAMA_DE[$R]:-main}"
  tiene() { git -C "$DIR" cat-file -e "origin/$RAMA:$1" 2>/dev/null && echo "sí" || echo "—"; }
  tiene_dir() { git -C "$DIR" ls-tree "origin/$RAMA" "$1" 2>/dev/null | grep -q . && echo "sí" || echo "—"; }
  echo "| \`$R\` | $(tiene CLAUDE.md) | $(tiene README.md) | $(tiene_dir docs/) | $(tiene_dir docs/adr/) |" >> "$SALIDA"
done

{
  echo
  echo "---"
  echo
  echo "## Qué hacer con esto"
  echo
  echo "1. Toda fila de la sección 2 marcada como rezagada necesita una decisión escrita:"
  echo "   se actualiza, o se documenta por qué se queda donde está."
  echo "2. Toda rama de la sección 3 necesita un destino: se integra, se descarta, o se"
  echo "   anota como trabajo en curso con dueño."
  echo "3. Todo repo sin \`CLAUDE.md\` en la sección 4 lo necesita antes de que un agente"
  echo "   trabaje ahí de forma desatendida."
  echo
  echo "Esta auditoría mira el SERVIDOR. Lo que esté solo en tu Windows o en tu Mac y"
  echo "no se haya empujado, no aparece aquí — para eso está \`auditar-local\`."
} >> "$SALIDA"

echo
echo "Informe escrito en: $SALIDA"
echo "Espejo de los repos en: $ESPEJO"
