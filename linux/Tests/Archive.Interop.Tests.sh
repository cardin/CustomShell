#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2034

# Verifies the authenticated format in both directions using real Windows and
# Linux OpenSSL/tar implementations. This test is skipped outside WSL.

set -u

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

if ! command -v pwsh.exe >/dev/null 2>&1 || ! command -v wslpath >/dev/null 2>&1; then
	echo "Archive interoperability tests skipped: Windows PowerShell 7 is unavailable"
	exit 0
fi

project_root="$(realpath -e -- "$(dirname -- "${BASH_SOURCE[0]}")/../..")" || exit 1
windows_temp="$(pwsh.exe -NoLogo -NoProfile -Command '[IO.Path]::GetTempPath()' | tr -d '\r')"
test_parent="$(wslpath -u "$windows_temp")"
test_root="$(mktemp -d "$test_parent/CustomShell-Interop.XXXXXX")" || exit 1
trap 'rm -rf -- "$test_root"' EXIT

source "$project_root/linux/commands/archive.sh"
PROJ_DIR="$project_root"

mkdir -p "$test_root/bin"
mock_age="$test_root/bin/age"
cat >"$mock_age" <<'EOF'
#!/usr/bin/env bash
output=""
input=""
mode=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output="$2"; shift 2 ;;
        -p) mode="encrypt"; shift ;;
        -d) mode="decrypt"; shift ;;
        *) input="$1"; shift ;;
    esac
done
if [[ "$mode" == "encrypt" ]]; then
    hash="$(sha256sum "$input" | cut -d' ' -f1)"
    {
        printf "age-encryption.org/v1\n"
        printf "%s\n" "$hash"
        cat "$input"
    } >"$output"
elif [[ "$mode" == "decrypt" ]]; then
    header="$(head -n 1 "$input")"
    if [[ "$header" != "age-encryption.org/v1" ]]; then
        exit 1
    fi
    expected_hash="$(sed -n '2p' "$input")"
    actual_hash="$(tail -n +3 "$input" | sha256sum | cut -d' ' -f1)"
    if [[ "$expected_hash" != "$actual_hash" ]]; then
        exit 1
    fi
    tail -n +3 "$input" >"$output"
fi
EOF
chmod +x "$mock_age"

cat >"$test_root/bin/mock_age.ps1" <<'EOF'
param()
$output = $null
$mode = 'encrypt'
$inputFile = $null
$i = 0
while ($i -lt $args.Count) {
    if ($args[$i] -eq '-o') {
        $output = $args[$i+1]
        $i += 2
    }
    elseif ($args[$i] -eq '-p') {
        $mode = 'encrypt'
        $i++
    }
    elseif ($args[$i] -eq '-d') {
        $mode = 'decrypt'
        $i++
    }
    else {
        $inputFile = $args[$i]
        $i++
    }
}
if ($mode -eq 'encrypt') {
    $bytes = [IO.File]::ReadAllBytes($inputFile)
    $hasher = [Security.Cryptography.SHA256]::Create()
    $hash = [BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    $header = [Text.Encoding]::ASCII.GetBytes("age-encryption.org/v1`n$hash`n")
    $outBytes = New-Object byte[] ($header.Length + $bytes.Length)
    [Buffer]::BlockCopy($header, 0, $outBytes, 0, $header.Length)
    [Buffer]::BlockCopy($bytes, 0, $outBytes, $header.Length, $bytes.Length)
    [IO.File]::WriteAllBytes($output, $outBytes)
    exit 0
}
elseif ($mode -eq 'decrypt') {
    $data = [IO.File]::ReadAllBytes($inputFile)
    $headerPrefix = [Text.Encoding]::ASCII.GetString($data, 0, [Math]::Min(22, $data.Length))
    if ($headerPrefix -ne "age-encryption.org/v1`n") {
        exit 1
    }
    if ($data.Length -lt 87) {
        exit 1
    }
    $expHash = [Text.Encoding]::ASCII.GetString($data, 22, 64)
    $body = New-Object byte[] ($data.Length - 87)
    [Buffer]::BlockCopy($data, 87, $body, 0, $body.Length)
    $hasher = [Security.Cryptography.SHA256]::Create()
    $actHash = [BitConverter]::ToString($hasher.ComputeHash($body)).Replace('-', '').ToLowerInvariant()
    if ($expHash -ne $actHash) {
        exit 1
    }
    [IO.File]::WriteAllBytes($output, $body)
    exit 0
}
EOF

cat >"$test_root/bin/age.cmd" <<'EOF'
@echo off
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mock_age.ps1" %*
exit /b %ERRORLEVEL%
EOF

export PATH="$test_root/bin:$PATH"

mkdir "$test_root/bash-source"
echo "bash payload" >"$test_root/bash-source/data.txt"
Protect-Tar "$test_root/bash-source" "$test_root/from-bash" >/dev/null ||
	fail "Bash failed to create an authenticated archive"
bash_archives=("$test_root"/from-bash_*.enc)
[[ ${#bash_archives[@]} -eq 1 ]] || fail "Bash archive filename was not deterministic"

CUSTOMSHELL_INTEROP_ROOT="$(wslpath -w "$test_root")" || exit 1
CUSTOMSHELL_INTEROP_ARCHIVE="$(wslpath -w "${bash_archives[0]}")" || exit 1
CUSTOMSHELL_PROJECT_ROOT="$(wslpath -w "$project_root")" || exit 1
export CUSTOMSHELL_INTEROP_ROOT CUSTOMSHELL_INTEROP_ARCHIVE CUSTOMSHELL_PROJECT_ROOT
export WSLENV="${WSLENV:+$WSLENV:}CUSTOMSHELL_INTEROP_ROOT:CUSTOMSHELL_INTEROP_ARCHIVE:CUSTOMSHELL_PROJECT_ROOT"

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command '
    $ErrorActionPreference = "Stop"
    $env:PATH = "$env:CUSTOMSHELL_INTEROP_ROOT\bin;$env:PATH"
    . (Join-Path $env:CUSTOMSHELL_PROJECT_ROOT "pwsh/Modules/CustomShell.Commands/Archive.ps1")
    Unprotect-Tar `
        $env:CUSTOMSHELL_INTEROP_ARCHIVE `
        (Join-Path $env:CUSTOMSHELL_INTEROP_ROOT "pwsh-restored") |
        Out-Null
    $source = Join-Path $env:CUSTOMSHELL_INTEROP_ROOT "pwsh-source.txt"
    Set-Content -LiteralPath $source -Value "pwsh payload"
    Protect-Tar $source (Join-Path $env:CUSTOMSHELL_INTEROP_ROOT "from-pwsh") |
        Out-Null
' || fail "PowerShell failed to extract or create an authenticated archive"

[[ "$(<"$test_root/pwsh-restored/bash-source/data.txt")" == "bash payload" ]] ||
	fail "PowerShell did not recreate the Bash input"

pwsh_archives=("$test_root"/from-pwsh_*.enc)
[[ ${#pwsh_archives[@]} -eq 1 ]] || fail "PowerShell archive filename was not deterministic"
Unprotect-Tar "${pwsh_archives[0]}" "$test_root/bash-restored" >/dev/null ||
	fail "Bash failed to extract the PowerShell archive"
[[ "$(tr -d '\r\n' <"$test_root/bash-restored/pwsh-source.txt")" == "pwsh payload" ]] ||
	fail "Bash did not recreate the PowerShell input"

echo "Archive interoperability tests passed"
