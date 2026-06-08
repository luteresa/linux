// rss_trace.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>

void show_rss(const char *tag)
{
	    char buf[256];
		    FILE *f = fopen("/proc/self/status", "r");
			    while (fgets(buf, sizeof(buf), f)) {
					        if (strncmp(buf, "VmRSS:", 6) == 0) {
								            printf("[%s] %s", tag, buf);
											            break;
														        }
																    }
																	    fclose(f);
}

int main(void)
{
	    size_t size = 64 * 1024 * 1024;   /* 64 MB */

		    show_rss("start");

			    char *p = mmap(NULL, size, PROT_READ|PROT_WRITE,
				                   MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
				    if (p == MAP_FAILED) { perror("mmap"); return 1; }
					    show_rss("after mmap (lazy, no allocation)");

						    int i;
							    for (i = 0; i < size / 2; i += 4096)
									        p[i] = 1;
											    show_rss("after write half (32MB touched)");

												    for (; i < size; i += 4096)
														        p[i] = 1;
																    show_rss("after write all (64MB touched)");

																	    munmap(p, size);
																		    show_rss("after munmap (freed)");

																			    return 0;
}
