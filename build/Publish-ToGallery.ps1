#Requires -Version 7.2
<#
.SYNOPSIS
    Publica el módulo PurviewAssessment en la Galería de PowerShell
    (pública) o en un repositorio privado registrado (GitHub Packages,
    Azure Artifacts, carpeta compartida).
.DESCRIPTION
    1. Ejecuta el gate de solo lectura (se niega a publicar si falla).
    2. Valida el manifiesto.
    3. Hace staging SOLO de los archivos de runtime (excluye Tests/,
       build/, .github/ — la Galería empaqueta la carpeta completa).
    4. Publica con Publish-PSResource (o Publish-Module si se indica
       -UseLegacyPublish).
.PARAMETER Repository
    Nombre del repositorio destino registrado en la máquina.
    'PSGallery' (pública, por defecto) o el nombre de un repo privado
    registrado con Register-PSResourceRepository.
.PARAMETER ApiKey
    API key del repositorio. Para GitHub Packages usar un PAT con scope
    write:packages; para PSGallery la clave de powershellgallery.com.
.PARAMETER UseLegacyPublish
    Usa Publish-Module (PowerShellGet v2) en lugar de Publish-PSResource.
.EXAMPLE
    # Galería pública
    ./build/Publish-ToGallery.ps1 -ApiKey $env:PSGALLERY_KEY
.EXAMPLE
    # Feed privado de GitHub Packages (registrado como 'GHPrivado')
    ./build/Publish-ToGallery.ps1 -Repository GHPrivado -ApiKey $env:GH_PAT
#>
[CmdletBinding()]
param(
    [Parameter()][string]$Repository = 'PSGallery',
    [Parameter(Mandatory)][string]$ApiKey,
    [switch]$UseLegacyPublish
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$moduleRoot = Split-Path -Parent $PSScriptRoot

# ── 1. Gate de solo lectura: nunca publicar un build que lo viole ────────────
Write-Host 'Ejecutando gate de solo lectura...' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Invoke-ReadOnlyGate.ps1') -ModulePath $moduleRoot
if ($LASTEXITCODE -ne 0) { throw 'Gate de solo lectura fallido: publicación cancelada.' }

# ── 2. Manifiesto válido ──────────────────────────────────────────────────────
$manifest = Test-ModuleManifest -Path (Join-Path $moduleRoot 'PurviewAssessment.psd1')
Write-Host "Publicando PurviewAssessment v$($manifest.Version) → repositorio '$Repository'" -ForegroundColor Cyan

# ── 3. Staging de runtime (sin Tests/build/.github) ──────────────────────────
$stage = Join-Path ([IO.Path]::GetTempPath()) 'PavPublish/PurviewAssessment'
if (Test-Path (Split-Path $stage)) { Remove-Item (Split-Path $stage) -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$runtimeItems = @('PurviewAssessment.psd1', 'PurviewAssessment.psm1', 'README.md', 'CHANGELOG.md', 'LICENSE', 'Public', 'Private', 'Assets')
foreach ($item in $runtimeItems) {
    $src = Join-Path $moduleRoot $item
    if (Test-Path $src) { Copy-Item $src -Destination $stage -Recurse }
    else { Write-Warning "Elemento de runtime no encontrado (omitido): $item" }
}
# Excluir README de Assets (placeholder interno)
Remove-Item (Join-Path $stage 'Assets/README.md') -ErrorAction SilentlyContinue
Write-Host "Staging: $stage ($(@(Get-ChildItem $stage -Recurse -File).Count) archivos)" -ForegroundColor Cyan

# ── 4. Publicar ───────────────────────────────────────────────────────────────
if ($UseLegacyPublish) {
    Publish-Module -Path $stage -Repository $Repository -NuGetApiKey $ApiKey -Verbose
}
else {
    if (-not (Get-Command Publish-PSResource -ErrorAction SilentlyContinue)) {
        throw "Publish-PSResource no disponible. Instale: Install-Module Microsoft.PowerShell.PSResourceGet — o use -UseLegacyPublish."
    }
    Publish-PSResource -Path $stage -Repository $Repository -ApiKey $ApiKey -Verbose
}

Write-Host "Publicado PurviewAssessment v$($manifest.Version) en '$Repository'." -ForegroundColor Green
if ($Repository -eq 'PSGallery') {
    Write-Host 'Nota: la indexación pública tarda ~15 minutos. Las versiones no se pueden borrar, solo des-listar.' -ForegroundColor Yellow
}
