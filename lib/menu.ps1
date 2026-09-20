# uwh - Menue: Mehrfachauswahl, Abfragen, Zusammenfassung

Set-StrictMode -Version 2.0

$script:UwhWidth = 78
$script:UwhLastHeight = 0

# ------------------------------------------------------------------
# Rahmen zeichnen
# ------------------------------------------------------------------

function New-UwhLine {
    param([string]$Text = '')
    $inner = $script:UwhWidth - 2
    if ($Text.Length -gt $inner) { $Text = $Text.Substring(0, $inner - 1) + '.' }
    return '|' + $Text.PadRight($inner) + '|'
}

function New-UwhRule { '+' + ('=' * ($script:UwhWidth - 2)) + '+' }

function Write-UwhFrame {
    param([string[]]$Lines)

    try {
        $w = [Console]::WindowWidth - 1
        [Console]::SetCursorPosition(0, 0)
        foreach ($l in $Lines) {
            $t = $l
            if ($t.Length -gt $w) { $t = $t.Substring(0, $w) }
            [Console]::Write($t.PadRight($w)); [Console]::Write("`n")
        }
        for ($i = $Lines.Count; $i -lt $script:UwhLastHeight; $i++) {
            [Console]::Write(' ' * $w); [Console]::Write("`n")
        }
        [Console]::SetCursorPosition(0, [Math]::Min($Lines.Count, [Console]::WindowHeight - 1))
        $script:UwhLastHeight = $Lines.Count
    } catch {
        Clear-Host
        $Lines | ForEach-Object { Write-Host $_ }
    }
}

function Get-UwhHeader {
    param([string]$Subtitle)
    $v = if (Get-Variable UwhVersion -Scope Global -ErrorAction SilentlyContinue) { $global:UwhVersion } else { '' }
    $left = '  uwh - unknown windows helper'
    $right = "v$v  "
    $pad = $script:UwhWidth - 2 - $left.Length - $right.Length
    if ($pad -lt 1) { $pad = 1 }

    $out = @((New-UwhRule), (New-UwhLine ($left + (' ' * $pad) + $right)), (New-UwhRule))
    if ($Subtitle) { $out += @((New-UwhLine "  $Subtitle"), (New-UwhRule)) }
    return $out
}

# ------------------------------------------------------------------
# Zeilen der Auswahlliste
# ------------------------------------------------------------------

function Build-UwhRows {
    param($Catalog, [string]$Filter, [hashtable]$Installed)

    $entries = @(Find-UwhEntries $Catalog $Filter)
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($cat in $Catalog.Categories) {
        $inCat = @($entries | Where-Object { $_.Category -eq $cat } | Sort-Object Name)
        if ($inCat.Count -eq 0) { continue }
        $rows.Add([pscustomobject]@{ Kind = 'header'; Text = $cat; Entry = $null })
        foreach ($e in $inCat) {
            $rows.Add([pscustomobject]@{
                Kind      = 'entry'
                Text      = $e.Name
                Entry     = $e
                Installed = [bool]($Installed.Contains($e.Key))
            })
        }
    }
    return $rows.ToArray()
}

function Format-UwhRow {
    param($Row, [bool]$Selected, [bool]$Cursor)

    if ($Row.Kind -eq 'header') { return New-UwhLine ('  ' + $Row.Text.ToUpperInvariant()) }

    $mark = if ($Cursor) { '>' } else { ' ' }
    $box  = if ($Selected) { '[x]' } else { '[ ]' }
    # Breiten sind aufeinander abgestimmt: 2+1+1+3+1+24+1+31+1+11 = 76 = Innenbreite.
    $name = $Row.Entry.Name
    if ($name.Length -gt 24) { $name = $name.Substring(0, 23) + '.' }
    $desc = $Row.Entry.Description
    if ($desc.Length -gt 31) { $desc = $desc.Substring(0, 30) + '.' }
    $state = if ($Row.Installed) { 'installiert' } else { '' }

    $text = '  {0} {1} {2} {3} {4}' -f $mark, $box, $name.PadRight(24), $desc.PadRight(31), $state
    return New-UwhLine $text
}

