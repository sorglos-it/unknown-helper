<#
    uwh bauen: erst alle Pruefungen ohne Internet, dann das Archiv fuer ein Release.

        powershell -ExecutionPolicy Bypass -File tools\uwh\build.ps1

    Ergebnis: dist\uwh-<version>.zip - der Stand des letzten Commits, maximal
    komprimiert, oben ein Ordner uwh-<version>\ wie im Archiv von GitHub. Damit
    geht es auch als Quelle fuer eine Einrichtung ohne Internet:
        .\tools\install.ps1 -Quelle dist\uwh-<version>.zip

    Die Pruefung der Paketkennungen braucht Internet und laeuft extra:
        powershell -ExecutionPolicy Bypass -File apps\cli-uwh\tests\online.tests.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$stamm = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cli = Join-Path $stamm 'apps\cli-uwh'
$version = (Get-Content -LiteralPath (Join-Path $cli 'VERSION') -Raw).Trim()
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

Write-Host ''
Write-Host "  uwh $version bauen" -ForegroundColor Cyan
Write-Host ''

# ------------------------------------------------------------------
# Pruefen - in Windows PowerShell 5.1, wie beim Anwender
# ------------------------------------------------------------------

$fehler = 0
$tests = Get-ChildItem -LiteralPath (Join-Path $cli 'tests') -Filter '*.tests.ps1' |
         Where-Object { $_.Name -ne 'online.tests.ps1' }
foreach ($t in $tests) {
    $aus = & $ps51 -NoProfile -ExecutionPolicy Bypass -File $t.FullName 2>&1 | Out-String
    $gut = $LASTEXITCODE -eq 0
    if (-not $gut) { $fehler++ }
    $zeilen = @($aus -split "`r?`n")
    $summe = @($zeilen | Where-Object { $_ -match '\d+ bestanden, \d+ fehlgeschlagen' }) | Select-Object -Last 1
    Write-Host ('  {0,-12} {1}' -f ($t.Name -replace '\.tests\.ps1$'), ([string]$summe).Trim()) `
        -ForegroundColor $(if ($gut) { 'Green' } else { 'Red' })
    if (-not $gut) {
        for ($i = 0; $i -lt $zeilen.Count; $i++) {
            if ($zeilen[$i] -match '^\s+FEHL\s{2}\S') { Write-Host $zeilen[$i]; Write-Host $zeilen[$i + 1] -ForegroundColor DarkGray }
        }
    }
}
if ($fehler -gt 0) {
    Write-Host ''
    Write-Host "  $fehler Pruefung(en) fehlgeschlagen - kein Archiv." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------------
# Archiv aus dem letzten Commit
# ------------------------------------------------------------------

$offen = @(& git -C $stamm status --porcelain --untracked-files=no)
if ($offen.Count -gt 0) {
    Write-Host ''
    Write-Host '  Achtung: nicht committete Aenderungen kommen nicht ins Archiv.' -ForegroundColor Yellow
}

$dist = Join-Path $stamm 'dist'
if (-not (Test-Path -LiteralPath $dist)) { New-Item -ItemType Directory -Path $dist | Out-Null }
$ziel = Join-Path $dist "uwh-$version.zip"
$tmp = Join-Path $env:TEMP ('uwh-build-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
    # git archive schreibt die Zeilenenden wie im Arbeitsbaum (.gitattributes):
    # uwh.cmd und die Skripte behalten CRLF.
    $tar = Join-Path $tmp 'uwh.tar'
    & git -C $stamm archive --format=tar --prefix="uwh-$version/" -o $tar HEAD
    if ($LASTEXITCODE -ne 0) { throw 'git archive ist fehlgeschlagen.' }
    & tar.exe -xf $tar -C $tmp
    if ($LASTEXITCODE -ne 0) { throw 'Das Auspacken ist fehlgeschlagen.' }
    Remove-Item -LiteralPath $tar

    $ordner = Join-Path $tmp "uwh-$version"
    $drin = (Get-Content -LiteralPath (Join-Path $ordner 'apps\cli-uwh\VERSION') -Raw).Trim()
    if ($drin -ne $version) { throw "VERSION $version ist noch nicht committet (im Commit steht $drin)." }

    if (Test-Path -LiteralPath $ziel) { Remove-Item -LiteralPath $ziel }
    $7z = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
    if (Test-Path -LiteralPath $7z) {
        # Zip mit allen Durchlaeufen von 7-Zip: kleiner als ein normales Zip und
        # trotzdem mit jedem Windows ohne Zusatzprogramm zu oeffnen.
        & $7z a -tzip -mx=9 -mfb=258 -mpass=15 $ziel $ordner | Out-Null
        if ($LASTEXITCODE -ne 0) { throw '7-Zip ist fehlgeschlagen.' }
    } else {
        Compress-Archive -Path $ordner -DestinationPath $ziel -CompressionLevel Optimal
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$groesse = (Get-Item -LiteralPath $ziel).Length
Write-Host ''
Write-Host ('  {0}  ({1:N0} KB)' -f $ziel, ($groesse / 1KB)) -ForegroundColor Green
Write-Host ''
exit 0
