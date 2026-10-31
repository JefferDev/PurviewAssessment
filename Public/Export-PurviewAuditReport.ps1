function Export-PurviewAuditReport {
<#
.SYNOPSIS
    Genera el informe de auditoría (HTML + Excel).
.DESCRIPTION
    HTML: estado del registro de auditoría unificada con sus hallazgos, y
    detalle de las directivas de retención. Excel: Resumen Ejecutivo,
    Estado, Hallazgos y Directivas de Retención.
.PARAMETER Data
    Datos de Get-PurviewAuditData. Si se omite, se recolectan.
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
    Export-PurviewAuditReport -OutputPath C:\Reports -ClientName 'Cliente Demo'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)]
        [PSTypeName('PurviewAssessment.AuditData')]
        [object]$Data,

        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter()][string]$ClientName = '',
        [switch]$SkipExcel,

        # Oculta los avisos derivados de propiedades no concluyentes
        [switch]$HideInconclusiveWarnings
    )

    process {
        if ($PSBoundParameters.ContainsKey('HideInconclusiveWarnings')) { $script:PavHideInconclusive = [bool]$HideInconclusiveWarnings }
        if (-not $Data) { $Data = Get-PurviewAuditData }
        if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

        $ts       = Get-Date -Format 'yyyy-MM-dd_HH-mm'
        $htmlPath = Join-Path $OutputPath "Audit_Report_$ts.html"
        $xlsxPath = Join-Path $OutputPath "Audit_Report_$ts.xlsx"
        $pols     = @($Data.RetentionPolicies)
        $findings = @($Data.Findings)
        $st       = $Data.Status

        Write-PavLog -Level Step -Message 'Generando informe HTML de auditoría...'
        $sections = New-PavAuditSections -Data $Data

        $doc = New-PavHtmlDocument -Title 'Auditoría — Microsoft Purview' `
            -Subtitle 'Assessment del registro de auditoría unificada y sus directivas de retención (solo lectura)' `
            -ClientName $ClientName -Sections $sections `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Directivas' -Value "$($pols.Count)"),
                (New-PavStat -Label 'Auditoría unificada' -Value "$($st.UnifiedAuditLogIngestion)"),
                (New-PavStat -Label 'Auditoría de buzones' -Value "$($st.MailboxAuditing)")
            ))
        $doc | Set-Content -Path $htmlPath -Encoding UTF8
        Write-PavLog -Level Success -Message "Informe HTML: $htmlPath"

        $excelPath = $null
        if (-not $SkipExcel) {
            $resumen = @(
                [pscustomobject]@{ Metrica = 'Ingesta de auditoria unificada'; Valor = $st.UnifiedAuditLogIngestion }
                [pscustomobject]@{ Metrica = 'Nota de verificacion';           Valor = $st.IngestionNote }
                [pscustomobject]@{ Metrica = 'Auditoria de administracion';    Valor = $st.AdminAuditLog }
                [pscustomobject]@{ Metrica = 'Auditoria de buzones';           Valor = $st.MailboxAuditing }
                [pscustomobject]@{ Metrica = 'Sesion de Exchange Online';      Valor = $st.ExchangeOnlineSession }
                [pscustomobject]@{ Metrica = 'Directivas de retencion';        Valor = $pols.Count }
                [pscustomobject]@{ Metrica = 'Directivas habilitadas';         Valor = @($pols | Where-Object { "$($_.Enabled)" -eq 'True' }).Count }
                [pscustomobject]@{ Metrica = 'Directivas sin ambito';          Valor = @($pols | Where-Object AppliesToAll).Count }
                [pscustomobject]@{ Metrica = 'Retencion maxima configurada';   Valor = $(if ($pols.Count) { ($pols | Sort-Object RetentionDays -Descending | Select-Object -First 1).RetentionDuration } else { 'N/D' }) }
                [pscustomobject]@{ Metrica = 'Cliente';                        Valor = $ClientName }
                [pscustomobject]@{ Metrica = 'Fecha';                          Valor = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
            )
            $sheets = [ordered]@{ 'Resumen Ejecutivo' = $resumen }
            if ($pols.Count) {
                $sheets['Directivas Retencion'] = @($pols | Select-Object Name, Description, Enabled, Priority,
                    RetentionDuration, RetentionRaw, RetentionDays, RecordTypes, RecordTypeCount, Operations,
                    OperationCount, UserIds, UserCount, AppliesToAll, Mode, Workload, DistributionStatus,
                    DistributionSyncStatus, CreatedBy, LastModifiedBy, CreatedUtc, LastModifiedUtc, Guid)
            }
            $excelPath = Export-PavExcelWorkbook -Path $xlsxPath -Title 'Microsoft Purview - Auditoria' -Sheets $sheets
        }

        [pscustomobject]@{
            PSTypeName = 'PurviewAssessment.ReportResult'
            Workload   = 'AUDIT'
            HtmlPath   = $htmlPath
            ExcelPath  = $excelPath
        }
    }
}
