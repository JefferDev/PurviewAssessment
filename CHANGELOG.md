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

## [1.2.0] - 2026-08-14
### Corregido
- **Get-PurviewSitData -Online exportaba el paquete equivocado.** La llamada estaba fijada a `-Identity 'Microsoft Rule Package'`, que es el catalogo de SITs PREDEFINIDOS de Microsoft (Publisher: Microsoft Corporation), no los SITs personalizados del tenant. Los SITs propios viven en paquetes como 'Microsoft.SCCManaged.CustomRulePack' o en paquetes cargados con New-DlpSensitiveInformationTypeRulePackage. Detectado en tenant real.
### Agregado
- Soporte de MULTIPLES RulePackages: se enumeran todos los paquetes del tenant y se procesan los personalizados. Nuevos parametros -Identity (limitar a paquetes concretos), -IncludeBuiltIn (incluir el catalogo de Microsoft) e -IncludeFingerprint (incluir el paquete de huellas digitales de documento). -XmlPath acepta varias rutas.
- Cada SIT queda anotado con RulePackName/RulePackIdentity; el informe agrupa por paquete y el Excel incluye la columna RulePackage y una hoja RulePackages.
- Desambiguacion de paquetes con el mismo RuleCollectionName (caso real: varios 'Microsoft.SCCManaged.CustomRulePack') anexando el GUID de su Identity.
- Aviso cuando un identificador de regex/keyword/filtro se repite entre paquetes.
- Se respeta IsExportable y se registran los paquetes omitidos con su motivo.
### Compatibilidad
- El objeto de datos expone RulePacks y SourceXmlPaths (colecciones); se conservan RulePack y SourceXmlPath en singular apuntando al primer paquete.

## [1.3.0] - 2026-08-15
### Agregado (nueva carga de trabajo: Records Management)
- Get-PurviewRmData + Export-PurviewRmReport: septima carga de trabajo (-Workload RM), con recoleccion tolerante cmdlet por cmdlet.
- File plan completo como catalogo propio: Department, Category, SubCategory, Authority, Citation (con CitationUrl y CitationJurisdiction) y ReferenceId, mas Get-FilePlanPropertyStructure.
- Retencion por eventos: Get-ComplianceRetentionEventType -LoadTag (obligatorio: sin ese modificador la propiedad ComplianceTags viene vacia) con resolucion de las etiquetas asociadas desde su DN, y eventos activos.
- Etiquetas declaradas como registro (record y regulatory) con su file plan, disposicion multi-etapa y vinculo a tipo de evento.
- Ambitos adaptativos y estado de Get-ComplianceTagStorage.
- Hallazgos de gobierno derivados del cruce: descriptores definidos sin uso, citaciones sin referencia normativa, tipos de evento sin etiquetas, etiquetas de registro sin file plan, eliminacion sin revision de disposicion y descriptores duplicados (normalizando acentos y signos).
- Informe HTML con los hallazgos como primera pestana (lectura ejecutiva) y Excel de hasta 8 hojas; hojas RM-* en el consolidado.
- Tests/PurviewAssessment.DlmSit.Tests.ps1: 5 pruebas de RM.

## [1.4.0] - 2026-08-15
### Agregado (nueva carga de trabajo: Auditoria)
- Get-PurviewAuditData + Export-PurviewAuditReport: octava carga (-Workload AUDIT) con las directivas de retencion del registro de auditoria unificada (Get-UnifiedAuditLogRetentionPolicy): tipos de registro, operaciones, usuarios en ambito, duracion, prioridad y estado de distribucion.
- Estado del registro de auditoria con VERIFICACION DE SESION: la propiedad UnifiedAuditLogIngestionEnabled devuelve siempre False desde una sesion de Security & Compliance, por lo que el colector comprueba si hay sesion de Exchange Online (probando Get-OrganizationConfig) antes de interpretarla. Sin esa sesion reporta 'No determinable' con la instruccion de verificacion, en lugar de un falso hallazgo critico de auditoria deshabilitada. Un valor True se considera fiable en cualquier caso.
- Auditoria de buzones a nivel de organizacion (AuditDisabled) cuando Exchange Online esta disponible.
- Hallazgos de gobierno: auditoria unificada o de buzones deshabilitada, ausencia de directivas personalizadas (todo en la retencion por defecto del plan), cobertura acotada a tipos de registro, directivas deshabilitadas, distribucion pendiente o fallida, retencion igual o inferior a 90 dias, directivas sin ambito y prioridades duplicadas.
- Tests/PurviewAssessment.Audit.Tests.ps1 (8 pruebas, incluidos los tres escenarios de sesion).
### Corregido
- New-PavWorkloadSections: '(foreach ...)' no es valido como expresion en PowerShell; se corrigio a '@(foreach ...)'.

