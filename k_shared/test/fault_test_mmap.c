/*
 * fault_test_mmap.c —— 触发 do_anonymous_page 的标准复现程序
 *
 * 设计要点：
 *  1. mmap(MAP_PRIVATE|MAP_ANONYMOUS) 拿到的 VMA 在用户态从未被任何代码
 *     碰过，PTE 全 0。后续的第一次访问就是真正的 first-touch。
 *  2. raise(SIGSTOP) 让 trace 脚本在 fault 发生前挂上 ftrace。
 *  3. SIGCONT 之后的 p[0] = 1 是写访问 → 进 do_anonymous_page 的写分支
 *     (mm/memory.c §5b) → alloc_zeroed_user_highpage_movable → __alloc_pages。
 *
 *  - 不能用 malloc：见 fault_test.c 注释，glibc 会预先写 chunk header。
 *  - 不能预先读 p[0]：读会让 PTE 指向全局零页（do_anonymous_page §5a），
 *    后续的写就变成 do_wp_page (COW) 而非 first-touch。
 *  - 不能 mlock/madvise(WILLNEED)：那些会通过 populate_vma_page_range
 *    在用户态写之前替我们装好 PTE，trace 时机就错位了。
 *
 * 编译：
 *   gcc -O0 -static fault_test_mmap.c -o fault_test_mmap
 *
 *  -static 让 ELF loader 的 .so 懒加载缺页量降到最低，trace 里 file-backed
 *  fault 的噪声更少。即便如此，静态二进制自身的 .text 仍可能有未触及页，
 *  trace 里第二个 do_mem_abort 通常是它（见 v2 §15.2）。
 *
 * 详细对照实测见
 *   k_shared/buddy_demo/anon_fault_to_page_alloc_v2.md  §15
 */
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <sys/mman.h>

int main(void)
{
	char *p = mmap(NULL, 4096,
		       PROT_READ | PROT_WRITE,
		       MAP_PRIVATE | MAP_ANONYMOUS,
		       -1, 0);
	if (p == MAP_FAILED) {
		perror("mmap");
		return 1;
	}

	/* 让 trace 脚本在缺页前挂上 ftrace */
	raise(SIGSTOP);

	/* SIGCONT 后，第一次访问 = 写 → do_anonymous_page (5b) */
	p[0] = 1;

	return 0;
}
