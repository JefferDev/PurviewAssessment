#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    Pruebas de la capa de conexión con mocks (no requieren tenant ni
    ExchangeOnlineManagement instalado): se mockean los helpers privados
    dentro del scope del módulo con InModuleScope.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Get-Module PurviewAssessment -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot 'PurviewAssessment.psd1') -Force -ErrorAction Stop
}

Describe 'Connect-PurviewAssessment' {
    BeforeAll {
        InModuleScope PurviewAssessment {
            # Mock exige que el comando exista. ExchangeOnlineManagement no se
            # instala en CI a proposito (estas pruebas no deben depender de el),
            # asi que se declara un sustituto vacio en el alcance del modulo.
            if (-not (Get-Command Connect-IPPSSession -ErrorAction SilentlyContinue)) {
                Set-Item function:script:Connect-IPPSSession { param($UserPrincipalName, $ShowBanner, $ErrorAction) }
            }
        }
    }

    It 'valida el formato del UPN antes de intentar conectar' {
        { Connect-PurviewAssessment -UserPrincipalName 'no-es-un-upn' } |
            Should -Throw -ErrorId 'ParameterArgumentValidationError*'
    }

    It 'reutiliza la sesión existente sin invocar Connect-IPPSSession' {
        InModuleScope PurviewAssessment {
            Mock Assert-PavModule { $true }
            Mock Test-PavSession  { $true }
            Mock Connect-IPPSSession { throw 'no debe llamarse' }
            Mock Write-PavLog { }

            { Connect-PurviewAssessment } | Should -Not -Throw
            Should -Invoke Connect-IPPSSession -Times 0
            (Test-PurviewAssessmentConnection -Quiet) | Should -BeTrue
        }
    }

    It 'traduce el error de MFA (AADSTS50076) a un hint accionable en español' {
        InModuleScope PurviewAssessment {
            Mock Assert-PavModule { $true }
            Mock Test-PavSession  { $false }
            Mock Connect-IPPSSession { throw 'AADSTS50076: user must use multi-factor authentication' }
            Mock Write-PavLog { }

            { Connect-PurviewAssessment } | Should -Throw '*MFA requerido*'
        }
    }

    It 'falla con mensaje de rol si tras conectar no hay cmdlets registrados' {
        InModuleScope PurviewAssessment {
            Mock Assert-PavModule { $true }
            Mock Test-PavSession  { $false }   # antes y después de conectar
            Mock Connect-IPPSSession { }
            Mock Write-PavLog { }

            { Connect-PurviewAssessment } | Should -Throw '*rol de la cuenta*'
        }
    }
}

Describe 'Assert-PavConnection (guard de los colectores)' {
    It 'lanza error accionable si no hay sesión' {
        InModuleScope PurviewAssessment {
            $script:PavContext.Connected = $false
            Mock Test-PavSession { $false }

            { Assert-PavConnection } | Should -Throw '*Connect-PurviewAssessment*'
        }
    }

    It 'detecta sesión expirada aunque el contexto diga Connected' {
        InModuleScope PurviewAssessment {
            $script:PavContext.Connected = $true
            Mock Test-PavSession { $false }
            Mock Write-PavLog { }

            { Assert-PavConnection } | Should -Throw
            $script:PavContext.Connected | Should -BeFalse
        }
    }
}

Describe 'Invoke-PavRetry' {
    It 'reintenta ante error transitorio y devuelve el resultado' {
        InModuleScope PurviewAssessment {
            Mock Write-PavLog { }
            Mock Start-Sleep { }
            $script:intentos = 0

            $r = Invoke-PavRetry -OperationName 'Prueba' -MaxAttempts 3 -InitialDelaySeconds 1 -ScriptBlock {
                $script:intentos++
                if ($script:intentos -lt 3) { throw 'server is busy, Micro delay applied' }
                'ok'
            }

            $r | Should -Be 'ok'
            $script:intentos | Should -Be 3
        }
    }

    It 'NO reintenta ante errores no transitorios (p. ej. permisos)' {
        InModuleScope PurviewAssessment {
            Mock Write-PavLog { }
            Mock Start-Sleep { }
            $script:intentos = 0

            { Invoke-PavRetry -OperationName 'Prueba' -MaxAttempts 3 -ScriptBlock {
                $script:intentos++
                throw 'Access is denied'
            } } | Should -Throw '*Access is denied*'

            $script:intentos | Should -Be 1
        }
    }
}

Describe 'Disconnect-PurviewAssessment' {
    It 'es idempotente: no falla sin sesión y limpia el contexto' {
        InModuleScope PurviewAssessment {
            Mock Write-PavLog { }
            $script:PavContext.Connected = $true
            $script:PavContext.Upn = 'x@y.com'

            { Disconnect-PurviewAssessment } | Should -Not -Throw
            $script:PavContext.Connected | Should -BeFalse
            $script:PavContext.Upn | Should -BeNullOrEmpty
        }
    }
}