## [1.5.0] - 2026-08-16
### Agregado (capa de evaluacion de controles)
- Controls/PavControlCatalog.psd1: catalogo declarativo propio con esquema de identificadores PAV-<DOMINIO>-<NN>. Cada control declara enunciado en positivo, fundamento, impacto de negocio, severidad base, tipo (Technical/Process/Hybrid), evaluador, referencias normativas y licenciamiento. Piloto con los diez controles del dominio MIP.
- Invoke-PurviewControlEvaluation: motor que evalua los datos ya recolectados contra el catalogo. Cinco estados (Implemented, PartiallyImplemented, NotImplemented, RequiresValidation, NotApplicable) y puntaje por dominio contando los parciales como medio control. Los controles de proceso admiten respuestas del cliente via -InterviewResponses y quedan marcados con su procedencia.
- Principio de diseno: la ausencia de datos NUNCA produce 'no implementado', sino 'requiere validacion'. Toda evidencia cita el objeto y el valor concretos.
- Export-PurviewControlReport: informe HTML con puntaje global, brechas priorizadas por severidad y detalle por control; Excel de tres hojas donde la de Controles sirve como plan de remediacion (incluye Responsable y Fecha objetivo).
- Invoke-PurviewAssessment -Evaluate: agrega la evaluacion al paquete de entregables.
- Tests/PurviewAssessment.Controls.Tests.ps1 (8 pruebas).

### Agregado en 1.5.0 (continuacion): dominio DLP del catalogo
- Doce controles PAV-DLP-01 a PAV-DLP-12: uso de SIT propios, cobertura de datos personales, financieros y de salud, modo de aplicacion frente a prueba, cobertura por carga de trabajo, acciones de bloqueo, notificacion al usuario, alertas e informes de incidente, higiene del inventario, y dos controles de proceso (cadencia de revision de alertas y revision de exclusiones).
- Test-PavControlsDlp.ps1 con Get-PavDlpSitCategory, que clasifica el texto de los tipos de informacion sensible en PII, Financiero o Salud para determinar cobertura por categoria de dato regulado.
- PAV-DLP-04 (datos de salud) es condicional: su ausencia produce 'Requiere validacion', no incumplimiento, porque depende de si la organizacion trata ese tipo de dato.
- PAV-DLP-10 detecta el inventario inerte cruzando directivas deshabilitadas con las que superan el umbral de dias sin modificacion.

## [1.5.1] - 2026-08-16
### Corregido (hallazgos de ejecucion real)
- **El bloqueo de Endpoint y de aplicaciones no se recolectaba.** En las directivas de punto de conexion y de aplicaciones (incluido Copilot) la accion de bloqueo no viaja en BlockAccess, sino en EndpointDlpRestrictions, RestrictAccess y EndpointDlpBrowserRestrictions, como pares Setting/Value. El colector no las leia, por lo que reglas que si bloquean impresion, portapapeles, medios extraibles o el procesamiento de contenido en prompts figuraban como si solo detectaran.
- Nuevo ConvertFrom-PavDlpRestrictions y campos derivados por regla: EndpointRestrictions, EndpointBlockedActions, AppRestrictions, AppBlockedActions, BrowserRestrictions, HasBlockingAction y BlockingSummary (resumen legible del motivo del bloqueo).
- ConvertTo-PavReadableValue: las hashtables ya no se serializan como 'System.Collections.Hashtable' en informes y backup JSON (afectaba a NotifyEndpointUser, AlertProperties y similares).
- **PAV-DLP-07 rediseñado**: la unidad de medida pasa de la regla a la DIRECTIVA. Un diseño maduro estratifica las reglas por confianza (_High bloquea, _Medium y _Low notifican), y medir el porcentaje de reglas con bloqueo penalizaba ese diseño correcto. Ahora una directiva se considera cubierta si tiene al menos un escalon de bloqueo, y la evidencia detalla el motivo por regla.

## [1.5.2] - 2026-08-16
### Corregido (hallazgos de ejecucion real)
- Invoke-PurviewAssessment: -SitXmlPath ahora alimenta tambien la evaluacion de controles aunque SIT no figure en -Workload. Antes, ejecutar '-Workload DLP -SitXmlPath ...' ignoraba los XML y PAV-DLP-01 quedaba en 'Requiere validacion'.
- Invoke-PurviewControlEvaluation: sin -Domain se evaluan solo los dominios cuya carga se recolecto. Antes el informe mostraba 0% en dominios no evaluados, lo que se lee como incumplimiento total. Nuevo -IncludeUncollected para el comportamiento anterior.
- Informe de evaluacion: la tabla de brechas priorizadas muestra la situacion observada (evidencia) en lugar del impacto de negocio generico, que hacia parecer que un control parcialmente implementado no tenia ninguna cobertura.

## [1.5.3] - 2026-08-16
### Corregido (hallazgos de ejecucion real)
- **Los SIT se citan por GUID en las reglas construidas con AdvancedRule.** El cruce de PAV-DLP-01 comparaba solo por nombre, por lo que nunca coincidia. Ahora contempla nombre e identificador.
- ConvertFrom-PavRulePackage tolera RulePackages con otro namespace o sin el: si la busqueda con el namespace estandar no devuelve nodos, reintenta por nombre local (Rules, Entity, Version). Un XML exportado con namespace distinto producia cero entidades sin error visible.
- Informe DLP y consolidado: cada directiva muestra si alguna de sus reglas bloquea, con el badge 'Bloquea (n/m)' o 'Solo detecta'; cada regla con bloqueo detalla el motivo (Endpoint, Aplicaciones, cuarentena, cifrado) en su propio badge.

