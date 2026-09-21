# uwh - Provider: der jeweilige Installationsweg
#
# Jeder Provider liefert ein Ergebnis mit Status, Meldung und Neustart-Bedarf.
# Status: ok | nichts | fehler

Set-StrictMode -Version 2.0

function New-UwhResult {
    param([string]$Status, [string]$Message, [switch]$Reboot)
    [pscustomobject]@{ Status = $Status; Message = $Message; Reboot = [bool]$Reboot }
}

function Invoke-UwhProvider {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)][string]$Action, [hashtable]$Answers = @{})

    switch ($Entry.Provider) {
        'winget'     { return Invoke-UwhWinget     $Entry $Action }
        'msstore'    { return Invoke-UwhWinget     $Entry $Action -Source 'msstore' }
        'feature'    { return Invoke-UwhFeature    $Entry $Action }
        'capability' { return Invoke-UwhCapability $Entry $Action }
        'url'        { return Invoke-UwhUrl        $Entry $Action }
        'psmodule'   { return Invoke-UwhPsModule   $Entry $Action }
        'script'     { return Invoke-UwhScript     $Entry $Action $Answers }
    }
    return New-UwhResult 'fehler' "Unbekannter provider '$($Entry.Provider)'."
}

# ------------------------------------------------------------------
# Hilfsmittel: externes Programm ausfuehren
# ------------------------------------------------------------------


function Show-UwhFailure {
    param([string]$Output)
    if (-not $Output) { return }
    $lines = @($Output -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -Last 8
    foreach ($l in $lines) { Write-Host "        $l" -ForegroundColor DarkGray }
}

# ------------------------------------------------------------------
# winget
# ------------------------------------------------------------------

$script:UwhWingetPath = $null

function Get-UwhWinget {
    if ($script:UwhWingetPath) { return $script:UwhWingetPath }

    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { $script:UwhWingetPath = $cmd.Source; return $script:UwhWingetPath }

    # In erhoehten Sitzungen liegt winget nicht immer im Suchpfad.
    try {
        $pattern = Join-Path $env:ProgramFiles 'WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe\winget.exe'
        $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($found) { $script:UwhWingetPath = $found.FullName; return $script:UwhWingetPath }
    } catch { }

    return $null
}

function Test-UwhWinget { $null -ne (Get-UwhWinget) }

# Neustart-Codes von Windows-Installationsprogrammen. Alles andere wird
# NICHT geraten: winget-Codes aendern sich zwischen Versionen und bedeuten je
# nach Befehl etwas anderes. Deshalb fragen wir hinterher den echten Zustand ab.
$script:UwhRebootCodes = @(3010, 1641)

# Ist das Paket laut winget installiert?
function Test-UwhWingetPresent {
    param([string]$Id, [string]$Source = 'winget')
    $exe = Get-UwhWinget
    if (-not $exe) { return $false }
    $r = Invoke-UwhExe $exe @('list', '--id', $Id, '--exact', '--source', $Source,
                              '--accept-source-agreements', '--disable-interactivity')
    return ($r.Code -eq 0)
}

function Invoke-UwhWinget {
    param($Entry, [string]$Action, [string]$Source = 'winget')

    $exe = Get-UwhWinget
    if (-not $exe) {
        return New-UwhResult 'fehler' 'winget fehlt. Bitte "App Installer" aus dem Microsoft Store installieren.'
    }

    $common = @(
        '--id', $Entry.Id, '--exact',
        '--source', $Source,
        '--accept-source-agreements',
        '--disable-interactivity',
        '--silent'
    )

    switch ($Action) {
        'install' {
            $cmd = @('install') + $common + @('--accept-package-agreements')
            if ($Entry.Scope -eq 'machine') { $cmd += @('--scope', 'machine') }
            $r = Invoke-UwhExe $exe $cmd

            # Manche Pakete gibt es nur fuer den angemeldeten Benutzer.
            # Deshalb bei jedem Fehlschlag einmal ohne Bereichsangabe nachfassen.
            if ($r.Code -ne 0 -and $Entry.Scope -eq 'machine') {
                Write-UwhLog 'INFO' "$($Entry.Id): zweiter Versuch ohne --scope machine."
                $zweiter = Invoke-UwhExe $exe (@('install') + $common + @('--accept-package-agreements'))
                if ($zweiter.Code -eq 0 -or $zweiter.Code -in $script:UwhRebootCodes) { $r = $zweiter }
            }

            if ($r.Code -eq 0) { return New-UwhResult 'ok' '' }
            if ($r.Code -in $script:UwhRebootCodes) { return New-UwhResult 'ok' 'Neustart noetig' -Reboot }
            if (Test-UwhWingetPresent $Entry.Id $Source) { return New-UwhResult 'nichts' 'Bereits installiert' }
            return New-UwhResult 'fehler' (Get-UwhWingetFehler $r)
        }

        'update' {
            $r = Invoke-UwhExe $exe (@('upgrade') + $common + @('--accept-package-agreements'))

            if ($r.Code -eq 0) { return New-UwhResult 'ok' '' }
            if ($r.Code -in $script:UwhRebootCodes) { return New-UwhResult 'ok' 'Neustart noetig' -Reboot }
            # Steht es noch da, war schlicht nichts zu tun.
            if (Test-UwhWingetPresent $Entry.Id $Source) { return New-UwhResult 'nichts' 'Bereits aktuell' }
            return New-UwhResult 'fehler' (Get-UwhWingetFehler $r)
        }

        'uninstall' {
            $r = Invoke-UwhExe $exe (@('uninstall') + $common)

            if ($r.Code -eq 0) { return New-UwhResult 'ok' '' }
            if ($r.Code -in $script:UwhRebootCodes) { return New-UwhResult 'ok' 'Neustart noetig' -Reboot }
            if (-not (Test-UwhWingetPresent $Entry.Id $Source)) { return New-UwhResult 'nichts' 'Nicht installiert' }
            return New-UwhResult 'fehler' (Get-UwhWingetFehler $r)
        }
    }

    return New-UwhResult 'fehler' "Aktion '$Action' kennt winget nicht."
}

# Klartext von winget mitnehmen - eine nackte Zahl hilft niemandem weiter.
function Get-UwhWingetFehler {
    param($Run)
    $zeilen = @($Run.Output -split "`r?`n" | ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and $_ -notmatch '^[-\|/ ]+$' })
    $letzte = if ($zeilen.Count -gt 0) { $zeilen[-1] } else { '' }
    if ($letzte.Length -gt 90) { $letzte = $letzte.Substring(0, 89) + '.' }
    if ($letzte) { return ("{0} (Code {1})" -f $letzte, $Run.Code) }
    return ("winget meldet Code {0}" -f $Run.Code)
}

