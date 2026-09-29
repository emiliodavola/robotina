# AGENTS.md — instrucciones para agentes que trabajan en este repositorio

Este repo define **un solo contenedor de agentes** (`robotina`). La imagen se
construye desde `robotina/Dockerfile`, por encima de la base vendor de Hermes
(`nousresearch/hermes-agent:<tag>@sha256:<digest>`), y no rearma esa base: le
agrega la toolchain (opencode, LSP, gh, codegraph, engram, gentle-ai, R, go). El
stack se levanta con `compose.yml`.

## Invariantes que no se rompen

- **Los `ARG` del Dockerfile son la única fuente de versión de las herramientas
  horneadas desde un release o un asset npm** (engram, gentle-ai, marksman,
  opencode, gh, taplo), y la pregunta "qué versión corre" se contesta desde el
  repo y desde la imagen. La base vendor y el proxy no van por `ARG`: se fijan
  por tag y digest (`FROM …:v2026.9.24@sha256:…` y `ubuntu/squid:latest`).
- **`/usr/local/bin` es `root:root` y los servicios corren como `hermes` (uid
  10000).** Por eso ninguna herramienta horneada se auto-actualiza dentro del
  contenedor: el updater de `gentle-ai`, por ejemplo, prepara un temporal al lado
  del binario y muere con un `EACCES` opaco. Actualizar = subir el pin y
  reconstruir.
- **El estado del agente vive en el bind `/opt/data`.** Lo horneado es imagen; lo
  que el agente produce (config, memoria, herramientas de `uv`) es estado y
  sobrevive a los recreates porque está en el bind.

## Cómo actualizar una herramienta horneada

```sh
scripts/bump-tools.sh --check          # qué pin quedó atrás
scripts/bump-tools.sh --write <tool>   # reescribe el ARG correspondiente
docker compose build robotina          # reconstruir con el pin nuevo
```

Dependabot no ve los `ARG`, así que este script es el camino soportado. El
healthcheck (`robotina/healthcheck.sh`) compara la versión que corre contra el pin
que la imagen publicó y falla si una copia en `/opt/data/.local/bin` ensombrece el
binario horneado. Ese chequeo existe para las dos herramientas que publican pin
(`engram` y `gentle-ai`); las otras cuatro pineadas por `ARG` todavía no lo tienen.

## Contrato, tracker y verificación

- `openspec/specs/*` es el **contrato** del sistema: los requisitos AC y las
  recetas de shell que los prueban; `odd/tasks/*` es el **tracker por feature**.
- No hay runner de tests (`openspec/config.yaml` → `testing.runner: none`): la
  verificación es a nivel shell y usa las recetas que nombran los propios specs
  (`docker compose exec`, `docker compose config -q`). Nunca corras
  `docker compose config` sin `-q`: la forma pelada imprime los secretos resueltos.

## Secretos

Los secretos viajan por `.env` y variables de entorno. **Nunca** los imprimas en
logs, issues, comentarios ni artefactos: `docker inspect` sin un `--format`
acotado, por ejemplo, los muestra.
