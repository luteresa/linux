#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

int main(void)
{
	char *p;

	p = mmap(NULL,
		 1024 * 1024,
		 PROT_READ | PROT_WRITE,
		 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);

	printf("mmap done\n");

	//getchar();
	sleep(1);

	p[0] = 'A';

	printf("after touch\n");

	//getchar();
	sleep(1);

	munmap(p, 1024 * 1024);

	return 0;
}
