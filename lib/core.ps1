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

function Write-UwhOk {
    param([string]$Message)
    Write-Host '  OK  ' -NoNewline -ForegroundColor Black -BackgroundColor DarkGreen
    Write-Host " $Message"
    Write-UwhLog 'OK' $Message
}

function Write-UwhInfo {
    param([string]$Message)
    Write-Host ' INFO ' -NoNewline -ForegroundColor Black -BackgroundColor DarkCyan
    Write-Host " $Message"
    Write-UwhLog 'INFO' $Message
}

function Write-UwhWarn {
    param([string]$Message)
    Write-Host ' ACHT ' -NoNewline -ForegroundColor Black -BackgroundColor DarkYellow
    Write-Host " $Message" -ForegroundColor Yellow
    Write-UwhLog 'WARN' $Message
}

function Write-UwhErr {
    param([string]$Message)
    Write-Host ' FEHL ' -NoNewline -ForegroundColor White -BackgroundColor DarkRed
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
# Rechte
# ------------------------------------------------------------------

function Test-UwhAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Startet uwh erhoeht neu und liefert den Exit-Code des Kindprozesses.
function Invoke-UwhElevated {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $entry = Get-UwhPath 'uwh.ps1'
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
