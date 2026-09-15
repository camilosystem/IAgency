---
name: definicion-de-hecho
description: Cómo escribir una Definición de Hecho verificable y cómo decidir si una tarea está realmente terminada. Úsalo al encuadrar cualquier trabajo nuevo, al escribir criterios de aceptación, y antes de cerrar una tarea o dar una entrega por buena.
---

# Definición de Hecho

Una tarea está hecha cuando **cada** condición de su Definición de Hecho tiene al lado
la evidencia que la comprueba. No antes, y no por consenso.

# Cómo se escribe una condición

Una condición válida cumple tres cosas:

1. **Se comprueba ejecutando algo**, no leyendo ni opinando.
2. **Tiene un resultado esperado concreto**, no un adjetivo.
3. **Otra persona (u otro agente) puede comprobarla** sin preguntarte nada.

En una tarea de documentación no hay software que ejecutar y la regla 1 se degrada
sola. Cómo se sostiene ahí: *Tareas de documentación*, más abajo. No escribas
condiciones de documentación sin leer esa sección.

| Mal | Bien |
|---|---|
| El módulo funciona correctamente | `dotnet test --filter Categoria=Devoluciones` pasa las 14 pruebas |
| La pantalla se ve bien en móvil | La pantalla se opera completa en 390 px de ancho sin desplazamiento horizontal; evidencia: captura |
| El reporte está cuadrado | El total de ventas del reporte coincide con `SELECT SUM(...)` del ERP para el mes de agosto, diferencia 0 |
| Es rápido | La consulta responde en menos de 2 s con los 1,4 M de filas de la réplica |
| Es seguro | Un usuario del rol Vendedor recibe 403 al pedir `/api/pedidos/{id}` de otra ruta; evidencia: salida de la petición |

# Tareas de documentación: la condición se invierte

En una tarea de documentación no hay nada que ejecutar, así que la condición se
degrada sola a la forma *"el documento recoge X"* — y eso se comprueba leyendo la
frase que lo afirma. Eso no es verificar: es encontrar lo que ya se sabía que estaba.
El resultado es un falso verde, y ya ocurrió: se aprobó "no hay contradicción en el
documento" tras leer solo la frase de encabezado de la sección. La contradicción
estaba cuatro líneas más abajo.

El principio que lo corrige:

> **Una condición de coherencia NO se verifica encontrando la frase que la afirma,
> sino buscando la frase que la contradice.**

Por eso la condición debe nombrar **qué contradicción hay que cazar y dónde**, no qué
afirmación hay que encontrar. Se da por cumplida cuando la búsqueda se hizo completa y
volvió vacía; la evidencia es el barrido, no la cita.

| Mal — busca la afirmación | Bien — caza la contradicción |
|---|---|
| El documento no se contradice sobre el alcance | Ninguna de las 9 apariciones de "alcance" en el archivo nombra un módulo fuera de los 3 de la sección 1; evidencia: salida completa de `grep -n alcance` |
| La guía dice que el proceso tiene 4 pasos | Ninguna sección posterior enumera un quinto paso ni renumera los 4; evidencia: salida completa de `grep -nE 'paso [0-9]'` |
| Los ejemplos están en español neutro | Cero apariciones de voseo en todo el archivo; evidencia: `grep -nE '(^\|[^[:alnum:]])(hacé\|revisá\|verificá\|elegí\|tenés\|podés)([^[:alnum:]áéíóúñ]\|$)'` vacío, descontadas las citas que enseñan qué no escribir |
| La versión del contrato está actualizada | No queda mención de la versión anterior ni en este archivo ni en los que lo citan; evidencia: `grep -rn` de la versión vieja, vacío |
| El comentario del script explica la regla | Ninguna línea de comentario describe un criterio distinto del que aplica el código de al lado; evidencia: cada bloque de comentario contrastado contra su regla, uno por uno |

Reglas de la búsqueda:

- **El alcance es el archivo entero, no la sección.** El falso verde típico es leer el
  encabezado y aprobar. El encabezado casi siempre dice lo correcto; el desmentido
  vive más abajo, donde ya nadie mira.
- **Sí hay algo que ejecutar: la búsqueda.** Un `grep` con su patrón y su salida
  pegada es evidencia ejecutable y otro agente la reproduce. "Lo leí y está bien" no
  lo es, y no cuenta como criterio cumplido.
- **Una búsqueda vacía solo vale si el patrón podía encontrar algo.** Antes de creerle
  al vacío, comprueba que el mismo patrón encuentra un caso que sí existe. Un patrón
  mal escrito y un documento limpio se ven idénticos. El error clásico en español:
  `\b` no cierra palabra después de una vocal acentuada, así que `\bverificá\b` marca
  "verificándolo" y el barrido se llena de ruido en el que el hallazgo real se pierde.
- **Descuenta las citas que enseñan qué no escribir.** Un documento de doctrina
  contiene a propósito los ejemplos malos que prohíbe; el patrón va a encontrarlos.
  Eso no es un hallazgo — pero decidirlo exige mirar cada línea, no el número total.
- **Quien verifica no es quien escribió el documento.** Y no es `qa`: estas tareas van
  al `revisor`.

# Piso mínimo de toda entrega de código

Ninguna tarea de implementación se cierra sin esto, aunque nadie lo haya pedido:

- [ ] Compila sin errores y sin advertencias nuevas.
- [ ] Linter y chequeo de tipos en verde.
- [ ] Pruebas nuevas por cada criterio de aceptación **y** por cada camino de error.
- [ ] Suite completa en verde (no solo lo nuevo): sin regresiones.
- [ ] Ninguna prueba omitida, debilitada o modificada para hacerla pasar.
- [ ] Cero secretos en el código o en la configuración versionada.
- [ ] Texto visible al usuario en español neutro, sin voseo.
- [ ] `qa` aprobó con evidencia.
- [ ] `revisor` aprobó.
- [ ] `seguridad` aprobó, si el cambio toca autenticación, permisos, datos de cliente,
      red, secretos o dependencias nuevas.
- [ ] Documentación actualizada si el cambio altera cómo se usa el sistema.

# Lo que NO cuenta como hecho

- "Funciona en mi entorno" sin la salida pegada.
- Una prueba que prueba el mock y no el comportamiento.
- Un criterio marcado como cumplido sin evidencia al lado.
- Un camino de error que nunca se ejecutó.
- Un reporte que nunca se contrastó contra la fuente de verdad.
- Una integración con un sistema externo que solo se probó contra un simulador.

# Regla de las tres rondas

Si una tarea vuelve rechazada por tercera vez, no se intenta una cuarta. Se detiene,
se escribe el postmortem y se escala. Un agente atascado consume presupuesto de forma
lineal y produce valor cero; el problema casi nunca está en la implementación, sino en
la especificación o en el diseño, y ninguna cantidad de intentos lo va a arreglar.
