# Lista de congelamiento del WMS Dinas — 28 de agosto de 2026

Los commits exactos con los que se congeló el código para la demostración del 2 de
septiembre, y la receta de reconstrucción de cada repositorio.

**Por qué existe este archivo.** Esta lista vivía únicamente en la conversación del
arquitecto. Los tres `RECONSTRUIR.md` de las apps la citan como coordenada oficial
—"si la rama avanzó después del congelamiento, usa el hash de la lista"— y el hash
no estaba en ningún repositorio. Un agente que buscara `congelam|freeze` en los ocho
repositorios no encontraba nada, y con razón. Este documento cierra ese hueco.

---

## Los hashes

Cada uno fue leído con `git rev-parse HEAD` y confirmado con `git ls-remote` contra
el servidor — no con la salida del push, que puede mentir sobre lo que llegó.

| Repositorio | Commit | Referencia |
|---|---|---|
| `dinas-wms-contracts` | `f65c5e8c91622ade283de0f19f06af3a0347a380` | tag **v0.99.5** |
| `dinas-wms-middleware` | `ca97d206b09793187f7717d452e870190da72aed` | `main` |
| `dinas-wms-sap-sync` | `97627de894e5dc0c780358479b3595e7fc9f1fc2` | `main` |
| `dinas-wms-dashboard` | `453c9b6f87fd2c3afe7ea8eefc815e004fbbb2a1` | rama `feat/dashboard-carrito-ventana-unica` |
| `dinas-wms-app-sales` | `488c61610ccc53abc30e3c2e1dc8694acc83b534` | rama `feat/settings-backup` |
| `dinas-wms-app-bodega` | `eee11896ad20947542c80ae365940d4b744deed7` | rama `feat/app-shortages` |
| `dinas-wms-app-driver` | `1ade7fe5822d8f05afa534164bf046611bb7329f` | rama `feat/app-payments` |
| `dinas-wms-sql` | — | **entra con su hueco escrito, ver abajo** |

Contrato: blob `239d026ac6bf9ec6220e9cf698d215954e4069d6`, submódulo apuntando a
`f65c5e8c91622ade283de0f19f06af3a0347a380`.

### Hashes intermedios, para no confundirlos con el final

Aparecen en el historial y **no** son el congelamiento:

- `dashboard`: `500e6013…` → `38761d588065111e7be30ecb9aad29aafb81a42c` (arreglo de
  recogidas) → `c65089ffc876a33e6f7f075fe053ea5faa42423e` (logo) → **`453c9b6f…` final**
- `app-sales`: `a99a1103…` → **`488c6161…` final**
- `middleware`: `0a8ab891…` → `4f974264…` → **`ca97d206…` final**

---

## La lista de hashes no alcanza

Conclusión escrita al cerrar el congelamiento: **hace falta hash más receta de
reconstrucción, y la receta no es la misma en los siete repositorios.** Un hash sin
su receta produce un clon que no compila, y el fallo no dice por qué.

### Lo que aplica a todos

**Un clon sin `--recurse-submodules` no trae el contrato**, y sin contrato no corre
ni el chequeo de tipos. El puntero está dentro del commit, pero solo sirve si quien
clona inicializa el submódulo:

```
git submodule update --init --recursive
```

### `dinas-wms-app-driver`

El `.xcodeproj` está **gitignorado**: se genera. Antes de compilar, desde la raíz:

```
ruby Scripts/generate_project.rb
```

Es el único de los tres que **no puede desincronizarse**, precisamente porque se
genera. `app-sales` y `app-bodega` commitean un archivo que ya se desincronizó dos
veces el 26 de agosto.

### `dinas-wms-middleware`

`ConnectionStrings:Sap` vive en los user-secrets del perfil de Windows
(`%APPDATA%\Microsoft\UserSecrets\8c8a1c0c-…\secrets.json`), **invisible a git**.

