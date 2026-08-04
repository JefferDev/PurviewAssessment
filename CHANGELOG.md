# Changelog

## [0.1.0] - 2026-07-08
### Agregado (Fase 1 - Nucleo)
- Manifiesto con exportacion explicita, PS 7.2 Core, GUID definitivo.
- Cargador con contexto de sesion compartido y limpieza OnRemove.
- Connect/Disconnect/Test-PurviewAssessmentConnection.
- Helpers privados: Write-PavLog, Assert-PavModule, Test-PavSession, Assert-PavConnection, Invoke-PavRetry.
- Gate de solo lectura por AST (build/Invoke-ReadOnlyGate.ps1) integrado en pruebas y firma.
- Firma Authenticode con timestamping (build/Invoke-Sign.ps1).
- Suite Pester 5: manifiesto, superficie publica, invariante de solo lectura (con autoprueba del gate) y conexion con mocks.

## [0.2.0] - 2026-07-08
### Agregado (Fase 2 - Motor de reporting)
- Assets/report.css|js: paleta corporativa de SIT v2 generalizada, tema dia/noche persistente (localStorage + prefers-color-scheme), impresion, sin dependencias externas (fuentes de sistema, apto offline).
- Private/Reporting: ConvertTo-PavHtml, New-PavBadge, New-PavHtmlCard, New-PavHtmlTable, New-PavPropList, New-PavHtmlSection, New-PavStat(Group), New-PavHtmlDocument (tabs automaticas con 2+ secciones), Export-PavExcelWorkbook (degrada sin ImportExcel; saneo de nombres de hoja).
- build/New-DemoReport.ps1: informe fixture (criterio de salida F2), incluye caso XSS para validar codificacion.
- Tests/PurviewAssessment.Reporting.Tests.ps1 (17 pruebas).

## [0.3.0] - 2026-07-08
### Agregado (Fase 3a - Etiquetas de Sensibilidad)
- Private/Parsing/ConvertFrom-PavLabelSettings.ps1: Get-PavProp, ConvertFrom-PavJson, Get-PavSettingValue y los 3 parsers de v3 (Settings k/v, LabelActions JSON con normalizacion footer/header/watermark/encrypt, LocaleSettings).
- Get-PurviewLabelData: colector de solo lectura (Get-Label con fallback sin -IncludeDetailedLabelActions, Get-LabelPolicy) con resolucion de etiqueta padre, flags de cifrado/marcas, locales y PublishedInPolicies.
- Export-PurviewLabelReport: HTML (tabs Etiquetas/Directivas, badges, tarjetas) + Excel estandar v3 (Resumen/Detalle Etiquetas, Resumen/Detalle Directivas; detalle tecnico completo en formato largo).
- Tests/PurviewAssessment.Labels.Tests.ps1 (7 pruebas con fixtures y cmdlets stub).
### Corregido
- Tests: aserciones '>Si<' aceptan la entidad HTML &#237; de WebUtility.HtmlEncode.
- Tests: limpieza de copias multiples del modulo en BeforeAll (Remove-Module -All).

## [0.3.1] - 2026-07-08
### Corregido
- ConvertFrom-PavKeyValueSettings: colecciones Settings de UN elemento llegaban como string suelto (des-enrollado de PowerShell en la salida de Get-PavProp) y se parseaban como vacias ('No configurado'). Afectaba tenants reales con etiquetas/directivas de un solo setting. Test de regresion incluido.
- Get-PavProp: advertencia documentada sobre el des-enrollado para futuros consumidores.

## [0.4.0] - 2026-07-08
### Agregado (Fase 3b - DLP)
- Private/Parsing/ConvertFrom-PavDlpHelpers.ps1: ConvertFrom-PavJsonValue (JSON REST sin deserializar), Resolve-PavDlpLocation (todos los formatos de ubicacion), Resolve-PavScopedUsers, Get-PavGroupSits/Labels (variantes de casing por tenant), Format-PavSitEntry/LabelEntry, Resolve-PavSitValue (5 formatos de CCSI).
- Private/Parsing/ConvertFrom-PavAdvancedRule.ps1: arbol logico And/Or/Not completo en texto (Excel) y HTML (clases pav-adv-*), colectores de SITs/Labels/AccessScope, truncado de listas largas.
- Get-PurviewDlpData: directivas con 13 ubicaciones resueltas + reglas con ~75 propiedades normalizadas (condiciones, excepciones, acciones, notificaciones), -IncludeDisabled.
- Export-PurviewDlpReport: HTML (tabs, badges de modo Enforce/Test, arbol de condiciones) + Excel 5 hojas (Resumen/Detalle Directivas, Resumen/Detalle Reglas, Condiciones).
- Assets/report.css: estilos del arbol AdvancedRule.
- Tests/PurviewAssessment.Dlp.Tests.ps1 (11 pruebas con fixture AdvancedRule realista).

