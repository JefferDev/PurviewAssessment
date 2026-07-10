function Get-PurviewLabelData {
<#
.SYNOPSIS
    Recolecta y parsea las etiquetas de sensibilidad y directivas de
    publicación de Microsoft Purview (solo lectura).
.DESCRIPTION
    Port del pipeline de Export-SensitivityLabelsReport_v3.ps1: parsea
    Settings ([clave, valor]), LabelActions (JSON: encrypt, header, footer,
    watermark, protectgroup, protectsites) y LocaleSettings, resuelve la
    etiqueta padre y las directivas donde cada etiqueta está publicada.
    Devuelve objetos de datos, sin HTML: la presentación corresponde a
    Export-PurviewLabelReport.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.LabelData' con
    Labels, Policies, CollectedAt.
.EXAMPLE
    $data = Get-PurviewLabelData
    $data.Labels | Where-Object HasEncryption
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Assert-PavConnection
    Write-PavLog -Level Step -Message 'Recolectando etiquetas de sensibilidad y directivas de publicación...'

    $rawLabels = @(Invoke-PavRetry -OperationName 'Get-Label' -ScriptBlock {
        try { Get-Label -IncludeDetailedLabelActions -ErrorAction Stop }
        catch { Get-Label -ErrorAction Stop }   # parámetro no disponible en todas las versiones
    })
    $rawPolicies = @(Invoke-PavRetry -OperationName 'Get-LabelPolicy' -ScriptBlock {
        Get-LabelPolicy -ErrorAction Stop
    })
    Write-PavLog -Level Info -Message "Etiquetas: $($rawLabels.Count) | Directivas: $($rawPolicies.Count)"

    # Acción deshabilitada si su setting 'disabled' es afirmativo
    $isActive = {
        param($actionSettings)
        if ($null -eq $actionSettings) { return $false }
        ((Get-PavSettingValue $actionSettings 'disabled' 'false').ToLowerInvariant() -notin @('true', 'si', 'sí', 'yes', '1'))
    }

    # ── Directivas (primero: se usan para PublishedInPolicies) ───────────────
    $ixP = 0
    $policies = foreach ($pol in $rawPolicies) {
        $ixP++
        Write-PavLog -Level Info -Message "  > Directiva $ixP/$($rawPolicies.Count): $(Get-PavProp $pol 'Name' '(sin nombre)')"
        $pSettings = ConvertFrom-PavKeyValueSettings (Get-PavProp $pol 'Settings')
        [pscustomobject]@{
            PSTypeName    = 'PurviewAssessment.LabelPolicy'
            Name          = [string](Get-PavProp $pol 'Name' '')
            Guid          = [string](Get-PavProp $pol 'Guid' '')
            Type          = [string](Get-PavProp $pol 'Type' '')
            Enabled       = [bool](Get-PavProp $pol 'Enabled' $true)
            Mode          = [string](Get-PavProp $pol 'Mode' '')
            Priority      = Get-PavProp $pol 'Priority'
            Workload      = [string](Get-PavProp $pol 'Workload' '')
            ScopedLabels  = @(Get-PavProp $pol 'ScopedLabels' @())
            LabelsCount   = @(Get-PavProp $pol 'ScopedLabels' @()).Count
            Mandatory     = Get-PavSettingValue $pSettings 'mandatory'
            DefaultLabelId = Get-PavSettingValue $pSettings 'defaultlabelid' ''
            OutlookDefaultLabelId = Get-PavSettingValue $pSettings 'outlookdefaultlabelid' ''
            AttachmentAction      = Get-PavSettingValue $pSettings 'attachmentaction' ''
            DistributionStatus    = [string](Get-PavProp $pol 'DistributionStatus' '')
            CreatedBy             = [string](Get-PavProp $pol 'CreatedBy' '')
            RequireDowngradeJustification = Get-PavSettingValue $pSettings 'requiredowngradejustification'
            ExchangeLocation    = @(Get-PavProp $pol 'ExchangeLocation' @()) -join ', '
            SharePointLocation  = @(Get-PavProp $pol 'SharePointLocation' @()) -join ', '
            OneDriveLocation    = @(Get-PavProp $pol 'OneDriveLocation' @()) -join ', '
            ModernGroupLocation = @(Get-PavProp $pol 'ModernGroupLocation' @()) -join ', '
            WhenCreatedUTC = Get-PavProp $pol 'WhenCreatedUTC'
            WhenChangedUTC = Get-PavProp $pol 'WhenChangedUTC'
            SettingsRaw   = if ($pSettings.Count) { ($pSettings.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ' } else { 'No configurado' }
        }
    }

    # ── Etiquetas ─────────────────────────────────────────────────────────────
    $ixL = 0
    $labels = foreach ($label in $rawLabels) {
        $ixL++
        Write-PavLog -Level Info -Message "  > Etiqueta $ixL/$($rawLabels.Count): $(Get-PavProp $label 'DisplayName' (Get-PavProp $label 'Name' '(sin nombre)'))"
        $settings = ConvertFrom-PavKeyValueSettings (Get-PavProp $label 'Settings')
        $actions  = ConvertFrom-PavLabelActions   (Get-PavProp $label 'LabelActions')
        $locales  = ConvertFrom-PavLocaleSettings (Get-PavProp $label 'LocaleSettings')

        $guid = [string](Get-PavProp $label 'Guid' '')
        $name = [string](Get-PavProp $label 'Name' '')

        # Etiqueta padre (ParentId directo o settings.parentid)
        $parentDisplay = '-- (Etiqueta principal)'
        $parentId = [string](Get-PavProp $label 'ParentId' '')
        if (-not $parentId) {
            $v = Get-PavSettingValue $settings 'parentid' ''
            if ($v -and $v -ne 'No configurado') { $parentId = $v }
        }
        if ($parentId) {
            $parentObj = $rawLabels | Where-Object {
                "$(Get-PavProp $_ 'Guid')" -eq $parentId -or "$(Get-PavProp $_ 'ImmutableId')" -eq $parentId
            } | Select-Object -First 1
            $parentDisplay = if ($parentObj) { [string]$parentObj.DisplayName } else { $parentId }
        }

        # Locales: displayName/tooltip por idioma + default
        $localeStrings = [System.Collections.Generic.List[string]]::new()
        $localeDisplayName = ''; $localeTooltip = ''
        foreach ($lk in $locales.Keys) {
            foreach ($lang in $locales[$lk].Keys) { $localeStrings.Add("$lk [$lang]: $($locales[$lk][$lang])") }
            if ($lk -eq 'displayName' -and $locales[$lk].ContainsKey('default')) { $localeDisplayName = [string]$locales[$lk]['default'] }
            if ($lk -eq 'tooltip'     -and $locales[$lk].ContainsKey('default')) { $localeTooltip     = [string]$locales[$lk]['default'] }
        }

        $hasHeader    = & $isActive $actions['header']
        $hasFooter    = & $isActive $actions['footer']
        $hasWatermark = & $isActive $actions['watermark']

        [pscustomobject]@{
            PSTypeName   = 'PurviewAssessment.Label'
            Priority     = Get-PavProp $label 'Priority'
            Name         = $name
            DisplayName  = [string](Get-PavProp $label 'DisplayName' $name)
            Guid         = $guid
            ImmutableId  = [string](Get-PavProp $label 'ImmutableId' '')
            ParentId     = $parentId
            ParentDisplay = $parentDisplay
            IsParent     = [bool](Get-PavProp $label 'IsParent' $false)
            Comment      = [string](Get-PavProp $label 'Comment' '')
            Color        = Get-PavSettingValue $settings 'color' 'Sin color'
            ContentType  = Get-PavSettingValue $settings 'contenttype'
            Tooltip      = if ($localeTooltip) { $localeTooltip } else { [string](Get-PavProp $label 'Tooltip' '') }
            Workload     = [string](Get-PavProp $label 'Workload' '')
            Mode         = [string](Get-PavProp $label 'Mode' '')
            Enabled      = Get-PavProp $label 'Enabled' ''
            HasEncryption     = & $isActive $actions['encrypt']
            HasHeader         = $hasHeader
            HasFooter         = $hasFooter
            HasWatermark      = $hasWatermark
            HasContentMarking = ($hasHeader -or $hasFooter -or $hasWatermark)
            HasProtectGroup   = & $isActive $actions['protectgroup']
            HasProtectSites   = & $isActive $actions['protectsites']
            LocaleDisplayName = $localeDisplayName
            LocaleAll    = if ($localeStrings.Count) { $localeStrings -join ' | ' } else { 'No configurado' }
            SettingsRaw  = if ($settings.Count) { ($settings.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ' } else { 'No configurado' }
            ActionsRaw   = if ($actions.Count) { (($actions.GetEnumerator() | ForEach-Object {
                                "$($_.Key) [$( ($_.Value.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ' )]"
                            }) -join ' | ') } else { 'No configurado' }
            WhenCreatedUTC = Get-PavProp $label 'WhenCreatedUTC'
            WhenChangedUTC = Get-PavProp $label 'WhenChangedUTC'
            CreatedBy      = [string](Get-PavProp $label 'CreatedBy' '')
            PublishedInPolicies = (@($policies | Where-Object { $_.ScopedLabels -contains $name -or $_.ScopedLabels -contains $guid } | ForEach-Object { $_.Name }) -join ', ')
        }
    }

    [pscustomobject]@{
        PSTypeName  = 'PurviewAssessment.LabelData'
        Labels      = @($labels)
        Policies    = @($policies)
        CollectedAt = Get-Date
    }
}
