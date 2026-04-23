#!/usr/bin/env bash
# ============================================================================
# V6_Shield — 独立配置节点管理控制台
# ============================================================================

set -euo pipefail

# ── 颜色与定义 ──────────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly DIM='\033[2m'
readonly RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROFILES_DIR="${SCRIPT_DIR}/profiles"
readonly RUN_DIR="${SCRIPT_DIR}/run"

die() {
    echo -e "${RED}[FATAL] $1${RESET}" >&2
    exit 1
}

# ============================================================================
# 核心逻辑
# ============================================================================

main() {
    echo ""
    echo -e "  ${GREEN}V6_Shield · 节点管理阵列${RESET}"
    echo ""

    if [[ ! -d "$PROFILES_DIR" ]]; then
        die "未检测到 profiles/ 目录，请先导入节点"
    fi

    # 获取包含文件名的列表
    local items=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && items+=("$(basename "$file")")
    done < <(find "$PROFILES_DIR" -maxdepth 1 -name '*.json' -type f | sort)

    if (( ${#items[@]} == 0 )); then
        die "配置仓库为空"
    fi

    # 获取当前活跃记录
    local active_name=""
    if [[ -f "${RUN_DIR}/node.name" ]]; then
        active_name="$(<"${RUN_DIR}/node.name")"
    fi

    # 循环宣读
    local idx=1
    for name in "${items[@]}"; do
        local display_idx="[${idx}]"
        
        # ── 闪电测速 (TCP Ping) ────────────
        local config_file="${PROFILES_DIR}/${name}"
        # 精准切出 vnext 远端节点块以避免提取到本地 Inbound 的监听端口
        local vnext_block=$(sed -n '/"vnext"/,/"users"/p' "$config_file")
        local addr=$(echo "$vnext_block" | grep '"address":' | head -n 1 | sed -E 's/.*"address":\s*"([^"]+)".*/\1/')
        local port=$(echo "$vnext_block" | grep '"port":' | head -n 1 | sed -E 's/.*"port":\s*([0-9]+).*/\1/')
        
        local latency_str="${RED}超时/阻断${RESET}"
        if [[ -n "$addr" && -n "$port" ]]; then
            local start end latency
            start=$(date +%s%3N)
            if timeout 1 bash -c "</dev/tcp/${addr}/${port}" 2>/dev/null; then
                end=$(date +%s%3N)
                latency=$((end - start))
                latency_str="$(printf "%4sms" "$latency")"
            fi
        fi
        # ───────────────────────────────────

        if [[ "$name" == "$active_name" ]]; then
            # 活跃节点高亮标注
            echo -e "    ${CYAN}${display_idx}${RESET}  ${name}    (${latency_str})  ${GREEN}[活跃]${RESET}"
        else
            echo -e "    ${display_idx}  ${name}    (${latency_str})"
        fi
        ((idx++))
    done

    echo ""
    echo -n -e "  ${DIM}输入编号切换节点，或前缀 d 删除(例 d1)，空回车退出: ${RESET}"
    local choice
    read -r choice

    if [[ -z "$choice" ]]; then
        exit 0
    fi

    # ── 删除操作 ──
    if [[ "$choice" =~ ^d([0-9]+)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        if (( num >= 1 && num <= ${#items[@]} )); then
            local target="${items[$((num-1))]}"
            rm -f "${PROFILES_DIR}/${target}"
            echo -e "  ${GREEN}\u2713${RESET} 已删除节点: ${CYAN}${target}${RESET}"
            
            # 若删去的是当前活跃节点，则清空跑道防侧漏
            if [[ "$target" == "$active_name" ]]; then
                rm -f "${RUN_DIR}/config.json" "${RUN_DIR}/node.name"
            fi
        else
            die "无效的索引: $num"
        fi
    # ── 切换操作 ──
    elif [[ "$choice" =~ ^[0-9]+$ ]]; then
        if (( choice >= 1 && choice <= ${#items[@]} )); then
            local target="${items[$((choice-1))]}"
            
            # 执行纯粹隔离切换
            mkdir -p "$RUN_DIR"
            rm -f "${RUN_DIR}"/*
            cp "${PROFILES_DIR}/${target}" "${RUN_DIR}/config.json"
            echo "$target" > "${RUN_DIR}/node.name"

            echo ""
            echo -e "  ${GREEN}\u2713${RESET} 已装配至沙箱: ${CYAN}${target}${RESET}"
            echo -e "  ${DIM}→ 若代理进程运行中，请在原终端按 Ctrl+C 后重启 ./shield.sh${RESET}"
        else
            die "无效的索引: $choice"
        fi
    else
        die "无效的指令"
    fi
}

main "$@"
