function Get-PurviewDlpData {
<#
.SYNOPSIS
    Recolecta y parsea directivas y reglas DLP de Microsoft Purview
    (solo lectura).
.DESCRIPTION
    Port del pipeline de Export-DLPPolicies.ps1:
      - Directivas con todas las ubicaciones resueltas a texto legible
        (Resolve-PavDlpLocation sobre los formatos REST).
      - Reglas con: parseo completo de AdvancedRule (árbol And/Or/Not,
        SITs, Labels, AccessScope), resolución de
        ContentContainsSensitiveInformation en reglas clásicas, y
        extracción normalizada de condiciones/excepciones/acciones
        (listas curadas de propiedades procesadas por un único pipeline:
        JSON REST → usuarios con ámbito → unión legible).
.PARAMETER IncludeDisabled
    Incluye directivas y reglas deshabilitadas.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.DlpData' con
    Policies, Rules, CollectedAt.
.EXAMPLE
    $dlp = Get-PurviewDlpData -IncludeDisabled
    $dlp.Rules | Where-Object IsAdvancedRule -eq 'Sí'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([switch]$IncludeDisabled)

    Assert-PavConnection
    Write-PavLog -Level Step -Message 'Recolectando directivas y reglas DLP...'

    Write-PavLog -Level Info -Message 'Consultando Get-DlpCompliancePolicy (única llamada global a la API)...'
    $rawPolicies = @(Invoke-PavRetry -OperationName 'Get-DlpCompliancePolicy' -ScriptBlock {
        Get-DlpCompliancePolicy -ErrorAction Stop
    })
    # Directivas en eliminación pendiente se excluyen siempre (patrón del script original)
    $rawPolicies = @($rawPolicies | Where-Object { "$(Get-PavProp $_ 'Mode' '')" -ne 'PendingDeletion' })
    if (-not $IncludeDisabled) {
        $rawPolicies = @($rawPolicies | Where-Object { [bool](Get-PavProp $_ 'Enabled' $true) })
    }
    Write-PavLog -Level Success -Message "Directivas: $($rawPolicies.Count)"

    # CRÍTICO (rendimiento en tenants grandes): las reglas se consultan POR
    # DIRECTIVA, nunca con una llamada global — Get-DlpComplianceRule sin
    # filtro puede exceder el timeout REST con AdvancedRules voluminosos.
    # Un fallo en una directiva se registra y NO detiene la recolección.
    $rawRules = [System.Collections.Generic.List[object]]::new()
    $rulesFailed = 0
    $ixQ = 0
    foreach ($pol in $rawPolicies) {
        $ixQ++
        $pn  = [string](Get-PavProp $pol 'Name' "#$ixQ")
        $pct = if ($rawPolicies.Count) { [math]::Round($ixQ / $rawPolicies.Count * 100) } else { 0 }
        Write-Progress -Activity 'Recolectando reglas DLP' -Status "[$ixQ/$($rawPolicies.Count)] $pn" -PercentComplete $pct
        Write-PavLog -Level Info -Message "  > [$ixQ/$($rawPolicies.Count)] Reglas de la directiva: $pn"
        try {
            $polRules = @(Invoke-PavRetry -OperationName "Get-DlpComplianceRule '$pn'" -MaxAttempts 2 -ScriptBlock {
                Get-DlpComplianceRule -Policy $pn -ErrorAction Stop
            })
            foreach ($pr in $polRules) { if ($null -ne $pr) { $rawRules.Add($pr) } }
            Write-PavLog -Level Info -Message "      Reglas obtenidas: $(@($polRules | Where-Object { $null -ne $_ }).Count)"
        }
        catch {
            $rulesFailed++
            Write-PavLog -Level Warn -Message "      Reglas de '$pn' no recuperadas: $($_.Exception.Message)"
        }
    }
    Write-Progress -Activity 'Recolectando reglas DLP' -Completed
    $rawRules = @($rawRules)
    if (-not $IncludeDisabled) {
        $rawRules = @($rawRules | Where-Object { -not [bool](Get-PavProp $_ 'Disabled' $false) })
    }
    $failNote = if ($rulesFailed) { " | Directivas con reglas no recuperadas: $rulesFailed" } else { '' }
    Write-PavLog -Level Info -Message "Directivas: $($rawPolicies.Count) | Reglas: $($rawRules.Count)$failNote"

    # ── Directivas ────────────────────────────────────────────────────────────
    $locationProps = @(
        'ExchangeLocation', 'SharePointLocation', 'OneDriveLocation', 'TeamsLocation', 'TeamsChannelLocation'
        'EndpointDlpLocation', 'OnPremisesScannerDlpLocation', 'ThirdPartyAppDlpLocation', 'PowerBIDlpLocation'
        'ExchangeLocationException', 'SharePointLocationException', 'OneDriveLocationException', 'TeamsLocationException'
        'EndpointDlpLocationException'
    )
    $ixP = 0
    $policies = foreach ($pol in $rawPolicies) {
        $ixP++
        Write-PavLog -Level Info -Message "  > Directiva $ixP/$($rawPolicies.Count): $(Get-PavProp $pol 'Name' '(sin nombre)')"
        $obj = [ordered]@{
            PSTypeName = 'PurviewAssessment.DlpPolicy'
            Name       = [string](Get-PavProp $pol 'Name' '')
            Guid       = [string](Get-PavProp $pol 'Guid' '')
            Enabled    = [bool](Get-PavProp $pol 'Enabled' $true)
            Mode       = [string](Get-PavProp $pol 'Mode' '')
            Type       = [string](Get-PavProp $pol 'Type' '')
            Comment    = [string](Get-PavProp $pol 'Comment' '')
            Priority   = Get-PavProp $pol 'Priority'
            Workload   = [string](Get-PavProp $pol 'Workload' '')
            CreatedBy      = [string](Get-PavProp $pol 'CreatedBy' '')
            LastModifiedBy = [string](Get-PavProp $pol 'LastModifiedBy' '')
            WhenCreated    = Get-PavProp $pol 'WhenCreated'
            WhenChanged    = Get-PavProp $pol 'WhenChanged'
        }
        foreach ($lp in $locationProps) { $obj[$lp] = Resolve-PavDlpLocation -PropName $lp -PolicyObj $pol }
        # Usuarios con ámbito a nivel de directiva (columnas del export original)
        $obj['ExchangeSender']          = Resolve-PavScopedUsers (Get-PavProp $pol 'ExchangeSender')
        $obj['ExchangeSenderException'] = Resolve-PavScopedUsers (Get-PavProp $pol 'ExchangeSenderException')
        $obj['UsersIncluded']           = Resolve-PavScopedUsers (Get-PavProp $pol 'ExchangeSenderMemberOf')
        $obj['UsersExcluded']           = Resolve-PavScopedUsers (Get-PavProp $pol 'ExchangeSenderMemberOfException')
        [pscustomobject]$obj
    }

    # ── Reglas ────────────────────────────────────────────────────────────────
    # Condiciones/excepciones con posibles objetos JSON de usuarios con ámbito
    $scopedProps = @('FromMemberOf', 'SentToMemberOf', 'ExceptIfFromMemberOf', 'ExceptIfSentToMemberOf',
                     'DocumentCreatedByMemberOf', 'ExceptIfDocumentCreatedByMemberOf')
    # Condiciones/excepciones simples (strings/arrays) — lista curada del script original
    $plainProps = @(
        'SenderDomainIs', 'RecipientDomainIs', 'From', 'SentTo', 'SharedWithDomain'
        'SenderIPRanges', 'SenderAddressLocation', 'SenderType', 'FromScope', 'AccessScope'
        'ContentExtensionMatchesWords', 'ContentFileTypeMatches'
        'DocumentNameMatchesWords', 'DocumentNameMatchesPatterns'
        'DocumentContainsWords', 'DocumentMatchesPatterns'
        'SubjectContainsWords', 'SubjectMatchesPatterns'
        'SubjectOrBodyContainsWords', 'SubjectOrBodyMatchesPatterns'
        'HeaderContainsWords', 'HeaderMatchesPatterns'
        'FromAddressContainsWords', 'FromAddressMatchesPatterns'
        'AnyOfRecipientAddressContainsWords', 'AnyOfRecipientAddressMatchesPatterns'
        'ContentPropertyContainsWords', 'ContentCharacterSetContainsWords'
        'DocumentIsPasswordProtected', 'DocumentIsUnsupported'
        'ContentIsNotLabeled', 'AttachmentIsNotLabeled', 'MessageIsNotLabeled', 'ContentIsShared', 'HasSenderOverride', 'ProcessingLimitExceeded'
        'ActivationDate', 'ExpiryDate'
        'DocumentCreatedBy', 'DocumentSizeOver', 'MessageSizeOver', 'AttachmentCountOver'
        'MessageTypeMatches', 'WithImportance'
        'ExceptIfSenderDomainIs', 'ExceptIfRecipientDomainIs', 'ExceptIfFrom', 'ExceptIfSentTo'
        'ExceptIfSharedWithDomain', 'ExceptIfAccessScope', 'ExceptIfFromScope'
        'ExceptIfContentExtensionMatchesWords', 'ExceptIfDocumentIsPasswordProtected'
        'ExceptIfDocumentIsUnsupported', 'ExceptIfHasSenderOverride', 'ExceptIfProcessingLimitExceeded'
        'ExceptIfSenderIPRanges', 'ExceptIfSubjectContainsWords', 'ExceptIfSubjectMatchesPatterns'
        'ExceptIfHeaderContainsWords', 'ExceptIfHeaderMatchesPatterns'
        'ExceptIfMessageTypeMatches', 'ExceptIfWithImportance', 'ExceptIfContentIsShared'
    )
    # Acciones y notificaciones
    $actionProps = @(
        'BlockAccess', 'BlockAccessScope', 'RestrictBrowserAccess', 'Quarantine', 'Moderate'
        'RedirectMessageTo', 'RemoveRMSTemplate', 'ApplyRightsProtectionTemplate', 'EncryptRMSTemplate'
        'NotifyUser', 'NotifyUserType', 'NotifyAllowOverride', 'NotifyOverrideRequirements'
        'NotifyPolicyTipCustomText', 'NotifyPolicyTipDisplayOption', 'NotifyPolicyTipUrl'
        'NotifyEmailCustomText', 'NotifyEmailCustomSubject', 'NotifyEndpointUser'
        'GenerateAlert', 'GenerateIncidentReport', 'IncidentReportContent', 'ReportSeverityLevel'
        'StopPolicyProcessing', 'SetHeader', 'RemoveHeader', 'PrependSubject', 'AddRecipients'
        'AlertProperties', 'ApplyHtmlDisclaimer', 'TriggerPowerAutomateFlow', 'ApplyBrandingTemplate'
        'NotifyEmailCustomSenderDisplayName', 'NotifyEmailExchangeIncludeAttachment'
    )

    $normalize = {
        param($raw)
        if ($null -eq $raw) { return '' }
        $v = ConvertFrom-PavJsonValue $raw
        if ($v -is [bool]) { if ($v) { return 'Sí' } else { return 'No' } }
        if ($v -is [string]) { if ($v.Trim() -in @('{}', '[]')) { return '' } else { return $v } }
        if ($v -is [System.Collections.IEnumerable]) {
            $items = @(@($v) | ForEach-Object {
                if ($_ -is [string] -or $_ -is [ValueType]) { "$_" }
                else {
                    $n = Get-PavProp $_ 'Name' (Get-PavProp $_ 'DisplayName' (Get-PavProp $_ 'PrimarySmtpAddress' ''))
                    if ($n) { "$n" } else { "$_" }
                }
            } | Where-Object { $_ })
            return ($items -join '; ')
        }
        return "$v"
    }

    $ixR = 0
    $rules = foreach ($rule in $rawRules) {
        $ixR++
        Write-PavLog -Level Info -Message "  > Regla $ixR/$($rawRules.Count): $(Get-PavProp $rule 'Name' '(sin nombre)')"
        $advJsonRaw = Get-PavProp $rule 'AdvancedRule'
        $advJson    = if ($advJsonRaw -is [string]) { $advJsonRaw } elseif ($null -ne $advJsonRaw) { $advJsonRaw | ConvertTo-Json -Depth 20 } else { '' }
        $isAdvanced = -not [string]::IsNullOrWhiteSpace($advJson)
        if ($isAdvanced) { Write-PavLog -Level Info -Message "      [i] AdvancedRule detectado: SITs y condiciones extraídos del árbol JSON ($($advJson.Length) chars)" }
        $adv        = ConvertFrom-PavAdvancedRule $advJson

        # Reglas clásicas: SITs desde ContentContainsSensitiveInformation
        $sits = $adv.SensitiveInfoTypes; $lbls = $adv.SensitivityLabels
        if (-not $isAdvanced) {
            $resolved = Resolve-PavSitValue (Get-PavProp $rule 'ContentContainsSensitiveInformation')
            $sits = $resolved.SITs; $lbls = $resolved.Labels
        }
        $exceptResolved = Resolve-PavSitValue (Get-PavProp $rule 'ExceptIfContentContainsSensitiveInformation')

        $obj = [ordered]@{
            PSTypeName   = 'PurviewAssessment.DlpRule'
            PolicyName   = [string](Get-PavProp $rule 'ParentPolicyName' (Get-PavProp $rule 'Policy' ''))
            RuleName     = [string](Get-PavProp $rule 'Name' '')
            RuleGuid     = [string](Get-PavProp $rule 'Guid' '')
            Disabled     = if ([bool](Get-PavProp $rule 'Disabled' $false)) { 'Sí' } else { 'No' }
            Priority     = Get-PavProp $rule 'Priority'
            Comment      = [string](Get-PavProp $rule 'Comment' '')
            Workload     = [string](Get-PavProp $rule 'Workload' '')
            IsAdvancedRule     = if ($isAdvanced) { 'Sí' } else { 'No' }
            SensitiveInfoTypes = $sits
            SensitivityLabels  = $lbls
            AccessScopeAdv     = $adv.AccessScope
            ExceptIfSensitiveInfoTypes = $exceptResolved.SITs
            ConditionsTree     = $adv.ConditionsTree
            ConditionsHtml     = $adv.ConditionsHtml
            AdvancedRuleRaw    = $advJson
            RawMode            = [string](Get-PavProp $rule 'Mode' '')
            CreatedBy          = [string](Get-PavProp $rule 'CreatedBy' '')
            LastModifiedBy     = [string](Get-PavProp $rule 'LastModifiedBy' '')
            WhenCreated        = Get-PavProp $rule 'WhenCreated'
            WhenChanged        = Get-PavProp $rule 'WhenChanged'
        }
        foreach ($p in $scopedProps) { $obj[$p] = Resolve-PavScopedUsers (Get-PavProp $rule $p) }
        foreach ($p in $plainProps)  { $obj[$p] = & $normalize (Get-PavProp $rule $p) }
        foreach ($p in $actionProps) { $obj[$p] = & $normalize (Get-PavProp $rule $p) }
        [pscustomobject]$obj
    }

    [pscustomobject]@{
        PSTypeName  = 'PurviewAssessment.DlpData'
        Policies    = @($policies)
        Rules       = @($rules)
        CollectedAt = Get-Date
    }
}
