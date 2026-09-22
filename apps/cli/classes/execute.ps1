# uwh - Ablauf: planen, fragen, abarbeiten, Neustart ueberstehen

Set-StrictMode -Version 2.0

# ------------------------------------------------------------------
# Ablage
# ------------------------------------------------------------------

$script:UwhStateDir = $null

function Get-UwhStateDir {
    if ($script:UwhStateDir) { return $script:UwhStateDir }
    # Zwischenstand und Protokolle sind Laufzeitdaten - sie gehoeren nach data\,
    # neben das Programm, nicht in AppData. So bleibt uwh portabel.
    $script:UwhStateDir = Get-UwhPath 'data'
    return $script:UwhStateDir
}

function Set-UwhStateDir {
    param([string]$Path)
    if ($Path) { $script:UwhStateDir = $Path }
}

function Get-UwhStateFile {
    param([string]$Id)
    Join-Path (Join-Path (Get-UwhStateDir) 'state') "$Id.json"
}

function Save-UwhState {
    param($State)

    $file = Get-UwhStateFile $State.Id
    $dir = Split-Path -Parent $file
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    ConvertTo-UwhStateFuerPlatte $State | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $file -Encoding UTF8
}

# Eine Kopie zum Schreiben - der laufende Plan darf nicht veraendert werden,
# sonst waeren die Antworten danach im Arbeitsspeicher verschluesselt.
function ConvertTo-UwhStateFuerPlatte {
    param($State)

    $items = @()
    foreach ($i in @($State.Items)) {
        $geschuetzt = [ordered]@{}
        foreach ($k in (ConvertTo-UwhHashtable $i.Answers).Keys) {
            $geschuetzt[$k] = Protect-UwhText ([string](ConvertTo-UwhHashtable $i.Answers)[$k])
        }
        $items += [pscustomobject]@{
            Key = $i.Key; Action = $i.Action; Answers = $geschuetzt
            Status = $i.Status; Message = $i.Message
        }
    }

    [pscustomobject]@{
        Id = $State.Id; Created = $State.Created
        Unattended = $State.Unattended; ContinueOnError = $State.ContinueOnError
        RebootPolicy = $State.RebootPolicy; Index = $State.Index
        NeedsAdmin = $State.NeedsAdmin; MayReboot = $State.MayReboot
        LogFile = $State.LogFile; Items = $items
    }
}

function Import-UwhState {
    param([string]$Id)
    $file = Get-UwhStateFile $Id
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $state = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
    # ConvertFrom-Json macht aus einer einelementigen Liste ein einzelnes Objekt.
    $state.Items = @($state.Items)

    foreach ($i in $state.Items) {
        $klar = @{}
        foreach ($p in $i.Answers.PSObject.Properties) {
            $klar[$p.Name] = Unprotect-UwhText ([string]$p.Value)
        }
        $i.Answers = $klar
    }
    return $state
}

function Remove-UwhState {
    param([string]$Id)
    Remove-Item -LiteralPath (Get-UwhStateFile $Id) -Force -ErrorAction SilentlyContinue
}

function ConvertTo-UwhHashtable {
    param($Object)
    $h = @{}
    if ($null -eq $Object) { return $h }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($k in $Object.Keys) { $h[[string]$k] = $Object[$k] }
        return $h
    }
    foreach ($p in $Object.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
}

# ------------------------------------------------------------------
# Plan bauen
# ------------------------------------------------------------------

function New-UwhPlan {
    param(
        $Catalog,
        [Parameter(Mandatory)]$Selection,   # geordnete Liste: @{ Key; Action; Answers }
        [bool]$Unattended = $false,
        [bool]$ContinueOnError = $true,
        [string]$RebootPolicy = 'ask'
    )

    $items = New-Object System.Collections.Generic.List[object]
    $needsAdmin = $false
    $mayReboot = $false

    foreach ($sel in $Selection) {
        $entry = Get-UwhEntry $Catalog $sel.Key
        if (-not $entry) {
            Write-UwhWarn (T 'plan.unknown' $sel.Key)
            continue
        }
        $action = if ($sel.Action) { $sel.Action } else { 'install' }
        if (-not (Get-UwhAction $entry $action)) {
            Write-UwhWarn (T 'plan.noaction' $entry.Name $action)
            continue
        }

        if ($entry.Admin) { $needsAdmin = $true }
        if ($entry.Reboot -eq 'required' -or $entry.Provider -in @('feature', 'capability')) { $mayReboot = $true }

        $items.Add([pscustomobject]@{
            Key     = $entry.Key
            Action  = $action
            Answers = (ConvertTo-UwhHashtable $sel.Answers)
            Status  = 'offen'
            Message = ''
        })
    }

    [pscustomobject]@{
        Id              = [guid]::NewGuid().ToString('N').Substring(0, 12)
        Created         = (Get-Date).ToString('o')
        Unattended      = $Unattended
        ContinueOnError = $ContinueOnError
        RebootPolicy    = $RebootPolicy
        Index           = 0
        NeedsAdmin      = $needsAdmin
        MayReboot       = $mayReboot
        LogFile         = (Join-Path (Join-Path (Get-UwhStateDir) 'logs') ('uwh-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss')))
        Items           = $items.ToArray()
    }
}

