function Get-PurviewDlmData {
<#
.SYNOPSIS
    Recolecta y parsea la configuración de retención/DLM: directivas,
    reglas y etiquetas (solo lectura). Port de Export-DLMConfiguration.ps1.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.DlmData' con Policies,
    PolicyLocations, Rules, Tags, FilePlans, ReviewStages, CollectedAt.
.EXAMPLE
    (Get-PurviewDlmData).Tags | Where-Object LabelCategory -eq 'Regulatory Record'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Assert-PavConnection
    Write-PavLog -Level Step -Message 'Recolectando configuración de retención (DLM)...'

    $rawPolicies = @(Invoke-PavRetry -OperationName 'Get-RetentionCompliancePolicy' -ScriptBlock {
        Get-RetentionCompliancePolicy -DistributionDetail -ErrorAction Stop })
    $rawRules = @(Invoke-PavRetry -OperationName 'Get-RetentionComplianceRule' -ScriptBlock {
        Get-RetentionComplianceRule -ErrorAction Stop })

    # Las directivas que cubren Teams (chats, canales y canales privados) y
    # Viva Engage, así como las de ámbito adaptativo, NO se devuelven con
    # Get-RetentionCompliancePolicy: viven en los cmdlets *-AppRetentionCompliance*.
    # Omitirlas produce un falso negativo de cobertura en esas cargas.
    if (Get-Command Get-AppRetentionCompliancePolicy -ErrorAction SilentlyContinue) {
        try {
            $appPols = @(Invoke-PavRetry -OperationName 'Get-AppRetentionCompliancePolicy' -MaxAttempts 2 -ScriptBlock {
                Get-AppRetentionCompliancePolicy -DistributionDetail -ErrorAction Stop })
            if ($appPols.Count -gt 0) {
                Write-PavLog -Level Info -Message "  > Directivas de aplicaciones (Teams, Viva Engage, ámbito adaptativo): $($appPols.Count)"
                $rawPolicies += $appPols
            }
        }
        catch { Write-PavLog -Level Warn -Message "  - Directivas de aplicaciones no recuperadas: $($_.Exception.Message)" }
        if (Get-Command Get-AppRetentionComplianceRule -ErrorAction SilentlyContinue) {
            try {
                $appRules = @(Invoke-PavRetry -OperationName 'Get-AppRetentionComplianceRule' -MaxAttempts 2 -ScriptBlock {
                    Get-AppRetentionComplianceRule -ErrorAction Stop })
                if ($appRules.Count -gt 0) { $rawRules += $appRules }
            }
            catch { Write-PavLog -Level Warn -Message "  - Reglas de aplicaciones no recuperadas: $($_.Exception.Message)" }
        }
    }
    else { Write-PavLog -Level Warn -Message '  - Get-AppRetentionCompliancePolicy no disponible: las directivas de Teams y Viva Engage no podrán evaluarse.' }
    $rawTags = @(Invoke-PavRetry -OperationName 'Get-ComplianceTag' -ScriptBlock {
        Get-ComplianceTag -ErrorAction Stop })
    Write-PavLog -Level Info -Message "Directivas: $($rawPolicies.Count) | Reglas: $($rawRules.Count) | Etiquetas: $($rawTags.Count)"

    [void](Resolve-PavDistributionStatus -Policies $rawPolicies -CmdletName 'Get-RetentionCompliancePolicy')
    # Mapa GUID/ExchangeObjectId → nombre (port de Build-PolicyGuidMap)
    $guidMap = @{}
    foreach ($p in $rawPolicies) {
        foreach ($k in "$(Get-PavProp $p 'Guid' '')", "$(Get-PavProp $p 'ExchangeObjectId' '')") {
            if ($k -and -not $guidMap.ContainsKey($k)) { $guidMap[$k] = [string](Get-PavProp $p 'Name' '') }
        }
    }

    $locationDefs = [ordered]@{
        'SharePoint'     = @{ Incl = 'SharePointLocation';    Excl = 'SharePointLocationException' }
        'Exchange'       = @{ Incl = 'ExchangeLocation';      Excl = 'ExchangeLocationException' }
        'OneDrive'       = @{ Incl = 'OneDriveLocation';      Excl = 'OneDriveLocationException' }
        'Teams Chat'     = @{ Incl = 'TeamsChatLocation';     Excl = 'TeamsChatLocationException' }
        'Teams Channel'  = @{ Incl = 'TeamsChannelLocation';  Excl = 'TeamsChannelLocationException' }
        'Grupos M365'    = @{ Incl = 'ModernGroupLocation';   Excl = 'ModernGroupLocationException' }
        'Skype'          = @{ Incl = 'SkypeLocation';         Excl = 'SkypeLocationException' }
        'Carpetas Públicas' = @{ Incl = 'PublicFolderLocation'; Excl = $null }
        'Ámbito Adaptativo' = @{ Incl = 'AdaptiveScopeLocation'; Excl = $null }
        'Viva Engage'       = @{ Incl = 'YammerLocation';         Excl = 'YammerLocationException' }
    }

    $ixP = 0
    $policies = foreach ($p in $rawPolicies) {
        $ixP++
        Write-PavLog -Level Info -Message "  > Directiva $ixP/$($rawPolicies.Count): $(Get-PavProp $p 'Name' '(sin nombre)')"
        $configured = 0
        foreach ($def in $locationDefs.Values) {
            $arr = @(Get-PavProp $p $def.Incl @())
            if ($arr.Count -gt 0 -and "$($arr[0])" -ne '') { $configured++ }
        }
        [pscustomobject]@{
            PSTypeName = 'PurviewAssessment.DlmPolicy'
            Name       = [string](Get-PavProp $p 'Name' '')
            Guid       = [string](Get-PavProp $p 'Guid' '')
            PolicyType = ConvertTo-PavFriendlyPolicyType ([string](Get-PavProp $p 'Type' ''))
            Mode       = ConvertTo-PavFriendlyMode ([string](Get-PavProp $p 'Mode' '')) ([bool](Get-PavProp $p 'IsSimulation' $false))
            Enabled    = Get-PavProp $p 'Enabled'
            Priority   = Get-PavProp $p 'Priority'
            DistributionStatus  = [string](Get-PavProp $p 'DistributionStatus' '')
            Workload            = [string](Get-PavProp $p 'Workload' '')
            ConfiguredLocations = $configured
            IsAdaptivePolicy    = Get-PavProp $p 'IsAdaptivePolicy'
            RestrictiveRetention = Get-PavProp $p 'RestrictiveRetention'
            TeamsPolicy         = Get-PavProp $p 'TeamsPolicy'
            RetainCloudAttachment = Get-PavProp $p 'RetainCloudAttachment'
            Applications        = (@(Get-PavProp $p 'Applications' @()) | Where-Object { $_ }) -join ', '
            ApplicationsDetalle = Get-PavAppScopeDetail ((@(@(Get-PavProp $p 'Applications' @()) | Where-Object { $_ })) -join ', ')
            NotaAlcance         = $(if (@(@(Get-PavProp $p 'Applications' @()) | Where-Object { $_ }).Count -gt 0) {
                'En las directivas de aplicaciones, Workload y las ubicaciones de Exchange o grupos son el sustrato de almacenamiento, no el alcance. El alcance efectivo es el declarado en Applications. La ubicación de experiencias de Copilot está en versión preliminar y no admite filtrado por aplicación.'
            } else { '' })
            IsValid             = Get-PavProp $p 'IsValid'
            CreatedBy           = [string](Get-PavProp $p 'CreatedBy' '')
            LastModifiedBy      = [string](Get-PavProp $p 'LastModifiedBy' '')
            CreatedUtc          = Get-PavProp $p 'CreationTimeUtc'
            LastModifiedUtc     = Get-PavProp $p 'ModificationTimeUtc'
        }
    }

    # Cargas declaradas en Applications por las directivas de aplicaciones.
    # Estas directivas no pueblan TeamsChatLocation ni TeamsChannelLocation:
    # expresan la carga real en Applications, y sus ubicaciones de Exchange y
    # grupos son solo el sustrato donde se almacenan los mensajes.
    $appWorkloadMap = [ordered]@{
        'TeamsChatUserInteractions' = 'Teams Chat'
        'MicrosoftTeams'            = 'Teams Channel'
        'TeamsChannel'              = 'Teams Channel'
        'CopilotInteractions'       = 'Copilot'
        'M365Copilot'               = 'Copilot'
        'CopilotForSecurity'        = 'Copilot'
        'CopilotinFabricPowerBI'    = 'Copilot'
        'CopilotStudio'             = 'Copilot'
        'SQLCopilot'                = 'Copilot'
        'Yammer'                    = 'Viva Engage'
        'VivaEngage'                = 'Viva Engage'
    }
    $cargasPorDirectiva = @{}
    foreach ($p in $rawPolicies) {
        $apps = "$(Get-PavProp $p 'Applications' '')"
        if (-not $apps) { continue }
        $derivadas = @()
        foreach ($k in $appWorkloadMap.Keys) {
            if ($apps -like "*$k*" -and $derivadas -notcontains $appWorkloadMap[$k]) { $derivadas += $appWorkloadMap[$k] }
        }
        if ($derivadas.Count -gt 0) { $cargasPorDirectiva["$(Get-PavProp $p 'Name' '')"] = $derivadas }
    }

    # Ubicaciones expandidas (port de Expand-PolicyLocations)
    $locations = foreach ($p in $rawPolicies) {
        $pName = [string](Get-PavProp $p 'Name' '')
        # Cargas declaradas vía Applications, con el alcance de la directiva
        if ($cargasPorDirectiva.ContainsKey($pName)) {
            $alcance = 'Todos'
            foreach ($lp in 'ExchangeLocation', 'ModernGroupLocation', 'AdaptiveScopeLocation') {
                $v = Get-PavLocationScope (Get-PavProp $p $lp @())
                if ($v -ne 'No configurado') { $alcance = $v; break }
            }
            foreach ($carga in $cargasPorDirectiva[$pName]) {
                [pscustomobject]@{
                    PolicyName      = $pName
                    Workload        = $carga
                    Coverage        = $alcance
                    Exclusions      = ''
                    IncludedDetails = $(
                        $leg = Get-PavAppScopeDetail "$(Get-PavProp $p 'Applications' '')"
                        if (-not $leg) { $leg = "$(Get-PavProp $p 'Applications' '')" }
                        "Alcance declarado en Applications: $leg")
                    ExcludedDetails = ''
                }
            }
        }
        foreach ($loc in $locationDefs.GetEnumerator()) {
            $incl = @(Get-PavProp $p $loc.Value.Incl @())
            $excl = if ($loc.Value.Excl) { @(Get-PavProp $p $loc.Value.Excl @()) } else { @() }
            $exclNonEmpty = @($excl | Where-Object { $_ })
            [pscustomobject]@{
                PolicyName      = $pName
                Workload        = $loc.Key
                Coverage        = Get-PavLocationScope $incl
                Exclusions      = if ($exclNonEmpty.Count) { "$($exclNonEmpty.Count) excluido(s)" } else { '' }
                IncludedDetails = Get-PavLocationDetails $incl
                ExcludedDetails = (@($exclNonEmpty | ForEach-Object { "$_" }) -join ' | ')
            }
        }
    }

    # Reglas (port de Build-RuleSummaryRow)
    $ixR = 0
    $rules = foreach ($r in $rawRules) {
        $ixR++
        Write-PavLog -Level Info -Message "  > Regla $ixR/$($rawRules.Count): $(Get-PavProp $r 'Name' '(sin nombre)')"
        $polGuid = "$(Get-PavProp $r 'Policy' '')"
        $tagProp = "$(Get-PavProp $r 'ComplianceTagProperty' '')"
        $publish = "$(Get-PavProp $r 'PublishComplianceTag' '')"
        [pscustomobject]@{
            PSTypeName  = 'PurviewAssessment.DlmRule'
            PolicyName  = if ($guidMap.ContainsKey($polGuid)) { $guidMap[$polGuid] } else { $polGuid }
            RuleName    = [string](Get-PavProp $r 'Name' '')
            Disabled    = Get-PavProp $r 'Disabled'
            Mode        = [string](Get-PavProp $r 'Mode' '')
            RetentionAction   = ConvertTo-PavFriendlyAction ([string](Get-PavProp $r 'RetentionComplianceAction' ''))
            RetentionDuration = ConvertTo-PavFriendlyDuration (Get-PavProp $r 'RetentionDuration')
            RetentionDurationRawDays = "$(Get-PavProp $r 'RetentionDuration' '')"
            # En las reglas de retención, el momento desde el que se cuenta el
            # periodo viaja en ExpirationDateOption; RetentionType solo se
            # puebla en las etiquetas (Get-ComplianceTag). Se usa el primero
            # que traiga valor y se conserva siempre el literal del cmdlet.
            RetentionType     = $(
                $rt = [string](Get-PavProp $r 'RetentionType' '')
                if (-not $rt) { $rt = [string](Get-PavProp $r 'ExpirationDateOption' '') }
                if ($rt) { ConvertTo-PavFriendlyRetentionType $rt } else { '' })
            RetentionTypeRaw  = $(
                $rt = [string](Get-PavProp $r 'RetentionType' '')
                if (-not $rt) { $rt = [string](Get-PavProp $r 'ExpirationDateOption' '') }
                $rt)
            ExpirationDateOption = Get-PavProp $r 'ExpirationDateOption'
            ContentMatchQuery = [string](Get-PavProp $r 'ContentMatchQuery' '')
            PublishComplianceTag = if ($publish -match ',(.+)$') { $Matches[1].Trim() } else { $publish }
            ApplyComplianceTag   = "$(Get-PavProp $r 'ApplyComplianceTag' '')"
            TagPropertyName      = if ($tagProp -match ',(.+)$') { $Matches[1].Trim() } else { $tagProp }
            SensitiveInfoTypes   = Get-PavDlmSitText (Get-PavProp $r 'ContentContainsSensitiveInformation')
            Workload    = [string](Get-PavProp $r 'Workload' '')
            Guid        = [string](Get-PavProp $r 'Guid' '')
        }
    }

    # Etiquetas (port de Build-TagSummaryRow) + file plan + etapas de revisión
    $tags = [System.Collections.Generic.List[object]]::new()
    $filePlans = [System.Collections.Generic.List[object]]::new()
    $reviewStages = [System.Collections.Generic.List[object]]::new()
    $ixT = 0
    foreach ($t in $rawTags) {
        $ixT++
        Write-PavLog -Level Info -Message "  > Etiqueta $ixT/$($rawTags.Count): $(Get-PavProp $t 'Name' '(sin nombre)')"
        $polGuid = "$(Get-PavProp $t 'Policy' '')"
        $fpRaw   = "$(Get-PavProp $t 'FilePlanMetadata' '')"
        $revRaw  = "$(Get-PavProp $t 'MultiStageReviewerMetadata' '')"
        $category = if ([bool](Get-PavProp $t 'Regulatory' $false)) { 'Regulatory Record' }
                    elseif ([bool](Get-PavProp $t 'IsRecordLabel' $false)) { 'Record Label' }
                    else { 'Standard Label' }
        $ambito = Get-PavLabelScope $t
        $tags.Add([pscustomobject]@{
            PSTypeName    = 'PurviewAssessment.DlmTag'
            Scope         = $ambito.Scope
            ScopeReason   = $ambito.Reasons
            Name          = [string](Get-PavProp $t 'Name' '')
            LabelCategory = $category
            RetentionAction   = ConvertTo-PavFriendlyAction ([string](Get-PavProp $t 'RetentionAction' ''))
            RetentionDuration = ConvertTo-PavFriendlyDuration (Get-PavProp $t 'RetentionDuration')
            RetentionType     = ConvertTo-PavFriendlyRetentionType ([string](Get-PavProp $t 'RetentionType' ''))
            HasRetentionAction = Get-PavProp $t 'HasRetentionAction'
            IsRecordLabel = Get-PavProp $t 'IsRecordLabel'
            Regulatory    = Get-PavProp $t 'Regulatory'
            IsReviewTag   = Get-PavProp $t 'IsReviewTag'
            HasFilePlan   = (-not [string]::IsNullOrWhiteSpace($fpRaw))
            HasReviewStages = (-not [string]::IsNullOrWhiteSpace($revRaw))
            ReviewerEmail = (@(Get-PavProp $t 'ReviewerEmail' @()) | ForEach-Object { "$_" }) -join '; '
            EventTypeId   = "$(Get-PavProp $t 'EventTypeId' '')"
            Notes         = [string](Get-PavProp $t 'Notes' '')
            Workload      = [string](Get-PavProp $t 'Workload' '')
            PolicyName    = if ($guidMap.ContainsKey($polGuid)) { $guidMap[$polGuid] } else { $polGuid }
            CreatedBy     = [string](Get-PavProp $t 'CreatedBy' '')
            Guid          = [string](Get-PavProp $t 'Guid' '')
        })
        if ($fpRaw) {
            $fp = ConvertFrom-PavJson $fpRaw
            if ($fp) {
                $dict = @{}
                foreach ($s in @(Get-PavProp $fp 'Settings' @())) { $dict[[string](Get-PavProp $s 'Key' '')] = Get-PavProp $s 'Value' }
                $filePlans.Add([pscustomobject]@{
                    LabelName   = [string](Get-PavProp $t 'Name' '')
                    Department  = $dict['FilePlanPropertyDepartment']
                    Category    = $dict['FilePlanPropertyCategory']
                    Subcategory = $dict['FilePlanPropertySubcategory']
                    Authority   = $dict['FilePlanPropertyAuthority']
                    Citation    = $dict['FilePlanPropertyCitation']
                })
            }
        }
        if ($revRaw) {
            $meta = ConvertFrom-PavJson $revRaw
            foreach ($stage in @(Get-PavProp $meta 'MultiStageReviewSettings' @())) {
                $reviewStages.Add([pscustomobject]@{
                    LabelName = [string](Get-PavProp $t 'Name' '')
                    StageId   = Get-PavProp $stage 'StageId'
                    StageName = Get-PavProp $stage 'StageName'
                    Reviewers = (@(Get-PavProp $stage 'Reviewers' @()) -join ' | ')
                })
            }
        }
    }

    # ── Separación de ámbitos ────────────────────────────────────────────────
    # Get-ComplianceTag y Get-RetentionCompliancePolicy devuelven tanto los
    # objetos de ciclo de vida como los de gestión de registros. Se clasifica
    # por criterio estructural (nunca por nomenclatura): las etiquetas del
    # ámbito de registros y las directivas que las publican se excluyen de
    # este informe y se contabilizan aparte.
    $tagsCiclo   = @(@($tags) | Where-Object { $_.Scope -ne 'Gestión de registros' })
    $tagsRegistro = @(@($tags) | Where-Object { $_.Scope -eq 'Gestión de registros' })

    # Directivas que publican alguna etiqueta del ámbito de registros
    $polRegistro = @()
    if ($tagsRegistro.Count -gt 0) {
        $refsRegistro = @($tagsRegistro | ForEach-Object { "$($_.PolicyName)" } | Where-Object { $_ } | Sort-Object -Unique)
        $nombresRegistro = @($tagsRegistro | ForEach-Object { "$($_.Name)" })
        foreach ($pol in @($policies)) {
            $esRm = $false
            if ($refsRegistro -contains "$($pol.Name)") { $esRm = $true }
            else {
                # La regla declara qué etiqueta publica la directiva
                foreach ($r in @($rules | Where-Object { "$($_.PolicyName)" -eq "$($pol.Name)" })) {
                    if ($nombresRegistro -contains "$($r.PublishComplianceTag)" -or $nombresRegistro -contains "$($r.ApplyComplianceTag)") { $esRm = $true; break }
                }
            }
            if ($esRm) { $polRegistro += "$($pol.Name)" }
        }
    }
    $policiesCiclo = @(@($policies) | Where-Object { $polRegistro -notcontains "$($_.Name)" })
    $rulesCiclo    = @(@($rules)    | Where-Object { $polRegistro -notcontains "$($_.PolicyName)" })
    $locsCiclo     = @(@($locations) | Where-Object { $polRegistro -notcontains "$($_.PolicyName)" })

    if ($tagsRegistro.Count -gt 0 -or $polRegistro.Count -gt 0) {
        Write-PavLog -Level Info -Message "  > Excluidos del ámbito de ciclo de vida: $($tagsRegistro.Count) etiqueta(s) y $($polRegistro.Count) directiva(s) de gestión de registros."
    }

    [pscustomobject]@{
        PSTypeName      = 'PurviewAssessment.DlmData'
        Policies        = $policiesCiclo
        PolicyLocations = $locsCiclo
        Rules           = $rulesCiclo
        Tags            = $tagsCiclo
        RecordsScopeTags     = $tagsRegistro
        RecordsScopePolicies = @($polRegistro)
        FilePlans       = @($filePlans)
        ReviewStages    = @($reviewStages)
        CollectedAt     = Get-Date
    }
}
