# uwh - Katalog: config.yaml einlesen, pruefen, durchsuchen

Set-StrictMode -Version 2.0

$script:UwhProviderActions = @{
    winget     = @('install', 'update', 'uninstall')
    msstore    = @('install', 'update', 'uninstall')
    feature    = @('install', 'uninstall')
    capability = @('install', 'uninstall')
    url        = @('install')
    psmodule   = @('install', 'update', 'uninstall')
    script     = @('install')
}

# Ohne Pfad: der Katalog von uwh plus die Kataloge aller aktiven eigenen Repos
# unter custom/. Mit Pfad: nur diese eine Datei (fuer Pruefungen).
function Get-UwhCatalog {
    param([string]$Path)

    if ($Path) { return Read-UwhCatalogFile $Path }

    $haupt = Read-UwhCatalogFile (Get-UwhPath 'config.yaml')

    $eintraege = [ordered]@{}
    foreach ($e in $haupt.Entries) { $eintraege[$e.Key] = $e }
    $kategorien = New-Object System.Collections.Generic.List[string]
    foreach ($k in $haupt.Categories) { $kategorien.Add($k) }
    $probleme = New-Object System.Collections.Generic.List[string]
    foreach ($p in $haupt.Problems) { $probleme.Add($p) }

    $info = Get-UwhRepos
    foreach ($p in $info.Probleme) { $probleme.Add($p) }

    $herkunft = New-Object System.Collections.Generic.List[object]
    foreach ($k in @(Get-UwhRepoKataloge $info)) {
        try {
            $teil = Read-UwhCatalogFile $k.Datei $k.Repo.Id $k.Repo.Name
        } catch {
            $probleme.Add(("{0}: {1}" -f $k.Repo.Name, $_.Exception.Message))
            continue
        }

        $ersetzt = 0
        foreach ($e in $teil.Entries) {
            # Eigene Eintraege gewinnen: wer 'firefox' selbst beschreibt, meint seine Fassung.
            if ($eintraege.Contains($e.Key)) { $ersetzt++ }
            $eintraege[$e.Key] = $e
        }
        foreach ($c in $teil.Categories) { if (-not $kategorien.Contains($c)) { $kategorien.Add($c) } }
        foreach ($p in $teil.Problems) { $probleme.Add(("{0}: {1}" -f $k.Repo.Name, $p)) }

        $herkunft.Add([pscustomobject]@{
            Repo = $k.Repo; Anzahl = @($teil.Entries).Count; Ersetzt = $ersetzt
        })
    }

    [pscustomobject]@{
        Entries    = @($eintraege.Values)
        Categories = $kategorien.ToArray()
        Problems   = $probleme.ToArray()
        Source     = $haupt.Source
        Repos      = $herkunft.ToArray()
    }
}

function Read-UwhCatalogFile {
    param([Parameter(Mandatory)][string]$Path, [string]$Quelle = 'uwh', [string]$Kategorie = '')

    if (-not (Test-Path -LiteralPath $Path)) { throw "Katalog nicht gefunden: $Path" }

    $raw = Import-UwhYaml $Path
    if (-not $raw -or -not $raw.Contains('scripts')) {
        # Ein eigenes Repo darf leer anfangen - der Katalog von uwh nicht.
        if ($Quelle -ne 'uwh') {
            return [pscustomobject]@{ Entries = @(); Categories = @(); Problems = @(); Source = $Path; Repos = @() }
        }
        throw "Katalog enthaelt keinen Abschnitt 'scripts'."
    }

    $entries = New-Object System.Collections.Generic.List[object]
    $problems = New-Object System.Collections.Generic.List[string]

    $liste = $raw['scripts']
    if ($liste -is [System.Collections.IDictionary]) {
        foreach ($key in $liste.Keys) {
            try {
                $e = ConvertTo-UwhEntry $key $liste[$key] (Split-Path -Parent $Path)
                # In eigenen Repos ist die Kategorie freiwillig - ohne landet der
                # Eintrag unter dem Namen des Repos.
                if (-not $e.Category -and $Kategorie) { $e.Category = $Kategorie }
                $e | Add-Member -NotePropertyName Quelle -NotePropertyValue $Quelle
                $entries.Add($e)
            } catch {
                $problems.Add(("{0}: {1}" -f $key, $_.Exception.Message))
            }
        }
    }

    $categories = @()
    if ($raw.Contains('categories') -and $raw.categories) { $categories = @($raw.categories) }
    foreach ($e in $entries) { if ($categories -notcontains $e.Category) { $categories += $e.Category } }

    [pscustomobject]@{
        Entries    = $entries.ToArray()
        Categories = $categories
        Problems   = $problems.ToArray()
        Source     = $Path
        Repos      = @()
    }
}

