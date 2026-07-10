function New-PavHtmlSection {
<#
.SYNOPSIS
    Genera una sección de carga de trabajo del informe.
.DESCRIPTION
    Una sección agrupa el contenido de una carga de trabajo (DLP, MIP,
    IRM...). En el informe consolidado cada sección se convierte en un
    panel de pestaña; en los informes individuales es la única sección.
    Si ContentHtml es nulo/vacío, se renderiza el aviso estándar de
    'No evaluado' (secciones omitidas por error en la recolección).
.PARAMETER Id
    Identificador único (se usa para el panel de tab). Solo [a-z0-9-].
.PARAMETER Title
    Título de la sección (texto plano; se codifica).
.PARAMETER Description
    Descripción bajo el título (texto plano; se codifica).
.PARAMETER StatsHtml
    HTML de tarjetas de estadística de la sección (New-PavStat).
.PARAMETER ContentHtml
    HTML del contenido (tarjetas, tablas).
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.HtmlSection' con
    Id, Title y Html — el formato que consume New-PavHtmlDocument.
.EXAMPLE
    New-PavHtmlSection -Id 'dlp' -Title 'Prevención de pérdida de datos (DLP)' -ContentHtml $cards
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter()]
        [string]$Description = '',

        [Parameter()]
        [string]$StatsHtml = '',

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ContentHtml
    )

    $titleEnc = ConvertTo-PavHtml $Title
    $descHtml = if ($Description) { '<p class="desc">{0}</p>' -f (ConvertTo-PavHtml $Description) } else { '' }

    $body = if ([string]::IsNullOrWhiteSpace($ContentHtml)) {
        '<div class="pav-empty">Esta carga de trabajo no fue evaluada en esta ejecución (sin datos o recolección omitida por error). Debe revisarse el log de la ejecución.</div>'
    }
    else {
        $ContentHtml
    }

    $html = @"
<section class="pav-section" id="section-$Id">
  <h2>$titleEnc</h2>
  $descHtml
  $StatsHtml
  $body
</section>
"@

    [pscustomobject]@{
        PSTypeName = 'PurviewAssessment.HtmlSection'
        Id         = $Id
        Title      = $Title
        Html       = $html
    }
}

function New-PavStat {
<#
.SYNOPSIS
    Genera una tarjeta de estadística (KPI del resumen ejecutivo).
.PARAMETER Label
    Etiqueta descriptiva.
.PARAMETER Value
    Valor a destacar.
.OUTPUTS
    [string] HTML del stat. Envolver un conjunto en New-PavStatGroup.
.EXAMPLE
    New-PavStatGroup -Stats (New-PavStat -Label 'Directivas' -Value 12), (New-PavStat -Label 'Reglas' -Value 48)
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    '<div class="pav-stat"><div class="v">{0}</div><div class="l">{1}</div></div>' -f (ConvertTo-PavHtml $Value), (ConvertTo-PavHtml $Label)
}

function New-PavStatGroup {
<#
.SYNOPSIS
    Agrupa tarjetas de estadística en su contenedor flex.
.PARAMETER Stats
    HTML de stats (New-PavStat).
.OUTPUTS
    [string]
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Stats
    )

    '<div class="pav-stats">{0}</div>' -f ($Stats -join "`n")
}