## [1.5.4] - 2026-08-16
### Corregido (causa raiz del parseo de RulePackages)
- **El RulePackage exportado por el servicio declara encoding="utf-16".** El parser lo leia con Get-Content -Encoding UTF8 y lo convertia a [xml], lo que producia error de codificacion o contenido corrupto (acentos ilegibles) y, en la practica, cero entidades sin mensaje claro. Ahora el XML se carga por ruta con XmlDocument.Load, que resuelve la codificacion desde la declaracion y el marcador de orden de bytes, con reintento que prueba UTF-16, UTF-8 y BigEndian si la carga directa falla.
- Tests/fixtures/rulepack-utf16.xml: fixture escrito realmente en UTF-16, en una sola linea y con namespace por defecto, replicando la exportacion real del servicio.
### Nota
- No es necesario formatear ni reguardar manualmente los XML exportados: el modulo los procesa tal como los entrega el servicio.

## [1.6.0] - 2026-08-16
### Agregado
- Dominio RM del catalogo: diez controles PAV-RM-01 a PAV-RM-10 (declaracion de registro, distincion de registro regulado, plan de archivos con sus descriptores, citaciones con referencia normativa, asignacion del plan a las etiquetas, retencion por eventos, tipos de evento con etiquetas asociadas, revision de disposicion, aplicacion automatica y evidencia de destruccion como control de proceso).
- **Filtros interactivos en los informes HTML**: chips de filtrado por estado y severidad en el informe de evaluacion, combinables entre si y con el buscador de texto. New-PavHtmlCard admite -FilterTags para emitir atributos data-* arbitrarios, de modo que cualquier informe puede incorporar filtros sin cambios en el motor.
- PAV-RM-02, RM-05, RM-08 y RM-09 devuelven 'No aplica' cuando el supuesto del control no se cumple en el tenant (sin etiquetas de registro, o sin etiquetas que eliminen contenido), en lugar de penalizar una configuracion que no corresponde.
### Corregido
- -SitXmlPath aceptaba rutas relativas pero el parser podia ejecutarse con otro directorio de trabajo: ahora se resuelven a ruta absoluta antes de abrir el archivo.

## [1.6.1] - 2026-08-16
### Cambiado (separacion entre inventario y evaluacion)
- El informe de assessment de RM ya no incluye la seccion de hallazgos de gobierno: el assessment documenta la configuracion existente y el juicio sobre ella corresponde al informe de evaluacion de controles. Los hallazgos siguen calculandose y disponibles en el objeto de datos.
### Agregado
- Get-PurviewRmData recolecta el inventario completo: RetentionLabels (TODAS las etiquetas de retencion, no solo las declaradas como registro) y PublishPolicies (directivas de retencion que las publican, con las etiquetas de cada una y su cobertura por ubicacion).
  Antes, un tenant con etiquetas de retencion pero sin ninguna declarada como registro producia un informe RM sin inventario visible.
- Informe RM: secciones 'Etiquetas de retencion' y 'Directivas de publicacion', con badges de categoria, file plan, revision de disposicion, ambito adaptativo y bloqueo de preservacion; hojas equivalentes en el Excel.

## [1.6.2] - 2026-08-16
### Agregado (distincion entre etiquetas de RM y de ciclo de vida)
- Get-PavLabelScope clasifica cada etiqueta devuelta por Get-ComplianceTag en ambito de gestion de registros o de ciclo de vida, con el motivo explicito. Criterio: declara registro, esta incorporada al plan de archivos, tiene revision de disposicion, o computa la retencion desde un evento. IsRecordLabel por si solo NO es discriminante: en tenants reales hay etiquetas plenamente integradas al plan de archivos con IsRecordLabel en False.
- El objeto de datos de RM expone RetentionLabels (ambito de registros) y LifecycleLabels (ambito DLM), y el informe indica cuantas etiquetas quedaron fuera por corresponder al ciclo de vida.
- Cada etiqueta lleva Scope y ScopeReason, de modo que el informe justifica por que se clasifico en un ambito u otro.

## [1.6.3] - 2026-08-16
### Cambiado (portabilidad entre tenants)
- Los controles de cobertura por categoria de dato (PAV-DLP-02/03/04) dependian de que los tipos de informacion sensible emplearan terminos reconocibles. En un tenant que nombre sus SIT con codigos internos u otro idioma, la ausencia de coincidencias se reportaba como falta de cobertura: un hallazgo falso.
- Salvaguarda: si NINGUNA regla del tenant puede clasificarse en categoria alguna, los tres controles devuelven 'Requiere validacion' explicando que la nomenclatura no es interpretable, en lugar de afirmar ausencia de cobertura.
- Nuevo parametro -CategoryTerms en Invoke-PurviewControlEvaluation para ampliar el diccionario con los terminos propios del tenant: @{ PII = @('titular','derechohabiente') }.
### Nota de diseño
- La clasificacion de ambito de las etiquetas (Get-PavLabelScope) no depende de nomenclatura: se basa unicamente en propiedades estructurales del objeto (FilePlanMetadata, IsReviewTag, EventTypeId, IsRecordLabel, Regulatory), definidas por el producto y por tanto identicas en cualquier tenant e idioma.

