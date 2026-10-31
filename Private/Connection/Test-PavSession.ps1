function Test-PavSession {
<#
.SYNOPSIS
    Verifica si existe una sesión de Security & Compliance PowerShell activa.
.DESCRIPTION
    CRÍTICO — patrón heredado (y documentado) de Export-DLPPolicies.ps1:
    la verificación se hace comprobando el REGISTRO de cmdlets con
    Get-Command, NUNCA invocando cmdlets de datos. Con sesiones REST de
    ExchangeOnlineManagement v3+, cerrar el pipeline de un cmdlet de datos
    (p. ej. '... | Select-Object -First 1') deja la conexión en estado
    inconsistente y la siguiente llamada se cuelga indefinidamente.

    Se comprueban varios cmdlets porque el conjunto importado depende del
    rol RBAC de la cuenta conectada (una cuenta con solo
    'View-Only DLP Compliance Management' no recibe Get-Label, etc.).
.OUTPUTS
    [bool]
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $probeCmdlets = @(
        'Get-DlpCompliancePolicy'
        'Get-Label'
        'Get-RetentionCompliancePolicy'
        'Get-InsiderRiskPolicy'
        'Get-SupervisoryReviewPolicyV2'
    )

    foreach ($cmdlet in $probeCmdlets) {
        if (Get-Command -Name $cmdlet -ErrorAction SilentlyContinue) {
            Write-Verbose "Sesión IPPS detectada (cmdlet registrado: $cmdlet)."
            return $true
        }
    }

    Write-Verbose 'No se detectó sesión IPPS activa.'
    return $false
}
