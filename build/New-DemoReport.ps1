#Requires -Version 7.2
<#
.SYNOPSIS
    Genera un informe HTML de demostración con datos fixture para validar
    el motor de reporting (criterio de salida de F2): tema día/noche,
    tarjetas colapsables, tabs, búsqueda, badges, tablas e impresión.
.EXAMPLE
    pwsh -File build/New-DemoReport.ps1 -OutputPath ./demo-report.html
#>
[CmdletBinding()]
param([string]$OutputPath = (Join-Path (Get-Location) 'PurviewAssessment-Demo.html'))

$ErrorActionPreference = 'Stop'
$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'PurviewAssessment.psd1') -Force

# Las funciones del motor son privadas: se invocan en el scope del módulo.
$html = & (Get-Module PurviewAssessment) {

    # ── Fixture: DLP ──────────────────────────────────────────────────────────
    $dlpRules = @(
        [pscustomobject]@{ Regla = 'Bloqueo PII externa'; Modo = 'Enforce'; Prioridad = 0; SITs = 'Credit Card, <Custom> SSN' }
        [pscustomobject]@{ Regla = 'Aviso datos financieros'; Modo = 'TestWithNotifications'; Prioridad = 1; SITs = 'IBAN & "SWIFT"' }
    )
    $dlpCards = (New-PavHtmlCard -Title 'Directiva PII — Producción' -Subtitle 'GUID: 11111111-2222-3333-4444-555555555555' `
        -BadgesHtml ((New-PavBadge -Text 'Habilitada' -Type Ok) + (New-PavBadge -Text 'Enforce' -Type Err)) `
        -BodyHtml ((New-PavPropList -Properties ([ordered]@{ 'Ámbito' = 'Exchange, SharePoint, OneDrive'; 'Comentario' = $null; 'Prioridad' = 0 })) + (New-PavHtmlTable -Data $dlpRules)) -Expanded) +
        (New-PavHtmlCard -Title 'Directiva <script>alert(1)</script> XSS-test' -Subtitle 'Verifica codificación HTML' `
        -BadgesHtml (New-PavBadge -Bool $false) -BodyHtml (New-PavPropList -Properties ([ordered]@{ 'Nota' = 'El título malicioso debe verse como texto plano' })))

    $sDlp = New-PavHtmlSection -Id 'dlp' -Title 'DLP' -Description 'Directivas de prevención de pérdida de datos.' `
        -StatsHtml (New-PavStatGroup -Stats (New-PavStat -Label 'Directivas' -Value '2'), (New-PavStat -Label 'Reglas' -Value '2')) `
        -ContentHtml $dlpCards

    # ── Fixture: Etiquetas ────────────────────────────────────────────────────
    $sMip = New-PavHtmlSection -Id 'labels' -Title 'Etiquetas' -Description 'Etiquetas de sensibilidad y directivas de publicación.' `
        -ContentHtml (New-PavHtmlCard -Title 'Confidencial \ Todos los empleados' -Subtitle 'Cifrado + marca de agua' `
            -BadgesHtml ((New-PavBadge -Text 'Publicada' -Type Ok) + (New-PavBadge -Text 'Cifrado' -Type Special)) `
            -BodyHtml (New-PavPropList -Properties ([ordered]@{ 'Tooltip' = 'Datos internos sensibles'; 'Marca de agua' = $true; 'Color' = '#F5C344' })))

    # ── Fixture: sección sin datos (carga omitida) ────────────────────────────
    $sIrm = New-PavHtmlSection -Id 'irm' -Title 'IRM' -Description 'Insider Risk Management.' -ContentHtml $null

    New-PavHtmlDocument -Title 'Assessment de Microsoft Purview' -Subtitle 'Informe de demostración del motor de reporting (F2)' `
        -ClientName 'Contoso (DEMO)' -TenantInfo 'contoso.onmicrosoft.com' `
        -StatsHtml (New-PavStatGroup -Stats (New-PavStat -Label 'Cargas evaluadas' -Value '2 de 3'), (New-PavStat -Label 'Hallazgos' -Value '3')) `
        -Sections $sDlp, $sMip, $sIrm
}

$html | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "Demo generada: $OutputPath ($([math]::Round((Get-Item $OutputPath).Length/1KB,1)) KB)" -ForegroundColor Green
