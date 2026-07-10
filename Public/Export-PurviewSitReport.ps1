function Export-PurviewSitReport {
<#
.SYNOPSIS
    Genera el informe de SITs personalizados (HTML + Excel).
.DESCRIPTION
    HTML: tarjeta por SIT con confianza recomendada, proximidad y tabla de
    patrones (IdMatch con regex resuelta, evidencia de soporte, keywords y
    filtros). Excel: 4 hojas (SITs, Patrones, Regex, Keywords).
.PARAMETER Data
    Datos de Get-PurviewSitData. Si se omite, se recolectan en línea.
.PARAMETER OutputPath
    Carpeta de salida.
.PARAMETER ClientName
    Nombre del cliente.
.PARAMETER SkipExcel
    Omite el libro Excel.
.EXAMPLE
    Get-PurviewSitData -XmlPath .\rulepack.xml | Export-PurviewSitReport -OutputPath C:\Reports
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)]
        [PSTypeName('PurviewAssessment.SitData')]
        [object]$Data,

        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter()][string]$ClientName = '',
        [switch]$SkipExcel
    )

    process {
        if (-not $Data) { $Data = Get-PurviewSitData -Online }
        if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

        $ts       = Get-Date -Format 'yyyy-MM-dd_HH-mm'
        $htmlPath = Join-Path $OutputPath "SIT_Report_$ts.html"
        $xlsxPath = Join-Path $OutputPath "SIT_Report_$ts.xlsx"
        $entities = @($Data.Entities)

        Write-PavLog -Level Step -Message 'Generando informe HTML de SITs...'

        $sections = New-PavSitSections -Data $Data

        $doc = New-PavHtmlDocument -Title 'SITs Personalizados — Microsoft Purview' `
            -Subtitle 'Tipos de información sensible del RulePackage (solo lectura)' -ClientName $ClientName -Sections $sections
        $doc | Set-Content -Path $htmlPath -Encoding UTF8
        Write-PavLog -Level Success -Message "Informe HTML: $htmlPath"

        $excelPath = $null
        if (-not $SkipExcel) {
            $sitRows = foreach ($e in $entities) {
                [pscustomobject]@{ 'Nombre' = $e.Name; 'ID' = $e.Id; 'Descripción' = $e.Description
                    'Confianza recomendada' = $e.RecommendedConfidence; 'Proximidad' = $e.PatternsProximity
                    'Patrones' = @($e.Patterns).Count; 'Modificado' = $e.LastModified }
            }
            $patRows = foreach ($e in $entities) {
                foreach ($p in @($e.Patterns)) {
                    [pscustomobject]@{ 'SIT' = $e.Name; 'Confianza' = $p.ConfidenceLevel; 'Proximidad' = $p.Proximity
                        'IdMatch' = $p.IdMatchRef
                        'Soporte' = (@($p.Matches | ForEach-Object { $_.IdRef }) -join '; ')
                        'Filtro' = $p.FilterId }
                }
            }
            $regexRows = foreach ($k in $Data.RegexMap.Keys) {
                [pscustomobject]@{ 'Id' = $k; 'Patrón' = $Data.RegexMap[$k] }
            }
            $kwRows = foreach ($k in $Data.KeywordMap.Keys) {
                foreach ($g in $Data.KeywordMap[$k]) {
                    [pscustomobject]@{ 'Id' = $k; 'MatchStyle' = $g.MatchStyle
                        'Términos' = (@($g.Terms | ForEach-Object { $_.Text }) -join ', ') }
                }
            }
            $excelPath = Export-PavExcelWorkbook -Path $xlsxPath -Title 'Microsoft Purview - SITs Personalizados' -Sheets ([ordered]@{
                'SITs' = $sitRows; 'Patrones' = $patRows; 'Regex' = $regexRows; 'Keywords' = $kwRows
            })
        }

        [pscustomobject]@{ PSTypeName = 'PurviewAssessment.ReportResult'
            Workload = 'SIT'; HtmlPath = $htmlPath; ExcelPath = $excelPath }
    }
}
