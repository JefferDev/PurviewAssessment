# ═══════════════════════════════════════════════════════════════════════════
# Constructores de secciones por carga de trabajo.
# Usados por los Export-Purview*Report individuales Y por el consolidado de
# Invoke-PurviewAssessment: mismo detalle (tarjetas, árboles, tablas) en ambos.
# ═══════════════════════════════════════════════════════════════════════════

function New-PavLabelSections {
<#
.SYNOPSIS
    Secciones HTML (detalle completo) de la carga Label a partir de sus
    datos parseados. Compartido por el informe individual y el consolidado.
.PARAMETER Data
    Objeto de datos del colector correspondiente.
.PARAMETER TitlePrefix
    Prefijo de título para desambiguar pestañas en el consolidado
    (p. ej. 'DLP · ').
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Data,
        [Parameter()][string]$TitlePrefix = ''
    )
    $labels   = @($Data.Labels)
        $policies = @($Data.Policies)


        $labelCards = foreach ($l in ($labels | Sort-Object Priority)) {
            $badges = (New-PavBadge -Text "Prioridad $($l.Priority)" -Type Neutral)
            if ($l.IsParent)          { $badges += New-PavBadge -Text 'Grupo' -Type Info }
            if ($l.HasEncryption)     { $badges += New-PavBadge -Text 'Cifrado' -Type Special }
            if ($l.HasContentMarking) { $badges += New-PavBadge -Text 'Marcas visuales' -Type Info }
            if (-not $l.PublishedInPolicies) { $badges += New-PavBadge -Text 'Sin publicar' -Type Warn }

            $body = New-PavPropList -Properties ([ordered]@{
                'Nombre interno' = $l.Name;            'GUID' = $l.Guid
                'ImmutableId'    = $l.ImmutableId;     'Etiqueta padre' = $l.ParentDisplay
                'Tooltip'        = $l.Tooltip;         'Comentario' = $l.Comment
                'Color'          = $l.Color;           'ContentType' = $l.ContentType
                'Workload'       = $l.Workload
                'Cifrado' = $l.HasEncryption; 'Encabezado' = $l.HasHeader
                'Pie de página' = $l.HasFooter; 'Marca de agua' = $l.HasWatermark
                'Protege grupos' = $l.HasProtectGroup; 'Protege sitios' = $l.HasProtectSites
                'Idiomas (locales)' = $l.LocaleAll
                'Publicada en directivas' = $l.PublishedInPolicies
                'Creación (UTC)' = $l.WhenCreatedUTC; 'Modificación (UTC)' = $l.WhenChangedUTC
                'Settings (raw)' = $l.SettingsRaw; 'LabelActions (raw)' = $l.ActionsRaw
            })
            New-PavHtmlCard -Title $l.DisplayName -Subtitle $l.Guid -BadgesHtml $badges -BodyHtml $body -AccentColor $(if ($l.Color -match '^#') { $l.Color } else { '' })
        }

        $policyCards = foreach ($p in $policies) {
            $badges = (New-PavBadge -Bool $p.Enabled)
            if ($p.Mode)      { $badges += New-PavBadge -Text $p.Mode -Type Info }
            if ("$($p.Mandatory)".ToLowerInvariant() -in @('true','si','sí')) { $badges += New-PavBadge -Text 'Obligatoria' -Type Warn }

            $body = (New-PavPropList -Properties ([ordered]@{
                'GUID' = $p.Guid; 'Tipo' = $p.Type; 'Workload' = $p.Workload
                'Etiquetado obligatorio' = $p.Mandatory
                'Justificación al degradar' = $p.RequireDowngradeJustification
                'Etiqueta por defecto (Id)' = $p.DefaultLabelId
                'Exchange' = $p.ExchangeLocation; 'SharePoint' = $p.SharePointLocation
                'OneDrive' = $p.OneDriveLocation; 'Grupos M365' = $p.ModernGroupLocation
                'Creación (UTC)' = $p.WhenCreatedUTC; 'Modificación (UTC)' = $p.WhenChangedUTC
                'Settings (raw)' = $p.SettingsRaw
            })) + (New-PavHtmlTable -Data (@($p.ScopedLabels) | ForEach-Object { [pscustomobject]@{ 'Etiqueta publicada' = $_ } }))
            New-PavHtmlCard -Title $p.Name -Subtitle "$($p.LabelsCount) etiqueta(s) publicada(s)" -BadgesHtml $badges -BodyHtml $body
        }

        $encCount = @($labels | Where-Object HasEncryption).Count
        $sections = @(
            (New-PavHtmlSection -Id 'mip-labels' -Title "$($TitlePrefix)Etiquetas MIP" `
                -Description 'Etiquetas de sensibilidad de Microsoft Information Protection.' `
                -StatsHtml (New-PavStatGroup -Stats (
                    (New-PavStat -Label 'Etiquetas' -Value "$($labels.Count)"),
                    (New-PavStat -Label 'Con cifrado' -Value "$encCount"),
                    (New-PavStat -Label 'Con marcas visuales' -Value "$(@($labels | Where-Object HasContentMarking).Count)"),
                    (New-PavStat -Label 'Grupos' -Value "$(@($labels | Where-Object IsParent).Count)")
                )) -ContentHtml ($labelCards -join "`n")),
            (New-PavHtmlSection -Id 'mip-policies' -Title "$($TitlePrefix)Directivas - Etiquetas MIP" `
                -Description 'Directivas de publicación de etiquetas.' `
                -StatsHtml (New-PavStatGroup -Stats (
                    (New-PavStat -Label 'Directivas' -Value "$($policies.Count)"),
                    (New-PavStat -Label 'Habilitadas' -Value "$(@($policies | Where-Object Enabled).Count)")
                )) -ContentHtml ($policyCards -join "`n"))
        )

    return @($sections)
}

