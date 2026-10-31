#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Pruebas de la carga de trabajo Etiquetas (Fase 3a). Sin tenant: fixtures y stubs.

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Get-Module PurviewAssessment -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot 'PurviewAssessment.psd1') -Force -ErrorAction Stop
}

Describe 'Parsers de Labels (portados de v3)' {
    It 'ConvertFrom-PavKeyValueSettings: formatos [k, v], k=v y diccionario' {
        InModuleScope PurviewAssessment {
            $r = ConvertFrom-PavKeyValueSettings @('[Color, #f5c344]', 'tooltip=Uso interno')
            $r['color']   | Should -Be '#f5c344'
            $r['tooltip'] | Should -Be 'Uso interno'
            (ConvertFrom-PavKeyValueSettings @{ ParentId = 'abc' })['parentid'] | Should -Be 'abc'
            (ConvertFrom-PavKeyValueSettings $null).Count | Should -Be 0
        }
    }

    It 'ConvertFrom-PavLabelActions: normaliza footer/watermark y parsea settings JSON' {
        InModuleScope PurviewAssessment {
            $actions = @(
                '{"Type":"applycontentmarking","SubType":"footer","Settings":["{\"Key\":\"Text\",\"Value\":\"Confidencial\"}"]}'
                '{"Type":"applywatermarking","SubType":null,"Settings":["{\"Key\":\"Disabled\",\"Value\":\"true\"}"]}'
                '{"Type":"encrypt","SubType":null,"Settings":[]}'
            )
            $r = ConvertFrom-PavLabelActions $actions
            $r.Keys | Should -Contain 'footer'
            $r['footer']['text'] | Should -Be 'Confidencial'
            $r.Keys | Should -Contain 'watermark'
            $r['watermark']['disabled'] | Should -Be 'true'
            $r.Keys | Should -Contain 'encrypt'
        }
    }

    It 'ConvertFrom-PavLocaleSettings: displayName por idioma' {
        InModuleScope PurviewAssessment {
            $r = ConvertFrom-PavLocaleSettings @('{"LocaleKey":"displayName","Settings":["{\"Key\":\"default\",\"Value\":\"Confidencial\"}","{\"Key\":\"en-us\",\"Value\":\"Confidential\"}"]}')
            $r['displayName']['default'] | Should -Be 'Confidencial'
            $r['displayName']['en-us']   | Should -Be 'Confidential'
        }
    }

    It 'regresión: Settings de UN elemento sobrevive al des-enrollado de PowerShell' {
        InModuleScope PurviewAssessment {
            $o = [pscustomobject]@{ Settings = @('[mandatory, true]') }
            $h = ConvertFrom-PavKeyValueSettings (Get-PavProp $o 'Settings')
            $h['mandatory'] | Should -Be 'true'
        }
    }

    It 'JSON inválido devuelve $null sin excepción' {
        InModuleScope PurviewAssessment {
            ConvertFrom-PavJson '{no-es-json' | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-PurviewLabelData (con cmdlets stub, sin tenant)' {
    BeforeAll {
        InModuleScope PurviewAssessment {
            Set-Item function:script:Get-Label {
                param([switch]$IncludeDetailedLabelActions, $ErrorAction)
                @(
                    [pscustomobject]@{
                        Name = 'Confidential'; DisplayName = 'Confidencial'; Guid = 'g-conf'; ImmutableId = 'i-conf'
                        Priority = 1; ParentId = $null; IsParent = $true; Comment = 'Raíz'
                        Settings = @('[color, #ff0000]'); LocaleSettings = @()
                        LabelActions = @('{"Type":"encrypt","SubType":null,"Settings":[]}')
                        Workload = 'Exchange, SharePoint'
                    }
                    [pscustomobject]@{
                        Name = 'Confidential-All'; DisplayName = 'Confidencial \ Todos'; Guid = 'g-all'; ImmutableId = 'i-all'
                        Priority = 2; ParentId = 'g-conf'; IsParent = $false; Comment = ''
                        Settings = @('[color, #ff0000]')
                        LocaleSettings = @('{"LocaleKey":"tooltip","Settings":["{\"Key\":\"default\",\"Value\":\"Datos internos\"}"]}')
                        LabelActions = @('{"Type":"applycontentmarking","SubType":"footer","Settings":["{\"Key\":\"Disabled\",\"Value\":\"false\"}"]}')
                        Workload = 'Exchange'
                    }
                )
            }
            Set-Item function:script:Get-LabelPolicy {
                param($ErrorAction)
                @([pscustomobject]@{
                    Name = 'Directiva Global'; Guid = 'p1'; Type = 'PublishLabels'; Enabled = $true; Mode = 'Enable'
                    ScopedLabels = @('Confidential-All'); Settings = @('[mandatory, true]')
                    ExchangeLocation = @('All'); Workload = 'Exchange'
                })
            }
            Mock Assert-PavConnection { }
            Mock Write-PavLog { }
        }
    }

    It 'procesa etiquetas: cifrado, padre resuelto, marcas, tooltip locale y publicación' {
        InModuleScope PurviewAssessment {
            $d = Get-PurviewLabelData
            $d.PSObject.TypeNames[0] | Should -Be 'PurviewAssessment.LabelData'
            $d.Labels.Count | Should -Be 2

            $root = $d.Labels | Where-Object Name -eq 'Confidential'
            $root.HasEncryption | Should -BeTrue
            $root.PublishedInPolicies | Should -BeNullOrEmpty

            $child = $d.Labels | Where-Object Name -eq 'Confidential-All'
            $child.ParentDisplay | Should -Be 'Confidencial'
            $child.HasFooter | Should -BeTrue
            $child.HasContentMarking | Should -BeTrue
            $child.Tooltip | Should -Be 'Datos internos'
            $child.PublishedInPolicies | Should -Be 'Directiva Global'
        }
    }

    It 'procesa directivas: mandatory desde Settings y conteo de etiquetas' {
        InModuleScope PurviewAssessment {
            $d = Get-PurviewLabelData
            $p = $d.Policies[0]
            $p.Mandatory | Should -Be 'true'
            $p.LabelsCount | Should -Be 1
            $p.ExchangeLocation | Should -Be 'All'
        }
    }
}

Describe 'Export-PurviewLabelReport (HTML end-to-end con fixture)' {
    It 'genera HTML con tabs, tarjetas y datos codificados; -SkipExcel omite el libro' {
        InModuleScope PurviewAssessment {
            Mock Write-PavLog { }
            $fix = [pscustomobject]@{
                PSTypeName = 'PurviewAssessment.LabelData'
                Labels = @([pscustomobject]@{
                    PSTypeName='PurviewAssessment.Label'; Priority=1; Name='L1'; DisplayName='Etiqueta <Test>'
                    Guid='g1'; ImmutableId='i1'; ParentId=''; ParentDisplay='--'; IsParent=$false; Comment=''
                    Color='#fff'; ContentType=''; Tooltip='t'; Workload='Exchange'
                    HasEncryption=$true; HasHeader=$false; HasFooter=$false; HasWatermark=$false
                    HasContentMarking=$false; HasProtectGroup=$false; HasProtectSites=$false
                    LocaleDisplayName=''; LocaleAll=''; SettingsRaw=''; ActionsRaw=''
                    WhenCreatedUTC=$null; WhenChangedUTC=$null; CreatedBy=''; PublishedInPolicies='P1'
                })
                Policies = @([pscustomobject]@{
                    PSTypeName='PurviewAssessment.LabelPolicy'; Name='P1'; Guid='p1'; Type='PublishLabels'
                    Enabled=$true; Mode='Enable'; Workload=''; ScopedLabels=@('L1'); LabelsCount=1
                    Mandatory='true'; DefaultLabelId=''; RequireDowngradeJustification=''
                    ExchangeLocation='All'; SharePointLocation=''; OneDriveLocation=''; ModernGroupLocation=''
                    WhenCreatedUTC=$null; WhenChangedUTC=$null; SettingsRaw=''
                })
                CollectedAt = Get-Date
            }
            $out = Join-Path ([IO.Path]::GetTempPath()) "PavLabelsTest_$(Get-Random)"
            try {
                $r = Export-PurviewLabelReport -Data $fix -OutputPath $out -ClientName 'Cliente Demo' -SkipExcel
                Test-Path $r.HtmlPath | Should -BeTrue
                $r.ExcelPath | Should -BeNullOrEmpty
                $h = Get-Content $r.HtmlPath -Raw
                $h | Should -Match 'class="pav-tabs"'          # 2 secciones → tabs
                $h | Should -Match 'Etiqueta &lt;Test&gt;'      # codificación
                $h | Should -Match 'Obligatoria'                # badge de directiva
            }
            finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Etiquetado automático (auto-labeling)' {
    BeforeAll {
        InModuleScope PurviewAssessment {
            Set-Item function:script:Get-Label {
                param([switch]$IncludeDetailedLabelActions, $ErrorAction)
                @([pscustomobject]@{ Name='Interna'; DisplayName='Interna'; Guid='g1'; ImmutableId='i1'; Priority=1
                    ParentId=$null; IsParent=$false; Comment=''; Settings=@('[color, #0b57d0]')
                    LocaleSettings=@(); LabelActions=@(); Workload='Exchange' })
            }
            Set-Item function:script:Get-LabelPolicy {
                param($ErrorAction)
                @([pscustomobject]@{ Name='P1'; Guid='p1'; Type='PublishLabels'; Enabled=$true; Mode='Enable'
                    ScopedLabels=@('Interna'); Settings=@('[mandatory, true]'); ExchangeLocation=@('All'); Workload='Exchange' })
            }
            # Salida equivalente a la real de Get-AutoSensitivityLabelPolicy
            Set-Item function:script:Get-AutoSensitivityLabelPolicy {
                param($ErrorAction)
                @([pscustomobject]@{ Name='AL - Info Sensible'; Guid='c0be'; Type='AutoLabeling'
                    Mode='TestWithoutNotifications'; Enabled=$true; Priority=7
                    LabelDisplayName='Interna'; ApplySensitivityLabel='Interna'; OverwriteLabel=$false; RemoveLabel=$false
                    ExchangeLocation=@('All'); SharePointLocation=@('All'); OneDriveLocation=@('All')
                    ExchangeAdaptiveScopes=@('Scope-MX'); SharePointAdaptiveScopes=@()
                    ItemsMatchedDuringTestMode=42; DistributionStatus='Pending'; DistributionSyncStatus='Unknown'
                    CreatedBy='Seguridad TI'; Workload='Exchange, SharePoint' })
            }
            Set-Item function:script:Get-AutoSensitivityLabelRule {
                param($Policy, $ErrorAction)
                @([pscustomobject]@{ Name='RULE_InfoSensible-EXO'; DisplayName='RULE_InfoSensible-EXO'; Guid='f28a'
                    ParentPolicyName='AL - Info Sensible'; Policy='c0be'; Priority=0; Disabled=$false; Mode='Enforce'
                    IsAdvancedRule=$true; LogicalWorkload='Exchange'; ReportSeverityLevel='Low'
                    StampLabelId='g1'; ContentIsNotLabeled=$false
                    AdvancedRule='{"Version":"1.0","Condition":{"Operator":"And","SubConditions":[{"ConditionName":"AccessScope","Value":"NotInOrganization"},{"ConditionName":"ContentContainsSensitiveInformation","Value":[{"Groups":[{"Name":"InfoSensible","Sensitivetypes":[{"Name":"MX-CONT-Contratos","Mincount":1,"Confidencelevel":"High"}]}]}]}]}}' })
            }
            Mock Assert-PavConnection { }
            Mock Write-PavLog { }
        }
    }

    It 'recolecta directivas y reglas, y traduce el modo de simulación' {
        InModuleScope PurviewAssessment {
            $d = Get-PurviewLabelData
            @($d.AutoLabelPolicies).Count | Should -Be 1
            @($d.AutoLabelRules).Count    | Should -Be 1
            $ap = $d.AutoLabelPolicies[0]
            $ap.ModeFriendly           | Should -Be 'Simulación (no etiqueta)'
            $ap.ApplySensitivityLabel  | Should -Be 'Interna'
            $ap.ExchangeLocation       | Should -Be 'Todos'
            $ap.AdaptiveScopes         | Should -Match 'Exchange: Scope-MX'
            $ap.SimulationItemsMatched | Should -Be 42
        }
    }
    It 'parsea el AdvancedRule de la regla con SITs y AccessScope' {
        InModuleScope PurviewAssessment {
            $ar = (Get-PurviewLabelData).AutoLabelRules[0]
            $ar.IsAdvancedRule     | Should -Be 'Sí'
            $ar.AccessScopeAdv     | Should -Be 'NotInOrganization'
            $ar.SensitiveInfoTypes | Should -Match 'MX-CONT-Contratos \| Mincount:1'
            $ar.ConditionsTree     | Should -Match 'AND:'
        }
    }
    It '-SkipAutoLabeling omite la recolección' {
        InModuleScope PurviewAssessment {
            $d = Get-PurviewLabelData -SkipAutoLabeling
            @($d.AutoLabelPolicies).Count | Should -Be 0
        }
    }
    It 'tolera tenants sin la feature (cmdlet no registrado)' {
        InModuleScope PurviewAssessment {
            $backup = ${function:script:Get-AutoSensitivityLabelPolicy}
            Remove-Item function:script:Get-AutoSensitivityLabelPolicy -Force
            try {
                $d = Get-PurviewLabelData
                @($d.AutoLabelPolicies).Count | Should -Be 0
                @($d.Labels).Count | Should -Be 1     # el resto del informe sigue
            }
            finally { Set-Item function:script:Get-AutoSensitivityLabelPolicy $backup }
        }
    }
    It 'el informe incluye las secciones de etiquetado automático' {
        InModuleScope PurviewAssessment {
            $out = Join-Path ([IO.Path]::GetTempPath()) "PavAuto_$(Get-Random)"
            try {
                $r = Export-PurviewLabelReport -OutputPath $out -SkipExcel
                $h = Get-Content $r.HtmlPath -Raw
                $h | Should -Match 'Etiquetado autom'
                $h | Should -Match 'NotInOrganization'
                $h | Should -Match 'MX-CONT-Contratos'
            }
            finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
