# Helpers de Records Management — parseo de descriptores de file plan,
# tipos de evento de retención y ámbitos adaptativos.
# Propiedades tomadas de la salida real de un tenant.

function ConvertFrom-PavFilePlanProperty {
<#
.SYNOPSIS
    Normaliza un descriptor de file plan (Department, Category,
    SubCategory, Authority, Citation, ReferenceId) a objeto de datos.
.DESCRIPTION
    Los seis cmdlets Get-FilePlanProperty* devuelven la misma forma base;
    Citation añade CitationUrl y CitationJurisdiction, que son las
    propiedades con valor regulatorio real.
.PARAMETER Property
    Objeto crudo del cmdlet.
.PARAMETER TypeHint
    Tipo a usar si el objeto no trae FilePlanPropertyType.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.RmFilePlanProperty'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)][object]$Property,
        [Parameter(Position = 1)][string]$TypeHint = ''
    )

    $type = [string](Get-PavProp $Property 'FilePlanPropertyType' $TypeHint)
    $url  = [string](Get-PavProp $Property 'CitationUrl' '')
    $juri = [string](Get-PavProp $Property 'CitationJurisdiction' '')

    [pscustomobject]@{
        PSTypeName       = 'PurviewAssessment.RmFilePlanProperty'
        Type             = $type
        Name             = [string](Get-PavProp $Property 'Name' (Get-PavProp $Property 'DisplayName' ''))
        DisplayName      = [string](Get-PavProp $Property 'DisplayName' '')
        UnrestrictedName = [string](Get-PavProp $Property 'UnrestrictedName' '')
        # Solo Citation: referencia normativa
        CitationUrl          = $url
        CitationJurisdiction = $juri
        HasCitationDetail    = (-not [string]::IsNullOrWhiteSpace($url)) -or (-not [string]::IsNullOrWhiteSpace($juri))
        Comment          = [string](Get-PavProp $Property 'Comment' '')
        Priority         = Get-PavProp $Property 'Priority'
        Workload         = [string](Get-PavProp $Property 'Workload' '')
        Mode             = [string](Get-PavProp $Property 'Mode' '')
        Disabled         = Get-PavProp $Property 'Disabled' $false
        ReadOnly         = Get-PavProp $Property 'ReadOnly' $false
        IsValid          = Get-PavProp $Property 'IsValid' $true
        Guid             = [string](Get-PavProp $Property 'Guid' '')
        Policy           = [string](Get-PavProp $Property 'Policy' '')
        CreatedBy        = [string](Get-PavProp $Property 'CreatedBy' '')
        LastModifiedBy   = [string](Get-PavProp $Property 'LastModifiedBy' '')
        CreatedUtc       = Get-PavProp $Property 'WhenCreatedUTC'
        LastModifiedUtc  = Get-PavProp $Property 'WhenChangedUTC'
    }
}

function Get-PavNameFromDn {
<#
.SYNOPSIS
    Extrae el nombre legible del final de un DN o Identity de Purview.
    Los tipos de evento devuelven las etiquetas asociadas como rutas
    completas ('.../Configuration/Nombre de la etiqueta').
#>
    [CmdletBinding()]
    param([Parameter(Position = 0)][AllowNull()][AllowEmptyString()][string]$Dn)

    if ([string]::IsNullOrWhiteSpace($Dn)) { return '' }
    $t = $Dn.Trim()
    if ($t -match '/Configuration/(.+)$') { return $Matches[1] }
    if ($t -match '^CN=([^,]+)')          { return $Matches[1] }
    if ($t -match '/([^/]+)$')            { return $Matches[1] }
    return $t
}

function ConvertFrom-PavRetentionEventType {
<#
.SYNOPSIS
    Normaliza un tipo de evento de retención, resolviendo las etiquetas
    asociadas (propiedad ComplianceTags, que solo se puebla si el cmdlet
    se invocó con -LoadTag).
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.RmEventType'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory, Position = 0)][object]$EventType)

    $tags = @(@(Get-PavProp $EventType 'ComplianceTags' @()) | ForEach-Object { Get-PavNameFromDn "$_" } | Where-Object { $_ })

    [pscustomobject]@{
        PSTypeName      = 'PurviewAssessment.RmEventType'
        Name            = [string](Get-PavProp $EventType 'Name' '')
        Comment         = [string](Get-PavProp $EventType 'Comment' '')
        LinkedLabels    = ($tags -join ' | ')
        LinkedLabelCount = $tags.Count
        Priority        = Get-PavProp $EventType 'Priority'
        Workload        = [string](Get-PavProp $EventType 'Workload' '')
        Mode            = [string](Get-PavProp $EventType 'Mode' '')
        Disabled        = Get-PavProp $EventType 'Disabled' $false
        IsValid         = Get-PavProp $EventType 'IsValid' $true
        Guid            = [string](Get-PavProp $EventType 'Guid' '')
        Policy          = [string](Get-PavProp $EventType 'Policy' '')
        CreatedBy       = [string](Get-PavProp $EventType 'CreatedBy' '')
        LastModifiedBy  = [string](Get-PavProp $EventType 'LastModifiedBy' '')
        CreatedUtc      = Get-PavProp $EventType 'WhenCreatedUTC'
        LastModifiedUtc = Get-PavProp $EventType 'WhenChangedUTC'
    }
}

