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
SALIDA="${1:-$AREA/docs/auditoria/$(date +%Y%m%d-%H%M%S).md}"
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
  tail -200 "${IAGENCY_AUDIT_LOG:-/var/log/iagency/comandos.log}" 2>/dev/null || echo "sin registro"
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
