function ConvertFrom-PavJsonValue {
<#
.SYNOPSIS
    Deserializa valores que la API REST de EXO v3+ devuelve como strings
    JSON sin parsear (ContentContainsSensitiveInformation, AdvancedRule...).
    Port de ConvertFrom-JsonSafe (Export-DLPPolicies.ps1): si ya es objeto
    lo devuelve tal cual; si es string JSON lo parsea; si falla, devuelve
    el string original.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        $trimmed = $Value.Trim()
        if (($trimmed.StartsWith('{') -or $trimmed.StartsWith('[')) -and $trimmed.Length -gt 2) {
            try { return ($trimmed | ConvertFrom-Json -ErrorAction Stop) }
            catch {
                Write-PavLog -Level Warn -Message "JSON no parseable ($($trimmed.Length) chars): $($_.Exception.Message)"
                return $Value
            }
        }
        return $Value
    }
    return $Value
}

function Resolve-PavDlpLocation {
<#
.SYNOPSIS
    Resuelve una propiedad de ubicación de directiva DLP a texto legible.
    Port de Resolve-Location: maneja $null/''/'All'/@('All')/objetos con
    Name-DisplayName-PrimarySmtpAddress/JSON string.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PropName,
        [Parameter(Mandatory)][AllowNull()][object]$PolicyObj
    )

    $raw = Get-PavProp $PolicyObj $PropName
    if ($null -eq $raw) { return 'No' }
    if ($raw -is [string] -and [string]::IsNullOrWhiteSpace($raw)) { return 'No' }

    if ($raw -is [string]) {
        if ($raw -eq 'All') { return 'Todos' }
        $parsed = ConvertFrom-PavJsonValue $raw
        if ($parsed -and $parsed -isnot [string]) {
            $names = @(@($parsed) | ForEach-Object {
                $n = Get-PavProp $_ 'Name' (Get-PavProp $_ 'DisplayName' '')
                if ($n) { $n }
            } | Where-Object { $_ })
            if ($names.Count -gt 0) { return ($names -join '; ') }
            return 'Todos'
        }
        return $raw
    }

    $arr = @($raw)
    if ($arr.Count -eq 0) { return 'No' }

    if ($arr[0] -is [string]) {
        $nonEmpty = @($arr | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($nonEmpty.Count -gt 0) {
            return (($nonEmpty | ForEach-Object { if ($_ -eq 'All') { 'Todos' } else { $_ } }) -join '; ')
        }
        return 'No'
    }

    $names = @($arr | ForEach-Object {
        $n = $null
        if ($null -ne $_) {
            $n = Get-PavProp $_ 'Name' ''
            if (-not $n) { $n = Get-PavProp $_ 'DisplayName' '' }
            if (-not $n) { $n = Get-PavProp $_ 'PrimarySmtpAddress' '' }
        }
        if ($n -eq 'All') { 'Todos' } elseif ($n) { $n }
    } | Where-Object { $_ })

    if ($names.Count -gt 0) { return ($names -join '; ') }
    return 'Todos'
}

function Resolve-PavScopedUsers {
<#
.SYNOPSIS
    Resuelve ExchangeSenderMemberOf y similares (JSON REST con
    DisplayName/PrimarySmtpAddress) a 'Nombre (smtp)'. Port de
    Resolve-ScopedUsers.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][object]$RawValue)

    if ($null -eq $RawValue) { return '' }
    if ($RawValue -is [string]) {
        $t = $RawValue.Trim()
        if ($t -in @('{}', '[]') -or [string]::IsNullOrWhiteSpace($t)) { return '' }
    }
    $parsed = ConvertFrom-PavJsonValue $RawValue
    if ($null -eq $parsed) { return '' }
    if ($parsed -is [string]) {
        if ($parsed.Trim() -in @('{}', '[]')) { return '' }
        return $parsed
    }
    $entries = @(@($parsed) | ForEach-Object {
        $display = Get-PavProp $_ 'DisplayName' ''
        $smtp    = Get-PavProp $_ 'PrimarySmtpAddress' ''
        if ($display -and $smtp) { "$display ($smtp)" }
        elseif ($display) { $display }
        elseif ($smtp) { $smtp }
    } | Where-Object { $_ })
    return ($entries -join '; ')
}

function Get-PavGroupSits {
<#
.SYNOPSIS
    SITs de un Group de AdvancedRule/CCSI, probando TODAS las variantes de
    nombre de propiedad observadas por versión/tenant. Port de Get-GroupSITs.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][object]$Group)

    if ($null -eq $Group) { return @() }
    foreach ($propName in @('Sensitivetypes', 'SensitiveTypes', 'sensitivetypes',
                            'SensitiveInformation', 'sensitiveinformation',
                            'SensitiveInfoTypes', 'sensitiveinfotypes')) {
        $val = Get-PavProp $Group $propName
        if ($val) { return @($val) }
    }
    return @()
}

