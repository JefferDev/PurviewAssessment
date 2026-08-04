# Helpers de etiquetado automático (Auto-labeling) — parseo de
# Get-AutoSensitivityLabelPolicy / Get-AutoSensitivityLabelRule.
# Las propiedades se tomaron de la salida real de un tenant (PhalanxSec).

function ConvertFrom-PavAutoLabelPolicy {
<#
.SYNOPSIS
    Normaliza una directiva de etiquetado automático a objeto de datos.
.DESCRIPTION
    Resuelve ubicaciones, ámbitos adaptativos, usuarios con ámbito y las
    métricas de simulación (modo de prueba), que son el dato operativo
    más relevante en estas directivas.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.AutoLabelPolicy'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory, Position = 0)][object]$Policy)

    # Ubicaciones: mismas variantes REST que DLP
    $locMap = [ordered]@{
        ExchangeLocation    = 'ExchangeLocation'
        SharePointLocation  = 'SharePointLocation'
        OneDriveLocation    = 'OneDriveLocation'
        PowerBILocation     = 'PowerBILocation'
        EndpointDlpLocation = 'EndpointDlpLocation'
    }
    $obj = [ordered]@{
        PSTypeName = 'PurviewAssessment.AutoLabelPolicy'
        Name       = [string](Get-PavProp $Policy 'Name' '')
        Guid       = [string](Get-PavProp $Policy 'Guid' '')
        Type       = [string](Get-PavProp $Policy 'Type' 'AutoLabeling')
        Enabled    = Get-PavProp $Policy 'Enabled' $false
        Mode       = [string](Get-PavProp $Policy 'Mode' '')
        ModeFriendly = ConvertTo-PavAutoLabelMode ([string](Get-PavProp $Policy 'Mode' ''))
        Priority   = Get-PavProp $Policy 'Priority'
        Comment    = [string](Get-PavProp $Policy 'Comment' '')
        Workload   = [string](Get-PavProp $Policy 'Workload' '')

        # Etiqueta que aplica la directiva y su comportamiento
        LabelDisplayName      = [string](Get-PavProp $Policy 'LabelDisplayName' '')
        ApplySensitivityLabel = [string](Get-PavProp $Policy 'ApplySensitivityLabel' '')
        OverwriteLabel        = Get-PavProp $Policy 'OverwriteLabel' $false
        RemoveLabel           = Get-PavProp $Policy 'RemoveLabel' $false
        OverwriteWorkloads    = [string](Get-PavProp $Policy 'ApplySensitivityLabelOverwriteWorkloads' '')
        AutoEnableAfter       = Get-PavProp $Policy 'AutoEnableAfter'
        DefaultSpoDocLibrary  = Get-PavProp $Policy 'isDefaultSPODocLibraryLabelInUse' $false
    }
    foreach ($k in $locMap.Keys) {
        $obj[$k] = Resolve-PavDlpLocation -PropName $locMap[$k] -PolicyObj $Policy
        $obj["${k}Exception"] = Resolve-PavDlpLocation -PropName "$($locMap[$k])Exception" -PolicyObj $Policy
    }

    # Ámbitos adaptativos (característica propia de auto-labeling)
    $adaptive = @()
    foreach ($scope in 'Exchange', 'SharePoint', 'OneDrive', 'Teams', 'EndpointDlp') {
        $vals = @(@(Get-PavProp $Policy "${scope}AdaptiveScopes" @()) | Where-Object { $_ } | ForEach-Object { "$_" })
        if ($vals.Count -gt 0) { $adaptive += "${scope}: $($vals -join ', ')" }
    }
    $obj['AdaptiveScopes'] = ($adaptive -join ' | ')

    # Usuarios con ámbito
    $obj['ExchangeSender']          = Resolve-PavScopedUsers (Get-PavProp $Policy 'ExchangeSender')
    $obj['ExchangeSenderException'] = Resolve-PavScopedUsers (Get-PavProp $Policy 'ExchangeSenderException')
    $obj['UsersIncluded']           = Resolve-PavScopedUsers (Get-PavProp $Policy 'ExchangeSenderMemberOf')
    $obj['UsersExcluded']           = Resolve-PavScopedUsers (Get-PavProp $Policy 'ExchangeSenderMemberOfException')
    $obj['OneDriveSharedBy']        = Resolve-PavScopedUsers (Get-PavProp $Policy 'OneDriveSharedBy')
    $obj['OneDriveSharedByMemberOf'] = Resolve-PavScopedUsers (Get-PavProp $Policy 'OneDriveSharedByMemberOf')

    # Simulación / modo de prueba: el indicador operativo clave
    $obj['SimulationItemsMatched']   = Get-PavProp $Policy 'ItemsMatchedDuringTestMode' 0
    $obj['SimulationPending']        = Get-PavProp $Policy 'PendingItemsCount' 0
    $obj['SimulationCompleted']      = Get-PavProp $Policy 'CompletedItemsCount' 0
    $obj['SimulationFailed']         = Get-PavProp $Policy 'FailedItemsCount' 0
    $obj['SimulationLastCompletion'] = Get-PavProp $Policy 'LastSimulationCompletionDate'
    $obj['TestModeStatus']           = [string](Get-PavProp $Policy 'TestModeStatus' '')
    $obj['TestModeVerdict']          = [string](Get-PavProp $Policy 'TestModeVerdict' '')

    # Distribución y auditoría
    $obj['DistributionStatus']     = [string](Get-PavProp $Policy 'DistributionStatus' '')
    $obj['DistributionSyncStatus'] = [string](Get-PavProp $Policy 'DistributionSyncStatus' '')
    $obj['ExpectedLocations']      = Get-PavProp $Policy 'ExpectedLocations' 0
    $obj['CompletedLocations']     = Get-PavProp $Policy 'CompletedLocations' 0
    $obj['FailedLocations']        = Get-PavProp $Policy 'FailedLocations' 0
    $obj['IsValid']                = Get-PavProp $Policy 'IsValid' $true
    $obj['CreatedBy']              = [string](Get-PavProp $Policy 'CreatedBy' '')
    $obj['LastModifiedBy']         = [string](Get-PavProp $Policy 'LastModifiedBy' '')
    $obj['CreatedUtc']             = Get-PavProp $Policy 'CreationTimeUtc' (Get-PavProp $Policy 'WhenCreatedUTC')
    $obj['LastModifiedUtc']        = Get-PavProp $Policy 'ModificationTimeUtc' (Get-PavProp $Policy 'WhenChangedUTC')

    [pscustomobject]$obj
}

