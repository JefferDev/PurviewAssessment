function Export-PurviewIrmReport {
<#
.SYNOPSIS
    Genera el informe de Insider Risk Management (HTML + Excel).
.DESCRIPTION
    HTML: sección de directivas con badges de salud/estado y tarjetas con
    detalle, trigger insights e indicadores por directiva. Excel: 6 hojas
    (Resumen Directivas, Detalle Directivas, Salud, Trigger Insights,
    Indicadores, Indicadores Extensibles).
.PARAMETER Data
    Datos de Get-PurviewIrmData. Si se omite, se recolectan.
.PARAMETER OutputPath
    Carpeta de salida.
.PARAMETER ClientName
    Nombre del cliente.
.PARAMETER HideInconclusiveWarnings
    Oculta los avisos derivados de propiedades que el servicio no reporta de
    forma concluyente.
.PARAMETER SkipExcel
    Omite el libro Excel.
.EXAMPLE
    Export-PurviewIrmReport -OutputPath C:\Reports -ClientName 'Cliente Demo'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)]
        [PSTypeName('PurviewAssessment.IrmData')]
        [object]$Data,

        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter()][string]$ClientName = '',
        [switch]$SkipExcel,

        # Oculta los avisos derivados de propiedades no concluyentes
        [switch]$HideInconclusiveWarnings
    )

    process {
        if ($PSBoundParameters.ContainsKey('HideInconclusiveWarnings')) { $script:PavHideInconclusive = [bool]$HideInconclusiveWarnings }
        if (-not $Data) { $Data = Get-PurviewIrmData }
        if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

        $ts       = Get-Date -Format 'yyyy-MM-dd_HH-mm'
        $htmlPath = Join-Path $OutputPath "IRM_Report_$ts.html"
        $xlsxPath = Join-Path $OutputPath "IRM_Report_$ts.xlsx"
        $policies = @($Data.Policies)

        Write-PavLog -Level Step -Message 'Generando informe HTML de IRM...'

        $sections = New-PavIrmSections -Data $Data

        $doc = New-PavHtmlDocument -Title 'Insider Risk Management — Microsoft Purview' `
            -Subtitle 'Assessment de riesgo interno (solo lectura)' -ClientName $ClientName -Sections $sections
        $doc | Set-Content -Path $htmlPath -Encoding UTF8
        Write-PavLog -Level Success -Message "Informe HTML: $htmlPath"

        $excelPath = $null
        if (-not $SkipExcel) {
            $summary = foreach ($p in $policies) {
                [pscustomobject]@{ 'Nombre' = $p.Name; 'Habilitada' = $p.Enabled; 'Escenario' = $p.Scenario
                    'Categoría' = $p.PolicyCategory; 'Prioridad' = $p.Priority; 'Salud' = $p.HealthStatus
                    'DLP vinculada' = $p.HasDlpPolicy; 'Distribución' = $p.DistributionStatus
                    'Modificada' = $p.LastModifiedUtc }
            }
            $detail = foreach ($p in $policies) {
                foreach ($prop in $p.PSObject.Properties) {
                    if ($prop.Name -eq 'PSTypeName') { continue }
                    [pscustomobject]@{ 'Directiva' = $p.Name; 'Propiedad' = $prop.Name
                        'Valor' = if ($null -eq $prop.Value) { '' } else { "$($prop.Value)" } }
                }
            }
            $excelPath = Export-PavExcelWorkbook -Path $xlsxPath -Title 'Microsoft Purview - Insider Risk Management' -Sheets ([ordered]@{
                'Resumen Directivas'  = $summary
                'Detalle Directivas'  = $detail
                'Salud'               = @($Data.Health)
                'Trigger Insights'    = @($Data.TriggerInsights)
                'Indicadores'         = @($Data.Indicators)
                'Indicadores Extensibles' = @($Data.ExtensibleIndicators)
            })
        }

        [pscustomobject]@{ PSTypeName = 'PurviewAssessment.ReportResult'
            Workload = 'IRM'; HtmlPath = $htmlPath; ExcelPath = $excelPath }
    }
}
