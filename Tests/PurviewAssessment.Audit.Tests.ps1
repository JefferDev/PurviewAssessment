#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Pruebas de la carga de auditoría (AUDIT).

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Get-Module PurviewAssessment -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot 'PurviewAssessment.psd1') -Force -ErrorAction Stop
}

Describe 'Helpers de auditoría' {
    It 'traduce las duraciones de retención' {
        InModuleScope PurviewAssessment {
            ConvertTo-PavAuditDuration 'TwelveMonths' | Should -Be '12 meses (1 año)'
            ConvertTo-PavAuditDuration 'TenYears'     | Should -Be '10 años'
            ConvertTo-PavAuditDuration ''             | Should -Be 'No definida'
            Get-PavAuditDurationDays 'TwelveMonths'   | Should -Be 365
            Get-PavAuditDurationDays 'ThreeMonths'    | Should -Be 90
        }
    }
    It 'marca AppliesToAll solo cuando no hay ámbito declarado' {
        InModuleScope PurviewAssessment {
            $sinAmbito = ConvertFrom-PavAuditRetentionPolicy ([pscustomobject]@{ Name='Todo'; RecordTypes=@(); Operations=@(); UserIds=@(); RetentionDuration='TenYears' })
            $sinAmbito.AppliesToAll | Should -BeTrue
            $conAmbito = ConvertFrom-PavAuditRetentionPolicy ([pscustomobject]@{ Name='Copilot'; RecordTypes=@('CopilotInteraction'); Operations=@('CopilotInteraction'); UserIds=@(); RetentionDuration='TwelveMonths' })
            $conAmbito.AppliesToAll    | Should -BeFalse
            $conAmbito.RecordTypeCount | Should -Be 1
        }
    }
}

Describe 'Get-PurviewAuditData: estado de la auditoría' {
    BeforeAll {
        InModuleScope PurviewAssessment {
            Set-Item function:script:Get-UnifiedAuditLogRetentionPolicy {
                param($ErrorAction)
                @([pscustomobject]@{ Name='Copilot 12m'; Description='Copilot'; Operations=@('CopilotInteraction')
                    RecordTypes=@('CopilotInteraction'); UserIds=@(); RetentionDuration='TwelveMonths'
                    Priority=100; Enabled=$true; Mode='Enforce'; DistributionStatus='Pending'; IsValid=$true })
            }
            Mock Assert-PavConnection { }
            Mock Write-PavLog { }
        }
    }

    It 'sin sesión de Exchange Online NO reporta la ingesta como deshabilitada' {
        InModuleScope PurviewAssessment {
            Set-Item function:script:Get-AdminAuditLogConfig { param($ErrorAction) [pscustomobject]@{ UnifiedAuditLogIngestionEnabled=$false; AdminAuditLogEnabled=$true } }
            Remove-Item function:script:Get-OrganizationConfig -Force -ErrorAction SilentlyContinue
            $d = Get-PurviewAuditData
            # Falso negativo evitado: IPPS siempre devuelve False
            $d.Status.UnifiedAuditLogIngestion | Should -Be 'No determinable'
            $d.Status.ExchangeOnlineSession    | Should -Be 'No disponible'
            ($d.Findings | Where-Object Finding -match 'no verificable').Count | Should -Be 1
            ($d.Findings | Where-Object Finding -match 'Auditoría unificada deshabilitada').Count | Should -Be 0
        }
    }

    It 'con sesión de Exchange Online reporta el valor real' {
        InModuleScope PurviewAssessment {
            Set-Item function:script:Get-AdminAuditLogConfig { param($ErrorAction) [pscustomobject]@{ UnifiedAuditLogIngestionEnabled=$true; AdminAuditLogEnabled=$true } }
            Set-Item function:script:Get-OrganizationConfig { param($ErrorAction) [pscustomobject]@{ AuditDisabled=$false } }
            $d = Get-PurviewAuditData
            $d.Status.UnifiedAuditLogIngestion | Should -Be 'Habilitada'
            $d.Status.MailboxAuditing          | Should -Be 'Habilitada'
            $d.Status.ExchangeOnlineSession    | Should -Be 'Disponible'
        }
    }

    It 'detecta auditoría realmente deshabilitada como hallazgo crítico' {
        InModuleScope PurviewAssessment {
            Set-Item function:script:Get-AdminAuditLogConfig { param($ErrorAction) [pscustomobject]@{ UnifiedAuditLogIngestionEnabled=$false; AdminAuditLogEnabled=$true } }
            Set-Item function:script:Get-OrganizationConfig { param($ErrorAction) [pscustomobject]@{ AuditDisabled=$true } }
            $d = Get-PurviewAuditData
            $d.Status.UnifiedAuditLogIngestion | Should -Be 'Deshabilitada'
            @($d.Findings | Where-Object Severity -eq 'Alta').Count | Should -BeGreaterOrEqual 2
        }
    }

    It 'deriva hallazgos de cobertura y distribución' {
        InModuleScope PurviewAssessment {
            Set-Item function:script:Get-AdminAuditLogConfig { param($ErrorAction) [pscustomobject]@{ UnifiedAuditLogIngestionEnabled=$true; AdminAuditLogEnabled=$true } }
            Set-Item function:script:Get-OrganizationConfig { param($ErrorAction) [pscustomobject]@{ AuditDisabled=$false } }
            $f = (Get-PurviewAuditData).Findings
            ($f | Where-Object Finding -match 'acotada a tipos').Count | Should -Be 1
            ($f | Where-Object Finding -match 'Distribución en estado Pending').Count | Should -Be 1
        }
    }

    It 'sin directivas señala la retención por defecto' {
        InModuleScope PurviewAssessment {
            Set-Item function:script:Get-UnifiedAuditLogRetentionPolicy { param($ErrorAction) @() }
            Set-Item function:script:Get-AdminAuditLogConfig { param($ErrorAction) [pscustomobject]@{ UnifiedAuditLogIngestionEnabled=$true; AdminAuditLogEnabled=$true } }
            Set-Item function:script:Get-OrganizationConfig { param($ErrorAction) [pscustomobject]@{ AuditDisabled=$false } }
            $d = Get-PurviewAuditData
            ($d.Findings | Where-Object Finding -match 'Sin directivas de retención').Count | Should -Be 1
        }
    }

    It 'genera el informe con estado y directivas' {
        InModuleScope PurviewAssessment {
            Set-Item function:script:Get-UnifiedAuditLogRetentionPolicy {
                param($ErrorAction)
                @([pscustomobject]@{ Name='Copilot 12m'; RecordTypes=@('CopilotInteraction'); Operations=@(); UserIds=@()
                    RetentionDuration='TwelveMonths'; Priority=100; Enabled=$true; DistributionStatus='Pending' })
            }
            Set-Item function:script:Get-AdminAuditLogConfig { param($ErrorAction) [pscustomobject]@{ UnifiedAuditLogIngestionEnabled=$true; AdminAuditLogEnabled=$true } }
            Set-Item function:script:Get-OrganizationConfig { param($ErrorAction) [pscustomobject]@{ AuditDisabled=$false } }
            $out = Join-Path ([IO.Path]::GetTempPath()) "PavAudit_$(Get-Random)"
            try {
                $r = Export-PurviewAuditReport -OutputPath $out -SkipExcel
                $h = Get-Content $r.HtmlPath -Raw
                $h | Should -Match 'Estado del registro de auditor'
                $h | Should -Match 'Copilot 12m'
                $h | Should -Match '12 meses'
            }
            finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
