function Connect-PavExchangeOnline {
<#
.SYNOPSIS
    Establece o reutiliza la sesión de Exchange Online, necesaria para
    verificar el estado del registro de auditoría.
.DESCRIPTION
    Desde la sesión de cumplimiento, UnifiedAuditLogIngestionEnabled y
    AuditDisabled no son concluyentes. Esta función deja el contexto
    marcado para que los colectores sepan si el dato es fiable.
    Nunca lanza: si no puede conectar, registra el aviso y devuelve $false.
.OUTPUTS
    [bool] indica si la sesión está disponible.
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()][string]$UserPrincipalName,
        [Parameter()][string]$Organization
    )

    if (-not $script:PavContext.PSObject.Properties['ExchangeOnline']) {
        $script:PavContext | Add-Member -NotePropertyName ExchangeOnline -NotePropertyValue $false -Force
    }

    # Sesión ya disponible con prefijo propio: se reutiliza
    if (Get-Command Get-PavExoOrganizationConfig -ErrorAction SilentlyContinue) {
        try {
            Get-PavExoOrganizationConfig -ErrorAction Stop | Out-Null
            $script:PavContext.ExchangeOnline = $true
            Write-PavLog -Level Success -Message 'Sesión de Exchange Online disponible; se reutiliza.'
            return $true
        }
        catch { Write-Verbose 'Sesión con prefijo no activa.' }
    }
    # Sesión sin prefijo abierta por el usuario: se reutiliza sin reconectar
    if (Get-Command Get-OrganizationConfig -ErrorAction SilentlyContinue) {
        try {
            Get-OrganizationConfig -ErrorAction Stop | Out-Null
            $script:PavContext.ExchangeOnline = $true
            Write-PavLog -Level Success -Message 'Sesión de Exchange Online disponible; se reutiliza.'
            return $true
        }
        catch { Write-Verbose "Sesión de Exchange Online no activa: $($_.Exception.Message)" }
    }

    if (-not (Get-Command Connect-ExchangeOnline -ErrorAction SilentlyContinue)) {
        Write-PavLog -Level Warn -Message 'Connect-ExchangeOnline no disponible: el estado de auditoría no podrá verificarse.'
        $script:PavContext.ExchangeOnline = $false
        return $false
    }

    try {
        Write-PavLog -Level Step -Message 'Estableciendo sesión de Exchange Online...'
        # CRÍTICO: el prefijo evita que los cmdlets de Exchange Online se
        # sobrepongan a los de la sesión de cumplimiento. Sin él, cmdlets como
        # Get-SupervisoryReviewPolicyV2 resuelven contra la sesión equivocada y
        # devuelven objetos con otros identificadores, además de duplicar
        # resultados al haber dos sesiones activas.
        $p = @{ ShowBanner = $false; ErrorAction = 'Stop'; Prefix = 'PavExo' }
        if ($UserPrincipalName) { $p['UserPrincipalName'] = $UserPrincipalName }
        if ($Organization)      { $p['Organization'] = $Organization }
        Connect-ExchangeOnline @p
        $script:PavContext.ExchangeOnline = $true
        Write-PavLog -Level Success -Message 'Sesión de Exchange Online establecida.'
        return $true
    }
    catch {
        Write-PavLog -Level Warn -Message "No se pudo establecer la sesión de Exchange Online: $($_.Exception.Message). Los controles de auditoría quedarán como 'Requiere validación'."
        $script:PavContext.ExchangeOnline = $false
        return $false
    }
}
