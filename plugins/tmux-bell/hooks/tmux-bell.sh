#!/bin/sh
# Claude Code 回覆完、或要你允許 / 回答問題時,在它自己那格送出一個 BEL(響一聲)。
# tmux 收到其他分頁的 BEL,就會把下面狀態列那個分頁反白;切過去看之後反白自動消失。
# 你正在看的分頁不送,免得每次回覆都嗶一聲。不在 tmux 裡就什麼都不做。
#
# Ring a BEL in Claude Code's own tmux pane when it stops or asks for input.
# tmux then highlights that window in the status line until you visit it.
# Skipped when that window is the one you are looking at, and outside tmux.

cat >/dev/null   # hook 的 JSON 輸入用不到 / the hook's JSON input is not needed

[ -n "$TMUX" ] && [ -n "$TMUX_PANE" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

# 這個分頁是不是目前畫面上的分頁、這個工作階段有沒有人在看、這格的終端機裝置
# window_active, session_attached, pane_tty
set -- $(tmux display-message -p -t "$TMUX_PANE" '#{window_active} #{session_attached} #{pane_tty}' 2>/dev/null)
[ $# -eq 3 ] || exit 0
[ "$1" = 1 ] && [ "$2" != 0 ] && exit 0

# 寫進這格的終端機,tmux 會當成這格的程式響了一聲
# Writing to the pane's tty makes tmux see the bell as coming from this pane
[ -w "$3" ] && printf '\a' > "$3"
exit 0
