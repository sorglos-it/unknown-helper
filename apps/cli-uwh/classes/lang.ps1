# uwh - Sprache: erkennen, umschalten, Texte liefern
#
# Fuenf Sprachen, jede mit einer Datei lang\<xx>.yaml. Welche gilt, entscheidet
# in dieser Reihenfolge: -Language beim Aufruf, config\settings.yaml (dort merkt
# sich uwh den Wechsel mit L im Menue), sonst die Sprache von Windows. Fehlt ein
# Text in einer Sprache, kommt der englische.

Set-StrictMode -Version 2.0

$script:UwhLanguages = @('de', 'en', 'fr', 'it', 'es')
$script:UwhLang = 'en'
$script:UwhLangSource = 'windows'
$script:UwhTexts = @{}
$script:UwhTextsEn = @{}

function Get-UwhLanguages { $script:UwhLanguages }
function Get-UwhLanguage { $script:UwhLang }

# Woher die Sprache kommt: parameter, settings oder windows.
function Get-UwhLanguageSource { $script:UwhLangSource }

function Test-UwhLanguage {
    param([string]$Language)
    return ($script:UwhLanguages -contains ([string]$Language).Trim())
}

# Die Anzeigesprache von Windows - ist sie keine der fuenf, gilt Englisch.
function Get-UwhSystemLanguage {
    $l = ''
    try { $l = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName } catch { }
    if (Test-UwhLanguage $l) { return $l.ToLowerInvariant() }
    return 'en'
}

function Initialize-UwhLanguage {
    param([string]$Language)

    if (Test-UwhLanguage $Language) {
        $script:UwhLangSource = 'parameter'
    } else {
        $Language = Get-UwhSavedLanguage
        $script:UwhLangSource = 'settings'
        if (-not $Language) {
            $Language = Get-UwhSystemLanguage
            $script:UwhLangSource = 'windows'
        }
    }
    Set-UwhLanguage $Language
}

function Set-UwhLanguage {
    param([string]$Language)

    $l = ([string]$Language).Trim().ToLowerInvariant()
    if (-not (Test-UwhLanguage $l)) { $l = 'en' }

    if ($script:UwhTextsEn.Count -eq 0) { $script:UwhTextsEn = Read-UwhLangFile 'en' }
    $script:UwhTexts = if ($l -eq 'en') { $script:UwhTextsEn } else { Read-UwhLangFile $l }
    $script:UwhLang = $l
}

function Read-UwhLangFile {
    param([string]$Language)

    $texte = @{}
    try {
        $raw = Import-UwhYaml (Get-UwhPath "lang\$Language.yaml")
        if ($raw -is [System.Collections.IDictionary]) {
            foreach ($k in $raw.Keys) {
                if ($null -ne $raw[$k]) { $texte[[string]$k] = [string]$raw[$k] }
            }
        }
    } catch {
        Write-UwhLog 'WARN' ("Sprachdatei {0}.yaml: {1}" -f $Language, $_.Exception.Message)
    }
    return $texte
}

# Die naechste Sprache fuer die Taste L - nach der letzten kommt die erste.
function Get-UwhNextLanguage {
    $i = [array]::IndexOf($script:UwhLanguages, $script:UwhLang)
    return $script:UwhLanguages[($i + 1) % $script:UwhLanguages.Count]
}

# ------------------------------------------------------------------
# Texte
# ------------------------------------------------------------------

# Text zum Schluessel, mit {0}, {1} ... aus den weiteren Argumenten:
#   T 'menu.selected' 3   ->   '3 ausgewaehlt'
function T {
    param([string]$Key)

    $text = $script:UwhTexts[$Key]
    if ($null -eq $text) { $text = $script:UwhTextsEn[$Key] }
    if ($null -eq $text) { $text = $Key }
    if ($args.Count -eq 0) { return $text }

    try {
        return ($text -f $args)
    } catch {
        # Eine kaputte Uebersetzung darf das Menue nicht abstuerzen lassen.
        return ('{0} {1}' -f $text, ($args -join ' '))
    }
}

# Ein Feld aus einer YAML-Zuordnung in allen Sprachen. 'description' ist der
# Grundtext, 'descriptionDE', 'descriptionFR' usw. sind die Uebersetzungen:
#   @{ '' = 'Text editor'; de = 'Texteditor'; ... }  - nur, was angegeben ist.
function Get-UwhVariants {
    param($Data, [string]$Field)

    $v = @{ '' = '' }
    if (-not ($Data -is [System.Collections.IDictionary])) { return $v }
    if ($Data.Contains($Field) -and $null -ne $Data[$Field]) { $v[''] = [string]$Data[$Field] }
    foreach ($l in $script:UwhLanguages) {
        $k = $Field + $l.ToUpperInvariant()
        if ($Data.Contains($k) -and $null -ne $Data[$k] -and [string]$Data[$k] -ne '') { $v[$l] = [string]$Data[$k] }
    }
    return $v
}

# Der Text in der gewuenschten Sprache, ohne Uebersetzung der Grundtext.
function Select-UwhText {
    param([hashtable]$Variants, [string]$Language = $script:UwhLang)
    if ($Variants.ContainsKey($Language)) { return $Variants[$Language] }
    return [string]$Variants['']
}

# ------------------------------------------------------------------
# Merken
# ------------------------------------------------------------------

function Get-UwhSettingsFile { Get-UwhPath 'config\settings.yaml' }

function Get-UwhSavedLanguage {
    $datei = Get-UwhSettingsFile
    if (-not (Test-Path -LiteralPath $datei)) { return '' }
    try { $raw = Import-UwhYaml $datei } catch { return '' }
    if (-not ($raw -is [System.Collections.IDictionary]) -or -not $raw.Contains('language')) { return '' }
    $l = ([string]$raw['language']).Trim().ToLowerInvariant()
    if (Test-UwhLanguage $l) { return $l }
    return ''
}

# Schreibt die Sprache nach config\settings.yaml. Ersetzt wird nur die Zeile
# 'language:' - Kommentare und alles andere bleiben, wie der Anwender sie hat.
function Save-UwhLanguage {
    param([string]$Language)

    $datei = Get-UwhSettingsFile
    try {
        $zeilen = @()
        if (Test-Path -LiteralPath $datei) {
            $zeilen = @(Get-Content -LiteralPath $datei -Encoding UTF8)
        } elseif (Test-Path -LiteralPath "$datei.example") {
            $zeilen = @(Get-Content -LiteralPath "$datei.example" -Encoding UTF8)
        }

        $gefunden = $false
        for ($i = 0; $i -lt $zeilen.Count; $i++) {
            if ($zeilen[$i] -match '^language\s*:') { $zeilen[$i] = "language: $Language"; $gefunden = $true; break }
        }
        if (-not $gefunden) { $zeilen += "language: $Language" }

        $ordner = Split-Path -Parent $datei
        if (-not (Test-Path -LiteralPath $ordner)) { New-Item -ItemType Directory -Path $ordner -Force | Out-Null }
        Set-Content -LiteralPath $datei -Value $zeilen -Encoding UTF8
        $script:UwhLangSource = 'settings'
        return $true
    } catch {
        Write-UwhLog 'WARN' ("Sprache nicht gespeichert: {0}" -f $_.Exception.Message)
        return $false
    }
}
