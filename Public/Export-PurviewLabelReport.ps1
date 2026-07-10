function Export-PurviewLabelReport {
<#
.SYNOPSIS
    Genera el informe de etiquetas de sensibilidad (HTML + Excel).
.DESCRIPTION
    Presentación sobre los datos de Get-PurviewLabelData usando el motor
    compartido: HTML con tema día/noche, pestañas Etiquetas/Directivas,
    tarjetas colapsables y búsqueda; y libro Excel con el estándar de los
    informes v3 (4 hojas: Resumen Etiquetas, Detalle Etiquetas, Resumen
    Directivas, Detalle Directivas — el detalle en formato largo
    Elemento/Sección/Propiedad/Valor con el detalle técnico completo).
.PARAMETER Data
    Datos de Get-PurviewLabelData. Si se omite, se recolectan (requiere
    sesión activa).
.PARAMETER OutputPath
    Carpeta de salida (se crea si no existe).
.PARAMETER ClientName
    Nombre del cliente para portada y pie.
.PARAMETER SkipExcel
    Omite el libro Excel.
.OUTPUTS
    [pscustomobject] con HtmlPath y ExcelPath.
.EXAMPLE
    Connect-PurviewAssessment
    Export-PurviewLabelReport -OutputPath C:\Reports -ClientName 'Contoso'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)]
        [PSTypeName('PurviewAssessment.LabelData')]
        [object]$Data,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [string]$ClientName = '',

        [switch]$SkipExcel
    )

    process {
        if (-not $Data) { $Data = Get-PurviewLabelData }
        if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

        $ts       = Get-Date -Format 'yyyy-MM-dd_HH-mm'
        $htmlPath = Join-Path $OutputPath "SensitivityLabels_Report_$ts.html"
        $xlsxPath = Join-Path $OutputPath "SensitivityLabels_Report_$ts.xlsx"
        $labels   = @($Data.Labels)
        $policies = @($Data.Policies)

        # ══ HTML ═════════════════════════════════════════════════════════════
        Write-PavLog -Level Step -Message 'Generando informe HTML de etiquetas...'

        $sections = New-PavLabelSections -Data $Data

        $doc = New-PavHtmlDocument -Title 'Etiquetas de Sensibilidad — Microsoft Purview' `
            -Subtitle 'Assessment de Information Protection (solo lectura)' `
            -ClientName $ClientName -Sections $sections `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Etiquetas' -Value "$($labels.Count)"),
                (New-PavStat -Label 'Directivas' -Value "$($policies.Count)")
            ))
        $doc | Set-Content -Path $htmlPath -Encoding UTF8
        Write-PavLog -Level Success -Message "Informe HTML: $htmlPath"

        # ══ Excel (estándar v3: 4 hojas) ═════════════════════════════════════
        $excelPath = $null
        if (-not $SkipExcel) {
            $summary = foreach ($l in ($labels | Sort-Object Priority)) {
                [pscustomobject]@{
                    'Prioridad' = $l.Priority; 'Nombre interno' = $l.Name
                    'Nombre para mostrar' = $l.DisplayName; 'Etiqueta padre' = $l.ParentDisplay
                    'Es grupo' = $l.IsParent; 'Color' = $l.Color
                    'Habilitada' = $l.Enabled; 'Modo' = $l.Mode
                    'Cifrado' = $l.HasEncryption; 'Marcas visuales' = $l.HasContentMarking
                    'ContentType' = $l.ContentType; 'Workload' = $l.Workload
                    'Creado por' = $l.CreatedBy
                    'Creacion' = $l.WhenCreatedUTC; 'Modificacion' = $l.WhenChangedUTC
                    'Publicada en directivas' = $l.PublishedInPolicies
                }
            }
            # Detalle técnico completo en formato largo
            # Detalle técnico completo en formato largo con Sección (estándar v3)
            $labelSectionMap = [ordered]@{
                'General'       = @('Priority','Name','DisplayName','Guid','ImmutableId','ParentId','ParentDisplay','IsParent','Comment')
                'Configuracion' = @('Color','ContentType','Tooltip','Workload','Mode','Enabled')
                'Proteccion'    = @('HasEncryption','HasHeader','HasFooter','HasWatermark','HasContentMarking','HasProtectGroup','HasProtectSites')
                'Idiomas'       = @('LocaleDisplayName','LocaleAll')
                'Publicacion'   = @('PublishedInPolicies')
                'Auditoria'     = @('CreatedBy','WhenCreatedUTC','WhenChangedUTC')
                'Raw'           = @('SettingsRaw','ActionsRaw')
            }
            $labelDetail = foreach ($l in ($labels | Sort-Object Priority)) {
                foreach ($sec in $labelSectionMap.Keys) {
                    foreach ($pname in $labelSectionMap[$sec]) {
                        $p = $l.PSObject.Properties[$pname]
                        if ($null -eq $p) { continue }
                        [pscustomobject]@{
                            'Etiqueta' = $l.DisplayName; 'Seccion' = $sec; 'Propiedad' = $pname
                            'Valor' = if ($null -eq $p.Value -or "$($p.Value)" -eq '') { 'No configurado' } else { "$($p.Value)" }
                        }
                    }
                }
            }
            $polSummary = foreach ($p in $policies) {
                [pscustomobject]@{
                    'Nombre' = $p.Name; 'Tipo' = $p.Type; 'GUID' = $p.Guid
                    'Habilitada' = $p.Enabled; 'Modo' = $p.Mode; 'Prioridad' = $p.Priority
                    'Workload' = $p.Workload
                    'Etiquetas publicadas' = ($p.ScopedLabels -join ', '); 'Nro etiquetas' = $p.LabelsCount
                    'Obligatoria' = $p.Mandatory; 'Predeterminada' = $p.DefaultLabelId
                    'Outlook default' = $p.OutlookDefaultLabelId
                    'Justif. degradacion' = $p.RequireDowngradeJustification
                    'Attachment action' = $p.AttachmentAction; 'Distribucion' = $p.DistributionStatus
                    'ExchangeLocation' = $p.ExchangeLocation; 'Creado por' = $p.CreatedBy
                    'Creacion' = $p.WhenCreatedUTC; 'Modificacion' = $p.WhenChangedUTC
                }
            }
            $polSectionMap = [ordered]@{
                'General'       = @('Name','Guid','Type','Enabled','Mode','Workload','DistributionStatus')
                'Configuracion' = @('Mandatory','DefaultLabelId','OutlookDefaultLabelId','RequireDowngradeJustification','AttachmentAction')
                'Etiquetas'     = @('ScopedLabels','LabelsCount')
                'Ubicaciones'   = @('ExchangeLocation','SharePointLocation','OneDriveLocation','ModernGroupLocation')
                'Auditoria'     = @('WhenCreatedUTC','WhenChangedUTC')
                'Raw'           = @('SettingsRaw')
            }
            $polDetail = foreach ($p in $policies) {
                foreach ($sec in $polSectionMap.Keys) {
                    foreach ($pname in $polSectionMap[$sec]) {
                        $prop = $p.PSObject.Properties[$pname]
                        if ($null -eq $prop) { continue }
                        $v = if ($prop.Value -is [System.Collections.IEnumerable] -and $prop.Value -isnot [string]) { @($prop.Value) -join ', ' } else { "$($prop.Value)" }
                        [pscustomobject]@{
                            'Directiva' = $p.Name; 'Seccion' = $sec; 'Propiedad' = $pname
                            'Valor' = if ([string]::IsNullOrEmpty($v)) { 'No configurado' } else { $v }
                        }
                    }
                }
            }
            $excelPath = Export-PavExcelWorkbook -Path $xlsxPath -Title 'Microsoft Purview - Etiquetas de Sensibilidad' -Sheets ([ordered]@{
                'Resumen Etiquetas'  = $summary
                'Detalle Etiquetas'  = $labelDetail
                'Resumen Directivas' = $polSummary
                'Detalle Directivas' = $polDetail
            })
        }

        [pscustomobject]@{
            PSTypeName = 'PurviewAssessment.ReportResult'
            Workload   = 'Labels'
            HtmlPath   = $htmlPath
            ExcelPath  = $excelPath
        }
    }
}
