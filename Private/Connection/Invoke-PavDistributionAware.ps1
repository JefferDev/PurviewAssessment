function Invoke-PavDistributionAware {
<#
.SYNOPSIS
    Invoca un cmdlet de directivas solicitando el detalle de distribución, y
    recurre a la llamada simple si el cmdlet no admite el modificador.
.DESCRIPTION
    Sin -DistributionDetail, la propiedad DistributionStatus devuelve
    'Pending' incluso en directivas plenamente distribuidas, y las
    propiedades de ubicación pueden ser inexactas. Comprobado en tenant:
    la misma directiva devuelve 'Pending' sin el modificador y 'Success'
    con él.

    La llamada es más lenta, por lo que se usa solo donde el estado de
    distribución o las ubicaciones importan.

    Admiten el modificador (verificado en tenant con
    ExchangeOnlineManagement 3.x): Get-DlpCompliancePolicy,
    Get-AutoSensitivityLabelPolicy, Get-RetentionCompliancePolicy,
    Get-AppRetentionCompliancePolicy, Get-CaseHoldPolicy y
    Get-InsiderRiskPolicy.

    NO lo admiten: Get-LabelPolicy, Get-SupervisoryReviewPolicyV2 y
    Get-UnifiedAuditLogRetentionPolicy; esos se invocan de forma directa y
    su DistributionStatus, cuando existe, no es concluyente.

    La comprobación sigue siendo en tiempo de ejecución porque el soporte
    puede variar entre versiones del módulo. Get-PavDistributionSupport
    informa del estado en la sesión actual.
.PARAMETER CmdletName
    Nombre del cmdlet a invocar.
.PARAMETER Arguments
    Argumentos adicionales (por ejemplo @{ Identity = 'X' }).
.OUTPUTS
    Los objetos devueltos por el cmdlet.
.EXAMPLE
    Invoke-PavDistributionAware -CmdletName 'Get-DlpCompliancePolicy'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$CmdletName,
        [Parameter(Position = 1)][hashtable]$Arguments = @{}
    )

    $cmd = Get-Command $CmdletName -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "El cmdlet '$CmdletName' no está disponible en esta sesión." }

    $p = @{} + $Arguments
    $p['ErrorAction'] = 'Stop'

    if ($cmd.Parameters.ContainsKey('DistributionDetail')) {
        try {
            $p['DistributionDetail'] = $true
            # El servicio advierte que sin Identity el estado puede no ser
            # exacto; Resolve-PavDistributionStatus lo confirma después sobre
            # las directivas cuyo estado no sea 'Success'.
            if (-not $p.ContainsKey('Identity') -and -not $script:PavDistribWarned) {
                Write-PavLog -Level Info -Message 'El estado de distribución obtenido del listado se confirmará por identidad en las directivas que no reporten Success.'
                $script:PavDistribWarned = $true
            }
            return & $CmdletName @p
        }
        catch {
            Write-PavLog -Level Info -Message "  - $CmdletName con -DistributionDetail falló ($($_.Exception.Message)); se reintenta sin el modificador. El estado de distribución no será concluyente."
            $p.Remove('DistributionDetail')
        }
    }
    & $CmdletName @p
}

function Get-PavDistributionSupport {
<#
.SYNOPSIS
    Informa qué cmdlets de la sesión admiten -DistributionDetail.
.DESCRIPTION
    El soporte del modificador varía entre cmdlets y entre versiones del
    módulo ExchangeOnlineManagement. Esta función lo comprueba en la sesión
    actual, para no depender de suposiciones.
.OUTPUTS
    [pscustomobject[]] con Cmdlet, Disponible y AdmiteDistributionDetail.
.EXAMPLE
    Get-PavDistributionSupport | Format-Table -AutoSize
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $lista = 'Get-DlpCompliancePolicy', 'Get-LabelPolicy', 'Get-AutoSensitivityLabelPolicy',
             'Get-RetentionCompliancePolicy', 'Get-AppRetentionCompliancePolicy', 'Get-CaseHoldPolicy',
             'Get-SupervisoryReviewPolicyV2', 'Get-InsiderRiskPolicy', 'Get-UnifiedAuditLogRetentionPolicy'

    @($lista | ForEach-Object {
        $c = Get-Command $_ -ErrorAction SilentlyContinue
        [pscustomobject]@{
            PSTypeName = 'PurviewAssessment.DistributionSupport'
            Cmdlet     = $_
            Disponible = [bool]$c
            AdmiteDistributionDetail = if ($c) { $c.Parameters.ContainsKey('DistributionDetail') } else { $null }
        }
    })
}

function Resolve-PavDistributionStatus {
<#
.SYNOPSIS
    Confirma el estado de distribución consultando cada directiva por
    identidad, que es la única forma exacta de obtenerlo.
.DESCRIPTION
    El propio servicio advierte que el estado de distribución puede no ser
    exacto si no se especifica Identity junto con DistributionDetail. Como
    esa consulta es costosa, solo se realiza sobre las directivas cuyo
    estado NO es 'Success' en el listado: un 'Success' del listado no
    presenta el falso negativo documentado, mientras que un 'Pending' sí
    puede serlo.

    Actualiza la propiedad DistributionStatus de los objetos recibidos y
    devuelve el número de directivas confirmadas.
.PARAMETER Policies
    Objetos crudos devueltos por el listado.
.PARAMETER CmdletName
    Cmdlet con el que reconsultar.
.PARAMETER MaxQueries
    Límite de consultas individuales, para acotar el tiempo en tenants con
    muchas directivas. Por defecto 25.
.OUTPUTS
    [int] número de directivas reconsultadas.
#>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Policies,
        [Parameter(Mandatory)][string]$CmdletName,
        [Parameter()][int]$MaxQueries = 25
    )

    if ($script:PavSkipDistribution) { return 0 }
    $cmd = Get-Command $CmdletName -ErrorAction SilentlyContinue
    if (-not $cmd -or -not $cmd.Parameters.ContainsKey('DistributionDetail')) { return 0 }

    $dudosas = @($Policies | Where-Object { "$(Get-PavProp $_ 'DistributionStatus' '')" -ne 'Success' })
    if ($dudosas.Count -eq 0) { return 0 }

    if ($dudosas.Count -gt $MaxQueries) {
        Write-PavLog -Level Info -Message "  > $($dudosas.Count) directiva(s) sin estado 'Success'; se confirmarán las primeras $MaxQueries por identidad."
        $dudosas = @($dudosas | Select-Object -First $MaxQueries)
    }

    $n = 0
    foreach ($pol in $dudosas) {
        $ident = "$(Get-PavProp $pol 'Identity' (Get-PavProp $pol 'Name' ''))"
        if (-not $ident) { continue }
        try {
            $full = & $CmdletName -Identity $ident -DistributionDetail -ErrorAction Stop
            $st = "$(Get-PavProp $full 'DistributionStatus' '')"
            if ($st) {
                $pol | Add-Member -NotePropertyName DistributionStatus -NotePropertyValue $st -Force
                $n++
            }
        }
        catch { Write-Verbose "Estado de distribución de '$ident' no confirmado: $($_.Exception.Message)" }
    }
    if ($n -gt 0) { Write-PavLog -Level Info -Message "  > Estado de distribución confirmado por identidad en $n directiva(s)." }
    return $n
}