## [0.5.0] - 2026-07-08
### Agregado (Fase 4a - IRM y Communication Compliance)
- Private/Parsing/ConvertFrom-PavIrmCcHelpers.ps1: Expand-PavIrmTriggerInsights/Indicators, Get-PavIrmHealthRow (PolicyHealth JSON con issues de validacion), ConvertFrom-PavCcContentSources/Classifiers, Get-PavCcWorkloads, Get-PavCcDirection (KQL).
- Get-PurviewIrmData + Export-PurviewIrmReport: HTML con badges de salud/DLP vinculada/personalizada, tablas de insights e indicadores por directiva; Excel 6 hojas.
- Get-PurviewCcData + Export-PurviewCcReport: cruce reglas-directiva por GUID/nombre, workloads desde ContentSources, badges Active/Activating/Failed; Excel 4 hojas.
- Tests/PurviewAssessment.IrmCc.Tests.ps1 (10 pruebas).
### Corregido
- Convencion 1 archivo = 1 funcion publica respetada (el cargador exporta por BaseName).

## [0.6.0] - 2026-07-08
### Agregado (Fase 4b - DLM y SITs)
- Private/Parsing/ConvertFrom-PavDlmHelpers.ps1: conversores friendly (duracion/accion/tipo/modo/tipo de directiva) y helpers de ubicaciones/SITs de retencion.
- Private/Parsing/ConvertFrom-PavRulePackage.ps1: parser XML completo del RulePackage (entidades con patrones/IdMatch/Any, incluye nodos <Version> con MinEngineVersion, mapas regex/keywords/filters, strings localizados).
- Get-PurviewDlmData + Export-PurviewDlmReport: directivas con 9 ubicaciones expandidas (cobertura/exclusiones), reglas con resolucion GUID->nombre, etiquetas con categoria (Regulatory/Record/Standard), file plan y etapas de revision multi-etapa; HTML 3 tabs + Excel 7 hojas.
- Get-PurviewSitData (-Online exporta y parsea el RulePackage eliminando el paso manual; -XmlPath modo offline sin sesion ni EXO; -SaveXmlTo conserva el XML) + Export-PurviewSitReport: tarjetas por SIT con regex resuelta, keywords y filtros; Excel 4 hojas.
- Tests/fixtures/rulepack-sample.xml + Tests/PurviewAssessment.DlmSit.Tests.ps1 (8 pruebas).
### Corregido
- Get-PurviewCcData: faltaba .EXAMPLE en la ayuda (fallo detectado por Pester en Windows); el test de ayuda ahora nombra la funcion culpable.
- ConvertTo-PavFriendlyMode: segundo parametro sin Position explicito dejaba de ser posicional.

## [0.7.0] - 2026-07-08
### Agregado (Fase 5 - Orquestador)
- Invoke-PurviewAssessment: assessment full o selectivo (-Workload) en una linea. Recoleccion resiliente por carga (errores no detienen el resto; seccion 'No evaluado' con motivo), genera los 6 informes individuales completos + consolidado ejecutivo HTML (tab por carga con stats y tabla resumen, referencia al informe de detalle) + Excel consolidado (hojas con prefijo por carga) + backup JSON de datos parseados (generaliza el de CC). SIT en linea guarda el XML exportado como evidencia (-SaveXmlTo OutputPath) o acepta -SitXmlPath offline.
- Tests/PurviewAssessment.Orchestrator.Tests.ps1 (2 pruebas, incluye resiliencia con IRM fallando).
### Corregido
- Test de superficie publica: lista esperada en orden alfabetico correcto.

## [0.7.1] - 2026-07-08
### Cambiado (feedback de revision)
- Consolidado con DETALLE COMPLETO: los constructores de secciones se extrajeron de los 6 exportadores a Private/Reporting/New-PavWorkloadSections.ps1 y ahora los comparten los informes individuales y el consolidado. El consolidado muestra las mismas tarjetas colapsables, arboles de AdvancedRule, tablas de reglas/insights/patrones y directivas de etiquetado que los informes individuales, con pestanas prefijadas por carga ('DLP · Reglas', 'Etiquetas · Directivas'...).
### Corregido
- Test del orquestador: el conteo de pestanas contaba tambien pav-table-wrap/pav-tabs; ahora cuenta exactamente <button class="pav-tab">.

## [0.7.2] - 2026-07-08
### Cambiado (feedback de revision)
- Titulos de las secciones de Information Protection en informes individual y consolidado: 'Etiquetas MIP' y 'Directivas - Etiquetas MIP' (sin prefijo generico en el consolidado).

## [0.8.0] - 2026-07-08
### Agregado (Fase 6 - Publicacion)
- .github/workflows/ci.yml: CI en Windows y Linux con gate de solo lectura (bloqueante), PSScriptAnalyzer y Pester.
- build/RELEASE.md: pipeline de release y firma (certificado de laboratorio y comercial), verificacion de firmas.
- README final con tabla de funciones y contenido del paquete de assessment.
### Cambiado
- Pestana SIT del consolidado sin prefijo redundante ('SITs personalizados').

