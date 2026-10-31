function Get-PurviewSitData {
<#
.SYNOPSIS
    Obtiene los SITs personalizados de TODOS los RulePackages del tenant:
    en línea (enumera, exporta y parsea automáticamente) u offline desde
    uno o varios XML ya exportados.
.DESCRIPTION
    Un tenant puede tener varios RulePackages: el de SITs creados desde el
    portal (Microsoft.SCCManaged.CustomRulePack), los cargados por
    PowerShell con New-DlpSensitiveInformationTypeRulePackage, el paquete
    integrado de Microsoft y el de huellas digitales de documento. Por
    defecto se procesan únicamente los PERSONALIZADOS: el paquete
    integrado ('Microsoft Rule Package', SITs predefinidos de Microsoft) y
    el de huellas digitales se excluyen salvo que se soliciten.
    Nota: dos paquetes pueden compartir RuleCollectionName, por lo que la
    identificación se realiza por Identity.
.PARAMETER Online
    Enumera los RulePackages del tenant
    (Get-DlpSensitiveInformationTypeRulePackage), exporta el XML de cada
    uno y lo parsea. Requiere sesión activa.
.PARAMETER XmlPath
    Modo offline: una o varias rutas de XML ya exportados. No requiere
    sesión ni ExchangeOnlineManagement.
.PARAMETER SaveXmlTo
    (Solo -Online) Carpeta donde conservar los XML exportados, uno por
    paquete, como evidencia. Si se omite se usan archivos temporales.
.PARAMETER Identity
    (Solo -Online) Limita la recolección a los paquetes indicados, por
    Identity o por RuleCollectionName.
.PARAMETER IncludeBuiltIn
    Incluye el paquete integrado de Microsoft (SITs predefinidos).
.PARAMETER IncludeFingerprint
    Incluye el paquete de huellas digitales de documento.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.SitData' con RulePacks
    (colección), Entities (cada una con RulePackName), RegexMap,
    KeywordMap, FilterMap, SourceXmlPaths, CollectedAt. Se conservan
    RulePack y SourceXmlPath en singular (primer paquete) por
    compatibilidad con versiones anteriores.
.EXAMPLE
    Get-PurviewSitData -Online -SaveXmlTo C:\Reports
.EXAMPLE
    Get-PurviewSitData -Online -Identity 'RulePack Maestro Ejemplo'
.EXAMPLE
    Get-PurviewSitData -XmlPath .\pack1.xml, .\pack2.xml
#>
    [CmdletBinding(DefaultParameterSetName = 'Online')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'Online')]
        [switch]$Online,

        [Parameter(Mandatory, ParameterSetName = 'Offline')]
        [ValidateScript({ foreach ($p in $_) { if (-not (Test-Path $p -PathType Leaf)) { throw "No existe el archivo: $p" } } $true })]
        [string[]]$XmlPath,

        [Parameter(ParameterSetName = 'Online')]
        [string]$SaveXmlTo,

        [Parameter(ParameterSetName = 'Online')]
        [string[]]$Identity,

        [Parameter(ParameterSetName = 'Online')]
        [switch]$IncludeBuiltIn,

        [Parameter(ParameterSetName = 'Online')]
        [switch]$IncludeFingerprint
    )

    $tempFiles  = [System.Collections.Generic.List[string]]::new()
    $xmlToParse = [System.Collections.Generic.List[object]]::new()

    try {
        if ($PSCmdlet.ParameterSetName -eq 'Online') {
            Assert-PavConnection
            Write-PavLog -Level Step -Message 'Enumerando RulePackages de SITs del tenant...'

            $allPacks = @(Invoke-PavRetry -OperationName 'Get-DlpSensitiveInformationTypeRulePackage' -ScriptBlock {
                Get-DlpSensitiveInformationTypeRulePackage -ErrorAction Stop
            })
            Write-PavLog -Level Info -Message "RulePackages encontrados: $($allPacks.Count)"

            $selected = foreach ($pk in $allPacks) {
                $collName  = [string](Get-PavProp $pk 'RuleCollectionName' (Get-PavProp $pk 'LocalizedName' ''))
                $ident     = [string](Get-PavProp $pk 'Identity' '')
                $publisher = [string](Get-PavProp $pk 'Publisher' '')
                $isFinger  = [bool](Get-PavProp $pk 'IsFingerprintRuleCollection' $false)
                $isBuiltIn = ($collName -eq 'Microsoft Rule Package') -or ($publisher -eq 'Microsoft Corporation')
                $size      = Get-PavProp $pk 'rulePackSize' 0

                if ($Identity) {
                    if (-not (@($Identity) | Where-Object { $ident -eq $_ -or $collName -eq $_ })) { continue }
                }
                else {
                    if ($isBuiltIn -and -not $IncludeBuiltIn) {
                        Write-PavLog -Level Info -Message "  - Omitido (paquete integrado de Microsoft, $size SITs): $collName"
                        continue
                    }
                    if ($isFinger -and -not $IncludeFingerprint) {
                        Write-PavLog -Level Info -Message "  - Omitido (huellas digitales de documento): $collName"
                        continue
                    }
                }
                if (-not [bool](Get-PavProp $pk 'IsExportable' $true)) {
                    Write-PavLog -Level Warn -Message "  - No exportable, se omite: $collName"
                    continue
                }
                [pscustomobject]@{
                    CollectionName = $collName;  Identity     = $ident
                    Publisher      = $publisher; Description  = [string](Get-PavProp $pk 'Description' '')
                    Version        = [string](Get-PavProp $pk 'Version' '')
                    IsBuiltIn      = $isBuiltIn; IsFingerprint = $isFinger
                    IsEncrypted    = [bool](Get-PavProp $pk 'IsEncrypted' $false)
                    DeclaredSize   = $size
                }
            }
            $selected = @($selected)
            if ($selected.Count -eq 0) {
                Write-PavLog -Level Warn -Message 'No se encontraron RulePackages personalizados (use -IncludeBuiltIn para incluir los SITs predefinidos de Microsoft).'
            }
            else {
                Write-PavLog -Level Success -Message "RulePackages a procesar: $($selected.Count)"
            }

            if ($SaveXmlTo -and -not (Test-Path $SaveXmlTo)) {
                New-Item -ItemType Directory -Path $SaveXmlTo -Force | Out-Null
            }
            $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
            $ix = 0
            foreach ($meta in $selected) {
                $ix++
                $label = if ($meta.CollectionName) { $meta.CollectionName } else { "#$ix" }
                Write-PavLog -Level Info -Message "  > [$ix/$($selected.Count)] Exportando: $label"
                try {
                    $key = if ($meta.Identity) { $meta.Identity } else { $meta.CollectionName }
                    $full = Invoke-PavRetry -OperationName "Get-DlpSensitiveInformationTypeRulePackage '$label'" -MaxAttempts 2 -ScriptBlock {
                        Get-DlpSensitiveInformationTypeRulePackage -Identity $key -ErrorAction Stop
                    }
                    $bytes = Get-PavProp $full 'SerializedClassificationRuleCollection'
                    if ($null -eq $bytes) {
                        Write-PavLog -Level Warn -Message "      Sin contenido serializado, se omite: $label"
                        continue
                    }
                    $safe = ($label -replace '[^\w\.-]', '_')
                    if ($safe.Length -gt 40) { $safe = $safe.Substring(0, 40) }
                    if ($SaveXmlTo) { $target = Join-Path $SaveXmlTo "RulePackage_${safe}_$ts.xml" }
                    else {
                        $target = Join-Path ([IO.Path]::GetTempPath()) "PavRulePack_$(Get-Random).xml"
                        $tempFiles.Add($target)
                    }
                    [System.IO.File]::WriteAllBytes($target, [byte[]]$bytes)
                    $xmlToParse.Add(@{ Path = $target; Meta = $meta })
                    Write-PavLog -Level Info -Message "      XML: $target"
                }
                catch {
                    Write-PavLog -Level Warn -Message "      No se pudo exportar '$label': $($_.Exception.Message)"
                }
            }
        }
        else {
            foreach ($p in @($XmlPath)) { $xmlToParse.Add(@{ Path = $p; Meta = $null }) }
        }

        # ── Parseo y fusión de todos los paquetes ────────────────────────────
        $rulePacks = [System.Collections.Generic.List[object]]::new()
        $entities  = [System.Collections.Generic.List[object]]::new()
        $regexMap = @{}; $keywordMap = @{}; $filterMap = @{}
        $sources  = [System.Collections.Generic.List[string]]::new()

        foreach ($item in $xmlToParse) {
            try {
                # Se resuelve a ruta absoluta: el parser puede ejecutarse con
                # otro directorio de trabajo que el de la llamada.
                $rutaXml = try { (Resolve-Path -LiteralPath $item.Path -ErrorAction Stop).ProviderPath } catch { $item.Path }
                $parsed = ConvertFrom-PavRulePackage -XmlPath $rutaXml
            }
            catch {
                Write-PavLog -Level Warn -Message "XML no parseable ($($item.Path)): $($_.Exception.Message)"
                continue
            }

            $packName = [string]$parsed.RulePack.Name
            if (-not $packName -and $item.Meta) { $packName = $item.Meta.CollectionName }
            if (-not $packName) { $packName = [IO.Path]::GetFileNameWithoutExtension($item.Path) }
            $packIdent = if ($item.Meta) { $item.Meta.Identity } else { '' }

            $ents = @($parsed.Entities)
            foreach ($e in $ents) {
                $e | Add-Member -NotePropertyName 'RulePackName'     -NotePropertyValue $packName  -Force
                $e | Add-Member -NotePropertyName 'RulePackIdentity' -NotePropertyValue $packIdent -Force
                $entities.Add($e)
            }

            foreach ($pair in @(@{ S = $parsed.RegexMap; D = $regexMap }, @{ S = $parsed.KeywordMap; D = $keywordMap }, @{ S = $parsed.FilterMap; D = $filterMap })) {
                foreach ($k in @($pair.S.Keys)) {
                    if ($pair.D.ContainsKey($k)) {
                        Write-PavLog -Level Warn -Message "Identificador duplicado entre RulePackages: $k (prevalece '$packName')"
                    }
                    $pair.D[$k] = $pair.S[$k]
                }
            }

            $rulePacks.Add([pscustomobject]@{
                PSTypeName    = 'PurviewAssessment.SitRulePack'
                Name          = $packName
                Publisher     = $(if ($item.Meta -and $item.Meta.Publisher) { $item.Meta.Publisher } else { [string]$parsed.RulePack.Publisher })
                Description   = $(if ($item.Meta -and $item.Meta.Description) { $item.Meta.Description } else { [string]$parsed.RulePack.Description })
                Version       = $(if ($item.Meta) { $item.Meta.Version } else { '' })
                Identity      = $packIdent
                IsBuiltIn     = $(if ($item.Meta) { $item.Meta.IsBuiltIn } else { $false })
                IsFingerprint = $(if ($item.Meta) { $item.Meta.IsFingerprint } else { $false })
                SitCount      = $ents.Count
                XmlPath       = $item.Path
            })
            $sources.Add($item.Path)
            Write-PavLog -Level Info -Message "  = $packName : $($ents.Count) SIT(s)"
        }

        $packsArr = @($rulePacks)
        # Desambiguación: dos paquetes pueden compartir RuleCollectionName
        # (p. ej. varios 'Microsoft.SCCManaged.CustomRulePack'). Se anexa el
        # GUID de su Identity para que sean distinguibles en los informes.
        foreach ($grp in @($packsArr | Group-Object Name | Where-Object Count -gt 1)) {
            foreach ($dup in $grp.Group) {
                $short = ''
                if ($dup.Identity -match '([0-9A-Fa-f]{8})-[0-9A-Fa-f]{4}-') { $short = $Matches[1] }
                elseif ($dup.Identity) { $short = ($dup.Identity -split '[/\\]')[-1] }
                if ($short) {
                    $newName = "$($dup.Name) [$short]"
                    foreach ($e in @($entities | Where-Object { "$(Get-PavProp $_ 'RulePackName' '')" -eq $dup.Name -and "$(Get-PavProp $_ 'RulePackIdentity' '')" -eq $dup.Identity })) {
                        $e | Add-Member -NotePropertyName 'RulePackName' -NotePropertyValue $newName -Force
                    }
                    $dup.Name = $newName
                }
            }
        }
        $srcArr   = @($sources)
        Write-PavLog -Level Success -Message "SITs recolectados: $(@($entities).Count) en $($packsArr.Count) RulePackage(s)"

        [pscustomobject]@{
            PSTypeName     = 'PurviewAssessment.SitData'
            RulePacks      = $packsArr
            RulePack       = $(if ($packsArr.Count -gt 0) { $packsArr[0] } else { [pscustomobject]@{ Name = ''; Publisher = ''; Description = '' } })
            Entities       = @($entities)
            RegexMap       = $regexMap
            KeywordMap     = $keywordMap
            FilterMap      = $filterMap
            SourceXmlPaths = @($srcArr | Where-Object { $tempFiles -notcontains $_ })
            SourceXmlPath  = $(if ($srcArr.Count -gt 0 -and $tempFiles -notcontains $srcArr[0]) { $srcArr[0] } else { '' })
            CollectedAt    = Get-Date
        }
    }
    finally {
        foreach ($t in $tempFiles) { if (Test-Path $t) { Remove-Item $t -Force -ErrorAction SilentlyContinue } }
    }
}
