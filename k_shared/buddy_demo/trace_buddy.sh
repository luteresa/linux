#!/bin/sh
# trace_buddy.sh
#
# 只做 buddyinfo + dmesg，不启用 ftrace。
# 用途：观察模块内部 T0/T1/T2/T3 快照，确认 buddy expand/merge 的 order 计数变化。

set +e

KO=${1:-./buddy_demo.ko}

sep()
{
    echo ""
    echo "---------- $1 ----------"
}

echo ""
echo "========================================"
echo "  Buddy Allocator Demo: buddyinfo + dmesg"
echo "========================================"

sep "[0] 检查模块"
if [ ! -f "$KO" ]; then
    echo "!! module not found: $KO"
    echo "usage: sh ./trace_buddy.sh [buddy_demo.ko]"
    echo "请先编译或拷贝 buddy_demo.ko 到当前目录。"
    exit 1
fi

echo "module: $KO"

sep "[1] 清理旧模块"
rmmod buddy_demo 2>/dev/null || true

sep "[2] buddyinfo before"
cat /proc/buddyinfo | tee /tmp/buddy.before

sep "[3] insmod buddy_demo.ko"
insmod "$KO"
INS_RET=$?
if [ $INS_RET -ne 0 ]; then
    echo "!! insmod failed: $INS_RET"
fi

sep "[4] buddyinfo after"
cat /proc/buddyinfo | tee /tmp/buddy.after

sep "[5] buddyinfo diff"
diff -u /tmp/buddy.before /tmp/buddy.after 2>&1 || true

sep "[6] dmesg: Buddy Demo 相关输出"
# busybox grep 不一定支持复杂上下文，这里直接 tail 足够。
dmesg | tail -220

sep "[7] 清理模块"
rmmod buddy_demo 2>/dev/null || true

echo ""
echo "========================================"
echo "  Done"
echo "  before: /tmp/buddy.before"
echo "  after:  /tmp/buddy.after"
echo "========================================"
