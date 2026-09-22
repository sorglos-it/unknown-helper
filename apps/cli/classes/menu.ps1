# uwh - Menue: Mehrfachauswahl, Abfragen, Zusammenfassung

Set-StrictMode -Version 2.0

$script:UwhWidth = 78
$script:UwhLastHeight = 0
$script:UwhLastFrameWidth = 0

# Der Rahmen ist hoechstens 78 Zeichen breit, passt sich aber schmaleren
# Fenstern an - sonst fehlt rechts der Rand und alles sieht kaputt aus.
function Set-UwhWidth {
    try {
        $script:UwhWidth = [Math]::Max(46, [Math]::Min(78, [Console]::WindowWidth - 1))
    } catch {
        $script:UwhWidth = 78
    }
}

# Die drei Betriebsarten des Menues, in dieser Reihenfolge durchgeschaltet.
# Titel und Frage kommen aus der Sprachdatei.
$script:UwhModi = @('install', 'update', 'uninstall')

function Get-UwhModus {
    param([int]$Nummer)
    $name = $script:UwhModi[$Nummer % $script:UwhModi.Count]
    [pscustomobject]@{ Name = $name; Titel = (T "mode.$name.title"); Frage = (T "mode.$name.ask") }
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

        # Wird das Fenster waehrend des Laufs schmaler, sind die alten Zeilen
        # umgebrochen und stehen noch da. Einmal leeren raeumt das auf.
        if ($w -ne $script:UwhLastFrameWidth) {
            Clear-Host
            $script:UwhLastHeight = 0
            $script:UwhLastFrameWidth = $w
        }

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
    $left = if ($script:UwhWidth -ge 60) { '  uwh - unknown windows helper' } else { '  uwh' }
    $right = "v$v  "
    $pad = $script:UwhWidth - 2 - $left.Length - $right.Length
    if ($pad -lt 1) { $pad = 1 }

    $out = @((New-UwhRule), (New-UwhLine ($left + (' ' * $pad) + $right)), (New-UwhRule))
    if ($Subtitle) { $out += @((New-UwhLine "  $Subtitle"), (New-UwhRule)) }
    return $out
}

# Verteilt Bausteine auf Zeilen: passt alles in eine, mit drei Leerzeichen
# dazwischen, sonst mit zwei - und notfalls auf mehrere Zeilen.
function Join-UwhParts {
    param([string[]]$Parts, [int]$Width)

    foreach ($abstand in @('   ', '  ')) {
        $ganz = $Parts -join $abstand
        if ($ganz.Length -le $Width) { return ,@($ganz.TrimEnd()) }
    }

    $zeilen = New-Object System.Collections.Generic.List[string]
    $z = ''
    foreach ($p in $Parts) {
        if ($z -and ($z.Length + 2 + $p.Length) -gt $Width) { $zeilen.Add($z.TrimEnd()); $z = '' }
        $z = if ($z) { $z + '  ' + $p } else { $p }
    }
    if ($z) { $zeilen.Add($z.TrimEnd()) }
    return ,$zeilen.ToArray()
}

