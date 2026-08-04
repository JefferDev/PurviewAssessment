function Invoke-PurviewAssessment {
<#
.SYNOPSIS
    Ejecuta el assessment completo (o selectivo) de Microsoft Purview y
    genera el paquete de entregables en una sola línea.
.DESCRIPTION
    Orquestador del módulo. Para cada carga de trabajo seleccionada:
      1. Recolecta datos (resiliente: un fallo en una carga no detiene el
         resto; la sección queda marcada como 'No evaluado').
      2. Genera el informe individual COMPLETO (HTML + Excel) de esa carga
         con los mismos exportadores dedicados.
    Y produce además los entregables consolidados:
      - HTML consolidado ejecutivo: una pestaña por carga con estadísticas
        y tabla resumen; el detalle completo vive en los informes
        individuales del mismo paquete.
      - Excel consolidado: una hoja resumen por carga con prefijo.
      - Backup JSON con todos los datos crudos parseados (evidencia).
    Diseño de solo lectura: la ejecución no realiza ningún cambio sobre el
    tenant. Compliance Manager está excluido por diseño (sin cmdlets en
    ExchangeOnlineManagement).
.PARAMETER Workload
    MIP | DLP | IRM | CC | DLM | SIT | All (por defecto: All).
    MIP incluye etiquetas, directivas de publicación y etiquetado
    automático. 'Labels' se acepta como alias de 'MIP' por
    compatibilidad con versiones anteriores.
.PARAMETER OutputPath
    Carpeta raíz del paquete de entregables (se crea si no existe).
.PARAMETER ClientName
    Nombre del cliente (rotula todos los informes).
.PARAMETER UserPrincipalName
    UPN para -Connect.
.PARAMETER Connect
    Establece la sesión implícitamente (único punto del módulo donde se
    permite conexión implícita).
.PARAMETER IncludeDisabled
    Incluye directivas/reglas deshabilitadas (DLP y CC).
.PARAMETER SitXmlPath
    Modo offline para SIT: parsea este XML en lugar de exportar en línea.
.PARAMETER SkipExcel
    Omite todos los libros Excel.
.PARAMETER SkipJsonBackup
    Omite el backup JSON de datos crudos.
.OUTPUTS
    [pscustomobject] con ConsolidatedHtml, ConsolidatedExcel, JsonBackup,
    Reports (resultados por carga) y Errors.
.EXAMPLE
    Invoke-PurviewAssessment -Connect -UserPrincipalName consultor@cliente.com -OutputPath C:\Reports -ClientName 'Contoso'
.EXAMPLE
    Invoke-PurviewAssessment -Workload DLP,Labels -OutputPath C:\Reports -IncludeDisabled
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('MIP', 'Labels', 'DLP', 'IRM', 'CC', 'DLM', 'SIT', 'All')]
        [string[]]$Workload = 'All',

        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter()][string]$ClientName = '',
        [Parameter()][string]$UserPrincipalName,
        [switch]$Connect,
        [switch]$IncludeDisabled,
        [Parameter()][string]$SitXmlPath,
        [switch]$SkipExcel,
        [switch]$SkipJsonBackup
    )

    $resolved = if ($Workload -contains 'All') { @('MIP', 'DLP', 'IRM', 'CC', 'DLM', 'SIT') } else { @($Workload) }
    # 'Labels' es alias histórico de 'MIP': se normaliza y se deduplica
    $resolved = @($resolved | ForEach-Object { if ($_ -eq 'Labels') { 'MIP' } else { $_ } } | Select-Object -Unique)
    if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

    if ($Connect) { Connect-PurviewAssessment -UserPrincipalName $UserPrincipalName }
    # SIT offline puro no requiere sesión; cualquier otra carga sí.
    $onlyOfflineSit = ($resolved.Count -eq 1 -and $resolved[0] -eq 'SIT' -and $SitXmlPath)
    if (-not $onlyOfflineSit) { Assert-PavConnection }

    $displayNames = @{ SIT = 'Custom SIT' }
    $displayList  = ($resolved | ForEach-Object { if ($displayNames.ContainsKey($_)) { $displayNames[$_] } else { $_ } }) -join ', '
    Write-PavLog -Banner -Level Step -Message "ASSESSMENT DE MICROSOFT PURVIEW — $displayList"

    # ── FASE 1: recolección resiliente ────────────────────────────────────────
    $data   = [ordered]@{}
    $errors = [ordered]@{}
    foreach ($w in $resolved) {
        try {
            Write-PavLog -Level Step -Message "[$w] Recolectando..."
            $data[$w] = switch ($w) {
                'MIP'    { Get-PurviewLabelData }
                'DLP'    { Get-PurviewDlpData -IncludeDisabled:$IncludeDisabled }
                'IRM'    { Get-PurviewIrmData }
                'CC'     { Get-PurviewCcData -IncludeDisabled:$IncludeDisabled }
                'DLM'    { Get-PurviewDlmData }
                'SIT'    { if ($SitXmlPath) { Get-PurviewSitData -XmlPath $SitXmlPath }
                           else             { Get-PurviewSitData -Online -SaveXmlTo $OutputPath } }
            }
        }
        catch {
            $errors[$w] = $_.Exception.Message
            $data[$w]   = $null
            Write-PavLog -Level Warn -Message "[$w] Omitida: $($_.Exception.Message)"
        }
    }

    # ── FASE 2: informes individuales completos ───────────────────────────────
    $reports = [ordered]@{}
    foreach ($w in $resolved) {
        if ($null -eq $data[$w]) { continue }
        try {
            $reports[$w] = switch ($w) {
                'MIP'    { Export-PurviewLabelReport -Data $data[$w] -OutputPath $OutputPath -ClientName $ClientName -SkipExcel:$SkipExcel }
                'DLP'    { Export-PurviewDlpReport   -Data $data[$w] -OutputPath $OutputPath -ClientName $ClientName -SkipExcel:$SkipExcel }
                'IRM'    { Export-PurviewIrmReport   -Data $data[$w] -OutputPath $OutputPath -ClientName $ClientName -SkipExcel:$SkipExcel }
                'CC'     { Export-PurviewCcReport    -Data $data[$w] -OutputPath $OutputPath -ClientName $ClientName -SkipExcel:$SkipExcel }
                'DLM'    { Export-PurviewDlmReport   -Data $data[$w] -OutputPath $OutputPath -ClientName $ClientName -SkipExcel:$SkipExcel }
                'SIT'    { Export-PurviewSitReport   -Data $data[$w] -OutputPath $OutputPath -ClientName $ClientName -SkipExcel:$SkipExcel }
            }
        }
        catch {
            $errors[$w] = "Informe individual falló: $($_.Exception.Message)"
            Write-PavLog -Level Warn -Message "[$w] $($errors[$w])"
        }
    }

    # ── FASE 3: consolidado ejecutivo ─────────────────────────────────────────
    $ts = Get-Date -Format 'yyyy-MM-dd_HH-mm'
    $titles = @{ MIP = 'Etiquetas MIP'; DLP = 'DLP'; IRM = 'Insider Risk'; CC = 'Comm. Compliance'; DLM = 'Retención (DLM)'; SIT = 'SITs personalizados' }

    $sections = @(foreach ($w in $resolved) {
        $d = $data[$w]
        if ($null -eq $d) {
            # Sección 'No evaluado' con el motivo del error
            New-PavHtmlSection -Id "$($w.ToLowerInvariant())-na" -Title $titles[$w] -ContentHtml $null `
                -Description $(if ($errors.Contains($w)) { "Error: $($errors[$w])" } else { '' })
            continue
        }
        # DETALLE COMPLETO: los mismos constructores de secciones (tarjetas
        # colapsables, árboles de AdvancedRule, tablas) que usan los informes
        # individuales, con prefijo de título para desambiguar pestañas.
        $prefix = if ($w -in 'MIP', 'SIT') { '' } else { "$($titles[$w]) · " }
        switch ($w) {
            'MIP'    { New-PavLabelSections -Data $d -TitlePrefix $prefix }
            'DLP'    { New-PavDlpSections   -Data $d -TitlePrefix $prefix }
            'IRM'    { New-PavIrmSections   -Data $d -TitlePrefix $prefix }
            'CC'     { New-PavCcSections    -Data $d -TitlePrefix $prefix }
            'DLM'    { New-PavDlmSections   -Data $d -TitlePrefix $prefix }
            'SIT'    { New-PavSitSections   -Data $d -TitlePrefix $prefix }
        }
    })

    $evaluated = @($resolved | Where-Object { $null -ne $data[$_] })
    $consolidatedHtml = Join-Path $OutputPath "PurviewAssessment_Consolidado_$ts.html"
    $doc = New-PavHtmlDocument -Title 'Assessment de Microsoft Purview' `
        -Subtitle 'Informe consolidado con detalle completo por carga de trabajo (solo lectura). Compliance Manager excluido por diseño (sin cmdlets EXO/IPPS).' `
        -ClientName $ClientName -Sections @($sections) `
        -StatsHtml (New-PavStatGroup -Stats (
            (New-PavStat -Label 'Cargas evaluadas' -Value "$($evaluated.Count) de $($resolved.Count)"),
            (New-PavStat -Label 'Con errores' -Value "$($errors.Count)")
        ))
    $doc | Set-Content -Path $consolidatedHtml -Encoding UTF8
    Write-PavLog -Level Success -Message "Consolidado HTML: $consolidatedHtml"

    # Excel consolidado (hojas resumen con prefijo por carga)
    $consolidatedExcel = $null
    if (-not $SkipExcel -and $evaluated.Count -gt 0) {
        $sheets = [ordered]@{}
        foreach ($w in $evaluated) {
            $d = $data[$w]
            switch ($w) {
                'MIP'    { $sheets['MIP-Etiquetas']  = @($d.Labels  | Select-Object Priority, DisplayName, ParentDisplay, Color, HasEncryption, HasContentMarking, PublishedInPolicies)
                           $autoP = @(Get-PavProp $d 'AutoLabelPolicies' @())
                           if ($autoP.Count) {
                               $autoR = @(Get-PavProp $d 'AutoLabelRules' @())
                               $sheets['MIP-AutoEtiquetado'] = @($autoP | ForEach-Object {
                                   [pscustomobject]@{ 'Nombre' = $_.Name; 'Habilitada' = $_.Enabled; 'Modo' = $_.ModeFriendly
                                       'Etiqueta aplicada' = $_.ApplySensitivityLabel; 'Sobrescribe' = $_.OverwriteLabel
                                       'Asignación Exchange' = $_.ExchangeLocation; 'Asignación SharePoint' = $_.SharePointLocation
                                       'Asignación OneDrive' = $_.OneDriveLocation; 'Ámbitos adaptativos' = $_.AdaptiveScopes
                                       'Coincidencias (simulación)' = $_.SimulationItemsMatched
                                       'Distribución' = $_.DistributionStatus
                                       'Reglas' = @($autoR | Where-Object PolicyName -eq $_.Name).Count } })
                           }
                           # Asignación actual de la directiva: ubicaciones donde aplica
                           $sheets['MIP-Directivas'] = @($d.Policies | ForEach-Object {
                               [pscustomobject]@{ 'Nombre' = $_.Name; 'Habilitada' = $_.Enabled; 'Modo' = $_.Mode
                                   'Nro etiquetas' = $_.LabelsCount; 'Obligatoria' = $_.Mandatory
                                   'Asignación Exchange' = $_.ExchangeLocation; 'Asignación SharePoint' = $_.SharePointLocation
                                   'Asignación OneDrive' = $_.OneDriveLocation; 'Asignación Grupos M365' = $_.ModernGroupLocation } }) }
                'DLP'    { $sheets['DLP-Directivas'] = @($d.Policies | Select-Object Name, Enabled, Mode, Workload, Priority)
                           $sheets['DLP-Reglas']     = @($d.Rules | Select-Object PolicyName, RuleName, Disabled, IsAdvancedRule, SensitiveInfoTypes, BlockAccess) }
                'IRM'    { $sheets['IRM-Directivas'] = @($d.Policies | ForEach-Object {
                               [pscustomobject]@{ 'Nombre' = $_.Name; 'Habilitada' = $_.Enabled; 'Escenario' = $_.Scenario
                                   'Categoría' = $_.PolicyCategory; 'Salud' = $_.HealthStatus
                                   'Asignación (usuarios Exchange)' = $_.ExchangeLocation; 'Workload' = $_.Workload } }) }
                'CC'     { $sheets['CC-Directivas']  = @($d.Policies | ForEach-Object {
                               $pol = $_
                               # Asignación actual: orígenes de contenido supervisados (desde las reglas)
                               $asig = @(@($d.Rules) | Where-Object { $_.PolicyRef -eq $pol.Guid -or $_.RuleName -eq $pol.Name } |
                                   ForEach-Object { $_.ContentSources } | Where-Object { $_ -and $_ -ne 'N/D' } | Sort-Object -Unique) -join ' || '
                               [pscustomobject]@{ 'Nombre' = $pol.Name; 'Habilitada' = $pol.Enabled; 'Estado' = $pol.PolicyStatus
                                   'Aprovisionamiento' = $pol.ProvisionStatus; 'Reglas' = $pol.RulesCount
                                   'Asignación (orígenes supervisados)' = $asig; 'Workloads' = $pol.Workloads
                                   'Revisores' = $pol.Reviewers; 'Buzón de revisión' = $pol.ReviewMailbox } }) }
                'DLM'    { $sheets['DLM-Directivas'] = @($d.Policies | Select-Object Name, PolicyType, Mode, Enabled, ConfiguredLocations)
                           $sheets['DLM-Etiquetas']  = @($d.Tags | Select-Object Name, LabelCategory, RetentionAction, RetentionDuration, HasFilePlan) }
                'SIT'    { $sheets['SIT-Inventario'] = @($d.Entities | ForEach-Object { [pscustomobject]@{ Nombre = $_.Name; Id = $_.Id; Confianza = $_.RecommendedConfidence; Patrones = @($_.Patterns).Count } }) }
            }
        }
        $consolidatedExcel = Export-PavExcelWorkbook -Path (Join-Path $OutputPath "PurviewAssessment_Consolidado_$ts.xlsx") `
            -Title 'Microsoft Purview Assessment - Consolidado' -Sheets $sheets
    }

    # Backup JSON de datos crudos parseados (generaliza el backup que solo tenía CC)
    $jsonBackup = $null
    if (-not $SkipJsonBackup -and $evaluated.Count -gt 0) {
        $jsonBackup = Join-Path $OutputPath "PurviewAssessment_Datos_$ts.json"
        $export = [ordered]@{}
        foreach ($w in $evaluated) { $export[$w] = $data[$w] }
        ($export | ConvertTo-Json -Depth 15 -WarningAction SilentlyContinue) | Set-Content -Path $jsonBackup -Encoding UTF8
        Write-PavLog -Level Success -Message "Backup JSON: $jsonBackup"
    }

    if ($errors.Count) { Write-PavLog -Level Warn -Message "Assessment finalizado con $($errors.Count) carga(s) omitida(s): $($errors.Keys -join ', ')" }
    else { Write-PavLog -Level Success -Message 'Assessment finalizado sin errores.' }

    [pscustomobject]@{
        PSTypeName        = 'PurviewAssessment.AssessmentResult'
        Workloads         = $resolved
        Evaluated         = $evaluated
        ConsolidatedHtml  = $consolidatedHtml
        ConsolidatedExcel = $consolidatedExcel
        JsonBackup        = $jsonBackup
        Reports           = $reports
        Errors            = $errors
    }
}
