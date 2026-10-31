function Export-PurviewEdsReport {
<#
.SYNOPSIS
    Genera el informe de eDiscovery (HTML + Excel).
.PARAMETER Data
    Datos de Get-PurviewEdsData. Si se omite, se recolectan.
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
    Export-PurviewEdsReport -OutputPath C:\Reports -ClientName 'Cliente Demo'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)]
        [PSTypeName('PurviewAssessment.EdsData')]
        [object]$Data,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter()][string]$ClientName = '',
        [switch]$SkipExcel,

        # Oculta los avisos derivados de propiedades no concluyentes
        [switch]$HideInconclusiveWarnings
    )
    process {
        if ($PSBoundParameters.ContainsKey('HideInconclusiveWarnings')) { $script:PavHideInconclusive = [bool]$HideInconclusiveWarnings }
        if (-not $Data) { $Data = Get-PurviewEdsData }
        if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
        $ts = Get-Date -Format 'yyyy-MM-dd_HH-mm'
        $htmlPath = Join-Path $OutputPath "eDiscovery_Report_$ts.html"
        $xlsxPath = Join-Path $OutputPath "eDiscovery_Report_$ts.xlsx"

        Write-PavLog -Level Step -Message 'Generando informe HTML de eDiscovery...'
        $sections = New-PavEdsSections -Data $Data
        $doc = New-PavHtmlDocument -Title 'eDiscovery — Microsoft Purview' `
            -Subtitle 'Assessment de descubrimiento electrónico: casos, retenciones legales y búsquedas (solo lectura)' `
            -ClientName $ClientName -Sections $sections `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Casos' -Value "$(@($Data.Cases).Count)"),
                (New-PavStat -Label 'Retenciones' -Value "$(@($Data.HoldPolicies).Count)"),
                (New-PavStat -Label 'Búsquedas' -Value "$(@($Data.Searches).Count)")
            ))
        $doc | Set-Content -Path $htmlPath -Encoding UTF8
        Write-PavLog -Level Success -Message "Informe HTML: $htmlPath"

        $excelPath = $null
        if (-not $SkipExcel) {
            $sheets = [ordered]@{ 'Resumen' = @(
                [pscustomobject]@{ Metrica='Casos';                Valor=@($Data.Cases).Count }
                [pscustomobject]@{ Metrica='Casos activos';        Valor=@($Data.Cases | Where-Object Status -ne 'Closed').Count }
                [pscustomobject]@{ Metrica='Retenciones legales';  Valor=@($Data.HoldPolicies).Count }
                [pscustomobject]@{ Metrica='Retenciones activas';  Valor=@($Data.HoldPolicies | Where-Object { "$($_.Enabled)" -in @('True','Sí') }).Count }
                [pscustomobject]@{ Metrica='Busquedas';            Valor=@($Data.Searches).Count }
                [pscustomobject]@{ Metrica='Cliente';              Valor=$ClientName }
                [pscustomobject]@{ Metrica='Fecha';                Valor=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') } ) }
            if (@($Data.Cases).Count)        { $sheets['Casos'] = @($Data.Cases | Select-Object * -ExcludeProperty PSTypeName) }
            if (@($Data.HoldPolicies).Count) { $sheets['Retenciones'] = @($Data.HoldPolicies | Select-Object * -ExcludeProperty PSTypeName) }
            if (@($Data.Searches).Count)     { $sheets['Busquedas'] = @($Data.Searches | Select-Object * -ExcludeProperty PSTypeName) }
            $excelPath = Export-PavExcelWorkbook -Path $xlsxPath -Title 'Microsoft Purview - eDiscovery' -Sheets $sheets
        }
        [pscustomobject]@{ PSTypeName='PurviewAssessment.ReportResult'; Workload='EDS'; HtmlPath=$htmlPath; ExcelPath=$excelPath }
    }
}
