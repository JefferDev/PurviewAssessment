# Modelo de nivel de evidencia y catálogo de propiedades no fiables.
#
# Eje ortogonal al estado del control: el estado responde "¿está
# implementado?"; el nivel de evidencia, "¿con qué calidad de información
# lo sé?".
#
#   Verified         Hay evidencia de operación (actividad, coincidencias).
#   Configured       El objeto existe y está configurado, sin evidencia de
#                    que esté operando.
#   NotDeterminable  La propiedad no es fiable por esta vía, falta permiso o
#                    no hay volumen suficiente.
#
# REGLA: ningún control puede emitir 'NotImplemented' apoyándose en una
# propiedad de este catálogo, ni en el resultado vacío de un cmdlet que
# filtra en silencio por falta de rol.

$script:PavUnreliableProperties = @(
    # DistributionStatus solo es fiable si la consulta usó -DistributionDetail.
    # El módulo lo solicita donde el cmdlet lo admite, por lo que el valor es
    # concluyente salvo en los tres cmdlets que no lo soportan.
    @{ Property = 'DistributionStatus'
       Cmdlets  = @('Get-LabelPolicy', 'Get-SupervisoryReviewPolicyV2', 'Get-UnifiedAuditLogRetentionPolicy')
       Motivo   = "Estos cmdlets no admiten -DistributionDetail, por lo que devuelven 'Pending' sin reflejar el estado real de distribución." }
    @{ Property = 'DistributionResults'; Cmdlets = @('Get-RetentionCompliancePolicy')
       Motivo   = 'Documentada como poco fiable y propensa a errores.' }
    @{ Property = 'ProvisionStatus'; Cmdlets = @('Get-SupervisoryReviewPolicyV2')
       Motivo   = "Devuelve 'NotStarted' en directivas que el portal muestra activas y con coincidencias acumuladas: refleja una marca de inicialización, no el estado operativo." }
    @{ Property = 'PolicyStatus'; Cmdlets = @('Get-SupervisoryReviewPolicyV2')
       Motivo   = "Permanece en 'Activating' en directivas plenamente operativas." }
    @{ Property = 'ExchangeLocation'; Cmdlets = @('Get-CaseHoldPolicy')
       Motivo   = "Devuelve 'No' aunque el portal muestre ubicaciones en retención: los orígenes de datos se asocian al caso, no a la directiva." }
    @{ Property = 'TeamsChatLocation'; Cmdlets = @('Get-AppRetentionCompliancePolicy')
       Motivo   = 'Las directivas de aplicaciones declaran su cobertura en la propiedad Applications.' }
    @{ Property = 'SimulationItemsMatched'; Cmdlets = @('Get-AutoSensitivityLabelPolicy')
       Motivo   = 'El listado devuelve cero aunque la simulación haya procesado miles de elementos; requiere consulta por identidad.' }
    @{ Property = 'ContentContainsSensitiveInformation'; Cmdlets = @('Get-DlpComplianceRule')
       Motivo   = 'Vacía cuando la regla usa AdvancedRule: los tipos de información sensible residen en el JSON de la regla.' }
)

function Get-PavUnreliableReason {
<#
.SYNOPSIS
    Motivo por el que una propiedad no es fiable; cadena vacía si no está catalogada.
.PARAMETER Property
    Nombre de la propiedad.
.PARAMETER Cmdlet
    Cmdlet de origen (opcional).
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Property,
        [Parameter(Position = 1)][string]$Cmdlet
    )
    foreach ($e in $script:PavUnreliableProperties) {
        if ($e.Property -ne $Property) { continue }
        if ($Cmdlet -and $e.Cmdlets -notcontains $Cmdlet) { continue }
        return "$($e.Motivo)"
    }
    return ''
}

function Get-PavUnreliablePropertyList {
<#
.SYNOPSIS
    Catálogo completo de propiedades no fiables.
#>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    @($script:PavUnreliableProperties | ForEach-Object {
        [pscustomobject]@{ PSTypeName = 'PurviewAssessment.UnreliableProperty'
            Property = $_.Property; Cmdlets = ($_.Cmdlets -join '; '); Motivo = $_.Motivo }
    })
}

function ConvertTo-PavEvidenceLevelText {
<#
.SYNOPSIS
    Texto del nivel de evidencia para el informe.
#>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Position = 0)][AllowNull()][string]$Level)
    switch ("$Level") {
        'Verified'        { 'Verificado' }
        'NotDeterminable' { 'No determinable' }
        default           { 'Configurado' }
    }
}