## [1.6.4] - 2026-08-16
### Corregido (hallazgos de ejecucion real)
- **Una etiqueta con error abortaba todo el inventario.** El try/catch envolvia el bucle completo de Get-ComplianceTag, de modo que una excepcion al procesar una etiqueta descartaba silenciosamente todas las siguientes: en el tenant se recolectaron 2 de 7. Ahora el manejo de errores es POR ETIQUETA, se registra el nombre de la que falla y el inventario continua con el resto.
- **El cruce entre etiquetas y directivas no resolvia.** El campo Policy de la etiqueta no siempre coincide con el Guid de la directiva de retencion. El cruce contempla ahora Guid y ExchangeObjectId, y como via alternativa resuelve las etiquetas publicadas desde las reglas de retencion (PublishComplianceTag), que es donde la relacion queda declarada de forma fiable.
- Las directivas indican si publican etiquetas del ambito de gestion de registros (PublicaRegistros), para distinguirlas de las directivas de retencion por tiempo que pertenecen al ciclo de vida.

## [1.7.0] - 2026-08-16
### Agregado
- Dominio DLM del catalogo: diez controles PAV-DLM-01 a PAV-DLM-10 (existencia de directivas, cobertura por carga, etiquetas disponibles, eliminacion al vencimiento, modo de aplicacion frente a simulacion, ambitos adaptativos, bloqueo de preservacion, computo del periodo desde el hecho que exige la norma, vigencia de la configuracion y alineacion legal como control de proceso).
- El catalogo alcanza 42 controles en cuatro dominios: MIP (10), DLP (12), RM (10) y DLM (10).
### Cambiado
- Informe RM: las directivas se filtran por ambito usando el criterio estructural de que publiquen alguna etiqueta de gestion de registros, sin depender de la nomenclatura. Si el cruce no resuelve en ninguna, se listan todas indicandolo expresamente.

## [1.7.1] - 2026-08-16
### Corregido (separacion de ambitos en DLM)
- Get-PurviewDlmData incluia las etiquetas y directivas de gestion de registros, de modo que los mismos objetos aparecian en ambos informes. Ahora se aplica la misma clasificacion estructural que en RM, en sentido inverso: el informe de ciclo de vida excluye las etiquetas del ambito de registros y las directivas que las publican, y las contabiliza en RecordsScopeTags y RecordsScopePolicies.
- La pertenencia de una directiva al ambito de registros se determina por las etiquetas que publica (campo Policy de la etiqueta o PublishComplianceTag/ApplyComplianceTag de su regla), nunca por nomenclatura.
- Las reglas de retencion se filtran junto con su directiva, de modo que no quedan reglas de registros dentro del inventario de ciclo de vida.
- Los informes indican cuantos objetos se excluyeron y por que motivo.
### Corregido (trampa conocida)
- Get-PavLabelScope: el pipeline posterior a @() des-enrollaba ReviewerEmail cuando tenia un unico revisor, lo que hacia fallar .Count bajo StrictMode y abortaba la clasificacion.

## [1.7.2] - 2026-08-16
### Corregido
- PAV-DLM-02 evaluaba la superficie de chats de Teams pero omitia la de mensajes de canal, que suele concentrar el mayor volumen. Ahora se evaluan ambas y la evidencia indica cuando solo una de las dos esta cubierta.
- Se documenta el criterio sobre canales privados de Teams: no se evaluan como ubicacion independiente porque quedan cubiertos por la directiva de mensajes de canal desde su consolidacion; comprobarlos aparte produciria un falso negativo en cualquier tenant actualizado.

## [1.7.3] - 2026-08-16
### Corregido (falso negativo de cobertura en Teams y Viva Engage)
- **Las directivas de retención de Teams no se recolectaban.** Get-RetentionCompliancePolicy no devuelve las directivas que cubren chats de Teams, canales, canales privados ni Viva Engage: esas viven en los cmdlets *-AppRetentionCompliance*, segun documenta Microsoft, y los *-RetentionCompliance* soportan principalmente Exchange y SharePoint. El colector consultaba solo el primero, por lo que una directiva de Teams existente y habilitada en el tenant no aparecia en el inventario y PAV-DLM-02 la reportaba como carga sin alcance.
- Get-PurviewDlmData consulta ahora tambien Get-AppRetentionCompliancePolicy y Get-AppRetentionComplianceRule, de forma tolerante: si los cmdlets no estan disponibles se registra el aviso y el resto continua.
- Se agrega la ubicacion de Viva Engage (YammerLocation) al mapa de cobertura.

## [1.7.4] - 2026-08-16
### Corregido
- Las directivas de aplicaciones declaran la carga real en el campo Applications (por ejemplo 'Group:MicrosoftTeams, User:TeamsChatUserInteractions') y NO pueblan TeamsChatLocation ni TeamsChannelLocation. Sus valores de ExchangeLocation y ModernGroupLocation son unicamente el sustrato donde se almacenan los mensajes, por lo que el inventario mostraba la directiva de Teams como cobertura de Exchange y Grupos M365.
- El colector deriva ahora la carga funcional desde Applications (Teams Chat, Teams Channel, Viva Engage, Copilot) conservando el alcance declarado por la directiva, e indica en el detalle que la ubicacion proviene de ese campo.

