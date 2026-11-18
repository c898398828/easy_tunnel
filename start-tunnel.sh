#!/usr/bin/env bash
# =============================================================
# 内网穿透服务管理脚本 (cloudflared / ngrok, 支持双工具共存)
#
# 用法:
#   ./start-tunnel.sh                      # 交互式菜单
#   ./start-tunnel.sh install              # 安装工具 (可分别安装两种)
#   ./start-tunnel.sh start [tool|all] [fg]
#                                          # tool = cloudflared | ngrok
#                                          # 都配置了会询问; all = 两个都启动
#                                          # fg = 前台运行 (调试用)
#   ./start-tunnel.sh status               # 查看运行状态 (两个工具分别显示)
#   ./start-tunnel.sh stop [tool|all]      # 停止服务 (两个都在跑会询问)
#   ./start-tunnel.sh config               # 修改配置
#   ./start-tunnel.sh show                 # 查看当前配置
#
# 配置: tunnel.conf    日志: tunnel.<tool>.log    PID: tunnel.<tool>.pid
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/tunnel.conf"

# -------------------- 默认配置 --------------------
CLOUDFLARED_TOKEN=""   # cloudflared 隧道 token (空 = 未配置)
NGROK_TOKEN=""         # ngrok authtoken (空 = 未配置)
PORT="8888"            # 本地要暴露的端口 (仅 ngrok 使用)
NETNS="proxytest"      # 网络命名空间, 留空表示不使用 netns
METRICS_PORT="20241"   # cloudflared metrics 端口
BIN_DIR="${SCRIPT_DIR}"  # 二进制存放目录

# -------------------- 工具函数 --------------------
c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'; c_cyan=$'\e[36m'; c_off=$'\e[0m'
info()  { printf '%s[INFO]%s %s\n'  "$c_cyan"   "$c_off" "$*"; }
warn()  { printf '%s[WARN]%s %s\n'  "$c_yellow" "$c_off" "$*"; }
error() { printf '%s[ERROR]%s %s\n' "$c_red"    "$c_off" "$*" >&2; }

load_conf() {
    if [[ -f "$CONF_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONF_FILE"
        # 兼容旧版单工具配置 (TOOL/TOKEN) 迁移到双 token 字段
        if [[ -n "${TOOL:-}" && -n "${TOKEN:-}" ]]; then
            case "$TOOL" in
                cloudflared) [[ -z "$CLOUDFLARED_TOKEN" ]] && CLOUDFLARED_TOKEN="$TOKEN" ;;
                ngrok)       [[ -z "$NGROK_TOKEN" ]]       && NGROK_TOKEN="$TOKEN" ;;
            esac
        fi
    fi
}

save_conf() {
    cat > "$CONF_FILE" <<EOF
# 内网穿透配置 (由 start-tunnel.sh 生成)
CLOUDFLARED_TOKEN="${CLOUDFLARED_TOKEN}"
NGROK_TOKEN="${NGROK_TOKEN}"
PORT="${PORT}"
NETNS="${NETNS}"
METRICS_PORT="${METRICS_PORT}"
BIN_DIR="${BIN_DIR}"
EOF
    chmod 600 "$CONF_FILE"
    info "配置已保存到 ${CONF_FILE}"
}

prompt() { # prompt "提示" "默认值" -> stdout
    local ans
    read -r -p "$(printf '%s%s%s%s' "$c_green" "$1" "$c_off" "${2:+ [${2}]: }")" ans
    echo "${ans:-$2}"
}

require_cmd() { command -v "$1" >/dev/null 2>&1; }

tool_token()  { case "$1" in cloudflared) echo "$CLOUDFLARED_TOKEN" ;; ngrok) echo "$NGROK_TOKEN" ;; esac; }
tool_set_token() { case "$1" in cloudflared) CLOUDFLARED_TOKEN="$2" ;; ngrok) NGROK_TOKEN="$2" ;; esac; }
tool_bin()    { echo "${BIN_DIR}/$1"; }
tool_pid_file() { echo "${SCRIPT_DIR}/tunnel.$1.pid"; }
tool_log_file() { echo "${SCRIPT_DIR}/tunnel.$1.log"; }

