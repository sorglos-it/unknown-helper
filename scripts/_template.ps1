<#
    Vorlage fuer eigene uwh-Skripte.

    So wird ein Skript eingebunden - Eintrag in config.yaml:

      meinskript:
        name: Mein Skript
        description: Was es macht
        category: Windows-Einstellungen
        provider: script
        file: meinskript.ps1
        admin: true
        actions:
          - name: install
            prompts:
              - question: Wie soll der Ordner heissen?
                variable: ORDNER
                type: text          # text | yesno | secret
                default: C:\Daten

    Spielregeln:
      - Antworten kommen als Umgebungsvariablen an: $env:ORDNER
      - Rueckgabe 0   = erledigt
      - Rueckgabe 3010 = erledigt, Windows muss neu starten (uwh macht danach weiter)
      - Alles andere  = Fehler
      - Keine eigenen Abfragen einbauen. Fragen gehoeren in config.yaml,
        damit uwh sie vorab sammeln und in Profilen speichern kann.
      - Das Skript laeuft in einem eigenen Prozess. Es teilt sich mit uwh
        nichts ausser den Umgebungsvariablen - und kann uwh deshalb auch
        nicht durcheinanderbringen.
      - Write-Host-Ausgaben erscheinen nach dem Lauf, nicht waehrenddessen.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Action)

$ErrorActionPreference = 'Stop'

function Invoke-Install {
    $ordner = $env:ORDNER
    if (-not $ordner) { $ordner = 'C:\Daten' }

    Write-Host "  Lege $ordner an..."
    New-Item -ItemType Directory -Path $ordner -Force | Out-Null
}

function Invoke-Uninstall {
    Write-Host '  Nichts zu entfernen.'
}

switch ($Action) {
    'install'   { Invoke-Install }
    'uninstall' { Invoke-Uninstall }
    default     { Write-Error "Unbekannte Aktion '$Action'."; exit 1 }
}

exit 0
