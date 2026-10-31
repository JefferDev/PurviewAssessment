@{
    RootModule           = 'PurviewAssessment.psm1'
    ModuleVersion        = '1.10.8'
    GUID                 = '63080730-0a23-4ba4-86c5-d531cc38cf92'
    Author               = 'Jefferson Castiblanco'
    CompanyName          = 'Jefferson Castiblanco'
    Copyright            = '(c) 2026 Jefferson Castiblanco. Todos los derechos reservados.'
    Description          = 'Assessment de solo lectura de cargas de trabajo de Microsoft Purview (MIP, DLP, IRM, Communication Compliance, DLM, SITs) con informes HTML y Excel consolidados. El modulo no realiza ninguna operacion de escritura sobre el tenant.'

    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')

    # NOTA DE DISENO: ExchangeOnlineManagement NO se declara en RequiredModules.
    # Motivo: el modo offline (p. ej. Get-PurviewSitData -XmlPath) debe funcionar
    # sin EXO instalado. La validacion de EXO >= 3.2.0 ocurre en runtime mediante
    # Assert-PavModule al invocar Connect-PurviewAssessment.
    RequiredModules      = @()

    FunctionsToExport    = @(
        'Connect-PurviewAssessment'
        'Disconnect-PurviewAssessment'
        'Test-PurviewAssessmentConnection'
        'Get-PurviewLabelData'
        'Export-PurviewLabelReport'
        'Get-PurviewDlpData'
        'Export-PurviewDlpReport'
        'Get-PurviewIrmData'
        'Export-PurviewIrmReport'
        'Invoke-PurviewControlEvaluation'
        'Export-PurviewControlReport'
        'Get-PurviewEdsData'
        'Export-PurviewEdsReport'
        'Get-PurviewAuditData'
        'Export-PurviewAuditReport'
        'Get-PurviewCcData'
        'Export-PurviewCcReport'
        'Get-PurviewDlmData'
        'Export-PurviewDlmReport'
        'Get-PurviewRmData'
        'Export-PurviewRmReport'
        'Get-PurviewSitData'
        'Export-PurviewSitReport'
        'Invoke-PurviewAssessment'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Purview', 'Compliance', 'Assessment', 'DLP', 'MIP', 'IRM', 'ReadOnly', 'Report')
            ProjectUri   = 'https://github.com/jefferdev/PurviewAssessment'
            LicenseUri   = 'https://github.com/jefferdev/PurviewAssessment/blob/main/LICENSE'
            ReleaseNotes = 'v1.10.8: el repositorio queda sin referencias a ninguna organizacion en manifiesto, fixtures, pruebas y ejemplos. Agrega publicacion por GitHub Releases e instalacion remota verificada por huella.'
        }

        # Metadatos propios del modulo (consumidos por Assert-PavModule y el gate)
        PavMinExoVersion      = '3.2.0'
        PavOptionalModules    = @(
            @{ Name = 'ImportExcel'; MinVersion = '7.8.0' }
        )
        PavSupportedWorkloads = @('Labels', 'DLP', 'IRM', 'CC', 'DLM', 'SIT')
    }
}
