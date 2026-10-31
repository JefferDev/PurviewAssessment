# Evaluadores de los controles del dominio MIP.
#
# Contrato de todo evaluador:
#   - Recibe -Data (objeto del colector correspondiente) y -Options (hashtable).
#   - Devuelve un hashtable con:
#       Status   : Implemented | PartiallyImplemented | NotImplemented |
#                  RequiresValidation | NotApplicable
#       Evidence : texto con el OBJETO y el VALOR concretos que sustentan el
#                  veredicto. Nunca un juicio sin dato.
#       Severity : (opcional) severidad ajustada al contexto del tenant.
#
# Regla de oro: si el dato necesario no se pudo recolectar, el veredicto es
# RequiresValidation. Nunca NotImplemented por ausencia de evidencia.

function New-PavCtrlResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Implemented', 'PartiallyImplemented', 'NotImplemented', 'RequiresValidation', 'NotApplicable')]
        [string]$Status,
        [Parameter(Mandatory)][string]$Evidence,
        [Parameter()][string]$Severity,

        # Calidad de la información que sustenta el veredicto
        [Parameter()][ValidateSet('Verified', 'Configured', 'NotDeterminable')]
        [string]$EvidenceLevel = 'Configured',

        # Motivo cuando el nivel es NotDeterminable
        [Parameter()][string]$UnreliableReason
    )
    $r = @{ Status = $Status; Evidence = $Evidence; EvidenceLevel = $EvidenceLevel }
    if ($Severity) { $r.Severity = $Severity }
    if ($UnreliableReason) { $r.UnreliableReason = $UnreliableReason }
    return $r
}

