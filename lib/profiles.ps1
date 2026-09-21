# uwh - Profile: Auswahl und Antworten aufbewahren und wieder abspielen

Set-StrictMode -Version 2.0

function Get-UwhProfileDir {
    $dir = Get-UwhPath 'profiles'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-UwhProfileFile {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Test-UwhSafeName $Name)) { throw "Profilname '$Name' ist nicht erlaubt." }
    Join-Path (Get-UwhProfileDir) ($Name + '.yaml')
}

function Get-UwhProfileNames {
    Get-ChildItem -Path (Get-UwhProfileDir) -Filter '*.yaml' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.BaseName } | Sort-Object
}

# ------------------------------------------------------------------
# Lesen
# ------------------------------------------------------------------

function Import-UwhProfile {
    param([Parameter(Mandatory)][string]$Name, [string[]]$Seen = @())

    if ($Seen -contains $Name) { throw "Profil '$Name' verweist im Kreis auf sich selbst." }
    if ($Seen.Count -ge 5) { throw 'Zu viele verschachtelte Profile.' }

    $file = Get-UwhProfileFile $Name
    if (-not (Test-Path -LiteralPath $file)) { throw "Profil '$Name' gibt es nicht." }

    $raw = Import-UwhYaml $file
    if (-not $raw) { throw "Profil '$Name' ist leer." }

    $select = New-Object System.Collections.Generic.List[object]
    $options = @{ unattended = $false; continue_on_error = $true; reboot = 'ask' }

    if ($raw.Contains('extends') -and $raw['extends']) {
        $parent = Import-UwhProfile ([string]$raw['extends']) ($Seen + $Name)
        foreach ($i in $parent.Select) { $select.Add($i) }
        foreach ($k in $parent.Options.Keys) { $options[$k] = $parent.Options[$k] }
    }

    if ($raw.Contains('options') -and $raw['options']) {
        foreach ($k in $raw['options'].Keys) { $options[$k] = $raw['options'][$k] }
    }

    foreach ($item in @(Get-UwhField $raw 'select')) {
        $parsed = ConvertTo-UwhProfileItem $item
        if (-not $parsed) { continue }
        $existing = $select | Where-Object { $_.Key -eq $parsed.Key } | Select-Object -First 1
        if ($existing) {
            $existing.Action = $parsed.Action
            foreach ($k in $parsed.Answers.Keys) { $existing.Answers[$k] = $parsed.Answers[$k] }
        } else {
            $select.Add($parsed)
        }
    }

    [pscustomobject]@{
        Name        = [string](Get-UwhField $raw 'name')
        Description = [string](Get-UwhField $raw 'description')
        Select      = $select.ToArray()
        Options     = $options
    }
}

function ConvertTo-UwhProfileItem {
    param($Item)

    if ($null -eq $Item) { return $null }

    if ($Item -is [string]) {
        return [pscustomobject]@{ Key = $Item; Action = 'install'; Answers = @{} }
    }

    $key = Get-UwhField $Item 'key'
    if (-not $key) { throw "Eintrag in 'select' ohne 'key'." }

    $action = Get-UwhField $Item 'action'
    if (-not $action) { $action = 'install' }

    $answers = @{}
    $raw = Get-UwhField $Item 'answers'
    if ($raw -and $raw -is [System.Collections.IDictionary]) {
        foreach ($k in $raw.Keys) { $answers[[string]$k] = [string]$raw[$k] }
    }

    [pscustomobject]@{ Key = [string]$key; Action = [string]$action; Answers = $answers }
}

# ------------------------------------------------------------------
# Schreiben
# ------------------------------------------------------------------

# Antworten, die nicht in eine weitergebbare Datei gehoeren.
#
# Massgeblich ist 'type: secret' aus config.yaml - das ist eine Ansage des
# Katalogs, kein Raten. Der Namensfilter kommt nur zusaetzlich dazu, fuer
# Eintraege, bei denen der Typ vergessen wurde. Er darf grosszuegig sein:
# eine Antwort zu viel nicht zu speichern kostet eine Nachfrage, eine
# Antwort zu wenig zu verschweigen gibt ein Kennwort weiter.
function Test-UwhGeheim {
    param([string]$Variable, $Entry, [string]$Action)

    # Der Katalog kann Geheimhaltung nur hinzufuegen, nie aufheben: steht dort
    # versehentlich 'type: text' bei einem Kennwort, greift der Namensfilter.
    if ($Entry) {
        $a = Get-UwhAction $Entry $Action
        if ($a) {
            foreach ($p in $a.Prompts) {
                if ($p.Variable -eq $Variable -and $p.Type -eq 'secret') { return $true }
            }
        }
    }

    return ($Variable -match '(?i)(pass|pwd|kennwort|secret|token|credential|geheim|schluessel)|key$|pin$')
}

function Save-UwhProfile {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Items,
        $Catalog,
        [hashtable]$Options = @{}
    )

    $file = Get-UwhProfileFile $Name

    $select = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Items) {
        $answers = ConvertTo-UwhHashtable $item.Answers
        $entry = if ($Catalog) { Get-UwhEntry $Catalog $item.Key } else { $null }

        $secretFree = [ordered]@{}
        foreach ($k in ($answers.Keys | Sort-Object)) {
            if (Test-UwhGeheim $k $entry $item.Action) { continue }
            $secretFree[$k] = [string]$answers[$k]
        }

        if ($secretFree.Count -eq 0 -and $item.Action -eq 'install') {
            $select.Add($item.Key)
        } else {
            $e = [ordered]@{ key = $item.Key; action = $item.Action }
            if ($secretFree.Count -gt 0) { $e['answers'] = $secretFree }
            $select.Add($e)
        }
    }

    $data = [ordered]@{
        name   = $Name
        select = $select.ToArray()
        options = [ordered]@{
            unattended        = [bool]($Options['unattended'])
            continue_on_error = if ($Options.ContainsKey('continue_on_error')) { [bool]$Options['continue_on_error'] } else { $true }
            reboot            = if ($Options['reboot']) { [string]$Options['reboot'] } else { 'ask' }
        }
    }

    $header = @(
        "uwh-Profil '$Name'"
        "Erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
        ''
        'Abspielen:  uwh.ps1 -Profile ' + $Name
        'Kennwoerter werden bewusst nicht gespeichert.'
    ) -join "`n"

    Export-UwhYaml $data $file $header
    return $file
}

# ------------------------------------------------------------------
# Auswahl im Menue
# ------------------------------------------------------------------

function Show-UwhProfilePicker {
    $names = @(Get-UwhProfileNames)

    Set-UwhWidth
    $script:UwhLastHeight = 0
    Clear-Host
    Get-UwhHeader 'Profil laden' | ForEach-Object { Write-Host $_ }
    Write-Host ''

    if ($names.Count -eq 0) {
        Write-Host '  Noch keine Profile vorhanden.' -ForegroundColor DarkGray
        Write-Host '  Ein Profil entsteht, wenn du nach der Auswahl "Als Profil speichern" waehlst.'
        Write-Host ''
        Write-Host '  Weiter mit einer beliebigen Taste...' -ForegroundColor DarkGray
        [void][Console]::ReadKey($true)
        return $null
    }

    for ($i = 0; $i -lt $names.Count; $i++) {
        Write-Host ('   {0}) {1}' -f ($i + 1), $names[$i])
    }
    Write-Host ''
    $answer = Read-UwhInline 'Nummer (oder ENTER fuer zurueck):'
    if (-not $answer) { return $null }

    $n = 0
    if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $names.Count) {
        return $names[$n - 1]
    }
    return $null
}
