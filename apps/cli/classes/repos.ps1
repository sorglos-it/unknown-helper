# uwh - Eigene Repos: config\repo.yaml lesen, per git holen, Kataloge finden
#
# Das Modell stammt aus ulh (custom/ dort): alles Eigene liegt getrennt, und die
# Aktualisierung von uwh fasst es nie an. Nach dem Projektstandard heisst das hier
# config\ (Einstellungen, im Repo nur *.example) und data\ (Profile,
# Schluessel, eigene Repos - nicht im Repo). Eigene Programme stehen deshalb nicht
# im Katalog von uwh, sondern in eigenen Repos - jedes mit eigener config.yaml
# und eigenem scripts\.
#
# Unterschied zu ulh: git ist unter Windows nicht immer installiert. Ein
# eigenes Repo funktioniert deshalb immer als lokaler Ordner und wird nur dann
# per git geholt, wenn eine Adresse eingetragen und git vorhanden ist.

Set-StrictMode -Version 2.0

$script:UwhRepoAuth = @('none', 'ssh', 'https_token', 'https_basic')
$script:UwhGitPath = $null
$script:UwhGitGewarnt = $false

function Get-UwhConfigDir { Get-UwhPath 'config' }
function Get-UwhDataDir { Get-UwhPath 'data' }

# ulh setzt Schalter durch blosses Vorhandensein ('enabled:' ohne Wert). Das
# bleibt so. Ein ausdrueckliches 'false' schaltet trotzdem ab - alles andere
# waere eine Falle fuer jeden, der ulh nicht kennt.
function Test-UwhSchalter {
    param($Daten, [string]$Name)

    if (-not ($Daten -is [System.Collections.IDictionary])) { return $false }
    if (-not $Daten.Contains($Name)) { return $false }

    $wert = $Daten[$Name]
    if ($null -eq $wert) { return $true }
    if ($wert -is [bool]) { return $wert }
    return ([string]$wert -notmatch '^(false|nein|no|0|aus|off)$')
}

# Erlaubt: https, ssh, git@host:pfad und file:/// (lokale Spiegel). Kein http.
function Test-UwhRepoUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    return ($Url -match '^(https://[A-Za-z0-9.\-]+(:\d+)?/|ssh://|file:///|git@[A-Za-z0-9.\-]+:)')
}

# ${NAME} durch die gleichnamige Umgebungsvariable ersetzen, wie bei ulh.
# So stehen Token und Kennwoerter nie in repo.yaml.
function Expand-UwhVariable {
    param([string]$Text)
    if (-not $Text) { return '' }
    return [regex]::Replace($Text, '\$\{([A-Za-z_][A-Za-z0-9_]*)\}', {
        param($m)
        [string][Environment]::GetEnvironmentVariable($m.Groups[1].Value)
    })
}

# ------------------------------------------------------------------
# config\repo.yaml lesen
# ------------------------------------------------------------------

function Get-UwhRepos {
    param([string]$Datei)

    if (-not $Datei) { $Datei = Join-Path (Get-UwhConfigDir) 'repo.yaml' }

    $repos = New-Object System.Collections.Generic.List[object]
    $probleme = New-Object System.Collections.Generic.List[string]
    $einstellungen = [pscustomobject]@{ BeimStart = $true; Versuche = 3; Pause = 5 }

    $leer = [pscustomobject]@{ Repos = @(); Probleme = @(); Einstellungen = $einstellungen }
    if (-not (Test-Path -LiteralPath $Datei)) { return $leer }

    try {
        $raw = Import-UwhYaml $Datei
    } catch {
        $leer.Probleme = @("repo.yaml: $($_.Exception.Message)")
        return $leer
    }
    if (-not $raw) { return $leer }

    $u = Get-UwhField $raw 'update_settings'
    if ($u -is [System.Collections.IDictionary]) {
        if ($u.Contains('auto_update_on_start')) { $einstellungen.BeimStart = Test-UwhSchalter $u 'auto_update_on_start' }
        $v = Get-UwhField $u 'retry_on_failure'
        if ($v -is [int] -and $v -ge 1 -and $v -le 10) { $einstellungen.Versuche = $v }
        $p = Get-UwhField $u 'retry_delay_seconds'
        if ($p -is [int] -and $p -ge 0 -and $p -le 60) { $einstellungen.Pause = $p }
    }

    $liste = Get-UwhField $raw 'repositories'
    if ($liste -is [System.Collections.IDictionary]) {
        foreach ($id in $liste.Keys) {
            try {
                $repos.Add((ConvertTo-UwhRepo ([string]$id) $liste[$id]))
            } catch {
                $probleme.Add(("repo.yaml, {0}: {1}" -f $id, $_.Exception.Message))
            }
        }
    }

    [pscustomobject]@{
        Repos         = $repos.ToArray()
        Probleme      = $probleme.ToArray()
        Einstellungen = $einstellungen
    }
}

