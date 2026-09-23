# =============================================================================
# /etc/profile.d/robotina-path.sh
#
# Por que existe: el /etc/profile de Debian RESETEA el PATH de forma dura para
# los login shells (`bash -l`, `sh -l`, `su -`). Ese reset se lleva puesto todo
# lo que agrega esta imagen: el CLI de Hermes (/opt/hermes/bin), los binarios de
# su venv, /opt/data/.local/bin y — lo mas importante — el wrapper `opencode` de
# /opt/robotina/bin.
#
# Sin este archivo, en un login shell: `hermes` no se encuentra, y un `opencode`
# suelto resuelve a /usr/local/bin/opencode, que se autentica con la clave de
# HERMES en vez de con la propia de OpenCode (ver robotina/bin/opencode).
#
# /etc/profile sourcea /etc/profile.d/*.sh DESPUES de su reset (el reset esta en
# la linea 9, el sourceo en las 27-28), asi que reponer aca alcanza. El orden
# replica el PATH que la imagen ya define por ENV: los directorios propios
# primero — asi el wrapper gana sobre /usr/local/bin —, el resto del PATH que
# fijo Debian en el medio, y /opt/uv/bin al final, igual que en el ENV.
#
# Alcance: solo login shells. Los servicios de s6 y `docker compose exec` usan el
# PATH del ENV de la imagen y no pasan por aca, asi que su comportamiento no
# cambia.
# =============================================================================
export PATH="/opt/robotina/bin:/opt/hermes/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin:${PATH}:/opt/uv/bin"
