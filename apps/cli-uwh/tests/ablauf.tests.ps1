# Prueft die ganze Kette: Katalog, Profil, Plan, Ablauf, Menuezeilen.
# Es wird nichts installiert - der Provider wird durch eine Attrappe ersetzt.
#
# Aufruf aus apps\cli-uwh:  powershell -ExecutionPolicy Bypass -File tests\ablauf.tests.ps1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
foreach ($lib in @('core', 'yaml', 'lang', 'repos', 'catalog', 'providers', 'menu', 'execute', 'profiles', 'update')) {
    . (Join-Path $root "classes\$lib.ps1")
}
$global:UwhVersion = 'test'
# Gepruefte Texte sind deutsch - unabhaengig davon, wie Windows eingestellt ist.
Set-UwhLanguage 'de'

# Ablage waehrend des Tests in einen eigenen Ordner legen.
$sandkasten = Join-Path $env:TEMP ('uwh-test-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
Set-UwhStateDir $sandkasten

# Profile ebenfalls in den Sandkasten, nicht nach data\ der Arbeitskopie.
# Das Beispielprofil kommt aus der Vorlage - wie beim ersten Start.
$script:ProfilOrdner = Join-Path $sandkasten 'profiles'
New-Item -ItemType Directory -Path $script:ProfilOrdner -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'templates\beispiel-profil.yaml') `
          -Destination (Join-Path $script:ProfilOrdner 'beispiel.yaml')
function Get-UwhProfileDir { $script:ProfilOrdner }

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

# Attrappe statt echter Installation.
$script:Aufrufe = New-Object System.Collections.Generic.List[string]
function Invoke-UwhProvider {
    param($Entry, [string]$Action, [hashtable]$Answers = @{})
    $script:Aufrufe.Add("$($Entry.Key)/$Action")
    if ($Entry.Key -eq 'kaputt') { return New-UwhResult 'fehler' 'Absicht' }
    return New-UwhResult 'ok' ''
}

Write-Host ''
Write-Host 'Ablauf' -ForegroundColor Cyan

# ------------------------------------------------------------------

$catalog = $null

Test-Case 'Katalog laedt ohne Beanstandung' {
    $script:catalog = Get-UwhCatalog
    if ($script:catalog.Problems.Count -gt 0) {
        throw ($script:catalog.Problems -join '; ')
    }
    Assert-True ($script:catalog.Entries.Count -gt 20) 'mehr als 20 Eintraege'
}

Test-Case 'Jeder Eintrag hat eine bekannte Kategorie' {
    foreach ($e in $script:catalog.Entries) {
        if ($script:catalog.Categories -notcontains $e.Category) {
            throw "'$($e.Key)' zeigt auf unbekannte Kategorie '$($e.Category)'"
        }
    }
}

Test-Case 'Jeder Eintrag hat Name und Beschreibung' {
    foreach ($e in $script:catalog.Entries) {
        if (-not $e.Name)        { throw "'$($e.Key)' hat keinen Namen" }
        if (-not $e.Description) { throw "'$($e.Key)' hat keine Beschreibung" }
    }
}

Test-Case 'Keine doppelten Paketkennungen' {
    # Auch die Kennungen je Sprache zaehlen mit (Mozilla.Firefox.de usw.).
    $gesehen = @{}
    foreach ($e in $script:catalog.Entries) {
        foreach ($id in @($e.Ids)) {
            if (-not $id) { continue }
            if ($gesehen.ContainsKey($id)) { throw "Kennung '$id' kommt zweimal vor" }
            $gesehen[$id] = $true
        }
    }
}

Test-Case 'Skript-Eintraege zeigen auf vorhandene Dateien' {
    foreach ($e in $script:catalog.Entries | Where-Object { $_.Provider -eq 'script' }) {
        $p = Join-Path $e.BaseDir $e.File
        if (-not (Test-Path -LiteralPath $p)) { throw "'$($e.Key)': $($e.File) fehlt" }
    }
}

# ------------------------------------------------------------------

Test-Case 'Beispielprofil laedt' {
    $p = Import-UwhProfile 'beispiel'
    Assert-Equal 5 $p.Select.Count 'Anzahl Eintraege'
    $explorer = $p.Select | Where-Object { $_.Key -eq 'explorer' }
    Assert-Equal 'ja' $explorer.Answers['ENDUNGEN'] 'hinterlegte Antwort'
}

Test-Case 'Plan aus Profil' {
    $p = Import-UwhProfile 'beispiel'
    $plan = New-UwhPlan $script:catalog $p.Select -Unattended $true
    Assert-Equal 5 $plan.Items.Count 'Anzahl Schritte'
    Assert-True $plan.NeedsAdmin 'braucht Administratorrechte'
    Assert-Equal 0 $plan.Index 'startet bei 0'
}

Test-Case 'Sammelphase fuellt Antworten aus den Vorgaben' {
    $p = Import-UwhProfile 'beispiel'
    $plan = New-UwhPlan $script:catalog $p.Select -Unattended $true
    Invoke-UwhCollect $script:catalog $plan

    $explorer = $plan.Items | Where-Object { $_.Key -eq 'explorer' }
    Assert-Equal 'ja'   $explorer.Answers['ENDUNGEN']  'aus dem Profil'
    Assert-Equal 'nein' $explorer.Answers['VERSTECKT'] 'aus dem Profil'
}

Test-Case 'Unbekannte Auswahl wird uebersprungen, nicht abgebrochen' {
    $auswahl = @(
        [pscustomobject]@{ Key = '7zip';      Action = 'install'; Answers = @{} }
        [pscustomobject]@{ Key = 'gibtsnicht'; Action = 'install'; Answers = @{} }
    )
    $plan = New-UwhPlan $script:catalog $auswahl -Unattended $true
    Assert-Equal 1 $plan.Items.Count 'nur der gueltige Eintrag'
}

Test-Case 'Unbekannte Aktion wird abgelehnt' {
    $auswahl = @([pscustomobject]@{ Key = 'wsl'; Action = 'update'; Answers = @{} })
    $plan = New-UwhPlan $script:catalog $auswahl -Unattended $true
    Assert-Equal 0 $plan.Items.Count 'Windows-Funktionen koennen kein update'
}

# ------------------------------------------------------------------

Test-Case 'Ablauf arbeitet alle Schritte ab' {
    $script:Aufrufe.Clear()
    $auswahl = @('7zip', 'firefox', 'vlc') | ForEach-Object {
        [pscustomobject]@{ Key = $_; Action = 'install'; Answers = @{} }
    }
    $plan = New-UwhPlan $script:catalog $auswahl -Unattended $true
    [void](Invoke-UwhPlan $script:catalog $plan)

    Assert-Equal 3 $script:Aufrufe.Count 'drei Aufrufe'
    Assert-Equal 3 $plan.Index 'Zeiger am Ende'
    foreach ($i in $plan.Items) { Assert-Equal 'ok' $i.Status "Status von $($i.Key)" }
}

Test-Case 'Zwischenstand wird nach jedem Schritt gesichert' {
    $auswahl = @([pscustomobject]@{ Key = '7zip'; Action = 'install'; Answers = @{} })
    $plan = New-UwhPlan $script:catalog $auswahl -Unattended $true
    [void](Invoke-UwhPlan $script:catalog $plan)

    $wieder = Import-UwhState $plan.Id
    Assert-True ($null -ne $wieder) 'Zwischenstand vorhanden'
    Assert-Equal 1 $wieder.Index 'Zeiger gesichert'
    Assert-Equal 'ok' $wieder.Items[0].Status 'Status gesichert'
    Assert-Equal 1 $wieder.Items.Count 'einzelner Schritt bleibt eine Liste'
    Remove-UwhState $plan.Id
}

Test-Case 'Fehler stoppt den Lauf nicht, wenn es so eingestellt ist' {
    $auswahl = @(
        [pscustomobject]@{ Key = '7zip';    Action = 'install'; Answers = @{} }
        [pscustomobject]@{ Key = 'firefox'; Action = 'install'; Answers = @{} }
    )
    $plan = New-UwhPlan $script:catalog $auswahl -Unattended $true -ContinueOnError $true
    $plan.Items[0].Key = 'kaputt'
    [void](Invoke-UwhPlan $script:catalog $plan)
    Assert-Equal 2 $plan.Index 'beide Schritte angefasst'
}

# ------------------------------------------------------------------

Test-Case 'Profil schreiben und wieder lesen ergibt dasselbe' {
    $auswahl = @(
        [pscustomobject]@{ Key = '7zip';     Action = 'install'; Answers = @{} }
        [pscustomobject]@{ Key = 'explorer'; Action = 'install'; Answers = @{ ENDUNGEN = 'ja'; VERSTECKT = 'nein' } }
    )
    $plan = New-UwhPlan $script:catalog $auswahl -Unattended $true
    $datei = Save-UwhProfile 'testprofil' $plan.Items
    try {
        $p = Import-UwhProfile 'testprofil'
        Assert-Equal 2 $p.Select.Count 'Anzahl'
        $ex = $p.Select | Where-Object { $_.Key -eq 'explorer' }
        Assert-Equal 'ja' $ex.Answers['ENDUNGEN'] 'Antwort erhalten'
    } finally {
        Remove-Item -LiteralPath $datei -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Kennwoerter landen nicht im Profil' {
    $items = @([pscustomobject]@{
        Key = '7zip'; Action = 'install'
        Answers = @{ BENUTZER = 'thomas'; PASSWORT = 'Hu7xQz'; API_TOKEN = 'Kd41Vb' }
    })
    $datei = Save-UwhProfile 'testschutz' $items
    try {
        $text = Get-Content -LiteralPath $datei -Raw
        Assert-True ($text -notmatch 'Hu7xQz')   'Kennwort nicht enthalten'
        Assert-True ($text -notmatch 'Kd41Vb')   'Token nicht enthalten'
        Assert-True ($text -notmatch 'PASSWORT') 'Variablenname nicht enthalten'
        Assert-True ($text -match 'thomas')      'harmlose Angabe enthalten'
    } finally {
        Remove-Item -LiteralPath $datei -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Der Katalog entscheidet, was geheim ist' {
    $datei = Join-Path $sandkasten 'geheim.yaml'
    New-Item -ItemType Directory -Path $sandkasten -Force | Out-Null
    Set-Content -LiteralPath $datei -Encoding UTF8 -Value @(
        'categories:'
        '  - Test'
        'scripts:'
        '  zugang:'
        '    name: Zugang'
        '    description: Test'
        '    category: Test'
        '    provider: script'
        '    file: _template.ps1'
        '    admin: false'
        '    actions:'
        '      - name: install'
        '        prompts:'
        '          - question: Benutzer?'
        '            variable: BENUTZER'
        '            type: text'
        '          - question: Zugangsdaten?'
        '            variable: ZUGANG'
        '            type: secret'
        '          - question: Kennwort?'
        '            variable: PASSWORT'
        '            type: text'
    )
    $c = Get-UwhCatalog $datei
    $e = Get-UwhEntry $c 'zugang'

    Assert-True (Test-UwhGeheim 'ZUGANG' $e 'install')          'type secret zaehlt, auch bei harmlosem Namen'
    Assert-True (-not (Test-UwhGeheim 'BENUTZER' $e 'install')) 'type text bleibt sichtbar'
    Assert-True (Test-UwhGeheim 'PASSWORT' $e 'install')        'falscher Typ im Katalog hebt den Schutz nicht auf'
}

Test-Case 'Der Namensfilter faengt ab, was der Katalog nicht kennt' {
    foreach ($n in @('PASSWORT', 'PWD', 'KENNWORT', 'API_KEY', 'SECRET_X',
                     'ACCESS_TOKEN', 'CREDENTIAL', 'LIZENZSCHLUESSEL', 'GEHEIM', 'PIN')) {
        if (-not (Test-UwhGeheim $n $null 'install')) { throw "'$n' wurde nicht als geheim erkannt" }
    }
    foreach ($n in @('BENUTZER', 'DOMAIN', 'ZIELPFAD', 'PORT', 'GIT_USER', 'GIT_EMAIL')) {
        if (Test-UwhGeheim $n $null 'install') { throw "'$n' wurde faelschlich als geheim behandelt" }
    }
}

Test-Case 'Eine als geheim erklaerte Antwort landet nicht im Profil' {
    $datei = Join-Path $sandkasten 'geheim.yaml'
    $c = Get-UwhCatalog $datei
    $items = @([pscustomobject]@{
        Key = 'zugang'; Action = 'install'
        Answers = @{ BENUTZER = 'thomas'; ZUGANG = 'Xr7pQz'; PASSWORT = 'Vb31Kd' }
    })
    $pfad = Save-UwhProfile 'testkatalog' $items $c
    try {
        $text = Get-Content -LiteralPath $pfad -Raw
        Assert-True ($text -notmatch 'Xr7pQz') 'geheime Antwort nicht enthalten'
        Assert-True ($text -notmatch 'Vb31Kd') 'Kennwort nicht enthalten'
        Assert-True ($text -match 'thomas')    'harmlose Antwort enthalten'
    } finally {
        Remove-Item -LiteralPath $pfad -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Profil mit Kreisbezug wird erkannt' {
    Export-UwhYaml ([ordered]@{ name = 'a'; extends = 'testb'; select = @('7zip') }) (Get-UwhProfileFile 'testa')
    Export-UwhYaml ([ordered]@{ name = 'b'; extends = 'testa'; select = @('vlc')  }) (Get-UwhProfileFile 'testb')
    try {
        $fehler = $false
        try { Import-UwhProfile 'testa' } catch { $fehler = $true }
        Assert-True $fehler 'Kreisbezug gemeldet'
    } finally {
        Remove-Item -LiteralPath (Get-UwhProfileFile 'testa') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Get-UwhProfileFile 'testb') -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Profil erbt vom Elternprofil' {
    Export-UwhYaml ([ordered]@{ name = 'basis'; select = @('7zip', 'vlc') }) (Get-UwhProfileFile 'testbasis')
    Export-UwhYaml ([ordered]@{ name = 'kind'; extends = 'testbasis'; select = @('firefox') }) (Get-UwhProfileFile 'testkind')
    try {
        $p = Import-UwhProfile 'testkind'
        Assert-Equal 3 $p.Select.Count 'geerbte plus eigene'
        Assert-Equal '7zip' $p.Select[0].Key 'Reihenfolge: Eltern zuerst'
    } finally {
        Remove-Item -LiteralPath (Get-UwhProfileFile 'testbasis') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Get-UwhProfileFile 'testkind') -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------------

Test-Case 'Menuezeilen haben durchgehend dieselbe Breite' {
    $rows = Build-UwhRows $script:catalog '' @{}
    Assert-True ($rows.Count -gt 20) 'Zeilen vorhanden'

    $breite = (New-UwhRule).Length
    foreach ($r in ($rows | Select-Object -First 30)) {
        $text = Format-UwhRow $r $true $true
        Assert-Equal $breite $text.Length "Breite bei '$($r.Text)'"
    }
}

Test-Case 'Kein Name und keine Beschreibung wird abgeschnitten - in keiner Sprache' {
    foreach ($e in $script:catalog.Entries) {
        foreach ($name in @($e.Texte.name.Values)) {
            if ($name.Length -gt 24) { throw "Name zu lang: '$name' ($($name.Length))" }
        }
        foreach ($desc in @($e.Texte.description.Values)) {
            if ($desc.Length -gt 31) { throw "Beschreibung zu lang bei '$($e.Key)': '$desc' ($($desc.Length))" }
        }
    }
}

Test-Case 'Der Rahmen passt sich schmalen Fenstern an' {
    $vorher = $script:UwhWidth
    try {
        foreach ($breite in @(46, 50, 60, 64, 70, 78)) {
            $script:UwhWidth = $breite
            $rows = Build-UwhRows $script:catalog '' @{ '7zip' = $true } 'install'

            $zeilen = @(Get-UwhHeader 'Test')
            foreach ($r in ($rows | Select-Object -First 12)) {
                $zeilen += Format-UwhRow $r $true $true
            }
            $zeilen += New-UwhRule

            foreach ($z in $zeilen) {
                if ($z.Length -ne $breite) {
                    throw "bei Breite $breite ist eine Zeile $($z.Length) Zeichen lang: '$z'"
                }
            }
        }
    } finally {
        $script:UwhWidth = $vorher
    }
}

Test-Case 'In schmalen Fenstern faellt die Spalte installiert weg' {
    $vorher = $script:UwhWidth
    try {
        $rows = Build-UwhRows $script:catalog '' @{ '7zip' = $true } 'install'
        $zeile = $rows | Where-Object { $_.Kind -eq 'entry' -and $_.Entry.Key -eq '7zip' } | Select-Object -First 1

        $script:UwhWidth = 78
        Assert-True ((Format-UwhRow $zeile $false $false) -like '*installiert*') 'breit: Spalte da'

        $script:UwhWidth = 56
        Assert-True ((Format-UwhRow $zeile $false $false) -notlike '*installiert*') 'schmal: Spalte weg'
    } finally {
        $script:UwhWidth = $vorher
    }
}

Test-Case 'Set-UwhWidth bleibt in sinnvollen Grenzen' {
    $vorher = $script:UwhWidth
    try {
        Set-UwhWidth
        Assert-True ($script:UwhWidth -ge 46) 'nicht schmaler als 46'
        Assert-True ($script:UwhWidth -le 78) 'nicht breiter als 78'
    } finally {
        $script:UwhWidth = $vorher
    }
}

Test-Case 'Suche findet ueber Name und Beschreibung' {
    $rows = Build-UwhRows $script:catalog 'browser' @{}
    $treffer = @($rows | Where-Object { $_.Kind -eq 'entry' })
    Assert-True ($treffer.Count -ge 3) 'mindestens drei Treffer'
}

Test-Case 'Sehr lange Namen brechen die Darstellung nicht' {
    $lang = [pscustomobject]@{
        Kind = 'entry'; Text = 'x'; Installed = $false
        Entry = [pscustomobject]@{
            Name = ('N' * 120); Description = ('B' * 120); Key = 'x'
        }
    }
    Assert-Equal (New-UwhRule).Length (Format-UwhRow $lang $true $true).Length 'Breite bleibt'
}

# ------------------------------------------------------------------

Test-Case 'Versionsvergleich fuer die Selbstaktualisierung' {
    Assert-True (Test-UwhNewer '0.2.0' '0.1.0')      'neuer wird erkannt'
    Assert-True (Test-UwhNewer '1.0.0' '0.9.9')      'Hauptnummer zaehlt'
    Assert-True (Test-UwhNewer '0.1.10' '0.1.9')     'wird als Zahl verglichen, nicht als Text'
    Assert-True (-not (Test-UwhNewer '0.1.0' '0.1.0')) 'gleich ist kein Update'
    Assert-True (-not (Test-UwhNewer '0.1.0' '0.2.0')) 'aelter ist kein Update'
}

Test-Case 'Unbrauchbare Versionsangabe loest kein Update aus' {
    # Eine kaputte Antwort vom Server darf nicht in einer Schleife enden.
    foreach ($murks in @('kaputt', '', '   ', '<html>404</html>', 'v1.0')) {
        if (Test-UwhNewer $murks '0.1.0') { throw "'$murks' hat ein Update ausgeloest" }
    }
}

Test-Case 'Die eigene VERSION ist lesbar und gueltig' {
    $v = Get-UwhLocalVersion
    Assert-True ($v -match '^\d+\.\d+\.\d+$') "VERSION ist '$v', erwartet wird z.B. 0.1.0"
    Assert-True ($v -eq $v.Trim()) 'keine Leerzeichen drumherum'
    Assert-True (Test-UwhNewer '99.0.0' $v) 'laesst sich vergleichen'
}

Test-Case 'Aktualisierung kopiert richtig ueber eine vorhandene Installation' {
    $quelle = Join-Path $sandkasten 'neu'
    $ziel   = Join-Path $sandkasten 'alt'

    # So sieht ein frisch entpacktes Archiv aus.
    $neuCli = Join-Path $quelle 'apps\cli-uwh'
    foreach ($o in @('classes', 'assets', 'config', 'data\profiles')) {
        New-Item -ItemType Directory -Path (Join-Path $neuCli $o) -Force | Out-Null
    }
    Set-Content (Join-Path $neuCli 'VERSION')              '9.9.9'      -Encoding UTF8
    Set-Content (Join-Path $neuCli 'uwh.ps1')              'neu'        -Encoding UTF8
    Set-Content (Join-Path $neuCli 'classes\core.ps1')     'neu'        -Encoding UTF8
    Set-Content (Join-Path $neuCli 'classes\dazu.ps1')     'dazu'       -Encoding UTF8
    Set-Content (Join-Path $neuCli 'assets\a.ps1')         'neu'        -Encoding UTF8
    Set-Content (Join-Path $neuCli 'config\repo.yaml')     'aus-archiv' -Encoding UTF8
    Set-Content (Join-Path $neuCli 'data\profiles\x.yaml') 'aus-archiv' -Encoding UTF8

    # So sieht die vorhandene Installation aus.
    $altCli = Join-Path $ziel 'apps\cli-uwh'
    foreach ($o in @('classes', 'config', 'data\profiles')) {
        New-Item -ItemType Directory -Path (Join-Path $altCli $o) -Force | Out-Null
    }
    Set-Content (Join-Path $altCli 'VERSION')                  '0.1.0' -Encoding UTF8
    Set-Content (Join-Path $altCli 'uwh.ps1')                  'alt'   -Encoding UTF8
    Set-Content (Join-Path $altCli 'classes\core.ps1')         'alt'   -Encoding UTF8
    Set-Content (Join-Path $altCli 'config\repo.yaml')         'meins' -Encoding UTF8
    Set-Content (Join-Path $altCli 'data\profiles\meins.yaml') 'meins' -Encoding UTF8

    Copy-UwhTree $quelle $ziel

    Assert-True (-not (Test-Path (Join-Path $altCli 'classes\classes'))) 'kein verschachtelter Ordner'
    Assert-Equal 'neu'   (Get-Content (Join-Path $altCli 'classes\core.ps1') -Raw).Trim() 'Datei ersetzt'
    Assert-Equal 'dazu'  (Get-Content (Join-Path $altCli 'classes\dazu.ps1') -Raw).Trim() 'neue Datei dazugekommen'
    Assert-Equal '9.9.9' (Get-Content (Join-Path $altCli 'VERSION') -Raw).Trim()          'VERSION ersetzt'
    Assert-True (Test-Path (Join-Path $altCli 'assets\a.ps1')) 'fehlender Ordner angelegt'

    # Das Wichtigste: Eigenes ueberlebt die Aktualisierung - auch wenn ein
    # Archiv versehentlich etwas an dieser Stelle mitbringt.
    Assert-Equal 'meins' (Get-Content (Join-Path $altCli 'data\profiles\meins.yaml') -Raw).Trim() 'eigenes Profil unberuehrt'
    Assert-True (-not (Test-Path (Join-Path $altCli 'data\profiles\x.yaml'))) 'Profile aus dem Archiv nicht uebernommen'
    Assert-Equal 'meins' (Get-Content (Join-Path $altCli 'config\repo.yaml') -Raw).Trim() 'eigene Einstellungen unberuehrt'
}

Test-Case 'Ohne Projektbaum drumherum aktualisiert sich uwh nicht' {
    # Wer nur apps\cli-uwh irgendwohin kopiert hat, bekaeme sonst den ganzen
    # Projektbaum in einen fremden Ordner gekippt.
    Assert-Equal (Split-Path -Parent (Split-Path -Parent $root)) (Get-UwhProjectRoot) 'Stamm der Arbeitskopie'
    $lose = Join-Path $sandkasten 'woanders\uwh'
    function Get-UwhRoot { $lose }
    Assert-True ($null -eq (Get-UwhProjectRoot)) 'kein Stamm erkannt'
    Assert-True (-not (Update-Uwh -Quiet)) 'keine Aktualisierung'
}

Test-Case 'Antworten liegen nicht im Klartext auf der Platte' {
    $auswahl = @([pscustomobject]@{ Key = 'explorer'; Action = 'install'
                                    Answers = @{ ENDUNGEN = 'ja'; KENNWORT = 'Hu7xQzGeheim' } })
    $plan = New-UwhPlan $script:catalog $auswahl -Unattended $true
    Save-UwhState $plan
    try {
        $text = Get-Content -LiteralPath (Get-UwhStateFile $plan.Id) -Raw
        Assert-True ($text -notlike '*Hu7xQzGeheim*') 'Kennwort nicht im Klartext'
        Assert-True ($text -like '*dpapi:*')          'als verschluesselt gekennzeichnet'
        Assert-True ($text -like '*ENDUNGEN*')        'Variablennamen bleiben lesbar'

        $zurueck = Import-UwhState $plan.Id
        Assert-Equal 'Hu7xQzGeheim' $zurueck.Items[0].Answers['KENNWORT'] 'wieder lesbar'
        Assert-Equal 'ja'           $zurueck.Items[0].Answers['ENDUNGEN'] 'auch die harmlose'

        # Der laufende Plan darf davon nichts mitbekommen.
        Assert-Equal 'Hu7xQzGeheim' $plan.Items[0].Answers['KENNWORT'] 'Plan im Speicher unveraendert'
    } finally {
        Remove-UwhState $plan.Id
    }
}

Test-Case 'Unlesbarer Schutz gibt nichts preis und stuerzt nicht ab' {
    Assert-Equal '' (Unprotect-UwhText 'dpapi:voellig-kaputt') 'kaputte Daten ergeben nichts'
    Assert-Equal 'klartext' (Unprotect-UwhText 'klartext')     'unverschluesselt bleibt unveraendert'
    Assert-Equal '' (Protect-UwhText '')                       'leer bleibt leer'
}

Test-Case 'Netzlaufwerk wird zum UNC-Pfad aufgeloest' {
    # Lokale Pfade und UNC-Pfade bleiben unveraendert.
    Assert-Equal 'C:\Temp\x.ps1' (Resolve-UwhUncPath 'C:\Temp\x.ps1') 'lokaler Pfad'
    Assert-Equal '\\server\share\x.ps1' (Resolve-UwhUncPath '\\server\share\x.ps1') 'UNC bleibt UNC'

    # Zugeordnete Laufwerke werden ersetzt - mit einem echten, falls vorhanden.
    $netz = @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.DisplayRoot }) | Select-Object -First 1
    if ($netz) {
        $pfad = "$($netz.Name):\ordner\datei.ps1"
        $auf = Resolve-UwhUncPath $pfad
        Assert-True ($auf -ne $pfad) 'Laufwerksbuchstabe ersetzt'
        Assert-True ($auf.StartsWith('\\')) 'Ergebnis ist ein UNC-Pfad'
        Assert-True ($auf -notmatch [char]0) 'keine Null-Zeichen im Ergebnis'
        Assert-True ($auf.EndsWith('\ordner\datei.ps1')) 'Rest des Pfades erhalten'
    }
}

Test-Case 'Gefaehrliche Kennungen werden abgelehnt' {
    foreach ($boese in @('--scope machine', 'a b', 'a;b', 'a&b', '', '-x', 'a|b', 'a$b')) {
        if (Test-UwhSafeId $boese) { throw "'$boese' wurde faelschlich zugelassen" }
    }
    foreach ($gut in @('Microsoft.VisualStudioCode', '7zip.7zip', 'Notepad++.Notepad++',
                       'OpenSSH.Client~~~~0.0.1.0', 'Microsoft-Windows-Subsystem-Linux')) {
        if (-not (Test-UwhSafeId $gut)) { throw "'$gut' wurde faelschlich abgelehnt" }
    }
}

Test-Case 'Profilnamen mit Pfadwechsel werden abgelehnt' {
    foreach ($boese in @('..\..\windows\system32', 'a/b', 'a\b', '', '.hidden')) {
        $fehler = $false
        try { Get-UwhProfileFile $boese } catch { $fehler = $true }
        if (-not $fehler) { throw "'$boese' wurde faelschlich zugelassen" }
    }
}

Test-Case 'Nur https wird als Quelle akzeptiert' {
    Assert-True (Test-UwhHttpsUrl 'https://example.com/a.exe') 'https erlaubt'
    Assert-True (-not (Test-UwhHttpsUrl 'http://example.com/a.exe')) 'http abgelehnt'
    Assert-True (-not (Test-UwhHttpsUrl 'file://C:/a.exe')) 'file abgelehnt'
}

Test-Case 'Katalog lehnt einen Eintrag mit Schadkennung ab' {
    $y = @(
        'categories:'
        '  - Test'
        'scripts:'
        '  boese:'
        '    name: Boese'
        '    description: Test'
        '    category: Test'
        '    provider: winget'
        '    id: "Paket --scope machine"'
    ) -join "`r`n"
    $datei = Join-Path $sandkasten 'boese.yaml'
    New-Item -ItemType Directory -Path $sandkasten -Force | Out-Null
    Set-Content -LiteralPath $datei -Value $y -Encoding UTF8

    $c = Get-UwhCatalog $datei
    Assert-Equal 0 $c.Entries.Count 'Eintrag verworfen'
    Assert-Equal 1 $c.Problems.Count 'Problem gemeldet'
}

# ------------------------------------------------------------------
# Tastensteuerung im Menue
# ------------------------------------------------------------------

function Taste {
    param([string]$Name, [string]$Zeichen = "`0")
    [pscustomobject]@{ Key = $Name; KeyChar = [char]$Zeichen[0] }
}

