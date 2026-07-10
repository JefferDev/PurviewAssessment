function New-PavHtmlDocument {
<#
.SYNOPSIS
    Genera el documento HTML completo del informe (shell compartido).
.DESCRIPTION
    Shell único de todos los informes del módulo, portado del diseño de
    Export-SITReport_v2.ps1 y generalizado:
      - Tema día/noche con persistencia (localStorage) y detección de
        prefers-color-scheme, con bootstrap anti-parpadeo en <head>.
      - Barra superior fija: cambio de tema, expandir/contraer todo,
        imprimir/exportar a PDF.
      - Tarjetas de estadística como resumen ejecutivo.
      - Búsqueda en vivo sobre tarjetas.
      - Con 2+ secciones genera pestañas (informe consolidado); con una
        sola sección omite las pestañas (informes individuales).
      - CSS/JS embebidos inline: el informe es UN archivo portable, sin
        dependencias externas ni fuentes remotas (apto para entornos
        offline de cliente).
.PARAMETER Title
    Título principal del informe.
.PARAMETER Subtitle
    Subtítulo (p. ej. descripción del assessment).
.PARAMETER ClientName
    Nombre del cliente (portada y pie).
.PARAMETER TenantInfo
    Identificación del tenant evaluado (dominio/organización).
.PARAMETER Sections
    Secciones creadas con New-PavHtmlSection (PurviewAssessment.HtmlSection).
.PARAMETER StatsHtml
    HTML de estadísticas globales bajo la cabecera (New-PavStatGroup).
.OUTPUTS
    [string] documento HTML completo.
.EXAMPLE
    $doc = New-PavHtmlDocument -Title 'Assessment de Microsoft Purview' -ClientName 'Contoso' -Sections $s1, $s2
    $doc | Set-Content -Path informe.html -Encoding UTF8
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter()]
        [string]$Subtitle = 'Informe de assessment de solo lectura',

        [Parameter()]
        [string]$ClientName = '',

        [Parameter()]
        [string]$TenantInfo = '',

        [Parameter(Mandatory)]
        [PSTypeName('PurviewAssessment.HtmlSection')]
        [object[]]$Sections,

        [Parameter()]
        [string]$StatsHtml = ''
    )

    # ── Assets embebidos (informe de archivo único) ──────────────────────────
    $cssPath = Join-Path $script:PavAssetsPath 'report.css'
    $jsPath  = Join-Path $script:PavAssetsPath 'report.js'
    foreach ($asset in $cssPath, $jsPath) {
        if (-not (Test-Path $asset)) { throw "Asset del motor de reporting no encontrado: $asset" }
    }
    $css = Get-Content -Path $cssPath -Raw
    $js  = Get-Content -Path $jsPath  -Raw

    $titleEnc  = ConvertTo-PavHtml $Title
    $subEnc    = ConvertTo-PavHtml $Subtitle
    $clientEnc = ConvertTo-PavHtml $ClientName
    $tenantEnc = ConvertTo-PavHtml $TenantInfo
    $now       = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $modVer    = try { $MyInvocation.MyCommand.Module.Version.ToString() } catch { '' }

    # ── Metadatos de cabecera ─────────────────────────────────────────────────
    $metaParts = [System.Collections.Generic.List[string]]::new()
    if ($clientEnc) { $metaParts.Add("<span><b>Cliente:</b> $clientEnc</span>") }
    if ($tenantEnc) { $metaParts.Add("<span><b>Tenant:</b> $tenantEnc</span>") }
    $metaParts.Add("<span><b>Generado:</b> $now</span>")
    if ($modVer)    { $metaParts.Add("<span><b>PurviewAssessment:</b> v$modVer</span>") }
    $metaHtml = $metaParts -join "`n    "

    # ── Tabs + paneles (solo con 2+ secciones) ────────────────────────────────
    $useTabs   = ($Sections.Count -gt 1)
    $tabsHtml  = ''
    $panelsSb  = [System.Text.StringBuilder]::new()

    if ($useTabs) {
        $tabsSb = [System.Text.StringBuilder]::new()
        [void]$tabsSb.AppendLine('<div class="pav-tabs">')
        for ($i = 0; $i -lt $Sections.Count; $i++) {
            $s = $Sections[$i]
            $active = if ($i -eq 0) { ' active' } else { '' }
            [void]$tabsSb.AppendLine(('<button class="pav-tab{0}" onclick="pavSwitchTab(this, ''panel-{1}'')">{2}</button>' -f $active, $s.Id, (ConvertTo-PavHtml $s.Title)))
            [void]$panelsSb.AppendLine(('<div class="pav-panel{0}" id="panel-{1}">' -f $active, $s.Id))
            [void]$panelsSb.AppendLine($s.Html)
            [void]$panelsSb.AppendLine('</div>')
        }
        [void]$tabsSb.AppendLine('</div>')
        $tabsHtml = $tabsSb.ToString()
    }
    else {
        # Una sola sección: panel activo sin barra de pestañas
        [void]$panelsSb.AppendLine(('<div class="pav-panel active" id="panel-{0}">' -f $Sections[0].Id))
        [void]$panelsSb.AppendLine($Sections[0].Html)
        [void]$panelsSb.AppendLine('</div>')
    }
    $panelsHtml = $panelsSb.ToString()

    # ── Documento ─────────────────────────────────────────────────────────────
    @"
<!DOCTYPE html>
<html lang="es" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$titleEnc</title>
<script>
/* Bootstrap de tema anti-parpadeo: se ejecuta antes del primer render */
(function () {
  try {
    var saved = localStorage.getItem('pav-report-theme');
    if (!saved) {
      saved = (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) ? 'light' : 'dark';
    }
    document.documentElement.setAttribute('data-theme', saved);
  } catch (e) {
    document.documentElement.setAttribute('data-theme', 'dark');
  }
})();
</script>
<style>
$css
</style>
</head>
<body>

<div class="pav-topbar">
  <div class="pav-brand"><span class="pav-dot"></span> Microsoft Purview &middot; Assessment</div>
  <div class="pav-actions">
    <button class="pav-btn" onclick="pavToggleAll()" title="Expandir o contraer todas las tarjetas">Expandir / Contraer</button>
    <button class="pav-btn" onclick="pavToggleTheme()" title="Cambiar entre modo día y noche">Día / Noche</button>
    <button class="pav-btn" onclick="window.print()" title="Imprimir o exportar a PDF">Imprimir</button>
  </div>
</div>

<header class="pav-header">
  <h1 class="pav-title">$titleEnc</h1>
  <p class="pav-subtitle">$subEnc</p>
  <div class="pav-meta">
    $metaHtml
  </div>
  $StatsHtml
</header>

$tabsHtml

<div class="pav-search">
  <input type="text" id="pav-search" placeholder="Buscar por nombre o contenido..." oninput="pavFilter()">
</div>

$panelsHtml

<footer class="pav-footer">
  Microsoft Purview Assessment &mdash; <b>$clientEnc</b> &mdash; Informe generado el $now.
  Este informe es de solo lectura: su generación no realizó ningún cambio sobre el tenant evaluado.
</footer>

<script>
$js
</script>
</body>
</html>
"@
}