function New-PavDlpSections {
<#
.SYNOPSIS
    Secciones HTML (detalle completo) de la carga Dlp a partir de sus
    datos parseados. Compartido por el informe individual y el consolidado.
.PARAMETER Data
    Objeto de datos del colector correspondiente.
.PARAMETER TitlePrefix
    Prefijo de título para desambiguar pestañas en el consolidado
    (p. ej. 'DLP · ').
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Data,
        [Parameter()][string]$TitlePrefix = ''
    )
    $policies = @($Data.Policies)
        $rules    = @($Data.Rules)


        $modeBadge = {
            param($mode)
            switch -Regex ("$mode") {
                '^Enable$'                { New-PavBadge -Text 'Enforce' -Type Err }
                'TestWithNotifications'   { New-PavBadge -Text 'Test + Notificaciones' -Type Warn }
                'TestWithoutNotifications' { New-PavBadge -Text 'Test (simulación)' -Type Info }
                'Disable'                 { New-PavBadge -Text 'Deshabilitada' -Type Neutral }
                default                   { if ($mode) { New-PavBadge -Text "$mode" -Type Neutral } else { '' } }
            }
        }

        $policyCards = foreach ($p in $policies) {
            $badges = (New-PavBadge -Bool $p.Enabled) + (& $modeBadge $p.Mode)
            $ruleCount = @($rules | Where-Object PolicyName -eq $p.Name).Count
            $locs = [ordered]@{}
            foreach ($prop in $p.PSObject.Properties) {
                if ($prop.Name -match 'Location') { $locs[$prop.Name] = $prop.Value }
            }
            $body = (New-PavPropList -Properties ([ordered]@{
                'GUID' = $p.Guid; 'Tipo' = $p.Type; 'Prioridad' = $p.Priority
                'Comentario' = $p.Comment; 'Workload' = $p.Workload
                'Reglas asociadas' = $ruleCount
                'Creada por' = $p.CreatedBy; 'Modificada por' = $p.LastModifiedBy
                'Creación' = $p.WhenCreated; 'Modificación' = $p.WhenChanged
            })) + '<h4>Ubicaciones</h4>' + (New-PavPropList -Properties $locs)
            New-PavHtmlCard -Title $p.Name -Subtitle "$ruleCount regla(s)" -BadgesHtml $badges -BodyHtml $body
        }

        $ruleCards = foreach ($r in $rules) {
            $badges = ''
            if ($r.Disabled -eq 'Sí') { $badges += New-PavBadge -Text 'Deshabilitada' -Type Neutral }
            if ($r.IsAdvancedRule -eq 'Sí') { $badges += New-PavBadge -Text 'AdvancedRule' -Type Special }
            if ($r.BlockAccess -eq 'Sí') { $badges += New-PavBadge -Text 'Bloquea' -Type Err }
            if ($r.NotifyUser)   { $badges += New-PavBadge -Text 'Notifica' -Type Info }
            if ($r.GenerateAlert) { $badges += New-PavBadge -Text 'Alerta' -Type Warn }

            # Propiedades no vacías (excluye árbol/HTML, se muestran aparte)
            $props = [ordered]@{}
            foreach ($prop in $r.PSObject.Properties) {
                if ($prop.Name -in @('ConditionsHtml', 'ConditionsTree', 'PSTypeName')) { continue }
                if ($null -ne $prop.Value -and "$($prop.Value)" -ne '') { $props[$prop.Name] = $prop.Value }
            }
            $body = New-PavPropList -Properties $props
            if ($r.ConditionsHtml) {
                $body += "<h4>Árbol de condiciones (AdvancedRule)</h4><div class='pav-adv-tree'>$($r.ConditionsHtml)</div>"
            }
            New-PavHtmlCard -Title $r.RuleName -Subtitle "Directiva: $($r.PolicyName)" -BadgesHtml $badges -BodyHtml $body
        }

        $advCount = @($rules | Where-Object IsAdvancedRule -eq 'Sí').Count
        $sections = @(
            (New-PavHtmlSection -Id 'dlp-policies' -Title "$($TitlePrefix)Directivas" `
                -Description 'Directivas de prevención de pérdida de datos y sus ubicaciones.' `
                -StatsHtml (New-PavStatGroup -Stats (
                    (New-PavStat -Label 'Directivas' -Value "$($policies.Count)"),
                    (New-PavStat -Label 'Habilitadas' -Value "$(@($policies | Where-Object Enabled).Count)"),
                    (New-PavStat -Label 'En Enforce' -Value "$(@($policies | Where-Object Mode -eq 'Enable').Count)")
                )) -ContentHtml ($policyCards -join "`n")),
            (New-PavHtmlSection -Id 'dlp-rules' -Title "$($TitlePrefix)Reglas" `
                -Description 'Reglas con condiciones, excepciones, acciones y árbol de AdvancedRule.' `
                -StatsHtml (New-PavStatGroup -Stats (
                    (New-PavStat -Label 'Reglas' -Value "$($rules.Count)"),
                    (New-PavStat -Label 'AdvancedRule' -Value "$advCount"),
                    (New-PavStat -Label 'Con bloqueo' -Value "$(@($rules | Where-Object BlockAccess -eq 'Sí').Count)")
                )) -ContentHtml ($ruleCards -join "`n"))
        )

    return @($sections)
}

