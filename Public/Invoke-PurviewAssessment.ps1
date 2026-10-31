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
    MIP | DLP | IRM | CC | DLM | RM | AUDIT | SIT | All (por defecto: All).
    AUDIT cubre el registro de auditoría unificada y sus directivas de retención.
    RM cubre Records Management: file plan, retención por eventos,
    etiquetas de registro, disposición y ámbitos adaptativos.
    MIP incluye etiquetas, directivas de publicación y etiquetado
    automático. 'Labels' se acepta como alias de 'MIP' por
    compatibilidad con versiones anteriores.
.PARAMETER OutputPath
    Carpeta raíz del paquete de entregables (se crea si no existe).
.PARAMETER ClientName
    Nombre del cliente (rotula todos los informes).
.PARAMETER UserPrincipalName
    UPN para -Connect.
.PARAMETER HideInconclusiveWarnings
    Oculta en los informes los avisos derivados de propiedades que el
    servicio no reporta de forma concluyente: estados 'Activating' o
    'Pending' y la ausencia de miembros en casos de eDiscovery, que no son
    visibles por PowerShell aunque existan. Recomendado para informes
    dirigidos al cliente.
.PARAMETER SkipDistributionDetail
    Omite la confirmación del estado de distribución por identidad. El
    assessment es más rápido, pero el estado de distribución deja de ser
    concluyente y los controles que dependen de él quedan como
    'Requiere validación'.
.PARAMETER IncludeExchangeOnline
    Con -Connect, establece también la sesión de Exchange Online. Necesaria
    para que los controles de auditoría verifiquen el estado real en lugar de
    quedar como 'Requiere validación'.
.PARAMETER Connect
    Establece la sesión implícitamente (único punto del módulo donde se
    permite conexión implícita).
.PARAMETER IncludeDisabled
    Incluye directivas/reglas deshabilitadas (DLP y CC).
.PARAMETER SitXmlPath
    Modo offline para SIT: parsea estos XML en lugar de exportar en línea.
    Acepta varias rutas, una por RulePackage.
.PARAMETER SkipExcel
    Omite todos los libros Excel.
.PARAMETER SkipJsonBackup
    Omite el backup JSON de datos crudos.
.PARAMETER Evaluate
    Evalúa la configuración contra el catálogo de controles y agrega el
    informe de evaluación (puntaje por dominio y evidencia por control).
.PARAMETER InterviewResponses
    Respuestas del cliente para los controles de proceso, que de otro modo
    quedan como 'Requiere validación'.
.OUTPUTS
    [pscustomobject] con ConsolidatedHtml, ConsolidatedExcel, JsonBackup,
    Reports (resultados por carga) y Errors.
.EXAMPLE
    Invoke-PurviewAssessment -Connect -UserPrincipalName consultor@cliente.com -OutputPath C:\Reports -ClientName 'Cliente Demo'
