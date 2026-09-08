# Verificación del perímetro

No pases de aquí hasta que las cinco comprobaciones den el resultado esperado. Todo lo
demás de la fábrica se apoya en esto: si el perímetro no está bien, la autonomía total
deja de ser un riesgo calculado y pasa a ser un riesgo a secas.

Ejecuta cada comprobación **en el nodo**, como el usuario `fabrica`, y anota el resultado.

---

## 1. El agente no puede salir a internet por su cuenta

Esto **debe fallar** (tiempo agotado o conexión rechazada):

```
docker run --rm --network iagency iagency/agente:1 curl -s -m 5 https://example.com
```

- Esperado: sin salida, código distinto de 0.
- Si devuelve HTML, el cortafuegos no está aplicando. Revisa `nft list ruleset` y que la
  red `iagency` sea `172.20.0.0/16`.

## 2. El agente sí puede salir a lo permitido, y solo por el proxy

Esto **debe devolver un código HTTP**:

```
docker run --rm --network iagency -e HTTPS_PROXY=http://172.20.0.1:3128 iagency/agente:1 curl -s -o /dev/null -w '%{http_code}\n' https://api.anthropic.com
```

- Esperado: un código HTTP (401 o 404 están bien; lo que importa es que hubo respuesta).
- Si da 0 o se cuelga, revisa `systemctl status squid` y `/var/log/iagency/proxy.log`.

## 3. Un dominio fuera de la lista se deniega aunque uses el proxy

Esto **debe fallar** con un error del proxy (403):

```
docker run --rm --network iagency -e HTTPS_PROXY=http://172.20.0.1:3128 iagency/agente:1 curl -s -o /dev/null -w '%{http_code}\n' https://pastebin.com
```

- Esperado: 403, o un fallo de CONNECT.
- Si devuelve 200, la lista `dominios-permitidos.txt` no se está aplicando: el
  `http_access deny all` final de `squid.conf` tiene que ser la última regla.

## 4. El contenedor no corre como root

```
docker run --rm iagency/agente:1 id
```

- Esperado: `uid=1001(agente)`. Si dice `uid=0(root)`, el `USER` del Dockerfile no se
  aplicó y Claude Code se negará a arrancar con permisos amplios.

## 5. Los guardarraíles bloquean de verdad

Con el plugin instalado, en un proyecto de prueba, pídele a un agente que ejecute
`git push --force origin main`. **Debe** rehusarse citando la razón del hook, no
ejecutarlo y no pedirte permiso.

Comprobación directa del script, sin agente de por medio:

```
echo '{"tool_input":{"command":"git push --force origin main"}}' | bash plugins/iagency-core/scripts/guard-bash.sh
```

- Esperado: un JSON con `"permissionDecision":"deny"`.
- Si no sale nada, el script no es ejecutable o falta `jq`.

---

## Registro

| # | Comprobación | Fecha | Resultado | Quién |
|---|---|---|---|---|
| 1 | Salida directa denegada | | | |
| 2 | Salida por proxy permitida | | | |
| 3 | Dominio no permitido denegado | | | |
| 4 | Contenedor no root | | | |
| 5 | Guardarraíl bloquea | | | |

Repite las cinco cada vez que cambies el cortafuegos, el proxy, la imagen del agente o
la lista de dominios. Es media hora al mes y es lo que hace defendible darle una máquina
entera a un agente.
