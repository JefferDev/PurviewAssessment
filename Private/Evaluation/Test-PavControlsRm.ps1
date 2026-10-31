# Evaluadores del dominio de gestión de registros.

function Test-PavCtrlRm01 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $tags = @($Data.RecordTags)
    if ($tags.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence 'No existe ninguna etiqueta que declare el contenido como registro: las etiquetas de retención conservan el contenido pero no lo hacen inmutable.'
    }
    return New-PavCtrlResult -Status Implemented -Evidence "$($tags.Count) etiqueta(s) declaran contenido como registro: $(($tags | Select-Object -First 5 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}

function Test-PavCtrlRm02 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $tags = @($Data.RecordTags)
    if ($tags.Count -eq 0) { return New-PavCtrlResult -Status NotApplicable -Evidence 'No hay etiquetas de registro, por lo que la distinción entre regulado y ordinario no aplica (ver PAV-RM-01).' }
    $reg = @($tags | Where-Object { "$($_.Regulatory)" -in @('True', 'Sí') })
    if ($reg.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($tags.Count) etiquetas de registro son de tipo ordinario: ninguna se declara como registro regulado, por lo que un administrador puede retirarlas o acortar su periodo."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "$($reg.Count) de $($tags.Count) etiquetas son registros regulados: $(($reg | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}

function Test-PavCtrlRm03 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $props = @($Data.FilePlanProperties)
    if ($props.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence 'No hay descriptores de plan de archivos definidos (departamento, categoría, autoridad, citación ni identificador de referencia).'
    }
    $tipos = @($props | Group-Object Type)
    $detalle = ($tipos | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', '
    # Un plan mínimo requiere al menos categoría o departamento, y una autoridad o citación
    $tieneClasif = @($props | Where-Object { $_.Type -in @('Category', 'Department', 'SubCategory') }).Count -gt 0
    $tieneFundamento = @($props | Where-Object { $_.Type -in @('Authority', 'Citation') }).Count -gt 0
    if ($tieneClasif -and $tieneFundamento) {
        return New-PavCtrlResult -Status Implemented -Evidence "$($props.Count) descriptores definidos en $($tipos.Count) tipo(s): $detalle."
    }
    $falta = @()
    if (-not $tieneClasif)     { $falta += 'clasificación (categoría o departamento)' }
    if (-not $tieneFundamento) { $falta += 'fundamento (autoridad o citación)' }
    return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($props.Count) descriptores definidos ($detalle), pero falta $($falta -join ' y ')."
}

function Test-PavCtrlRm04 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $cit = @($Data.FilePlanProperties | Where-Object Type -eq 'Citation')
    if ($cit.Count -eq 0) { return New-PavCtrlResult -Status NotImplemented -Evidence 'No hay citaciones definidas en el plan de archivos: los periodos de conservación no se vinculan a ninguna norma.' }
    $sinRef = @($cit | Where-Object { -not $_.HasCitationDetail })
    if ($sinRef.Count -eq 0) {
        return New-PavCtrlResult -Status Implemented -Evidence "Las $($cit.Count) citaciones declaran referencia normativa o jurisdicción: $(($cit | Select-Object -First 3 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    if ($sinRef.Count -eq $cit.Count) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($cit.Count) citaciones declara URL ni jurisdicción: $(($sinRef | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($sinRef.Count) de $($cit.Count) citaciones no declaran referencia normativa: $(($sinRef | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}

function Test-PavCtrlRm05 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $tags = @($Data.RecordTags)
    if ($tags.Count -eq 0) { return New-PavCtrlResult -Status NotApplicable -Evidence 'No hay etiquetas de registro que evaluar (ver PAV-RM-01).' }
    $con = @($tags | Where-Object { "$($_.HasFilePlan)" -in @('True', 'Sí') })
    if ($con.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($tags.Count) etiquetas de registro tiene descriptores de plan de archivos asignados."
    }
    if ($con.Count -lt $tags.Count) {
        $sin = @($tags | Where-Object { "$($_.HasFilePlan)" -notin @('True', 'Sí') })
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($con.Count) de $($tags.Count) etiquetas de registro tienen plan de archivos. Sin asignar: $(($sin | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Las $($tags.Count) etiquetas de registro tienen descriptores de plan de archivos asignados."
}

function Test-PavCtrlRm06 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $ev = @($Data.EventTypes)
    if ($ev.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence 'No hay tipos de evento de retención definidos: todos los plazos se computan desde la creación o modificación del contenido.'
    }
    $inst = @($Data.Events).Count
    return New-PavCtrlResult -Status Implemented -Evidence "$($ev.Count) tipo(s) de evento definidos ($inst evento(s) registrados): $(($ev | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}

function Test-PavCtrlRm07 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $ev = @($Data.EventTypes)
    if ($ev.Count -eq 0) { return New-PavCtrlResult -Status NotApplicable -Evidence 'No hay tipos de evento definidos (ver PAV-RM-06).' }
    $huerfanos = @($ev | Where-Object { [int]"$($_.LinkedLabelCount)" -eq 0 })
    if ($huerfanos.Count -eq 0) {
        return New-PavCtrlResult -Status Implemented -Evidence "Los $($ev.Count) tipos de evento tienen etiquetas asociadas."
    }
    if ($huerfanos.Count -eq $ev.Count) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguno de los $($ev.Count) tipos de evento tiene etiquetas asociadas: no disparan el cómputo de ningún periodo. Afectados: $(($huerfanos | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($huerfanos.Count) de $($ev.Count) tipos de evento no tienen etiquetas asociadas: $(($huerfanos | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
}

function Test-PavCtrlRm08 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $tags = @($Data.RecordTags)
    if ($tags.Count -eq 0) { return New-PavCtrlResult -Status NotApplicable -Evidence 'No hay etiquetas de registro que evaluar (ver PAV-RM-01).' }
    # Solo exigible a las etiquetas que eliminan contenido al vencer
    $eliminan = @($tags | Where-Object { "$($_.RetentionAction)" -match 'elimin' })
    if ($eliminan.Count -eq 0) {
        return New-PavCtrlResult -Status NotApplicable -Evidence "Ninguna de las $($tags.Count) etiquetas de registro elimina contenido al vencer la retención, por lo que la revisión de disposición no aplica."
    }
    $conRev = @($eliminan | Where-Object { "$($_.HasReviewStages)" -in @('True', 'Sí') })
    if ($conRev.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($eliminan.Count) etiquetas que eliminan contenido lo hacen sin revisión de disposición previa: $(($eliminan | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    if ($conRev.Count -lt $eliminan.Count) {
        $sin = @($eliminan | Where-Object { "$($_.HasReviewStages)" -notin @('True', 'Sí') })
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($conRev.Count) de $($eliminan.Count) etiquetas con eliminación tienen revisión de disposición. Sin revisión: $(($sin | Select-Object -First 4 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Las $($eliminan.Count) etiquetas que eliminan contenido tienen revisión de disposición configurada."
}

function Test-PavCtrlRm09 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    $tags = @($Data.RecordTags)
    if ($tags.Count -eq 0) { return New-PavCtrlResult -Status NotApplicable -Evidence 'No hay etiquetas de registro que evaluar (ver PAV-RM-01).' }
    # La aplicación automática se evidencia por vínculo a evento o por regla de auto-aplicación
    $auto = @($tags | Where-Object { "$($_.EventTypeId)" })
    if ($auto.Count -eq 0) {
        return New-PavCtrlResult -Status RequiresValidation -Evidence "Ninguna de las $($tags.Count) etiquetas de registro muestra vínculo a un tipo de evento. La aplicación automática mediante reglas de auto-aplicación debe confirmarse en el portal, ya que no es visible en los datos recolectados."
    }
    return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($auto.Count) de $($tags.Count) etiquetas de registro se vinculan a un tipo de evento. La existencia de reglas de auto-aplicación debe confirmarse en el portal."
}
