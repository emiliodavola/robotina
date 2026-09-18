# Modelo de seguridad del stack

Este stack corre **dos agentes autónomos con capacidad de ejecutar código**
(Hermes gateway y OpenCode) sobre un workspace compartido. El objetivo del
diseño no es "que no pase nada" sino **acotar el daño**: si un agente es
inducido a actuar en contra de tus intereses, no tiene ruta para exfiltrar
datos ni para moverse lateralmente.

Todo lo que dice este documento sobre las imágenes fue **verificado
ejecutándolas**, no inferido de la documentación. Donde una afirmación es una
suposición, está marcada como tal.

## Garantías

| Garantía | Cómo se implementa |
| --- | --- |
| Sin ruta directa a Internet para los agentes | `hermes` y `opencode` están **solo** en la red `agents` (`internal: true`). Esa red no tiene gateway: no hay salida ni resolución externa de nombres. |
| Egreso mediado y con allowlist | El único contenedor con salida es `egress-proxy` (Squid). Solo pasa lo que figura en `squid/allowlist.txt`; el resto se deniega con `403` y queda en el log del proxy. |
| Nada entra desde el host o la LAN | Ningún servicio publica puertos. El bot de Telegram funciona por polling saliente. |
| Sin pivotaje hacia la red interna o metadata de cloud | Squid deniega rangos privados (`10/8`, `172.16/12`, `192.168/16`, `127/8`, `169.254/16`, `fc00::/7`, …) antes de evaluar la allowlist. |
| Sin escalada de privilegios | `no-new-privileges` y `ulimits.core: 0` en los tres. `cap_drop: [ALL]`: entero en `egress-proxy` y en `opencode`; en `hermes` con el mínimo readmitido (ver abajo). |
| Sin socket de Docker | Nunca se monta `/var/run/docker.sock`. |
| Proxy inmutable | `egress-proxy` corre como usuario `proxy` (uid 13) con rootfs de solo lectura y `/var/log`, `/var/spool`, `/run`, `/tmp` en tmpfs. Verificado: `touch /usr/sbin/evil` → *Read-only file system*. |
| Blast radius acotado | Límites de CPU, memoria y PIDs por contenedor; logs `json-file` con rotación (10 MB × 3). |
| Auditoría sin secretos | El formato de log registra timestamp, IP de origen, **dominio**, método y estado — nunca la URL completa, porque el token del bot viaja en la ruta (`/bot<token>/...`). |

## Compatibilidad verificada con las imágenes

Ejecutando las imágenes reales aparecieron tres cosas que hay que respetar. Las
tres están ya aplicadas en `compose.yml`.

**1. Hermes exige ser PID 1.** Corre s6-overlay y su entrypoint hace
`exec /init` solo si `$$ -eq 1`. Con `init: true` (el `tini` de Docker como
PID 1) degrada y pierde el árbol de supervisión:

```text
[hermes] WARNING: container entrypoint is not PID 1; skipping s6-overlay /init
and falling back to direct bootstrap. Supervised services are unavailable...
```

Por eso `hermes` **no** lleva `init: true`. `opencode` sí lo lleva: es un
binario único, no necesita PID 1.

**2. Hermes necesita cinco capabilities.** Corre como root y baja privilegios
con `s6-setuidgid hermes`, además de ajustar el dueño del volumen. Con
`cap_drop: [ALL]` el arranque muere:

```text
s6-applyuidgid: fatal: unable to set supplementary group list: Operation not permitted
```

De ahí `cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID]` en `hermes` y
en ningún otro servicio. Con eso, s6 arranca completo (preinit → `s6-rc` →
`cont-init` → stage2). `opencode` verificado con `cap_drop: [ALL]` puro:
responde `1.18.31` sin quejarse.

**3. Hermes no acepta `user:` arbitrario.** La imagen aborta a propósito si la
arrancás con un UID que no sea root ni `hermes`:

```text
[hermes] ERROR: container started with --user 1000 (an arbitrary, non-hermes UID) — not supported.
```

Para que los archivos queden con tu UID del host, la vía soportada es mantener
root en el arranque y pasar `HERMES_UID` / `HERMES_GID` (o `PUID`/`PGID`). No
uses `user:` en ese servicio.

