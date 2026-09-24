# Modelo de seguridad del stack

Este stack corre **un agente autónomo con capacidad de ejecutar código** dentro de un único
contenedor `robotina`: Hermes (gateway de Telegram) y `opencode serve` (servidor HTTP en
loopback) conviven como servicios supervisados por s6 sobre un workspace compartido. Aparte,
sin fusionar, corre `egress-proxy` (Squid). El objetivo del diseño no es "que no pase nada"
sino **acotar el daño**: si un agente es inducido a actuar en contra de tus intereses, no
tiene ruta para exfiltrar datos ni para moverse lateralmente.

Todo lo que dice este documento sobre las imágenes fue **verificado ejecutándolas**, no
inferido de la documentación. Donde una afirmación es una suposición, está marcada como tal.

## Garantías

| Garantía | Cómo se implementa |
| --- | --- |
| Sin ruta directa a Internet para el agente | `robotina` está **solo** en la red `agents` (`internal: true`). Esa red no tiene gateway: no hay salida ni resolución externa de nombres. |
| Egreso mediado y con allowlist | El único contenedor con salida es `egress-proxy` (Squid). Solo pasa lo que figura en `squid/allowlist.txt`; el resto se deniega con `403` y queda en el log del proxy. La allowlist acota el **destino**, no el contenido: ver «Puntos de atención». |
| Nada entra desde el host o la LAN | Ningún servicio publica puertos. El bot de Telegram funciona por polling saliente y el servidor de OpenCode escucha solo en `127.0.0.1`. |
| Sin pivotaje hacia la red interna o metadata de cloud | Squid deniega rangos privados (`10/8`, `172.16/12`, `192.168/16`, `127/8`, `169.254/16`, `fc00::/7`, …) antes de evaluar la allowlist. |
| Sin escalada de privilegios | `no-new-privileges` y `ulimits.core: 0`. `cap_drop: [ALL]`: entero en `egress-proxy`; en `robotina` con el mínimo readmitido para que arranque s6 como PID 1 (ver abajo). |
| Sin socket de Docker | Nunca se monta `/var/run/docker.sock`. |
| Proxy inmutable | `egress-proxy` corre como usuario `proxy` (uid 13) con rootfs de solo lectura y `/var/log`, `/var/spool`, `/run`, `/tmp` en tmpfs. Verificado: `touch /usr/sbin/evil` → *Read-only file system*. |
| Blast radius acotado | Un único cgroup con límites de CPU, memoria y PIDs; logs `json-file` con rotación (10 MB × 3). |
| Auditoría sin secretos | El formato de log registra timestamp, IP de origen, **dominio**, método y estado — nunca la URL completa, porque el token del bot viaja en la ruta (`/bot<token>/...`). |

## Compatibilidad verificada con la imagen

Ejecutando la imagen real aparecieron tres cosas que hay que respetar. Las tres están ya
aplicadas en `compose.yml`.

**1. El entrypoint de la imagen exige ser PID 1.** El contenedor corre s6-overlay y su
entrypoint hace `exec /init` solo si `$$ -eq 1`. Con `init: true` (el `tini` de Docker como
PID 1) degrada y pierde el árbol de supervisión:

```text
WARNING: container entrypoint is not PID 1; skipping s6-overlay /init
and falling back to direct bootstrap. Supervised services are unavailable...
```

Por eso `robotina` **no** lleva `init: true`: PID 1 debe ser la cadena de entrada de la
imagen para que s6 supervise los servicios. `docker compose exec robotina sh -c
'tr "\0" " " < /proc/1/cmdline'` debe mostrar la cadena de s6 y **no** `tini`/`docker-init`.

**2. s6 necesita seis capabilities.** El contenedor arranca como root y baja privilegios
con `s6-setuidgid hermes`, además de ajustar el dueño del volumen y de poder señalar a sus
hijos de uid 10000 para bajarlos. Con `cap_drop: [ALL]` a secas el arranque muere:

```text
s6-applyuidgid: fatal: unable to set supplementary group list: Operation not permitted
```

De ahí `cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, KILL]`, que da una máscara de
bounding set `0xeb`. Las cinco primeras hacen que s6 arranque completo (preinit → `s6-rc` →
`cont-init` → stage2); `KILL` se agregó después de medir que, sin ella, un apagado iniciado
adentro del contenedor se traba (ver «Apagado y ciclo de vida», más abajo). El proceso
`opencode serve` (uid 10000) **no** conserva ninguna: medido en el contenedor que corre,
`CapEff=0x0`, `CapPrm=0x0`, `CapAmb=0x0`, `CapBnd=0xeb`, `NoNewPrivs: 1`. No puede ganar
`KILL` ni ninguna otra capability, así que readmitirla en el contenedor no amplía lo que el
agente puede hacer.

**3. La imagen no acepta `user:` arbitrario.** Aborta a propósito si la arrancás con un UID
que no sea root ni `hermes`:

```text
ERROR: container started with --user 1000 (an arbitrary, non-hermes UID) — not supported.
```

Para que los archivos queden con tu UID del host, la vía soportada es mantener root en el
arranque y pasar `HERMES_UID` / `HERMES_GID` (o `PUID`/`PGID`). No uses `user:`.

## Apagado y ciclo de vida (medido)

El contenedor tiene **un solo ciclo de vida**, y su PID 1 es el **árbol de supervisión de s6**,
no Hermes. Medido en el contenedor que corre:

- `hermes gateway run` es el servicio **`gateway-default`** de s6 (`s6-supervise gateway-default`).
  Si el gateway muere, s6 lo **reinicia en el lugar**: el pid del gateway cambia y el contenedor
  sigue arriba, con `RestartCount` y `StartedAt` **sin cambios**. El propio gateway lo confirma
  en su log: `gateway is now running under s6 supervision (auto-restart on crash …)`.
- El contenedor **sale cuando baja el árbol de supervisión** (un `docker compose stop robotina`,
  o un `kill` de PID 1), y `restart: unless-stopped` vuelve a levantar la unidad completa.
- El apagado es **ordenado**: con `KILL` en el capability set, `docker compose stop robotina`
  termina en **5.50 s** (muy adentro de los `stop_grace_period: 20s`), con `ExitCode=0` y **sin**
  `SIGKILL` de Docker. El log muestra el árbol bajando servicio por servicio
  (`opencode-ready` → `opencode` → `main-hermes` → `dashboard` → `engram` → `opencode-init` →
  `legacy-cont-init` → `fix-attrs`, todos `successfully stopped`) y el gateway recibiendo
  `SIGTERM`.

Antes de agregar `KILL`, ese mismo apagado **se trababa**: los supervisores root no podían
señalar a los servicios de uid 10000, `s6-rc` nunca terminaba de bajar el árbol, PID 1 no salía
y Docker terminaba mandando `SIGKILL` pasado el grace period. Ese es el motivo de la sexta
capability.

## El transporte de Telegram sí pasa por el proxy

Verificado, no supuesto: la imagen trae `python-telegram-bot`, que usa la **Bot API sobre
HTTPS** (`api.telegram.org`), no MTProto. Su `HTTPXRequest` construye
`httpx.AsyncClient(proxy=None, ...)`, y httpx con `trust_env=True` lee `HTTPS_PROXY` del
entorno. En la corrida real el proxy registró los túneles:

