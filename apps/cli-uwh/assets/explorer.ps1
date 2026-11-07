# Explorer aufraeumen: Dateiendungen und versteckte Dateien.
# Gilt nur fuer den angemeldeten Benutzer, braucht keine Administratorrechte.
# Die Sprache gibt uwh in UWH_LANG mit - ohne uwh gilt die von Windows.

[CmdletBinding()]
param([Parameter(Mandatory)][string]$Action)

$ErrorActionPreference = 'Stop'

$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

$texte = @{
    de = @{
        endungenAn = 'Dateiendungen: sichtbar';            endungenAus = 'Dateiendungen: ausgeblendet'
        verstecktAn = 'Versteckte Dateien: sichtbar';      verstecktAus = 'Versteckte Dateien: ausgeblendet'
        wirksam = 'Wirksam nach dem nächsten Anmelden oder Neustart des Explorers.'
        aktion = "Unbekannte Aktion '{0}'."
    }
    en = @{
        endungenAn = 'File extensions: shown';             endungenAus = 'File extensions: hidden'
        verstecktAn = 'Hidden files: shown';               verstecktAus = 'Hidden files: not shown'
        wirksam = 'Takes effect after the next sign-in or a restart of Explorer.'
        aktion = "Unknown action '{0}'."
    }
    fr = @{
        endungenAn = 'Extensions de fichiers : affichées'; endungenAus = 'Extensions de fichiers : masquées'
        verstecktAn = 'Fichiers cachés : affichés';        verstecktAus = 'Fichiers cachés : masqués'
        wirksam = "Prend effet à la prochaine connexion ou au redémarrage de l'Explorateur."
        aktion = "Action inconnue '{0}'."
    }
    it = @{
        endungenAn = 'Estensioni dei file: visibili';      endungenAus = 'Estensioni dei file: nascoste'
        verstecktAn = 'File nascosti: visibili';           verstecktAus = 'File nascosti: non visibili'
        wirksam = 'Attivo dal prossimo accesso o dopo il riavvio di Esplora file.'
        aktion = "Azione sconosciuta '{0}'."
    }
    es = @{
        endungenAn = 'Extensiones de archivo: visibles';   endungenAus = 'Extensiones de archivo: ocultas'
        verstecktAn = 'Archivos ocultos: visibles';        verstecktAus = 'Archivos ocultos: no visibles'
        wirksam = 'Surte efecto tras el próximo inicio de sesión o al reiniciar el Explorador.'
        aktion = "Acción desconocida '{0}'."
    }
}

$sprache = [string]$env:UWH_LANG
if (-not $texte.ContainsKey($sprache)) { $sprache = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName }
if (-not $texte.ContainsKey($sprache)) { $sprache = 'en' }
$t = $texte[$sprache]

# Antworten kommen von uwh als ja/nein - von Hand gestartet geht auch yes, 1 usw.
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

    Write-Host ('  ' + $(if ($endungen) { $t.endungenAn } else { $t.endungenAus }))
    Write-Host ('  ' + $(if ($versteckt) { $t.verstecktAn } else { $t.verstecktAus }))
    Write-Host ('  ' + $t.wirksam)
}

switch ($Action) {
    'install' { Invoke-Install }
    default   { Write-Error ($t.aktion -f $Action); exit 1 }
}

exit 0
