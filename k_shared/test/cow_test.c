#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>

int main()
{
	char *p = malloc(4096);

	p[0] = 1;

	pid_t pid = fork();

	if (pid == 0) {

		raise(SIGSTOP);

		p[0] = 2;

		printf("child write done\n");
	}

	wait(NULL);

	return 0;
}
