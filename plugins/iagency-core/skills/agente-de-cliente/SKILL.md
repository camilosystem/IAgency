---
name: agente-de-cliente
description: Cómo construir y entregar un agente de IA entrenado sobre los datos y procesos de un cliente — el que responde preguntas de negocio, analiza sus datos y genera reportes. Cubre el alcance, la base de conocimiento, los límites, la evaluación y la entrega. Úsalo cuando el encargo sea crear un agente para un cliente, no software convencional.
---

# Construir un agente para un cliente

Un agente entregado a un cliente es un producto, no un experimento. Se especifica, se
evalúa con un conjunto de casos, y se entrega con sus límites escritos. Un agente que
responde con seguridad algo falso destruye la confianza del cliente en todo lo que le
hayas entregado, incluido el software que sí funciona.

# 1. Alcance, antes de nada

Escribe `docs/agentes/<nombre>/alcance.md`:

- **Preguntas que debe responder.** Una lista concreta de al menos 20 preguntas
  reales, en las palabras del usuario del cliente. Salen del PM y del cliente, no de tu
  imaginación.
- **Preguntas que NO debe responder.** Igual de importante. Todo lo que quede fuera
  debe recibir una negativa clara, no una respuesta aproximada.
- **Quién pregunta**: rol, nivel técnico, dispositivo, contexto.
- **Qué puede hacer además de responder**: ¿genera gráficos? ¿escribe en algún sistema?
  Cualquier capacidad de escritura necesita aprobación explícita y confirmación humana.

# 2. La base de conocimiento

La calidad del agente es la calidad de sus datos. Casi todo el trabajo está aquí.

- **Inventaria las fuentes**: tablas, vistas, documentos, procedimientos. Para cada una:
  quién la mantiene, cada cuánto se actualiza, y si es confiable.
- **Prepara los datos estructurados** con el agente `dev-datos`: vistas planas, nombres
  autoexplicativos, sin abreviaturas internas.
- **Escribe un diccionario de datos**: qué significa cada columna, qué valores son
  válidos, qué significa un vacío, en qué unidad y en qué moneda. Sin esto el agente
  inventa la interpretación.
- **Escribe las reglas de negocio del cliente** en texto: cómo calcula él las ventas,
  qué considera un cliente activo, cómo trata las devoluciones. Cada empresa define
  esto distinto y el agente no puede adivinarlo.
- **Marca lo que está desactualizado o es dudoso**. Un dato malo etiquetado como malo
  es útil; un dato malo sin etiquetar es una respuesta equivocada esperando su turno.

# 3. Límites que todo agente de cliente debe tener

- **Solo lectura** contra los sistemas del cliente, salvo aprobación explícita por
  escrito para una operación concreta.
- **Cita la fuente** de cada cifra que dé: de qué vista o documento salió, de qué
  periodo.
- **Dice "no lo sé"**. Se le instruye explícitamente a no responder cuando la
  información no está en su base. Esto se prueba en la evaluación.
- **No inventa cifras.** Si el dato no está, no se estima, no se aproxima, no se
  ilustra con un ejemplo que parezca real.
- **No mezcla clientes ni sucursales.** Si el agente sirve a varios usuarios con
  distinto alcance, el filtro de alcance se aplica en la consulta, no en la instrucción
  al modelo.
- **Registra toda pregunta y respuesta**, para poder auditar y mejorar.

# 4. Evaluación: el paso que nadie hace y que decide todo

Antes de entregar, construye `docs/agentes/<nombre>/evaluacion.md` con un conjunto de
casos:

- **30 a 50 preguntas** con su respuesta correcta conocida, verificada contra la fuente.
- Reparto: preguntas directas, preguntas que requieren combinar dos fuentes, preguntas
  ambiguas (debe pedir aclaración), preguntas fuera de alcance (debe negarse), y
  preguntas trampa cuya premisa es falsa (debe corregir la premisa, no seguirle la
  corriente).
- Se ejecuta la batería completa y se registra el resultado de cada caso.
- **Criterio de entrega**: cero respuestas con cifra incorrecta. Una cifra equivocada
  con tono seguro es peor que diez "no lo sé". Las negativas incorrectas se toleran y se
  corrigen después; las afirmaciones falsas, no.
- La batería se vuelve a correr **entera** cada vez que se cambia el prompt, los datos
  o el modelo. Un ajuste que arregla una pregunta suele romper tres.

# 5. Entrega al cliente

- **Documento de capacidades y límites**, en lenguaje de negocio: qué puede preguntar,
  qué no, y qué hacer cuando el agente diga que no sabe.
- **Advertencia explícita**: las respuestas se verifican antes de tomar decisiones con
  consecuencia económica. Escrito, no dicho.
- **Canal de retroalimentación**: cómo reporta el cliente una respuesta mala. Cada
  reporte se convierte en un caso nuevo de la batería de evaluación.
- **Plan de mantenimiento**: los datos cambian y el agente se degrada en silencio. Fija
  cada cuánto se revisa y quién lo hace.

# Elección de modelo

- Preguntas de negocio sobre datos preparados: un modelo intermedio basta y el costo
  por consulta importa, porque el volumen es alto.
- Análisis que requiere razonamiento de varios pasos o interpretar ambigüedad: modelo
  mayor.
- Clasificación, extracción y enrutamiento: modelo pequeño y barato.
- Si los datos del cliente no pueden salir de su perímetro: modelo abierto en servidor
  local. Deja escrito qué se pierde en calidad con esa decisión, para que el cliente la
  tome informado.
