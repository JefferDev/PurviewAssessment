function ConvertTo-PavControlStatusText {
<#
.SYNOPSIS
    Traduce el estado interno de un control al texto del informe.
#>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Position = 0)][AllowNull()][string]$Status)
    switch ("$Status") {
        'Implemented'          { 'Implementado' }
        'PartiallyImplemented' { 'Parcialmente implementado' }
        'NotImplemented'       { 'No implementado' }
        'RequiresValidation'   { 'Requiere validación' }
        'NotApplicable'        { 'No aplica' }
        default                { "$Status" }
    }
}

function Get-PavControlStatusBadgeType {
<#
.SYNOPSIS
    Tipo de badge HTML para cada estado de control.
#>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Position = 0)][AllowNull()][string]$Status)
    switch ("$Status") {
        'Implemented'          { 'Ok' }
        'PartiallyImplemented' { 'Warn' }
        'NotImplemented'       { 'Err' }
        'RequiresValidation'   { 'Info' }
        'NotApplicable'        { 'Neutral' }
        default                { 'Neutral' }
    }
}
