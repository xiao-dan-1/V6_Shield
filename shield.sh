#!/usr/bin/env bash
# ============================================================================
# V6_Shield — 极简 Xray 启动脚本
# 环境校验 → 配置装载 → 端口检测 → 前台托管
# 遵循"前台运行，随终端生灭"哲学
# ============================================================================

set -euo pipefail

# ── 颜色定义 ──────────────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly RESET='\033[0m'

# ── 脚本根目录 ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly XRAY_BIN="${SCRIPT_DIR}/xray"
readonly PROFILES_DIR="${SCRIPT_DIR}/profiles"
readonly RUN_DIR="${SCRIPT_DIR}/run"

# ── 端口常量（与 converter.sh 保持一致）────────────────────────────────────────
readonly SOCKS_PORT=37080
readonly HTTP_PORT=37081

# ============================================================================
# 工具函数
# ============================================================================

die() {
    echo -e "${RED}[FATAL] $1${RESET}" >&2
    exit 1
}

# ============================================================================
# 步骤 1：开局物理斩断 (Fail-Fast)
# ============================================================================

preflight_check() {
    # ── 无核心则死 ────────────────────────────────────────────────────────
    if [[ ! -f "$XRAY_BIN" ]]; then
        die "未检测到 Xray 核心程序 (${XRAY_BIN})\n    请将 xray 二进制文件放置在项目根目录"
    fi

    if [[ ! -x "$XRAY_BIN" ]]; then
        die "Xray 核心程序无执行权限\n    请执行: chmod +x ${XRAY_BIN}"
    fi

    # ── 空配置则死 ────────────────────────────────────────────────────────
    if [[ ! -d "$PROFILES_DIR" ]]; then
        die "未检测到 profiles/ 目录\n    请先使用转换工具导入 VLESS 节点:\n    ./converter.sh \"vless://...\""
    fi
}

# ============================================================================
# 步骤 2：优雅寻址与装载
# ============================================================================

load_config() {
    local specified_config="${1:-}"

    if [[ -n "$specified_config" ]]; then
        # 激活阶段：将目标节点变为绝对活跃姿态
        local base_name="$(basename "$specified_config")"
        local target_path="${PROFILES_DIR}/${base_name}"

        [[ -f "$target_path" ]] || die "指定的配置文件不存在: ${target_path}"
        
        # 净化运行道并锚定配置
        mkdir -p "$RUN_DIR"
        rm -f "${RUN_DIR}"/*
        cp "$target_path" "${RUN_DIR}/config.json"
        echo "$base_name" > "${RUN_DIR}/node.name"
        
        CONFIG_NAME="$base_name"
    fi

    CONFIG_PATH="${RUN_DIR}/config.json"

    [[ -f "$CONFIG_PATH" ]] || die "运行专区不存在有效配置\n    请运行: ./shield.sh <节点文件名.json> 进行节点切换与锚定"

    # 抽取回显名字。由于运行区失去名字上下文，便优先从记录指针读取
    if [[ -z "${CONFIG_NAME:-}" ]]; then
        if [[ -f "${RUN_DIR}/node.name" ]]; then
            CONFIG_NAME="$(<"${RUN_DIR}/node.name")"
        else
            CONFIG_NAME="[运行沙箱当前配置]"
        fi
    fi

}

# ============================================================================
# 步骤 3：接管与生灭
# ============================================================================

# 跨平台端口检测
check_port() {
    local port="$1"
    local occupied=1  # 1 = not occupied (shell convention: 0=true, 1=false)

    # 优先使用 ss
    if command -v ss &>/dev/null; then
        ss -tlnH "sport = :${port}" 2>/dev/null | grep -q "${port}" && occupied=0
    # 次选 lsof
    elif command -v lsof &>/dev/null; then
        lsof -iTCP:"${port}" -sTCP:LISTEN -P -n &>/dev/null && occupied=0
    # 兜底 netstat
    elif command -v netstat &>/dev/null; then
        netstat -tln 2>/dev/null | grep -q ":${port} " && occupied=0
    fi

    return $occupied
}

verify_ports() {
    local has_conflict=0

    if check_port "$SOCKS_PORT"; then
        echo -e "${RED}[CONFLICT] SOCKS5 端口 ${SOCKS_PORT} 已被占用${RESET}" >&2
        has_conflict=1
    fi

    if check_port "$HTTP_PORT"; then
        echo -e "${RED}[CONFLICT] HTTP 端口 ${HTTP_PORT} 已被占用${RESET}" >&2
        has_conflict=1
    fi

    if (( has_conflict )); then
        die "端口冲突，无法启动\n    请检查是否有其他代理实例正在运行"
    fi
}

print_banner() {
    echo ""
    echo -e "  ${GREEN}${BOLD}V6_Shield${RESET} ${DIM}·${RESET} ${GREEN}引擎活跃${RESET}"
    echo ""
    echo -e "    ${DIM}SOCKS5${RESET}  ${CYAN}127.0.0.1:${SOCKS_PORT}${RESET}"
    echo -e "    ${DIM}HTTP${RESET}    ${CYAN}127.0.0.1:${HTTP_PORT}${RESET}"
    echo -e "    ${DIM}节点${RESET}    ${CONFIG_NAME}"
    echo -e "    ${DIM}退出${RESET}    Ctrl+C 或关闭终端"
    echo ""
    echo -e "  ${DIM}── Xray 输出 ─────────────────────${RESET}"
    echo ""
}

# ============================================================================
# 主逻辑
# ============================================================================

main() {
    local config_arg="${1:-}"

    # 步骤 1: Fail-Fast
    preflight_check

    # 步骤 2: 装载配置
    load_config "$config_arg"

    # 步骤 3: 端口校验 + 前台托管
    verify_ports
    print_banner

    # 阻塞托管: exec 替换当前进程为 Xray
    # 实现真正的"随窗生灭"——终端关闭即进程销毁
    exec "$XRAY_BIN" -c "$CONFIG_PATH"
}

main "$@"
