## ═══ Helpers IRM (port de Export-IRMPolicies.ps1) ════════════════════════════

function Expand-PavIrmTriggerInsights {
<#
.SYNOPSIS
    Expande TriggerInsightGroups (JSON) de una directiva IRM a filas
    planas. Port de Expand-TriggerInsights.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Policy)

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($groupRaw in @(Get-PavProp $Policy 'TriggerInsightGroups' @())) {
        $group = ConvertFrom-PavJson ([string]$groupRaw)
        if ($null -eq $group) { continue }
        foreach ($insight in @(Get-PavProp $group 'Insights' @())) {
            $thresholds = Get-PavProp $insight 'EventThresholds'
            $result.Add([pscustomobject]@{
                PolicyName       = [string](Get-PavProp $Policy 'Name' '')
                GroupName        = [string](Get-PavProp $group 'Name' '')
                InsightName      = [string](Get-PavProp $insight 'Name' '')
                Enabled          = Get-PavProp $insight 'Enabled'
                CustomThresholds = Get-PavProp $insight 'UseCustomThresholds'
                HasThresholds    = ($null -ne $thresholds -and "$thresholds" -ne '')
            })
        }
    }
    return $result
}

function Expand-PavIrmIndicators {
<#
.SYNOPSIS
    Expande Indicators (Native) o ExtensibleIndicators de una directiva
    IRM a filas planas con sub-indicadores. Port de Expand-Indicators.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Policy,
        [ValidateSet('Native', 'Extensible')][string]$IndicatorSet = 'Native'
    )

    $result = [System.Collections.Generic.List[object]]::new()
    $sourceProp = if ($IndicatorSet -eq 'Native') { 'Indicators' } else { 'ExtensibleIndicators' }
    foreach ($indRaw in @(Get-PavProp $Policy $sourceProp @())) {
        $ind = ConvertFrom-PavJson ([string]$indRaw)
        if ($null -eq $ind) { continue }
        $subNames = @(@(Get-PavProp $ind 'Indicators' @()) | ForEach-Object { Get-PavProp $_ 'Name' '' } | Where-Object { $_ }) -join ' | '
        $result.Add([pscustomobject]@{
            PolicyName    = [string](Get-PavProp $Policy 'Name' '')
            GroupName     = [string](Get-PavProp $ind 'Name' '')
            Type          = Get-PavProp $ind 'Type'
            Enabled       = Get-PavProp $ind 'Enabled'
            UseDefault    = Get-PavProp $ind 'UseDefault'
            ThresholdMode = Get-PavProp $ind 'ThresholdMode'
            UseInScoring  = Get-PavProp $ind 'UseInScoring'
            SubIndicators = $subNames
        })
    }
    return $result
}

function Get-PavIrmHealthRow {
<#
.SYNOPSIS
    Resume PolicyHealth (JSON) de una directiva IRM: estado, conteos e
    issues de validación. Port de Get-PolicyHealthRow.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Policy)

    $name = [string](Get-PavProp $Policy 'Name' '')
    $raw  = ConvertFrom-PavJson ([string](Get-PavProp $Policy 'PolicyHealth' ''))
    if ($null -eq $raw) {
        return [pscustomobject]@{ PolicyName = $name; HealthStatus = 'Unknown'
            UnhealthyCount = 0; RecommendReviewCount = 0; ValidationIssues = '' }
    }
    $issues = @(@(Get-PavProp $raw 'ValidationDetails' @()) | ForEach-Object {
        "$(Get-PavProp $_ 'Name' '') [$(Get-PavProp $_ 'ValidationSeverity' '')]: $(Get-PavProp $_ 'Status' '')"
    })
    [pscustomobject]@{
        PolicyName           = $name
        HealthStatus         = Get-PavProp $raw 'HealthStatus' 'Unknown'
        UnhealthyCount       = Get-PavProp $raw 'UnhealthyCount' 0
        RecommendReviewCount = Get-PavProp $raw 'RecommendReviewCount' 0
        ValidationIssues     = ($issues -join ' | ')
    }
}

## ═══ Helpers Communication Compliance (port de Export-CCPolicies.ps1) ═══════

function ConvertFrom-PavCcContentSources {
<#
.SYNOPSIS
    Resume ContentSources (JSON por elemento) de una regla CC:
    'Reviewee: x | Workloads: a,b'. Port de Parse-ContentSources.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][object]$RuleObj)

    $arr = @(Get-PavProp $RuleObj 'ContentSources' @())
    if ($arr.Count -eq 0) { return 'N/D' }
    $parts = @()
    foreach ($src in $arr) {
        $j = ConvertFrom-PavJson ([string]$src)
        if ($null -eq $j) { continue }
        $rev = Get-PavProp $j 'RevieweeName'
        $wl  = Get-PavProp $j 'Workloads'
        if ($rev) { $parts += "Reviewee: $rev" }
        if ($wl)  { $parts += 'Workloads: ' + (@($wl) -join ',') }
    }
    if ($parts.Count -gt 0) { return ($parts -join ' | ') }
    $s = "$($arr[0])"
    return $s.Substring(0, [Math]::Min(100, $s.Length))
}

function Get-PavCcWorkloads {
<#
.SYNOPSIS
    Workloads únicos desde ContentSources; fallback a la propiedad
    Workload. Port de Get-RuleWorkloads.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][object]$RuleObj)

    $fallback = [string](Get-PavProp $RuleObj 'Workload' 'N/D')
    if (-not $fallback) { $fallback = 'N/D' }
    $arr = @(Get-PavProp $RuleObj 'ContentSources' @())
    if ($arr.Count -eq 0) { return $fallback }
    $wl = @()
    foreach ($src in $arr) {
        $j = ConvertFrom-PavJson ([string]$src)
        if ($j) { $wl += @(Get-PavProp $j 'Workloads' @()) }
    }
    $wl = @($wl | Where-Object { $_ } | Sort-Object -Unique)
    if ($wl.Count -gt 0) { return ($wl -join ', ') }
    return $fallback
}

function ConvertFrom-PavCcClassifiers {
<#
.SYNOPSIS
    Nombres de clasificadores/modelos entrenables desde el AdvancedRule
    de CC (condition.subconditions[].value.datamodels[].name).
    Port de Parse-AdvancedRule (CC).
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][object]$RuleObj)

    $raw = [string](Get-PavProp $RuleObj 'AdvancedRule' '')
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw -eq '{}') { return 'N/D' }
    $json = ConvertFrom-PavJson $raw
    if ($null -eq $json -or $json -is [string]) { return 'N/D' }
    $models = @()
    foreach ($s in @(Get-PavProp (Get-PavProp $json 'condition') 'subconditions' @())) {
        $dms = Get-PavProp (Get-PavProp $s 'value') 'datamodels'
        foreach ($dm in @($dms)) {
            $n = Get-PavProp $dm 'name'
            if ($n) { $models += $n }
        }
    }
    if ($models.Count -gt 0) { return ($models -join ' | ') }
    return 'N/D'
}

function Get-PavCcDirection {
<#
.SYNOPSIS
    Direcciones (Inbound/Outbound/Internal) desde la condición KQL de una
    regla CC. Port de Parse-Direction.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][AllowEmptyString()][string]$Condition)

    if ([string]::IsNullOrEmpty($Condition) -or $Condition -eq 'N/D') { return 'N/D' }
    $dirs = @()
    foreach ($d in 'Inbound', 'Outbound', 'Internal') {
        if ($Condition -match "Direction:$d") { $dirs += $d }
    }
    if ($dirs.Count -gt 0) { return ($dirs -join ', ') }
    return 'N/D'
}