function Neues-Menue {
    param([string]$Filter = '', [string]$Modus = 'install')
    $rows = Build-UwhRows $script:catalog $Filter @{} $Modus
    $pick = @(Get-UwhPickIndexes $rows)
    [pscustomobject]@{
        Rows  = $rows
        Pick  = $pick
        Stand = [pscustomobject]@{ Cursor = 0; Filter = $Filter; Modus = $Modus }
        Wahl  = [ordered]@{}
    }
}
function Druecke {
    param($M, $Taste)
    Invoke-UwhPickerKey $Taste $M.Stand $M.Wahl $M.Rows $M.Pick
}

Test-Case 'Menue: Pfeiltasten bewegen den Cursor' {
    $m = Neues-Menue
    [void](Druecke $m (Taste 'DownArrow'))
    Assert-Equal 1 $m.Stand.Cursor 'runter'
    [void](Druecke $m (Taste 'UpArrow'))
    Assert-Equal 0 $m.Stand.Cursor 'wieder rauf'
}

Test-Case 'Menue: Cursor kann die Liste nicht verlassen' {
    $m = Neues-Menue
    1..5 | ForEach-Object { [void](Druecke $m (Taste 'UpArrow')) }
    Assert-Equal 0 $m.Stand.Cursor 'nicht vor den Anfang'

    1..500 | ForEach-Object { [void](Druecke $m (Taste 'DownArrow')) }
    Assert-Equal ($m.Pick.Count - 1) $m.Stand.Cursor 'nicht hinter das Ende'
}