```text
domain=raw.githubusercontent.com      method=CONNECT squid=TCP_TUNNEL http=200
domain=openrouter.ai                  method=CONNECT squid=TCP_DENIED http=403
domain=hermes-agent.nousresearch.com  method=CONNECT squid=TCP_DENIED http=403
domain=portal.nousresearch.com        method=CONNECT squid=TCP_DENIED http=403
```

Los tres denegados son pedidos de arranque (catálogo de modelos, portal de Nous, canal de
update). Bloquearlos **no degrada** al gateway: completa su bootstrap, sincroniza sus skills
incluidas y no reporta errores. Quedan listados y comentados en la allowlist para que los
habilites solo si los necesitás.

La llamada real al proveedor de modelos quedó **verificada después**, con el log del proxy:
aparece como túnel autorizado, no como denegación.

```text
domain=models.opencode.ai  method=CONNECT squid=TCP_TUNNEL http=200
```

`.opencode.ai` fue la única entrada de la allowlist habilitada por evidencia del código de la
imagen antes de tener esa observación.

## Variables de entorno

`compose.yml` interpola estas variables desde un `.env` **externo y no versionado**;
`.env.example` trae los nombres, sin valores. Cuatro son **obligatorias**: compose aborta con
un mensaje explícito si faltan, en vez de arrancar con claves vacías (`${VAR:?…}`). Las demás
tienen default vacío (`${VAR:-}`).

```ini
# Obligatorias
HOST_DATA_DIR=               # carpeta del host donde vive todo el estado
ROBOTINA_TELEGRAM_BOT_TOKEN= # token emitido por @BotFather
ROBOTINA_HERMES_MODEL_KEY=   # clave del proveedor que usa Hermes
ROBOTINA_OPENCODE_MODEL_KEY= # clave del proveedor que usa OpenCode

# Opcionales
ROBOTINA_TELEGRAM_ALLOWED_USERS=   # allowlist de usuarios de Telegram (ver abajo)
ROBOTINA_OPENCODE_SERVER_PASSWORD= # HTTP Basic del server de opencode (defensa en profundidad)
ROBOTINA_GITHUB_TOKEN=             # PAT fine-grained; ver «Autenticación de GitHub»

# Modelo de Hermes (no son secretos; ver «Modelo y plan del proveedor»)
ROBOTINA_HERMES_MODEL_PROVIDER=    # proveedor (default opencode-go)
ROBOTINA_HERMES_MODEL_BASE_URL=    # endpoint  (default https://opencode.ai/zen/go/v1)
ROBOTINA_HERMES_MODEL=             # id del modelo (default deepseek-v4.1-flash)
```

Las dos claves del proveedor entran al contenedor bajo **nombres distintos**. Hermes recibe la
suya con el nombre exacto que espera la imagen vendor (`OPENCODE_GO_API_KEY`); `opencode serve`
recibe la suya con un nombre propio (`ROBOTINA_OPENCODE_GO_API_KEY`) y su `run` de s6 la
exporta como `OPENCODE_GO_API_KEY` **solo para su proceso**. En el `.env`, en cambio, ambas van
namespaced (`ROBOTINA_HERMES_MODEL_KEY` y `ROBOTINA_OPENCODE_MODEL_KEY`) por la trampa de
shadowing de abajo. El resultado observable es que **cada proceso queda configurado únicamente
con su propia clave** (ver «Columnas de la fusión»).

**Trampa documentada: el entorno del proceso pisa al `.env`.** Docker Compose le da
precedencia al entorno del proceso por sobre el archivo `.env`. Un input que se llame igual que
una variable del vendor o del ambiente del host puede quedar **shadowed en silencio** por un
valor exportado viejo: pasó exactamente con `OPENCODE_GO_API_KEY`, que era el nombre del input
en `.env` y a la vez el nombre propio del vendor. Con esa variable exportada en el shell, el
contenedor recibió una credencial vieja en lugar de la del `.env`. Por eso **todos** los inputs
de `.env` llevan prefijo `ROBOTINA_`, que no existe en el entorno del host: la colisión deja de
ser posible. Corolario: no exportes estas variables en el shell; editá el `.env` y recreá el
contenedor.

Ojo al inspeccionar: la validación estática resuelve y **imprime los valores** del `.env` si se
corre sin filtro. La forma correcta y única admitida es con `-q`; el resto de las recetas de
este documento usan `docker inspect` con un `--format` acotado que excluye `.Config.Env`.

Riesgo residual asumido: las variables de entorno son legibles con
`docker inspect robotina` (con `--format` acotado) y en `/proc/1/environ`. Materializarlas como
archivos (`/run/secrets`) requiere envolver el entrypoint de la imagen vendorizada, así que
quedó fuera de alcance.

## Operación: agregar un dominio

1. Editá `squid/allowlist.txt`. Un dominio por línea; el punto inicial incluye el dominio y
   todos sus subdominios (`.github.com` cubre `api.github.com`).
2. Aplicá el cambio:

   ```bash
   docker compose up -d --force-recreate egress-proxy
   ```

3. Verificá que la política quedó bien formada (falla si hay un ACL inválido):

   ```bash
   docker compose run --rm --no-deps --entrypoint /usr/sbin/squid \
     egress-proxy -f /etc/squid/squid.conf -k parse
   ```

   Corrélo desde PowerShell. En Git Bash/MSYS las rutas absolutas se reescriben (aparece un
   `C:/Program Files/Git/usr/sbin/squid` que no existe, y parece una política rota cuando en
   realidad es el shell) y hay que anteponer `MSYS_NO_PATHCONV=1`.

4. Para descubrir **qué** está rebotando, mirá el log del proxy: registra el dominio sin la
   URL.

   ```bash
   docker logs egress-proxy | grep -v '127.0.0.1' | grep 'client='
   ```

5. Antes de agregar un destino, preguntate si ese servicio necesita ver el tráfico del
   agente. Si la respuesta es "no sé", no lo agregues.

## Verificación del aislamiento

Desde la red del agente, con un contenedor efímero:

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

El bot escucha por polling, así que el control de acceso **no** es la red: es la allowlist de
usuarios. Con `TELEGRAM_ALLOWED_USERS` vacío, Hermes le manda un **código de pairing** a
cualquier DM desconocido y lo rechaza hasta aprobarlo. Ese aprobado se hace normalmente desde
el dashboard (puerto 9119) —que acá **no está publicado a propósito**— así que el camino sin
fricción es declararlo de antemano:

1. Pedile tu ID numérico a `@userinfobot` en Telegram (desde tu cliente, no desde el
   contenedor).
2. Agregá a `.env`: `TELEGRAM_ALLOWED_USERS=123456789` (varios, separados por coma).
3. `docker compose up -d robotina`

Para comprobar cómo quedó el agente:

```bash
docker compose exec robotina hermes status
```

El proveedor de modelos debe aparecer resuelto (con `OPENCODE_GO_API_KEY` resuelve a
`OpenCode Go`, base `https://opencode.ai/zen/go/v1`, ya permitida por la allowlist).

