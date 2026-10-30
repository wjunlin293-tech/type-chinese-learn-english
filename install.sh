#!/usr/bin/env bash
# 一键安装「打中文，顺便背单词」。打开「终端」，粘贴下面这一行，回车：
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/wjunlin293-tech/type-chinese-learn-english/main/install.sh)"
#
# 它会下载最新版程序到 ~/Library/Application Support/cn2en，然后运行 cn2en install：
# 自动装好鼠须管输入法、雾凇拼音、中英词表、语法模型和本机翻译服务，中途不问问题。
# 不需要事先装 Homebrew 或 git。重复运行没关系：已装好的部分会跳过，没装完的会接着装。
# 想少装一些可以在末尾加参数，例如 ... install.sh)" -- --no-mt
set -uo pipefail

APP_HOME=${CN2EN_APP_DIR:-"$HOME/Library/Application Support/cn2en"}
TARBALL=${CN2EN_APP_TARBALL_URL:-https://github.com/wjunlin293-tech/type-chinese-learn-english/archive/refs/heads/main.tar.gz}

fail() { printf '\n\033[31m没能完成：%s\033[0m\n%s\n' "$1" "${2:-}" >&2; exit 1; }

[ "$(uname)" = Darwin ] || [ -n "${CN2EN_ALLOW_NON_MAC:-}" ] || fail "目前只支持 macOS"
[ "$(id -u)" != 0 ] || fail "请不要用 sudo 运行" "直接粘贴安装命令即可，需要密码时会单独问你。"

printf '\033[1m==> 下载安装程序…\033[0m\n'
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 --connect-timeout 20 -o "$tmp/app.tar.gz" "$TARBALL" ||
  fail "下载失败" "请检查网络（公司或学校网络可能需要代理），然后重新运行同一条命令。"
mkdir -p "$tmp/x"
tar -xzf "$tmp/app.tar.gz" -C "$tmp/x" || fail "下载的文件不完整，请重新运行"
src=$(find "$tmp/x" -maxdepth 2 -name VERSION -exec dirname {} \; | head -1)
if [ -z "$src" ] || [ ! -x "$src/bin/cn2en" ]; then fail "下载的文件内容不对，请稍后再试"; fi

mkdir -p "$(dirname "$APP_HOME")"
rm -rf "$APP_HOME.old"
[ -d "$APP_HOME" ] && mv "$APP_HOME" "$APP_HOME.old"
mv "$src" "$APP_HOME" || { [ -d "$APP_HOME.old" ] && mv "$APP_HOME.old" "$APP_HOME"; fail "无法写入 $APP_HOME"; }
rm -rf "$APP_HOME.old"

exec "$APP_HOME/bin/cn2en" install "$@"
