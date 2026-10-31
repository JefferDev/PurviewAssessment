#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    Pruebas del núcleo del módulo (Fase 1):
    manifiesto válido, importación limpia y superficie pública exacta.
    Ejecución: Invoke-Pester -Path .\Tests
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    $script:Manifest   = Join-Path $ModuleRoot 'PurviewAssessment.psd1'
    Get-Module PurviewAssessment -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $Manifest -Force -ErrorAction Stop
}

Describe 'Manifiesto PurviewAssessment.psd1' {
    It 'Test-ModuleManifest lo valida sin errores' {
        { Test-ModuleManifest -Path $Manifest -ErrorAction Stop } | Should -Not -Throw
    }

    It 'declara PowerShell 7.2 y edición Core (decisión #1)' {
        $m = Test-ModuleManifest -Path $Manifest
        $m.PowerShellVersion | Should -Be ([version]'7.2')
        $m.CompatiblePSEditions | Should -Contain 'Core'
    }

    It 'tiene GUID real (no placeholder)' {
        $m = Test-ModuleManifest -Path $Manifest
        $m.Guid | Should -Not -Be ([guid]::Empty)
    }

    It 'declara la versión mínima de EXO en PrivateData' {
        $m = Import-PowerShellDataFile -Path $Manifest
        $m.PrivateData.PavMinExoVersion | Should -Be '3.2.0'
    }
}

Describe 'Superficie pública del módulo' {
    It 'exporta exactamente las funciones publicadas' {
        $exported = (Get-Module PurviewAssessment).ExportedFunctions.Keys | Sort-Object
        $exported | Should -Be @(
            'Connect-PurviewAssessment'
            'Disconnect-PurviewAssessment'
            'Export-PurviewAuditReport'
            'Export-PurviewCcReport'
            'Export-PurviewControlReport'
            'Export-PurviewDlmReport'
            'Export-PurviewEdsReport'
            'Export-PurviewDlpReport'
            'Export-PurviewIrmReport'
            'Export-PurviewLabelReport'
            'Export-PurviewRmReport'
            'Export-PurviewSitReport'
            'Get-PurviewAuditData'
            'Get-PurviewCcData'
            'Get-PurviewDlmData'
            'Get-PurviewEdsData'
            'Get-PurviewDlpData'
            'Get-PurviewIrmData'
            'Get-PurviewLabelData'
            'Get-PurviewRmData'
            'Get-PurviewSitData'
            'Invoke-PurviewControlEvaluation'
            'Invoke-PurviewAssessment'
            'Test-PurviewAssessmentConnection'
        )
    }

    It 'NO expone los helpers privados' {
        foreach ($helper in 'Write-PavLog', 'Test-PavSession', 'Assert-PavModule', 'Assert-PavConnection', 'Invoke-PavRetry') {
            Get-Command $helper -Module PurviewAssessment -ErrorAction SilentlyContinue |
                Should -BeNullOrEmpty -Because "$helper es privado"
        }
    }

    It 'todas las funciones públicas usan verbos aprobados' {
        $verbs = (Get-Verb).Verb
        foreach ($fn in (Get-Module PurviewAssessment).ExportedFunctions.Keys) {
            ($fn -split '-')[0] | Should -BeIn $verbs
        }
    }

    It 'todas las funciones públicas tienen ayuda con Synopsis y ejemplo' {
        foreach ($fn in (Get-Module PurviewAssessment).ExportedFunctions.Keys) {
            $help = Get-Help $fn
            $help.Synopsis | Should -Not -BeNullOrEmpty -Because "$fn debe tener .SYNOPSIS"
            $help.Examples | Should -Not -BeNullOrEmpty -Because "$fn debe tener .EXAMPLE"
        }
    }
}
