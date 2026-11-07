# Prueft die fuenf Sprachen: Sprachdateien vollstaendig und gleich aufgebaut,
# alles passt in den Rahmen, Katalog uebersetzt, Sprache erkennen, merken,
# umschalten und an Skripte weitergeben.
#
# Aufruf aus apps\cli-uwh:  powershell -ExecutionPolicy Bypass -File tests\sprache.tests.ps1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
foreach ($lib in @('core', 'yaml', 'lang', 'repos', 'catalog', 'providers', 'menu', 'execute', 'profiles', 'update')) {
    . (Join-Path $root "classes\$lib.ps1")
}
$global:UwhVersion = 'test'
# Wie uwh selbst: ohne UTF-8 kaemen Umlaute aus Skripten verstuemmelt an.
Initialize-UwhConsole
Set-UwhLanguage 'de'

$sandkasten = Join-Path $env:TEMP ('uwh-sprache-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $sandkasten 'config') -Force | Out-Null
function Get-UwhSettingsFile { Join-Path $sandkasten 'config\settings.yaml' }

$script:Pass = 0
$script:Fail = 0

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:Pass++
        Write-Host "  ok    $Name" -ForegroundColor DarkGreen
    } catch {
        $script:Fail++
        Write-Host "  FEHL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}
function Assert-Equal {
    param($Expected, $Actual, [string]$What = 'Wert')
    if ($Expected -ne $Actual) { throw ("{0}: erwartet '{1}', erhalten '{2}'" -f $What, $Expected, $Actual) }
}
function Assert-True {
    param($Condition, [string]$What = 'Bedingung')
    if (-not $Condition) { throw "$What war nicht erfuellt" }
}

$sprachen = @(Get-UwhLanguages)
$roh = @{}
foreach ($l in $sprachen) { $roh[$l] = Import-UwhYaml (Join-Path $root "lang\$l.yaml") }
$katalog = Get-UwhCatalog (Join-Path $root 'assets\catalog.yaml')

function Get-Platzhalter {
    param([string]$Text)
    (@([regex]::Matches($Text, '\{\d+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique)) -join ','
}

function Stelle-Ein {
    param([string]$Sprache)
    Set-UwhLanguage $Sprache
    Set-UwhCatalogLanguage $katalog
}

# ------------------------------------------------------------------

Write-Host ''
Write-Host 'Sprachdateien' -ForegroundColor Cyan

Test-Case 'Es gibt genau die fuenf Sprachen de, en, fr, it, es' {
    Assert-Equal 'de,en,fr,it,es' ($sprachen -join ',') 'Liste'
    foreach ($l in $sprachen) { Assert-True ($roh[$l] -is [System.Collections.IDictionary]) "lang\$l.yaml lesbar" }
}

Test-Case 'Jede Sprache hat alle Schluessel, keinen leeren und dieselben Platzhalter' {
    $en = $roh['en']
    foreach ($l in $sprachen) {
        $d = $roh[$l]
        foreach ($k in $en.Keys) {
            if (-not $d.Contains($k)) { throw "${l}: '$k' fehlt" }
            $v = [string]$d[$k]
            if (-not $v.Trim()) { throw "${l}: '$k' ist leer" }
            if ((Get-Platzhalter $v) -ne (Get-Platzhalter ([string]$en[$k]))) { throw "${l}: '$k' hat andere Platzhalter als Englisch" }
        }
        foreach ($k in $d.Keys) { if (-not $en.Contains($k)) { throw "${l}: '$k' gibt es auf Englisch nicht" } }
    }
}

Test-Case 'Jeder Schluessel im Code steht in den Sprachdateien - und jeder dort wird benutzt' {
    $code = (@(Get-ChildItem (Join-Path $root 'classes') -Filter '*.ps1') + @(Get-Item (Join-Path $root 'uwh.ps1')) |
             ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    $benutzt = @{}
    foreach ($m in [regex]::Matches($code, "(?:\bT|Format-UwhBadge)\s+'([a-z0-9_.]+)'")) { $benutzt[$m.Groups[1].Value] = $true }
    # Zusammengesetzte Schluessel
    foreach ($m in @('install', 'update', 'uninstall')) {
        foreach ($k in @("mode.$m.title", "mode.$m.ask", "summary.$m")) { $benutzt[$k] = $true }
    }
    foreach ($q in @('windows', 'settings', 'parameter')) { $benutzt["doctor.language.$q"] = $true }
    foreach ($k in @('repo.clonefail', 'repo.pullfail')) { $benutzt[$k] = $true }

    foreach ($k in $benutzt.Keys) { if (-not $roh['en'].Contains($k)) { throw "'$k' steht im Code, aber nicht in en.yaml" } }
    foreach ($k in $roh['en'].Keys) { if (-not $benutzt.ContainsKey($k)) { throw "'$k' steht in en.yaml, wird aber nirgends benutzt" } }
}

Test-Case 'Kurze Texte bleiben kurz' {
    foreach ($l in $sprachen) {
        $d = $roh[$l]
        $grenzen = [ordered]@{
            6  = @('badge.ok', 'badge.info', 'badge.warn', 'badge.err')
            11 = @('menu.installed')
            14 = @('mode.install.title', 'mode.update.title', 'mode.uninstall.title')
            17 = @('doctor.admin', 'doctor.state', 'doctor.folder', 'doctor.netdrive', 'doctor.language',
                   'doctor.catalog', 'doctor.repos')
            40 = @('mode.install.ask', 'mode.update.ask', 'mode.uninstall.ask', 'summary.title',
                   'collect.title', 'run.title', 'profile.load', 'doctor.title')
        }
        foreach ($max in $grenzen.Keys) {
            foreach ($k in $grenzen[$max]) {
                $n = ([string]$d[$k]).Length
                if ($n -gt $max) { throw "${l}: '$k' hat $n Zeichen, erlaubt sind $max" }
            }
        }
    }
}

Test-Case 'Plaketten sind in jeder Sprache gleich breit' {
    try {
        foreach ($l in $sprachen) {
            Set-UwhLanguage $l
            $breiten = @('badge.ok', 'badge.info', 'badge.warn', 'badge.err' | ForEach-Object { (Format-UwhBadge $_).Length })
            Assert-Equal 1 @($breiten | Sort-Object -Unique).Count "Breiten in $l"
        }
    } finally { Set-UwhLanguage 'de' }
}

Test-Case 'Ja und Nein versteht uwh in allen fuenf Sprachen' {
    foreach ($j in @('j', 'ja', 'J', 'y', 'yes', 'o', 'oui', 's', 'si', "s$([char]0xEC)", "s$([char]0xED)", 'true')) {
        Assert-True (Test-UwhJa $j) "'$j' heisst ja"
    }
    foreach ($n in @('n', 'nein', 'N', 'no', 'non', 'false')) { Assert-True (Test-UwhNein $n) "'$n' heisst nein" }
    Assert-True (-not (Test-UwhJa 'n')) 'n ist nicht ja'
    Assert-True (-not (Test-UwhNein 'j')) 'j ist nicht nein'
    foreach ($l in $sprachen) {
        $b = [string]$roh[$l]['yesno.letter']
        Assert-True (Test-UwhJa $b) "der Buchstabe fuer ja in $l"
        Assert-True (([string]$roh[$l]['yesno.yes']).Contains($b.ToUpperInvariant())) "Hinweis in $l nennt ihn"
    }
}

# ------------------------------------------------------------------

Write-Host ''
Write-Host 'Darstellung' -ForegroundColor Cyan

Test-Case 'Die Tastenhilfe ist in jeder Sprache und Breite vollstaendig' {
    $vorher = $script:UwhWidth
    try {
        foreach ($l in $sprachen) {
            Set-UwhLanguage $l
            foreach ($breite in @(46, 52, 60, 70, 78)) {
                $script:UwhWidth = $breite
                foreach ($nr in 0..2) {
                    $modus = Get-UwhModus $nr
                    $fuss = @(Get-UwhPickerFoot $modus 12)
                    foreach ($z in $fuss) {
                        if ($z.Length -ne $breite) { throw "${l}, Breite ${breite}: eine Zeile ist $($z.Length) lang" }
                    }
                    $ganz = ($fuss | ForEach-Object { $_.Trim('|', ' ') }) -join ' '
                    foreach ($teil in @((T 'menu.move'), (T 'menu.toggle'), (T 'menu.next'), (T 'menu.find'),
                                        (T 'menu.quit'), (T 'menu.all'), (T 'menu.profile'), $modus.Titel,
                                        (T 'lang.name'), (T 'menu.selected' 12))) {
                        if (-not $ganz.Contains($teil)) { throw "${l}, Breite ${breite}: '$teil' fehlt oder ist abgeschnitten" }
                    }
                }
            }
        }
    } finally {
        $script:UwhWidth = $vorher
        Set-UwhLanguage 'de'
    }
}

Test-Case 'Menuezeilen und Ueberschriften sind in jeder Sprache gleich breit' {
    $vorher = $script:UwhWidth
    try {
        foreach ($l in $sprachen) {
            Stelle-Ein $l
            foreach ($breite in @(46, 78)) {
                $script:UwhWidth = $breite
                foreach ($r in (Build-UwhRows $katalog '' @{ '7zip' = $true } 'install')) {
                    $z = Format-UwhRow $r $true $true
                    if ($z.Length -ne $breite) { throw "${l}, Breite ${breite}: '$($r.Text)' ist $($z.Length) breit" }
                }
            }
            foreach ($c in $katalog.Categories) {
                $n = Get-UwhCategoryName $katalog $c
                if ($n.Length -gt 40) { throw "${l}: Kategorie '$n' zu lang" }
            }
        }
    } finally {
        $script:UwhWidth = $vorher
        Stelle-Ein 'de'
    }
}

# ------------------------------------------------------------------

Write-Host ''
Write-Host 'Sprache erkennen, merken, umschalten' -ForegroundColor Cyan

Test-Case 'Die Sprache kommt aus Windows - ist sie keine der fuenf, gilt Englisch' {
    $alt = [Threading.Thread]::CurrentThread.CurrentUICulture
    try {
        foreach ($paar in @(@('de-DE', 'de'), @('de-AT', 'de'), @('fr-CH', 'fr'), @('it-IT', 'it'),
                             @('es-MX', 'es'), @('en-GB', 'en'), @('nl-NL', 'en'), @('ja-JP', 'en'))) {
            [Threading.Thread]::CurrentThread.CurrentUICulture = [Globalization.CultureInfo]$paar[0]
            Assert-Equal $paar[1] (Get-UwhSystemLanguage) $paar[0]
        }
    } finally {
        [Threading.Thread]::CurrentThread.CurrentUICulture = $alt
    }
}

Test-Case 'Gemerkt wird in config\settings.yaml - Aufruf vor Einstellung vor Windows' {
    Copy-Item -LiteralPath (Join-Path $root 'config\settings.yaml.example') -Destination "$(Get-UwhSettingsFile).example"
    Assert-Equal '' (Get-UwhSavedLanguage) 'noch nichts gemerkt'

    Assert-True (Save-UwhLanguage 'it') 'gespeichert'
    $text = Get-Content -LiteralPath (Get-UwhSettingsFile) -Raw
    Assert-True ($text -match '(?m)^language: it\s*$') 'Zeile gesetzt'
    Assert-True ($text -like '*Leer = wie Windows*') 'die Erklaerung aus der Vorlage bleibt'

    [void](Save-UwhLanguage 'fr')
    Assert-Equal 1 @(Get-Content -LiteralPath (Get-UwhSettingsFile) | Where-Object { $_ -match '^language:' }).Count 'nur eine Zeile'

    Initialize-UwhLanguage ''
    Assert-Equal 'fr' (Get-UwhLanguage) 'gemerkte Sprache'
    Assert-Equal 'settings' (Get-UwhLanguageSource) 'Quelle'

    Initialize-UwhLanguage 'ES'
    Assert-Equal 'es' (Get-UwhLanguage) 'der Aufruf gewinnt'
    Assert-Equal 'parameter' (Get-UwhLanguageSource) 'Quelle'

    Set-Content -LiteralPath (Get-UwhSettingsFile) -Value 'language: xx' -Encoding UTF8
    Initialize-UwhLanguage ''
    Assert-Equal (Get-UwhSystemLanguage) (Get-UwhLanguage) 'Unsinn in der Datei: wie Windows'
    Assert-Equal 'windows' (Get-UwhLanguageSource) 'Quelle'
    Set-UwhLanguage 'de'
}

Test-Case 'L schaltet reihum durch alle fuenf Sprachen' {
    Set-UwhLanguage 'de'
    $folge = @()
    for ($i = 0; $i -lt 5; $i++) {
        $n = Get-UwhNextLanguage
        $folge += $n
        Set-UwhLanguage $n
    }
    Assert-Equal 'en,fr,it,es,de' ($folge -join ',') 'Reihenfolge'
}

Test-Case 'Eine unbekannte Sprache faellt auf Englisch zurueck' {
    Set-UwhLanguage 'xx'
    Assert-Equal 'en' (Get-UwhLanguage) 'Sprache'
    Assert-Equal 'Nothing selected.' (T 'main.nothing') 'Text'
    Set-UwhLanguage 'de'
    Assert-Equal 'gibts.nicht' (T 'gibts.nicht') 'unbekannter Schluessel zeigt sich selbst'
}

# ------------------------------------------------------------------

Write-Host ''
Write-Host 'Katalog' -ForegroundColor Cyan

Test-Case 'Jeder Eintrag ist in jeder Sprache uebersetzt' {
    Assert-Equal 0 $katalog.Problems.Count 'Katalog ohne Beanstandung'
    foreach ($e in $katalog.Entries) {
        foreach ($l in @('de', 'es', 'it', 'fr')) {
            $k = $l.ToUpperInvariant()
            foreach ($f in @('description', 'category')) {
                if (-not $e.Texte[$f].ContainsKey($l)) { throw "'$($e.Key)': $f$k fehlt" }
            }
            if ($e.Texte.note[''] -and -not $e.Texte.note.ContainsKey($l)) { throw "'$($e.Key)': note$k fehlt" }
            if ($e.Texte.name.Count -gt 1 -and -not $e.Texte.name.ContainsKey($l)) { throw "'$($e.Key)': name$k fehlt" }
            if ($e.Texte.id.Count -gt 1 -and -not $e.Texte.id.ContainsKey($l)) { throw "'$($e.Key)': id$k fehlt" }
            foreach ($a in $e.Actions) {
                if ($a.Texte.description[''] -and -not $a.Texte.description.ContainsKey($l)) {
                    throw "'$($e.Key)', Aktion $($a.Name): description$k fehlt"
                }
                foreach ($p in $a.Prompts) {
                    if (-not $p.Texte.question.ContainsKey($l)) { throw "'$($e.Key)', $($p.Variable): question$k fehlt" }
                }
            }
            # Eine Kategorie heisst in jedem Eintrag gleich - sonst stimmt die Ueberschrift nicht.
            if ($e.Texte.category[$l] -ne $katalog.CategoryTexts[$e.Category][$l]) {
                throw "'$($e.Key)': category$k '$($e.Texte.category[$l])' weicht ab"
            }
        }
    }
}

Test-Case 'Firefox und Thunderbird kommen in der eingestellten Sprache' {
    $erwartet = @{ de = '.de'; en = ''; fr = '.fr'; it = '.it'; es = '.es-ES' }
    try {
        foreach ($l in $sprachen) {
            Stelle-Ein $l
            Assert-Equal ('Mozilla.Firefox' + $erwartet[$l]) (Get-UwhEntry $katalog 'firefox').Id "Firefox $l"
            Assert-Equal ('Mozilla.Thunderbird' + $erwartet[$l]) (Get-UwhEntry $katalog 'thunderbird').Id "Thunderbird $l"
        }
    } finally { Stelle-Ein 'de' }
    Assert-Equal 5 @((Get-UwhEntry $katalog 'firefox').Ids).Count 'fuenf Fassungen'
    Assert-Equal 1 @((Get-UwhEntry $katalog '7zip').Ids).Count 'sonst eine'
}

Test-Case 'Installiert ist installiert - egal in welcher Sprache' {
    $script:UwhInstalledIds = @{ 'Mozilla.Firefox.de' = $true }
    try {
        Stelle-Ein 'fr'
        $f = Get-UwhEntry $katalog 'firefox'
        Assert-True (Test-UwhEntryInstalled $f) 'als installiert erkannt'
        Assert-Equal 'Mozilla.Firefox.de' (Get-UwhInstalledVariant $f) 'die deutsche Fassung ist da'
        Assert-True ($null -eq (Get-UwhInstalledVariant (Get-UwhEntry $katalog '7zip'))) 'eine Kennung: nichts zu suchen'
    } finally {
        $script:UwhInstalledIds = $null
        Stelle-Ein 'de'
    }
}

Test-Case 'Aktualisiert wird die installierte Fassung, installiert die der Sprache' {
    $script:UwhInstalledIds = @{ 'Mozilla.Firefox.de' = $true }
    $script:Befehle = New-Object System.Collections.Generic.List[string]
    function Get-UwhWinget { 'winget.exe' }
    function Invoke-UwhExe { param($Exe, $Arguments) $script:Befehle.Add(($Arguments -join ' ')); [pscustomobject]@{ Code = 0; Output = '' } }
    try {
        Stelle-Ein 'fr'
        $f = Get-UwhEntry $katalog 'firefox'
        [void](Invoke-UwhWinget $f 'update')
        [void](Invoke-UwhWinget $f 'install')
        Assert-True ($script:Befehle[0] -like 'upgrade --id Mozilla.Firefox.de *') "Aktualisieren: $($script:Befehle[0])"
        Assert-True ($script:Befehle[1] -like 'install --id Mozilla.Firefox.fr *') "Installieren: $($script:Befehle[1])"
    } finally {
        $script:UwhInstalledIds = $null
        Stelle-Ein 'de'
    }
}

Test-Case 'Die Suche findet auch ueber den englischen Grundtext' {
    try {
        Stelle-Ein 'fr'
        Assert-True (@(Find-UwhEntries $katalog 'navigateur').Count -ge 3) 'franzoesisch'
        Assert-True (@(Find-UwhEntries $katalog 'browser').Count -ge 3) 'englisch'
        [void](Find-UwhEntries $katalog '[*?')
    } finally { Stelle-Ein 'de' }
}

# ------------------------------------------------------------------

Write-Host ''
Write-Host 'Skripte und Aufruf' -ForegroundColor Cyan

Test-Case 'Eingebaute Skripte sprechen die eingestellte Sprache - mit allen Akzenten' {
    $e = Get-UwhEntry $katalog 'explorer'
    $erwartet = @{
        de = 'Unbekannte Aktion'; en = 'Unknown action'; fr = 'Action inconnue'
        it = 'Azione sconosciuta'; es = "Acci$([char]0xF3)n desconocida"
    }
    try {
        foreach ($l in $sprachen) {
            Set-UwhLanguage $l
            $r = Invoke-UwhScript $e 'gibtsnicht' @{}
            Assert-Equal 'fehler' $r.Status "Status $l"
            Assert-True ($r.Message -like "*$($erwartet[$l])*") "${l}: '$($r.Message)'"
        }

        # energie.ps1 bricht bei unbekanntem Plan ab, bevor es etwas aendert.
        Set-UwhLanguage 'fr'
        $r = Invoke-UwhScript (Get-UwhEntry $katalog 'energie') 'install' @{ PLAN = 'xyz' }
        Assert-True ($r.Message -like "*Mode inconnu 'xyz'*") "energie.ps1: '$($r.Message)'"
    } finally { Set-UwhLanguage 'de' }
}

function Rufe-Uwh {
    param([string[]]$Argumente)
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $datei = Join-Path $sandkasten ('cli-{0}.txt' -f [guid]::NewGuid().ToString('N').Substring(0, 6))
    $p = Start-Process -FilePath $exe -Wait -PassThru -NoNewWindow -RedirectStandardOutput $datei `
         -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass',
                          '-File', (Join-Path $root 'uwh.ps1'), '-NoUpdate') + $Argumente)
    $text = if (Test-Path $datei) { Get-Content -LiteralPath $datei -Raw } else { '' }
    return [pscustomobject]@{ Code = $p.ExitCode; Text = [string]$text }
}

Test-Case 'Aufruf: -Language fr zeigt die Liste auf Franzoesisch' {
    $r = Rufe-Uwh @('-List', '-Language', 'fr')
    Assert-Equal 0 $r.Code 'Rueckgabewert'
    Assert-True ($r.Text -like '*Navigateurs*') 'Kategorie'
    Assert-True ($r.Text -like '*Navigateur web*') 'Beschreibung'
}

Test-Case 'Aufruf: eine unbekannte Sprache wird freundlich abgelehnt' {
    $r = Rufe-Uwh @('-List', '-Language', 'xx')
    Assert-Equal 2 $r.Code 'Rueckgabewert'
    Assert-True ($r.Text -like "*'xx'*") 'nennt die Eingabe'
    Assert-True ($r.Text -like '*de, en, fr, it, es*') 'nennt die fuenf'
}

# ------------------------------------------------------------------

Remove-Item -LiteralPath $sandkasten -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("  {0} bestanden, {1} fehlgeschlagen" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
Write-Host ''
if ($script:Fail -gt 0) { exit 1 }
exit 0
