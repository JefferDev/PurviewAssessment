function Export-PurviewDlmReport {
<#
.SYNOPSIS
    Genera el informe de retención/DLM (HTML + Excel).
.DESCRIPTION
    HTML: pestañas Directivas/Reglas/Etiquetas con badges de modo,
    categoría de etiqueta (Regulatory/Record/Standard), file plan y etapas
    de revisión. Excel: 7 hojas (Resumen Directivas, Ubicaciones, Reglas,
    Etiquetas, File Plan, Etapas Revisión, Detalle Directivas).
.PARAMETER Data
    Datos de Get-PurviewDlmData. Si se omite, se recolectan.
.PARAMETER OutputPath
    Carpeta de salida.
.PARAMETER ClientName
    Nombre del cliente.
.PARAMETER SkipExcel
    Omite el libro Excel.
.EXAMPLE
    Export-PurviewDlmReport -OutputPath C:\Reports -ClientName 'Contoso'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)]
        [PSTypeName('PurviewAssessment.DlmData')]
        [object]$Data,

        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter()][string]$ClientName = '',
        [switch]$SkipExcel
    )

    process {
        if (-not $Data) { $Data = Get-PurviewDlmData }
        if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

        $ts       = Get-Date -Format 'yyyy-MM-dd_HH-mm'
        $htmlPath = Join-Path $OutputPath "DLM_Report_$ts.html"
        $xlsxPath = Join-Path $OutputPath "DLM_Report_$ts.xlsx"
        $policies = @($Data.Policies); $rules = @($Data.Rules); $tags = @($Data.Tags)

        Write-PavLog -Level Step -Message 'Generando informe HTML de DLM...'

        $sections = New-PavDlmSections -Data $Data

        $doc = New-PavHtmlDocument -Title 'Retención (DLM) — Microsoft Purview' `
            -Subtitle 'Assessment de gestión del ciclo de vida de los datos (solo lectura)' -ClientName $ClientName -Sections $sections
        $doc | Set-Content -Path $htmlPath -Encoding UTF8
        Write-PavLog -Level Success -Message "Informe HTML: $htmlPath"

        $excelPath = $null
        if (-not $SkipExcel) {
            $polDetail = foreach ($p in $policies) {
                foreach ($prop in $p.PSObject.Properties) {
                    if ($prop.Name -eq 'PSTypeName') { continue }
                    [pscustomobject]@{ 'Directiva' = $p.Name; 'Propiedad' = $prop.Name
                        'Valor' = if ($null -eq $prop.Value) { '' } else { "$($prop.Value)" } }
                }
            }
            $excelPath = Export-PavExcelWorkbook -Path $xlsxPath -Title 'Microsoft Purview - Retencion (DLM)' -Sheets ([ordered]@{
                'Resumen Directivas' = @($policies | Select-Object * -ExcludeProperty PSTypeName)
                'Ubicaciones'        = @($Data.PolicyLocations)
                'Reglas'             = @($rules | Select-Object * -ExcludeProperty PSTypeName)
                'Etiquetas'          = @($tags | Select-Object * -ExcludeProperty PSTypeName)
                'File Plan'          = @($Data.FilePlans)
                'Etapas Revision'    = @($Data.ReviewStages)
                'Detalle Directivas' = $polDetail
            })
        }

        [pscustomobject]@{ PSTypeName = 'PurviewAssessment.ReportResult'
            Workload = 'DLM'; HtmlPath = $htmlPath; ExcelPath = $excelPath }
    }
}
