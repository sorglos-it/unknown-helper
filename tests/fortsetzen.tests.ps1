# Prueft eigene Skripte und die Fortsetzung nach einem Neustart.
# Es wird nichts installiert und nichts neu gestartet - der Neustart wird
# durch eine Attrappe ersetzt, alles davor und danach laeuft echt.
#
# Aufruf:  powershell -ExecutionPolicy Bypass -File tests\fortsetzen.tests.ps1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
foreach ($lib in @('core', 'yaml', 'catalog', 'providers', 'menu', 'execute', 'profiles', 'update')) {
    . (Join-Path $root "lib\$lib.ps1")
}
$global:UwhVersion = 'test'

$sandkasten = Join-Path $env:TEMP ('uwh-fort-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $sandkasten 'scripts') -Force | Out-Null
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

# ------------------------------------------------------------------
# Ein eigener kleiner Katalog mit echten Skripten
# ------------------------------------------------------------------

$spurDatei = Join-Path $sandkasten 'spur.txt'

# Schreibt seinen Namen, die Aktion und eine Antwort in die Spurdatei.
@'
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Action)
Add-Content -LiteralPath $env:UWH_SPUR -Value ("{0}|{1}|{2}" -f $env:UWH_NAME, $Action, $env:ANTWORT)
exit 0
'@ | Set-Content -LiteralPath (Join-Path $sandkasten 'scripts\spur.ps1') -Encoding UTF8

# Verlangt einen Neustart.
@'
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Action)
Add-Content -LiteralPath $env:UWH_SPUR -Value "neustarter|$Action|"
exit 3010
'@ | Set-Content -LiteralPath (Join-Path $sandkasten 'scripts\neustarter.ps1') -Encoding UTF8

# Endet mit einem Fehlercode, ohne etwas zu melden.
@'
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Action)
exit 5
'@ | Set-Content -LiteralPath (Join-Path $sandkasten 'scripts\kaputt.ps1') -Encoding UTF8

# Bricht mit einer eigenen Meldung ab.
@'
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Action)
$ErrorActionPreference = 'Stop'
Write-Error 'Da fehlt die Freigabe'
'@ | Set-Content -LiteralPath (Join-Path $sandkasten 'scripts\meckert.ps1') -Encoding UTF8

@'
categories:
  - Test
scripts:
  eins:
    name: Eins
    description: Erster Schritt
    category: Test
    provider: script
    file: spur.ps1
    admin: false
    actions:
      - name: install
        prompts:
          - question: Antwort?
            variable: ANTWORT
            type: text
            default: standardwert
  zwei:
    name: Zwei
    description: Zweiter Schritt
    category: Test
    provider: script
    file: spur.ps1
    admin: false
  drei:
    name: Drei
    description: Dritter Schritt
    category: Test
    provider: script
    file: spur.ps1
    admin: false
  neustarter:
    name: Neustarter
    description: Verlangt einen Neustart
    category: Test
    provider: script
    file: neustarter.ps1
    admin: false
  kaputt:
    name: Kaputt
    description: Geht schief
    category: Test
    provider: script
    file: kaputt.ps1
    admin: false
  meckert:
    name: Meckert
    description: Bricht mit Meldung ab
    category: Test
    provider: script
    file: meckert.ps1
    admin: false
'@ | Set-Content -LiteralPath (Join-Path $sandkasten 'config.yaml') -Encoding UTF8

$env:UWH_SPUR = $spurDatei
$katalog = Get-UwhCatalog (Join-Path $sandkasten 'config.yaml')

function Neue-Spur { Set-Content -LiteralPath $spurDatei -Value '' -Encoding UTF8 }
function Lies-Spur {
    if (-not (Test-Path $spurDatei)) { return @() }
    @(Get-Content -LiteralPath $spurDatei | Where-Object { $_.Trim() })
}
function Neuer-Plan {
    param([string[]]$Schluessel, [string]$Reboot = 'never')
    $auswahl = $Schluessel | ForEach-Object {
        [pscustomobject]@{ Key = $_; Action = 'install'; Answers = @{} }
    }
    New-UwhPlan $katalog $auswahl -Unattended $true -RebootPolicy $Reboot
}

Write-Host ''
Write-Host 'Eigene Skripte und Fortsetzung' -ForegroundColor Cyan

# ------------------------------------------------------------------
# provider: script
# ------------------------------------------------------------------

Test-Case 'Eigenes Skript laeuft und bekommt die Aktion' {
    Neue-Spur
    $env:UWH_NAME = 'eins'
    $plan = Neuer-Plan @('eins')
    Invoke-UwhCollect $katalog $plan
    [void](Invoke-UwhPlan $katalog $plan)

    $spur = @(Lies-Spur)
    Assert-Equal 1 $spur.Count 'eine Zeile geschrieben'
    Assert-True ($spur[0] -like '*|install|*') 'Aktion angekommen'
    Assert-Equal 'ok' $plan.Items[0].Status 'Status'
}

