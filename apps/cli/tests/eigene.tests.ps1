# Prueft eigene Repos: config\repo.yaml lesen, Kataloge zusammenfuehren,
# per git holen und aktualisieren, Zugangsdaten schuetzen.
#
# git laeuft echt, aber gegen ein lokales Repo (file:///) - kein Netz noetig.
# Ohne git werden nur die git-Pruefungen uebersprungen.
#
# Aufruf aus apps\cli:  powershell -ExecutionPolicy Bypass -File tests\eigene.tests.ps1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
foreach ($lib in @('core', 'yaml', 'lang', 'repos', 'catalog', 'providers')) { . (Join-Path $root "classes\$lib.ps1") }
# Die Sprachdateien werden gelesen, bevor uwh in den Sandkasten umzieht.
Set-UwhLanguage 'de'

# uwh wird fuer die ganze Pruefung in einen eigenen Ordner umgeleitet.
$sb = Join-Path $env:TEMP ('uwh-eigene-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $sb 'data') -Force | Out-Null
function Get-UwhRoot { $sb }
$protokoll = Join-Path $sb 'test.log'
Set-UwhLogFile $protokoll

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
function Schreibe {
    param([string]$Relativ, [string[]]$Zeilen)
    $p = Join-Path $sb $Relativ
    New-Item -ItemType Directory -Path (Split-Path -Parent $p) -Force | Out-Null
    Set-Content -LiteralPath $p -Encoding UTF8 -Value $Zeilen
}

# ------------------------------------------------------------------
# Ein kleiner uwh mit eigenem Repo
# ------------------------------------------------------------------

# Wie der echte Katalog: Grundtext Englisch, Uebersetzung mit Kuerzel.
Schreibe 'assets\catalog.yaml' @(
    'categories:'
    '  - Essentials'
    '  - Browsers'
    'scripts:'
    '  7zip:'
    '    name: 7-Zip'
    '    description: Archives'
    '    category: Essentials'
    '    descriptionDE: Archive'
    '    categoryDE: Grundausstattung'
    '    provider: winget'
    '    id: 7zip.7zip'
    '  firefox:'
    '    name: Mozilla Firefox'
    '    description: Web browser'
    '    category: Browsers'
    '    descriptionDE: Webbrowser'
    '    categoryDE: Browser'
    '    provider: winget'
    '    id: Mozilla.Firefox'
    '    idDE: Mozilla.Firefox.de'
)

Schreibe 'data\eigene\config.yaml' @(
    'scripts:'
    '  loxone:'
    '    name: Loxone Config'
    '    description: Ohne Kategorie'
    '    provider: winget'
    '    id: Loxone.LoxoneConfig'
    '  alt:'
    '    name: Alter Eintrag'
    '    description: Deutsche Kategorie von frueher'
    '    category: Grundausstattung'
    '    provider: winget'
    '    id: Alt.Alt'
    '  vivaldi:'
    '    name: Vivaldi'
    '    description: In einer vorhandenen Kategorie'
    '    category: Browser'
    '    provider: winget'
    '    id: Vivaldi.Vivaldi'
    '  firefox:'
    '    name: Firefox (eigene Fassung)'
    '    description: Ersetzt den uwh-Eintrag'
    '    category: Browser'
    '    provider: winget'
    '    id: Mozilla.Firefox.ESR'
    '  hallo:'
    '    name: Hallo'
    '    description: Eigenes Skript'
    '    provider: script'
    '    file: hallo.ps1'
    '    admin: false'
)
Schreibe 'data\eigene\scripts\hallo.ps1' @('param($Action)', 'exit 0')

Schreibe 'data\aus\config.yaml' @(
    'scripts:', '  versteckt:', '    name: X', '    description: X', '    provider: winget', '    id: Nicht.Sichtbar')

Schreibe 'data\kaputt\config.yaml' @('scripts:', "`tfalsch: eingerueckt")

Schreibe 'config\repo.yaml' @(
    'repositories:'
    '  eigene:'
    '    name: Eigene Programme'
    '    nameEN: Own programs'
    '    url: ""'
    '    path: eigene'
    '    enabled:'
    '  aus:'
    '    name: Ausgeschaltet'
    '    path: aus'
    '  kaputt:'
    '    name: Kaputt'
    '    path: kaputt'
    '    enabled:'
    '  boeser-pfad:'
    '    path: ..\ausserhalb'
    '    enabled:'
    '  boese-url:'
    '    url: http://unsicher.example/x.git'
    '    enabled:'
    '  boese-anmeldung:'
    '    auth_method: zauberei'
    '  reserviert:'
    '    path: keys'
    '    enabled:'
)

Write-Host ''
Write-Host 'Schalter wie bei ulh' -ForegroundColor Cyan

Test-Case 'enabled: ohne Wert schaltet an' {
    Assert-True (Test-UwhSchalter ([ordered]@{ enabled = $null }) 'enabled') 'ohne Wert'
    Assert-True (Test-UwhSchalter ([ordered]@{ enabled = $true }) 'enabled') 'true'
}

Test-Case 'enabled: false schaltet ab - keine Falle' {
    foreach ($w in @($false, 'false', 'nein', 'no', 'aus')) {
        if (Test-UwhSchalter ([ordered]@{ enabled = $w }) 'enabled') { throw "'$w' hat angeschaltet" }
    }
}

Test-Case 'Fehlender Schalter ist aus' {
    Assert-True (-not (Test-UwhSchalter ([ordered]@{ name = 'x' }) 'enabled')) 'fehlt'
}

Write-Host ''
Write-Host 'config\repo.yaml' -ForegroundColor Cyan

$info = Get-UwhRepos

Test-Case 'Gueltige Repos werden gelesen' {
    $ids = @($info.Repos | ForEach-Object { $_.Id })
    foreach ($id in @('eigene', 'aus', 'kaputt')) { Assert-True ($ids -contains $id) "Repo '$id'" }
    $e = $info.Repos | Where-Object { $_.Id -eq 'eigene' }
    Assert-True $e.Aktiv 'eigene ist an'
    Assert-Equal (Join-Path (Join-Path $sb 'data') 'eigene') $e.Pfad 'liegt unter data'
}

Test-Case 'Unsichere Eintraege werden abgelehnt, nicht uebernommen' {
    $ids = @($info.Repos | ForEach-Object { $_.Id })
    foreach ($id in @('boeser-pfad', 'boese-url', 'boese-anmeldung', 'reserviert')) {
        Assert-True ($ids -notcontains $id) "'$id' nicht uebernommen"
        Assert-True (@($info.Probleme | Where-Object { $_ -like "*$id*" }).Count -gt 0) "'$id' gemeldet"
    }
}

Test-Case 'Ohne repo.yaml gibt es einfach keine eigenen Repos' {
    $leer = Get-UwhRepos (Join-Path $sb 'gibtsnicht.yaml')
    Assert-Equal 0 @($leer.Repos).Count 'keine Repos'
    Assert-Equal 0 @($leer.Probleme).Count 'kein Fehler'
}

Write-Host ''
Write-Host 'Katalog zusammenfuehren' -ForegroundColor Cyan

$katalog = Get-UwhCatalog

Test-Case 'Eigene Eintraege erscheinen im Katalog' {
    foreach ($k in @('loxone', 'vivaldi', 'hallo')) {
        Assert-True ($null -ne (Get-UwhEntry $katalog $k)) "Eintrag '$k'"
    }
    Assert-True ($null -ne (Get-UwhEntry $katalog '7zip')) 'uwh-Eintraege bleiben'
}

Test-Case 'Ohne Kategorie landet ein Eintrag unter dem Namen des Repos' {
    Assert-Equal 'Eigene Programme' (Get-UwhEntry $katalog 'loxone').Category 'Kategorie'
    Assert-True ($katalog.Categories -contains 'Eigene Programme') 'Kategorie angelegt'
}

Test-Case 'Mit vorhandener Kategorie reiht er sich dort ein - auch mit deutschem Namen' {
    # 'Browser' ist der deutsche Name der Kategorie 'Browsers' von uwh.
    Assert-Equal 'Browsers' (Get-UwhEntry $katalog 'vivaldi').Category 'Kategorie'
    Assert-Equal 'Essentials' (Get-UwhEntry $katalog 'alt').Category 'alte deutsche Kategorie'
    Assert-Equal 1 @($katalog.Categories | Where-Object { $_ -eq 'Browsers' }).Count 'Browsers nur einmal'
    Assert-Equal 0 @($katalog.Categories | Where-Object { $_ -eq 'Browser' -or $_ -eq 'Grundausstattung' }).Count 'keine doppelte Kategorie'
}

Test-Case 'Ersetzt ein eigener Eintrag den einzigen der Kategorie, bleiben ihre Namen' {
    # Die eigene Fassung von firefox nennt die Kategorie nur 'Browser'.
    Assert-Equal 'Browsers' (Get-UwhEntry $katalog 'firefox').Category 'Kennung'
    Assert-Equal 'Browser' (Get-UwhCategoryName $katalog 'Browsers') 'deutscher Name'
    Set-UwhLanguage 'en'
    try {
        Set-UwhCatalogLanguage $katalog
        Assert-Equal 'Browsers' (Get-UwhCategoryName $katalog 'Browsers') 'englischer Name'
    } finally {
        Set-UwhLanguage 'de'
        Set-UwhCatalogLanguage $katalog
    }
}

Test-Case 'Der Name eines Repos darf uebersetzt sein' {
    Set-UwhLanguage 'en'
    try {
        Set-UwhCatalogLanguage $katalog
        Assert-Equal 'Own programs' (Get-UwhCategoryName $katalog 'Eigene Programme') 'Kategorie auf Englisch'
    } finally {
        Set-UwhLanguage 'de'
        Set-UwhCatalogLanguage $katalog
    }
    Assert-Equal 'Eigene Programme' (Get-UwhCategoryName $katalog 'Eigene Programme') 'und auf Deutsch'
}

Test-Case 'Gleicher Name: die eigene Fassung ersetzt die von uwh' {
    $f = Get-UwhEntry $katalog 'firefox'
    Assert-Equal 'Mozilla.Firefox.ESR' $f.Id 'eigene Kennung'
    Assert-Equal 'eigene' $f.Quelle 'Herkunft'
    Assert-Equal 1 @($katalog.Entries | Where-Object { $_.Key -eq 'firefox' }).Count 'nicht doppelt'
    $r = $katalog.Repos | Where-Object { $_.Repo.Id -eq 'eigene' }
    Assert-Equal 1 $r.Ersetzt 'als Ersetzung gezaehlt'
}

Test-Case 'Ausgeschaltete Repos bleiben draussen' {
    Assert-True ($null -eq (Get-UwhEntry $katalog 'versteckt')) 'nicht im Katalog'
}

Test-Case 'Ein kaputtes Repo verdirbt nicht den Rest' {
    Assert-True (@($katalog.Problems | Where-Object { $_ -like 'Kaputt*' }).Count -gt 0) 'gemeldet'
    Assert-True ($null -ne (Get-UwhEntry $katalog '7zip')) 'uwh laeuft weiter'
    Assert-True ($null -ne (Get-UwhEntry $katalog 'loxone')) 'andere Repos laufen weiter'
}

Test-Case 'Skripte eigener Repos liegen im eigenen scripts-Ordner' {
    $h = Get-UwhEntry $katalog 'hallo'
    $pfad = Join-Path (Join-Path $h.BaseDir 'scripts') $h.File
    Assert-True (Test-Path -LiteralPath $pfad) "gefunden unter $pfad"
}

Test-Case 'Ein leeres eigenes Repo ist kein Fehler' {
    Schreibe 'data\leer\config.yaml' @('# noch nichts eingetragen')
    $t = Read-UwhCatalogFile (Join-Path $sb 'data\leer\config.yaml') 'leer' 'Leer'
    Assert-Equal 0 @($t.Entries).Count 'keine Eintraege'
    Assert-Equal 0 @($t.Problems).Count 'kein Problem'
}

Test-Case 'Erster Start legt Vorlagen an, ueberschreibt aber nichts' {
    foreach ($n in @('config\repo.yaml.example', 'config\settings.yaml.example', 'templates\eigene.yaml', 'templates\beispiel-profil.yaml')) {
        $z = Join-Path $sb $n
        New-Item -ItemType Directory -Path (Split-Path -Parent $z) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root $n) -Destination $z
    }
    $vorher = Get-Content -LiteralPath (Join-Path $sb 'config\repo.yaml') -Raw

    Initialize-UwhEigenes

    Assert-Equal $vorher (Get-Content -LiteralPath (Join-Path $sb 'config\repo.yaml') -Raw) 'repo.yaml unberuehrt'
    Assert-True ((Get-Content (Join-Path $sb 'data\eigene\config.yaml') -Raw) -like '*Loxone*') 'eigene Programme unberuehrt'
    Assert-True (Test-Path (Join-Path $sb 'data\profiles\beispiel.yaml')) 'Beispielprofil angelegt'
    Assert-True (Test-Path (Join-Path $sb 'config\settings.yaml')) 'Einstellungen angelegt'

    # Wer das Beispielprofil loescht, will es nicht zurueck.
    Remove-Item -LiteralPath (Join-Path $sb 'data\profiles\beispiel.yaml')
    Initialize-UwhEigenes
    Assert-True (-not (Test-Path (Join-Path $sb 'data\profiles\beispiel.yaml'))) 'bleibt geloescht'
}

