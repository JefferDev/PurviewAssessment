#Requires -Version 7.2
<#
.SYNOPSIS
    Gate de SOLO LECTURA del módulo PurviewAssessment.
.DESCRIPTION
    Requisito contractual del assessment: el módulo jamás debe ejecutar
    operaciones de cambio o eliminación sobre cargas de trabajo de Purview.
    Este script convierte ese requisito en una verificación automática:
    analiza el AST de todos los .ps1/.psm1 del módulo y FALLA (exit 1) si
    encuentra la invocación de cualquier cmdlet de escritura sobre nouns
    de Purview/EXO.

    Se analiza el AST (no texto plano), de modo que menciones en comentarios
    o en cadenas de ayuda no generan falsos positivos: solo cuenta la
    INVOCACIÓN real del comando.

    Diseñado para ejecutarse en CI (GitHub Actions / Azure DevOps) y como
    paso previo a la firma del módulo.
.EXAMPLE
    pwsh -File build/Invoke-ReadOnlyGate.ps1 -ModulePath .
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$ModulePath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Verbos de escritura x nouns de Purview/EXO. Cualquier coincidencia en una
# invocación real es violación. Disconnect-ExchangeOnline está permitido
# explícitamente (gestión de sesión, no de datos del tenant).
$forbiddenPattern = '^(Set|New|Remove|Add|Update|Enable|Disable|Start|Stop|Import|Clear|Invoke)-(Dlp\w*|Label\w*|Retention\w*|Compliance\w*|Supervisory\w*|InsiderRisk\w*|OrganizationConfig|AdaptiveScope\w*|FilePlan\w*|RecordLabel\w*|InformationBarrier\w*|ProtectionAlert\w*|CaseHoldPolicy\w*|AutoSensitivityLabel\w*)$'

$targets = @(Get-ChildItem -Path $ModulePath -Recurse -Include '*.ps1', '*.psm1' -File |
    Where-Object { $_.FullName -notmatch '[\\/](Tests|build)[\\/]' })

$violations = [System.Collections.Generic.List[object]]::new()

foreach ($file in $targets) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)

    if ($errors -and $errors.Count -gt 0) {
        Write-Host "ERROR de sintaxis en $($file.FullName):" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 1
    }

    # Todas las invocaciones de comandos en el archivo
    $commandAsts = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)

    foreach ($cmd in $commandAsts) {
        $name = $cmd.GetCommandName()
        if ($name -and $name -match $forbiddenPattern) {
            $violations.Add([pscustomobject]@{
                Archivo = $file.FullName.Replace("$ModulePath", '.')
                Linea   = $cmd.Extent.StartLineNumber
                Comando = $name
            })
        }
    }
}

Write-Host ''
Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor White
Write-Host '  GATE DE SOLO LECTURA — PurviewAssessment' -ForegroundColor White
Write-Host '══════════════════════════════════════════════════════════════' -ForegroundColor White
Write-Host "  Archivos analizados : $($targets.Count)"

if ($violations.Count -gt 0) {
    Write-Host "  RESULTADO           : VIOLACIÓN — $($violations.Count) invocación(es) de escritura" -ForegroundColor Red
    foreach ($v in $violations) {
        Write-Host ("    {0}:{1}  ->  {2}" -f $v.Archivo, $v.Linea, $v.Comando) -ForegroundColor Red
    }
    Write-Host '  El módulo NO cumple el invariante de solo lectura. Build detenido.' -ForegroundColor Red
    exit 1
}

Write-Host '  RESULTADO           : APROBADO — 0 cmdlets de escritura sobre Purview' -ForegroundColor Green
Write-Host ''
exit 0
