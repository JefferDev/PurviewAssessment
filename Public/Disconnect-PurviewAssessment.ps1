function Disconnect-PurviewAssessment {
<#
.SYNOPSIS
    Cierra la sesión de Security & Compliance PowerShell y limpia el
    contexto del módulo.
.DESCRIPTION
    Invoca Disconnect-ExchangeOnline sin confirmación interactiva y
    restablece el contexto interno. Es seguro invocarla aunque no exista
    sesión activa (idempotente).
.EXAMPLE
    Disconnect-PurviewAssessment
#>
    [CmdletBinding()]
    param()

    if (Get-Command -Name 'Disconnect-ExchangeOnline' -ErrorAction SilentlyContinue) {
        try {
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction Stop | Out-Null
            Write-PavLog -Level Success -Message 'Sesión de Security & Compliance PowerShell cerrada.'
        }
        catch {
            Write-PavLog -Level Warn -Message "No fue posible cerrar la sesión limpiamente: $($_.Exception.Message)"
        }
    }
    else {
        Write-PavLog -Level Info -Message 'No hay sesión que cerrar (ExchangeOnlineManagement no está cargado).'
    }

    $script:PavContext.Connected    = $false
    $script:PavContext.Upn          = $null
    $script:PavContext.Organization = $null
    $script:PavContext.ConnectedAt  = $null
}
