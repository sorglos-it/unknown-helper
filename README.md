# unknown-helper

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Donate](https://img.shields.io/badge/Donate-PayPal-00457C.svg?logo=paypal)](https://www.paypal.com/donate/?hosted_button_id=6CDEVZGJWTNQQ)

Menus that install, update, configure and remove software - pick a number, answer a few questions, done.
One for Linux (ulh), one for Windows (uwh).

| Folder | Purpose | Language | Start | Build |
|---|---|---|---|---|
| `apps/cli-ulh` | ulh - unknown linux helper | Bash | `bash ~/unknown-helper/apps/cli-ulh/ulh.sh` | none; tests `bash apps/cli-ulh/tests/run.sh` |
| `apps/cli-uwh` | uwh - unknown windows helper | PowerShell 5.1 | `apps\cli-uwh\uwh.cmd` | `tools\uwh\build.ps1` (tests + release zip) |

## Start in 3 steps

**Linux**

1. Open a terminal.
2. `wget -qO - https://raw.githubusercontent.com/sorglos-it/unknown-helper/main/tools/ulh/install.sh | bash`
3. `bash ~/unknown-helper/apps/cli-ulh/ulh.sh`

**Windows**

1. Open PowerShell.
2. `irm https://raw.githubusercontent.com/sorglos-it/unknown-helper/main/tools/uwh/install.ps1 | iex`
3. Start uwh from the shortcut the installer creates.

Details: [ulh](docs/ulh/README.md) · [uwh](docs/uwh/README.md)

## License

MIT - see [LICENSE](LICENSE).
