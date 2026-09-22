# uwh - YAML: lesen und schreiben
#
# Bewusst nur die Teilmenge, die uwh selbst benutzt:
# Zuordnungen, Listen, einfache Werte, Kommentare, Einzeiler-Listen [a, b].
# Kein Zusatzmodul, keine fremde Programmdatei - siehe tests/yaml.tests.ps1.

Set-StrictMode -Version 2.0

# ------------------------------------------------------------------
# Lesen
# ------------------------------------------------------------------

function ConvertFrom-UwhYaml {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $state = [pscustomobject]@{
        Lines = @(ConvertTo-UwhYamlLines $Text)
        Pos   = 0
    }
    if ($state.Lines.Count -eq 0) { return $null }
    Read-UwhYamlNode $state $state.Lines[0].Indent
}

function Import-UwhYaml {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    try {
        return ConvertFrom-UwhYaml $text
    } catch {
        throw (T 'yaml.broken' (Split-Path -Leaf $Path) $_.Exception.Message)
    }
}

function ConvertTo-UwhYamlLines {
    param([string]$Text)

    $out = New-Object System.Collections.Generic.List[object]
    $no = 0
    foreach ($raw in ($Text -split "`r?`n")) {
        $no++
        if ($raw.IndexOf("`t") -ge 0) {
            throw (T 'yaml.tab' $no)
        }
        $line = Remove-UwhYamlComment $raw
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $trimmed = $line.TrimEnd()
        if ($trimmed -eq '---' -or $trimmed -eq '...') { continue }

        $indent = 0
        while ($indent -lt $trimmed.Length -and $trimmed[$indent] -eq ' ') { $indent++ }

        $out.Add([pscustomobject]@{
            Indent = $indent
            Text   = $trimmed.Substring($indent)
            Number = $no
        })
    }
    return $out.ToArray()
}

# Entfernt ' # Kommentar', achtet dabei auf Anfuehrungszeichen.
function Remove-UwhYamlComment {
    param([string]$Line)

    # Die meisten Zeilen haben gar keine Raute - dann gibt es nichts zu tun.
    if ($Line.IndexOf('#') -lt 0) { return $Line }

    $inSingle = $false
    $inDouble = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($c -eq "'" -and -not $inDouble) { $inSingle = -not $inSingle; continue }
        if ($c -eq '"' -and -not $inSingle) { $inDouble = -not $inDouble; continue }
        if ($c -eq '#' -and -not $inSingle -and -not $inDouble) {
            if ($i -eq 0 -or $Line[$i - 1] -eq ' ') { return $Line.Substring(0, $i) }
        }
    }
    return $Line
}

function Read-UwhYamlNode {
    param($State, [int]$Indent)

    if ($State.Pos -ge $State.Lines.Count) { return $null }
    $line = $State.Lines[$State.Pos]
    if ($line.Indent -lt $Indent) { return $null }

    if (Test-UwhYamlSeqLine $line.Text) {
        $seq = Read-UwhYamlSeq $State $line.Indent
        return ,$seq
    }
    return Read-UwhYamlMap $State $line.Indent
}

function Test-UwhYamlSeqLine {
    param([string]$Text)
    return ($Text -eq '-' -or $Text.StartsWith('- '))
}

function Read-UwhYamlSeq {
    param($State, [int]$Indent)

    $items = New-Object System.Collections.Generic.List[object]

    while ($State.Pos -lt $State.Lines.Count) {
        $line = $State.Lines[$State.Pos]
        if ($line.Indent -ne $Indent -or -not (Test-UwhYamlSeqLine $line.Text)) { break }

        $after = $line.Text.Substring(1)
        $spaces = 0
        while ($spaces -lt $after.Length -and $after[$spaces] -eq ' ') { $spaces++ }
        $rest = $after.Substring($spaces)

        if ($rest -eq '') {
            # Wert steht eingerueckt in den Folgezeilen.
            $State.Pos++
            if ($State.Pos -lt $State.Lines.Count -and $State.Lines[$State.Pos].Indent -gt $Indent) {
                $items.Add((Read-UwhYamlNode $State $State.Lines[$State.Pos].Indent))
            } else {
                $items.Add($null)
            }
            continue
        }

        if (Test-UwhYamlMapLine $rest) {
            # '- name: wert' startet eine Zuordnung ab der Spalte von 'name'.
            $childIndent = $Indent + 1 + $spaces
            $State.Lines[$State.Pos] = [pscustomobject]@{
                Indent = $childIndent
                Text   = $rest
                Number = $line.Number
            }
            $items.Add((Read-UwhYamlMap $State $childIndent))
            continue
        }

        $items.Add((ConvertTo-UwhYamlValue $rest))
        $State.Pos++
    }

    # Das Komma haelt die Liste zusammen - ohne es loest PowerShell sie auf.
    return ,$items.ToArray()
}

