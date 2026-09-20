# Prueft die ganze Kette: Katalog, Profil, Plan, Ablauf, Menuezeilen.
# Es wird nichts installiert - der Provider wird durch eine Attrappe ersetzt.
#
# Aufruf:  powershell -ExecutionPolicy Bypass -File tests\ablauf.tests.ps1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
foreach ($lib in @('core', 'yaml', 'catalog', 'providers', 'menu', 'execute', 'profiles', 'update')) {
    . (Join-Path $root "lib\$lib.ps1")
}
$global:UwhVersion = 'test'

# Ablage waehrend des Tests in einen eigenen Ordner legen.
$sandkasten = Join-Path $env:TEMP ('uwh-test-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
Set-UwhStateDir $sandkasten

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
    $gesehen = @{}
    foreach ($e in $script:catalog.Entries) {
        if (-not $e.Id) { continue }
        if ($gesehen.ContainsKey($e.Id)) { throw "Kennung '$($e.Id)' kommt zweimal vor" }
        $gesehen[$e.Id] = $true
    }
}

Test-Case 'Skript-Eintraege zeigen auf vorhandene Dateien' {
    foreach ($e in $script:catalog.Entries | Where-Object { $_.Provider -eq 'script' }) {
        $p = Join-Path (Join-Path $root 'scripts') $e.File
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

Test-Case 'Kein Name und keine Beschreibung wird abgeschnitten' {
    foreach ($e in $script:catalog.Entries) {
        if ($e.Name.Length -gt 24) { throw "Name zu lang: '$($e.Name)' ($($e.Name.Length))" }
        if ($e.Description.Length -gt 31) { throw "Beschreibung zu lang bei '$($e.Key)' ($($e.Description.Length))" }
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
    New-Item -ItemType Directory -Path (Join-Path $quelle 'lib') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $quelle 'scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $quelle 'custom\profiles') -Force | Out-Null
    Set-Content (Join-Path $quelle 'VERSION')            '9.9.9'      -Encoding UTF8
    Set-Content (Join-Path $quelle 'uwh.ps1')            'neu'        -Encoding UTF8
    Set-Content (Join-Path $quelle 'lib\core.ps1')        'neu'        -Encoding UTF8
    Set-Content (Join-Path $quelle 'lib\dazu.ps1')        'dazu'       -Encoding UTF8
    Set-Content (Join-Path $quelle 'scripts\a.ps1')       'neu'        -Encoding UTF8
    Set-Content (Join-Path $quelle 'custom\profiles\x.yaml') 'aus-archiv' -Encoding UTF8

    # So sieht die vorhandene Installation aus.
    New-Item -ItemType Directory -Path (Join-Path $ziel 'lib') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ziel 'custom\profiles') -Force | Out-Null
    Set-Content (Join-Path $ziel 'VERSION')                 '0.1.0'  -Encoding UTF8
    Set-Content (Join-Path $ziel 'uwh.ps1')                 'alt'    -Encoding UTF8
    Set-Content (Join-Path $ziel 'lib\core.ps1')             'alt'    -Encoding UTF8
    Set-Content (Join-Path $ziel 'custom\profiles\meins.yaml') 'meins'  -Encoding UTF8

    Copy-UwhTree $quelle $ziel

    Assert-True (-not (Test-Path (Join-Path $ziel 'lib\lib'))) 'kein verschachtelter lib-Ordner'
    Assert-Equal 'neu'   (Get-Content (Join-Path $ziel 'lib\core.ps1') -Raw).Trim()  'Datei ersetzt'
    Assert-Equal 'dazu'  (Get-Content (Join-Path $ziel 'lib\dazu.ps1') -Raw).Trim()  'neue Datei dazugekommen'
    Assert-Equal '9.9.9' (Get-Content (Join-Path $ziel 'VERSION') -Raw).Trim()      'VERSION ersetzt'
    Assert-True (Test-Path (Join-Path $ziel 'scripts\a.ps1')) 'fehlender Ordner angelegt'

    # Das Wichtigste: eigene Profile ueberleben die Aktualisierung.
    Assert-Equal 'meins' (Get-Content (Join-Path $ziel 'custom\profiles\meins.yaml') -Raw).Trim() 'eigenes Profil unberuehrt'
    Assert-True (-not (Test-Path (Join-Path $ziel 'custom\profiles\x.yaml'))) 'custom aus dem Archiv nicht uebernommen'
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

Remove-Item -LiteralPath $sandkasten -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("  {0} bestanden, {1} fehlgeschlagen" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
Write-Host ''
if ($script:Fail -gt 0) { exit 1 }
exit 0
