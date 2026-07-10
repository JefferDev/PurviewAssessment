# PurviewAssessment

Módulo de PowerShell para el **assessment de solo lectura** de Microsoft Purview: Etiquetas de Sensibilidad (MIP), DLP, Insider Risk Management, Communication Compliance, Retención (DLM) y SITs personalizados. Genera informes HTML interactivos (tema día/noche, tarjetas colapsables, búsqueda) y libros Excel con el detalle técnico completo, más un consolidado con todo el detalle por carga.

> **Invariante:** el módulo no ejecuta ninguna operación de escritura sobre el tenant. Se verifica automáticamente por análisis de AST (`build/Invoke-ReadOnlyGate.ps1`) en cada build de CI y como condición previa de la firma del módulo. Compliance Manager está **excluido por diseño** (sin cmdlets en ExchangeOnlineManagement).

## Requisitos

- PowerShell **7.2+** (Core)
- `ExchangeOnlineManagement` **>= 3.2.0** — solo para operaciones en línea (el informe SIT offline funciona sin él)
- `ImportExcel` >= 7.8.0 — opcional (sin él, los informes degradan a HTML)
- **RBAC recomendado:** cuenta con **Global Reader** o grupo de roles **View-Only Compliance**

## Uso rápido

```powershell
Import-Module .\PurviewAssessment\PurviewAssessment.psd1

# Assessment completo en una línea (paquete de ~13 entregables)
Invoke-PurviewAssessment -Connect -UserPrincipalName consultor@cliente.com `
    -OutputPath C:\Reports\Contoso -ClientName 'Contoso' -IncludeDisabled

# Solo cargas seleccionadas
Invoke-PurviewAssessment -Workload DLP, Labels -OutputPath C:\Reports

# Informe individual clásico
Connect-PurviewAssessment
Export-PurviewDlpReport -OutputPath C:\Reports -IncludeDisabled

# SITs sin conexión (XML ya exportado)
Get-PurviewSitData -XmlPath .\rulepack.xml | Export-PurviewSitReport -OutputPath C:\Reports
```

## Funciones (16)

| Categoría | Funciones |
|---|---|
| Sesión | `Connect-PurviewAssessment`, `Disconnect-PurviewAssessment`, `Test-PurviewAssessmentConnection` |
| Colectores (objetos) | `Get-PurviewLabelData`, `Get-PurviewDlpData`, `Get-PurviewIrmData`, `Get-PurviewCcData`, `Get-PurviewDlmData`, `Get-PurviewSitData` |
| Informes (HTML+Excel) | `Export-PurviewLabelReport`, `Export-PurviewDlpReport`, `Export-PurviewIrmReport`, `Export-PurviewCcReport`, `Export-PurviewDlmReport`, `Export-PurviewSitReport` |
| Orquestador | `Invoke-PurviewAssessment` |

## Paquete de entregables de `Invoke-PurviewAssessment`

- 6 informes HTML individuales (detalle completo por carga) + sus 6 libros Excel
- `PurviewAssessment_Consolidado_<ts>.html` — todas las cargas en pestañas, **mismo detalle** que los individuales (tarjetas, árbol de AdvancedRule, patrones SIT); cargas con error quedan marcadas "No evaluado" con el motivo
- `PurviewAssessment_Consolidado_<ts>.xlsx` — hojas resumen con prefijo por carga
- `PurviewAssessment_Datos_<ts>.json` — backup de todos los datos parseados (evidencia)
- `RulePackage_<ts>.xml` — export del RulePackage de SITs (evidencia)

## Validación y release

```powershell
./build/Invoke-ReadOnlyGate.ps1          # invariante de solo lectura (AST)
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path ./Tests              # 75+ pruebas (fixtures, sin tenant)
```

CI (`.github/workflows/ci.yml`) ejecuta los tres pasos en Windows y Linux. Firma Authenticode: ver `build/RELEASE.md` — `Invoke-Sign.ps1` re-ejecuta el gate y se niega a firmar si falla.

## Estructura

```
PurviewAssessment/
├── PurviewAssessment.psd1|psm1     # Manifiesto + cargador (contexto de sesión)
├── Public/                          # 16 funciones (1 archivo = 1 función)
├── Private/
│   ├── Connection/                  # Sesión IPPS segura, reintentos, asserts
│   ├── Logging/                     # Write-PavLog unificado
│   ├── Parsing/                     # Parsers por carga (AdvancedRule, RulePackage...)
│   └── Reporting/                   # Motor HTML/Excel + secciones por carga
├── Assets/                          # CSS/JS (tema día/noche, offline)
├── Tests/                           # Pester 5 + fixtures
├── build/                           # Gate solo-lectura, firma, RELEASE.md
└── .github/workflows/ci.yml
```