## [1.8.0] - 2026-08-16
### Agregado (catalogo completo sobre las cargas recolectadas)
- Dominio CC: ocho controles PAV-CC-01 a 08 (existencia y estado de aprovisionamiento de las directivas, cobertura de canales, revisores asignados, clasificadores entrenables, muestreo, reconocimiento optico y proceso de revision).
- Dominio IRM: siete controles PAV-IRM-01 a 07 (directivas habilitadas, salud, cobertura de fuga de informacion y salida de personal, indicadores de actividad, ventanas de deteccion, seudonimizacion y flujo de triaje).
- Dominio AUD: seis controles PAV-AUD-01 a 06 (auditoria unificada, auditoria de buzones, directivas de retencion del registro, retencion superior al periodo por defecto, distribucion de las directivas y revision de accesos al propio registro).
- El catalogo alcanza 63 controles en siete dominios: MIP (10), DLP (12), RM (10), DLM (10), CC (8), IRM (7) y AUD (6). Quedan pendientes eDiscovery y gobierno de IA, que requieren desarrollo previo del colector.
- PAV-CC-02 y PAV-AUD-05 elevan su severidad cuando detectan fallo de aprovisionamiento o de distribucion, frente al estado meramente pendiente.

## [1.8.1] - 2026-08-16
### Corregido (falso negativo en revisores de Communication Compliance)
- Get-SupervisoryReviewPolicyV2 puede devolver Reviewers vacio aunque la directiva tenga revisores: en Communication Compliance v2 estos se declaran en la REGLA. El colector leia solo la propiedad de la directiva, por lo que PAV-CC-04 reportaba ausencia de revisores en directivas que si los tenian.
- Get-PurviewCcData consolida ahora ambas fuentes y expone Reviewers, ReviewerCount y ReviewerSource (Directiva, Reglas o ambas); las reglas exponen su propio campo Reviewers.
- PAV-CC-04 cita en la evidencia la directiva y el revisor concreto.

## [1.8.2] - 2026-08-16
### Cambiado (revisores de Communication Compliance)
- Get-SupervisoryReviewPolicyV2 sin -Identity devuelve un objeto reducido: propiedades como Reviewers llegan vacias tanto en la directiva como en la regla aunque el portal muestre revisores asignados. El colector consulta ahora cada directiva por identidad para obtener el objeto completo, con el mismo patron ya empleado para las reglas DLP.
- La busqueda de revisores contempla variantes de nombre de propiedad (Reviewers, ReviewerList, Reviewer, SupervisoryReviewers) tanto en la directiva como en sus reglas.

## [1.8.3] - 2026-08-16
### Agregado (sesion complementaria de Exchange Online)
- Connect-PurviewAssessment -IncludeExchangeOnline establece tambien la sesion de Exchange Online, necesaria para verificar UnifiedAuditLogIngestionEnabled y AuditDisabled: desde la sesion de cumplimiento esas propiedades no son concluyentes y los controles PAV-AUD-01 y PAV-AUD-02 quedaban en 'Requiere validacion'.
- Si ya existe una sesion de Exchange Online, se reutiliza en lugar de abrir otra. Si el cmdlet no esta disponible o la conexion falla, se registra el aviso y el assessment continua: los controles de auditoria quedan como 'Requiere validacion' en lugar de emitir un veredicto no fundamentado.
- Invoke-PurviewAssessment propaga el modificador con -Connect.

## [1.8.4] - 2026-08-16
### Corregido
- **PavContext es un objeto con propiedades fijas, no un hashtable**: asignar ExchangeOnline lanzaba SetValueInvocationException. La propiedad se declara ahora en el contexto del cargador, con alta defensiva por Add-Member si se carga un contexto de version anterior.
- **La sesion de Exchange Online no se establecia al reutilizar la sesion de cumplimiento**: Connect-PurviewAssessment retorna de forma temprana cuando ya hay sesion IPPS activa, y ese camino no pasaba por el bloque de Exchange Online. La logica se extrajo a Connect-PavExchangeOnline y se invoca en ambos caminos.
- Connect-PavExchangeOnline nunca lanza: reutiliza la sesion existente si la hay, y ante cualquier fallo registra el aviso y devuelve $false para que los controles de auditoria queden como 'Requiere validacion'.

## [1.8.5] - 2026-08-16
### Corregido (regresion introducida en 1.8.2)
- Reemplazar la directiva del listado por el objeto de la consulta por identidad rompio el resto de la carga: ese objeto tiene un identificador distinto, por lo que el cruce con las reglas dejaba de resolver (RulesCount 0, Workloads vacio), PolicyStatus pasaba a Unknown y las reglas se duplicaban. Los controles PAV-CC-03, CC-04 y CC-05 quedaban como no implementados pese a estar bien configurados.
- Ahora se conserva el objeto del listado y la consulta por identidad se usa UNICAMENTE para incorporar los revisores y el buzon de revision, que son las propiedades que ese listado no puebla. Si la directiva ya trae revisores, no se realiza la consulta adicional.

## [1.8.6] - 2026-08-16
### Corregido (interferencia entre la sesion de Exchange Online y la de cumplimiento)
- **La sesion de Exchange Online rompia la carga de Communication Compliance.** Con ambas sesiones activas, los cmdlets de Exchange Online se sobreponen a los de la sesion de cumplimiento y Get-SupervisoryReviewPolicyV2 resuelve contra la sesion equivocada: devuelve objetos con otros identificadores (el cruce con las reglas deja de resolver) y duplica resultados. Se comprobo por correlacion entre tres ejecuciones: sin sesion de Exchange Online, CC evaluaba bien; con ella, los controles CC-03, CC-04 y CC-05 caian a no implementado.
- Connect-PavExchangeOnline establece ahora la sesion con -Prefix PavExo, de modo que sus cmdlets (Get-PavExoOrganizationConfig, Get-PavExoAdminAuditLogConfig) no colisionan con los de cumplimiento.
- Get-PurviewAuditData prueba primero los cmdlets con prefijo y recurre a los normales si el usuario tiene una sesion propia sin prefijo, de modo que ambos escenarios funcionan.