Si en algún momento querés aprobar pairings desde el dashboard, **no** publiques el puerto en
`0.0.0.0`: mapeá `127.0.0.1:9119:9119` únicamente. El dashboard tiene control total sobre el
agente; publicarlo en la LAN o en Internet es regalarle el agente a quien alcance ese puerto.

## Modelo y plan del proveedor

El modelo default **no** vive en este repo: está en `/opt/data/config.yaml`, dentro del bind
de Hermes. `HERMES_MODEL` no alcanza para cambiarlo, porque la config del archivo tiene
precedencia sobre la variable (ver `hermes_cli/config.py`: *a truthy configured model wins over
HERMES_MODEL*).

`OPENCODE_GO_API_KEY` resuelve al perfil `opencode-go`, cuyo relay sirve **únicamente modelos
abiertos**. Un id que no esté en ese catálogo devuelve:

```text
HTTP 401: Model <id> is not supported
provider=opencode-go base_url=https://opencode.ai/zen/go/v1
```

Hermes lo marca como no reintentable y no hay reintento que lo arregle: hay que cambiar el id.
El catálogo real del plan se consulta en `https://opencode.ai/zen/go/v1/models` con
`Authorization: Bearer $OPENCODE_GO_API_KEY` y, importante, con el **User-Agent de Hermes**
(`HermesAgent/<version>`): sin ese UA, Cloudflare responde `403 error code: 1010` y parece un
problema de credenciales cuando no lo es.

Para cambiar de modelo (los ids son los del catálogo, sin prefijo):

```bash
# backup una sola vez
cp -n /opt/data/config.yaml /opt/data/config.yaml.bak
docker compose exec -T robotina \
  sed -i 's|^  default: .*|  default: kimi-k2.7-code|' /opt/data/config.yaml
docker compose restart robotina
docker compose exec robotina hermes status   # debe mostrar Model y Provider
```

Dejá `provider:` explícito (`opencode-go`) en vez de `auto`: con `auto` el agente adivina entre
proveedores logueados y los errores se vuelven indescifrables. Si el modelo elegido no
contesta, mirá `docker compose exec robotina hermes logs errors`.

Nota de datos en reposo: cada llamada fallida deja un dump completo del request (prompt +
contexto) en `/opt/data/sessions/request_dump_*.json`, dentro del bind. Si el agente va a
manejar datos sensibles, conviene limpiarlos y decidir qué tier de modelo corresponde.

## Columnas de la fusión: qué cambió al pasar a un contenedor

Antes el gateway y el servidor de OpenCode vivían en contenedores separados y se hablaban
por red. Ahora ambos corren en un solo contenedor `robotina`, y eso cambia cuatro fronteras que
conviene tener explícitas.

### R1 — El invariante «Hermes no tiene credencial de GitHub» quedó retirado

En el layout anterior el PAT vivía solo en el contenedor de OpenCode y Hermes delegaba. Con un
único contenedor esa separación ya no existe: **`GITHUB_TOKEN` está presente y es alcanzable
por todo el contenedor**, incluido el agente que atiende Telegram. El PAT se **mantiene tal
como está** (no hay trabajo de acotado de token en este cambio).

Consecuencia asumida, escrita sin eufemismos: una **inyección de prompt** en el bot de Telegram
puede llegar a GitHub con el PAT vigente — leer repos permitidos, escribir donde el PAT lo
permita y publicar contenido. La mitigación es el alcance del PAT (fine-grained, repos justos,
permisos mínimos), no la frontera entre procesos.

### R2 — La aislación de claves por proceso no es exigible

Los dos procesos corren con el **mismo uid** (10000) dentro del mismo contenedor. A igual uid
**no se puede aislar** una variable de entorno de otro proceso que ya tiene acceso al mismo
`/proc` y al mismo filesystem: cualquier proceso del contenedor puede leer el entorno o los
archivos del otro. La garantía que este stack sí da es más débil y hay que decirla con
precisión:

> cada proceso queda **configurado** únicamente con su propia clave.

Es decir: el wiring de `compose.yml` y los `run` de s6 hacen que cada proceso *vea* solo su
clave en su propio entorno, y esa configuración se verifica con hashes. Lo que **no** se
promete es que un proceso no pueda leer la clave del otro si se lo propone. No afirmes lo
segundo: no es cierto a igual uid.

### R3 — Las capabilities son del contenedor, no del proceso (medido)

`cap_drop: [ALL]` con `cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, KILL]` es una
propiedad **del contenedor**: el *bounding set* del cgroup es lo que hereda cada proceso, y no hay
forma de darle a un proceso un conjunto de capabilities distinto al de otro dentro del mismo
contenedor. Lo que sí se midió es que el proceso de la app (uid 10000) **no conserva ninguna**:

| Proceso | `CapInh` | `CapPrm` | `CapEff` | `CapBnd` | `CapAmb` | `NoNewPrivs` |
| --- | --- | --- | --- | --- | --- | --- |
| PID 1 (`s6-svscan`, uid 0) | `0x0` | `0xeb` | `0xeb` | `0xeb` | `0x0` | 1 |
| `opencode serve` (uid 10000) | `0x0` | `0x0` | `0x0` | `0xeb` | `0x0` | 1 |

Decodificación de los seis bits de `0xeb` = 235 = `0b11101011`:

| Bit | Valor | Capability |
| --- | --- | --- |
| 0 | 1 | `CAP_CHOWN` |
| 1 | 2 | `CAP_DAC_OVERRIDE` |
| 3 | 8 | `CAP_FOWNER` |
| 5 | 32 | `CAP_KILL` |
| 6 | 64 | `CAP_SETGID` |
| 7 | 128 | `CAP_SETUID` |

`CAP_KILL` es la sexta y la agregó el apply (slice 10) para que los supervisores root puedan
señalar a sus hijos de uid 10000: sin ella, un apagado iniciado adentro del contenedor se trababa.
El proceso de la app **no** puede ganarla — su `CapEff` es `0x0` y `NoNewPrivs: 1` impide que la
recupere por `exec` de un binario con *file capabilities*. Es decir: readmitir `KILL` en el
contenedor no amplía lo que el agente puede hacer. Lo que **no** se promete es que el agente corra
con un conjunto de capabilities *distinto* al del resto del contenedor; eso es imposible con un
único bounding set.

### R4 — Ciclo de vida único

El contenedor tiene **un solo ciclo de vida**, compartido por todos los procesos de adentro.
PID 1 es el **árbol de supervisión de s6** (no Hermes); `opencode`, `engram` y el propio gateway
(`gateway-default`) son servicios supervisados por s6. A nivel **servicio** la recuperación es
independiente: si un servicio muere, s6 lo reinicia en el lugar y los demás siguen. A nivel
**contenedor**, en cambio, no hay dos dominios de falla: todo lo que baja PID 1 —un
`docker compose stop`, un `kill` de PID 1, el agotamiento del cgroup compartido (R5) o un reset
del daemon— se lleva a todos los procesos juntos y los vuelve a levantar juntos
(`restart: unless-stopped`).

