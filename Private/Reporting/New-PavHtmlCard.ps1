function New-PavHtmlCard {
<#
.SYNOPSIS
    Genera una tarjeta HTML colapsable (directiva, etiqueta, regla, SIT...).
.DESCRIPTION
    Unifica New-PolicyCardHtml / New-LabelCardHtml de los scripts
    originales. La cabecera es clicable (pavToggleCard) y la tarjeta expone
    data-name para la búsqueda en vivo (pavFilter).

    SEGURIDAD: Title y Subtitle se codifican SIEMPRE. BadgesHtml y BodyHtml
    se insertan tal cual porque son HTML ya construido por el motor
    (New-PavBadge, New-PavHtmlTable, New-PavPropList) — nunca deben
    recibir texto crudo del tenant sin codificar.
.PARAMETER Title
    Título de la tarjeta (texto plano; se codifica).
.PARAMETER Subtitle
    Línea secundaria bajo el título (texto plano; se codifica).
.PARAMETER BadgesHtml
    HTML de badges para la cabecera (generado con New-PavBadge).
.PARAMETER BodyHtml
    HTML del cuerpo (generado con New-PavHtmlTable / New-PavPropList / etc.).
.PARAMETER Expanded
    Renderiza la tarjeta expandida por defecto.
.OUTPUTS
    [string] HTML de la tarjeta.
.EXAMPLE
    New-PavHtmlCard -Title $p.Name -Subtitle $p.Guid -BadgesHtml (New-PavBadge -Bool $p.Enabled) -BodyHtml $body
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter()]
        [string]$Subtitle = '',

        [Parameter()]
        [string]$BadgesHtml = '',

        [Parameter()]
        [string]$BodyHtml = '',

        [switch]$Expanded,

        # Color de acento (hex) de la etiqueta/elemento: borde izquierdo + swatch
        [Parameter()][string]$AccentColor = ''
    )

    $expClass  = if ($Expanded) { ' exp' } else { '' }
    $accentOk  = ($AccentColor -match '^#[0-9a-fA-F]{3,8}$')   # hex validado (anti-inyección)
    $cardStyle = if ($accentOk) { ' style="border-left:4px solid ' + $AccentColor + '"' } else { '' }
    $swatch    = if ($accentOk) { '<span class="pav-swatch" style="background:' + $AccentColor + '" title="' + $AccentColor + '"></span>' } else { '' }
    $titleEnc  = ConvertTo-PavHtml $Title
    $subHtml   = if ($Subtitle) { '<div class="pav-card-sub">{0}</div>' -f (ConvertTo-PavHtml $Subtitle) } else { '' }
    # data-name en minúsculas para la búsqueda (se codifica también como atributo)
    $dataName  = ConvertTo-PavHtml $Title.ToLowerInvariant()

    @"
<div class="pav-card$expClass"$cardStyle data-name="$dataName">
  <div class="pav-card-head" onclick="pavToggleCard(this)">
    <div>
      <div class="pav-card-title">$swatch$titleEnc</div>
      $subHtml
    </div>
    <div class="pav-card-badges">$BadgesHtml<span class="pav-caret">&#9654;</span></div>
  </div>
  <div class="pav-card-body">
$BodyHtml
  </div>
</div>
"@
}