# 工具是否已配置 (token 已填 且 二进制存在)
tool_ready() {
    [[ -n "$(tool_token "$1")" ]] && [[ -x "$(tool_bin "$1")" ]]
}

ready_tools() {
    local out=() t
    for t in cloudflared ngrok; do tool_ready "$t" && out+=("$t"); done
    echo "${out[*]:-}"
}

check_linux_amd64() {
    if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
        warn "当前系统不是 linux-amd64, 下载链接按 linux-amd64 提供, 可能无法运行"
    fi
}

# -------------------- 进程管理 --------------------
get_pid() { local f; f="$(tool_pid_file "$1")"; [[ -f "$f" ]] && cat "$f" || true; }

is_running() { # is_running <tool>
    local pid
    pid="$(get_pid "$1")"
    [[ -n "$pid" ]] || return 1
    kill -0 "$pid" 2>/dev/null && return 0
    sudo kill -0 "$pid" 2>/dev/null && return 0
    return 1
}

pkill_by_tool() { # 兜底清理
    sudo pkill -f "$(tool_bin "$1")" 2>/dev/null || true
}

# -------------------- 安装 --------------------
install_cloudflared() {
    info "下载 cloudflared (linux-amd64) 到 ${BIN_DIR} ..."
    check_linux_amd64
    require_cmd wget || { error "缺少 wget, 请先安装"; exit 1; }
    wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
        -O "$(tool_bin cloudflared)"
    chmod +x "$(tool_bin cloudflared)"
    info "cloudflared 安装完成: $(tool_bin cloudflared)"
}

install_ngrok() {
    info "下载 ngrok (linux-amd64) 到 ${BIN_DIR} ..."
    check_linux_amd64
    require_cmd wget || { error "缺少 wget, 请先安装"; exit 1; }
    local tmp
    tmp="$(mktemp -d)"
    wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz -O "${tmp}/ngrok.tgz"
    tar -xzf "${tmp}/ngrok.tgz" -C "$tmp"
    mv "${tmp}/ngrok" "$(tool_bin ngrok)"
    chmod +x "$(tool_bin ngrok)"
    rm -rf "$tmp"
    info "ngrok 安装完成: $(tool_bin ngrok)"
}

do_install() {
    local inst_hint=""
    [[ -x "$(tool_bin cloudflared)" ]] && inst_hint="${inst_hint} cloudflared已装"
    [[ -x "$(tool_bin ngrok)" ]] && inst_hint="${inst_hint} ngrok已装"
    [[ -n "$inst_hint" ]] && info "已安装:${inst_hint} (重复执行本命令可安装另一个)"
    local choice tool
    choice="$(prompt "安装哪个工具? [1=cloudflared | 2=ngrok]" "")"
    case "$choice" in
        1) tool="cloudflared"; install_cloudflared ;;
        2) tool="ngrok";       install_ngrok ;;
        *) error "无效选择"; exit 1 ;;
    esac

    local tok
    tok="$(prompt "请输入 ${tool} 的 token" "$(tool_token "$tool")")"
    if [[ -z "$tok" ]]; then
        warn "token 为空, ${tool} 将无法启动"
    fi
    tool_set_token "$tool" "$tok"

    # 端口只有 ngrok 需要; cloudflared 是出站隧道, 本地端口在 Cloudflare 后台路由里配
    if [[ "$tool" == "ngrok" ]]; then
        PORT="$(prompt "本地暴露端口" "$PORT")"
    fi

    # ngrok 需要先把 authtoken 写入其配置
    if [[ "$tool" == "ngrok" && -n "$NGROK_TOKEN" ]]; then
        "$(tool_bin ngrok)" config add-authtoken "$NGROK_TOKEN" \
            || warn "ngrok authtoken 写入失败, 可稍后手动执行"
    fi

    save_conf
    info "安装完成, 可执行 ./start-tunnel.sh start 启动"
}

