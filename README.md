# uwh - unknown windows helper

Software für Windows auswählen und in einem Rutsch installieren. Die Auswahl
lässt sich als Profil speichern und auf dem nächsten Rechner wiederholen.
Windows-Gegenstück zu [ulh](https://github.com/sorglos-it/ulh).

| Ordner | Zweck | Sprache | Start | Build |
|---|---|---|---|---|
| `apps/cli` | Software auswählen und installieren | PowerShell 5.1 | `apps\cli\uwh.cmd` | keiner nötig |

## Start in 3 Schritten

1. **PowerShell** öffnen: Startmenü, `PowerShell` eintippen, Enter.
2. Diese Zeile einfügen, Enter:
   ```powershell
   irm https://raw.githubusercontent.com/sorglos-it/uwh/main/tools/install.ps1 | iex
   ```
3. Künftig auf dem Desktop **uwh** doppelklicken.

Schon eine Kopie des Ordners da? Dann reicht ein Doppelklick auf
**`apps\cli\uwh.cmd`**.

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
abspielen, im Ordner `apps\cli`:

```powershell
.\uwh.ps1 -Profile Arbeitsplatz
```

Profile liegen in `apps\cli\data\profiles\`. Kennwörter werden nie gespeichert.

## Eigene Programme

In `apps\cli\data\eigene\config.yaml` eintragen — wie, steht oben in der Datei.
`apps\cli\data\` und `apps\cli\config\` gehören dir: ein Update von uwh fasst
sie nie an.

Mehrere Rechner oder ein Team: eigene Repos per git, eingetragen in
`apps\cli\config\repo.yaml` — so wie bei ulh.

## Wenn etwas nicht geht

Im Ordner `apps\cli`:

```powershell
.\uwh.ps1 -Doctor
```

Protokolle liegen in `apps\cli\data\logs\`.

Braucht Windows 10 oder 11 und winget (bei Windows 11 dabei, bei Windows 10 als
„App Installer" im Microsoft Store).

## Lizenz

MIT
