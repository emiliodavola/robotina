#!/usr/bin/env pwsh
# Herramienta de REPARACION; ya NO forma parte del setup.
#
# SUPERSEDED: el chown de arranque lo hace ahora el cont-init del contenedor
# (`robotina/s6/cont-init.d/10-robotina-state`), que corre como root en cada
# start y deja el estado escribible por el uid 10000 sin ningun paso
# privilegiado en el host. Este script queda solo para reparar a mano un arbol
# de estado que aparezca mal dueno, por ejemplo despues de restaurar un backup.
#
# Ya no cubre `opencode/`, `git/` ni `go/`: esas carpetas del host no son
# montajes en el layout de un solo contenedor. Se mantienen `workspace/` y
# `backups/` (binds) mas los dos volumenes nombrados.
#
# Uso, solo para reparar, desde la raiz del repo:
#   pwsh -File scripts/fix-permissions.ps1
#
# Cualquier valor >= 1 es valido: el uid debe coincidir con el usuario `hermes`
# de la imagen (10000 por defecto), que es quien escribe el estado.

$ErrorActionPreference = 'Stop'
$TargetUid = '10000'
$Subdirs   = @('backups', 'workspace')
$Volumes   = @('robotina_engram_db', 'robotina_opencode_db')

# HOST_DATA_DIR sale del .env, que es la unica fuente de verdad de la ruta.
$envPath = Join-Path $PSScriptRoot '..\.env'
$match = Select-String -Path $envPath -Pattern '^HOST_DATA_DIR=(.+)$' | Select-Object -First 1
if (-not $match) { throw "No encontre HOST_DATA_DIR en $envPath" }
# Docker acepta barras invertidas, pero normalizarlas evita mezclas raras.
$data = ($match.Matches[0].Groups[1].Value.Trim()) -replace '\\', '/'
Write-Host "HOST_DATA_DIR = $data`n"

foreach ($sub in $Subdirs) {
    Write-Host "  chown -R ${TargetUid}:${TargetUid}  $sub"
    docker run --rm -v "${data}:/d" alpine chown -R "${TargetUid}:${TargetUid}" "/d/$sub"
}

foreach ($vol in $Volumes) {
    Write-Host "  chown -R ${TargetUid}:${TargetUid}  (volumen $vol)"
    docker run --rm -v "${vol}:/v" alpine chown -R "${TargetUid}:${TargetUid}" /v
}

Write-Host "`nVerificacion, como lo ve un contenedor:"
docker run --rm -v "${data}:/d" alpine ls -ld /d/backups /d/workspace
Write-Host "`nListo. Reparacion terminada."