function New-PavIrmSections {
<#
.SYNOPSIS
    Secciones HTML (detalle completo) de la carga Irm a partir de sus
    datos parseados. Compartido por el informe individual y el consolidado.
.PARAMETER Data
    Objeto de datos del colector correspondiente.
.PARAMETER TitlePrefix
    Prefijo de título para desambiguar pestañas en el consolidado
    (p. ej. 'DLP · ').
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Data,
        [Parameter()][string]$TitlePrefix = ''
    )
    $policies = @($Data.Policies)


        $healthBadge = {
            param($status)
            switch -Regex ("$status") {
                '^Healthy$'         { New-PavBadge -Text 'Saludable' -Type Ok }
                'Unhealthy'         { New-PavBadge -Text 'No saludable' -Type Err }
                'RecommendReview'   { New-PavBadge -Text 'Revisar' -Type Warn }
                default             { New-PavBadge -Text "$status" -Type Neutral }
            }
        }

        $cards = foreach ($p in $policies) {
            $badges = (New-PavBadge -Bool $p.Enabled) + (& $healthBadge $p.HealthStatus)
            if ($p.HasDlpPolicy) { $badges += New-PavBadge -Text 'DLP vinculada' -Type Info }
            if ("$($p.IsCustom)" -eq 'True') { $badges += New-PavBadge -Text 'Personalizada' -Type Special }

            $props = [ordered]@{}
            foreach ($prop in $p.PSObject.Properties) {
                if ($prop.Name -eq 'PSTypeName') { continue }
                $props[$prop.Name] = $prop.Value
            }
            $body = New-PavPropList -Properties $props

            $ins = @($Data.TriggerInsights | Where-Object PolicyName -eq $p.Name)
            if ($ins.Count) { $body += '<h4>Trigger Insights</h4>' + (New-PavHtmlTable -Data $ins -Property GroupName, InsightName, Enabled, CustomThresholds, HasThresholds) }
            $ind = @($Data.Indicators | Where-Object PolicyName -eq $p.Name)
            if ($ind.Count) { $body += '<h4>Indicadores</h4>' + (New-PavHtmlTable -Data $ind -Property GroupName, Type, Enabled, ThresholdMode, SubIndicators) }
            $hRow = @($Data.Health | Where-Object PolicyName -eq $p.Name) | Select-Object -First 1
            if ($hRow -and $hRow.ValidationIssues) { $body += '<h4>Issues de validación</h4>' + (New-PavPropList -Properties ([ordered]@{ 'Detalle' = $hRow.ValidationIssues })) }

            New-PavHtmlCard -Title $p.Name -Subtitle "$($p.Scenario) · $($p.PolicyCategory)" -BadgesHtml $badges -BodyHtml $body
        }

        $unhealthy = @($Data.Health | Where-Object HealthStatus -notin @('Healthy', 'Unknown')).Count
        $sections = @(New-PavHtmlSection -Id 'irm' -Title "$($TitlePrefix)Insider Risk Management" `
            -Description 'Directivas de riesgo interno, trigger insights, indicadores y estado de salud.' `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Directivas' -Value "$($policies.Count)"),
                (New-PavStat -Label 'Habilitadas' -Value "$(@($policies | Where-Object { "$($_.Enabled)" -eq 'True' }).Count)"),
                (New-PavStat -Label 'Con issues de salud' -Value "$unhealthy"),
                (New-PavStat -Label 'Indicadores' -Value "$(@($Data.Indicators).Count)")
            )) -ContentHtml ($cards -join "`n"))

    return @($sections)
}

