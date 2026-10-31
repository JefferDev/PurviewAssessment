#Requires -Version 7.2
Set-StrictMode -Version Latest

# ══════════════════════════════════════════════════════════════════════════════
#  PurviewAssessment — cargador raíz
#  Módulo de assessment de SOLO LECTURA sobre Microsoft Purview.
#  Invariante del proyecto: ninguna función invoca cmdlets de escritura
#  contra el tenant (verificado por Tests/PurviewAssessment.ReadOnly.Tests.ps1
#  y build/Invoke-ReadOnlyGate.ps1).
# ══════════════════════════════════════════════════════════════════════════════

# ── Estado del módulo ─────────────────────────────────────────────────────────
# Contexto único de sesión, compartido por todas las funciones del módulo.
# Banderas de sesión leídas por colectores e informes. Se declaran aquí para
# que los colectores puedan invocarse de forma directa, sin el orquestador.
$script:PavSkipDistribution = $false
$script:PavHideInconclusive = $false
$script:PavDistribWarned    = $false

$script:PavContext = [pscustomobject]@{
    PSTypeName   = 'PurviewAssessment.Context'
    Connected    = $false
    Upn          = $null
    Organization = $null
    ConnectedAt  = $null
    ExchangeOnline    = $false
}

# Ruta de assets del motor de reporting (se puebla en Fase 2)
$script:PavAssetsPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assets'

# ── Carga de funciones (Private primero: Public depende de helpers) ──────────
$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue)
$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -File -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        throw "Error cargando la función '$($file.FullName)': $($_.Exception.Message)"
    }
}

# Exporta ÚNICAMENTE lo público. Defensa en profundidad junto con
# FunctionsToExport del manifiesto: cualquier helper privado queda inaccesible.
Export-ModuleMember -Function $public.BaseName

# ── Limpieza al descargar el módulo ───────────────────────────────────────────
$ExecutionContext.SessionState.Module.OnRemove = {
    if ($script:PavContext.Connected) {
        try {
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            Write-Verbose "OnRemove: no fue posible cerrar la sesión EXO: $($_.Exception.Message)"
        }
    }
}