function ConvertFrom-PavRetentionEvent {
<#
.SYNOPSIS
    Normaliza un evento de retención (instancia que dispara el cómputo).
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.RmEvent'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory, Position = 0)][object]$Event)

    [pscustomobject]@{
        PSTypeName     = 'PurviewAssessment.RmEvent'
        Name           = [string](Get-PavProp $Event 'Name' '')
        EventType      = Get-PavNameFromDn "$(Get-PavProp $Event 'EventType' '')"
        EventDateTime  = Get-PavProp $Event 'EventDateTime'
        Comment        = [string](Get-PavProp $Event 'Comment' '')
        SharePointAssetIdQuery = [string](Get-PavProp $Event 'SharePointAssetIdQuery' '')
        ExchangeAssetIdQuery   = [string](Get-PavProp $Event 'ExchangeAssetIdQuery' '')
        AssetId        = [string](Get-PavProp $Event 'AssetId' '')
        Status         = [string](Get-PavProp $Event 'Status' '')
        Guid           = [string](Get-PavProp $Event 'Guid' '')
        CreatedBy      = [string](Get-PavProp $Event 'CreatedBy' '')
        CreatedUtc     = Get-PavProp $Event 'WhenCreatedUTC'
    }
}

function ConvertFrom-PavAdaptiveScope {
<#
.SYNOPSIS
    Normaliza un ámbito adaptativo (consulta dinámica de destinatarios).
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.RmAdaptiveScope'
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory, Position = 0)][object]$Scope)

    [pscustomobject]@{
        PSTypeName      = 'PurviewAssessment.RmAdaptiveScope'
        Name            = [string](Get-PavProp $Scope 'Name' '')
        Comment         = [string](Get-PavProp $Scope 'Comment' '')
        LocationType    = [string](Get-PavProp $Scope 'LocationType' '')
        FilterQuery     = "$(Get-PavProp $Scope 'FilterQuery' '')"
        RawQuery        = "$(Get-PavProp $Scope 'RawQuery' '')"
        Disabled        = Get-PavProp $Scope 'Disabled' $false
        Mode            = [string](Get-PavProp $Scope 'Mode' '')
        Guid            = [string](Get-PavProp $Scope 'Guid' '')
        CreatedBy       = [string](Get-PavProp $Scope 'CreatedBy' '')
        LastModifiedBy  = [string](Get-PavProp $Scope 'LastModifiedBy' '')
        CreatedUtc      = Get-PavProp $Scope 'WhenCreatedUTC'
        LastModifiedUtc = Get-PavProp $Scope 'WhenChangedUTC'
    }
}