function Test-PavCtrlMip01 {
    # Jerarquía de etiquetas: existen etiquetas padre con subetiquetas.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $labels = @($Data.Labels)
    if ($labels.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron etiquetas de confidencialidad.' }

    $parents = @($labels | Where-Object { "$($_.IsParent)" -eq 'True' })
    $children = @($labels | Where-Object { "$($_.ParentId)" -and "$($_.IsParent)" -ne 'True' })
    if ($parents.Count -gt 0 -and $children.Count -gt 0) {
        return New-PavCtrlResult -Status Implemented -Evidence "$($labels.Count) etiquetas con $($parents.Count) etiqueta(s) principal(es) y $($children.Count) subetiqueta(s). Ejemplo: $(($parents | Select-Object -First 3 | ForEach-Object { $_.DisplayName }) -join ', ')."
    }
    return New-PavCtrlResult -Status NotImplemented -Evidence "$($labels.Count) etiqueta(s) sin estructura jerárquica: no se detectaron subetiquetas asociadas a una etiqueta principal."
}

function Test-PavCtrlMip02 {
    # Cifrado en las etiquetas de mayor confidencialidad.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $labels = @($Data.Labels)
    if ($labels.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron etiquetas de confidencialidad.' }

    $enc = @($labels | Where-Object { "$($_.HasEncryption)" -eq 'True' })
    if ($enc.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($labels.Count) etiquetas aplica cifrado."
    }
    $names = ($enc | Select-Object -First 5 | ForEach-Object { $_.DisplayName }) -join ', '
    # La etiqueta de mayor prioridad numérica es la más restrictiva del esquema
    $top = $labels | Sort-Object { [int]("$($_.Priority)" -replace '\D', '0') } -Descending | Select-Object -First 1
    if ("$($top.HasEncryption)" -ne 'True') {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($enc.Count) de $($labels.Count) etiquetas aplican cifrado ($names), pero la etiqueta de mayor prioridad del esquema ('$($top.DisplayName)', prioridad $($top.Priority)) no lo aplica."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "$($enc.Count) de $($labels.Count) etiquetas aplican cifrado, incluida la de mayor prioridad ('$($top.DisplayName)'). Etiquetas con cifrado: $names."
}

function Test-PavCtrlMip03 {
    # Marcado visual del contenido.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $labels = @($Data.Labels)
    if ($labels.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron etiquetas de confidencialidad.' }

    $mark = @($labels | Where-Object { "$($_.HasContentMarking)" -eq 'True' })
    if ($mark.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($labels.Count) etiquetas aplica marcado visual (encabezado, pie o marca de agua)."
    }
    $nombres = ($mark | Select-Object -First 5 | ForEach-Object { $_.DisplayName }) -join ', '

    # El marcado importa donde el contenido es sensible: se contrasta contra
    # las etiquetas que aplican cifrado, no contra el total de la taxonomía.
    $enc = @($labels | Where-Object { "$($_.HasEncryption)" -eq 'True' })
    if ($enc.Count -eq 0) {
        return New-PavCtrlResult -Status Implemented -Evidence "$($mark.Count) de $($labels.Count) etiquetas aplican marcado visual: $nombres."
    }
    $encSinMarca = @($enc | Where-Object { "$($_.HasContentMarking)" -ne 'True' })
    if ($encSinMarca.Count -eq 0) {
        return New-PavCtrlResult -Status Implemented -Evidence "Las $($enc.Count) etiquetas con cifrado aplican además marcado visual: $nombres."
    }
    return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($mark.Count) de $($labels.Count) etiquetas aplican marcado visual ($nombres), pero $($encSinMarca.Count) etiqueta(s) con cifrado no lo aplican: $(($encSinMarca | Select-Object -First 5 | ForEach-Object { $_.DisplayName }) -join ', ')."
}

function Test-PavCtrlMip04 {
    # Etiqueta predeterminada para documentos y para correo.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $pols = @($Data.Policies)
    if ($pols.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron directivas de publicación de etiquetas.' }

    $conDoc     = @($pols | Where-Object { "$($_.DefaultLabelId)" -and "$($_.DefaultLabelId)" -ne 'No configurado' })
    $conOutlook = @($pols | Where-Object { "$($_.OutlookDefaultLabelId)" -and "$($_.OutlookDefaultLabelId)" -ne 'No configurado' })
    $nombres    = ($pols | ForEach-Object { "'$($_.Name)'" }) -join ', '

    if ($conDoc.Count -eq 0 -and $conOutlook.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($pols.Count) directivas de publicación ($nombres) define etiqueta predeterminada para documentos ni para correo."
    }
    if ($conDoc.Count -eq $pols.Count -and $conOutlook.Count -eq $pols.Count) {
        return New-PavCtrlResult -Status Implemented -Evidence "Las $($pols.Count) directivas definen etiqueta predeterminada para documentos y para Outlook."
    }
    return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($conDoc.Count) de $($pols.Count) directivas definen predeterminada para documentos y $($conOutlook.Count) para Outlook. Directivas evaluadas: $nombres."
}

function Test-PavCtrlMip05 {
    # Etiquetado obligatorio.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $pols = @($Data.Policies)
    if ($pols.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron directivas de publicación de etiquetas.' }

    $obl = @($pols | Where-Object { "$($_.Mandatory)" -in @('True', 'true', 'Sí') })
    if ($obl.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($pols.Count) directivas de publicación activa el etiquetado obligatorio: $(($pols | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    if ($obl.Count -lt $pols.Count) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($obl.Count) de $($pols.Count) directivas exigen etiquetado obligatorio. Sin obligatoriedad: $(($pols | Where-Object { $_ -notin $obl } | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Las $($pols.Count) directivas de publicación exigen etiquetado obligatorio."
}

function Test-PavCtrlMip06 {
    # Justificación al degradar la etiqueta.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $pols = @($Data.Policies)
    if ($pols.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron directivas de publicación de etiquetas.' }

    $just = @($pols | Where-Object { "$($_.RequireDowngradeJustification)" -in @('True', 'true', 'Sí') })
    if ($just.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($pols.Count) directivas exige justificación al reducir el nivel de una etiqueta."
    }
    if ($just.Count -lt $pols.Count) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($just.Count) de $($pols.Count) directivas exigen justificación al degradar."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Las $($pols.Count) directivas exigen justificación al reducir el nivel de una etiqueta."
}

function Test-PavCtrlMip07 {
    # Existencia de directivas de etiquetado automático.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $auto = @(Get-PavProp $Data 'AutoLabelPolicies' @())
    if ($auto.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence 'No se detectaron directivas de etiquetado automático en el tenant.'
    }
    return New-PavCtrlResult -Status Implemented -Evidence "$($auto.Count) directiva(s) de etiquetado automático: $(($auto | Select-Object -First 5 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}

function Test-PavCtrlMip08 {
    # Modo productivo del etiquetado automático (no simulación).
    # Control diseñado a partir de un patrón real: la mera existencia de la
    # directiva no implica que aplique etiquetas.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $auto = @(Get-PavProp $Data 'AutoLabelPolicies' @())
    if ($auto.Count -eq 0) {
        return New-PavCtrlResult -Status NotApplicable -Evidence 'No existen directivas de etiquetado automático, por lo que su modo de operación no aplica (ver PAV-MIP-07).'
    }
    $sim  = @($auto | Where-Object { "$($_.ModeFriendly)" -match 'Simulaci' })
    $prod = @($auto | Where-Object { "$($_.ModeFriendly)" -match 'Activa' })

    if ($prod.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($auto.Count) directivas de etiquetado automático operan en simulación y no aplican ninguna etiqueta: $(($sim | Select-Object -First 6 | ForEach-Object { "'$($_.Name)' [$($_.Mode)]" }) -join ', ')."
    }
    if ($sim.Count -gt 0) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($prod.Count) de $($auto.Count) directivas aplican etiquetas; $($sim.Count) permanecen en simulación: $(($sim | Select-Object -First 6 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Las $($auto.Count) directivas de etiquetado automático operan en modo productivo: $(($prod | Select-Object -First 5 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}

function Test-PavCtrlMip09 {
    # Uso de SIT personalizados en el etiquetado automático.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $rules = @(Get-PavProp $Data 'AutoLabelRules' @())
    if ($rules.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence 'No existen reglas de etiquetado automático, por lo que ningún tipo de información sensible alimenta la clasificación automática.'
    }

    # SIT personalizados del tenant, si la carga SIT se recolectó en la misma ejecución
    $customNames = @()
    if ($Options.ContainsKey('SitData') -and $Options.SitData) {
        $customNames = @(@($Options.SitData.Entities) | ForEach-Object { "$($_.Name)" } | Where-Object { $_ })
    }

    $conSit = @($rules | Where-Object { "$($_.SensitiveInfoTypes)" })
    if ($conSit.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($rules.Count) reglas de etiquetado automático no declaran tipos de información sensible como condición."
    }

    if ($customNames.Count -gt 0) {
        $usados = @()
        foreach ($r in $conSit) {
            foreach ($n in $customNames) {
                if ("$($r.SensitiveInfoTypes)" -like "*$n*" -and $usados -notcontains $n) { $usados += $n }
            }
        }
        if ($usados.Count -eq 0) {
            return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($conSit.Count) regla(s) usan tipos de información sensible, pero ninguno de los $($customNames.Count) SIT personalizados del tenant participa en el etiquetado automático."
        }
        return New-PavCtrlResult -Status Implemented -Evidence "$($usados.Count) SIT personalizado(s) alimentan el etiquetado automático: $(($usados | Select-Object -First 5) -join ', ')."
    }

    return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($conSit.Count) de $($rules.Count) reglas usan tipos de información sensible. No se recolectó el catálogo de SIT personalizados en esta ejecución, por lo que no pudo confirmarse si son propios de la organización o integrados."
}

function Test-PavCtrlMip10 {
    # Vigencia de la taxonomía. Umbral parametrizable.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $labels = @($Data.Labels)
    if ($labels.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron etiquetas de confidencialidad.' }

    $umbral = if ($Options.ContainsKey('StaleDays')) { [int]$Options.StaleDays } else { 365 }
    $hoy = Get-Date
    $stale = @()
    $sinFecha = 0
    foreach ($l in $labels) {
        [datetime]$f = [datetime]::MinValue
        if (-not [datetime]::TryParse("$($l.WhenChangedUTC)", [ref]$f)) { $sinFecha++; continue }
        $dias = [int]($hoy - $f).TotalDays
        if ($dias -gt $umbral) { $stale += [pscustomobject]@{ Name = $l.DisplayName; Days = $dias } }
    }

    if ($sinFecha -eq $labels.Count) {
        return New-PavCtrlResult -Status RequiresValidation -Evidence "No se pudo determinar la fecha de última modificación de ninguna de las $($labels.Count) etiquetas."
    }
    if ($stale.Count -eq 0) {
        return New-PavCtrlResult -Status Implemented -Evidence "Las $($labels.Count) etiquetas se han modificado dentro de los últimos $umbral días."
    }
    $detalle = ($stale | Sort-Object Days -Descending | Select-Object -First 5 | ForEach-Object { "'$($_.Name)' ($($_.Days) días)" }) -join ', '
    $status = if ($stale.Count -eq $labels.Count) { 'NotImplemented' } else { 'PartiallyImplemented' }
    return New-PavCtrlResult -Status $status -Evidence "$($stale.Count) de $($labels.Count) etiquetas superan el umbral de $umbral días sin modificación: $detalle."
}
