#!/usr/bin/env bash
# ==============================================================================
# TinyTitan Model Server Management Script (Qwen 3.8 Flash Next / 125B 4-Bit)
# TinyTitan 本地模型服务管理脚本（双语注释版 · 对齐官方最新规范）
# ==============================================================================

ROOT_DIR="${ROOT_DIR:-$HOME/TinyTitan}"
if [[ ! -d "$ROOT_DIR" && -d "/Volumes/JustinSSD/TinyTitan-work" ]]; then
    ROOT_DIR="/Volumes/JustinSSD/TinyTitan-work"
fi
BIN="$ROOT_DIR/bin/TinyTitanServer"
LOG_FILE="$ROOT_DIR/server.log"
PID_FILE="$ROOT_DIR/server.pid"

# 加载 TinyTitan Manager 持久化配置 (若存在)
if [[ -f "$ROOT_DIR/config.env" ]]; then
    # shellcheck disable=SC1090
    source "$ROOT_DIR/config.env"
fi

# ==============================================================================
# 1. Network & Model Path / 网络端口与模型路径
# ==============================================================================

# [EN] HTTP listening port for OpenAI-compatible API.
# [CN] OpenAI 兼容 API 服务的监听端口（如 1231、8080 等）。
PORT="${PORT:-1231}"

# [EN] Path to the unpacked/repacked model directory (.gturbo format).
# [CN] 已打包的模型目录路径（包含 manifest.json、model_weights.bin、packed_experts 等）。
MODEL="${MODEL:-$ROOT_DIR/models/qwen3.8-flash-next_125B_A6B_4Bit}"


# ==============================================================================
# 2. RAM & Hardware Resource Budget / 内存与硬件资源控制
# ==============================================================================

# [EN] --ram-budget <size> (e.g. 4G, 6G, 8G, 10G, 12G, 16G)
#      Resident-memory (RSS) target for the ENTIRE process, not just expert cache.
#      Formula: Expert Cache = target - (resident weights 3.22G + runtime floor 0.53G).
#      - Minimum: 4G (Below 4G, base weights ~3.8G + 8 slots minimum cannot fit).
#      - 8G (Recommended for 16GB Mac): Allocates 32 slots (~4GB cache), real peak RSS ~7.4-7.8G.
#      - 12G: Allocates 64 slots (~8GB cache), peak RSS ~11.7G (faster decode, but needs 24GB+ Mac).
# [CN] --ram-budget <容量>（整机进程常驻物理内存 RSS 真实目标上限）
#      官方最新核心重构：此参数控制的是“整个进程”的总内存占用，而非仅仅专家缓存！
#      底层分配公式：实际专家缓存 = 目标值 - (常驻骨干权重 3.22G + 运行时底噪 0.53G)。
#      - 允许最低值：4G（低于4G无法容纳约3.8G固有常驻底座与最少8个槽位）。
#      - 8G（16GB Mac 黄金推荐值）：自动分配 32 个专家槽位（约 4GB 缓存），实测峰值稳定在 7.4~7.8GB，
#        为 macOS 系统和其它应用留出 8GB+ 充足可用空间，彻底杜绝爆内存或频繁 swap。
#      - 12G（大内存机型）：分配 64 个专家槽位（约 8GB 缓存），峰值 ~11.7GB，适合 24GB+ 内存机型。
RAM_BUDGET="${RAM_BUDGET:-8G}"

# [EN] --expert-cache-slots <count> (Optional manual override)
#      Routed-expert cache slots per layer: 8, 16, 24, 32, 40, 48, 64, 96, 112, 128, 160, 192, 256.
#      Leave empty to let --ram-budget automatically compute the optimal fit.
# [CN] --expert-cache-slots <槽位数>（手动指定每层专家缓存槽位，覆盖自动计算）
#      可选阶梯：8, 16, 24, 32, 40, 48, 64, 96, 112, 128, 160, 192, 256。
#      通常留空即可，系统会根据 RAM_BUDGET 自动向下匹配最安全的阶梯（如 8G 对应 32 槽位）。
EXPERT_CACHE_SLOTS="${EXPERT_CACHE_SLOTS:-}"


# ==============================================================================
# 3. Context Length & KV Cache / 上下文长度与 KV 缓存精度
# ==============================================================================

