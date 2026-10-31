function Export-PurviewDlpReport {
<#
.SYNOPSIS
    Genera el informe DLP (HTML + Excel).
.DESCRIPTION
    HTML con el motor compartido: pestañas Directivas/Reglas, tarjetas
    colapsables, badges de modo/estado, y el árbol lógico de AdvancedRule
    renderizado (And/Or/Not, grupos de SITs, excepciones).
    Excel: 5 hojas — Resumen Directivas, Detalle Directivas, Resumen
    Reglas, Detalle Reglas (formato largo con el detalle técnico completo
    de ~80 propiedades por regla) y Condiciones (árbol de AdvancedRule
    en texto).
.PARAMETER Data
    Datos de Get-PurviewDlpData. Si se omite, se recolectan.
.PARAMETER OutputPath
    Carpeta de salida.
.PARAMETER ClientName
    Nombre del cliente para portada y pie.
.PARAMETER IncludeDisabled
    Se propaga al colector cuando -Data no se proporciona.
.PARAMETER HideInconclusiveWarnings
    Oculta los avisos derivados de propiedades que el servicio no reporta de
    forma concluyente.
.PARAMETER SkipExcel
    Omite el libro Excel.
.OUTPUTS
    [pscustomobject] con HtmlPath y ExcelPath.
.EXAMPLE
    Connect-PurviewAssessment
    Export-PurviewDlpReport -OutputPath C:\Reports -ClientName 'Cliente Demo' -IncludeDisabled
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)]
        [PSTypeName('PurviewAssessment.DlpData')]
        [object]$Data,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [string]$ClientName = '',

        [switch]$IncludeDisabled,
        [switch]$SkipExcel,

        # Oculta los avisos derivados de propiedades no concluyentes
        [switch]$HideInconclusiveWarnings
    )

    process {
        if ($PSBoundParameters.ContainsKey('HideInconclusiveWarnings')) { $script:PavHideInconclusive = [bool]$HideInconclusiveWarnings }
        if (-not $Data) { $Data = Get-PurviewDlpData -IncludeDisabled:$IncludeDisabled }
        if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

        $ts       = Get-Date -Format 'yyyy-MM-dd_HH-mm'
        $htmlPath = Join-Path $OutputPath "DLP_Report_$ts.html"
        $xlsxPath = Join-Path $OutputPath "DLP_Report_$ts.xlsx"
        $policies = @($Data.Policies)
        $rules    = @($Data.Rules)

        # ══ HTML ═════════════════════════════════════════════════════════════
        Write-PavLog -Level Step -Message 'Generando informe HTML de DLP...'

        $sections = New-PavDlpSections -Data $Data

        $doc = New-PavHtmlDocument -Title 'DLP — Microsoft Purview' `
            -Subtitle 'Assessment de prevención de pérdida de datos (solo lectura)' `
            -ClientName $ClientName -Sections $sections `
            -StatsHtml (New-PavStatGroup -Stats (
                (New-PavStat -Label 'Directivas' -Value "$($policies.Count)"),
                (New-PavStat -Label 'Reglas' -Value "$($rules.Count)")
            ))
        $doc | Set-Content -Path $htmlPath -Encoding UTF8
        Write-PavLog -Level Success -Message "Informe HTML: $htmlPath"

        # ══ Excel ════════════════════════════════════════════════════════════
        $excelPath = $null
        if (-not $SkipExcel) {
            $estado = { param($r) if ($r.Disabled -eq 'Sí') { 'Deshabilitada' } else { 'Habilitada' } }
            $trunc  = { param($v) $s = "$v"; if ($s.Length -gt 32000) { $s.Substring(0,32000) + ' ...[TRUNCADO]' } else { $s } }

            # 1 ── Resumen Ejecutivo (Metrica/Valor, formato del export v2.1)
            $resumen = @(
                [pscustomobject]@{ Metrica = 'Total Directivas DLP';       Valor = $policies.Count }
                [pscustomobject]@{ Metrica = 'Directivas Habilitadas';     Valor = @($policies | Where-Object Enabled).Count }
                [pscustomobject]@{ Metrica = 'Directivas Deshabilitadas';  Valor = @($policies | Where-Object { -not $_.Enabled }).Count }
                [pscustomobject]@{ Metrica = 'Directivas en Test/Auditoria'; Valor = @($policies | Where-Object Mode -match 'Test|Audit').Count }
                [pscustomobject]@{ Metrica = 'Total Reglas DLP';           Valor = $rules.Count }
                [pscustomobject]@{ Metrica = 'Reglas Habilitadas';         Valor = @($rules | Where-Object Disabled -eq 'No').Count }
                [pscustomobject]@{ Metrica = 'Reglas Deshabilitadas';      Valor = @($rules | Where-Object Disabled -eq 'Sí').Count }
                [pscustomobject]@{ Metrica = 'Reglas con AdvancedRule';    Valor = @($rules | Where-Object IsAdvancedRule -eq 'Sí').Count }
                [pscustomobject]@{ Metrica = 'Cliente';                    Valor = $ClientName }
                [pscustomobject]@{ Metrica = 'Fecha';                      Valor = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
                [pscustomobject]@{ Metrica = 'Generado por';               Valor = "PurviewAssessment v$((Get-Module PurviewAssessment).Version)" }
            )

            # 2 ── Directivas DLP (columnas del export original)
            $shPolicies = foreach ($p in $policies) {
                [pscustomobject]@{
                    'Nombre' = $p.Name
                    'Estado' = if ($p.Enabled) { 'Habilitada' } else { 'Deshabilitada' }
                    'Modo' = $p.Mode; 'Descripcion' = $p.Comment
                    'Creada' = $p.WhenCreated; 'Modificada' = $p.WhenChanged; 'Prioridad' = $p.Priority
                    'Exchange' = $p.ExchangeLocation; 'SharePoint' = $p.SharePointLocation
                    'OneDrive' = $p.OneDriveLocation; 'Teams' = $p.TeamsLocation
                    'Teams Channel' = $p.TeamsChannelLocation; 'Endpoint' = $p.EndpointDlpLocation
                    '3rd Party App' = $p.ThirdPartyAppDlpLocation; 'On-Premises' = $p.OnPremisesScannerDlpLocation
                    'PowerBI' = $p.PowerBIDlpLocation
                    'SPO Excepcion' = $p.SharePointLocationException; 'ODB Excepcion' = $p.OneDriveLocationException
                    'Teams Excepcion' = $p.TeamsLocationException; 'Endpoint Excepcion' = $p.EndpointDlpLocationException
                    'Exchange Sender' = $p.ExchangeSender; 'Exchange Sender Exc' = $p.ExchangeSenderException
                    'Usuarios Incluidos (MemberOf)' = $p.UsersIncluded; 'Usuarios Excluidos (MemberOf)' = $p.UsersExcluded
                    'Creada Por' = $p.CreatedBy; 'Modificada Por' = $p.LastModifiedBy
                    'Num Reglas' = @($rules | Where-Object PolicyName -eq $p.Name).Count
                    'GUID' = $p.Guid
                }
            }

            # 3 ── Reglas - Condiciones
            $shCond = foreach ($r in $rules) {
                [pscustomobject]@{
                    'Directiva' = $r.PolicyName; 'Regla' = $r.RuleName; 'Estado' = (& $estado $r)
                    'Prioridad' = $r.Priority; 'Workload' = $r.Workload; 'Severidad' = $r.ReportSeverityLevel
                    'Avanzada' = $r.IsAdvancedRule
                    'Tipos Info Sensible' = $r.SensitiveInfoTypes; 'Etiquetas Sensibilidad' = $r.SensitivityLabels
                    'Access Scope' = $(if ($r.AccessScopeAdv) { $r.AccessScopeAdv } else { $r.AccessScope })
                    'From Scope' = $r.FromScope
                    'Dominio Remitente' = $r.SenderDomainIs; 'Dominio Destinatario' = $r.RecipientDomainIs
                    'De' = $r.From; 'De Miembro De' = $r.FromMemberOf
                    'Enviado A' = $r.SentTo; 'Enviado A Miembro De' = $r.SentToMemberOf
                    'Compartido con' = $r.SharedWithDomain; 'IP Remitente' = $r.SenderIPRanges; 'Tipo Remitente' = $r.SenderType
                    'Extensiones' = $r.ContentExtensionMatchesWords; 'Tipo Archivo' = $r.ContentFileTypeMatches
                    'Doc Nombre Palabras' = $r.DocumentNameMatchesWords; 'Doc Nombre Patron' = $r.DocumentNameMatchesPatterns
                    'Doc Contiene' = $r.DocumentContainsWords
                    'Subject Contiene' = $r.SubjectContainsWords; 'Subject Patron' = $r.SubjectMatchesPatterns
                    'Subject/Body' = $r.SubjectOrBodyContainsWords
                    'Header Contiene' = $r.HeaderContainsWords; 'Header Patron' = $r.HeaderMatchesPatterns
                    'From Address' = $r.FromAddressContainsWords; 'Recipient Address' = $r.AnyOfRecipientAddressContainsWords
                    'Doc Protegido' = $r.DocumentIsPasswordProtected; 'Doc No Soportado' = $r.DocumentIsUnsupported
                    'Sin Etiqueta' = $r.ContentIsNotLabeled; 'Adjunto Sin Etiqueta' = $r.AttachmentIsNotLabeled
                    'Msg Sin Etiqueta' = $r.MessageIsNotLabeled
                    'Compartido' = $r.ContentIsShared; 'Override' = $r.HasSenderOverride; 'Limite Proc' = $r.ProcessingLimitExceeded
                    'Tipo Mensaje' = $r.MessageTypeMatches; 'Importancia' = $r.WithImportance
                    'Tam Doc' = $r.DocumentSizeOver; 'Tam Msg' = $r.MessageSizeOver
                    'Cond Avanzada (Arbol)' = (& $trunc $r.ConditionsTree)
                    'GUID' = $r.RuleGuid
                }
            }

            # 4 ── Reglas - Excepciones
            $shExc = foreach ($r in $rules) {
                [pscustomobject]@{
                    'Directiva' = $r.PolicyName; 'Regla' = $r.RuleName; 'Estado' = (& $estado $r)
                    'Exc Info Sensible' = $r.ExceptIfSensitiveInfoTypes
                    'Exc Dom Remitente' = $r.ExceptIfSenderDomainIs; 'Exc Dom Destinatario' = $r.ExceptIfRecipientDomainIs
                    'Exc De' = $r.ExceptIfFrom; 'Exc De Miembro' = $r.ExceptIfFromMemberOf
                    'Exc Enviado A' = $r.ExceptIfSentTo; 'Exc Enviado Miembro' = $r.ExceptIfSentToMemberOf
                    'Exc Dom Compartido' = $r.ExceptIfSharedWithDomain
                    'Exc Access Scope' = $r.ExceptIfAccessScope; 'Exc From Scope' = $r.ExceptIfFromScope
                    'Exc Extensiones' = $r.ExceptIfContentExtensionMatchesWords
                    'Exc Doc Protegido' = $r.ExceptIfDocumentIsPasswordProtected; 'Exc Doc No Sop' = $r.ExceptIfDocumentIsUnsupported
                    'Exc Override' = $r.ExceptIfHasSenderOverride; 'Exc Limite Proc' = $r.ExceptIfProcessingLimitExceeded
                    'Exc IP' = $r.ExceptIfSenderIPRanges
                    'Exc Subject' = $r.ExceptIfSubjectContainsWords; 'Exc Header' = $r.ExceptIfHeaderContainsWords
                    'Exc Tipo Msg' = $r.ExceptIfMessageTypeMatches; 'Exc Compartido' = $r.ExceptIfContentIsShared
                }
            }

            # 5 ── Reglas - Acciones
            $shAct = foreach ($r in $rules) {
                [pscustomobject]@{
                    'Directiva' = $r.PolicyName; 'Regla' = $r.RuleName; 'Estado' = (& $estado $r)
                    'Bloquear' = $r.BlockAccess; 'Alcance Bloqueo' = $r.BlockAccessScope
                    'Restringir Browser' = $r.RestrictBrowserAccess; 'Cuarentena' = $r.Quarantine
                    'Notificar' = $r.NotifyUser; 'Tipo Notif' = $r.NotifyUserType
                    'Override' = $r.NotifyAllowOverride; 'Req Override' = $r.NotifyOverrideRequirements
                    'Policy Tip' = $r.NotifyPolicyTipCustomText; 'Tip Display' = $r.NotifyPolicyTipDisplayOption; 'Tip URL' = $r.NotifyPolicyTipUrl
                    'Email Text' = $r.NotifyEmailCustomText; 'Email Subject' = $r.NotifyEmailCustomSubject
                    'Email Sender' = $r.NotifyEmailCustomSenderDisplayName; 'Email Attach' = $r.NotifyEmailExchangeIncludeAttachment
                    'Endpoint Notif' = $r.NotifyEndpointUser
                    'Alerta' = $r.GenerateAlert; 'Alert Props' = $r.AlertProperties
                    'Incidente' = $r.GenerateIncidentReport; 'Contenido Inc' = $r.IncidentReportContent; 'Severidad' = $r.ReportSeverityLevel
                    'Cifrar RMS' = $r.EncryptRMSTemplate; 'Aplicar RMS' = $r.ApplyRightsProtectionTemplate; 'Remover RMS' = $r.RemoveRMSTemplate
                    'Branding' = $r.ApplyBrandingTemplate
                    'Redirigir A' = $r.RedirectMessageTo; 'Add Dest' = $r.AddRecipients; 'Moderar' = $r.Moderate
                    'Prepend Subj' = $r.PrependSubject; 'Disclaimer' = $r.ApplyHtmlDisclaimer
                    'Set Header' = $r.SetHeader; 'Remove Header' = $r.RemoveHeader
                    'Power Automate' = $r.TriggerPowerAutomateFlow; 'Stop Proc' = $r.StopPolicyProcessing
                }
            }

            # 6 ── Reglas - Metadatos (incluye árbol y AdvancedRule crudo)
            $shMeta = foreach ($r in $rules) {
                [pscustomobject]@{
                    'Directiva' = $r.PolicyName; 'Regla' = $r.RuleName; 'Estado' = (& $estado $r)
                    'Disabled' = $r.Disabled; 'Raw Mode' = $r.RawMode; 'Prioridad' = $r.Priority
                    'Workload' = $r.Workload; 'Severidad' = $r.ReportSeverityLevel; 'Avanzada' = $r.IsAdvancedRule
                    'Creada Por' = $r.CreatedBy; 'Modificada Por' = $r.LastModifiedBy
                    'Creada' = $r.WhenCreated; 'Modificada' = $r.WhenChanged
                    'Activacion' = $r.ActivationDate; 'Expiracion' = $r.ExpiryDate
                    'Comentario' = $r.Comment; 'GUID' = $r.RuleGuid
                    'Condiciones Avanzadas' = (& $trunc $r.ConditionsTree)
                    'AdvancedRule Raw' = (& $trunc $r.AdvancedRuleRaw)
                }
            }

            # 7 ── Leyenda
            $leyenda = @(
                [pscustomobject]@{ Campo = 'Estado';   Descripcion = 'Habilitada / Deshabilitada segun la propiedad Disabled de la regla o Enabled de la directiva.' }
                [pscustomobject]@{ Campo = 'Modo';     Descripcion = 'Enable = Enforce; TestWith/WithoutNotifications = simulacion; Audit/AuditAndNotify = auditoria.' }
                [pscustomobject]@{ Campo = 'Avanzada'; Descripcion = 'Si = la regla usa AdvancedRule (JSON); sus condiciones se representan en el arbol.' }
                [pscustomobject]@{ Campo = 'Tipos Info Sensible'; Descripcion = 'SITs con Mincount/Maxcount/Confidencelevel extraidos del arbol o de ContentContainsSensitiveInformation.' }
                [pscustomobject]@{ Campo = 'Cond Avanzada (Arbol)'; Descripcion = 'Arbol logico AND/OR/NOT de la AdvancedRule en texto. NOT representa excepciones.' }
                [pscustomobject]@{ Campo = 'AdvancedRule Raw'; Descripcion = 'JSON original de la regla (truncado a 32000 caracteres si excede el limite de celda).' }
                [pscustomobject]@{ Campo = 'Vacio';    Descripcion = 'Celda vacia = condicion/accion no configurada en la regla.' }
            )

            $excelPath = Export-PavExcelWorkbook -Path $xlsxPath -Title 'Microsoft Purview - Reporte DLP' -Sheets ([ordered]@{
                'Resumen Ejecutivo'    = $resumen
                'Directivas DLP'       = $shPolicies
                'Reglas - Condiciones' = $shCond
                'Reglas - Excepciones' = $shExc
                'Reglas - Acciones'    = $shAct
                'Reglas - Metadatos'   = $shMeta
                'Leyenda'              = $leyenda
            })
        }

        [pscustomobject]@{
            PSTypeName = 'PurviewAssessment.ReportResult'
            Workload   = 'DLP'
            HtmlPath   = $htmlPath
            ExcelPath  = $excelPath
        }
    }
}
