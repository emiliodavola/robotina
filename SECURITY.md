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

## Puesta en marcha: quién puede hablarle al agente

El bot escucha por polling, así que el control de acceso **no** es la red: es
la allowlist de usuarios. Con `TELEGRAM_ALLOWED_USERS` vacío, Hermes le manda un
**código de pairing** a cualquier DM desconocido y lo rechaza hasta aprobarlo.
Ese aprobado se hace normalmente desde el dashboard (puerto 9119) —que acá
**no está publicado a propósito**— así que el camino sin fricción es declararlo
de antemano:

1. Pedile tu ID numérico a `@userinfobot` en Telegram (desde tu cliente, no
desde el contenedor).
2. Agregá a `.env`: `TELEGRAM_ALLOWED_USERS=123456789` (varios, separados por
   coma).
3. `docker compose up -d hermes`

Para comprobar cómo quedó el agente: `docker compose exec hermes hermes status`.
El proveedor de modelos debe aparecer resuelto (con `OPENCODE_GO_API_KEY`
resuelve a `OpenCode Go`, base `https://opencode.ai/zen/go/v1`, ya permitida por
la allowlist).

Si en algún momento querés aprobar pairings desde el dashboard, **no** publiques
el puerto en `0.0.0.0`: mapeá `127.0.0.1:9119:9119` únicamente. El dashboard
tiene control total sobre el agente; publicarlo en la LAN o en Internet es
regalarle el agente a quien alcance ese puerto.

## Modelo y plan del proveedor

El modelo default **no** vive en este repo: está en `/opt/data/config.yaml`,
dentro del volumen `hermes_data`. `HERMES_MODEL` no alcanza para cambiarlo, por
que la config del archivo tiene precedencia sobre la variable (ver
`hermes_cli/config.py`: *a truthy configured model wins over HERMES_MODEL*).

`OPENCODE_GO_API_KEY` resuelve al perfil `opencode-go`, cuyo relay sirve
**únicamente modelos abiertos**. Un id que no esté en ese catálogo devuelve:

```text
HTTP 401: Model <id> is not supported
provider=opencode-go base_url=https://opencode.ai/zen/go/v1
```

Hermes lo marca como no reintentable y no hay reintento que lo arregle: hay que
cambiar el id. El catálogo real del plan se consulta en
`https://opencode.ai/zen/go/v1/models` con `Authorization: Bearer
$OPENCODE_GO_API_KEY` y, importante, con el **User-Agent de Hermes**
(`HermesAgent/<version>`): sin ese UA, Cloudflare responde
`403 error code: 1010` y parece un problema de credenciales cuando no lo es.

Para cambiar de modelo (los ids son los del catálogo, sin prefijo):

```bash
# backup una sola vez
cp -n /opt/data/config.yaml /opt/data/config.yaml.bak
docker compose exec -T hermes \
  sed -i 's|^  default: .*|  default: kimi-k2.7-code|' /opt/data/config.yaml
docker compose restart hermes
docker compose exec hermes hermes status   # debe mostrar Model y Provider
```

Dejá `provider:` explícito (`opencode-go`) en vez de `auto`: con `auto` el
agente adivina entre proveedores logueados y los errores se vuelven
indescifrables. Si el modelo elegido no contesta, mirá
`docker compose exec hermes hermes logs errors`.

Nota de datos en reposo: cada llamada fallida deja un dump completo del request
(prompt + contexto) en `/opt/data/sessions/request_dump_*.json`, dentro del
volumen. Si el agente va a manejar datos sensibles, conviene limpiarlos y
decidir qué tier de modelo corresponde.

## Interoperación Hermes <-> OpenCode

Son **dos contenedores separados** que se hablan por **red**, no dos procesos en el
mismo contenedor. Verificado:

```text
/hermes   ip=172.19.0.3 pid_host=69678
/opencode ip=172.19.0.2 pid_host=69619
hermes: command -v opencode -> NO EXISTE
unico volumen compartido: /workspace
```

| Pieza | Cómo está |
| --- | --- |
| Servicio | `opencode serve --hostname 0.0.0.0 --port 4096` (headless, sin TUI ni TTY) |
| Alcance | Solo la red `agents`. El puerto **no** se publica: no lo alcanza el host ni la LAN. |
| Dirección del flujo | Hermes llama a `http://opencode:4096`. Al revés no hace falta. |
| Credenciales | Ninguna por defecto. Con `OPENCODE_SERVER_PASSWORD` en `.env`, el servidor exige HTTP Basic (usuario `opencode`) y Hermes lo manda desde su entorno. |
| Conocimiento | Skill `opencode-server` en `hermes/skills/`, montada **read-only**: el agente no puede reescribir sus propias instrucciones. |
| Egreso | Sin cambios: opencode no tiene ruta propia. Su llamada al modelo aparece como `models.opencode.ai TCP_TUNNEL` en el log del proxy. |

### Por qué conviene poner el password

`egress-proxy` es el único otro miembro de la red `agents`. Si alguien compromete
ese contenedor, sin password puede manejar a opencode — es decir, ejecutar código
en `/workspace`. Es un salto de privilegio real, y se cierra con una línea:

```ini
# .env
OPENCODE_SERVER_PASSWORD=<algo largo y random>
```

```bash
docker compose up -d opencode hermes
```

Verificado: con el password puesto, `sin credencial -> 401`, `con credencial -> 200`,
y la receta de la skill funciona sin cambios. Por defecto queda vacío, y el server
avisa `server is unsecured` en su log: si ves ese warning, sabés que falta.

### Trampa de red que te va a morder si no la sabés

Las llamadas internas **deben usar el nombre de servicio** (`opencode`). Cualquier
host interno que no esté en `NO_PROXY` sale por el proxy y el proxy lo deniega:
síntoma `403` con una página HTML de Squid, que parece un problema de permisos de
opencode y no lo es. Si algún día renombrás el servicio, actualizá `NO_PROXY`.

### Modelos que opencode puede usar

Solo tiene autenticado el tier **free** de `opencode/*` (`mimo-v2.5-free`,
`nemotron-3-ultra-free`, `muse-spark-1.3-contributor-free`, …). Son gratis y
suficientes para probar el circuito; para que use el plan Go hay que autenticarlo
aparte (`opencode auth`, interactivo). El listado real está siempre en
`GET http://opencode:4096/config/providers`.

Nota: la skill que Hermes trae de fábrica (`opencode`) asume que el **CLI** está
instalado en su propio contenedor: por eso el agente contestaba "no lo tengo
instalado". La skill de este stack (`opencode-server`) es la que aplica.

## Puntos de atención

- **Hermes intenta descubrir IPs de Telegram por DNS-over-HTTPS.** Al conectar
  pide `dns.google` y `cloudflare-dns.com`; el proxy los deniega y la conexión
  igual se establece contra `api.telegram.org`. Dejalo bloqueado: habilitar esos
  dos hosts reabre un canal de DNS paralelo que esquiva la allowlist por
  dominio.
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
