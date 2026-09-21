# Prueft die Provider fuer Windows-Funktionen, optionale Komponenten und
# PowerShell-Module.
#
# Diese drei Wege laufen sonst nur mit Administratorrechten und veraendern
# dabei das System. Hier werden die Windows-Befehle durch Attrappen ersetzt:
# geprueft wird die Entscheidung von uwh, nicht Windows selbst.
#
# Aufruf:  powershell -ExecutionPolicy Bypass -File tests\provider.tests.ps1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
foreach ($lib in @('core', 'yaml', 'repos', 'catalog', 'providers')) { . (Join-Path $root "lib\$lib.ps1") }
Set-UwhLogFile (Join-Path $env:TEMP 'uwh-provider.log')

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

function Neuer-Eintrag {
    param([string]$Provider, [string]$Id, [string]$Scope = 'machine')
    [pscustomobject]@{
        Key = 'test'; Name = 'Test'; Description = ''; Category = ''
        Provider = $Provider; Id = $Id; Scope = $Scope
        Url = ''; Sha256 = ''; SilentArgs = ''; File = ''; BaseDir = $root
        Actions = @(); Admin = $true; Reboot = ''; Recommended = $false; Note = ''
    }
}

# Was die Attrappen zurueckgeben und womit sie aufgerufen wurden.
$script:Lage = @{}
$script:Protokoll = New-Object System.Collections.Generic.List[string]

# ------------------------------------------------------------------
# Attrappen der Windows-Befehle
# ------------------------------------------------------------------

function Get-WindowsOptionalFeature {
    param([switch]$Online, [string]$FeatureName, $ErrorAction)
    $script:Protokoll.Add("get-feature:$FeatureName")
    if ($script:Lage['wirft']) { throw 'Die Funktion ist unbekannt.' }
    [pscustomobject]@{ State = $script:Lage['state'] }
}
function Enable-WindowsOptionalFeature {
    param([switch]$Online, [string]$FeatureName, [switch]$All, [switch]$NoRestart, $ErrorAction)
    $script:Protokoll.Add("enable-feature:$FeatureName")
    [pscustomobject]@{ RestartNeeded = [bool]$script:Lage['restart'] }
}
function Disable-WindowsOptionalFeature {
    param([switch]$Online, [string]$FeatureName, [switch]$NoRestart, $ErrorAction)
    $script:Protokoll.Add("disable-feature:$FeatureName")
    [pscustomobject]@{ RestartNeeded = [bool]$script:Lage['restart'] }
}
function Get-WindowsCapability {
    param([switch]$Online, [string]$Name, $ErrorAction)
    $script:Protokoll.Add("get-capability:$Name")
    if ($script:Lage['wirft']) { throw 'Die Komponente ist unbekannt.' }
    [pscustomobject]@{ State = $script:Lage['state'] }
}
function Add-WindowsCapability {
    param([switch]$Online, [string]$Name, $ErrorAction)
    $script:Protokoll.Add("add-capability:$Name")
    [pscustomobject]@{ RestartNeeded = [bool]$script:Lage['restart'] }
}
function Remove-WindowsCapability {
    param([switch]$Online, [string]$Name, $ErrorAction)
    $script:Protokoll.Add("remove-capability:$Name")
    [pscustomobject]@{ RestartNeeded = [bool]$script:Lage['restart'] }
}
function Get-PackageProvider {
    param([string]$Name, $ErrorAction)
    [pscustomobject]@{ Name = 'NuGet' }
}
function Get-Module {
    param([switch]$ListAvailable, [string]$Name, $ErrorAction)
    $script:Protokoll.Add("get-module:$Name")
    if ($script:Lage['vorhanden']) { return [pscustomobject]@{ Name = $Name } }
    return $null
}
function Install-Module {
    param([string]$Name, [string]$Scope, [switch]$Force, [switch]$AcceptLicense,
          [switch]$AllowClobber, $ErrorAction)
    # ${Name} noetig: ohne Klammern liest PowerShell '$Name:' als Laufwerk.
    $script:Protokoll.Add("install-module:${Name}:$Scope")
    if ($script:Lage['wirft']) { throw 'Das Modul wurde in der Quelle nicht gefunden.' }
}
function Update-Module {
    param([string]$Name, [switch]$Force, $ErrorAction)
    $script:Protokoll.Add("update-module:$Name")
}
function Uninstall-Module {
    param([string]$Name, [switch]$AllVersions, [switch]$Force, $ErrorAction)
    $script:Protokoll.Add("uninstall-module:$Name")
}

function Setze-Lage {
    param([hashtable]$Werte = @{})
    $script:Lage = @{ state = 'Disabled'; restart = $false; wirft = $false; vorhanden = $false }
    foreach ($k in $Werte.Keys) { $script:Lage[$k] = $Werte[$k] }
    $script:Protokoll.Clear()
}