La afirmación original de esta sección —«si el programa principal de Hermes muere, el
contenedor se reinicia y se lleva a opencode y engram»— **era falsa y quedó corregida por
medición**: `hermes gateway run` es el servicio s6 `gateway-default`, así que un crash del
gateway lo reinicia s6 **en el lugar** y el contenedor sigue corriendo (`RestartCount` y
`StartedAt` sin cambios). Lo que se acepta, entonces, no es «un ciclo de vida que sigue a
Hermes» sino **un ciclo de vida de contenedor compartido**: los agentes viven y mueren con el
contenedor, no con el gateway. El detalle medido está en «Apagado y ciclo de vida».

### R5 — Presupuesto de recursos compartido (medido)

El merge convierte `mem_limit: 2g + 4g`, `cpus: 2.0 + 4.0` y dos `pids_limit: 512` en **un solo**
presupuesto por cgroup. Lo que se acepta es exactamente eso — un techo **compartido** —, no un techo
recortado en silencio:

| Recurso | Valor | Por qué |
| --- | --- | --- |
| `mem_limit` | `6g` | suma de los dos anteriores (2g + 4g) |
| `cpus` | `6.0` | suma de los dos anteriores (2.0 + 4.0) |
| `pids_limit` | `1024` | paridad exacta con el peor caso anterior (512 + 512) |

El valor de `pids_limit` se decidió **antes** de medir (design §16) con una regla pre-comprometida:
pico ≤ 614 (60 % de 1024) → confirmar 1024; pico > 614 → subir a 1536 y después a 2048; pico ≥ 256
pero chico → dejar 1024 igual. La medición confirmó el valor original:

- **Línea base en reposo:** `pids.current = 52` de `pids.max = 1024`, sin sesión de OpenCode.
- **Pico medido:** `pids.current = 478` (mediana `329`, mínimo `60`) sobre **900 muestras a 1 Hz**
  con el peor caso concurrente corriendo; `pids.max = 1024` (finito, nunca `max`).
- **Veredicto de la regla:** `478 ≤ 614` → **se confirma `1024`**. `compose.yml` **no** se tocó.
  Headroom en el pico: 546 PIDs (53 % del límite).
- **Método de lectura:** `cat /sys/fs/cgroup/pids.current` una vez por segundo; el pico es el máximo
  de la serie completa, no un valor instantáneo elegido a mano.

`pids_limit` es la restricción **vinculante** del conteo de procesos: `nofile` queda holgado con el
default de Docker. El detalle del trabajo que produjo el pico, y lo que **no** se pudo reproducir,
está en «Evidencia medida».

### R6 — El documento de tareas de interoperación queda superseded

`odd/tasks/agent-interop-http.md` describe la etapa en la que `opencode serve` vivía en su
propio contenedor y se alcanzaba por red a través del nombre de servicio interno (`opencode`).
Ese diseño quedó **superado** por este cambio y su documento lleva la nota **superseded-by**
correspondiente. Su historial se conserva como registro de cómo se construyó el interop HTTP, no
como la topología vigente.

### R7 — Workspace compartido sin frontera de contenedor detrás

El workspace (`${HOST_DATA_DIR}/workspace`) es un bind compartido por los dos procesos del
mismo contenedor. A diferencia del layout anterior, **no hay una frontera de contenedor** entre
`opencode` y Hermes: comparten uid, filesystem y entorno. Un compromiso de cualquiera de los
dos alcanza lo que el otro ve, incluido el workspace y el estado en `/opt/data`. Esto es una
regresión aceptada (D2), no un defecto a corregir por configuración: con `cap_drop: [ALL]` y
`no-new-privileges`, la contención está en el cgroup y en la allowlist de egreso, no en una
muralla entre los dos procesos.

## Interoperación Hermes ↔ OpenCode

Hermes y OpenCode ya **no** se hablan por red entre contenedores: son dos procesos del mismo
contenedor `robotina`. `opencode serve` escucha en **loopback** y Hermes lo alcanza por
`http://127.0.0.1:4096`.

| Pieza | Cómo está |
| --- | --- |
| Servicio | `opencode serve --hostname 127.0.0.1 --port 4096` (headless, sin TUI ni TTY), supervisado por s6 |
| Alcance | Solo loopback **dentro** del contenedor. El puerto **no** se publica: no lo alcanza el host, ni la LAN, ni ningún par de la red `agents`. |
| Dirección del flujo | Hermes llama a `http://127.0.0.1:4096`. Al revés no hace falta. |
| Credenciales | `OPENCODE_SERVER_PASSWORD` es defensa en profundidad (ver abajo). Con la variable presente, el servidor exige HTTP Basic (usuario `opencode`) y Hermes la manda desde su entorno. |
| Conocimiento | El agente usa el **CLI local** (wrapper en `/opt/robotina/bin/opencode`) y dos skills para OpenCode: la **builtin `opencode`** del vendor, que documenta ese CLI, y la skill propia del repo `hermes/skills/opencode-delegation/SKILL.md`, que fija el contrato de delegación (agente ejecutor, regla de proveedor/modelo, endpoint no bloqueante y servidor único). `hermes/skills/` monta `github-private-repos` y `opencode-delegation`, **read-only** en `/opt/data/skills/stack`, así que el agente no puede reescribir estas instrucciones. El resto de su árbol de skills vive en el bind escribible `/opt/data`, que sí puede modificar. |
| Arranque | Un oneshot `opencode-ready` no declara el arranque terminado hasta que `/global/health` responde de verdad; el gate es acotado y con credencial. |
| Egreso | Sin cambios: `opencode` no tiene ruta propia. Su llamada al modelo aparece como `models.opencode.ai TCP_TUNNEL` en el log del proxy. |

### Por qué se conserva `OPENCODE_SERVER_PASSWORD`

Con el servidor en loopback, **ningún par de red puede alcanzar el puerto 4096**: ni el host,
ni `egress-proxy`, ni ningún contenedor de la red `agents`. La razón de la variable, por lo
tanto, **ya no** es separar a los agentes entre sí —esa racionalidad quedó retirada— sino actuar
como **segunda cerradura** frente a un proceso que llegue a loopback *sin heredar el entorno del
contenedor*. La variable **no** es una frontera contra un proceso que sí hereda el entorno (que,
en un contenedor con un solo uid, incluye al propio agente).

Se conserva porque el costo ya está aceptado y documentado (variable legible con
`docker inspect --format` acotado y una copia en el `argv` de `scripts/export-state.sh`), y
porque quitarla obligaría a tocar una ruta de autenticación que hoy funciona sin ganar nada en
seguridad.

```ini
# .env
OPENCODE_SERVER_PASSWORD=<algo largo y random>
```

```bash
docker compose up -d robotina
```

Por defecto puede quedar vacío, y el server avisa `server is unsecured` en su log: si ves ese
warning, sabés que falta.

### Modelos que opencode puede usar

Solo tiene autenticado el tier **free** de `opencode/*` (`mimo-v2.5-free`,
`nemotron-3-ultra-free`, `muse-spark-1.3-contributor-free`, …). Son gratis y suficientes para
probar el circuito; para que use el plan Go hay que autenticarlo aparte (`opencode auth`,
interactivo). Para listar el catálogo usá el endpoint **público** de modelos del plan; **nunca**
`GET http://127.0.0.1:4096/config/providers`, que expone las claves (ver la trampa de abajo).

