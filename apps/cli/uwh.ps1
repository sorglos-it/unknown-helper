<#
.SYNOPSIS
    uwh - unknown windows helper. Software auswaehlen, installieren, als Profil wiederholen.

.EXAMPLE
    .\uwh.cmd
    Menue oeffnen und auswaehlen.

.EXAMPLE
    .\uwh.cmd -Profile Arbeitsplatz -Unattended
    Gespeichertes Profil ohne Rueckfragen abspielen.

.EXAMPLE
    .\uwh.cmd -Language fr
    Auf Franzoesisch, egal wie Windows eingestellt ist (de, en, fr, it, es).
#>
[CmdletBinding()]
param(
    [Alias('Profile')][string]$ProfileName,
    [switch]$Unattended,
    [string]$Resume,
    [string]$StateDir,
    [string]$Language,
    [switch]$List,
    [switch]$NoUpdate,
    [switch]$NoScan,
    [switch]$Doctor,
    [switch]$Version
)

$ErrorActionPreference = 'Stop'
# Der Fortschrittsbalken macht Downloads in Windows PowerShell 5.1 bis zu
# hundertmal langsamer - Installationsprogramme, Aktualisierung, Module.
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version 2.0

foreach ($lib in @('core', 'yaml', 'lang', 'repos', 'catalog', 'providers', 'menu', 'execute', 'profiles', 'update')) {
    . (Join-Path $PSScriptRoot "classes\$lib.ps1")
}

$global:UwhVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()

Initialize-UwhConsole
Initialize-UwhTls
if ($StateDir) { Set-UwhStateDir $StateDir }
Initialize-UwhEigenes
Initialize-UwhLanguage $Language

# Sicherheitsnetz: Anwender bekommen eine Meldung, keinen Stapelabzug.
# Die technischen Einzelheiten stehen im Protokoll.
trap {
    Write-Host ''
    Write-UwhErr $_.Exception.Message
    Write-UwhLog 'TRAP' ("{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace)
    Exit-Uwh 1 $Unattended
}

if ($Language -and -not (Test-UwhLanguage $Language)) {
    Write-UwhErr (T 'main.badlang' $Language ((Get-UwhLanguages) -join ', '))
    Exit-Uwh 2 $Unattended
}

# ------------------------------------------------------------------
# Kleine Betriebsarten
# ------------------------------------------------------------------

if ($Version) { Write-Host "uwh $global:UwhVersion"; exit 0 }

if ($Doctor) {
    function Write-Zeile { param([string]$Name, [string]$Wert) Write-Host ('  {0,-17} {1}' -f $Name, $Wert) }

    $os = Get-UwhOsInfo
    Write-Host ''
    Set-UwhWidth
    Get-UwhHeader (T 'doctor.title') | ForEach-Object { Write-Host $_ }
    Write-Host ''
    Write-Zeile 'Windows' ("{0} (Build {1}, {2})" -f $os.Caption, $os.Build, $os.Arch)
    Write-Zeile 'PowerShell' $PSVersionTable.PSVersion
    Write-Zeile (T 'doctor.admin') $(if (Test-UwhAdmin) { T 'doctor.yes' } else { T 'doctor.no' })
    Write-Zeile 'winget' $(if (Test-UwhWinget) { Get-UwhWinget } else { T 'doctor.missing' })
    Write-Zeile (T 'doctor.language') (T ('doctor.language.' + (Get-UwhLanguageSource)) (T 'lang.name'))
    Write-Zeile (T 'doctor.state') (Get-UwhStateDir)
    Write-Zeile (T 'doctor.folder') (Get-UwhRoot)
    if (Test-UwhOnNetworkDrive) {
        Write-Host ('  {0,-17} {1}' -f (T 'doctor.netdrive'), (T 'doctor.netdrive.value' (Resolve-UwhUncPath (Get-UwhRoot)))) -ForegroundColor Yellow
    }
    Write-Zeile 'git' $(if (Get-UwhGit) { Get-UwhGit } else { T 'doctor.git.missing' })
    try {
        $cat = Get-UwhCatalog
        Write-Zeile (T 'doctor.catalog') (T 'doctor.catalog.value' $cat.Entries.Count $cat.Categories.Count)

        $info = Get-UwhRepos
        if (@($info.Repos).Count -gt 0) {
            Write-Host ('  ' + (T 'doctor.repos'))
            foreach ($r in $info.Repos) {
                $treffer = @($cat.Repos | Where-Object { $_.Repo.Id -eq $r.Id }) | Select-Object -First 1
                $stand = if (-not $r.Aktiv) { T 'doctor.repo.off' }
                         elseif (-not (Test-Path -LiteralPath $r.Pfad)) { T 'doctor.repo.nofolder' }
                         elseif ($treffer) { T 'doctor.repo.entries' $treffer.Anzahl } else { T 'doctor.repo.noconfig' }
                if ($treffer -and $treffer.Ersetzt -gt 0) { $stand += (T 'doctor.repo.replaces' $treffer.Ersetzt) }
                $art = if ($r.Url) { 'git' } else { T 'doctor.repo.local' }
                Write-Host ("    {0,-22} {1,-6} {2}" -f $r.Name, $art, $stand)
            }
        }

        if ($cat.Problems.Count -gt 0) {
            Write-Host ('  ' + (T 'doctor.problems')) -ForegroundColor Yellow
            $cat.Problems | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray }
        }
    } catch {
        Write-Host ('  {0,-17} {1}' -f (T 'doctor.catalog'), (T 'doctor.catalog.error' $_.Exception.Message)) -ForegroundColor Red
    }
    Write-Host ''
    if (-not (Test-UwhWinget)) {
        Write-Host ('  ' + (T 'doctor.nowinget')) -ForegroundColor Yellow
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
        Write-Host ('  ' + (Get-UwhCategoryName $cat $c)) -ForegroundColor Cyan
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
        Write-UwhInfo (T 'run.admin')
        try {
            # Die Sprache reist mit: ein Administrator-Konto kann eine andere haben.
            $code = Invoke-UwhElevated @('-Resume', $Plan.Id, '-StateDir', (Get-UwhStateDir), '-NoUpdate',
                                         '-Language', (Get-UwhLanguage))
            return $code
        } catch {
            # Abgelehnt: dann gibt es auch nichts fortzusetzen.
            Remove-UwhState $Plan.Id
            Write-UwhErr (T 'run.noadmin')
            if (-not $Plan.Unattended -and (Test-UwhInteractive)) {
                Write-Host ('  ' + (T 'run.presskey')) -ForegroundColor DarkGray
                [void][Console]::ReadKey($true)
            }
            return 2
        }
    }

    Set-UwhWidth
    Clear-Host
    Get-UwhHeader (T 'run.title') | ForEach-Object { Write-Host $_ }

    [void](Invoke-UwhPlan $Catalog $Plan)
    $code = Show-UwhReport $Catalog $Plan

    if (@($Plan.Items | Where-Object { $_.Status -eq 'offen' }).Count -eq 0) {
        Unregister-UwhResume $Plan.Id
        Remove-UwhState $Plan.Id
    }

    if (-not $Plan.Unattended) {
        Write-Host ('  ' + (T 'run.presskey')) -ForegroundColor DarkGray
        [void][Console]::ReadKey($true)
    }
    return $code
}

