# uwh - unknown windows helper

[![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal&logoColor=white)](https://www.paypal.com/donate/?hosted_button_id=6CDEVZGJWTNQQ)

Pick software for Windows and install it in one go. The selection can be
saved as a profile and repeated on the next PC.
The Windows counterpart of [ulh](https://github.com/sorglos-it/ulh).

| Folder | Purpose | Language | Start | Build |
|---|---|---|---|---|
| `apps/cli` | pick and install software | PowerShell 5.1 | `apps\cli\uwh.cmd` | `tools\build.ps1` (tests + release zip) |

## Start in 3 steps

1. Open **PowerShell**: Start menu, type `PowerShell`, Enter.
2. Paste this line, Enter:
   ```powershell
   irm https://raw.githubusercontent.com/sorglos-it/uwh/main/tools/install.ps1 | iex
   ```
3. From then on, double-click **uwh** on the desktop.

Already have a copy of the folder – for example `uwh-<version>.zip` from the
[releases](https://github.com/sorglos-it/uwh/releases), unzipped? Then a
double-click on **`apps\cli\uwh.cmd`** is enough.

## Usage

uwh speaks English, German, French, Italian and Spanish – the same language as
Windows. `L` switches the language, and uwh remembers the choice.

```text
+============================================================================+
|  uwh - unknown windows helper                                      v0.2.1  |
+============================================================================+
|  What should be installed?                                                 |
+============================================================================+
|                                                                            |
|  ESSENTIALS                                                                |
|    [x] 7-Zip                    Packs and unpacks archives                 |
|  > [ ] Everything               Finds files instantly                      |
|    [x] Notepad++                Text editor                     installed  |
|                                                                            |
+============================================================================+
|  Arrows Move   SPACE On/Off   ENTER Next   / Search   ESC Quit             |
|  A all on/off   P Load profile   M Mode: Install   L Language: English     |
|                                                                2 selected  |
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
| `L` | language: Deutsch → English → Français → Italiano → Español |
| Esc | quit |

A fixed language for one run, e.g. French: `.\uwh.cmd -Language fr`.

All questions come first. After that everything runs on its own, even across a
restart.

## Profiles

After the selection, uwh asks whether to save it as a profile. To run a saved
profile again, e.g. “Office”, in the folder `apps\cli`:

```powershell
.\uwh.cmd -Profile Office
```

Profiles are stored in `apps\cli\data\profiles\`. Passwords are never saved.

## Your own programs

Add them to `apps\cli\data\eigene\config.yaml` — the top of the file says how.
Translations are optional: `description` counts for every language,
`descriptionDE`, `descriptionFR` and so on override it.
`apps\cli\data\` and `apps\cli\config\` are yours: an update of uwh never
touches them.

Several PCs or a team: your own repos via git, listed in
`apps\cli\config\repo.yaml` — just like with ulh.

## If something goes wrong

In the folder `apps\cli`:

```powershell
.\uwh.cmd -Doctor
```

Logs are in `apps\cli\data\logs\`.

Needs Windows 10 or 11 and winget (part of Windows 11; on Windows 10 it comes as
“App Installer” from the Microsoft Store).

## Donate via PayPal

If uwh saves you time setting up a PC, a donation is very welcome. Thank you!

[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal&logoColor=white&style=for-the-badge)](https://www.paypal.com/donate/?hosted_button_id=6CDEVZGJWTNQQ)

## License

[MIT](LICENSE)
