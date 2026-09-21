# uwh - unknown windows helper

Software für Windows auswählen und in einem Rutsch installieren. Die Auswahl
lässt sich als Profil speichern und auf dem nächsten Rechner wiederholen.

Windows-Gegenstück zu [ulh](https://github.com/sorglos-it/ulh).

## Starten

Doppelklick auf **`uwh.cmd`**.

Auf einem neuen Rechner PowerShell öffnen und einfügen:

```powershell
irm https://raw.githubusercontent.com/sorglos-it/uwh/main/install.ps1 | iex
```

Danach liegt **uwh** auf dem Desktop.

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
|    [x] Notepad++                Texteditor                      installiert|
|                                                                            |
+============================================================================+
|  Pfeile Bewegen   LEER An/Aus   ENTER Weiter   / Suchen   ESC Beenden      |
|  A alle an/aus    P Profil laden    M Modus: Installieren                  |
|                                                          2 ausgewaehlt     |
+============================================================================+
```

| Taste | Wirkung |
|---|---|
| Pfeile | auf und ab |
| Leertaste | an- und abwählen |
| Enter | weiter |
| `/` | suchen |
| `A` | alles an oder ab |
| `P` | Profil laden |
| `M` | Installieren → Aktualisieren → Entfernen |
| Esc | beenden |

Alle Fragen kommen vorher. Danach läuft alles allein durch, auch über einen
Neustart hinweg.

## Profile

Nach der Auswahl fragt uwh, ob sie als Profil gespeichert werden soll. Wieder
abspielen:

```powershell
.\uwh.ps1 -Profile Arbeitsplatz
```

Profile liegen in `profiles\`. Kennwörter werden nie gespeichert.

## Eigene Programme

In `config.yaml` eintragen — wie, steht oben in der Datei. Für alles andere ein
eigenes Skript nach der Vorlage `scripts\_template.ps1`.

## Wenn etwas nicht geht

```powershell
.\uwh.ps1 -Doctor
```

Braucht Windows 10 oder 11 und winget (bei Windows 11 dabei, bei Windows 10 als
„App Installer" im Microsoft Store).

## Lizenz

MIT
