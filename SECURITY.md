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

## Persistencia: qué vive dónde

Todo el estado vive en carpetas del host bajo `HOST_DATA_DIR` (que se define en
`.env`), **salvo dos bases SQLite** que van a volumenes nativos de Docker. No es
capricho: es una medicion.

| Dato | Donde | Por que |
| --- | --- | --- |
| Config y sesiones de Hermes | `${HOST_DATA_DIR}/hermes` | Carpeta del host: visible, editable, backupable. |
| Workspace compartido | `${HOST_DATA_DIR}/workspace` | El mismo codigo que ven los dos agentes. |
| Config de opencode (opencode.json, plugins, skills de gentle-ai, temas, `AGENTS.md`) | `${HOST_DATA_DIR}/opencode` | Idem. El entrypoint re-aplica ahi los artefactos de gentle-ai en cada arranque. |
| Backups en JSON | `${HOST_DATA_DIR}/backups` | Salida de `scripts/export-state.sh`. |
| `opencode.db` (sesiones) | volumen `robotina_opencode_db` | Usa **WAL**, y ver mas abajo. |
| `engram.db` (memoria) | volumen `robotina_engram_db` | Usa **WAL**, idem. |
| Logs del proxy | tmpfs | No persisten a proposito: no dejamos trafico ni credenciales en disco. |

### Por que dos bases van a volumen y no al host

SQLite en modo **WAL** sobre una carpeta de Windows (virtiofs/9p) puede
corromperse en silencio: el WAL necesita memoria compartida y bloqueos que no son
coherentes cruzando la frontera de la VM. Lo dice Hermes con todas las letras en
su log (`cross-VM filesystem ... concurrent writers can silently corrupt the
database`) y lo medimos leyendo el header de cada base (bytes 18-19: `1 1` =
rollback, `2 2` = WAL):

| Base | Modo medido | Se puede fijar en rollback? |
| --- | --- | --- |
| Las 6 bases de Hermes | `2 2` → **`1 1`** | **Si.** Hermes lo documenta: `database.journal_mode: delete` en `config.yaml` mas una conversion offline de cada base. Ya esta aplicado. |
| `opencode.db` | `2 2` | **No**: al escribir vuelve a WAL. |
| `engram.db` | `2 2` | **No**: idem (lo probamos convirtiendolo). |

Por eso las dos que no se pueden fijar viven en volumen nativo, donde WAL es
seguro, y el estado se saca al host en un formato que si es portable:

```bash
docker compose exec opencode sh /opt/export-state.sh
# -> ${HOST_DATA_DIR}/backups/engram-<fecha>.json
# -> ${HOST_DATA_DIR}/backups/opencode-<sesion>-<fecha>.json
```

Compromiso explicito: esas dos bases **no** se pueden abrir a mano desde el
Explorador, y un reset de fabrica de Docker Desktop las borra. Los JSON si
sobreviven, y `engram export` / `opencode export` permiten reconstruir.

## Autenticación de GitHub en el contenedor de opencode

Herramientas disponibles: `git` 2.54.0, `gh` 2.97.0, `curl`, `node`, `npm`, `go`
1.26.8, `uv` 0.11.19, `jq`. **No** hay cliente `ssh`, y no es un olvido: el proxy
solo permite `CONNECT` al puerto 443, así que SSH por el 22 es imposible. Las URLs
`git@github.com:` se reescriben a HTTPS con `insteadOf`, en la config de SISTEMA
(`/etc/gitconfig`), así que cualquier receta que use la forma SSH funciona igual:

```bash
# verificado: devuelve el hash aunque la URL sea ssh
git ls-remote git@github.com:artempyanykh/marksman HEAD
```

El token va por entorno y `gh` actúa de credential helper de git. Sin
`gh auth login`:

```ini
# .env
GITHUB_TOKEN=<pat fine-grained>
```

Verificado con un token dummy: `git credential fill` para `github.com` devuelve
`username=x-access-token` y el password tomado del entorno.

