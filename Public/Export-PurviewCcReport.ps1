function Export-PurviewCcReport {
<#
.SYNOPSIS
    Genera el informe de Communication Compliance (HTML + Excel).
.DESCRIPTION
    HTML: pestañas Directivas/Reglas con badges de estado y
    aprovisionamiento (Active/Activating/Error, Success/Pending/Failed),
    revisores, workloads y clasificadores. Excel: 4 hojas (Resumen
    Directivas, Detalle Directivas, Reglas, Detalle Reglas).
.PARAMETER Data
    Datos de Get-PurviewCcData. Si se omite, se recolectan.
.PARAMETER OutputPath
    Carpeta de salida.
.PARAMETER ClientName
    Nombre del cliente.
.PARAMETER IncludeDisabled
    Se propaga al colector cuando -Data no se proporciona.
.PARAMETER SkipExcel
    Omite el libro Excel.
.EXAMPLE
    Export-PurviewCcReport -OutputPath C:\Reports -ClientName 'Contoso'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)]
        [PSTypeName('PurviewAssessment.CcData')]
        [object]$Data,

        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter()][string]$ClientName = '',
        [switch]$IncludeDisabled,
        [switch]$SkipExcel
    )

    process {
        if (-not $Data) { $Data = Get-PurviewCcData -IncludeDisabled:$IncludeDisabled }
        if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

        $ts       = Get-Date -Format 'yyyy-MM-dd_HH-mm'
        $htmlPath = Join-Path $OutputPath "CC_Report_$ts.html"
        $xlsxPath = Join-Path $OutputPath "CC_Report_$ts.xlsx"
        $policies = @($Data.Policies)
        $rules    = @($Data.Rules)

        Write-PavLog -Level Step -Message 'Generando informe HTML de Communication Compliance...'

        $sections = New-PavCcSections -Data $Data

        $doc = New-PavHtmlDocument -Title 'Communication Compliance — Microsoft Purview' `
            -Subtitle 'Assessment de cumplimiento de comunicaciones (solo lectura)' -ClientName $ClientName -Sections $sections
        $doc | Set-Content -Path $htmlPath -Encoding UTF8
        Write-PavLog -Level Success -Message "Informe HTML: $htmlPath"

        $excelPath = $null
        if (-not $SkipExcel) {
            $polSummary = foreach ($p in $policies) {
                [pscustomobject]@{ 'Nombre' = $p.Name; 'Habilitada' = $p.Enabled; 'Estado' = $p.PolicyStatus
                    'Aprovisionamiento' = $p.ProvisionStatus; 'Modo' = $p.Mode; 'Reglas' = $p.RulesCount
                    'Workloads' = $p.Workloads; 'Revisores' = $p.Reviewers; 'Retención (días)' = $p.PreservationDays }
            }
            $polDetail = foreach ($p in $policies) {
                foreach ($prop in $p.PSObject.Properties) {
                    if ($prop.Name -eq 'PSTypeName') { continue }
                    [pscustomobject]@{ 'Directiva' = $p.Name; 'Propiedad' = $prop.Name
                        'Valor' = if ($null -eq $prop.Value) { '' } else { "$($prop.Value)" } }
                }
            }
            $ruleSummary = foreach ($r in $rules) {
                [pscustomobject]@{ 'Regla' = $r.RuleName; 'Dirección' = $r.Direction; 'Workloads' = $r.Workloads
                    'Muestreo' = $r.SamplingRate; 'OCR' = $r.OcrEnabled; 'Clasificadores' = $r.ClassifiersModels }
            }
            $ruleDetail = foreach ($r in $rules) {
                foreach ($prop in $r.PSObject.Properties) {
                    if ($prop.Name -eq 'PSTypeName') { continue }
                    $v = if ($null -eq $prop.Value) { '' } else { "$($prop.Value)" }
                    if ($v -eq '') { continue }
                    [pscustomobject]@{ 'Regla' = $r.RuleName; 'Propiedad' = $prop.Name; 'Valor' = $v }
                }
            }
            $excelPath = Export-PavExcelWorkbook -Path $xlsxPath -Title 'Microsoft Purview - Communication Compliance' -Sheets ([ordered]@{
                'Resumen Directivas' = $polSummary
                'Detalle Directivas' = $polDetail
                'Reglas'             = $ruleSummary
                'Detalle Reglas'     = $ruleDetail
            })
        }

        [pscustomobject]@{ PSTypeName = 'PurviewAssessment.ReportResult'
            Workload = 'CC'; HtmlPath = $htmlPath; ExcelPath = $excelPath }
    }
}
