function Get-PurviewEdsData {
<#
.SYNOPSIS
    Recolecta la configuración de descubrimiento electrónico (eDiscovery)
    de Microsoft Purview: casos, retenciones legales y búsquedas.
.DESCRIPTION
    Cada bloque se recolecta de forma tolerante: si la sesión no expone un
    cmdlet, se registra el aviso y el resto continúa.
    Cubre casos (estándar y premium), directivas de retención de caso con
    sus ubicaciones, y búsquedas de cumplimiento.
.PARAMETER IncludeClosed
    Incluye los casos cerrados. Por defecto se recolectan todos.
.OUTPUTS
    [pscustomobject] PSTypeName 'PurviewAssessment.EdsData' con Cases,
    HoldPolicies, Searches, CollectedAt.
.EXAMPLE
    Get-PurviewEdsData | Export-PurviewEdsReport -OutputPath C:\Reports
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([switch]$IncludeClosed)

    Assert-PavConnection
    Write-PavLog -Level Step -Message 'Recolectando configuración de eDiscovery...'

    # ── Casos ────────────────────────────────────────────────────────────────
    $cases = [System.Collections.Generic.List[object]]::new()
    if (Get-Command Get-ComplianceCase -ErrorAction SilentlyContinue) {
        try {
            # Sin -CaseType el cmdlet no devuelve todos los tipos de caso: los
            # de eDiscovery estándar y premium deben pedirse explícitamente.
            # Se consulta cada tipo y se deduplica por identidad.
            $raw = @(Invoke-PavRetry -OperationName 'Get-ComplianceCase' -MaxAttempts 2 -ScriptBlock {
                Get-ComplianceCase -ErrorAction Stop
            })
            foreach ($tipo in 'eDiscovery', 'AdvancedEdiscovery', 'DSR') {
                try {
                    $porTipo = @(Invoke-PavRetry -OperationName "Get-ComplianceCase -CaseType $tipo" -MaxAttempts 2 -ScriptBlock {
                        Get-ComplianceCase -CaseType $tipo -ErrorAction Stop
                    })
                    if ($porTipo.Count -gt 0) {
                        Write-PavLog -Level Info -Message "  > Casos de tipo ${tipo}: $($porTipo.Count)"
                        $raw += $porTipo
                    }
                }
                catch { Write-Verbose "Tipo de caso $tipo no disponible: $($_.Exception.Message)" }
            }
            # Deduplicación: un mismo caso puede llegar por varias consultas
            $vistos = @{}
            $raw = @($raw | Where-Object {
                if ($null -eq $_) { return $false }
                $k = "$(Get-PavProp $_ 'Identity' (Get-PavProp $_ 'Name' ''))"
                if (-not $k -or $vistos.ContainsKey($k)) { return $false }
                $vistos[$k] = $true
                return $true
            })
            foreach ($c in $raw) {
                if ($null -eq $c) { continue }
                $estado = [string](Get-PavProp $c 'Status' '')
                if (-not $IncludeClosed -and $estado -eq 'Closed') { }
                $cases.Add([pscustomobject]@{
                    PSTypeName  = 'PurviewAssessment.EdsCase'
                    Name        = [string](Get-PavProp $c 'Name' '')
                    CaseType    = [string](Get-PavProp $c 'CaseType' 'eDiscovery')
                    Status      = $estado
                    Description = [string](Get-PavProp $c 'Description' (Get-PavProp $c 'Comment' ''))
                    Members     = (@(Get-PavProp $c 'Members' @()) | ForEach-Object { "$_" }) -join '; '
                    MemberCount = @(@(Get-PavProp $c 'Members' @()) | Where-Object { $_ }).Count
                    ClosedBy    = [string](Get-PavProp $c 'ClosedBy' '')
                    ClosedDate  = Get-PavProp $c 'ClosedDateTime'
                    CreatedBy   = [string](Get-PavProp $c 'CreatedBy' '')
                    CreatedUtc  = Get-PavProp $c 'CreatedDateTime' (Get-PavProp $c 'WhenCreatedUTC')
                    LastModifiedUtc = Get-PavProp $c 'LastModifiedDateTime' (Get-PavProp $c 'WhenChangedUTC')
                    # En los casos premium, las búsquedas, los orígenes de datos
                    # y los custodios se gestionan fuera de PowerShell.
                    PortalOnlyDetails = $(if ("$(Get-PavProp $c 'CaseType' '')" -match 'Advanced|Premium') {
                        'Búsquedas, orígenes de datos y custodios: no expuestos por PowerShell, verificar en el portal'
                    } else { '' })
                    Identity    = [string](Get-PavProp $c 'Identity' '')
                    Guid        = [string](Get-PavProp $c 'Guid' '')
                })
            }
            Write-PavLog -Level Success -Message "Casos de eDiscovery: $(@($cases).Count)"
        }
        catch { Write-PavLog -Level Warn -Message "Casos no recuperados: $($_.Exception.Message)" }
    }
    else { Write-PavLog -Level Warn -Message 'Get-ComplianceCase no disponible en esta sesión.' }

    # ── Retenciones legales asociadas a los casos ────────────────────────────
    $holds = [System.Collections.Generic.List[object]]::new()
    if (Get-Command Get-CaseHoldPolicy -ErrorAction SilentlyContinue) {
        try {
            # Las retenciones de un caso solo se devuelven al consultar con
            # -Case: la llamada global no las incluye.
            $rawH = @()
            try { $rawH += @(Invoke-PavRetry -OperationName 'Get-CaseHoldPolicy' -MaxAttempts 2 -ScriptBlock { Invoke-PavDistributionAware -CmdletName 'Get-CaseHoldPolicy' }) }
            catch { Write-Verbose "Listado global de retenciones no disponible: $($_.Exception.Message)" }
            foreach ($caso in @($cases)) {
                $idCaso = "$($caso.Identity)"; $nomCaso = "$($caso.Name)"
                foreach ($ref in @($idCaso, $nomCaso) | Where-Object { $_ } | Select-Object -Unique) {
                    try {
                        $porCaso = @(Invoke-PavRetry -OperationName "Get-CaseHoldPolicy -Case '$ref'" -MaxAttempts 2 -ScriptBlock {
                            Get-CaseHoldPolicy -Case $ref -ErrorAction Stop
                        })
                        if ($porCaso.Count -gt 0) {
                            Write-PavLog -Level Info -Message "  > Retenciones de '$nomCaso': $($porCaso.Count)"
                            foreach ($x in $porCaso) { $x | Add-Member -NotePropertyName PavCaseName -NotePropertyValue $nomCaso -Force }
                            $rawH += $porCaso
                            break
                        }
                    }
                    catch { Write-Verbose "Retenciones de '$ref' no disponibles: $($_.Exception.Message)" }
                }
            }
            $vistosH = @{}
            $rawH = @($rawH | Where-Object {
                if ($null -eq $_) { return $false }
                $k = "$(Get-PavProp $_ 'Name' '')"
                if (-not $k -or $vistosH.ContainsKey($k)) { return $false }
                $vistosH[$k] = $true; return $true
            })
            foreach ($h in $rawH) {
                if ($null -eq $h) { continue }
                $holds.Add([pscustomobject]@{
                    PSTypeName = 'PurviewAssessment.EdsHold'
                    Name       = [string](Get-PavProp $h 'Name' '')
                    Enabled    = Get-PavProp $h 'Enabled' $false
                    Mode       = [string](Get-PavProp $h 'Mode' '')
                    CaseName   = $(
                        $cn = "$(Get-PavProp $h 'PavCaseName' '')"
                        if (-not $cn) { $cn = Get-PavNameFromDn "$(Get-PavProp $h 'Case' '')" }
                        $cn)
                    Exchange   = Resolve-PavDlpLocation -PropName 'ExchangeLocation'   -PolicyObj $h
                    SharePoint = Resolve-PavDlpLocation -PropName 'SharePointLocation' -PolicyObj $h
                    OneDrive   = Resolve-PavDlpLocation -PropName 'OneDriveLocation'   -PolicyObj $h
                    PublicFolder = Resolve-PavDlpLocation -PropName 'PublicFolderLocation' -PolicyObj $h
                    DistributionStatus = [string](Get-PavProp $h 'DistributionStatus' '')
                    CreatedBy  = [string](Get-PavProp $h 'CreatedBy' '')
                    CreatedUtc = Get-PavProp $h 'WhenCreatedUTC'
                    LastModifiedUtc = Get-PavProp $h 'WhenChangedUTC'
                    Guid       = [string](Get-PavProp $h 'Guid' '')
                })
            }
            Write-PavLog -Level Info -Message "  > Retenciones legales: $(@($holds).Count)"
        }
        catch { Write-PavLog -Level Warn -Message "Retenciones legales no recuperadas: $($_.Exception.Message)" }
    }

    # Las ubicaciones preservadas se declaran en la regla de la retención
    if ($holds.Count -gt 0 -and (Get-Command Get-CaseHoldRule -ErrorAction SilentlyContinue)) {
        foreach ($h in $holds) {
            try {
                $reglas = @(Invoke-PavRetry -OperationName "Get-CaseHoldRule '$($h.Name)'" -MaxAttempts 2 -ScriptBlock {
                    Get-CaseHoldRule -Policy $h.Name -ErrorAction Stop
                })
                $q = @($reglas | ForEach-Object { "$(Get-PavProp $_ 'ContentMatchQuery' '')" } | Where-Object { $_ })
                if ($q.Count -gt 0) { $h | Add-Member -NotePropertyName ContentMatchQuery -NotePropertyValue ($q -join ' | ') -Force }
                $h | Add-Member -NotePropertyName RuleCount -NotePropertyValue $reglas.Count -Force
            }
            catch { Write-Verbose "Reglas de retención de '$($h.Name)' no disponibles: $($_.Exception.Message)" }
        }
    }

    # ── Búsquedas de cumplimiento ────────────────────────────────────────────
    $searches = [System.Collections.Generic.List[object]]::new()
    if (Get-Command Get-ComplianceSearch -ErrorAction SilentlyContinue) {
        try {
            $rawS = @()
            try { $rawS += @(Invoke-PavRetry -OperationName 'Get-ComplianceSearch' -MaxAttempts 2 -ScriptBlock { Get-ComplianceSearch -ErrorAction Stop }) }
            catch { Write-Verbose "Listado global de búsquedas no disponible: $($_.Exception.Message)" }
            foreach ($caso in @($cases)) {
                $idCaso = "$($caso.Identity)"; $nomCaso = "$($caso.Name)"
                $encontradas = 0
                foreach ($ref in @($idCaso, $nomCaso) | Where-Object { $_ } | Select-Object -Unique) {
                    try {
                        $porCaso = @(Invoke-PavRetry -OperationName "Get-ComplianceSearch -Case '$ref'" -MaxAttempts 2 -ScriptBlock {
                            Get-ComplianceSearch -Case $ref -ErrorAction Stop
                        })
                        if ($porCaso.Count -gt 0) {
                            Write-PavLog -Level Info -Message "  > Búsquedas de '$nomCaso': $($porCaso.Count)"
                            foreach ($x in $porCaso) { $x | Add-Member -NotePropertyName PavCaseName -NotePropertyValue $nomCaso -Force }
                            $rawS += $porCaso
                            $encontradas = $porCaso.Count
                            break
                        }
                    }
                    catch {
                        # Visible: si el cmdlet rechaza el caso, el consultor debe saberlo
                        Write-PavLog -Level Warn -Message "      Búsquedas de '$nomCaso' (ref '$ref'): $($_.Exception.Message)"
                    }
                }
                if ($encontradas -eq 0) {
                    Write-PavLog -Level Info -Message "  > '$nomCaso' no devolvió búsquedas asociadas. En casos de eDiscovery premium las búsquedas pueden no exponerse por PowerShell; verifíquese en el portal."
                }
            }
            $vistosS = @{}
            $rawS = @($rawS | Where-Object {
                if ($null -eq $_) { return $false }
                $k = "$(Get-PavProp $_ 'Name' '')"
                if (-not $k -or $vistosS.ContainsKey($k)) { return $false }
                $vistosS[$k] = $true; return $true
            })
            foreach ($x in $rawS) {
                if ($null -eq $x) { continue }
                $searches.Add([pscustomobject]@{
                    PSTypeName = 'PurviewAssessment.EdsSearch'
                    Name       = [string](Get-PavProp $x 'Name' '')
                    Status     = [string](Get-PavProp $x 'Status' '')
                    CaseName   = $(
                        $cn = "$(Get-PavProp $x 'PavCaseName' '')"
                        if (-not $cn) { $cn = Get-PavNameFromDn "$(Get-PavProp $x 'Case' '')" }
                        $cn)
                    ContentMatchQuery = [string](Get-PavProp $x 'ContentMatchQuery' '')
                    Items      = Get-PavProp $x 'Items'
                    CreatedBy  = [string](Get-PavProp $x 'CreatedBy' '')
                    CreatedUtc = Get-PavProp $x 'CreatedTime'
                })
            }
            Write-PavLog -Level Info -Message "  > Búsquedas: $(@($searches).Count)"
        }
        catch { Write-PavLog -Level Warn -Message "Búsquedas no recuperadas: $($_.Exception.Message)" }
    }

    [pscustomobject]@{
        PSTypeName   = 'PurviewAssessment.EdsData'
        Cases        = @($cases)
        HoldPolicies = @($holds)
        Searches     = @($searches)
        CollectedAt  = Get-Date
    }
}
