# Installing and upgrading CustomShell

Run the setup script on first installation, after pulling upgrades, and whenever
the repository moves to a new location. It is idempotent: re-running it makes no
changes when the setup is already current.

```ps1
# Windows
& <repo>\pwsh\Install.ps1
```

```sh
# Linux and WSL
bash <repo>/linux/install.sh
```

## What the setup script does

- Adds a marker-delimited block to the shell profile that sources the entry
  point (`pwsh/main.ps1` or `linux/main.sh`). On Windows the block is written to
  the current user's all-hosts profile (`profile.ps1`). A stale block is updated
  in place; an unmarked manual `source` line is reported and left untouched.
- Persists the environment values listed under
  [Persistent environment](#persistent-environment).
- Installs or registers shared tool configuration:
  - Espanso: `config/espanso/_base.yml` and `config/espanso/whitelist.yml` are
    installed into the `match/` and `config/` directories of the root Espanso
    reports for itself. See [Espanso layout](#espanso-layout).
  - Clink (Windows, when `clink` is available): registers `config/clink` as a
    Lua script path with `clink installscripts`; selects the Clink prompt from
    `Settings.psd1` (`oh-my-posh` with `ohmyposh.theme` set to
    `config/omp/catppuccin_gruvbox.json`, or `starship` with `STARSHIP_CONFIG`
    set to `config/starship/catppuccin-powerline.toml`; `none` selects no
    custom prompt); and points `clink.autostart` at
    `config/clink/clink_start.cmd`. Clink only runs inside `cmd.exe`, so it uses
    the standalone (glyph) themes. All changes go through the Clink CLI, and the
    registered path and managed settings are recorded so `-Uninstall` can
    reverse them. When `clink` is not on `PATH`, these steps are skipped with an
    advisory.
- Resolves the Espanso root by asking the tool (Windows tries `espansod path
  config` then `espanso path config`; Linux tries `espanso` then `espansod`),
  then falls back to the platform default (`%APPDATA%\espanso` on Windows,
  `${XDG_CONFIG_HOME:-~/.config}/espanso` on Linux). The `-EspansoRoot` /
  `--espanso-root` option overrides detection.
- Reports unavailable expected commands on every run; `-Check` / `--check` also
  reports setup freshness. Missing optional tools never fail the run, and
  profile startup does not enumerate commands.

All other startup behavior remains runtime-managed: PATH, aliases, prompt
initialization, the SSH agent, the Git credential helper, and the generated
`environment.d` file are handled by startup code and are never modified here.

## What it does not do

- No package installation and no privilege escalation.
- No creation of symbolic links or junctions on Windows; configuration files
  are copied so no elevation is required.
- No changes to secrets, SSH data, CA certificates, or Git credentials. The
  installer never writes `environment.d` directly; runtime startup publishes the
  managed values.

## Persistent environment

Setup keeps these values set (Windows values live in the User environment scope
unless noted):

- `UV_SYSTEM_CERTS=true` — use the platform certificate store for uv, which
  otherwise bundles Mozilla roots. On Linux, startup exports it from the managed
  profile block and publishes it to
  `~/.config/environment.d/90-customshell.conf` for the systemd user session.
- `WSLENV=USERPROFILE/up` — share the Windows user-profile path with WSL,
  translating the path and applying only from Windows to WSL.
- `CONDA_PATH=<directory containing conda.exe>` — set when conda is found on
  `PATH`, so profile startup can lazily initialize conda. It is not set when
  conda is absent, and an existing valid value is respected and left unmanaged.
- `STARSHIP_CONFIG=<repo>\config\starship\catppuccin-powerline.toml` — set when
  `Settings.psd1` selects the `starship` prompt, so Starship (including Clink's
  starship prompt) reads the repository theme. It is cleared when the prompt
  changes away from starship.

On Windows these values are tracked in
`%LOCALAPPDATA%\CustomShell\environment.txt`; `-Uninstall` clears values it still
owns, and locally modified values are reported and kept. `CONDA_PATH` is
recorded only when setup set it, and `STARSHIP_CONFIG` only while the starship
prompt is selected. `-EnvironmentScope Process` applies changes to the current
process only and exists so tests never touch the registry.

Processes already running before setup keep their old environment block, so a
new session may not see new values until the environment refreshes (sign out and
back in, or restart the terminal host). Linux shells pick them up the next time
they start.

## Linux and WSL options

```text
--check              Report current state without changing anything.
--dry-run            Print intended actions without changing anything.
--uninstall          Remove the managed profile block and links.
--force              Replace conflicting Espanso files (with a backup).
--bashrc <path>      Override the rc file to edit.
--espanso-root <dir> Override the Espanso configuration root.
-h, --help           Show help and exit.
```

Linux links `config/espanso/_base.yml` into `<root>/match` and
`config/espanso/whitelist.yml` into `<root>/config`. A conflicting regular file
is skipped unless `--force` is given, in which case it is moved to
`<file>.customshell.bak` before linking. `--uninstall` removes only links that
still point into the repository.

`--check` exits non-zero when the profile block or Espanso links are missing or
stale, and reports the `CUSTOM_CA_CERT` prerequisite (only needed on managed
devices). Advisories about optional commands do not affect the exit status.

## Windows options

```text
-Check                Report current state without changing anything.
-Help                 Print help and exit.
-DryRun               Print intended actions without changing anything.
-Uninstall            Remove the managed profile block and configuration.
-Force                Replace conflicting configuration files (with a backup).
-ProfilePath <path>   Override the profile file to edit (defaults to the
                      current user's all-hosts profile).
-EspansoRoot <dir>    Override the Espanso configuration root.
-ClinkCommand <cmd>   Override the Clink command (defaults to clink on PATH).
-SettingsPath <path>  Override the settings data file (defaults to
                      pwsh/Settings.psd1).
-StateDir <dir>       Override the install-manifest and state directory.
-EnvironmentScope     User (default) or Process. Process is for testing only.
```

Windows copies `config/espanso/_base.yml` into `<root>\match` and
`config/espanso/whitelist.yml` into `<root>\config`, recording destinations in
`%LOCALAPPDATA%\CustomShell\installed.txt`. A conflicting file is skipped unless
`-Force` is given, in which case it is backed up to `<file>.customshell.bak`.
`-Uninstall` removes only tracked files that still match the shipped source, and
reports and keeps locally modified files. Clink state is tracked separately in
`%LOCALAPPDATA%\CustomShell\clink.json`.

`-Check` exits non-zero when the profile block or expected configuration files
are missing or stale, when another profile also sources CustomShell, when a
User-scope environment value differs, or when Clink is installed but its script
path or managed settings are stale. Missing optional commands, and Clink itself,
do not affect the exit status when absent.

## Layout

The entry scripts are thin and delegate to focused modules so behavior is easy to
find and test:

```text
linux/install.sh              linux/install/common.sh
                              linux/install/profile.sh
                              linux/install/environment.sh
                              linux/install/espanso.sh
                              linux/install/checks.sh

pwsh/Install.ps1              pwsh/Install/Common.ps1
                              pwsh/Install/Profile.ps1
                              pwsh/Install/Environment.ps1
                              pwsh/Install/Espanso.ps1
                              pwsh/Install/Configs.ps1
                              pwsh/Install/Clink.ps1
                              pwsh/Install/Checks.ps1
```

## Prompt configuration

The prompt is selected by `pwsh/Settings.psd1` (PowerShell) or `PRETTY_PROMPT`
(Bash). Oh My Posh and Starship read their themes directly from `config/omp/`
and `config/starship/`. Starship is pointed at the repository theme through
`STARSHIP_CONFIG`, choosing `catppuccin-powerline.toml` for standalone terminals
and `plain-text-symbols.toml` otherwise.

## Espanso layout

Espanso keeps its configuration under a single root containing `config/` and
`match/`. The repository follows that layout: `whitelist.yml` lives in `config/`
and its `includes: ../match/_base.yml` resolves to the `_base.yml` installed in
`match/`.

Scoop installs Espanso in portable mode, so the root is a `.espanso` junction
under `scoop\persist\espanso` (reported by `espanso path config` as the
versioned `scoop\apps\espanso\current\.espanso` path, which points at the same
place). The installer prefers the tool's own report, so it follows updates
across Espanso versions.

## Known limitations

- Clink configuration is skipped when `clink` is not on `PATH`; installer runs
  report an advisory and `-Check` treats it as optional.
- Clink always uses the standalone (glyph) themes, so a glyph-limited console
  may render them imperfectly.
- `clink.autostart` is executed as a command line, so a repository path
  containing spaces may need manual quoting.