# ------------------------------------------------------------------
# Sammelphase: alle Fragen vorab
# ------------------------------------------------------------------

function Invoke-UwhCollect {
    param($Catalog, $Plan)

    $withPrompts = @($Plan.Items | Where-Object {
        $e = Get-UwhEntry $Catalog $_.Key
        $a = if ($e) { Get-UwhAction $e $_.Action } else { $null }
        $a -and $a.Prompts.Count -gt 0
    })
    if ($withPrompts.Count -eq 0) { return }

    if (-not $Plan.Unattended) {
        Set-UwhWidth
        Clear-Host
        Get-UwhHeader (T 'collect.title') | ForEach-Object { Write-Host $_ }
        Write-Host ''
        Write-Host ('  ' + (T 'collect.after')) -ForegroundColor DarkGray
        Write-Host ''
    }

    foreach ($item in $withPrompts) {
        $entry = Get-UwhEntry $Catalog $item.Key
        $action = Get-UwhAction $entry $item.Action
        $answers = ConvertTo-UwhHashtable $item.Answers

        if (-not $Plan.Unattended) { Write-Host ("  {0}" -f $entry.Name) -ForegroundColor Cyan }

        $fehlend = New-Object System.Collections.Generic.List[string]

        foreach ($p in $action.Prompts) {
            $preset = if ($answers.ContainsKey($p.Variable)) { [string]$answers[$p.Variable] } else { '' }

            if ($Plan.Unattended) {
                if ($preset -eq '') { $preset = $p.Default }
                if ($preset -eq '' -and $p.Type -ne 'yesno') { $fehlend.Add($p.Variable) }
                $answers[$p.Variable] = $preset
            } else {
                $answers[$p.Variable] = Read-UwhAnswer $p $preset
            }
        }

        $item.Answers = $answers

        # Im stillen Lauf gibt es niemanden, der nachtragen koennte. Mit einem
        # Leerwert weiterzumachen hiesse, etwas falsch einzurichten, ohne dass
        # es jemand merkt - also wird der Schritt uebersprungen und gemeldet.
        if ($fehlend.Count -gt 0) {
            $item.Status = 'fehler'
            $item.Message = T 'collect.missing' ($fehlend -join ', ')
            Write-UwhWarn (T 'collect.skipped' $entry.Name $item.Message)
        }
        if (-not $Plan.Unattended) { Write-Host '' }
    }
}

# ------------------------------------------------------------------
# Abarbeiten
# ------------------------------------------------------------------

function Invoke-UwhPlan {
    param($Catalog, $Plan)

    Set-UwhLogFile $Plan.LogFile
    Write-UwhLog 'RUN' ("Lauf {0}, {1} Schritte, ab {2}" -f $Plan.Id, $Plan.Items.Count, $Plan.Index)

    $total = $Plan.Items.Count

    while ($Plan.Index -lt $total) {
        $item = $Plan.Items[$Plan.Index]
        $entry = Get-UwhEntry $Catalog $item.Key

        if (-not $entry) {
            $item.Status = 'fehler'
            $item.Message = T 'run.gone'
            $Plan.Index++
            Save-UwhState $Plan
            continue
        }

        Write-UwhStep ('[{0}/{1}] {2}' -f ($Plan.Index + 1), $total, $entry.Name)

        # In der Sammelphase bereits als unvollstaendig erkannt.
        if ($item.Status -eq 'fehler') {
            Write-UwhErr ("{0} - {1}" -f $entry.Name, $item.Message)
            $Plan.Index++
            Save-UwhState $Plan
            if (-not $Plan.ContinueOnError) { return $false }
            continue
        }

        if ($entry.Note) { Write-Host "  $($entry.Note)" -ForegroundColor DarkGray }

        $result = $null
        try {
            $result = Invoke-UwhProvider $entry $item.Action (ConvertTo-UwhHashtable $item.Answers)
        } catch {
            $result = New-UwhResult 'fehler' $_.Exception.Message
        }

        $item.Status = $result.Status
        $item.Message = $result.Message

        switch ($result.Status) {
            'ok'     { Write-UwhOk   ($entry.Name + $(if ($result.Message) { " - $($result.Message)" } else { '' })) }
            'nichts' { Write-UwhInfo ("{0} - {1}" -f $entry.Name, $result.Message) }
            default  {
                Write-UwhErr ("{0} - {1}" -f $entry.Name, $result.Message)
                if (-not $Plan.ContinueOnError) {
                    $Plan.Index++
                    Save-UwhState $Plan
                    return $false
                }
            }
        }

        $Plan.Index++
        Save-UwhState $Plan

        if ($result.Reboot) {
            if (Invoke-UwhReboot $Plan) { return $true }
        }
    }

    return $true
}