Test-Case 'Antworten kommen als Umgebungsvariable an' {
    Neue-Spur
    $env:UWH_NAME = 'eins'
    $plan = Neuer-Plan @('eins')
    Invoke-UwhCollect $katalog $plan       # nimmt den Vorgabewert
    [void](Invoke-UwhPlan $katalog $plan)

    Assert-True (@(Lies-Spur)[0] -like '*|standardwert') 'Vorgabewert im Skript'
}

Test-Case 'Umgebung wird nach dem Skript wiederhergestellt' {
    $env:ANTWORT = 'vorher'
    $plan = Neuer-Plan @('eins')
    Invoke-UwhCollect $katalog $plan
    [void](Invoke-UwhPlan $katalog $plan)
    Assert-Equal 'vorher' $env:ANTWORT 'alter Wert wieder da'
    Remove-Item Env:\ANTWORT -ErrorAction SilentlyContinue
}

Test-Case 'Rueckgabe 5 ist ein Fehler' {
    $plan = Neuer-Plan @('kaputt')
    [void](Invoke-UwhPlan $katalog $plan)
    Assert-Equal 'fehler' $plan.Items[0].Status 'Status'
    Assert-True ($plan.Items[0].Message -like '*5*') 'Code in der Meldung'
}

Test-Case 'Meldung des Skripts landet im Ergebnis' {
    $plan = Neuer-Plan @('meckert')
    [void](Invoke-UwhPlan $katalog $plan)
    Assert-Equal 'fehler' $plan.Items[0].Status 'Status'
    Assert-True ($plan.Items[0].Message -like '*Freigabe*') 'eigener Text uebernommen'
}

Test-Case 'Ein Skript kann uwh nicht uebernehmen' {
    # Laeuft das Skript im selben Prozess, wuerde es Get-UwhRoot ersetzen.
    $angriff = Join-Path $sandkasten 'scripts\angriff.ps1'
    Set-Content -LiteralPath $angriff -Encoding UTF8 -Value @(
        '[CmdletBinding()]'
        'param([Parameter(Mandatory)][string]$Action)'
        'function global:Get-UwhRoot { return "GEKAPERT" }'
        '$global:UwhVersion = "GEKAPERT"'
        'exit 0'
    )
    $datei = Join-Path $sandkasten 'angriff.yaml'
    Set-Content -LiteralPath $datei -Encoding UTF8 -Value @(
        'categories:'
        '  - Test'
        'scripts:'
        '  angriff:'
        '    name: Angriff'
        '    description: Test'
        '    category: Test'
        '    provider: script'
        '    file: angriff.ps1'
        '    admin: false'
    )
    $c = Get-UwhCatalog $datei
    $plan = New-UwhPlan $c @([pscustomobject]@{ Key='angriff'; Action='install'; Answers=@{} }) -Unattended $true
    [void](Invoke-UwhPlan $c $plan)

    Assert-Equal 'ok' $plan.Items[0].Status 'Skript lief'
    Assert-True ((Get-UwhRoot) -ne 'GEKAPERT') 'Get-UwhRoot unveraendert'
    Assert-True ($global:UwhVersion -ne 'GEKAPERT') 'Version unveraendert'
}

Test-Case 'Rueckgabe 3010 meldet Neustartbedarf' {
    Neue-Spur
    $plan = Neuer-Plan @('neustarter') 'never'
    [void](Invoke-UwhPlan $katalog $plan)
    Assert-Equal 'ok' $plan.Items[0].Status 'Status'
    Assert-True ($plan.Items[0].Message -like '*Neustart*') 'Neustart gemeldet'
}

# ------------------------------------------------------------------
# Neustart-Entscheidung, ohne wirklich neu zu starten
# ------------------------------------------------------------------

$script:Neustarts = 0
$script:Aufgaben = 0
function Restart-Computer { param([switch]$Force) $script:Neustarts++ }
function Register-UwhResume { param([string]$Id) $script:Aufgaben++; return $true }
function Start-Sleep { param([int]$Seconds) }

Test-Case 'reboot never startet nicht neu und laeuft weiter' {
    Neue-Spur
    $script:Neustarts = 0
    $env:UWH_NAME = 'x'
    $plan = Neuer-Plan @('neustarter', 'eins') 'never'
    [void](Invoke-UwhPlan $katalog $plan)

    Assert-Equal 0 $script:Neustarts 'kein Neustart'
    Assert-Equal 2 $plan.Index 'beide Schritte erledigt'
    Assert-Equal 2 @(Lies-Spur).Count 'beide Skripte gelaufen'
}

Test-Case 'reboot auto startet neu und legt die Aufgabe an' {
    Neue-Spur
    $script:Neustarts = 0
    $script:Aufgaben = 0
    $plan = Neuer-Plan @('neustarter', 'eins') 'auto'
    [void](Invoke-UwhPlan $katalog $plan)

    Assert-Equal 1 $script:Neustarts 'genau ein Neustart'
    Assert-Equal 1 $script:Aufgaben 'Aufgabe fuer die Anmeldung angelegt'
    Assert-Equal 1 $plan.Index 'Zeiger steht auf dem naechsten Schritt'
    Assert-Equal 1 @(Lies-Spur).Count 'zweites Skript noch nicht gelaufen'
}