# [EN] --max-context <tokens> (Context window size)
#      Native support: 4096...262144 (4K to 256K tokens, default 262144).
#      - 32768 (32K, Recommended): Balances long conversation history with fast TTFT and low KV memory.
#      - 8192 (8K): Ultra low memory and latency.
#      - 131072 (128K) / 262144 (256K): Full document processing, requires more KV memory during generation.
# [CN] --max-context <tokens>（最大上下文窗口大小）
#      原生范围支持：4096 ~ 262144（4K 到 256K tokens，默认 262144 即 256K）。
#      - 32768（32K，日常黄金推荐）：兼顾长文档提问/多轮对话，且首字延迟（TTFT）与 KV 显存开销极小。
#      - 8192（8K）：极速模式，显存开销降到最低。
#      - 65536（64K）/ 131072（128K）：超长文本模式，长篇分析时使用。
MAX_CONTEXT="${MAX_CONTEXT:-32768}"

# [EN] --kv-bits <4|8|16> (KV Cache Storage Precision)
#      - 8  (Default): 8-bit quantization, optimal balance of perplexity/quality and memory.
#      - 4  : 4-bit compression, cuts KV cache memory consumption in half for extremely long prompts.
#      - 16 : Full FP16 precision, highest fidelity, doubles KV cache memory.
# [CN] --kv-bits <4|8|16>（KV 缓存压缩存储精度）
#      - 8 （默认推荐）：8-bit 量化，在长文本生成中兼顾文本精度与极低的显存开销。
#      - 4 ：4-bit 深度压缩，超长文本下可将 KV 缓存再砍一半显存占用。
#      - 16：未压缩 FP16 原生精度，显存占用最大。
KV_BITS="${KV_BITS:-8}"


# ==============================================================================
# 4. Reasoning & Thinking Mode / 思考模式与推理深度
# ==============================================================================

# [EN] --reasoning <level> (Server-wide reasoning level)
#      Allowed levels:
#      - off     : Fast mode without reasoning tokens. Pure direct response (Lowest latency).
#      - on      : Full reasoning enabled (Model produces <think>...</think> chain before answering).
#      - minimal / low / medium / high / xhigh / max : Fine-grained reasoning effort for Qwen 3.8.
#      Note: When 'off', TinyTitan automatically applies the official Qwen Instruct sampling
#            parameters (presence penalty 1.5) for highest response quality.
# [CN] --reasoning <级别>（思考模式深度开关）
#      可选级别：
#      - off     : 极速非思考模式（推荐日常使用，直接输出最终答案，首字与生成延迟最低）。
#      - on      : 开启深度思考（模型会先在 <think>...</think> 中推理，再输出正文）。
#      - minimal / low / medium / high / xhigh / max : Qwen 3.8 原生支持的思考细粒度深度控制。
#      注意：设置为 off 时，TinyTitan 会自动挂载官方发布的 Instruct 标准采样参数（如 presence_penalty 1.5），
#            输出质量完全媲美标准官方 Instruct 模型。
REASONING="${REASONING:-off}"


# ==============================================================================
# 5. Lifecycle & Multi-Turn Cache / 内存自愈、空闲释放与多轮缓存
# ==============================================================================

# [EN] --lazy-load (Deferred Loading)
#      - true  : Binds HTTP port immediately; defers loading large model weights until the first request arrives.
#      - false : Loads model weights immediately upon server launch.
# [CN] --lazy-load（懒加载模式）
#      - true （推荐）：启动脚本秒级监听端口，常驻内存仅 20MB；等第一个聊天请求到达时才加载 7GB 权重。
#      - false：执行脚本时立即挂载模型到内存中（冷启动等待 ~8-10 秒）。
LAZY_LOAD="${LAZY_LOAD:-true}"

# [EN] --idle-unload-seconds <n> (Auto Memory Release)
#      Releases 7GB+ model weights back to macOS after <n> seconds of inactivity (no requests).
#      - 0    : Disabled. Model stays resident indefinitely in memory (Default).
#      - 1800 : Automatically unloads after 30 minutes of idle time. RAM drops back to ~20MB!
#               The next incoming chat request will automatically and transparently reload the model.
# [CN] --idle-unload-seconds <秒数>（空闲超时自动释放内存，Mac 内存自愈神技）
#      - 0    ：关闭自动释放，模型一直常驻在内存中随时待命（默认）。
#      - 1800 ：闲置 30 分钟（1800秒）无对话后，自动将 7GB+ 模型卸载，内存彻底还给 macOS（降回 20MB）！
#               当下一次你在 Open WebUI 发送消息时，底层会自动无感重新加载唤醒，完全不影响使用。
#               强烈建议需要兼顾其它大型软件（如剪辑、游戏、Docker）的用户设为 1800 或 3600。
IDLE_UNLOAD_SECONDS="${IDLE_UNLOAD_SECONDS:-0}"

