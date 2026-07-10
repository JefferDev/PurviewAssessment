#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Pruebas de las cargas DLM y SIT (Fase 4b).

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Get-Module PurviewAssessment -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot 'PurviewAssessment.psd1') -Force -ErrorAction Stop
    $script:FixtureXml = Join-Path $PSScriptRoot 'fixtures/rulepack-sample.xml'
}

Describe 'Helpers DLM' {
    It 'duraciones: años/meses/días/Unlimited' {
        InModuleScope PurviewAssessment {
            ConvertTo-PavFriendlyDuration 2555 | Should -Be '7 año(s)'
            ConvertTo-PavFriendlyDuration 90   | Should -Be '3 mes(es)'
            ConvertTo-PavFriendlyDuration 45   | Should -Be '45 días'
            ConvertTo-PavFriendlyDuration $null | Should -Be 'Unlimited'
            ConvertTo-PavFriendlyDuration -1   | Should -Be 'Unlimited'
        }
    }
    It 'acciones, tipos y modos friendly' {
        InModuleScope PurviewAssessment {
            ConvertTo-PavFriendlyAction 'KeepAndDelete' | Should -Be 'Retener y luego eliminar'
            ConvertTo-PavFriendlyRetentionType 'ModificationAgeInDays' | Should -Be 'Desde última modificación'
            ConvertTo-PavFriendlyMode 'Enforce' $true  | Should -Be 'Simulación'
            ConvertTo-PavFriendlyMode 'Enforce' $false | Should -Be 'Activa (Enforce)'
        }
    }
    It 'ubicaciones: Todos / N elementos / no configurado' {
        InModuleScope PurviewAssessment {
            Get-PavLocationScope @('All') | Should -Be 'Todos'
            Get-PavLocationScope @('a','b') | Should -Be '2 elemento(s) específico(s)'
            Get-PavLocationScope @() | Should -Be 'No configurado'
            Get-PavLocationDetails @('All','sitio1') | Should -Be 'sitio1'
        }
    }
}

Describe 'ConvertFrom-PavRulePackage (fixture XML)' {
    It 'parsea metadatos, entidades (incluye <Version>), regex, keywords y filtros' {
        InModuleScope PurviewAssessment -Parameters @{ Xml = $script:FixtureXml } {
            param($Xml)
            Mock Write-PavLog { }
            $r = ConvertFrom-PavRulePackage -XmlPath $Xml
            $r.RulePack.Name | Should -Be 'Contoso Custom SITs'
            $r.Entities.Count | Should -Be 2
            $ced = $r.Entities | Where-Object Id -eq 'ent-cedula'
            $ced.Name | Should -Be 'Cedula CO'
            $ced.RecommendedConfidence | Should -Be '85'
            @($ced.Patterns).Count | Should -Be 2
            @($ced.Patterns)[0].IdMatchRef | Should -Be 'rx-cedula'
            @(@($ced.Patterns)[0].AnyBlocks).Count | Should -Be 1
            ($r.Entities | Where-Object Id -eq 'ent-contrato').MinEngineVersion | Should -Be '15.20.3'
            $r.RegexMap['rx-cedula'] | Should -Be '\d{8,10}'
            $r.KeywordMap['kw-cedula'][0].Terms.Count | Should -Be 2
            $r.FilterMap['flt-1'][0].Type | Should -Be 'ExcludeTextMatch'
        }
    }
}

