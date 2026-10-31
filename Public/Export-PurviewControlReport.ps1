function Export-PurviewControlReport {
<#
.SYNOPSIS
    Genera el informe de evaluación de controles (HTML + Excel).
.DESCRIPTION
    Informe orientado a la lectura ejecutiva: puntaje global y por dominio,
    controles no implementados ordenados por severidad, y el detalle de cada
    control con su evidencia, fundamento e impacto de negocio.
    Excel: Resumen, Puntaje por Dominio y Controles (apto para usarse como
    plan de remediación, con columnas de responsable y fecha objetivo).
.PARAMETER Evaluation
    Resultado de Invoke-PurviewControlEvaluation.
.PARAMETER OutputPath
    Carpeta de salida.
.PARAMETER ClientName
    Nombre del cliente.
.PARAMETER HideInconclusiveWarnings
    Oculta los avisos derivados de propiedades que el servicio no reporta de
    forma concluyente.
.PARAMETER SkipExcel
    Omite el libro Excel.
.OUTPUTS
    [pscustomobject] con Workload, HtmlPath y ExcelPath.
.EXAMPLE
    $ev = Invoke-PurviewControlEvaluation -Data @{ MIP = $mip }
    Export-PurviewControlReport -Evaluation $ev -OutputPath C:\Reports -ClientName 'Cliente Demo'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('PurviewAssessment.ControlEvaluation')]
        [object]$Evaluation,

        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter()][string]$ClientName = '',
        [switch]$SkipExcel,

        # Oculta los avisos derivados de propiedades no concluyentes
        [switch]$HideInconclusiveWarnings
    )

    process {
        if ($PSBoundParameters.ContainsKey('HideInconclusiveWarnings')) { $script:PavHideInconclusive = [bool]$HideInconclusiveWarnings }
        if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
        $ts       = Get-Date -Format 'yyyy-MM-dd_HH-mm'
        $htmlPath = Join-Path $OutputPath "Evaluacion_Controles_$ts.html"
        $xlsxPath = Join-Path $OutputPath "Evaluacion_Controles_$ts.xlsx"

        $res    = @($Evaluation.Results)
        $scores = @($Evaluation.DomainScores)
        Write-PavLog -Level Step -Message 'Generando informe de evaluación de controles...'

        # ── Resumen ejecutivo ────────────────────────────────────────────────
        $scoreRows = foreach ($s in $scores) {
            [pscustomobject]@{
                'Dominio' = $s.DomainName; 'Controles' = $s.Total
                'Implementados' = $s.Implemented; 'Parciales' = $s.Partial
                'No implementados' = $s.NotImplemented
                'Requieren validación' = $s.RequiresValidation
                'Puntaje' = "$($s.Score)%"
            }
        }
        $abiertos = @($res | Where-Object Status -in @('NotImplemented', 'PartiallyImplemented'))
        $sevOrder = @{ 'Alta' = 1; 'Media' = 2; 'Baja' = 3 }
        $abiertosOrd = @($abiertos | Sort-Object @{ E = { $sevOrder["$($_.Severity)"] } }, Id)

        $gapRows = foreach ($c in $abiertosOrd) {
            [pscustomobject]@{
                'ID' = $c.Id; 'Severidad' = $c.Severity; 'Estado' = $c.StatusText
                'Control' = $c.Title
                'Situación observada' = $(if ("$($c.Evidence)".Length -gt 220) { "$($c.Evidence)".Substring(0, 220) + '…' } else { "$($c.Evidence)" })
            }
        }

        $resumenHtml = (New-PavHtmlCard -Title 'Puntaje por dominio' -Expanded `
            -BadgesHtml (New-PavBadge -Text "Implementación global: $($Evaluation.OverallScore)%" -Type $(if ($Evaluation.OverallScore -ge 70) { 'Ok' } elseif ($Evaluation.OverallScore -ge 40) { 'Warn' } else { 'Err' })) `
            -BodyHtml (New-PavHtmlTable -Data $scoreRows))
        if ($gapRows) {
            $resumenHtml += New-PavHtmlCard -Title 'Brechas priorizadas por severidad' -Expanded `
                -Subtitle "$($abiertos.Count) control(es) abiertos" `
                -BodyHtml (New-PavHtmlTable -Data $gapRows)
        }

        $sections = @(New-PavHtmlSection -Id 'ctrl-resumen' -Title 'Resumen de la evaluación' `
            -Description "Catálogo de controles v$($Evaluation.CatalogVersion). El puntaje considera los controles verificables; los parcialmente implementados computan como medio control." `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Implementación global' -Value "$($Evaluation.OverallScore)%"),
                (New-PavStat -Label 'Controles evaluados' -Value "$($Evaluation.TotalControls)"),
                (New-PavStat -Label 'Implementados' -Value "$(@($res | Where-Object Status -eq 'Implemented').Count)"),
                (New-PavStat -Label 'No implementados' -Value "$(@($res | Where-Object Status -eq 'NotImplemented').Count)"),
                (New-PavStat -Label 'Requieren validación' -Value "$(@($res | Where-Object Status -eq 'RequiresValidation').Count)")
            )) -ContentHtml $resumenHtml)

        # ── Detalle por dominio ──────────────────────────────────────────────
        foreach ($s in $scores) {
            $ctrls = @($res | Where-Object Domain -eq $s.Domain | Sort-Object Id)
            $cards = foreach ($c in $ctrls) {
                $badges = (New-PavBadge -Text $c.StatusText -Type (Get-PavControlStatusBadgeType $c.Status)) +
                          (New-PavBadge -Text "Severidad: $($c.Severity)" -Type $(switch ($c.Severity) { 'Alta' { 'Err' } 'Media' { 'Warn' } default { 'Neutral' } })) +
                          (New-PavBadge -Text $c.Source -Type Info) +
                          (New-PavBadge -Text "Evidencia: $($c.EvidenceLevelText)" -Type $(switch ("$($c.EvidenceLevel)") { 'Verified' { 'Ok' } 'NotDeterminable' { 'Warn' } default { 'Neutral' } }))
                if ($c.License) { $badges += New-PavBadge -Text $c.License -Type Neutral }
                $body = New-PavPropList -Properties ([ordered]@{
                    'Evidencia'          = $c.Evidence
                    'Nivel de evidencia' = $(if ($c.UnreliableReason) { "$($c.EvidenceLevelText) — $($c.UnreliableReason)" } else { $c.EvidenceLevelText })
                    'Fundamento'         = $c.Rationale
                    'Impacto de negocio' = $c.BusinessImpact
                    'Referencias'        = $c.Frameworks
                    'Tipo de control'    = $c.Type
                })
                New-PavHtmlCard -Title "$($c.Id) — $($c.Title)" -BadgesHtml $badges -BodyHtml $body `
                    -Expanded:($c.Status -eq 'NotImplemented') `
                    -FilterTags @{ estado = $c.Status; sev = $c.Severity; tipo = $c.Type; evid = $c.EvidenceLevel }
            }
            $filtros = @'
<div class="pav-filters"><span class="pav-filters-label">Estado:</span>
<button class="pav-chip" onclick="pavFilterBy(this,'estado','NotImplemented')">No implementados</button>
<button class="pav-chip" onclick="pavFilterBy(this,'estado','PartiallyImplemented')">Parciales</button>
<button class="pav-chip" onclick="pavFilterBy(this,'estado','Implemented')">Implementados</button>
<button class="pav-chip" onclick="pavFilterBy(this,'estado','RequiresValidation')">Requieren validación</button>
</div>
<div class="pav-filters"><span class="pav-filters-label">Severidad:</span>
<button class="pav-chip" onclick="pavFilterBy(this,'sev','Alta')">Alta</button>
<button class="pav-chip" onclick="pavFilterBy(this,'sev','Media')">Media</button>
<button class="pav-chip" onclick="pavFilterBy(this,'sev','Baja')">Baja</button>
</div>
'@
            $sections += (New-PavHtmlSection -Id "ctrl-$($s.Domain.ToLowerInvariant())" -Title $s.DomainName `
                -Description "Evaluación de los $($s.Total) controles del dominio." `
                -StatsHtml (New-PavStatGroup -Stats (
                    (New-PavStat -Label 'Puntaje' -Value "$($s.Score)%"),
                    (New-PavStat -Label 'Implementados' -Value "$($s.Implemented) de $($s.Evaluable)"),
                    (New-PavStat -Label 'No implementados' -Value "$($s.NotImplemented)")
                )) -ContentHtml ($filtros + ($cards -join "`n")))
        }

        $doc = New-PavHtmlDocument -Title 'Evaluación de controles — Microsoft Purview' `
            -Subtitle 'Nivel de implementación por dominio, con la evidencia técnica que sustenta cada veredicto (solo lectura)' `
            -ClientName $ClientName -Sections $sections `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Implementación global' -Value "$($Evaluation.OverallScore)%"),
                (New-PavStat -Label 'Controles' -Value "$($Evaluation.TotalControls)")
            ))
        $doc | Set-Content -Path $htmlPath -Encoding UTF8
        Write-PavLog -Level Success -Message "Informe HTML: $htmlPath"

        $excelPath = $null
        if (-not $SkipExcel) {
            $resumen = @(
                [pscustomobject]@{ Metrica = 'Implementacion global';        Valor = "$($Evaluation.OverallScore)%" }
                [pscustomobject]@{ Metrica = 'Controles del catalogo';       Valor = $Evaluation.TotalControls }
                [pscustomobject]@{ Metrica = 'Controles evaluables';         Valor = $Evaluation.EvaluableCount }
                [pscustomobject]@{ Metrica = 'Implementados';                Valor = @($res | Where-Object Status -eq 'Implemented').Count }
                [pscustomobject]@{ Metrica = 'Parcialmente implementados';   Valor = @($res | Where-Object Status -eq 'PartiallyImplemented').Count }
                [pscustomobject]@{ Metrica = 'No implementados';             Valor = @($res | Where-Object Status -eq 'NotImplemented').Count }
                [pscustomobject]@{ Metrica = 'Requieren validacion';         Valor = @($res | Where-Object Status -eq 'RequiresValidation').Count }
                [pscustomobject]@{ Metrica = 'No aplican';                   Valor = @($res | Where-Object Status -eq 'NotApplicable').Count }
                [pscustomobject]@{ Metrica = 'Severidad alta abiertos';      Valor = @($abiertos | Where-Object Severity -eq 'Alta').Count }
                [pscustomobject]@{ Metrica = 'Version del catalogo';         Valor = $Evaluation.CatalogVersion }
                [pscustomobject]@{ Metrica = 'Umbral de obsolescencia (dias)'; Valor = $Evaluation.StaleDays }
                [pscustomobject]@{ Metrica = 'Cliente';                      Valor = $ClientName }
                [pscustomobject]@{ Metrica = 'Fecha';                        Valor = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
            )
            # La hoja de controles sirve como plan de remediación
            $ctrlRows = foreach ($c in ($res | Sort-Object @{ E = { $sevOrder["$($_.Severity)"] } }, Id)) {
                [pscustomobject]@{
                    'ID' = $c.Id; 'Dominio' = $c.Domain; 'Control' = $c.Title
                    'Estado' = $c.StatusText; 'Severidad' = $c.Severity; 'Tipo' = $c.Type
                    'Nivel de evidencia' = $c.EvidenceLevelText; 'Motivo no determinable' = $c.UnreliableReason
                    'Procedencia' = $c.Source; 'Evidencia' = $c.Evidence
                    'Fundamento' = $c.Rationale; 'Impacto de negocio' = $c.BusinessImpact
                    'Referencias' = $c.Frameworks; 'Licencia' = $c.License
                    'Responsable' = $c.Owner; 'Fecha objetivo' = $c.TargetDate
                }
            }
            $excelPath = Export-PavExcelWorkbook -Path $xlsxPath -Title 'Microsoft Purview - Evaluacion de controles' -Sheets ([ordered]@{
                'Resumen'            = $resumen
                'Puntaje por Dominio' = @($scores | Select-Object DomainName, Total, Implemented, Partial, NotImplemented, RequiresValidation, NotApplicable, Evaluable, Score)
                'Controles'          = $ctrlRows
            })
        }

        [pscustomobject]@{
            PSTypeName = 'PurviewAssessment.ReportResult'
            Workload   = 'CONTROLS'
            HtmlPath   = $htmlPath
            ExcelPath  = $excelPath
        }
    }
}
