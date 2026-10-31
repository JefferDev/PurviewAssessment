function Export-PavExcelWorkbook {
<#
.SYNOPSIS
    Genera el libro Excel del informe con estilo corporativo unificado.
.DESCRIPTION
    Unifica Export-ExcelReport / Export-ToExcel de los scripts originales.
    Recibe un diccionario ordenado hojaNombre → datos y produce UN libro:
      - Cabecera en negrita, panel congelado, autofiltro y autoajuste.
      - Estilo de tabla uniforme (TableStyle Medium2).
      - Saneo de nombres de hoja (límite 31 caracteres de Excel y
        caracteres inválidos : \ / ? * [ ]).
    Si ImportExcel no está disponible, degrada con advertencia y devuelve
    $null (el informe HTML no depende de Excel).
.PARAMETER Sheets
    [System.Collections.IDictionary] ordenado: nombre de hoja → colección
    de objetos. Hojas con datos vacíos se omiten con aviso.
.PARAMETER Path
    Ruta del .xlsx de salida.
.PARAMETER Title
    Título del libro (propiedades del documento).
.OUTPUTS
    [string] ruta del archivo generado, o $null si Excel se omitió.
.EXAMPLE
    Export-PavExcelWorkbook -Path C:\Reports\dlp.xlsx -Sheets ([ordered]@{
        'DLP-Directivas' = $policies
        'DLP-Reglas'     = $rules
    })
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Sheets,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$Title = 'Microsoft Purview Assessment'
    )

    if (-not (Assert-PavModule -Name 'ImportExcel' -MinimumVersion '7.8.0' -Optional)) {
        Write-PavLog -Level Warn -Message 'Generación de Excel omitida (ImportExcel no disponible). El informe HTML no se ve afectado.'
        return $null
    }

    Import-Module ImportExcel -ErrorAction Stop

    if (Test-Path $Path) { Remove-Item -Path $Path -Force }

    $invalidChars = '[:\\/?*\[\]]'
    $usedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $written = 0

    foreach ($rawName in $Sheets.Keys) {
        $data = @($Sheets[$rawName] | Where-Object { $null -ne $_ })
        if ($data.Count -eq 0) {
            Write-PavLog -Level Warn -Message "Hoja '$rawName' omitida: sin datos."
            continue
        }

        # Saneo de nombre de hoja: caracteres inválidos y límite de 31
        $name = ($rawName -replace $invalidChars, '-')
        if ($name.Length -gt 31) { $name = $name.Substring(0, 31) }
        $base = $name; $n = 2
        while (-not $usedNames.Add($name)) {
            $suffix = "~$n"
            $name = $base.Substring(0, [Math]::Min($base.Length, 31 - $suffix.Length)) + $suffix
            $n++
        }

        $excelParams = @{
            Path          = $Path
            WorksheetName = $name
            TableStyle    = 'Medium2'
            AutoSize      = $true
            FreezeTopRow  = $true
            AutoFilter    = $true
            BoldTopRow    = $true
            Title         = $Title
        }
        $data | Export-Excel @excelParams
        $written++
        Write-PavLog -Level Info -Message "Hoja '$name' escrita ($($data.Count) filas)."
    }

    if ($written -eq 0) {
        Write-PavLog -Level Warn -Message 'Libro Excel no generado: ninguna hoja con datos.'
        return $null
    }

    Write-PavLog -Level Success -Message "Libro Excel generado: $Path ($written hojas)."
    return $Path
}
