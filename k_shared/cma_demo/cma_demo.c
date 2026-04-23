// SPDX-License-Identifier: GPL-2.0
/*
 * cma_demo.c
  *
   * Minimal CMA allocation/release demo:
    *   - create a fake platform_device
	 *   - allocate pages from default/device CMA via dma_alloc_from_contiguous()
	  *   - release them via dma_release_from_contiguous()
	   *
	    * Build:
		 *   make -C /lib/modules/$(uname -r)/build M=$PWD modules
		  *
		   * Test:
		    *   insmod cma_demo.ko
			 *   ls -l /dev/cma_demo
			  *   ./cma_demo_test
			   */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/miscdevice.h>
#include <linux/platform_device.h>
#include <linux/uaccess.h>
#include <linux/mutex.h>
#include <linux/dma-map-ops.h>
#include <linux/mm.h>
#include <linux/ioctl.h>
#include <linux/slab.h>

#define CMA_DEMO_IOC_MAGIC  'C'

struct cma_demo_alloc_req {
    __u32 count;		/* number of pages */
    __u32 order;		/* alignment order for dma_alloc_from_contiguous() */
};

struct cma_demo_info {
    __u64 pfn;
    __u64 phys;
    __u32 count;
    __u32 order;
    __u32 allocated;
};

#define CMA_DEMO_ALLOC  _IOW(CMA_DEMO_IOC_MAGIC, 0x01, struct cma_demo_alloc_req)
#define CMA_DEMO_FREE   _IO(CMA_DEMO_IOC_MAGIC,  0x02)
#define CMA_DEMO_INFO   _IOR(CMA_DEMO_IOC_MAGIC, 0x03, struct cma_demo_info)

struct cma_demo_ctx {
    struct device *dev;
    struct page *pages;
    unsigned int count;
    unsigned int order;
    struct mutex lock;
};

static struct cma_demo_ctx g_ctx;
static struct platform_device *g_pdev;

static long cma_demo_ioctl(struct file *file, unsigned int cmd,
			   unsigned long arg)
{
    struct cma_demo_ctx *ctx = &g_ctx;
    long ret = 0;

    mutex_lock(&ctx->lock);

    switch (cmd) {
    case CMA_DEMO_ALLOC:
	{
	    struct cma_demo_alloc_req req;
	    unsigned long phys;

	    if (copy_from_user(&req, (void __user *) arg, sizeof(req))) {
		ret = -EFAULT;
		break;
	    }

	    if (!req.count) {
		ret = -EINVAL;
		break;
	    }

	    if (ctx->pages) {
		ret = -EBUSY;
		break;
	    }

	    ctx->pages =
		dma_alloc_from_contiguous(ctx->dev, req.count,
					  req.order, false);
	    if (!ctx->pages) {
		pr_err
		    ("cma_demo: dma_alloc_from_contiguous failed, count=%u order=%u\n",
		     req.count, req.order);
		ret = -ENOMEM;
		break;
	    }

	    ctx->count = req.count;
	    ctx->order = req.order;
	    phys = page_to_phys(ctx->pages);

	    pr_info
		("cma_demo: alloc success: pages=%u order=%u start_pfn=%lu phys=%pa\n",
		 ctx->count, ctx->order, page_to_pfn(ctx->pages), &phys);
	    break;
	}

    case CMA_DEMO_FREE:
	if (!ctx->pages) {
	    ret = -ENOENT;
	    break;
	}

	pr_info("cma_demo: free: pages=%u start_pfn=%lu\n",
		ctx->count, page_to_pfn(ctx->pages));

	dma_release_from_contiguous(ctx->dev, ctx->pages, ctx->count);

	ctx->pages = NULL;
	ctx->count = 0;
	ctx->order = 0;
	break;

    case CMA_DEMO_INFO:
	{
	    struct cma_demo_info info;

	    memset(&info, 0, sizeof(info));
	    if (ctx->pages) {
		info.allocated = 1;
		info.count = ctx->count;
		info.order = ctx->order;
		info.pfn = page_to_pfn(ctx->pages);
		info.phys = page_to_phys(ctx->pages);
	    }

	    if (copy_to_user((void __user *) arg, &info, sizeof(info))) {
		ret = -EFAULT;
		break;
	    }
	    break;
	}

    default:
	ret = -ENOTTY;
	break;
    }

    mutex_unlock(&ctx->lock);
    return ret;
}

static const struct file_operations cma_demo_fops = {
    .owner = THIS_MODULE,
    .unlocked_ioctl = cma_demo_ioctl,
#ifdef CONFIG_COMPAT
    .compat_ioctl = cma_demo_ioctl,
#endif
};

static struct miscdevice cma_demo_miscdev = {
    .minor = MISC_DYNAMIC_MINOR,
    .name = "cma_demo",
    .fops = &cma_demo_fops,
};

static int __init cma_demo_init(void)
{
    int ret;
    static u64 dma_mask = DMA_BIT_MASK(32);

    mutex_init(&g_ctx.lock);

    g_pdev = platform_device_register_simple("cma-demo-pdev", -1, NULL, 0);
    if (IS_ERR(g_pdev))
	return PTR_ERR(g_pdev);

    g_pdev->dev.dma_mask = &dma_mask;
    g_pdev->dev.coherent_dma_mask = DMA_BIT_MASK(32);

    g_ctx.dev = &g_pdev->dev;

    ret = misc_register(&cma_demo_miscdev);
    if (ret) {
	platform_device_unregister(g_pdev);
	return ret;
    }

    pr_info("cma_demo: loaded, dev=/dev/%s\n", cma_demo_miscdev.name);
    pr_info("cma_demo: use ioctl to alloc/free CMA pages\n");
    return 0;
}

static void __exit cma_demo_exit(void)
{
    mutex_lock(&g_ctx.lock);
    if (g_ctx.pages) {
	pr_info
	    ("cma_demo: releasing outstanding allocation: pages=%u start_pfn=%lu\n",
	     g_ctx.count, page_to_pfn(g_ctx.pages));
	dma_release_from_contiguous(g_ctx.dev, g_ctx.pages, g_ctx.count);
	g_ctx.pages = NULL;
	g_ctx.count = 0;
	g_ctx.order = 0;
    }
    mutex_unlock(&g_ctx.lock);

    misc_deregister(&cma_demo_miscdev);
    platform_device_unregister(g_pdev);

    pr_info("cma_demo: unloaded\n");
}

module_init(cma_demo_init);
module_exit(cma_demo_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("OpenAI");
MODULE_DESCRIPTION("Simple CMA allocation/release demo");
