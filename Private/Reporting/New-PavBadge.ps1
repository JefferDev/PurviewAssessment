function New-PavBadge {
<#
.SYNOPSIS
    Genera un badge HTML de estado.
.DESCRIPTION
    Unifica Badge-Status / Badge-Prov / Badge-Bool / Get-ModeBadge de los
    scripts originales. El texto se codifica siempre (ConvertTo-PavHtml).
.PARAMETER Text
    Texto del badge.
.PARAMETER Type
    Ok | Warn | Err | Info | Special | Neutral. Por defecto: Neutral.
.PARAMETER Bool
    Modo booleano: genera 'Sí' (Ok) / 'No' (Neutral) a partir de un valor.
.OUTPUTS
    [string] HTML del badge.
.EXAMPLE
    New-PavBadge -Text 'Habilitada' -Type Ok
.EXAMPLE
    New-PavBadge -Bool $policy.Enabled
#>
    [CmdletBinding(DefaultParameterSetName = 'Text')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Text')]
        [string]$Text,

        [Parameter(ParameterSetName = 'Text')]
        [ValidateSet('Ok', 'Warn', 'Err', 'Info', 'Special', 'Neutral')]
        [string]$Type = 'Neutral',

        [Parameter(Mandatory, ParameterSetName = 'Bool')]
        [AllowNull()]
        [object]$Bool
    )

    if ($PSCmdlet.ParameterSetName -eq 'Bool') {
        $isTrue = [bool]$Bool
        $Text = if ($isTrue) { 'Sí' } else { 'No' }
        $Type = if ($isTrue) { 'Ok' } else { 'Neutral' }
    }

    $cssClass = switch ($Type) {
        'Ok'      { 'ok' }
        'Warn'    { 'warn' }
        'Err'     { 'err' }
        'Info'    { 'info' }
        'Special' { 'special' }
        default   { 'neutral' }
    }

    '<span class="pav-badge {0}">{1}</span>' -f $cssClass, (ConvertTo-PavHtml $Text)
}


function Test-PavShowInconclusive {
<#
.SYNOPSIS
    Indica si deben mostrarse los avisos que provienen de propiedades no
    concluyentes.
.DESCRIPTION
    Algunos estados que devuelve el servicio no reflejan la realidad
    ('Activating', 'Pending', 'NotStarted') y otros datos no son visibles
    por PowerShell aunque existan en el portal (los miembros de un caso de
    eDiscovery). Mostrarlos en un informe de cliente genera ruido y puede
    leerse como un hallazgo cuando no lo es.

    Los informes los omiten cuando la ejecución establece la bandera
    correspondiente, que gobierna Invoke-PurviewAssessment
    -HideInconclusiveWarnings o el parámetro homónimo de cada Export-*.
.OUTPUTS
    [bool]
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return (-not $script:PavHideInconclusive)
}

function New-PavInconclusiveBadge {
<#
.SYNOPSIS
    Emite un badge de aviso no concluyente, o cadena vacía si están ocultos.
.PARAMETER Text
    Texto del badge.
.PARAMETER Type
    Tipo de badge (por defecto Warn).
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Text,
        [Parameter(Position = 1)][string]$Type = 'Warn'
    )
    if (-not (Test-PavShowInconclusive)) { return '' }
    New-PavBadge -Text $Text -Type $Type
}
