#!/bin/sh

TRACE=/sys/kernel/debug/tracing
OUT=/tmp/cow_trace.txt
TEST=./cow_test

echo 0 > $TRACE/tracing_on

echo nop > $TRACE/current_tracer
echo > $TRACE/set_graph_function
echo > $TRACE/set_ftrace_pid
echo > $TRACE/trace

echo function_graph > $TRACE/current_tracer

cat <<EOF > $TRACE/set_graph_function
do_mem_abort
do_page_fault
handle_mm_fault
handle_pte_fault
do_wp_page
wp_page_copy
copy_user_highpage
EOF

$TEST &

PID=$!

sleep 1

CHILD=$(pgrep -P $PID)

while true
do
    STATE=$(cat /proc/$CHILD/status | grep State)

    echo "$STATE" | grep -q "T (stopped)"

    if [ $? -eq 0 ]; then
        break
    fi

sleep 0.1
done

echo $CHILD > $TRACE/set_ftrace_pid

echo 1 > $TRACE/tracing_on

kill -CONT $CHILD

wait $PID

echo 0 > $TRACE/tracing_on

cat $TRACE/trace > $OUT

grep -A30 "do_mem_abort" $OUT
