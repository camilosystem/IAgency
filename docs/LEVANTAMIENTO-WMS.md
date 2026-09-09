# Levantamiento de contexto del WMS Dinas

Procedimiento para que la fábrica pueda trabajar el WMS de forma desatendida sin
romper nada y sin decidir a ciegas. Se ejecuta **una vez**, en este orden, y el
resultado queda versionado en los repositorios.

La premisa: hoy el conocimiento del proyecto está repartido entre ocho repositorios,
una docena de conversaciones y la cabeza de Camilo. Un agente solo puede leer lo
primero. Todo lo que no baje a archivos, para un agente **no existe** — y actuará
como si nunca hubiera existido, que es exactamente el riesgo de la autonomía.

---

## Orden

Cada paso depende del anterior. No los adelantes.

1. **Auditar el servidor** — qué hay realmente en GitHub.
2. **Auditar las copias locales** — qué tienes sin empujar en Windows y en el Mac.
3. **Cerrar las brechas** — empujar, integrar o documentar cada diferencia.
4. **Extraer el contexto de cada conversación** — con la plantilla de este documento.
5. **Consolidar** — que el `analista` cruce todo y produzca el estado real.
6. **Resolver contradicciones** — las que aparezcan, contigo decidiendo.
7. **Escribir el `CLAUDE.md` de cada repositorio** — la memoria permanente del equipo.

---

## Paso 1 — Auditar el servidor

En el nodo:

```
bash /opt/iagency/fabrica/infra/auditar-wms.sh
```

Produce un informe con: el commit de cada repositorio en su rama por defecto, la
última versión del contrato publicada, a qué versión apunta el submódulo de cada
consumidor, qué ramas tienen trabajo fuera del tronco, y qué documentación de
contexto existe hoy en cada repositorio.

**Qué mirar primero:** la tabla de "a qué versión apunta cada consumidor". Un repo
rezagado no es necesariamente un error —puede estar deliberadamente atrás si su
bloque no requiere lo nuevo— pero tiene que ser una decisión escrita. Si nadie
recuerda por qué está atrás, está atrás por olvido.

---

## Paso 2 — Auditar las copias locales

La auditoría del servidor no ve lo que está solo en tus máquinas. En **Windows**
(middleware y dashboard) y en el **Mac** (las tres apps iOS), para cada repositorio:

```
git status --short --branch
```

```
git log --oneline origin/main..HEAD
```

```
git stash list
```

Lo que buscas son tres cosas, y cada una es una forma distinta de perder trabajo:

- **Cambios sin commitear.** Existen solo en ese disco.
- **Commits sin empujar.** Existen solo en ese disco.
- **Stashes olvidados.** Trabajo guardado a medias que nadie recuerda.

Anota lo que encuentres. Todo eso es invisible para los agentes.

**Una trampa específica del submódulo:** en un repositorio consumidor, comprueba
que `contracts/` no tenga un `openapi.yaml` suelto distinto del que trae el
puntero. Ya pasó tres veces: alguien copia el archivo descargado dentro del repo
consumidor en vez de mover el puntero del submódulo.

```
git -C contracts status --short
```

Debe salir vacío y en detached HEAD sobre un tag. Cualquier otra cosa es una copia
manual que hay que deshacer.

---

## Paso 3 — Cerrar las brechas

Para cada diferencia encontrada en los pasos 1 y 2, una de tres decisiones, y las
tres se escriben:

- **Se integra** — empujas la rama, mueves el puntero, actualizas el submódulo.
- **Se descarta** — borras la rama, tiras el stash, y anotas qué había.
- **Se queda como está** — y escribes por qué, con nombre y fecha.

No hay cuarta opción. Una rama sin destino asignado es trabajo que dentro de tres
meses nadie sabrá si importaba.

---

## Paso 4 — Extraer el contexto de cada conversación

Esta es la parte que solo puedes hacer tú, y la que más valor aporta.

### Cómo funciona

Abres cada conversación del proyecto, pegas la plantilla de abajo tal cual, y
guardas la respuesta como un archivo en
`dinas-wms-contracts/docs/levantamiento/<nombre-del-chat>.md`.

Uno por conversación. Mismo formato en todos, para que el `analista` pueda cruzarlos.

### Por qué el repositorio de contratos

Porque es el único que todos los demás ya consumen, y porque es donde vive la
autoridad del proyecto. El levantamiento no pertenece a ningún repositorio de
código en particular: es transversal.

### La plantilla

Pega esto literalmente en cada conversación:

---

