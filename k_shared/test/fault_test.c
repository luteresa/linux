/*
 * fault_test.c —— 历史上想用 malloc+首写 触发匿名页 fault 的尝试
 *
 * 重要：实测在 myQEMU(arm64-6.1) 上这条路径 **看不到** do_anonymous_page。
 * 原因：glibc malloc 在分配 chunk 时会写 chunk header（boundary tag /
 * arena 元数据），所以 raise(SIGSTOP) 之前那一页的 PTE 已经装好了，
 * SIGCONT 后的 p[0] = 1 直接命中，根本不进 do_page_fault。
 *
 * 想复现完整的 do_anonymous_page → __alloc_pages 调用链请用同目录的
 * fault_test_mmap.c，它用 mmap(MAP_PRIVATE|MAP_ANONYMOUS) 拿到一段在
 * 用户态从未被任何代码碰过的内存，第一次写就是 first-touch。
 *
 * 详细对照实测见
 *   k_shared/buddy_demo/anon_fault_to_page_alloc_v2.md  §15
 */
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>

int main()
{
	char *p = malloc(4096);

	raise(SIGSTOP);

	p[0] = 1;	/* 实测命中 PTE，无 fault */

	return 0;
}
