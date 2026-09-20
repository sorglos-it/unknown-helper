# Explorer aufraeumen: Dateiendungen und versteckte Dateien.
# Gilt nur fuer den angemeldeten Benutzer, braucht keine Administratorrechte.

[CmdletBinding()]
param([Parameter(Mandatory)][string]$Action)

$ErrorActionPreference = 'Stop'

$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

function Test-Ja {
    param([string]$Wert)
    return ($Wert -match '^(ja|j|yes|y|true|1)$')
}

function Invoke-Install {
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }

    $endungen = Test-Ja $env:ENDUNGEN
    $versteckt = Test-Ja $env:VERSTECKT

    # HideFileExt: 0 = Endungen sichtbar
    Set-ItemProperty -Path $key -Name 'HideFileExt' -Value ([int](-not $endungen)) -Type DWord
    # Hidden: 1 = versteckte Dateien sichtbar, 2 = ausgeblendet
    Set-ItemProperty -Path $key -Name 'Hidden' -Value $(if ($versteckt) { 1 } else { 2 }) -Type DWord

    Write-Host ("  Dateiendungen: {0}" -f $(if ($endungen) { 'sichtbar' } else { 'ausgeblendet' }))
    Write-Host ("  Versteckte Dateien: {0}" -f $(if ($versteckt) { 'sichtbar' } else { 'ausgeblendet' }))
    Write-Host '  Wirksam nach dem naechsten Anmelden oder Neustart des Explorers.'
}

switch ($Action) {
    'install' { Invoke-Install }
    default   { Write-Error "Unbekannte Aktion '$Action'."; exit 1 }
}

exit 0