# ------------------------------------------------------------------
# Fortsetzung: genau das, was nach dem Neustart passiert
# ------------------------------------------------------------------

Test-Case 'Nach dem Neustart wird genau dort weitergemacht' {
    Neue-Spur
    $env:UWH_NAME = 'y'

    # Lauf 1: bis zum Neustart.
    $plan = Neuer-Plan @('neustarter', 'eins', 'zwei') 'auto'
    [void](Invoke-UwhPlan $katalog $plan)
    Assert-Equal 1 @(Lies-Spur).Count 'nur der erste Schritt lief'
    $id = $plan.Id

    # Lauf 2: so, wie uwh nach dem Neustart startet - frisch von der Platte.
    $weiter = Import-UwhState $id
    Assert-True ($null -ne $weiter) 'Zwischenstand gefunden'
    Assert-Equal 1 $weiter.Index 'setzt bei Schritt 2 an'
    [void](Invoke-UwhPlan $katalog $weiter)

    $spur = @(Lies-Spur)
    Assert-Equal 3 $spur.Count 'jetzt sind alle drei durch'
    Assert-True ($spur[1] -like 'y|install|*') 'Schritt 2 lief'
    Assert-True ($spur[2] -like 'y|install|*') 'Schritt 3 lief'
    Assert-Equal 3 $weiter.Index 'Zeiger am Ende'
    Remove-UwhState $id
}

Test-Case 'Ein Schritt wird nach dem Neustart nicht doppelt ausgefuehrt' {
    Neue-Spur
    $env:UWH_NAME = 'z'

    $plan = Neuer-Plan @('eins', 'zwei', 'drei') 'never'
    [void](Invoke-UwhPlan $katalog $plan)
    Assert-Equal 3 @(Lies-Spur).Count 'drei Durchlaeufe'

    # Fertigen Stand erneut laden und laufen lassen: darf nichts mehr tun.
    Save-UwhState $plan
    $nochmal = Import-UwhState $plan.Id
    [void](Invoke-UwhPlan $katalog $nochmal)
    Assert-Equal 3 @(Lies-Spur).Count 'kein Schritt wurde wiederholt'
    Remove-UwhState $plan.Id
}

Test-Case 'Antworten ueberstehen den Neustart' {
    Neue-Spur
    $env:UWH_NAME = 'a'

    $auswahl = @([pscustomobject]@{ Key = 'eins'; Action = 'install'; Answers = @{ ANTWORT = 'gemerkt' } },
                 [pscustomobject]@{ Key = 'zwei'; Action = 'install'; Answers = @{} })
    $plan = New-UwhPlan $katalog $auswahl -Unattended $true -RebootPolicy 'never'
    Invoke-UwhCollect $katalog $plan
    Save-UwhState $plan

    # Frisch von der Platte - wie nach dem Neustart.
    $weiter = Import-UwhState $plan.Id
    [void](Invoke-UwhPlan $katalog $weiter)

    Assert-True (@(Lies-Spur)[0] -like '*|gemerkt') 'Antwort war noch da'
    Remove-UwhState $plan.Id
}

# ------------------------------------------------------------------
# Katalogpruefung fuer Direkt-Downloads
# ------------------------------------------------------------------

Test-Case 'Download ohne https wird abgelehnt' {
    $datei = Join-Path $sandkasten 'http.yaml'
    @'
categories:
  - Test
scripts:
  unsicher:
    name: Unsicher
    description: Test
    category: Test
    provider: url
    url: http://example.com/setup.exe
'@ | Set-Content -LiteralPath $datei -Encoding UTF8

    $c = Get-UwhCatalog $datei
    Assert-Equal 0 $c.Entries.Count 'Eintrag verworfen'
    Assert-True ($c.Problems[0] -like '*https*') 'Grund genannt'
}

Test-Case 'Skriptname mit Pfadwechsel wird abgelehnt' {
    $datei = Join-Path $sandkasten 'pfad.yaml'
    @'
categories:
  - Test
scripts:
  boese:
    name: Boese
    description: Test
    category: Test
    provider: script
    file: ..\..\windows\system32\calc.exe
'@ | Set-Content -LiteralPath $datei -Encoding UTF8

    $c = Get-UwhCatalog $datei
    Assert-Equal 0 $c.Entries.Count 'Eintrag verworfen'
}

# ------------------------------------------------------------------

Remove-Item Env:\UWH_SPUR -ErrorAction SilentlyContinue
Remove-Item Env:\UWH_NAME -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $sandkasten -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("  {0} bestanden, {1} fehlgeschlagen" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
Write-Host ''
if ($script:Fail -gt 0) { exit 1 }
exit 0