# ------------------------------------------------------------------

Write-Host ''
Write-Host 'Windows-Funktionen' -ForegroundColor Cyan

Test-Case 'Ist die Funktion schon an, passiert nichts' {
    Setze-Lage @{ state = 'Enabled' }
    $r = Invoke-UwhFeature (Neuer-Eintrag 'feature' 'Microsoft-Windows-Subsystem-Linux') 'install'
    Assert-Equal 'nichts' $r.Status 'Status'
    Assert-True ($r.Message -like '*Bereits*') 'Begruendung'
    Assert-True ($script:Protokoll -notcontains 'enable-feature:Microsoft-Windows-Subsystem-Linux') 'nicht angeschaltet'
}

Test-Case 'Ist sie aus, wird sie angeschaltet' {
    Setze-Lage @{ state = 'Disabled' }
    $r = Invoke-UwhFeature (Neuer-Eintrag 'feature' 'NetFx3') 'install'
    Assert-Equal 'ok' $r.Status 'Status'
    Assert-True ($script:Protokoll -contains 'enable-feature:NetFx3') 'richtige Funktion angeschaltet'
    Assert-True (-not $r.Reboot) 'kein Neustart noetig'
}

Test-Case 'Verlangt Windows einen Neustart, wird das weitergereicht' {
    Setze-Lage @{ state = 'Disabled'; restart = $true }
    $r = Invoke-UwhFeature (Neuer-Eintrag 'feature' 'VirtualMachinePlatform') 'install'
    Assert-Equal 'ok' $r.Status 'Status'
    Assert-True $r.Reboot 'Neustart gemeldet'
    Assert-True ($r.Message -like '*Neustart*') 'und benannt'
}

Test-Case 'Entfernen einer nicht aktiven Funktion tut nichts' {
    Setze-Lage @{ state = 'Disabled' }
    $r = Invoke-UwhFeature (Neuer-Eintrag 'feature' 'NetFx3') 'uninstall'
    Assert-Equal 'nichts' $r.Status 'Status'
    Assert-True ($script:Protokoll -notcontains 'disable-feature:NetFx3') 'nicht abgeschaltet'
}

Test-Case 'Entfernen einer aktiven Funktion schaltet sie ab' {
    Setze-Lage @{ state = 'Enabled' }
    $r = Invoke-UwhFeature (Neuer-Eintrag 'feature' 'Microsoft-Hyper-V-All') 'uninstall'
    Assert-Equal 'ok' $r.Status 'Status'
    Assert-True ($script:Protokoll -contains 'disable-feature:Microsoft-Hyper-V-All') 'abgeschaltet'
}

Test-Case 'Eine unbekannte Funktion meldet einen Fehler' {
    Setze-Lage @{ wirft = $true }
    $r = Invoke-UwhFeature (Neuer-Eintrag 'feature' 'GibtsNicht') 'install'
    Assert-Equal 'fehler' $r.Status 'Status'
    Assert-True ($r.Message -like '*unbekannt*') 'Grund genannt'
}

Test-Case 'Aktualisieren gibt es fuer Windows-Funktionen nicht' {
    Setze-Lage
    $r = Invoke-UwhFeature (Neuer-Eintrag 'feature' 'NetFx3') 'update'
    Assert-Equal 'fehler' $r.Status 'Status'
}

Write-Host ''
Write-Host 'Optionale Komponenten' -ForegroundColor Cyan

Test-Case 'Vorhandene Komponente wird nicht noch einmal geholt' {
    Setze-Lage @{ state = 'Installed' }
    $r = Invoke-UwhCapability (Neuer-Eintrag 'capability' 'OpenSSH.Client~~~~0.0.1.0') 'install'
    Assert-Equal 'nichts' $r.Status 'Status'
    Assert-True ($script:Protokoll -notcontains 'add-capability:OpenSSH.Client~~~~0.0.1.0') 'nichts geholt'
}

Test-Case 'Fehlende Komponente wird geholt' {
    Setze-Lage @{ state = 'NotPresent' }
    $r = Invoke-UwhCapability (Neuer-Eintrag 'capability' 'OpenSSH.Server~~~~0.0.1.0') 'install'
    Assert-Equal 'ok' $r.Status 'Status'
    Assert-True ($script:Protokoll -contains 'add-capability:OpenSSH.Server~~~~0.0.1.0') 'richtige Komponente'
}

Test-Case 'Auch hier wird ein Neustart weitergereicht' {
    Setze-Lage @{ state = 'NotPresent'; restart = $true }
    $r = Invoke-UwhCapability (Neuer-Eintrag 'capability' 'OpenSSH.Server~~~~0.0.1.0') 'install'
    Assert-True $r.Reboot 'Neustart gemeldet'
}

