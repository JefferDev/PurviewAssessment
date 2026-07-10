function Assert-PavModule {
<#
.SYNOPSIS
    Verifica que un módulo dependiente esté instalado en la versión mínima.
.DESCRIPTION
    Unifica Ensure-Module / Ensure-ImportExcel / Assert-RequiredModules /
    Assert-EXOModuleVersion de los scripts originales, con verbo aprobado.
    En modo -Optional degrada a advertencia y devuelve $false en lugar de
    lanzar excepción (p. ej. ImportExcel: el informe HTML no lo requiere).
.PARAMETER Name
    Nombre del módulo (p. ej. ExchangeOnlineManagement).
.PARAMETER MinimumVersion
    Versión mínima exigida.
.PARAMETER Optional
    No lanza excepción si falta: registra advertencia y devuelve $false.
.OUTPUTS
    [bool] $true si el módulo está disponible en versión suficiente.
.EXAMPLE
    Assert-PavModule -Name ExchangeOnlineManagement -MinimumVersion 3.2.0
.EXAMPLE
    if (-not (Assert-PavModule -Name ImportExcel -MinimumVersion 7.8.0 -Optional)) { $SkipExcel = $true }
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [version]$MinimumVersion,

        [switch]$Optional
    )

    $found = Get-Module -ListAvailable -Name $Name |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($found -and $found.Version -ge $MinimumVersion) {
        Write-Verbose "Módulo '$Name' v$($found.Version) disponible (mínimo: $MinimumVersion)."
        return $true
    }

    $detalle = if ($found) {
        "instalado en v$($found.Version), se requiere >= $MinimumVersion"
    }
    else {
        'no instalado'
    }
    $accion = "Instálelo con: Install-Module $Name -MinimumVersion $MinimumVersion -Scope CurrentUser"

    if ($Optional) {
        Write-PavLog -Level Warn -Message "Módulo opcional '$Name' $detalle. $accion"
        return $false
    }

    throw "Dependencia no satisfecha: módulo '$Name' $detalle. $accion"
}
