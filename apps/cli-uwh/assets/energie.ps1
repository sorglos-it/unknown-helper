# Energieplan setzen. Braucht Administratorrechte.
# Die Sprache gibt uwh in UWH_LANG mit - ohne uwh gilt die von Windows.

[CmdletBinding()]
param([Parameter(Mandatory)][string]$Action)

$ErrorActionPreference = 'Stop'

# Gewaehlt wird mit 1, 2 oder 3 - das versteht jede Sprache.
$plaene = @{
    '1' = '381b4222-f694-41f0-9685-ff5bb260df2e'
    '2' = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    '3' = 'a1841308-3541-4fab-bc81-f71556f20b4a'
}

# Die Namen aus der Zeit vor den Sprachen stehen noch in Profilen - sie gelten weiter.
$alteNamen = @{ 'ausgewogen' = '1'; 'hoechstleistung' = '2'; "h$([char]0xF6)chstleistung" = '2'; 'energiesparen' = '3' }

$texte = @{
    de = @{
        namen = @{ '1' = 'Ausbalanciert'; '2' = 'Höchstleistung'; '3' = 'Energiesparmodus' }
        plan = 'Energieplan: {0}'
        unbekannt = "Unbekannter Plan '{0}'. Möglich: 1, 2 oder 3."
        gesperrt = 'Energieplan konnte nicht gesetzt werden. Auf diesem Gerät ist er evtl. gesperrt.'
        an = 'Bildschirm: bleibt an'
        aus = 'Bildschirm aus nach: {0} Minuten'
        unveraendert = 'Bildschirmzeit unverändert (keine gültige Zahl angegeben).'
        aktion = "Unbekannte Aktion '{0}'."
    }
    en = @{
        namen = @{ '1' = 'Balanced'; '2' = 'High performance'; '3' = 'Power saver' }
        plan = 'Power plan: {0}'
        unbekannt = "Unknown plan '{0}'. Possible: 1, 2 or 3."
        gesperrt = 'The power plan could not be set. It may be locked on this device.'
        an = 'Screen: stays on'
        aus = 'Screen off after: {0} minutes'
        unveraendert = 'Screen timeout unchanged (no valid number given).'
        aktion = "Unknown action '{0}'."
    }
    fr = @{
        namen = @{ '1' = 'Utilisation normale'; '2' = 'Performances élevées'; '3' = "Économies d'énergie" }
        plan = "Mode d'alimentation : {0}"
        unbekannt = "Mode inconnu '{0}'. Possible : 1, 2 ou 3."
        gesperrt = "Le mode d'alimentation n'a pas pu être défini. Il est peut-être verrouillé sur cet appareil."
        an = 'Écran : reste allumé'
        aus = 'Écran éteint après : {0} minutes'
        unveraendert = "Délai de l'écran inchangé (aucun nombre valide indiqué)."
        aktion = "Action inconnue '{0}'."
    }
    it = @{
        namen = @{ '1' = 'Bilanciato'; '2' = 'Prestazioni elevate'; '3' = 'Risparmio di energia' }
        plan = 'Piano energetico: {0}'
        unbekannt = "Piano sconosciuto '{0}'. Possibili: 1, 2 o 3."
        gesperrt = 'Impossibile impostare il piano energetico. Potrebbe essere bloccato su questo dispositivo.'
        an = 'Schermo: resta acceso'
        aus = 'Schermo spento dopo: {0} minuti'
        unveraendert = 'Spegnimento dello schermo invariato (nessun numero valido).'
        aktion = "Azione sconosciuta '{0}'."
    }
    es = @{
        namen = @{ '1' = 'Equilibrado'; '2' = 'Alto rendimiento'; '3' = 'Economizador' }
        plan = 'Plan de energía: {0}'
        unbekannt = "Plan desconocido '{0}'. Posibles: 1, 2 o 3."
        gesperrt = 'No se pudo establecer el plan de energía. Puede que esté bloqueado en este equipo.'
        an = 'Pantalla: permanece encendida'
        aus = 'Pantalla apagada tras: {0} minutos'
        unveraendert = 'Tiempo de pantalla sin cambios (no se indicó un número válido).'
        aktion = "Acción desconocida '{0}'."
    }
}

$sprache = [string]$env:UWH_LANG
if (-not $texte.ContainsKey($sprache)) { $sprache = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName }
if (-not $texte.ContainsKey($sprache)) { $sprache = 'en' }
$t = $texte[$sprache]

function Invoke-Install {
    $wahl = ([string]$env:PLAN).Trim().ToLowerInvariant()
    if (-not $wahl) { $wahl = '1' }
    if ($alteNamen.ContainsKey($wahl)) { $wahl = $alteNamen[$wahl] }

    if (-not $plaene.ContainsKey($wahl)) {
        Write-Error ($t.unbekannt -f $env:PLAN)
        exit 1
    }

    powercfg /setactive $plaene[$wahl] | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error $t.gesperrt
        exit 1
    }
    Write-Host ('  ' + ($t.plan -f $t.namen[$wahl]))

    $minuten = 0
    if ([int]::TryParse(([string]$env:BILDSCHIRM).Trim(), [ref]$minuten) -and $minuten -ge 0) {
        powercfg /change monitor-timeout-ac $minuten | Out-Null
        powercfg /change monitor-timeout-dc $minuten | Out-Null
        if ($minuten -eq 0) {
            Write-Host ('  ' + $t.an)
        } else {
            Write-Host ('  ' + ($t.aus -f $minuten))
        }
    } else {
        Write-Host ('  ' + $t.unveraendert)
    }
}

switch ($Action) {
    'install' { Invoke-Install }
    default   { Write-Error ($t.aktion -f $Action); exit 1 }
}

exit 0
