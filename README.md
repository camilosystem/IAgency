# Fábrica de agentes IAgency

Un equipo de desarrollo hecho de agentes, con un solo humano por proyecto: el Project
Manager. Este repositorio contiene el estándar completo: los agentes, las skills de
proceso, los guardarraíles de seguridad, la infraestructura y el orquestador.

Está pensado para lo que hace IAgency: software a la medida para pequeñas y medianas
empresas — ERP, WMS, CRM, BI — y agentes entrenados sobre los datos del cliente.

---

## Cómo está organizado

```
iagency-fabrica/
├── .claude-plugin/marketplace.json     Marketplace propio, se instala en cualquier máquina
├── plugins/iagency-core/               El estándar del equipo, versionado y distribuible
│   ├── agents/                         Los 11 agentes del equipo
│   ├── skills/                         El proceso: handoff, definición de hecho, contrato…
│   ├── hooks/hooks.json                Enganche de los guardarraíles
│   └── scripts/                        Los guardarraíles y la auditoría
├── plantilla-proyecto/                 Lo que se copia a cada repositorio de cliente
│   ├── CLAUDE.md                       Contexto que leen todos los agentes
│   └── .claude/settings.json           Permisos, sandbox y variables
├── infra/                              Servidor, contenedor, proxy, aislamiento
└── runner/                             Orquestador desatendido + cola de ejemplo
```

---

## Instalación

### 1. Publica este repositorio

```
git init && git add . && git commit -m "Fábrica de agentes IAgency v1"
```

Súbelo a tu organización de GitHub como repositorio **privado**. Ajusta
`TU-ORG/iagency-fabrica` en `plantilla-proyecto/.claude/settings.json`.

### 2. Registra el marketplace en cada máquina

```
/plugin marketplace add TU-ORG/iagency-fabrica
```

### 3. Instala el plugin

```
/plugin install iagency-core@iagency
```

A partir de aquí, cualquier proyecto tuyo tiene los 11 agentes disponibles. Cuando
mejores un agente, actualizas este repositorio y todas las máquinas lo reciben.

### 4. Prepara un proyecto de cliente

Copia `plantilla-proyecto/CLAUDE.md` y `plantilla-proyecto/.claude/settings.json` al
repositorio del cliente y rellena lo que está entre `<>`. Ese `CLAUDE.md` es lo que
convierte agentes genéricos en agentes que conocen ese proyecto.

### 5. Monta un nodo de la fábrica

En un servidor **dedicado y desechable**, como root, una sola vez:

```
bash infra/bootstrap-servidor.sh
```

Y después sigue, uno por uno, los pasos que imprime al terminar.

---

## El equipo

| Agente | Qué hace | Modelo sugerido |
|---|---|---|
| `supervisor` | Único que habla con el PM humano. Encuadra, reparte, verifica, reporta | Opus |
| `analista` | Convierte negocio en especificación verificable | Sonnet |
| `arquitecto` | Estructura, contratos, ADR, plan de implementación | Opus |
| `dev-backend` | API, servicios, integraciones con ERP | Sonnet |
| `dev-frontend` | Pantallas, componentes, estado | Sonnet |
| `dev-datos` | Modelo de datos, vistas SQL, ETL, reportes, BI | Sonnet |
| `disenador` | Flujos, pantallas, textos, sistema de diseño | Opus |
| `qa` | Ejecuta y trata de romperlo. No puede editar | Sonnet |
| `revisor` | Lee el diff completo y señala defectos. No puede editar | Opus |
| `seguridad` | Audita el producto y audita la propia fábrica | Opus |
| `devops` | Build, entornos, CI, procedimiento de despliegue | Sonnet |
| `documentador` | Manual, notas de versión, resumen para el PM | Haiku |

Dos reglas sostienen todo lo demás:

- **Quien escribe no aprueba.** `qa` y `revisor` no pueden editar archivos. Es una
  restricción del propio agente, no una promesa.
- **Un archivo, un dueño.** Dos agentes nunca editan el mismo archivo a la vez. El
  supervisor lo garantiza al repartir; los worktrees lo hacen físico.

---

## Autonomía sin confirmaciones

Este es el punto delicado del diseño. Se resuelve con **tres anillos**, no con
desactivar los permisos.

### Anillo 1 — Aislamiento del sistema

Un contenedor **efímero por tarea**, usuario no root, sin credenciales de larga vida
dentro, sistema de archivos de solo lectura salvo el worktree, capacidades
eliminadas y límites de CPU, memoria y procesos. Cuando la tarea termina, el
contenedor se destruye: cualquier persistencia maliciosa muere con él.

