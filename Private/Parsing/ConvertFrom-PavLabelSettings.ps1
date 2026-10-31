function Get-PavProp {
<#
.SYNOPSIS
    Acceso seguro a una propiedad de un objeto (unifica Get-PropSafe /
    Get-SafeProp / Get-Prop* de los scripts originales).
.PARAMETER InputObject
    Objeto origen.
.PARAMETER Name
    Nombre de la propiedad.
.PARAMETER Default
    Valor si la propiedad no existe o es $null.
.NOTES
    ADVERTENCIA: PowerShell des-enrolla arrays de un solo elemento en la
    salida de la función. Los consumidores que esperan colecciones deben
    envolver con @(...) o aceptar string suelto (como hace
    ConvertFrom-PavKeyValueSettings).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][AllowNull()][object]$Default = $null
    )
    if ($null -eq $InputObject) { return $Default }
    $p = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $p -and $null -ne $p.Value) { return $p.Value }
    return $Default
}

function ConvertFrom-PavJson {
<#
.SYNOPSIS
    ConvertFrom-Json tolerante: devuelve $null ante entrada vacía o
    JSON inválido (unifica ConvertFrom-SafeJson / ConvertTo-SafeJson).
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][AllowEmptyString()][string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    try { return ($Raw | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Get-PavSettingValue {
<#
.SYNOPSIS
    Valor de un hashtable de settings parseados (equivalente a Get-Val de
    Export-SensitivityLabelsReport_v3).
#>
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][hashtable]$Hash,
        [Parameter(Mandatory)][string]$Key,
        [Parameter()][string]$Default = 'No configurado'
    )
    if ($null -eq $Hash) { return $Default }
    $k = $Key.ToLowerInvariant()
    if ($Hash.ContainsKey($k) -and $null -ne $Hash[$k] -and "$($Hash[$k])" -ne '') { return "$($Hash[$k])" }
    return $Default
}

function ConvertFrom-PavKeyValueSettings {
<#
.SYNOPSIS
    Parsea la propiedad Settings de Get-Label / Get-LabelPolicy a hashtable
    con claves en minúsculas. Portado de Get-LabelSettings (v3).
.DESCRIPTION
    Soporta los tres formatos observados en el tenant:
    diccionario, lista de strings "[clave, valor]" y strings "clave=valor".
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Position = 0)][AllowNull()][object]$SettingsRaw)

    $result = @{}
    if ($null -eq $SettingsRaw) { return $result }

    # PowerShell des-enrolla arrays de UN elemento en la salida de funciones
    # (p. ej. Get-PavProp): un Settings de un solo item llega como string
    # suelto. Se normaliza a colección para no perderlo.
    if ($SettingsRaw -is [string]) { $SettingsRaw = @($SettingsRaw) }

    if ($SettingsRaw -is [System.Collections.IDictionary]) {
        foreach ($key in $SettingsRaw.Keys) { $result[$key.ToString().ToLowerInvariant()] = $SettingsRaw[$key] }
        return $result
    }
    if ($SettingsRaw -is [System.Collections.IEnumerable] -and $SettingsRaw -isnot [string]) {
        foreach ($item in $SettingsRaw) {
            if ($item -is [string]) {
                $s = $item.Trim()
                if ($s.StartsWith('[') -and $s.EndsWith(']')) {
                    $inner = $s.Substring(1, $s.Length - 2)
                    $ci = $inner.IndexOf(',')
                    if ($ci -gt 0) {
                        $result[$inner.Substring(0, $ci).Trim().ToLowerInvariant()] = $inner.Substring($ci + 1).Trim()
                    }
                }
                elseif ($s.Contains('=')) {
                    $parts = $s -split '=', 2
                    $result[$parts[0].Trim().ToLowerInvariant()] = $parts[1].Trim()
                }
            }
            elseif ($null -ne (Get-PavProp $item 'Key')) {
                $result[$item.Key.ToString().ToLowerInvariant()] = $item.Value
            }
        }
    }
    return $result
}

function ConvertFrom-PavLabelActions {
<#
.SYNOPSIS
    Parsea LabelActions (JSON embebido) a hashtable acción → settings.
    Portado de Get-LabelActionsParsed (v3), con su mapa de normalización:
    applycontentmarking+footer→footer, +header→header,
    applywatermarking→watermark, encrypt→encrypt, protectsites→protectsites.
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Position = 0)][AllowNull()][object]$LabelActionsRaw)

    $normalizeMap = @{
        'applywatermarking'   = 'watermark'
        'applycontentmarking' = 'contentmarking'
        'applyheader'         = 'header'
        'applyfooter'         = 'footer'
    }
    $result = @{}
    if ($null -eq $LabelActionsRaw) { return $result }

    foreach ($actionItem in @($LabelActionsRaw)) {
        $action = if ($actionItem -is [string]) { ConvertFrom-PavJson $actionItem } else { $actionItem }
        if ($null -eq $action) { continue }

        $settings = @{}
        foreach ($s in @(Get-PavProp $action 'Settings' @())) {
            $sObj = if ($s -is [string]) { ConvertFrom-PavJson $s } else { $s }
            if ($null -ne $sObj -and $null -ne (Get-PavProp $sObj 'Key')) {
                $settings[$sObj.Key.ToString().ToLowerInvariant()] = $sObj.Value
            }
        }

        $subType = [string](Get-PavProp $action 'SubType' '')
        $key = if (-not [string]::IsNullOrWhiteSpace($subType)) { $subType.ToLowerInvariant() }
               else { ([string](Get-PavProp $action 'Type' 'desconocido')).ToLowerInvariant() }
        if ($normalizeMap.ContainsKey($key)) { $key = $normalizeMap[$key] }

        $result[$key] = $settings
    }
    return $result
}

function ConvertFrom-PavLocaleSettings {
<#
.SYNOPSIS
    Parsea LocaleSettings (JSON) a hashtable localeKey → (idioma → texto).
    Portado de Get-LocaleSettingsParsed (v3).
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Position = 0)][AllowNull()][object]$LocaleSettingsRaw)

    $result = @{}
    if ($null -eq $LocaleSettingsRaw) { return $result }

    foreach ($localeItem in @($LocaleSettingsRaw)) {
        $locale = if ($localeItem -is [string]) { ConvertFrom-PavJson $localeItem } else { $localeItem }
        if ($null -eq $locale) { continue }

        $entries = @{}
        foreach ($s in @(Get-PavProp $locale 'Settings' @())) {
            $sObj = if ($s -is [string]) { ConvertFrom-PavJson $s } else { $s }
            if ($null -ne $sObj -and $null -ne (Get-PavProp $sObj 'Key')) { $entries[[string]$sObj.Key] = $sObj.Value }
        }
        $lk = Get-PavProp $locale 'LocaleKey' 'desconocido'
        $result[[string]$lk] = $entries
    }
    return $result
}
