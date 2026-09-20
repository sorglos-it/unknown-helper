# uwh - Menue: Mehrfachauswahl, Abfragen, Zusammenfassung

Set-StrictMode -Version 2.0

$script:UwhWidth = 78
$script:UwhLastHeight = 0

# Die drei Betriebsarten des Menues, in dieser Reihenfolge durchgeschaltet.
$script:UwhModi = @(
    [pscustomobject]@{ Name = 'install';   Titel = 'Installieren'; Frage = 'Was soll installiert werden?' }
    [pscustomobject]@{ Name = 'update';    Titel = 'Aktualisieren'; Frage = 'Was soll aktualisiert werden?' }
    [pscustomobject]@{ Name = 'uninstall'; Titel = 'Entfernen';     Frage = 'Was soll entfernt werden?' }
)

function Get-UwhModus {
    param([int]$Nummer)
    $script:UwhModi[$Nummer % $script:UwhModi.Count]
}

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
    param($Catalog, [string]$Filter, [hashtable]$Installed, [string]$Action = 'install')

    # Was die Aktion nicht kann, wird gar nicht erst angeboten.
    $entries = @(Find-UwhEntries $Catalog $Filter |
                 Where-Object { @($_.Actions | ForEach-Object { $_.Name }) -contains $Action })
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

# Die Zeilennummern, auf denen der Cursor stehen darf - Ueberschriften nicht.
function Get-UwhPickIndexes {
    param($Rows)
    if (-not $Rows -or $Rows.Count -eq 0) { return @() }
    return @(0..($Rows.Count - 1) | Where-Object { $Rows[$_].Kind -eq 'entry' })
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
    $modusNr = 0

    while ($true) {
        $modus = Get-UwhModus $modusNr
        $rows = Build-UwhRows $Catalog $filter $Installed $modus.Name
        $pick = @(Get-UwhPickIndexes $rows)

        if ($pick.Count -eq 0) {
            $body = @((New-UwhLine ''), (New-UwhLine '  Nichts gefunden. ESC loescht die Suche.'), (New-UwhLine ''))
        } else {
            if ($cursor -lt 0) { $cursor = 0 }
            if ($cursor -ge $pick.Count) { $cursor = $pick.Count - 1 }

            # Rahmen kostet 12 Zeilen: 5 Kopf + 2 Leerzeilen + 5 Fuss.
            # Eine bleibt fuer den Zeilenumbruch am Ende.
            $height = [Math]::Max(5, [Console]::WindowHeight - 13)
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

        $sub = if ($filter) { "Suche: $filter" } else { $modus.Frage }
        $count = $Selection.Keys.Count
        $foot = @(
            (New-UwhRule)
            (New-UwhLine ('  Pfeile Bewegen   LEER An/Aus   ENTER Weiter   / Suchen   ESC Beenden'))
            (New-UwhLine ('  A alle an/aus    P Profil laden    M Modus: {0}' -f $modus.Titel.PadRight(14)))
            (New-UwhLine ('{0}{1} ausgewaehlt' -f (' ' * 58), $count))
            (New-UwhRule)
        )

        Write-UwhFrame (@(Get-UwhHeader $sub) + $body + $foot)

        $stand = [pscustomobject]@{ Cursor = $cursor; Filter = $filter; Modus = $modus.Name }
        $folge = Invoke-UwhPickerKey ([Console]::ReadKey($true)) $stand $Selection $rows $pick
        $cursor = $stand.Cursor
        $filter = $stand.Filter

        switch ($folge) {
            'weiter' { return 'weiter' }
            'ende'   { return 'ende' }
            'profil' { return 'profil' }
            'suchen' {
                $filter = Read-UwhInline 'Suchen nach'
                $cursor = 0; $top = 0
            }
            'oben'   { $top = 0 }
            'modus'  {
                # Beim Wechsel faengt die Auswahl neu an - sonst waere unklar,
                # was mit den bereits angehakten Eintraegen passieren soll.
                $Selection.Clear()
                $modusNr++
                $cursor = 0; $top = 0
            }
        }
    }
}

# Welche Aktion im gerade eingestellten Modus gemeint ist.
function Get-UwhStandAktion {
    param($Stand)
    if ($Stand.PSObject.Properties['Modus'] -and $Stand.Modus) { return [string]$Stand.Modus }
    return 'install'
}

# Was eine Taste bewirkt - ohne Bildschirm und ohne Tastatur, damit pruefbar.
# Aendert $Stand (Cursor, Filter) und $Selection, liefert die naechste Handlung.
function Invoke-UwhPickerKey {
    param($Key, $Stand, $Selection, $Rows, $Pick)

    switch ($Key.Key) {
        'UpArrow'   { $Stand.Cursor-- }
        'DownArrow' { $Stand.Cursor++ }
        'PageUp'    { $Stand.Cursor -= 5 }
        'PageDown'  { $Stand.Cursor += 5 }
        'Home'      { $Stand.Cursor = 0 }
        'End'       { $Stand.Cursor = $Pick.Count - 1 }

        'Spacebar' {
            if ($Pick.Count -gt 0) {
                $e = $Rows[$Pick[$Stand.Cursor]].Entry
                if ($Selection.Contains($e.Key)) { $Selection.Remove($e.Key) }
                else { $Selection[$e.Key] = Get-UwhStandAktion $Stand }
            }
        }

        'Enter' {
            # Ohne Auswahl gibt es nichts zu tun - die Taste tut dann nichts.
            if ($Selection.Keys.Count -gt 0) { return 'weiter' }
        }

        'Escape' {
            # Erst die Suche loeschen, beim zweiten Mal beenden.
            if ($Stand.Filter) { $Stand.Filter = ''; $Stand.Cursor = 0; return 'oben' }
            return 'ende'
        }

        default {
            $c = [string]$Key.KeyChar
            if ($c -eq '/') { return 'suchen' }

            if ($c -eq 'a' -or $c -eq 'A') {
                # Sind schon alle sichtbaren gewaehlt, wird abgewaehlt.
                $sichtbar = @($Rows | Where-Object { $_.Kind -eq 'entry' })
                $alleDrin = $sichtbar.Count -gt 0
                foreach ($r in $sichtbar) {
                    if (-not $Selection.Contains($r.Entry.Key)) { $alleDrin = $false; break }
                }
                foreach ($r in $sichtbar) {
                    if ($alleDrin) { $Selection.Remove($r.Entry.Key) }
                    else { $Selection[$r.Entry.Key] = Get-UwhStandAktion $Stand }
                }
            } elseif ($c -eq 'p' -or $c -eq 'P') {
                return 'profil'
            } elseif ($c -eq 'm' -or $c -eq 'M') {
                return 'modus'
            }
        }
    }

    # Cursor darf die Liste nie verlassen.
    if ($Stand.Cursor -lt 0) { $Stand.Cursor = 0 }
    if ($Pick.Count -eq 0) { $Stand.Cursor = 0 }
    elseif ($Stand.Cursor -ge $Pick.Count) { $Stand.Cursor = $Pick.Count - 1 }

    return ''
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
