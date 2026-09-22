#!/usr/bin/env pwsh
# Migra el estado del layout de contenedores separados al layout del contenedor unico
# `robotina`.
#
# Que hace: copia "hacia adelante" el estado que hoy vive en carpetas del host
# dentro de las rutas nuevas del agente unico. Copia POR RUTA y SOLO cuando el
# destino no existe: un archivo destino mas nuevo nunca se pisa. No borra ni
# mueve nada: las carpetas legacy quedan intactas como red de seguridad de
# rollback.
#
# Destinos:
#   ${HOST_DATA_DIR}/opencode/  ->  ${HOST_DATA_DIR}/hermes/.config/opencode/
#   ${HOST_DATA_DIR}/git/       ->  ${HOST_DATA_DIR}/hermes/.config/git/
#   ${HOST_DATA_DIR}/go/        ->  NO se copia (cache reconstruible)
#
# Dentro de la carpeta legacy de opencode se omite `node_modules/` (cache
# reconstruible que opencode repuebla al arrancar) pero SI se copia
# `package-lock.json`, para que una reinstalacion sea determinista.
#
# Uso, desde la raiz del repo (lee HOST_DATA_DIR del .env):
#   pwsh -File scripts/migrate-state.ps1
#
# Para probar contra un arbol sintetico sin tocar el estado real del host:
#   pwsh -File scripts/migrate-state.ps1 -DataDir C:/ruta/fixture

[CmdletBinding()]
param(
    # Raiz de datos alternativa. Si no se pasa, se lee HOST_DATA_DIR del .env.
    # Existe para poder ejercitar la migracion contra un fixture sintetico.
    [string]$DataDir
)

$ErrorActionPreference = 'Stop'

# --- Resolver la raiz de datos: parametro explicito o HOST_DATA_DIR del .env ---
if (-not $DataDir) {
    $envPath = Join-Path $PSScriptRoot '..\.env'
    $match = Select-String -Path $envPath -Pattern '^HOST_DATA_DIR=(.+)$' | Select-Object -First 1
    if (-not $match) { throw "No encontre HOST_DATA_DIR en $envPath" }
    # Docker acepta barras invertidas, pero normalizarlas evita mezclas raras.
    $DataDir = ($match.Matches[0].Groups[1].Value.Trim()) -replace '\\', '/'
}
$DataDir = $DataDir.TrimEnd('/')
Write-Host "HOST_DATA_DIR = $DataDir`n"

# Contadores del resumen final.
$script:copiados = 0
$script:omitidos = 0
$script:omitidosNodeModules = 0

# Copia-forward recursivo: crea el arbol destino, pero jamas pisa un archivo.
function Copy-Forward {
    param(
        [string]$Source,
        [string]$Destination,
        [bool]$OmitirNodeModules
    )

    if (-not (Test-Path -LiteralPath $Source)) { return }
    $item = Get-Item -LiteralPath $Source -Force

    if ($item.PSIsContainer) {
        # Cache reconstruible: no se copia, solo se informa.
        if ($OmitirNodeModules -and $item.Name -eq 'node_modules') {
            $script:omitidosNodeModules++
            Write-Host "  omitido (cache): $Source"
            return
        }
        if (-not (Test-Path -LiteralPath $Destination)) {
            # -Force crea los directorios intermedios que falten.
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        }
        foreach ($hijo in Get-ChildItem -LiteralPath $Source -Force) {
            Copy-Forward -Source $hijo.FullName `
                         -Destination (Join-Path $Destination $hijo.Name) `
                         -OmitirNodeModules $OmitirNodeModules
        }
    }
    else {
        if (Test-Path -LiteralPath $Destination) {
            $script:omitidos++
            Write-Host "  omitido (ya existe): $Destination"
        }
        else {
            Copy-Item -LiteralPath $Source -Destination $Destination
            $script:copiados++
            Write-Host "  copiado: $Destination"
        }
    }
}

# --- Pares origen -> destino. `go/` no aparece: no se copia. ---
$pares = @(
    @{ Origen = 'opencode'; Destino = 'hermes/.config/opencode'; OmitirNodeModules = $true },
    @{ Origen = 'git';      Destino = 'hermes/.config/git';      OmitirNodeModules = $false }
)

foreach ($par in $pares) {
    $origen = Join-Path $DataDir $par.Origen
    $destino = Join-Path $DataDir $par.Destino
    Write-Host "== $($par.Origen) -> $($par.Destino) =="
    if (-not (Test-Path -LiteralPath $origen)) {
        Write-Host "  no existe el origen, se omite: $origen"
        continue
    }
    Copy-Forward -Source $origen -Destination $destino -OmitirNodeModules $par.OmitirNodeModules
    Write-Host ""
}

# --- Resumen de lo copiado y lo omitido ---
$resumen = "Resumen: {0} archivos copiados, {1} omitidos (ya existian), {2} directorios node_modules omitidos." -f `
           $script:copiados, $script:omitidos, $script:omitidosNodeModules
Write-Host $resumen

# --- Asercion final: nada se borro ni se movio ---
# Las tres carpetas legacy deben seguir existiendo (red de rollback), y las dos
# carpetas de las que copiamos no deben haber quedado vacias.
$faltantes = @()
foreach ($nombre in @('opencode', 'git', 'go')) {
    if (-not (Test-Path -LiteralPath (Join-Path $DataDir $nombre))) { $faltantes += $nombre }
}
if ($faltantes.Count -gt 0) {
    throw "Asercion fallida: faltan carpetas legacy intactas: $($faltantes -join ', ')"
}

foreach ($nombre in @('opencode', 'git')) {
    $origen = Join-Path $DataDir $nombre
    $conteo = (Get-ChildItem -LiteralPath $origen -Force | Measure-Object).Count
    if ($conteo -eq 0) {
        throw "Asercion fallida: la carpeta legacy '$nombre' quedo vacia; no debia tocarse"
    }
}

Write-Host "`nOK: las tres carpetas legacy siguen ahi y opencode/git no quedaron vacias."