function Get-PavRmFindings {
<#
.SYNOPSIS
    Deriva hallazgos de gobierno de registros a partir de los datos
    recolectados: descriptores sin usar, etiquetas de registro sin file
    plan, tipos de evento sin etiquetas, citaciones sin referencia
    normativa y nombres duplicados.
.PARAMETER Properties
    Descriptores del file plan normalizados.
.PARAMETER EventTypes
    Tipos de evento normalizados.
.PARAMETER RecordTags
    Etiquetas de retención de tipo registro (de Get-ComplianceTag).
.PARAMETER FilePlanUsage
    Valores de file plan efectivamente usados por las etiquetas.
.OUTPUTS
    [pscustomobject[]] con Severity, Area, Finding, Detail.
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter()][object[]]$Properties = @(),
        [Parameter()][object[]]$EventTypes = @(),
        [Parameter()][object[]]$RecordTags = @(),
        [Parameter()][string[]]$FilePlanUsage = @()
    )

    $out = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($sev, $area, $finding, $detail)
        $out.Add([pscustomobject]@{
            PSTypeName = 'PurviewAssessment.RmFinding'
            Severity = $sev; Area = $area; Finding = $finding; Detail = $detail
        })
    }

    # 1. Descriptores definidos pero no utilizados por ninguna etiqueta
    $used = @($FilePlanUsage | Where-Object { $_ } | ForEach-Object { "$_".Trim().ToLowerInvariant() })
    foreach ($p in @($Properties)) {
        $n = "$($p.Name)".Trim().ToLowerInvariant()
        if ($n -and $used -notcontains $n) {
            & $add 'Media' 'File plan' "Descriptor '$($p.Type)' sin uso" "El descriptor '$($p.Name)' está definido pero ninguna etiqueta de retención lo referencia."
        }
    }

    # 2. Citaciones sin referencia normativa (URL o jurisdicción)
    foreach ($c in @($Properties | Where-Object { $_.Type -eq 'Citation' -and -not $_.HasCitationDetail })) {
        & $add 'Alta' 'File plan' 'Citación sin referencia normativa' "La citación '$($c.Name)' no declara CitationUrl ni CitationJurisdiction, por lo que no es trazable a la norma que la sustenta."
    }

    # 3. Tipos de evento sin etiquetas asociadas
    foreach ($e in @($EventTypes | Where-Object { $_.LinkedLabelCount -eq 0 })) {
        & $add 'Alta' 'Retención por eventos' 'Tipo de evento sin etiquetas' "El tipo de evento '$($e.Name)' no tiene etiquetas de retención asociadas: no dispara el cómputo de ningún periodo."
    }

    # 4. Etiquetas de registro sin file plan asignado
    foreach ($t in @($RecordTags | Where-Object { -not $_.HasFilePlan })) {
        & $add 'Media' 'Registros' 'Etiqueta de registro sin file plan' "La etiqueta '$($t.Name)' declara contenido como registro pero no tiene descriptores de file plan, lo que dificulta su auditoría."
    }

    # 5. Etiquetas de registro sin revisión de disposición
    foreach ($t in @($RecordTags | Where-Object { -not $_.HasReviewStages -and "$($_.RetentionAction)" -match 'elimin' })) {
        & $add 'Media' 'Disposición' 'Eliminación sin revisión' "La etiqueta '$($t.Name)' elimina contenido al vencer la retención sin revisión de disposición previa."
    }

    # 6. Nombres duplicados o casi duplicados entre descriptores del mismo tipo
    foreach ($grp in @($Properties | Group-Object Type)) {
        $seen = @{}
        foreach ($p in $grp.Group) {
            # Normalización tolerante: sin acentos, minúsculas, sin signos
            $k = "$($p.Name)".ToLowerInvariant() -replace '[áàä]', 'a' -replace '[éèë]', 'e' -replace '[íìï]', 'i' -replace '[óòö]', 'o' -replace '[úùü]', 'u' -replace '[^a-z0-9]', ''
            if (-not $k) { continue }
            if ($seen.ContainsKey($k)) {
                & $add 'Media' 'File plan' "Descriptores '$($grp.Name)' duplicados" "'$($p.Name)' y '$($seen[$k])' son equivalentes tras normalizar acentos y signos: probable duplicidad."
            }
            else { $seen[$k] = $p.Name }
        }
    }

    return @($out)
}

function Get-PavLabelScope {
<#
.SYNOPSIS
    Determina si una etiqueta de retención pertenece al ámbito de gestión de
    registros o al de ciclo de vida de los datos, y por qué.
.DESCRIPTION
    Get-ComplianceTag devuelve tanto las etiquetas de retención simples como
    las que forman parte del plan de archivos, e IsRecordLabel NO basta para
    distinguirlas: una etiqueta puede estar plenamente incorporada al plan de
    archivos, con descriptores y revisión de disposición, y aun así tener
    IsRecordLabel en False (la declaración de registro es un atributo
    adicional, no el criterio de pertenencia).

    Se considera de gestión de registros la etiqueta que cumple alguno de:
      - Declara el contenido como registro (IsRecordLabel o Regulatory).
      - Tiene descriptores de plan de archivos asignados.
      - Tiene revisión de disposición (IsReviewTag o etapas de revisión).
      - Computa la retención desde un evento de negocio.
    El resto conserva o elimina por tiempo: ámbito de ciclo de vida.
.OUTPUTS
    [pscustomobject] con Scope, Reasons (motivos) e IsRecordsManagement.
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory, Position = 0)][object]$Tag)

    $motivos = @()
    if ([bool](Get-PavProp $Tag 'Regulatory' $false))    { $motivos += 'Declara registro regulado' }
    elseif ([bool](Get-PavProp $Tag 'IsRecordLabel' $false)) { $motivos += 'Declara registro' }

    $fp = "$(Get-PavProp $Tag 'FilePlanMetadata' '')"
    if (-not [string]::IsNullOrWhiteSpace($fp)) { $motivos += 'Incorporada al plan de archivos' }

    $rev = "$(Get-PavProp $Tag 'MultiStageReviewerMetadata' '')"
    $revisores = @(@(Get-PavProp $Tag 'ReviewerEmail' @()) | Where-Object { $_ })
    if ([bool](Get-PavProp $Tag 'IsReviewTag' $false) -or -not [string]::IsNullOrWhiteSpace($rev) -or $revisores.Count -gt 0) {
        $motivos += 'Con revisión de disposición'
    }

    $evId = "$(Get-PavProp $Tag 'EventTypeId' '')"
    if ($evId -or "$(Get-PavProp $Tag 'RetentionType' '')" -eq 'EventAgeInDays') { $motivos += 'Retención basada en evento' }

    $esRm = $motivos.Count -gt 0
    [pscustomobject]@{
        Scope   = if ($esRm) { 'Gestión de registros' } else { 'Ciclo de vida (DLM)' }
        Reasons = ($motivos -join '; ')
        IsRecordsManagement = $esRm
    }
}
