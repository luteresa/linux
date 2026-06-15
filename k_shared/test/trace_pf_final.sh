#!/bin/sh
# 匿名页 / file-backed 页 缺页异常 → 物理页分配：最终版 trace 脚本
#
# 用法：
#   sh ./trace_pf_final.sh                              # 默认跑 ./fault_test (malloc 版)
#   TEST=./fault_test_mmap sh ./trace_pf_final.sh       # 跑 mmap 版（推荐，能抓到 do_anonymous_page）
#
# 同时启用三种观测手段：
#   1. function_graph  ── 可见调用脊柱（取 do_mem_abort 为根）
#   2. tracepoint      ── 区分 PCP 命中 vs 真正下到 buddy
#   3. kprobe          ── 给 kallsyms 里仍存在但被 ftrace 内联消去的符号补抓 hit
#
# 抓得到 do_anonymous_page 需要内核侧两处改动（已在本仓库做了）：
#   * mm/Makefile 追加：
#       CFLAGS_memory.o     += -fno-inline-small-functions -fno-inline-functions-called-once
#       CFLAGS_page_alloc.o += -fno-inline-small-functions -fno-inline-functions-called-once
#   * mm/memory.c 给 do_anonymous_page 加 noinline + noclone：
#       static noinline __attribute__((__noclone__)) vm_fault_t do_anonymous_page(...)
#     单独 noinline 不够 —— GCC 的 IPA-CP clone 仍会把它复制进 handle_pte_fault。
#
# 设计原则：
# - 写 ftrace 控制文件前先 grep available_filter_functions / kallsyms 校验
# - 任何一项不可用就跳过、不影响其余
# - 末尾按时间顺序打印：graph 树 + kprobe hits + 分配类 tracepoints
#
# 详情见 k_shared/buddy_demo/anon_fault_to_page_alloc_v2.md §15


TRACE=/sys/kernel/debug/tracing
OUT=/tmp/pagefault_trace.txt
TEST=${TEST:-./fault_test}        # 可用环境变量切换：TEST=./fault_test_mmap sh ./trace_pf_final.sh

# ---------- 工具函数 ----------

write_each_filter() {
    file=$1; shift
    : > "$file"
    for name in "$@"; do
        if grep -q "^${name}\$" $TRACE/available_filter_functions; then
            echo "$name" >> "$file" 2>/dev/null \
                && echo "  [+] graph: $name" \
                || echo "  [!] reject (write failed): $name"
        else
            echo "  [-] skip (inlined / no symbol): $name"
        fi
    done
}

add_kprobe_if_present() {
    name=$1
    # /proc/kallsyms 第三列符号；用空格匹配避免子串误命中
    if grep -qE " ${name}\$" /proc/kallsyms; then
        if echo "p:${name}_hit $name" >> $TRACE/kprobe_events 2>/dev/null; then
            echo "  [+] kprobe: $name"
        else
            echo "  [!] kprobe failed: $name (notrace?)"
        fi
    else
        echo "  [-] skip kprobe (not in kallsyms): $name"
    fi
}

enable_tracepoint_if_present() {
    path=$1
    if [ -f "$TRACE/events/$path/enable" ]; then
        echo 1 > "$TRACE/events/$path/enable"
        echo "  [+] tracepoint: $path"
    else
        echo "  [-] skip tracepoint: $path (not present)"
    fi
}

# ---------- 1. 清场 ----------

echo "[+] stop tracing & cleanup"
echo 0 > $TRACE/tracing_on
echo nop > $TRACE/current_tracer
: > $TRACE/set_graph_function
: > $TRACE/set_ftrace_filter
: > $TRACE/set_ftrace_pid
: > $TRACE/trace
[ -f $TRACE/events/kprobes/enable ] && echo 0 > $TRACE/events/kprobes/enable
: > $TRACE/kprobe_events 2>/dev/null

# 关掉先前可能开过的 tracepoint（按需）
for ev in kmem/mm_page_alloc kmem/mm_page_alloc_zone_locked \
          kmem/mm_page_free exceptions/page_fault_user; do
    [ -f $TRACE/events/$ev/enable ] && echo 0 > $TRACE/events/$ev/enable
done

# ---------- 2. function_graph ----------

echo "[+] setup function_graph"
echo function_graph > $TRACE/current_tracer

# 让 graph 在调用脊柱上展开
echo "[+] set_graph_function:"
write_each_filter $TRACE/set_graph_function \
    do_mem_abort

# 过滤器（只显示这些函数 & 它们的子调用），避免被 schedule/spinlock 之类淹没
echo "[+] set_ftrace_filter:"
write_each_filter $TRACE/set_ftrace_filter \
    do_mem_abort \
    do_translation_fault \
    do_page_fault \
    __do_page_fault \
    handle_mm_fault \
    __handle_mm_fault \
    handle_pte_fault \
    do_anonymous_page \
    do_wp_page \
    wp_page_copy \
    __wp_page_copy_user \
    do_fault \
    do_read_fault \
    do_cow_fault \
    do_shared_fault \
    __do_fault \
    filemap_fault \
    do_swap_page \
    pte_alloc \
    __pte_alloc \
    pte_alloc_one \
    anon_vma_prepare \
    alloc_page_vma \
    vma_alloc_folio \
    __alloc_pages \
    get_page_from_freelist \
    rmqueue \
    rmqueue_pcplist \
    rmqueue_bulk \
    __rmqueue \
    __rmqueue_smallest \
    expand \
    prep_new_page \
    clear_user_highpage \
    clear_page \
    page_add_new_anon_rmap \
    lru_cache_add_inactive_or_unevictable \
    set_pte_at \
    mm_account_fault \
    free_unref_page \
    free_unref_page_list \
    free_unref_page_commit \
    free_pcppages_bulk \
    drain_local_pages \
    lru_add_drain \
    lru_add_drain_cpu \
    __page_cache_release \
    release_pages