function ConvertTo-UwhEntry {
    param([string]$Key, $Data, [string]$BaseDir)

    if (-not $Data) { throw 'Eintrag ist leer.' }
    if (-not (Test-UwhSafeName $Key)) { throw "Kennung '$Key' enthaelt unerlaubte Zeichen." }

    $provider = Get-UwhField $Data 'provider'
    if (-not $provider) { throw "Feld 'provider' fehlt." }
    $provider = ([string]$provider).ToLowerInvariant()
    if (-not $script:UwhProviderActions.ContainsKey($provider)) {
        throw "Unbekannter provider '$provider'."
    }

    $id = Get-UwhField $Data 'id'
    if ($provider -in @('winget', 'msstore', 'feature', 'capability', 'psmodule')) {
        if (-not $id) { throw "Feld 'id' fehlt fuer provider '$provider'." }
        if (-not (Test-UwhSafeId $id)) { throw "Kennung '$id' enthaelt unerlaubte Zeichen." }
    }

    $url = Get-UwhField $Data 'url'
    if ($provider -eq 'url') {
        if (-not (Test-UwhHttpsUrl $url)) { throw 'Feld "url" fehlt oder ist kein https-Link.' }
    }

    $file = Get-UwhField $Data 'file'
    if ($provider -eq 'script') {
        if (-not $file) { throw "Feld 'file' fehlt fuer provider 'script'." }
        if ($file -match '[\\/]|\.\.') { throw "Dateiname '$file' darf keinen Pfad enthalten." }
    }

    $actions = Get-UwhActions $Data $provider
    $name = Get-UwhField $Data 'name'
    if (-not $name) { $name = $Key }

    $scope = Get-UwhField $Data 'scope'
    if (-not $scope) { $scope = 'machine' }
    if ($scope -notin @('machine', 'user')) { throw "Feld 'scope' muss 'machine' oder 'user' sein." }

    $admin = Get-UwhField $Data 'admin'
    if ($null -eq $admin) {
        $admin = ($provider -in @('feature', 'capability', 'url')) -or
                 ($provider -in @('winget', 'msstore', 'psmodule') -and $scope -eq 'machine')
    }

    [pscustomobject]@{
        Key         = $Key
        Name        = [string]$name
        Description = [string](Get-UwhField $Data 'description')
        Category    = [string](Get-UwhField $Data 'category')
        Provider    = $provider
        Id          = [string]$id
        Scope       = $scope
        Url         = [string]$url
        Sha256      = [string](Get-UwhField $Data 'sha256')
        SilentArgs  = [string](Get-UwhField $Data 'args')
        File        = [string]$file
        BaseDir     = $BaseDir
        Actions     = $actions
        Admin       = [bool]$admin
        Reboot      = [string](Get-UwhField $Data 'reboot')
        Recommended = [bool](Get-UwhField $Data 'recommended')
        Note        = [string](Get-UwhField $Data 'note')
    }
}

function Get-UwhActions {
    param($Data, [string]$Provider)

    $defined = Get-UwhField $Data 'actions'
    $result = New-Object System.Collections.Generic.List[object]

    if (-not $defined) {
        foreach ($a in $script:UwhProviderActions[$Provider]) {
            $result.Add([pscustomobject]@{ Name = $a; Description = ''; Prompts = @() })
        }
        return $result.ToArray()
    }

    foreach ($a in @($defined)) {
        if ($a -is [string]) {
            $result.Add([pscustomobject]@{ Name = $a; Description = ''; Prompts = @() })
            continue
        }
        $an = Get-UwhField $a 'name'
        if (-not $an) { throw "Aktion ohne 'name'." }
        $result.Add([pscustomobject]@{
            Name        = [string]$an
            Description = [string](Get-UwhField $a 'description')
            Prompts     = @(ConvertTo-UwhPrompts (Get-UwhField $a 'prompts'))
        })
    }
    return $result.ToArray()
}

function ConvertTo-UwhPrompts {
    param($Data)
    if (-not $Data) { return @() }

    $out = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($Data)) {
        $variable = Get-UwhField $p 'variable'
        if (-not $variable) { throw "Abfrage ohne 'variable'." }
        if ($variable -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Variablenname '$variable' ist unzulaessig."
        }
        $type = Get-UwhField $p 'type'
        if (-not $type) { $type = 'text' }
        if ($type -notin @('text', 'yesno', 'secret')) { throw "Unbekannter Abfragetyp '$type'." }

        $out.Add([pscustomobject]@{
            Question = [string](Get-UwhField $p 'question')
            Variable = [string]$variable
            Type     = [string]$type
            Default  = [string](Get-UwhField $p 'default')
        })
    }
    return $out.ToArray()
}

function Get-UwhField {
    param($Data, [string]$Name)
    if ($null -eq $Data) { return $null }
    if ($Data -is [System.Collections.IDictionary]) {
        if ($Data.Contains($Name)) { return $Data[$Name] }
        return $null
    }
    return $null
}

# ------------------------------------------------------------------
# Zugriff
# ------------------------------------------------------------------

function Get-UwhEntry {
    param($Catalog, [string]$Key)
    $Catalog.Entries | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
}

function Get-UwhAction {
    param($Entry, [string]$Name)
    $Entry.Actions | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
}

function Find-UwhEntries {
    param($Catalog, [string]$Term)
    if (-not $Term) { return $Catalog.Entries }
    $t = $Term.Trim()
    $Catalog.Entries | Where-Object {
        $_.Name -like "*$t*" -or $_.Key -like "*$t*" -or
        $_.Description -like "*$t*" -or $_.Category -like "*$t*"
    }
}
