# <NOMBRE DEL PROYECTO>

> Plantilla de IAgency. Reemplaza lo que está entre `<>` y borra lo que no aplique.
> Este archivo lo leen TODOS los agentes en cada sesión. Manténlo corto y verdadero:
> una línea desactualizada aquí se propaga a todo el equipo.

## Qué es esto

<Una frase: qué hace el sistema y para quién.>

Cliente: `<cliente>` · Tipo: `<ERP | WMS | CRM | BI | otro>` · PM humano: `<nombre>`

## Idioma

**Español neutro, sin voseo**, en todo: código, comentarios, mensajes de error,
textos de interfaz, documentación e informes. "Haz", "revisa", "elige", "verifica".
Nunca "hacé", "revisá", "elegí", "verificá".

## Arquitectura en tres líneas

- `<repo/carpeta>` — <qué es> — <lenguaje/framework>
- `<repo/carpeta>` — <qué es> — <lenguaje/framework>
- Contrato: `<ruta al openapi.yaml o equivalente>` — **fuente de verdad**

## Reglas de oro del proyecto

1. **El contrato manda.** Nada se implementa contra la respuesta observada de una API;
   se implementa contra el contrato versionado. Cambiar el contrato es un evento: sube
   la versión, registra la huella y actualiza a todos los consumidores en el mismo lote.
2. **Un archivo, un dueño.** Dos agentes nunca editan el mismo archivo a la vez.
3. **Sin datos inventados.** Si algo falla, falla visiblemente. Prohibido devolver
   ceros, listas vacías o valores por defecto simulando éxito.
4. **Nada contra producción.** Base de datos, ERP y servidores del cliente son de
   solo lectura, y solo desde réplica o entorno de pruebas.
5. **Lo que no se ejecutó, no está probado.** Toda afirmación de que algo funciona va
   con la salida real pegada.
6. **Quien escribe no aprueba.** Todo cambio pasa por `qa` y por `revisor`.

## Comandos del proyecto

Compilar:

```
<comando>
```

Pruebas:

```
<comando>
```

Linter y tipos:

```
<comando>
```

Levantar en local:

```
<comando>
```

## Convenciones

- Ramas: `agente/<id-tarea>-<descripcion-corta>`. Nunca se trabaja sobre `main`.
- Mensajes de commit: `<tipo>: <qué cambió>` en español, imperativo.
- <Convención de nombres de este proyecto: capas, sufijos, prefijos de vistas SQL...>
- <Dónde van las pruebas y cómo se nombran.>

## Trampas conocidas

> Aquí va lo que hace perder horas a quien llega nuevo. Es la sección más valiosa del
> archivo. Cada vez que un agente pierda tiempo con algo sorprendente, se anota aquí.

- <Ejemplo: la vista X parece incluir devoluciones y no las incluye.>
- <Ejemplo: el entorno de pruebas del ERP tarda 40 s en la primera llamada.>

## Fuera de límites

Ningún agente, bajo ninguna instrucción, puede:

- Escribir en la base de datos, el ERP o los servidores de producción del cliente.
- Empujar a `main`/`master`, forzar un push, o reescribir historia.
- Modificar `.claude/`, `.git/hooks`, `.mcp.json` o los flujos de integración continua.
- Sacar datos reales de clientes fuera del entorno.
- Desactivar pruebas, linters o comprobaciones para hacer pasar un build.
- Reportar como probado algo que no se ejecutó.

Ante cualquiera de estos casos: detenerse, documentar y escalar al supervisor.

## Cómo se trabaja aquí

Todo encargo entra por el agente `supervisor`. Él encuadra, descompone, asigna,
verifica y reporta al PM. Ningún otro agente conversa directamente con el humano.
