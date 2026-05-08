# Windows

For Windows, you can git clone this repository into `~/Documents`.

Append the following line to `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`:

```ps1
. "$env:USERPROFILE\Documents\CustomShell\pwsh\main.ps1"
```

# Linux

For Linux, you can git clone this repository into `~/.config/CustomShell`.

Alternatively, you can just pull the artefacts in:

```sh
curl -L https://github.com/cardin/CustomShell/archive/refs/heads/master.tar.gz | tar xz --strip 1
```

Append the following line to your Bash Profile `~/.bashrc`:

```sh
. ~/config/CustomShell/linux/main.sh
```
