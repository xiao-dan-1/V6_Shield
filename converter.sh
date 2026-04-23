#!/usr/bin/env bash
# ============================================================================
# V6_Shield — VLESS 订阅转换器
# 将 vless:// 链接解析为标准 Xray JSON 配置
# 纯 Bash 实现，零外部依赖
# ============================================================================

set -euo pipefail

# ── 颜色定义 ──────────────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly RESET='\033[0m'

# ── 默认端口 ──────────────────────────────────────────────────────────────────
readonly DEFAULT_SOCKS_PORT=37080
readonly DEFAULT_HTTP_PORT=37081

# ── 脚本根目录 ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROFILES_DIR="${SCRIPT_DIR}/profiles"

# ============================================================================
# 工具函数
# ============================================================================

die() {
    echo -e "${RED}[ERROR] $1${RESET}" >&2
    exit 1
}

usage() {
    cat <<EOF
${CYAN}V6_Shield — VLESS 订阅转换器${RESET}

用法:
    $(basename "$0") <vless://...> [-o <filename>]

参数:
    <vless://...>       VLESS 订阅链接
    -o <filename>       自定义输出文件名（不含路径，存入 profiles/）

示例:
    $(basename "$0") "vless://uuid@host:443?type=ws&security=tls&path=/ws#MyNode"
    $(basename "$0") "vless://uuid@host:443?type=tcp&security=reality&sni=example.com#MyNode" -o mynode.json

支持的传输协议:
    • WebSocket + TLS
    • TCP + Reality
    • gRPC + TLS
    • TCP + TLS
    • TCP (无加密)
EOF
    exit 0
}

# ============================================================================
# URL 解码（纯 Bash 实现）
# ============================================================================

url_decode() {
    local encoded="$1"
    local decoded=""
    local i=0
    local len=${#encoded}

    while (( i < len )); do
        local char="${encoded:i:1}"
        if [[ "$char" == "%" ]] && (( i + 2 < len )); then
            local hex="${encoded:i+1:2}"
            # 使用 printf 将十六进制转为字符
            decoded+=$(printf "\\x${hex}")
            (( i += 3 ))
        elif [[ "$char" == "+" ]]; then
            decoded+=" "
            (( i += 1 ))
        else
            decoded+="$char"
            (( i += 1 ))
        fi
    done

    echo "$decoded"
}

# ============================================================================
# VLESS 链接解析器
# ============================================================================

parse_vless_link() {
    local link="$1"

    # 校验协议头
    [[ "$link" =~ ^vless:// ]] || die "无效的 VLESS 链接：必须以 vless:// 开头"

    # 去掉 vless:// 前缀
    local body="${link#vless://}"

    # 提取备注名（# 之后的部分）
    if [[ "$body" == *"#"* ]]; then
        REMARK="$(url_decode "${body##*#}")"
        body="${body%%#*}"
    else
        REMARK="node_$(date +%s)"
    fi

    # 提取 UUID（@ 之前的部分）
    UUID="${body%%@*}"
    [[ -n "$UUID" ]] || die "无法解析 UUID"
    body="${body#*@}"

    # 分离 host:port 和查询参数
    local host_port_part="${body%%\?*}"
    local query_part=""
    if [[ "$body" == *"?"* ]]; then
        query_part="${body#*\?}"
    fi

    # 解析地址和端口（支持 IPv6 方括号格式）
    if [[ "$host_port_part" == "["* ]]; then
        # IPv6 地址: [::1]:443
        ADDRESS="${host_port_part%%]*}"
        ADDRESS="${ADDRESS#[}"
        local remaining="${host_port_part#*]}"
        PORT="${remaining#:}"
    else
        # IPv4 或域名: host:443
        ADDRESS="${host_port_part%%:*}"
        PORT="${host_port_part##*:}"
    fi

    [[ -n "$ADDRESS" ]] || die "无法解析服务器地址"
    [[ -n "$PORT" ]] || die "无法解析服务器端口"

    # 解析查询参数
    NETWORK="tcp"
    SECURITY="none"
    SNI=""
    WS_PATH="/"
    WS_HOST=""
    GRPC_SERVICE=""
    FLOW=""
    FINGERPRINT=""
    PUBLIC_KEY=""
    SHORT_ID=""
    SPIDER_X=""
    ALPN=""
    HEADER_TYPE=""

    if [[ -n "$query_part" ]]; then
        # 将 & 分隔的参数逐一解析
        local IFS='&'
        for param in $query_part; do
            local key="${param%%=*}"
            local value="${param#*=}"
            value="$(url_decode "$value")"

            case "$key" in
                type)           NETWORK="$value" ;;
                security)       SECURITY="$value" ;;
                sni)            SNI="$value" ;;
                path)           WS_PATH="$value" ;;
                host)           WS_HOST="$value" ;;
                serviceName)    GRPC_SERVICE="$value" ;;
                flow)           FLOW="$value" ;;
                fp)             FINGERPRINT="$value" ;;
                pbk)            PUBLIC_KEY="$value" ;;
                sid)            SHORT_ID="$value" ;;
                spx)            SPIDER_X="$value" ;;
                alpn)           ALPN="$value" ;;
                headerType)     HEADER_TYPE="$value" ;;
            esac
        done
        unset IFS
    fi
}

# ============================================================================
# JSON 配置生成器
# ============================================================================

# 转义 JSON 字符串中的特殊字符
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