function ConvertTo-UwhRepo {
    param([string]$Id, $Daten)

    if (-not (Test-UwhSafeName $Id)) { throw 'Kennung enthaelt unerlaubte Zeichen.' }
    if (-not ($Daten -is [System.Collections.IDictionary])) { $Daten = [ordered]@{} }

    # Der Ordner liegt immer unter data\. Anders als ulh erlaubt uwh keine
    # absoluten Pfade: eigene Repos sollen genau dort liegen, wo das Update sie
    # nie anfasst.
    $ordner = [string](Get-UwhField $Daten 'path')
    if (-not $ordner) { $ordner = $Id }
    if (-not (Test-UwhSafeName $ordner)) { throw "path '$ordner' muss ein einfacher Ordnername sein." }
    if ($ordner -in @('profiles', 'keys', 'state', 'logs')) { throw "path '$ordner' ist fuer uwh selbst reserviert." }

    $url = [string](Get-UwhField $Daten 'url')
    if ($url -and -not (Test-UwhRepoUrl $url)) {
        throw "url '$url' ist keine erlaubte Adresse (https, ssh, git@... oder file:///)."
    }

    $auth = [string](Get-UwhField $Daten 'auth_method')
    if (-not $auth) { $auth = 'none' }
    if ($script:UwhRepoAuth -notcontains $auth) { throw "auth_method '$auth' gibt es nicht." }

    $name = [string](Get-UwhField $Daten 'name')
    if (-not $name) { $name = $Id }

    [pscustomobject]@{
        Id         = $Id
        Name       = $name
        Url        = $url
        Ordner     = $ordner
        Pfad       = Join-Path (Get-UwhDataDir) $ordner
        Auth       = $auth
        SshKey     = [string](Get-UwhField $Daten 'ssh_key')
        Token      = [string](Get-UwhField $Daten 'token')
        Benutzer   = [string](Get-UwhField $Daten 'username')
        Kennwort   = [string](Get-UwhField $Daten 'password')
        Aktiv      = Test-UwhSchalter $Daten 'enabled'
        AutoUpdate = Test-UwhSchalter $Daten 'auto_update'
    }
}

# Beim ersten Start die eigenen Dateien aus den Vorlagen anlegen. Vorhandenes
# wird nie ueberschrieben - das gehoert dem Anwender.
function Initialize-UwhEigenes {
    $paare = @(
        @{ Von = (Get-UwhPath 'config\repo.yaml.example'); Nach = (Join-Path (Get-UwhConfigDir) 'repo.yaml') }
        @{ Von = (Get-UwhPath 'templates\eigene.yaml');      Nach = (Join-Path (Get-UwhDataDir) 'eigene\config.yaml') }
    )
    # Das Beispielprofil nur beim allerersten Start - wer es loescht, will es nicht zurueck.
    $profilOrdner = Join-Path (Get-UwhDataDir) 'profiles'
    if (-not (Test-Path -LiteralPath $profilOrdner)) {
        $paare += @{ Von = (Get-UwhPath 'templates\beispiel-profil.yaml'); Nach = (Join-Path $profilOrdner 'beispiel.yaml') }
    }

    foreach ($p in $paare) {
        if ((Test-Path -LiteralPath $p.Nach) -or -not (Test-Path -LiteralPath $p.Von)) { continue }
        try {
            New-Item -ItemType Directory -Path (Split-Path -Parent $p.Nach) -Force | Out-Null
            Copy-Item -LiteralPath $p.Von -Destination $p.Nach -ErrorAction Stop
        } catch {
            Write-UwhLog 'WARN' ("Vorlage nicht angelegt: {0} - {1}" -f $p.Nach, $_.Exception.Message)
        }
    }
}

