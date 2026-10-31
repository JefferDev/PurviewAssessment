function ConvertTo-PavHtml {
<#
.SYNOPSIS
    Codifica texto para inserción segura en HTML.
.DESCRIPTION
    Unifica EscHtml / HtmlEncode de los scripts originales. Todo valor
    proveniente del tenant (nombres de directivas, descripciones, UPNs)
    DEBE pasar por esta función antes de concatenarse en HTML: los datos
    de Purview son entrada no confiable para el informe.
.PARAMETER Value
    Texto a codificar. $null se convierte en cadena vacía.
.OUTPUTS
    [string]
.EXAMPLE
    ConvertTo-PavHtml -Value $policy.Name
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    process {
        if ([string]::IsNullOrEmpty($Value)) { return '' }
        [System.Net.WebUtility]::HtmlEncode($Value)
    }
}
