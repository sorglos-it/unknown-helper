# ulh - unknown linux helper

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../../LICENSE)
[![Donate](https://img.shields.io/badge/Donate-PayPal-00457C.svg?logo=paypal)](https://www.paypal.com/donate/?hosted_button_id=6CDEVZGJWTNQQ)

A menu for the Linux terminal that installs, updates, configures and removes software:
101 scripts for Debian, Ubuntu, Red Hat, Arch, SUSE, Alpine and Proxmox. Pick a number,
answer a few questions, done - ulh keeps itself up to date.

| Folder | Purpose | Language | Start | Build |
|---|---|---|---|---|
| `apps/cli-ulh` | The menu: installs, updates and removes software on Linux | Bash | `bash ~/unknown-helper/apps/cli-ulh/ulh.sh` | none needed |

## Start in 3 steps

1. **Open a terminal** on the Linux machine (or log in via SSH).
2. **Install** - paste this line and press Enter. It installs git if needed and puts
   ulh into `~/unknown-helper`:
   ```bash
   wget -qO - https://raw.githubusercontent.com/sorglos-it/unknown-helper/main/tools/ulh/install.sh | bash
   ```
3. **Start** ulh:
   ```bash
   bash ~/unknown-helper/apps/cli-ulh/ulh.sh
   ```

No wget? `curl -sSL https://raw.githubusercontent.com/sorglos-it/unknown-helper/main/tools/ulh/install.sh | bash`.
By hand: `git clone https://github.com/sorglos-it/unknown-helper.git ~/unknown-helper && bash ~/unknown-helper/apps/cli-ulh/ulh.sh`.
ulh used to live in its own repository `sorglos-it/ulh`. That repository is gone:
install ulh again with the line above - older copies no longer update themselves.

> **Deploy by cloning, not by copying.** Copying the files from a Windows machine
> (SMB, SCP, rsync from a checked-out working copy) can carry CRLF line endings
> along, and the target then fails with `/bin/bash^M: bad interpreter`. A clone is
> always LF (enforced by `.gitattributes`) and keeps the auto-update working.
> Already hit it? `find . -type f \( -name '*.sh' -o -name '*.yaml' \) -exec sed -i 's/\r$//' {} +`

## Usage

Pick a category, a script, an action; answer the questions (Enter takes the
default); confirm. Scripts that need root run with `sudo` - ulh itself stays
unprivileged. Started as root (Proxmox, containers), ulh runs them directly.

```
1. Repository Selector (only when you use your own repositories)
   ├─ ulh Scripts
   │  └─ Categories
   │     └─ Scripts
   │        └─ Actions
   └─ Custom Repos
      └─ Scripts
         └─ Actions
```

**Finding a script fast:** press **`s`** in the repository, category or script
menu - or type **`/term`** directly at the prompt:

```
  Choose: /spool

+==============================================================================+
| Search: spool                                                                |
+==============================================================================+
|
|   1) spoolman         System Management          Spoolman filament spool ma..
|
+==============================================================================+
|  s) Search  (or /term)                                                       |
|  b) Back                                                                     |
|  l) Language: English                                                        |
|  q) Quit                                           ubuntu (debian) · v24.04  |
+==============================================================================+

  Choose: 1        -> straight into spoolman's actions, ready to run
```

The search matches script name, description and category (case-insensitive) and
only lists scripts that work on your distribution. `s` inside the results starts a
new search, `b` goes back, `q` quits.

What the 101 scripts cover (network, web servers, databases, containers, languages,
editors, shells, monitoring, backup, system management ...): **[docs/ulh/scripts.md](scripts.md)**.

## Languages

ulh speaks English, German, French, Italian and Spanish: the menu, the messages and
the descriptions and questions of all 101 scripts. It starts in the language of the
system (`$LANG`), otherwise in English.

- Press **`l`** in any menu for the next language - ulh remembers it in
  `apps/cli-ulh/config/settings.yaml`.
- Or start with `--lang de` (`en`, `fr`, `it`, `es`) for one run.

Yes/no questions take the answer in every language (`y`, `j`, `o`, `s` = yes). What
the scripts themselves print stays English.

## Update

ulh updates itself on every start (git pull) and restarts. Your own files in
`apps/cli-ulh/config/` and `apps/cli-ulh/data/` are never touched.

```bash
bash ~/unknown-helper/apps/cli-ulh/ulh.sh --check-update   # are there updates?
bash ~/unknown-helper/apps/cli-ulh/ulh.sh --update         # update now
bash ~/unknown-helper/apps/cli-ulh/ulh.sh --no-update      # start without updating
bash ~/unknown-helper/apps/cli-ulh/ulh.sh --help           # all options
```

## Custom scripts

**Your own repositories** - a folder or a git repository with a `config.yaml` and a
`scripts/` folder - appear in the menu next to ulh's scripts. Register them in
`apps/cli-ulh/config/repo.yaml`:

```yaml
repositories:
  my-scripts:
    name: "My Custom Scripts"
    url: "git@github.com:user/my-scripts.git"
    path: "my-scripts"        # -> apps/cli-ulh/data/repos/my-scripts/
    auth_method: "ssh"        # ssh (keys in apps/cli-ulh/data/keys/), https_token, https_basic or none
    enabled:                  # show in menu
    auto_update:              # git pull on startup
```

A ready-made example ships switched off: remove the `#` in front of `enabled:` for
`demo-scripts` in `apps/cli-ulh/config/repo.yaml` and look at
`apps/cli-ulh/data/repos/demo-scripts/`.

**Preset answers and automation** - `apps/cli-ulh/config/answer.yaml` fills in the
questions, `autoscript: true` runs an action without asking:

```yaml
scripts:
  ubuntu:
    install:
      - default: "no"               # Interactive: user sees prompt
    pro:
      autoscript: true              # Automated: no prompts
      answers:
        - default: "token123"
```

Works for ulh's scripts and your own. Details, authentication and troubleshooting:
**[docs/ulh/guide.md](guide.md)**.

## Supported distributions

- ✅ Debian / Ubuntu / Linux Mint
- ✅ Red Hat / Fedora / CentOS / Rocky / AlmaLinux
- ✅ Arch / Manjaro
- ✅ SUSE / openSUSE
- ✅ Alpine
- ✅ Proxmox VE
- ⚠️ PiKVM v3 (Arch-based appliance, limited package management)

Needs Bash 4.0+, git and root rights for system-level operations: `sudo`, or start
ulh as root.

## Security

- Scripts run **individually with sudo** (ulh stays unprivileged); as root they run directly
- SSH keys for your repositories stay in **apps/cli-ulh/data/keys/** (git-ignored)
- No hardcoded credentials - tokens and passwords come from environment variables (`${NAME}`)
- All scripts pass **syntax validation** (`bash -n`)

## Documentation

| Document | What is in it |
|---|---|
| [Guide](guide.md) | folders, catalog, answer.yaml, custom repositories, writing scripts, troubleshooting |
| [Scripts](scripts.md) | all 101 scripts with actions, sudo and distributions |
| [Changes](CHANGELOG.md) | version history |
| [Backstory](backstory.md) | how "unknown linux helper" got its name - featuring Kevin and the Unknown Man |

## Development

```bash
cp apps/cli-ulh/templates/script-template.sh apps/cli-ulh/assets/scripts/my-script.sh
# + an entry in apps/cli-ulh/assets/catalog.yaml
bash apps/cli-ulh/tests/run.sh          # Linux: syntax, catalog, menu, updates - installs nothing
bash tools/ulh/gen-scripts-doc.sh       # refresh docs/ulh/scripts.md from the catalog
```

Contributions welcome - see [docs/ulh/guide.md](guide.md#script-development).
Questions? Open an issue on GitHub.

## License

MIT - see [LICENSE](../../LICENSE). ulh ships [yq](https://github.com/mikefarah/yq) (MIT),
see [THIRD-PARTY.md](THIRD-PARTY.md).

## Donate via PayPal

If ulh saves you time and Linux headaches, consider supporting the project:

**[➡️ Donate via PayPal](https://www.paypal.com/donate/?hosted_button_id=6CDEVZGJWTNQQ)**
