function manShell()
    local blue  = "\027[34m"
    local green = "\027[32m"
    local reset = "\027[0m"

    clink.print(string.format("%s󰗉󰗉󰗉  manShell()  󰗉󰗉󰗉%s", blue, reset))
    clink.print(string.format("%s• conda 󰇙 pipx 󰇙 node%s", green, reset))
    clink.print(string.format("%s• z[i] 󰇙 bat[diff] 󰇙 nvitop 󰇙 vim%s", green, reset))
    clink.print(string.format(
        "%s• rg <regex> [--glob ..] [--type <py>] [--no-ignore] [--hidden] [--max-depth ..] " ..
        "\n    [-l] [-B|A|C <int>] [<path> ...]%s",
        green, reset))
    clink.print(string.format(
        "%s• fd <regex> [--glob ..] [--type d|f] [--no-ignore] [--hidden] [--max|min-depth ..] " ..
        "\n    [--full-path] [-e <py>] [<targetDir>] [--exec <cmd> {} /;]%s",
        green, reset))
    clink.print(string.format(
        "%s• ssh [-p <port>] [-NT] [-L [<local>:]<port>:<remote>:<port>] [-J <user>@<hop1>] <user>@<hop2>%s",
        green, reset))
    clink.print(string.format("%s• %%USERPROFILE%%%s", green, reset))
end

-- Run on startup
manShell()
clink.onfilterinput(function(line)
    if line == "manShell" then
        _G.manShell()
        return ""
    end
end)