## [1.9.0] - 2026-08-16
### Agregado (marco completo: nueve dominios)
- **Carga eDiscovery**: Get-PurviewEdsData y Export-PurviewEdsReport (-Workload EDS). Casos con sus miembros y estado, directivas de retencion de caso con las ubicaciones preservadas, y busquedas de cumplimiento. Recoleccion tolerante cmdlet por cmdlet.
- **Dominio EDS del catalogo**: cinco controles PAV-EDS-01 a 05 (capacidad en uso, retenciones legales, cobertura de ubicaciones, restriccion de acceso a los casos y procedimiento documentado de respuesta).
- **Dominio AI del catalogo**: ocho controles PAV-AI-01 a 08 sobre gobierno de inteligencia artificial. Son TRANSVERSALES: cruzan varias cargas (etiquetas que limitan el contenido procesable, DLP dirigido a la IA, retencion de las interacciones, supervision por cumplimiento de comunicaciones, riesgo interno, registro de auditoria, localizacion para descubrimiento electronico y acotacion del acceso).
- Invoke-PurviewControlEvaluation admite controles con Workload 'MULTI', a los que entrega el conjunto completo de datos en lugar de una sola carga.
- El catalogo alcanza **76 controles en nueve dominios**: MIP 10, DLP 12, RM 10, DLM 10, CC 8, IRM 7, AUD 6, EDS 5 y AI 8. Diez son de proceso y requieren entrevista.

## [1.9.1] - 2026-08-16
### Cambiado (separacion entre inventario y evaluacion, tambien en auditoria)
- El informe de assessment de auditoria ya no presenta los hallazgos de gobierno: la pestana pasa a llamarse 'Estado del registro' y documenta unicamente el estado de la auditoria unificada, la de buzones y las directivas de retencion. El juicio corresponde al informe de evaluacion de controles, igual que en Records Management.
- Se retiran tambien de la cabecera de estadisticas y de la hoja Excel del informe de inventario. Los hallazgos siguen calculandose y disponibles en el objeto de datos y en el backup JSON.

## [1.9.2] - 2026-08-16
### Corregido
- **Get-ComplianceCase sin -CaseType no devuelve todos los casos.** El colector obtenia unicamente el caso por defecto del portal (Content Search) y omitia los casos de eDiscovery creados en el tenant. Ahora se consulta cada tipo de caso de forma explicita (eDiscovery, AdvancedEdiscovery, DSR) ademas de la llamada sin parametros, y se deduplica por identidad, ya que un mismo caso puede llegar por varias consultas.

## [1.9.3] - 2026-08-17
### Corregido (eDiscovery: retenciones y busquedas por caso)
- Las retenciones legales y las busquedas asociadas a un caso solo se devuelven al consultar con -Case: la llamada global no las incluye. El colector consultaba unicamente en global, de modo que un caso con retenciones y busquedas configuradas figuraba sin ellas y las busquedas sueltas del tenant aparecian sin caso asignado.
- Get-PurviewEdsData consulta ahora cada caso por su identidad y por su nombre, deduplica los resultados y anota el caso de origen en cada retencion y busqueda.
- Las ubicaciones y la consulta preservada se completan desde Get-CaseHoldRule, ya que la regla es la que declara ContentMatchQuery.
### Limitacion conocida
- Los origenes de datos del caso (custodios y ubicaciones no gestionadas por custodio) no se exponen en Security & Compliance PowerShell; deben consultarse en el portal.

## [1.9.4] - 2026-08-17
### Cambiado
- El fallo al consultar las busquedas de un caso se registraba solo en verbose, por lo que pasaba inadvertido. Ahora se emite como aviso con el mensaje del cmdlet y la referencia empleada, y cuando un caso no devuelve busquedas se indica expresamente que en eDiscovery premium pueden no exponerse por PowerShell y deben verificarse en el portal.

## [1.9.5] - 2026-08-17
### Limitacion documentada (eDiscovery premium)
- Confirmado en tenant: Get-ComplianceSearch -Case devuelve vacio sin error para casos de tipo AdvancedEdiscovery. Las busquedas, los origenes de datos y los custodios de los casos premium no se exponen en Security & Compliance PowerShell y deben verificarse en el portal.
- Los casos premium incorporan el campo PortalOnlyDetails y el informe lo muestra en una seccion propia de la tarjeta, para que la ausencia de esos elementos no se interprete como falta de configuracion.
- La tarjeta del caso muestra ademas las busquedas asociadas cuando si estan disponibles (casos estandar).