Test-Case 'Menue: Pos1 und Ende springen an den Rand' {
    $m = Neues-Menue
    [void](Druecke $m (Taste 'End'))
    Assert-Equal ($m.Pick.Count - 1) $m.Stand.Cursor 'ans Ende'
    [void](Druecke $m (Taste 'Home'))
    Assert-Equal 0 $m.Stand.Cursor 'an den Anfang'
}

Test-Case 'Menue: Bild-ab springt, bleibt aber im Rahmen' {
    $m = Neues-Menue
    [void](Druecke $m (Taste 'PageDown'))
    Assert-Equal 5 $m.Stand.Cursor 'fuenf weiter'
    1..100 | ForEach-Object { [void](Druecke $m (Taste 'PageDown')) }
    Assert-Equal ($m.Pick.Count - 1) $m.Stand.Cursor 'haengt am Ende'
}

Test-Case 'Menue: Leertaste waehlt an und wieder ab' {
    $m = Neues-Menue
    $erster = $m.Rows[$m.Pick[0]].Entry.Key

    [void](Druecke $m (Taste 'Spacebar'))
    Assert-True $m.Wahl.Contains($erster) 'angewaehlt'
    Assert-Equal 'install' $m.Wahl[$erster] 'mit der Aktion install'

    [void](Druecke $m (Taste 'Spacebar'))
    Assert-True (-not $m.Wahl.Contains($erster)) 'wieder abgewaehlt'
}