El modo de fallo es el peligroso: sin esa clave el middleware **arranca igual** y
los lectores de SAP devuelven null. "Funciona, sin SAP" — que es exactamente el peor
estado para una demostración cuyo cuarto acto es SAP.

El repositorio es **privado**. Su README trae la plantilla de conexión con servidor,
base y usuario internos, con la contraseña como marcador. En un repositorio privado
eso es normal. **Condicional a recordar: si alguna vez se hace público, hay que
sustituir esa línea por marcadores ANTES de cambiar la visibilidad, no después.**

### `dinas-wms-dashboard`

`.env.development` está gitignorado, pero el fallo es **ruidoso**: `src/config/env.ts`
lanza si falta la variable, y `.env.example` está commiteado con la misma URL. Es la
versión buena del patrón — comparar con el middleware, que susurra.

### Las tres apps iOS

Cada una trae `RECONSTRUIR.md` en su raíz, y la receta se ejecutó verbatim desde tres
directorios vacíos antes de darla por buena.

**Advertencia que solo vive en esos archivos:** la build **Release apunta a producción
real** — SAP y licencias compartidas con Attain. Una demostración va en Debug/Dev,
nunca en Release.

Y dos condiciones de la demostración que están en el código, no en el guion:

- Las tres apps están bloqueadas a **vertical solo en `Info-Dev.plist`**. El
  `Info.plist` de producción conserva todas las orientaciones.
- `app-driver` es **solo iPhone** (`TARGETED_DEVICE_FAMILY='1'`). En iPad corre en
  modo compatibilidad y se ve mal.
- El logo sigue la apariencia del sistema, así que el iPad debe quedar en apariencia
  **fija**, nunca en "Automático": si no, la pantalla puede cambiar de aspecto a
  mitad de la demostración.

### `dinas-wms-sql` — el octavo, con su hueco

Entra a la lista **con el hueco escrito a propósito**, porque omitirlo haría que la
lista se leyera como completa:

- Sin control de versiones en el momento del congelamiento.
- Tres carpetas divergentes.
- No se midió cuál está desplegada.

La auditoría del 9 de septiembre encuentra el repositorio en `main` con commit
`4c4978d` del 6 de agosto. **Queda por verificar si ese repositorio refleja lo que de
verdad está desplegado en SQL Server**, o si sigue siendo una de las tres carpetas.

Relacionado: `sap-sync` tiene sin trackear `Vistas WMS-DINAS/` — los `.sql` de las
diez vistas `vw_WMS_` y su script de permisos. Es la frontera de gobernanza del
proyecto y falta decidir si es la copia autoritativa o un duplicado de
`dinas-wms-sql`.

---

## El estándar de reproducibilidad

`sap-sync` es el único de los ocho donde **el binario en ejecución declara de qué
commit salió**:

```
ProductVersion: 1.0.0+97627de…
```

Eso convierte "creo que corre el commit X" en un dato verificable. Se decidió
copiarlo en los demás repositorios después del 2 de septiembre. Sigue pendiente.

---

## Verificación del 9 de septiembre de 2026

Ejecutada con `infra/verificar-congelamiento.sh` contra el servidor.

**Cuatro en el congelamiento, tres avanzaron un commit, cero problemas.**

| Referencia | Estado |
|---|---|
| `contracts` main | igual — `f65c5e8c9162` |
| `middleware` main | igual — `ca97d206b097` |
| `sap-sync` main | igual — `97627de894e5` |
| `dashboard` `feat/dashboard-carrito-ventana-unica` | igual — `453c9b6f87fd` |
| `app-sales` `feat/settings-backup` | avanzó 1 → `bdb3f9aa1412` |
| `app-bodega` `feat/app-shortages` | avanzó 1 → `227840646ed6` |
| `app-driver` `feat/app-payments` | avanzó 1 → `afb831d6cee2` |

### DECISIÓN: los tres commits posteriores ENTRAN

Los tres son el mismo cambio, del mismo día 28 de agosto:

