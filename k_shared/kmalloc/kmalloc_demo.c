#include <linux/module.h>
#include <linux/slab.h>
#include <linux/mm.h>


#define CNT 1000

static void *p[CNT];

static int __init demo_init(void)
{
	int i;

	for (i = 0; i < CNT; i++) {
		p[i] = kmalloc(4096, GFP_KERNEL);
	}

	pr_info("alloc done\n");

	return 0;
}

static void __exit demo_exit(void)
{
	int i;

	for (i = 0; i < CNT; i++)
		kfree(p[i]);

	pr_info("free done\n");
}

module_init(demo_init);
module_exit(demo_exit);

MODULE_LICENSE("GPL");
