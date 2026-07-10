function Get-PurviewCcData {
<#
.SYNOPSIS
    Recolecta y parsea directivas y reglas de Communication Compliance
    (solo lectura). Port de Export-CCPolicies.ps1.
.PARAMETER IncludeDisabled
    Incluye directivas con Enabled = False.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.CcData' con
    Policies, Rules, CollectedAt.
.EXAMPLE
    (Get-PurviewCcData).Rules | Where-Object Direction -Match 'Outbound'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([switch]$IncludeDisabled)

    Assert-PavConnection
    Write-PavLog -Level Step -Message 'Recolectando directivas de Communication Compliance...'

    $rawPolicies = @(Invoke-PavRetry -OperationName 'Get-SupervisoryReviewPolicyV2' -ScriptBlock {
        Get-SupervisoryReviewPolicyV2 -ErrorAction Stop
    })
    $rawRules = @()
    try {
        $rawRules = @(Invoke-PavRetry -OperationName 'Get-SupervisoryReviewRule' -ScriptBlock {
            Get-SupervisoryReviewRule -ErrorAction Stop
        })
    }
    catch { Write-PavLog -Level Warn -Message "Lectura global de reglas CC falló: $($_.Exception.Message)" }
    Write-PavLog -Level Info -Message "Directivas CC: $($rawPolicies.Count) | Reglas: $($rawRules.Count)"

    if (-not $IncludeDisabled) {
        $rawPolicies = @($rawPolicies | Where-Object { "$(Get-PavProp $_ 'Enabled' $true)" -ne 'False' })
    }

    $ixP = 0
    $policies = foreach ($pol in $rawPolicies) {
        $ixP++
        Write-PavLog -Level Info -Message "  > Directiva $ixP/$($rawPolicies.Count): $(Get-PavProp $pol 'Name' '(sin nombre)')"
        $polName = [string](Get-PavProp $pol 'Name' '(sin nombre)')
        $polGuid = [string](Get-PavProp $pol 'Guid' '')
        $polRules = @($rawRules | Where-Object {
            "$(Get-PavProp $_ 'Policy' '')" -eq $polGuid -or "$(Get-PavProp $_ 'Name' '')" -eq $polName
        })
        $reviewers = (@(Get-PavProp $pol 'Reviewers' @()) | ForEach-Object { "$_" }) -join '; '
        $ruleWl = @($polRules | ForEach-Object { Get-PavCcWorkloads -RuleObj $_ } | Where-Object { $_ -ne 'N/D' } | Sort-Object -Unique)

        [pscustomobject]@{
            PSTypeName        = 'PurviewAssessment.CcPolicy'
            Name              = $polName
            Guid              = $polGuid
            Type              = [string](Get-PavProp $pol 'Type' 'SupervisoryReview')
            Enabled           = ("$(Get-PavProp $pol 'Enabled' $true)" -ne 'False')
            PolicyStatus      = [string](Get-PavProp $pol 'PolicyStatus' 'Unknown')
            ProvisionStatus   = [string](Get-PavProp $pol 'ProvisioningStatus' 'Unknown')
            DistributionStatus = [string](Get-PavProp $pol 'DistributionStatus' 'Unknown')
            Mode              = [string](Get-PavProp $pol 'Mode' 'N/D')
            Description       = [string](Get-PavProp $pol 'Comment' '')
            Priority          = Get-PavProp $pol 'Priority'
            PreservationDays  = Get-PavProp $pol 'PreservationPeriodInDays' 0
            ReviewMailbox     = [string](Get-PavProp $pol 'ReviewMailbox' '')
            Reviewers         = $reviewers
            Workloads         = ($ruleWl -join ', ')
            RulesCount        = $polRules.Count
            CreatedBy         = [string](Get-PavProp $pol 'CreatedBy' '')
            LastModifiedBy    = [string](Get-PavProp $pol 'LastModifiedBy' '')
            CreationTimeUtc   = Get-PavProp $pol 'CreationTimeUtc'
            ModificationTimeUtc = Get-PavProp $pol 'ModificationTimeUtc'
        }
    }

    $ixR = 0
    $rules = foreach ($rule in $rawRules) {
        $ixR++
        Write-PavLog -Level Info -Message "  > Regla $ixR/$($rawRules.Count): $(Get-PavProp $rule 'Name' '(sin nombre)')"
        $cond = [string](Get-PavProp $rule 'Condition' '')
        [pscustomobject]@{
            PSTypeName        = 'PurviewAssessment.CcRule'
            PolicyRef         = [string](Get-PavProp $rule 'Policy' '')
            RuleName          = [string](Get-PavProp $rule 'Name' '')
            RuleGuid          = [string](Get-PavProp $rule 'Guid' '')
            Condition         = $cond
            Direction         = Get-PavCcDirection $cond
            Workloads         = Get-PavCcWorkloads -RuleObj $rule
            SamplingRate      = Get-PavProp $rule 'SamplingRate' 'N/D'
            OcrEnabled        = Get-PavProp $rule 'Ocr' 'False'
            ClassifiersModels = ConvertFrom-PavCcClassifiers -RuleObj $rule
            ContentSources    = ConvertFrom-PavCcContentSources -RuleObj $rule
            Disabled          = Get-PavProp $rule 'Disabled' $false
            CreatedBy         = [string](Get-PavProp $rule 'CreatedBy' '')
            CreationTimeUtc   = Get-PavProp $rule 'CreationTimeUtc'
        }
    }

    [pscustomobject]@{
        PSTypeName  = 'PurviewAssessment.CcData'
        Policies    = @($policies)
        Rules       = @($rules)
        CollectedAt = Get-Date
    }
}
