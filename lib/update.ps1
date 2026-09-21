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
        $r = Invoke-WebRequest -Uri "$script:UwhRepoRaw/VERSION" -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
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

# Kopiert den Inhalt von Quelle nach Ziel und laesst 'profiles' in Ruhe -
# das sind die Profile des Anwenders, eine Aktualisierung darf sie nie anfassen.
#
# Copy-Item -Recurse auf einen VORHANDENEN Zielordner legt ihn verschachtelt
# an ('lib\lib') statt zusammenzufuehren. Deshalb wird hier Datei fuer Datei
# gegangen und jeder Ordner ausdruecklich angelegt.
function Copy-UwhTree {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [string[]]$Skip = @('profiles')
    )

    if (-not (Test-Path -LiteralPath $Target)) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
    }

    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($Skip -contains $item.Name) { continue }
        $ziel = Join-Path $Target $item.Name

        if ($item.PSIsContainer) {
            Copy-UwhTree $item.FullName $ziel @()
        } else {
            Copy-Item -LiteralPath $item.FullName -Destination $ziel -Force
        }
    }
}

# Liefert $true, wenn aktualisiert wurde und neu gestartet werden soll.
function Update-Uwh {
    param([switch]$Quiet)

    $local = Get-UwhLocalVersion
    $remote = Get-UwhRemoteVersion
    if (-not $remote) { return $false }
    if (-not (Test-UwhNewer $remote $local)) { return $false }

    if (-not $Quiet) { Write-UwhInfo "Neue Version $remote wird geladen (aktuell $local)..." }

    $tmp = Join-Path $env:TEMP ('uwh-update-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    $zip = "$tmp.zip"

    try {
        Initialize-UwhTls
        Invoke-WebRequest -Uri $script:UwhRepoZip -OutFile $zip -UseBasicParsing -ErrorAction Stop

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)

        $source = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
        if (-not $source) { throw 'Archiv ist leer.' }

        Copy-UwhTree $source.FullName (Get-UwhRoot)

        if (-not $Quiet) { Write-UwhOk "Auf Version $remote aktualisiert." }
        return $true
    } catch {
        Write-UwhLog 'WARN' "Aktualisierung fehlgeschlagen: $($_.Exception.Message)"
        if (-not $Quiet) { Write-UwhWarn 'Aktualisierung fehlgeschlagen - es geht mit der vorhandenen Version weiter.' }
        return $false
    } finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
