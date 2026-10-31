function ConvertFrom-PavRulePackage {
<#
.SYNOPSIS
    Parsea el XML de un RulePackage de SITs personalizados
    (Get-DlpSensitiveInformationTypeRulePackage) al modelo de datos del
    módulo. Port del parser de Export-SITReport_v2.ps1.
.PARAMETER XmlPath
    Ruta del XML del RulePackage.
.OUTPUTS
    [pscustomobject] con RulePack (Name/Description/Publisher), Entities,
    RegexMap, KeywordMap, FilterMap.
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][ValidateScript({ Test-Path $_ -PathType Leaf })][string]$XmlPath)

    # El RulePackage exportado por el servicio declara encoding="utf-16" en su
    # cabecera. Leerlo con Get-Content -Encoding UTF8 y convertirlo a [xml]
    # produce un error de codificación o contenido corrupto, por lo que se
    # carga por ruta y se deja que el analizador resuelva el encoding real a
    # partir de la declaración y del marcador de orden de bytes.
    $xmlDoc = New-Object System.Xml.XmlDocument
    $xmlDoc.PreserveWhitespace = $false
    try {
        $xmlDoc.Load($XmlPath)
    }
    catch {
        # Reintento tolerante: se leen los bytes y se detecta la codificación
        Write-PavLog -Level Info -Message "Carga directa del XML fallida ($($_.Exception.Message)). Se reintenta detectando la codificación."
        $bytes = [System.IO.File]::ReadAllBytes($XmlPath)
        $texto = $null
        foreach ($enc in [System.Text.Encoding]::Unicode, [System.Text.Encoding]::UTF8, [System.Text.Encoding]::BigEndianUnicode, [System.Text.Encoding]::Default) {
            try {
                $t = $enc.GetString($bytes)
                if ($t -match '<\s*RulePackage') {
                    # La declaración puede contradecir la codificación real del texto ya decodificado
                    $texto = $t -replace '^\uFEFF', '' -replace '(?i)encoding\s*=\s*"utf-16"', 'encoding="utf-8"'
                    break
                }
            }
            catch { continue }
        }
        if (-not $texto) { throw "No se pudo interpretar el XML '$XmlPath': codificación no reconocida." }
        $xmlDoc.LoadXml($texto)
    }
    $ns = [System.Xml.XmlNamespaceManager]::new($xmlDoc.NameTable)
    $ns.AddNamespace('mce', 'http://schemas.microsoft.com/office/2011/mce')

    $rulesNode = $xmlDoc.SelectSingleNode('//mce:Rules', $ns)
    if ($null -eq $rulesNode) {
        # El RulePackage exportado puede declarar otro namespace (o ninguno).
        # Se reintenta por nombre local antes de darlo por inválido.
        $rulesNode = $xmlDoc.SelectSingleNode("//*[local-name()='Rules']")
        if ($rulesNode) {
            $nsUri = $rulesNode.NamespaceURI
            if ($nsUri) { $ns.AddNamespace('mce', $nsUri) }
            Write-PavLog -Level Info -Message "RulePackage con namespace '$nsUri': se ajusta el parser."
        }
    }
    if ($null -eq $rulesNode) { throw 'No se encontró el nodo <Rules> en el XML. Debe verificarse que sea un RulePackage válido.' }

    # ── Metadatos del RulePack ────────────────────────────────────────────────
    $rpName = ''; $rpDesc = ''; $rpPublisher = ''
    $rulePackNode = $xmlDoc.SelectSingleNode('//mce:RulePack', $ns)
    if ($rulePackNode) {
        $details = $rulePackNode.SelectSingleNode('.//mce:LocalizedDetails', $ns)
        if ($details) {
            $rpName      = "$($details.SelectSingleNode('mce:Name', $ns).'#text')"
            $rpDesc      = "$($details.SelectSingleNode('mce:Description', $ns).'#text')"
            $rpPublisher = "$($details.SelectSingleNode('mce:PublisherName', $ns).'#text')"
        }
    }

    # ── Strings localizados (nombre/descripción por entidad) ─────────────────
    $localizedStrings = @{}
    foreach ($resource in $xmlDoc.SelectNodes('//mce:LocalizedStrings/mce:Resource', $ns)) {
        $refId    = $resource.GetAttribute('idRef')
        $nameNode = $resource.SelectSingleNode("mce:Name[@default='true']", $ns)
        $descNode = $resource.SelectSingleNode("mce:Description[@default='true']", $ns)
        $localizedStrings[$refId] = @{
            Name        = if ($nameNode) { $nameNode.'#text'.Trim() } else { '' }
            Description = if ($descNode) { $descNode.'#text'.Trim() } else { '' }
            LangCode    = if ($nameNode) { $nameNode.GetAttribute('langcode') } else { '' }
        }
    }

    # ── Mapas: Regex / Keywords / Filters (incluye nodos bajo <Version>) ─────
    $regexMap = @{}
    foreach ($regex in $rulesNode.SelectNodes('.//mce:Regex', $ns)) {
        $regexMap[$regex.GetAttribute('id')] = $regex.InnerText.Trim()
    }
    $keywordMap = @{}
    foreach ($kw in $rulesNode.SelectNodes('.//mce:Keyword', $ns)) {
        $groups = @()
        foreach ($group in $kw.SelectNodes('mce:Group', $ns)) {
            $terms = @()
            foreach ($term in $group.SelectNodes('mce:Term', $ns)) {
                $terms += @{ Text = $term.InnerText.Trim(); CaseSensitive = $term.GetAttribute('caseSensitive') }
            }
            $groups += @{ MatchStyle = $group.GetAttribute('matchStyle'); Terms = $terms }
        }
        $keywordMap[$kw.GetAttribute('id')] = $groups
    }
    $filterMap = @{}
    foreach ($filter in $rulesNode.SelectNodes('.//mce:Filters', $ns)) {
        $items = @()
        foreach ($f in $filter.SelectNodes('mce:Filter', $ns)) {
            $items += @{ Type = $f.GetAttribute('type'); Logic = $f.GetAttribute('logic') }
        }
        $filterMap[$filter.GetAttribute('id')] = $items
    }

    # ── Entidades (SITs) y sus patrones — port de Parse-Entity ───────────────
    $parseEntity = {
        param($entityNode)
        $entityId  = $entityNode.GetAttribute('id')
        $localized = $localizedStrings[$entityId]
        $patterns  = @()
        foreach ($pattern in $entityNode.SelectNodes('mce:Pattern', $ns)) {
            $idMatch = $pattern.SelectSingleNode('mce:IdMatch', $ns)
            $matches = @()
            foreach ($m in $pattern.SelectNodes('mce:Match', $ns)) {
                $matches += @{ IdRef = $m.GetAttribute('idRef'); Proximity = $m.GetAttribute('proximity') }
            }
            $anyBlocks = @()
            foreach ($any in $pattern.SelectNodes('mce:Any', $ns)) {
                $anyMatches = @()
                foreach ($am in $any.SelectNodes('mce:Match', $ns)) {
                    $anyMatches += @{ IdRef = $am.GetAttribute('idRef'); Proximity = $am.GetAttribute('proximity') }
                }
                $anyBlocks += @{ MinMatches = $any.GetAttribute('minMatches'); Matches = $anyMatches }
            }
            $patterns += @{
                ConfidenceLevel = $pattern.GetAttribute('confidenceLevel')
                Proximity       = $pattern.GetAttribute('proximity')
                FilterId        = $pattern.GetAttribute('filters')
                IdMatchRef      = if ($idMatch) { $idMatch.GetAttribute('idRef') } else { '' }
                Matches         = $matches
                AnyBlocks       = $anyBlocks
            }
        }
        [pscustomobject]@{
            Id                    = $entityId
            Name                  = if ($localized) { $localized.Name } else { $entityId }
            Description           = if ($localized) { $localized.Description } else { '' }
            Language              = if ($localized) { $localized.LangCode } else { '' }
            PatternsProximity     = $entityNode.GetAttribute('patternsProximity')
            RecommendedConfidence = $entityNode.GetAttribute('recommendedConfidence')
            LastModified          = $entityNode.GetAttribute('lastModifiedTime')
            Patterns              = $patterns
            MinEngineVersion      = ''
        }
    }

    $entities = @()
    $entityNodes = @($rulesNode.SelectNodes('mce:Entity', $ns))
    if ($entityNodes.Count -eq 0) { $entityNodes = @($rulesNode.SelectNodes("*[local-name()='Entity']")) }
    foreach ($entity in $entityNodes) {
        $parsedE = & $parseEntity $entity
        Write-PavLog -Level Info -Message "  > SIT: $($parsedE.Name) ($(@($parsedE.Patterns).Count) patrón(es))"
        $entities += $parsedE
    }
    $versionNodes = @($rulesNode.SelectNodes('mce:Version', $ns))
    if ($versionNodes.Count -eq 0) { $versionNodes = @($rulesNode.SelectNodes("*[local-name()='Version']")) }
    foreach ($versionNode in $versionNodes) {
        $minEngine = $versionNode.GetAttribute('minEngineVersion')
        $vEntities = @($versionNode.SelectNodes('mce:Entity', $ns))
        if ($vEntities.Count -eq 0) { $vEntities = @($versionNode.SelectNodes("*[local-name()='Entity']")) }
        foreach ($entity in $vEntities) {
            $parsed = & $parseEntity $entity
            $parsed.MinEngineVersion = $minEngine
            Write-PavLog -Level Info -Message "  > SIT: $($parsed.Name) ($(@($parsed.Patterns).Count) patrón(es), engine >= $minEngine)"
            $entities += $parsed
        }
    }

    Write-PavLog -Level Info -Message "RulePackage: $($entities.Count) SITs, $($regexMap.Count) Regex, $($keywordMap.Count) Keywords, $($filterMap.Count) Filters"

    [pscustomobject]@{
        RulePack   = [pscustomobject]@{ Name = $rpName.Trim(); Description = $rpDesc; Publisher = $rpPublisher }
        Entities   = @($entities)
        RegexMap   = $regexMap
        KeywordMap = $keywordMap
        FilterMap  = $filterMap
    }
}
