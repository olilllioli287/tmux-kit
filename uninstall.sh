#!/bin/zsh
# 拿掉 tmux-kit:檔案不會直接刪掉,全部移到 ~/tmux-kit-removed-日期時間,想恢復可以搬回來
stamp=$(date +%Y%m%d-%H%M%S)
out=~/tmux-kit-removed-$stamp
mkdir -p $out
agent=io.github.olilllioli287.tmux-kit-board
if [[ -e ~/Library/LaunchAgents/$agent.plist ]]; then
  launchctl bootout gui/$UID/$agent 2>/dev/null
  mv ~/Library/LaunchAgents/$agent.plist $out/ && print "已關掉排列視窗(Cmd+Ctrl+A)"
fi
# ~/.tmux.conf 裡安裝時加的兩行(說明 + source-file)拿掉,原本的檔案先備份
if grep -qs '^# tmux-kit 的中文選單' ~/.tmux.conf; then
  cp ~/.tmux.conf $out/tmux.conf.bak
  awk '/^# tmux-kit 的中文選單/ { skip = 1; next } skip && /tmux-kit\/tmux-kit.conf/ { skip = 0; next } { skip = 0; print }' $out/tmux.conf.bak > ~/.tmux.conf
  print "已從 ~/.tmux.conf 拿掉載入 tmux-kit 的那行(原本的檔案在 $out/tmux.conf.bak)"
fi
[[ -d ~/.tmux-kit ]] && mv ~/.tmux-kit $out/tmux-kit && print "已移走 ~/.tmux-kit"
if command -v claude >/dev/null && claude plugin list 2>/dev/null | grep -q 'tmux-bell@tmux-kit'; then
  claude plugin uninstall tmux-bell@tmux-kit >/dev/null 2>&1 && claude plugin marketplace remove tmux-kit >/dev/null 2>&1 && print "已移除 Claude 回完反白(tmux-bell)"
fi
# 正在跑的 tmux:把選單的按鍵拿掉(Ctrl+B 恢復成原本的「把 Ctrl+B 傳給程式」),再重新載入設定
if tmux info >/dev/null 2>&1; then
  tmux list-keys -T prefix 2>/dev/null | awk '/tmux-kit\/menu.conf/ { print $4 }' | while read -r k; do
    if [[ $k == C-b ]]; then tmux bind-key C-b send-prefix; else tmux unbind-key $k; fi
  done
  tmux source-file ~/.tmux.conf 2>/dev/null
  print "已關掉正在跑的 tmux 裡的中文選單(格子名字列這類小設定,tmux 下次重開才會完全恢復原狀)"
fi
print ""
print "完成。"
print "東西都在 $out,確定不要了可以自己刪掉。"
