# Configures interactive PSReadLine key bindings and display options when the
# module is available. The selected bindings enable menu completion, word-wise
# movement, and prefix-aware history navigation without making PSReadLine required.

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function ForwardWord
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -ShowToolTips
}
