#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Pruebas de la carga DLP (Fase 3b). Sin tenant: fixtures y stubs.

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Get-Module PurviewAssessment -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot 'PurviewAssessment.psd1') -Force -ErrorAction Stop

    # AdvancedRule realista (estructura tipo GNB del script original)
    $script:AdvFixture = @'
{
  "Version": "1.0",
  "Condition": {
    "Operator": "And",
    "SubConditions": [
      { "ConditionName": "ContentContainsSensitiveInformation",
        "Value": [ { "Groups": [ { "Name": "Default",
            "Sensitivetypes": [ { "Name": "CEDULA CO", "Mincount": 1, "Confidencelevel": "High" } ],
            "Labels": [ { "Name": "Confidencial", "Type": "Sensitivity", "Id": "lbl-1" } ] } ] } ] },
      { "ConditionName": "SenderDomainIs", "Value": [ "contoso.com", "fabrikam.com" ] },
      { "Operator": "Not", "SubConditions": [
          { "Operator": "Or", "SubConditions": [
              { "ConditionName": "SentTo", "Value": [ "a@x.com", "b@x.com", "c@x.com", "d@x.com", "e@x.com", "f@x.com" ] },
              { "ConditionName": "SubjectContainsWords", "Value": [ "Requerimiento" ] }
          ] }
      ] },
      { "ConditionName": "AccessScope", "Value": "NotInOrganization" }
    ]
  }
}
'@
}

Describe 'ConvertFrom-PavAdvancedRule' {
    It 'extrae SITs, Labels y AccessScope del árbol' {
        InModuleScope PurviewAssessment -Parameters @{ Adv = $script:AdvFixture } {
            param($Adv)
            Mock Write-PavLog { }
            $r = ConvertFrom-PavAdvancedRule $Adv
            $r.SensitiveInfoTypes | Should -Match 'CEDULA CO \| Mincount:1 \| Confidencelevel:High'
            $r.SensitivityLabels  | Should -Match 'Confidencial \(Sensitivity\) \[ID: lbl-1\]'
            $r.AccessScope        | Should -Be 'NotInOrganization'
        }
    }
    It 'árbol de texto: AND raíz, NOT/OR anidados, truncado de listas largas (>5)' {
        InModuleScope PurviewAssessment -Parameters @{ Adv = $script:AdvFixture } {
            param($Adv)
            Mock Write-PavLog { }
            $t = (ConvertFrom-PavAdvancedRule $Adv).ConditionsTree
            $t | Should -Match '(?m)^AND:'
            $t | Should -Match 'NOT:'
            $t | Should -Match 'OR:'
            $t | Should -Match '\[Default\] CEDULA CO'
            $t | Should -Match '\(\+3 mas, total: 6\)'     # SentTo con 6 valores
        }
    }
    It 'árbol HTML: clases pav-adv-* y contenido codificado' {
        InModuleScope PurviewAssessment -Parameters @{ Adv = $script:AdvFixture } {
            param($Adv)
            Mock Write-PavLog { }
            $h = (ConvertFrom-PavAdvancedRule $Adv).ConditionsHtml
            $h | Should -Match 'pav-adv-and'
            $h | Should -Match 'pav-adv-not'
            $h | Should -Match 'pav-adv-sit'
            $h | Should -Match 'NOT \(excepción\)'
        }
    }
    It 'JSON vacío o inválido devuelve resultado vacío sin excepción' {
        InModuleScope PurviewAssessment {
            Mock Write-PavLog { }
            (ConvertFrom-PavAdvancedRule '').ConditionsTree | Should -Be ''
            (ConvertFrom-PavAdvancedRule '{roto').ConditionsTree | Should -Be ''
        }
    }
}

Describe 'Helpers DLP' {
    It 'Resolve-PavSitValue: formato Groups y formato plano' {
        InModuleScope PurviewAssessment {
            $g = '[{"Groups":[{"Name":"G1","Sensitivetypes":[{"Name":"SSN","minCount":2}]}]}]'
            (Resolve-PavSitValue $g).SITs | Should -Match 'SSN \| Mincount:2'
            $flat = '[{"name":"Credit Card","id":"cc-1","mincount":"1"}]'
            (Resolve-PavSitValue $flat).SITs | Should -Match 'Credit Card \| Mincount:1'
        }
    }
    It 'Resolve-PavDlpLocation: All→Todos, objetos con Name, JSON string, vacío→No' {
        InModuleScope PurviewAssessment {
            $pol = [pscustomobject]@{
                A = 'All'
                B = @([pscustomobject]@{ Name = 'Sitio1' }, [pscustomobject]@{ DisplayName = 'Sitio2' })
                C = '[{"Name":"Buzon1"}]'
                D = @()
            }
            Resolve-PavDlpLocation -PropName A -PolicyObj $pol | Should -Be 'Todos'
            Resolve-PavDlpLocation -PropName B -PolicyObj $pol | Should -Be 'Sitio1; Sitio2'
            Resolve-PavDlpLocation -PropName C -PolicyObj $pol | Should -Be 'Buzon1'
            Resolve-PavDlpLocation -PropName D -PolicyObj $pol | Should -Be 'No'
            Resolve-PavDlpLocation -PropName Z -PolicyObj $pol | Should -Be 'No'
        }
    }
    It 'Resolve-PavScopedUsers: JSON REST → Nombre (smtp); vacíos → cadena vacía' {
        InModuleScope PurviewAssessment {
            $j = '[{"DisplayName":"Grupo Finanzas","PrimarySmtpAddress":"fin@contoso.com"}]'
            Resolve-PavScopedUsers $j | Should -Be 'Grupo Finanzas (fin@contoso.com)'
            Resolve-PavScopedUsers '{}' | Should -Be ''
            Resolve-PavScopedUsers $null | Should -Be ''
        }
    }
}