# Die Kataloge der Repos, die im Menue erscheinen sollen.
function Get-UwhRepoKataloge {
    param($Info)
    if (-not $Info) { $Info = Get-UwhRepos }
    foreach ($r in $Info.Repos) {
        if (-not $r.Aktiv) { continue }
        $datei = Join-Path $r.Pfad 'config.yaml'
        if (Test-Path -LiteralPath $datei) {
            [pscustomobject]@{ Repo = $r; Datei = $datei }
        }
    }
}

# ------------------------------------------------------------------
# git
# ------------------------------------------------------------------

function Get-UwhGit {
    if ($script:UwhGitPath) { return $script:UwhGitPath }
    $cmd = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($cmd) { $script:UwhGitPath = $cmd.Source }
    return $script:UwhGitPath
}

# SSH-Schluessel: erst data\keys\, dann ~/.ssh/ - wie bei ulh (custom/keys/ dort).
function Resolve-UwhSshKey {
    param([string]$Name)

    $Name = Expand-UwhVariable $Name
    if (-not $Name) { return $null }
    if ([IO.Path]::IsPathRooted($Name)) {
        if (Test-Path -LiteralPath $Name) { return $Name }
        return $null
    }
    foreach ($ort in @((Join-Path (Get-UwhDataDir) 'keys'), (Join-Path $env:USERPROFILE '.ssh'))) {
        $kandidat = Join-Path $ort $Name
        if (Test-Path -LiteralPath $kandidat) { return $kandidat }
    }
    return $null
}

