#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>

int main()
{
	char *p = malloc(4096);

	raise(SIGSTOP);

	p[0] = 1;

	return 0;
}
