# uwh - Kern: Ausgabe, Rechte, Pfade, Protokoll
# Wird von allen anderen Bibliotheken zuerst geladen.

Set-StrictMode -Version 2.0

# ------------------------------------------------------------------
# Pfade
# ------------------------------------------------------------------

function Get-UwhRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-UwhPath {
    param([Parameter(Mandatory)][string]$Relative)
    Join-Path (Get-UwhRoot) $Relative
}

# Der Projektstamm liegt zwei Ebenen ueber dem Programm: <stamm>\apps\cli.
# Ist uwh nicht so eingebettet - jemand hat nur apps\cli woandershin kopiert -,
# kommt nichts zurueck. Die Selbstaktualisierung schreibt dann nirgendwohin,
# statt den ganzen Projektbaum in einen fremden Ordner zu kippen.
function Get-UwhProjectRoot {
    $programm = Get-UwhRoot
    $apps = Split-Path -Parent $programm
    if ((Split-Path -Leaf $programm) -ne 'cli' -or (Split-Path -Leaf $apps) -ne 'apps') { return $null }
    return (Split-Path -Parent $apps)
}

# ------------------------------------------------------------------
# Ausgabe
# ------------------------------------------------------------------

$script:UwhLogFile = $null

function Set-UwhLogFile {
    param([string]$Path)
    $script:UwhLogFile = $Path
    if ($Path) {
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
}

function Write-UwhLog {
    param([string]$Level, [string]$Message)
    if (-not $script:UwhLogFile) { return }
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $script:UwhLogFile -Value $line -Encoding UTF8 } catch { }
}

# Die Plakette vor einer Meldung. Alle einer Sprache sind gleich breit - so
# breit wie die laengste, denn nicht jede Sprache kommt mit vier Buchstaben aus.
function Format-UwhBadge {
    param([string]$Key)
    $breite = 4
    foreach ($k in @('badge.ok', 'badge.info', 'badge.warn', 'badge.err')) {
        $breite = [Math]::Max($breite, (T $k).Length)
    }
    $text = T $Key
    $links = [int][Math]::Floor(($breite - $text.Length) / 2)
    return ' ' + (' ' * $links) + $text + (' ' * ($breite - $text.Length - $links)) + ' '
}

function Write-UwhOk {
    param([string]$Message)
    Write-Host (Format-UwhBadge 'badge.ok') -NoNewline -ForegroundColor Black -BackgroundColor DarkGreen
    Write-Host " $Message"
    Write-UwhLog 'OK' $Message
}

function Write-UwhInfo {
    param([string]$Message)
    Write-Host (Format-UwhBadge 'badge.info') -NoNewline -ForegroundColor Black -BackgroundColor DarkCyan
    Write-Host " $Message"
    Write-UwhLog 'INFO' $Message
}

function Write-UwhWarn {
    param([string]$Message)
    Write-Host (Format-UwhBadge 'badge.warn') -NoNewline -ForegroundColor Black -BackgroundColor DarkYellow
    Write-Host " $Message" -ForegroundColor Yellow
    Write-UwhLog 'WARN' $Message
}

function Write-UwhErr {
    param([string]$Message)
    Write-Host (Format-UwhBadge 'badge.err') -NoNewline -ForegroundColor White -BackgroundColor DarkRed
    Write-Host " $Message" -ForegroundColor Red
    Write-UwhLog 'ERROR' $Message
}

function Write-UwhStep {
    param([string]$Message)
    Write-Host ''
    Write-Host "> $Message" -ForegroundColor Cyan
    Write-UwhLog 'STEP' $Message
}

# ------------------------------------------------------------------
# Fremdprogramme ausfuehren
# ------------------------------------------------------------------

function Invoke-UwhExe {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string[]]$Arguments)

    # Zugangsdaten in Adressen (https://nutzer:kennwort@...) nie ins Protokoll.
    $sichtbar = @($Arguments | ForEach-Object { [string]$_ -replace '(://)[^/@\s]+@', '$1***@' })
    Write-UwhLog 'CMD' ("{0} {1}" -f $Exe, ($sichtbar -join ' '))

    # Fremdprogramme schreiben Warnungen nach stderr. Steht der Aufrufer auf
    # 'Stop', wuerde daraus eine Ausnahme statt eines auswertbaren Ergebnisses.
    # Die Zuweisung gilt nur in dieser Funktion.
    $ErrorActionPreference = 'Continue'

    $output = & $Exe @Arguments 2>&1
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }

    $text = ($output | Out-String)
    if ($text.Trim()) { Write-UwhLog 'OUT' $text.Trim() }

    [pscustomobject]@{ Code = $code; Output = $text }
}

# ------------------------------------------------------------------
# Rechte
# ------------------------------------------------------------------

