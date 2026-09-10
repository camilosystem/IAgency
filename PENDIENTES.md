# Pendientes de endurecimiento del nodo

Cosas acordadas que todavía no están hechas. Cada una con lo que hay que hacer y
por qué importa, para que no dependan de que alguien se acuerde.

---

## 1. Cloud Firewall de DigitalOcean — puerto 22 solo desde la IP de Camilo

**Estado:** pendiente · **Acordado el:** 9 de septiembre de 2026 · **Prioridad:** alta

Hoy el puerto 22 del nodo está abierto a todo internet. El bootstrap ya desactivó la
autenticación por contraseña y activó fail2ban, así que no es una emergencia — pero
un puerto SSH expuesto recibe miles de intentos al día y no hay ninguna razón para
regalar esa superficie.

### Qué hacer

En la consola de DigitalOcean: **Networking → Firewalls → Create Firewall**.

- Nombre: `iagency-nodo`
- **Inbound Rules**: deja SOLO una regla — SSH, TCP, puerto 22, y en Sources la IP
  pública de Camilo. Borra la regla que viene por defecto con "All IPv4 / All IPv6".
- **Outbound Rules**: déjalas como vienen (todo permitido). El control de salida ya
  lo hace el proxy Squid con su lista de dominios; duplicarlo aquí solo añade un
  sitio más donde equivocarse.
- **Apply to Droplets**: `IA-gency-ubuntu-s-8vcpu-16gb-amd-nyc1`

### La trampa: no quedarte fuera de tu propio servidor

Si la IP de tu casa u oficina es dinámica —y la de la mayoría de las conexiones
residenciales lo es— el día que cambie perderás el acceso por SSH.

Dos salvaguardas, y conviene tener las dos:

1. **La Web Console de DigitalOcean sigue funcionando siempre.** Va por la
   infraestructura de DO, no por la red pública, así que el Cloud Firewall no la
   afecta. Esa es tu vía de rescate: desde ahí puedes editar o quitar la regla.
   Compruébalo ANTES de aplicar el firewall, no después.
2. Si tu IP cambia a menudo, en vez de una IP suelta pon el **rango de tu proveedor**
   (un /24 suele bastar) o considera una IP estática.

### Cómo verificar que quedó bien

Desde tu máquina, esto debe seguir funcionando:

```
ssh fabrica@137.184.210.100
```

Y desde cualquier otra red (el teléfono con datos móviles sirve), esto debe agotar
el tiempo de espera en lugar de pedir credenciales:

```
ssh -o ConnectTimeout=8 fabrica@137.184.210.100
```

---

## 2. Actualizar el plugin en las máquinas donde ya estaba instalado

**Estado:** pendiente · **Prioridad:** media

El guardarraíl `guard-bash.sh` se corrigió después de la primera instalación: el
patrón de borrado bloqueaba cualquier ruta absoluta, incluidas las de los worktrees.
Las máquinas que instalaron antes de esa corrección siguen con la versión vieja.

```
claude plugin marketplace update iagency
```

```
claude plugin update iagency-core
```

---

## 3. Alerta de gasto en la consola de la API

**Estado:** pendiente · **Prioridad:** alta antes de la primera jornada desatendida

Un agente en bucle a las tres de la mañana no tiene quien lo detenga. El hook de
presupuesto corta por número de llamadas de herramienta, pero eso es por tarea, no
por mes. Configura un límite de gasto mensual y una alerta por correo en la consola
de la plataforma antes de dejar la fábrica corriendo sin supervisión.

---

## 4. Réplica de solo lectura para el trabajo con datos

**Estado:** pendiente · **Prioridad:** alta antes de cualquier tarea de `dev-datos`

Ningún agente toca la base de producción de un cliente. Antes de asignar la primera
tarea que consulte datos reales, tiene que existir la réplica de solo lectura o el
entorno de pruebas con datos anonimizados, y la cadena de conexión de trabajo debe
apuntar ahí.

---

## 5. Snapshot del nodo una vez configurado

**Estado:** pendiente · **Prioridad:** media

Cuando el perímetro esté verificado y el nodo funcionando, toma un snapshot en
DigitalOcean. Si más adelante hay que recrear el nodo o levantar un segundo, partir
del snapshot ahorra los quince minutos del bootstrap y garantiza que la segunda
máquina es idéntica a la primera.

---

## 6. Rotar la clave de firma JWT del middleware de desarrollo

**Estado:** pendiente · **Descubierto el:** 10 de septiembre de 2026 · **Prioridad:** media

La auditoría local del Mac encontró que `.claude/settings.local.json` estaba
**rastreado en git** en `dinas-wms-app-sales`, y ese archivo contiene tokens JWT
completos de al menos tres roles (`APROBADOR_PAGOS`, `APROBADOR_CREDITOS`,
`vendedor1`), además de la IP de Tailscale del middleware y parte de la topología
de la red interna.

**Por qué no es una emergencia.** Los tokens decodificados expiraron el 30 de julio
y el 10 de agosto de 2026. El repositorio es privado. El middleware solo responde
por Tailscale.

**Por qué sigue siendo un defecto.** Los tokens quedaron en el *historial* de git,
no solo en el archivo. Y el archivo crecía en cada sesión de agente, así que iba a
volver a capturar tokens — esos sí vigentes.

**Lo hecho el 10 de septiembre:** el archivo se desrastreó y se ignoró en los tres
repositorios iOS. Eso corta el flujo hacia adelante.

**Lo que falta:** rotar la clave de firma JWT del middleware `dev`. Eso invalida de
un golpe todo token que exista en cualquier historial de git, sin necesidad de
reescribir historia — que sobre ramas a punto de integrarse al tronco sería peor
que el riesgo que resuelve. Hacerlo cuando toque tocar la configuración del
middleware, no antes.

**Regla que queda:** `.claude/settings.local.json` nunca se commitea. Es
configuración de una máquina, captura rutas locales y argumentos de comandos —
incluidos tokens que aparecieron en la línea de comandos.

---

## 7. Decidir dónde vive el arte fuente del logo (ADR)

**Estado:** pendiente · **Descubierto el:** 10 de septiembre de 2026 · **Prioridad:** baja

`DinasApp.png` y `DinasApp_blanco.png` estaban sueltos en la raíz de `app-bodega` y
`app-driver`, sin commitear y sin ignorar — dos copias idénticas (shasum
`1a9ee732…` y `a1898b0e…`) del 28 de agosto. Un agente que corriera `git add -A`
las habría metido al commit sin que nadie lo pidiera.

El `imageset` derivado sí está commiteado en las apps, pero **el original no está en
ningún repositorio**. Ese es exactamente el hueco que produjo el defecto documentado
en la lista de congelamiento: el velo alfa del PNG blanco tratado de dos maneras
distintas por dos agentes que no se hablaban, porque cada uno derivó del original
por su cuenta.

**Lo hecho el 10 de septiembre:** las cuatro copias se consolidaron en
`~/Desktop/dinas-wms-arte-fuente/` en el Mac, fuera de los repositorios. Cierra el
riesgo del `git add -A`, no pierde nada, y no compromete la decisión de fondo.

**Lo que falta decidir (es del arquitecto):** dónde vive el arte fuente de forma
autoritativa y con su receta de derivación. El candidato natural es
`dinas-wms-contracts`, porque es el único repositorio que las ocho consumidoras ya
traen como submódulo — una sola copia, disponible para todos. Contra: amplía el
significado de "contracts" de contrato de API a activos compartidos. Escribir la
decisión como ADR, no dejarla implícita.