Test-Case 'Menue: Leertaste trifft den Eintrag unter dem Cursor' {
    $m = Neues-Menue
    [void](Druecke $m (Taste 'DownArrow'))
    [void](Druecke $m (Taste 'DownArrow'))
    [void](Druecke $m (Taste 'Spacebar'))

    $erwartet = $m.Rows[$m.Pick[2]].Entry.Key
    Assert-Equal 1 $m.Wahl.Keys.Count 'genau einer gewaehlt'
    Assert-True $m.Wahl.Contains($erwartet) 'der richtige'
}

Test-Case 'Menue: Eingabe braucht eine Auswahl' {
    $m = Neues-Menue
    Assert-Equal '' (Druecke $m (Taste 'Enter')) 'ohne Auswahl passiert nichts'

    [void](Druecke $m (Taste 'Spacebar'))
    Assert-Equal 'weiter' (Druecke $m (Taste 'Enter')) 'mit Auswahl geht es weiter'
}

Test-Case 'Menue: A waehlt alles an und beim zweiten Mal wieder ab' {
    $m = Neues-Menue
    $anzahl = $m.Pick.Count

    [void](Druecke $m (Taste 'A' 'a'))
    Assert-Equal $anzahl $m.Wahl.Keys.Count 'alle gewaehlt'

    [void](Druecke $m (Taste 'A' 'a'))
    Assert-Equal 0 $m.Wahl.Keys.Count 'alle wieder abgewaehlt'
}

