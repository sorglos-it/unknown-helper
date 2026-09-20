# Energieplan setzen. Braucht Administratorrechte.

[CmdletBinding()]
param([Parameter(Mandatory)][string]$Action)

$ErrorActionPreference = 'Stop'

$plaene = @{
    'ausgewogen'      = '381b4222-f694-41f0-9685-ff5bb260df2e'
    'hoechstleistung' = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    'energiesparen'   = 'a1841308-3541-4fab-bc81-f71556f20b4a'
}

function Invoke-Install {
    $name = ([string]$env:PLAN).Trim().ToLowerInvariant()
    if (-not $name) { $name = 'ausgewogen' }

    if (-not $plaene.ContainsKey($name)) {
        Write-Error ("Unbekannter Plan '{0}'. Moeglich: {1}" -f $name, ($plaene.Keys -join ', '))
        exit 1
    }

    powercfg /setactive $plaene[$name] | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Energieplan konnte nicht gesetzt werden. Auf diesem Geraet ist er evtl. gesperrt.'
        exit 1
    }
    Write-Host "  Energieplan: $name"

    $minuten = 0
    if ([int]::TryParse(([string]$env:BILDSCHIRM).Trim(), [ref]$minuten) -and $minuten -ge 0) {
        powercfg /change monitor-timeout-ac $minuten | Out-Null
        powercfg /change monitor-timeout-dc $minuten | Out-Null
        if ($minuten -eq 0) {
            Write-Host '  Bildschirm: bleibt an'
        } else {
            Write-Host "  Bildschirm aus nach: $minuten Minuten"
        }
    } else {
        Write-Host '  Bildschirmzeit unveraendert (keine gueltige Zahl angegeben).'
    }
}

switch ($Action) {
    'install' { Invoke-Install }
    default   { Write-Error "Unbekannte Aktion '$Action'."; exit 1 }
}

exit 0
