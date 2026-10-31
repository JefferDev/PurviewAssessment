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

        # ── Etiquetado automático: secciones adicionales solo si hay datos ────
        $autoPols  = @(Get-PavProp $Data 'AutoLabelPolicies' @())
        $autoRules = @(Get-PavProp $Data 'AutoLabelRules' @())
        if ($autoPols.Count -gt 0) {
            $autoCards = foreach ($ap in $autoPols) {
                $badges = New-PavBadge -Bool $ap.Enabled
                if ($ap.ModeFriendly -match 'Simulaci') { $badges += New-PavBadge -Text $ap.ModeFriendly -Type Warn }
                elseif ($ap.ModeFriendly -match 'Activa') { $badges += New-PavBadge -Text $ap.ModeFriendly -Type Ok }
                else { $badges += New-PavBadge -Text $ap.ModeFriendly -Type Neutral }
                if ($ap.LabelDisplayName) { $badges += New-PavBadge -Text "Etiqueta: $($ap.LabelDisplayName)" -Type Special }
                if ("$($ap.OverwriteLabel)" -eq 'True') { $badges += New-PavBadge -Text 'Sobrescribe etiqueta' -Type Err }
                if ($ap.AdaptiveScopes) { $badges += New-PavBadge -Text 'Ámbito adaptativo' -Type Info }
                if ("$($ap.DistributionStatus)" -eq 'Pending') { $badges += New-PavInconclusiveBadge 'Distribución pendiente' }

                $props = [ordered]@{}
                foreach ($prop in $ap.PSObject.Properties) {
                    if ($prop.Name -eq 'PSTypeName') { continue }
                    $props[$prop.Name] = $prop.Value
                }
                $body = New-PavPropList -Properties $props
                $rulesOf = @($autoRules | Where-Object PolicyName -eq $ap.Name)
                if ($rulesOf.Count) {
                    $body += '<h4>Reglas</h4>' + (New-PavHtmlTable -Data $rulesOf -Property RuleName, Mode, IsAdvancedRule, SensitiveInfoTypes, LogicalWorkload, ReportSeverityLevel)
                }
                New-PavHtmlCard -Title $ap.Name -Subtitle "Aplica: $($ap.ApplySensitivityLabel)" -BadgesHtml $badges -BodyHtml $body
            }

            $autoRuleCards = foreach ($ar in $autoRules) {
                $badges = ''
                if ($ar.Disabled -eq 'Sí') { $badges += New-PavBadge -Text 'Deshabilitada' -Type Neutral }
                if ($ar.IsAdvancedRule -eq 'Sí') { $badges += New-PavBadge -Text 'AdvancedRule' -Type Special }
                if ($ar.Mode) { $badges += New-PavBadge -Text $ar.Mode -Type Info }
                if ($ar.ReportSeverityLevel) { $badges += New-PavBadge -Text "Severidad: $($ar.ReportSeverityLevel)" -Type Neutral }

                $props = [ordered]@{}
                foreach ($prop in $ar.PSObject.Properties) {
                    if ($prop.Name -in @('PSTypeName', 'ConditionsHtml', 'ConditionsTree', 'AdvancedRuleRaw')) { continue }
                    if ($null -ne $prop.Value -and "$($prop.Value)" -ne '') { $props[$prop.Name] = $prop.Value }
                }
                $body = New-PavPropList -Properties $props
                if ($ar.ConditionsHtml) {
                    $body += "<h4>Árbol de condiciones (AdvancedRule)</h4><div class='pav-adv-tree'>$($ar.ConditionsHtml)</div>"
                }
                New-PavHtmlCard -Title $(if ($ar.DisplayName) { $ar.DisplayName } else { $ar.RuleName }) -Subtitle "Directiva: $($ar.PolicyName)" -BadgesHtml $badges -BodyHtml $body
            }

            $simCount = @($autoPols | Where-Object { $_.ModeFriendly -match 'Simulaci' }).Count
            $sections += (New-PavHtmlSection -Id 'mip-autolabel' -Title "$($TitlePrefix)Etiquetado automático" `
                -Description 'Directivas de etiquetado automático (auto-labeling) del lado del servicio.' `
                -StatsHtml (New-PavStatGroup -Stats (
                    (New-PavStat -Label 'Directivas' -Value "$($autoPols.Count)"),
                    (New-PavStat -Label 'En simulación' -Value "$simCount"),
                    (New-PavStat -Label 'Activas' -Value "$(@($autoPols | Where-Object { $_.ModeFriendly -match 'Activa' }).Count)"),
                    (New-PavStat -Label 'Reglas' -Value "$($autoRules.Count)")
                )) -ContentHtml ($autoCards -join "`n"))

            if ($autoRules.Count -gt 0) {
                $sections += (New-PavHtmlSection -Id 'mip-autolabel-rules' -Title "$($TitlePrefix)Reglas - Etiquetado automático" `
                    -Description 'Condiciones de detección: SITs, ámbito de acceso y árbol de AdvancedRule.' `
                    -StatsHtml (New-PavStatGroup -Stats (
                        (New-PavStat -Label 'Reglas' -Value "$($autoRules.Count)"),
                        (New-PavStat -Label 'AdvancedRule' -Value "$(@($autoRules | Where-Object IsAdvancedRule -eq 'Sí').Count)")
                    )) -ContentHtml ($autoRuleCards -join "`n"))
            }
        }

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
            $polRules  = @($rules | Where-Object PolicyName -eq $p.Name)
            $ruleCount = $polRules.Count
            $conBloqueo = @($polRules | Where-Object { "$(Get-PavProp $_ 'HasBlockingAction' '')" -eq 'Sí' -or "$($_.BlockAccess)" -eq 'Sí' })
            if ($conBloqueo.Count -gt 0) { $badges += New-PavBadge -Text "Bloquea ($($conBloqueo.Count)/$ruleCount)" -Type Err }
            elseif ($ruleCount -gt 0) { $badges += New-PavBadge -Text 'Solo detecta' -Type Warn }
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
            if ("$(Get-PavProp $r 'HasBlockingAction' '')" -eq 'Sí' -or $r.BlockAccess -eq 'Sí') {
                $resumen = "$(Get-PavProp $r 'BlockingSummary' '')"
                $corto = if ($resumen.Length -gt 58) { $resumen.Substring(0, 58) + '…' } else { $resumen }
                $badges += New-PavBadge -Text $(if ($corto) { "Bloquea: $corto" } else { 'Bloquea' }) -Type Err
            }
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
                '^Activating$'       { New-PavInconclusiveBadge 'Activating' }
                '^(Disabled|Error)$' { New-PavBadge -Text "$s" -Type Err }
                '^Inactive$'         { New-PavBadge -Text 'Inactive' -Type Neutral }
                default              { if ($s) { New-PavBadge -Text "$s" -Type Neutral } else { '' } }
            }
        }
        $provBadge = {
            param($s)
            switch -Regex ("$s") {
                '^Success$'    { New-PavBadge -Text 'Aprovisionada' -Type Ok }
                '^NotStarted$' { New-PavInconclusiveBadge 'Pendiente' }
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
                -Description $("Directivas del ámbito de ciclo de vida de los datos." + $(if (@(Get-PavProp $Data 'RecordsScopePolicies' @()).Count -gt 0) { " Se excluyen $(@(Get-PavProp $Data 'RecordsScopePolicies' @()).Count) directiva(s) que publican etiquetas de gestión de registros." } else { '' })) `
                -StatsHtml (New-PavStatGroup -Stats (
                    (New-PavStat -Label 'Directivas' -Value "$($policies.Count)"),
                    (New-PavStat -Label 'Adaptativas' -Value "$(@($policies | Where-Object { "$($_.IsAdaptivePolicy)" -eq 'True' }).Count)")
                )) -ContentHtml ($policyCards -join "`n")),
            (New-PavHtmlSection -Id 'dlm-rules' -Title "$($TitlePrefix)Reglas" `
                -Description 'Reglas de retención: acción, duración y auto-aplicación.' `
                -StatsHtml (New-PavStatGroup -Stats ((New-PavStat -Label 'Reglas' -Value "$($rules.Count)"))) `
                -ContentHtml ($ruleCards -join "`n")),
            (New-PavHtmlSection -Id 'dlm-tags' -Title "$($TitlePrefix)Etiquetas de retención" `
                -Description $("Etiquetas de retención por tiempo." + $(if (@(Get-PavProp $Data 'RecordsScopeTags' @()).Count -gt 0) { " Se excluyen $(@(Get-PavProp $Data 'RecordsScopeTags' @()).Count) etiqueta(s) del ámbito de gestión de registros." } else { '' })) `
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
            $packOf = "$(Get-PavProp $e 'RulePackName' '')"
            if ($packOf) { $badges += New-PavBadge -Text $packOf -Type Info }
            New-PavHtmlCard -Title $e.Name -Subtitle $e.Id -BadgesHtml $badges -BodyHtml $body
        }

        $packs = @(Get-PavProp $Data 'RulePacks' @())
        if ($packs.Count -eq 0 -and $Data.RulePack) { $packs = @($Data.RulePack) }
        $desc = if ($packs.Count -gt 1) { "$($packs.Count) RulePackages: $((@($packs | ForEach-Object { $_.Name }) -join ' · '))" }
                elseif ($packs.Count -eq 1) { "RulePackage: $($packs[0].Name) — $($packs[0].Publisher)" }
                else { 'Sin RulePackages de SITs personalizados.' }

        $sections = @(New-PavHtmlSection -Id 'sits' -Title "$($TitlePrefix)SITs personalizados" `
            -Description $desc `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'SITs' -Value "$($entities.Count)"),
                (New-PavStat -Label 'RulePackages' -Value "$($packs.Count)"),
                (New-PavStat -Label 'Regex' -Value "$($Data.RegexMap.Count)"),
                (New-PavStat -Label 'Listas de keywords' -Value "$($Data.KeywordMap.Count)"),
                (New-PavStat -Label 'Filtros' -Value "$($Data.FilterMap.Count)")
            )) -ContentHtml ($cards -join "`n"))

        # Sección propia de paquetes cuando hay más de uno
        if ($packs.Count -gt 1) {
            $packCards = foreach ($pk in $packs) {
                $b = New-PavBadge -Text "$($pk.SitCount) SIT(s)" -Type Special
                if ($pk.IsBuiltIn)     { $b += New-PavBadge -Text 'Integrado de Microsoft' -Type Neutral }
                if ($pk.IsFingerprint) { $b += New-PavBadge -Text 'Huellas digitales' -Type Neutral }
                if ($pk.Publisher)     { $b += New-PavBadge -Text $pk.Publisher -Type Info }
                $bodyP = (New-PavPropList -Properties ([ordered]@{
                    'Descripción' = $pk.Description; 'Versión' = $pk.Version
                    'Identity' = $pk.Identity; 'SITs' = $pk.SitCount
                })) + (New-PavHtmlTable -Data @($entities | Where-Object { "$(Get-PavProp $_ 'RulePackName' '')" -eq $pk.Name } |
                        ForEach-Object { [pscustomobject]@{ 'SIT' = $_.Name; 'Id' = $_.Id
                            'Confianza recomendada' = $_.RecommendedConfidence; 'Patrones' = @($_.Patterns).Count } }))
                New-PavHtmlCard -Title $pk.Name -Subtitle $pk.Publisher -BadgesHtml $b -BodyHtml $bodyP
            }
            $sections = @((New-PavHtmlSection -Id 'sit-packs' -Title "$($TitlePrefix)RulePackages" `
                -Description 'Paquetes de reglas de SITs presentes en el tenant y su contenido.' `
                -StatsHtml (New-PavStatGroup -Stats (
                    (New-PavStat -Label 'RulePackages' -Value "$($packs.Count)"),
                    (New-PavStat -Label 'SITs totales' -Value "$($entities.Count)")
                )) -ContentHtml ($packCards -join "`n"))) + $sections
        }

    return @($sections)
}