function ConvertTo-PavAutoLabelMode {
<#
.SYNOPSIS
    Modo de una directiva de etiquetado automático a texto legible.
    Estas directivas nacen en simulación: distinguirlo es crítico para el
    assessment (una directiva en simulación NO etiqueta contenido).
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][string]$Mode)
    switch ($Mode) {
        'Enable'                   { 'Activa (etiqueta contenido)' }
        'Enforce'                  { 'Activa (etiqueta contenido)' }
        'TestWithoutNotifications' { 'Simulación (no etiqueta)' }
        'TestWithNotifications'    { 'Simulación con notificaciones (no etiqueta)' }
        'Disable'                  { 'Deshabilitada' }
        ''                         { 'No definido' }
        default                    { $Mode }
    }
}

function ConvertFrom-PavAutoLabelRule {
<#
.SYNOPSIS
    Normaliza una regla de etiquetado automático a objeto de datos.
.DESCRIPTION
    Reutiliza los parsers de DLP: el AdvancedRule de estas reglas tiene la
    misma gramática (árbol And/Or/Not con ContentContainsSensitiveInformation
    y AccessScope), y las condiciones clásicas usan los mismos formatos REST.
.PARAMETER Rule
    Objeto crudo de Get-AutoSensitivityLabelRule.
.PARAMETER PolicyNameByGuid
    Hashtable GUID de directiva → nombre, para resolver la propiedad Policy.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.AutoLabelRule'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)][object]$Rule,
        [Parameter(Position = 1)][hashtable]$PolicyNameByGuid = @{}
    )

    $advRaw  = Get-PavProp $Rule 'AdvancedRule'
    $advJson = if ($advRaw -is [string]) { $advRaw } elseif ($null -ne $advRaw) { $advRaw | ConvertTo-Json -Depth 20 } else { '' }
    $isAdv   = [bool](Get-PavProp $Rule 'IsAdvancedRule' $false) -or -not [string]::IsNullOrWhiteSpace($advJson)
    $adv     = ConvertFrom-PavAdvancedRule $advJson

    # Reglas clásicas: SITs desde ContentContainsSensitiveInformation
    $sits = $adv.SensitiveInfoTypes
    $lbls = $adv.SensitivityLabels
    if (-not $isAdv -or -not $sits) {
        $resolved = Resolve-PavSitValue (Get-PavProp $Rule 'ContentContainsSensitiveInformation')
        if ($resolved.SITs)   { $sits = $resolved.SITs }
        if ($resolved.Labels) { $lbls = $resolved.Labels }
    }
    $exc = Resolve-PavSitValue (Get-PavProp $Rule 'ExceptIfContentContainsSensitiveInformation')

    $polGuid = "$(Get-PavProp $Rule 'Policy' '')"
    $polName = [string](Get-PavProp $Rule 'ParentPolicyName' '')
    if (-not $polName -and $PolicyNameByGuid.ContainsKey($polGuid)) { $polName = $PolicyNameByGuid[$polGuid] }

    $obj = [ordered]@{
        PSTypeName  = 'PurviewAssessment.AutoLabelRule'
        PolicyName  = $polName
        RuleName    = [string](Get-PavProp $Rule 'Name' '')
        DisplayName = [string](Get-PavProp $Rule 'DisplayName' '')
        RuleGuid    = [string](Get-PavProp $Rule 'Guid' '')
        Disabled    = if ([bool](Get-PavProp $Rule 'Disabled' $false)) { 'Sí' } else { 'No' }
        Mode        = [string](Get-PavProp $Rule 'Mode' '')
        Priority    = Get-PavProp $Rule 'Priority'
        Workload        = [string](Get-PavProp $Rule 'Workload' '')
        LogicalWorkload = [string](Get-PavProp $Rule 'LogicalWorkload' '')
        StampLabelId    = [string](Get-PavProp $Rule 'StampLabelId' '')
        ReportSeverityLevel = [string](Get-PavProp $Rule 'ReportSeverityLevel' '')
        IsAdvancedRule     = if ($isAdv) { 'Sí' } else { 'No' }
        SensitiveInfoTypes = $sits
        SensitivityLabels  = $lbls
        AccessScopeAdv     = $adv.AccessScope
        ExceptIfSensitiveInfoTypes = $exc.SITs
        ConditionsTree     = $adv.ConditionsTree
        ConditionsHtml     = $adv.ConditionsHtml
        AdvancedRuleRaw    = $advJson
    }

    # Condiciones y excepciones clásicas presentes en estas reglas
    $plain = @(
        'AccessScope', 'FromScope', 'ContentIsNotLabeled', 'AttachmentIsNotLabeled', 'MessageIsNotLabeled'
        'ContentMissingSensitivityLabel', 'HasLabelDowngradedFrom', 'MessageLabelChangeDetected'
        'SenderDomainIs', 'RecipientDomainIs', 'From', 'SentTo', 'SharedWithDomain', 'SenderIPRanges'
        'ContentExtensionMatchesWords', 'ContentFileTypeMatches', 'DocumentNameMatchesWords'
        'SubjectMatchesPatterns', 'HeaderMatchesPatterns', 'FromAddressContainsWords'
        'AnyOfRecipientAddressContainsWords', 'ContentPropertyContainsWords', 'UrlContainsText'
        'ContextPropertiesContainWords', 'DocumentSizeOver', 'DocumentCreatedBy', 'WithImportance'
        'DocumentIsPasswordProtected', 'DocumentIsUnsupported', 'HasSenderOverride', 'ContentIsShared'
        'ProcessingLimitExceeded', 'RestrictBrowserAccess', 'TeamsSharedWithParticipantCategory'
        'ExceptIfAccessScope', 'ExceptIfFromScope', 'ExceptIfSenderDomainIs', 'ExceptIfRecipientDomainIs'
        'ExceptIfFrom', 'ExceptIfSentTo', 'ExceptIfSharedWithDomain', 'ExceptIfDocumentNameMatchesWords'
        'ExceptIfContentExtensionMatchesWords', 'ExceptIfUrlContainsText', 'ExceptIfContentIsShared'
        'ActivationDate', 'ExpiryDate', 'Comment'
    )
    $scoped = @('FromMemberOf', 'SentToMemberOf', 'DocumentCreatedByMemberOf',
                'ExceptIfFromMemberOf', 'ExceptIfSentToMemberOf', 'ExceptIfDocumentCreatedByMemberOf')

    foreach ($p in $scoped) { $obj[$p] = Resolve-PavScopedUsers (Get-PavProp $Rule $p) }
    foreach ($p in $plain) {
        $v = ConvertFrom-PavJsonValue (Get-PavProp $Rule $p)
        $obj[$p] = if ($null -eq $v) { '' }
                   elseif ($v -is [bool]) { if ($v) { 'Sí' } else { 'No' } }
                   elseif ($v -is [string]) { if ($v.Trim() -in @('{}', '[]')) { '' } else { $v } }
                   elseif ($v -is [System.Collections.IEnumerable]) {
                       (@(@($v) | ForEach-Object {
                           if ($_ -is [string] -or $_ -is [ValueType]) { "$_" }
                           else { "$(Get-PavProp $_ 'Name' (Get-PavProp $_ 'DisplayName' "$_"))" }
                       } | Where-Object { $_ }) -join '; ')
                   }
                   else { "$v" }
    }
    $obj['CreatedBy']       = [string](Get-PavProp $Rule 'CreatedBy' '')
    $obj['LastModifiedBy']  = [string](Get-PavProp $Rule 'LastModifiedBy' '')
    $obj['CreatedUtc']      = Get-PavProp $Rule 'WhenCreatedUTC'
    $obj['LastModifiedUtc'] = Get-PavProp $Rule 'WhenChangedUTC'

    [pscustomobject]$obj
}
