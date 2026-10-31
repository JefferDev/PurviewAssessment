# Evaluadores del dominio DLP. Mismo contrato que el resto: reciben -Data y
# -Options, devuelven Status + Evidence citando objetos y valores concretos.

function Get-PavDlpSitCategory {
<#
.SYNOPSIS
    Clasifica el texto de un tipo de información sensible en una categoría
    de dato regulado, por coincidencia de términos habituales.
.DESCRIPTION
    Se usa para determinar si el conjunto de reglas cubre datos personales,
    financieros o de salud. La clasificación es indicativa: nombra la
    categoría probable, y la evidencia siempre cita el SIT concreto para que
    el consultor pueda contrastarla.
.OUTPUTS
    [string[]] categorías detectadas: PII, Financiero, Salud.
#>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Position = 0)][AllowNull()][AllowEmptyString()][string]$Text,
        # Términos adicionales por categoría, para tenants cuya nomenclatura no
        # coincida con la habitual: @{ PII = @('titular','beneficiario') }
        [Parameter(Position = 1)][hashtable]$ExtraTerms = @{}
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $t = $Text.ToLowerInvariant()
    $cats = @()

    $pii = 'cedula', 'cédula', 'curp', 'rfc', ' ine', 'ife', 'pasaporte', 'passport', 'dni', 'nie',
           'social security', 'ssn', 'national id', 'identity card', 'identification', 'licencia de conducir',
           'driver', 'nomina', 'nómina', 'payroll', 'employee', 'empleado', 'personal data', 'datos personales',
           'nss', 'seguro social', 'telefono', 'address', 'domicilio'
    $fin = 'credit card', 'tarjeta', 'debit', 'iban', 'swift', 'clabe', 'bank account', 'cuenta bancaria',
           'routing', 'p-card', 'pcard', 'pci', 'financial', 'financiero', 'financiera', 'payment', 'pago',
           'factura', 'invoice', 'contable', 'nomina bancaria'
    $sal = 'health', 'salud', 'medical', 'médic', 'medic', 'hipaa', 'ephi', ' phi', 'diagnos', 'patient',
           'paciente', 'clinic', 'clínic', 'expediente medico', 'seguro medico', 'incapacidad'

    # Términos propios del tenant, si se proporcionaron
    foreach ($cat in @('PII', 'Financiero', 'Salud')) {
        if ($ExtraTerms.ContainsKey($cat)) {
            switch ($cat) {
                'PII'        { $pii += @($ExtraTerms[$cat] | ForEach-Object { "$_".ToLowerInvariant() }) }
                'Financiero' { $fin += @($ExtraTerms[$cat] | ForEach-Object { "$_".ToLowerInvariant() }) }
                'Salud'      { $sal += @($ExtraTerms[$cat] | ForEach-Object { "$_".ToLowerInvariant() }) }
            }
        }
    }
    foreach ($k in $pii) { if ($t -like "*$k*") { $cats += 'PII'; break } }
    foreach ($k in $fin) { if ($t -like "*$k*") { $cats += 'Financiero'; break } }
    foreach ($k in $sal) { if ($t -like "*$k*") { $cats += 'Salud'; break } }
    return @($cats)
}

function Get-PavDlpRuleSits {
    # Texto consolidado de SITs de una regla (árbol avanzado o condición clásica)
    [CmdletBinding()]
    param([Parameter(Position = 0)][object]$Rule)
    $s = "$(Get-PavProp $Rule 'SensitiveInfoTypes' '')"
    if (-not $s) { $s = "$(Get-PavProp $Rule 'ConditionsTree' '')" }
    return $s
}