**Trampa documentada: `GET /config/providers` serializa las credenciales del proveedor en
texto plano.** Ese endpoint devuelve, por proveedor, la clave tal cual. Nunca lo dumpees a un
log, transcript o issue: una credencial se filtró exactamente por ese endpoint durante este
trabajo, y cualquier credencial que haya quedado expuesta así **debe rotarse**. Para conocer el
catálogo del plan está el endpoint público de modelos (ver «Modelo y plan del proveedor»), que
no necesita exponer la clave.

Nota: la superficie de conocimiento del agente para OpenCode son dos skills: la **builtin
`opencode`** del vendor, que documenta el **CLI** — y el CLI ahora sí está disponible en el
entorno del agente (wrapper en `/opt/robotina/bin/opencode`, que le da la clave propia de
OpenCode) — y la skill propia del repo `hermes/skills/opencode-delegation/SKILL.md`, montada
**read-only** en `/opt/data/skills/stack`, que documenta el contrato de delegación: el agente
ejecutor, la regla de proveedor/modelo, el endpoint no bloqueante y el servidor único
supervisado. La skill anterior, orientada al endpoint HTTP, se había eliminado por duplicar la
builtin; esta la reemplaza con el contrato corregido para el layout de dos claves.

## Persistencia: qué vive dónde

Todo el estado vive en carpetas del host bajo `HOST_DATA_DIR` (que se define en `.env`),
**salvo dos bases SQLite** que van a volúmenes nativos de Docker, montados **anidados dentro**
del bind `/opt/data`. No es capricho: es una medición.

| Dato | Dónde | Por qué |
| --- | --- | --- |
| Config y sesiones de Hermes | `${HOST_DATA_DIR}/hermes` (bind en `/opt/data`) | Carpeta del host: visible, editable, backupable. |
| Workspace compartido | `${HOST_DATA_DIR}/workspace` | El mismo código que ven los dos procesos. |
| Config de opencode (`opencode.json`, plugins, skills de gentle-ai, temas, `AGENTS.md`) | `/opt/data/.config/opencode` (dentro del bind) | Idem. El oneshot `opencode-init` re-aplica ahí los artefactos de gentle-ai en cada arranque. |
| Backups en JSON | `${HOST_DATA_DIR}/backups` | Salida de `scripts/export-state.sh`. |
| `opencode.db` (sesiones) | volumen `robotina_opencode_db`, montado en `/opt/data/.local/share/opencode` | Usa **WAL**, y ver más abajo. |
| `engram.db` (memoria) | volumen `robotina_engram_db`, montado en `/opt/data/.engram` | Usa **WAL**, idem. |
| Logs del proxy | tmpfs | No persisten a propósito: no dejamos tráfico ni credenciales en disco. |

### Montaje anidado (volumen dentro de bind)

Los dos volúmenes WAL se montan **dentro** del bind `/opt/data`: la ruta final
(`/opt/data/.engram`, `/opt/data/.local/share/opencode`) es un volumen nativo que **ensombrece**
la carpeta homónima del host. El host sigue teniendo esos puntos de montaje vacíos —los ve, pero
el volumen los tapa— de modo que un archivo escrito en el "volumen" **no** aparece en el bind del
host. Esa separación es la que hace que el estado WAL no viva sobre la carpeta de Windows
(virtiofs/9p). La verificación medida del tipo de montaje (ext4 frente a `9p`/`virtiofs`), del
control negativo y de la durabilidad se registra en la **sección de evidencia medida**; acá se
deja la decisión de diseño, no los números.

### Logs de engram

`engram serve` corre como servicio de s6 y escribe en el **stream de logs del contenedor**, no
en un archivo. El redirect anterior a `/var/log/engram.log` fallaba en silencio para uid 10000.
La salida queda acotada por la rotación `json-file` (10 MB × 3) y se lee con
`docker compose logs --tail 200 robotina`.

### Temp del agente (`TMPDIR`)

El temp del contenedor esta fijado a `/var/tmp`, **no** al scratch de Hermes. El scratch
(`HERMES_HOME/cache/scratch`) es un arbol de **cache purgado**: `SCRATCH_MAX_IDLE_HOURS=24` y
`_PRUNED_CACHE_DIRS={scratch,terminal}`, mas los `rmtree` de `kanban_db_workspace` y
`session_lost_and_found`. Con `TMPDIR` apuntando ahi, los tmpfiles de una suite de pytest
desaparecian en el teardown (`FileNotFoundError` al truncar).

`/var/tmp` es disco (no el tmpfs de 256 MB, que Hermes evita justamente para no comerse RAM con
perfiles de browser y PTY probes), existe con modo `1777` y es escribible por uid 10000. Hermes
respeta un temp puesto por el usuario: `export_scratch_tmp_env()` solo actua si `TMPDIR` esta
vacio. Override con `ROBOTINA_TMPDIR` en `.env`.

### Por qué dos bases van a volumen y no al host

SQLite en modo **WAL** sobre una carpeta de Windows (virtiofs/9p) puede corromperse en
silencio: el WAL necesita memoria compartida y bloqueos que no son coherentes cruzando la
frontera de la VM. Lo dice Hermes con todas las letras en su log
(`cross-VM filesystem ... concurrent writers can silently corrupt the database`) y lo medimos
leyendo el header de cada base (offsets 18 y 19 contando desde 0, los dos bytes de versión de
formato: `1 1` = rollback, `2 2` = WAL):

| Base | Modo medido | Se puede fijar en rollback? |
| --- | --- | --- |
| Las 6 bases de Hermes | `2 2` → **`1 1`** | **Sí.** Hermes lo documenta: `database.journal_mode: delete` en `config.yaml` más una conversión offline de cada base. Ya está aplicado. |
| `opencode.db` | `2 2` | **No**: al escribir vuelve a WAL. |
| `engram.db` | `2 2` | **No**: idem (lo probamos convirtiéndolo). |

Por eso las dos que no se pueden fijar viven en volumen nativo, donde WAL es seguro, y el
estado se saca al host en un formato que sí es portable:

```bash
docker compose exec robotina sh /opt/export-state.sh
# -> ${HOST_DATA_DIR}/backups/engram-<fecha>.json
# -> ${HOST_DATA_DIR}/backups/opencode-<sesion>-<fecha>.json
```

Compromiso explícito: esas dos bases **no** se pueden abrir a mano desde el Explorador, y un
reset de fábrica de Docker Desktop las borra. Los JSON sí sobreviven, y `engram export` /
`opencode export` permiten reconstruir.

## Autenticación de GitHub en el contenedor

Herramientas disponibles, medidas en la imagen que está corriendo: `git`, `gh`, `curl`, `node`,
`npm`, `go`, `uv`, `jq`, `rg`. **Ninguna está pinneada** más allá de lo que fija el Dockerfile
del stack, así que describen la imagen medida, no una garantía a futuro: para auditar una
versión hay que medirla otra vez en el contenedor. **No** hay cliente `ssh`, y no es un olvido:
el proxy solo permite `CONNECT` al puerto 443, así que SSH por el 22 es imposible. Las URLs
`git@github.com:` se reescriben a HTTPS con `insteadOf`, en la config de SISTEMA
(`/etc/gitconfig`), así que cualquier receta que use la forma SSH funciona igual:

