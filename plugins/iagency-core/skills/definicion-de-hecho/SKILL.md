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

| Mal | Bien |
|---|---|
| El módulo funciona correctamente | `dotnet test --filter Categoria=Devoluciones` pasa las 14 pruebas |
| La pantalla se ve bien en móvil | La pantalla se opera completa en 390 px de ancho sin desplazamiento horizontal; evidencia: captura |
| El reporte está cuadrado | El total de ventas del reporte coincide con `SELECT SUM(...)` del ERP para el mes de agosto, diferencia 0 |
| Es rápido | La consulta responde en menos de 2 s con los 1,4 M de filas de la réplica |
| Es seguro | Un usuario del rol Vendedor recibe 403 al pedir `/api/pedidos/{id}` de otra ruta; evidencia: salida de la petición |

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
