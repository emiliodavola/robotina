# Modelo de seguridad del stack

Este stack corre **dos agentes autónomos con capacidad de ejecutar código**
(Hermes gateway y OpenCode) sobre un workspace compartido. El objetivo del
diseño no es "que no pase nada" sino **acotar el daño**: si un agente es
inducido a actuar en contra de tus intereses, no tiene ruta para exfiltrar
datos ni para moverse lateralmente.

## Garantías

| Garantía | Cómo se implementa |
| --- | --- |
| Sin ruta directa a Internet para los agentes | `hermes` y `opencode` están **solo** en la red `agents` (`internal: true`). Esa red no tiene gateway: no hay salida ni resolución externa de nombres. |
| Egreso mediado y con allowlist | El único contenedor con salida es `egress-proxy` (Squid). Solo pasa lo que figura en `squid/allowlist.txt`; el resto se deniega con `403` y queda en el log del proxy. |
| Nada entra desde el host o la LAN | Ningún servicio publica puertos. El bot de Telegram funciona por polling saliente. |
| Sin pivotaje hacia la red interna o metadata de cloud | Squid deniega rangos privados (`10/8`, `172.16/12`, `192.168/16`, `127/8`, `169.254/16`, `fc00::/7`, …) antes de evaluar la allowlist. |
| Sin escalada de privilegios | Los tres contenedores: `cap_drop: [ALL]`, `no-new-privileges`, `ulimits.core: 0`. |
| Sin socket de Docker | Nunca se monta `/var/run/docker.sock`. |
| Proxy inmutable | `egress-proxy` corre como usuario `proxy` (uid 13) con rootfs de solo lectura y `/var/log`, `/var/spool`, `/run`, `/tmp` en tmpfs. |
| Blast radius acotado | Límites de CPU, memoria y PIDs por contenedor; logs `json-file` con rotación (10 MB × 3). |
| Auditoría sin secretos | El formato de log de Squid registra timestamp, IP de origen, método y estado — **nunca la URL**, porque el token del bot viaja en la ruta (`/bot<token>/...`). |

## Variables requeridas

`compose.yml` interpola estas variables desde un `.env` **externo y no
versionado**. Si falta alguna, compose aborta con un mensaje explícito en vez
de arrancar con claves vacías:

```ini
# Hermes (gateway de Telegram)
TELEGRAM_BOT_TOKEN=          # token emitido por @BotFather
HERMES_OPENCODE_GO_API_KEY=  # clave del proveedor de modelos que usa Hermes

# OpenCode (agente de código)
OPENCODE_GO_API_KEY=         # clave del proveedor de modelos que usa OpenCode
```

Riesgo residual asumido: las variables de entorno son legibles con
`docker inspect hermes`, `docker inspect opencode` y en `/proc/1/environ`.
Materializarlas como archivos (`/run/secrets`) requiere envolver los
entrypoints de las imágenes vendorizadas, así que quedó fuera de alcance.

## Operación: agregar un dominio

1. Editá `squid/allowlist.txt`. Un dominio por línea; el punto inicial incluye
   el dominio y todos sus subdominios (`.github.com` cubre `api.github.com`).
2. Recargá la política:

   ```bash
   docker compose restart egress-proxy
   ```

3. Verificá que quedó bien formada (falla si hay un ACL inválido):

   ```bash
   docker compose run --rm --no-deps --entrypoint /usr/sbin/squid \
     egress-proxy -f /etc/squid/squid.conf -k parse
   ```

4. Antes de agregar un destino, preguntate si ese servicio necesita ver el
   tráfico de los agentes. Si la respuesta es "no sé", no lo agregues.

## Verificación del aislamiento

Desde la red de los agentes, con un contenedor efímero:

```bash
# 1. Sin salida directa (debe fallar la resolución / la conexión)
docker run --rm --network agents curlimages/curl -m 8 https://example.com/
#    curl: (6) Could not resolve host: example.com

# 2. Destino permitido a través del proxy
docker run --rm --network agents curlimages/curl \
  -x http://egress-proxy:3128 -o /dev/null -w '%{http_code}\n' https://api.telegram.org/
#    302

# 3. Destino no listado (denegado)
docker run --rm --network agents curlimages/curl \
  -x http://egress-proxy:3128 https://example.com/
#    curl: (7) CONNECT tunnel failed, response 403

# 4. Metadata de cloud (denegada)
docker run --rm --network agents curlimages/curl \
  -x http://egress-proxy:3128 -o /dev/null -w '%{http_code}\n' http://169.254.169.254/
#    403

# 5. Auditoría del proxy, sin URLs
docker logs egress-proxy | grep client=
#    1789688743.014 client=172.20.0.3 method=CONNECT squid=TCP_TUNNEL http=200
#    1789688743.564 client=172.20.0.3 method=CONNECT squid=TCP_DENIED http=403
```

## Puntos de atención

- **Transporte de Telegram.** `HTTP(S)_PROXY` lo respetan los clientes HTTP
  (Bot API sobre HTTPS, `curl`, `git`, npm, pip). Un cliente que resuelva el
  destino por su cuenta y abra un socket directo — típicamente MTProto
  (Telethon) o el `fetch` de Node — **no** usa el proxy y va a fallar. Si
  Hermes no arranca su gateway, ese es el primer lugar donde mirar: la salida
  correcta es resolverlo dentro del proxy o aceptar una excepción explícita,
  no devolverle una red con Internet al contenedor.
- **IP del proveedor de modelos.** `squid/allowlist.txt` tiene un `TODO` para
  el host de OpenCode Go: hasta completarlo, OpenCode no alcanza su API
  (falla cerrado, por diseño).
- **Nombres de red.** La red con salida se llama `egress` (antes
  `agent_internet`). Si quedó la vieja, se limpia con
  `docker network rm agent_internet`.

## Fuera de alcance (siguientes pasos)

- Docker rootless o `userns-remap` a nivel daemon: aislamiento real entre
  contenedor y host, no se resuelve desde `compose.yml`.
- Secretos como archivos en `/run/secrets` (requiere entrypoint propio).
- `read_only: true` en los agentes y ejecución como usuario no-root: hoy
  quedan con rootfs escribible y root dentro del contenedor, acotado por
  `cap_drop: [ALL]` y `no-new-privileges`. Es el próximo escalón más barato.
- Perfil `seccomp` propio y `apparmor`: se usa el default de Docker, que ya
  bloquea las syscalls peligrosas más comunes.
