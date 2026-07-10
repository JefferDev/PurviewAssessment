function Get-PurviewSitData {
<#
.SYNOPSIS
    Obtiene los SITs personalizados del RulePackage de Purview: en línea
    (exporta y parsea automáticamente, eliminando el paso manual del XML)
    u offline desde un XML ya exportado.
.PARAMETER Online
    Exporta el RulePackage 'Microsoft Rule Package' del tenant
    (Get-DlpSensitiveInformationTypeRulePackage), lo escribe formateado y
    lo parsea. Requiere sesión activa.
.PARAMETER XmlPath
    Modo offline: parsea un XML ya exportado. No requiere sesión ni EXO.
.PARAMETER SaveXmlTo
    (Solo -Online) Carpeta donde conservar el XML exportado. Si se omite,
    se usa un archivo temporal que se elimina al terminar.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.SitData' con RulePack,
    Entities, RegexMap, KeywordMap, FilterMap, SourceXmlPath, CollectedAt.
.EXAMPLE
    Get-PurviewSitData -Online -SaveXmlTo C:\Reports
.EXAMPLE
    Get-PurviewSitData -XmlPath C:\exports\rulepack.xml
#>
    [CmdletBinding(DefaultParameterSetName = 'Online')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'Online')]
        [switch]$Online,

        [Parameter(Mandatory, ParameterSetName = 'Offline')]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$XmlPath,

        [Parameter(ParameterSetName = 'Online')]
        [string]$SaveXmlTo
    )

    $tempXml = $null
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Online') {
            Assert-PavConnection
            Write-PavLog -Level Step -Message 'Exportando RulePackage de SITs personalizados...'
            $rulepack = Invoke-PavRetry -OperationName 'Get-DlpSensitiveInformationTypeRulePackage' -ScriptBlock {
                Get-DlpSensitiveInformationTypeRulePackage -Identity 'Microsoft Rule Package' -ErrorAction Stop
            }
            $bytes = Get-PavProp $rulepack 'SerializedClassificationRuleCollection'
            if ($null -eq $bytes) { throw 'El RulePackage no contiene SerializedClassificationRuleCollection (¿sin SITs personalizados en el tenant?).' }

            if ($SaveXmlTo) {
                if (-not (Test-Path $SaveXmlTo)) { New-Item -ItemType Directory -Path $SaveXmlTo -Force | Out-Null }
                $XmlPath = Join-Path $SaveXmlTo ("RulePackage_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.xml')
            }
            else {
                $tempXml = Join-Path ([IO.Path]::GetTempPath()) ("PavRulePack_$(Get-Random).xml")
                $XmlPath = $tempXml
            }
            [System.IO.File]::WriteAllBytes($XmlPath, [byte[]]$bytes)
            # Formatear/normalizar: el export sale sin formato; [xml] lo valida
            Write-PavLog -Level Info -Message "RulePackage exportado: $XmlPath"
        }

        $parsed = ConvertFrom-PavRulePackage -XmlPath $XmlPath

        [pscustomobject]@{
            PSTypeName    = 'PurviewAssessment.SitData'
            RulePack      = $parsed.RulePack
            Entities      = $parsed.Entities
            RegexMap      = $parsed.RegexMap
            KeywordMap    = $parsed.KeywordMap
            FilterMap     = $parsed.FilterMap
            SourceXmlPath = if ($tempXml) { '' } else { $XmlPath }
            CollectedAt   = Get-Date
        }
    }
    finally {
        if ($tempXml -and (Test-Path $tempXml)) { Remove-Item $tempXml -Force -ErrorAction SilentlyContinue }
    }
}
