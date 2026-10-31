function Invoke-PurviewControlEvaluation {
<#
.SYNOPSIS
    Evalúa la configuración recolectada contra el catálogo de controles del
    assessment y calcula el nivel de implementación por dominio.
.DESCRIPTION
    Capa de evaluación del módulo. No accede al tenant: consume los objetos
    de datos que devuelven los colectores Get-Purview*Data y emite, por cada
    control del catálogo, un veredicto con la evidencia que lo sustenta.

    Estados posibles:
      Implemented          El control está desplegado y verificado.
      PartiallyImplemented Desplegado de forma incompleta o parcial.
      NotImplemented       Ausente, verificado técnicamente.
      RequiresValidation   No se pudo verificar con los datos disponibles, o
                           es un control de proceso que exige confirmación
                           con el cliente. NUNCA se reporta como ausente.
      NotApplicable        No aplica al contexto del tenant.

    El puntaje de implementación se calcula sobre los controles evaluables
    (se excluyen NotApplicable y RequiresValidation), contando los
    parcialmente implementados como medio control.
.PARAMETER Data
    Hashtable de datos por carga: @{ MIP = $mip; DLP = $dlp; ... }
.PARAMETER Domain
    Limita la evaluación a los dominios indicados.
.PARAMETER CatalogPath
    Ruta a un catálogo alternativo. Por defecto, Controls\PavControlCatalog.psd1.
.PARAMETER InterviewResponses
    Hashtable con las respuestas del cliente para los controles de proceso:
    @{ 'PAV-DLP-05' = @{ Status = 'Implemented'; Evidence = 'Revisión mensual documentada' } }
.PARAMETER StaleDays
    Umbral en días para considerar obsoleta una configuración (por defecto 365).
.PARAMETER IncludeUncollected
    Incluye en la evaluación los dominios cuya carga no se recolectó. Por
    defecto se omiten, para no reportar 0% en un dominio no evaluado.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.ControlEvaluation' con
    Results, DomainScores, OverallScore, CatalogVersion, EvaluatedAt.
.EXAMPLE
    $mip = Get-PurviewLabelData
    Invoke-PurviewControlEvaluation -Data @{ MIP = $mip }
.EXAMPLE
    $ev = Invoke-PurviewControlEvaluation -Data @{ MIP = $mip; SIT = $sit }
    $ev.Results | Where-Object Status -eq 'NotImplemented' | Format-Table Id, Title, Severity
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][hashtable]$Data,
        [Parameter()][string[]]$Domain,
        [Parameter()][string]$CatalogPath,
        [Parameter()][hashtable]$InterviewResponses = @{},
        [Parameter()][int]$StaleDays = 365,

        # Incluye los dominios cuya carga no se recolectó (quedarán como
        # 'Requiere validación'). Por defecto se omiten.
        [switch]$IncludeUncollected,

        # Terminos adicionales para clasificar los tipos de informacion
        # sensible por categoria de dato, cuando la nomenclatura del tenant
        # no emplea terminos habituales:
        #   @{ PII = @('titular','derechohabiente'); Financiero = @('erogacion') }
        [Parameter()][hashtable]$CategoryTerms = @{}
    )

    if (-not $CatalogPath) {
        $CatalogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Controls/PavControlCatalog.psd1'
    }
    if (-not (Test-Path $CatalogPath)) { throw "No se encontró el catálogo de controles en '$CatalogPath'." }

    $catalog = Import-PowerShellDataFile -Path $CatalogPath
    Write-PavLog -Level Step -Message "Evaluando controles del catálogo v$($catalog.CatalogVersion)..."

    $controls = @($catalog.Controls)
    if ($Domain) {
        $controls = @($controls | Where-Object { $_.Domain -in $Domain })
    }
    elseif (-not $IncludeUncollected) {
        # Sin -Domain se evalúan solo los dominios cuya carga se recolectó:
        # informar 0% en un dominio que no se evaluó induce a error.
        $conDatos = @($Data.Keys | Where-Object { $null -ne $Data[$_] })
        $controls = @($controls | Where-Object { $_.Workload -in $conDatos -or ($_.Workload -eq 'MULTI' -and $conDatos.Count -gt 0) })
        $omitidos = @($catalog.Controls | Where-Object { $_.Workload -notin $conDatos } | Group-Object Domain | ForEach-Object { $_.Name })
        if ($omitidos.Count -gt 0) {
            Write-PavLog -Level Info -Message "Dominios no evaluados por falta de datos: $($omitidos -join ', '). Use -IncludeUncollected para incluirlos."
        }
    }
    if ($controls.Count -eq 0) { throw 'Ningún control del catálogo corresponde a las cargas recolectadas.' }

    $options = @{ StaleDays = $StaleDays; CategoryTerms = $CategoryTerms }
    if ($Data.ContainsKey('SIT')) { $options.SitData = $Data['SIT'] }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($c in $controls) {
        $status = 'RequiresValidation'
        $evidence = ''
        $severity = $c.Severity
        $source = 'Verificación técnica'
        $evidenceLevel = 'Configured'
        $unreliable = ''

        # 1. Respuesta de entrevista: prevalece en controles de proceso
        if ($InterviewResponses.ContainsKey($c.Id)) {
            $resp = $InterviewResponses[$c.Id]
            $status   = "$($resp.Status)"
            $evidence = "$($resp.Evidence)"
            $source   = 'Declarado por el cliente'
        }
        elseif ($c.Type -eq 'Process') {
            $evidence = 'Control de proceso: requiere confirmación con el cliente. No es verificable con la configuración del tenant.'
            $source   = 'Pendiente de entrevista'
            $evidenceLevel = 'NotDeterminable'
        }
        # 2. Evaluación técnica
        elseif ($c.Evaluator) {
            $wl = "$($c.Workload)"
            # Los controles transversales (gobierno de IA) evalúan varias
            # cargas a la vez: reciben el conjunto completo de datos.
            if ($wl -eq 'MULTI') {
                if (-not (Get-Command $c.Evaluator -ErrorAction SilentlyContinue)) {
                    $evidence = "El evaluador '$($c.Evaluator)' no está disponible en el módulo."
                }
                else {
                    try {
                        $r = & $c.Evaluator -Data $Data -Options $options
                        $status = "$($r.Status)"; $evidence = "$($r.Evidence)"
                        if ($r.ContainsKey('Severity') -and $r.Severity) { $severity = "$($r.Severity)" }
                        if ($r.ContainsKey('EvidenceLevel') -and $r.EvidenceLevel) { $evidenceLevel = "$($r.EvidenceLevel)" }
                        if ($r.ContainsKey('UnreliableReason') -and $r.UnreliableReason) { $unreliable = "$($r.UnreliableReason)" }
                    }
                    catch { $evidence = "El evaluador falló: $($_.Exception.Message)" }
                }
            }
            elseif (-not $Data.ContainsKey($wl) -or $null -eq $Data[$wl]) {
                $evidence = "No se recolectaron datos de la carga '$wl' en esta ejecución."
            }
            elseif (-not (Get-Command $c.Evaluator -ErrorAction SilentlyContinue)) {
                $evidence = "El evaluador '$($c.Evaluator)' no está disponible en el módulo."
            }
            else {
                try {
                    $r = & $c.Evaluator -Data $Data[$wl] -Options $options
                    $status   = "$($r.Status)"
                    $evidence = "$($r.Evidence)"
                    if ($r.ContainsKey('Severity') -and $r.Severity) { $severity = "$($r.Severity)" }
                    if ($r.ContainsKey('EvidenceLevel') -and $r.EvidenceLevel) { $evidenceLevel = "$($r.EvidenceLevel)" }
                    if ($r.ContainsKey('UnreliableReason') -and $r.UnreliableReason) { $unreliable = "$($r.UnreliableReason)" }
                }
                catch {
                    $evidence = "El evaluador falló: $($_.Exception.Message)"
                }
            }
        }

        $results.Add([pscustomobject]@{
            PSTypeName     = 'PurviewAssessment.ControlResult'
            Id             = $c.Id
            Domain         = $c.Domain
            Title          = $c.Title
            Status         = $status
            StatusText     = ConvertTo-PavControlStatusText $status
            Severity       = $severity
            EvidenceLevel     = $evidenceLevel
            EvidenceLevelText = ConvertTo-PavEvidenceLevelText $evidenceLevel
            UnreliableReason  = $unreliable
            Type           = $c.Type
            Source         = $source
            Evidence       = $evidence
            Rationale      = $c.Rationale
            BusinessImpact = $c.BusinessImpact
            Frameworks     = (@($c.Frameworks) -join '; ')
            License        = $c.License
            Owner          = ''
            TargetDate     = ''
        })
        Write-PavLog -Level Info -Message "  > $($c.Id): $(ConvertTo-PavControlStatusText $status)"
    }

    # ── Puntajes ─────────────────────────────────────────────────────────────
    $domainScores = foreach ($grp in @($results | Group-Object Domain)) {
        $dom = @($catalog.Domains | Where-Object Code -eq $grp.Name) | Select-Object -First 1
        $eval = @($grp.Group | Where-Object { $_.Status -in @('Implemented', 'PartiallyImplemented', 'NotImplemented') })
        $full = @($grp.Group | Where-Object Status -eq 'Implemented').Count
        $part = @($grp.Group | Where-Object Status -eq 'PartiallyImplemented').Count
        $score = if ($eval.Count -gt 0) { [math]::Round((($full + ($part * 0.5)) / $eval.Count) * 100) } else { 0 }
        [pscustomobject]@{
            PSTypeName  = 'PurviewAssessment.ControlDomainScore'
            Domain      = $grp.Name
            DomainName  = if ($dom) { $dom.Name } else { $grp.Name }
            Order       = if ($dom) { $dom.Order } else { 99 }
            Total       = $grp.Count
            Implemented = $full
            Partial     = $part
            NotImplemented = @($grp.Group | Where-Object Status -eq 'NotImplemented').Count
            RequiresValidation = @($grp.Group | Where-Object Status -eq 'RequiresValidation').Count
            NotApplicable = @($grp.Group | Where-Object Status -eq 'NotApplicable').Count
            Evaluable   = $eval.Count
            Score       = $score
        }
    }
    $domainScores = @($domainScores | Sort-Object Order)

    $allEval = @($results | Where-Object { $_.Status -in @('Implemented', 'PartiallyImplemented', 'NotImplemented') })
    $allFull = @($results | Where-Object Status -eq 'Implemented').Count
    $allPart = @($results | Where-Object Status -eq 'PartiallyImplemented').Count
    $overall = if ($allEval.Count -gt 0) { [math]::Round((($allFull + ($allPart * 0.5)) / $allEval.Count) * 100) } else { 0 }

    Write-PavLog -Level Success -Message "Evaluación: $overall% de implementación sobre $($allEval.Count) control(es) evaluable(s) de $($results.Count)."

    [pscustomobject]@{
        PSTypeName     = 'PurviewAssessment.ControlEvaluation'
        Results        = @($results)
        DomainScores   = $domainScores
        OverallScore   = $overall
        TotalControls  = $results.Count
        EvaluableCount = $allEval.Count
        CatalogVersion = $catalog.CatalogVersion
        StaleDays      = $StaleDays
        EvaluatedAt    = Get-Date
    }
}