function Test-PavCtrlDlp01 {
    # SIT personalizados en uso dentro de las reglas.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $rules = @($Data.Rules)
    if ($rules.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron reglas DLP.' }

    # Los SIT se citan por nombre o por GUID segun como se haya construido la
    # regla, por lo que el cruce contempla ambos identificadores.
    $custom = @()
    if ($Options.ContainsKey('SitData') -and $Options.SitData) {
        $custom = @(@($Options.SitData.Entities) | ForEach-Object {
            [pscustomobject]@{ Name = "$($_.Name)"; Id = "$($_.Id)" }
        } | Where-Object { $_.Name -or $_.Id })
    }
    $conSit = @($rules | Where-Object { Get-PavDlpRuleSits $_ })

    if ($conSit.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($rules.Count) reglas DLP declara tipos de información sensible como condición."
    }
    if ($custom.Count -eq 0) {
        return New-PavCtrlResult -Status RequiresValidation -Evidence "$($conSit.Count) de $($rules.Count) reglas usan tipos de información sensible, pero no se recolectó el catálogo de SIT personalizados (carga SIT) para confirmar si son propios de la organización."
    }
    $usados = @()
    foreach ($r in $conSit) {
        $txt = Get-PavDlpRuleSits $r
        foreach ($c in $custom) {
            $etiqueta = if ($c.Name) { $c.Name } else { $c.Id }
            if ($usados -contains $etiqueta) { continue }
            if (($c.Name -and $txt -like "*$($c.Name)*") -or ($c.Id -and $txt -like "*$($c.Id)*")) { $usados += $etiqueta }
        }
    }
    if ($usados.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Las reglas DLP solo emplean tipos integrados: ninguno de los $($custom.Count) SIT personalizados del tenant participa en las condiciones de detección."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "$($usados.Count) de $($custom.Count) SIT personalizados participan en las reglas DLP: $(($usados | Select-Object -First 6) -join ', ')."
}

function Test-PavCtrlDlpCategoria {
    # Motor común de PAV-DLP-02/03/04
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Data,
        [Parameter(Mandatory)][string]$Categoria,
        [Parameter()][switch]$Condicional,
        [Parameter()][hashtable]$Options = @{}
    )
    $rules = @($Data.Rules)
    if ($rules.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron reglas DLP.' }

    $extra = if ($Options -and $Options.ContainsKey('CategoryTerms')) { $Options.CategoryTerms } else { @{} }
    $match = @()
    $clasificadas = 0
    foreach ($r in $rules) {
        $txt = "$(Get-PavDlpRuleSits $r) $($r.RuleName) $($r.PolicyName)"
        $cats = @(Get-PavDlpSitCategory $txt $extra)
        if ($cats.Count -gt 0) { $clasificadas++ }
        if ($cats -contains $Categoria) { $match += $r }
    }
    if ($match.Count -gt 0) {
        $ejemplos = ($match | Select-Object -First 4 | ForEach-Object { "'$($_.PolicyName)' → '$($_.RuleName)'" }) -join '; '
        $activas = @($match | Where-Object { "$($_.Disabled)" -ne 'Sí' })
        if ($activas.Count -eq 0) {
            return New-PavCtrlResult -Status PartiallyImplemented -Evidence "Se detectaron $($match.Count) regla(s) para datos de tipo $Categoria, pero todas están deshabilitadas: $ejemplos."
        }
        return New-PavCtrlResult -Status Implemented -Evidence "$($activas.Count) regla(s) activa(s) cubren datos de tipo ${Categoria}: $ejemplos."
    }
    # Si NINGUNA regla del tenant pudo clasificarse en categoría alguna, la
    # nomenclatura no es interpretable por el diccionario: afirmar que no hay
    # cobertura seria un hallazgo falso.
    if ($clasificadas -eq 0) {
        return New-PavCtrlResult -Status RequiresValidation -Evidence "No fue posible determinar la categoría de dato de ninguna de las $($rules.Count) reglas a partir de su nomenclatura (los tipos de información sensible del tenant no emplean términos reconocibles). La cobertura de datos de tipo $Categoria debe confirmarse con el cliente, o ampliarse el diccionario de términos con -CategoryTerms."
    }
    if ($Condicional) {
        return New-PavCtrlResult -Status RequiresValidation -Evidence "No se detectaron reglas orientadas a datos de tipo $Categoria en las $($rules.Count) reglas evaluadas. Debe confirmarse con el cliente si la organización trata este tipo de dato; de no hacerlo, el control no aplica."
    }
    return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($rules.Count) reglas DLP evaluadas cubre datos de tipo $Categoria."
}

function Test-PavCtrlDlp02 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    Test-PavCtrlDlpCategoria -Data $Data -Categoria 'PII' -Options $Options
}

function Test-PavCtrlDlp03 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    Test-PavCtrlDlpCategoria -Data $Data -Categoria 'Financiero' -Options $Options
}

