#Requires -Version 7.2
<#
.SYNOPSIS
    Instala el modulo PurviewAssessment desde las Releases del repositorio en GitHub.

.DESCRIPTION
    Descarga el paquete publicado en GitHub Releases, verifica su huella SHA256
    contra el archivo .sha256 de la misma Release y lo despliega en la ruta de
    modulos del usuario, con la version como subcarpeta. Al convivir varias
    versiones, PowerShell carga la mas alta salvo que se indique otra con
    Import-Module -RequiredVersion.

    No requiere privilegios de administrador y no modifica rutas del sistema.

.PARAMETER Version
    Version concreta a instalar (por ejemplo 1.10.7). Si se omite, instala la
    ultima Release publicada.

.PARAMETER Scope
    CurrentUser (predeterminado) o AllUsers. AllUsers exige consola elevada.

.PARAMETER Force
    Reinstala la version aunque ya este presente.

.EXAMPLE
    irm https://raw.githubusercontent.com/jefferdev/PurviewAssessment/main/Install-PurviewAssessment.ps1 | iex

.EXAMPLE
    .\Install-PurviewAssessment.ps1 -Version 1.10.7 -Force
#>
[CmdletBinding()]
param(
    [string] $Version,

    [ValidateSet('CurrentUser', 'AllUsers')]
    [string] $Scope = 'CurrentUser',

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo       = 'jefferdev/PurviewAssessment'
$moduleName = 'PurviewAssessment'

function Write-Paso { param([string] $Texto) Write-Host "  $Texto" -ForegroundColor Cyan }

try {
    # --- 1. Resolver la Release -------------------------------------------------
    $api = if ($Version) {
        "https://api.github.com/repos/$repo/releases/tags/v$Version"
    } else {
        "https://api.github.com/repos/$repo/releases/latest"
    }

    Write-Paso 'Consultando la Release en GitHub...'
    $cabeceras = @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent' = 'PurviewAssessment-Installer' }
    if ($env:GITHUB_TOKEN) { $cabeceras['Authorization'] = "Bearer $env:GITHUB_TOKEN" }

    $release = Invoke-RestMethod -Uri $api -Headers $cabeceras
    $ver     = $release.tag_name -replace '^v', ''

    $activos = @($release.assets)
    $zipAsset  = $activos | Where-Object { $_.name -like "$moduleName-*.zip" } | Select-Object -First 1
    $hashAsset = $activos | Where-Object { $_.name -like "$moduleName-*.zip.sha256" } | Select-Object -First 1

    if (-not $zipAsset) { throw "La Release v$ver no publica un paquete .zip del modulo." }

    # --- 2. Comprobar si ya esta instalada --------------------------------------
    $raizModulos = if ($Scope -eq 'AllUsers') {
        if ($IsWindows) { Join-Path $env:ProgramFiles 'PowerShell/Modules' } else { '/usr/local/share/powershell/Modules' }
    } else {
        @($env:PSModulePath -split [IO.Path]::PathSeparator)[0]
    }

    $destino = Join-Path $raizModulos "$moduleName/$ver"

    if ((Test-Path $destino) -and -not $Force) {
        Write-Host "$moduleName $ver ya esta instalado en $destino" -ForegroundColor Yellow
        Write-Host 'Use -Force para reinstalarlo.'
        return
    }

    # --- 3. Descargar y verificar ------------------------------------------------
    $temporal = Join-Path ([IO.Path]::GetTempPath()) ("pav-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporal -Force | Out-Null

    try {
        $zipLocal = Join-Path $temporal $zipAsset.name
        Write-Paso "Descargando $($zipAsset.name) ($([math]::Round($zipAsset.size / 1KB)) KB)..."
        Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipLocal -Headers $cabeceras

        if ($hashAsset) {
            Write-Paso 'Verificando la huella SHA256...'
            $esperado = ((Invoke-RestMethod -Uri $hashAsset.browser_download_url -Headers $cabeceras) -split '\s+')[0]
            $obtenido = (Get-FileHash $zipLocal -Algorithm SHA256).Hash
            if ($obtenido -ne $esperado.Trim()) {
                throw "La huella no coincide. Esperada: $esperado. Obtenida: $obtenido. No se instala."
            }
        } else {
            Write-Warning 'La Release no publica archivo .sha256; se omite la verificacion de integridad.'
        }

        # --- 4. Desplegar --------------------------------------------------------
        Write-Paso 'Extrayendo el paquete...'
        $extraido = Join-Path $temporal 'x'
        Expand-Archive -Path $zipLocal -DestinationPath $extraido -Force

        # El zip contiene PurviewAssessment/<ver>/...  o bien  PurviewAssessment/...
        $manifiesto = Get-ChildItem -Path $extraido -Recurse -Filter "$moduleName.psd1" |
                      Select-Object -First 1
        if (-not $manifiesto) { throw 'El paquete descargado no contiene el manifiesto del modulo.' }

        $origen = $manifiesto.Directory.FullName

        if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
        New-Item -ItemType Directory -Path $destino -Force | Out-Null
        Copy-Item -Path (Join-Path $origen '*') -Destination $destino -Recurse -Force

        # --- 5. Dependencias -----------------------------------------------------
        $requeridos = @(
            @{ Nombre = 'ExchangeOnlineManagement'; Minima = '3.4.0' }
            @{ Nombre = 'ImportExcel';              Minima = '7.8.0' }
        )
        foreach ($d in $requeridos) {
            $presente = Get-Module $d.Nombre -ListAvailable |
                        Where-Object { $_.Version -ge [version]$d.Minima }
            if ($presente) { continue }
            Write-Paso "Instalando dependencia $($d.Nombre)..."
            Install-Module $d.Nombre -MinimumVersion $d.Minima -Scope $Scope -Force -AllowClobber
        }

        # --- 6. Comprobacion final -----------------------------------------------
        Import-Module (Join-Path $destino "$moduleName.psd1") -Force
        $cargado = Get-Module $moduleName

        Write-Host ''
        Write-Host "$moduleName $($cargado.Version) instalado correctamente." -ForegroundColor Green
        Write-Host "Ruta:      $destino"
        Write-Host "Funciones: $(@($cargado.ExportedFunctions.Keys).Count)"
        Write-Host ''
        Write-Host 'Siguiente paso:' -ForegroundColor Cyan
        Write-Host '  Connect-PurviewAssessment -UserPrincipalName admin@sutenant.onmicrosoft.com'
        Write-Host '  Invoke-PurviewAssessment -Workload All -ClientName "Cliente" -OutputPath .\Informes'
    }
    finally {
        Remove-Item $temporal -Recurse -Force -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Host ''
    Write-Error "La instalacion fallo: $($_.Exception.Message)"
    Write-Host 'Si el repositorio es privado, exporte un token de lectura antes de ejecutar:' -ForegroundColor Yellow
    Write-Host '  $env:GITHUB_TOKEN = "ghp_..."'
    exit 1
}