function Test-UwhAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Ein erhoehter Prozess sieht zugeordnete Netzlaufwerke NICHT - die Zuordnung
# haengt an der Anmeldesitzung, und der Administrator-Token ist eine andere.
# Darum vor dem Start alles auf den UNC-Pfad umstellen.
function Resolve-UwhUncPath {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -match '^\\\\') { return $Path }
    if ($Path -notmatch '^([A-Za-z]):') { return $Path }

    $letter = $Matches[1]
    try {
        $drive = Get-PSDrive -Name $letter -ErrorAction Stop
        if (-not $drive.DisplayRoot) { return $Path }

        # DisplayRoot kommt je nach System mit Null-Zeichen aufgefuellt.
        $root = ([string]$drive.DisplayRoot).Trim([char]0).Trim()
        if (-not $root) { return $Path }

        return $root + $Path.Substring(2)
    } catch {
        return $Path
    }
}

function Test-UwhOnNetworkDrive {
    $root = Get-UwhRoot
    if ($root -match '^\\\\') { return $true }
    return ((Resolve-UwhUncPath $root) -ne $root)
}

# Startet uwh erhoeht neu und liefert den Exit-Code des Kindprozesses.
function Invoke-UwhElevated {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $entry = Resolve-UwhUncPath (Get-UwhPath 'uwh.ps1')
    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', ('"{0}"' -f $entry)
    ) + $Arguments

    $proc = Start-Process -FilePath (Get-UwhPowerShellExe) `
                          -ArgumentList $argList `
                          -Verb RunAs -PassThru -Wait -ErrorAction Stop
    return $proc.ExitCode
}

function Get-UwhPowerShellExe {
    Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
}

# ------------------------------------------------------------------
# Sicherheit: Eingaben pruefen
# ------------------------------------------------------------------

# Paket-Kennungen duerfen nur harmlose Zeichen enthalten. Verhindert,
# dass Katalogdaten als zusaetzliche Kommandozeilen-Argumente wirken.
function Test-UwhSafeId {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match '^[A-Za-z0-9][A-Za-z0-9._~+\-]*$')
}

# Dateinamen fuer Profile: kein Pfadwechsel, keine Sonderzeichen.
function Test-UwhSafeName {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match '^[A-Za-z0-9][A-Za-z0-9 _\-]{0,63}$')
}

function Test-UwhHttpsUrl {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match '^https://[A-Za-z0-9.\-]+(/|$)')
}

# ------------------------------------------------------------------
# Antworten auf der Platte schuetzen
# ------------------------------------------------------------------
#
# Ein unterbrochener Lauf muss die gesammelten Antworten ueberstehen, also
# liegen sie in der Zustandsdatei. Sie sind mit dem Windows-Datenschutz
# verschluesselt: lesen kann sie nur derselbe Benutzer auf demselben Rechner.
# Ein Kennwort liegt damit nicht im Klartext herum, auch wenn ein Lauf
# abgebrochen wird und die Datei stehenbleibt.

function Protect-UwhText {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    try {
        $sicher = ConvertTo-SecureString -String $Text -AsPlainText -Force
        return 'dpapi:' + (ConvertFrom-SecureString -SecureString $sicher)
    } catch {
        # Ohne Verschluesselung lieber gar nichts speichern als im Klartext.
        Write-UwhLog 'WARN' "Antwort konnte nicht geschuetzt werden: $($_.Exception.Message)"
        return ''
    }
}

function Unprotect-UwhText {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    if (-not $Text.StartsWith('dpapi:')) { return $Text }

    $bstr = [IntPtr]::Zero
    try {
        $sicher = ConvertTo-SecureString -String $Text.Substring(6) -ErrorAction Stop
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sicher)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } catch {
        # Anderer Benutzer oder anderer Rechner - die Antwort ist verloren.
        Write-UwhLog 'WARN' 'Eine gespeicherte Antwort konnte nicht gelesen werden.'
        return ''
    } finally {
        if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}

# ------------------------------------------------------------------
# Netzwerk
# ------------------------------------------------------------------

# Windows PowerShell 5.1 nutzt ohne Zutun teils veraltete Protokolle.
function Initialize-UwhTls {
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
    } catch { }
}

# ------------------------------------------------------------------
# Werkzeuge
# ------------------------------------------------------------------

function Test-UwhCommand {
    param([Parameter(Mandatory)][string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-UwhOsInfo {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Caption = if ($os) { $os.Caption } else { 'Windows' }
        Build   = [System.Environment]::OSVersion.Version.Build
        Arch    = $env:PROCESSOR_ARCHITECTURE
    }
}

function Initialize-UwhConsole {
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    try { $Host.UI.RawUI.WindowTitle = 'uwh - unknown windows helper' } catch { }
}
