---
name: contrato-primero
description: Cómo definir, versionar, verificar y cambiar el contrato que une a los componentes de un sistema (OpenAPI, esquema de base de datos, mapeo de campos con un ERP). Úsalo antes de implementar cualquier cosa que cruce un límite entre componentes, y siempre que haya que modificar una interfaz que ya tiene consumidores.
---

# El contrato manda

En todo proyecto de este equipo, la interfaz entre dos componentes se define **antes**
de implementarla, vive en un archivo versionado, y es la única fuente de verdad. Ni el
código del servidor ni el del cliente pueden contradecirla.

Esto no es burocracia: es lo que permite que varios agentes trabajen en paralelo sin
coordinarse turno a turno. Cada uno programa contra el contrato, no contra lo que otro
agente esté haciendo en ese momento.

# Qué es un contrato, por tipo de límite

| Límite | Contrato |
|---|---|
| API HTTP | `openapi.yaml` — operaciones, esquemas, códigos de error |
| Base de datos | Migraciones versionadas + registro de objetos |
| Cola / mensajería | Esquema del mensaje, versionado |
| Integración con ERP | Mapeo campo a campo: campo origen, campo destino, tipo, obligatoriedad, transformación, valor por defecto |
| Archivo de intercambio | Especificación del formato con ejemplo real |

# Cómo se verifica que un contrato está íntegro

Un contrato solo sirve si todos trabajan sobre exactamente el mismo archivo. Para
eso se publica con su huella:

Calcula la huella del contrato:

```
sha256sum openapi.yaml
```

Registra en `docs/contrato/historial.md`: versión, fecha, huella, y qué cambió.
Quien consume el contrato compara su huella con la publicada antes de empezar. Si no
coinciden, no se programa: se sincroniza primero.

Para que la huella sea estable entre sistemas operativos, fija los finales de línea:

```
echo "*.yaml text eol=lf" >> .gitattributes
```

# Cómo se cambia un contrato

Un cambio de contrato es un evento del proyecto, no una edición más.

1. **Clasifica el cambio.**
   - *Aditivo*: campo opcional nuevo, operación nueva, valor nuevo en una lista que ya
     tolera desconocidos. Compatible hacia atrás.
   - *Rompedor*: campo eliminado o renombrado, tipo cambiado, campo que pasa a
     obligatorio, semántica distinta con el mismo nombre. **Cualquiera de estos rompe a
     todos los consumidores.**

2. **Localiza a los consumidores.** Antes de cambiar nada, lista qué componentes usan
   la operación o el campo afectado. Si no tienes ese mapa, constrúyelo: buscar el
   nombre de la operación en todos los repositorios es suficiente y toma minutos.

3. **Sube la versión** del contrato y actualiza el historial con la huella nueva.

4. **Actualiza a los consumidores en el mismo lote.** Un contrato cambiado sin sus
   consumidores actualizados es un sistema roto que todavía no se ha dado cuenta.

5. **Para un cambio rompedor en un sistema ya en operación**: convivencia. Se agrega
   lo nuevo, se marca lo viejo como obsoleto, se migran los consumidores, y solo
   entonces se elimina lo viejo. Nunca de golpe.

# Reglas duras

- Nunca cambies un contrato de forma silenciosa. Sube la versión, siempre.
- Nunca dejes que el código y el contrato se contradigan. Si los ves distintos, para y
  reporta; no elijas tú cuál gana.
- Nunca implementes contra la respuesta observada de una API en vez de contra su
  contrato. Lo que devolvió hoy no es lo que promete.
- Nunca inventes un campo porque te haría falta. Pide el cambio de contrato.
- Un contrato sin ejemplo real de petición y respuesta está a medio escribir.
