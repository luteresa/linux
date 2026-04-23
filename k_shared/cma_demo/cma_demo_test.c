#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>

#define CMA_DEMO_IOC_MAGIC  'C'

struct cma_demo_alloc_req {
    uint32_t count;
    uint32_t order;
};

struct cma_demo_info {
    uint64_t pfn;
    uint64_t phys;
    uint32_t count;
    uint32_t order;
    uint32_t allocated;
};

#define CMA_DEMO_ALLOC  _IOW(CMA_DEMO_IOC_MAGIC, 0x01, struct cma_demo_alloc_req)
#define CMA_DEMO_FREE   _IO(CMA_DEMO_IOC_MAGIC,  0x02)
#define CMA_DEMO_INFO   _IOR(CMA_DEMO_IOC_MAGIC, 0x03, struct cma_demo_info)

static void dump_info(int fd, const char *tag)
{
    struct cma_demo_info info;

    memset(&info, 0, sizeof(info));
    if (ioctl(fd, CMA_DEMO_INFO, &info) < 0) {
	perror("ioctl(CMA_DEMO_INFO)");
	return;
    }

    printf("\n\n[%s] allocated=%u count=%u order=%u pfn=0x%llx phys=0x%llx\n",
	   tag,
	   info.allocated,
	   info.count,
	   info.order,
	   (unsigned long long) info.pfn, (unsigned long long) info.phys);
	system("cat /proc/pagetypeinfo");
}

int main(int argc, char *argv[]) 
{
    int fd;
    struct cma_demo_alloc_req req;
	int input_num = 0;

	if (argc < 2) {
		printf("使用方法: %s <数字> [其他参数...]\n", argv[0]);
		return 1;
	}

	input_num = atoi(argv[1]);
    fd = open("/dev/cma_demo", O_RDWR);
    if (fd < 0) {
		perror("open /dev/cma_demo");
		return 1;
    }

    dump_info(fd, "before");

    req.count = 256*input_num;		/* 256 pages = 1MB */
    req.order = 0;		/* alignment order in pages */

    if (ioctl(fd, CMA_DEMO_ALLOC, &req) < 0) {
		perror("ioctl(CMA_DEMO_ALLOC)");
		close(fd);
	return 1;
    }

    dump_info(fd, "after alloc");

    if (ioctl(fd, CMA_DEMO_FREE) < 0) {
		perror("ioctl(CMA_DEMO_FREE)");
		close(fd);
		return 1;
    }

    dump_info(fd, "after free");

    close(fd);
    return 0;
}
