#Requires -Version 7.2
<#
.SYNOPSIS
    Firma Authenticode de todos los artefactos del módulo PurviewAssessment.
.DESCRIPTION
    Firma .psd1, .psm1 y .ps1 (excepto Tests/ y build/) con un certificado
    de firma de código, incluyendo sello de tiempo (timestamp) para que la
    firma siga siendo válida tras la expiración del certificado.

    Origen del certificado (en orden de preferencia para generar confianza
    en clientes):
      1. Certificado comercial de Code Signing (DigiCert, Sectigo, GlobalSign):
         confiado por defecto en cualquier equipo Windows. Recomendado para
         distribución a clientes.
      2. Certificado emitido por la CA interna de la organización: válido
         dentro del dominio corporativo / equipos que confían en esa CA.
      3. Certificado autofirmado: SOLO para laboratorio y pruebas de la
         cadena de firma (los clientes verían "UnknownError" salvo que
         importen el certificado manualmente).

    Nota sobre plataformas: Set-AuthenticodeSignature requiere Windows.
    Este script debe ejecutarse en un equipo/agente Windows con PS 7.2+.
.PARAMETER ModulePath
    Raíz del módulo. Por defecto: carpeta padre de build/.
.PARAMETER Thumbprint
    Huella del certificado en Cert:\CurrentUser\My (o LocalMachine\My).
    Alternativa a -PfxPath.
.PARAMETER PfxPath
    Ruta a un archivo .pfx con la clave privada. Solicita la contraseña
    de forma segura.
.PARAMETER TimestampServer
    Servidor de sellado de tiempo RFC 3161. Por defecto: DigiCert.
.EXAMPLE
    # Con certificado del almacén personal
    .\Invoke-Sign.ps1 -Thumbprint 'A1B2C3D4E5F6...'
.EXAMPLE
    # Con archivo PFX
    .\Invoke-Sign.ps1 -PfxPath 'C:\certs\codesign.pfx'
.EXAMPLE
    # Certificado autofirmado de LABORATORIO (una sola vez):
    # $cert = New-SelfSignedCertificate -Subject 'CN=PurviewAssessment Lab' `
    #     -Type CodeSigningCert -CertStoreLocation Cert:\CurrentUser\My
    # .\Invoke-Sign.ps1 -Thumbprint $cert.Thumbprint
#>
[CmdletBinding(DefaultParameterSetName = 'Store')]
param(
    [Parameter()]
    [string]$ModulePath = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory, ParameterSetName = 'Store')]
    [string]$Thumbprint,

    [Parameter(Mandatory, ParameterSetName = 'Pfx')]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$PfxPath,

    [Parameter()]
    [string]$TimestampServer = 'http://timestamp.digicert.com'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
    throw 'La firma Authenticode (Set-AuthenticodeSignature) requiere Windows. Ejecute este script en un equipo o agente de build Windows.'
}

# ── Obtener certificado ───────────────────────────────────────────────────────
$cert = if ($PSCmdlet.ParameterSetName -eq 'Pfx') {
    $pwd = Read-Host -Prompt 'Contraseña del PFX' -AsSecureString
    [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($PfxPath, $pwd)
}
else {
    Get-ChildItem -Path Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object Thumbprint -eq $Thumbprint |
        Select-Object -First 1
}

if (-not $cert) { throw "No se encontró el certificado (huella: $Thumbprint)." }
if (-not $cert.HasPrivateKey) { throw 'El certificado no incluye la clave privada; no puede firmar.' }
if ($cert.NotAfter -lt (Get-Date)) { throw "El certificado expiró el $($cert.NotAfter)." }
if ($cert.EnhancedKeyUsageList.ObjectId -notcontains '1.3.6.1.5.5.7.3.3') {
    throw 'El certificado no tiene el EKU de Code Signing (1.3.6.1.5.5.7.3.3).'
}

Write-Host "Certificado: $($cert.Subject) (expira: $($cert.NotAfter.ToString('yyyy-MM-dd')))" -ForegroundColor Cyan

# ── Gate previo: nunca firmar un módulo que viole el invariante ──────────────
Write-Host 'Ejecutando gate de solo lectura antes de firmar...' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Invoke-ReadOnlyGate.ps1') -ModulePath $ModulePath
if ($LASTEXITCODE -ne 0) { throw 'Gate de solo lectura fallido: NO se firma el módulo.' }

# ── Firmar artefactos ─────────────────────────────────────────────────────────
$targets = Get-ChildItem -Path $ModulePath -Recurse -Include '*.ps1', '*.psm1', '*.psd1' -File |
    Where-Object { $_.FullName -notmatch '[\\/](Tests|build)[\\/]' }

$results = foreach ($file in $targets) {
    $sig = Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $cert `
        -TimestampServer $TimestampServer -HashAlgorithm SHA256
    [pscustomobject]@{
        Archivo = $file.FullName.Replace($ModulePath, '.')
        Estado  = $sig.Status
    }
}

$results | Format-Table -AutoSize

$failed = @($results | Where-Object Estado -ne 'Valid')
if ($failed.Count -gt 0) {
    throw "Firma fallida en $($failed.Count) archivo(s)."
}

Write-Host "Firmados $($results.Count) archivos con sello de tiempo ($TimestampServer)." -ForegroundColor Green
Write-Host 'Verificación posterior sugerida: Get-AuthenticodeSignature -FilePath <archivo> | Format-List' -ForegroundColor Cyan
