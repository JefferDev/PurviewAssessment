function ConvertFrom-PavAdvancedRule {
<#
.SYNOPSIS
    Parsea el JSON de AdvancedRule de una regla DLP preservando toda la
    estructura lógica (operadores And/Or/Not anidados, condiciones,
    excepciones, SITs, Labels, AccessScope).
.DESCRIPTION
    Port de ConvertFrom-AdvancedRule (Export-DLPPolicies.ps1). Genera:
      - ConditionsTree: árbol de condiciones en texto plano (Excel).
      - ConditionsHtml: árbol en HTML con clases pav-adv-* (informe HTML).
      - SensitiveInfoTypes / SensitivityLabels / AccessScope: colectores
        planos extraídos durante el recorrido.
.OUTPUTS
    [pscustomobject] con AccessScope, SensitivityLabels, SensitiveInfoTypes,
    ConditionsTree, ConditionsHtml.
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Position = 0)][AllowNull()][AllowEmptyString()][string]$AdvancedRuleJson)

    $result = [pscustomobject]@{
        AccessScope        = ''
        SensitivityLabels  = ''
        SensitiveInfoTypes = ''
        ConditionsTree     = ''
        ConditionsHtml     = ''
    }
    if ([string]::IsNullOrWhiteSpace($AdvancedRuleJson)) { return $result }

    try { $parsed = $AdvancedRuleJson | ConvertFrom-Json -ErrorAction Stop }
    catch {
        Write-PavLog -Level Warn -Message "AdvancedRule JSON no parseable: $($_.Exception.Message)"
        return $result
    }

    $sitNames     = [System.Collections.Generic.List[string]]::new()
    $labelNames   = [System.Collections.Generic.List[string]]::new()
    $accessScopes = [System.Collections.Generic.List[string]]::new()

    # ── Recursivo: nodo → texto plano ─────────────────────────────────────────
    function script:RenderPavNodeText {
        param($Node, [int]$Depth = 0)
        if ($null -eq $Node) { return '' }
        $indent = '  ' * $Depth
        $lines  = [System.Collections.Generic.List[string]]::new()

        $operator = Get-PavProp $Node 'Operator'
        $condName = Get-PavProp $Node 'ConditionName'
        $value    = Get-PavProp $Node 'Value'
        $subConds = Get-PavProp $Node 'SubConditions'

        if ($condName) {
            if ($condName -eq 'ContentContainsSensitiveInformation') {
                $lines.Add("${indent}ContentContainsSensitiveInformation:")
                foreach ($valItem in @($value)) {
                    $groups = Get-PavProp $valItem 'Groups'
                    if ($groups) {
                        foreach ($group in @($groups)) {
                            $gName = Get-PavProp $group 'Name' 'Default'
                            foreach ($sit in (Get-PavGroupSits $group)) {
                                $f = Format-PavSitEntry $sit
                                if ($f) { $sitNames.Add($f); $lines.Add("$indent    [$gName] $f") }
                            }
                            foreach ($label in (Get-PavGroupLabels $group)) {
                                $f = Format-PavLabelEntry $label
                                if ($f) { $labelNames.Add($f); $lines.Add("$indent    [$gName] LABEL: $f") }
                            }
                        }
                    }
                    else {
                        $f = Format-PavSitEntry $valItem
                        if ($f) { $sitNames.Add($f); $lines.Add("$indent    $f") }
                    }
                }
            }
            elseif ($condName -eq 'AccessScope') {
                $val = if ($value -is [string]) { $value } else { "$value" }
                $accessScopes.Add($val)
                $lines.Add("${indent}AccessScope: $val")
            }
            else {
                $valStr = ''
                if ($null -ne $value) {
                    if ($value -is [string]) { $valStr = $value }
                    elseif ($value -is [System.Collections.IEnumerable]) {
                        $items = @(@($value) | ForEach-Object { "$_" } | Where-Object { $_ })
                        if ($items.Count -le 5) { $valStr = $items -join '; ' }
                        else { $valStr = "$(($items | Select-Object -First 3) -join '; '); ... (+$($items.Count - 3) mas, total: $($items.Count))" }
                    }
                    else { $valStr = "$value" }
                }
                $lines.Add("${indent}${condName}: $valStr")
            }
            return ($lines -join "`n")
        }

        if ($operator -and $subConds) {
            $opLabel = switch ($operator) { 'And' { 'AND' } 'Or' { 'OR' } 'Not' { 'NOT' } default { "$operator".ToUpper() } }
            $lines.Add("${indent}${opLabel}:")
            foreach ($sub in @($subConds)) {
                $subText = RenderPavNodeText $sub ($Depth + 1)
                if ($subText) { $lines.Add($subText) }
            }
            return ($lines -join "`n")
        }
        return ''
    }

    # ── Recursivo: nodo → HTML (clases pav-adv-*, todo codificado) ────────────
    function script:RenderPavNodeHtml {
        param($Node, [int]$Depth = 0)
        if ($null -eq $Node) { return '' }
        $html = ''

        $operator = Get-PavProp $Node 'Operator'
        $condName = Get-PavProp $Node 'ConditionName'
        $value    = Get-PavProp $Node 'Value'
        $subConds = Get-PavProp $Node 'SubConditions'

        if ($condName) {
            if ($condName -eq 'ContentContainsSensitiveInformation') {
                $html += "<div class='pav-adv-cond'><span class='pav-adv-name'>ContentContainsSensitiveInformation</span>"
                foreach ($valItem in @($value)) {
                    $groups = Get-PavProp $valItem 'Groups'
                    if ($groups) {
                        foreach ($group in @($groups)) {
                            $gName = ConvertTo-PavHtml (Get-PavProp $group 'Name' 'Default')
                            $html += "<div class='pav-adv-group'>Grupo: $gName<ul>"
                            foreach ($sit in (Get-PavGroupSits $group)) {
                                $f = Format-PavSitEntry $sit
                                if ($f) { $html += "<li class='pav-adv-sit'>$(ConvertTo-PavHtml $f)</li>" }
                            }
                            foreach ($label in (Get-PavGroupLabels $group)) {
                                $f = Format-PavLabelEntry $label
                                if ($f) { $html += "<li class='pav-adv-lbl'>LABEL: $(ConvertTo-PavHtml $f)</li>" }
                            }
                            $html += '</ul></div>'
                        }
                    }
                    else {
                        $f = Format-PavSitEntry $valItem
                        if ($f) { $html += "<div class='pav-adv-group'><ul><li class='pav-adv-sit'>$(ConvertTo-PavHtml $f)</li></ul></div>" }
                    }
                }
                $html += '</div>'
            }
            else {
                $valStr = ''
                if ($null -ne $value) {
                    if ($value -is [string]) { $valStr = $value }
                    elseif ($value -is [System.Collections.IEnumerable]) {
                        $items = @(@($value) | ForEach-Object { "$_" } | Where-Object { $_ })
                        if ($items.Count -le 8) { $valStr = $items -join '; ' }
                        else { $valStr = "$(($items | Select-Object -First 5) -join '; ') ... (+$($items.Count - 5) mas, total: $($items.Count))" }
                    }
                    else { $valStr = "$value" }
                }
                $html += "<div class='pav-adv-cond'><span class='pav-adv-name'>$(ConvertTo-PavHtml $condName)</span><span class='pav-adv-val'>$(ConvertTo-PavHtml $valStr)</span></div>"
            }
            return $html
        }

        if ($operator -and $subConds) {
            $opClass = switch ($operator) { 'Not' { 'pav-adv-not' } 'Or' { 'pav-adv-or' } default { 'pav-adv-and' } }
            $opLabel = switch ($operator) { 'And' { 'AND' } 'Or' { 'OR' } 'Not' { 'NOT (excepción)' } default { "$operator".ToUpper() } }
            $html += "<div class='pav-adv-block $opClass'><span class='pav-adv-op'>$opLabel</span>"
            foreach ($sub in @($subConds)) { $html += RenderPavNodeHtml $sub ($Depth + 1) }
            $html += '</div>'
            return $html
        }
        return ''
    }

    $rootCondition = Get-PavProp $parsed 'Condition'
    if ($rootCondition) {
        $result.ConditionsTree = RenderPavNodeText $rootCondition 0
        $result.ConditionsHtml = RenderPavNodeHtml $rootCondition 0
    }

    $result.SensitiveInfoTypes = $sitNames -join "`n"
    $result.SensitivityLabels  = $labelNames -join "`n"
    $result.AccessScope        = $accessScopes -join '; '
    return $result
}