# -------------------- 启动 --------------------
start_cloudflared() {
    if [[ -n "$NETNS" ]]; then
        exec sudo ip netns exec "$NETNS" \
            "$(tool_bin cloudflared)" tunnel \
            --protocol http2 \
            --metrics "127.0.0.1:${METRICS_PORT}" \
            --loglevel info \
            run --token "$CLOUDFLARED_TOKEN"
    else
        exec "$(tool_bin cloudflared)" tunnel \
            --protocol http2 \
            --metrics "127.0.0.1:${METRICS_PORT}" \
            --loglevel info \
            run --token "$CLOUDFLARED_TOKEN"
    fi
}

start_ngrok() {
    if [[ -n "$NETNS" ]]; then
        exec sudo ip netns exec "$NETNS" \
            runuser -u "$(id -un)" -- \
            env -u HTTP_PROXY -u HTTPS_PROXY \
                -u http_proxy -u https_proxy \
                -u ALL_PROXY -u all_proxy \
                -u NO_PROXY -u no_proxy \
            "$(tool_bin ngrok)" http "127.0.0.1:${PORT}" \
                --log stdout \
                --log-level info
    else
        exec env -u HTTP_PROXY -u HTTPS_PROXY \
                -u http_proxy -u https_proxy \
                -u ALL_PROXY -u all_proxy \
                -u NO_PROXY -u no_proxy \
            "$(tool_bin ngrok)" http "127.0.0.1:${PORT}" \
                --log stdout \
                --log-level info
    fi
}

# start_one <tool> [fg]
start_one() {
    local tool="$1" fg="${2:-}"
    local tok
    tok="$(tool_token "$tool")"
    [[ -n "$tok" ]] || { error "${tool} 未配置 token, 请先 ./start-tunnel.sh install 或 config"; return 1; }
    [[ -x "$(tool_bin "$tool")" ]] || { error "${tool} 未安装 ($(tool_bin "$tool") 不存在)"; return 1; }

    if is_running "$tool"; then
        warn "${tool} 已在运行 (PID $(get_pid "$tool")), 跳过"
        return 0
    fi

    local pid_file log_file
    pid_file="$(tool_pid_file "$tool")"
    log_file="$(tool_log_file "$tool")"
    rm -f "$pid_file"

    if [[ "$fg" == "fg" ]]; then
        info "前台启动 ${tool} (Ctrl+C 退出) ..."
        "start_${tool}"
        return
    fi

    info "后台启动 ${tool} (netns=${NETNS:-none}), 日志: ${log_file}"
    # nohup 无法执行 shell 函数, 通过脚本自身内部命令 __run 调起
    nohup "$0" __run "$tool" >"$log_file" 2>&1 &
    echo $! > "$pid_file"
    sleep 2
    if is_running "$tool"; then
        info "${tool} 启动成功, PID $(get_pid "$tool")"
        [[ "$tool" == "ngrok" ]] && tip_ngrok_url
    else
        error "${tool} 启动失败, 最近日志 (${log_file}):"
        tail -n 20 "$log_file" || true
        rm -f "$pid_file"
        return 1
    fi
}

tip_ngrok_url() {
    local url
    url="$(grep -oE 'https://[a-zA-Z0-9.-]+ngrok[a-zA-Z0-9.-]*' "$(tool_log_file ngrok)" 2>/dev/null | tail -1 || true)"
    [[ -n "$url" ]] && info "ngrok 公网地址: ${url}"
}

