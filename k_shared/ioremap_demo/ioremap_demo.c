#include <linux/module.h>
#include <linux/init.h>
#include <linux/io.h>
#define DEMO_RTC_PHYS   0x09010000UL
#define DEMO_RTC_SIZE   0x1000
/* PL031 RTC 常见寄存器偏移 */
#define RTC_DR          0x000
#define RTC_MR          0x004
#define RTC_LR          0x008
#define RTC_CR          0x00c
#define RTC_IMSC        0x010
static void __iomem *rtc_base;

static int __init ioremap_demo_init(void)
{
	u32 dr, mr, lr, cr, imsc;
	phys_addr_t phys = DEMO_RTC_PHYS;

	pr_info("demo_ioremap: init start\n");
	pr_info("demo_ioremap: phys=%pa size=0x%x\n", &phys,
		DEMO_RTC_SIZE);

	rtc_base = ioremap(DEMO_RTC_PHYS, DEMO_RTC_SIZE);
	if (!rtc_base) {
		pr_err("demo_ioremap: ioremap failed\n");
		return -ENOMEM;
	}

	pr_info("demo_ioremap: rtc_base=%px\n", rtc_base);

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
