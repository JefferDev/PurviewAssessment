@{
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # El módulo es una herramienta de consola para consultores: la salida
        # con color de Write-PavLog usa Write-Host de forma deliberada.
        # Warn/Error se duplican en los streams nativos (Write-Warning/Write-Error).
        'PSAvoidUsingWriteHost'
    )

    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.2')
        }
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }
        PSUseApprovedVerbs = @{
            Enable = $true
        }
    }
}