function New-PavRmSections {
<#
.SYNOPSIS
    Secciones HTML (detalle completo) de Records Management.
.PARAMETER Data
    Objeto de Get-PurviewRmData.
.PARAMETER TitlePrefix
    Prefijo de título para desambiguar pestañas en el consolidado.
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Data,
        [Parameter()][string]$TitlePrefix = ''
    )
    $props    = @($Data.FilePlanProperties)
    $evTypes  = @($Data.EventTypes)
    $events   = @($Data.Events)
    $recTags  = @($Data.RecordTags)
    $scopes   = @($Data.AdaptiveScopes)
    $findings = @($Data.Findings)
    $sections = @()

    # Nota: los hallazgos de gobierno se presentan en el informe de evaluación
    # de controles. Este informe es el inventario de la configuración.

    # ── File plan ──
    if ($props.Count -gt 0) {
        $planCards = foreach ($grp in ($props | Group-Object Type)) {
            $cols = if ($grp.Name -eq 'Citation') { @('Name', 'CitationJurisdiction', 'CitationUrl', 'Priority', 'LastModifiedBy') }
                    else { @('Name', 'Comment', 'Priority', 'Workload', 'LastModifiedBy', 'LastModifiedUtc') }
            $badges = New-PavBadge -Text "$($grp.Count) elemento(s)" -Type Info
            if ($grp.Name -eq 'Citation') {
                $sinRef = @($grp.Group | Where-Object { -not $_.HasCitationDetail }).Count
                if ($sinRef -gt 0) { $badges += New-PavBadge -Text "$sinRef sin referencia normativa" -Type Err }
            }
            New-PavHtmlCard -Title $grp.Name -BadgesHtml $badges `
                -BodyHtml (New-PavHtmlTable -Data @($grp.Group) -Property $cols)
        }
        $sections += (New-PavHtmlSection -Id 'rm-fileplan' -Title "$($TitlePrefix)File plan" `
            -Description 'Catálogo de descriptores: departamento, categoría, subcategoría, autoridad, citación y ID de referencia.' `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Descriptores' -Value "$($props.Count)"),
                (New-PavStat -Label 'Tipos usados' -Value "$(@($props | Group-Object Type).Count)"),
                (New-PavStat -Label 'Citaciones' -Value "$(@($props | Where-Object Type -eq 'Citation').Count)")
            )) -ContentHtml ($planCards -join "`n"))
    }

    # ── Retención por eventos ──
    if ($evTypes.Count -gt 0 -or $events.Count -gt 0) {
        $evCards = foreach ($e in $evTypes) {
            $badges = if ($e.LinkedLabelCount -gt 0) { New-PavBadge -Text "$($e.LinkedLabelCount) etiqueta(s)" -Type Ok }
                      else { New-PavBadge -Text 'Sin etiquetas asociadas' -Type Err }
            if ("$($e.Disabled)" -eq 'True') { $badges += New-PavBadge -Text 'Deshabilitado' -Type Neutral }
            $p = [ordered]@{}
            foreach ($prop in $e.PSObject.Properties) { if ($prop.Name -ne 'PSTypeName') { $p[$prop.Name] = $prop.Value } }
            $body = New-PavPropList -Properties $p
            $inst = @($events | Where-Object EventType -eq $e.Name)
            if ($inst.Count) { $body += '<h4>Eventos registrados</h4>' + (New-PavHtmlTable -Data $inst -Property Name, EventDateTime, SharePointAssetIdQuery, Status) }
            New-PavHtmlCard -Title $e.Name -Subtitle $e.Comment -BadgesHtml $badges -BodyHtml $body
        }
        $sections += (New-PavHtmlSection -Id 'rm-events' -Title "$($TitlePrefix)Retención por eventos" `
            -Description 'Tipos de evento que disparan el cómputo de retención y sus etiquetas asociadas.' `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Tipos de evento' -Value "$($evTypes.Count)"),
                (New-PavStat -Label 'Sin etiquetas' -Value "$(@($evTypes | Where-Object LinkedLabelCount -eq 0).Count)"),
                (New-PavStat -Label 'Eventos activos' -Value "$($events.Count)")
            )) -ContentHtml ($evCards -join "`n"))
    }

    # ── Etiquetas de retención (inventario completo) ──
    $retLabels = @(Get-PavProp $Data 'RetentionLabels' @())
    if ($retLabels.Count -gt 0) {
        $retCards = foreach ($t in $retLabels) {
            $tipo = switch -Wildcard ("$($t.LabelCategory)") { 'Registro regulado' { 'Err' } 'Registro' { 'Warn' } default { 'Neutral' } }
            $badges = (New-PavBadge -Text $t.LabelCategory -Type $tipo) + (New-PavBadge -Text $t.RetentionDuration -Type Info)
            if ($t.HasFilePlan)     { $badges += New-PavBadge -Text 'Con file plan' -Type Ok }
            if ($t.HasReviewStages) { $badges += New-PavBadge -Text 'Revisión de disposición' -Type Special }
            if ($t.EventTypeId)     { $badges += New-PavBadge -Text 'Basada en evento' -Type Info }
            $p = [ordered]@{}
            foreach ($prop in $t.PSObject.Properties) { if ($prop.Name -ne 'PSTypeName') { $p[$prop.Name] = $prop.Value } }
            New-PavHtmlCard -Title $t.Name -Subtitle $t.RetentionAction -BadgesHtml $badges -BodyHtml (New-PavPropList -Properties $p)
        }
        $sections += (New-PavHtmlSection -Id 'rm-labels' -Title "$($TitlePrefix)Etiquetas de retención" `
            -Description $("Etiquetas del ámbito de gestión de registros: incorporadas al plan de archivos, con revisión de disposición, declaradas como registro o con retención basada en evento." + $(if (@(Get-PavProp $Data 'LifecycleLabels' @()).Count -gt 0) { " Otras $(@(Get-PavProp $Data 'LifecycleLabels' @()).Count) etiqueta(s) conservan por tiempo y corresponden al ciclo de vida de los datos (DLM)." } else { '' })) `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Etiquetas' -Value "$($retLabels.Count)"),
                (New-PavStat -Label 'Declaradas registro' -Value "$(@($retLabels | Where-Object { "$($_.IsRecordLabel)" -eq 'True' }).Count)"),
                (New-PavStat -Label 'Con file plan' -Value "$(@($retLabels | Where-Object HasFilePlan).Count)"),
                (New-PavStat -Label 'Basadas en evento' -Value "$(@($retLabels | Where-Object EventTypeId).Count)")
            )) -ContentHtml ($retCards -join "`n"))
    }

    # ── Directivas de publicación ──
    # Una directiva pertenece al ámbito de registros si publica alguna etiqueta
    # de ese ámbito. Si el cruce no resolvió en ninguna, se muestran todas.
    $todasPub = @(Get-PavProp $Data 'PublishPolicies' @())
    $conRegistros = @($todasPub | Where-Object { "$(Get-PavProp $_ 'PublicaRegistros' '')" -eq 'True' })
    $pubPols = if ($conRegistros.Count -gt 0) { $conRegistros } else { $todasPub }
    if ($pubPols.Count -gt 0) {
        $pubCards = foreach ($pp in $pubPols) {
            $badges = (New-PavBadge -Bool $pp.Enabled) + (New-PavBadge -Text $pp.Mode -Type $(if ("$($pp.Mode)" -match 'Simulaci') { 'Warn' } else { 'Ok' }))
            if ($pp.LabelCount -gt 0) { $badges += New-PavBadge -Text "$($pp.LabelCount) etiqueta(s)" -Type Info }
            if ("$($pp.IsAdaptive)" -eq 'True') { $badges += New-PavBadge -Text 'Ámbito adaptativo' -Type Special }
            if ("$($pp.RestrictiveRetention)" -eq 'True') { $badges += New-PavBadge -Text 'Bloqueo de preservación' -Type Err }
            $p = [ordered]@{}
            foreach ($prop in $pp.PSObject.Properties) { if ($prop.Name -ne 'PSTypeName') { $p[$prop.Name] = $prop.Value } }
            New-PavHtmlCard -Title $pp.Name -Subtitle $pp.PolicyType -BadgesHtml $badges -BodyHtml (New-PavPropList -Properties $p)
        }
        $sections += (New-PavHtmlSection -Id 'rm-publish' -Title "$($TitlePrefix)Directivas de publicación" `
            -Description $(if ($conRegistros.Count -gt 0) { "Directivas que publican etiquetas del ámbito de gestión de registros. Otras $($todasPub.Count - $conRegistros.Count) directiva(s) de retención corresponden al ciclo de vida de los datos." } else { 'Directivas de retención del tenant y ubicaciones que alcanzan. No fue posible determinar cuáles publican etiquetas del ámbito de registros, por lo que se listan todas.' }) `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Directivas' -Value "$($pubPols.Count)"),
                (New-PavStat -Label 'Habilitadas' -Value "$(@($pubPols | Where-Object { "$($_.Enabled)" -eq 'True' }).Count)"),
                (New-PavStat -Label 'Con bloqueo de preservación' -Value "$(@($pubPols | Where-Object { "$($_.RestrictiveRetention)" -eq 'True' }).Count)")
            )) -ContentHtml ($pubCards -join "`n"))
    }

    # ── Etiquetas de registro ──
    if ($recTags.Count -gt 0) {
        $tagCards = foreach ($t in $recTags) {
            $badges = New-PavBadge -Text $t.LabelCategory -Type $(if ($t.Regulatory) { 'Err' } else { 'Warn' })
            $badges += New-PavBadge -Text $t.RetentionDuration -Type Info
            if (-not $t.HasFilePlan)     { $badges += New-PavBadge -Text 'Sin file plan' -Type Err }
            if ($t.HasReviewStages)      { $badges += New-PavBadge -Text 'Revisión de disposición' -Type Special }
            if ($t.EventTypeId)          { $badges += New-PavBadge -Text 'Basada en evento' -Type Info }
            $p = [ordered]@{}
            foreach ($prop in $t.PSObject.Properties) { if ($prop.Name -ne 'PSTypeName') { $p[$prop.Name] = $prop.Value } }
            New-PavHtmlCard -Title $t.Name -Subtitle $t.RetentionAction -BadgesHtml $badges -BodyHtml (New-PavPropList -Properties $p)
        }
        $sections += (New-PavHtmlSection -Id 'rm-records' -Title "$($TitlePrefix)Etiquetas de registro" `
            -Description 'Etiquetas que declaran contenido como registro, con su file plan y disposición.' `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Etiquetas' -Value "$($recTags.Count)"),
                (New-PavStat -Label 'Registros regulados' -Value "$(@($recTags | Where-Object Regulatory).Count)"),
                (New-PavStat -Label 'Sin file plan' -Value "$(@($recTags | Where-Object { -not $_.HasFilePlan }).Count)"),
                (New-PavStat -Label 'Con revisión' -Value "$(@($recTags | Where-Object HasReviewStages).Count)")
            )) -ContentHtml ($tagCards -join "`n"))
    }

    # ── Ámbitos adaptativos ──
    if ($scopes.Count -gt 0) {
        $scopeCards = foreach ($s in $scopes) {
            $p = [ordered]@{}
            foreach ($prop in $s.PSObject.Properties) { if ($prop.Name -ne 'PSTypeName') { $p[$prop.Name] = $prop.Value } }
            New-PavHtmlCard -Title $s.Name -Subtitle $s.LocationType `
                -BadgesHtml (New-PavBadge -Text $s.LocationType -Type Info) -BodyHtml (New-PavPropList -Properties $p)
        }
        $sections += (New-PavHtmlSection -Id 'rm-scopes' -Title "$($TitlePrefix)Ámbitos adaptativos" `
            -Description 'Consultas dinámicas que definen el alcance de las directivas de retención.' `
            -StatsHtml (New-PavStatGroup -Stats ((New-PavStat -Label 'Ámbitos' -Value "$($scopes.Count)"))) `
            -ContentHtml ($scopeCards -join "`n"))
    }

    if ($sections.Count -eq 0) {
        $sections = @(New-PavHtmlSection -Id 'rm-empty' -Title "$($TitlePrefix)Records Management" `
            -Description 'No se recolectó configuración de Records Management en este tenant.' -ContentHtml $null)
    }
    return @($sections)
}

function New-PavAuditSections {
<#
.SYNOPSIS
    Secciones HTML (detalle completo) de la carga de auditoría.
.PARAMETER Data
    Objeto de Get-PurviewAuditData.
.PARAMETER TitlePrefix
    Prefijo de título para desambiguar pestañas en el consolidado.
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Data,
        [Parameter()][string]$TitlePrefix = ''
    )
    $pols     = @($Data.RetentionPolicies)
    $st       = $Data.Status
    $findings = @($Data.Findings)
    $sections = @()

    # ── Estado y hallazgos ──
    $stBadges = ''
    switch ("$($st.UnifiedAuditLogIngestion)") {
        'Habilitada'      { $stBadges += New-PavBadge -Text 'Auditoría unificada habilitada' -Type Ok }
        'Deshabilitada'   { $stBadges += New-PavBadge -Text 'Auditoría unificada DESHABILITADA' -Type Err }
        default           { $stBadges += New-PavBadge -Text 'Ingesta no determinable' -Type Warn }
    }
    switch ("$($st.MailboxAuditing)") {
        'Habilitada'    { $stBadges += New-PavBadge -Text 'Auditoría de buzones habilitada' -Type Ok }
        'Deshabilitada' { $stBadges += New-PavBadge -Text 'Auditoría de buzones DESHABILITADA' -Type Err }
        default         { $stBadges += New-PavBadge -Text 'Buzones no determinable' -Type Neutral }
    }

    $stProps = [ordered]@{
        'Ingesta de auditoría unificada' = $st.UnifiedAuditLogIngestion
        'Nota sobre la verificación'     = $st.IngestionNote
        'Registro de auditoría de administración' = $st.AdminAuditLog
        'Auditoría de buzones (organización)'     = $st.MailboxAuditing
        'Sesión de Exchange Online'      = $st.ExchangeOnlineSession
        'Directivas de retención'        = $st.RetentionPolicyCount
    }
    $statusCard = New-PavHtmlCard -Title 'Estado del registro de auditoría' `
        -BadgesHtml $stBadges -BodyHtml (New-PavPropList -Properties $stProps) -Expanded

    # Nota: los hallazgos de gobierno se presentan en el informe de evaluación
    # de controles. Este informe documenta la configuración existente.

    $sections += (New-PavHtmlSection -Id 'audit-status' -Title "$($TitlePrefix)Estado del registro" `
        -Description 'Estado del registro de auditoría unificada y de la auditoría de buzones.' `
        -StatsHtml (New-PavStatGroup -Stats (
            (New-PavStat -Label 'Directivas de retención' -Value "$($pols.Count)"),
            (New-PavStat -Label 'Auditoría unificada' -Value "$($st.UnifiedAuditLogIngestion)"),
            (New-PavStat -Label 'Auditoría de buzones' -Value "$($st.MailboxAuditing)")
        )) -ContentHtml $statusCard)

    # ── Directivas de retención ──
    if ($pols.Count -gt 0) {
        $polCards = foreach ($p in ($pols | Sort-Object Priority)) {
            $badges = (New-PavBadge -Bool $p.Enabled) + (New-PavBadge -Text $p.RetentionDuration -Type Info)
            $badges += New-PavBadge -Text "Prioridad $($p.Priority)" -Type Neutral
            if ($p.AppliesToAll) { $badges += New-PavBadge -Text 'Aplica a todo' -Type Special }
            if ("$($p.DistributionStatus)" -eq 'Pending') { $badges += New-PavInconclusiveBadge 'Distribución pendiente' }
            elseif ("$($p.DistributionStatus)" -in @('Failed', 'Error')) { $badges += New-PavBadge -Text 'Distribución fallida' -Type Err }

            $props = [ordered]@{}
            foreach ($prop in $p.PSObject.Properties) { if ($prop.Name -ne 'PSTypeName') { $props[$prop.Name] = $prop.Value } }
            New-PavHtmlCard -Title $p.Name -Subtitle $p.Description -BadgesHtml $badges -BodyHtml (New-PavPropList -Properties $props)
        }
        $sections += (New-PavHtmlSection -Id 'audit-retention' -Title "$($TitlePrefix)Retención de auditoría" `
            -Description 'Directivas que definen cuánto se conservan los registros según tipo, operación o usuario.' `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Directivas' -Value "$($pols.Count)"),
                (New-PavStat -Label 'Habilitadas' -Value "$(@($pols | Where-Object { "$($_.Enabled)" -eq 'True' }).Count)"),
                (New-PavStat -Label 'Retención máxima' -Value "$(if ($pols.Count) { (ConvertTo-PavAuditDuration (($pols | Sort-Object RetentionDays -Descending | Select-Object -First 1).RetentionRaw)) } else { 'N/D' })")
            )) -ContentHtml ($polCards -join "`n"))
    }

    return @($sections)
}