```
fix(ui): quitar el velo del logo blanco en modo oscuro (derivada del imageset)
```

**Contexto que lo explica.** Al congelar quedó anotado que el PNG blanco traía un
velo (alfa 12 sobre el 42 % del lienzo). El Dashboard lo había quitado en su
derivada descartando alfa menor que 40 y dejó la receta en `docs/logo.md`; **el Mac
no lo había quitado**, y por eso en modo oscuro el Home mostraba un recuadro gris
tenue. Se registró entonces como "mismo defecto, mismo archivo, dos tratamientos por
dos agentes que no se hablan", sin impacto en la demostración porque iba en claro.

Estos tres commits son el agente del Mac cerrando ese pendiente, horas después de
que se escribiera la lista.

**Por qué entran:**

- Corrigen un defecto conocido, documentado y ya resuelto del otro lado.
- Son puramente cosméticos: no tocan lógica, contrato ni datos.
- Los tres son el mismo cambio, coherentes entre sí.
- Excluirlos significaría reintroducir a propósito un defecto ya corregido.

Decidido el 9 de septiembre de 2026. Si alguien necesita reproducir exactamente la
build de la demostración del 2 de septiembre, los hashes de la tabla de arriba
siguen siendo la coordenada; esta decisión aplica a la **integración al tronco**,
no a la reproducción histórica.

---

## Movimientos posteriores — 9 y 10 de septiembre de 2026

Para que nadie confunda estos avances con divergencia. **Ninguno toca código,
contrato ni datos**: son documentación e higiene de repositorio. La tabla de hashes
de arriba sigue siendo la coordenada para reproducir la build del 2 de septiembre.

| Referencia | Congelamiento | Al 10-sep | Qué se agregó |
|---|---|---|---|
| `middleware` main | `ca97d206` | `dd1317a` | RECUPERACION.md y `catalog-images/` al .gitignore |
| `dashboard` rama | `453c9b6f` | `f233ae1` | documentación de la página de recuperación |
| `app-sales` rama | `488c6161` | `9f9926e` | velo del logo, más los tres documentos rescatados del Mac |
| `app-bodega` rama | `eee11896` | `bb13269` | velo del logo, más `.gitignore` |
| `app-driver` rama | `1ade7fe5` | `edbec8c` | velo del logo, más `.gitignore` |
| `contracts` main | `f65c5e8c` | igual | — |
| `sap-sync` main | `97627de8` | igual | — |

### Lo que rescató la auditoría del Mac

Tres documentos vivían únicamente en el disco del Mac y ahora están en
`dinas-wms-app-sales/docs/`:

- `checklist-verificacion-en-vivo.md` — el más valioso de los tres. Registra que
  **dos de los arreglos de fecha solo divergen después de las 20:00 hora de Nueva
  York**, que es cuando el día UTC se adelanta al de NY. Verificados por la mañana
  pasan sin probar nada. Un agente de QA que verificara a las 10 a.m. habría
  reportado verde con el defecto vivo.
- `instrucciones-app-sales-pagos-creditos.md` — contra contrato v0.17.8.
- `instrucciones-app-sales-payment-channel.md` — contra contrato v0.19.1. Contiene
  una decisión y su reversa: la app **nunca** muestra ni envía `payment_channel`;
  todo pago reportado desde la app es `VENDEDOR` del lado del middleware. Material
  directo para los ADR del paso 6 del levantamiento.

Los tres referencian versiones antiguas del contrato. Se commitearon tal cual: son
documentos históricos y su valor está en registrar qué se decidió y cuándo.

---

## Cómo verificar que una rama sigue en el congelamiento

Los tres `RECONSTRUIR.md` advierten: si la rama avanzó después del congelamiento,
manda el hash de esta lista, no el tip de la rama. Para comprobarlo:

```
bash infra/verificar-congelamiento.sh
```

Compara el tip actual de cada referencia contra los hashes de arriba y dice cuáles
avanzaron, cuántos commits, y de qué fecha son.