.EXAMPLE
    Invoke-PurviewAssessment -Workload DLP,Labels -OutputPath C:\Reports -IncludeDisabled
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('MIP', 'Labels', 'DLP', 'IRM', 'CC', 'DLM', 'RM', 'AUDIT', 'EDS', 'SIT', 'All')]
        [string[]]$Workload = 'All',

        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter()][string]$ClientName = '',
        [Parameter()][string]$UserPrincipalName,
        [switch]$Connect,

        # Añade la sesión de Exchange Online al conectar, necesaria para
        # verificar el estado del registro de auditoría.
        [switch]$IncludeExchangeOnline,

        # Omite la confirmación del estado de distribución por identidad.
        # Acelera el assessment a costa de que ese estado no sea concluyente.
        [switch]$SkipDistributionDetail,

        # Oculta en los informes los avisos que provienen de propiedades no
        # concluyentes ('Activating', 'Pending', 'Sin miembros asignados'),
        # para no trasladar al cliente lo que puede ser un falso negativo.
        [switch]$HideInconclusiveWarnings,
        [switch]$IncludeDisabled,
        [Parameter()][string[]]$SitXmlPath,
        [switch]$SkipExcel,
        [switch]$SkipJsonBackup,

        # Evalúa la configuración recolectada contra el catálogo de controles
        # y agrega el informe de evaluación al paquete de entregables.
        [switch]$Evaluate,

        # Respuestas del cliente para los controles de proceso.
        [Parameter()][hashtable]$InterviewResponses = @{}
    )

    $resolved = if ($Workload -contains 'All') { @('MIP', 'DLP', 'IRM', 'CC', 'DLM', 'RM', 'AUDIT', 'EDS', 'SIT') } else { @($Workload) }
    # 'Labels' es alias histórico de 'MIP': se normaliza y se deduplica
    $resolved = @($resolved | ForEach-Object { if ($_ -eq 'Labels') { 'MIP' } else { $_ } } | Select-Object -Unique)
    if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

    # Bandera de sesión leída por Resolve-PavDistributionStatus
    $script:PavSkipDistribution  = [bool]$SkipDistributionDetail
    $script:PavHideInconclusive  = [bool]$HideInconclusiveWarnings
    if ($HideInconclusiveWarnings) { Write-PavLog -Level Info -Message 'Los avisos no concluyentes se omitirán en los informes.' }
    if ($SkipDistributionDetail) { Write-PavLog -Level Info -Message 'Confirmación del estado de distribución omitida por parámetro.' }

    if ($Connect) { Connect-PurviewAssessment -UserPrincipalName $UserPrincipalName -IncludeExchangeOnline:$IncludeExchangeOnline }
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
                'RM'     { Get-PurviewRmData }
                'AUDIT'  { Get-PurviewAuditData }
                'EDS'    { Get-PurviewEdsData }
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
                'EDS'    { Export-PurviewEdsReport   -Data $data[$w] -OutputPath $OutputPath -ClientName $ClientName -SkipExcel:$SkipExcel }
                'AUDIT'  { Export-PurviewAuditReport -Data $data[$w] -OutputPath $OutputPath -ClientName $ClientName -SkipExcel:$SkipExcel }
                'RM'     { Export-PurviewRmReport   -Data $data[$w] -OutputPath $OutputPath -ClientName $ClientName -SkipExcel:$SkipExcel }
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
    $titles = @{ MIP = 'Etiquetas MIP'; DLP = 'DLP'; IRM = 'Insider Risk'; CC = 'Comm. Compliance'; DLM = 'Retención (DLM)'; RM = 'Records Management'; AUDIT = 'Auditoría'; EDS = 'eDiscovery'; SIT = 'SITs personalizados' }

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
            'RM'     { New-PavRmSections    -Data $d -TitlePrefix $prefix }
            'AUDIT'  { New-PavAuditSections -Data $d -TitlePrefix $prefix }
            'EDS'    { New-PavEdsSections   -Data $d -TitlePrefix $prefix }
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
                'RM'     { if (@($d.Findings).Count) { $sheets['RM-Hallazgos'] = @($d.Findings | Select-Object Severity, Area, Finding, Detail) }
                           if (@($d.FilePlanProperties).Count) { $sheets['RM-FilePlan'] = @($d.FilePlanProperties | Select-Object Type, Name, CitationJurisdiction, CitationUrl, Priority, LastModifiedBy) }
                           if (@($d.EventTypes).Count) { $sheets['RM-TiposEvento'] = @($d.EventTypes | Select-Object Name, LinkedLabelCount, LinkedLabels, Comment, Disabled) }
                           if (@($d.RecordTags).Count) { $sheets['RM-Registros'] = @($d.RecordTags | Select-Object Name, LabelCategory, RetentionAction, RetentionDuration, HasFilePlan, Department, Category, Citation, HasReviewStages) } }
                'AUDIT'  { $sheets['AUDIT-Estado'] = @([pscustomobject]@{
                               'Ingesta auditoría unificada' = $d.Status.UnifiedAuditLogIngestion
                               'Nota' = $d.Status.IngestionNote
                               'Auditoría de buzones' = $d.Status.MailboxAuditing
                               'Directivas' = $d.Status.RetentionPolicyCount })
                           if (@($d.RetentionPolicies).Count) { $sheets['AUDIT-Retencion'] = @($d.RetentionPolicies | Select-Object Name, Enabled, Priority, RetentionDuration, RecordTypes, Operations, UserIds, AppliesToAll, DistributionStatus) }
                           if (@($d.Findings).Count) { $sheets['AUDIT-Hallazgos'] = @($d.Findings | Select-Object Severity, Area, Finding, Detail) } }
                'EDS'    { if (@($d.Cases).Count) { $sheets['EDS-Casos'] = @($d.Cases | Select-Object Name, CaseType, Status, MemberCount, Members, CreatedBy, CreatedUtc) }
                           if (@($d.HoldPolicies).Count) { $sheets['EDS-Retenciones'] = @($d.HoldPolicies | Select-Object Name, CaseName, Enabled, Exchange, SharePoint, OneDrive, DistributionStatus) } }
                'SIT'    { $sheets['SIT-Inventario'] = @($d.Entities | ForEach-Object { [pscustomobject]@{ RulePackage = "$(Get-PavProp $_ 'RulePackName' '')"; Nombre = $_.Name; Id = $_.Id; Confianza = $_.RecommendedConfidence; Patrones = @($_.Patterns).Count } })
                           $pks = @(Get-PavProp $d 'RulePacks' @())
                           if ($pks.Count -gt 1) { $sheets['SIT-RulePackages'] = @($pks | Select-Object Name, Publisher, Version, SitCount, Identity) } }
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

    # ── FASE 4: evaluación de controles (opcional) ────────────────────────────
    $evaluation = $null
    $evalReport = $null
    if ($Evaluate -and $evaluated.Count -gt 0) {
        try {
            $evalData = @{}
            foreach ($w in $evaluated) { $evalData[$w] = $data[$w] }
            # Los SIT personalizados enriquecen la evaluación de otras cargas
            # (p. ej. saber si las reglas DLP usan identificadores propios).
            # Si se indicaron XML y la carga SIT no se pidió, se cargan aquí.
            if (-not $evalData.ContainsKey('SIT') -and $SitXmlPath) {
                try {
                    $evalData['SIT'] = Get-PurviewSitData -XmlPath $SitXmlPath
                    Write-PavLog -Level Info -Message 'Catálogo de SIT cargado para el cruce de controles.'
                }
                catch { Write-PavLog -Level Warn -Message "No se pudo cargar el catálogo de SIT para la evaluación: $($_.Exception.Message)" }
            }
            $evaluation = Invoke-PurviewControlEvaluation -Data $evalData -InterviewResponses $InterviewResponses
            $evalReport = Export-PurviewControlReport -Evaluation $evaluation -OutputPath $OutputPath -ClientName $ClientName -SkipExcel:$SkipExcel
        }
        catch {
            Write-PavLog -Level Warn -Message "Evaluación de controles omitida: $($_.Exception.Message)"
        }
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
        Evaluation        = $evaluation
        EvaluationReport  = $evalReport
    }
}
