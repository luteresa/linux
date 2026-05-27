#!/bin/sh

TRACE=/sys/kernel/debug/tracing
OUT=/tmp/pagefault_trace.txt
TEST=./fault_test

echo "[+] stop tracing"

echo 0 > $TRACE/tracing_on

echo "[+] cleanup"

echo nop > $TRACE/current_tracer
echo > $TRACE/set_graph_function
echo > $TRACE/set_ftrace_pid
echo > $TRACE/trace

echo "[+] setup function_graph"

echo function_graph > $TRACE/current_tracer

cat <<EOF > $TRACE/set_graph_function
do_mem_abort
do_page_fault
handle_mm_fault
__handle_mm_fault
handle_pte_fault
EOF

echo "[+] start test"

$TEST &

PID=$!

echo "[+] pid=$PID"

echo "[+] wait process stop"

while true
do
    STATE=$(cat /proc/$PID/status | grep State)

    echo "$STATE" | grep -q "T (stopped)"

    if [ $? -eq 0 ]; then
        break
    fi

    sleep 0.1
done

echo "[+] process stopped before fault"

echo $PID > $TRACE/set_ftrace_pid

echo "[+] start tracing"

echo 1 > $TRACE/tracing_on

echo "[+] continue process"

kill -CONT $PID

wait $PID

echo "[+] stop tracing"

echo 0 > $TRACE/tracing_on

cat $TRACE/trace > $OUT

echo
echo "[+] trace saved:"
echo "    $OUT"

echo
echo "[+] key fault path:"
echo

grep -A20 "do_mem_abort" $OUT
