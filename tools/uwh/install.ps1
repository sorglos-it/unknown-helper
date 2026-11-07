<#
    uwh einrichten.

    Einzeiler in PowerShell:
        irm https://raw.githubusercontent.com/sorglos-it/unknown-helper/main/tools/uwh/install.ps1 | iex

    Es wird kein git gebraucht. uwh landet unter:
        %LOCALAPPDATA%\Programs\uwh

    Aus dem eigenen Netz statt aus dem Internet:
        .\tools\install.ps1 -Quelle \\server\freigabe\uwh-main.zip

    Still, ohne Desktop-Verknuepfung und ohne Start:
        .\tools\install.ps1 -KeineVerknuepfung -KeinStart

    Sprache wie Windows: de, en, fr, it oder es, sonst Englisch.

    Nur ASCII und ohne BOM speichern: irm reicht einen BOM an iex weiter, das
    daran scheitert - und ohne BOM liest PowerShell 5.1 die Datei als ANSI.
    Umlaute und Akzente deshalb als \u00fc usw. in die Texte schreiben.
#>
[CmdletBinding()]
param(
    [string]$Ziel,
    [string]$Quelle,
    [switch]$KeinStart,
    [switch]$KeineVerknuepfung
)

# Alles Weitere in einem eigenen Block: ueber irm | iex blieben sonst
# $ErrorActionPreference = 'Stop' und die Hilfsfunktionen in der PowerShell
# des Anwenders haengen.
& {
$ErrorActionPreference = 'Stop'
# Ohne Fortschrittsbalken ist der Download in PowerShell 5.1 um ein Vielfaches schneller.
$ProgressPreference = 'SilentlyContinue'

# Als Datei gestartet endet das Skript mit Rueckgabewert 1. Ueber irm | iex laeuft
# es aber in der PowerShell des Anwenders - dort wuerde exit das Fenster
# schliessen, bevor man die Fehlermeldung lesen kann.
$AlsDatei = [bool]$PSCommandPath

# Alle Texte, eine Tabelle je Sprache. {0} steht fuer einen Wert, etwa einen Pfad.
$Texte = @{
    de = @{
        psAlt         = 'Es wird mindestens Windows PowerShell 5.1 gebraucht.'
        laden         = 'Lade uwh herunter...'
        holen         = 'Hole uwh aus {0} ...'
        ohneOrdner    = 'Das Archiv enthielt keinen Ordner.'
        fertig        = 'Eingerichtet unter: {0}'
        linkInfo      = 'uwh - Software ausw\u00e4hlen und installieren'
        link          = 'Verkn\u00fcpfung auf dem Desktop angelegt.'
        linkFehler    = 'Verkn\u00fcpfung konnte nicht angelegt werden.'
        start         = 'uwh startet...'
        startenMit    = 'Starten mit:  {0}'
        fehler        = 'Einrichtung fehlgeschlagen.'
        technisch     = 'Technische Meldung: {0}'
        nichtGefunden = @(
            'uwh wurde unter der angegebenen Adresse nicht gefunden.'
            'M\u00f6gliche Ursachen:'
            '  - das Repository ist (noch) nicht \u00f6ffentlich'
            '  - die Adresse im Skript stimmt nicht mehr'
        )
        verweigert    = 'Der Zugriff wurde verweigert. Das Repository ist vermutlich nicht \u00f6ffentlich.'
        keinNetz      = 'Keine Verbindung zum Internet, oder der Server ist nicht erreichbar.'
        tls           = @(
            'Die gesicherte Verbindung kam nicht zustande.'
            'Meist liegt das an einer Firewall oder an einem Virenscanner, der mitliest.'
        )
        zielGesperrt  = @(
            'Es durfte nicht in den Zielordner geschrieben werden.'
            'L\u00e4uft uwh gerade? Dann bitte erst schlie\u00dfen.'
        )
        allgemein     = 'Bitte Internetverbindung pr\u00fcfen und es noch einmal versuchen.'
    }
    en = @{
        psAlt         = 'Windows PowerShell 5.1 or newer is needed.'
        laden         = 'Downloading uwh...'
        holen         = 'Getting uwh from {0} ...'
        ohneOrdner    = 'The archive did not contain a folder.'
        fertig        = 'Installed in: {0}'
        linkInfo      = 'uwh - pick and install software'
        link          = 'Shortcut created on the desktop.'
        linkFehler    = 'The shortcut could not be created.'
        start         = 'Starting uwh...'
        startenMit    = 'Start with:  {0}'
        fehler        = 'Setup failed.'
        technisch     = 'Technical details: {0}'
        nichtGefunden = @(
            'uwh was not found at the given address.'
            'Possible causes:'
            '  - the repository is not public (yet)'
            '  - the address in the script is out of date'
        )
        verweigert    = 'Access was denied. The repository is probably not public.'
        keinNetz      = 'No connection to the internet, or the server cannot be reached.'
        tls           = @(
            'The secure connection could not be established.'
            'This is usually caused by a firewall or an antivirus program that inspects the connection.'
        )
        zielGesperrt  = @(
            'Writing to the target folder was not allowed.'
            'Is uwh running right now? Then please close it first.'
        )
        allgemein     = 'Please check the internet connection and try again.'
    }
    fr = @{
        psAlt         = 'Il faut au moins Windows PowerShell 5.1.'
        laden         = 'T\u00e9l\u00e9chargement de uwh...'
        holen         = 'R\u00e9cup\u00e9ration de uwh depuis {0} ...'
        ohneOrdner    = 'L''archive ne contient aucun dossier.'
        fertig        = 'Install\u00e9 dans : {0}'
        linkInfo      = 'uwh - choisir et installer des logiciels'
        link          = 'Raccourci cr\u00e9\u00e9 sur le Bureau.'
        linkFehler    = 'Le raccourci n''a pas pu \u00eatre cr\u00e9\u00e9.'
        start         = 'D\u00e9marrage de uwh...'
        startenMit    = 'Pour d\u00e9marrer :  {0}'
        fehler        = 'L''installation a \u00e9chou\u00e9.'
        technisch     = 'D\u00e9tails techniques : {0}'
        nichtGefunden = @(
            'uwh est introuvable \u00e0 l''adresse indiqu\u00e9e.'
            'Causes possibles :'
            '  - le d\u00e9p\u00f4t n''est pas (encore) public'
            '  - l''adresse dans le script n''est plus \u00e0 jour'
        )
        verweigert    = 'L''acc\u00e8s a \u00e9t\u00e9 refus\u00e9. Le d\u00e9p\u00f4t n''est probablement pas public.'
        keinNetz      = 'Pas de connexion \u00e0 Internet, ou le serveur est injoignable.'
        tls           = @(
            'La connexion s\u00e9curis\u00e9e n''a pas pu \u00eatre \u00e9tablie.'
            'C''est souvent d\u00fb \u00e0 un pare-feu ou \u00e0 un antivirus qui analyse la connexion.'
        )
        zielGesperrt  = @(
            'L''\u00e9criture dans le dossier cible a \u00e9t\u00e9 refus\u00e9e.'
            'uwh est-il ouvert ? Si oui, veuillez d''abord le fermer.'
        )
        allgemein     = 'Veuillez v\u00e9rifier la connexion Internet et r\u00e9essayer.'
    }
    it = @{
        psAlt         = 'Occorre almeno Windows PowerShell 5.1.'
        laden         = 'Download di uwh in corso...'
        holen         = 'Recupero di uwh da {0} ...'
        ohneOrdner    = 'L''archivio non contiene alcuna cartella.'
        fertig        = 'Installato in: {0}'
        linkInfo      = 'uwh - scegliere e installare software'
        link          = 'Collegamento creato sul desktop.'
        linkFehler    = 'Impossibile creare il collegamento.'
        start         = 'Avvio di uwh in corso...'
        startenMit    = 'Per avviare:  {0}'
        fehler        = 'Installazione non riuscita.'
        technisch     = 'Dettagli tecnici: {0}'
        nichtGefunden = @(
            'uwh non \u00e8 stato trovato all''indirizzo indicato.'
            'Possibili cause:'
            '  - il repository non \u00e8 (ancora) pubblico'
            '  - l''indirizzo nello script non \u00e8 pi\u00f9 valido'
        )
        verweigert    = 'Accesso negato. Probabilmente il repository non \u00e8 pubblico.'
        keinNetz      = 'Nessuna connessione a Internet, oppure il server non \u00e8 raggiungibile.'
        tls           = @(
            'Impossibile stabilire la connessione sicura.'
            'Di solito la causa \u00e8 un firewall o un antivirus che controlla la connessione.'
        )
        zielGesperrt  = @(
            'Non \u00e8 consentito scrivere nella cartella di destinazione.'
            'uwh \u00e8 aperto? In tal caso, chiuderlo prima.'
        )
        allgemein     = 'Controllare la connessione a Internet e riprovare.'
    }
    es = @{
        psAlt         = 'Se necesita al menos Windows PowerShell 5.1.'
        laden         = 'Descargando uwh...'
        holen         = 'Obteniendo uwh desde {0} ...'
        ohneOrdner    = 'El archivo comprimido no contiene ninguna carpeta.'
        fertig        = 'Instalado en: {0}'
        linkInfo      = 'uwh - elegir e instalar software'
        link          = 'Acceso directo creado en el escritorio.'
        linkFehler    = 'No se pudo crear el acceso directo.'
        start         = 'Iniciando uwh...'
        startenMit    = 'Para iniciar:  {0}'
        fehler        = 'No se pudo completar la instalaci\u00f3n.'
        technisch     = 'Detalles t\u00e9cnicos: {0}'
        nichtGefunden = @(
            'No se encontr\u00f3 uwh en la direcci\u00f3n indicada.'
            'Posibles causas:'
            '  - el repositorio (todav\u00eda) no es p\u00fablico'
            '  - la direcci\u00f3n del script ya no es correcta'
        )
        verweigert    = 'Acceso denegado. Probablemente el repositorio no es p\u00fablico.'
        keinNetz      = 'No hay conexi\u00f3n a Internet o no se puede acceder al servidor.'
        tls           = @(
            'No se pudo establecer la conexi\u00f3n segura.'
            'Suele deberse a un firewall o a un antivirus que analiza la conexi\u00f3n.'
        )
        zielGesperrt  = @(
            'No se permiti\u00f3 escribir en la carpeta de destino.'
            '\u00bfEst\u00e1 abierto uwh? En ese caso, hay que cerrarlo primero.'
        )
        allgemein     = 'Conviene comprobar la conexi\u00f3n a Internet y volver a intentarlo.'
    }
}

# Sprache von Windows - fehlt sie oben, gilt Englisch.
$Sprache = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
if (-not $Texte.ContainsKey($Sprache)) { $Sprache = 'en' }

# Text in dieser Sprache: \u00fc wird zum Zeichen, {0} zum Wert. Bewusst nicht
# [regex]::Unescape - das wuerde auch jeden anderen Backslash auswerten.
function Get-Text {
    param([string]$Name)
    foreach ($zeile in $Texte[$Sprache][$Name]) {
        [regex]::Replace($zeile, '\\u([0-9a-fA-F]{4})', {
            param($m)
            [string][char][Convert]::ToInt32($m.Groups[1].Value, 16)
        }) -f $args
    }
}

# Ohne Angabe von GitHub. Mit -Quelle geht auch ein Archiv aus dem eigenen
# Netz - fuer Rollouts ohne Internetzugang.
$Zip = 'https://codeload.github.com/sorglos-it/unknown-helper/zip/refs/heads/main'
if ($Quelle) {
    if (Test-Path -LiteralPath $Quelle) {
        $Zip = ([uri]((Resolve-Path -LiteralPath $Quelle).ProviderPath)).AbsoluteUri
    } else {
        $Zip = $Quelle
    }
}

if (-not $Ziel) { $Ziel = Join-Path $env:LOCALAPPDATA 'Programs\uwh' }

Write-Host ''
Write-Host '  uwh - unknown windows helper' -ForegroundColor Cyan
Write-Host '  ----------------------------' -ForegroundColor DarkGray
Write-Host ''

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "  $(Get-Text psAlt)" -ForegroundColor Red
    if ($AlsDatei) { exit 1 } else { return }
}

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
} catch { }