Test-Case 'Entfernen einer fehlenden Komponente tut nichts' {
    Setze-Lage @{ state = 'NotPresent' }
    $r = Invoke-UwhCapability (Neuer-Eintrag 'capability' 'OpenSSH.Client~~~~0.0.1.0') 'uninstall'
    Assert-Equal 'nichts' $r.Status 'Status'
}

Test-Case 'Eine unbekannte Komponente meldet einen Fehler' {
    Setze-Lage @{ wirft = $true }
    $r = Invoke-UwhCapability (Neuer-Eintrag 'capability' 'Gibts.Nicht~~~~0.0.0.0') 'install'
    Assert-Equal 'fehler' $r.Status 'Status'
}

Write-Host ''
Write-Host 'PowerShell-Module' -ForegroundColor Cyan

Test-Case 'Vorhandenes Modul wird nicht noch einmal geholt' {
    Setze-Lage @{ vorhanden = $true }
    $r = Invoke-UwhPsModule (Neuer-Eintrag 'psmodule' 'PSWindowsUpdate') 'install'
    Assert-Equal 'nichts' $r.Status 'Status'
    Assert-True ($script:Protokoll -notlike '*install-module*') 'nichts geholt'
}

Test-Case 'Fehlendes Modul wird maschinenweit geholt' {
    Setze-Lage
    $r = Invoke-UwhPsModule (Neuer-Eintrag 'psmodule' 'PSWindowsUpdate' 'machine') 'install'
    Assert-Equal 'ok' $r.Status 'Status'
    Assert-True ($script:Protokoll -contains 'install-module:PSWindowsUpdate:AllUsers') 'fuer alle Benutzer'
}

Test-Case 'Mit scope user nur fuer den angemeldeten Benutzer' {
    Setze-Lage
    $r = Invoke-UwhPsModule (Neuer-Eintrag 'psmodule' 'Terminal-Icons' 'user') 'install'
    Assert-Equal 'ok' $r.Status 'Status'
    Assert-True ($script:Protokoll -contains 'install-module:Terminal-Icons:CurrentUser') 'nur fuer diesen Benutzer'
}

Test-Case 'Aktualisieren und Entfernen rufen die richtigen Befehle' {
    Setze-Lage
    [void](Invoke-UwhPsModule (Neuer-Eintrag 'psmodule' 'PSWindowsUpdate') 'update')
    Assert-True ($script:Protokoll -contains 'update-module:PSWindowsUpdate') 'Aktualisieren'

    Setze-Lage
    [void](Invoke-UwhPsModule (Neuer-Eintrag 'psmodule' 'PSWindowsUpdate') 'uninstall')
    Assert-True ($script:Protokoll -contains 'uninstall-module:PSWindowsUpdate') 'Entfernen'
}

Test-Case 'Ein unbekanntes Modul meldet einen Fehler' {
    Setze-Lage @{ wirft = $true }
    $r = Invoke-UwhPsModule (Neuer-Eintrag 'psmodule' 'GibtsNicht') 'install'
    Assert-Equal 'fehler' $r.Status 'Status'
    Assert-True ($r.Message -like '*nicht gefunden*') 'Grund weitergereicht'
}

Test-Case 'Eine unbekannte Aktion meldet einen Fehler' {
    Setze-Lage
    $r = Invoke-UwhPsModule (Neuer-Eintrag 'psmodule' 'PSWindowsUpdate') 'reparieren'
    Assert-Equal 'fehler' $r.Status 'Status'
}

Write-Host ''
Write-Host 'Verteiler' -ForegroundColor Cyan

Test-Case 'Jeder provider landet beim richtigen Weg' {
    Setze-Lage @{ state = 'Enabled' }
    Assert-Equal 'nichts' (Invoke-UwhProvider (Neuer-Eintrag 'feature' 'NetFx3') 'install' @{}).Status 'feature'

    Setze-Lage @{ state = 'Installed' }
    Assert-Equal 'nichts' (Invoke-UwhProvider (Neuer-Eintrag 'capability' 'OpenSSH.Client~~~~0.0.1.0') 'install' @{}).Status 'capability'

    Setze-Lage @{ vorhanden = $true }
    Assert-Equal 'nichts' (Invoke-UwhProvider (Neuer-Eintrag 'psmodule' 'PSWindowsUpdate') 'install' @{}).Status 'psmodule'
}

Test-Case 'Ein unbekannter provider meldet einen Fehler' {
    $e = Neuer-Eintrag 'feature' 'NetFx3'
    $e.Provider = 'erfunden'
    $r = Invoke-UwhProvider $e 'install' @{}
    Assert-Equal 'fehler' $r.Status 'Status'
    Assert-True ($r.Message -like '*erfunden*') 'nennt den provider'
}

Write-Host ''
Write-Host ("  {0} bestanden, {1} fehlgeschlagen" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
Write-Host ''
if ($script:Fail -gt 0) { exit 1 }
exit 0