# Die Tastenhilfe unter der Liste - in jeder Sprache und jeder Fensterbreite
# vollstaendig, ohne etwas abzuschneiden.
function Get-UwhPickerFoot {
    param($Modus, [int]$Count)

    # 2 Rand + 2 Einzug + 2 Luft rechts.
    $breite = $script:UwhWidth - 6

    # Der Modus bekommt die Breite des laengsten Titels - sonst springt die
    # Aufteilung beim Durchschalten.
    $laengste = 0
    foreach ($m in $script:UwhModi) { $laengste = [Math]::Max($laengste, (T "mode.$m.title").Length) }

    $zeilen = New-Object System.Collections.Generic.List[string]
    $gruppen = @(
        ,@(
            ('{0} {1}' -f (T 'menu.key.arrows'), (T 'menu.move'))
            ('{0} {1}' -f (T 'menu.key.space'), (T 'menu.toggle'))
            ('{0} {1}' -f (T 'menu.key.enter'), (T 'menu.next'))
            ('/ {0}' -f (T 'menu.find'))
            ('ESC {0}' -f (T 'menu.quit'))
        )
        ,@(
            ('A {0}' -f (T 'menu.all'))
            ('P {0}' -f (T 'menu.profile'))
            ('M {0}: {1}' -f (T 'menu.mode'), $Modus.Titel.PadRight($laengste))
            ('L {0}: {1}' -f (T 'menu.language'), (T 'lang.name'))
        )
    )
    foreach ($g in $gruppen) {
        foreach ($z in (Join-UwhParts $g $breite)) { $zeilen.Add($z) }
    }

    # Die Anzahl steht rechts in der letzten Zeile, wenn dort Platz ist.
    $zahl = T 'menu.selected' $Count
    $letzte = $zeilen[$zeilen.Count - 1]
    if ($letzte.Length + 3 + $zahl.Length -le $breite) {
        $zeilen[$zeilen.Count - 1] = $letzte + (' ' * ($breite - $letzte.Length - $zahl.Length)) + $zahl
    } else {
        $zeilen.Add((' ' * ($breite - $zahl.Length)) + $zahl)
    }

    $out = @(New-UwhRule)
    foreach ($z in $zeilen) { $out += New-UwhLine ('  ' + $z) }
    $out += New-UwhRule
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
        $rows.Add([pscustomobject]@{ Kind = 'header'; Text = (Get-UwhCategoryName $Catalog $cat); Entry = $null })
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

    # Feste Zeichen: 2 Einzug + Zeiger + Leer + [x] + Leer + Leer + Leer = 10.
    # Der Rest wird auf Name und Beschreibung verteilt; in schmalen Fenstern
    # faellt die Spalte 'installiert' als erstes weg.
    $inner = $script:UwhWidth - 2
    $platzStand = if ($inner -ge 70) { 11 } else { 0 }
    $rest = $inner - 10 - $platzStand
    $breiteName = [Math]::Max(8, [Math]::Min(24, [int]($rest * 0.44)))
    $breiteDesc = [Math]::Max(4, $rest - $breiteName)

    $name = $Row.Entry.Name
    if ($name.Length -gt $breiteName) { $name = $name.Substring(0, $breiteName - 1) + '.' }
    $desc = $Row.Entry.Description
    if ($desc.Length -gt $breiteDesc) { $desc = $desc.Substring(0, $breiteDesc - 1) + '.' }

    $text = '  {0} {1} {2} {3}' -f $mark, $box, $name.PadRight($breiteName), $desc.PadRight($breiteDesc)
    if ($platzStand -gt 0 -and $Row.Installed) { $text += ' ' + (T 'menu.installed') }
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
        Set-UwhWidth
        $modus = Get-UwhModus $modusNr
        $rows = Build-UwhRows $Catalog $filter $Installed $modus.Name
        $pick = @(Get-UwhPickIndexes $rows)

        $sub = if ($filter) { T 'menu.search' $filter } else { $modus.Frage }
        $head = @(Get-UwhHeader $sub)
        $foot = @(Get-UwhPickerFoot $modus $Selection.Keys.Count)

        if ($pick.Count -eq 0) {
            $body = @((New-UwhLine ''), (New-UwhLine ('  ' + (T 'menu.nothing'))), (New-UwhLine ''))
        } else {
            if ($cursor -lt 0) { $cursor = 0 }
            if ($cursor -ge $pick.Count) { $cursor = $pick.Count - 1 }

            # Kopf, zwei Leerzeilen und Fuss gehen ab - wie hoch der Fuss ist,
            # haengt von Sprache und Fensterbreite ab. Eine Zeile bleibt fuer
            # den Zeilenumbruch am Ende.
            $height = [Math]::Max(5, [Console]::WindowHeight - $head.Count - $foot.Count - 3)
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

        Write-UwhFrame ($head + $body + $foot)

        $stand = [pscustomobject]@{ Cursor = $cursor; Filter = $filter; Modus = $modus.Name }
        $folge = Invoke-UwhPickerKey ([Console]::ReadKey($true)) $stand $Selection $rows $pick
        $cursor = $stand.Cursor
        $filter = $stand.Filter

        switch ($folge) {
            'weiter' { return 'weiter' }
            'ende'   { return 'ende' }
            'profil' { return 'profil' }
            'suchen' {
                $filter = Read-UwhInline (T 'menu.searchfor')
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
            'sprache' {
                # Die Auswahl bleibt - nur die Texte wechseln. Gemerkt wird die
                # Sprache fuer den naechsten Start.
                $neu = Get-UwhNextLanguage
                Set-UwhLanguage $neu
                [void](Save-UwhLanguage $neu)
                Set-UwhCatalogLanguage $Catalog
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
            } elseif ($c -eq 'l' -or $c -eq 'L') {
                return 'sprache'
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

# Ja und Nein in allen fuenf Sprachen: j, y, o (oui) und s (si) heissen ja.
function Test-UwhJa {
    param([string]$Text)
    return ([string]$Text).Trim() -match '^(j|ja|y|yes|o|oui|s|si|sì|sí|true)$'
}

function Test-UwhNein {
    param([string]$Text)
    return ([string]$Text).Trim() -match '^(n|nein|no|non|false)$'
}

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

# Antworten auf Ja/Nein-Fragen heissen intern immer 'ja' oder 'nein' - so
# stehen sie in Profilen und so kommen sie in den Skripten an, egal in
# welcher Sprache gefragt wurde.
function Read-UwhAnswer {
    param($Prompt, [string]$Preset)

    $default = if ($null -ne $Preset -and $Preset -ne '') { $Preset } else { $Prompt.Default }

    while ($true) {
        if ($Prompt.Type -eq 'yesno') {
            $hint = if (Test-UwhJa $default) { T 'yesno.yes' } else { T 'yesno.no' }
            Write-Host ("  {0} {1} " -f $Prompt.Question, $hint) -NoNewline
            $in = (Read-Host).Trim()
            if ($in -eq '') { $in = $default }
            if (Test-UwhJa $in)   { return 'ja' }
            if (Test-UwhNein $in) { return 'nein' }
            Write-Host ('  ' + (T 'yesno.again')) -ForegroundColor Yellow
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

        # Ohne Vorgabe geht es ohne Antwort nicht weiter - dann muss man auch
        # wissen, wie man wieder herauskommt.
        Write-Host ('  ' + (T 'input.required')) -ForegroundColor Yellow
        Write-Host ('  ' + (T 'input.cancel')) -ForegroundColor DarkGray
    }
}

function Read-UwhConfirm {
    param([string]$Question, [bool]$Default = $true)

    $hint = if ($Default) { T 'yesno.yes' } else { T 'yesno.no' }
    while ($true) {
        Write-Host ("  {0} {1} " -f $Question, $hint) -NoNewline
        $in = (Read-Host).Trim()
        if ($in -eq '') { return $Default }
        if (Test-UwhJa $in)   { return $true }
        if (Test-UwhNein $in) { return $false }
    }
}

# ------------------------------------------------------------------
# Auswahl bestaetigen
# ------------------------------------------------------------------

function Show-UwhSummary {
    param($Catalog, $Plan)

    Set-UwhWidth
    $script:UwhLastHeight = 0
    Clear-Host

    $lines = Get-UwhHeader (T 'summary.title')
    $lines += New-UwhLine ''

    foreach ($item in $Plan.Items) {
        $entry = Get-UwhEntry $Catalog $item.Key
        $name = if ($entry) { $entry.Name } else { $item.Key }
        $verb = if ($item.Action -in $script:UwhModi) { T "summary.$($item.Action)" } else { $item.Action }
        $lines += New-UwhLine ('   - {0} {1}' -f $name.PadRight(30), $verb)
    }

    $anzahl = $Plan.Items.Count
    $lines += New-UwhLine ''
    $lines += New-UwhRule
    $lines += New-UwhLine ('  ' + $(if ($anzahl -eq 1) { T 'summary.step' $anzahl } else { T 'summary.steps' $anzahl }))
    if ($Plan.NeedsAdmin)  { $lines += New-UwhLine ('  ' + (T 'summary.admin')) }
    if ($Plan.MayReboot)   { $lines += New-UwhLine ('  ' + (T 'summary.reboot')) }
    $lines += New-UwhRule

    $lines | ForEach-Object { Write-Host $_ }
    Write-Host ''
    return (Read-UwhConfirm (T 'summary.start') $true)
}