Test-Case 'Nur das erste Holen wird wiederholt - Aktualisieren kostet ohne Netz keine Wartezeit' {
    $script:GitAufrufe = 0
    function Get-UwhGit { 'git.exe' }
    function Invoke-UwhGit { param($Repo, $Argumente) $script:GitAufrufe++; [pscustomobject]@{ Code = 1; Output = '' } }
    function Start-Sleep { param([int]$Seconds) }
    $repo = [pscustomobject]@{ Name = 'Test'; Url = 'https://example.com/x.git'; Pfad = Join-Path $sb 'data\x' }
    $einst = [pscustomobject]@{ BeimStart = $true; Versuche = 3; Pause = 5 }

    [void](Invoke-UwhRepoMitWiederholung $repo 'pull' $einst $true)
    Assert-Equal 1 $script:GitAufrufe 'Aktualisieren: ein Versuch'

    $script:GitAufrufe = 0
    [void](Invoke-UwhRepoMitWiederholung $repo 'clone' $einst $true)
    Assert-Equal 3 $script:GitAufrufe 'Holen: drei Versuche'
}

Write-Host ''
Write-Host 'Zugangsdaten' -ForegroundColor Cyan

Test-Case 'Adressen mit Kennwort werden im Protokoll geschwaerzt' {
    [void](Invoke-UwhExe (Join-Path $env:SystemRoot 'System32\cmd.exe') @('/c', 'rem', 'https://thomas:Hu7xQz@git.example/a.git'))
    $text = Get-Content -LiteralPath $protokoll -Raw
    Assert-True ($text -notlike '*Hu7xQz*') 'Kennwort nicht im Protokoll'
    Assert-True ($text -like '*https://***@git.example*') 'geschwaerzt statt entfernt'
}