Test-Case 'Menue: A ergaenzt eine angefangene Auswahl' {
    $m = Neues-Menue
    [void](Druecke $m (Taste 'Spacebar'))
    [void](Druecke $m (Taste 'A' 'a'))
    Assert-Equal $m.Pick.Count $m.Wahl.Keys.Count 'aus teilweise wird alles'
}

Test-Case 'Menue: A trifft nur, was die Suche zeigt' {
    $m = Neues-Menue 'browser'
    $sichtbar = $m.Pick.Count
    Assert-True ($sichtbar -lt $script:catalog.Entries.Count) 'die Suche schraenkt ein'

    [void](Druecke $m (Taste 'A' 'a'))
    Assert-Equal $sichtbar $m.Wahl.Keys.Count 'nur die sichtbaren'
}

Test-Case 'Menue: Esc loescht erst die Suche, dann beendet es' {
    $m = Neues-Menue 'browser'
    Assert-Equal 'oben' (Druecke $m (Taste 'Escape')) 'erst zurueck nach oben'
    Assert-Equal '' $m.Stand.Filter 'Suche geloescht'
    Assert-Equal 'ende' (Druecke $m (Taste 'Escape')) 'dann beenden'
}

Test-Case 'Menue: Schraegstrich und P melden ihre Handlung' {
    $m = Neues-Menue
    Assert-Equal 'suchen' (Druecke $m (Taste 'Oem2' '/')) 'Suche'
    Assert-Equal 'profil' (Druecke $m (Taste 'P' 'p')) 'Profil'
    Assert-Equal 'profil' (Druecke $m (Taste 'P' 'P')) 'auch gross geschrieben'
}