Describe 'Get-PurviewSitData / Export-PurviewSitReport' {
    It 'modo offline no requiere sesión y genera informe con regex resuelta' {
        InModuleScope PurviewAssessment -Parameters @{ Xml = $script:FixtureXml } {
            param($Xml)
            Mock Write-PavLog { }
            $d = Get-PurviewSitData -XmlPath $Xml
            $d.PSObject.TypeNames[0] | Should -Be 'PurviewAssessment.SitData'
            $out = Join-Path ([IO.Path]::GetTempPath()) "PavSitTest_$(Get-Random)"
            try {
                $r = $d | Export-PurviewSitReport -OutputPath $out -SkipExcel
                $h = Get-Content $r.HtmlPath -Raw
                $h | Should -Match 'Cedula CO'
                $h | Should -Match 'rx-cedula: \\d\{8,10\}'
                $h | Should -Match 'Contoso Custom SITs'
            }
            finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Get-PurviewDlmData / Export-PurviewDlmReport (stubs)' {
    BeforeAll {
        InModuleScope PurviewAssessment {
            Set-Item function:script:Get-RetentionCompliancePolicy {
                param([switch]$DistributionDetail, $ErrorAction)
                @([pscustomobject]@{ Name = 'Retención Global'; Guid = 'dlm-1'; ExchangeObjectId = 'eo-1'
                    Type = 'Hold'; Mode = 'Enforce'; IsSimulation = $false; Enabled = $true; Priority = 0
                    DistributionStatus = 'Success'; Workload = 'Exchange'
                    ExchangeLocation = @('All'); SharePointLocation = @('https://x/sitio1')
                    SharePointLocationException = @('https://x/excluido'); IsAdaptivePolicy = $true })
            }
            Set-Item function:script:Get-RetentionComplianceRule {
                param($ErrorAction)
                @([pscustomobject]@{ Name = 'Regla 7 años'; Guid = 'dlmr-1'; Policy = 'dlm-1'
                    RetentionComplianceAction = 'KeepAndDelete'; RetentionDuration = 2555
                    RetentionType = 'CreationAgeInDays'; PublishComplianceTag = 'guid,Etiqueta Fiscal'
                    ContentContainsSensitiveInformation = @([pscustomobject]@{ Name = 'NIT CO' }) })
            }
            Set-Item function:script:Get-ComplianceTag {
                param($ErrorAction)
                @([pscustomobject]@{ Name = 'Etiqueta Fiscal'; Guid = 'tag-1'; Policy = 'dlm-1'
                    RetentionAction = 'KeepAndDelete'; RetentionDuration = 2555; RetentionType = 'CreationAgeInDays'
                    Regulatory = $true; IsRecordLabel = $true
                    FilePlanMetadata = '{"Settings":[{"Key":"FilePlanPropertyDepartment","Value":"Finanzas"},{"Key":"FilePlanPropertyCitation","Value":"Ley 962"}]}'
                    MultiStageReviewerMetadata = '{"MultiStageReviewSettings":[{"StageId":1,"StageName":"Legal","Reviewers":["legal@contoso.com"]}]}' })
            }
            Mock Assert-PavConnection { }
            Mock Write-PavLog { }
        }
    }
    It 'resuelve política por GUID, duración friendly, file plan y etapas' {
        InModuleScope PurviewAssessment {
            $d = Get-PurviewDlmData
            $d.Rules[0].PolicyName | Should -Be 'Retención Global'
            $d.Rules[0].RetentionDuration | Should -Be '7 año(s)'
            $d.Rules[0].PublishComplianceTag | Should -Be 'Etiqueta Fiscal'
            $d.Rules[0].SensitiveInfoTypes | Should -Be 'NIT CO'
            $d.Tags[0].LabelCategory | Should -Be 'Regulatory Record'
            $d.FilePlans[0].Department | Should -Be 'Finanzas'
            $d.ReviewStages[0].Reviewers | Should -Be 'legal@contoso.com'
            ($d.PolicyLocations | Where-Object Workload -eq 'SharePoint').Exclusions | Should -Be '1 excluido(s)'
        }
    }
    It 'Export genera HTML con 3 tabs y contenido' {
        InModuleScope PurviewAssessment {
            $out = Join-Path ([IO.Path]::GetTempPath()) "PavDlmTest_$(Get-Random)"
            try {
                $r = Export-PurviewDlmReport -OutputPath $out -SkipExcel
                $h = Get-Content $r.HtmlPath -Raw
                ($h | Select-String -Pattern 'class="pav-tab ' -AllMatches).Matches.Count + ($h | Select-String -Pattern 'class="pav-tab"' -AllMatches).Matches.Count | Should -BeGreaterOrEqual 3
                $h | Should -Match 'Regulatory Record'
                $h | Should -Match 'File Plan'
                $h | Should -Match 'Etapas de revisión'
            }
            finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
