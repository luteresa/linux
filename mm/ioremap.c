// SPDX-License-Identifier: GPL-2.0
/*
 * Re-map IO memory to kernel address space so that we can access it.
 * This is needed for high PCI addresses that aren't mapped in the
 * 640k-1MB IO memory area on PC's
 *
 * (C) Copyright 1995 1996 Linus Torvalds
 */
#include <linux/vmalloc.h>
#include <linux/mm.h>
#include <linux/io.h>
#include <linux/export.h>

void __iomem *ioremap_prot(phys_addr_t phys_addr, size_t size,
			   unsigned long prot)
{
	unsigned long offset, vaddr;
	phys_addr_t last_addr;
	struct vm_struct *area;

	/* Disallow wrap-around or zero size */
	last_addr = phys_addr + size - 1;
	if (!size || last_addr < phys_addr)
		return NULL;

	/* Page-align mappings */
	offset = phys_addr & (~PAGE_MASK);
	phys_addr -= offset;
	///对齐物理地址
	size = PAGE_ALIGN(size + offset);

///只针对设备内存?
///普通ram以及映射，比如phys_to_virt就可以访问；
///device memory不能cache，
	if (!ioremap_allowed(phys_addr, size, prot))
		return NULL;

///申请一个vma
///VM_IOREMAP:从vmalloc区域申请vma
	area = get_vm_area_caller(size, VM_IOREMAP,
			__builtin_return_address(0));
	if (!area)
		return NULL;
	vaddr = (unsigned long)area->addr;
	area->phys_addr = phys_addr;

///映射虚拟地址，建立页表
	if (ioremap_page_range(vaddr, vaddr + size, phys_addr,
			       __pgprot(prot))) {
		free_vm_area(area);
		return NULL;
	}

///返回可访问虚拟地址
	return (void __iomem *)(vaddr + offset);
}
EXPORT_SYMBOL(ioremap_prot);

void iounmap(volatile void __iomem *addr)
{
	void *vaddr = (void *)((unsigned long)addr & PAGE_MASK);

	if (!iounmap_allowed(vaddr))
		return;

	if (is_vmalloc_addr(vaddr))
		vunmap(vaddr);
}
EXPORT_SYMBOL(iounmap);