function New-PavEdsSections {
<#
.SYNOPSIS
    Secciones HTML del informe de eDiscovery.
.PARAMETER Data
    Objeto de Get-PurviewEdsData.
.PARAMETER TitlePrefix
    Prefijo de título para el consolidado.
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][string]$TitlePrefix = '')
    $cases = @($Data.Cases); $holds = @($Data.HoldPolicies); $srch = @($Data.Searches)
    $sections = @()

    if ($cases.Count -gt 0) {
        $cards = foreach ($c in $cases) {
            $b = New-PavBadge -Text $c.Status -Type $(if ("$($c.Status)" -eq 'Active') { 'Ok' } elseif ("$($c.Status)" -eq 'Closed') { 'Neutral' } else { 'Info' })
            $b += New-PavBadge -Text $c.CaseType -Type Special
            if ($c.MemberCount -gt 0) { $b += New-PavBadge -Text "$($c.MemberCount) miembro(s)" -Type Info }
            else { $b += New-PavInconclusiveBadge 'Sin miembros asignados' }
            $p = [ordered]@{}
            foreach ($pr in $c.PSObject.Properties) { if ($pr.Name -ne 'PSTypeName') { $p[$pr.Name] = $pr.Value } }
            $body = New-PavPropList -Properties $p
            $hs = @($holds | Where-Object CaseName -eq $c.Name)
            if ("$(Get-PavProp $c 'PortalOnlyDetails' '')") {
                $body += "<h4>Elementos no visibles por PowerShell</h4>" + (New-PavPropList -Properties ([ordered]@{
                    'Detalle' = "$(Get-PavProp $c 'PortalOnlyDetails' '')" }))
            }
            $sr = @($Data.Searches | Where-Object CaseName -eq $c.Name)
            if ($sr.Count) { $body += '<h4>Búsquedas</h4>' + (New-PavHtmlTable -Data $sr -Property Name, Status, ContentMatchQuery, CreatedBy) }
            if ($hs.Count) { $body += '<h4>Retenciones legales</h4>' + (New-PavHtmlTable -Data $hs -Property Name, Enabled, Exchange, SharePoint, OneDrive, DistributionStatus) }
            New-PavHtmlCard -Title $c.Name -Subtitle $c.Description -BadgesHtml $b -BodyHtml $body
        }
        $sections += (New-PavHtmlSection -Id 'eds-cases' -Title "$($TitlePrefix)Casos" `
            -Description 'Casos de descubrimiento electrónico y sus retenciones legales.' `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Casos' -Value "$($cases.Count)"),
                (New-PavStat -Label 'Activos' -Value "$(@($cases | Where-Object Status -ne 'Closed').Count)"),
                (New-PavStat -Label 'Sin miembros' -Value "$(@($cases | Where-Object { $_.MemberCount -eq 0 }).Count)")
            )) -ContentHtml ($cards -join "`n"))
    }

    if ($holds.Count -gt 0) {
        $hcards = foreach ($h in $holds) {
            $b = (New-PavBadge -Bool $h.Enabled)
            if ("$($h.DistributionStatus)" -eq 'Pending') { $b += New-PavInconclusiveBadge 'Distribución pendiente' }
            $p = [ordered]@{}
            foreach ($pr in $h.PSObject.Properties) { if ($pr.Name -ne 'PSTypeName') { $p[$pr.Name] = $pr.Value } }
            New-PavHtmlCard -Title $h.Name -Subtitle "Caso: $($h.CaseName)" -BadgesHtml $b -BodyHtml (New-PavPropList -Properties $p)
        }
        $sections += (New-PavHtmlSection -Id 'eds-holds' -Title "$($TitlePrefix)Retenciones legales" `
            -Description 'Directivas de retención de caso y ubicaciones preservadas.' `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Retenciones' -Value "$($holds.Count)"),
                (New-PavStat -Label 'Habilitadas' -Value "$(@($holds | Where-Object { "$($_.Enabled)" -in @('True','Sí') }).Count)")
            )) -ContentHtml ($hcards -join "`n"))
    }

    if ($srch.Count -gt 0) {
        $sections += (New-PavHtmlSection -Id 'eds-searches' -Title "$($TitlePrefix)Búsquedas" `
            -Description 'Búsquedas de cumplimiento registradas.' `
            -StatsHtml (New-PavStatGroup -Stats ((New-PavStat -Label 'Búsquedas' -Value "$($srch.Count)"))) `
            -ContentHtml (New-PavHtmlTable -Data $srch -Property Name, Status, CaseName, ContentMatchQuery, CreatedBy))
    }

    if ($sections.Count -eq 0) {
        $sections = @(New-PavHtmlSection -Id 'eds-empty' -Title "$($TitlePrefix)eDiscovery" `
            -Description 'No se encontraron casos, retenciones legales ni búsquedas en el tenant.' -ContentHtml $null)
    }
    return @($sections)
}