# 解析要启动哪些工具; 参数为任意组合的 [tool|all] [fg], 顺序不限
resolve_tools() {
    local arg="" fg="" a
    for a in "$@"; do
        if [[ "$a" == "fg" ]]; then fg="fg"
        elif [[ -n "$a" ]]; then arg="$a"
        fi
    done
    local ready
    ready="$(ready_tools)"
    case "$ready" in
        "") error "没有任何工具完成配置 (需 token + 二进制), 请先 ./start-tunnel.sh install"; exit 1 ;;
        cloudflared|ngrok) echo "$ready $fg" ; return ;;
    esac

    # 两个都就绪
    if [[ "$arg" == "all" ]]; then
        echo "cloudflared ngrok $fg"
    elif [[ "$arg" == "cloudflared" || "$arg" == "ngrok" ]]; then
        echo "$arg $fg"
    else
        echo "$(prompt_two_choice) $fg"
    fi
}

prompt_two_choice() {
    local c
    c="$(prompt "两个工具都已配置, 启动哪个? [1=cloudflared | 2=ngrok | 3=两个都启动]" "3")"
    case "$c" in
        1) echo "cloudflared" ;;
        2) echo "ngrok" ;;
        3) echo "cloudflared ngrok" ;;
        *) error "无效选择"; exit 1 ;;
    esac
}

# do_start [tool|all] [fg] — 参数顺序不限
do_start() {
    local resolved fg="" t failed=0
    resolved="$(resolve_tools "$@")"
    [[ "$resolved" == *" fg" || "$resolved" == "fg" ]] && fg="fg"
    for t in $resolved; do
        [[ "$t" == "fg" ]] && continue
        start_one "$t" "$fg" || failed=1
    done
    [[ $failed -eq 0 ]] || exit 1
}

# -------------------- 状态 / 停止 --------------------
do_status() {
    local t running_any=""
    for t in cloudflared ngrok; do
        echo "==== ${t} ===="
        if ! tool_ready "$t"; then
            echo "  配置: ${c_yellow}未就绪${c_off} (token 或二进制缺失)"
        elif is_running "$t"; then
            running_any="$t"
            echo "  状态: ${c_green}运行中${c_off} (PID $(get_pid "$t"))"
            [[ "$t" == "ngrok" ]] && tip_ngrok_url
        else
            echo "  状态: ${c_red}未运行${c_off}"
        fi
        local log
        log="$(tool_log_file "$t")"
        if [[ -f "$log" ]]; then
            echo "  日志尾部:"
            tail -n 3 "$log" 2>/dev/null | sed 's/^/    /' || true
        fi
    done
    [[ -n "$running_any" ]] || info "提示: 当前没有隧道在运行"
}

stop_one() {
    local tool="$1"
    if ! is_running "$tool"; then
        pkill_by_tool "$tool"
        warn "${tool} 未在运行"
        rm -f "$(tool_pid_file "$tool")"
        return 0
    fi
    local pid
    pid="$(get_pid "$tool")"
    info "停止 ${tool} (PID ${pid}) ..."
    sudo kill "$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    local i
    for i in $(seq 1 10); do
        is_running "$tool" || break
        sleep 0.5
    done
    if is_running "$tool"; then
        warn "${tool} 未退出, 强制清理 ..."
        sudo kill -9 "$pid" 2>/dev/null || true
        pkill_by_tool "$tool"
    fi
    rm -f "$(tool_pid_file "$tool")"
    info "${tool} 已停止"
}

running_tools() {
    local out=() t
    for t in cloudflared ngrok; do is_running "$t" && out+=("$t"); done
    echo "${out[*]:-}"
}