function New-PavCcSections {
<#
.SYNOPSIS
    Secciones HTML (detalle completo) de la carga Cc a partir de sus
    datos parseados. Compartido por el informe individual y el consolidado.
.PARAMETER Data
    Objeto de datos del colector correspondiente.
.PARAMETER TitlePrefix
    Prefijo de título para desambiguar pestañas en el consolidado
    (p. ej. 'DLP · ').
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Data,
        [Parameter()][string]$TitlePrefix = ''
    )
    $policies = @($Data.Policies)
        $rules    = @($Data.Rules)


        # Port de Badge-Status / Badge-Prov
        $statusBadge = {
            param($s)
            switch -Regex ("$s") {
                '^(Active|Enabled)$' { New-PavBadge -Text "$s" -Type Ok }
                '^Activating$'       { New-PavBadge -Text 'Activating' -Type Warn }
                '^(Disabled|Error)$' { New-PavBadge -Text "$s" -Type Err }
                '^Inactive$'         { New-PavBadge -Text 'Inactive' -Type Neutral }
                default              { if ($s) { New-PavBadge -Text "$s" -Type Neutral } else { '' } }
            }
        }
        $provBadge = {
            param($s)
            switch -Regex ("$s") {
                '^Success$'    { New-PavBadge -Text 'Aprovisionada' -Type Ok }
                '^NotStarted$' { New-PavBadge -Text 'Pendiente' -Type Warn }
                '^Failed$'     { New-PavBadge -Text 'Fallo aprovisionamiento' -Type Err }
                default        { '' }
            }
        }

        $policyCards = foreach ($p in $policies) {
            $badges = (New-PavBadge -Bool $p.Enabled) + (& $statusBadge $p.PolicyStatus) + (& $provBadge $p.ProvisionStatus)
            $props = [ordered]@{}
            foreach ($prop in $p.PSObject.Properties) {
                if ($prop.Name -eq 'PSTypeName') { continue }
                $props[$prop.Name] = $prop.Value
            }
            $body = New-PavPropList -Properties $props
            $polRules = @($rules | Where-Object { $_.PolicyRef -eq $p.Guid -or $_.RuleName -eq $p.Name })
            if ($polRules.Count) {
                $body += '<h4>Reglas</h4>' + (New-PavHtmlTable -Data $polRules -Property RuleName, Direction, Workloads, SamplingRate, OcrEnabled, ClassifiersModels)
            }
            New-PavHtmlCard -Title $p.Name -Subtitle "$($p.RulesCount) regla(s) · $($p.Workloads)" -BadgesHtml $badges -BodyHtml $body
        }

        $ruleCards = foreach ($r in $rules) {
            $badges = ''
            if ("$($r.Disabled)" -eq 'True') { $badges += New-PavBadge -Text 'Deshabilitada' -Type Neutral }
            if ($r.Direction -ne 'N/D') { $badges += New-PavBadge -Text $r.Direction -Type Info }
            if ($r.ClassifiersModels -ne 'N/D') { $badges += New-PavBadge -Text 'Clasificadores' -Type Special }
            $props = [ordered]@{}
            foreach ($prop in $r.PSObject.Properties) {
                if ($prop.Name -eq 'PSTypeName') { continue }
                $props[$prop.Name] = $prop.Value
            }
            New-PavHtmlCard -Title $r.RuleName -Subtitle $r.ContentSources -BadgesHtml $badges -BodyHtml (New-PavPropList -Properties $props)
        }

        $sections = @(
            (New-PavHtmlSection -Id 'cc-policies' -Title "$($TitlePrefix)Directivas" `
                -Description 'Directivas de Communication Compliance, revisores y estado.' `
                -StatsHtml (New-PavStatGroup -Stats (
                    (New-PavStat -Label 'Directivas' -Value "$($policies.Count)"),
                    (New-PavStat -Label 'Activas' -Value "$(@($policies | Where-Object PolicyStatus -eq 'Active').Count)"),
                    (New-PavStat -Label 'Con fallo aprovisionamiento' -Value "$(@($policies | Where-Object ProvisionStatus -eq 'Failed').Count)")
                )) -ContentHtml ($policyCards -join "`n")),
            (New-PavHtmlSection -Id 'cc-rules' -Title "$($TitlePrefix)Reglas" `
                -Description 'Reglas: dirección, muestreo, OCR, clasificadores y orígenes de contenido.' `
                -StatsHtml (New-PavStatGroup -Stats (
                    (New-PavStat -Label 'Reglas' -Value "$($rules.Count)"),
                    (New-PavStat -Label 'Con clasificadores' -Value "$(@($rules | Where-Object ClassifiersModels -ne 'N/D').Count)")
                )) -ContentHtml ($ruleCards -join "`n"))
        )

    return @($sections)
}

