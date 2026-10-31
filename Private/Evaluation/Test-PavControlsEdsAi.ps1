# Evaluadores de descubrimiento electrónico y gobierno de inteligencia
# artificial. Los de IA son transversales: reciben el hashtable completo de
# datos y cruzan varias cargas.

# ── eDiscovery ───────────────────────────────────────────────────────────────

function Test-PavCtrlEds01 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $c = @($Data.Cases)
    if ($c.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence 'No existe ningún caso de descubrimiento electrónico en el tenant: la capacidad no está en uso.' }
    $act = @($c | Where-Object { "$($_.Status)" -ne 'Closed' })
    return New-PavCtrlResult -Status Implemented -Evidence "$($c.Count) caso(s), $($act.Count) activo(s): $(($c | Select-Object -First 4 | ForEach-Object { "'$($_.Name)' [$($_.Status)]" }) -join ', ')."
}

function Test-PavCtrlEds02 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $h = @($Data.HoldPolicies)
    if ($h.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence 'No existe ninguna retención legal: el contenido puede eliminarse por las políticas de retención antes de poder preservarse.' }
    $act = @($h | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($act.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($h.Count) retenciones legales existentes están deshabilitadas." }
    return New-PavCtrlResult -Status Implemented -Evidence "$($act.Count) de $($h.Count) retenciones legales activas: $(($act | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}

function Test-PavCtrlEds03 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $h = @($Data.HoldPolicies | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($h.Count -eq 0) { return New-PavCtrlResult -Status NotApplicable -Evidence 'No hay retenciones legales activas cuyo alcance evaluar (ver PAV-EDS-02).' }
    $cub = @(); $sin = @()
    foreach ($u in 'Exchange', 'SharePoint', 'OneDrive') {
        if (@($h | Where-Object { $v = "$(Get-PavProp $_ $u '')"; $v -and $v -ne 'No' }).Count -gt 0) { $cub += $u } else { $sin += $u }
    }
    if ($sin.Count -eq 0) { return New-PavCtrlResult -Status Implemented -Evidence "Las retenciones activas cubren Exchange, SharePoint y OneDrive." }
    if ($cub.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($h.Count) retenciones activas no declaran ubicación en ninguna de las cargas principales." }
    return New-PavCtrlResult -Status PartiallyImplemented -Evidence "Ubicaciones preservadas: $($cub -join ', '). Sin cobertura: $($sin -join ', ')."
}

function Test-PavCtrlEds04 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $c = @($Data.Cases)
    if ($c.Count -eq 0) { return New-PavCtrlResult -Status NotApplicable -Evidence 'No hay casos cuyo acceso evaluar (ver PAV-EDS-01).' }
    $sin = @($c | Where-Object { [int]"$($_.MemberCount)" -eq 0 })
    if ($sin.Count -eq $c.Count) {
        return New-PavCtrlResult -Status RequiresValidation -Evidence "Ninguno de los $($c.Count) casos declara miembros en los datos recolectados. La restricción de acceso puede estar gestionada por grupos de roles, lo que debe confirmarse en el portal."
    }
    if ($sin.Count -gt 0) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($sin.Count) de $($c.Count) casos no tienen miembros asignados: $(($sin | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Los $($c.Count) casos tienen miembros asignados de forma explícita."
}

# ── Gobierno de IA (transversales) ───────────────────────────────────────────

function Test-PavCtrlAi01 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    if (-not $Data.ContainsKey('MIP') -or $null -eq $Data['MIP']) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectó la carga MIP: no puede evaluarse la protección del contenido accesible por la IA.' }
    $lbl = @($Data['MIP'].Labels)
    $enc = @($lbl | Where-Object { "$($_.HasEncryption)" -eq 'True' })
    if ($lbl.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence 'No hay etiquetas de confidencialidad: la IA puede acceder a todo el contenido del usuario sin restricción por clasificación.' }
    if ($enc.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($lbl.Count) etiquetas no aplican cifrado: ninguna restringe qué contenido puede procesar la IA." }
    return New-PavCtrlResult -Status Implemented -Evidence "$($enc.Count) de $($lbl.Count) etiquetas aplican cifrado y limitan el contenido procesable por la IA: $(($enc | Select-Object -First 4 | ForEach-Object { "'$($_.DisplayName)'" }) -join ', ')."
}

function Test-PavCtrlAiPorCarga {
    # Motor común: busca menciones de IA en el texto de una carga concreta
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Data,
        [Parameter(Mandatory)][string]$Carga,
        [Parameter(Mandatory)][scriptblock]$Extractor,
        [Parameter(Mandatory)][string]$Descripcion,
        [Parameter()][string]$SinCarga
    )
    if (-not $Data.ContainsKey($Carga) -or $null -eq $Data[$Carga]) {
        return New-PavCtrlResult -Status RequiresValidation -Evidence "No se recolectó la carga $Carga$(if ($SinCarga) { ": $SinCarga" })."
    }
    $items = @(& $Extractor $Data[$Carga])
    $patron = 'copilot|\bIA\b|artificial|CloudAIApp|ConnectedAIApp|GenerativeAI|AIApp'
    $match = @($items | Where-Object { "$_" -match $patron })
    if ($match.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguno de los $($items.Count) elementos de $Carga $Descripcion."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "$($match.Count) elemento(s) de $Carga $($Descripcion -replace '^no ', '')$(if ($match.Count -le 4) { ": $(($match | Select-Object -First 4 | ForEach-Object { "'$_'" }) -join ', ')" })."
}

function Test-PavCtrlAi02 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    Test-PavCtrlAiPorCarga -Data $Data -Carga 'DLP' -Descripcion 'está dirigido a superficies de inteligencia artificial' `
        -Extractor { param($d) @($d.Policies | ForEach-Object { "$($_.Name) $($_.Workload) $($_.Comment)" }) + @($d.Rules | ForEach-Object { "$($_.RuleName) $($_.AppRestrictions)" }) }
}

function Test-PavCtrlAi03 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    Test-PavCtrlAiPorCarga -Data $Data -Carga 'DLM' -Descripcion 'conserva contenido generado por inteligencia artificial' `
        -Extractor { param($d) @($d.Policies | ForEach-Object { "$($_.Name) $($_.Applications) $($_.Workload)" }) + @($d.PolicyLocations | ForEach-Object { "$($_.Workload) $($_.IncludedDetails)" }) }
}

function Test-PavCtrlAi04 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    Test-PavCtrlAiPorCarga -Data $Data -Carga 'CC' -Descripcion 'supervisa interacciones con inteligencia artificial' `
        -Extractor { param($d) @($d.Policies | ForEach-Object { "$($_.Name) $($_.Workloads)" }) + @($d.Rules | ForEach-Object { "$($_.RuleName) $($_.Workloads) $($_.ContentSources)" }) }
}

function Test-PavCtrlAi05 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    Test-PavCtrlAiPorCarga -Data $Data -Carga 'IRM' -Descripcion 'contempla el uso indebido de inteligencia artificial' `
        -Extractor { param($d) @($d.Policies | ForEach-Object { "$($_.Name) $($_.Scenario) $($_.PolicyCategory)" }) }
}

function Test-PavCtrlAi06 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    if (-not $Data.ContainsKey('AUDIT') -or $null -eq $Data['AUDIT']) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectó la carga de auditoría.' }
    $a = $Data['AUDIT']
    if ("$($a.Status.UnifiedAuditLogIngestion)" -eq 'Deshabilitada') {
        return New-PavCtrlResult -Status NotImplemented -Evidence 'El registro de auditoría unificada está deshabilitado: ninguna interacción con la IA queda registrada.'
    }
    $pol = @($a.RetentionPolicies | Where-Object { "$($_.Name) $($_.RecordTypes) $($_.Operations)" -match 'Copilot|AI' })
    if ("$($a.Status.UnifiedAuditLogIngestion)" -eq 'No determinable') {
        return New-PavCtrlResult -Status RequiresValidation -Evidence 'El estado del registro de auditoría no pudo verificarse; conéctese también a Exchange Online para confirmarlo.'
    }
    if ($pol.Count -gt 0) {
        return New-PavCtrlResult -Status Implemented -Evidence "El registro está habilitado y $($pol.Count) directiva(s) de retención cubren registros de inteligencia artificial: $(($pol | Select-Object -First 3 | ForEach-Object { "'$($_.Name)' ($($_.RetentionDuration))" }) -join ', ')."
    }
    return New-PavCtrlResult -Status PartiallyImplemented -Evidence 'El registro de auditoría está habilitado y captura las interacciones, pero ninguna directiva de retención las conserva más allá del periodo por defecto del plan.'
}

function Test-PavCtrlAi07 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    if (-not $Data.ContainsKey('EDS') -or $null -eq $Data['EDS']) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectó la carga de eDiscovery: no puede evaluarse si el contenido generado por la IA es localizable.' }
    $e = $Data['EDS']
    if (@($e.Cases).Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence 'No existe ningún caso de descubrimiento electrónico, por lo que el contenido generado por la IA no puede buscarse ni preservarse de forma defendible.'
    }
    $h = @($e.HoldPolicies | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($h.Count -eq 0) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "Existen $(@($e.Cases).Count) caso(s) pero ninguna retención legal activa que preserve el contenido de la IA."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "$(@($e.Cases).Count) caso(s) y $($h.Count) retención(es) activa(s) permiten localizar y preservar el contenido generado por la IA."
}