# [EN] --prompt-cache-mode <off|single-prefix|multi-prefix>
#      Reuses KV states for recurring prompt prefixes in multi-turn dialogues.
#      - multi-prefix (Default & Recommended): Caches multiple conversation branches; drastically speeds up TTFT.
#      - single-prefix : Single conversation prefix only.
#      - off           : Disables prompt prefix caching.
# [CN] --prompt-cache-mode（多轮对话提示词前缀复用）
#      - multi-prefix（默认推荐）：自动缓存多轮对话的历史前缀，第 2 轮及以后的对话无需从头计算历史，首字极速响应。
#      - off         ：关闭前缀缓存。
PROMPT_CACHE_MODE="${PROMPT_CACHE_MODE:-multi-prefix}"

# [EN] --prompt-cache-memory-mib <MiB> (Prefix Cache RAM Buffer)
#      RAM buffer dedicated to prefix caching (0...4096, default 256 MiB).
# [CN] --prompt-cache-memory-mib（提示词前缀缓存的内存池大小，单位 MiB，默认 256MB）
PROMPT_CACHE_MEM_MIB="${PROMPT_CACHE_MEM_MIB:-256}"

# [EN] --queue-limit <count> (Request Queue Ceiling)
#      Maximum queued requests allowed before returning HTTP 429 (Default 4).
# [CN] --queue-limit（请求队列上限，超出则返回 429 忙碌，默认 4）
QUEUE_LIMIT="${QUEUE_LIMIT:-4}"


# ==============================================================================
# Helper Functions / 辅助控制函数
# ==============================================================================

get_pid() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
            echo "$pid"
            return 0
        fi
    fi
    local port_pid
    port_pid=$(lsof -ti :"$PORT" 2>/dev/null | head -n 1)
    if [[ -n "$port_pid" ]]; then
        echo "$port_pid"
        return 0
    fi
    return 1
}

start_server() {
    local pid
    if pid=$(get_pid); then
        echo "⚠️  TinyTitanServer 已经在运行中！(PID: $pid, 端口: $PORT)"
        echo "   查看状态: $0 status"
        echo "   停止服务: $0 stop"
        return 0
    fi

    echo "🚀 正在启动 TinyTitanServer (原生 Apple M4 优化构建)..."
    echo "   • 模型目录: $(basename "$MODEL")"
    echo "   • 监听端口: $PORT"
    echo "   • 进程内存上限: $RAM_BUDGET (专家缓存约 4GB，严格不超标)"
    echo "   • 上下文上限: $MAX_CONTEXT tokens"
    echo "   • KV 缓存精度: ${KV_BITS}-bit"
    echo "   • 思考模式: $REASONING"
    echo "   • 懒加载模式: $LAZY_LOAD"
    if [[ "$IDLE_UNLOAD_SECONDS" -gt 0 ]]; then
        echo "   • 空闲内存释放: 闲置 ${IDLE_UNLOAD_SECONDS} 秒后自动卸载权重 (释放回 20MB)"
    else
        echo "   • 空闲内存释放: 保持常驻内存 (未开启自动释放)"
    fi
    echo "   • 多轮前缀缓存: $PROMPT_CACHE_MODE (${PROMPT_CACHE_MEM_MIB} MiB)"

    # 对齐模型安装收据 (Receipt) 的物理路径绑定：
    # TinyTitanServer 严格校验 --model 传入的路径与 verified-install.json 中的 modelDirectoryPath 完全一致。
    # 若模型路径是符号链接（如 ~/TinyTitan/...），自动对齐至收据签发时的实际物理路径，彻底杜绝 receipt mismatch 异常。
    if [[ -f "$MODEL/verified-install.json" ]]; then
        local receipt_dir
        receipt_dir=$(grep -m 1 '"modelDirectoryPath"' "$MODEL/verified-install.json" 2>/dev/null | awk -F '"' '{print $4}')
        if [[ -n "$receipt_dir" && -d "$receipt_dir" ]]; then
            local model_real receipt_real
            model_real=$(cd "$MODEL" 2>/dev/null && pwd -P)
            receipt_real=$(cd "$receipt_dir" 2>/dev/null && pwd -P)
            if [[ "$model_real" == "$receipt_real" ]]; then
                MODEL="$receipt_dir"
            fi
        fi
    fi

    # 动态组装命令行参数 / Assemble CLI Arguments
    local cmd=(
        "$BIN"
        --model "$MODEL"
        --port "$PORT"
        --ram-budget "$RAM_BUDGET"
        --max-context "$MAX_CONTEXT"
        --kv-bits "$KV_BITS"
        --reasoning "$REASONING"
        --prompt-cache-mode "$PROMPT_CACHE_MODE"
        --prompt-cache-memory-mib "$PROMPT_CACHE_MEM_MIB"
        --queue-limit "$QUEUE_LIMIT"
    )

    if [[ "$LAZY_LOAD" == "true" ]]; then
        cmd+=(--lazy-load)
    fi

    if [[ "$IDLE_UNLOAD_SECONDS" -gt 0 ]]; then
        cmd+=(--idle-unload-seconds "$IDLE_UNLOAD_SECONDS")
    fi

    if [[ -n "$EXPERT_CACHE_SLOTS" ]]; then
        cmd+=(--expert-cache-slots "$EXPERT_CACHE_SLOTS")
    fi

    nohup "${cmd[@]}" > "$LOG_FILE" 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$PID_FILE"

    echo -n "⏳ 等待服务端口就绪..."
    for (( i=0; i<15; i++ )); do
        sleep 0.5
        if curl -s "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"'; then
            echo " 完成！"
            echo "✅ TinyTitanServer 启动成功！"
            echo "   • PID: $new_pid"
            echo "   • 访问地址: http://127.0.0.1:$PORT/v1"
            echo "   • 日志文件: $LOG_FILE"
            echo "   • 实时日志: $0 logs"
            return 0
        fi
        echo -n "."
    done

    echo
    if ps -p "$new_pid" >/dev/null 2>&1; then
        echo "⚠️  进程已启动但健康检查暂未响应，请查看日志: $0 logs"
    else
        echo "❌ 启动失败，请检查日志:"
        tail -n 20 "$LOG_FILE"
        rm -f "$PID_FILE"
        return 1
    fi
}

