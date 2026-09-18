#!/usr/bin/env pwsh
# Deja con uid 10000 las carpetas y volumenes que escribe el contenedor de
# opencode.
#
# Por que: los dos agentes comparten /workspace y, con `cap_drop: ALL`, un
# proceso sin CAP_DAC_OVERRIDE no puede escribir archivos de otro uid. Medido:
# root crea 0644 y el usuario `hermes` (uid 10000) 0664, asi que NINGUNO podia
# editar lo del otro. La imagen de Hermes descarta HERMES_UID=0 (valida 1-65534),
# asi que se alinea al reves: opencode corre como uid 10000.
#
# Uso, desde la raiz del repo:
#   pwsh -File scripts/fix-permissions.ps1
#
# Cualquier valor >= 1 es valido: si mas adelante cambias el uid, cambia la
# constante de abajo y la linea `user:` de compose.yml en el mismo commit.

$ErrorActionPreference = 'Stop'
$TargetUid = '10000'
$Subdirs   = @('opencode', 'go', 'backups', 'git', 'workspace')
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
docker run --rm -v "${data}:/d" alpine ls -ld /d/opencode /d/go /d/backups /d/git /d/workspace
Write-Host "`nListo. Despues de esto, en compose.yml: user: `"$TargetUid`:$TargetUid`" para opencode."