Test-Case '${NAME} wird aus der Umgebung geholt' {
    $env:UWH_TEST_GEHEIM = 'aus-der-umgebung'
    try {
        Assert-Equal 'x-aus-der-umgebung-y' (Expand-UwhVariable 'x-${UWH_TEST_GEHEIM}-y') 'ersetzt'
        Assert-Equal 'x--y' (Expand-UwhVariable 'x-${UWH_GIBTS_NICHT}-y') 'unbekannt wird leer'
    } finally {
        Remove-Item Env:\UWH_TEST_GEHEIM -ErrorAction SilentlyContinue
    }
}

$git = Get-UwhGit
if (-not $git) {
    Write-Host ''
    Write-Host '  git fehlt - die git-Pruefungen werden uebersprungen.' -ForegroundColor DarkYellow
} else {
    Write-Host ''
    Write-Host 'git' -ForegroundColor Cyan

    function Git { param([string[]]$A) & $git @A 2>&1 | Out-Null; if ($LASTEXITCODE) { throw "git $($A -join ' ') -> $LASTEXITCODE" } }
    $ich = @('-c', 'user.name=uwh-test', '-c', 'user.email=test@uwh.invalid')

    # Quelle: ein normales Repo, daraus ein blankes als "Server".
    $arbeit = Join-Path $sb 'arbeit'
    $server = Join-Path $sb 'server.git'
    Git @('init', '--quiet', $arbeit)
    Set-Content -LiteralPath (Join-Path $arbeit 'config.yaml') -Encoding UTF8 -Value @(
        'scripts:', '  eins:', '    name: Eins', '    description: Aus git', '    provider: winget', '    id: Eins.Eins')
    Git @('-C', $arbeit, 'add', '.')
    Git (@('-C', $arbeit) + $ich + @('commit', '--quiet', '-m', 'eins'))
    Git @('clone', '--quiet', '--bare', $arbeit, $server)
    Git @('-C', $arbeit, 'remote', 'add', 'origin', $server)
    $url = ([uri]$server).AbsoluteUri

    Schreibe 'config\repo.yaml' @(
        'repositories:'
        '  fern:'
        '    name: Fern'
        "    url: $url"
        '    path: fern'
        '    enabled:'
        '    auto_update:'
        '  nur-an:'
        '    name: Nur an'
        "    url: $url"
        '    path: nur-an'
        '    enabled:'
        '  nur-aus:'
        '    name: Nie geholt'
        "    url: $url"
        '    path: nur-aus'
        'update_settings:'
        '  retry_on_failure: 1'
        '  retry_delay_seconds: 0'
    )

    Sync-UwhRepos -Quiet

    Test-Case 'Aktives Repo mit Adresse wird geholt' {
        Assert-True (Test-Path (Join-Path $sb 'data\fern\config.yaml')) 'fern geholt'
        Assert-True (Test-Path (Join-Path $sb 'data\nur-an\config.yaml')) 'nur-an geholt'
        Assert-True ($null -ne (Get-UwhEntry (Get-UwhCatalog) 'eins')) 'Eintrag im Katalog'
    }

    Test-Case 'Ohne enabled wird nichts geholt' {
        Assert-True (-not (Test-Path (Join-Path $sb 'data\nur-aus'))) 'nicht geholt'
    }

    # Neuer Stand auf dem "Server".
    Add-Content -LiteralPath (Join-Path $arbeit 'config.yaml') -Encoding UTF8 -Value @(
        '  zwei:', '    name: Zwei', '    description: Nachgeschoben', '    provider: winget', '    id: Zwei.Zwei')
    Git (@('-C', $arbeit) + $ich + @('commit', '--quiet', '-am', 'zwei'))
    Git @('-C', $arbeit, 'push', '--quiet', 'origin', 'HEAD')

    Sync-UwhRepos -Quiet

    Test-Case 'Mit auto_update wird beim Start aktualisiert' {
        $text = Get-Content (Join-Path $sb 'data\fern\config.yaml') -Raw
        Assert-True ($text -like '*Zwei*') 'neuer Stand da'
    }

    Test-Case 'Ohne auto_update bleibt der alte Stand' {
        $text = Get-Content (Join-Path $sb 'data\nur-an\config.yaml') -Raw
        Assert-True ($text -notlike '*Zwei*') 'alter Stand'
    }

    Test-Case 'Zugangsdaten landen weder im Protokoll noch in .git/config' {
        $token = 'GeheimesToken' + [guid]::NewGuid().ToString('N').Substring(0, 6)
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${token}:"))
        $repo = [pscustomobject]@{
            Id = 'geheim'; Name = 'Geheim'; Url = $url; Ordner = 'geheim'
            Pfad = Join-Path $sb 'data\geheim'; Auth = 'https_token'
            SshKey = ''; Token = $token; Benutzer = ''; Kennwort = ''; Aktiv = $true; AutoUpdate = $false
        }
        $r = Invoke-UwhGit $repo @('clone', '--quiet', $url, $repo.Pfad)
        Assert-Equal 0 $r.Code 'geholt'

        $log = Get-Content -LiteralPath $protokoll -Raw
        Assert-True ($log -notlike "*$token*") 'Token nicht im Protokoll'
        Assert-True ($log -notlike "*$b64*")   'auch nicht verschluesselt'

        $cfg = Get-Content -LiteralPath (Join-Path $repo.Pfad '.git\config') -Raw
        Assert-True ($cfg -notlike "*$token*") 'Token nicht in .git/config'
    }

    Test-Case 'Nach dem git-Aufruf ist die Umgebung wie vorher' {
        # Manche Umgebungen setzen GIT_TERMINAL_PROMPT schon selbst - fuer die
        # Pruefung muss es vorher weg sein, danach kommt es zurueck.
        $gitPrompt = $env:GIT_TERMINAL_PROMPT
        Remove-Item Env:\GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
        $env:GIT_CONFIG_COUNT = 'vorher'
        try {
            $repo = [pscustomobject]@{
                Id = 'x'; Name = 'X'; Url = $url; Ordner = 'x'; Pfad = Join-Path $sb 'data\x'
                Auth = 'https_basic'; SshKey = ''; Token = ''; Benutzer = 'nutzer'; Kennwort = 'Kw7x'
                Aktiv = $true; AutoUpdate = $false
            }
            [void](Invoke-UwhGit $repo @('--version'))
            Assert-Equal 'vorher' $env:GIT_CONFIG_COUNT 'alter Wert zurueck'
            Assert-True ($null -eq $env:GIT_CONFIG_VALUE_0) 'kein Kopf liegen geblieben'
            Assert-True ($null -eq $env:GIT_TERMINAL_PROMPT) 'keine Einstellung liegen geblieben'
        } finally {
            Remove-Item Env:\GIT_CONFIG_COUNT -ErrorAction SilentlyContinue
            if ($null -ne $gitPrompt) { $env:GIT_TERMINAL_PROMPT = $gitPrompt }
        }
    }
}

# ------------------------------------------------------------------

Remove-Item -LiteralPath $sb -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("  {0} bestanden, {1} fehlgeschlagen" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
Write-Host ''
if ($script:Fail -gt 0) { exit 1 }
exit 0
