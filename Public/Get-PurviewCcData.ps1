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

    # El listado no puebla Reviewers, pero el objeto que devuelve la consulta
    # por identidad tiene otro identificador y rompe el cruce con las reglas.
    # Por eso se conserva el objeto del listado y se le añaden ÚNICAMENTE los
    # revisores obtenidos de la consulta puntual.
    $ixD = 0
    foreach ($pol in $rawPolicies) {
        $ixD++
        $yaTiene = @(@(Get-PavProp $pol 'Reviewers' @()) | Where-Object { $_ })
        if ($yaTiene.Count -gt 0) { continue }
        $ident = "$(Get-PavProp $pol 'Identity' (Get-PavProp $pol 'Name' ''))"
        if (-not $ident) { continue }
        try {
            $full = Invoke-PavRetry -OperationName "Get-SupervisoryReviewPolicyV2 '$ident'" -MaxAttempts 2 -ScriptBlock {
                Get-SupervisoryReviewPolicyV2 -Identity $ident -ErrorAction Stop
            }
            $revs = @()
            foreach ($f in @($full)) {
                foreach ($prop in 'Reviewers', 'ReviewerList', 'Reviewer') {
                    $v = @(Get-PavProp $f $prop @()) | ForEach-Object { "$_" } | Where-Object { $_ }
                    if (@($v).Count -gt 0) { $revs += @($v); break }
                }
            }
            $revs = @($revs | Sort-Object -Unique)
            if ($revs.Count -gt 0) {
                $pol | Add-Member -NotePropertyName Reviewers -NotePropertyValue $revs -Force
                Write-PavLog -Level Info -Message "  > [$ixD/$($rawPolicies.Count)] Revisores de '$(Get-PavProp $pol 'Name' '')': $($revs -join ', ')"
            }
            # El buzón de revisión tampoco viaja en el listado
            $mbx = @($full | ForEach-Object { "$(Get-PavProp $_ 'ReviewMailbox' '')" } | Where-Object { $_ }) | Select-Object -First 1
            if ($mbx) { $pol | Add-Member -NotePropertyName ReviewMailbox -NotePropertyValue $mbx -Force }
        }
        catch { Write-PavLog -Level Warn -Message "      Revisores de '$(Get-PavProp $pol 'Name' '')' no recuperados: $($_.Exception.Message)" }
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
        # Los revisores pueden declararse en la directiva o en sus reglas,
        # según cómo se creara la directiva. Se consolidan ambas fuentes.
        $revPol = @()
        foreach ($prop in 'Reviewers', 'ReviewerList', 'Reviewer', 'SupervisoryReviewers') {
            $v = @(Get-PavProp $pol $prop @()) | ForEach-Object { "$_" } | Where-Object { $_ }
            if (@($v).Count -gt 0) { $revPol = @($v); break }
        }
        $revRul = @()
        foreach ($r in $polRules) {
            foreach ($prop in 'Reviewers', 'ReviewerList', 'Reviewer') {
                $v = @(Get-PavProp $r $prop @()) | ForEach-Object { "$_" } | Where-Object { $_ }
                if (@($v).Count -gt 0) { $revRul += @($v); break }
            }
        }
        $revRul = @($revRul)
        $revTodos = @(@($revPol + $revRul) | Sort-Object -Unique)
        $reviewers = ($revTodos -join '; ')
        $reviewerSource = if ($revPol.Count -gt 0 -and $revRul.Count -gt 0) { 'Directiva y reglas' }
                          elseif ($revPol.Count -gt 0) { 'Directiva' }
                          elseif ($revRul.Count -gt 0) { 'Reglas' } else { '' }
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
            ReviewerCount     = $revTodos.Count
            ReviewerSource    = $reviewerSource
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
            Reviewers         = (@(@(Get-PavProp $rule 'Reviewers' @()) | ForEach-Object { "$_" } | Where-Object { $_ }) -join '; ')
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
