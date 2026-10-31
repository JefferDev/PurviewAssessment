# Helpers de auditoría — Get-UnifiedAuditLogRetentionPolicy y estado del
# registro de auditoría unificada. Propiedades tomadas de salida real.

function ConvertTo-PavAuditDuration {
<#
.SYNOPSIS
    Traduce el valor de RetentionDuration a texto legible.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][string]$Duration)
    switch ("$Duration") {
        'ThreeMonths'  { '3 meses (90 días)' }
        'SixMonths'    { '6 meses' }
        'NineMonths'   { '9 meses' }
        'TwelveMonths' { '12 meses (1 año)' }
        'TenYears'     { '10 años' }
        ''             { 'No definida' }
        default        { $Duration }
    }
}

function Get-PavAuditDurationDays {
<#
.SYNOPSIS
    Convierte RetentionDuration a días aproximados, para comparaciones.
#>
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Position = 0)][AllowNull()][string]$Duration)
    switch ("$Duration") {
        'ThreeMonths'  { 90 }
        'SixMonths'    { 180 }
        'NineMonths'   { 270 }
        'TwelveMonths' { 365 }
        'TenYears'     { 3650 }
        default        { 0 }
    }
}

function ConvertFrom-PavAuditRetentionPolicy {
<#
.SYNOPSIS
    Normaliza una directiva de retención del registro de auditoría.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.AuditRetentionPolicy'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory, Position = 0)][object]$Policy)

    $recTypes = @(@(Get-PavProp $Policy 'RecordTypes' @()) | ForEach-Object { "$_" } | Where-Object { $_ })
    $ops      = @(@(Get-PavProp $Policy 'Operations'  @()) | ForEach-Object { "$_" } | Where-Object { $_ })
    $users    = @(@(Get-PavProp $Policy 'UserIds'     @()) | ForEach-Object { "$_" } | Where-Object { $_ })
    $dur      = [string](Get-PavProp $Policy 'RetentionDuration' '')

    [pscustomobject]@{
        PSTypeName        = 'PurviewAssessment.AuditRetentionPolicy'
        Name              = [string](Get-PavProp $Policy 'Name' '')
        Description       = [string](Get-PavProp $Policy 'Description' (Get-PavProp $Policy 'Comment' ''))
        Enabled           = Get-PavProp $Policy 'Enabled' $true
        Priority          = Get-PavProp $Policy 'Priority'
        RetentionDuration = ConvertTo-PavAuditDuration $dur
        RetentionRaw      = $dur
        RetentionDays     = Get-PavAuditDurationDays $dur
        RecordTypes       = ($recTypes -join ', ')
        RecordTypeCount   = $recTypes.Count
        Operations        = ($ops -join ', ')
        OperationCount    = $ops.Count
        UserIds           = ($users -join '; ')
        UserCount         = $users.Count
        # Sin ámbito declarado, la directiva aplica a todos los registros
        AppliesToAll      = (($recTypes.Count + $ops.Count + $users.Count) -eq 0)
        Mode              = [string](Get-PavProp $Policy 'Mode' '')
        Workload          = [string](Get-PavProp $Policy 'Workload' '')
        Type              = [string](Get-PavProp $Policy 'Type' '')
        DistributionStatus     = [string](Get-PavProp $Policy 'DistributionStatus' '')
        DistributionSyncStatus = [string](Get-PavProp $Policy 'DistributionSyncStatus' '')
        LastStatusUpdateTime   = Get-PavProp $Policy 'LastStatusUpdateTime'
        ReadOnly          = Get-PavProp $Policy 'ReadOnly' $false
        IsValid           = Get-PavProp $Policy 'IsValid' $true
        CreatedBy         = [string](Get-PavProp $Policy 'CreatedBy' '')
        LastModifiedBy    = [string](Get-PavProp $Policy 'LastModifiedBy' '')
        CreatedUtc        = Get-PavProp $Policy 'CreationTimeUtc' (Get-PavProp $Policy 'WhenCreatedUTC')
        LastModifiedUtc   = Get-PavProp $Policy 'ModificationTimeUtc' (Get-PavProp $Policy 'WhenChangedUTC')
        Guid              = [string](Get-PavProp $Policy 'Guid' '')
    }
}

