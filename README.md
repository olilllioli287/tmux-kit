# tmux-kit

**繁體中文** | [English](#english)

給 tmux 的三個小工具，每一樣都可以選要不要裝：

| 工具 | 做什麼 | 需要 |
|---|---|---|
| **中文選單** | 前綴鍵連按兩次（例如 Ctrl+A 兩下）叫出中文選單：分割、關掉、放大格子，開分頁、換分頁、取名，把格子搬到別的分頁、換排列方式、幫格子取名 | tmux 3.4 以上 |
| **排列視窗** | 在 iTerm 裡按 Cmd+Ctrl+A，開一個 Mac 視窗，把所有工作階段、分頁、格子畫成小縮圖，用滑鼠拖曳就能排好 | macOS、Command Line Tools（編譯用） |
| **Claude 回完反白** | 好幾個分頁各跑一個 Claude Code 時，哪個 Claude 回覆完或在等你允許，下面那個分頁就反白 | Claude Code |

原本是 [codenv](https://github.com/olilllioli287/codenv) 的一部分，2026-10-15 拆出來，不用 codenv 也能單獨裝。

## 安裝

在終端機執行這一行（之後想更新，再執行一次同一行就好）：

```
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/olilllioli287/tmux-kit/main/get.sh)"
```

它會一樣一樣問你要不要裝，直接按 Enter 就是要，輸入 `n` 再按 Enter 就跳過：

```
1/3 裝中文選單?(前綴鍵連按兩次叫出來,可以分割、搬動、取名格子) [Y/n]
2/3 裝排列視窗?(在 iTerm 裡按 Cmd+Ctrl+A,用滑鼠拖曳排列格子和分頁) [Y/n]
3/3 裝 Claude 回完反白?(Claude Code 回覆完或在等你允許時,下面那個分頁反白) [Y/n]
```

會動到的地方：

- 檔案都放在 `~/.tmux-kit/`，下載的原始檔在 `~/.tmux-kit-src/`。
- `~/.tmux.conf` 最後加一行 `source-file -q ~/.tmux-kit/tmux-kit.conf`（原本的檔案先備份成 `~/.tmux.conf.bak-日期時間`）。用 codenv 的話，codenv 的設定本來就有這行，不會再加。
- 排列視窗：`~/Library/LaunchAgents/io.github.olilllioli287.tmux-kit-board.plist`，登入時在背景啟動，Cmd+Ctrl+A 才隨時有效。不需要「輔助使用」權限。
- Claude 回完反白：用 `claude plugin` 裝 Claude Code 外掛 `tmux-bell@tmux-kit`。

## 中文選單

前綴鍵連按兩次叫出來。前綴鍵是 Ctrl+A 就是 Ctrl+A 兩下；沒改過的 tmux 是 Ctrl+B 兩下。用 ↑ ↓ 選、Enter 執行，也可以用滑鼠點；Esc 或點選單外面關掉。

```
左右分割:右邊開一格            開新分頁                     幫這個工作階段取名
上下分割:下面開一格            下一個分頁 / 上一個分頁        關掉整個工作階段
放大這格 / 還原                列出所有分頁,切換過去          開關滑鼠功能
關掉這格                       幫這個分頁取名
                               這個分頁往左移 / 往右移
                               分頁重新編號(補上空號)
                               用滑鼠排列格子(開視窗)
                               模塊化排列(搬動格子、取名)…
```

「模塊化排列」是第二層選單：把這格搬到別的分頁、把別的格子搬進來、把這格拆成新的分頁，四種排法（左右並排、上下堆疊、左邊一大格、方格），還有幫格子取名。取了名的格子，名字顯示在格子上方。

另外也把幾個按鍵改成中文提示：前綴鍵 `x` 關掉這格、`&` 關掉整個分頁（按 Enter 確定，中文輸入法開著也行）、`,` 幫分頁取名。

注意：沒改過前綴鍵的話，Ctrl+B 兩下原本是「把 Ctrl+B 傳給程式」，裝了之後變成叫出選單。

## 排列視窗

在 iTerm（或 Mac 內建的「終端機」）裡按 **Cmd+Ctrl+A** 打開，再按一次收起來。在別的 App 按不會有反應，不會搶走那個 App 自己的快捷鍵；切到別的 App 時視窗也會自動收起來。也可以從中文選單的「用滑鼠排列格子」打開。

| 想做的事 | 怎麼做 |
|---|---|
| 把格子搬到別的分頁 | 把格子拖到那個分頁的卡片上 |
| 把格子拆成新的分頁 | 拖到虛線框「新 window」 |
| 交換兩個分頁的位置 | 按住分頁卡片的標題列，拖到另一個分頁上 |
| 把分頁搬到別的工作階段 | 拖到那個工作階段的名字 |
| 開新的工作階段 | 按右上角「新增 session」，或把分頁、格子拖到最下面的「新 session」 |
| 切換過去 | 點一下格子 |
| 改名字 | 雙擊分頁名字或格子，或按右鍵；工作階段按「改名」 |

Esc、Cmd+W、Cmd+Q 都只是收起來。iTerm 開成全螢幕時，視窗也會疊在畫面上。

## Claude 回完反白

tmux 本來就會把「響了一聲」的分頁反白，但 Claude Code 在 iTerm2 裡預設只送 iTerm2 自己的通知，不會響。這個外掛在 Claude 回覆完（`Stop`）、或要你允許／回答問題（`Notification` 的 `permission_prompt`、`elicitation_dialog`）時，替它在自己那格響一聲。你正在看的分頁不會響；不在 tmux 裡的 Claude Code 完全不受影響。

已經開著的 Claude Code 要重開才會用上。也可以不用安裝程式，直接在 Claude Code 裡裝：

```
/plugin marketplace add olilllioli287/tmux-kit
/plugin install tmux-bell@tmux-kit
```

## 從舊版搬過來

- **codenv 舊版**（2026-10-15 以前）：更新 codenv 時，舊的排列視窗會自動關掉，移到 `~/codenv-removed`。安裝 tmux-kit 就回來了，已經取好的格子名字也會保留。
- **claude-code-tmux-bell**：裝 tmux-kit 的第 3 項時，會自動移除舊的 `tmux-bell@tmux-bell`，換成 `tmux-bell@tmux-kit`。

## 解除安裝

```
zsh ~/.tmux-kit/uninstall.sh
```

檔案不會直接刪掉，全部移到 `~/tmux-kit-removed-日期時間`，想恢復可以搬回來。

## 檔案

| 檔案 | 做什麼 |
|---|---|
| `menu/tmux-kit.conf` | 載入點：把前綴鍵連按兩次綁到選單、格子名字列、中文提示 |
| `menu/menu.conf` | 中文選單本體（`display-menu -O -M`） |
| `board/tmux-kit-board.swift` | 排列視窗（SwiftUI），`--daemon` 時用 Carbon `RegisterEventHotKey` 註冊 Cmd+Ctrl+A，只在 iTerm／終端機在最前面時註冊 |
| `plugins/tmux-bell/` | Claude Code 外掛：`Stop`／`Notification` hook 寫一個 BEL 到自己那格的終端機 |
| `install.sh`、`get.sh`、`uninstall.sh` | 安裝、一行安裝、解除安裝 |

## English

Three small add-ons for tmux. The installer asks about each one.

- **Chinese menu** — press your prefix key twice (Ctrl+A Ctrl+A, or Ctrl+B Ctrl+B on stock tmux) for a mouse-clickable menu: split, zoom, close, rename windows and sessions, move panes between windows, change layouts, and name panes (shown in the pane border). Needs tmux 3.4+.
- **Board** — a macOS window (SwiftUI) that draws every session, window and pane; drag to rearrange. Toggle with Cmd+Ctrl+A while iTerm2 or Terminal is in front (the hotkey is released in other apps). Runs as a LaunchAgent; no Accessibility permission needed.
- **tmux-bell** — a Claude Code plugin that rings the bell in Claude's own pane when it finishes or needs permission, so tmux highlights that window. Replaces the standalone `claude-code-tmux-bell`.

```
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/olilllioli287/tmux-kit/main/get.sh)"
```

Uninstall with `zsh ~/.tmux-kit/uninstall.sh` (files are moved to `~/tmux-kit-removed-<date>`, not deleted).

## License

MIT
