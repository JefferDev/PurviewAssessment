function Test-PurviewAssessmentConnection {
<#
.SYNOPSIS
    Devuelve el estado actual de la conexión del módulo con
    Security & Compliance PowerShell.
.DESCRIPTION
    Combina el contexto interno del módulo con una verificación en vivo
    de la sesión (Test-PavSession). Si el contexto indicaba conexión pero
    la sesión ya no existe (expiración, cierre externo), sincroniza el
    contexto y lo refleja en la salida.
.PARAMETER Quiet
    Devuelve únicamente [bool] en lugar del objeto de estado.
.OUTPUTS
    [pscustomobject] con Connected, Upn, Organization, ConnectedAt,
    SessionAlive — o [bool] con -Quiet.
.EXAMPLE
    Test-PurviewAssessmentConnection

    Connected Upn                    Organization             ConnectedAt         SessionAlive
    --------- ---                    ------------             -----------         ------------
         True consultor@ejemplo.com  sutenant.onmicrosoft.com  08/07/2026 10:15:03         True
.EXAMPLE
    if (-not (Test-PurviewAssessmentConnection -Quiet)) { Connect-PurviewAssessment }
#>
    [CmdletBinding()]
    [OutputType([pscustomobject], [bool])]
    param(
        [switch]$Quiet
    )

    $alive = Test-PavSession

    if ($script:PavContext.Connected -and -not $alive) {
        Write-PavLog -Level Warn -Message 'La sesión registrada ya no está activa (expirada o cerrada externamente).'
        $script:PavContext.Connected = $false
    }

    if ($Quiet) {
        return [bool]($script:PavContext.Connected -and $alive)
    }

    [pscustomobject]@{
        PSTypeName   = 'PurviewAssessment.ConnectionStatus'
        Connected    = $script:PavContext.Connected
        Upn          = $script:PavContext.Upn
        Organization = $script:PavContext.Organization
        ConnectedAt  = $script:PavContext.ConnectedAt
        SessionAlive = $alive
    }
}