stop_server() {
    local pid
    if ! pid=$(get_pid); then
        echo "ℹ️  TinyTitanServer 当前没有在运行。"
        rm -f "$PID_FILE"
        return 0
    fi

    echo "🛑 正在停止 TinyTitanServer (PID: $pid)..."
    kill "$pid" 2>/dev/null

    for (( i=0; i<10; i++ )); do
        sleep 0.5
        if ! ps -p "$pid" >/dev/null 2>&1; then
            echo "✅ 服务已成功停止。"
            rm -f "$PID_FILE"
            return 0
        fi
    done

    echo "⚠️  服务未在 5 秒内退出，正在强制结束..."
    kill -9 "$pid" 2>/dev/null
    rm -f "$PID_FILE"
    echo "✅ 服务已强制停止。"
}

show_status() {
    local pid
    if pid=$(get_pid); then
        echo "✅ TinyTitanServer 正在运行中"
        echo "   • PID: $pid"
        echo "   • 端口: $PORT"
        echo "   • 内存使用: $(ps -o rss= -p "$pid" 2>/dev/null | awk '{printf "%.2f GB\n", $1/1024/1024}')"
        echo "   • 运行时间: $(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')"
        echo "   • 健康状态: $(curl -s "http://127.0.0.1:$PORT/health" 2>/dev/null || echo "无法连接")"
    else
        echo "⚪ TinyTitanServer 当前已停止"
    fi
}

show_logs() {
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "⚠️  日志文件不存在: $LOG_FILE"
        return 1
    fi
    echo "📋 正在查看实时日志 (按 Ctrl + C 退出)..."
    echo "--------------------------------------------------------"
    tail -n 30 -f "$LOG_FILE"
}

# ==============================================================================
# Entrypoint / 命令入口
# ==============================================================================
case "${1:-}" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        stop_server
        sleep 1
        start_server
        ;;
    status)
        show_status
        ;;
    logs|log)
        show_logs
        ;;
    *)
        echo "================================================================="
        echo "TinyTitan 服务管理脚本 (支持直接传参 / 环境变量覆盖)"
        echo "================================================================="
        echo "基础命令:"
        echo "  $0 start   - 一键后台启动服务"
        echo "  $0 stop    - 一键停止服务"
        echo "  $0 restart - 重启服务"
        echo "  $0 status  - 查看运行状态与内存占用"
        echo "  $0 logs    - 跟踪实时运行日志 (Ctrl + C 退出)"
        echo
        echo "快捷环境参数启动示例 (无需改脚本即可临时调试):"
        echo "  REASONING=on $0 restart               # 临时开启思考模式重启"
        echo "  IDLE_UNLOAD_SECONDS=1800 $0 restart    # 开启30分钟闲置自动释放内存重启"
        echo "  RAM_BUDGET=6G $0 restart              # 临时压缩到 6G 内存预算"
        echo "  PORT=8080 $0 restart                  # 临时更换端口"
        echo "================================================================="
        show_status
        exit 1
        ;;
esac