## [1.9.6] - 2026-08-17
### Corregido (metricas de simulacion del etiquetado automatico)
- Get-AutoSensitivityLabelPolicy sin -Identity no puebla las metricas de simulacion: ItemsMatchedDuringTestMode, los contadores de elementos y la fecha de ultima ejecucion llegan en cero o vacios aunque la simulacion haya procesado miles de elementos. El informe daba a entender que la simulacion no se habia iniciado.
- El colector consulta cada directiva por identidad e incorpora UNICAMENTE los campos de simulacion y distribucion, conservando el objeto del listado para no alterar los identificadores (leccion de la regresion 1.8.2 en Communication Compliance). Solo se consulta cuando el listado no trae ya el dato.
- Nuevo campo SimulationSummary con el estado legible de la simulacion, y SimulationStatus e SimulationInInterval en el objeto normalizado.

## [1.10.0] - 2026-08-17
### Agregado (modelo de nivel de evidencia)
- Cada control emite ahora, ademas de su estado, un NIVEL DE EVIDENCIA que responde a una pregunta distinta: Verificado (hay evidencia de operacion), Configurado (el objeto existe y esta configurado) o No determinable (la propiedad no es fiable, falta permiso o no hay volumen). El estado responde si esta implementado; el nivel, con que calidad de informacion se sabe.
- Private/Evaluation/PavEvidenceModel.ps1: catalogo declarativo de propiedades NO fiables con el motivo de cada una (DistributionStatus, DistributionResults, ProvisionStatus, PolicyStatus, ExchangeLocation en retenciones legales, TeamsChatLocation en directivas de aplicaciones, SimulationItemsMatched y ContentContainsSensitiveInformation). Get-PavUnreliableReason y Get-PavUnreliablePropertyList permiten consultarlo desde cualquier evaluador.
- **Regla incorporada al modelo**: ningun control puede emitir 'No implementado' apoyandose en una propiedad del catalogo, ni en el resultado vacio de un cmdlet que filtra en silencio por falta de rol.
- El informe muestra el nivel de evidencia como badge y como campo, con el motivo cuando no es determinable, y permite filtrar por el.
### Corregido (falsos negativos confirmados)
- **PAV-CC-02** penalizaba PolicyStatus 'Activating' y ProvisionStatus 'NotStarted', que permanecen en esos valores en directivas plenamente operativas. Ahora evalua lo concluyente (directiva habilitada con reglas y condiciones definidas) y reporta esas propiedades como informacion, no como incumplimiento.
- **PAV-AUD-05** se apoyaba enteramente en DistributionStatus. Solo un fallo explicito de distribucion es concluyente; el estado 'Pending' produce 'Requiere validacion' con el motivo, en lugar de un incumplimiento.

## [1.10.1] - 2026-09-16
### Analizado (sin correccion necesaria)
- ExpirationDateOption NO se transforma: el colector lo pasa crudo y el informe muestra el literal del cmdlet. El valor 'ModificationAgeInDays' corresponde a la directiva de SharePoint y OneDrive, no a la de Copilot, que efectivamente devuelve 'CreationAgeInDays'.
### Corregido
- **RetentionType llegaba vacio en todas las reglas de retencion.** Esa propiedad solo se puebla en las etiquetas (Get-ComplianceTag); en las reglas el momento desde el que se computa el periodo viaja en ExpirationDateOption. El colector usa ahora la primera que traiga valor, expone el literal en RetentionTypeRaw y muestra la traduccion en RetentionType.
- **Las superficies de Copilot no se derivaban como carga.** El mapa de Applications solo contemplaba 'CopilotInteractions' y los valores reales son M365Copilot, CopilotForSecurity, CopilotinFabricPowerBI, CopilotStudio, CopilotinBusinessApplicationplatformsSales y SQLCopilot. La directiva figuraba cubriendo Exchange, que es el sustrato de almacenamiento y no su alcance.
### Agregado
- Get-PavAppScopeDetail: desglosa Applications en nombres comerciales y marca como 'obligatorio, sin efecto actual' las superficies que Microsoft exige declarar pero que no operan (Copilot en plataformas de negocio Sales y Copilot para SQL).
- Las directivas de aplicaciones exponen ApplicationsDetalle y NotaAlcance, esta ultima advirtiendo que Workload y las ubicaciones de Exchange o grupos son el sustrato y no el alcance, y que la ubicacion de experiencias de Copilot esta en version preliminar sin filtrado por aplicacion.

## [1.10.2] - 2026-09-16
### Corregido (estado de distribucion sistematicamente Pending)
- **Los colectores no solicitaban -DistributionDetail.** Comprobado en tenant: la misma directiva devuelve 'Pending' sin el modificador y 'Success' con el. El informe reportaba distribucion pendiente en directivas plenamente distribuidas, en todas las cargas.
- Nuevo Invoke-PavDistributionAware: invoca el cmdlet con -DistributionDetail cuando lo admite, comprobando el parametro antes de usarlo, y recurre a la llamada simple si falla, dejando constancia de que el estado no sera concluyente.
- Aplicado a Get-DlpCompliancePolicy, Get-LabelPolicy, Get-AutoSensitivityLabelPolicy (listado y consulta por identidad), Get-InsiderRiskPolicy, Get-SupervisoryReviewPolicyV2, Get-UnifiedAuditLogRetentionPolicy y Get-CaseHoldPolicy. Los colectores de retencion ya lo empleaban.
- Get-PurviewDlpData expone DistributionStatus en el objeto de directiva, que no se mapeaba.
- DistributionStatus sale del catalogo de propiedades no fiables: con el modificador el valor es concluyente. PAV-AUD-05 vuelve a emitir veredicto (Implementado, Parcial o No implementado segun el estado) con nivel de evidencia Verificado, y solo cae a 'Requiere validacion' si ninguna directiva reporta Success.