```bash
# verificado: devuelve el hash aunque la URL sea ssh
git ls-remote git@github.com:artempyanykh/marksman HEAD
```

El token va por entorno y `gh` actúa de credential helper de git. Sin `gh auth login`:

```ini
# .env
GITHUB_TOKEN=<pat fine-grained>
```

Verificado con un token dummy: `git credential fill` para `github.com` devuelve
`username=x-access-token` y el password tomado del entorno.

### Límites y riesgos (medidos, no supuestos)

- **`gh auth token` imprime el token.** Cualquier proceso del contenedor, incluido el agente, lo
  lee con un comando. El deny-list de `permission.read` protege de la lectura accidental de
  archivos (`**/.env`, `**/.ssh/**`, `**/.config/gh/hosts.yml`), no de un agente decidido: si le
  pedís que te lo muestre, te lo muestra. Ver R1: el PAT es alcanzable por todo el contenedor.
- Por eso: **PAT fine-grained**, con los repos justos y el alcance mínimo (Contents read/write;
  Pull requests solo si lo necesitás).
- La variable es legible con `docker inspect --format` acotado: el mismo riesgo ya aceptado para
  el resto de las claves.
- La config GLOBAL de git (identidad de commits, preferencias) vive en
  `${HOST_DATA_DIR}/hermes/.config/git/config` vía `GIT_CONFIG_GLOBAL`, así que sobrevive a los
  recreates. Verificado escribiendo desde el contenedor y leyendo el archivo en el host.
- **`scripts/export-state.sh` deja el password en el `argv`.** Construye
  `curl -u "opencode:$OPENCODE_SERVER_PASSWORD"` como parámetros posicionales (que es lo
  correcto para que sobreviva caracteres raros), y eso lo vuelve legible en el `ps` del
  contenedor mientras corre. No agrega un secreto nuevo — el agente ya tiene esa variable en su
  entorno — pero sí una copia fuera del entorno, en un lugar que cualquier proceso del
  contenedor puede leer.

## Python y Go dentro del contenedor

### Python: solo `uv`

No se instala el `python3` del sistema para uso general. `uv` administra su propio intérprete
(**CPython 3.13**, horneado en la imagen durante el build, así que no depende de la red en
runtime) y `python3`/`python` son symlinks a él para que cualquier script que espere `python3`
en el PATH siga funcionando.

El flujo correcto es por entorno virtual, **en el proyecto**:

```bash
cd /workspace/mi-proyecto
uv venv            # crea .venv
uv pip install requests
uv run script.py
```

Eso además cumple la regla de persistencia: el `.venv` queda dentro del workspace, que está
montado en la carpeta del host. Verificado: instalar `six` por el proxy tarda 139 ms y el
`.venv` aparece en el host.

Dos cosas que conviene saber porque **no** son errores:

- `uv pip install --system` **se niega**: *"This Python installation is managed by uv and should
  not be modified"*. uv protege su intérprete a propósito; instalá en un venv.
- `uv tool install <cli>` escribe en la capa de la imagen y se pierde al recrear el contenedor.
  Para una herramienta que quieras fija, agregala al Dockerfile; para uso puntual, `uvx <cli>`.

Hosts que esto necesita en la allowlist: `pypi.org` y `files.pythonhosted.org` (verificado
instalando `six`). Los puertos de salida permitidos son 80 y 443, y para `CONNECT` —o sea
HTTPS— solo 443.

### Go

`go` con `GOPATH` apuntando a `/opt/data/go`: el cache de módulos y los binarios de `go install`
sobreviven a los recreates y los ves en el host bajo `${HOST_DATA_DIR}/hermes/go`. Verificado
bajando un módulo real.

Para que `go get` / `go build` funcionen se agregaron a la allowlist `proxy.golang.org`
(GOPROXY) y `sum.golang.org` (base de checksums). La alternativa —`GOSUMDB=off`— los evitaría a
costa de perder la verificación de integridad de los módulos, que no vale la pena.

## Workspace compartido: por qué todo corre como uid 10000

Los dos procesos escriben la misma carpeta, y con `cap_drop: ALL` un proceso sin
`CAP_DAC_OVERRIDE` **no puede escribir archivos de otro uid**. Medido con los uid originales:
root creaba `0644` y el usuario `hermes` `0664`, así que ninguno podía editar lo del otro — ni
siquiera root, porque ya no tiene la capability que lo permitía. Síntoma indirecto: `git`
respondía `detected dubious ownership`.

La imagen de Hermes **no acepta** `HERMES_UID=0`: valida 1-65534 y descarta el 0 en silencio.
Por eso la alineación se hace al revés: **`opencode serve` corre con el uid de Hermes (10000)**,
y entonces todo archivo que crea cualquiera de los dos tiene el mismo dueño.

El dueño lo fija el **contenedor mismo** en cada arranque, con el `cont-init`
`robotina/s6/cont-init.d/10-robotina-state`, que corre como root antes de los servicios de
usuario. Así una carpeta de estado recién creada en el host queda escribible por uid 10000 **sin
ningún paso privilegiado del host**. El antiguo helper de host `scripts/fix-permissions.ps1` fue
**eliminado** (Q7): el `cont-init` lo reemplaza y ya no hay un `docker run` de root con el estado
del host montado como paso obligatorio.

### Trampas que costaron tiempo, para no repetirlas

- **Un directorio del árbol de estado puede venir con dueño root y romper el arranque en
  silencio.** `install -d` no le cambia el dueño a un directorio existente, así que el `cont-init`
  no solo crea las hojas: también re-aplica el dueño a los padres intermedios y luego re-corea el
  árbol con un `find -prune` acotado, sin tocar los montajes read-only (`/opt/data/skins`,
  `/opt/data/skills/stack`).
- **`chown` no tiene `--one-file-system`** en la imagen. Un `chown -R /opt/data` a secas bajaría
  a los montajes read-only y abortaría el arranque; el `find -prune` es el sustituto que funciona.
  Si agregás un montaje nuevo bajo `/opt/data`, actualizá la lista de prune.
- **Cambiar el Dockerfile no recrea el contenedor.** `docker compose up -d` compara la
  configuración declarada, no el contenido de la imagen, así que el contenedor sigue con la imagen
  vieja y el cambio "no tiene efecto". Después de un build:
  `docker compose up -d --force-recreate robotina`.
- **Los binds de Windows no siembran desde la imagen.** A diferencia de un volumen nombrado, un
  bind muestra la carpeta del host tal cual: si está vacía, el contenedor no recibe el contenido
  horneado. Por eso el oneshot `opencode-init` re-aplica los artefactos de gentle-ai y el overlay
  en cada arranque.

## Cómo le llega una instrucción al agente (y por qué la skill sola no alcanza)

Medido en carne propia: se le pidió al agente clonar un repo privado y **pidió un token dos
veces**, incluso con la política ya escrita en una skill y la caché regenerada. Causas, en orden
de importancia:

