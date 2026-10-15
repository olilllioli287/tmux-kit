#!/bin/zsh
# tmux-kit 安裝 / 更新:三樣工具各問一次要不要裝,直接按 Enter 就是要
#   1. 中文選單:前綴鍵連按兩次叫出來,分割、搬動、取名格子都用選的
#   2. 排列視窗:在 iTerm 裡按 Cmd+Ctrl+A,用滑鼠拖曳排列格子和分頁(要編譯器)
#   3. Claude 回完反白:Claude Code 回覆完或在等你允許時,那個分頁反白(要 Claude Code)
# 全部都裝、不要問:TMUX_KIT_YES=1 zsh install.sh
# 原本就有的 ~/.tmux.conf 會先備份成 ~/.tmux.conf.bak-日期時間,只在最後加一行載入 tmux-kit
cd "${0:A:h}" || exit 1
kit=~/.tmux-kit
stamp=$(date +%Y%m%d-%H%M%S)
mkdir -p $kit
cp uninstall.sh $kit/

ask() {
  [[ -n $TMUX_KIT_YES ]] && return 0
  local a=""
  read "a?$1 [Y/n] " || return 1
  [[ $a != [nN]* ]]
}

print ""
print "tmux-kit:給 tmux 的三個小工具,每一樣都可以選要不要裝"
print ""

# ===== 1. 中文選單和格子取名 =====
if ask "1/3 裝中文選單?(前綴鍵連按兩次叫出來,可以分割、搬動、取名格子)"; then
  cp menu/tmux-kit.conf menu/menu.conf $kit/
  line='source-file -q ~/.tmux-kit/tmux-kit.conf'
  if grep -qs 'tmux-kit/tmux-kit.conf' ~/.tmux.conf; then
    print "  ~/.tmux.conf 已經會載入 tmux-kit"
  else
    [[ -e ~/.tmux.conf ]] && cp ~/.tmux.conf ~/.tmux.conf.bak-$stamp && print "  已備份原本的 ~/.tmux.conf → ~/.tmux.conf.bak-$stamp"
    print "\n# tmux-kit 的中文選單(要拿掉就刪掉下一行)\n$line" >> ~/.tmux.conf
    print "  已在 ~/.tmux.conf 最後加上載入 tmux-kit 的一行"
  fi
  # 舊版 codenv 幫格子取的名字(@codenv-pane-name)搬到 tmux-kit 的名字,已經取好的名字不會不見
  if tmux info >/dev/null 2>&1; then
    tmux list-panes -a -F '#{pane_id}	#{@codenv-pane-name}' 2>/dev/null | while IFS=$'\t' read -r p n; do
      [[ -n $n ]] && tmux set -p -t $p @tmux-kit-pane-name "$n" && tmux set -p -u -t $p @codenv-pane-name
    done
    tmux source-file ~/.tmux.conf && print "  tmux 已載入新設定"
    # 有取名格子的分頁把名字列打開(平常是格子搬動時才會自動開關)
    tmux list-windows -a -F '#{window_id} #{P:#{?@tmux-kit-pane-name,1,}}' 2>/dev/null | while read -r w named; do
      [[ -n $named ]] && tmux set -w -t $w pane-border-status top
    done
  fi
  prefix=$(tmux show -gv prefix 2>/dev/null)
  case $prefix in
    (None|C-a) print "  已裝好中文選單:Ctrl+A 連按兩次叫出來" ;;
    ("")       print "  已裝好中文選單:開 tmux 後,前綴鍵連按兩次叫出來(沒改過的話是 Ctrl+B 兩下)" ;;
    (C-?)      print "  已裝好中文選單:Ctrl+${(U)prefix#C-} 連按兩次叫出來" ;;
    (*)        print "  已裝好中文選單:前綴鍵($prefix)連按兩次叫出來" ;;
  esac
fi
print ""

