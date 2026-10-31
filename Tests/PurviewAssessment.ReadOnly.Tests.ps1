#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    Invariante contractual: el módulo es de SOLO LECTURA sobre el tenant.
    Esta prueba ejecuta el gate de AST (build/Invoke-ReadOnlyGate.ps1) y
    falla si existe cualquier invocación de cmdlet de escritura sobre
    nouns de Purview en Public/ o Private/.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:Gate       = Join-Path $ModuleRoot 'build/Invoke-ReadOnlyGate.ps1'
}

Describe 'Invariante de solo lectura' {
    It 'el gate de AST no encuentra cmdlets de escritura sobre Purview' {
        & $Gate -ModulePath $ModuleRoot *> $null
        $LASTEXITCODE | Should -Be 0
    }

    It 'el gate SÍ detecta una violación inyectada (autoprueba del gate)' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) "PavGateSelfTest_$(Get-Random)"
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            # Falso módulo con una invocación de escritura real
            Set-Content -Path (Join-Path $tmp 'Bad.ps1') -Value @'
function Invoke-Bad {
    Remove-DlpCompliancePolicy -Identity 'x' -Confirm:$false
}
'@
            & $Gate -ModulePath $tmp *> $null
            $LASTEXITCODE | Should -Be 1 -Because 'el gate debe fallar ante cmdlets de escritura'
        }
        finally {
            Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'el gate ignora menciones en comentarios y strings (solo invocaciones reales)' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) "PavGateSelfTest_$(Get-Random)"
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            Set-Content -Path (Join-Path $tmp 'Ok.ps1') -Value @'
function Invoke-Ok {
    # Este comentario menciona Set-Label y Remove-DlpCompliancePolicy
    $doc = "La ayuda dice que New-RetentionCompliancePolicy existe"
    Write-Output $doc
}
'@
            & $Gate -ModulePath $tmp *> $null
            $LASTEXITCODE | Should -Be 0 -Because 'comentarios y strings no son invocaciones'
        }
        finally {
            Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
