#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(void)
{
	char *p;

	printf("before brk = %p\n", sbrk(0));

	p = malloc(1024 * 1024);

	printf("malloc ptr = %p\n", p);

	printf("after malloc brk = %p\n", sbrk(0));

	getchar();

	p[0] = 'A';

	printf("after touch\n");

	getchar();

	free(p);

	return 0;
}
