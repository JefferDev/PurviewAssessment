#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Pruebas de la capa de evaluación de controles.

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Get-Module PurviewAssessment -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot 'PurviewAssessment.psd1') -Force -ErrorAction Stop

    # Datos MIP equivalentes a un despliegue con clasificación voluntaria
    $script:MipData = [pscustomobject]@{
        PSTypeName = 'PurviewAssessment.LabelData'
        Labels = @(
            [pscustomobject]@{ DisplayName='Publico'; Priority=1; IsParent=$true; ParentId=''; HasEncryption=$false
                HasContentMarking=$false; WhenChangedUTC=(Get-Date).AddDays(-30) }
            [pscustomobject]@{ DisplayName='Confidencial'; Priority=2; IsParent=$true; ParentId=''; HasEncryption=$true
                HasContentMarking=$true; WhenChangedUTC=(Get-Date).AddDays(-30) }
            [pscustomobject]@{ DisplayName='Confidencial\Todos'; Priority=3; IsParent=$false; ParentId='g2'
                HasEncryption=$true; HasContentMarking=$true; WhenChangedUTC=(Get-Date).AddDays(-30) }
        )
        Policies = @(
            [pscustomobject]@{ Name='Global'; Mandatory=$false; DefaultLabelId=''; OutlookDefaultLabelId=''
                RequireDowngradeJustification=$false }
        )
        AutoLabelPolicies = @(
            [pscustomobject]@{ Name='AL-1'; Mode='TestWithoutNotifications'; ModeFriendly='Simulación (no etiqueta)' }
        )
        AutoLabelRules = @(
            [pscustomobject]@{ RuleName='R1'; SensitiveInfoTypes='Credit Card Number | Mincount:1' }
        )
        CollectedAt = Get-Date
    }
}

Describe 'Catálogo de controles' {
    It 'carga y declara identificadores propios con el esquema PAV-<DOM>-<NN>' {
        $cat = Import-PowerShellDataFile (Join-Path $ModuleRoot 'Controls/PavControlCatalog.psd1')
        $cat.CatalogVersion | Should -Not -BeNullOrEmpty
        @($cat.Controls).Count | Should -BeGreaterOrEqual 10
        foreach ($c in $cat.Controls) {
            $c.Id | Should -Match '^PAV-[A-Z]{2,3}-\d{2}$'
            $c.Title    | Should -Not -BeNullOrEmpty
            $c.Severity | Should -BeIn @('Alta', 'Media', 'Baja')
            $c.Type     | Should -BeIn @('Technical', 'Process', 'Hybrid')
        }
    }
    It 'cada evaluador declarado existe en el módulo' {
        $cat = Import-PowerShellDataFile (Join-Path $ModuleRoot 'Controls/PavControlCatalog.psd1')
        InModuleScope PurviewAssessment -Parameters @{ Ctrls = $cat.Controls } {
            param($Ctrls)
            foreach ($c in $Ctrls) {
                if ($c.Evaluator) {
                    Get-Command $c.Evaluator -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty -Because "$($c.Id) declara $($c.Evaluator)"
                }
            }
        }
    }
}