function Invoke-UwhReboot {
    param($Plan)

    if ($Plan.RebootPolicy -eq 'never') {
        Write-UwhWarn (T 'reboot.skipped')
        return $false
    }

    if ($Plan.RebootPolicy -eq 'ask' -and -not $Plan.Unattended) {
        Write-Host ''
        Write-UwhWarn (T 'reboot.needed')
        if (-not (Read-UwhConfirm (T 'reboot.ask') $true)) {
            Write-UwhInfo (T 'reboot.later' $Plan.Id)
            return $true
        }
    }

    if (-not (Register-UwhResume $Plan.Id)) {
        Write-UwhWarn (T 'reboot.noauto' $Plan.Id)
    }

    Write-UwhInfo (T 'reboot.countdown')
    Start-Sleep -Seconds 10
    Restart-Computer -Force
    return $true
}

# ------------------------------------------------------------------
# Fortsetzung nach Neustart
# ------------------------------------------------------------------

function Get-UwhResumeTaskName {
    param([string]$Id)
    "uwh-weiter-$Id"
}

function Register-UwhResume {
    param([string]$Id)

    try {
        # Die Aufgabe laeuft erhoeht und sieht deshalb keine Netzlaufwerke.
        $entry = Resolve-UwhUncPath (Get-UwhPath 'uwh.ps1')
        # Die Sprache reist mit - nach dem Neustart geht es in derselben weiter.
        $argument = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Resume {1} -StateDir "{2}" -Language {3}' -f
                    $entry, $Id, (Resolve-UwhUncPath (Get-UwhStateDir)), (Get-UwhLanguage)

        $action = New-ScheduledTaskAction -Execute (Get-UwhPowerShellExe) -Argument $argument
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                                                -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                                 -DontStopIfGoingOnBatteries `
                                                 -ExecutionTimeLimit ([TimeSpan]::FromHours(4))

        Register-ScheduledTask -TaskName (Get-UwhResumeTaskName $Id) `
                               -Action $action -Trigger $trigger `
                               -Principal $principal -Settings $settings `
                               -Force -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-UwhLog 'WARN' "Aufgabe konnte nicht angelegt werden: $($_.Exception.Message)"
        return $false
    }
}

function Unregister-UwhResume {
    param([string]$Id)
    try {
        Unregister-ScheduledTask -TaskName (Get-UwhResumeTaskName $Id) -Confirm:$false -ErrorAction Stop
    } catch { }
}

# ------------------------------------------------------------------
# Abschluss
# ------------------------------------------------------------------

function Show-UwhReport {
    param($Catalog, $Plan)

    Set-UwhWidth
    $ok    = @($Plan.Items | Where-Object { $_.Status -eq 'ok' })
    $skip  = @($Plan.Items | Where-Object { $_.Status -eq 'nichts' })
    $fail  = @($Plan.Items | Where-Object { $_.Status -eq 'fehler' })
    $open  = @($Plan.Items | Where-Object { $_.Status -eq 'offen' })

    Write-Host ''
    Write-Host (New-UwhRule)
    Write-Host (New-UwhLine ('  ' + (T 'report.done' $ok.Count $skip.Count $fail.Count)))
    if ($open.Count -gt 0) { Write-Host (New-UwhLine ('  ' + (T 'report.open' $open.Count))) }
    Write-Host (New-UwhRule)

    if ($fail.Count -gt 0) {
        Write-Host ''
        Write-Host ('  ' + (T 'report.failed')) -ForegroundColor Yellow
        foreach ($f in $fail) {
            $e = Get-UwhEntry $Catalog $f.Key
            $name = if ($e) { $e.Name } else { $f.Key }
            Write-Host ("    - {0}: {1}" -f $name, $f.Message) -ForegroundColor DarkGray
        }
    }

    Write-Host ''
    Write-Host ('  ' + (T 'report.log' $Plan.LogFile)) -ForegroundColor DarkGray
    Write-Host ''

    if ($fail.Count -gt 0) { return 1 }
    return 0
}