generate_stream_settings() {
    local stream=""

    # 传输层配置
    stream+="\"network\": \"${NETWORK}\""

    # ── 安全层 ────────────────────────────────────────────────────────────
    if [[ "$SECURITY" == "tls" ]]; then
        stream+=",\n        \"security\": \"tls\""
        stream+=",\n        \"tlsSettings\": {"
        [[ -n "$SNI" ]] && stream+="\n          \"serverName\": \"$(json_escape "$SNI")\","
        if [[ -n "$FINGERPRINT" ]]; then
            stream+="\n          \"fingerprint\": \"$(json_escape "$FINGERPRINT")\","
        fi
        if [[ -n "$ALPN" ]]; then
            # 将逗号分隔的 alpn 转为 JSON 数组
            local alpn_arr=""
            local IFS=','
            for a in $ALPN; do
                [[ -n "$alpn_arr" ]] && alpn_arr+=", "
                alpn_arr+="\"$(json_escape "$a")\""
            done
            unset IFS
            stream+="\n          \"alpn\": [${alpn_arr}],"
        fi
        # 移除末尾逗号
        stream="${stream%,}"
        stream+="\n        }"

    elif [[ "$SECURITY" == "reality" ]]; then
        stream+=",\n        \"security\": \"reality\""
        stream+=",\n        \"realitySettings\": {"
        [[ -n "$SNI" ]] && stream+="\n          \"serverName\": \"$(json_escape "$SNI")\","
        [[ -n "$FINGERPRINT" ]] && stream+="\n          \"fingerprint\": \"$(json_escape "$FINGERPRINT")\","
        [[ -n "$PUBLIC_KEY" ]] && stream+="\n          \"publicKey\": \"$(json_escape "$PUBLIC_KEY")\","
        [[ -n "$SHORT_ID" ]] && stream+="\n          \"shortId\": \"$(json_escape "$SHORT_ID")\","
        [[ -n "$SPIDER_X" ]] && stream+="\n          \"spiderX\": \"$(json_escape "$SPIDER_X")\","
        # 移除末尾逗号
        stream="${stream%,}"
        stream+="\n        }"
    else
        stream+=",\n        \"security\": \"none\""
    fi

    # ── 传输层详细配置 ────────────────────────────────────────────────────
    if [[ "$NETWORK" == "ws" ]]; then
        stream+=",\n        \"wsSettings\": {"
        stream+="\n          \"path\": \"$(json_escape "$WS_PATH")\""
        if [[ -n "$WS_HOST" ]]; then
            stream+=",\n          \"headers\": { \"Host\": \"$(json_escape "$WS_HOST")\" }"
        fi
        stream+="\n        }"

    elif [[ "$NETWORK" == "grpc" ]]; then
        stream+=",\n        \"grpcSettings\": {"
        stream+="\n          \"serviceName\": \"$(json_escape "$GRPC_SERVICE")\","
        stream+="\n          \"multiMode\": false"
        stream+="\n        }"

    elif [[ "$NETWORK" == "tcp" ]]; then
        if [[ "$HEADER_TYPE" == "http" ]]; then
            stream+=",\n        \"tcpSettings\": {"
            stream+="\n          \"header\": { \"type\": \"http\" }"
            stream+="\n        }"
        fi
    fi

    echo -e "$stream"
}

generate_config() {
    local output_file="$1"

    # 用户配置（outbound）
    local user_block="\"id\": \"$(json_escape "$UUID")\", \"encryption\": \"none\""
    if [[ -n "$FLOW" ]]; then
        user_block+=", \"flow\": \"$(json_escape "$FLOW")\""
    fi

    local stream_settings
    stream_settings="$(generate_stream_settings)"

    cat > "$output_file" <<JSONEOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "port": ${DEFAULT_SOCKS_PORT},
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "udp": true
      }
    },
    {
      "tag": "http-in",
      "port": ${DEFAULT_HTTP_PORT},
      "listen": "127.0.0.1",
      "protocol": "http"
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$(json_escape "$ADDRESS")",
            "port": ${PORT},
            "users": [
              {
                ${user_block}
              }
            ]
          }
        ]
      },
      "streamSettings": {
        ${stream_settings}
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ]
}
JSONEOF
}

# ============================================================================
# 主逻辑
# ============================================================================

main() {
    local vless_link=""
    local output_name=""

    # 参数解析
    while (( $# > 0 )); do
        case "$1" in
            -h|--help)
                usage
                ;;
            -o)
                shift
                [[ $# -gt 0 ]] || die "-o 参数需要指定文件名"
                output_name="$1"
                ;;
            vless://*)
                vless_link="$1"
                ;;
            *)
                die "未知参数: $1\n使用 --help 查看帮助"
                ;;
        esac
        shift
    done

    [[ -n "$vless_link" ]] || die "请提供 VLESS 链接\n使用 --help 查看帮助"

    # 解析链接
    parse_vless_link "$vless_link"

    # 确定输出文件名
    if [[ -z "$output_name" ]]; then
        # 清理备注名中的非法文件名字符
        local safe_name="${REMARK//[^a-zA-Z0-9_\-\.]/_}"
        safe_name="${safe_name:-node_$(date +%s)}"
        output_name="${safe_name}.json"
    fi

    # 确保 .json 后缀
    [[ "$output_name" == *.json ]] || output_name="${output_name}.json"

    # 创建 profiles 目录
    mkdir -p "$PROFILES_DIR"

    local output_path="${PROFILES_DIR}/${output_name}"

    # 生成配置
    generate_config "$output_path"

    # 输出摘要
    echo ""
    echo -e "  ${GREEN}\u2713${RESET} ${CYAN}${REMARK}${RESET}"
    echo ""
    echo "    地址  ${ADDRESS}:${PORT}"
    echo "    协议  ${NETWORK} + ${SECURITY}"
    echo "    文件  ${output_path}"
    echo "    端口  SOCKS5=${DEFAULT_SOCKS_PORT}  HTTP=${DEFAULT_HTTP_PORT}"
    echo ""
    echo -e "  ${GREEN}\u2192${RESET} ./shield.sh 启动代理"
}

main "$@"
