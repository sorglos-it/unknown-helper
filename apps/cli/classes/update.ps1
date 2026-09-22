# uwh - Selbstaktualisierung ueber ZIP, ohne git

Set-StrictMode -Version 2.0

$script:UwhRepoRaw = 'https://raw.githubusercontent.com/sorglos-it/uwh/main'
$script:UwhRepoZip = 'https://codeload.github.com/sorglos-it/uwh/zip/refs/heads/main'

function Get-UwhLocalVersion {
    $file = Get-UwhPath 'VERSION'
    if (Test-Path -LiteralPath $file) {
        return ConvertTo-UwhVersionText (Get-Content -LiteralPath $file -Raw)
    }
    return '0.0.0'
}

function Get-UwhRemoteVersion {
    Initialize-UwhTls
    try {
        $r = Invoke-WebRequest -Uri "$script:UwhRepoRaw/apps/cli/VERSION" -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        return ConvertTo-UwhVersionText $r.Content
    } catch {
        return $null
    }
}

# Der Inhalt kommt je nach Quelle als Text oder als Bytes, mit oder ohne
# Byte-Reihenfolge-Markierung. Ein unbemerkter BOM wuerde den Versionsvergleich
# scheitern lassen - und damit die Aktualisierung stillschweigend abschalten.
function ConvertTo-UwhVersionText {
    param($Inhalt)

    if ($null -eq $Inhalt) { return '' }
    if ($Inhalt -is [byte[]]) { $Inhalt = [Text.Encoding]::UTF8.GetString($Inhalt) }

    $text = [string]$Inhalt
    $text = $text.TrimStart([char]0xFEFF)
    return $text.Trim()
}

function Test-UwhNewer {
    param([string]$Remote, [string]$Local)
    try {
        return ([version]$Remote -gt [version]$Local)
    } catch {
        return $false
    }
}

# Kopiert den Inhalt von Quelle nach Ziel und laesst das Eigene des Anwenders in
# Ruhe: apps\cli\data (Profile, eigene Repos, Schluessel), config\repo.yaml und\r
# config\settings.yaml (die gewaehlte Sprache).
# Beides ist nie im Archiv - der Schutz greift, falls es doch hineingeraet.
# Skip nimmt Pfade relativ zur Quelle.
#
# Copy-Item -Recurse auf einen VORHANDENEN Zielordner legt ihn verschachtelt
# an ('classes\classes') statt zusammenzufuehren. Deshalb wird hier Datei fuer Datei
# gegangen und jeder Ordner ausdruecklich angelegt.
function Copy-UwhTree {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [string[]]$Skip = @('apps\cli\data', 'apps\cli\config\repo.yaml', 'apps\cli\config\settings.yaml'),
        [string]$Relativ = ''
    )

    if (-not (Test-Path -LiteralPath $Target)) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
    }

    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        $rel = if ($Relativ) { Join-Path $Relativ $item.Name } else { $item.Name }
        if ($Skip -contains $rel) { continue }
        $ziel = Join-Path $Target $item.Name

        if ($item.PSIsContainer) {
            Copy-UwhTree $item.FullName $ziel $Skip $rel
        } else {
            Copy-Item -LiteralPath $item.FullName -Destination $ziel -Force
        }
    }
}

# Liefert $true, wenn aktualisiert wurde und neu gestartet werden soll.
function Update-Uwh {
    param([switch]$Quiet)

    $stamm = Get-UwhProjectRoot
    if (-not $stamm) {
        Write-UwhLog 'INFO' 'uwh liegt nicht in seinem Projektbaum - keine Selbstaktualisierung.'
        return $false
    }

    $local = Get-UwhLocalVersion
    $remote = Get-UwhRemoteVersion
    if (-not $remote) { return $false }
    if (-not (Test-UwhNewer $remote $local)) { return $false }

    if (-not $Quiet) { Write-UwhInfo (T 'update.loading' $remote $local) }

    $tmp = Join-Path $env:TEMP ('uwh-update-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    $zip = "$tmp.zip"

    try {
        Initialize-UwhTls
        Invoke-WebRequest -Uri $script:UwhRepoZip -OutFile $zip -UseBasicParsing -ErrorAction Stop

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)

        $source = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
        if (-not $source) { throw 'Archiv ist leer.' }

        Copy-UwhTree $source.FullName $stamm

        if (-not $Quiet) { Write-UwhOk (T 'update.done' $remote) }
        return $true
    } catch {
        Write-UwhLog 'WARN' "Aktualisierung fehlgeschlagen: $($_.Exception.Message)"
        if (-not $Quiet) { Write-UwhWarn (T 'update.failed') }
        return $false
    } finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
