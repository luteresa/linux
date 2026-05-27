#include <linux/module.h>
#include <linux/vmalloc.h>
#include <linux/mm.h>
#include<linux/delay.h>

static void *p;

static int __init demo_init(void)
{
	struct page *page;
	phys_addr_t pa;

	msleep(100);

	p = vmalloc(20 * 1024 * 1024);

	if (!p)
		return -ENOMEM;

	page = vmalloc_to_page(p);

	pa = page_to_phys(page);

	pr_info("vmalloc va = %px\n", p);
	pr_info("first page pa = %pa\n", &pa);
	for (int i = 0; i < 512*5; i += 256) {
		void *va = p + i * PAGE_SIZE;
		struct page *page;
		phys_addr_t pa;

		page = vmalloc_to_page(va);
		pa = page_to_phys(page);

		pr_info("va=%px pa=%pa\n", va, &pa);
	}

	return 0;
}

static void __exit demo_exit(void)
{
	vfree(p);
}

module_init(demo_init);
module_exit(demo_exit);

MODULE_LICENSE("GPL");
