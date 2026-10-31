# Evaluadores del dominio de ciclo de vida de los datos.

function Test-PavCtrlDlm01 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $p = @($Data.Policies)
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence 'No existen directivas de retención en el tenant.' }
    $hab = @($p | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($hab.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($p.Count) directivas de retención existentes están deshabilitadas."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "$($hab.Count) de $($p.Count) directivas de retención habilitadas: $(($hab | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}

function Test-PavCtrlDlm02 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $locs = @($Data.PolicyLocations | Where-Object { "$($_.Coverage)" -ne 'No configurado' })
    if (@($Data.Policies).Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay directivas de retención que evaluar.' }
    # Superficies evaluadas. Los canales privados de Teams NO se evalúan por
    # separado: desde su consolidación quedan cubiertos por la directiva de
    # mensajes de canal, y comprobarlos aparte produciría un falso negativo.
    $principales = 'Exchange', 'SharePoint', 'OneDrive', 'Teams Chat', 'Teams Channel', 'Grupos M365'
    $cubiertas = @(); $sin = @()
    foreach ($c in $principales) {
        if (@($locs | Where-Object { "$($_.Workload)" -eq $c }).Count -gt 0) { $cubiertas += $c } else { $sin += $c }
    }
    # Teams se considera cubierto si alguna de sus dos superficies lo está;
    # se informa la que falte, sin contarla como carga descubierta completa.
    $teamsParcial = ($cubiertas -match '^Teams').Count -gt 0 -and ($sin -match '^Teams').Count -gt 0
    if ($cubiertas.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las cargas principales tiene directiva de retención con alcance configurado: $($principales -join ', ')."
    }
    if ($sin.Count -gt 0) {
        $nota = if ($teamsParcial) { ' Una de las dos superficies de Teams sí está cubierta.' } else { '' }
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "Con retención: $($cubiertas -join ', '). Sin alcance configurado: $($sin -join ', ').$nota"
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Las $($principales.Count) superficies evaluadas tienen alcance de retención configurado: $($cubiertas -join ', ')."
}

function Test-PavCtrlDlm03 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $t = @($Data.Tags)
    if ($t.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence 'No existen etiquetas de retención definidas: la conservación no puede diferenciarse por tipo documental.' }
    return New-PavCtrlResult -Status Implemented -Evidence "$($t.Count) etiqueta(s) de retención definidas: $(($t | Select-Object -First 5 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}

function Test-PavCtrlDlm04 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $t = @($Data.Tags); $r = @($Data.Rules)
    if ($t.Count -eq 0 -and $r.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron etiquetas ni reglas de retención.' }
    $elimT = @($t | Where-Object { "$($_.RetentionAction)" -match 'elimin' })
    $elimR = @($r | Where-Object { "$($_.RetentionAction)" -match 'elimin' })
    $total = $elimT.Count + $elimR.Count
    if ($total -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($t.Count) etiqueta(s) ni de las $($r.Count) regla(s) elimina contenido al vencer: la política solo conserva, sin cierre del ciclo de vida."
    }
    $ej = @(@($elimT | ForEach-Object { "'$($_.Name)'" }) + @($elimR | ForEach-Object { "'$($_.RuleName)'" })) | Select-Object -First 4
    return New-PavCtrlResult -Status Implemented -Evidence "$total elemento(s) eliminan contenido al vencer su periodo: $($ej -join ', ')."
}

function Test-PavCtrlDlm05 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $p = @($Data.Policies | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay directivas de retención habilitadas que evaluar.' }
    $sim = @($p | Where-Object { "$($_.Mode)" -match 'Simulaci' })
    if ($sim.Count -eq $p.Count) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($p.Count) directivas habilitadas operan en simulación: no conservan ni eliminan contenido."
    }
    if ($sim.Count -gt 0) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($sim.Count) de $($p.Count) directivas permanecen en simulación: $(($sim | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Las $($p.Count) directivas habilitadas operan en modo de aplicación."
}

function Test-PavCtrlDlm06 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $p = @($Data.Policies)
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay directivas de retención que evaluar.' }
    $ad = @($p | Where-Object { "$($_.IsAdaptivePolicy)" -in @('True', 'Sí') })
    if ($ad.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($p.Count) directivas usa ámbito adaptativo: el alcance debe mantenerse manualmente conforme cambia la organización."
    }
    if ($ad.Count -lt $p.Count) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($ad.Count) de $($p.Count) directivas usan ámbito adaptativo: $(($ad | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Las $($p.Count) directivas usan ámbito adaptativo."
}

function Test-PavCtrlDlm07 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $p = @($Data.Policies | Where-Object { "$($_.Enabled)" -in @('True', 'Sí') })
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay directivas de retención habilitadas que evaluar.' }
    $lock = @($p | Where-Object { "$($_.RestrictiveRetention)" -in @('True', 'Sí') })
    if ($lock.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($p.Count) directivas habilitadas tiene bloqueo de preservación: pueden modificarse o eliminarse por un administrador."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "$($lock.Count) de $($p.Count) directivas habilitadas tienen bloqueo de preservación: $(($lock | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}

function Test-PavCtrlDlm08 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $t = @($Data.Tags)
    if ($t.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay etiquetas de retención que evaluar.' }
    $porTipo = @($t | Group-Object RetentionType)
    $soloCreacion = @($t | Where-Object { "$($_.RetentionType)" -match 'creación|creacion' })
    $detalle = ($porTipo | ForEach-Object { "$($_.Name): $($_.Count)" }) -join '; '
    if ($soloCreacion.Count -eq $t.Count) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "Las $($t.Count) etiquetas computan su periodo desde la creación del contenido. Conviene verificar si algún tipo documental exige contar desde la última modificación, el etiquetado o un evento de negocio."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Los periodos se computan desde distintos hechos según el tipo documental: $detalle."
}

function Test-PavCtrlDlm09 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $p = @($Data.Policies)
    if ($p.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay directivas de retención que evaluar.' }
    $umbral = if ($Options.ContainsKey('StaleDays')) { [int]$Options.StaleDays } else { 365 }
    $hoy = Get-Date; $viejas = @(); $sinFecha = 0
    foreach ($x in $p) {
        [datetime]$f = [datetime]::MinValue
        if (-not [datetime]::TryParse("$($x.LastModifiedUtc)", [ref]$f)) { $sinFecha++; continue }
        $d = [int]($hoy - $f).TotalDays
        if ($d -gt $umbral) { $viejas += [pscustomobject]@{ Name = $x.Name; Days = $d } }
    }
    if ($sinFecha -eq $p.Count) { return New-PavCtrlResult -Status RequiresValidation -Evidence "No se pudo determinar la fecha de última modificación de las $($p.Count) directivas." }
    if ($viejas.Count -eq 0) { return New-PavCtrlResult -Status Implemented -Evidence "Las $($p.Count) directivas se han modificado dentro de los últimos $umbral días." }
    $st = if ($viejas.Count -eq $p.Count) { 'NotImplemented' } else { 'PartiallyImplemented' }
    return New-PavCtrlResult -Status $st -Evidence "$($viejas.Count) de $($p.Count) directivas superan $umbral días sin modificación: $(($viejas | Sort-Object Days -Descending | Select-Object -First 4 | ForEach-Object { "'$($_.Name)' ($($_.Days) d)" }) -join ', ')."
}
