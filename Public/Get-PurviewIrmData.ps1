function Get-PurviewIrmData {
<#
.SYNOPSIS
    Recolecta y parsea las directivas de Insider Risk Management
    (solo lectura). Port de Export-IRMPolicies.ps1.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.IrmData' con
    Policies, TriggerInsights, Indicators, ExtensibleIndicators,
    Health, CollectedAt.
.EXAMPLE
    (Get-PurviewIrmData).Health | Where-Object HealthStatus -ne 'Healthy'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Assert-PavConnection
    Write-PavLog -Level Step -Message 'Recolectando directivas de Insider Risk Management...'

    $raw = @(Invoke-PavRetry -OperationName 'Get-InsiderRiskPolicy' -ScriptBlock {
        Get-InsiderRiskPolicy -ErrorAction Stop
    })
    Write-PavLog -Level Info -Message "Directivas IRM: $($raw.Count)"

    $ixP = 0
    $policies = foreach ($pol in $raw) {
        $ixP++
        Write-PavLog -Level Info -Message "  > Directiva $ixP/$($raw.Count): $(Get-PavProp $pol 'Name' '(sin nombre)')"
        $healthJson = ConvertFrom-PavJson ([string](Get-PavProp $pol 'PolicyHealth' ''))
        [pscustomobject]@{
            PSTypeName          = 'PurviewAssessment.IrmPolicy'
            Name                = [string](Get-PavProp $pol 'Name' '')
            Guid                = [string](Get-PavProp $pol 'Guid' '')
            Enabled             = Get-PavProp $pol 'Enabled'
            Mode                = [string](Get-PavProp $pol 'Mode' '')
            Type                = [string](Get-PavProp $pol 'Type' '')
            Scenario            = [string](Get-PavProp $pol 'InsiderRiskScenario' '')
            PolicyCategory      = [string](Get-PavProp $pol 'PolicyCategory' '')
            Priority            = Get-PavProp $pol 'Priority'
            DistributionStatus  = [string](Get-PavProp $pol 'DistributionStatus' '')
            Workload            = [string](Get-PavProp $pol 'Workload' '')
            ExchangeLocation    = (@(Get-PavProp $pol 'ExchangeLocation' @()) | ForEach-Object { "$_" }) -join '; '
            InScopeTimeSpanDays   = Get-PavProp $pol 'InScopeTimeSpan'
            HistoricTimeSpanDays  = Get-PavProp $pol 'HistoricTimeSpan'
            FutureTerminationDays = Get-PavProp $pol 'FutureTerminationWindow'
            PastTerminationDays   = Get-PavProp $pol 'PastTerminationWindow'
            PostTerminationActivity = Get-PavProp $pol 'PostTerminationActivity'
            HasDlpPolicy        = (-not [string]::IsNullOrWhiteSpace([string](Get-PavProp $pol 'DlpPolicy' '')))
            IsCustom            = Get-PavProp $pol 'IsCustom'
            IsPriorityContentOnly = Get-PavProp $pol 'IsPriorityContentOnlyScoring'
            HealthStatus        = if ($healthJson) { [string](Get-PavProp $healthJson 'HealthStatus' 'Unknown') } else { 'Unknown' }
            SchemaVersion       = Get-PavProp $pol 'SchemaVersion'
            IsValid             = Get-PavProp $pol 'IsValid'
            CreatedBy           = [string](Get-PavProp $pol 'CreatedBy' '')
            LastModifiedBy      = [string](Get-PavProp $pol 'LastModifiedBy' '')
            CreatedUtc          = Get-PavProp $pol 'CreationTimeUtc'
            LastModifiedUtc     = Get-PavProp $pol 'ModificationTimeUtc'
        }
    }

    $insights = [System.Collections.Generic.List[object]]::new()
    $native   = [System.Collections.Generic.List[object]]::new()
    $ext      = [System.Collections.Generic.List[object]]::new()
    $health   = [System.Collections.Generic.List[object]]::new()
    foreach ($pol in $raw) {
        foreach ($i in (Expand-PavIrmTriggerInsights -Policy $pol)) { $insights.Add($i) }
        foreach ($i in (Expand-PavIrmIndicators -Policy $pol -IndicatorSet Native))     { $native.Add($i) }
        foreach ($i in (Expand-PavIrmIndicators -Policy $pol -IndicatorSet Extensible)) { $ext.Add($i) }
        $health.Add((Get-PavIrmHealthRow -Policy $pol))
    }

    [pscustomobject]@{
        PSTypeName           = 'PurviewAssessment.IrmData'
        Policies             = @($policies)
        TriggerInsights      = @($insights)
        Indicators           = @($native)
        ExtensibleIndicators = @($ext)
        Health               = @($health)
        CollectedAt          = Get-Date
    }
}
