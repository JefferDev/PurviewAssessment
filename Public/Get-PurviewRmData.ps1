function Get-PurviewRmData {
<#
.SYNOPSIS
    Recolecta la configuración de Records Management de Microsoft Purview
    (solo lectura): file plan, retención por eventos, etiquetas de
    registro, ámbitos adaptativos y disposición.
.DESCRIPTION
    Cada bloque se recolecta de forma tolerante: si la sesión no expone un
    cmdlet (feature no aprovisionada o rol insuficiente) se registra el
    aviso y el resto continúa.

    Cubre:
      - Descriptores del file plan: Department, Category, SubCategory,
        Authority, Citation, ReferenceId (catálogo completo, no solo lo
        usado por las etiquetas).
      - Tipos de evento de retención y sus etiquetas asociadas
        (Get-ComplianceRetentionEventType -LoadTag, imprescindible: sin
        ese modificador la propiedad ComplianceTags viene vacía).
      - Eventos de retención activos.
      - Etiquetas de retención declaradas como registro (record y
        regulatory), con su file plan y etapas de revisión.
      - Ámbitos adaptativos.
      - Estado del almacenamiento de etiquetas (Get-ComplianceTagStorage).
      - Hallazgos de gobierno derivados del cruce de todo lo anterior.
.PARAMETER SkipFindings
    Omite el análisis de hallazgos de gobierno.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.RmData' con
    FilePlanProperties, RetentionLabels, PublishPolicies, EventTypes,
    Events, RecordTags, AdaptiveScopes, Findings, TagStorage, CollectedAt.
.EXAMPLE
    Connect-PurviewAssessment
    (Get-PurviewRmData).Findings | Where-Object Severity -eq 'Alta'
.EXAMPLE
    Get-PurviewRmData | Export-PurviewRmReport -OutputPath C:\Reports
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([switch]$SkipFindings)

    Assert-PavConnection
    Write-PavLog -Level Step -Message 'Recolectando configuración de Records Management...'

    # ── 1. Descriptores del file plan ────────────────────────────────────────
    $props = [System.Collections.Generic.List[object]]::new()
    $planTypes = [ordered]@{
        'Department'  = 'Get-FilePlanPropertyDepartment'
        'Category'    = 'Get-FilePlanPropertyCategory'
        'SubCategory' = 'Get-FilePlanPropertySubCategory'
        'Authority'   = 'Get-FilePlanPropertyAuthority'
        'Citation'    = 'Get-FilePlanPropertyCitation'
        'ReferenceId' = 'Get-FilePlanPropertyReferenceId'
    }
    foreach ($t in $planTypes.GetEnumerator()) {
        $cmd = $t.Value
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            Write-PavLog -Level Warn -Message "  - $cmd no disponible en esta sesión, se omite."
            continue
        }
        try {
            $raw = @(Invoke-PavRetry -OperationName $cmd -MaxAttempts 2 -ScriptBlock {
                & $cmd -ErrorAction Stop
            })
            foreach ($p in $raw) { if ($null -ne $p) { $props.Add((ConvertFrom-PavFilePlanProperty $p $t.Key)) } }
            Write-PavLog -Level Info -Message "  > $($t.Key): $(@($raw | Where-Object { $null -ne $_ }).Count)"
        }
        catch { Write-PavLog -Level Warn -Message "  - $($t.Key) no recuperado: $($_.Exception.Message)" }
    }

    # Estructura del file plan (jerarquía declarada), si el cmdlet existe
    $structure = ''
    if (Get-Command Get-FilePlanPropertyStructure -ErrorAction SilentlyContinue) {
        try {
            $st = Invoke-PavRetry -OperationName 'Get-FilePlanPropertyStructure' -MaxAttempts 2 -ScriptBlock {
                Get-FilePlanPropertyStructure -ErrorAction Stop
            }
            $structure = "$st"
        }
        catch { Write-PavLog -Level Warn -Message "  - Estructura del file plan no recuperada: $($_.Exception.Message)" }
    }

    # ── 2. Tipos de evento y eventos de retención ────────────────────────────
    $eventTypes = [System.Collections.Generic.List[object]]::new()
    if (Get-Command Get-ComplianceRetentionEventType -ErrorAction SilentlyContinue) {
        try {
            # -LoadTag es obligatorio: sin él, ComplianceTags viene vacío
            $raw = @(Invoke-PavRetry -OperationName 'Get-ComplianceRetentionEventType' -MaxAttempts 2 -ScriptBlock {
                Get-ComplianceRetentionEventType -LoadTag -ErrorAction Stop
            })
            foreach ($e in $raw) { if ($null -ne $e) { $eventTypes.Add((ConvertFrom-PavRetentionEventType $e)) } }
            Write-PavLog -Level Info -Message "  > Tipos de evento: $(@($eventTypes).Count)"
        }
        catch { Write-PavLog -Level Warn -Message "  - Tipos de evento no recuperados: $($_.Exception.Message)" }
    }
    else { Write-PavLog -Level Warn -Message '  - Get-ComplianceRetentionEventType no disponible en esta sesión.' }

    $events = [System.Collections.Generic.List[object]]::new()
    if (Get-Command Get-ComplianceRetentionEvent -ErrorAction SilentlyContinue) {
        try {
            $raw = @(Invoke-PavRetry -OperationName 'Get-ComplianceRetentionEvent' -MaxAttempts 2 -ScriptBlock {
                Get-ComplianceRetentionEvent -ErrorAction Stop
            })
            foreach ($e in $raw) { if ($null -ne $e) { $events.Add((ConvertFrom-PavRetentionEvent $e)) } }
            Write-PavLog -Level Info -Message "  > Eventos activos: $(@($events).Count)"
        }
        catch { Write-PavLog -Level Warn -Message "  - Eventos de retención no recuperados: $($_.Exception.Message)" }
    }

    # ── 3. Etiquetas declaradas como registro ────────────────────────────────
    $recordTags = [System.Collections.Generic.List[object]]::new()
    $allTags    = [System.Collections.Generic.List[object]]::new()
    $usage      = [System.Collections.Generic.List[string]]::new()
    if (Get-Command Get-ComplianceTag -ErrorAction SilentlyContinue) {
        try {
            $rawTags = @(Invoke-PavRetry -OperationName 'Get-ComplianceTag' -MaxAttempts 2 -ScriptBlock {
                Get-ComplianceTag -ErrorAction Stop
            })
            $tagFallidas = 0
            foreach ($t in $rawTags) {
                if ($null -eq $t) { continue }
                try {
                $fpRaw  = "$(Get-PavProp $t 'FilePlanMetadata' '')"
                $revRaw = "$(Get-PavProp $t 'MultiStageReviewerMetadata' '')"
                $isRec  = [bool](Get-PavProp $t 'IsRecordLabel' $false)
                $isReg  = [bool](Get-PavProp $t 'Regulatory' $false)

                # Valores de file plan efectivamente usados (para hallazgos)
                $fpVals = @{}
                if ($fpRaw) {
                    $fp = ConvertFrom-PavJson $fpRaw
                    foreach ($s in @(Get-PavProp $fp 'Settings' @())) {
                        $k = [string](Get-PavProp $s 'Key' ''); $v = "$(Get-PavProp $s 'Value' '')"
                        if ($v) { $fpVals[$k] = $v; $usage.Add($v) }
                    }
                }
                # Clasificación de ámbito: Get-ComplianceTag devuelve también
                # las etiquetas de ciclo de vida, que corresponden a DLM.
                $ambito = Get-PavLabelScope $t
                $allTags.Add([pscustomobject]@{
                    PSTypeName    = 'PurviewAssessment.RmRetentionLabel'
                    Name          = [string](Get-PavProp $t 'Name' '')
                    Scope         = $ambito.Scope
                    ScopeReason   = $ambito.Reasons
                    LabelCategory = if ($isReg) { 'Registro regulado' } elseif ($isRec) { 'Registro' } else { 'Retención (sin declarar registro)' }
                    IsReviewTag   = Get-PavProp $t 'IsReviewTag' $false
                    RetentionAction   = ConvertTo-PavFriendlyAction ([string](Get-PavProp $t 'RetentionAction' ''))
                    RetentionDuration = ConvertTo-PavFriendlyDuration (Get-PavProp $t 'RetentionDuration')
                    RetentionType     = ConvertTo-PavFriendlyRetentionType ([string](Get-PavProp $t 'RetentionType' ''))
                    IsRecordLabel = $isRec
                    Regulatory    = $isReg
                    HasFilePlan   = ($fpVals.Count -gt 0)
                    Department    = "$($fpVals['FilePlanPropertyDepartment'])"
                    Category      = "$($fpVals['FilePlanPropertyCategory'])"
                    SubCategory   = "$($fpVals['FilePlanPropertySubcategory'])"
                    Authority     = "$($fpVals['FilePlanPropertyAuthority'])"
                    Citation      = "$($fpVals['FilePlanPropertyCitation'])"
                    ReferenceId   = "$($fpVals['FilePlanPropertyReferenceId'])"
                    HasReviewStages = (-not [string]::IsNullOrWhiteSpace($revRaw))
                    EventTypeId   = "$(Get-PavProp $t 'EventTypeId' '')"
                    Workload      = [string](Get-PavProp $t 'Workload' '')
                    Notes         = [string](Get-PavProp $t 'Notes' '')
                    Guid          = [string](Get-PavProp $t 'Guid' '')
                    CreatedBy     = [string](Get-PavProp $t 'CreatedBy' '')
                    PolicyRef     = "$(Get-PavProp $t 'Policy' '')"
                })
                if (-not ($isRec -or $isReg)) { continue }

                $recordTags.Add([pscustomobject]@{
                    PSTypeName    = 'PurviewAssessment.RmRecordTag'
                    Name          = [string](Get-PavProp $t 'Name' '')
                    LabelCategory = if ($isReg) { 'Regulatory Record' } else { 'Record Label' }
                    RetentionAction   = ConvertTo-PavFriendlyAction ([string](Get-PavProp $t 'RetentionAction' ''))
                    RetentionDuration = ConvertTo-PavFriendlyDuration (Get-PavProp $t 'RetentionDuration')
                    RetentionType     = ConvertTo-PavFriendlyRetentionType ([string](Get-PavProp $t 'RetentionType' ''))
                    IsRecordLabel = $isRec
                    Regulatory    = $isReg
                    IsReviewTag   = Get-PavProp $t 'IsReviewTag' $false
                    HasFilePlan   = ($fpVals.Count -gt 0)
                    Department    = "$($fpVals['FilePlanPropertyDepartment'])"
                    Category      = "$($fpVals['FilePlanPropertyCategory'])"
                    SubCategory   = "$($fpVals['FilePlanPropertySubcategory'])"
                    Authority     = "$($fpVals['FilePlanPropertyAuthority'])"
                    Citation      = "$($fpVals['FilePlanPropertyCitation'])"
                    ReferenceId   = "$($fpVals['FilePlanPropertyReferenceId'])"
                    HasReviewStages = (-not [string]::IsNullOrWhiteSpace($revRaw))
                    ReviewerEmail = (@(Get-PavProp $t 'ReviewerEmail' @()) | ForEach-Object { "$_" }) -join '; '
                    EventTypeId   = "$(Get-PavProp $t 'EventTypeId' '')"
                    Notes         = [string](Get-PavProp $t 'Notes' '')
                    Workload      = [string](Get-PavProp $t 'Workload' '')
                    Guid          = [string](Get-PavProp $t 'Guid' '')
                    CreatedBy     = [string](Get-PavProp $t 'CreatedBy' '')
                })
                }
                catch {
                    $tagFallidas++
                    Write-PavLog -Level Warn -Message "  - Etiqueta '$(Get-PavProp $t 'Name' '?')' no procesada: $($_.Exception.Message)"
                }
            }
            if ($tagFallidas -gt 0) { Write-PavLog -Level Warn -Message "  - $tagFallidas etiqueta(s) no pudieron procesarse; el resto del inventario continúa." }
            $rmCount = @($allTags | Where-Object { $_.Scope -eq 'Gestión de registros' }).Count
            Write-PavLog -Level Info -Message "  > Etiquetas: $(@($allTags).Count) en total | $rmCount del ámbito de gestión de registros | $(@($allTags).Count - $rmCount) de ciclo de vida"
        }
        catch { Write-PavLog -Level Warn -Message "  - Etiquetas de registro no recuperadas: $($_.Exception.Message)" }
    }

    # ── 3b. Directivas de retención que publican las etiquetas ───────────────
    $publishPolicies = [System.Collections.Generic.List[object]]::new()
    # Etiquetas publicadas segun las reglas de retencion (via alternativa al
    # cruce por GUID, que no siempre coincide entre etiqueta y directiva).
    $reglasPorDirectiva = @{}
    if (Get-Command Get-RetentionComplianceRule -ErrorAction SilentlyContinue) {
        try {
            foreach ($rr in @(Invoke-PavRetry -OperationName 'Get-RetentionComplianceRule' -MaxAttempts 2 -ScriptBlock { Get-RetentionComplianceRule -ErrorAction Stop })) {
                if ($null -eq $rr) { continue }
                $pg = "$(Get-PavProp $rr 'Policy' '')"
                $pub = "$(Get-PavProp $rr 'PublishComplianceTag' '')"
                if ($pub -match ',(.+)$') { $pub = $Matches[1].Trim() }
                if ($pg -and $pub) {
                    if (-not $reglasPorDirectiva.ContainsKey($pg)) { $reglasPorDirectiva[$pg] = @() }
                    $reglasPorDirectiva[$pg] += $pub
                }
            }
        }
        catch { Write-PavLog -Level Info -Message 'Reglas de retención no disponibles para resolver las etiquetas publicadas.' }
    }
    if (Get-Command Get-RetentionCompliancePolicy -ErrorAction SilentlyContinue) {
        try {
            $rawPub = @(Invoke-PavRetry -OperationName 'Get-RetentionCompliancePolicy' -MaxAttempts 2 -ScriptBlock {
                Get-RetentionCompliancePolicy -ErrorAction Stop
            })
            foreach ($pp in $rawPub) {
                if ($null -eq $pp) { continue }
                $g   = "$(Get-PavProp $pp 'Guid' '')"
                $eoi = "$(Get-PavProp $pp 'ExchangeObjectId' '')"
                # El campo Policy de la etiqueta puede referenciar el GUID de la
                # directiva o su identificador de objeto, según cómo se creara.
                $etq = @($allTags | Where-Object { $_.PolicyRef -and ($_.PolicyRef -eq $g -or $_.PolicyRef -eq $eoi) } | ForEach-Object { $_.Name })
                # Complemento: etiquetas publicadas declaradas en las reglas
                if ($etq.Count -eq 0 -and $reglasPorDirectiva.ContainsKey($g)) { $etq = @($reglasPorDirectiva[$g]) }
                $publishPolicies.Add([pscustomobject]@{
                    PSTypeName = 'PurviewAssessment.RmPublishPolicy'
                    Name       = [string](Get-PavProp $pp 'Name' '')
                    PolicyType = ConvertTo-PavFriendlyPolicyType ([string](Get-PavProp $pp 'Type' ''))
                    Enabled    = Get-PavProp $pp 'Enabled'
                    Mode       = ConvertTo-PavFriendlyMode ([string](Get-PavProp $pp 'Mode' '')) ([bool](Get-PavProp $pp 'IsSimulation' $false))
                    LabelsPublished = ($etq -join ' | ')
                    LabelCount = $etq.Count
                    PublicaRegistros = ((@($etq | Where-Object { $n = $_; @($allTags | Where-Object { $_.Name -eq $n -and $_.Scope -eq 'Gestión de registros' }).Count -gt 0 }).Count) -gt 0)
                    Exchange   = Get-PavLocationScope (Get-PavProp $pp 'ExchangeLocation' @())
                    SharePoint = Get-PavLocationScope (Get-PavProp $pp 'SharePointLocation' @())
                    OneDrive   = Get-PavLocationScope (Get-PavProp $pp 'OneDriveLocation' @())
                    TeamsChat  = Get-PavLocationScope (Get-PavProp $pp 'TeamsChatLocation' @())
                    TeamsChannel = Get-PavLocationScope (Get-PavProp $pp 'TeamsChannelLocation' @())
                    ModernGroup  = Get-PavLocationScope (Get-PavProp $pp 'ModernGroupLocation' @())
                    IsAdaptive = Get-PavProp $pp 'IsAdaptivePolicy'
                    RestrictiveRetention = Get-PavProp $pp 'RestrictiveRetention'
                    DistributionStatus = [string](Get-PavProp $pp 'DistributionStatus' '')
                    CreatedBy  = [string](Get-PavProp $pp 'CreatedBy' '')
                    LastModifiedUtc = Get-PavProp $pp 'ModificationTimeUtc'
                    Guid       = $g
                })
            }
            Write-PavLog -Level Info -Message "  > Directivas de publicación: $(@($publishPolicies).Count)"
        }
        catch { Write-PavLog -Level Warn -Message "  - Directivas de retención no recuperadas: $($_.Exception.Message)" }
    }

    # ── 4. Ámbitos adaptativos ───────────────────────────────────────────────
    $scopes = [System.Collections.Generic.List[object]]::new()
    if (Get-Command Get-AdaptiveScope -ErrorAction SilentlyContinue) {
        try {
            $raw = @(Invoke-PavRetry -OperationName 'Get-AdaptiveScope' -MaxAttempts 2 -ScriptBlock {
                Get-AdaptiveScope -ErrorAction Stop
            })
            foreach ($s in $raw) { if ($null -ne $s) { $scopes.Add((ConvertFrom-PavAdaptiveScope $s)) } }
            Write-PavLog -Level Info -Message "  > Ámbitos adaptativos: $(@($scopes).Count)"
        }
        catch { Write-PavLog -Level Warn -Message "  - Ámbitos adaptativos no recuperados: $($_.Exception.Message)" }
    }

    # ── 5. Almacenamiento de etiquetas ───────────────────────────────────────
    $tagStorage = ''
    if (Get-Command Get-ComplianceTagStorage -ErrorAction SilentlyContinue) {
        try {
            $ts = Invoke-PavRetry -OperationName 'Get-ComplianceTagStorage' -MaxAttempts 2 -ScriptBlock {
                Get-ComplianceTagStorage -ErrorAction Stop
            }
            $tagStorage = "$(Get-PavProp $ts 'Name' "$ts")"
        }
        catch { Write-PavLog -Level Warn -Message "  - Estado de almacenamiento no recuperado: $($_.Exception.Message)" }
    }

    # ── 6. Hallazgos de gobierno ─────────────────────────────────────────────
    $findings = @()
    if (-not $SkipFindings) {
        $findings = @(Get-PavRmFindings -Properties @($props) -EventTypes @($eventTypes) `
                        -RecordTags @($recordTags) -FilePlanUsage @($usage))
        Write-PavLog -Level Info -Message "  > Hallazgos de gobierno: $($findings.Count)"
    }

    Write-PavLog -Level Success -Message "Records Management: $(@($props).Count) descriptores, $(@($eventTypes).Count) tipos de evento, $(@($recordTags).Count) etiquetas de registro."

    [pscustomobject]@{
        PSTypeName         = 'PurviewAssessment.RmData'
        FilePlanProperties = @($props)
        FilePlanStructure  = $structure
        EventTypes         = @($eventTypes)
        Events             = @($events)
        RetentionLabels    = @($allTags | Where-Object { $_.Scope -eq 'Gestión de registros' })
        LifecycleLabels    = @($allTags | Where-Object { $_.Scope -ne 'Gestión de registros' })
        PublishPolicies    = @($publishPolicies)
        RecordTags         = @($recordTags)
        AdaptiveScopes     = @($scopes)
        TagStorage         = $tagStorage
        Findings           = @($findings)
        CollectedAt        = Get-Date
    }
}