function Test-UwhYamlMapLine {
    param([string]$Text)
    if (Test-UwhYamlSeqLine $Text) { return $false }
    return ($null -ne (Get-UwhYamlKeySplit $Text))
}

# Trennt 'schluessel: wert' und beachtet Anfuehrungszeichen im Schluessel.
function Get-UwhYamlKeySplit {
    param([string]$Text)

    # Ohne Anfuehrungszeichen reicht die Suche nach dem ersten ': ' - Zeichen
    # fuer Zeichen durchzugehen kostet in PowerShell 5.1 spuerbar Zeit.
    if ($Text.IndexOf("'") -lt 0 -and $Text.IndexOf('"') -lt 0) {
        $i = $Text.IndexOf(': ')
        if ($i -lt 0 -and $Text.EndsWith(':')) { $i = $Text.Length - 1 }
        if ($i -lt 0) { return $null }
        return [pscustomobject]@{
            Key   = $Text.Substring(0, $i).Trim()
            Value = $Text.Substring([Math]::Min($i + 1, $Text.Length)).Trim()
        }
    }

    $inSingle = $false
    $inDouble = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($c -eq "'" -and -not $inDouble) { $inSingle = -not $inSingle; continue }
        if ($c -eq '"' -and -not $inSingle) { $inDouble = -not $inDouble; continue }
        if ($c -eq ':' -and -not $inSingle -and -not $inDouble) {
            if ($i -eq $Text.Length - 1 -or $Text[$i + 1] -eq ' ') {
                return [pscustomobject]@{
                    Key   = $Text.Substring(0, $i).Trim()
                    Value = $Text.Substring([Math]::Min($i + 1, $Text.Length)).Trim()
                }
            }
        }
    }
    return $null
}

function Read-UwhYamlMap {
    param($State, [int]$Indent)

    $map = [ordered]@{}

    while ($State.Pos -lt $State.Lines.Count) {
        $line = $State.Lines[$State.Pos]
        if ($line.Indent -ne $Indent -or (Test-UwhYamlSeqLine $line.Text)) { break }

        $split = Get-UwhYamlKeySplit $line.Text
        if (-not $split) {
            throw (T 'yaml.badline' $line.Number $line.Text)
        }

        $key = Remove-UwhYamlQuotes $split.Key
        $State.Pos++

        if ($split.Value -ne '') {
            $map[$key] = ConvertTo-UwhYamlValue $split.Value
            continue
        }

        if ($State.Pos -ge $State.Lines.Count) { $map[$key] = $null; continue }
        $next = $State.Lines[$State.Pos]

        if ($next.Indent -gt $Indent) {
            $map[$key] = Read-UwhYamlNode $State $next.Indent
        } elseif ($next.Indent -eq $Indent -and (Test-UwhYamlSeqLine $next.Text)) {
            # Liste auf gleicher Ebene wie ihr Schluessel - in YAML erlaubt.
            $map[$key] = Read-UwhYamlSeq $State $Indent
        } else {
            $map[$key] = $null
        }
    }

    return $map
}

function Remove-UwhYamlQuotes {
    param([string]$Text)

    if ($Text.Length -ge 2) {
        if ($Text.StartsWith('"') -and $Text.EndsWith('"')) {
            $inner = $Text.Substring(1, $Text.Length - 2)
            # In einem Durchgang - nacheinander ersetzt, wuerde aus \\nas (Backslash,
            # Backslash, n) ein Zeilenumbruch.
            return [regex]::Replace($inner, '\\(["\\n])', {
                param($m)
                if ($m.Groups[1].Value -eq 'n') { "`n" } else { $m.Groups[1].Value }
            })
        }
        if ($Text.StartsWith("'") -and $Text.EndsWith("'")) {
            return $Text.Substring(1, $Text.Length - 2).Replace("''", "'")
        }
    }
    return $Text
}