> Necesito extraer el contexto de esta conversación a un documento, para que agentes
> que no participaron en ella puedan continuar el trabajo sin perder nada. Responde
> en español neutro, sin voseo, con esta estructura exacta y sin añadir secciones.
>
> **1. Alcance de este chat.** Qué parte del WMS se trabajó aquí, en tres o cuatro
> frases. Qué repositorios se tocaron.
>
> **2. Estado al cierre.** Qué quedó terminado y funcionando, qué quedó a medias, y
> qué se abandonó. Para cada cosa terminada, cómo se verificó — comando, prueba o
> evidencia concreta. Si algo se dio por bueno sin verificar, dilo.
>
> **3. Versión del contrato.** Con qué versión de `openapi.yaml` se trabajó, y si
> este chat propuso o aplicó algún cambio de contrato. Da el tag y el blob id si los
> tienes.
>
> **4. Decisiones tomadas y su porqué.** Cada decisión de diseño con la razón real y
> las alternativas que se descartaron. El "por qué" importa más que el "qué": un
> agente que no conoce la razón va a deshacer la decisión en cuanto le estorbe.
>
> **5. Supuestos.** Todo lo que se asumió sin confirmar. Especialmente sobre datos
> reales, comportamiento de SAP, o cómo trabaja el personal de Dinas.
>
> **6. Lo que se intentó y no funcionó.** Enfoques descartados, callejones sin
> salida, cosas que parecían buena idea y no lo eran. Esta sección es la que más se
> pierde y la que más tiempo ahorra: sin ella, otro agente va a intentar exactamente
> lo mismo.
>
> **7. Trampas del terreno.** Lo que hace perder horas a quien llega nuevo. Bugs con
> forma engañosa, verificaciones que dan falso verde, comportamientos que sorprenden.
>
> **8. Deuda conocida.** Lo que quedó mal a sabiendas, con el motivo y el riesgo que
> implica.
>
> **9. Pendientes.** Lo que falta, en el orden en que este chat lo abordaría, y por
> qué ese orden.
>
> **10. Lo prometido.** Si en este chat se comprometió algo ante Camilo, ante los
> directivos de Dinas o en la demostración, escríbelo textualmente y di si se cumplió.
>
> **11. Contradicciones que sospechas.** Cosas que crees que otro chat pudo haber
> decidido distinto, o donde tu información puede estar desactualizada.
>
> **12. Lo que un agente nuevo debe saber antes de tocar nada.** Cinco puntos como
> máximo. Si solo pudieras dejarle una nota, ¿qué diría?
>
> Reglas: distingue siempre lo que VERIFICASTE de lo que ASUMISTE. Si no sabes algo,
> escribe "no lo sé" en vez de una estimación. No adornes el estado: un problema
> escondido aquí se convierte en trabajo desatendido mal ejecutado.

---

### La lista de conversaciones

Márcalas a medida que las extraigas. Completa las que falten — esta lista sale de
lo que consta hasta hoy, y solo tú sabes si está entera.

| # | Conversación | Extraída |
|---|---|---|
| 1 | Arquitecto principal — autoridad del contrato | ☐ |
| 2 | Arquitecto de Infraestructura | ☐ |
| 3 | Agente del middleware | ☐ |
| 4 | Agente del Dashboard | ☐ |
| 5 | Agente del Mac (app-sales, app-bodega, app-driver) | ☐ |
| 6 | Agente de revisiones (Claude in Chrome) | ☐ |
| 7 | Demostración a los directivos / MVP | ☐ |
| 8 | Carrito institucional (VENDEDOR_INSTITUCIONAL) | ☐ |
| 9 | Pagos de cartera y solicitudes de crédito | ☐ |
| 10 | Órdenes de venta → Facturas | ☐ |
| 11 | Retornos y disposición del producto | ☐ |
| 12 | Venta controlada / cupo por vendedor | ☐ |
| 13 | Avisos y novedades | ☐ |
| 14 | Segunda ola de pruebas (olas 1 y 2) | ☐ |
| 15 | Sincronizador SAP y su monitor | ☐ |
| 16 | Vistas SQL (`dinas-wms-sql`) | ☐ |
| 17 | Congelamiento de código | ☐ |
| 18 | | ☐ |
| 19 | | ☐ |
| 20 | | ☐ |

**Cómo saber si falta alguna:** recorre el historial de conversaciones por fecha,
desde el inicio del proyecto. Cualquiera que haya producido código, contrato o una
decisión de diseño va en la lista. Una conversación de la que no salió nada
tampoco hace falta extraerla, pero anótala como descartada para no volver a
preguntártelo.

---

## Paso 5 — Consolidar

Con los documentos del paso 4 dentro del repositorio, el `analista` los cruza y
produce `docs/ESTADO-REAL.md`: qué está construido, qué está decidido, qué quedó
abierto, y **dónde las fuentes se contradicen**.

Esa última parte es el producto más valioso del levantamiento. Una contradicción
entre dos chats no es ruido: es una decisión que nunca se cerró, y si un agente la
encuentra sin avisar, va a elegir una de las dos versiones por su cuenta.

La cola de esta tarea se escribe cuando los documentos estén. Antes no tiene
sentido: el agente no puede cruzar lo que no existe.

---

## Paso 6 — Resolver contradicciones

El `analista` no decide: reporta. Cada contradicción llega a ti con las dos
versiones y la consecuencia de cada una, y tú eliges. Lo elegido se escribe como
ADR en `docs/adr/` del repositorio que corresponda.

Esto es trabajo tuyo y no se puede delegar. Es también la razón por la que este
levantamiento tiene valor más allá de los agentes: vas a descubrir decisiones que
creías cerradas y no lo estaban.

---

## Paso 7 — El `CLAUDE.md` de cada repositorio

Al final, cada repositorio recibe el suyo, construido sobre lo consolidado. Ese
archivo es lo que un agente lee en **cada** sesión: es la memoria permanente del
equipo, y la diferencia entre un agente que entiende el proyecto y uno que
re-descubre lo mismo cada vez.

Lleva, como mínimo: qué es ese componente, con qué versión del contrato trabaja,
las reglas de oro del proyecto, las trampas conocidas de ese repositorio en
concreto, los comandos de build y prueba, y lo que está fuera de límites.

---

## Cuándo está terminado el levantamiento

Las cinco condiciones, todas verificables:

- [ ] La auditoría del servidor no reporta ningún rezagado sin explicación escrita.
- [ ] Ninguna máquina local tiene commits sin empujar ni stashes sin destino.
- [ ] Cada conversación de la lista está extraída o marcada como descartada.
- [ ] `ESTADO-REAL.md` existe y sus contradicciones están todas resueltas o
      escaladas.
- [ ] Los ocho repositorios tienen `CLAUDE.md`.

Hasta que las cinco estén, la fábrica trabaja el WMS **con supervisión**. La
autonomía desatendida se gana con este documento cerrado, no antes.