# Aus einer technischen Meldung etwas machen, mit dem man etwas anfangen kann.
# Die Muster passen auf die Meldungen von Windows, deutsch und englisch.
function Get-Klartext {
    param($Fehler)

    $text = [string]$Fehler.Exception.Message
    $status = ''
    if ($Fehler.Exception -is [Net.WebException] -and $Fehler.Exception.Response) {
        $status = [string][int]$Fehler.Exception.Response.StatusCode
    }

    if ($status -eq '404' -or $text -match '\(404\)') { return Get-Text nichtGefunden }
    if ($status -eq '403' -or $status -eq '401') { return Get-Text verweigert }
    if ($text -match 'Remotename|remote name|NameResolution|konnte nicht aufgel') { return Get-Text keinNetz }
    if ($text -match 'SSL|TLS|Vertrauensstellung|trust relationship') { return Get-Text tls }
    if ($text -match 'Zugriff verweigert|Access to the path|UnauthorizedAccess') { return Get-Text zielGesperrt }
    return Get-Text allgemein
}

$tmp = Join-Path $env:TEMP ('uwh-setup-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$zipFile = "$tmp.zip"

try {
    if ($Quelle) { Write-Host "  $(Get-Text holen $Quelle)" } else { Write-Host "  $(Get-Text laden)" }
    Invoke-WebRequest -Uri $Zip -OutFile $zipFile -UseBasicParsing -ErrorAction Stop

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $tmp)

    # Nicht '$quelle' nennen: PowerShell unterscheidet keine Gross- und
    # Kleinschreibung, das waere der Parameter -Quelle vom Typ [string].
    $entpackt = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
    if (-not $entpackt) { throw (Get-Text ohneOrdner) }

    if (-not (Test-Path $Ziel)) { New-Item -ItemType Directory -Path $Ziel -Force | Out-Null }

    # Alles Eigene bleibt bei einer Neuinstallation erhalten: apps\cli-uwh\data und
    # die eigenen Einstellungen. Im Archiv ist nichts davon, nur config\*.example.
    $auslassen = @('apps\cli-uwh\data', 'apps\cli-uwh\config\repo.yaml', 'apps\cli-uwh\config\settings.yaml')

    # Copy-Item -Recurse wuerde einen vorhandenen Zielordner verschachteln.
    function Kopiere-Baum {
        param([string]$Von, [string]$Nach, [string[]]$Aus = @(), [string]$Rel = '')
        if (-not (Test-Path -LiteralPath $Nach)) {
            New-Item -ItemType Directory -Path $Nach -Force | Out-Null
        }
        foreach ($i in Get-ChildItem -LiteralPath $Von -Force) {
            $r = if ($Rel) { Join-Path $Rel $i.Name } else { $i.Name }
            if ($Aus -contains $r) { continue }
            $z = Join-Path $Nach $i.Name
            if ($i.PSIsContainer) { Kopiere-Baum $i.FullName $z $Aus $r }
            else { Copy-Item -LiteralPath $i.FullName -Destination $z -Force }
        }
    }
    Kopiere-Baum $entpackt.FullName $Ziel $auslassen

    Write-Host "  $(Get-Text fertig $Ziel)" -ForegroundColor Green

    # Verknuepfung auf dem Desktop, damit man es wiederfindet.
    # Bei stillen Rollouts nicht erwuenscht - dann -KeineVerknuepfung.
    if (-not $KeineVerknuepfung) {
    try {
        $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'uwh.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $s = $shell.CreateShortcut($lnk)
        $s.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $s.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $Ziel 'apps\cli-uwh\uwh.ps1')
        $s.WorkingDirectory = (Join-Path $Ziel 'apps\cli-uwh')
        $s.IconLocation = 'shell32.dll,165'
        $s.Description = Get-Text linkInfo
        $s.Save()
        Write-Host "  $(Get-Text link)" -ForegroundColor Green
    } catch {
        Write-Host "  $(Get-Text linkFehler)" -ForegroundColor DarkGray
    }
    }

    Write-Host ''
    if (-not $KeinStart) {
        Write-Host "  $(Get-Text start)"
        Write-Host ''
        & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
            '-NoProfile' '-ExecutionPolicy' 'Bypass' '-File' (Join-Path $Ziel 'apps\cli-uwh\uwh.ps1')
    } else {
        Write-Host "  $(Get-Text startenMit (Join-Path $Ziel 'apps\cli-uwh\uwh.cmd'))"
        Write-Host ''
    }
} catch {
    Write-Host ''
    Write-Host "  $(Get-Text fehler)" -ForegroundColor Red
    Write-Host ''
    foreach ($zeile in (Get-Klartext $_)) { Write-Host "  $zeile" -ForegroundColor Yellow }
    Write-Host ''
    Write-Host "  $(Get-Text technisch $_.Exception.Message)" -ForegroundColor DarkGray
    Write-Host ''
    if ($AlsDatei) { exit 1 } else { return }
} finally {
    Remove-Item -LiteralPath $zipFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
}