1. **De cada skill el modelo ve solo su `description`**, y después **decide** si abre el cuerpo.
   Si el gancho no nombra su caso, la skill no se consulta. Por eso ahora cada skill nuestra tiene
   una sola responsabilidad y un `description` que nombra su disparador.
2. **El índice de skills está cacheado y la caché no vigila el directorio.** Lo dice el código de
   la imagen (`prompt_builder.py`: *the skills index cache (LRU + disk snapshot) does not watch
   the skills dir*). Se invalida comparando una firma de archivos y se reescribe al construir un
   prompt — o sea con el mensaje siguiente, no al reiniciar el contenedor. Y cada sesión guarda su
   propio system prompt, así que una conversación vieja puede seguir viendo la lista vieja: para
   ver skills nuevas hace falta **una conversación nueva**.
3. **Lo que se carga siempre no es una skill**: es el archivo de contexto del `cwd`
   (`.hermes.md`, prioridad máxima) y `SOUL.md`. Ahí va lo que el agente **no debe deducir**:
   hechos del entorno y reglas duras.

Implementación: `hermes/context/.hermes.md`, montado read-only en `/workspace/.hermes.md`, con el
cwd de la terminal del agente apuntando ahí (`terminal.cwd: /workspace`). Efecto secundario
deseable: el agente trabaja en el workspace compartido por defecto.

### Config que vive en tu carpeta, no en el repo

Estos ajustes son estado tuyo (`HOST_DATA_DIR/hermes/config.yaml`), así que no viajan en el repo:
si alguna vez regenerás la config con `hermes setup`, hay que volver a aplicarlos.

| Ajuste | Por qué | Backup |
| --- | --- | --- |
| `database.journal_mode: delete` | WAL sobre carpeta de Windows puede corromperse | `config.yaml.bak-predelete` |
| `terminal.cwd: /workspace` | para que el contexto del agente y su trabajo caigan en el workspace compartido | `config.yaml.bak-cwd` |
| `model.default` + `provider: opencode-go` | el plan Go no sirve Claude | `config.yaml.bak` |

## Puntos de atención

- **La allowlist controla el destino, no el contenido.** Squid no intercepta TLS — no hay
  `ssl_bump` en `squid.conf` — así que autoriza `CONNECT` a un dominio y a partir de ahí el túnel
  es opaco. Consecuencia práctica: cualquier host de la allowlist es una ruta de salida usable
  para *cualquier* payload. `mcp.context7.com` y `mcp.grep.app` son terceros con los que el agente
  habla por diseño, y `.github.com` está habilitado con el `GITHUB_TOKEN` disponible. El control
  real es «a qué dominios puede hablar», no «qué puede mandar»: si el agente llega a manejar
  material que no debe salir, este es el límite que hay que asumir, y la mitigación es sacar el
  host de la lista, no confiar en el filtro.
- **Hermes intenta descubrir IPs de Telegram por DNS-over-HTTPS.** Al conectar pide `dns.google`
  y `cloudflare-dns.com`; el proxy los deniega y la conexión igual se establece contra
  `api.telegram.org`. Dejalo bloqueado: habilitar esos dos hosts reabre un canal de DNS paralelo
  que esquiva la allowlist por dominio.
- **Un cliente que ignore `HTTP(S)_PROXY` falla, no evade.** Si resuelve el nombre por su cuenta y
  abre un socket directo, se choca con que la red `agents` no tiene ruta ni DNS externo. Para
  Hermes eso quedó descartado por evidencia; si en el futuro agregás otro proceso, verificá su
  cliente HTTP antes de asumir que el proxy lo cubre.
- **El DNS externo está cerrado por accidente del entorno, no por configuración.** Desde `agents`
  no resuelven `example.com`, `github.com` ni `pypi.org`. Es deseable, pero es una propiedad
  observada: si cambiás de daemon de Docker o de resolutor del host, volvé a medirlo.
- **`/opt/data/config.yaml` de Hermes es viejo.** El bootstrap avisa: *"This config predates
  version 12 (~2 years old) and can no longer be auto-migrated"*, y sugiere `hermes setup`. Es un
  tema de mantenimiento, no de seguridad, pero conviene resolverlo antes de usar el gateway en
  serio.
- **Nombres de red.** La red con salida se llama `egress` (antes `agent_internet`). Si quedó la
  vieja: `docker network rm agent_internet`.

## Fuera de alcance (siguientes pasos)

- Docker rootless o `userns-remap` a nivel daemon: aislamiento real entre contenedor y host, no se
  resuelve desde `compose.yml`.
- Secretos como archivos en `/run/secrets` (requiere entrypoint propio).
- `read_only: true` en el agente: `opencode` probablemente lo tolere; Hermes escribe durante el
  arranque (config, skills, ledger) y necesita más análisis antes de intentarlo.
- Perfil `seccomp` propio y `apparmor`: se usa el default de Docker, que ya bloquea las syscalls
  peligrosas más comunes.

## Evidencia medida

Todo lo de esta sección sale de la corrida real (2026-09-22, contenedor `robotina` en Docker Desktop
para Windows, los dos servicios `(healthy)`), no de estimaciones. Las recetas usan patrones de
caracteres (`[o]pencode serve`, `[h]ermes gateway`), un match vacío es FAILURE, y `docker inspect`
siempre va con `--format` acotado.

### Capacidades (R3)

```text
$ docker compose exec robotina sh -c 'for p in $(pgrep -f "[o]pencode serve"); do echo "pid=$p uid=$(awk \047/^Uid/{print $2}\047 /proc/$p/status)"; grep -E "Cap(Inh|Prm|Eff|Bnd|Amb)|NoNewPrivs" /proc/$p/status; done'
pid=416 uid=10000
CapInh:	0000000000000000
CapPrm:	0000000000000000
CapEff:	0000000000000000
CapBnd:	00000000000000eb
CapAmb:	0000000000000000
NoNewPrivs:	1
```

`0xeb` = 235 = `0b11101011`: `CHOWN`(1) + `DAC_OVERRIDE`(2) + `FOWNER`(8) + `KILL`(32) +
`SETGID`(64) + `SETUID`(128). El proceso de la app conserva la máscara de *bounding* pero
**no** tiene ninguna efectiva (`CapEff=0x0`), y `NoNewPrivs: 1` le impide recuperarlas. El detalle
de por qué son del contenedor y no del proceso está en R3.

### Presupuesto de recursos y pico de `pids` (R5)

```text
$ docker compose exec robotina sh -c 'cat /sys/fs/cgroup/pids.current; cat /sys/fs/cgroup/pids.max'
52
1024
$ docker compose exec robotina sh -c 'i=0; while [ $i -lt 900 ]; do cat /sys/fs/cgroup/pids.current; i=$((i+1)); sleep 1; done' | sort -n | tail -1
478
(900 muestras: mínimo 60, mediana 329, máximo 478)
```

El pico se buscó con el peor caso concurrente corriendo **en paralelo** durante toda la ventana.
Lo que sí se reprodujo:

1. una **sesión real de OpenCode** por la API de loopback (creada con `POST /session` y manejada con
   `/session/{id}/message`) sobre un workspace con `.py`, `.R`, `.toml`, `.md`, `.json` y un
   `Dockerfile`: los LSP `python`/`pyright`, `json`, `toml`, `r` y `marksman` quedaron `connected`;
