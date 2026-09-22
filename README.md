# uwh - unknown windows helper

[![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal&logoColor=white)](https://www.paypal.com/donate/?hosted_button_id=6CDEVZGJWTNQQ)

Pick software for Windows and install it in one go. The selection can be
saved as a profile and repeated on the next PC.
The Windows counterpart of [ulh](https://github.com/sorglos-it/ulh).

| Folder | Purpose | Language | Start | Build |
|---|---|---|---|---|
| `apps/cli` | pick and install software | PowerShell 5.1 | `apps\cli\uwh.cmd` | none needed |

## Start in 3 steps

1. Open **PowerShell**: Start menu, type `PowerShell`, Enter.
2. Paste this line, Enter:
   ```powershell
   irm https://raw.githubusercontent.com/sorglos-it/uwh/main/tools/install.ps1 | iex
   ```
3. From then on, double-click **uwh** on the desktop.

Already have a copy of the folder? Then a double-click on
**`apps\cli\uwh.cmd`** is enough.

## Usage

The menu is in German:

```text
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

| Key | Action |
|---|---|
| Arrows | up and down |
| Space | select and deselect |
| Enter | continue |
| `/` | search |
| `A` | all on or off |
| `P` | load a profile |
| `M` | mode: install → update → remove |
| Esc | quit |

All questions come first. After that everything runs on its own, even across a
restart.

## Profiles

After the selection, uwh asks whether to save it as a profile. To run a saved
profile again, e.g. “Office”, in the folder `apps\cli`:

```powershell
.\uwh.ps1 -Profile Office
```

Profiles are stored in `apps\cli\data\profiles\`. Passwords are never saved.

## Your own programs

Add them to `apps\cli\data\eigene\config.yaml` — the top of the file says how.
`apps\cli\data\` and `apps\cli\config\` are yours: an update of uwh never
touches them.

Several PCs or a team: your own repos via git, listed in
`apps\cli\config\repo.yaml` — just like with ulh.

## If something goes wrong

In the folder `apps\cli`:

```powershell
.\uwh.ps1 -Doctor
```

Logs are in `apps\cli\data\logs\`.

Needs Windows 10 or 11 and winget (part of Windows 11; on Windows 10 it comes as
“App Installer” from the Microsoft Store).

## Donate via PayPal

If uwh saves you time setting up a PC, a donation is very welcome. Thank you!

[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal&logoColor=white&style=for-the-badge)](https://www.paypal.com/donate/?hosted_button_id=6CDEVZGJWTNQQ)

## License

[MIT](LICENSE)
