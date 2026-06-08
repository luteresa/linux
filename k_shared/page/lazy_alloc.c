// lazy_alloc.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

#define PAGE_SIZE 4096

/* 从 /proc/self/pagemap 读 PFN */
uint64_t read_pagemap(pid_t pid, void *vaddr)
{
	char path[64];
	snprintf(path, sizeof(path), "/proc/%d/pagemap", pid);
	int fd = open(path, O_RDONLY);
	if (fd < 0) {
		perror("open");
		return 0;
	}

	uint64_t offset =
	    ((uint64_t) vaddr / PAGE_SIZE) * sizeof(uint64_t);
	uint64_t entry = 0;
	pread(fd, &entry, sizeof(entry), offset);
	close(fd);
	return entry;
}

void show_pagemap(pid_t pid, void *p, const char *label)
{
	uint64_t e = read_pagemap(pid, p);
	int present = (e >> 63) & 1;
	uint64_t pfn = e & ((1UL << 55) - 1);
	printf("[%s] present=%d  pfn=0x%lx  raw=0x%016lx\n",
	       label, present, pfn, e);
}

int main(void)
{
	char *p = mmap(NULL, PAGE_SIZE, PROT_READ | PROT_WRITE,
		       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (p == MAP_FAILED) {
		perror("mmap");
		return 1;
	}

	pid_t me = getpid();

	/* data pre Zero page */
	show_pagemap(me, p, "write before");

	p[0] = 'X';		/* 第一次写 → 触发缺页 */

	/* 现在应有物理页 */
	show_pagemap(me, p, "write after");

	munmap(p, PAGE_SIZE);
	return 0;
}
