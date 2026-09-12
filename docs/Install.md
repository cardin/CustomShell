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
  point (`pwsh/main.ps1` or `linux/main.sh`). A stale block is updated in place;
  an unmarked manual `source` line is reported and left untouched.
- Sets `UV_SYSTEM_CERTS=true` persistently. uv defaults to bundled Mozilla root
  certificates, so this opts into the platform certificate store. On Windows the
  value is written to the User environment scope; on Linux it is exported from
  the managed profile block and published to `environment.d` by runtime startup.
- Sets `BAT_CONFIG_PATH` to the repository's `config/bat.conf` on Windows so
  plain `bat` reads CustomShell's shared configuration. Linux startup exports the
  same value from `linux/integrations/tools.sh`.
- Installs shared tool configuration that the runtime does not reference by
  repository path:
  - Espanso: `config/espanso/_base.yml` is installed into `<root>/match` and
    `config/espanso/whitelist.yml` into `<root>/config`, where `<root>` is the
    directory Espanso reports for itself.
  - Clink Lua scripts (`config/clink/*.lua`), Windows only.
- Resolves the Espanso root by asking the tool (`espanso path config`, falling
  back to `espansod path config`), then falls back to the platform default
  (`%APPDATA%\espanso` on Windows, `${XDG_CONFIG_HOME:-~/.config}/espanso` on
  Linux). The `-EspansoRoot` / `--espanso-root` option overrides detection.
- Reports expected commands that are missing on every run. `-Check` / `--check`
  additionally reports setup freshness and the state of `CUSTOM_CA_CERT`,
  `CONDA_PATH`, and the selected prompt. Missing optional tools never fail the
  run, and profile startup does not enumerate commands.

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

## Linux and WSL options

```text
--check             Report current state without changing anything.
--dry-run           Print intended actions without changing anything.
--uninstall         Remove the managed profile block and links.
--force             Replace conflicting Espanso files (with a backup).
--bashrc <path>      Override the rc file to edit.
--espanso-root <dir> Override the Espanso configuration root.
-h, --help           Show help and exit.
```

Linux links `config/espanso/_base.yml` into `<root>/match` and
`config/espanso/whitelist.yml` into `<root>/config`. The root defaults to what
`espanso path config` reports, falling back to
`${XDG_CONFIG_HOME:-~/.config}/espanso`. A conflicting regular file is skipped
unless `--force` is given, in which case it is moved to `<file>.customshell.bak`
before linking. `--uninstall` removes only links that still point into the
repository.

`--check` exits non-zero when the profile block or Espanso links are missing or
stale. Advisories about optional commands do not affect the exit status.

## Windows options

```text
-Check                Report current state without changing anything.
-Help                 Print help and exit.
-DryRun               Print intended actions without changing anything.
-Uninstall            Remove the managed profile block and configuration.
-Force                Replace conflicting configuration files (with a backup).
-ProfilePath <path>   Override the profile file to edit.
-EspansoRoot <dir>    Override the Espanso configuration root.
-ClinkScriptDir <dir> Override the Clink scripts directory.
-StateDir <dir>       Override the install-manifest directory.
-EnvironmentScope     User (default) or Process. Process is for testing only.
```

Windows copies `config/espanso/_base.yml` into `<root>\match` and
`config/espanso/whitelist.yml` into `<root>\config`, and
`config/clink/*.lua` into `%LOCALAPPDATA%\clink`. Installed destinations are
recorded in `%LOCALAPPDATA%\CustomShell\installed.txt`. A conflicting file is
skipped unless `-Force` is given, in which case it is backed up to
`<file>.customshell.bak`. `-Uninstall` removes only tracked files that still
match the shipped source; locally modified files are reported and kept.

`-Check` exits non-zero when the profile block or expected configuration files
are missing or stale, or when a User-scope environment value differs. Missing
optional commands do not affect the exit status.

## Persistent environment

The setup script keeps these values set:

- `UV_SYSTEM_CERTS=true` — use the platform certificate store for uv.
- `BAT_CONFIG_PATH=<repo>\config\bat.conf` — point `bat` at CustomShell's shared
  configuration (header and grid, no line numbers).

uv bundles Mozilla root certificates by default, so `UV_SYSTEM_CERTS` is required
to trust the operating system's certificate store. On Windows both values are
stored in the User environment scope and tracked in
`%LOCALAPPDATA%\CustomShell\environment.txt`; `-Uninstall` clears values it still
owns, and locally modified values are reported and kept. On Linux `UV_SYSTEM_CERTS`
is exported from the managed profile block and runtime startup publishes it
through `~/.config/environment.d/90-customshell.conf` for the systemd user
session; `BAT_CONFIG_PATH` is exported by `linux/integrations/tools.sh` at
startup.

On Windows these values are applied only by setup; profile startup does not set
them. Processes that were already running before setup keep their old
environment block, so a newly opened session may not see the new values until
the environment refreshes (for example, after signing out and back in, or
restarting the terminal host). Linux shells pick up the managed exports the next
time they start.

Managed environment values always win: a conflicting Windows value is
overwritten so the persistent value is guaranteed. `-EnvironmentScope Process`
applies the change only to the current process and exists so tests never touch
the registry.

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

- Clink: only `*.lua` scripts are installed. `config/clink/clink_start.cmd` is a
  Cmder-specific autorun file and is not installed automatically.