function ConvertTo-UwhYamlValue {
    param([string]$Text)

    $t = $Text.Trim()
    if ($t -eq '' -or $t -eq '~' -or $t -eq 'null') { return $null }

    if ($t.StartsWith('"') -or $t.StartsWith("'")) { return Remove-UwhYamlQuotes $t }

    if ($t -eq '[]') { return ,@() }
    if ($t -eq '{}') { return [ordered]@{} }

    if ($t.StartsWith('[') -and $t.EndsWith(']')) {
        $inner = $t.Substring(1, $t.Length - 2).Trim()
        if ($inner -eq '') { return ,@() }
        return ,@($inner -split ',' | ForEach-Object { ConvertTo-UwhYamlValue $_.Trim() })
    }

    if ($t -ieq 'true')  { return $true }
    if ($t -ieq 'false') { return $false }

    if ($t -match '^-?\d+$') {
        $n = 0L
        if ([long]::TryParse($t, [ref]$n)) {
            if ($n -ge [int]::MinValue -and $n -le [int]::MaxValue) { return [int]$n }
            return $n
        }
    }
    if ($t -match '^-?\d+\.\d+$') {
        $d = 0.0
        if ([double]::TryParse($t, [Globalization.NumberStyles]::Float,
                                [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    }

    return $t
}

# ------------------------------------------------------------------
# Schreiben (fuer Profile)
# ------------------------------------------------------------------

function ConvertTo-UwhYaml {
    param([Parameter(Mandatory)][AllowNull()]$Data, [int]$Indent = 0)

    $pad = ' ' * $Indent
    $sb = New-Object System.Text.StringBuilder

    if ($null -eq $Data) { return '' }

    if ($Data -is [System.Collections.IDictionary]) {
        foreach ($key in $Data.Keys) {
            $value = $Data[$key]
            if ($null -eq $value) {
                [void]$sb.AppendLine("$pad${key}:")
            } elseif (Test-UwhYamlComplex $value) {
                [void]$sb.AppendLine("$pad${key}:")
                [void]$sb.Append((ConvertTo-UwhYaml $value ($Indent + 2)))
            } else {
                [void]$sb.AppendLine("$pad${key}: " + (Format-UwhYamlScalar $value))
            }
        }
        return $sb.ToString()
    }

    if ($Data -is [System.Collections.IEnumerable] -and $Data -isnot [string]) {
        foreach ($item in $Data) {
            if ($null -eq $item) {
                [void]$sb.AppendLine("$pad-")
            } elseif (Test-UwhYamlComplex $item) {
                $block = (ConvertTo-UwhYaml $item ($Indent + 2)).TrimEnd()
                $first = $true
                foreach ($l in ($block -split "`r?`n")) {
                    if ($first) {
                        [void]$sb.AppendLine("$pad- " + $l.Substring([Math]::Min($Indent + 2, $l.Length)))
                        $first = $false
                    } else {
                        [void]$sb.AppendLine($l)
                    }
                }
            } else {
                [void]$sb.AppendLine("$pad- " + (Format-UwhYamlScalar $item))
            }
        }
        return $sb.ToString()
    }

    return "$pad" + (Format-UwhYamlScalar $Data) + "`r`n"
}

function Test-UwhYamlComplex {
    param($Value)
    if ($Value -is [string]) { return $false }
    if ($Value -is [System.Collections.IDictionary]) { return $true }
    return ($Value -is [System.Collections.IEnumerable])
}

function Format-UwhYamlScalar {
    param($Value)

    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) {
        return [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Value)
    }

    $s = [string]$Value
    if ($s -eq '') { return '""' }
    # Was wie Zahl, Wahrheitswert oder "nichts" aussieht, kaeme als solches
    # zurueck: aus der Postleitzahl 01067 wuerde 1067. Also in Anfuehrungszeichen.
    $mehrdeutig = ($s -match '^-?\d+(\.\d+)?$') -or ($s -match '^(true|false|null|~)$')
    if (-not $mehrdeutig -and $s -match '^[A-Za-z0-9][A-Za-z0-9 ._@/\\:+\-]*$' -and $s -notmatch '\s$') { return $s }
    return '"' + $s.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", '\n') + '"'
}

function Export-UwhYaml {
    param([Parameter(Mandatory)]$Data, [Parameter(Mandatory)][string]$Path, [string]$Header)

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $text = ''
    if ($Header) { $text += ($Header -split "`r?`n" | ForEach-Object { "# $_" }) -join "`r`n"; $text += "`r`n`r`n" }
    $text += (ConvertTo-UwhYaml $Data 0)

    Set-Content -LiteralPath $Path -Value $text -Encoding UTF8 -NoNewline
}
