# Helpers de DLM/Retención — ports de Export-DLMConfiguration.ps1

function ConvertTo-PavFriendlyDuration {
<#
.SYNOPSIS
    Días de retención → 'N year(s)/month(s)/days' o 'Unlimited'.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()]$Duration)
    if ($null -eq $Duration -or "$Duration" -eq '' -or "$Duration" -eq 'Unlimited') { return 'Unlimited' }
    $d = 0
    if (-not [int]::TryParse("$Duration", [ref]$d)) { return "$Duration" }
    if ($d -le 0)        { return 'Unlimited' }
    if ($d % 365 -eq 0)  { return "$($d / 365) año(s)" }
    if ($d % 30 -eq 0)   { return "$($d / 30) mes(es)" }
    return "$d días"
}

function ConvertTo-PavFriendlyAction {
<#
.SYNOPSIS
    Acción de retención → texto legible.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][string]$Action)
    switch ($Action) {
        'Keep'          { 'Solo retener' }
        'KeepAndDelete' { 'Retener y luego eliminar' }
        'Delete'        { 'Solo eliminar' }
        default         { $Action }
    }
}

function ConvertTo-PavFriendlyRetentionType {
<#
.SYNOPSIS
    Tipo de disparo de retención → texto legible.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][string]$Type)
    switch ($Type) {
        'CreationAgeInDays'     { 'Desde creación' }
        'ModificationAgeInDays' { 'Desde última modificación' }
        'EventAgeInDays'        { 'Desde evento' }
        'TaggedAgeInDays'       { 'Desde aplicación de etiqueta' }
        default                 { $Type }
    }
}

function ConvertTo-PavFriendlyMode {
<#
.SYNOPSIS
    Modo de directiva DLM → texto legible (respeta IsSimulation).
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][string]$Mode, [Parameter(Position = 1)][bool]$IsSimulation)
    if ($IsSimulation) { return 'Simulación' }
    switch ($Mode) {
        'Enforce'                  { 'Activa (Enforce)' }
        'TestWithoutNotifications' { 'Simulación (sin notificar)' }
        'TestWithNotifications'    { 'Simulación (notifica)' }
        default                    { $Mode }
    }
}

function ConvertTo-PavFriendlyPolicyType {
<#
.SYNOPSIS
    Tipo de directiva de retención → texto legible.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][string]$Type)
    switch ($Type) {
        'Hold'               { 'Directiva de retención' }
        'Label'              { 'Publicación de etiquetas' }
        'ModernGroup'        { 'Directiva de grupos M365' }
        'InformationBarrier' { 'Information Barrier' }
        default              { $Type }
    }
}

function Get-PavDlmSitText {
<#
.SYNOPSIS
    Nombres de SITs de una regla de retención (auto-aplicación).
    Port de Get-SensitiveInfoText.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()]$SIT)
    $arr = @($SIT)
    if ($arr.Count -eq 0 -or $null -eq $arr[0]) { return '' }
    $names = @($arr | ForEach-Object {
        if ($null -eq $_) { return }
        if ($_ -is [System.Collections.IDictionary]) { if ($_.Contains('Name')) { $_['Name'] } else { "$_" } }
        else { Get-PavProp $_ 'Name' "$_" }
    } | Where-Object { $_ })
    return ($names -join ' | ')
}

function Get-PavLocationScope {
<#
.SYNOPSIS
    Cobertura de una ubicación: 'Todos', 'N elemento(s)' o 'No configurado'.
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()]$LocationArray)
    $arr = @($LocationArray)
    if ($arr.Count -eq 0 -or ($arr.Count -eq 1 -and [string]::IsNullOrEmpty("$($arr[0])"))) { return 'No configurado' }
    if (@($arr | ForEach-Object { "$_" }) -contains 'All') { return 'Todos' }
    return "$($arr.Count) elemento(s) específico(s)"
}

function Get-PavLocationDetails {
<#
.SYNOPSIS
    Detalle de una ubicación (elementos distintos de 'All' unidos).
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()]$LocationArray)
    $arr = @($LocationArray) | Where-Object { $_ -and "$_" -ne 'All' } | ForEach-Object { "$_" }
    return ($arr -join ' | ')
}