### Límites y riesgos (medidos, no supuestos)

- **`gh auth token` imprime el token.** Cualquier proceso del contenedor,
  incluido el agente, lo lee con un comando. El deny-list de `permission.read`
  protege de la lectura accidental de archivos (`**/.env`, `**/.ssh/**`,
  `**/.config/gh/hosts.yml`), no de un agente decidido: si le pedís que te lo
  muestre, te lo muestra.
- Por eso: **PAT fine-grained**, con los repos justos y el alcance mínimo
  (Contents read/write; Pull requests solo si lo necesitás).
- La variable es legible con `docker inspect`: el mismo riesgo ya aceptado para
  el resto de las claves.
- La config GLOBAL de git (identidad de commits, preferencias) vive en
  `${HOST_DATA_DIR}/git/config` vía `GIT_CONFIG_GLOBAL`, así que sobrevive a los
  recreates. Verificado escribiendo desde el contenedor y leyendo el archivo en
  el host.

## Python y Go dentro del contenedor

### Python: solo `uv`, sin `python3` de Alpine

No se instala el paquete `python3` de Alpine. `uv` administra su propio
intérprete (**CPython 3.13.13**, horneado en la imagen durante el build, así que
no depende de la red en runtime) y `python3`/`python` son symlinks a él para que
cualquier script que espere `python3` en el PATH siga funcionando.

El flujo correcto es por entorno virtual, **en el proyecto**:

```bash
cd /workspace/mi-proyecto
uv venv            # crea .venv
uv pip install requests
uv run script.py
```

Eso además cumple la regla de persistencia: el `.venv` queda dentro del
workspace, que está montado en la carpeta del host. Verificado: instalar `six`
por el proxy tarda 139 ms y el `.venv` aparece en el host.

Dos cosas que conviene saber porque **no** son errores:

- `uv pip install --system` **se niega**: *"This Python installation is managed by
  uv and should not be modified"*. uv protege su intérprete a propósito; instalá
  en un venv.
- `uv tool install <cli>` escribe en la capa de la imagen y se pierde al recrear
  el contenedor. Para una herramienta que quieras fija, agregala al Dockerfile;
  para uso puntual, `uvx <cli>`.

Puertos de salida usados y permitidos: `pypi.org` y `files.pythonhosted.org`
(verificado instalando `six`).

### Go

`go` 1.26.8, con `GOPATH=/root/go` montado en `${HOST_DATA_DIR}/go`: el cache de
módulos y los binarios de `go install` sobreviven a los recreates y los ves en el
host. Verificado bajando un módulo real.

Para que `go get` / `go build` funcionen se agregaron a la allowlist
`proxy.golang.org` (GOPROXY) y `sum.golang.org` (base de checksums). La
alternativa —`GOSUMDB=off`— los evitaría a costa de perder la verificación de
integridad de los módulos, que no vale la pena.

## Workspace compartido: por qué opencode corre como uid 10000

Los dos agentes escriben la misma carpeta, y con `cap_drop: ALL` un proceso sin
`CAP_DAC_OVERRIDE` **no puede escribir archivos de otro uid**. Medido con los uid
originales: root creaba `0644` y el usuario `hermes` `0664`, así que ninguno podía
editar lo del otro — ni siquiera root, porque ya no tiene la capability que lo
permitía. Síntoma indirecto: `git` respondía `detected dubious ownership`.

La imagen de Hermes **no acepta** `HERMES_UID=0`: valida 1-65534 y descarta el 0 en
silencio. Por eso la alineación se hace al revés: **opencode corre con el uid de
Hermes (10000)**, y entonces todo archivo que crea cualquiera de los dos tiene el
mismo dueño.

Requiere que las carpetas montadas y los dos volúmenes pertenezcan a ese uid:

```bash
pwsh -File scripts/fix-permissions.ps1   # lee HOST_DATA_DIR del .env
```

Hay que volver a correrlo si alguna de esas carpetas se recrea desde cero.

