# uwh - unknown windows helper

Software für Windows auswählen, in einem Rutsch installieren und die Auswahl als
Profil speichern. Beim nächsten Rechner ein Befehl, kein Klick.

Windows-Gegenstück zu [ulh](https://github.com/sorglos-it/ulh).

## Einrichten

PowerShell öffnen und einfügen:

```powershell
irm https://raw.githubusercontent.com/sorglos-it/uwh/main/install.ps1 | iex
```

Danach liegt eine Verknüpfung **uwh** auf dem Desktop. Mehr ist nicht nötig —
kein git, keine Zusatzmodule.

Für Rollouts ohne Internetzugang lässt sich das Archiv auch aus dem eigenen Netz
holen, wahlweise ganz still:

```powershell
.\install.ps1 -Quelle \server\freigabe\uwh-main.zip -KeineVerknuepfung -KeinStart
```

## Bedienen

```
+============================================================================+
|  uwh - unknown windows helper                                      v0.1.0  |
+============================================================================+
|  Was soll installiert werden?                                              |
+============================================================================+
|                                                                            |
|  GRUNDAUSSTATTUNG                                                          |
|    [x] 7-Zip                    Packt und entpackt Archive                 |
|  > [ ] Everything               Findet Dateien sofort                      |
|    [ ] Microsoft PowerToys      Zusatzwerkzeuge fuer Windows               |
|    [x] Notepad++                Texteditor                      installiert|
|    [ ] Rufus                    Erstellt bootfaehige USB-Sticks            |
|  BROWSER                                                                   |
|    [x] Mozilla Firefox          Webbrowser                                 |
|                                                                            |
+============================================================================+
|  Pfeile Bewegen   LEER An/Aus   ENTER Weiter   / Suchen   ESC Beenden      |
|  A alle an/aus    P Profil laden    M Modus: Installieren                  |
|                                                          5 ausgewaehlt     |
+============================================================================+
```

| Taste | Wirkung |
|---|---|
| Pfeile | Auf und ab |
| Leertaste | An- und abwählen |
| Enter | Weiter zur Zusammenfassung |
| `/` | Suchen |
| `A` | Alles an- oder abwählen |
| `P` | Gespeichertes Profil laden |
| `M` | Modus wechseln: Installieren → Aktualisieren → Entfernen |
| Esc | Suche löschen, sonst beenden |

Der Modus entscheidet, was mit der Auswahl geschieht. Angezeigt wird immer nur,
was der jeweilige Modus auch kann — Windows-Funktionen lassen sich nicht
aktualisieren, eigene Skripte nicht entfernen. Ein Moduswechsel setzt die
Auswahl zurück, damit nie unklar ist, was gleich passiert.

Alle Rückfragen kommen **vor** der Installation. Danach läuft alles ohne
Unterbrechung durch — auch über einen Neustart hinweg.

Die Spalte **installiert** zeigt, was winget auf dem Rechner findet. Bei
Windows-Funktionen und optionalen Komponenten bleibt sie leer: das lässt sich
nur mit Administratorrechten feststellen, und das Menü läuft bewusst ohne sie —
die werden erst zur Ausführung angefordert.

## Profile

Nach der Auswahl fragt uwh, ob sie als Profil gespeichert werden soll. Das Profil
merkt sich, **was** installiert wird und **wie** geantwortet wurde.

```powershell
.\uwh.ps1 -Profile Arbeitsplatz              # mit Zusammenfassung
.\uwh.ps1 -Profile Arbeitsplatz -Unattended  # ohne jede Rückfrage
```

Profile liegen als Textdatei in `custom\profiles\` und lassen sich weitergeben.
**Kennwörter werden nicht gespeichert.** Maßgeblich ist `type: secret` in
`config.yaml` — das ist eine Ansage des Katalogs, kein Raten. Zusätzlich greift
ein Namensfilter für Fälle, in denen der Typ vergessen wurde (`PASSWORT`, `PWD`,
`API_KEY`, `…SCHLUESSEL`, `…PIN` und ähnliche). Der Katalog kann Geheimhaltung
nur hinzufügen, nie aufheben.

## Befehle

```powershell
.\uwh.ps1                      # Menü
.\uwh.ps1 -Profile <name>      # Profil abspielen
.\uwh.ps1 -List                # Katalog anzeigen
.\uwh.ps1 -Doctor              # Prüfen, ob alles bereit ist
.\uwh.ps1 -Resume <kennung>    # Unterbrochenen Lauf fortsetzen
.\uwh.ps1 -NoUpdate            # Ohne Selbstaktualisierung starten
.\uwh.ps1 -NoScan              # Schneller starten, vorhandene Programme nicht prüfen
```

## Eigene Programme aufnehmen

Der Katalog ist eine einzige Datei: `config.yaml`. Ein neuer Eintrag ist meist
sechs Zeilen und kein Code.

```yaml
  meintool:
    name: Mein Werkzeug
    description: Was es macht
    category: Grundausstattung
    provider: winget
    id: Hersteller.Werkzeug
```

`provider` bestimmt den Installationsweg:

| provider | wofür | Pflichtfeld |
|---|---|---|
| `winget` | normale Programme | `id` |
| `msstore` | Apps aus dem Microsoft Store | `id` |
| `feature` | Windows-Funktionen (WSL2, Hyper-V) | `id` |
| `capability` | optionale Komponenten (OpenSSH) | `id` |
| `url` | direkter Download | `url`, `args`, `sha256` |
| `psmodule` | PowerShell-Module | `id` |
| `script` | eigenes Skript in `scripts\` | `file` |

Für alles, was sich nicht deklarieren lässt, gibt es `provider: script`. Vorlage:
[`scripts\_template.ps1`](scripts/_template.ps1). Zwei Regeln:

- **Fragen gehören in `config.yaml`, nicht ins Skript.** Nur so kann uwh sie vorab
  sammeln und in Profilen speichern. Die Antworten kommen als
  Umgebungsvariablen an.
- **Das Skript läuft in einem eigenen Prozess.** Es kann uwh weder durcheinander-
  bringen noch dessen Funktionen ersetzen. Umgekehrt teilt es sich nichts mit uwh
  außer den Umgebungsvariablen. Rückgabe `0` = erledigt, `3010` = erledigt, aber
  Windows muss neu starten, alles andere = Fehler.

Danach prüfen — **beides**, der zweite Schritt ist der wichtige:

```powershell
.\uwh.ps1 -Doctor
```

```powershell
powershell -ExecutionPolicy Bypass -File tests\online.tests.ps1
```

`-Doctor` prüft den Aufbau des Katalogs, `online.tests.ps1` prüft, ob es jedes
Paket wirklich gibt. Paketkennungen veralten: Hersteller benennen um, Pakete
verschwinden aus der Quelle. Beim Aufbau dieses Katalogs waren 5 von 46
selbstgeschriebenen Kennungen falsch — geraten wird hier nichts.

## Neustarts

Windows-Funktionen wie WSL2 verlangen einen Neustart. uwh merkt sich den Stand,
legt eine Aufgabe für die Anmeldung an und macht danach allein weiter. Ein
unterbrochener Lauf lässt sich jederzeit von Hand fortsetzen:

```powershell
.\uwh.ps1 -Resume <kennung>
```

## uwh von einem Netzlaufwerk starten

Geht, braucht aber keinen Handgriff: ein Programm mit Administratorrechten sieht
**zugeordnete Netzlaufwerke nicht** — die Zuordnung hängt an der Anmeldesitzung,
und der Administrator-Token ist eine andere. `Z:\...` existiert für ihn schlicht
nicht.

uwh rechnet den eigenen Pfad deshalb vor jeder Rechteerhöhung und vor jeder
Neustart-Fortsetzung auf den UNC-Pfad um (`\server\freigabe\...`).
`.\uwh.ps1 -Doctor` zeigt an, ob das greift.

## Was uwh nicht macht

- Keine Bloatware-Entfernung, keine Telemetrie-Tweaks. Solche Eingriffe brechen
  bei jedem Windows-Update und gehören nicht in ein Installationswerkzeug.
- Kein Chocolatey und kein Scoop parallel zu winget. Ein Paketmanager, ein
  Zustand, keine doppelt installierten Programme.

## Voraussetzungen

- Windows 10 (ab 1709) oder Windows 11
- Windows PowerShell 5.1 (ist ab Werk dabei)
- winget — bei Windows 11 dabei, bei Windows 10 als **App Installer** im Store

`.\uwh.ps1 -Doctor` sagt, ob etwas fehlt.

## Wenn PowerShell die Ausführung verweigert

```powershell
powershell -ExecutionPolicy Bypass -File .\uwh.ps1
```

Die Desktop-Verknüpfung macht das bereits von selbst.

## Aufbau

```
uwh.ps1              Einstieg
install.ps1          Einrichtung per Einzeiler
config.yaml          Katalog - hier kommen eigene Programme rein
VERSION              Versionsnummer, steuert die Selbstaktualisierung
lib\                 Programmteile
  core.ps1             Ausgabe, Rechte, Prüfungen
  yaml.ps1             YAML lesen und schreiben
  catalog.ps1          Katalog einlesen und prüfen
  providers.ps1        die Installationswege
  menu.ps1             Menü und Abfragen
  execute.ps1          Ablauf, Neustart, Protokoll
  profiles.ps1         Profile
  update.ps1           Selbstaktualisierung
scripts\             eigene Skripte (provider: script)
custom\profiles\     gespeicherte Profile
tests\               Tests (6 Dateien, 126 ohne Systemzugriff)
```

Protokolle und Laufzeitdaten liegen unter `%LOCALAPPDATA%\uwh`.

## Tests

```powershell
powershell -ExecutionPolicy Bypass -File tests\yaml.tests.ps1
```

```powershell
powershell -ExecutionPolicy Bypass -File tests\ablauf.tests.ps1
```

```powershell
powershell -ExecutionPolicy Bypass -File tests\fortsetzen.tests.ps1
```

```powershell
powershell -ExecutionPolicy Bypass -File tests\provider.tests.ps1
```

```powershell
powershell -ExecutionPolicy Bypass -File tests\einrichtung.tests.ps1
```

```powershell
powershell -ExecutionPolicy Bypass -File tests\online.tests.ps1
```

| Datei | prüft | braucht |
|---|---|---|
| `yaml.tests.ps1` | YAML lesen und schreiben | nichts |
| `ablauf.tests.ps1` | Katalog, Profile, Plan, Ablauf, Menü samt Tastensteuerung, Eingabeprüfung, Selbstaktualisierung, Aufruf über die Befehlszeile | nichts |
| `fortsetzen.tests.ps1` | eigene Skripte, Neustart-Entscheidung, Fortsetzen | nichts |
| `provider.tests.ps1` | Windows-Funktionen, optionale Komponenten, PowerShell-Module | nichts |
| `einrichtung.tests.ps1` | Einrichtung und Selbstaktualisierung von Anfang bis Ende | nichts |
| `online.tests.ps1` | ob es jedes Paket wirklich gibt, und ob der Direkt-Download Prüfsumme und https durchsetzt | Internet, winget; Windows-Einträge zusätzlich Administratorrechte |

Nur `online.tests.ps1` geht ins Netz. Die anderen fünf installieren nichts,
ändern nichts am System und starten nichts neu: der Neustart und die
Windows-Befehle werden durch Attrappen ersetzt, und `einrichtung.tests.ps1` baut
sich ein eigenes Archiv, statt es von GitHub zu holen. Alles davor und danach
läuft echt.

## Lizenz

MIT
