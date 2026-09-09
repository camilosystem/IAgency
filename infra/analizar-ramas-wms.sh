#!/usr/bin/env bash
# analizar-ramas-wms.sh — Primera tarea real de la fábrica sobre el WMS.
#
# Responde la pregunta que bloquea todo el levantamiento: ¿el estado real del
# proyecto está en el tronco o en las ramas? Y lo hace SIN TOCAR NADA: el espejo
# de los repositorios se monta en SOLO LECTURA.
#
# Uso, en el nodo:
#   bash /opt/iagency/fabrica/infra/analizar-ramas-wms.sh
#
# Produce un informe en /opt/iagency/entregas/analisis-ramas/
#
# NOTA SOBRE LOS AGENTES: la imagen del contenedor trae Claude Code pero no el
# plugin iagency-core. Se resuelve montando las definiciones de agentes y skills
# como .claude/agents y .claude/skills del área de trabajo, que es donde Claude
# Code los descubre de forma nativa. Sin marketplace ni instalación.

set -uo pipefail

BASE="${IAGENCY_BASE:-/opt/iagency}"
FABRICA="$BASE/fabrica"
ESPEJO="$BASE/auditoria/wms"
SALIDA="$BASE/entregas/analisis-ramas"
IMAGEN="${IAGENCY_IMAGEN:-iagency/agente:1}"

[ -n "${ANTHROPIC_API_KEY:-}" ] || { echo "Falta ANTHROPIC_API_KEY. Corre: source ~/.iagency-env"; exit 1; }
[ -d "$ESPEJO/dinas-wms-dashboard" ] || { echo "No existe el espejo. Corre primero: bash $FABRICA/infra/auditar-wms.sh"; exit 1; }

mkdir -p "$SALIDA"

# El área de trabajo del agente: el informe se escribe aquí, los repos se leen
# desde el montaje de solo lectura.
cat > "$SALIDA/INSTRUCCIONES.md" <<'EOF'
# Contexto de esta tarea

Los repositorios del WMS Dinas están montados en `/repos`, en **solo lectura**.
No intentes escribir ahí: no puedes, y no debes.

Tu único destino de escritura es `/workspace`.

## El proyecto

WMS para Dinas Distribution Corp, ocho repositorios bajo `camilosystem`. El
contrato `openapi.yaml` vive centralizado en `dinas-wms-contracts` y cada
consumidor lo monta como submódulo git en `contracts/`, anclado a un tag.

El contrato va por **v0.99.5**. Pero en el tronco: `middleware` apunta a v0.99.5,
`dashboard` a v0.36.0, y las tres apps iOS a v0.29.0.

El proyecto está pausado desde un congelamiento de código a finales de agosto.
EOF

echo "Lanzando el análisis. Puede tardar entre diez y veinte minutos."
echo

docker run --rm \
  --name iagency-analisis-ramas \
  --network iagency \
  --cpus "${IAGENCY_CPUS:-3}" \
  --memory "${IAGENCY_RAM:-6g}" \
  --pids-limit 2048 \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  --tmpfs /tmp:rw,exec,size=2g \
  -v "$ESPEJO:/repos:ro" \
  -v "$SALIDA:/workspace:rw" \
  -v "$FABRICA/plugins/iagency-core/agents:/workspace/.claude/agents:ro" \
  -v "$FABRICA/plugins/iagency-core/skills:/workspace/.claude/skills:ro" \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  -e IAGENCY_TAREA="analisis-ramas" \
  -e IAGENCY_ENTORNO="pruebas" \
  "$IMAGEN" \
  claude -p "$(cat <<'PROMPT'
Eres el agente `analista` de la fábrica IAgency. Lee primero
/workspace/INSTRUCCIONES.md.

Tarea: determinar si el estado real del WMS Dinas está en el tronco (`main`) o en
las ramas de trabajo, y dejar el dato que el arquitecto principal necesita para
decidir qué hacer con el contrato.

Los repositorios están en `/repos`, en solo lectura. Son clones completos con
todas las ramas remotas: usa `git -C /repos/<repo> ...` para todo.

## Las cuatro ramas divergentes