# ------------------------------------------------------------------
# Hauptmenue: Software auswaehlen
# ------------------------------------------------------------------

function Show-UwhPicker {
    param($Catalog, [hashtable]$Selection, [hashtable]$Installed = @{})

    $filter = ''
    $cursor = 0
    $top = 0

    while ($true) {
        $rows = Build-UwhRows $Catalog $filter $Installed
        $pick = @(0..([Math]::Max($rows.Count - 1, 0)) | Where-Object { $rows.Count -gt 0 -and $rows[$_].Kind -eq 'entry' })

        if ($pick.Count -eq 0) {
            $body = @((New-UwhLine ''), (New-UwhLine '  Nichts gefunden. ESC loescht die Suche.'), (New-UwhLine ''))
        } else {
            if ($cursor -lt 0) { $cursor = 0 }
            if ($cursor -ge $pick.Count) { $cursor = $pick.Count - 1 }

            $height = [Math]::Max(5, [Console]::WindowHeight - 11)
            $cursorRow = $pick[$cursor]
            if ($cursorRow -lt $top) { $top = $cursorRow }
            if ($cursorRow -ge $top + $height) { $top = $cursorRow - $height + 1 }
            if ($top -gt $rows.Count - $height) { $top = [Math]::Max(0, $rows.Count - $height) }
            if ($top -lt 0) { $top = 0 }

            $body = @(New-UwhLine '')
            for ($i = $top; $i -lt [Math]::Min($top + $height, $rows.Count); $i++) {
                $r = $rows[$i]
                $sel = ($r.Kind -eq 'entry') -and $Selection.Contains($r.Entry.Key)
                $body += Format-UwhRow $r $sel ($i -eq $cursorRow)
            }
            $body += New-UwhLine ''
        }

        $sub = if ($filter) { "Suche: $filter" } else { 'Was soll installiert werden?' }
        $count = $Selection.Keys.Count
        $foot = @(
            (New-UwhRule)
            (New-UwhLine ('  Pfeile Bewegen   LEER An/Aus   ENTER Weiter   / Suchen   ESC Beenden'))
            (New-UwhLine ('  A alle an/aus    P Profil laden                     {0} ausgewaehlt' -f $count))
            (New-UwhRule)
        )

        Write-UwhFrame (@(Get-UwhHeader $sub) + $body + $foot)

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'    { $cursor-- }
            'DownArrow'  { $cursor++ }
            'PageUp'     { $cursor -= 5 }
            'PageDown'   { $cursor += 5 }
            'Home'       { $cursor = 0 }
            'End'        { $cursor = $pick.Count - 1 }
            'Spacebar'   {
                if ($pick.Count -gt 0) {
                    $e = $rows[$pick[$cursor]].Entry
                    if ($Selection.Contains($e.Key)) { $Selection.Remove($e.Key) }
                    else { $Selection[$e.Key] = 'install' }
                }
            }
            'Enter'  { if ($Selection.Keys.Count -gt 0) { return 'weiter' } }
            'Escape' { if ($filter) { $filter = ''; $cursor = 0; $top = 0 } else { return 'ende' } }
            default {
                $c = $key.KeyChar
                if ($c -eq '/') {
                    $filter = Read-UwhInline 'Suchen nach'
                    $cursor = 0; $top = 0
                } elseif ($c -eq 'a' -or $c -eq 'A') {
                    $visible = @($rows | Where-Object { $_.Kind -eq 'entry' })
                    $allSet = $true
                    foreach ($r in $visible) { if (-not $Selection.Contains($r.Entry.Key)) { $allSet = $false; break } }
                    foreach ($r in $visible) {
                        if ($allSet) { $Selection.Remove($r.Entry.Key) } else { $Selection[$r.Entry.Key] = 'install' }
                    }
                } elseif ($c -eq 'p' -or $c -eq 'P') {
                    return 'profil'
                }
            }
        }
    }
}