Test-Case 'Menue: die drei Modi wechseln im Kreis' {
    Assert-Equal 'install'   (Get-UwhModus 0).Name 'erster'
    Assert-Equal 'update'    (Get-UwhModus 1).Name 'zweiter'
    Assert-Equal 'uninstall' (Get-UwhModus 2).Name 'dritter'
    Assert-Equal 'install'   (Get-UwhModus 3).Name 'wieder von vorn'
    Assert-Equal 'update'    (Get-UwhModus 7).Name 'auch nach mehreren Runden'
}

Test-Case 'Menue: L meldet den Sprachwechsel' {
    $m = Neues-Menue
    Assert-Equal 'sprache' (Druecke $m (Taste 'L' 'l')) 'klein geschrieben'
    Assert-Equal 'sprache' (Druecke $m (Taste 'L' 'L')) 'gross geschrieben'
    Assert-Equal 0 $m.Wahl.Keys.Count 'die Auswahl bleibt unberuehrt'
}

Test-Case 'Menue: M meldet den Moduswechsel' {
    $m = Neues-Menue
    Assert-Equal 'modus' (Druecke $m (Taste 'M' 'm')) 'klein geschrieben'
    Assert-Equal 'modus' (Druecke $m (Taste 'M' 'M')) 'gross geschrieben'
}

Test-Case 'Menue: jeder Modus zeigt nur, was er auch kann' {
    $install   = @(Build-UwhRows $script:catalog '' @{} 'install'   | Where-Object { $_.Kind -eq 'entry' })
    $update    = @(Build-UwhRows $script:catalog '' @{} 'update'    | Where-Object { $_.Kind -eq 'entry' })
    $uninstall = @(Build-UwhRows $script:catalog '' @{} 'uninstall' | Where-Object { $_.Kind -eq 'entry' })

    Assert-True ($update.Count -lt $install.Count)    'Windows-Funktionen kennen kein Aktualisieren'
    Assert-True ($uninstall.Count -lt $install.Count) 'eigene Skripte kennen kein Entfernen'

    foreach ($satz in @(@{ A = 'update'; R = $update }, @{ A = 'uninstall'; R = $uninstall })) {
        foreach ($r in $satz.R) {
            $kann = @($r.Entry.Actions | ForEach-Object { $_.Name })
            if ($kann -notcontains $satz.A) {
                throw "'$($r.Entry.Key)' steht unter '$($satz.A)', kann es aber nicht"
            }
        }
    }
}

Test-Case 'Menue: die Auswahl merkt sich den eingestellten Modus' {
    foreach ($modus in @('install', 'update', 'uninstall')) {
        $m = Neues-Menue '' $modus
        [void](Druecke $m (Taste 'Spacebar'))
        $schluessel = @($m.Wahl.Keys)[0]
        Assert-Equal $modus $m.Wahl[$schluessel] "Leertaste im Modus '$modus'"

        $m2 = Neues-Menue '' $modus
        [void](Druecke $m2 (Taste 'A' 'a'))
        $erster = @($m2.Wahl.Keys)[0]
        Assert-Equal $modus $m2.Wahl[$erster] "Alles-Taste im Modus '$modus'"
    }
}

Test-Case 'Menue: aus dem Modus wird die Aktion im Plan' {
    $m = Neues-Menue '' 'uninstall'
    [void](Druecke $m (Taste 'Spacebar'))

    $auswahl = @($m.Wahl.Keys | ForEach-Object {
        [pscustomobject]@{ Key = $_; Action = $m.Wahl[$_]; Answers = @{} }
    })
    $plan = New-UwhPlan $script:catalog $auswahl -Unattended $true
    Assert-Equal 1 $plan.Items.Count 'ein Schritt'
    Assert-Equal 'uninstall' $plan.Items[0].Action 'Aktion uebernommen'
}

