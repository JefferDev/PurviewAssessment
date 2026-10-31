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
            $r.RulePack.Name | Should -Be 'SITs Personalizados Ejemplo'
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
                $h | Should -Match 'SITs Personalizados Ejemplo'
            }
            finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Get-PurviewDlmData / Export-PurviewDlmReport (stubs)' {
    BeforeAll {
        InModuleScope PurviewAssessment {
            # Dos juegos deliberados: uno de ciclo de vida, que es lo que el
            # colector DLM debe devolver, y uno de gestion de registros, que
            # debe quedar fuera de DLM y aparecer en el ambito de registros.
            Set-Item function:script:Get-RetentionCompliancePolicy {
                param([switch]$DistributionDetail, $ErrorAction)
                @(
                    [pscustomobject]@{ Name = 'Retención Global'; Guid = 'dlm-1'; ExchangeObjectId = 'eo-1'
                        Type = 'Hold'; Mode = 'Enforce'; IsSimulation = $false; Enabled = $true; Priority = 0
                        DistributionStatus = 'Success'; Workload = 'Exchange'
                        ExchangeLocation = @('All'); SharePointLocation = @('https://x/sitio1')
                        SharePointLocationException = @('https://x/excluido'); IsAdaptivePolicy = $true }
                    [pscustomobject]@{ Name = 'Serie Documental'; Guid = 'rm-1'; ExchangeObjectId = 'eo-2'
                        Type = 'Hold'; Mode = 'Enforce'; IsSimulation = $false; Enabled = $true; Priority = 1
                        DistributionStatus = 'Success'; Workload = 'SharePoint'
                        ExchangeLocation = @(); SharePointLocation = @('https://x/expedientes')
                        SharePointLocationException = @(); IsAdaptivePolicy = $false }
                )
            }
            Set-Item function:script:Get-RetentionComplianceRule {
                param($ErrorAction)
                @(
                    [pscustomobject]@{ Name = 'Regla 7 años'; Guid = 'dlmr-1'; Policy = 'dlm-1'
                        RetentionComplianceAction = 'KeepAndDelete'; RetentionDuration = 2555
                        RetentionType = 'CreationAgeInDays'; PublishComplianceTag = 'guid,Etiqueta Fiscal'
                        ContentContainsSensitiveInformation = @([pscustomobject]@{ Name = 'NIT CO' }) }
                    [pscustomobject]@{ Name = 'Regla Expedientes'; Guid = 'rmr-1'; Policy = 'rm-1'
                        RetentionComplianceAction = 'Keep'; RetentionDuration = 3650
                        RetentionType = 'CreationAgeInDays'; PublishComplianceTag = 'guid,Expediente Contable'
                        ContentContainsSensitiveInformation = @() }
                )
            }
            Set-Item function:script:Get-ComplianceTag {
                param($ErrorAction)
                @(
                    # Etiqueta de ciclo de vida: sin file plan, sin declaracion
                    # de registro. Es la que pertenece al ambito DLM.
                    [pscustomobject]@{ Name = 'Etiqueta Fiscal'; Guid = 'tag-1'; Policy = 'dlm-1'
                        RetentionAction = 'KeepAndDelete'; RetentionDuration = 2555; RetentionType = 'CreationAgeInDays'
                        Regulatory = $false; IsRecordLabel = $false }
                    # Etiqueta de registro regulado, con file plan y revision
                    # por etapas: pertenece al ambito de gestion de registros.
                    [pscustomobject]@{ Name = 'Expediente Contable'; Guid = 'tag-2'; Policy = 'rm-1'
                        RetentionAction = 'Keep'; RetentionDuration = 3650; RetentionType = 'CreationAgeInDays'
                        Regulatory = $true; IsRecordLabel = $true
                        FilePlanMetadata = '{"Settings":[{"Key":"FilePlanPropertyDepartment","Value":"Finanzas"},{"Key":"FilePlanPropertyCitation","Value":"Ley 962"}]}'
                        MultiStageReviewerMetadata = '{"MultiStageReviewSettings":[{"StageId":1,"StageName":"Legal","Reviewers":["legal@ejemplo.com"]}]}' }
                )
            }
            Mock Assert-PavConnection { }
            Mock Write-PavLog { }
        }
    }
    It 'resuelve política por GUID, duración friendly, file plan y etapas' {
        InModuleScope PurviewAssessment {
            $d = Get-PurviewDlmData
            $regla = @($d.Rules | Where-Object PolicyName -eq 'Retención Global')[0]
            $regla.RetentionDuration    | Should -Be '7 año(s)'
            $regla.PublishComplianceTag | Should -Be 'Etiqueta Fiscal'
            $regla.SensitiveInfoTypes   | Should -Be 'NIT CO'
            @($d.FilePlans    | Where-Object Department -eq 'Finanzas').Count | Should -Be 1
            @($d.ReviewStages | Where-Object Reviewers  -eq 'legal@ejemplo.com').Count | Should -Be 1
            @($d.PolicyLocations | Where-Object { $_.Workload -eq 'SharePoint' -and $_.Exclusions -eq '1 excluido(s)' }).Count |
                Should -BeGreaterOrEqual 1
        }
    }

    It 'separa el ámbito de registros del de ciclo de vida sin mirar la nomenclatura' {
        InModuleScope PurviewAssessment {
            $d = Get-PurviewDlmData
            # La etiqueta de registro y su directiva salen del inventario DLM
            @($d.Tags).Name             | Should -Not -Contain 'Expediente Contable'
            @($d.Tags).Name             | Should -Contain 'Etiqueta Fiscal'
            @($d.RecordsScopeTags).Name | Should -Contain 'Expediente Contable'
            @($d.RecordsScopePolicies)  | Should -Contain 'Serie Documental'
            # El criterio es estructural, no el nombre del objeto
            @($d.Tags | Where-Object Name -eq 'Etiqueta Fiscal')[0].LabelCategory | Should -Be 'Standard Label'
        }
    }
    It 'Export genera HTML con 3 tabs y contenido' {
        InModuleScope PurviewAssessment {
            $out = Join-Path ([IO.Path]::GetTempPath()) "PavDlmTest_$(Get-Random)"
            try {
                $r = Export-PurviewDlmReport -OutputPath $out -SkipExcel
                $h = Get-Content $r.HtmlPath -Raw
                ($h | Select-String -Pattern 'class="pav-tab ' -AllMatches).Matches.Count + ($h | Select-String -Pattern 'class="pav-tab"' -AllMatches).Matches.Count | Should -BeGreaterOrEqual 3
                $h | Should -Match 'Etiqueta Fiscal'
                $h | Should -Match 'File Plan'
                # La revision multi-etapa es una capacidad de gestion de
                # registros: se verifica en el informe RM, no aqui.
                $h | Should -Not -Match 'Expediente Contable'
            }
            finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'SITs: múltiples RulePackages' {
    BeforeAll {
        $script:Fx1 = Join-Path $PSScriptRoot 'fixtures/rulepack-multi.xml'
        $script:Fx2 = Join-Path $PSScriptRoot 'fixtures/rulepack-sample.xml'
    }

    It 'modo offline acepta varias rutas y anota cada SIT con su paquete' {
        InModuleScope PurviewAssessment -Parameters @{ A = $script:Fx1; B = $script:Fx2 } {
            param($A, $B)
            Mock Write-PavLog { }
            $d = Get-PurviewSitData -XmlPath $A, $B
            @($d.RulePacks).Count | Should -Be 2
            @($d.Entities).Count  | Should -Be 4
            ($d.Entities | Where-Object Name -match 'ContratosProveedores').RulePackName | Should -Be 'RulePack Maestro Ejemplo'
            ($d.Entities | Where-Object Name -eq 'Cedula CO').RulePackName | Should -Be 'SITs Personalizados Ejemplo'
        }
    }

    It 'conserva RulePack singular por compatibilidad' {
        InModuleScope PurviewAssessment -Parameters @{ B = $script:Fx2 } {
            param($B)
            Mock Write-PavLog { }
            $d = Get-PurviewSitData -XmlPath $B
            $d.RulePack.Name | Should -Be 'SITs Personalizados Ejemplo'
            @($d.RulePacks).Count | Should -Be 1
        }
    }

    It 'en línea omite el catálogo de Microsoft y el de huellas, y procesa los personalizados' {
        InModuleScope PurviewAssessment -Parameters @{ A = $script:Fx1; B = $script:Fx2 } {
            param($A, $B)
            Mock Write-PavLog { }
            Mock Assert-PavConnection { }
            # Las rutas se fijan en variables del modulo: dentro del cuerpo de
            # una funcion definida con Set-Item, $using: no esta en alcance y
            # la ruta llegaba vacia, de modo que no se exportaba ningun paquete.
            $script:FxA = $using:A
            $script:FxB = $using:B
            Set-Item function:script:Get-DlpSensitiveInformationTypeRulePackage {
                param($Identity, $ErrorAction)
                $all = @(
                    [pscustomobject]@{ Identity=''; RuleCollectionName='Microsoft Rule Package'; Publisher='Microsoft Corporation'
                        IsFingerprintRuleCollection=$false; IsExportable=$true; rulePackSize=180; Version='1.0.0.0'; Description='' }
                    [pscustomobject]@{ Identity='cn=86C0380E-AE4F-4BCC-8127-59CA2D04E4EA'; RuleCollectionName='RulePack Maestro Ejemplo'
                        Publisher='Organizacion Ejemplo'; IsFingerprintRuleCollection=$false; IsExportable=$true; rulePackSize=4; Version='1.0.0.0'; Description='' }
                    [pscustomobject]@{ Identity='cn=00000000-0000-0000-0001-000000000001'; RuleCollectionName='Document Fingerprint Rule Package'
                        Publisher='tenant'; IsFingerprintRuleCollection=$true; IsExportable=$true; rulePackSize=11; Version='1'; Description='' }
                )
                if (-not $Identity) { return $all }
                $m = $all | Where-Object { $_.Identity -eq $Identity -or $_.RuleCollectionName -eq $Identity } | Select-Object -First 1
                $xml = if ($m.RuleCollectionName -match 'Maestro') { $script:FxA } else { $script:FxB }
                $m | Add-Member -NotePropertyName SerializedClassificationRuleCollection -NotePropertyValue ([IO.File]::ReadAllBytes($xml)) -Force
                $m
            }
            $d = Get-PurviewSitData -Online
            @($d.RulePacks).Count | Should -Be 1
            $d.RulePacks[0].Name  | Should -Be 'RulePack Maestro Ejemplo'
            $d.RulePacks[0].IsBuiltIn | Should -BeFalse
        }
    }
}

Describe 'Records Management (RM)' {
    BeforeAll {
        InModuleScope PurviewAssessment {
            Set-Item function:script:Get-FilePlanPropertyDepartment { param($ErrorAction)
                @([pscustomobject]@{ Name='Finance'; DisplayName='Finance'; FilePlanPropertyType='Department'; Priority=0; Disabled=$false; IsValid=$true }
                  [pscustomobject]@{ Name='Recursos Humanos'; DisplayName='Recursos Humanos'; FilePlanPropertyType='Department'; Priority=0; Disabled=$false; IsValid=$true }
                  [pscustomobject]@{ Name='Recursos  Humanós'; DisplayName='Recursos  Humanós'; FilePlanPropertyType='Department'; Priority=0; Disabled=$false; IsValid=$true }) }
            Set-Item function:script:Get-FilePlanPropertyCitation { param($ErrorAction)
                @([pscustomobject]@{ Name='LFT Art. 804'; DisplayName='LFT Art. 804'; FilePlanPropertyType='Citation'
                     CitationUrl='https://x/LFT.pdf'; CitationJurisdiction='STPS'; Priority=2; Disabled=$false; IsValid=$true }
                  [pscustomobject]@{ Name='Sin norma'; DisplayName='Sin norma'; FilePlanPropertyType='Citation'
                     CitationUrl=''; CitationJurisdiction=''; Priority=3; Disabled=$false; IsValid=$true }) }
            foreach ($c in 'Get-FilePlanPropertyCategory','Get-FilePlanPropertySubCategory','Get-FilePlanPropertyAuthority','Get-FilePlanPropertyReferenceId') {
                Set-Item "function:script:$c" { param($ErrorAction) @() }
            }
            Set-Item function:script:Get-ComplianceRetentionEventType { param([switch]$LoadTag, $ErrorAction)
                @([pscustomobject]@{ Name='Terminacion Laboral'; Comment='Baja'; Priority=0; Disabled=$false; IsValid=$true
                     ComplianceTags=@('FFO.../Configuration/Expedientes - Registro (5 anios)') }
                  [pscustomobject]@{ Name='Evento huerfano'; Comment=''; Priority=1; Disabled=$false; IsValid=$true; ComplianceTags=@() }) }
            Set-Item function:script:Get-ComplianceRetentionEvent { param($ErrorAction) @() }
            Set-Item function:script:Get-AdaptiveScope { param($ErrorAction) @() }
            Set-Item function:script:Get-ComplianceTag { param($ErrorAction)
                @([pscustomobject]@{ Name='Expedientes - Registro (5 anios)'; Guid='t1'; IsRecordLabel=$true; Regulatory=$true
                     RetentionAction='KeepAndDelete'; RetentionDuration=1825; RetentionType='EventAgeInDays'; EventTypeId='e1'
                     FilePlanMetadata='{"Settings":[{"Key":"FilePlanPropertyDepartment","Value":"Recursos Humanos"}]}'
                     MultiStageReviewerMetadata='{"MultiStageReviewSettings":[{"StageId":1}]}'; ReviewerEmail=@(); Workload='Exchange' }
                  [pscustomobject]@{ Name='Registro sin plan'; Guid='t2'; IsRecordLabel=$true; Regulatory=$false
                     RetentionAction='KeepAndDelete'; RetentionDuration=2555; RetentionType='CreationAgeInDays'; EventTypeId=''
                     FilePlanMetadata=''; MultiStageReviewerMetadata=''; ReviewerEmail=@(); Workload='Exchange' }
                  [pscustomobject]@{ Name='No es registro'; Guid='t3'; IsRecordLabel=$false; Regulatory=$false
                     RetentionAction='Keep'; RetentionDuration=365; RetentionType='CreationAgeInDays'; EventTypeId=''
                     FilePlanMetadata=''; MultiStageReviewerMetadata=''; ReviewerEmail=@(); Workload='Exchange' }) }
            Mock Assert-PavConnection { }
            Mock Write-PavLog { }
        }
    }

    It 'recolecta descriptores y solo etiquetas declaradas como registro' {
        InModuleScope PurviewAssessment {
            $d = Get-PurviewRmData
            @($d.FilePlanProperties).Count | Should -Be 5
            @($d.RecordTags).Count | Should -Be 2      # excluye la etiqueta que no es registro
            ($d.RecordTags | Where-Object Regulatory).Name | Should -Match 'Expedientes'
        }
    }
    It 'resuelve las etiquetas asociadas a cada tipo de evento (-LoadTag)' {
        InModuleScope PurviewAssessment {
            $et = (Get-PurviewRmData).EventTypes | Where-Object Name -eq 'Terminacion Laboral'
            $et.LinkedLabelCount | Should -Be 1
            $et.LinkedLabels | Should -Be 'Expedientes - Registro (5 anios)'
        }
    }
    It 'deriva hallazgos: citación sin norma, evento sin etiquetas, registro sin file plan y duplicados' {
        InModuleScope PurviewAssessment {
            $f = (Get-PurviewRmData).Findings
            @($f | Where-Object Finding -match 'Citación sin referencia').Count | Should -Be 1
            @($f | Where-Object Finding -match 'Tipo de evento sin etiquetas').Count | Should -Be 1
            @($f | Where-Object Finding -match 'sin file plan').Count | Should -Be 1
            @($f | Where-Object Finding -match 'duplicados').Count | Should -BeGreaterOrEqual 1
        }
    }
    It '-SkipFindings omite el análisis' {
        InModuleScope PurviewAssessment {
            @((Get-PurviewRmData -SkipFindings).Findings).Count | Should -Be 0
        }
    }
    It 'genera el informe con las secciones esperadas' {
        InModuleScope PurviewAssessment {
            $out = Join-Path ([IO.Path]::GetTempPath()) "PavRm_$(Get-Random)"
            try {
                $r = Export-PurviewRmReport -OutputPath $out -SkipExcel
                $h = Get-Content $r.HtmlPath -Raw
                $h | Should -Match 'Hallazgos de gobierno'
                $h | Should -Match 'File plan'
                $h | Should -Match 'Sin etiquetas asociadas'
                $h | Should -Match 'STPS'
            }
            finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