function Get-PavGroupLabels {
<#
.SYNOPSIS
    Labels de un Group (variantes Labels/SensitivityLabels). Port de Get-GroupLabels.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][object]$Group)

    if ($null -eq $Group) { return @() }
    foreach ($propName in @('Labels', 'labels', 'SensitivityLabels', 'sensitivitylabels')) {
        $val = Get-PavProp $Group $propName
        if ($val) { return @($val) }
    }
    return @()
}

function Format-PavSitEntry {
<#
.SYNOPSIS
    SIT a string legible 'Nombre | Mincount:1 | Confidencelevel:High',
    manejando todas las variantes de casing. Port de Format-SITEntry.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][object]$SitObj)

    if ($null -eq $SitObj) { return $null }
    $sitName = [string](Get-PavProp $SitObj 'Name' '')
    $sitId   = [string](Get-PavProp $SitObj 'Id' (Get-PavProp $SitObj 'id' ''))
    if (-not $sitName -and $sitId) { $sitName = $sitId }
    if (-not $sitName) { return $null }

    $parts = @($sitName)
    $propVariants = @(
        , @('Mincount', 'minCount', 'mincount', 'MinCount')
        , @('Maxcount', 'maxCount', 'maxcount', 'MaxCount')
        , @('Confidencelevel', 'confidenceLevel', 'confidencelevel', 'ConfidenceLevel')
        , @('Minconfidence', 'minconfidence', 'MinConfidence', 'minConfidence')
        , @('Maxconfidence', 'maxconfidence', 'MaxConfidence', 'maxConfidence')
        , @('Classifiertype', 'classifiertype', 'ClassifierType', 'classifierType')
    )
    foreach ($variants in $propVariants) {
        foreach ($pName in $variants) {
            $pv = Get-PavProp $SitObj $pName
            if ($null -ne $pv -and "$pv" -ne '') {
                $parts += "$($variants[0]):$pv"
                break
            }
        }
    }
    return ($parts -join ' | ')
}

function Format-PavLabelEntry {
<#
.SYNOPSIS
    Label a string 'Nombre (Tipo) [ID: x]'. Port de Format-LabelEntry.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][object]$LabelObj)

    if ($null -eq $LabelObj) { return $null }
    $lName = [string](Get-PavProp $LabelObj 'Name' '')
    $lId   = [string](Get-PavProp $LabelObj 'Id' (Get-PavProp $LabelObj 'id' ''))
    $lType = [string](Get-PavProp $LabelObj 'Type' (Get-PavProp $LabelObj 'type' ''))
    if (-not $lName -and $lId) { $lName = $lId }
    if (-not $lName) { return $null }

    $entry = $lName
    if ($lType) { $entry += " ($lType)" }
    if ($lId)   { $entry += " [ID: $lId]" }
    return $entry
}

function Resolve-PavSitValue {
<#
.SYNOPSIS
    Extrae SITs y Labels de ContentContainsSensitiveInformation en TODOS
    los formatos REST (array directo, Groups con Sensitivetypes /
    SensitiveInformation / Labels / mixto). Port de Resolve-SITFromValue.
.OUTPUTS
    [hashtable] @{ SITs = <string multilinea>; Labels = <string multilinea> }
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][object]$RawValue)

    if ($null -eq $RawValue) { return @{ SITs = ''; Labels = '' } }
    $parsed = ConvertFrom-PavJsonValue $RawValue
    if ($null -eq $parsed -or $parsed -is [string]) { return @{ SITs = ''; Labels = '' } }

    $sitNames   = [System.Collections.Generic.List[string]]::new()
    $labelNames = [System.Collections.Generic.List[string]]::new()

    foreach ($item in @($parsed)) {
        $groups = Get-PavProp $item 'Groups'
        if ($groups) {
            foreach ($group in @($groups)) {
                foreach ($sit in (Get-PavGroupSits $group)) {
                    $f = Format-PavSitEntry $sit
                    if ($f) { $sitNames.Add($f) }
                }
                foreach ($label in (Get-PavGroupLabels $group)) {
                    $f = Format-PavLabelEntry $label
                    if ($f) { $labelNames.Add($f) }
                }
            }
            continue
        }
        $f = Format-PavSitEntry $item
        if ($f) { $sitNames.Add($f) }
    }

    return @{
        SITs   = ($sitNames -join "`n")
        Labels = ($labelNames -join "`n")
    }
}
