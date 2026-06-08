#!/bin/sh
# trace_buddy_stack.sh
#
# 只做 nop tracer + kmem tracepoint + stacktrace。
# 不启用 function_graph，避免和 event tracepoint 混用导致 trace 为空或输出混乱。
# 用途：抓 order>=2 的 mm_page_alloc/mm_page_free，并打印调用栈。

set +e

KO=${1:-./buddy_demo.ko}
TRACE=${TRACE:-/sys/kernel/tracing}

sep()
{
    echo ""
    echo "---------- $1 ----------"
}

has_trace_files()
{
    [ -d "$1" ] && [ -e "$1/tracing_on" ] && [ -e "$1/trace" ]
}

prepare_tracefs()
{
    if has_trace_files "$TRACE"; then
        return 0
    fi

    mkdir -p /sys/kernel/tracing 2>/dev/null
    mount -t tracefs nodev /sys/kernel/tracing 2>/dev/null
    TRACE=/sys/kernel/tracing
    if has_trace_files "$TRACE"; then
        return 0
    fi

    mkdir -p /sys/kernel/debug 2>/dev/null
    mount -t debugfs nodev /sys/kernel/debug 2>/dev/null
    TRACE=/sys/kernel/debug/tracing
    if has_trace_files "$TRACE"; then
        return 0
    fi

    return 1
}

write_if_exists()
{
    file="$1"
    value="$2"
    [ -e "$file" ] && echo "$value" > "$file" 2>/dev/null
}

echo ""
echo "========================================"
echo "  Buddy Allocator Demo: kmem stacktrace"
echo "========================================"

sep "[0] 检查模块"
if [ ! -f "$KO" ]; then
    echo "!! module not found: $KO"
    echo "usage: sh ./trace_buddy_stack.sh [buddy_demo.ko]"
    echo "请先编译或拷贝 buddy_demo.ko 到当前目录。"
    exit 1
fi

echo "module: $KO"

sep "[1] 准备 tracefs"
if ! prepare_tracefs; then
    echo "!! tracefs/debugfs unavailable"
    echo "请检查内核配置和挂载："
    echo "  zcat /proc/config.gz | grep -E 'CONFIG_TRACING|CONFIG_FTRACE|CONFIG_TRACEPOINTS|CONFIG_KMEM_EVENTS'"
    echo "  mount -t tracefs nodev /sys/kernel/tracing"
    exit 1
fi

echo "TRACE=$TRACE"

if [ ! -e "$TRACE/events/kmem/mm_page_alloc/enable" ] || [ ! -e "$TRACE/events/kmem/mm_page_free/enable" ]; then
    echo "!! kmem page alloc/free events unavailable"
    echo "请检查 CONFIG_KMEM_EVENTS 是否开启。"
    exit 1
fi

sep "[2] 清理旧模块"
rmmod buddy_demo 2>/dev/null || true

sep "[3] 配置 tracepoint + stacktrace"
echo 0 > "$TRACE/tracing_on" 2>/dev/null
echo nop > "$TRACE/current_tracer" 2>/dev/null
echo > "$TRACE/trace" 2>/dev/null
echo 0 > "$TRACE/events/enable" 2>/dev/null

# 清理旧 filter。
echo 0 > "$TRACE/events/kmem/mm_page_alloc/filter" 2>/dev/null
echo 0 > "$TRACE/events/kmem/mm_page_free/filter" 2>/dev/null

# 只抓高阶页，避免 order=0 噪声。
echo 'order >= 2' > "$TRACE/events/kmem/mm_page_alloc/filter" 2>/dev/null
echo 'order >= 2' > "$TRACE/events/kmem/mm_page_free/filter" 2>/dev/null

echo "mm_page_alloc filter:"
cat "$TRACE/events/kmem/mm_page_alloc/filter" 2>/dev/null
echo "mm_page_free filter:"
cat "$TRACE/events/kmem/mm_page_free/filter" 2>/dev/null

echo 1 > "$TRACE/events/kmem/mm_page_alloc/enable" 2>/dev/null
echo 1 > "$TRACE/events/kmem/mm_page_free/enable" 2>/dev/null

# 关键：为 event 打调用栈。
echo 1 > "$TRACE/options/stacktrace" 2>/dev/null

sep "[4] 开始 trace + insmod"
echo 1 > "$TRACE/tracing_on" 2>/dev/null
insmod "$KO"
INS_RET=$?
echo 0 > "$TRACE/tracing_on" 2>/dev/null
if [ $INS_RET -ne 0 ]; then
    echo "!! insmod failed: $INS_RET"
fi

sep "[5] 保存并展示 trace"
cat "$TRACE/trace" > /tmp/buddy_stack.trace

if [ -s /tmp/buddy_stack.trace ]; then
    echo "trace saved: /tmp/buddy_stack.trace"
    echo ""
    grep -A35 -E 'mm_page_alloc|mm_page_free' /tmp/buddy_stack.trace | head -320
else
    echo "!! trace is empty"
fi

sep "[6] dmesg: Buddy Demo 相关输出"
dmesg | tail -180

sep "[7] 清理"
rmmod buddy_demo 2>/dev/null || true
echo 0 > "$TRACE/tracing_on" 2>/dev/null
echo 0 > "$TRACE/options/stacktrace" 2>/dev/null
echo 0 > "$TRACE/events/enable" 2>/dev/null
echo nop > "$TRACE/current_tracer" 2>/dev/null

echo ""
echo "========================================"
echo "  Done"
echo "  trace: /tmp/buddy_stack.trace"
echo "========================================"
