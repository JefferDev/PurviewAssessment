function Export-PurviewRmReport {
<#
.SYNOPSIS
    Genera el informe de Records Management (HTML + Excel).
.DESCRIPTION
    HTML: pestañas de hallazgos de gobierno, file plan, retención por
    eventos, etiquetas de registro y ámbitos adaptativos.
    Excel: Resumen Ejecutivo, Hallazgos, File Plan, Citaciones, Tipos de
    Evento, Eventos, Etiquetas de Registro y Ámbitos Adaptativos.
.PARAMETER Data
    Datos de Get-PurviewRmData. Si se omite, se recolectan.
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
    Export-PurviewRmReport -OutputPath C:\Reports -ClientName 'Cliente Demo'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)]
        [PSTypeName('PurviewAssessment.RmData')]
        [object]$Data,

        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter()][string]$ClientName = '',
        [switch]$SkipExcel,

        # Oculta los avisos derivados de propiedades no concluyentes
        [switch]$HideInconclusiveWarnings
    )

    process {
        if ($PSBoundParameters.ContainsKey('HideInconclusiveWarnings')) { $script:PavHideInconclusive = [bool]$HideInconclusiveWarnings }
        if (-not $Data) { $Data = Get-PurviewRmData }
        if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

        $ts       = Get-Date -Format 'yyyy-MM-dd_HH-mm'
        $htmlPath = Join-Path $OutputPath "RecordsManagement_Report_$ts.html"
        $xlsxPath = Join-Path $OutputPath "RecordsManagement_Report_$ts.xlsx"

        $props    = @($Data.FilePlanProperties)
        $evTypes  = @($Data.EventTypes)
        $events   = @($Data.Events)
        $recTags  = @($Data.RecordTags)
        $scopes   = @($Data.AdaptiveScopes)
        $findings = @($Data.Findings)

        Write-PavLog -Level Step -Message 'Generando informe HTML de Records Management...'
        $sections = New-PavRmSections -Data $Data

        $doc = New-PavHtmlDocument -Title 'Records Management — Microsoft Purview' `
            -Subtitle 'Assessment de gestión de registros: file plan, retención por eventos y disposición (solo lectura)' `
            -ClientName $ClientName -Sections $sections `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Descriptores' -Value "$($props.Count)"),
                (New-PavStat -Label 'Etiquetas de registro' -Value "$($recTags.Count)"),
                (New-PavStat -Label 'Tipos de evento' -Value "$($evTypes.Count)"),
                (New-PavStat -Label 'Hallazgos' -Value "$($findings.Count)")
            ))
        $doc | Set-Content -Path $htmlPath -Encoding UTF8
        Write-PavLog -Level Success -Message "Informe HTML: $htmlPath"

        $excelPath = $null
        if (-not $SkipExcel) {
            $resumen = @(
                [pscustomobject]@{ Metrica = 'Descriptores de file plan';      Valor = $props.Count }
                [pscustomobject]@{ Metrica = 'Departamentos';                  Valor = @($props | Where-Object Type -eq 'Department').Count }
                [pscustomobject]@{ Metrica = 'Categorias';                     Valor = @($props | Where-Object Type -eq 'Category').Count }
                [pscustomobject]@{ Metrica = 'Subcategorias';                  Valor = @($props | Where-Object Type -eq 'SubCategory').Count }
                [pscustomobject]@{ Metrica = 'Autoridades';                    Valor = @($props | Where-Object Type -eq 'Authority').Count }
                [pscustomobject]@{ Metrica = 'Citaciones';                     Valor = @($props | Where-Object Type -eq 'Citation').Count }
                [pscustomobject]@{ Metrica = 'Citaciones sin referencia';      Valor = @($props | Where-Object { $_.Type -eq 'Citation' -and -not $_.HasCitationDetail }).Count }
                [pscustomobject]@{ Metrica = 'IDs de referencia';              Valor = @($props | Where-Object Type -eq 'ReferenceId').Count }
                [pscustomobject]@{ Metrica = 'Tipos de evento de retencion';   Valor = $evTypes.Count }
                [pscustomobject]@{ Metrica = 'Tipos de evento sin etiquetas';  Valor = @($evTypes | Where-Object LinkedLabelCount -eq 0).Count }
                [pscustomobject]@{ Metrica = 'Eventos de retencion activos';   Valor = $events.Count }
                [pscustomobject]@{ Metrica = 'Etiquetas de retencion';         Valor = @(Get-PavProp $Data 'RetentionLabels' @()).Count }
                [pscustomobject]@{ Metrica = 'Directivas de publicacion';      Valor = @(Get-PavProp $Data 'PublishPolicies' @()).Count }
                [pscustomobject]@{ Metrica = 'Etiquetas de registro';          Valor = $recTags.Count }
                [pscustomobject]@{ Metrica = 'Registros regulados';            Valor = @($recTags | Where-Object Regulatory).Count }
                [pscustomobject]@{ Metrica = 'Etiquetas sin file plan';        Valor = @($recTags | Where-Object { -not $_.HasFilePlan }).Count }
                [pscustomobject]@{ Metrica = 'Etiquetas con revision';         Valor = @($recTags | Where-Object HasReviewStages).Count }
                [pscustomobject]@{ Metrica = 'Ambitos adaptativos';            Valor = $scopes.Count }
                [pscustomobject]@{ Metrica = 'Hallazgos de gobierno';          Valor = $findings.Count }
                [pscustomobject]@{ Metrica = 'Hallazgos severidad alta';       Valor = @($findings | Where-Object Severity -eq 'Alta').Count }
                [pscustomobject]@{ Metrica = 'Almacenamiento de etiquetas';    Valor = $Data.TagStorage }
                [pscustomobject]@{ Metrica = 'Cliente';                        Valor = $ClientName }
                [pscustomobject]@{ Metrica = 'Fecha';                          Valor = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
            )

            $sheets = [ordered]@{ 'Resumen Ejecutivo' = $resumen }
            if ($findings.Count) { $sheets['Hallazgos'] = @($findings | Select-Object Severity, Area, Finding, Detail) }
            if ($props.Count) {
                $sheets['File Plan'] = @($props | Select-Object Type, Name, DisplayName, UnrestrictedName, Comment,
                    Priority, Workload, Mode, Disabled, ReadOnly, CreatedBy, LastModifiedBy, CreatedUtc, LastModifiedUtc, Guid)
                $cit = @($props | Where-Object Type -eq 'Citation')
                if ($cit.Count) {
                    $sheets['Citaciones'] = @($cit | Select-Object Name, CitationJurisdiction, CitationUrl,
                        HasCitationDetail, Priority, LastModifiedBy, LastModifiedUtc, Guid)
                }
            }
            $retL = @(Get-PavProp $Data 'RetentionLabels' @())
            if ($retL.Count) {
                $sheets['Etiquetas Retencion'] = @($retL | Select-Object Name, LabelCategory, RetentionAction,
                    RetentionDuration, RetentionType, IsRecordLabel, Regulatory, HasFilePlan, Department, Category,
                    SubCategory, Authority, Citation, ReferenceId, HasReviewStages, EventTypeId, Workload, CreatedBy, Guid)
            }
            $pubP = @(Get-PavProp $Data 'PublishPolicies' @())
            if ($pubP.Count) {
                $sheets['Directivas Publicacion'] = @($pubP | Select-Object Name, PolicyType, Enabled, Mode,
                    LabelCount, LabelsPublished, Exchange, SharePoint, OneDrive, TeamsChat, TeamsChannel, ModernGroup,
                    IsAdaptive, RestrictiveRetention, DistributionStatus, CreatedBy, LastModifiedUtc, Guid)
            }
            if ($evTypes.Count) {
                $sheets['Tipos de Evento'] = @($evTypes | Select-Object Name, Comment, LinkedLabelCount, LinkedLabels,
                    Priority, Workload, Mode, Disabled, CreatedBy, LastModifiedBy, CreatedUtc, LastModifiedUtc, Guid)
            }
            if ($events.Count) {
                $sheets['Eventos'] = @($events | Select-Object Name, EventType, EventDateTime, Status,
                    SharePointAssetIdQuery, ExchangeAssetIdQuery, AssetId, Comment, CreatedBy, CreatedUtc)
            }
            if ($recTags.Count) {
                $sheets['Etiquetas de Registro'] = @($recTags | Select-Object Name, LabelCategory, RetentionAction,
                    RetentionDuration, RetentionType, IsRecordLabel, Regulatory, HasFilePlan, Department, Category,
                    SubCategory, Authority, Citation, ReferenceId, HasReviewStages, ReviewerEmail, EventTypeId,
                    Workload, CreatedBy, Guid)
            }
            if ($scopes.Count) {
                $sheets['Ambitos Adaptativos'] = @($scopes | Select-Object Name, LocationType, FilterQuery, RawQuery,
                    Comment, Disabled, Mode, CreatedBy, LastModifiedBy, CreatedUtc, LastModifiedUtc, Guid)
            }

            $excelPath = Export-PavExcelWorkbook -Path $xlsxPath -Title 'Microsoft Purview - Records Management' -Sheets $sheets
        }

        [pscustomobject]@{
            PSTypeName = 'PurviewAssessment.ReportResult'
            Workload   = 'RM'
            HtmlPath   = $htmlPath
            ExcelPath  = $excelPath
        }
    }
}
