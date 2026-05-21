#include <linux/module.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/mm.h>
#include <linux/pgtable.h>

#define DEMO_RTC_PHYS   0x09010000UL
#define DEMO_RTC_SIZE   0x1000

/* PL031 RTC 常见寄存器偏移 */
#define RTC_DR          0x000
#define RTC_MR          0x004
#define RTC_LR          0x008
#define RTC_CR          0x00c
#define RTC_IMSC        0x010

static void __iomem *rtc_base;

static void demo_dump_ttbr1(void)
{
	u64 ttbr1;
	phys_addr_t pgd_phys;
	void *pgd_virt;

	ttbr1 = read_sysreg(ttbr1_el1);

	/*
	 * 这里只演示思路：
	 * 低位不是纯地址，实际要按你的内核/地址位数做 mask。
	 * 常见做法是把页表对齐以下的低位去掉。
	 */
	pgd_phys = ttbr1 & PAGE_MASK;
	pgd_virt = __va(pgd_phys);

	pr_info("demo_walk: TTBR1_EL1 = 0x%016llx\n",
		(unsigned long long) ttbr1);
	pr_info("demo_walk: kernel pgd phys = %pa\n", &pgd_phys);
	pr_info("demo_walk: kernel pgd virt = %px\n", pgd_virt);
}

static void demo_dump_kernel_va(unsigned long addr)
{
	pgd_t *pgdp;
	p4d_t *p4dp;
	pud_t *pudp;
	pmd_t *pmdp;
	pte_t *ptep;
	phys_addr_t phys;

	pr_info("demo_walk: dump addr = 0x%016lx\n", addr);

///1,.current拿到的是用户进程的mm
/*
	struct mm_struct *mm = current->active_mm;
	if (!mm) {
			pr_info("demo_walk: no active_mm\n");
			return;
	}

	pgdp = pgd_offset(mm, addr);
*/
///2.模块无法访问init_mm
/*
pgdp = pgd_offset_k(addr);
*/

///3.直接从ttbr1读取内核页表地址
	u64 ttbr1 = read_sysreg(ttbr1_el1);
	phys_addr_t pgd_phys = ttbr1 & PAGE_MASK;
	pgdp = (pgd_t *) __va(pgd_phys);

	/* 然后自己算 index，不能直接再用 pgd_offset(mm, addr) */
	pgdp = pgdp + pgd_index(addr);

	pr_info("demo_walk: PGD @ %px val=0x%016llx\n",
		pgdp, (unsigned long long) pgd_val(*pgdp));
	if (pgd_none(*pgdp) || pgd_bad(*pgdp)) {
		pr_info("demo_walk: bad/none pgd\n");
		return;
	}

	p4dp = p4d_offset(pgdp, addr);
	pr_info("demo_walk: P4D @ %px val=0x%016llx\n",
		p4dp, (unsigned long long) p4d_val(*p4dp));
	if (p4d_none(*p4dp) || p4d_bad(*p4dp)) {
		pr_info("demo_walk: bad/none p4d\n");
		return;
	}

	pudp = pud_offset(p4dp, addr);
	pr_info("demo_walk: PUD @ %px val=0x%016llx\n",
		pudp, (unsigned long long) pud_val(*pudp));
	if (pud_none(*pudp) || pud_bad(*pudp)) {
		pr_info("demo_walk: bad/none pud\n");
		return;
	}

	if (pud_leaf(*pudp)) {
		phys = ((phys_addr_t) pud_pfn(*pudp) << PAGE_SHIFT) |
		    (addr & ~PUD_MASK);
		pr_info("demo_walk: PUD leaf, phys=%pa\n", &phys);
		return;
	}

	pmdp = pmd_offset(pudp, addr);
	pr_info("demo_walk: PMD @ %px val=0x%016llx\n",
		pmdp, (unsigned long long) pmd_val(*pmdp));
	if (pmd_none(*pmdp) || pmd_bad(*pmdp)) {
		pr_info("demo_walk: bad/none pmd\n");
		return;
	}

	if (pmd_leaf(*pmdp)) {
		phys = ((phys_addr_t) pmd_pfn(*pmdp) << PAGE_SHIFT) |
		    (addr & ~PMD_MASK);
		pr_info("demo_walk: PMD leaf, phys=%pa\n", &phys);
		return;
	}

	ptep = pte_offset_kernel(pmdp, addr);
	pr_info("demo_walk: PTE @ %px val=0x%016llx\n",
		ptep, (unsigned long long) pte_val(*ptep));

	if (!pte_present(*ptep)) {
		pr_info("demo_walk: pte not present\n");
		return;
	}

	phys = ((phys_addr_t) pte_pfn(*ptep) << PAGE_SHIFT) |
	    (addr & ~PAGE_MASK);

	pr_info("demo_walk: PTE present, PFN=0x%lx phys=%pa\n",
		(unsigned long) pte_pfn(*ptep), &phys);

	pr_info
	    ("demo_walk: pte_valid=%d pte_write=%d pte_dirty=%d pte_young=%d\n",
	     pte_valid(*ptep), pte_write(*ptep), pte_dirty(*ptep),
	     pte_young(*ptep));
}

static int __init ioremap_demo_init(void)
{
	u32 dr, mr, lr, cr, imsc;
	phys_addr_t phys = DEMO_RTC_PHYS;

	pr_info("demo_ioremap: init start\n");
	pr_info("demo_ioremap: phys=%pa size=0x%x\n", &phys,
		DEMO_RTC_SIZE);

	/* 申请 vmalloc/ioremap 区虚拟地址，并建立到设备物理地址的页表映射 */
	rtc_base = ioremap(DEMO_RTC_PHYS, DEMO_RTC_SIZE);
	if (!rtc_base) {
		pr_err("demo_ioremap: ioremap failed\n");
		return -ENOMEM;
	}

	pr_info("demo_ioremap: rtc_base=%px\n", rtc_base);

	demo_dump_ttbr1();
	demo_dump_kernel_va((unsigned long) rtc_base);

	dr = readl(rtc_base + RTC_DR);
	mr = readl(rtc_base + RTC_MR);
	lr = readl(rtc_base + RTC_LR);
	cr = readl(rtc_base + RTC_CR);
	imsc = readl(rtc_base + RTC_IMSC);

	pr_info("demo_ioremap: RTC_DR   = 0x%08x\n", dr);
	pr_info("demo_ioremap: RTC_MR   = 0x%08x\n", mr);
	pr_info("demo_ioremap: RTC_LR   = 0x%08x\n", lr);
	pr_info("demo_ioremap: RTC_CR   = 0x%08x\n", cr);
	pr_info("demo_ioremap: RTC_IMSC = 0x%08x\n", imsc);

	return 0;
}

static void __exit ioremap_demo_exit(void)
{
	pr_info("demo_ioremap: exit\n");
	if (rtc_base) {
		pr_info("demo_ioremap: iounmap %px\n", rtc_base);
		iounmap(rtc_base);
		rtc_base = NULL;
	}
}

module_init(ioremap_demo_init);
module_exit(ioremap_demo_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Simple ioremap demo for QEMU virt PL031");
MODULE_AUTHOR("OpenAI");
