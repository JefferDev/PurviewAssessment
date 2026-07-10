function New-PavHtmlTable {
<#
.SYNOPSIS
    Genera una tabla HTML a partir de objetos.
.DESCRIPTION
    Renderiza una colección de objetos como tabla del motor de reporting.
    TODOS los valores y cabeceras se codifican (ConvertTo-PavHtml). Las
    columnas se toman de -Property o, en su ausencia, de las propiedades
    del primer objeto.
.PARAMETER Data
    Objetos a renderizar.
.PARAMETER Property
    Columnas (nombres de propiedad) en el orden deseado.
.OUTPUTS
    [string] HTML de la tabla (o aviso pav-empty si no hay datos).
.EXAMPLE
    New-PavHtmlTable -Data $rules -Property Name, Mode, Priority
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [object[]]$Data,

        [Parameter()]
        [string[]]$Property
    )

    $rows = @($Data | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) {
        return '<div class="pav-empty">Sin elementos que mostrar.</div>'
    }

    if (-not $Property -or $Property.Count -eq 0) {
        $Property = @($rows[0].PSObject.Properties.Name)
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<div class="pav-table-wrap"><table class="pav-table"><thead><tr>')
    foreach ($col in $Property) {
        [void]$sb.Append('<th>').Append((ConvertTo-PavHtml $col)).AppendLine('</th>')
    }
    [void]$sb.AppendLine('</tr></thead><tbody>')

    foreach ($row in $rows) {
        [void]$sb.Append('<tr>')
        foreach ($col in $Property) {
            $val = if ($row.PSObject.Properties[$col]) { $row.$col } else { $null }
            $text = if ($null -eq $val) { '' }
                    elseif ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) { (@($val) -join ', ') }
                    else { [string]$val }
            [void]$sb.Append('<td>').Append((ConvertTo-PavHtml $text)).Append('</td>')
        }
        [void]$sb.AppendLine('</tr>')
    }

    [void]$sb.AppendLine('</tbody></table></div>')
    $sb.ToString()
}

function New-PavPropList {
<#
.SYNOPSIS
    Genera una rejilla propiedad/valor a partir de un hashtable ordenado
    o de un objeto.
.DESCRIPTION
    Reemplaza New-HtmlPropRow y equivalentes. Claves y valores se codifican.
    Los valores $null o vacíos se muestran como 'No configurado' en tono
    tenue, siguiendo el estándar de los informes actuales.
.PARAMETER Properties
    [System.Collections.IDictionary] ordenado (clave → valor) o
    [pscustomobject].
.OUTPUTS
    [string] HTML de la rejilla.
.EXAMPLE
    New-PavPropList -Properties ([ordered]@{ 'Modo' = $p.Mode; 'Prioridad' = $p.Priority })
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$Properties
    )

    $pairs = if ($Properties -is [System.Collections.IDictionary]) {
        foreach ($k in $Properties.Keys) { [pscustomobject]@{ K = [string]$k; V = $Properties[$k] } }
    }
    else {
        foreach ($p in $Properties.PSObject.Properties) { [pscustomobject]@{ K = $p.Name; V = $p.Value } }
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<div class="pav-props">')
    foreach ($pair in $pairs) {
        $raw = $pair.V
        $text = if ($null -eq $raw -or ($raw -is [string] -and [string]::IsNullOrWhiteSpace($raw))) { $null }
                elseif ($raw -is [bool]) { if ($raw) { 'Sí' } else { 'No' } }
                elseif ($raw -is [System.Collections.IEnumerable] -and $raw -isnot [string]) { (@($raw) -join ', ') }
                else { [string]$raw }

        [void]$sb.Append('<div class="k">').Append((ConvertTo-PavHtml $pair.K)).Append('</div>')
        if ($null -eq $text) {
            [void]$sb.AppendLine('<div class="v" style="color:var(--text-muted)">No configurado</div>')
        }
        else {
            [void]$sb.Append('<div class="v">').Append((ConvertTo-PavHtml $text)).AppendLine('</div>')
        }
    }
    [void]$sb.AppendLine('</div>')
    $sb.ToString()
}
