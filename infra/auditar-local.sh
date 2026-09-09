#!/usr/bin/env bash
# auditar-local.sh — Qué tienes sin empujar en esta máquina (Mac o Linux).
#
# Equivalente de auditar-local.ps1. Recorre los repositorios del WMS que tengas
# localmente y reporta las tres formas de perder trabajo: cambios sin commitear,
# commits sin empujar, y stashes olvidados.
#
# Uso, apuntando a la carpeta que contiene los repos:
#     bash auditar-local.sh ~/Projects/WMS_DINAS

set -uo pipefail

RAIZ="${1:-.}"
SALIDA="${2:-auditoria-local-$(date +%Y%m%d-%H%M%S).md}"

[ -d "$RAIZ" ] || { echo "No existe la carpeta: $RAIZ"; exit 1; }

HALLAZGOS=0

{
  echo "# Auditoría local — $(hostname)"
  echo
  echo "Generada: $(date -Iseconds 2>/dev/null || date)"
  echo "Raíz: \`$RAIZ\`"
  echo
  echo "> Esto es lo que existe SOLO en esta máquina. Nada de lo que aparezca aquí"
  echo "> es visible para los agentes hasta que se empuje a GitHub."
  echo
} > "$SALIDA"

for REPO in "$RAIZ"/*/; do
  [ -d "$REPO/.git" ] || continue
  NOMBRE="$(basename "$REPO")"
  echo "Revisando $NOMBRE..."

  RAMA="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  SUCIO="$(git -C "$REPO" status --porcelain 2>/dev/null)"
  SINPUSH="$(git -C "$REPO" log --oneline '@{u}..HEAD' 2>/dev/null || true)"
  STASHES="$(git -C "$REPO" stash list 2>/dev/null)"
  SUBMAL=""
  SUBTAG=""
  if [ -d "$REPO/contracts" ]; then
    SUBMAL="$(git -C "$REPO/contracts" status --porcelain 2>/dev/null || true)"
    SUBTAG="$(git -C "$REPO/contracts" describe --tags --exact-match 2>/dev/null || true)"
  fi

  TIENE=""
  [ -n "$SUCIO" ] && TIENE="x"
  [ -n "$SINPUSH" ] && TIENE="x"
  [ -n "$STASHES" ] && TIENE="x"
  [ -n "$SUBMAL" ] && TIENE="x"
  [ -n "$TIENE" ] && HALLAZGOS=$((HALLAZGOS+1))

  {
    echo "## $NOMBRE"
    echo
    echo "Rama actual: \`$RAMA\`"
    echo

    if [ -n "$SUCIO" ]; then
      echo "### Cambios sin commitear"; echo; echo '```'; echo "$SUCIO"; echo '```'; echo
    fi
    if [ -n "$SINPUSH" ]; then
      echo "### Commits sin empujar"; echo; echo '```'; echo "$SINPUSH"; echo '```'; echo
    fi
    if [ -n "$STASHES" ]; then
      echo "### Stashes guardados"; echo; echo '```'; echo "$STASHES"; echo '```'; echo
      echo "Cada stash necesita un destino: se aplica, o se descarta anotando qué había."; echo
    fi
    if [ -n "$SUBMAL" ]; then
      echo "### AVISO — el submódulo contracts tiene cambios locales"; echo
      echo '```'; echo "$SUBMAL"; echo '```'; echo
      echo "Esto suele significar que alguien copió un openapi.yaml descargado dentro del"
      echo "repositorio consumidor en vez de mover el puntero del submódulo. Ya pasó tres"
      echo "veces en este proyecto. El flujo correcto es publicar en dinas-wms-contracts y"
      echo "mover el puntero, nunca copiar el archivo."; echo
    elif [ -n "$SUBTAG" ]; then
      echo "Submódulo \`contracts\` en el tag \`$SUBTAG\` y limpio."; echo
    fi
    [ -z "$TIENE" ] && { echo "Sin hallazgos: todo commiteado y empujado."; echo; }
  } >> "$SALIDA"
done

{
  echo "---"
  echo
  if [ "$HALLAZGOS" -eq 0 ]; then
    echo "**Ningún repositorio tiene trabajo sin empujar.** Esta máquina está al día."
  else
    echo "**$HALLAZGOS repositorios tienen algo que solo existe aquí.** Cada hallazgo"
    echo "necesita una decisión escrita: se integra, se descarta, o se queda con motivo."
  fi
} >> "$SALIDA"

echo
echo "Informe escrito en: $SALIDA"
echo "Repositorios con hallazgos: $HALLAZGOS"
