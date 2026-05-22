#!//bin/sh
set -e

#!/bin/sh
set -e

TR=/sys/kernel/debug/tracing

MOD=kmalloc_demo.ko

echo "[+] reset tracing"

echo 0 > $TR/tracing_on

echo nop > $TR/current_tracer
echo function_graph > $TR/current_tracer

echo > $TR/trace
echo > $TR/set_graph_function
echo > $TR/set_ftrace_pid

#
# 只跟踪关键函数
#
echo __kmalloc > $TR/set_graph_function
#echo __alloc_pages > $TR/set_graph_function

#
# 后台执行 insmod
#
echo "[+] insmod..."

insmod ./$MOD &
PID=$!

echo "[+] insmod pid = $PID"

#
# 只跟踪这个 PID
#
echo $PID > $TR/set_ftrace_pid

#
# 开启 tracing
#
echo 1 > $TR/tracing_on

#
# 等待 insmod 结束
#
wait $PID || true

#
# 关闭 tracing
#
echo 0 > $TR/tracing_on

echo "[+] trace result:"
echo

cat $TR/trace