- `dinas-wms-dashboard` → `origin/feat/dashboard-carrito-ventana-unica` (117 commits fuera del tronco), y también `origin/feat/dashboard-cartera` y `origin/polish/cartera-visual` (1 cada una)
- `dinas-wms-app-sales` → `origin/feat/settings-backup` (64)
- `dinas-wms-app-bodega` → `origin/feat/app-shortages` (42)
- `dinas-wms-app-driver` → `origin/feat/app-payments` (30)

## Para CADA rama, averigua y reporta

1. **Qué contiene.** Recorre los mensajes de commit y los archivos tocados. Resume
   en tres o cuatro frases qué funcionalidad aporta esa rama.
2. **Rango de fechas.** Primer y último commit fuera del tronco. Una rama cuyo
   último commit es muy anterior al del tronco huele distinto a una que siguió viva.
3. **A qué versión del contrato apunta.** Mira el gitlink del submódulo `contracts`
   en el tip de la rama: `git -C /repos/<repo> ls-tree origin/<rama> contracts`.
   Después busca a qué tag corresponde ese commit dentro de
   `/repos/dinas-wms-contracts`: `git -C /repos/dinas-wms-contracts tag --points-at <sha>`.
   **Este dato es el más importante de toda la tarea.**
4. **¿Se puede integrar limpio?** Comprueba si `origin/main` es ancestro del tip de
   la rama (`git merge-base --is-ancestor`). Si lo es, la integración sería un
   avance rápido. Si no, hubo trabajo en el tronco después de que la rama saliera y
   habría que fusionar.
5. **Archivos que tocaría la integración.** `git diff --stat origin/main..origin/<rama>`.
   Señala en particular si toca `contracts`, migraciones, o archivos de configuración.
6. **¿Viva o abandonada?** Da tu lectura, con la evidencia en que te apoyas. No
   afirmes de más: si no puedes distinguirlo, dilo.

## También

- Compara el `main` de cada repositorio contra su rama principal y di, en una
  frase por repositorio, cuál de los dos representa el trabajo más avanzado.
- Revisa si alguna rama contiene un `openapi.yaml` SUELTO dentro de `contracts/`
  además del submódulo. Eso indicaría una copia manual, que en este proyecto ya
  causó tres incidentes.
- Revisa qué documentación de contexto (`CLAUDE.md`, `docs/`) existe en las ramas
  y no en el tronco.

## Entregable

Escribe `/workspace/ANALISIS-RAMAS.md` con:

- Un resumen ejecutivo de media página: ¿tronco o ramas? Dicho en una frase, y
  luego los matices por repositorio.
- Una tabla con una fila por rama: repositorio, rama, commits, rango de fechas,
  versión del contrato en su tip, integrable por avance rápido sí/no, veredicto.
- Una sección por rama con el detalle de los seis puntos de arriba.
- Una sección final **"Lo que el arquitecto tiene que decidir"**: la lista de
  decisiones concretas que quedan abiertas, cada una con las opciones y la
  consecuencia de cada opción. No decidas tú: tu trabajo es que quien decida tenga
  el dato completo.
- Una sección **"No verificado"** con lo que no pudiste determinar y por qué.

Reglas: solo lectura sobre `/repos`. Pega la salida real de los comandos que
sustentan cada afirmación. Distingue siempre lo que verificaste de lo que
infieres. Español neutro, sin voseo.
PROMPT
)" \
  --permission-mode dontAsk \
  --allowedTools "Read,Glob,Grep,Write,Edit,Bash(git *),Bash(ls *),Bash(cat *),Bash(head *),Bash(tail *),Bash(wc *),Bash(sort *),Bash(uniq *),Bash(grep *),Bash(find *)" \
  --verbose 2>&1 | tee "$SALIDA/registro-$(date +%Y%m%d-%H%M%S).log"

echo
echo "==================================================================="
if [ -f "$SALIDA/ANALISIS-RAMAS.md" ]; then
  echo "  Informe listo: $SALIDA/ANALISIS-RAMAS.md"
  echo "  Longitud: $(wc -l < "$SALIDA/ANALISIS-RAMAS.md") líneas"
else
  echo "  El agente NO dejó el informe. Revisa el registro en $SALIDA/"
fi
echo "==================================================================="
