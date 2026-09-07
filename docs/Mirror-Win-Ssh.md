# mirror-win-ssh

One-way mirror of the Windows SSH directory into WSL.

- Source is `$USERPROFILE/.ssh`. Destination is `$HOME/.ssh`.
- The destination is replaced wholesale. Stale entries are removed. There is
  no merge mode.
- Requires WSL with `rsync` and `realpath` installed, and `USERPROFILE` set.
  The source must already exist.

## Safety

- Refuses unsafe paths: filesystem root, or source and destination identical.
- Refuses symbolic links for source, destination, and anything inside source.
- Refuses hard-linked files inside source.
- Refuses a non-directory destination.

## Permissions

Staged copy gets OpenSSH permissions before publication: directories `700`,
files `600`, except `*.pub` and `known_hosts` at `644`.

## Failure safety

- Staging failures leave the destination untouched and remove temp data.
- Publication moves the existing destination aside before installing the staged
  copy. On publish failure the original is restored; if restoration also fails
  its backup location is reported.
