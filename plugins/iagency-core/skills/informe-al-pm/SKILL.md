---
name: informe-al-pm
description: Cómo escribirle al Project Manager humano, que entiende el negocio del cliente pero no es programador ni arquitecto. Úsalo para el reporte de estado, para pedir una decisión, para reportar un bloqueo o un riesgo, y para las notas de entrega que el PM va a reenviar al cliente.
---

# Escribirle al PM

El PM decide, aprueba y habla con el cliente. No lee código y no debería tener que
hacerlo. Todo lo que le escribas debe poder leerse en dos minutos y terminar en una
acción clara.

# Formato del reporte de estado

```markdown
## <Proyecto> — <fecha>

**En una línea:** <dónde está el trabajo y si hay algo que te frene>

**Terminado**
- <lo que un usuario del cliente puede hacer ahora que antes no podía>

**En curso**
- <qué y para cuándo>

**Necesito que decidas**
1. <pregunta concreta> — Opciones: A) ... B) ... — Consecuencia de cada una en una frase.

**Riesgos**
- <qué puede salir mal, dicho en consecuencia para el cliente>
```

# Reglas

1. **Habla de capacidades, no de componentes.** No: "se implementó el endpoint
   `POST /returns` con validación de estado". Sí: "el bodeguero ya puede registrar una
   devolución desde la tableta y queda con foto y firma."

2. **Toda pregunta viene con opciones y consecuencias.** Preguntar "¿qué hacemos con
   las devoluciones parciales?" le traslada al PM un trabajo que es tuyo. Preguntar
   "¿una devolución parcial cierra el pedido o lo deja abierto? Si cierra, el vendedor
   no puede completar después; si queda abierto, hay que revisarlos manualmente cada
   semana" le permite decidir en treinta segundos.

3. **Un riesgo se cuenta en consecuencias.** No "la vista no tiene índice". Sí: "el
   reporte de ventas va a tardar más de un minuto cuando el cliente tenga un año de
   datos; conviene corregirlo antes de octubre."

4. **Los plazos, con su supuesto.** "Jueves, si la credencial del ERP de pruebas llega
   mañana." Un plazo sin supuesto es un plazo que se va a incumplir sin aviso.

5. **Las malas noticias van primero y sin rodeos.** Un bloqueo escondido en el tercer
   párrafo es un bloqueo que se descubre una semana tarde.

6. **Nada de jerga.** Ni "endpoint", ni "refactor", ni "deploy", ni "sprint" si el PM
   no los usa. Si un término técnico es imprescindible, explícalo en la misma frase.

7. **Español neutro, sin voseo.** Este texto puede llegar al cliente tal cual.

# Cuándo escribirle

- Al cerrar una entrega.
- Cuando algo se bloquea y no se puede desbloquear sin él.
- Cuando aparece un riesgo nuevo con consecuencia para el cliente.
- Cuando el alcance real difiere de lo acordado, en cuanto se detecta.
- Al final de cada jornada de trabajo autónomo, aunque no haya novedad: un resumen de
  tres líneas basta, y evita que el PM tenga que preguntar.

No le escribas para pedirle detalles que puedes deducir del sistema, ni para
confirmarle cosas que ya aprobó, ni para narrar avances intermedios sin decisión.