Test-Case 'Menue: leere Trefferliste bringt nichts durcheinander' {
    $m = Neues-Menue 'xyzgibtsnicht'
    Assert-Equal 0 $m.Pick.Count 'keine Treffer'
    foreach ($t in @('DownArrow', 'UpArrow', 'End', 'Spacebar', 'PageDown')) {
        [void](Druecke $m (Taste $t))
    }
    Assert-Equal 0 $m.Stand.Cursor 'Cursor bleibt bei 0'
    Assert-Equal 0 $m.Wahl.Keys.Count 'nichts gewaehlt'
}

Test-Case 'Menue: was angehakt wird, kommt beim Aufrufer an' {
    # [hashtable] als Parametertyp machte aus der geordneten Auswahl eine
    # Kopie - alles Angehakte war nach dem Menue wieder weg.
    $typ = (Get-Command Show-UwhPicker).Parameters['Selection'].ParameterType
    Assert-True ($typ -ne [hashtable]) 'Selection ist kein [hashtable]'
    Assert-True ($typ.IsAssignableFrom([System.Collections.Specialized.OrderedDictionary])) 'die geordnete Auswahl passt ohne Kopie'
}

# ------------------------------------------------------------------
# Erhoehter Neustart und Fortsetzen
# ------------------------------------------------------------------

