#!/bin/sh
set -e

set -e

TR=/sys/kernel/debug/tracing
APP=./mmap_demo

cleanup()
{
	    echo 0 > $TR/tracing_on || true
    }

    trap cleanup EXIT

    echo "[+] reset tracing"

    #
    # reset
    #
    echo 0 > $TR/tracing_on

    echo nop > $TR/current_tracer
    echo function_graph > $TR/current_tracer

    echo > $TR/trace
    echo > $TR/set_graph_function
    echo > $TR/set_ftrace_pid

    #
    # 只跟踪 page fault 关键路径
    #
    cat << EOF > $TR/set_graph_function
handle_mm_fault
do_anonymous_page
__alloc_pages
EOF

#
# 后台运行 mmap_demo
#
echo "[+] run mmap_demo"

$APP &
PID=$!

echo "[+] mmap_demo pid = $PID"

#
# 只跟踪 mmap_demo
#
echo $PID > $TR/set_ftrace_pid
echo function-fork >$TR/trace_options

#
# 开 tracing
#
echo 1 > $TR/tracing_on

#
# 等待程序结束
#
wait $PID || true

#
# 关闭 tracing
#
echo 0 > $TR/tracing_on

echo
echo "[+] trace result:"
echo

cat $TR/trace