Describe 'Get-PurviewDlpData / Export-PurviewDlpReport (stubs, sin tenant)' {
    BeforeAll {
        InModuleScope PurviewAssessment -Parameters @{ Adv = $script:AdvFixture } {
            param($Adv)
            $script:__adv = $Adv
            Set-Item function:script:Get-DlpCompliancePolicy {
                param($ErrorAction)
                @(
                    [pscustomobject]@{ Name = 'PII Producción'; Guid = 'pol-1'; Enabled = $true; Mode = 'Enable'
                        ExchangeLocation = 'All'; SharePointLocation = @([pscustomobject]@{ Name = 'Sitio RH' })
                        Workload = 'Exchange, SharePoint'; Priority = 0 }
                    [pscustomobject]@{ Name = 'Vieja deshabilitada'; Guid = 'pol-2'; Enabled = $false; Mode = 'Disable'
                        ExchangeLocation = 'All'; Workload = 'Exchange'; Priority = 1 }
                )
            }
            Set-Item function:script:Get-DlpComplianceRule {
                param($Policy, $ErrorAction)
                @(
                    [pscustomobject]@{ Name = 'Regla avanzada'; Guid = 'r-1'; ParentPolicyName = 'PII Producción'
                        Disabled = $false; Priority = 0; AdvancedRule = $script:__adv
                        BlockAccess = $true; NotifyUser = 'LastModifier'; GenerateAlert = 'SiteAdmin'
                        FromMemberOf = '[{"DisplayName":"VIP","PrimarySmtpAddress":"vip@contoso.com"}]' }
                    [pscustomobject]@{ Name = 'Regla clásica'; Guid = 'r-2'; ParentPolicyName = 'PII Producción'
                        Disabled = $false; Priority = 1; AdvancedRule = $null
                        ContentContainsSensitiveInformation = '[{"Groups":[{"Name":"Default","Sensitivetypes":[{"Name":"IBAN","minCount":1}]}]}]'
                        SenderDomainIs = @('externo.com') }
                    [pscustomobject]@{ Name = 'Regla deshabilitada'; Guid = 'r-3'; ParentPolicyName = 'PII Producción'
                        Disabled = $true; Priority = 2; AdvancedRule = $null }
                ) | Where-Object { -not $Policy -or $_.ParentPolicyName -eq $Policy }
            }
            Mock Assert-PavConnection { }
            Mock Write-PavLog { }
        }
    }

    It 'filtra deshabilitadas por defecto y las incluye con -IncludeDisabled' {
        InModuleScope PurviewAssessment {
            $d = Get-PurviewDlpData
            $d.Policies.Count | Should -Be 1
            $d.Rules.Count    | Should -Be 2
            (Get-PurviewDlpData -IncludeDisabled).Rules.Count | Should -Be 3
        }
    }
    It 'regla avanzada: SITs/árbol desde AdvancedRule; usuarios con ámbito resueltos' {
        InModuleScope PurviewAssessment {
            $r = (Get-PurviewDlpData).Rules | Where-Object RuleName -eq 'Regla avanzada'
            $r.IsAdvancedRule | Should -Be 'Sí'
            $r.SensitiveInfoTypes | Should -Match 'CEDULA CO'
            $r.ConditionsTree | Should -Match 'AND:'
            $r.FromMemberOf | Should -Be 'VIP (vip@contoso.com)'
            $r.BlockAccess | Should -Be 'Sí'
        }
    }
    It 'regla clásica: SITs desde ContentContainsSensitiveInformation' {
        InModuleScope PurviewAssessment {
            $r = (Get-PurviewDlpData).Rules | Where-Object RuleName -eq 'Regla clásica'
            $r.IsAdvancedRule | Should -Be 'No'
            $r.SensitiveInfoTypes | Should -Match 'IBAN \| Mincount:1'
            $r.SenderDomainIs | Should -Be 'externo.com'
        }
    }
    It 'Export genera HTML con tabs, árbol AdvancedRule y badges' {
        InModuleScope PurviewAssessment {
            $out = Join-Path ([IO.Path]::GetTempPath()) "PavDlpTest_$(Get-Random)"
            try {
                $r = Export-PurviewDlpReport -OutputPath $out -ClientName 'Contoso' -SkipExcel
                $h = Get-Content $r.HtmlPath -Raw
                $h | Should -Match 'class="pav-tabs"'
                $h | Should -Match 'pav-adv-tree'
                $h | Should -Match 'pav-adv-not'
                $h | Should -Match 'AdvancedRule'
                $h | Should -Match 'CEDULA CO'
            }
            finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
