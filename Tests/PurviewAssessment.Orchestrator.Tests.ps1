#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Pruebas del orquestador Invoke-PurviewAssessment (Fase 5).

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Get-Module PurviewAssessment -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot 'PurviewAssessment.psd1') -Force -ErrorAction Stop
    $script:FixtureXml = Join-Path $PSScriptRoot 'fixtures/rulepack-sample.xml'

    InModuleScope PurviewAssessment {
        # Stubs mínimos de las 6 cargas; IRM lanza error para probar resiliencia
        Set-Item function:script:Get-Label { param([switch]$IncludeDetailedLabelActions,$ErrorAction)
            @([pscustomobject]@{ Name='L1'; DisplayName='Etiqueta 1'; Guid='g1'; ImmutableId='i1'; Priority=1; ParentId=$null; IsParent=$false; Comment=''; Settings=@('[color, #fff]'); LocaleSettings=@(); LabelActions=@(); Workload='' }) }
        Set-Item function:script:Get-LabelPolicy { param($ErrorAction)
            @([pscustomobject]@{ Name='P1'; Guid='p1'; Type='PublishLabels'; Enabled=$true; Mode='Enable'; ScopedLabels=@('L1'); Settings=@('[mandatory, true]'); ExchangeLocation=@('All'); Workload='Exchange' }) }
        Set-Item function:script:Get-DlpCompliancePolicy { param($ErrorAction)
            @([pscustomobject]@{ Name='DLP1'; Guid='d1'; Enabled=$true; Mode='Enable'; ExchangeLocation='All'; Workload='Exchange'; Priority=0 }) }
        Set-Item function:script:Get-DlpComplianceRule { param($ErrorAction)
            @([pscustomobject]@{ Name='R1'; Guid='r1'; ParentPolicyName='DLP1'; Disabled=$false; Priority=0; AdvancedRule=$null; SenderDomainIs=@('x.com') }) }
        Set-Item function:script:Get-InsiderRiskPolicy { param($ErrorAction) throw 'AADSTS: sin rol IRM' }
        Set-Item function:script:Get-SupervisoryReviewPolicyV2 { param($ErrorAction)
            @([pscustomobject]@{ Name='CC1'; Guid='c1'; Enabled=$true; PolicyStatus='Active'; ProvisioningStatus='Success'; Mode='Enforce' }) }
        Set-Item function:script:Get-SupervisoryReviewRule { param($ErrorAction) @() }
        Set-Item function:script:Get-RetentionCompliancePolicy { param([switch]$DistributionDetail,$ErrorAction)
            @([pscustomobject]@{ Name='RET1'; Guid='dl1'; ExchangeObjectId='e1'; Type='Hold'; Mode='Enforce'; IsSimulation=$false; Enabled=$true; ExchangeLocation=@('All') }) }
        Set-Item function:script:Get-RetentionComplianceRule { param($ErrorAction) @() }
        Set-Item function:script:Get-ComplianceTag { param($ErrorAction) @() }
        Mock Write-PavLog { }
        $script:PavContext.Connected = $true
        Set-Item function:script:Test-PavSession { $true }
    }
}

Describe 'Invoke-PurviewAssessment' {
    It 'assessment full: resiliente ante fallo de IRM, genera consolidado + individuales + JSON' {
        InModuleScope PurviewAssessment -Parameters @{ Xml = $script:FixtureXml } {
            param($Xml)
            $out = Join-Path ([IO.Path]::GetTempPath()) "PavOrch_$(Get-Random)"
            try {
                $r = Invoke-PurviewAssessment -OutputPath $out -ClientName 'Cliente Demo' -SitXmlPath $Xml -SkipExcel
                $r.Workloads | Should -Contain 'MIP'      # Labels renombrado a MIP
                $r.Evaluated | Should -Not -Contain 'IRM'
                $r.Errors.Keys | Should -Contain 'IRM'
                # Sin numero fijo: el conteo se deriva de las cargas
                # resueltas menos las que fallaron, de modo que agregar
                # una carga nueva no rompa la prueba.
                @($r.Evaluated).Count | Should -Be (@($r.Workloads).Count - @($r.Errors.Keys).Count)
                @($r.Evaluated).Count | Should -BeGreaterThan 0
                Test-Path $r.ConsolidatedHtml | Should -BeTrue
                Test-Path $r.JsonBackup | Should -BeTrue
                $r.Reports.Keys | Should -Contain 'DLP'
                Test-Path $r.Reports['DLP'].HtmlPath | Should -BeTrue

                $h = Get-Content $r.ConsolidatedHtml -Raw
                # El numero exacto de pestañas depende de cuantas secciones
                # aporta cada carga, asi que se comprueba el invariante:
                # hay al menos una pestaña por carga evaluada, mas la de
                # la carga que fallo.
                ([regex]::Matches($h, '<button class="pav-tab')).Count |
                    Should -BeGreaterOrEqual (@($r.Evaluated).Count + 1)
                $h | Should -Match 'no fue evaluada'                        # sección IRM
                $h | Should -Match 'sin rol IRM'                            # motivo del error
                $h | Should -Match "$(@($r.Evaluated).Count) de $(@($r.Workloads).Count)"   # stat global
                $h | Should -Match 'Cedula CO'                              # SIT en consolidado
                $h | Should -Match 'pav-card'                               # detalle completo: tarjetas
                $h | Should -Match 'DLP (·|&#183;) '                                 # prefijo de pestañas
                $h | Should -Match '>Etiquetas MIP<'                        # título Labels solicitado
                $h | Should -Match 'Directivas - Etiquetas MIP'             # título directivas MIP
                $h | Should -Match 'rx-cedula'                              # regex resuelta (detalle SIT)
            }
            finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    It '-Workload selectivo genera solo esas cargas' {
        InModuleScope PurviewAssessment {
            $out = Join-Path ([IO.Path]::GetTempPath()) "PavOrch_$(Get-Random)"
            try {
                # 'Labels' es alias histórico: debe normalizarse a 'MIP'
                $r = Invoke-PurviewAssessment -Workload DLP, Labels -OutputPath $out -SkipExcel -SkipJsonBackup
                $r.Workloads | Should -Be @('DLP', 'MIP')
                $r.Evaluated.Count | Should -Be 2
                @(Get-ChildItem $out -Filter 'DLP_Report_*.html').Count | Should -Be 1
                @(Get-ChildItem $out -Filter 'IRM_*').Count | Should -Be 0
            }
            finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
