#include <linux/module.h>
#include <linux/init.h>
#include <linux/mm.h>

// 接 page_inspect.c 末尾追加
static int alloc_demo(void)
{
	struct page *page = alloc_pages(GFP_KERNEL, 0);
	if (!page)
		return -ENOMEM;

	pr_info("alloc: pfn=%lu, phys=0x%llx, virt=%px\n",
		page_to_pfn(page), (u64) page_to_phys(page),
		page_to_virt(page));
	pr_info("alloc: _refcount=%d, _mapcount=%d, PageBuddy=%d\n",
		page_count(page), page_mapcount(page), PageBuddy(page));

	__free_pages(page, 0);
	return 0;
}

static int __init mod_init(void)
{
	struct page *p0 = pfn_to_page(0);
	struct page *p1 = pfn_to_page(1);
	pr_info("=== page_inspect ===\n");
	pr_info("sizeof(struct page) = %zu\n", sizeof(struct page));
	pr_info("PAGE_SIZE           = %lu\n", PAGE_SIZE);
	pr_info("page[0]             = %px\n", p0);
	pr_info("page[1]             = %px\n", p1);
	pr_info("delta               = %lu bytes\n",
		(unsigned long) (p1) - (unsigned long) (p0));
	pr_info("Relocation Offset   = %lx\n", (unsigned long) kimage_voffset);	// ARM64 only

	alloc_demo();

	return 0;
}

static void __exit mod_exit(void)
{
	pr_info("page_inspect: unloaded\n");
}

module_init(mod_init);
module_exit(mod_exit);
MODULE_LICENSE("GPL");