## [0.8.1] - 2026-07-09
### Agregado (feedback de ejecucion real)
- DLP: las reglas se consultan POR DIRECTIVA (Get-DlpComplianceRule -Policy) con reintentos y progreso entre llamadas, como en el script original. Corrige el timeout de 30+ minutos observado en tenant real con la llamada global; el fallo de una directiva se registra sin detener la recoleccion. Se excluyen directivas en PendingDeletion.
- Progreso de recoleccion por elemento en consola en los 6 colectores, con el formato del script DLP original: '  > Directiva i/N: nombre', '  > Regla i/N: nombre', '  > Etiqueta i/N', '  > SIT: nombre (patrones)' y diagnostico '[i] AdvancedRule detectado' por regla avanzada.

## [0.8.2] - 2026-07-09
### Cambiado (feedback de ejecucion real)
- HTML de Etiquetas MIP: cada etiqueta/grupo muestra su color asignado (swatch junto al titulo + borde izquierdo de la tarjeta), con validacion hex anti-inyeccion.
- Excel de Labels al estandar v3 del ejemplo: Resumen con 16 columnas (Habilitada, Modo, Creado por...), Resumen Directivas con 19 (Predeterminada, Outlook default, Attachment action, Distribucion...) y Detalle en formato largo con columna Seccion (General/Configuracion/Proteccion/Idiomas/Publicacion/Auditoria/Raw).
- Excel de DLP al estandar del export v2.1: 7 hojas (Resumen Ejecutivo con metricas, Directivas DLP 28 col, Reglas-Condiciones 46 col, Reglas-Excepciones 23, Reglas-Acciones ~40, Reglas-Metadatos con arbol y AdvancedRule Raw truncado a limite de celda, Leyenda). Colectores ampliados: TeamsChannelLocation, usuarios con ambito a nivel directiva, ActivationDate/ExpiryDate, AlertProperties, disclaimer/branding/Power Automate y metadatos de regla.
- Banner de consola: 'ASSESSMENT DE MICROSOFT PURVIEW - MIP, DLP, IRM, CC, DLM, Custom SIT'.

## [1.0.0] - 2026-07-09
### Primera version estable
- Consolidado Excel: MIP-Directivas incluye la asignacion actual por ubicacion (Exchange/SharePoint/OneDrive/Grupos M365); IRM-Directivas la asignacion de usuarios (ExchangeLocation) y workload; CC-Directivas los origenes supervisados agregados desde las reglas, revisores y buzon de revision. MIP-Etiquetas incluye ademas el color.
- Validado contra tenant real (recoleccion por directiva en DLP, progreso por elemento, colores de etiqueta, Excel al estandar de los exports v2.1/v3).

### Publicacion (post-1.0.0, sin cambio de codigo)
- LICENSE (MIT), ProjectUri/LicenseUri en el manifiesto.
- build/Publish-ToGallery.ps1: staging de runtime (sin Tests/build/.github), gate previo obligatorio, soporte PSGallery publica y repositorios privados (GitHub Packages, Azure Artifacts, carpeta compartida) via PSResourceGet o PowerShellGet v2.
- build/RELEASE.md: guia de distribucion privada.

## [1.1.0] - 2026-07-30
### Agregado
- Etiquetado automatico (auto-labeling) incorporado a la carga MIP: Get-AutoSensitivityLabelPolicy y Get-AutoSensitivityLabelRule, con reglas consultadas POR DIRECTIVA (mismo patron anti-timeout de DLP) y deteccion tolerante: si el tenant no expone los cmdlets se registra el aviso y el resto del informe continua.
- Private/Parsing/ConvertFrom-PavAutoLabelHelpers.ps1: ConvertFrom-PavAutoLabelPolicy (ubicaciones, ambitos adaptativos, usuarios con ambito, metricas de simulacion, distribucion), ConvertTo-PavAutoLabelMode (distingue simulacion de activa) y ConvertFrom-PavAutoLabelRule (reutiliza el parser de AdvancedRule y los resolutores de SITs de DLP).
- Informe MIP: dos secciones nuevas (Etiquetado automatico y Reglas - Etiquetado automatico) con badges de modo/simulacion/sobrescritura/distribucion y arbol de AdvancedRule; tres hojas Excel nuevas (Auto-Etiquetado Directivas 26 col, Detalle y Reglas 28 col).
- Consolidado: hoja MIP-AutoEtiquetado con la asignacion por ubicacion, ambitos adaptativos y coincidencias de simulacion.
- Tests: 5 pruebas de auto-labeling (incluye tenant sin la feature y -SkipAutoLabeling).
### Cambiado
- El valor 'Labels' del parametro Workload pasa a llamarse 'MIP'. 'Labels' se sigue aceptando como alias y se normaliza internamente, por lo que los scripts existentes no se rompen.
