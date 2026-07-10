#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Pruebas del motor de reporting (Fase 2). No requieren tenant ni ImportExcel.

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Get-Module PurviewAssessment -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot 'PurviewAssessment.psd1') -Force -ErrorAction Stop
}

Describe 'ConvertTo-PavHtml (seguridad de codificación)' {
    It 'codifica caracteres peligrosos' {
        InModuleScope PurviewAssessment {
            ConvertTo-PavHtml '<script>&"x"</script>' | Should -Be '&lt;script&gt;&amp;&quot;x&quot;&lt;/script&gt;'
        }
    }
    It 'devuelve vacío ante $null' {
        InModuleScope PurviewAssessment { ConvertTo-PavHtml $null | Should -Be '' }
    }
}

Describe 'New-PavBadge' {
    It 'aplica la clase CSS del tipo' {
        InModuleScope PurviewAssessment {
            New-PavBadge -Text 'Habilitada' -Type Ok | Should -Match 'class="pav-badge ok"'
        }
    }
    It 'modo -Bool: Sí/Ok con verdadero, No/neutral con falso' {
        InModuleScope PurviewAssessment {
            New-PavBadge -Bool $true  | Should -Match '>S(í|&#237;)<'
            New-PavBadge -Bool $false | Should -Match 'neutral'
        }
    }
    It 'codifica el texto (sin HTML crudo)' {
        InModuleScope PurviewAssessment {
            New-PavBadge -Text '<b>x</b>' -Type Info | Should -Not -Match '<b>'
        }
    }
}

Describe 'New-PavHtmlCard' {
    It 'codifica título y genera data-name en minúsculas para la búsqueda' {
        InModuleScope PurviewAssessment {
            $c = New-PavHtmlCard -Title 'Directiva <XSS> PII'
            $c | Should -Match 'data-name="directiva &lt;xss&gt; pii"'
            $c | Should -Match 'Directiva &lt;XSS&gt; PII'
            $c | Should -Not -Match '<XSS>'
        }
    }
    It '-Expanded agrega la clase exp' {
        InModuleScope PurviewAssessment {
            (New-PavHtmlCard -Title 'x' -Expanded) | Should -Match 'pav-card exp'
            (New-PavHtmlCard -Title 'x')           | Should -Not -Match 'pav-card exp'
        }
    }
}

Describe 'New-PavHtmlTable / New-PavPropList' {
    It 'renderiza columnas en el orden de -Property y codifica valores' {
        InModuleScope PurviewAssessment {
            $t = New-PavHtmlTable -Data ([pscustomobject]@{ A = '<i>1</i>'; B = 2 }) -Property B, A
            $t | Should -Match '<th>B</th>\s*<th>A</th>'
            $t | Should -Match '&lt;i&gt;1&lt;/i&gt;'
        }
    }
    It 'sin datos devuelve el aviso pav-empty' {
        InModuleScope PurviewAssessment {
            New-PavHtmlTable -Data @() | Should -Match 'pav-empty'
        }
    }
    It 'PropList: nulos como "No configurado", booleanos como Sí/No, arrays unidos' {
        InModuleScope PurviewAssessment {
            $p = New-PavPropList -Properties ([ordered]@{ A = $null; B = $true; C = @('x','y') })
            $p | Should -Match 'No configurado'
            $p | Should -Match '>S(í|&#237;)<'
            $p | Should -Match 'x, y'
        }
    }
}

Describe 'New-PavHtmlSection' {
    It 'devuelve objeto tipado con Id/Title/Html' {
        InModuleScope PurviewAssessment {
            $s = New-PavHtmlSection -Id 'dlp' -Title 'DLP' -ContentHtml '<p>x</p>'
            $s.PSObject.TypeNames[0] | Should -Be 'PurviewAssessment.HtmlSection'
            $s.Html | Should -Match 'id="section-dlp"'
        }
    }
    It 'sin contenido renderiza el aviso de "no evaluada"' {
        InModuleScope PurviewAssessment {
            (New-PavHtmlSection -Id 'irm' -Title 'IRM' -ContentHtml $null).Html | Should -Match 'no fue evaluada'
        }
    }
    It 'rechaza Ids inválidos' {
        InModuleScope PurviewAssessment {
            { New-PavHtmlSection -Id 'DLP Malo!' -Title 'x' -ContentHtml 'x' } | Should -Throw
        }
    }
}

Describe 'New-PavHtmlDocument' {
    It 'con 2+ secciones genera tabs; con 1 sección no' {
        InModuleScope PurviewAssessment {
            $s1 = New-PavHtmlSection -Id 'a' -Title 'A' -ContentHtml 'x'
            $s2 = New-PavHtmlSection -Id 'b' -Title 'B' -ContentHtml 'y'
            (New-PavHtmlDocument -Title 'T' -Sections $s1, $s2) | Should -Match 'class="pav-tabs"'
            (New-PavHtmlDocument -Title 'T' -Sections $s1)      | Should -Not -Match 'class="pav-tabs"'
        }
    }
    It 'embebe ambos temas, bootstrap anti-parpadeo y JS del motor' {
        InModuleScope PurviewAssessment {
            $d = New-PavHtmlDocument -Title 'T' -Sections (New-PavHtmlSection -Id 'a' -Title 'A' -ContentHtml 'x')
            $d | Should -Match '\[data-theme="light"\]'
            $d | Should -Match 'prefers-color-scheme'
            $d | Should -Match 'pav-report-theme'
            foreach ($fn in 'pavToggleTheme', 'pavToggleCard', 'pavToggleAll', 'pavSwitchTab', 'pavFilter') {
                $d | Should -Match "function $fn"
            }
        }
    }
    It 'no referencia recursos externos (informe portable/offline)' {
        InModuleScope PurviewAssessment {
            $d = New-PavHtmlDocument -Title 'T' -Sections (New-PavHtmlSection -Id 'a' -Title 'A' -ContentHtml 'x')
            $d | Should -Not -Match 'https?://'
        }
    }
}

Describe 'Export-PavExcelWorkbook' {
    It 'degrada con $null y advertencia si ImportExcel no está disponible' {
        InModuleScope PurviewAssessment {
            Mock Assert-PavModule { $false }
            Mock Write-PavLog { }
            $r = Export-PavExcelWorkbook -Path (Join-Path ([IO.Path]::GetTempPath()) 'x.xlsx') -Sheets ([ordered]@{ Hoja = @([pscustomobject]@{ A = 1 }) })
            $r | Should -BeNullOrEmpty
            Should -Invoke Write-PavLog -ParameterFilter { $Level -eq 'Warn' }
        }
    }
}