# ===== 2. 排列視窗(Cmd+Ctrl+A) =====
agent=io.github.olilllioli287.tmux-kit-board
plist=~/Library/LaunchAgents/$agent.plist
old_agent=io.github.olilllioli287.codenv-board
if ask "2/3 裝排列視窗?(在 iTerm 裡按 Cmd+Ctrl+A,用滑鼠拖曳排列格子和分頁)"; then
  board_new=""
  if [[ -x $kit/tmux-kit-board ]] && cmp -s board/tmux-kit-board.swift $kit/tmux-kit-board.swift; then
    print "  排列視窗已經是最新版"
  elif command -v swiftc >/dev/null && swiftc -O -swift-version 5 board/tmux-kit-board.swift -o $kit/tmux-kit-board 2>/dev/null; then
    cp board/tmux-kit-board.swift $kit/
    print "  已編譯排列視窗 ~/.tmux-kit/tmux-kit-board"
    board_new=1
  else
    print "  排列視窗沒有裝成:需要編譯器,先執行 xcode-select --install,裝好再重新安裝 tmux-kit"
  fi
  # 用假的 HOME 測試安裝時不設定登入項目,免得動到真正的
  if [[ -x $kit/tmux-kit-board ]] && [[ $HOME == "$(dscl . -read /Users/$(id -un) NFSHomeDirectory 2>/dev/null | awk '{print $2}')" ]]; then
    # 舊版 codenv 的排列視窗也搶 Cmd+Ctrl+A,先關掉,設定檔移到 ~/.tmux-kit/old
    if [[ -e ~/Library/LaunchAgents/$old_agent.plist ]]; then
      launchctl bootout gui/$UID/$old_agent 2>/dev/null
      mkdir -p $kit/old && mv ~/Library/LaunchAgents/$old_agent.plist $kit/old/
      print "  已關掉舊版 codenv 的排列視窗(設定檔移到 ~/.tmux-kit/old)"
    fi
    want="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
  <key>Label</key><string>$agent</string>
  <key>ProgramArguments</key><array><string>$kit/tmux-kit-board</string><string>--daemon</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>"
    if [[ -z $board_new && -e $plist && "$(<$plist)" == "$want" ]] && launchctl print gui/$UID/$agent >/dev/null 2>&1; then
      print "  Cmd+Ctrl+A 已經設定好了"
    else
      mkdir -p ~/Library/LaunchAgents
      print -r -- "$want" > $plist
      launchctl bootout gui/$UID/$agent 2>/dev/null
      if launchctl bootstrap gui/$UID $plist; then
        print "  已設定 Cmd+Ctrl+A:在 iTerm 裡按一下叫出排列視窗,再按一下收起來(登入時自動在背景啟動)"
      else
        print "  Cmd+Ctrl+A 沒有設定成功:排列視窗還是可以從中文選單的「用滑鼠排列格子」打開"
      fi
    fi
  fi
fi
print ""

# ===== 3. Claude 回完反白(Claude Code 外掛 tmux-bell) =====
if ! command -v claude >/dev/null; then
  print "3/3 Claude 回完反白:這台電腦沒有 Claude Code,跳過"
elif ask "3/3 裝 Claude 回完反白?(Claude Code 回覆完或在等你允許時,下面那個分頁反白)"; then
  claude plugin marketplace add olilllioli287/tmux-kit >/dev/null 2>&1 || claude plugin marketplace update tmux-kit >/dev/null 2>&1
  if claude plugin install tmux-bell@tmux-kit >/dev/null 2>&1; then
    print "  已裝好 Claude 回完反白;已經開著的 Claude Code 要重開才會用上"
    # 舊的獨立版本(claude-code-tmux-bell)裝著的話拿掉,免得同一件事做兩次
    if claude plugin list 2>/dev/null | grep -q 'tmux-bell@tmux-bell'; then
      claude plugin uninstall tmux-bell@tmux-bell >/dev/null 2>&1 && claude plugin marketplace remove tmux-bell >/dev/null 2>&1
      print "  已移除舊的獨立版本 tmux-bell@tmux-bell"
    fi
  else
    print "  沒有裝成。可以在 Claude Code 的輸入框打這兩行:"
    print "    /plugin marketplace add olilllioli287/tmux-kit"
    print "    /plugin install tmux-bell@tmux-kit"
  fi
fi

print ""
command -v tmux >/dev/null || print "還缺 tmux:請執行 brew install tmux"
print "完成。要拿掉 tmux-kit,執行 zsh ~/.tmux-kit/uninstall.sh(東西會移到一個資料夾,不會直接刪掉)"