do_stop() {
    local arg="${1:-}"
    local running
    running="$(running_tools)"
    case "$running" in
        "") pkill_by_tool cloudflared; pkill_by_tool ngrok; warn "没有隧道在运行"; exit 0 ;;
        cloudflared|ngrok)
            [[ "$arg" == "cloudflared" || "$arg" == "ngrok" ]] && running="$arg"
            ;;
        *)  # 两个都在跑
            if [[ "$arg" != "cloudflared" && "$arg" != "ngrok" && "$arg" != "all" ]]; then
                local c
                c="$(prompt "两个隧道都在运行, 停止哪个? [1=cloudflared | 2=ngrok | 3=全部停止]" "3")"
                case "$c" in
                    1) running="cloudflared" ;; 2) running="ngrok" ;;
                    3) running="cloudflared ngrok" ;;
                    *) error "无效选择"; exit 1 ;;
                esac
            elif [[ "$arg" == "all" ]]; then
                running="cloudflared ngrok"
            else
                running="$arg"
            fi
            ;;
    esac
    local t
    for t in $running; do stop_one "$t"; done
}

# -------------------- 修改配置 --------------------
do_config() {
    info "修改配置 (直接回车保留当前值)"
    local choice tool
    choice="$(prompt "配置哪个工具? [1=cloudflared | 2=ngrok]" "")"
    case "$choice" in
        1) tool="cloudflared" ;;
        2) tool="ngrok" ;;
        *) error "无效选择"; exit 1 ;;
    esac
    local tok
    tok="$(prompt "${tool} token" "$(tool_token "$tool")")"
    tool_set_token "$tool" "$tok"

    if [[ "$tool" == "ngrok" ]]; then
        PORT="$(prompt "本地暴露端口" "$PORT")"
    fi
    echo "--- 公共配置 ---"
    METRICS_PORT="$(prompt "metrics 端口 (cloudflared 使用)" "$METRICS_PORT")"
    NETNS="$(prompt "网络命名空间 (留空=不使用 netns)" "$NETNS")"
    BIN_DIR="$(prompt "二进制目录" "$BIN_DIR")"

    # ngrok 换 token 时同步更新 authtoken
    if [[ "$tool" == "ngrok" && -x "$(tool_bin ngrok)" && -n "$NGROK_TOKEN" ]]; then
        "$(tool_bin ngrok)" config add-authtoken "$NGROK_TOKEN" || true
    fi
    save_conf
}

# -------------------- 查看配置 --------------------
do_show() {
    if [[ ! -f "$CONF_FILE" ]]; then
        warn "尚未创建配置 (${CONF_FILE})"
        return
    fi
    echo "---- ${CONF_FILE} ----"
    sed -E 's/(_TOKEN=".{4}).*(".{4}")/\1****\2/' "$CONF_FILE"
}

# -------------------- 入口 --------------------
main() {
    load_conf
    local cmd="${1:-}"
    if [[ -z "$cmd" ]]; then
        cat <<MENU
==========================================
  内网穿透服务管理 (cloudflared / ngrok)
==========================================
  1) 安装工具
  2) 启动服务 (后台)
  3) 查看状态
  4) 停止服务
  5) 修改配置
  6) 查看配置
  0) 退出
MENU
        cmd="$(prompt "请选择操作" "0")"
        case "$cmd" in
            1) cmd="install" ;; 2) cmd="start" ;;
            3) cmd="status" ;; 4) cmd="stop" ;;
            5) cmd="config" ;; 6) cmd="show" ;;
            *) exit 0 ;;
        esac
    fi
    case "$cmd" in
        install) do_install ;;
        start)   do_start "${2:-}" "${3:-}" ;;
        __run)   # 内部命令: 供后台 nohup 调用, exec 替换为真实隧道进程
            case "${2:-}" in
                cloudflared) start_cloudflared ;;
                ngrok)       start_ngrok ;;
                *) error "内部错误: 未知工具 '${2:-}'"; exit 1 ;;
            esac
            ;;
        status)  do_status ;;
        stop)    do_stop "${2:-}" ;;
        config)  do_config ;;
        show)    do_show ;;
        *) error "未知命令: $cmd (可用: install | start [tool|all] [fg] | status | stop [tool|all] | config | show)"; exit 1 ;;
    esac
}

main "$@"
