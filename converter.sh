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
    echo -e "${RED}[FATAL] $1${RESET}" >&2
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
    • gRPC + TLS/Reality
    • TCP + TLS
    • TCP (无加密)
EOF
    exit 0
}

# URL 解码：%XX → 对应字符（RFC 3986 标准，+ 号保持原义）
url_decode() { printf '%b' "${1//%/\\x}"; }

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

# 将参数用指定分隔符连接（数组聚合模式的基础设施）
_join() {
    local sep="$1"; shift
    (( $# )) || return 0
    local first="$1"; shift
    printf '%s' "$first"
    printf '%s' "${@/#/$sep}"
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
        ADDRESS="${host_port_part%%]*}"
        ADDRESS="${ADDRESS#[}"
        local remaining="${host_port_part#*]}"
        PORT="${remaining#:}"
    else
        ADDRESS="${host_port_part%%:*}"
        PORT="${host_port_part##*:}"
    fi

    [[ -n "$ADDRESS" ]] || die "无法解析服务器地址"
    [[ -n "$PORT" ]] || die "无法解析服务器端口"

    # 初始化查询参数默认值
    NETWORK="tcp"    SECURITY="none"
    SNI=""           WS_PATH="/"     WS_HOST=""
    GRPC_SERVICE=""  FLOW=""         FINGERPRINT=""
    PUBLIC_KEY=""    SHORT_ID=""     SPIDER_X=""
    ALPN=""          HEADER_TYPE=""

    if [[ -n "$query_part" ]]; then
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
# JSON 配置生成器（声明式微引擎）
# ============================================================================

# 声明式 JSON 对象构建：空值自动过滤，自动处理引号（支持自动识别嵌套 {}/[]/bool）
_obj() {
    local f=()
    while (( $# >= 2 )); do
        if [[ -n "$1" && -n "$2" ]]; then
            if [[ "$2" =~ ^(\{.*\}|\[.*\]|true|false)$ ]]; then
                f+=("\"$1\": $2")
            else
                f+=("\"$1\": \"$(json_escape "$2")\"")
            fi
        fi
        shift 2
    done
    echo "{$(_join ', ' "${f[@]}")}"
}

_tls_block() {
    local alpn_json=""
    if [[ -n "$ALPN" ]]; then
        local items=()
        local IFS=','
        for a in $ALPN; do items+=("\"$(json_escape "$a")\""); done
        unset IFS
        alpn_json="[$(_join ', ' "${items[@]}")]"
    fi
    _obj serverName "$SNI" fingerprint "$FINGERPRINT" alpn "$alpn_json"
}

_reality_block() {
    _obj serverName "$SNI" fingerprint "$FINGERPRINT" \
         publicKey "$PUBLIC_KEY" shortId "$SHORT_ID" spiderX "$SPIDER_X"
}

_ws_block() {
    local headers_json=""
    [[ -n "$WS_HOST" ]] && headers_json="{\"Host\": \"$(json_escape "$WS_HOST")\"}"
    _obj path "$WS_PATH" headers "$headers_json"
}

_grpc_block() {
    _obj serviceName "$GRPC_SERVICE" multiMode "false"
}

generate_stream_settings() {
    local sec_key="" sec_val="" net_key="" net_val=""
    
    case "$SECURITY" in
        tls)     sec_key="tlsSettings"     sec_val="$(_tls_block)" ;;
        reality) sec_key="realitySettings" sec_val="$(_reality_block)" ;;
    esac

    case "$NETWORK" in
        ws)   net_key="wsSettings"   net_val="$(_ws_block)" ;;
        grpc) net_key="grpcSettings" net_val="$(_grpc_block)" ;;
        tcp)  [[ "$HEADER_TYPE" == "http" ]] && net_key="tcpSettings" net_val="{\"header\": {\"type\": \"http\"}}" ;;
    esac

    _obj network "$NETWORK" \
         security "$SECURITY" \
         "$sec_key" "$sec_val" \
         "$net_key" "$net_val"
}

generate_config() {
    local output_file="$1"

    # 生成配置块
    local user_obj="$(_obj id "$UUID" encryption "none" flow "$FLOW")"
    local stream_settings_obj="$(generate_stream_settings)"

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
              ${user_obj}
            ]
          }
        ]
      },
      "streamSettings": ${stream_settings_obj}
    },
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "outboundTag": "direct",
        "ip": ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "::1/128", "fc00::/7", "fe80::/10"]
      },
      {
        "type": "field",
        "outboundTag": "direct",
        "domain": ["localhost"]
      }
    ]
  }
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
        # 剔除文件系统危险字符，保留 Unicode（中文/emoji 等）
        local safe_name="${REMARK//[\/\\:*?\"<>| ]/_}"
        safe_name="${safe_name:-node_$(date +%s)}"
        output_name="${safe_name}.json"
    fi

    # 确保 .json 后缀
    [[ "$output_name" == *.json ]] || output_name="${output_name}.json"

    # 创建 profiles 目录
    mkdir -p "$PROFILES_DIR"

    local output_path="${PROFILES_DIR}/${output_name}"

    # 生成配置至库
    generate_config "$output_path"

    # 输出摘要
    echo ""
    echo -e "  ${GREEN}\u2713${RESET} ${CYAN}${REMARK}${RESET}"
    echo ""
    echo "    地址  ${ADDRESS}:${PORT}"
    echo "    协议  ${NETWORK} + ${SECURITY}"
    echo "    文件  ${output_path}"
    echo ""
    echo -e "  ${GREEN}\u2192${RESET} ./shield.sh ${output_name}  启动并激活此节点"
}

main "$@"
