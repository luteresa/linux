#!/bin/sh
set -e

TR=/sys/kernel/debug/tracing
MOD=vmalloc_demo.ko

cleanup()
{
    echo 0 > $TR/tracing_on || true
}

trap cleanup EXIT

echo "[+] reset tracing"

echo 0 > $TR/tracing_on

echo nop > $TR/current_tracer
echo function_graph > $TR/current_tracer

echo > $TR/trace
echo > $TR/set_graph_function
echo > $TR/set_ftrace_pid

#
# 只放确认存在的函数
#
for f in \
    __vmalloc_node_range \
    vmap_pages_range
do
        grep -w "$f" $TR/available_filter_functions >/dev/null && \
	        echo $f >> $TR/set_graph_function
done

insmod ./$MOD &
PID=$!

echo "[+] tracing pid=$PID"

echo $PID > $TR/set_ftrace_pid

echo 1 > $TR/tracing_on

wait $PID || true

echo 0 > $TR/tracing_on

cat $TR/trace
