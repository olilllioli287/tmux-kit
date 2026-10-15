#!/bin/zsh
# tmux-kit 一行安裝 / 更新:把最新版下載到 ~/.tmux-kit-src,再執行裡面的 install.sh
# 用法: zsh -c "$(curl -fsSL https://raw.githubusercontent.com/olilllioli287/tmux-kit/main/get.sh)"
# 自己 fork 一份來改的話,把下面這行改成自己的「帳號/repo 名稱」
repo=olilllioli287/tmux-kit
src=~/.tmux-kit-src
tmp=$(mktemp -d) || exit 1
print "下載 tmux-kit 最新版…"
if ! curl -fsSL https://github.com/$repo/archive/refs/heads/main.tar.gz | tar -xz -C $tmp; then
  print "下載失敗,請確認網路連線後再試一次"
  rm -rf $tmp
  exit 1
fi
rm -rf $src && mv $tmp/*-main $src && rm -rf $tmp
zsh $src/install.sh