# Einmalig alle installierten Pakete ermitteln, damit das Menue den Stand zeigt.
$script:UwhInstalledIds = $null

function Get-UwhInstalledIds {
    if ($null -ne $script:UwhInstalledIds) { return $script:UwhInstalledIds }
    $script:UwhInstalledIds = @{}

    $exe = Get-UwhWinget
    if (-not $exe) { return $script:UwhInstalledIds }

    $tmp = Join-Path $env:TEMP ('uwh-export-{0}.json' -f [guid]::NewGuid())
    try {
        $null = Invoke-UwhExe $exe @('export', '-o', $tmp, '--accept-source-agreements', '--disable-interactivity')
        if (Test-Path -LiteralPath $tmp) {
            $data = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($src in @($data.Sources)) {
                foreach ($pkg in @($src.Packages)) {
                    if ($pkg.PackageIdentifier) { $script:UwhInstalledIds[$pkg.PackageIdentifier] = $true }
                }
            }
        }
    } catch {
        Write-UwhLog 'WARN' "Bestandsaufnahme fehlgeschlagen: $($_.Exception.Message)"
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    return $script:UwhInstalledIds
}

function Test-UwhEntryInstalled {
    param($Entry)

    switch ($Entry.Provider) {
        { $_ -in @('winget', 'msstore') } {
            return (Get-UwhInstalledIds).ContainsKey($Entry.Id)
        }
        'feature' {
            try {
                $f = Get-WindowsOptionalFeature -Online -FeatureName $Entry.Id -ErrorAction Stop
                return ($f.State -eq 'Enabled')
            } catch { return $false }
        }
        'capability' {
            try {
                $c = Get-WindowsCapability -Online -Name $Entry.Id -ErrorAction Stop
                return ($c.State -eq 'Installed')
            } catch { return $false }
        }
        'psmodule' {
            return ($null -ne (Get-Module -ListAvailable -Name $Entry.Id -ErrorAction SilentlyContinue))
        }
    }
    return $false
}

# ------------------------------------------------------------------
# Windows-Funktionen
# ------------------------------------------------------------------

function Invoke-UwhFeature {
    param($Entry, [string]$Action)

    try {
        if ($Action -eq 'install') {
            $state = Get-WindowsOptionalFeature -Online -FeatureName $Entry.Id -ErrorAction Stop
            if ($state.State -eq 'Enabled') { return New-UwhResult 'nichts' 'Bereits aktiv' }
            $r = Enable-WindowsOptionalFeature -Online -FeatureName $Entry.Id -All -NoRestart -ErrorAction Stop
        } elseif ($Action -eq 'uninstall') {
            $state = Get-WindowsOptionalFeature -Online -FeatureName $Entry.Id -ErrorAction Stop
            if ($state.State -ne 'Enabled') { return New-UwhResult 'nichts' 'Nicht aktiv' }
            $r = Disable-WindowsOptionalFeature -Online -FeatureName $Entry.Id -NoRestart -ErrorAction Stop
        } else {
            return New-UwhResult 'fehler' "Aktion '$Action' gibt es fuer Windows-Funktionen nicht."
        }

        if ($r.RestartNeeded) { return New-UwhResult 'ok' 'Neustart noetig' -Reboot }
        return New-UwhResult 'ok' ''
    } catch {
        return New-UwhResult 'fehler' $_.Exception.Message
    }
}

function Invoke-UwhCapability {
    param($Entry, [string]$Action)

    try {
        $state = Get-WindowsCapability -Online -Name $Entry.Id -ErrorAction Stop
        if ($Action -eq 'install') {
            if ($state.State -eq 'Installed') { return New-UwhResult 'nichts' 'Bereits vorhanden' }
            $r = Add-WindowsCapability -Online -Name $Entry.Id -ErrorAction Stop
        } elseif ($Action -eq 'uninstall') {
            if ($state.State -ne 'Installed') { return New-UwhResult 'nichts' 'Nicht vorhanden' }
            $r = Remove-WindowsCapability -Online -Name $Entry.Id -ErrorAction Stop
        } else {
            return New-UwhResult 'fehler' "Aktion '$Action' gibt es hier nicht."
        }

        if ($r -and $r.RestartNeeded) { return New-UwhResult 'ok' 'Neustart noetig' -Reboot }
        return New-UwhResult 'ok' ''
    } catch {
        return New-UwhResult 'fehler' $_.Exception.Message
    }
}

# ------------------------------------------------------------------
# Direkter Download
# ------------------------------------------------------------------

function Invoke-UwhUrl {
    param($Entry, [string]$Action)

    if ($Action -ne 'install') { return New-UwhResult 'fehler' "Aktion '$Action' gibt es hier nicht." }
    if (-not (Test-UwhHttpsUrl $Entry.Url)) { return New-UwhResult 'fehler' 'Kein gueltiger https-Link.' }

    Initialize-UwhTls
    $ext = [IO.Path]::GetExtension(([uri]$Entry.Url).AbsolutePath)
    if ($ext -notin @('.exe', '.msi')) { $ext = '.exe' }
    $target = Join-Path $env:TEMP ('uwh-{0}{1}' -f [guid]::NewGuid(), $ext)

    try {
        Invoke-WebRequest -Uri $Entry.Url -OutFile $target -UseBasicParsing -ErrorAction Stop

        if ($Entry.Sha256) {
            $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            if ($hash -ne $Entry.Sha256.ToUpperInvariant()) {
                return New-UwhResult 'fehler' 'Pruefsumme stimmt nicht. Download verworfen.'
            }
        } else {
            Write-UwhLog 'WARN' "$($Entry.Key): ohne sha256 geladen."
        }

        $silent = $Entry.SilentArgs
        if (-not $silent) { if ($ext -eq '.msi') { $silent = '/qn /norestart' } else { $silent = '/S' } }

        if ($ext -eq '.msi') {
            $r = Invoke-UwhExe 'msiexec.exe' (@('/i', $target) + ($silent -split ' +' | Where-Object { $_ }))
        } else {
            $r = Invoke-UwhExe $target (@($silent -split ' +' | Where-Object { $_ }))
        }

        if ($r.Code -eq 0) { return New-UwhResult 'ok' '' }
        if ($r.Code -eq 3010 -or $r.Code -eq 1641) { return New-UwhResult 'ok' 'Neustart noetig' -Reboot }
        return New-UwhResult 'fehler' ("Installationsprogramm meldet Code {0}" -f $r.Code)
    } catch {
        return New-UwhResult 'fehler' $_.Exception.Message
    } finally {
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------------
# PowerShell-Module
# ------------------------------------------------------------------

function Invoke-UwhPsModule {
    param($Entry, [string]$Action)

    Initialize-UwhTls
    try {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -Force -Scope AllUsers -ErrorAction Stop | Out-Null
        }
    } catch {
        return New-UwhResult 'fehler' "NuGet-Anbieter fehlt: $($_.Exception.Message)"
    }

    $scope = if ($Entry.Scope -eq 'user') { 'CurrentUser' } else { 'AllUsers' }
    try {
        switch ($Action) {
            'install' {
                if (Get-Module -ListAvailable -Name $Entry.Id) { return New-UwhResult 'nichts' 'Bereits vorhanden' }
                Install-Module -Name $Entry.Id -Scope $scope -Force -AcceptLicense -AllowClobber -ErrorAction Stop
            }
            'update'    { Update-Module -Name $Entry.Id -Force -ErrorAction Stop }
            'uninstall' { Uninstall-Module -Name $Entry.Id -AllVersions -Force -ErrorAction Stop }
            default     { return New-UwhResult 'fehler' "Aktion '$Action' gibt es hier nicht." }
        }
        return New-UwhResult 'ok' ''
    } catch {
        return New-UwhResult 'fehler' $_.Exception.Message
    }
}

# ------------------------------------------------------------------
# Eigene Skripte
# ------------------------------------------------------------------

function Invoke-UwhScript {
    param($Entry, [string]$Action, [hashtable]$Answers)

    $path = Join-Path (Join-Path $Entry.BaseDir 'scripts') $Entry.File
    if (-not (Test-Path -LiteralPath $path)) {
        return New-UwhResult 'fehler' "Skript nicht gefunden: $($Entry.File)"
    }

    # Eigene Skripte laufen in einem eigenen Prozess. Sonst koennte ein fremdes
    # Skript uwh-Funktionen ueberschreiben oder die Sitzung durcheinanderbringen.
    # Antworten werden ueber die Umgebung vererbt.
    $saved = @{}
    try {
        foreach ($k in $Answers.Keys) {
            $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
            [Environment]::SetEnvironmentVariable($k, [string]$Answers[$k], 'Process')
        }

        $r = Invoke-UwhExe (Get-UwhPowerShellExe) @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', (Resolve-UwhUncPath $path),
            '-Action', $Action
        )

        if ($r.Code -eq 0 -or $r.Code -eq 3010) {
            # Gelungen: zeigen, was das Skript gesagt hat.
            Show-UwhSkriptAusgabe $r.Output
            if ($r.Code -eq 3010) { return New-UwhResult 'ok' 'Neustart noetig' -Reboot }
            return New-UwhResult 'ok' ''
        }

        # Schiefgegangen: nur die eine Zeile, die zaehlt. Die Fehlerlawine
        # von PowerShell steht im Protokoll, nicht auf dem Bildschirm.
        return New-UwhResult 'fehler' (Get-UwhSkriptFehler $r)
    } catch {
        return New-UwhResult 'fehler' $_.Exception.Message
    } finally {
        foreach ($k in $saved.Keys) {
            [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process')
        }
    }
}

function Show-UwhSkriptAusgabe {
    param([string]$Output)
    if (-not $Output) { return }
    foreach ($z in ($Output -split "`r?`n")) {
        $t = $z.TrimEnd()
        if ($t) { Write-Host $t -ForegroundColor DarkGray }
    }
}

# Aus der Fehlerlawine von PowerShell die eine verstaendliche Zeile holen.
function Get-UwhSkriptFehler {
    param($Run)

    $zeilen = @($Run.Output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -and
        $_ -notmatch '^(At |In |\+|~)' -and
        $_ -notmatch '^(CategoryInfo|FullyQualifiedErrorId)'
    })
    if ($zeilen.Count -eq 0) { return ("Skript meldet Code {0}" -f $Run.Code) }

    # 'powershell.exe : C:\pfad\zum\skript.ps1 : Die eigentliche Meldung'
    $text = $zeilen[0]
    $text = $text -replace '^powershell\.exe\s*:\s*', ''
    $text = $text -replace '^.*\.ps1\s*:\s*', ''
    $text = $text.Trim()
    if (-not $text) { return ("Skript meldet Code {0}" -f $Run.Code) }
    if ($text.Length -gt 90) { $text = $text.Substring(0, 89) + '.' }

    return ("{0} (Code {1})" -f $text, $Run.Code)
}
