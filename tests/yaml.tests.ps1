# Pruefung des YAML-Lesers und -Schreibers.
# Aufruf:  powershell -ExecutionPolicy Bypass -File tests\yaml.tests.ps1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\yaml.ps1')

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
    if ($Expected -ne $Actual) {
        throw ("{0}: erwartet '{1}', erhalten '{2}'" -f $What, $Expected, $Actual)
    }
}

function Assert-True {
    param($Condition, [string]$What = 'Bedingung')
    if (-not $Condition) { throw "$What war nicht erfuellt" }
}

Write-Host ''
Write-Host 'YAML' -ForegroundColor Cyan

Test-Case 'Einfache Zuordnung' {
    $d = ConvertFrom-UwhYaml "name: uwh`nversion: 1"
    Assert-Equal 'uwh' $d.name 'name'
    Assert-Equal 1 $d.version 'version'
}

Test-Case 'Verschachtelte Zuordnung' {
    $d = ConvertFrom-UwhYaml "a:`n  b:`n    c: tief"
    Assert-Equal 'tief' $d.a.b.c 'a.b.c'
}

Test-Case 'Liste eingerueckt' {
    $d = ConvertFrom-UwhYaml "werte:`n  - eins`n  - zwei"
    Assert-Equal 2 $d.werte.Count 'Anzahl'
    Assert-Equal 'zwei' $d.werte[1] 'zweiter Wert'
}

Test-Case 'Liste auf gleicher Ebene wie Schluessel' {
    $d = ConvertFrom-UwhYaml "werte:`n- eins`n- zwei`nnach: da"
    Assert-Equal 2 $d.werte.Count 'Anzahl'
    Assert-Equal 'da' $d.nach 'Folgeschluessel'
}

Test-Case 'Liste aus Zuordnungen' {
    $y = @(
        'actions:'
        '  - name: install'
        '    beschreibung: Installieren'
        '  - name: uninstall'
        '    beschreibung: Entfernen'
    ) -join "`n"
    $d = ConvertFrom-UwhYaml $y
    Assert-Equal 2 $d.actions.Count 'Anzahl'
    Assert-Equal 'install' $d.actions[0].name 'erste Aktion'
    Assert-Equal 'Entfernen' $d.actions[1].beschreibung 'zweite Beschreibung'
}

Test-Case 'Tief verschachtelt wie im Katalog' {
    $y = @(
        'scripts:'
        '  vscode:'
        '    description: Code-Editor'
        '    provider: winget'
        '    actions:'
        '    - name: install'
        '      prompts:'
        '      - question: Pfad?'
        '        variable: ZIEL'
        '        default: C:\Tools'
    ) -join "`n"
    $d = ConvertFrom-UwhYaml $y
    Assert-Equal 'winget' $d.scripts.vscode.provider 'provider'
    Assert-Equal 'ZIEL' $d.scripts.vscode.actions[0].prompts[0].variable 'variable'
    Assert-Equal 'C:\Tools' $d.scripts.vscode.actions[0].prompts[0].default 'default'
}

Test-Case 'Kommentare und Leerzeilen' {
    $y = @(
        '# Kopfzeile'
        ''
        'a: 1   # hinten dran'
        'b: "wert # kein Kommentar"'
    ) -join "`n"
    $d = ConvertFrom-UwhYaml $y
    Assert-Equal 1 $d.a 'a'
    Assert-Equal 'wert # kein Kommentar' $d.b 'b'
}

Test-Case 'Datentypen' {
    $y = @(
        'text: hallo'
        'zahl: 42'
        'komma: 1.5'
        'ja: true'
        'nein: false'
        'leer:'
        'quoted: "no"'
        'pfad: C:\Programme\Test'
    ) -join "`n"
    $d = ConvertFrom-UwhYaml $y
    Assert-True ($d.text -is [string]) 'text ist Text'
    Assert-True ($d.zahl -is [int]) 'zahl ist Zahl'
    Assert-True ($d.komma -is [double]) 'komma ist Kommazahl'
    Assert-True ($d.ja -is [bool] -and $d.ja) 'ja ist wahr'
    Assert-True ($d.nein -is [bool] -and -not $d.nein) 'nein ist falsch'
    Assert-True ($null -eq $d.leer) 'leer ist leer'
    Assert-Equal 'no' $d.quoted 'quoted bleibt Text'
    Assert-Equal 'C:\Programme\Test' $d.pfad 'Pfad'
}

Test-Case 'Einzeiler-Liste' {
    $d = ConvertFrom-UwhYaml 'actions: [install, update, uninstall]'
    Assert-Equal 3 $d.actions.Count 'Anzahl'
    Assert-Equal 'update' $d.actions[1] 'zweiter Wert'
}

Test-Case 'Leere Liste und leere Zuordnung' {
    $d = ConvertFrom-UwhYaml "a: []`nb: {}"
    Assert-Equal 0 $d.a.Count 'leere Liste'
    Assert-Equal 0 $d.b.Count 'leere Zuordnung'
}

Test-Case 'Tabulator wird abgelehnt' {
    $fehler = $false
    try { ConvertFrom-UwhYaml "a:`n`tb: 1" } catch { $fehler = $true }
    Assert-True $fehler 'Tabulator meldet Fehler'
}

Test-Case 'Schreiben und wieder lesen' {
    $daten = [ordered]@{
        name   = 'Arbeitsplatz'
        select = @('git', 'vscode')
        options = [ordered]@{
            unattended = $true
            reboot     = 'auto'
        }
    }
    $yaml = ConvertTo-UwhYaml $daten
    $zurueck = ConvertFrom-UwhYaml $yaml
    Assert-Equal 'Arbeitsplatz' $zurueck.name 'name'
    Assert-Equal 2 $zurueck.select.Count 'Anzahl Auswahl'
    Assert-Equal 'vscode' $zurueck.select[1] 'zweiter Eintrag'
    Assert-True ($zurueck.options.unattended -eq $true) 'unattended'
    Assert-Equal 'auto' $zurueck.options.reboot 'reboot'
}

Test-Case 'Schreiben: Liste aus Zuordnungen' {
    $daten = [ordered]@{
        select = @(
            [ordered]@{ key = 'git'; answers = [ordered]@{ GIT_USER = 'Thomas' } }
            [ordered]@{ key = 'vscode' }
        )
    }
    $zurueck = ConvertFrom-UwhYaml (ConvertTo-UwhYaml $daten)
    Assert-Equal 2 $zurueck.select.Count 'Anzahl'
    Assert-Equal 'git' $zurueck.select[0].key 'erster Schluessel'
    Assert-Equal 'Thomas' $zurueck.select[0].answers.GIT_USER 'Antwort'
    Assert-Equal 'vscode' $zurueck.select[1].key 'zweiter Schluessel'
}

Test-Case 'Schreiben: Sonderzeichen werden geschuetzt' {
    $daten = [ordered]@{ text = 'mit: Doppelpunkt'; leer = ''; pfad = 'C:\Ein Pfad' }
    $zurueck = ConvertFrom-UwhYaml (ConvertTo-UwhYaml $daten)
    Assert-Equal 'mit: Doppelpunkt' $zurueck.text 'Doppelpunkt'
    Assert-Equal '' $zurueck.leer 'leerer Text'
    Assert-Equal 'C:\Ein Pfad' $zurueck.pfad 'Pfad mit Leerzeichen'
}

Write-Host ''
Write-Host ("  {0} bestanden, {1} fehlgeschlagen" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
Write-Host ''

if ($script:Fail -gt 0) { exit 1 }
exit 0