### Trampas que costaron tiempo, para no repetirlas

- **`/root/.local/state/opencode` ya existe en la imagen oficial y es de root.**
  `install -d` no le cambia el dueño a un directorio existente, así que opencode
  (uid 10000) no podía crear su subdirectorio de locks y **los dos MCP remotos
  fallaban** con `EACCES: mkdir '/root/.local/state/opencode/locks'`. Se resuelve
  con `chown -R 10000:10000 /root` en el Dockerfile, que además cubre cualquier
  otro directorio que la imagen vendor traiga con dueño root.
- **Cambiar el Dockerfile no recrea el contenedor.** `docker compose up -d` compara
  la configuración declarada, no el contenido de la imagen, así que el contenedor
  sigue con la imagen vieja y el cambio "no tiene efecto". Después de un build:
  `docker compose up -d --force-recreate opencode`.
- **Los binds de Windows no siembran desde la imagen.** A diferencia de un volumen
  nombrado, un bind muestra la carpeta del host tal cual: si está vacía, el
  contenedor no recibe el contenido horneado. Por eso el entrypoint re-aplica los
  artefactos de gentle-ai y el overlay en cada arranque.

## Cómo le llega una instrucción al agente (y por qué la skill sola no alcanza)

Medido en carne propia: se le pidió a Hermes clonar un repo privado y **pidió un token
dos veces**, incluso con la política ya escrita en una skill y la caché regenerada.
Causas, en orden de importancia:

1. **De cada skill el modelo ve solo su `description`**, y después **decide** si abre el
   cuerpo. Si el gancho no nombra su caso, la skill no se consulta. Por eso ahora cada
   skill nuestra tiene una sola responsabilidad y un `description` que nombra su
   disparador: `github-private-repos` dice "private repos, credentials, never ask the
   user for a token".
2. **El índice de skills está cacheado y la caché no vigila el directorio.** Lo dice el
   código de la imagen (`prompt_builder.py`: *the skills index cache (LRU + disk
   snapshot) does not watch the skills dir*). Se invalida comparando una firma de
   archivos y se reescribe al construir un prompt — o sea con el mensaje siguiente, no
   al reiniciar el contenedor. Y cada sesión guarda su propio system prompt, así que una
   conversación vieja puede seguir viendo la lista vieja: para ver skills nuevas hace
   falta **una conversación nueva**.
3. **Lo que se carga siempre no es una skill**: es el archivo de contexto del `cwd`
   (`.hermes.md`, prioridad máxima) y `SOUL.md`. Ahí va lo que el agente **no debe
   deducir**: hechos del entorno y reglas duras.

Implementación: `hermes/context/.hermes.md`, montado read-only en `/workspace/.hermes.md`,
con el cwd de la terminal del agente apuntando ahí (`terminal.cwd: /workspace`). Efecto
secundario deseable: el agente trabaja en el workspace compartido por defecto, que es lo
que se esperaba de él (antes clonaba en `/opt/data` porque el workspace no era escribible).

Verificado: con esos dos cambios, la misma pregunta que antes pedía un token ahora
responde que no tiene credenciales *a propósito*, que delega en OpenCode y que **nunca**
le pide un token al usuario.

### Config que vive en tu carpeta, no en el repo

Estos ajustes son estado tuyo (`HOST_DATA_DIR/hermes/config.yaml`), así que no viajan en
el repo: si alguna vez regenerás la config con `hermes setup`, hay que volver a aplicarlos.

| Ajuste | Por qué | Backup |
| --- | --- | --- |
| `database.journal_mode: delete` | WAL sobre carpeta de Windows puede corromperse | `config.yaml.bak-predelete` |
| `terminal.cwd: /workspace` | para que el contexto del agente y su trabajo caigan en el workspace compartido | `config.yaml.bak-cwd` |
| `model.default` + `provider: opencode-go` | el plan Go no sirve Claude | `config.yaml.bak` |

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
