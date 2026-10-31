function Get-PurviewAuditData {
<#
.SYNOPSIS
    Recolecta la configuración de auditoría de Microsoft Purview
    (solo lectura): directivas de retención del registro de auditoría
    unificada y estado del registro.
.DESCRIPTION
    Cubre:
      - Directivas de retención del log de auditoría
        (Get-UnifiedAuditLogRetentionPolicy) con tipos de registro,
        operaciones, usuarios en ámbito, duración y prioridad.
      - Estado de la auditoría unificada y de la auditoría de buzones.
      - Hallazgos de gobierno derivados de lo anterior.

    ADVERTENCIA IMPORTANTE sobre el estado de ingesta: la propiedad
    UnifiedAuditLogIngestionEnabled devuelve SIEMPRE False cuando
    Get-AdminAuditLogConfig se ejecuta en una sesión de Security &
    Compliance (Connect-IPPSSession), incluso con la auditoría activa.
    Para no producir un hallazgo crítico falso, el colector comprueba si
    la sesión dispone además de Exchange Online (probando
    Get-OrganizationConfig):
      - Con Exchange Online disponible: se reporta el valor real.
      - Sin Exchange Online: se reporta 'No determinable' y se indica
        cómo verificarlo. Nunca se reporta 'Deshabilitada' por defecto.
.PARAMETER SkipFindings
    Omite el análisis de hallazgos de gobierno.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.AuditData' con
    RetentionPolicies, Status, Findings, CollectedAt.
.EXAMPLE
    Connect-PurviewAssessment
    (Get-PurviewAuditData).Findings | Where-Object Severity -eq 'Alta'
.EXAMPLE
    Get-PurviewAuditData | Export-PurviewAuditReport -OutputPath C:\Reports
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([switch]$SkipFindings)

    Assert-PavConnection
    Write-PavLog -Level Step -Message 'Recolectando configuración de auditoría...'

    # ── 1. Directivas de retención del registro de auditoría ─────────────────
    $policies = [System.Collections.Generic.List[object]]::new()
    if (Get-Command Get-UnifiedAuditLogRetentionPolicy -ErrorAction SilentlyContinue) {
        try {
            $raw = @(Invoke-PavRetry -OperationName 'Get-UnifiedAuditLogRetentionPolicy' -MaxAttempts 2 -ScriptBlock {
                Get-UnifiedAuditLogRetentionPolicy -ErrorAction Stop
            })
            $ix = 0
            foreach ($p in $raw) {
                if ($null -eq $p) { continue }
                $ix++
                Write-PavLog -Level Info -Message "  > [$ix/$($raw.Count)] Directiva: $(Get-PavProp $p 'Name' '(sin nombre)')"
                $policies.Add((ConvertFrom-PavAuditRetentionPolicy $p))
            }
            Write-PavLog -Level Success -Message "Directivas de retención de auditoría: $(@($policies).Count)"
        }
        catch { Write-PavLog -Level Warn -Message "Directivas de retención no recuperadas: $($_.Exception.Message)" }
    }
    else {
        Write-PavLog -Level Warn -Message 'Get-UnifiedAuditLogRetentionPolicy no disponible en esta sesión (requiere licencia de auditoría avanzada o rol adicional).'
    }

    # ── 2. Estado de la auditoría ────────────────────────────────────────────
    # Detección de sesión Exchange Online: sin ella, la propiedad de ingesta
    # no es fiable (siempre False desde la sesión de cumplimiento).
    # La sesión de Exchange Online se establece con prefijo propio para no
    # interferir con los cmdlets de cumplimiento; se prueba primero esa vía.
    $hasExo = $false
    $orgCfg = $null
    foreach ($cmd in 'Get-PavExoOrganizationConfig', 'Get-OrganizationConfig') {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { continue }
        try {
            $orgCfg = Invoke-PavRetry -OperationName $cmd -MaxAttempts 2 -ScriptBlock { & $cmd -ErrorAction Stop }
            if ($orgCfg) { $hasExo = $true; break }
        }
        catch { Write-Verbose "$cmd no accesible: $($_.Exception.Message)" }
    }
    if (-not $hasExo) { Write-PavLog -Level Info -Message 'Sin sesión de Exchange Online: el estado de ingesta no podrá verificarse.' }

    $ingestion   = 'No determinable'
    $adminAudit  = 'No determinable'
    $mailboxAud  = 'No determinable'
    $ingestNote  = 'La sesión de cumplimiento devuelve siempre False. Debe verificarse con Connect-ExchangeOnline: Get-AdminAuditLogConfig | Format-List UnifiedAuditLogIngestionEnabled'

    $cmdAudit = @('Get-PavExoAdminAuditLogConfig', 'Get-AdminAuditLogConfig') |
        Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if ($cmdAudit) {
        try {
            $cfg = Invoke-PavRetry -OperationName $cmdAudit -MaxAttempts 2 -ScriptBlock {
                & $cmdAudit -ErrorAction Stop
            }
            $adminRaw = Get-PavProp $cfg 'AdminAuditLogEnabled'
            if ($null -ne $adminRaw) { $adminAudit = if ([bool]$adminRaw) { 'Habilitada' } else { 'Deshabilitada' } }

            $ingRaw = Get-PavProp $cfg 'UnifiedAuditLogIngestionEnabled'
            if ($hasExo) {
                # Valor fiable: hay sesión de Exchange Online
                $ingestion  = if ([bool]$ingRaw) { 'Habilitada' } else { 'Deshabilitada' }
                $ingestNote = 'Valor verificado con sesión de Exchange Online disponible.'
            }
            elseif ([bool]$ingRaw) {
                # True nunca es un falso positivo: si dice True, está activa
                $ingestion  = 'Habilitada'
                $ingestNote = 'Valor afirmativo, fiable aun sin sesión de Exchange Online.'
            }
            else {
                # False sin Exchange Online NO es concluyente: no se reporta como deshabilitada
                Write-PavLog -Level Warn -Message 'Estado de ingesta de auditoría no verificable desde la sesión de cumplimiento (siempre devuelve False). Se marca como no determinable.'
            }
        }
        catch { Write-PavLog -Level Warn -Message "Configuración de auditoría no recuperada: $($_.Exception.Message)" }
    }

    if ($hasExo) {
        $audDisabled = Get-PavProp $orgCfg 'AuditDisabled'
        if ($null -ne $audDisabled) { $mailboxAud = if ([bool]$audDisabled) { 'Deshabilitada' } else { 'Habilitada' } }
    }

    $status = [pscustomobject]@{
        PSTypeName               = 'PurviewAssessment.AuditStatus'
        UnifiedAuditLogIngestion = $ingestion
        IngestionNote            = $ingestNote
        AdminAuditLog            = $adminAudit
        MailboxAuditing          = $mailboxAud
        ExchangeOnlineSession    = if ($hasExo) { 'Disponible' } else { 'No disponible' }
        RetentionPolicyCount     = @($policies).Count
    }
    Write-PavLog -Level Info -Message "  > Auditoría unificada: $ingestion | Buzones: $mailboxAud"

    # ── 3. Hallazgos ─────────────────────────────────────────────────────────
    $findings = @()
    if (-not $SkipFindings) {
        $findings = @(Get-PavAuditFindings -Policies @($policies) -Status $status)
        Write-PavLog -Level Info -Message "  > Hallazgos de gobierno: $($findings.Count)"
    }

    [pscustomobject]@{
        PSTypeName        = 'PurviewAssessment.AuditData'
        RetentionPolicies = @($policies)
        Status            = $status
        Findings          = @($findings)
        CollectedAt       = Get-Date
    }
}