function New-PavDlmSections {
<#
.SYNOPSIS
    Secciones HTML (detalle completo) de la carga Dlm a partir de sus
    datos parseados. Compartido por el informe individual y el consolidado.
.PARAMETER Data
    Objeto de datos del colector correspondiente.
.PARAMETER TitlePrefix
    Prefijo de título para desambiguar pestañas en el consolidado
    (p. ej. 'DLP · ').
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Data,
        [Parameter()][string]$TitlePrefix = ''
    )
    $policies = @($Data.Policies); $rules = @($Data.Rules); $tags = @($Data.Tags)


        $policyCards = foreach ($p in $policies) {
            $badges = (New-PavBadge -Bool $p.Enabled)
            if ($p.Mode -match 'Simulación') { $badges += New-PavBadge -Text $p.Mode -Type Warn }
            elseif ($p.Mode) { $badges += New-PavBadge -Text $p.Mode -Type Ok }
            if ("$($p.IsAdaptivePolicy)" -eq 'True') { $badges += New-PavBadge -Text 'Adaptativa' -Type Special }
            $props = [ordered]@{}
            foreach ($prop in $p.PSObject.Properties) { if ($prop.Name -ne 'PSTypeName') { $props[$prop.Name] = $prop.Value } }
            $body = New-PavPropList -Properties $props
            $locs = @($Data.PolicyLocations | Where-Object { $_.PolicyName -eq $p.Name -and $_.Coverage -ne 'No configurado' })
            if ($locs.Count) { $body += '<h4>Ubicaciones</h4>' + (New-PavHtmlTable -Data $locs -Property Workload, Coverage, Exclusions, IncludedDetails) }
            New-PavHtmlCard -Title $p.Name -Subtitle $p.PolicyType -BadgesHtml $badges -BodyHtml $body
        }

        $ruleCards = foreach ($r in $rules) {
            $badges = (New-PavBadge -Text $r.RetentionAction -Type Info) + (New-PavBadge -Text $r.RetentionDuration -Type Neutral)
            $props = [ordered]@{}
            foreach ($prop in $r.PSObject.Properties) {
                if ($prop.Name -eq 'PSTypeName' -or "$($prop.Value)" -eq '') { continue }
                $props[$prop.Name] = $prop.Value
            }
            New-PavHtmlCard -Title $r.RuleName -Subtitle "Directiva: $($r.PolicyName)" -BadgesHtml $badges -BodyHtml (New-PavPropList -Properties $props)
        }

        $tagCards = foreach ($t in $tags) {
            $catType = switch ($t.LabelCategory) { 'Regulatory Record' { 'Err' } 'Record Label' { 'Warn' } default { 'Neutral' } }
            $badges = (New-PavBadge -Text $t.LabelCategory -Type $catType) + (New-PavBadge -Text $t.RetentionDuration -Type Info)
            if ($t.HasReviewStages) { $badges += New-PavBadge -Text 'Revisión multi-etapa' -Type Special }
            $props = [ordered]@{}
            foreach ($prop in $t.PSObject.Properties) { if ($prop.Name -ne 'PSTypeName') { $props[$prop.Name] = $prop.Value } }
            $body = New-PavPropList -Properties $props
            $fp = @($Data.FilePlans | Where-Object LabelName -eq $t.Name)
            if ($fp.Count) { $body += '<h4>File Plan</h4>' + (New-PavHtmlTable -Data $fp -Property Department, Category, Subcategory, Authority, Citation) }
            $stages = @($Data.ReviewStages | Where-Object LabelName -eq $t.Name)
            if ($stages.Count) { $body += '<h4>Etapas de revisión</h4>' + (New-PavHtmlTable -Data $stages -Property StageId, StageName, Reviewers) }
            New-PavHtmlCard -Title $t.Name -Subtitle $t.RetentionAction -BadgesHtml $badges -BodyHtml $body
        }

        $sections = @(
            (New-PavHtmlSection -Id 'dlm-policies' -Title "$($TitlePrefix)Directivas" `
                -Description 'Directivas de retención y sus ubicaciones.' `
                -StatsHtml (New-PavStatGroup -Stats (
                    (New-PavStat -Label 'Directivas' -Value "$($policies.Count)"),
                    (New-PavStat -Label 'Adaptativas' -Value "$(@($policies | Where-Object { "$($_.IsAdaptivePolicy)" -eq 'True' }).Count)")
                )) -ContentHtml ($policyCards -join "`n")),
            (New-PavHtmlSection -Id 'dlm-rules' -Title "$($TitlePrefix)Reglas" `
                -Description 'Reglas de retención: acción, duración y auto-aplicación.' `
                -StatsHtml (New-PavStatGroup -Stats ((New-PavStat -Label 'Reglas' -Value "$($rules.Count)"))) `
                -ContentHtml ($ruleCards -join "`n")),
            (New-PavHtmlSection -Id 'dlm-tags' -Title "$($TitlePrefix)Etiquetas de retención" `
                -Description 'Etiquetas: categoría, file plan y revisión de disposición.' `
                -StatsHtml (New-PavStatGroup -Stats (
                    (New-PavStat -Label 'Etiquetas' -Value "$($tags.Count)"),
                    (New-PavStat -Label 'Records' -Value "$(@($tags | Where-Object LabelCategory -ne 'Standard Label').Count)"),
                    (New-PavStat -Label 'Con file plan' -Value "$(@($tags | Where-Object HasFilePlan).Count)")
                )) -ContentHtml ($tagCards -join "`n"))
        )

    return @($sections)
}

