function Connect-PurviewAssessment {
<#
.SYNOPSIS
    Establece (o reutiliza) la sesión de Security & Compliance PowerShell
    para el assessment de Microsoft Purview.
.DESCRIPTION
    Envuelve Connect-IPPSSession con:
      - Validación de ExchangeOnlineManagement >= 3.2.0 (versiones
        anteriores presentan fallos de parsing REST: "Unexpected character '<'").
      - Detección de sesión existente mediante Get-Command, sin invocar
        cmdlets de datos (evita el cuelgue del pipeline REST en EXO v3+).
      - Diagnóstico en español de errores comunes de autenticación
        (MFA, Acceso Condicional, proxy, permisos).
      - Registro del contexto en el estado del módulo, compartido por
        todos los colectores y exportadores.

    GARANTÍA DE SOLO LECTURA: esta función y el resto del módulo no
    realizan ninguna operación de escritura sobre el tenant. Se recomienda
    ejecutar el assessment con una cuenta de rol Global Reader o del grupo
    de roles View-Only Compliance, de forma que los propios permisos de la
    cuenta sean de lectura.
.PARAMETER IncludeExchangeOnline
    Establece también la sesión de Exchange Online, necesaria para verificar
    el estado del registro de auditoría unificada (UnifiedAuditLogIngestionEnabled)
    y de la auditoría de buzones (AuditDisabled), que la sesión de cumplimiento
    no expone de forma concluyente.
.PARAMETER UserPrincipalName
    UPN de la cuenta con la que se autentica la sesión.
.PARAMETER Organization
    Dominio del tenant (p. ej. sutenant.onmicrosoft.com). Opcional.
.PARAMETER Force
    Fuerza la reconexión aunque exista una sesión activa.
.OUTPUTS
    Ninguno. El estado queda en el contexto del módulo
    (consultable con Test-PurviewAssessmentConnection).
.EXAMPLE
    Connect-PurviewAssessment -UserPrincipalName consultor@ejemplo.com
.EXAMPLE
    Connect-PurviewAssessment -UserPrincipalName consultor@ejemplo.com -Organization sutenant.onmicrosoft.com -Force
.NOTES
    Roles recomendados: Global Reader | View-Only Compliance
    (+ View-Only DLP Compliance Management / View-Only Retention Management
    según las cargas de trabajo a evaluar).
#>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
        [string]$UserPrincipalName,

        # Establece además la sesión de Exchange Online. Es necesaria para
        # verificar el estado real del registro de auditoría unificada y de la
        # auditoría de buzones: desde la sesión de cumplimiento esas
        # propiedades no son concluyentes.
        [switch]$IncludeExchangeOnline,

        [Parameter()]
        [string]$Organization,

        [switch]$Force
    )

    # Versión mínima de EXO definida en el manifiesto (PrivateData.PavMinExoVersion)
    $minExo = '3.2.0'
    try {
        $manifest = $MyInvocation.MyCommand.Module.PrivateData
        if ($manifest -and $manifest.ContainsKey('PavMinExoVersion')) {
            $minExo = $manifest['PavMinExoVersion']
        }
    }
    catch {
        Write-Verbose "No fue posible leer PavMinExoVersion del manifiesto; se usa el valor por defecto $minExo."
    }

    [void](Assert-PavModule -Name 'ExchangeOnlineManagement' -MinimumVersion $minExo)

    if (-not $Force -and (Test-PavSession)) {
        Write-PavLog -Level Success -Message 'Sesión IPPS activa reutilizada.'
        $script:PavContext.Connected = $true
        if (-not $script:PavContext.ConnectedAt) { $script:PavContext.ConnectedAt = Get-Date }
        if ($IncludeExchangeOnline) { [void](Connect-PavExchangeOnline -UserPrincipalName $UserPrincipalName -Organization $Organization) }
        return
    }

    if ($Force) {
        Write-PavLog -Level Info -Message 'Cerrando sesión previa (-Force)...'
        try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch { Write-Verbose $_.Exception.Message }
        $script:PavContext.Connected = $false
    }

    $params = @{ ErrorAction = 'Stop'; ShowBanner = $false }
    if ($UserPrincipalName) {
        $params['UserPrincipalName'] = $UserPrincipalName
        Write-PavLog -Level Info -Message "UPN para autenticación: $UserPrincipalName"
    }
    if ($Organization) {
        $params['Organization'] = $Organization
    }

    Write-PavLog -Level Info -Message 'Conectando a Security & Compliance PowerShell (se abrirá el navegador para autenticación)...'
    try {
        Connect-IPPSSession @params
    }
    catch {
        $msg  = $_.Exception.Message
        $hint = switch -Regex ($msg) {
            "Unexpected character.*<"  { "Módulo desactualizado o proxy interceptando TLS. Se requiere ExchangeOnlineManagement >= $minExo." }
            'AADSTS50076|AADSTS50079'  { 'MFA requerido: debe completarse la verificación en el navegador.' }
            'AADSTS53003'              { 'Bloqueado por directiva de Acceso Condicional del tenant.' }
            'AADSTS'                   { 'Error de Entra ID. Debe verificarse el estado de la cuenta y el rol asignado.' }
            'Conditional'              { 'Bloqueado por directiva de Acceso Condicional del tenant.' }
            'connection was closed'    { 'Conexión cerrada. Debe verificarse el acceso saliente a *.protection.outlook.com:443.' }
            default                    { "Requisitos: PowerShell 7.2+, ExchangeOnlineManagement >= $minExo, rol de solo lectura de cumplimiento." }
        }
        throw "No se pudo establecer la sesión con Purview: $msg`n  -> $hint"
    }

    if (-not (Test-PavSession)) {
        throw "La sesión se estableció pero los cmdlets de Purview no están registrados. Debe verificarse el rol de la cuenta (p. ej. Global Reader o View-Only Compliance)."
    }

    if ($IncludeExchangeOnline) { [void](Connect-PavExchangeOnline -UserPrincipalName $UserPrincipalName -Organization $Organization) }

    $script:PavContext.Connected    = $true
    $script:PavContext.Upn          = $UserPrincipalName
    $script:PavContext.Organization = $Organization
    $script:PavContext.ConnectedAt  = Get-Date

    Write-PavLog -Level Success -Message 'Conectado a Security & Compliance PowerShell.'
}