# ---------- 3. tracepoint：PCP vs buddy ----------

echo "[+] enable tracepoints:"
enable_tracepoint_if_present kmem/mm_page_alloc
enable_tracepoint_if_present kmem/mm_page_alloc_zone_locked
enable_tracepoint_if_present kmem/mm_page_free
enable_tracepoint_if_present exceptions/page_fault_user

# ---------- 4. kprobe：补抓被内联的符号 ----------

echo "[+] kprobe events:"
for sym in \
    __do_page_fault \
    handle_pte_fault \
    do_anonymous_page \
    do_wp_page \
    wp_page_copy \
    do_fault \
    do_read_fault \
    do_cow_fault \
    __do_fault \
    filemap_fault \
    do_swap_page \
    __pte_alloc \
    pte_alloc_one \
    rmqueue \
    rmqueue_pcplist \
    __rmqueue_smallest \
    expand \
    prep_new_page \
    free_unref_page \
    free_unref_page_list \
    free_pcppages_bulk \
    lru_add_drain \
    __page_cache_release \
    release_pages \
    mm_account_fault
do
    add_kprobe_if_present "$sym"
done

if [ -f $TRACE/events/kprobes/enable ]; then
    echo 1 > $TRACE/events/kprobes/enable
    echo "  [+] kprobes group enabled"
else
    echo "  [-] no kprobes created (none of the symbols exist)"
fi

# ---------- 5. 启动测试程序，等它在 SIGSTOP 上暂停 ----------

if [ ! -x "$TEST" ]; then
    echo "[X] $TEST not found or not executable. Run: gcc -O0 fault_test.c -o fault_test"
    exit 1
fi

echo "[+] launching $TEST"
$TEST &
PID=$!
echo "[+] pid=$PID"

echo "[+] wait process to enter T (stopped)"
while true; do
    grep -q "T (stopped)" /proc/$PID/status 2>/dev/null && break
    if ! kill -0 $PID 2>/dev/null; then
        echo "[X] process exited before SIGSTOP, abort"
        exit 1
    fi
    sleep 0.05
done
echo "[+] process stopped, ready to trace"

# pid 过滤只作用于 function_graph，避免 tracepoint 在 fault 上下文被过滤掉
echo $PID > $TRACE/set_ftrace_pid
# 注意：不再设置 set_event_pid——经验是在 fault 路径上会把 mm_page_alloc 过滤掉

# ---------- 6. 开 trace、放进程跑 ----------

echo "[+] start tracing"
echo 1 > $TRACE/tracing_on

echo "[+] SIGCONT $PID"
kill -CONT $PID
wait $PID

echo "[+] stop tracing"
echo 0 > $TRACE/tracing_on
[ -f $TRACE/events/kprobes/enable ] && echo 0 > $TRACE/events/kprobes/enable

# ---------- 7. 输出 ----------

cat $TRACE/trace > $OUT

cat <<EOF

==============================================================
[+] full trace saved: $OUT
==============================================================

[+] === function_graph view (pid=$PID, root=do_mem_abort) ===
EOF
grep -A80 "do_mem_abort() {" $OUT | head -120

cat <<EOF

[+] === kprobe hits in time order ===
EOF
grep "_hit:" $OUT | head -40

cat <<EOF

[+] === page allocator tracepoints ===
EOF
grep -E "mm_page_alloc:|mm_page_alloc_zone_locked:|mm_page_free:|mm_page_alloc_extfrag:" $OUT | head -60

cat <<EOF

[+] === interpretation ===
   * 路径判定（看 graph 树根节点之下的第一层）：
     - do_anonymous_page  → 私有匿名 VMA 第一次写 (fault_test_mmap)
     - do_wp_page         → 已有零页/共享页的写 → COW
     - do_fault → filemap_fault → file-backed VMA 缺页（ELF .text、libc 等）
     - do_swap_page       → 页在 swap 上

   * alloc 端：
     - mm_page_alloc 出现而无 mm_page_alloc_zone_locked → order=0 命中 PCP
     - 同时出现两者 → 真正下到 buddy free_list（rmqueue_bulk refill）
     - gfp 含 __GFP_ZERO → alloc_zeroed_user_highpage_movable 路径（匿名页）
     - gfp 仅 __GFP_COMP → __folio_alloc 路径（file-backed / 一般 folio 分配）

   * VM_FAULT_RETRY 是 file-backed 特有：filemap_fault 拿 folio_lock 失败
     会丢 mmap_lock 返回 retry，体现在 graph 树里"一对 do_mem_abort 内出现
     两次 handle_mm_fault、第二次没 __alloc_pages"。匿名 fault 通常一次走完。

   * filemap_fault 内部出现连续的
       __page_cache_release → free_unref_page → mm_page_free
     不是异常，是 readahead 把读多的 page cache 让出去。

   * 很多 static 函数没出现在 graph 里 → 已被编译器内联，符号不存在；
     重编内核时 mm/Makefile 已加：
       -fno-inline-small-functions -fno-inline-functions-called-once
     对 do_anonymous_page 这种"被调用一次又被 IPA-CP clone"的，
     需要单独 noinline + noclone（见脚本头部说明）。
EOF