function Test-PavCtrlDlp04 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})
    # Condicional: la ausencia no es incumplimiento si el negocio no trata datos de salud
    Test-PavCtrlDlpCategoria -Data $Data -Categoria 'Salud' -Condicional -Options $Options
}

function Test-PavCtrlDlp05 {
    # Modo de aplicación frente a modo de prueba.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $pols = @($Data.Policies | Where-Object { "$($_.Enabled)" -eq 'True' })
    if ($pols.Count -eq 0) {
        $total = @($Data.Policies).Count
        if ($total -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron directivas DLP.' }
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $total directivas DLP está habilitada."
    }
    $enforce = @($pols | Where-Object { "$($_.Mode)" -eq 'Enable' })
    $test    = @($pols | Where-Object { "$($_.Mode)" -match 'Test|Audit' })

    if ($enforce.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($pols.Count) directivas habilitadas operan en modo de prueba o auditoría, sin aplicar restricción alguna: $(($test | Select-Object -First 5 | ForEach-Object { "'$($_.Name)' [$($_.Mode)]" }) -join ', ')."
    }
    if ($test.Count -gt 0) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($enforce.Count) de $($pols.Count) directivas habilitadas aplican restricciones; $($test.Count) permanecen en prueba o auditoría: $(($test | Select-Object -First 5 | ForEach-Object { "'$($_.Name)'" }) -join ', ')."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Las $($enforce.Count) directivas habilitadas operan en modo de aplicación."
}

function Test-PavCtrlDlp06 {
    # Cobertura por carga de trabajo.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $pols = @($Data.Policies | Where-Object { "$($_.Enabled)" -eq 'True' })
    if ($pols.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay directivas DLP habilitadas que evaluar.' }

    $cargas = [ordered]@{
        'Exchange'   = 'ExchangeLocation'
        'SharePoint' = 'SharePointLocation'
        'OneDrive'   = 'OneDriveLocation'
        'Teams'      = 'TeamsLocation'
        'Endpoint'   = 'EndpointDlpLocation'
    }
    $cubiertas = @(); $sin = @()
    foreach ($c in $cargas.GetEnumerator()) {
        $conCarga = @($pols | Where-Object { $v = "$(Get-PavProp $_ $c.Value '')"; $v -and $v -ne 'No' })
        if ($conCarga.Count -gt 0) { $cubiertas += "$($c.Key) ($($conCarga.Count))" } else { $sin += $c.Key }
    }
    if ($cubiertas.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Las $($pols.Count) directivas habilitadas no declaran ubicación en ninguna de las cargas evaluadas."
    }
    if ($sin.Count -gt 0) {
        $sev = if ($sin -contains 'Exchange') { 'Alta' } else { 'Media' }
        return New-PavCtrlResult -Status PartiallyImplemented -Severity $sev -Evidence "Cubiertas: $($cubiertas -join ', '). Sin directiva habilitada: $($sin -join ', ')."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "Las cinco cargas evaluadas tienen directiva habilitada: $($cubiertas -join ', ')."
}

function Test-PavCtrlDlp07 {
    # Acciones de bloqueo o restricción.
    #
    # La unidad de medida es la DIRECTIVA, no la regla. Un diseño maduro de DLP
    # estratifica las reglas por confianza (por ejemplo _High / _Medium / _Low):
    # el escalón de alta confianza bloquea y los inferiores notifican o auditan.
    # Medir el porcentaje de reglas con bloqueo penalizaría ese diseño correcto.
    #
    # El bloqueo se reconoce en cualquiera de sus formas: BlockAccess en cargas
    # de Microsoft 365, restricciones de punto de conexión (impresión, USB,
    # portapapeles), restricciones de aplicaciones —incluidas las que atajan el
    # envío de contenido a Copilot— cuarentena o cifrado.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $rules = @($Data.Rules | Where-Object { "$($_.Disabled)" -ne 'Sí' })
    if ($rules.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay reglas DLP activas que evaluar.' }

    $tieneBloqueo = {
        param($r)
        if ("$(Get-PavProp $r 'HasBlockingAction' '')" -eq 'Sí') { return $true }
        # Compatibilidad con datos recolectados antes de v1.5.1
        return (
            "$(Get-PavProp $r 'BlockAccess' '')" -in @('Sí', 'True') -or
            "$(Get-PavProp $r 'RestrictBrowserAccess' '')" -in @('Sí', 'True') -or
            "$(Get-PavProp $r 'Quarantine' '')" -in @('Sí', 'True') -or
            [bool]"$(Get-PavProp $r 'EncryptRMSTemplate' '')" -or
            [bool]"$(Get-PavProp $r 'EndpointBlockedActions' '')" -or
            [bool]"$(Get-PavProp $r 'AppBlockedActions' '')"
        )
    }

    $conBloqueo = @($rules | Where-Object { & $tieneBloqueo $_ })
    if ($conBloqueo.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($rules.Count) reglas activas aplica bloqueo, restricción de punto de conexión o de aplicaciones, cuarentena ni cifrado: la detección no impide la acción del usuario."
    }

    # Cobertura por directiva: se considera cubierta si tiene al menos un
    # escalón de bloqueo entre sus reglas activas.
    $porDirectiva = @($rules | Group-Object PolicyName)
    $cubiertas = @($porDirectiva | Where-Object { @($_.Group | Where-Object { & $tieneBloqueo $_ }).Count -gt 0 })
    $sinCubrir = @($porDirectiva | Where-Object { $_ -notin $cubiertas })

    $ejemplos = ($conBloqueo | Select-Object -First 4 | ForEach-Object {
        $m = "$(Get-PavProp $_ 'BlockingSummary' '')"
        if (-not $m) { $m = 'bloqueo' }
        "'$($_.RuleName)' ($m)"
    }) -join '; '

    if ($sinCubrir.Count -eq 0) {
        return New-PavCtrlResult -Status Implemented -Evidence "Las $($porDirectiva.Count) directivas con reglas activas tienen al menos un escalón de bloqueo. $($conBloqueo.Count) de $($rules.Count) reglas aplican restricción. Ejemplos: $ejemplos."
    }

    $pct = [math]::Round(($cubiertas.Count / $porDirectiva.Count) * 100)
    $listaSin = ($sinCubrir | Select-Object -First 6 | ForEach-Object { "'$($_.Name)'" }) -join ', '
    $status = if ($pct -ge 50) { 'PartiallyImplemented' } else { 'NotImplemented' }
    return New-PavCtrlResult -Status $status -Evidence "$($cubiertas.Count) de $($porDirectiva.Count) directivas con reglas activas ($pct%) aplican bloqueo en algún escalón; $($conBloqueo.Count) de $($rules.Count) reglas lo aplican. Ejemplos con bloqueo: $ejemplos. Directivas que solo detectan: $listaSin."
}

function Test-PavCtrlDlp08 {
    # Notificación al usuario.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $rules = @($Data.Rules | Where-Object { "$($_.Disabled)" -ne 'Sí' })
    if ($rules.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay reglas DLP activas que evaluar.' }

    $notif = @($rules | Where-Object { "$(Get-PavProp $_ 'NotifyUser' '')" -or "$(Get-PavProp $_ 'NotifyEndpointUser' '')" })
    $tip   = @($rules | Where-Object { "$(Get-PavProp $_ 'NotifyPolicyTipCustomText' '')" })

    if ($notif.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($rules.Count) reglas activas notifica al usuario cuando su acción vulnera la directiva."
    }
    if ($tip.Count -eq 0) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($notif.Count) de $($rules.Count) reglas notifican al usuario, pero ninguna personaliza el texto de la sugerencia de directiva, que es lo que explica al usuario qué hacer."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "$($notif.Count) de $($rules.Count) reglas notifican al usuario y $($tip.Count) personalizan el texto de la sugerencia de directiva."
}

function Test-PavCtrlDlp09 {
    # Alertas e informes de incidente.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $rules = @($Data.Rules | Where-Object { "$($_.Disabled)" -ne 'Sí' })
    if ($rules.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No hay reglas DLP activas que evaluar.' }

    $alert = @($rules | Where-Object { "$(Get-PavProp $_ 'GenerateAlert' '')" })
    $inc   = @($rules | Where-Object { "$(Get-PavProp $_ 'GenerateIncidentReport' '')" })
    $sev   = @($rules | Where-Object { "$(Get-PavProp $_ 'ReportSeverityLevel' '')" })

    if ($alert.Count -eq 0 -and $inc.Count -eq 0) {
        return New-PavCtrlResult -Status NotImplemented -Evidence "Ninguna de las $($rules.Count) reglas activas genera alertas ni informes de incidente."
    }
    if ($alert.Count -eq 0 -or $inc.Count -eq 0) {
        return New-PavCtrlResult -Status PartiallyImplemented -Evidence "$($alert.Count) regla(s) generan alerta y $($inc.Count) generan informe de incidente, de $($rules.Count) activas."
    }
    return New-PavCtrlResult -Status Implemented -Evidence "$($alert.Count) de $($rules.Count) reglas activas generan alerta, $($inc.Count) generan informe de incidente y $($sev.Count) declaran nivel de severidad."
}

function Test-PavCtrlDlp10 {
    # Higiene del inventario: directivas inertes u obsoletas.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Data, [Parameter()][hashtable]$Options = @{})

    $pols = @($Data.Policies)
    if ($pols.Count -eq 0) { return New-PavCtrlResult -Status RequiresValidation -Evidence 'No se recolectaron directivas DLP.' }

    $umbral = if ($Options.ContainsKey('StaleDays')) { [int]$Options.StaleDays } else { 365 }
    $hoy = Get-Date
    $deshabilitadas = @($pols | Where-Object { "$($_.Enabled)" -ne 'True' })
    $obsoletas = @()
    foreach ($p in $pols) {
        [datetime]$f = [datetime]::MinValue
        if (-not [datetime]::TryParse("$($p.WhenChanged)", [ref]$f)) { continue }
        $dias = [int]($hoy - $f).TotalDays
        if ($dias -gt $umbral) { $obsoletas += [pscustomobject]@{ Name = $p.Name; Days = $dias; Enabled = $p.Enabled } }
    }
    $inertes = @($deshabilitadas | Where-Object { $o = $_; $obsoletas | Where-Object { $_.Name -eq $o.Name } })

    if ($deshabilitadas.Count -eq 0 -and $obsoletas.Count -eq 0) {
        return New-PavCtrlResult -Status Implemented -Evidence "Las $($pols.Count) directivas están habilitadas y se han modificado dentro de los últimos $umbral días."
    }
    $detalle = @()
    if ($deshabilitadas.Count) { $detalle += "$($deshabilitadas.Count) deshabilitada(s): $(($deshabilitadas | Select-Object -First 5 | ForEach-Object { "'$($_.Name)'" }) -join ', ')" }
    if ($obsoletas.Count) { $detalle += "$($obsoletas.Count) sin modificar en más de $umbral días: $(($obsoletas | Sort-Object Days -Descending | Select-Object -First 5 | ForEach-Object { "'$($_.Name)' ($($_.Days) d)" }) -join ', ')" }

    # Deshabilitada y obsoleta a la vez: inventario inerte, el caso más severo
    if ($inertes.Count -gt 0) {
        return New-PavCtrlResult -Status NotImplemented -Severity 'Media' -Evidence "$($inertes.Count) directiva(s) están deshabilitadas y sin mantenimiento, por lo que figuran en el inventario sin aportar protección. $($detalle -join '. ')."
    }
    return New-PavCtrlResult -Status PartiallyImplemented -Evidence ($detalle -join '. ')
}