# ------------------------------------------------------------------
# Eingaben
# ------------------------------------------------------------------

function Read-UwhInline {
    param([string]$Label)

    $row = [Math]::Max(0, [Console]::WindowHeight - 2)
    try {
        [Console]::SetCursorPosition(0, $row)
        [Console]::Write((' ' * ([Console]::WindowWidth - 1)))
        [Console]::SetCursorPosition(0, $row)
    } catch { }
    Write-Host "  $Label " -NoNewline -ForegroundColor Cyan
    $value = Read-Host
    $script:UwhLastHeight = 0
    try { Clear-Host } catch { }
    return $value.Trim()
}

function Read-UwhAnswer {
    param($Prompt, [string]$Preset)

    $default = if ($null -ne $Preset -and $Preset -ne '') { $Preset } else { $Prompt.Default }

    while ($true) {
        if ($Prompt.Type -eq 'yesno') {
            $hint = if ($default -match '^(j|ja|y|yes|true)$') { '[J/n]' } else { '[j/N]' }
            Write-Host ("  {0} {1} " -f $Prompt.Question, $hint) -NoNewline
            $in = (Read-Host).Trim()
            if ($in -eq '') { $in = $default }
            if ($in -match '^(j|ja|y|yes|true)$')  { return 'ja' }
            if ($in -match '^(n|nein|no|false)$')  { return 'nein' }
            Write-Host '  Bitte j oder n eingeben.' -ForegroundColor Yellow
            continue
        }

        if ($Prompt.Type -eq 'secret') {
            Write-Host ("  {0} " -f $Prompt.Question) -NoNewline
            $secure = Read-Host -AsSecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        }

        $hint = if ($default) { " [$default]" } else { '' }
        Write-Host ("  {0}{1} " -f $Prompt.Question, $hint) -NoNewline
        $in = (Read-Host).Trim()
        if ($in -eq '') { $in = $default }
        if ($in -ne '') { return $in }
        Write-Host '  Bitte einen Wert eingeben.' -ForegroundColor Yellow
    }
}

function Read-UwhConfirm {
    param([string]$Question, [bool]$Default = $true)

    $hint = if ($Default) { '[J/n]' } else { '[j/N]' }
    while ($true) {
        Write-Host ("  {0} {1} " -f $Question, $hint) -NoNewline
        $in = (Read-Host).Trim()
        if ($in -eq '') { return $Default }
        if ($in -match '^(j|ja|y|yes)$') { return $true }
        if ($in -match '^(n|nein|no)$')  { return $false }
    }
}

# ------------------------------------------------------------------
# Auswahl bestaetigen
# ------------------------------------------------------------------

function Show-UwhSummary {
    param($Catalog, $Plan)

    $script:UwhLastHeight = 0
    Clear-Host

    $lines = Get-UwhHeader 'Das wird jetzt gemacht'
    $lines += New-UwhLine ''

    foreach ($item in $Plan.Items) {
        $entry = Get-UwhEntry $Catalog $item.Key
        $name = if ($entry) { $entry.Name } else { $item.Key }
        $verb = switch ($item.Action) {
            'install'   { 'installieren' }
            'update'    { 'aktualisieren' }
            'uninstall' { 'entfernen' }
            default     { $item.Action }
        }
        $lines += New-UwhLine ('   - {0} {1}' -f $name.PadRight(30), $verb)
    }

    $lines += New-UwhLine ''
    $lines += New-UwhRule
    $lines += New-UwhLine ('  {0} Schritte' -f $Plan.Items.Count)
    if ($Plan.NeedsAdmin)  { $lines += New-UwhLine '  Windows fragt gleich nach Administratorrechten.' }
    if ($Plan.MayReboot)   { $lines += New-UwhLine '  Ein Neustart kann noetig sein - uwh macht danach allein weiter.' }
    $lines += New-UwhRule

    $lines | ForEach-Object { Write-Host $_ }
    Write-Host ''
    return (Read-UwhConfirm 'Jetzt starten?' $true)
}