### Anillo 2 — Egress por allowlist de dominio

El cortafuegos de Hetzner o DigitalOcean es de capa 3/4 y **no filtra por dominio**;
los dominios que los agentes necesitan están detrás de CDN con IP rotatoria, así que
por IP no se puede. La allowlist va en un proxy: Squid en el nodo (incluido en
`bootstrap-servidor.sh`) o `@anthropic-ai/sandbox-runtime`, que en Linux elimina el
namespace de red del proceso — no hay red que filtrar, solo el proxy.

### Anillo 3 — Guardarraíles en el harness

`permissions.defaultMode: "dontAsk"`: el agente **nunca** pregunta, todo lo que está
en `allow` corre solo, y lo que no está se deniega en silencio. Es la forma correcta
de tener cero confirmaciones sin perder las reglas.

> **No uses `bypassPermissions` como modo por defecto.** Salta *todas* las
> comprobaciones, incluidas tus reglas `deny`, y deja los hooks como única defensa.
> Resérvalo para un contenedor completamente desechable en un proyecto sin datos de
> cliente. Si `dontAsk` te deja corto, **amplía la lista `allow`** — no cambies el modo.

Encima de eso, los hooks de `plugins/iagency-core/scripts/` bloquean lo irreversible
(borrado masivo, push a `main`, reescritura de historia, escritura sobre puntos de
persistencia, descargar-y-ejecutar, escrituras SQL fuera de pruebas) y cortan al agente
que se atasca cuando agota su presupuesto de herramientas.

### Y una auditoría que no es opcional

`auditar-sesion.sh` corre al cerrar cada sesión. Existe por una razón concreta: en
Linux, la lista de rutas protegidas del sandbox se construye **una sola vez al
arrancar**, así que no cubre repositorios que la propia sesión haya creado con
`git init` o `git clone`. La auditoría cierra ese hueco. El agente `seguridad` lee su
salida y emite veredicto.

---

## Correr la fábrica

En el nodo, como el usuario `fabrica`:

```
export ANTHROPIC_API_KEY=...
```

Revisa primero lo que va a hacer, sin ejecutar nada:

```
python3 runner/runner.py runner/tareas.ejemplo.yaml --simular
```

Y cuando la cola esté bien, lánzala:

```
python3 runner/runner.py runner/tareas.ejemplo.yaml
```

El orquestador crea un worktree por tarea, respeta las dependencias, lanza un
contenedor efímero por cada una, recoge el informe de entrega y deja un resumen en
`/opt/iagency/entregas/`.

---

## Las cinco cosas que hacen que esto funcione o falle

1. **La verificación, no la generación, es el cuello de botella.** Generar código
   dejó de ser el problema. Por eso `qa`, `revisor` y `seguridad` no pueden editar
   nada, y por eso una entrega sin la salida real pegada no se acepta.

2. **La regla de las tres rondas.** Si una tarea vuelve rechazada tres veces, se
   detiene, se escribe el postmortem y se escala. El problema casi nunca está en la
   implementación, sino en la especificación; ninguna cantidad de intentos lo arregla.

3. **El contrato primero.** Es lo que permite que varios agentes trabajen en paralelo
   sin coordinarse turno a turno: cada uno programa contra el contrato, no contra lo
   que otro agente esté haciendo en ese momento.

4. **Nada contra producción, nunca.** Réplica de solo lectura o entorno de pruebas.
   Un agente autónomo con acceso de escritura al ERP de un cliente es un riesgo que
   ninguna mitigación compensa.

5. **El PM humano decide.** El supervisor le lleva preguntas con opciones y
   consecuencias, no problemas técnicos. Si el PM tiene que entender el código para
   responder, la pregunta está mal formulada.

---

## Antes de poner esto en un cliente

- [ ] `git init` en este repositorio y subirlo privado.
- [ ] Ajustar `TU-ORG/iagency-fabrica` en `plantilla-proyecto/.claude/settings.json`.
- [ ] Levantar el nodo y **verificar el egress con las dos pruebas** que imprime
      `bootstrap-servidor.sh` (una debe fallar, la otra debe funcionar).
- [ ] Preparar la réplica de solo lectura de la base del cliente.
- [ ] Estrenar la fábrica en un proyecto interno, no en uno de cliente.
- [ ] Correr una jornada completa y leer la auditoría de principio a fin.
- [ ] Fijar el presupuesto mensual y una alerta de gasto en la consola de la API.
