# uwh - Selbstaktualisierung ueber ZIP, ohne git

Set-StrictMode -Version 2.0

$script:UwhRepoRaw = 'https://raw.githubusercontent.com/sorglos-it/uwh/main'
$script:UwhRepoZip = 'https://codeload.github.com/sorglos-it/uwh/zip/refs/heads/main'

function Get-UwhLocalVersion {
    $file = Get-UwhPath 'VERSION'
    if (Test-Path -LiteralPath $file) { return (Get-Content -LiteralPath $file -Raw).Trim() }
    return '0.0.0'
}

function Get-UwhRemoteVersion {
    Initialize-UwhTls
    try {
        $r = Invoke-WebRequest -Uri "$script:UwhRepoRaw/VERSION" -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        return ([string]$r.Content).Trim()
    } catch {
        return $null
    }
}

function Test-UwhNewer {
    param([string]$Remote, [string]$Local)
    try {
        return ([version]$Remote -gt [version]$Local)
    } catch {
        return $false
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

        $root = Get-UwhRoot
        foreach ($item in Get-ChildItem -LiteralPath $source.FullName) {
            # 'custom' gehoert dem Anwender und bleibt unangetastet.
            if ($item.Name -eq 'custom') { continue }
            $target = Join-Path $root $item.Name
            if ($item.PSIsContainer) {
                Copy-Item -LiteralPath $item.FullName -Destination $root -Recurse -Force
            } else {
                Copy-Item -LiteralPath $item.FullName -Destination $target -Force
            }
        }

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
