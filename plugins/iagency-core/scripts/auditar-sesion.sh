#!/usr/bin/env bash
# auditar-sesion.sh — Auditoría posterior a una sesión autónoma.
# Hook SessionEnd, y también ejecutable a mano al cierre de cada jornada.
#
# La documentación de Claude Code es explícita: tras una ejecución desatendida hay que
# revisar lo que quedó escrito. En Linux, además, la lista de rutas protegidas del
# sandbox se construye UNA sola vez al arrancar, así que no cubre repositorios que la
# propia sesión haya creado con git init o git clone. Esta auditoría cierra ese hueco.

set -uo pipefail

AREA="${IAGENCY_WORKTREE:-$PWD}"

# La auditoría NO se escribe dentro del repositorio auditado. Escribirla ahí
# deja un archivo sin trackear por sesión dentro del código del cliente, y un
# agente que corra `git add -A` lo commitea sin que nadie lo pida. Va a un
# directorio propio, fuera del área de trabajo; se puede redirigir con
# IAGENCY_AUDIT_DIR o pasando la ruta como primer argumento.
DESTINO="${IAGENCY_AUDIT_DIR:-${HOME:-/tmp}/.iagency/auditorias}"
mkdir -p "$DESTINO" 2>/dev/null || true

# Solo se audita un repositorio de git, y se audita entero desde su raíz. Mordió dos
# veces: una sesión que arrancó en la carpeta personal lanzó find y grep -r sobre el
# disco entero —OneDrive incluido— y el cierre parecía colgado. El área de trabajo de
# un agente SIEMPRE es un repositorio; si no lo es, algo está mal, y barrer en
# silencio lo tapa. Se niega, lo dice, y deja constancia en el directorio de
# auditorías para que la negativa no se pierda con la sesión.
#
# La carpeta personal se rechaza aunque sea un repositorio: un `git init` en `~`
# convertiría la comprobación de arriba en el mismo barrido del disco.
RAIZ="$(git -C "$AREA" rev-parse --show-toplevel 2>/dev/null || true)"
MOTIVO=""
if [ -z "$RAIZ" ]; then
  MOTIVO="\`$AREA\` no es un repositorio de git."
elif [ -n "${HOME:-}" ] && [ "$(cd "$RAIZ" && pwd -P)" = "$(cd "$HOME" && pwd -P)" ]; then
  MOTIVO="la raíz del repositorio es la carpeta personal (\`$RAIZ\`)."
fi
if [ -n "$MOTIVO" ]; then
  AVISO="Auditoría NO realizada: $MOTIVO El área de trabajo de un agente siempre es un repositorio; si la sesión arrancó fuera de uno, eso es lo que hay que revisar. Para auditar a mano: IAGENCY_WORKTREE=/ruta/al/repo bash auditar-sesion.sh"
  printf '%s\n' "$AVISO" >&2
  printf '# Auditoría NO realizada — %s\n\n%s\n' "$(date -Is)" "$AVISO" \
    > "$DESTINO/no-auditado-$(date +%Y%m%d-%H%M%S).md" 2>/dev/null || true
  exit 1
fi
AREA="$RAIZ"

SALIDA="${1:-$DESTINO/$(basename "$AREA")-$(date +%Y%m%d-%H%M%S).md}"
mkdir -p "$(dirname "$SALIDA")"

{
  echo "# Auditoría de sesión — $(date -Is)"
  echo
  echo "Área de trabajo: \`$AREA\`"
  echo "Tarea: \`${IAGENCY_TAREA:-sin-tarea}\`"
  echo

  echo "## 1. Puntos de persistencia modificados"
  echo '```'
  find "$AREA" \( -path '*/.git/hooks/*' -o -name '.mcp.json' -o -path '*/.claude/*' \
       -o -name '.bashrc' -o -name '.zshrc' -o -path '*/.vscode/tasks.json' \) \
       -newermt '-24 hours' -type f 2>/dev/null || true
  echo '```'
  echo "_Vacío es lo correcto. Cualquier resultado aquí exige explicación._"
  echo

  echo "## 2. Repositorios git creados o anidados"
  echo '```'
  find "$AREA" -name '.git' -maxdepth 6 -newermt '-24 hours' 2>/dev/null || true
  echo '```'
  echo "_Un repositorio nuevo no cubierto por las protecciones iniciales. Revísalo a mano._"
  echo

  echo "## 3. Archivos ejecutables nuevos"
  echo '```'
  find "$AREA" -type f -perm -u+x -newermt '-24 hours' \
       -not -path '*/node_modules/*' -not -path '*/.git/*' \
       -not -path '*/bin/Debug/*' -not -path '*/obj/*' 2>/dev/null | head -50
  echo '```'
  echo

  echo "## 4. Posibles secretos en el árbol de trabajo"
  echo '```'
  grep -rInE '(api[_-]?key|secret|password|token|connectionstring|bearer)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{12,}' \
       "$AREA" --include='*.cs' --include='*.ts' --include='*.tsx' --include='*.js' \
       --include='*.json' --include='*.yaml' --include='*.yml' --include='*.py' \
       --exclude-dir=node_modules --exclude-dir=.git 2>/dev/null | head -30 || echo "sin coincidencias"
  echo '```'
  echo

  echo "## 5. Comandos ejecutados en la sesión"
  echo '```'
  # El mismo valor por defecto que guard-bash.sh, que es quien escribe el registro.
  # Hasta la 1.3.0 aquí seguía /var/log/iagency: el guard escribía en $HOME desde
  # la 1.1.2 y esta sección decía "sin registro" siempre.
  tail -200 "${IAGENCY_AUDIT_LOG:-${IAGENCY_LOG_DIR:-${HOME:-/tmp}/.iagency/logs}/comandos.log}" 2>/dev/null || echo "sin registro"
  echo '```'
  echo

  echo "## 6. Estado del repositorio"
  echo '```'
  git -C "$AREA" status --porcelain 2>/dev/null | head -60 || echo "no es un repositorio git"
  echo '```'
  echo '```'
  git -C "$AREA" log --oneline -15 2>/dev/null || true
  echo '```'
  echo

  echo "## 7. Salidas de red"
  echo '```'
  tail -100 "${IAGENCY_PROXY_LOG:-/var/log/iagency/proxy.log}" 2>/dev/null || echo "sin registro de proxy"
  echo '```'
  echo "_Revisa dominios fuera de la lista permitida y volúmenes de subida anómalos._"
  echo
  echo "---"
  echo "Pasa este informe al agente \`seguridad\` para su veredicto."
} > "$SALIDA"

echo "Auditoría escrita en: $SALIDA"
