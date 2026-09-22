# uwh - Katalog: config.yaml einlesen, pruefen, durchsuchen
#
# Texte stehen in jeder Sprache im Eintrag selbst: 'description' ist der
# Grundtext (Englisch), 'descriptionDE', 'descriptionFR' usw. die Uebersetzung.
# Das gilt fuer name, description, category, note, id und die Fragen.
# Set-UwhCatalogLanguage stellt alle Eintraege auf eine Sprache um.

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

# Ohne Pfad: der Katalog von uwh (assets\catalog.yaml) plus die Kataloge aller
# aktiven eigenen Repos unter data\. Mit Pfad: nur diese eine Datei (fuer Pruefungen).
function Get-UwhCatalog {
    param([string]$Path)

    if ($Path) {
        $teil = Read-UwhCatalogFile $Path
        return New-UwhCatalog $teil.Entries $teil.Categories $teil.Problems $Path @() @() $teil.Entries
    }

    $haupt = Read-UwhCatalogFile (Get-UwhPath 'assets\catalog.yaml')

    $eintraege = [ordered]@{}
    foreach ($e in $haupt.Entries) { $eintraege[$e.Key] = $e }
    $weitere = New-Object System.Collections.Generic.List[string]
    $probleme = New-Object System.Collections.Generic.List[string]
    foreach ($p in $haupt.Problems) { $probleme.Add($p) }

    $info = Get-UwhRepos
    foreach ($p in $info.Probleme) { $probleme.Add($p) }

    $herkunft = New-Object System.Collections.Generic.List[object]
    foreach ($k in @(Get-UwhRepoKataloge $info)) {
        try {
            $teil = Read-UwhCatalogFile $k.Datei $k.Repo.Id $k.Repo.Namen
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
        foreach ($c in $teil.Categories) { $weitere.Add($c) }
        foreach ($p in $teil.Problems) { $probleme.Add(("{0}: {1}" -f $k.Repo.Name, $p)) }

        $herkunft.Add([pscustomobject]@{
            Repo = $k.Repo; Anzahl = @($teil.Entries).Count; Ersetzt = $ersetzt
        })
    }

    New-UwhCatalog @($eintraege.Values) $haupt.Categories $probleme.ToArray() $haupt.Source $herkunft.ToArray() $weitere.ToArray() $haupt.Entries
}

# Fuegt alles zusammen: Kategorien vereinheitlichen, Sprache einstellen.
#
# Die Kennung einer Kategorie ist ihr Grundname aus dem Katalog von uwh. Eigene
# Eintraege duerfen jeden Namen einer vorhandenen Kategorie benutzen, in jeder
# Sprache - 'Grundausstattung' landet bei 'Essentials'. So passen auch eigene
# Kataloge, die noch aus der Zeit vor den Sprachen stammen.
function New-UwhCatalog {
    param($Entries, $Categories, $Problems, [string]$Source, $Repos, $Weitere = @(), $Stamm = @())

    # $Categories ist die Liste aus dem Katalog von uwh und legt die Reihenfolge
    # fest, $Weitere sind die Listen eigener Repos. $Stamm sind alle Eintraege
    # von uwh - auch die, die ein eigener Eintrag ersetzt hat: ihre Namen fuer
    # eine Kategorie gelten trotzdem.
    $Entries = @($Entries)
    $alias = @{}
    $texte = @{}
    foreach ($c in @($Categories)) {
        if ($c -and -not $alias.ContainsKey([string]$c)) { $alias[[string]$c] = [string]$c }
    }

    # Erst uwh, dann die eigenen: bei gleichem Namen gilt der von uwh.
    foreach ($e in (@($Stamm) + @($Entries | Where-Object { $_.Quelle -ne 'uwh' }))) {
        $namen = $e.Texte.category
        if (-not $namen['']) { continue }
        $kennung = if ($alias.ContainsKey($namen[''])) { $alias[$namen['']] } else { $namen[''] }
        if (-not $texte.ContainsKey($kennung)) { $texte[$kennung] = @{} }
        foreach ($l in @($namen.Keys)) {
            if ($namen[$l] -and -not $alias.ContainsKey($namen[$l])) { $alias[$namen[$l]] = $kennung }
            if ($l -and -not $texte[$kennung].ContainsKey($l)) { $texte[$kennung][$l] = $namen[$l] }
        }
    }
    foreach ($e in $Entries) {
        $basis = [string]$e.Texte.category['']
        $e.Category = if ($alias.ContainsKey($basis)) { $alias[$basis] } else { $basis }
    }

    $reihe = New-Object System.Collections.Generic.List[string]
    foreach ($c in (@($Categories) + @($Weitere) + @($Entries | ForEach-Object { $_.Category }))) {
        if (-not $c) { continue }
        $k = if ($alias.ContainsKey([string]$c)) { $alias[[string]$c] } else { [string]$c }
        if (-not $reihe.Contains($k)) { $reihe.Add($k) }
    }

    $katalog = [pscustomobject]@{
        Entries       = $Entries
        Categories    = $reihe.ToArray()
        CategoryTexts = $texte
        CategoryNames = @{}
        Problems      = @($Problems)
        Source        = $Source
        Repos         = @($Repos)
    }
    Set-UwhCatalogLanguage $katalog
    return $katalog
}

function Read-UwhCatalogFile {
    param([Parameter(Mandatory)][string]$Path, [string]$Quelle = 'uwh', $Kategorie = '')

    if (-not (Test-Path -LiteralPath $Path)) { throw (T 'catalog.notfound' $Path) }

    $raw = Import-UwhYaml $Path
    if (-not $raw -or -not $raw.Contains('scripts')) {
        # Ein eigenes Repo darf leer anfangen - der Katalog von uwh nicht.
        if ($Quelle -ne 'uwh') {
            return [pscustomobject]@{ Entries = @(); Categories = @(); Problems = @(); Source = $Path; Repos = @() }
        }
        throw (T 'catalog.noscripts')
    }

    # In eigenen Repos ist die Kategorie freiwillig - ohne landet der Eintrag
    # unter dem Namen des Repos, in jeder Sprache, in der das Repo einen hat.
    $ersatz = if ($Kategorie -is [hashtable]) { $Kategorie } else { @{ '' = [string]$Kategorie } }

    $entries = New-Object System.Collections.Generic.List[object]
    $problems = New-Object System.Collections.Generic.List[string]

    $liste = $raw['scripts']
    $ordner = Split-Path -Parent $Path
    if ($liste -is [System.Collections.IDictionary]) {
        foreach ($key in $liste.Keys) {
            try {
                $e = ConvertTo-UwhEntry $key $liste[$key] $ordner
                if (-not $e.Texte.category[''] -and $ersatz['']) {
                    $e.Texte.category = $ersatz.Clone()
                    $e.Category = [string]$ersatz['']
                }
                $e.Quelle = $Quelle
                $entries.Add($e)
            } catch {
                $problems.Add(("{0}: {1}" -f $key, $_.Exception.Message))
            }
        }
    }

    $categories = @()
    if ($raw.Contains('categories') -and $raw.categories) { $categories = @($raw.categories | ForEach-Object { [string]$_ }) }

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

    if (-not $Data) { throw (T 'catalog.empty') }
    if (-not (Test-UwhSafeName $Key)) { throw (T 'catalog.badkey' $Key) }

    $provider = Get-UwhField $Data 'provider'
    if (-not $provider) { throw (T 'catalog.noprovider') }
    $provider = ([string]$provider).ToLowerInvariant()
    if (-not $script:UwhProviderActions.ContainsKey($provider)) {
        throw (T 'catalog.badprovider' $provider)
    }

    # Die Paketkennung kann je Sprache eine andere sein: Firefox gibt es als
    # Mozilla.Firefox.de, .fr usw. Jede einzelne wird geprueft.
    $ids = Get-UwhVariants $Data 'id'
    if ($provider -in @('winget', 'msstore', 'feature', 'capability', 'psmodule')) {
        if (-not $ids['']) { throw (T 'catalog.noid' $provider) }
        foreach ($i in @($ids.Values)) {
            if (-not (Test-UwhSafeId $i)) { throw (T 'catalog.badkey' $i) }
        }
    }
    $alleIds = New-Object System.Collections.Generic.List[string]
    foreach ($l in @('') + @(Get-UwhLanguages)) {
        if ($ids.ContainsKey($l) -and $ids[$l] -and -not $alleIds.Contains($ids[$l])) { $alleIds.Add($ids[$l]) }
    }

    $url = Get-UwhField $Data 'url'
    if ($provider -eq 'url') {
        if (-not (Test-UwhHttpsUrl $url)) { throw (T 'catalog.badurl') }
        if (-not (Test-UwhSha256 ([string](Get-UwhField $Data 'sha256')))) { throw (T 'catalog.nosha') }
    }

    $file = Get-UwhField $Data 'file'
    if ($provider -eq 'script') {
        if (-not $file) { throw (T 'catalog.nofile') }
        if ($file -match '[\\/]|\.\.') { throw (T 'catalog.filepath' $file) }
        if ($file -notmatch '\.ps1$') { throw (T 'catalog.fileext' $file) }
    }

    $actions = Get-UwhActions $Data $provider

    $scope = Get-UwhField $Data 'scope'
    if (-not $scope) { $scope = 'machine' }
    if ($scope -notin @('machine', 'user')) { throw (T 'catalog.badscope') }

    $admin = Get-UwhField $Data 'admin'
    if ($null -eq $admin) {
        $admin = ($provider -in @('feature', 'capability', 'url')) -or
                 ($provider -in @('winget', 'msstore', 'psmodule') -and $scope -eq 'machine')
    }

    $texte = @{
        name        = Get-UwhVariants $Data 'name'
        description = Get-UwhVariants $Data 'description'
        category    = Get-UwhVariants $Data 'category'
        note        = Get-UwhVariants $Data 'note'
        id          = $ids
    }
    if (-not $texte.name['']) { $texte.name[''] = $Key }

    $e = [pscustomobject]@{
        Key         = $Key
        Name        = ''
        Description = ''
        Category    = [string]$texte.category['']
        Provider    = $provider
        Id          = ''
        Ids         = $alleIds.ToArray()
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
        Note        = ''
        Texte       = $texte
        Quelle      = 'uwh'
    }
    # Name, Beschreibung usw. fuellt Set-UwhCatalogLanguage, wenn der ganze
    # Katalog steht - einmal, nicht je Datei noch einmal.
    return $e
}

function Get-UwhActions {
    param($Data, [string]$Provider)

    $defined = Get-UwhField $Data 'actions'
    $result = New-Object System.Collections.Generic.List[object]

    if (-not $defined) {
        foreach ($a in $script:UwhProviderActions[$Provider]) {
            $result.Add((New-UwhAction $a $null @()))
        }
        return $result.ToArray()
    }

    foreach ($a in @($defined)) {
        if ($a -is [string]) {
            $result.Add((New-UwhAction $a $null @()))
            continue
        }
        $an = Get-UwhField $a 'name'
        if (-not $an) { throw (T 'catalog.actionname') }
        $result.Add((New-UwhAction ([string]$an) $a @(ConvertTo-UwhPrompts (Get-UwhField $a 'prompts'))))
    }
    return $result.ToArray()
}

function New-UwhAction {
    param([string]$Name, $Data, $Prompts)
    [pscustomobject]@{
        Name        = $Name
        Description = ''
        Prompts     = @($Prompts)
        Texte       = @{ description = Get-UwhVariants $Data 'description' }
    }
}

function ConvertTo-UwhPrompts {
    param($Data)
    if (-not $Data) { return @() }

    $out = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($Data)) {
        $variable = Get-UwhField $p 'variable'
        if (-not $variable) { throw (T 'catalog.promptvar') }
        if ($variable -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw (T 'catalog.badvar' $variable)
        }
        $type = Get-UwhField $p 'type'
        if (-not $type) { $type = 'text' }
        if ($type -notin @('text', 'yesno', 'secret')) { throw (T 'catalog.badtype' $type) }

        $out.Add([pscustomobject]@{
            Question = ''
            Variable = [string]$variable
            Type     = [string]$type
            Default  = [string](Get-UwhField $p 'default')
            Texte    = @{ question = Get-UwhVariants $p 'question' }
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
# Sprache
# ------------------------------------------------------------------

function Set-UwhEntryLanguage {
    param($Entry, [string]$Language)

    $t = $Entry.Texte
    $Entry.Name        = Select-UwhText $t.name $Language
    $Entry.Description = Select-UwhText $t.description $Language
    $Entry.Note        = Select-UwhText $t.note $Language
    $Entry.Id          = Select-UwhText $t.id $Language
    foreach ($a in $Entry.Actions) {
        $a.Description = Select-UwhText $a.Texte.description $Language
        foreach ($p in $a.Prompts) { $p.Question = Select-UwhText $p.Texte.question $Language }
    }
}

# Stellt den ganzen Katalog auf eine Sprache um - beim Laden und bei L im Menue.
function Set-UwhCatalogLanguage {
    param($Catalog, [string]$Language = (Get-UwhLanguage))

    foreach ($e in $Catalog.Entries) { Set-UwhEntryLanguage $e $Language }

    $namen = @{}
    foreach ($c in $Catalog.Categories) {
        $t = $Catalog.CategoryTexts[$c]
        $namen[$c] = if ($t -and $t.ContainsKey($Language)) { $t[$Language] } else { $c }
    }
    $Catalog.CategoryNames = $namen
}

# Der Name einer Kategorie in der eingestellten Sprache.
function Get-UwhCategoryName {
    param($Catalog, [string]$Key)
    if ($Catalog.CategoryNames.ContainsKey($Key)) { return $Catalog.CategoryNames[$Key] }
    return $Key
}

# ------------------------------------------------------------------
# Zugriff
# ------------------------------------------------------------------

# Schlichte Schleifen statt Where-Object: das wird in jedem Schritt gebraucht
# und waere bei vielen eigenen Eintraegen sonst spuerbar langsam.
function Get-UwhEntry {
    param($Catalog, [string]$Key)
    foreach ($e in $Catalog.Entries) { if ($e.Key -eq $Key) { return $e } }
    return $null
}

function Get-UwhAction {
    param($Entry, [string]$Name)
    foreach ($a in $Entry.Actions) { if ($a.Name -eq $Name) { return $a } }
    return $null
}

# Sucht in dem, was zu sehen ist, und im englischen Grundtext.
function Find-UwhEntries {
    param($Catalog, [string]$Term)
    if (-not $Term) { return $Catalog.Entries }
    $muster = '*' + [Management.Automation.WildcardPattern]::Escape($Term.Trim()) + '*'
    $Catalog.Entries | Where-Object {
        $_.Name -like $muster -or $_.Key -like $muster -or $_.Description -like $muster -or
        (Get-UwhCategoryName $Catalog $_.Category) -like $muster -or
        $_.Texte.description[''] -like $muster -or $_.Category -like $muster
    }
}
