function Write-PavLog {
<#
.SYNOPSIS
    Logging unificado del módulo (reemplaza Write-Status / Write-Log /
    Write-Banner de los scripts originales).
.DESCRIPTION
    Emite mensajes de consola con timestamp, nivel y color consistentes en
    todo el módulo. Idioma de consola: español (decisión de diseño #4).
    Los niveles Warn y Error se duplican en los streams nativos de
    PowerShell (Write-Warning / Write-Error no terminante) para que sean
    capturables/redirigibles por el consumidor.
.PARAMETER Message
    Texto del mensaje.
.PARAMETER Level
    Info | Success | Warn | Error | Step. Por defecto: Info.
.PARAMETER Banner
    Renderiza el mensaje como banner de sección.
.EXAMPLE
    Write-PavLog -Level Success -Message 'Conectado a Security & Compliance PowerShell.'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Success', 'Warn', 'Error', 'Step')]
        [string]$Level = 'Info',

        [switch]$Banner
    )

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $style = switch ($Level) {
        'Info'    { @{ Color = 'Cyan';   Tag = 'INFO ' } }
        'Success' { @{ Color = 'Green';  Tag = 'OK   ' } }
        'Warn'    { @{ Color = 'Yellow'; Tag = 'AVISO' } }
        'Error'   { @{ Color = 'Red';    Tag = 'ERROR' } }
        'Step'    { @{ Color = 'White';  Tag = 'PASO ' } }
    }

    if ($Banner) {
        $line = '═' * [Math]::Min(78, [Math]::Max(20, $Message.Length + 6))
        Write-Host $line -ForegroundColor $style.Color
        Write-Host "   $Message" -ForegroundColor $style.Color
        Write-Host $line -ForegroundColor $style.Color
    }
    else {
        Write-Host "[$ts] [$($style.Tag)] $Message" -ForegroundColor $style.Color
    }

    # Duplicar en streams nativos para automatización/captura
    switch ($Level) {
        'Warn'  { Write-Warning $Message }
        'Error' { Write-Error -Message $Message -ErrorAction Continue }
    }
}
