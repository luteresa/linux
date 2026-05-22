#!//bin/sh

if [[ $# -lt 2 ]]; then
    echo "用法: sudo $0 <ko_path> <module_name> [output_file]"
    echo "例子: sudo $0 ./ioremap_demo.ko ioremap_demo /tmp/ioremap_trace.txt"
    exit 1
fi

KO_PATH="$1"
MODULE_NAME="$2"
OUT_FILE="${3:-/tmp/${MODULE_NAME}_ftrace.txt}"

TRACE_DIR="/sys/kernel/debug/tracing"

if [[ ! -d "$TRACE_DIR" ]]; then
    echo "错误: $TRACE_DIR 不存在，请先挂载 debugfs/tracefs"
    echo "可尝试:"
    echo "  sudo mount -t debugfs none /sys/kernel/debug"
    exit 1
fi

if [[ ! -f "$KO_PATH" ]]; then
    echo "错误: 模块文件不存在: $KO_PATH"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "错误: 请用 root 运行"
    exit 1
fi

AVAILABLE_FUNCS="$TRACE_DIR/available_filter_functions"

add_func_if_exists() {
    local fn="$1"
    if grep -qw "$fn" "$AVAILABLE_FUNCS"; then
        echo "$fn" >> "$TRACE_DIR/set_graph_function"
        echo "  [+] 跟踪函数: $fn"
    else
        echo "  [-] 函数不存在或不可跟踪: $fn"
    fi
}

cleanup() {
    set +e
    echo 0 > "$TRACE_DIR/tracing_on"
    echo nop > "$TRACE_DIR/current_tracer"
    : > "$TRACE_DIR/set_graph_function"
}
trap cleanup EXIT

echo "[1/6] 清理旧状态"
echo 0 > "$TRACE_DIR/tracing_on"
echo nop > "$TRACE_DIR/current_tracer"
: > "$TRACE_DIR/set_graph_function"
: > "$TRACE_DIR/trace"

echo "[2/6] 设置 function_graph"
echo function_graph > "$TRACE_DIR/current_tracer"

echo "[3/6] 添加 ioremap 相关函数过滤"
#add_func_if_exists "ioremap_demo_init"
add_func_if_exists "ioremap_prot"
add_func_if_exists "__ioremap_caller"
#add_func_if_exists "__ioremap"
add_func_if_exists "get_vm_area_caller"
#add_func_if_exists "__get_vm_area_caller"
add_func_if_exists "alloc_vmap_area"
add_func_if_exists "ioremap_page_range"
#add_func_if_exists "__apply_to_page_range"
#add_func_if_exists "iounmap"

echo "[4/6] 开始跟踪"
echo 1 > "$TRACE_DIR/tracing_on"

echo "[5/6] 执行 insmod"
insmod "$KO_PATH"

sleep 1

echo "[6/6] 停止跟踪并导出日志"
echo 0 > "$TRACE_DIR/tracing_on"
cat "$TRACE_DIR/trace" > "$OUT_FILE"

echo
echo "trace 已保存到: $OUT_FILE"
echo
echo "你可以这样看关键调用链:"
echo "  grep -E 'ioremap|vm_area|vmap|iounmap' '$OUT_FILE'"
echo
echo "如果要卸载模块:"
echo "  rmmod $MODULE_NAME"
