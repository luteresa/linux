// SPDX-License-Identifier: GPL-2.0
/*
 * buddy_demo.c
  *
   * 演示 buddy 分配/释放链路。
    * 快照在驱动 init 里打印，避免外部脚本错过中间态。
	 */
#include <linux/module.h>
#include <linux/mm.h>
#include <linux/mmzone.h>
#include <linux/gfp.h>

#define DEMO_ORDER  4
#define SUB_ORDER   2
#define SUB_BLOCKS  (1 << (DEMO_ORDER - SUB_ORDER))

static struct page *big;
static struct page *subs[SUB_BLOCKS];

static void dump_buddyinfo(const char *tag)
{
	int nid, zi, order;

	pr_info("--- buddyinfo @ %s ---\n", tag);

	for_each_online_node(nid) {
		pg_data_t *pgdat = NODE_DATA(nid);

		if (!pgdat)
			continue;

		for (zi = 0; zi < MAX_NR_ZONES; zi++) {
			struct zone *zone = &pgdat->node_zones[zi];

			if (!populated_zone(zone))
				continue;

			pr_info("  Node %d, zone %-8s :", nid, zone->name);
			for (order = 0; order < MAX_ORDER; order++)
				pr_cont(" %6lu",
					zone->free_area[order].nr_free);
			pr_cont("\n");
		}
	}
}

static void show_page(struct page *page, int idx, const char *tag)
{
	pr_info("  %s[%d] pfn=%-7lu ref=%d PageBuddy=%d private=%ld\n",
		tag, idx,
		page_to_pfn(page),
		page_ref_count(page), PageBuddy(page), page_private(page));
}

static int __init buddy_demo_init(void)
{
	int i, j;

	pr_info("\n========================================\n");
	pr_info("  Buddy Allocator Demo\n");
	pr_info("========================================\n");
	pr_info("每列对应 order 0..MAX_ORDER-1 的 nr_free\n");

	dump_buddyinfo("T0 分配前");

	pr_info("\n=== step 1: alloc_pages(GFP_KERNEL, order=%d) ===\n",
		DEMO_ORDER);
	big = alloc_pages(GFP_KERNEL, DEMO_ORDER);
	if (!big) {
		pr_err("alloc_pages failed\n");
		return -ENOMEM;
	}

	pr_info("head page=%px head_pfn=%lu\n", big, page_to_pfn(big));
	pr_info("连续 %d 页:\n", 1 << DEMO_ORDER);
	for (i = 0; i < (1 << DEMO_ORDER); i++)
		show_page(big + i, i, "big");

	dump_buddyinfo("T1 alloc 之后");

	pr_info("\n=== step 2: __free_pages(order=%d) ===\n", DEMO_ORDER);
	__free_pages(big, DEMO_ORDER);
	big = NULL;

	dump_buddyinfo("T2 free 之后");

	pr_info("\n=== step 3: alloc %d 个 order=%d 子块 ===\n",
		SUB_BLOCKS, SUB_ORDER);
	for (i = 0; i < SUB_BLOCKS; i++) {
		subs[i] = alloc_pages(GFP_KERNEL, SUB_ORDER);
		if (!subs[i]) {
			pr_err("alloc sub[%d] failed\n", i);
			while (--i >= 0)
				__free_pages(subs[i], SUB_ORDER);
			return -ENOMEM;
		}

		pr_info("  sub[%d] head_pfn=%lu\n", i,
			page_to_pfn(subs[i]));
	}

	pr_info("打印 sub[0] 内部 page:\n");
	for (j = 0; j < (1 << SUB_ORDER); j++)
		show_page(subs[0] + j, j, "sub[0]");

	pr_info("\n=== step 4: 逐个释放子块 ===\n");
	for (i = 0; i < SUB_BLOCKS; i++) {
		pr_info("  -> free sub[%d] pfn=%lu\n", i,
			page_to_pfn(subs[i]));
		__free_pages(subs[i], SUB_ORDER);
		subs[i] = NULL;
	}

	dump_buddyinfo("T3 全部释放后");

	pr_info("\n========================================\n");
	pr_info("  Demo Done\n");
	pr_info("========================================\n");

	return 0;
}

static void __exit buddy_demo_exit(void)
{
	int i;

	if (big) {
		__free_pages(big, DEMO_ORDER);
		big = NULL;
	}

	for (i = 0; i < SUB_BLOCKS; i++) {
		if (subs[i]) {
			__free_pages(subs[i], SUB_ORDER);
			subs[i] = NULL;
		}
	}

	pr_info("buddy_demo exit\n");
}

module_init(buddy_demo_init);
module_exit(buddy_demo_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION
    ("Buddy allocator demo: snapshot buddyinfo inside kernel");
