function Assert-PavConnection {
<#
.SYNOPSIS
    Exige una sesión de Security & Compliance PowerShell activa.
.DESCRIPTION
    Guard de entrada de todos los colectores (Get-Purview*Data) y de los
    Export-Purview*Report en línea. Por diseño, los colectores NO conectan
    implícitamente: la conexión implícita solo está permitida en
    Invoke-PurviewAssessment -Connect. Si no hay sesión, lanza un error
    accionable en español.
.EXAMPLE
    Assert-PavConnection
#>
    [CmdletBinding()]
    param()

    if ($script:PavContext.Connected -and (Test-PavSession)) {
        return
    }

    # La sesión pudo expirar aunque el contexto diga Connected
    if ($script:PavContext.Connected) {
        Write-PavLog -Level Warn -Message 'El contexto indicaba sesión activa pero los cmdlets ya no están registrados (sesión expirada o cerrada externamente).'
        $script:PavContext.Connected = $false
    }

    throw 'No hay sesión activa con Security & Compliance PowerShell. Debe ejecutarse primero: Connect-PurviewAssessment [-UserPrincipalName <upn>]'
}