## [1.10.3] - 2026-09-16
### Cambiado
- Get-SupervisoryReviewPolicyV2 no admite -DistributionDetail: vuelve a invocarse de forma directa, sin el envoltorio.
- Invoke-PavDistributionAware documenta que lo admiten de forma confirmada Get-DlpCompliancePolicy, Get-AutoSensitivityLabelPolicy, Get-RetentionCompliancePolicy y Get-AppRetentionCompliancePolicy, y que el resto se comprueba en tiempo de ejecucion porque el soporte varia entre versiones del modulo ExchangeOnlineManagement.
- Nueva Get-PavDistributionSupport: informa, en la sesion actual, que cmdlets estan disponibles y cuales admiten el modificador, para verificarlo en cada tenant sin suposiciones.

## [1.10.4] - 2026-09-16
### Cambiado (lista verificada de soporte de -DistributionDetail)
- Verificado en tenant con ExchangeOnlineManagement 3.x. Lo admiten: Get-DlpCompliancePolicy, Get-AutoSensitivityLabelPolicy, Get-RetentionCompliancePolicy, Get-AppRetentionCompliancePolicy, Get-CaseHoldPolicy y Get-InsiderRiskPolicy. NO lo admiten: Get-LabelPolicy, Get-SupervisoryReviewPolicyV2 y Get-UnifiedAuditLogRetentionPolicy.
- El envoltorio se aplica unicamente a los seis cmdlets que lo soportan; los tres restantes se invocan de forma directa.
- El catalogo de propiedades no fiables recupera la entrada de DistributionStatus acotada a esos tres cmdlets, de modo que un estado 'Pending' proveniente de ellos no puede producir un veredicto de incumplimiento.

## [1.10.5] - 2026-09-16
### Corregido (exactitud del estado de distribucion)
- El servicio advierte que el estado de distribucion puede no ser exacto si no se especifica Identity junto con DistributionDetail, de modo que el listado seguia sin ser concluyente.
- Nueva Resolve-PavDistributionStatus: reconsulta por identidad UNICAMENTE las directivas cuyo estado no sea 'Success' en el listado, porque el falso negativo documentado afecta al valor 'Pending' y no al afirmativo. Asi se obtiene el estado exacto sin pagar una consulta individual por cada directiva.
- Limite de 25 consultas individuales por carga (MaxQueries) para acotar el tiempo en tenants con muchas directivas; el exceso se registra en consola.
- Aplicado en DLP, etiquetado automatico, riesgo interno y retencion, que son los cmdlets que admiten el modificador.
- Nuevo Invoke-PurviewAssessment -SkipDistributionDetail para omitir la confirmacion cuando prime la velocidad; en ese caso el estado deja de ser concluyente.

## [1.10.6] - 2026-09-18
### Corregido
- **Insider Risk no se recolectaba.** La confirmacion del estado de distribucion introducida en 1.10.5 referenciaba \$rawPolicies en Get-PurviewIrmData, donde la variable se llama \$raw, de modo que la carga fallaba entera y quedaba como no evaluada.
- Las banderas de sesion (PavSkipDistribution, PavHideInconclusive, PavDistribWarned) se declaran en el cargador del modulo. Antes solo existian si la ejecucion pasaba por Invoke-PurviewAssessment, por lo que invocar un colector de forma directa fallaba bajo StrictMode.
### Agregado
- **-HideInconclusiveWarnings** en Invoke-PurviewAssessment y en cada Export-Purview*Report: omite en los informes los avisos que provienen de propiedades que el servicio no reporta de forma concluyente ('Activating', 'Pending', 'Distribucion pendiente') y los que reflejan datos no visibles por PowerShell aunque existan en el portal ('Sin miembros asignados' en casos de eDiscovery). Evita trasladar al cliente lo que puede ser un falso negativo.
- New-PavInconclusiveBadge y Test-PavShowInconclusive centralizan esa decision, de modo que cualquier aviso nuevo de la misma naturaleza se acoge al parametro sin cambios en el motor. Los estados concluyentes, como un fallo explicito de distribucion, se siguen mostrando siempre.

## [1.10.8] - 2026-10-31
### Cambiado
- **El repositorio queda sin referencias a ninguna organizacion.** `CompanyName` del manifiesto pasa al autor; los fixtures de paquetes de reglas, los nombres de publicador, los dominios de ejemplo, los `ClientName` de las pruebas y los tenants citados en la ayuda usan ahora marcadores neutros. Requisito previo a publicar el repositorio.
- El ejemplo de `Get-PurviewSitData` y el comentario de `ConvertFrom-PavAutoLabelHelpers.ps1` dejan de citar tenants reales.

### Agregado
- `.github/workflows/release.yml`: al empujar una etiqueta `vX.Y.Z` ejecuta el gate de solo lectura y Pester, verifica que la etiqueta coincida con `ModuleVersion`, arma el paquete de runtime (sin `Tests`, `build` ni `.github`), calcula SHA256 y publica la Release con el zip y su huella.
- `Install-PurviewAssessment.ps1`: instalación remota desde GitHub Releases con verificación de huella, resolución de dependencias y soporte de repositorio privado mediante `GITHUB_TOKEN`.
- Sección de instalación en el README.