## El transporte de Telegram sí pasa por el proxy

Verificado, no supuesto: la imagen trae `python-telegram-bot 22.8`, que usa la
**Bot API sobre HTTPS** (`api.telegram.org`), no MTProto. Su
`HTTPXRequest` construye `httpx.AsyncClient(proxy=None, ...)`, y httpx con
`trust_env=True` lee `HTTPS_PROXY` del entorno. En la corrida real el proxy
registró los túneles:

```text
domain=raw.githubusercontent.com      method=CONNECT squid=TCP_TUNNEL http=200
domain=openrouter.ai                  method=CONNECT squid=TCP_DENIED http=403
domain=hermes-agent.nousresearch.com  method=CONNECT squid=TCP_DENIED http=403
domain=portal.nousresearch.com        method=CONNECT squid=TCP_DENIED http=403
```

Los tres denegados son pedidos de arranque (catálogo de modelos, portal de
Nous, canal de update). Bloquearlos **no degrada** a Hermes: completa su
bootstrap, sincroniza sus 58 skills incluidas y no reporta errores. Quedan
listados y comentados en la allowlist para que los habilites solo si los
necesitás.

Lo que **no** está verificado todavía: una llamada real al proveedor de
modelos. Requiere una clave con crédito. Lo único que se puede afirmar es que
`.opencode.ai` está habilitado en la allowlist por evidencia del código de la
imagen, no por una respuesta 200 observada.

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
2. Aplicá el cambio:

   ```bash
   docker compose up -d --force-recreate egress-proxy
   ```

3. Verificá que la política quedó bien formada (falla si hay un ACL inválido):

   ```bash
   docker compose run --rm --no-deps --entrypoint /usr/sbin/squid \
     egress-proxy -f /etc/squid/squid.conf -k parse
   ```

4. Para descubrir **qué** está rebotando, mirá el log del proxy: registra el
   dominio sin la URL.

   ```bash
   docker logs egress-proxy | grep -v '127.0.0.1' | grep 'client='
   ```

5. Antes de agregar un destino, preguntate si ese servicio necesita ver el
   tráfico de los agentes. Si la respuesta es "no sé", no lo agregues.

## Verificación del aislamiento

Desde la red de los agentes, con un contenedor efímero:

```bash
# 1. Sin salida directa (no resuelve ni conecta)
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
```

## Puntos de atención

- **Un cliente que ignore `HTTP(S)_PROXY` falla, no evade.** Si resuelve el
  nombre por su cuenta y abre un socket directo, se choca con que la red
  `agents` no tiene ruta ni DNS externo. Para Hermes eso quedó descartado por
  evidencia; si en el futuro agregás otro agente, verificá su cliente HTTP
  antes de asumir que el proxy lo cubre.
- **El DNS externo está cerrado por accidente del entorno, no por
  configuración.** Desde `agents` no resuelven `example.com`, `github.com` ni
  `pypi.org`. Es deseable, pero es una propiedad observada: si cambiás de
  daemon de Docker o de resolutor del host, volvé a medirlo.
- **`/opt/data/config.yaml` de Hermes es viejo.** El bootstrap avisa:
  *"This config predates version 12 (~2 years old) and can no longer be
  auto-migrated"*, y sugiere `hermes setup`. Es un tema de mantenimiento, no de
  seguridad, pero conviene resolverlo antes de usar el gateway en serio.
- **Nombres de red.** La red con salida se llama `egress` (antes
  `agent_internet`). Si quedó la vieja: `docker network rm agent_internet`.

## Fuera de alcance (siguientes pasos)

- Docker rootless o `userns-remap` a nivel daemon: aislamiento real entre
  contenedor y host, no se resuelve desde `compose.yml`.
- Secretos como archivos en `/run/secrets` (requiere entrypoint propio).
- `read_only: true` en los agentes: `opencode` probablemente lo tolere;
  `hermes` escribe durante el arranque (config, skills, ledger) y necesita más
  análisis antes de intentarlo.
- Perfil `seccomp` propio y `apparmor`: se usa el default de Docker, que ya
  bloquea las syscalls peligrosas más comunes.