Describe 'Invoke-PurviewControlEvaluation' {
    BeforeAll { InModuleScope PurviewAssessment { Mock Write-PavLog { } } }

    It 'evalúa los controles de MIP mas los transversales de IA y calcula el puntaje' {
        # MIP aporta 10 controles; los 8 de gobierno de IA son transversales
        # (Workload = MULTI) y se evaluan junto a cualquier carga solicitada.
        $ev = Invoke-PurviewControlEvaluation -Data @{ MIP = $script:MipData }
        @($ev.Results).Count | Should -Be 18
        $ev.OverallScore | Should -BeGreaterOrEqual 0
        $ev.OverallScore | Should -BeLessOrEqual 100
        @($ev.DomainScores).Count | Should -Be 2
        @($ev.DomainScores).Domain | Should -Contain 'MIP'
        @($ev.DomainScores).Domain | Should -Contain 'AI'
    }

    It 'detecta el etiquetado automático en simulación como NO implementado' {
        # El control que distingue existir de estar operando
        $r = (Invoke-PurviewControlEvaluation -Data @{ MIP = $script:MipData }).Results |
             Where-Object Id -eq 'PAV-MIP-08'
        $r.Status   | Should -Be 'NotImplemented'
        $r.Evidence | Should -Match 'simulación'
        $r.Evidence | Should -Match 'AL-1'      # evidencia con el objeto concreto
    }

    It 'toda evidencia cita el objeto o el valor que sustenta el veredicto' {
        $ev = Invoke-PurviewControlEvaluation -Data @{ MIP = $script:MipData }
        foreach ($r in $ev.Results) { $r.Evidence | Should -Not -BeNullOrEmpty -Because "$($r.Id) debe justificar su veredicto" }
    }

    It 'sin datos de la carga marca RequiresValidation, nunca NotImplemented' {
        # Una carga solicitada cuya recoleccion vino vacia es un colector que
        # fallo: sus controles deben quedar en RequiresValidation, nunca
        # desaparecer del informe ni darse por no implementados.
        $ev = Invoke-PurviewControlEvaluation -Data @{ DLP = $null }
        @($ev.Results).Count | Should -Be 20
        @($ev.Results | Where-Object Status -eq 'NotImplemented').Count | Should -Be 0
        @($ev.Results | Where-Object Status -eq 'RequiresValidation').Count | Should -Be 20
    }

    It 'las respuestas de entrevista prevalecen y quedan marcadas como declaradas' {
        $ev = Invoke-PurviewControlEvaluation -Data @{ MIP = $script:MipData } -InterviewResponses @{
            'PAV-MIP-05' = @{ Status = 'Implemented'; Evidence = 'Política interna vigente desde 2025' }
        }
        $r = $ev.Results | Where-Object Id -eq 'PAV-MIP-05'
        $r.Status | Should -Be 'Implemented'
        $r.Source | Should -Be 'Declarado por el cliente'
    }

    It 'el umbral de obsolescencia es parametrizable' {
        $viejo = [pscustomobject]@{
            PSTypeName='PurviewAssessment.LabelData'
            Labels=@([pscustomobject]@{ DisplayName='L'; Priority=1; IsParent=$true; ParentId=''
                HasEncryption=$true; HasContentMarking=$true; WhenChangedUTC=(Get-Date).AddDays(-400) })
            Policies=@(); AutoLabelPolicies=@(); AutoLabelRules=@(); CollectedAt=Get-Date }
        ((Invoke-PurviewControlEvaluation -Data @{ MIP = $viejo } -StaleDays 365).Results |
            Where-Object Id -eq 'PAV-MIP-10').Status | Should -Be 'NotImplemented'
        ((Invoke-PurviewControlEvaluation -Data @{ MIP = $viejo } -StaleDays 500).Results |
            Where-Object Id -eq 'PAV-MIP-10').Status | Should -Be 'Implemented'
    }

    It 'genera el informe de evaluación' {
        $out = Join-Path ([IO.Path]::GetTempPath()) "PavCtrl_$(Get-Random)"
        try {
            $ev = Invoke-PurviewControlEvaluation -Data @{ MIP = $script:MipData }
            $r = Export-PurviewControlReport -Evaluation $ev -OutputPath $out -SkipExcel
            $h = Get-Content $r.HtmlPath -Raw
            $h | Should -Match 'PAV-MIP-08'
            $h | Should -Match 'Impacto de negocio'
        }
        finally { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Controles del dominio DLP' {
    BeforeAll {
        InModuleScope PurviewAssessment { Mock Write-PavLog { } }
        $script:DlpData = [pscustomobject]@{
            PSTypeName = 'PurviewAssessment.DlpData'
            Policies = @(
                [pscustomobject]@{ Name='DLP PII'; Enabled=$true; Mode='Enable'; ExchangeLocation='Todos'
                    SharePointLocation='Todos'; OneDriveLocation='Todos'; TeamsLocation='No'
                    EndpointDlpLocation='No'; WhenChanged=(Get-Date).AddDays(-20) }
                [pscustomobject]@{ Name='DLP Legacy'; Enabled=$false; Mode='Enable'; ExchangeLocation='Todos'
                    WhenChanged=(Get-Date).AddDays(-1100) }
            )
            Rules = @(
                [pscustomobject]@{ PolicyName='DLP PII'; RuleName='R1'; Disabled='No'
                    SensitiveInfoTypes='MX-CURP-Empleados | Mincount:1'; BlockAccess='Sí'
                    NotifyUser='LastModifier'; NotifyPolicyTipCustomText='Aviso'; GenerateAlert='SiteAdmin'
                    GenerateIncidentReport='SiteAdmin'; ReportSeverityLevel='High'; ConditionsTree='' }
            )
            CollectedAt = Get-Date
        }
        $script:SitData = [pscustomobject]@{ PSTypeName='PurviewAssessment.SitData'
            Entities = @([pscustomobject]@{ Name='MX-CURP-Empleados' }, [pscustomobject]@{ Name='MX-No-Usado' }) }
    }

    It 'evalúa los doce controles del dominio' {
        $ev = Invoke-PurviewControlEvaluation -Data @{ DLP = $script:DlpData } -Domain DLP
        @($ev.Results).Count | Should -Be 12
    }

    It 'detecta los SIT personalizados en uso cruzando con la carga SIT' {
        $r = (Invoke-PurviewControlEvaluation -Data @{ DLP = $script:DlpData; SIT = $script:SitData } -Domain DLP).Results |
             Where-Object Id -eq 'PAV-DLP-01'
        $r.Status   | Should -Be 'Implemented'
        $r.Evidence | Should -Match 'MX-CURP-Empleados'
    }

    It 'sin la carga SIT no afirma ni niega el uso de SIT propios' {
        $r = (Invoke-PurviewControlEvaluation -Data @{ DLP = $script:DlpData } -Domain DLP).Results |
             Where-Object Id -eq 'PAV-DLP-01'
        $r.Status | Should -Be 'RequiresValidation'
    }

    It 'la ausencia de reglas de salud requiere validación, no es incumplimiento' {
        # El control es condicional: depende de si el negocio trata ese dato
        $r = (Invoke-PurviewControlEvaluation -Data @{ DLP = $script:DlpData } -Domain DLP).Results |
             Where-Object Id -eq 'PAV-DLP-04'
        $r.Status | Should -Be 'RequiresValidation'
    }

    It 'señala la cobertura parcial de cargas de trabajo' {
        $r = (Invoke-PurviewControlEvaluation -Data @{ DLP = $script:DlpData } -Domain DLP).Results |
             Where-Object Id -eq 'PAV-DLP-06'
        $r.Status   | Should -Be 'PartiallyImplemented'
        $r.Evidence | Should -Match 'Teams'
    }

    It 'detecta el inventario inerte: deshabilitado y sin mantenimiento' {
        $r = (Invoke-PurviewControlEvaluation -Data @{ DLP = $script:DlpData } -Domain DLP -StaleDays 365).Results |
             Where-Object Id -eq 'PAV-DLP-10'
        $r.Status   | Should -Be 'NotImplemented'
        $r.Evidence | Should -Match 'DLP Legacy'
    }

    It 'los controles de proceso quedan a la espera de la entrevista' {
        $ev = Invoke-PurviewControlEvaluation -Data @{ DLP = $script:DlpData } -Domain DLP
        foreach ($id in 'PAV-DLP-11', 'PAV-DLP-12') {
            $c = $ev.Results | Where-Object Id -eq $id
            $c.Status | Should -Be 'RequiresValidation'
            $c.Source | Should -Be 'Pendiente de entrevista'
        }
    }

    It 'clasifica categorías de dato por el texto del tipo de información sensible' {
        InModuleScope PurviewAssessment {
            Get-PavDlpSitCategory 'MX-CURP-Empleados'      | Should -Contain 'PII'
            Get-PavDlpSitCategory 'Credit Card Number'     | Should -Contain 'Financiero'
            Get-PavDlpSitCategory 'Expediente Medico'      | Should -Contain 'Salud'
            @(Get-PavDlpSitCategory 'Codigo interno XYZ').Count | Should -Be 0
        }
    }
}
