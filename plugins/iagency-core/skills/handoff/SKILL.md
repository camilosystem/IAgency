---
name: handoff
description: El formato obligatorio con el que un agente cierra su tarea y se la devuelve al supervisor. Úsalo al terminar cualquier tarea asignada, antes de decir que algo está listo, y cuando haya que pasarle trabajo a otro agente.
---

# Informe de entrega entre agentes

Todo agente cierra su tarea con este bloque. Sin él, el supervisor no puede evaluar
nada y el trabajo se considera no entregado.

Escríbelo en `docs/entregas/<id-tarea>/<tu-rol>.md` **y** repítelo como último mensaje
de tu turno.

```markdown
# Entrega — <id-tarea> — <rol>

## Estado
COMPLETADO | PARCIAL | BLOQUEADO

## Qué se pidió
Una frase.

## Qué se hizo
Lista corta. Solo hechos.

## Archivos tocados
- ruta/exacta/archivo.ext — qué cambió
(lista completa; si tocaste algo fuera de tu tarea, ponlo primero y explica por qué)

## Evidencia
La salida REAL de lo que ejecutaste, pegada tal cual.
Build, pruebas, consultas, capturas, respuestas de API.
Si no ejecutaste nada, esta sección dice "ninguna" y el estado no puede ser COMPLETADO.

## Criterios de aceptación
| # | Criterio | Estado | Evidencia |
|---|----------|--------|-----------|
| 1 | ...      | cumplido / no cumplido / no verificado | ... |

## Lo que NO hice
Lo que estaba en la tarea y quedó fuera, con el motivo.

## Supuestos
Todo lo que tuviste que asumir porque no estaba especificado.
Cada supuesto es una pregunta que el supervisor puede necesitar llevarle al PM.

## Riesgos y deuda
Lo que dejas a sabiendas y por qué.

## Siguiente paso sugerido
Qué agente debería recibir esto y para qué.
```

# Reglas del informe

1. **La evidencia es la salida real.** Pegar la salida del comando, no describirla.
   "Las pruebas pasan" no es evidencia; las 40 líneas del corredor de pruebas sí.

2. **Nunca declares COMPLETADO con criterios no verificados.** Si no pudiste
   verificar uno, el estado es PARCIAL. Esta regla es la que sostiene la confianza en
   toda la cadena; romperla una vez obliga a revisar todo a mano.

3. **La lista de archivos tocados es exacta.** El supervisor la usa para detectar
   colisiones entre agentes. Un archivo omitido provoca que dos agentes se pisen.

4. **Los supuestos se declaran siempre.** Un supuesto silencioso que resulta falso
   cuesta más que un día de espera por una respuesta del PM.

5. **BLOQUEADO no es un fracaso.** Es información. Di exactamente qué te falta: un
   dato, una credencial, una decisión, un entorno. Un agente bloqueado que sigue
   intentando durante veinte turnos es mucho peor que uno que reporta el bloqueo en el
   segundo.

6. **Sin adornos.** Nada de "he implementado exitosamente una solución robusta".
   Hechos, archivos, salidas.
