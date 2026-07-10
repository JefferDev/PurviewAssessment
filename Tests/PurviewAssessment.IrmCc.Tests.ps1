#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Pruebas de las cargas IRM y Communication Compliance (Fase 4a).

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Get-Module PurviewAssessment -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot 'PurviewAssessment.psd1') -Force -ErrorAction Stop
}

Describe 'Parsers IRM' {
    It 'Expand-PavIrmTriggerInsights: grupos JSON → filas planas' {
        InModuleScope PurviewAssessment {
            $pol = [pscustomobject]@{ Name = 'P1'
                TriggerInsightGroups = @('{"Name":"HR","Insights":[{"Name":"Resignation","Enabled":true,"UseCustomThresholds":false,"EventThresholds":"x"}]}') }
            $r = @(Expand-PavIrmTriggerInsights -Policy $pol)
            $r.Count | Should -Be 1
            $r[0].GroupName | Should -Be 'HR'
            $r[0].InsightName | Should -Be 'Resignation'
            $r[0].HasThresholds | Should -BeTrue
        }
    }
    It 'Expand-PavIrmIndicators: sub-indicadores unidos con |' {
        InModuleScope PurviewAssessment {
            $pol = [pscustomobject]@{ Name = 'P1'
                Indicators = @('{"Name":"Exfiltration","Type":"Native","Enabled":true,"UseDefault":true,"ThresholdMode":"Default","UseInScoring":true,"Indicators":[{"Name":"CopyToUSB"},{"Name":"PrintDocument"}]}')
                ExtensibleIndicators = @() }
            $r = @(Expand-PavIrmIndicators -Policy $pol)
            $r[0].SubIndicators | Should -Be 'CopyToUSB | PrintDocument'
        }
    }
    It 'Get-PavIrmHealthRow: issues de validación formateados; sin JSON → Unknown' {
        InModuleScope PurviewAssessment {
            $pol = [pscustomobject]@{ Name = 'P1'
                PolicyHealth = '{"HealthStatus":"Unhealthy","UnhealthyCount":2,"RecommendReviewCount":1,"ValidationDetails":[{"Name":"HRConnector","ValidationSeverity":"High","Status":"Missing"}]}' }
            $h = Get-PavIrmHealthRow -Policy $pol
            $h.HealthStatus | Should -Be 'Unhealthy'
            $h.ValidationIssues | Should -Be 'HRConnector [High]: Missing'
            (Get-PavIrmHealthRow -Policy ([pscustomobject]@{ Name = 'P2'; PolicyHealth = $null })).HealthStatus | Should -Be 'Unknown'
        }
    }
}

Describe 'Parsers CC' {
    It 'ConvertFrom-PavCcContentSources: Reviewee + Workloads' {
        InModuleScope PurviewAssessment {
            $rule = [pscustomobject]@{ ContentSources = @('{"RevieweeName":"Ventas","Workloads":["Exchange","Teams"]}') }
            ConvertFrom-PavCcContentSources -RuleObj $rule | Should -Be 'Reviewee: Ventas | Workloads: Exchange,Teams'
        }
    }
    It 'Get-PavCcWorkloads: únicos desde ContentSources; fallback a Workload' {
        InModuleScope PurviewAssessment {
            $rule = [pscustomobject]@{ ContentSources = @('{"Workloads":["Teams","Exchange"]}','{"Workloads":["Exchange"]}') }
            Get-PavCcWorkloads -RuleObj $rule | Should -Be 'Exchange, Teams'
            Get-PavCcWorkloads -RuleObj ([pscustomobject]@{ ContentSources = @(); Workload = 'Exchange' }) | Should -Be 'Exchange'
        }
    }
    It 'ConvertFrom-PavCcClassifiers: nombres de datamodels' {
        InModuleScope PurviewAssessment {
            $rule = [pscustomobject]@{ AdvancedRule = '{"condition":{"subconditions":[{"value":{"datamodels":[{"name":"Threat"},{"name":"Profanity"}]}}]}}' }
            ConvertFrom-PavCcClassifiers -RuleObj $rule | Should -Be 'Threat | Profanity'
            ConvertFrom-PavCcClassifiers -RuleObj ([pscustomobject]@{ AdvancedRule = '{}' }) | Should -Be 'N/D'
        }
    }
    It 'Get-PavCcDirection: direcciones desde KQL' {
        InModuleScope PurviewAssessment {
            Get-PavCcDirection '((Direction:Inbound) OR (Direction:Outbound))' | Should -Be 'Inbound, Outbound'
            Get-PavCcDirection 'Subject:test' | Should -Be 'N/D'
        }
    }
}

