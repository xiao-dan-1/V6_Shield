#!/usr/bin/env bash
# ============================================================================
# V6_Shield — Xray 核心安装工具
# 自动识别架构 → 抓取最新版本 → 下载并解压
# ============================================================================

set -euo pipefail

# ── 颜色定义 ──────────────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly DIM='\033[2m'
readonly RESET='\033[0m'

# ── 路径定义 ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly XRAY_BIN="${SCRIPT_DIR}/xray"

die() {
    echo -e "${RED}[FATAL] $1${RESET}" >&2
    exit 1
}

main() {
    echo ""
    echo -e "  ${GREEN}Xray 核心安装程序${RESET}"
    echo ""

    # 1. 识别架构
    local arch
    case "$(uname -m)" in
        x86_64)  arch="64" ;;
        aarch64) arch="arm64-v8a" ;;
        armv7*)  arch="arm32-v7a" ;;
        *)       die "不支持的系统架构: $(uname -m)" ;;
    esac

    # 2. 获取最新版本
    echo -e "    ${DIM}检查版本...${RESET}"
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | python3 -c "import sys, json; print(json.load(sys.stdin)['tag_name'])")
    [[ -n "$latest_version" ]] || die "无法从 GitHub 获取最新版本"

    local download_url="https://github.com/XTLS/Xray-core/releases/download/${latest_version}/Xray-linux-${arch}.zip"

    # 3. 下载与安装
    echo -e "    ${DIM}下载 ${latest_version} (${arch})...${RESET}"
    
    local tmp_zip="${SCRIPT_DIR}/xray_tmp.zip"
    
    # 使用 -s 保持输出整洁
    if ! curl -L -s -o "$tmp_zip" "$download_url"; then
        die "下载失败: ${download_url}"
    fi

    echo -e "    ${DIM}正在解压...${RESET}"
    if ! unzip -o "$tmp_zip" xray -d "$SCRIPT_DIR" > /dev/null; then
        rm -f "$tmp_zip"
        die "解压失败，请确保已安装 unzip"
    fi

    chmod +x "$XRAY_BIN"
    rm -f "$tmp_zip"

    # 4. 完成
    echo ""
    echo -e "  ${GREEN}\u2713${RESET} ${CYAN}安装成功${RESET}"
    echo ""
    echo "    版本  ${latest_version}"
    echo "    位置  ${XRAY_BIN}"
    echo ""
    echo -e "  ${GREEN}\u2192${RESET} ./converter.sh 导入节点"
}

main "$@"