function Get-PavAuditFindings {
<#
.SYNOPSIS
    Deriva hallazgos de gobierno sobre la configuración de auditoría.
.PARAMETER Policies
    Directivas de retención normalizadas.
.PARAMETER Status
    Objeto de estado de la auditoría (ingesta, buzones, confiabilidad).
.OUTPUTS
    [pscustomobject[]] con Severity, Area, Finding, Detail.
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter()][object[]]$Policies = @(),
        [Parameter()][object]$Status
    )

    $out = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($sev, $area, $finding, $detail)
        $out.Add([pscustomobject]@{
            PSTypeName = 'PurviewAssessment.AuditFinding'
            Severity = $sev; Area = $area; Finding = $finding; Detail = $detail
        })
    }
    $pols = @($Policies)

    # 1. Estado de la auditoría unificada
    if ($Status) {
        switch ("$($Status.UnifiedAuditLogIngestion)") {
            'Deshabilitada' {
                & $add 'Alta' 'Estado' 'Auditoría unificada deshabilitada' 'Sin ingesta de registros no existe evidencia de actividad de usuarios ni administradores: ninguna directiva de retención tiene efecto.'
            }
            'No determinable' {
                & $add 'Informativa' 'Estado' 'Estado de ingesta no verificable' 'La sesión de cumplimiento devuelve siempre False para UnifiedAuditLogIngestionEnabled. Debe verificarse con Connect-ExchangeOnline: Get-AdminAuditLogConfig | Format-List UnifiedAuditLogIngestionEnabled.'
            }
        }
        if ("$($Status.MailboxAuditing)" -eq 'Deshabilitada') {
            & $add 'Alta' 'Estado' 'Auditoría de buzones deshabilitada' 'AuditDisabled está en True a nivel de organización: no se registran acciones sobre buzones aunque la auditoría unificada esté activa.'
        }
    }

    # 2. Sin directivas personalizadas: todo cae en la retención por defecto
    if ($pols.Count -eq 0) {
        & $add 'Media' 'Retención' 'Sin directivas de retención personalizadas' 'Todos los registros de auditoría se conservan durante el periodo por defecto del plan (90 días en E3; 180 días en E5), sin diferenciación por tipo de registro ni por usuario.'
        return @($out)
    }

    # 3. Cobertura parcial: qué queda fuera de las directivas definidas
    $covered = @($pols | Where-Object { -not $_.AppliesToAll })
    if ($covered.Count -eq $pols.Count) {
        $tipos = @($pols | ForEach-Object { $_.RecordTypes -split ',\s*' } | Where-Object { $_ } | Sort-Object -Unique)
        & $add 'Media' 'Cobertura' 'Retención acotada a tipos de registro específicos' "Las directivas cubren únicamente: $($tipos -join ', '). El resto de la actividad conserva la retención por defecto del plan."
    }

    foreach ($p in $pols) {
        # 4. Directivas deshabilitadas
        if ("$($p.Enabled)" -eq 'False') {
            & $add 'Alta' 'Retención' 'Directiva deshabilitada' "La directiva '$($p.Name)' está deshabilitada: los registros de su ámbito no reciben la retención declarada."
        }
        # 5. Distribución pendiente o fallida
        if ("$($p.DistributionStatus)" -in @('Pending', 'Failed', 'Error')) {
            $sev = if ("$($p.DistributionStatus)" -eq 'Pending') { 'Informativa' } else { 'Alta' }
            & $add $sev 'Distribución' "Distribución en estado $($p.DistributionStatus)" "La directiva '$($p.Name)' aún no se ha propagado por completo al servicio."
        }
        # 6. Retención mínima
        if ($p.RetentionDays -gt 0 -and $p.RetentionDays -le 90) {
            & $add 'Media' 'Retención' 'Retención igual o inferior a 90 días' "La directiva '$($p.Name)' conserva sus registros $($p.RetentionDuration), que no supera la retención por defecto: conviene revisar si aporta valor o si debe extenderse."
        }
        # 7. Directiva sin ámbito: aplica a todo
        if ($p.AppliesToAll) {
            & $add 'Informativa' 'Cobertura' 'Directiva sin ámbito declarado' "La directiva '$($p.Name)' no acota tipos de registro, operaciones ni usuarios, por lo que aplica a toda la actividad auditada."
        }
    }

    # 8. Prioridades duplicadas: el desempate no es determinista para el consultor
    foreach ($grp in @($pols | Group-Object Priority | Where-Object Count -gt 1)) {
        & $add 'Media' 'Retención' 'Prioridad duplicada' "Las directivas $((@($grp.Group | ForEach-Object { "'$($_.Name)'" })) -join ', ') comparten la prioridad $($grp.Name); cuando un registro coincide con varias, el resultado depende del desempate del servicio."
    }

    return @($out)
}