# Fuehrt git fuer ein Repo aus. Zugangsdaten gehen ueber die Umgebung an git,
# nie ueber die Adresse: ulh baut sie in die URL ein, und dort landen sie im
# Klartext in .git/config des geholten Repos. Hier nicht.
function Invoke-UwhGit {
    param([Parameter(Mandatory)]$Repo, [Parameter(Mandatory)][string[]]$Argumente)

    $git = Get-UwhGit
    if (-not $git) { return [pscustomobject]@{ Code = -1; Output = 'git fehlt' } }

    $setzen = [ordered]@{
        # Nie auf eine Eingabe warten - uwh laeuft auch unbeaufsichtigt.
        GIT_TERMINAL_PROMPT = '0'
    }

    switch ($Repo.Auth) {
        'ssh' {
            $befehl = 'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new'
            $schluessel = Resolve-UwhSshKey $Repo.SshKey
            if ($schluessel) {
                $befehl += ' -o IdentitiesOnly=yes -i "' + ($schluessel -replace '\\', '/') + '"'
            }
            $setzen['GIT_SSH_COMMAND'] = $befehl
        }
        'https_token' {
            $kopf = ConvertTo-UwhBasicAuth (Expand-UwhVariable $Repo.Token) ''
            if ($kopf) { $g = Get-UwhGitKopf $kopf; foreach ($k in $g.Keys) { $setzen[$k] = $g[$k] } }
        }
        'https_basic' {
            $kopf = ConvertTo-UwhBasicAuth (Expand-UwhVariable $Repo.Benutzer) (Expand-UwhVariable $Repo.Kennwort)
            if ($kopf) { $g = Get-UwhGitKopf $kopf; foreach ($k in $g.Keys) { $setzen[$k] = $g[$k] } }
        }
    }

    $alt = @{}
    try {
        foreach ($k in $setzen.Keys) {
            $alt[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
            [Environment]::SetEnvironmentVariable($k, [string]$setzen[$k], 'Process')
        }
        return Invoke-UwhExe $git $Argumente
    } finally {
        foreach ($k in $alt.Keys) {
            [Environment]::SetEnvironmentVariable($k, $alt[$k], 'Process')
        }
    }
}

# Wie ulh: bei https_token ist das Token der Benutzername, das Kennwort leer.
function ConvertTo-UwhBasicAuth {
    param([string]$Benutzer, [string]$Kennwort)
    if (-not $Benutzer) { return $null }
    $roh = [Text.Encoding]::UTF8.GetBytes("${Benutzer}:$Kennwort")
    return 'Authorization: Basic ' + [Convert]::ToBase64String($roh)
}

# Konfiguration ueber die Umgebung statt ueber die Befehlszeile, damit das
# Geheimnis auch in der Prozessliste nicht auftaucht (git ab 2.31).
function Get-UwhGitKopf {
    param([string]$Kopf)
    [ordered]@{
        GIT_CONFIG_COUNT   = '1'
        GIT_CONFIG_KEY_0   = 'http.extraHeader'
        GIT_CONFIG_VALUE_0 = $Kopf
    }
}

# ------------------------------------------------------------------
# Holen und aktualisieren
# ------------------------------------------------------------------
#
# Logik wie bei ulh (repo_sync_one):
#   Ordner da  -> nur mit auto_update und git-Adresse aktualisieren
#   Ordner weg -> nur mit enabled und Adresse holen; ohne Adresse ist es ein
#                 lokales Repo, das der Anwender selbst anlegt
#   enabled und auto_update sind unabhaengig voneinander.

function Sync-UwhRepos {
    param($Info, [switch]$Quiet)

    if (-not $Info) { $Info = Get-UwhRepos }
    if (-not $Info.Einstellungen.BeimStart) { return }

    foreach ($r in $Info.Repos) {
        $hatOrdner = Test-Path -LiteralPath $r.Pfad

        if ($hatOrdner) {
            $istGit = Test-Path -LiteralPath (Join-Path $r.Pfad '.git')
            if ($istGit -and $r.AutoUpdate -and $r.Url) {
                [void](Invoke-UwhRepoMitWiederholung $r 'pull' $Info.Einstellungen $Quiet)
            }
            continue
        }

        if (-not $r.Aktiv -or -not $r.Url) { continue }
        [void](Invoke-UwhRepoMitWiederholung $r 'clone' $Info.Einstellungen $Quiet)
    }
}

function Invoke-UwhRepoMitWiederholung {
    param($Repo, [string]$Was, $Einstellungen, [bool]$Quiet)

    if (-not (Get-UwhGit)) {
        if (-not $script:UwhGitGewarnt -and -not $Quiet) {
            Write-UwhWarn 'git fehlt - eigene Repos aus dem Netz werden nicht geholt. Lokale Repos gehen weiterhin.'
            $script:UwhGitGewarnt = $true
        }
        return $false
    }

    if ($Was -eq 'clone') {
        if (-not $Quiet) { Write-UwhInfo "Hole eigenes Repo '$($Repo.Name)'..." }
        $argumente = @('clone', '--quiet', $Repo.Url, $Repo.Pfad)
    } else {
        if (-not $Quiet) { Write-UwhInfo "Aktualisiere eigenes Repo '$($Repo.Name)'..." }
        # safe.directory nur fuer diesen einen Aufruf: auf dem NAS gehoert der
        # Ordner einer fremden Kennung, und git verweigert sonst die Arbeit.
        $argumente = @('-c', 'safe.directory=*', '-C', $Repo.Pfad, 'pull', '--ff-only', '--quiet')
    }

    for ($i = 1; $i -le $Einstellungen.Versuche; $i++) {
        $r = Invoke-UwhGit $Repo $argumente
        if ($r.Code -eq 0) { return $true }
        if ($i -lt $Einstellungen.Versuche -and $Einstellungen.Pause -gt 0) {
            Start-Sleep -Seconds $Einstellungen.Pause
        }
    }

    if (-not $Quiet) {
        $was = if ($Was -eq 'clone') { 'geholt' } else { 'aktualisiert' }
        Write-UwhWarn "Eigenes Repo '$($Repo.Name)' konnte nicht $was werden. Details im Protokoll."
    }
    return $false
}