function New-PavSitSections {
<#
.SYNOPSIS
    Secciones HTML (detalle completo) de la carga Sit a partir de sus
    datos parseados. Compartido por el informe individual y el consolidado.
.PARAMETER Data
    Objeto de datos del colector correspondiente.
.PARAMETER TitlePrefix
    Prefijo de título para desambiguar pestañas en el consolidado
    (p. ej. 'DLP · ').
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Data,
        [Parameter()][string]$TitlePrefix = ''
    )
    $entities = @($Data.Entities)


        $resolveKw = {
            param($id)
            if (-not $id -or -not $Data.KeywordMap.ContainsKey($id)) { return '' }
            $parts = foreach ($g in $Data.KeywordMap[$id]) {
                $terms = @($g.Terms | ForEach-Object { $_.Text }) -join ', '
                "[$($g.MatchStyle)] $terms"
            }
            $parts -join ' | '
        }

        $cards = foreach ($e in $entities) {
            $badges = (New-PavBadge -Text "Confianza: $($e.RecommendedConfidence)" -Type Info) +
                      (New-PavBadge -Text "Proximidad: $($e.PatternsProximity)" -Type Neutral) +
                      (New-PavBadge -Text "$(@($e.Patterns).Count) patrón(es)" -Type Special)

            $patRows = foreach ($p in @($e.Patterns)) {
                $primary = if ($p.IdMatchRef -and $Data.RegexMap.ContainsKey($p.IdMatchRef)) { "$($p.IdMatchRef): $($Data.RegexMap[$p.IdMatchRef])" }
                           elseif ($p.IdMatchRef) { "$($p.IdMatchRef) $(& $resolveKw $p.IdMatchRef)" } else { '' }
                $support = @(foreach ($m in @($p.Matches)) {
                    if ($Data.RegexMap.ContainsKey($m.IdRef)) { "regex $($m.IdRef)" }
                    else { "$($m.IdRef) $(& $resolveKw $m.IdRef)" }
                }) -join '; '
                $filters = if ($p.FilterId -and $Data.FilterMap.ContainsKey($p.FilterId)) {
                    (@($Data.FilterMap[$p.FilterId] | ForEach-Object { "$($_.Type) [$($_.Logic)]" }) -join '; ')
                } else { '' }
                [pscustomobject]@{
                    'Confianza' = $p.ConfidenceLevel; 'Proximidad' = $p.Proximity
                    'Elemento primario (IdMatch)' = $primary
                    'Evidencia de soporte' = $support
                    'Filtros' = $filters
                }
            }
            $body = (New-PavPropList -Properties ([ordered]@{
                'ID' = $e.Id; 'Descripción' = $e.Description; 'Idioma' = $e.Language
                'Última modificación' = $e.LastModified; 'Min. versión de motor' = $e.MinEngineVersion
            })) + '<h4>Patrones de detección</h4>' + (New-PavHtmlTable -Data $patRows)
            New-PavHtmlCard -Title $e.Name -Subtitle $e.Id -BadgesHtml $badges -BodyHtml $body
        }

        $sections = @(New-PavHtmlSection -Id 'sits' -Title "$($TitlePrefix)SITs personalizados" `
            -Description "RulePackage: $($Data.RulePack.Name) — $($Data.RulePack.Publisher)" `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'SITs' -Value "$($entities.Count)"),
                (New-PavStat -Label 'Regex' -Value "$($Data.RegexMap.Count)"),
                (New-PavStat -Label 'Listas de keywords' -Value "$($Data.KeywordMap.Count)"),
                (New-PavStat -Label 'Filtros' -Value "$($Data.FilterMap.Count)")
            )) -ContentHtml ($cards -join "`n"))

    return @($sections)
}

