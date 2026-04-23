#!/usr/bin/env bash
# ============================================================================
# V6_Shield — 系统代理开关
#   ./proxy.sh on    → 开启桌面 + 终端代理（写入 shell rc）
#   ./proxy.sh off   → 关闭桌面 + 终端代理（清除 shell rc）
# ============================================================================

set -euo pipefail

_SOCKS=37080
_HTTP=37081
_NO="localhost,127.0.0.0/8,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
_TAG="# >>> V6_Shield proxy >>>"
_END="# <<< V6_Shield proxy <<<"

# 定位 shell rc 文件
_rc() {
    case "$(basename "$SHELL")" in
        zsh)  echo "$HOME/.zshrc" ;;
        *)    echo "$HOME/.bashrc" ;;
    esac
}

_on() {
    local rc="$(_rc)"

    # ── 桌面代理 ──
    if command -v gsettings &>/dev/null; then
        gsettings set org.gnome.system.proxy mode 'manual'
        local p; for p in http https ftp; do
            gsettings set org.gnome.system.proxy.$p host '127.0.0.1'
            gsettings set org.gnome.system.proxy.$p port $_HTTP
        done
        gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
        gsettings set org.gnome.system.proxy.socks port $_SOCKS
        gsettings set org.gnome.system.proxy ignore-hosts "['${_NO//,/', '}']"
    fi

    # ── 终端代理（幂等写入 rc）──
    # 先清除旧块，再写入新块
    sed -i "/$_TAG/,/$_END/d" "$rc" 2>/dev/null || true
    cat >> "$rc" <<EOF
$_TAG
export http_proxy="http://127.0.0.1:$_HTTP"
export https_proxy="http://127.0.0.1:$_HTTP"
export all_proxy="socks5h://127.0.0.1:$_SOCKS"
export no_proxy="$_NO"
$_END
EOF

    echo "✓ 代理已开启  桌面 + 终端（已写入 ${rc##*/}）"
}

_off() {
    local rc="$(_rc)"

    # ── 桌面代理 ──
    if command -v gsettings &>/dev/null; then
        gsettings set org.gnome.system.proxy mode 'none'
    fi

    # ── 终端代理（清除 rc 中的标记块）──
    sed -i "/$_TAG/,/$_END/d" "$rc" 2>/dev/null || true

    echo "✓ 代理已关闭  桌面 + 终端（已清除 ${rc##*/}）"
}

case "${1:-}" in
    on)  _on  ;;
    off) _off ;;
    *)   echo "用法: ./proxy.sh on|off" ;;
esac
