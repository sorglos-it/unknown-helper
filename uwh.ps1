<#
.SYNOPSIS
    uwh - unknown windows helper. Software auswaehlen, installieren, als Profil wiederholen.

.EXAMPLE
    .\uwh.ps1
    Menue oeffnen und auswaehlen.

.EXAMPLE
    .\uwh.ps1 -Profile Arbeitsplatz -Unattended
    Gespeichertes Profil ohne Rueckfragen abspielen.
#>
[CmdletBinding()]
param(
    [Alias('Profile')][string]$ProfileName,
    [switch]$Unattended,
    [string]$Resume,
    [string]$StateDir,
    [switch]$List,
    [switch]$NoUpdate,
    [switch]$NoScan,
    [switch]$Doctor,
    [switch]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

foreach ($lib in @('core', 'yaml', 'repos', 'catalog', 'providers', 'menu', 'execute', 'profiles', 'update')) {
    . (Join-Path $PSScriptRoot "lib\$lib.ps1")
}

$global:UwhVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()

Initialize-UwhConsole
Initialize-UwhTls
if ($StateDir) { Set-UwhStateDir $StateDir }

# Sicherheitsnetz: Anwender bekommen eine Meldung, keinen Stapelabzug.
# Die technischen Einzelheiten stehen im Protokoll.
trap {
    Write-Host ''
    Write-UwhErr $_.Exception.Message
    Write-UwhLog 'TRAP' ("{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace)
    Write-Host ''
    exit 1
}

# ------------------------------------------------------------------
# Kleine Betriebsarten
# ------------------------------------------------------------------

if ($Version) { Write-Host "uwh $global:UwhVersion"; exit 0 }

if ($Doctor) {
    $os = Get-UwhOsInfo
    Write-Host ''
    Set-UwhWidth
    Get-UwhHeader 'Systempruefung' | ForEach-Object { Write-Host $_ }
    Write-Host ''
    Write-Host ("  Windows           {0} (Build {1}, {2})" -f $os.Caption, $os.Build, $os.Arch)
    Write-Host ("  PowerShell        {0}" -f $PSVersionTable.PSVersion)
    Write-Host ("  Administrator     {0}" -f $(if (Test-UwhAdmin) { 'ja' } else { 'nein' }))
    Write-Host ("  winget            {0}" -f $(if (Test-UwhWinget) { Get-UwhWinget } else { 'FEHLT' }))
    Write-Host ("  Ablage            {0}" -f (Get-UwhStateDir))
    Write-Host ("  Ordner            {0}" -f (Get-UwhRoot))
    if (Test-UwhOnNetworkDrive) {
        Write-Host ("  Netzlaufwerk      ja -> erhoeht wird {0} benutzt" -f (Resolve-UwhUncPath (Get-UwhRoot))) -ForegroundColor Yellow
    }
    Write-Host ("  git               {0}" -f $(if (Get-UwhGit) { Get-UwhGit } else { 'fehlt - eigene Repos nur als lokaler Ordner' }))
    try {
        $cat = Get-UwhCatalog
        Write-Host ("  Katalog           {0} Eintraege, {1} Kategorien" -f $cat.Entries.Count, $cat.Categories.Count)

        $info = Get-UwhRepos
        if (@($info.Repos).Count -gt 0) {
            Write-Host '  Eigene Repos'
            foreach ($r in $info.Repos) {
                $treffer = @($cat.Repos | Where-Object { $_.Repo.Id -eq $r.Id }) | Select-Object -First 1
                $stand = if (-not $r.Aktiv) { 'aus' }
                         elseif (-not (Test-Path -LiteralPath $r.Pfad)) { 'Ordner fehlt' }
                         elseif ($treffer) { '{0} Eintraege' -f $treffer.Anzahl } else { 'keine config.yaml' }
                if ($treffer -and $treffer.Ersetzt -gt 0) { $stand += (', {0} ersetzen uwh-Eintraege' -f $treffer.Ersetzt) }
                $art = if ($r.Url) { 'git' } else { 'lokal' }
                Write-Host ("    {0,-22} {1,-6} {2}" -f $r.Name, $art, $stand)
            }
        }

        if ($cat.Problems.Count -gt 0) {
            Write-Host '  Fehlerhafte Eintraege:' -ForegroundColor Yellow
            $cat.Problems | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray }
        }
    } catch {
        Write-Host ("  Katalog           FEHLER: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
    Write-Host ''
    if (-not (Test-UwhWinget)) {
        Write-Host '  winget fehlt. Im Microsoft Store "App Installer" installieren.' -ForegroundColor Yellow
        Write-Host ''
        exit 1
    }
    exit 0
}

if ($List) {
    $cat = Get-UwhCatalog
    foreach ($c in $cat.Categories) {
        $items = @($cat.Entries | Where-Object { $_.Category -eq $c } | Sort-Object Name)
        if ($items.Count -eq 0) { continue }
        Write-Host ''
        Write-Host "  $c" -ForegroundColor Cyan
        foreach ($e in $items) {
            Write-Host ("    {0}  {1}" -f $e.Key.PadRight(22), $e.Description) -ForegroundColor Gray
        }
    }
    Write-Host ''
    exit 0
}

# ------------------------------------------------------------------
# Selbstaktualisierung
# ------------------------------------------------------------------

if (-not $NoUpdate -and -not $Resume) {
    # Eigene Repos zuerst: startet uwh sich nach der eigenen Aktualisierung neu,
    # tut es das mit -NoUpdate - und haette die Repos sonst uebersprungen.
    Sync-UwhRepos

    if (Update-Uwh) {
        $forward = @('-NoUpdate')
        foreach ($p in $PSBoundParameters.GetEnumerator()) {
            if ($p.Key -eq 'NoUpdate') { continue }
            if ($p.Value -is [switch]) { if ($p.Value) { $forward += "-$($p.Key)" } }
            else { $forward += @("-$($p.Key)", [string]$p.Value) }
        }
        & (Get-UwhPowerShellExe) '-NoProfile' '-ExecutionPolicy' 'Bypass' '-File' $PSCommandPath @forward
        exit $LASTEXITCODE
    }
}

# ------------------------------------------------------------------
# Gemeinsamer Abschluss: Plan ausfuehren, notfalls erhoeht
# ------------------------------------------------------------------

function Invoke-UwhRun {
    param($Catalog, $Plan)

    if ($Plan.NeedsAdmin -and -not (Test-UwhAdmin)) {
        Save-UwhState $Plan
        Write-Host ''
        Write-UwhInfo 'Fuer die Installation werden Administratorrechte gebraucht.'
        try {
            $code = Invoke-UwhElevated @('-Resume', $Plan.Id, '-StateDir', (Get-UwhStateDir), '-NoUpdate')
            return $code
        } catch {
            Write-UwhErr 'Ohne Administratorrechte geht es nicht weiter.'
            return 2
        }
    }

    Set-UwhWidth
    Clear-Host
    Get-UwhHeader 'Installation laeuft' | ForEach-Object { Write-Host $_ }

    [void](Invoke-UwhPlan $Catalog $Plan)
    $code = Show-UwhReport $Catalog $Plan

    if (@($Plan.Items | Where-Object { $_.Status -eq 'offen' }).Count -eq 0) {
        Unregister-UwhResume $Plan.Id
        Remove-UwhState $Plan.Id
    }

    if (-not $Plan.Unattended) {
        Write-Host '  Taste druecken zum Beenden...' -ForegroundColor DarkGray
        [void][Console]::ReadKey($true)
    }
    return $code
}

# ------------------------------------------------------------------
# Fortsetzen
# ------------------------------------------------------------------

if ($Resume) {
    if (-not (Test-UwhSafeId $Resume)) { Write-UwhErr 'Ungueltige Lauf-Kennung.'; exit 2 }

    Unregister-UwhResume $Resume
    $plan = Import-UwhState $Resume
    if (-not $plan) { Write-UwhErr "Kein Lauf mit der Kennung '$Resume' gefunden."; exit 2 }

    $catalog = Get-UwhCatalog
    exit (Invoke-UwhRun $catalog $plan)
}

# ------------------------------------------------------------------
# Profil abspielen
# ------------------------------------------------------------------

$catalog = Get-UwhCatalog
if ($catalog.Problems.Count -gt 0) {
    foreach ($p in $catalog.Problems) { Write-UwhWarn "Katalog: $p" }
}

if ($ProfileName) {
    try {
        $prof = Import-UwhProfile $ProfileName
    } catch {
        Write-Host ''
        Write-UwhErr $_.Exception.Message
        $vorhanden = @(Get-UwhProfileNames)
        Write-Host ''
        if ($vorhanden.Count -gt 0) {
            Write-Host '  Vorhandene Profile:' -ForegroundColor DarkGray
            foreach ($n in $vorhanden) { Write-Host "    $n" -ForegroundColor DarkGray }
        } else {
            Write-Host '  Es gibt noch kein Profil. Eines entsteht im Menue:' -ForegroundColor DarkGray
            Write-Host '  auswaehlen, dann "Auswahl vorher als Profil speichern?" mit j bestaetigen.' -ForegroundColor DarkGray
        }
        Write-Host ''
        exit 2
    }
    $unattended = $Unattended -or [bool]$prof.Options['unattended']

    $plan = New-UwhPlan $catalog $prof.Select `
                        -Unattended $unattended `
                        -ContinueOnError ([bool]$prof.Options['continue_on_error']) `
                        -RebootPolicy ([string]$prof.Options['reboot'])

    if ($plan.Items.Count -eq 0) { Write-UwhErr 'Das Profil enthaelt nichts Ausfuehrbares.'; exit 2 }

    Set-UwhLogFile $plan.LogFile
    Invoke-UwhCollect $catalog $plan

    if (-not $unattended) {
        if (-not (Show-UwhSummary $catalog $plan)) { Write-Host '  Abgebrochen.'; exit 0 }
    }
    exit (Invoke-UwhRun $catalog $plan)
}

# ------------------------------------------------------------------
# Menue
# ------------------------------------------------------------------

$installed = @{}
if (-not $NoScan) {
    Write-Host ''
    Write-Host '  Einen Moment - vorhandene Programme werden gesucht...' -ForegroundColor DarkGray
    foreach ($e in $catalog.Entries) {
        if ($e.Provider -in @('winget', 'msstore')) {
            if (Test-UwhEntryInstalled $e) { $installed[$e.Key] = $true }
        }
    }
}

$selection = [ordered]@{}
foreach ($e in $catalog.Entries) {
    if ($e.Recommended -and -not $installed.ContainsKey($e.Key)) { $selection[$e.Key] = 'install' }
}

$presetAnswers = @{}

while ($true) {
    $result = Show-UwhPicker $catalog $selection $installed

    if ($result -eq 'ende') {
        $script:UwhLastHeight = 0
        Clear-Host
        exit 0
    }

    if ($result -eq 'profil') {
        $name = Show-UwhProfilePicker
        if ($name) {
            try {
                $prof = Import-UwhProfile $name
                $selection.Clear()
                $presetAnswers = @{}
                foreach ($i in $prof.Select) {
                    $selection[$i.Key] = $i.Action
                    if ($i.Answers.Count -gt 0) { $presetAnswers[$i.Key] = $i.Answers }
                }
            } catch {
                Write-UwhErr $_.Exception.Message
                Start-Sleep -Seconds 2
            }
        }
        $script:UwhLastHeight = 0
        continue
    }

    break
}

$ordered = New-Object System.Collections.Generic.List[object]
foreach ($key in $selection.Keys) {
    $answers = if ($presetAnswers.ContainsKey($key)) { $presetAnswers[$key] } else { @{} }
    $ordered.Add([pscustomobject]@{ Key = $key; Action = $selection[$key]; Answers = $answers })
}

$plan = New-UwhPlan $catalog $ordered.ToArray()
if ($plan.Items.Count -eq 0) { Write-UwhErr 'Nichts ausgewaehlt.'; exit 2 }

Set-UwhLogFile $plan.LogFile
Invoke-UwhCollect $catalog $plan

if (-not (Show-UwhSummary $catalog $plan)) {
    Write-Host ''
    if (Read-UwhConfirm 'Auswahl als Profil speichern?' $false) {
        $name = Read-UwhInline 'Name fuer das Profil:'
        if ($name) {
            try { Write-UwhOk ("Gespeichert: {0}" -f (Save-UwhProfile $name $plan.Items $catalog)) }
            catch { Write-UwhErr $_.Exception.Message }
        }
    }
    Write-Host '  Abgebrochen.'
    exit 0
}

if (Read-UwhConfirm 'Auswahl vorher als Profil speichern?' $false) {
    $name = Read-UwhInline 'Name fuer das Profil:'
    if ($name) {
        try { Write-UwhOk ("Gespeichert: {0}" -f (Save-UwhProfile $name $plan.Items $catalog)) }
        catch { Write-UwhErr $_.Exception.Message }
    }
}

exit (Invoke-UwhRun $catalog $plan)