# ------------------------------------------------------------------
# Fortsetzen
# ------------------------------------------------------------------

if ($Resume) {
    if (-not (Test-UwhSafeId $Resume)) { Write-UwhErr (T 'main.badresume'); Exit-Uwh 2 }

    Unregister-UwhResume $Resume
    $plan = Import-UwhState $Resume
    if (-not $plan) { Write-UwhErr (T 'main.noresume' $Resume); Exit-Uwh 2 }

    # Weiter in der Sprache, in der der Lauf begann - Firefox soll nicht
    # halb deutsch, halb franzoesisch ankommen.
    if (-not $Language -and $plan.PSObject.Properties['Language'] -and (Test-UwhLanguage $plan.Language)) {
        Set-UwhLanguage $plan.Language
    }

    $catalog = Get-UwhCatalog
    exit (Invoke-UwhRun $catalog $plan)
}

# ------------------------------------------------------------------
# Profil abspielen
# ------------------------------------------------------------------

Clear-UwhAltlasten

$catalog = Get-UwhCatalog
if ($catalog.Problems.Count -gt 0) {
    foreach ($p in $catalog.Problems) { Write-UwhWarn (T 'main.catalog' $p) }
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
            Write-Host ('  ' + (T 'profile.list')) -ForegroundColor DarkGray
            foreach ($n in $vorhanden) { Write-Host "    $n" -ForegroundColor DarkGray }
        } else {
            Write-Host ('  ' + (T 'profile.none')) -ForegroundColor DarkGray
            Write-UwhProfileHowto
        }
        Exit-Uwh 2 $Unattended
    }
    $unattended = $Unattended -or [bool]$prof.Options['unattended']

    $plan = New-UwhPlan $catalog $prof.Select `
                        -Unattended $unattended `
                        -ContinueOnError ([bool]$prof.Options['continue_on_error']) `
                        -RebootPolicy ([string]$prof.Options['reboot'])

    if ($plan.Items.Count -eq 0) { Write-UwhErr (T 'main.emptyprofile'); Exit-Uwh 2 $unattended }

    Set-UwhLogFile $plan.LogFile
    Invoke-UwhCollect $catalog $plan

    if (-not $unattended) {
        if (-not (Show-UwhSummary $catalog $plan)) { Write-Host ('  ' + (T 'main.cancelled')); exit 0 }
    }
    exit (Invoke-UwhRun $catalog $plan)
}

# ------------------------------------------------------------------
# Menue
# ------------------------------------------------------------------

$installed = @{}
if (-not $NoScan) {
    Write-Host ''
    Write-Host ('  ' + (T 'main.scanning')) -ForegroundColor DarkGray
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
if ($plan.Items.Count -eq 0) { Write-UwhErr (T 'main.nothing'); Exit-Uwh 2 }

Set-UwhLogFile $plan.LogFile
Invoke-UwhCollect $catalog $plan

# Fragt nach einem Namen, bis er passt - oder leer bleibt, dann ohne Profil.
function Save-UwhProfileFromMenu {
    param($Plan, $Catalog)
    while ($true) {
        $name = Read-UwhInline (T 'main.profilename')
        if (-not $name) { return }
        if (-not (Test-UwhProfileName $name)) {
            Write-UwhErr (T 'profile.badname' $name)
            Write-Host ('  ' + (T 'profile.namehint')) -ForegroundColor DarkGray
            continue
        }
        try { Write-UwhOk (T 'main.saved' (Save-UwhProfile $name $Plan.Items $Catalog)) }
        catch { Write-UwhErr $_.Exception.Message }
        return
    }
}

if (-not (Show-UwhSummary $catalog $plan)) {
    Write-Host ''
    if (Read-UwhConfirm (T 'main.saveafter') $false) { Save-UwhProfileFromMenu $plan $catalog }
    Write-Host ('  ' + (T 'main.cancelled'))
    exit 0
}

if (Read-UwhConfirm (T 'main.savebefore') $false) { Save-UwhProfileFromMenu $plan $catalog }

exit (Invoke-UwhRun $catalog $plan)
