# Evaluadores de los dominios de cumplimiento de comunicaciones,
# riesgo interno y auditoría.

# ── Cumplimiento de comunicaciones ───────────────────────────────────────────

function Test-PavCtrlCc01 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $p = @($Data.Policies)
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence 'No existen directivas de cumplimiento de comunicaciones en el tenant.' }
    $hab = @($p | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($hab.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($p.Count) directivas existentes están deshabilitadas." }
    return New-PavCtrlResult -Status Implemented -Evidence "$($hab.Count) de $($p.Count) directivas habilitadas: $(($hab | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}

function Test-PavCtrlCc02 {
    # Operatividad de las directivas.
    #
    # PolicyStatus y ProvisionStatus NO determinan el veredicto: ambas son
    # propiedades no fiables que permanecen en 'Activating' o 'NotStarted' en
    # directivas plenamente operativas. Se evalúa lo que sí es concluyente
    # —la directiva existe, está habilitada y tiene reglas— y esas dos
    # propiedades se reportan como información, nunca como incumplimiento.
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $p = @($Data.Policies | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay directivas habilitadas que evaluar.' -EvidenceLevel NotDeterminable }

    $motivo = Get-PavUnreliableReason 'ProvisionStatus' 'Get-SupervisoryReviewPolicyV2'
    $conReglas = @($p | Where-Object { [int]"$(Get-PavProp $_ 'RulesCount' 0)" -gt 0 })
    $estados = @($p | ForEach-Object { "$($_.PolicyStatus)" } | Where-Object { $_ } | Sort-Object -Unique)
    $nota = if ($estados.Count -gt 0) { " Estado informado por el servicio: $($estados -join ', ') (propiedad no concluyente)." } else { '' }

    if ($conReglas.Count -eq 0) {
        return New-PavCtrlResult -Status PartiallyImplemented -EvidenceLevel NotDeterminable -UnreliableReason $motivo `
            -Evidence "Las $($p.Count) directivas habilitadas no muestran reglas asociadas en los datos recolectados.$nota La operatividad efectiva debe confirmarse en el portal o con evidencia de actividad."
    }
    return New-PavCtrlResult -Status Implemented -EvidenceLevel Configured `
        -Evidence "$($conReglas.Count) de $($p.Count) directivas habilitadas tienen reglas asociadas y condiciones de detección definidas: $(($conReglas | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ').$nota"
}

function Test-PavCtrlCc03 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $p = @($Data.Policies | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay directivas habilitadas que evaluar.' }
    $txt = (@($p | ForEach-Object { "$($_.Workloads)" }) -join ' ')
    $canales = [ordered]@{ 'Exchange' = 'Exchange'; 'Teams' = 'Teams'; 'Viva Engage' = 'Yammer|Viva' }
    $cub = @(); $sin = @()
    foreach ($c in $canales.GetEnumerator()) { if ($txt -match $c.Value) { $cub += $c.Key } else { $sin += $c.Key } }
    if ($cub.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($p.Count) directivas habilitadas no declaran carga de trabajo supervisada." }
    if ($sin.Count -gt 0) {
        $sev = if ($sin -contains 'Exchange') { 'Alta' } else { 'Media' }
        return New-PavCtrlResult -Status PartiallyImplemented -Severity $sev -Evidence "Canales supervisados: $($cub -join ', '). Sin supervisión: $($sin -join ', ')."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Los canales evaluados están supervisados: $($cub -join ', ')."
}

function Test-PavCtrlCc04 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $p = @($Data.Policies | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay directivas habilitadas que evaluar.' }
    $con = @($p | Where-Object { "$($_.Reviewers)" -or [int]"$(Get-PavProp $_ 'ReviewerCount' 0)" -gt 0 })
    if ($con.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($p.Count) directivas habilitadas tiene revisores asignados: los elementos marcados no llegan a triarse."
    }
    if ($con.Count -lt $p.Count) {
        $sin = @($p | Where-Object { -not "$($_.Reviewers)" })
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($con.Count) de $($p.Count) directivas tienen revisores. Sin revisor: $(($sin | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Las $($p.Count) directivas habilitadas tienen revisores asignados: $(($con | Select-Object -First 3 | ForEach-Object { "'$($_.Name)' → $($_.Reviewers)" }) -join '; ')."
}

function Test-PavCtrlCc05 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $r = @($Data.Rules)
    if ($r.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron reglas de cumplimiento de comunicaciones.' }
    $con = @($r | Where-Object { "$($_.ClassifiersModels)" -and "$($_.ClassifiersModels)" -ne 'N/D' })
    if ($con.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($r.Count) reglas emplea clasificadores entrenables: la detección se limita a coincidencias literales."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "$($con.Count) de $($r.Count) reglas emplean clasificadores: $(($con | Select-Object -First 3 | ForEach-Object { "'$($_.RuleName)' ($($_.ClassifiersModels))" }) -join '; ')."
}

function Test-PavCtrlCc06 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $r = @($Data.Rules)
    if ($r.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron reglas que evaluar.' }
    $bajo = @($r | Where-Object { $v = 0; [int]::TryParse("$($_.SamplingRate)", [ref]$v) | Out-Null; $v -gt 0 -and $v -lt 100 })
    $cien = @($r | Where-Object { "$($_.SamplingRate)" -eq '100' })
    if ($cien.Count -eq $r.Count) { return New-PavCtrlResult -Status Implemented -Evidence "Las $($r.Count) reglas supervisan el 100% de las comunicaciones en ámbito." }
    if ($bajo.Count -gt 0) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($bajo.Count) de $($r.Count) reglas aplican muestreo parcial: $(($bajo | Select-Object -First 4 | ForEach-Object { "'$($_.RuleName)' ($($_.SamplingRate)%)" }) -join ', ')."
    }
    return New-PavCtrlResult -Status RequiresValidation -Evidence "No fue posible determinar el porcentaje de muestreo de las $($r.Count) reglas."
}

function Test-PavCtrlCc07 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $r = @($Data.Rules)
    if ($r.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron reglas que evaluar.' }
    $ocr = @($r | Where-Object { "$($_.OcrEnabled)" -in @('True', 'Sí') })
    if ($ocr.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($r.Count) reglas analiza el contenido de las imágenes: la información compartida como captura elude la supervisión."
    }
    if ($ocr.Count -lt $r.Count) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($ocr.Count) de $($r.Count) reglas tienen reconocimiento óptico habilitado."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Las $($r.Count) reglas analizan el contenido de las imágenes."
}

# ── Riesgo interno ───────────────────────────────────────────────────────────

function Test-PavCtrlIrm01 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $p = @($Data.Policies)
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence 'No existen directivas de riesgo interno en el tenant.' }
    $hab = @($p | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($hab.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($p.Count) directivas de riesgo interno están deshabilitadas." }
    return New-PavCtrlResult -Status Implemented -Evidence "$($hab.Count) de $($p.Count) directivas habilitadas: $(($hab | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}

function Test-PavCtrlIrm02 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $h = @($Data.Health)
    if ($h.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectó el estado de salud de las directivas.' }
    $mal = @($h | Where-Object { "$($_.HealthStatus)" -notin @('Healthy', 'Unknown', '') })
    if ($mal.Count -eq 0) {
        return New-PavCtrlResult -Status Implemented -Evidence "Las $($h.Count) directivas evaluadas presentan estado saludable."
    }
    return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($mal.Count) de $($h.Count) directivas presentan problemas: $(($mal | Select-Object -First 3 | ForEach-Object { "'$($_.PolicyName)' [$($_.HealthStatus)] $($_.ValidationIssues)" }) -join '; ')."
}

function Test-PavCtrlIrm03 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $p = @($Data.Policies | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay directivas de riesgo interno habilitadas.' }
    $txt = (@($p | ForEach-Object { "$($_.Scenario) $($_.PolicyCategory) $($_.Name)" }) -join ' ')
    $fuga = ($txt -match 'DataLeak|Leak|Exfiltra')
    $baja = ($txt -match 'Leaver|Departing|Termination|Theft|IntellectualProperty')
    if ($fuga -and $baja) { return New-PavCtrlResult -Status Implemented -Evidence "Las directivas cubren fuga de información y salida de personal: $(($p | Select-Object -First 4 | ForEach-Object { "'$($_.Name)' [$($_.Scenario)]" }) -join ', ')." }
    if ($fuga -or $baja) {
        $falta = if ($fuga) { 'salida de personal' } else { 'fuga de información' }
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "Las $($p.Count) directivas habilitadas no cubren el escenario de $falta. Escenarios detectados: $(($p | ForEach-Object { "$($_.Scenario)" } | Sort-Object -Unique) -join ', ')."
    }
    return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($p.Count) directivas habilitadas no cubren ni la fuga de información ni la salida de personal. Escenarios: $(($p | ForEach-Object { "$($_.Scenario)" } | Sort-Object -Unique) -join ', ')."
}

function Test-PavCtrlIrm04 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $ind = @($Data.Indicators) + @($Data.ExtensibleIndicators)
    if ($ind.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence 'Las directivas no declaran indicadores de actividad: sin señales no hay evaluación de comportamiento.'
    }
    $act = @($ind | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    $grupos = @($ind | ForEach-Object { "$($_.GroupName)" } | Where-Object { $_ } | Sort-Object -Unique)
    if ($act.Count -eq 0) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($ind.Count) indicador(es) declarados pero ninguno habilitado."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "$($act.Count) de $($ind.Count) indicadores habilitados en $($grupos.Count) grupo(s): $(($grupos | Select-Object -First 5) -join ', ')."
}

function Test-PavCtrlIrm05 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $p = @($Data.Policies | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay directivas habilitadas que evaluar.' }
    $cortas = @()
    foreach ($x in $p) {
        $ins = 0; $his = 0
        [int]::TryParse("$($x.InScopeTimeSpanDays)", [ref]$ins) | Out-Null
        [int]::TryParse("$($x.HistoricTimeSpanDays)", [ref]$his) | Out-Null
        if (($ins -gt 0 -and $ins -lt 30) -or ($his -gt 0 -and $his -lt 60)) { $cortas += "'$($x.Name)' ($ins d en ámbito / $his d histórico)" }
    }
    if ($cortas.Count -eq 0) {
        $ej = ($p | Select-Object -First 2 | ForEach-Object { "$($_.InScopeTimeSpanDays) d en ámbito / $($_.HistoricTimeSpanDays) d histórico" }) -join '; '
        return New-PavCtrlResult -Status Implemented -Evidence "Las ventanas de detección de las $($p.Count) directivas son suficientes ($ej)."
    }
    return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($cortas.Count) directiva(s) con ventanas cortas: $(($cortas | Select-Object -First 4) -join ', ')."
}

# ── Auditoría ────────────────────────────────────────────────────────────────

function Test-PavCtrlAud01 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $st = $Data.Status
    switch ("$($st.UnifiedAuditLogIngestion)") {
        'Habilitada'    { return New-PavCtrlResult -Status Implemented -Evidence "El registro de auditoría unificada está habilitado. $($st.IngestionNote)" }
        'Deshabilitada' { return New-PavCtrlResult -Status NotImplemented -Evidence 'El registro de auditoría unificada está deshabilitado: no se captura actividad de usuarios ni de administradores.' }
        default         { return New-PavCtrlResult -Status RequiresValidation -Evidence "$($st.IngestionNote)" }
    }
}

function Test-PavCtrlAud02 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    switch ("$($Data.Status.MailboxAuditing)") {
        'Habilitada'    { return New-PavCtrlResult -Status Implemented -Evidence 'La auditoría de buzones está activa a nivel de organización.' }
        'Deshabilitada' { return New-PavCtrlResult -Status NotImplemented -Evidence 'La auditoría de buzones está deshabilitada a nivel de organización: no se registran acciones sobre el correo.' }
        default         { return New-PavCtrlResult -Status RequiresValidation -Evidence 'El estado de la auditoría de buzones no pudo verificarse desde la sesión de cumplimiento; requiere sesión de Exchange Online.' }
    }
}

function Test-PavCtrlAud03 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $p = @($Data.RetentionPolicies)
    if ($p.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence 'No existen directivas de retención del registro de auditoría: todos los registros caducan en el periodo por defecto del plan.'
    }
    $hab = @($p | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($hab.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($p.Count) directivas de retención de auditoría están deshabilitadas." }
    return New-PavCtrlResult -Status Implemented -Evidence "$($hab.Count) de $($p.Count) directivas de retención habilitadas: $(($hab | Select-Object -First 4 | ForEach-Object { "'$($_.Name)' ($($_.RetentionDuration))" }) -join ', ')."
}

function Test-PavCtrlAud04 {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $p = @($Data.RetentionPolicies | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status NotApplicable -Evidence 'No hay directivas de retención de auditoría habilitadas (ver PAV-AUD-03).' }
    $mas = @($p | Where-Object { [int]"$($_.RetentionDays)" -gt 90 })
    if ($mas.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($p.Count) directivas conservan 90 días o menos, sin superar la retención por defecto: $(($p | Select-Object -First 4 | ForEach-Object { "'$($_.Name)' ($($_.RetentionDuration))" }) -join ', ')."
    }
    if ($mas.Count -lt $p.Count) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($mas.Count) de $($p.Count) directivas superan los 90 días: $(($mas | Select-Object -First 4 | ForEach-Object { "'$($_.Name)' ($($_.RetentionDuration))" }) -join ', ')."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Las $($p.Count) directivas superan la retención por defecto: $(($p | Select-Object -First 4 | ForEach-Object { "'$($_.Name)' ($($_.RetentionDuration))" }) -join ', ')."
}

function Test-PavCtrlAud05 {
    # Distribución de las directivas de retención de auditoría.
    #
    # El colector consulta con -DistributionDetail, por lo que el valor es
    # concluyente. Solo si el cmdlet no admitió el modificador el estado
    # sigue siendo no determinable.
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $p = @($Data.RetentionPolicies)
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status NotApplicable -Evidence 'No hay directivas de retención de auditoría que evaluar.' }

    $fallo = @($p | Where-Object { "$($_.DistributionStatus)" -in @('Failed', 'Error') })
    $pend  = @($p | Where-Object { "$($_.DistributionStatus)" -in @('Pending', 'NotStarted') })
    $ok    = @($p | Where-Object { "$($_.DistributionStatus)" -eq 'Success' })

    if ($fallo.Count -gt 0) {
        return New-PavCtrlResult -Status NotImplemented -Severity 'Media' -EvidenceLevel Verified `
            -Evidence "$($fallo.Count) directiva(s) con fallo de distribución: $(($fallo | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    if ($ok.Count -eq $p.Count) {
        return New-PavCtrlResult -Status Implemented -EvidenceLevel Verified `
            -Evidence "Las $($p.Count) directivas están distribuidas correctamente."
    }
    if ($pend.Count -gt 0 -and $ok.Count -eq 0) {
        # Sin ninguna en Success, el valor puede venir de una consulta sin detalle
        return New-PavCtrlResult -Status RequiresValidation -EvidenceLevel NotDeterminable `
            -UnreliableReason 'DistributionStatus solo es concluyente si la consulta empleó -DistributionDetail.' `
            -Evidence "Las $($p.Count) directivas informan distribución pendiente. Verifíquese en el portal si el estado persiste."
    }
    return New-PavCtrlResult -Status PartiallyImplemented -EvidenceLevel Verified `
        -Evidence "$($ok.Count) de $($p.Count) directivas distribuidas; $($pend.Count) pendiente(s): $(($pend | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}