Test-Case 'Pfade mit Leerzeichen kommen beim erhoehten Neustart heil an' {
    Assert-Equal 'C:\a' (Format-UwhArgument 'C:\a') 'ohne Leerzeichen unveraendert'
    Assert-Equal '"C:\Users\Max Mustermann\data"' (Format-UwhArgument 'C:\Users\Max Mustermann\data') 'in Anfuehrungszeichen'
    Assert-Equal '"C:\a b\\"' (Format-UwhArgument 'C:\a b\') 'Backslash am Ende verdoppelt'
    Assert-Equal '""' (Format-UwhArgument '') 'leer'

    # So, wie Start-Process es wirklich weitergibt - wie in Invoke-UwhElevated.
    $ordner = Join-Path $sandkasten 'mit leer'
    New-Item -ItemType Directory -Path $ordner -Force | Out-Null
    $echo = Join-Path $ordner 'echo.ps1'
    Set-Content -LiteralPath $echo -Encoding ASCII -Value 'param([string]$StateDir, [string]$Resume) "[$StateDir][$Resume]"'
    $aus = Join-Path $sandkasten 'echo.txt'
    $pfad = Join-Path $ordner 'data'
    $argumente = @('-NoProfile', '-File', (Format-UwhArgument $echo)) +
                 @(@('-StateDir', $pfad, '-Resume', 'abc123') | ForEach-Object { Format-UwhArgument $_ })
    Start-Process -FilePath (Get-UwhPowerShellExe) -ArgumentList $argumente -Wait -NoNewWindow `
                  -RedirectStandardOutput $aus
    Assert-Equal "[$pfad][abc123]" (Get-Content -LiteralPath $aus -Raw).Trim() 'beim Kind angekommen'
}

Test-Case 'Der Zwischenstand liegt auf einem Pfad, den auch der erhoehte Lauf sieht' {
    $vorher = Get-UwhStateDir
    try {
        $netz = @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.DisplayRoot }) | Select-Object -First 1
        if ($netz) {
            Set-UwhStateDir "$($netz.Name):\uwh\data"
            Assert-True ((Get-UwhStateDir).StartsWith('\\')) "Netzlaufwerk wird UNC: $(Get-UwhStateDir)"
        }
        Set-UwhStateDir 'C:\uwh\data'
        Assert-Equal 'C:\uwh\data' (Get-UwhStateDir) 'lokaler Pfad bleibt'
    } finally {
        Set-UwhStateDir $vorher
    }
}

Test-Case 'Der Zwischenstand kennt die Sprache des Laufs' {
    Set-UwhLanguage 'fr'
    try {
        $plan = New-UwhPlan $script:catalog @([pscustomobject]@{ Key = '7zip'; Action = 'install'; Answers = @{} }) -Unattended $true
    } finally {
        Set-UwhLanguage 'de'
    }
    Save-UwhState $plan
    try {
        Assert-Equal 'fr' (Import-UwhState $plan.Id).Language 'Sprache gesichert'
    } finally {
        Remove-UwhState $plan.Id
    }
}

Test-Case 'Unlesbare Antworten fuehren zu einer Meldung, nicht zu leeren Werten' {
    # So sieht es aus, wenn ein anderes Konto die Administratorrechte gegeben hat.
    $auswahl = @([pscustomobject]@{ Key = 'explorer'; Action = 'install'; Answers = @{ ENDUNGEN = 'ja' } })
    $plan = New-UwhPlan $script:catalog $auswahl -Unattended $true
    Save-UwhState $plan
    try {
        $datei = Get-UwhStateFile $plan.Id
        $text = (Get-Content -LiteralPath $datei -Raw) -replace '"dpapi:[^"]*"', '"dpapi:fremdes-konto"'
        Set-Content -LiteralPath $datei -Value $text -Encoding UTF8

        $weiter = Import-UwhState $plan.Id
        Assert-Equal 'fehler' $weiter.Items[0].Status 'Schritt gesperrt'
        Assert-Equal (T 'run.lostanswers') $weiter.Items[0].Message 'mit Grund'
    } finally {
        Remove-UwhState $plan.Id
    }
}

Test-Case 'Profiloptionen: ein Tippfehler startet nie ungefragt neu' {
    foreach ($paar in @(@('never', 'never'), @('nein', 'never'), @('no', 'never'), @($false, 'never'),
                         @('auto', 'auto'), @('ja', 'auto'), @($true, 'auto'),
                         @('ask', 'ask'), @('', 'ask'), @($null, 'ask'), @('neustarten!', 'ask'))) {
        Assert-Equal $paar[1] (ConvertTo-UwhRebootPolicy $paar[0]) "reboot: '$($paar[0])'"
    }
    Assert-True (-not (ConvertTo-UwhJaNein 'false' $true)) '"false" in Anfuehrungszeichen ist falsch'
    Assert-True (-not (ConvertTo-UwhJaNein 'nein' $true)) 'nein ist falsch'
    Assert-True (ConvertTo-UwhJaNein 'oui' $false) 'oui ist wahr'
    Assert-True (ConvertTo-UwhJaNein 'quatsch' $true) 'Unsinn: Standard'

    Set-Content -LiteralPath (Get-UwhProfileFile 'testoptionen') -Encoding UTF8 -Value @(
        'select:', '  - 7zip', 'options:', '  unattended: "false"', '  reboot: nein')
    try {
        $p = Import-UwhProfile 'testoptionen'
        Assert-True ($p.Options['unattended'] -eq $false) 'unattended bleibt aus'
        Assert-Equal 'never' $p.Options['reboot'] 'reboot: nein heisst nie'
    } finally {
        Remove-Item -LiteralPath (Get-UwhProfileFile 'testoptionen') -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Profilnamen duerfen Umlaute und Akzente haben' {
    foreach ($gut in @("B$([char]0xFC)ro", "R$([char]0xE9)union", 'Werkstatt 2', 'a_b-c')) {
        Assert-True (Test-UwhProfileName $gut) "'$gut' erlaubt"
    }
    foreach ($boese in @('CON', 'nul', 'lpt1', '..\x', 'a/b', '.versteckt', ' ', '')) {
        Assert-True (-not (Test-UwhProfileName $boese)) "'$boese' abgelehnt"
    }
    $name = "B$([char]0xFC)ro"
    $datei = Save-UwhProfile $name @([pscustomobject]@{ Key = '7zip'; Action = 'install'; Answers = @{} })
    try {
        Assert-Equal 1 (Import-UwhProfile $name).Select.Count 'gespeichert und gelesen'
    } finally {
        Remove-Item -LiteralPath $datei -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Alte Protokolle und liegengebliebene Zwischenstaende werden aufgeraeumt' {
    $vorher = Get-UwhStateDir
    $ablage = Join-Path $sandkasten 'aufraeumen'
    $logs = Join-Path $ablage 'logs'
    $state = Join-Path $ablage 'state'
    New-Item -ItemType Directory -Path $logs, $state -Force | Out-Null
    for ($i = 1; $i -le 25; $i++) {
        $d = Join-Path $logs ('uwh-{0:D2}.log' -f $i)
        Set-Content -LiteralPath $d -Value 'x'
        (Get-Item -LiteralPath $d).LastWriteTime = (Get-Date).AddHours(-$i)
    }
    Set-Content -LiteralPath (Join-Path $state 'alt.json') -Value '{}'
    (Get-Item -LiteralPath (Join-Path $state 'alt.json')).LastWriteTime = (Get-Date).AddDays(-40)
    Set-Content -LiteralPath (Join-Path $state 'neu.json') -Value '{}'
    try {
        Set-UwhStateDir $ablage
        Clear-UwhAltlasten
        $rest = @(Get-ChildItem -LiteralPath $logs -File | ForEach-Object { $_.Name } | Sort-Object)
        Assert-Equal 20 $rest.Count 'die letzten 20 Protokolle bleiben'
        Assert-True ($rest -contains 'uwh-01.log') 'das neueste bleibt'
        Assert-True ($rest -notcontains 'uwh-25.log') 'das aelteste geht'
        Assert-True (-not (Test-Path (Join-Path $state 'alt.json'))) 'alter Zwischenstand weg'
        Assert-True (Test-Path (Join-Path $state 'neu.json')) 'neuer Zwischenstand bleibt'
    } finally {
        Set-UwhStateDir $vorher
    }
}

Test-Case 'Eine git-Arbeitskopie ueberschreibt sich nicht selbst' {
    # Das Archiv ueber eine Arbeitskopie zu kopieren, loeschte ungesicherte Aenderungen.
    $cli = Join-Path $sandkasten 'arbeitskopie\apps\cli-uwh'
    New-Item -ItemType Directory -Path $cli -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $sandkasten 'arbeitskopie\.git') -Force | Out-Null
    function Get-UwhRoot { $cli }
    $log = Join-Path $sandkasten 'update.log'
    Set-UwhLogFile $log
    try {
        Assert-True (-not (Update-Uwh -Quiet)) 'keine Aktualisierung'
        Assert-True ((Get-Content -LiteralPath $log -Raw) -like '*git-Arbeitskopie*') 'Grund im Protokoll'
    } finally {
        Set-UwhLogFile $null
    }
}

# ------------------------------------------------------------------
# Der tatsaechliche Aufruf, nicht nur die Funktionen dahinter
# ------------------------------------------------------------------

function Rufe-Uwh {
    param([string[]]$Argumente)
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $datei = Join-Path $env:TEMP ('uwh-cli-{0}.txt' -f [guid]::NewGuid().ToString('N').Substring(0, 6))
    try {
        $p = Start-Process -FilePath $exe -Wait -PassThru -NoNewWindow `
             -RedirectStandardOutput $datei `
             -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass',
                              '-File', (Join-Path $root 'uwh.ps1'), '-NoUpdate', '-Language', 'de') + $Argumente)
        $text = if (Test-Path $datei) { Get-Content -LiteralPath $datei -Raw } else { '' }
        return [pscustomobject]@{ Code = $p.ExitCode; Text = [string]$text }
    } finally {
        Remove-Item -LiteralPath $datei -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Aufruf: -Version nennt die Version' {
    $r = Rufe-Uwh @('-Version')
    Assert-Equal 0 $r.Code 'Rueckgabewert'
    Assert-True ($r.Text -match 'uwh \d+\.\d+\.\d+') "Ausgabe war '$($r.Text.Trim())'"
}

Test-Case 'Aufruf: -List zeigt den Katalog' {
    $r = Rufe-Uwh @('-List')
    Assert-Equal 0 $r.Code 'Rueckgabewert'
    Assert-True ($r.Text -like '*7zip*')            'ein bekannter Eintrag kommt vor'
    Assert-True ($r.Text -like '*Grundausstattung*') 'eine Kategorie kommt vor'
}

Test-Case 'Aufruf: unbekanntes Profil endet freundlich' {
    $r = Rufe-Uwh @('-Profile', 'gibtsganzsicherniocht', '-Unattended')
    Assert-Equal 2 $r.Code 'eigener Rueckgabewert, nicht 0'
    Assert-True ($r.Text -like '*gibt es nicht*')   'sagt, was los ist'
    Assert-True ($r.Text -notlike '*CategoryInfo*') 'kein Stapelabzug'
    Assert-True ($r.Text -notlike '*Zeichen:*')     'keine Zeilenangabe aus PowerShell'
}

Test-Case 'Aufruf: -Resume mit unbekannter Kennung endet freundlich' {
    $r = Rufe-Uwh @('-Resume', 'abc123')
    Assert-Equal 2 $r.Code 'eigener Rueckgabewert'
    Assert-True ($r.Text -notlike '*CategoryInfo*') 'kein Stapelabzug'
}

# ------------------------------------------------------------------

Remove-Item -LiteralPath $sandkasten -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("  {0} bestanden, {1} fehlgeschlagen" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
Write-Host ''
if ($script:Fail -gt 0) { exit 1 }
exit 0