2. builds de fuente de R con `Ncpus=6` (80 unidades de traducción C, `--preclean`, cuatro workers
   concurrentes) → tormenta de `gcc`;
3. `go build -a ./...` + `go vet ./...` sobre un módulo de 41 archivos (dos workers);
4. `npm ci` + `node --test --test-concurrency=6` (dos workers);
5. una tormenta de fork extra: `basedpyright` con varios workers de Node por invocación y un
   `R languageserver` de vida corta.

Lo que **no** se pudo reproducir, dicho sin adornos: **el tráfico de Telegram**. La conexión de
*long poll* del gateway está viva y contada en la línea base, pero no se generó una ráfaga de
mensajes: originarla requiere que un humano escriba al bot o enviar mensajes reales al chat del
usuario, y eso no se hizo. El pico registrado es, entonces, el del peor caso **sin** esa ráfaga;
Telegram aporta pocos procesos frente a un build concurrente, así que la omisión es menor, pero no
se presenta como el peor caso completo.

### Anidamiento de volúmenes (SL2)

```text
$ docker compose exec robotina sh -c 'mount | grep -E "\.engram|\.local/share/opencode"'
/dev/sdd on /opt/data/.engram type ext4 (rw,relatime)
/dev/sdd on /opt/data/.local/share/opencode type ext4 (rw,relatime)
$ ls -A "$HOST_DATA_DIR/hermes/.engram"     # control negativo: el marcador NO aparece en el bind
# (vacío)
$ docker volume ls --format '{{.Name}}' | grep -cE '^robotina_(engram|opencode)_db$'
2
```

Los dos volúmenes WAL son **`ext4`**, no `9p` ni `virtiofs`: Docker Desktop los presenta como un
volumen nativo, y eso es lo que hace segura la escritura WAL. La prueba positiva y el control
negativo cierran el riesgo D-1: un marcador escrito adentro del volumen (`.robotina-probe`) **no**
aparece en la carpeta del host (`hermes/.engram` queda vacía) y **sobrevive** a `docker compose down`
+ `up -d`. `HOST_DATA_DIR` contiene solo `backups`, `hermes` y `workspace`, que es el contrato del
layout de persistencia.

### Apagado y ciclo de vida

```text
$ start=$(date +%s%N); docker compose stop robotina; end=$(date +%s%N)
Stopping robotina  ...  Stopped
stop_duration_ms=5504        -> 5.50 s (dentro de stop_grace_period: 20s)
ExitCode=0  OOMKilled=false
# log: opencode-ready -> opencode -> main-hermes -> dashboard -> engram -> opencode-init
#      -> legacy-cont-init -> fix-attrs, todos "successfully stopped"; el gateway recibe SIGTERM
```

Apagado **ordenado**, sin `SIGKILL` de Docker: ese es el efecto observable de la sexta capability
(`CAP_KILL`). Antes de agregarla, el mismo `stop` se trababa y Docker terminaba matando PID 1
pasado el grace period. El contrato medido completo —el gateway es un servicio de s6 que se
reinicia **en el lugar**; el contenedor sale cuando baja el árbol de supervisión— está en «Apagado y
ciclo de vida (medido)» y en R4.

### Gate de readiness

```text
ciclo 1: StartedAt 19:05:59.228674207Z -> "opencode listo (intentos=1)" 19:06:03.569450221Z  = 4.34 s
ciclo 2: StartedAt 19:06:26.496136427Z -> "opencode listo (intentos=1)" 19:06:31.056849886Z  = 4.56 s
ciclo 3: StartedAt 19:06:53.652872543Z -> "opencode listo (intentos=1)" 19:06:58.092762695Z  = 4.44 s
probe_exit=0 en los tres; intentos=1 en los tres; bound = 120 s
$ docker compose logs --since 10m robotina | grep -Ei '127\.0\.0\.1:4096.*(refused|econnrefused)'
# (sin salida)
```

El gate se satisface en el **primer** intento y **nunca** aparece un `ECONNREFUSED` en el log: el
primer llamado de Hermes no compite con el arranque.

**Qué pasa si el gate falla** (observado forzando el fallo en un contenedor descartable, no
inferido): s6-overlay **continúa al CMD** con un warning por servicio y un arranque **degradado**,
no aborta:

```text
s6-rc: info: service opencode-ready: starting
s6-rc: warning: unable to start service opencode-ready: command exited 1
# docker inspect -> Status=running Running=true ExitCode=0
# S6_BEHAVIOUR_IF_STAGE2_FAILS sin definir (0 matches en /proc/1/environ)
```

Con `S6_BEHAVIOUR_IF_STAGE2_FAILS` sin definir, el `rc.init` real toma el valor por defecto `b=0`,
así que ni la rama de warning ni la de `haltwith` se activan y el CMD igual se ejecuta. Es el
escenario D-6 del design (arranque degradado) y no un cierre del stack.

### Autenticación del endpoint (EP1/EP4, §19.4)

```text
$ docker compose exec robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 5 http://127.0.0.1:4096/global/health'
{"healthy":true,"version":"1.18.32"}   # exit=0
$ docker compose exec robotina sh -c 'curl -s -o /dev/null -w "%{http_code}\n" -m 5 http://127.0.0.1:4096/global/health'
401
$ docker compose exec robotina sh -c 'ss -ltn | grep 4096'
LISTEN 0 512 127.0.0.1:4096 0.0.0.0:*
```

El endpoint **sí** está protegido: una sonda sin autenticación responde **HTTP 401**, con la credencial responde
**200**. Escucha solo en `127.0.0.1` —no hay bind comodín— y el puerto **no** se publica.

### Notas que necesitaron interpretación (§19.5)

- **EP2 (sonda del host):** desde el host, `curl -m 5 -sS http://127.0.0.1:4096/global/health` →
  `curl: (7) Failed to connect … Connection refused` (exit 7), y
  `Get-NetTCPConnection -LocalPort 4096` devuelve **0** listeners. Es decir: la sonda falla por
  *no haber puerto*, no porque otra cosa lo ocupe. Ojo con un detalle: `curl` **sin `-f`** devuelve
  exit 0 aunque la respuesta sea 401, así que la comprobación de autenticación compara el **código
  HTTP**, no el exit de `curl`.
- **ID1 (fuente del montaje):** en `mountinfo` la fuente del bind es la ruta del lado de la VM
  (`/run/desktop/mnt/host/c/…`), no la ruta Windows; el montaje del skin apunta a la carpeta del
  **repo** (`hermes/skins`), no a `HOST_DATA_DIR`, que es la intención que había que probar.
- **SL3 (lectura de engram):** el comando de lectura es
  `docker compose exec robotina engram export /backups/engram-<fecha>.json`, el mismo que usa
  `scripts/export-state.sh`, válido porque `ENGRAM_DATA_DIR` es del contenedor entero. No se inventó
  ninguna invocación nueva.
- **Sonda in-container `robotina:4096`:** queda confundida por el entorno de proxy (Squid responde
  con una página de deny, exit 0); la prueba no confundida es el rechazo desde un contenedor par.
