function Invoke-PavRetry {
<#
.SYNOPSIS
    Ejecuta un scriptblock con reintentos y backoff exponencial ante
    errores transitorios de Security & Compliance PowerShell.
.DESCRIPTION
    Generaliza Invoke-WithRetry (presente solo en Export-DLPPolicies.ps1)
    para todo el módulo. Reintenta únicamente ante patrones transitorios
    conocidos (throttling, timeouts, cierres de conexión REST); cualquier
    otro error se propaga de inmediato — reintentar un error de permisos
    solo retrasa el diagnóstico.
.PARAMETER ScriptBlock
    Operación a ejecutar (normalmente un cmdlet Get-* de Purview).
.PARAMETER OperationName
    Nombre descriptivo para los mensajes de log.
.PARAMETER MaxAttempts
    Intentos totales. Por defecto: 3.
.PARAMETER InitialDelaySeconds
    Espera antes del primer reintento; se duplica en cada intento. Por defecto: 5.
.EXAMPLE
    $policies = Invoke-PavRetry -OperationName 'Get-DlpCompliancePolicy' -ScriptBlock {
        Get-DlpCompliancePolicy -ErrorAction Stop
    }
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory)]
        [string]$OperationName,

        [ValidateRange(1, 10)]
        [int]$MaxAttempts = 3,

        [ValidateRange(1, 300)]
        [int]$InitialDelaySeconds = 5
    )

    # Patrones de error transitorio observados en EXO v3 / IPPS REST
    $transientPatterns = @(
        'Micro delay applied'
        'server is busy'
        'too many requests'
        '429'
        'timed?\s*out'
        'connection was closed'
        'temporarily unavailable'
        '503'
    ) -join '|'

    $delay = $InitialDelaySeconds

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $ScriptBlock
        }
        catch {
            $msg = $_.Exception.Message
            $isTransient = $msg -match $transientPatterns

            if (-not $isTransient -or $attempt -eq $MaxAttempts) {
                if ($isTransient) {
                    Write-PavLog -Level Error -Message "'$OperationName' agotó $MaxAttempts intentos (error transitorio persistente)."
                }
                throw
            }

            Write-PavLog -Level Warn -Message "'$OperationName' falló con error transitorio (intento $attempt de $MaxAttempts). Reintentando en $delay s... [$msg]"
            Start-Sleep -Seconds $delay
            $delay *= 2
        }
    }
}