Describe 'Colectores y exportadores IRM/CC (stubs, sin tenant)' {
    BeforeAll {
        InModuleScope PurviewAssessment {
            Set-Item function:script:Get-InsiderRiskPolicy {
                param($ErrorAction)
                @([pscustomobject]@{ Name = 'Fuga de datos'; Guid = 'irm-1'; Enabled = $true; Mode = 'Enable'
                    Type = 'InsiderRisk'; InsiderRiskScenario = 'DataLeaks'; PolicyCategory = 'DataTheft'; Priority = 0
                    DistributionStatus = 'Success'; Workload = 'Exchange'; ExchangeLocation = @('All')
                    InScopeTimeSpan = 30; HistoricTimeSpan = 90; DlpPolicy = 'PII Producción'
                    IsCustom = $true; PolicyHealth = '{"HealthStatus":"Unhealthy","UnhealthyCount":1,"RecommendReviewCount":0,"ValidationDetails":[{"Name":"HRConnector","ValidationSeverity":"High","Status":"Missing"}]}'
                    TriggerInsightGroups = @('{"Name":"HR","Insights":[{"Name":"Resignation","Enabled":true,"UseCustomThresholds":false,"EventThresholds":""}]}')
                    Indicators = @('{"Name":"Exfiltration","Type":"Native","Enabled":true,"UseDefault":true,"ThresholdMode":"Default","UseInScoring":true,"Indicators":[{"Name":"CopyToUSB"}]}')
                    ExtensibleIndicators = @(); CreatedBy = 'admin'; CreationTimeUtc = '2025-03-01' })
            }
            Set-Item function:script:Get-SupervisoryReviewPolicyV2 {
                param($ErrorAction)
                @(
                    [pscustomobject]@{ Name = 'Lenguaje inapropiado'; Guid = 'cc-1'; Enabled = $true
                        PolicyStatus = 'Active'; ProvisioningStatus = 'Success'; Mode = 'Enforce'
                        Reviewers = @('rev@contoso.com'); ReviewMailbox = 'buzon@contoso.com'; PreservationPeriodInDays = 365 }
                    [pscustomobject]@{ Name = 'Vieja'; Guid = 'cc-2'; Enabled = $false; PolicyStatus = 'Disabled' }
                )
            }
            Set-Item function:script:Get-SupervisoryReviewRule {
                param($ErrorAction)
                @([pscustomobject]@{ Name = 'Regla lenguaje'; Guid = 'ccr-1'; Policy = 'cc-1'
                    Condition = '((Direction:Inbound) OR (Direction:Internal))'; SamplingRate = 100; Ocr = $true
                    AdvancedRule = '{"condition":{"subconditions":[{"value":{"datamodels":[{"name":"Threat"}]}}]}}'
                    ContentSources = @('{"RevieweeName":"Todos","Workloads":["Exchange","Teams"]}'); Disabled = $false })
            }
            Mock Assert-PavConnection { }
            Mock Write-PavLog { }
        }
    }

    It 'Get-PurviewIrmData: salud, insights e indicadores expandidos' {
        InModuleScope PurviewAssessment {
            $d = Get-PurviewIrmData
            $d.Policies[0].HealthStatus | Should -Be 'Unhealthy'
            $d.Policies[0].HasDlpPolicy | Should -BeTrue
            $d.Health[0].ValidationIssues | Should -Match 'HRConnector'
            @($d.TriggerInsights).Count | Should -Be 1
            @($d.Indicators)[0].SubIndicators | Should -Be 'CopyToUSB'
        }
    }
    It 'Get-PurviewCcData: filtra deshabilitadas, cruza reglas y parsea dirección/clasificadores' {
        InModuleScope PurviewAssessment {
            $d = Get-PurviewCcData
            $d.Policies.Count | Should -Be 1
            (Get-PurviewCcData -IncludeDisabled).Policies.Count | Should -Be 2
            $d.Policies[0].RulesCount | Should -Be 1
            $d.Policies[0].Workloads | Should -Be 'Exchange, Teams'
            $d.Rules[0].Direction | Should -Be 'Inbound, Internal'
            $d.Rules[0].ClassifiersModels | Should -Be 'Threat'
        }
    }
    It 'Export-PurviewIrmReport y Export-PurviewCcReport generan HTML válidos' {
        InModuleScope PurviewAssessment {
            $out = Join-Path ([IO.Path]::GetTempPath()) "PavIrmCcTest_$(Get-Random)"
            try {
                $ri = Export-PurviewIrmReport -OutputPath $out -SkipExcel
                (Get-Content $ri.HtmlPath -Raw) | Should -Match 'No saludable'
                $rc = Export-PurviewCcReport -OutputPath $out -SkipExcel
                $h = Get-Content $rc.HtmlPath -Raw
                $h | Should -Match 'class="pav-tabs"'
                $h | Should -Match 'Inbound, Internal'
            }
            finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
