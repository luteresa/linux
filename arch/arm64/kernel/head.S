/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Low-level CPU initialisation
 * Based on arch/arm/kernel/head.S
 *
 * Copyright (C) 1994-2002 Russell King
 * Copyright (C) 2003-2012 ARM Ltd.
 * Authors:	Catalin Marinas <catalin.marinas@arm.com>
 *		Will Deacon <will.deacon@arm.com>
 */

#include <linux/linkage.h>
#include <linux/init.h>
#include <linux/pgtable.h>

#include <asm/asm_pointer_auth.h>
#include <asm/assembler.h>
#include <asm/boot.h>
#include <asm/bug.h>
#include <asm/ptrace.h>
#include <asm/asm-offsets.h>
#include <asm/cache.h>
#include <asm/cputype.h>
#include <asm/el2_setup.h>
#include <asm/elf.h>
#include <asm/image.h>
#include <asm/kernel-pgtable.h>
#include <asm/kvm_arm.h>
#include <asm/memory.h>
#include <asm/pgtable-hwdef.h>
#include <asm/page.h>
#include <asm/scs.h>
#include <asm/smp.h>
#include <asm/sysreg.h>
#include <asm/thread_info.h>
#include <asm/virt.h>

#include "efi-header.S"

#if (PAGE_OFFSET & 0x1fffff) != 0
#error PAGE_OFFSET must be at least 2MB aligned
#endif

/*
 * Kernel startup entry point.
 * ---------------------------
 *
 * The requirements are:
 *   MMU = off, D-cache = off, I-cache = on or off,
 *   x0 = physical address to the FDT blob.
 *
 * Note that the callee-saved registers are used for storing variables
 * that are useful before the MMU is enabled. The allocations are described
 * in the entry routines.
 */
 /*********************************************************************************
  * 
  * ARMV8支持EL2和EL3，这些异常等级都可以引导Linux内核的运行；
  * Linux内核运行在EL1, 
  * kernel启动条件的要求：
  * CPU：
  * 屏蔽CPU上所有的中断，比如清除PSTATE寄存器的DAIF域；
  * CPU必须处在EL2或非安全模式的EL1
  *
  * MMU和高速缓存:
  * 关闭MMU;
  * 关闭数据高速缓存；//清除内核镜像加载的地址范围的高速缓存，最简单办法，关闭缓存
  * 指令高速缓存可关闭或打开；//因为u-boot和内核指令代码不会重叠，缓存不会出错
  *
  * 其他：
  * X0寄存器指向设备树的物理地址；
  * 设置时钟，CNTFRQ和CNTVOFF寄存器；
  * 内存一致性；
  *
  * U-boot的作用是加载内核镜像到内存，跳转到kernel入口地址，即这里！ 
  ********************************************************************************/
	__HEAD
	/*
	 * DO NOT MODIFY. Image header expected by Linux boot-loaders.
	 */
	efi_signature_nop			// special NOP to identity as PE/COFF executable
	b	primary_entry			// branch to kernel start, magic     ///跳转到内核启动汇编代码入口
	.quad	0				// Image load offset from start of RAM, little-endian
	le64sym	_kernel_size_le			// Effective size of kernel image, little-endian
	le64sym	_kernel_flags_le		// Informative flags, little-endian
	.quad	0				// reserved
	.quad	0				// reserved
	.quad	0				// reserved
	.ascii	ARM64_IMAGE_MAGIC		// Magic number
	.long	.Lpe_header_offset		// Offset to the PE header.

	__EFI_PE_HEADER

	__INIT  ///以下代码处于".init.text"段

	/*
	 * The following callee saved general purpose registers are used on the
	 * primary lowlevel boot path:
	 *
	 *  Register   Scope                      Purpose
	 *  x20        primary_entry() .. __primary_switch()    CPU boot mode
	 *  x21        primary_entry() .. start_kernel()        FDT pointer passed at boot in x0
	 *  x22        create_idmap() .. start_kernel()         ID map VA of the DT blob
	 *  x23        primary_entry() .. start_kernel()        physical misalignment/KASLR offset
	 *  x24        __primary_switch()                       linear map KASLR seed
	 *  x25        primary_entry() .. start_kernel()        supported VA size
	 *  x28        create_idmap()                           callee preserved temp register
	 */
SYM_CODE_START(primary_entry)
///保持启动参数到boot_args[]数组
	bl	preserve_boot_args
///切换到EL1模式，以运行kernel
	bl	init_kernel_el			// w0=cpu_boot_mode
	mov	x20, x0
	bl	create_idmap

	/*
	 * The following calls CPU setup code, see arch/arm64/mm/proc.S for
	 * details.
	 * On return, the CPU will be ready for the MMU to be turned on and
	 * the TCR will have been set.
	 */
#if VA_BITS > 48
	mrs_s	x0, SYS_ID_AA64MMFR2_EL1
	tst	x0, #0xf << ID_AA64MMFR2_EL1_VARange_SHIFT
	mov	x0, #VA_BITS
	mov	x25, #VA_BITS_MIN
	csel	x25, x25, x0, eq
	mov	x0, x25
#endif
///为打开mmu做一些处理器相关的初始化
	bl	__cpu_setup			// initialise processor
///启动MMU，并跳转到start_kernel()函数(进入内核的C语言部分)
	b	__primary_switch
SYM_CODE_END(primary_entry)

/*
 * Preserve the arguments passed by the bootloader in x0 .. x3
 */
 ///把引导程序传递过来的参数x0~x3保存到boot_args[]数组中
SYM_CODE_START_LOCAL(preserve_boot_args)
	mov	x21, x0				// x21=FDT，x0设备树地址，暂存在x21

	adr_l	x0, boot_args			// record the contents of
	stp	x21, x1, [x0]			// x0 .. x3 at kernel entry
	stp	x2, x3, [x0, #16]       ///4个参数存入boot_args

	dmb	sy				// needed before dc ivac with
						// MMU off
						///保证后面__inval_dcache_area清除缓存前，执行完stp指令，保证参数保存完整性

	add	x1, x0, #0x20			// 4 x 8 bytes
	///x0为设备树地址，x1=32为长度，__inval_dcache_area使boot_args[]数组对应的高速缓存失效，并清除缓存
	b	dcache_inval_poc		// tail call
SYM_CODE_END(preserve_boot_args)

SYM_FUNC_START_LOCAL(clear_page_tables)
	/*
	 * Clear the init page tables.
	 */
	adrp	x0, init_pg_dir
	adrp	x1, init_pg_end
	sub	x2, x1, x0
	mov	x1, xzr
	b	__pi_memset			// tail call
SYM_FUNC_END(clear_page_tables)

/*
 * Macro to populate page table entries, these entries can be pointers to the next level
 * or last level entries pointing to physical memory.
 *
 *	tbl:	page table address
 *	rtbl:	pointer to page table or physical memory
 *	index:	start index to write
 *	eindex:	end index to write - [index, eindex] written to
 *	flags:	flags for pagetable entry to or in
 *	inc:	increment to rtbl between each entry
 *	tmp1:	temporary variable
 *
 * Preserves:	tbl, eindex, flags, inc
 * Corrupts:	index, tmp1
 * Returns:	rtbl
 */

	/*******************************************************************
	 * 填写页表
	 *
	 *	tbl:	页表基地址
	 *	rtbl:	下级页表基地址
	 *	index:	写入页表的起始索引
	 *	eindex: 页表结束索引
	 *	flags:	页表属性
	 *	inc:	
	 *	tmp1:	temporary variable
	 *********************************************************************/

	.macro populate_entries, tbl, rtbl, index, eindex, flags, inc, tmp1
.Lpe\@:	phys_to_pte \tmp1, \rtbl
	orr	\tmp1, \tmp1, \flags	// tmp1 = table entry
	str	\tmp1, [\tbl, \index, lsl #3] ///
	add	\rtbl, \rtbl, \inc	// rtbl = pa next level ///这里我理解为rtbl的下一个页(简单理解为相邻下个物理页)，而不是下一级，跟注释有点不同？
	add	\index, \index, #1
	cmp	\index, \eindex     ///判断是否填充完，未完则继续填写下一个
	b.ls	.Lpe\@
	.endm

/*
 * Compute indices of table entries from virtual address range. If multiple entries
 * were needed in the previous page table level then the next page table level is assumed
 * to be composed of multiple pages. (This effectively scales the end index).
 *
 *	vstart:	virtual address of start of range
 *	vend:	virtual address of end of range - we map [vstart, vend]
 *	shift:	shift used to transform virtual address into index
 *	order:  #imm 2log(number of entries in page table)
 *	istart:	index in table corresponding to vstart
 *	iend:	index in table corresponding to vend
 *	count:	On entry: how many extra entries were required in previous level, scales
 *			  our end index.
 *		On exit: returns how many extra entries required for next page table level
 *
 * Preserves:	vstart, vend
 * Returns:	istart, iend, count
 */
/**************************************************************
 * func:计算vstart,vend在页表的索引值，返回值填在istart,iend
 *
 * vstart:虚拟地址的起始地址
 * vend:虚拟地址结束地址；
 * shift各级页表在虚拟地址中的偏移；
 * ptrs：页表项的个数；
 * istart：vstart索引值；
 * iend:vend索引值；
 * count:页表项个数
 **************************************************************/

	.macro compute_indices, vstart, vend, shift, order, istart, iend, count
	ubfx	\istart, \vstart, \shift, \order
	ubfx	\iend, \vend, \shift, \order
	add	\iend, \iend, \count, lsl \order
	sub	\count, \iend, \istart

	.endm

/*
 * Map memory for specified virtual address range. Each level of page table needed supports
 * multiple entries. If a level requires n entries the next page table level is assumed to be
 * formed from n pages.
 *
 *	tbl:	location of page table
 *	rtbl:	address to be used for first level page table entry (typically tbl + PAGE_SIZE)
 *	vstart:	virtual address of start of range
 *	vend:	virtual address of end of range - we map [vstart, vend - 1]
 *	flags:	flags to use to map last level entries
 *	phys:	physical address corresponding to vstart - physical memory is contiguous
 *	order:  #imm 2log(number of entries in PGD table)
 *
 * If extra_shift is set, an extra level will be populated if the end address does
 * not fit in 'extra_shift' bits. This assumes vend is in the TTBR0 range.
 *
 * Temporaries:	istart, iend, tmp, count, sv - these need to be different registers
 * Preserves:	vstart, flags
 * Corrupts:	tbl, rtbl, vend, istart, iend, tmp, count, sv
 */
/* tbl：页表起始地址，页表基地址
 * rtbl：下一级页表起始地址，通常是tbl+PAGE_SIZE
 * vstart：要映射的虚拟地址的起始地址
 * vend：要映射的虚拟地址的结束地址
 * flags：最后一级页表的属性
 * phys：映射的物理地址
 * pgds：PGD页表项的个数
 */

	.macro map_memory, tbl, rtbl, vstart, vend, flags, phys, order, istart, iend, tmp, count, sv, extra_shift
	sub \vend, \vend, #1
	add \rtbl, \tbl, #PAGE_SIZE
	mov \count, #0

	.ifnb	\extra_shift
	tst	\vend, #~((1 << (\extra_shift)) - 1)
	b.eq	.L_\@

	///compute_indices宏计算vstart,vend在页表中的索引值
	compute_indices \vstart, \vend, #\extra_shift, #(PAGE_SHIFT - 3), \istart, \iend, \count
	mov \sv, \rtbl
	///设置页表内容，分别填充一级页表PGD，二级页表PMD, 最后一级页表PT
	populate_entries \tbl, \rtbl, \istart, \iend, #PMD_TYPE_TABLE, #PAGE_SIZE, \tmp
	mov \tbl, \sv
	.endif
.L_\@:
	compute_indices \vstart, \vend, #PGDIR_SHIFT, #\order, \istart, \iend, \count
	mov \sv, \rtbl
	populate_entries \tbl, \rtbl, \istart, \iend, #PMD_TYPE_TABLE, #PAGE_SIZE, \tmp
	mov \tbl, \sv

#if SWAPPER_PGTABLE_LEVELS > 3
	compute_indices \vstart, \vend, #PUD_SHIFT, #(PAGE_SHIFT - 3), \istart, \iend, \count
	mov \sv, \rtbl
	populate_entries \tbl, \rtbl, \istart, \iend, #PMD_TYPE_TABLE, #PAGE_SIZE, \tmp
	mov \tbl, \sv
#endif

#if SWAPPER_PGTABLE_LEVELS > 2
	compute_indices \vstart, \vend, #SWAPPER_TABLE_SHIFT, #(PAGE_SHIFT - 3), \istart, \iend, \count
	mov \sv, \rtbl
	populate_entries \tbl, \rtbl, \istart, \iend, #PMD_TYPE_TABLE, #PAGE_SIZE, \tmp
	mov \tbl, \sv
#endif

	compute_indices \vstart, \vend, #SWAPPER_BLOCK_SHIFT, #(PAGE_SHIFT - 3), \istart, \iend, \count
	bic \rtbl, \phys, #SWAPPER_BLOCK_SIZE - 1
	populate_entries \tbl, \rtbl, \istart, \iend, \flags, #SWAPPER_BLOCK_SIZE, \tmp
	.endm

/*
 * Remap a subregion created with the map_memory macro with modified attributes
 * or output address. The entire remapped region must have been covered in the
 * invocation of map_memory.
 *
 * x0: last level table address (returned in first argument to map_memory)
 * x1: start VA of the existing mapping
 * x2: start VA of the region to update
 * x3: end VA of the region to update (exclusive)
 * x4: start PA associated with the region to update
 * x5: attributes to set on the updated region
 * x6: order of the last level mappings
 */
SYM_FUNC_START_LOCAL(remap_region)
	sub	x3, x3, #1		// make end inclusive

	// Get the index offset for the start of the last level table
	lsr	x1, x1, x6
	bfi	x1, xzr, #0, #PAGE_SHIFT - 3

	// Derive the start and end indexes into the last level table
	// associated with the provided region
	lsr	x2, x2, x6
	lsr	x3, x3, x6
	sub	x2, x2, x1
	sub	x3, x3, x1

	mov	x1, #1
	lsl	x6, x1, x6		// block size at this level

	populate_entries x0, x4, x2, x3, x5, x6, x7
	ret
SYM_FUNC_END(remap_region)

SYM_FUNC_START_LOCAL(create_idmap)
	mov	x28, lr
	/*
	 * The ID map carries a 1:1 mapping of the physical address range
	 * covered by the loaded image, which could be anywhere in DRAM. This
	 * means that the required size of the VA (== PA) space is decided at
	 * boot time, and could be more than the configured size of the VA
	 * space for ordinary kernel and user space mappings.
	 *
	 * There are three cases to consider here:
	 * - 39 <= VA_BITS < 48, and the ID map needs up to 48 VA bits to cover
	 *   the placement of the image. In this case, we configure one extra
	 *   level of translation on the fly for the ID map only. (This case
	 *   also covers 42-bit VA/52-bit PA on 64k pages).
	 *
	 * - VA_BITS == 48, and the ID map needs more than 48 VA bits. This can
	 *   only happen when using 64k pages, in which case we need to extend
	 *   the root level table rather than add a level. Note that we can
	 *   treat this case as 'always extended' as long as we take care not
	 *   to program an unsupported T0SZ value into the TCR register.
	 *
	 * - Combinations that would require two additional levels of
	 *   translation are not supported, e.g., VA_BITS==36 on 16k pages, or
	 *   VA_BITS==39/4k pages with 5-level paging, where the input address
	 *   requires more than 47 or 48 bits, respectively.
	 */
#if (VA_BITS < 48)
#define IDMAP_PGD_ORDER	(VA_BITS - PGDIR_SHIFT)
#define EXTRA_SHIFT	(PGDIR_SHIFT + PAGE_SHIFT - 3)

	/*
	 * If VA_BITS < 48, we have to configure an additional table level.
	 * First, we have to verify our assumption that the current value of
	 * VA_BITS was chosen such that all translation levels are fully
	 * utilised, and that lowering T0SZ will always result in an additional
	 * translation level to be configured.
	 */
#if VA_BITS != EXTRA_SHIFT
#error "Mismatch between VA_BITS and page size/number of translation levels"
#endif
#else
#define IDMAP_PGD_ORDER	(PHYS_MASK_SHIFT - PGDIR_SHIFT)
#define EXTRA_SHIFT
	/*
	 * If VA_BITS == 48, we don't have to configure an additional
	 * translation level, but the top-level table has more entries.
	 */
#endif
	adrp	x0, init_idmap_pg_dir
	adrp	x3, _text
	adrp	x6, _end + MAX_FDT_SIZE + SWAPPER_BLOCK_SIZE
	mov	x7, SWAPPER_RX_MMUFLAGS

///调用map_memory宏建立__idmap_text代码段的映射页表；
/*
 * x0：idmap_pg_dir
 * x1：
 * x3：__idmap_text_start
 * x6： __idmap_text_end
 * x7： SWAPPER_MM_MMUFLAGS
 * x3： __idmap_text_start
 * x4： PTRS_PER_PGD
*/

	map_memory x0, x1, x3, x6, x7, x3, IDMAP_PGD_ORDER, x10, x11, x12, x13, x14, EXTRA_SHIFT

	/* Remap the kernel page tables r/w in the ID map */
	adrp	x1, _text
	adrp	x2, init_pg_dir
	adrp	x3, init_pg_end
	bic	x4, x2, #SWAPPER_BLOCK_SIZE - 1
	mov	x5, SWAPPER_RW_MMUFLAGS
	mov	x6, #SWAPPER_BLOCK_SHIFT
	bl	remap_region

	///调用map_memory宏建立整个内核镜像代码段的映射页表；
	/**************************************************************************
	 * 为什么要建第二张表？
	 * CPU刚启动时，物理内存一般都在低地址(不会超过256T大小)，恒等映射的地址实际在用户空间了，
	 * 即MMU启用后idmap_pg_dir会调入TTBR0;
     * 而内核空间的链接地址都是在高地址(内核空间在高地址)，需要填入TTBR1；
     * 因此，这里再建一张表，映射整个内核镜像，且虚拟地址空间实在高地址区0xffffxxxx xxxx xxxx

     * 注：init_pg_dir和idmap_pg_dir两个页表映射区别：
     * (1)init_pg_dir映射的虚拟地址在高位0xffff xxxx xxxx xxxx;
     *   idmap_pg_dir映射的虚拟地址在地位0x0000 xxxx xxxx xxxx;
     *   MMU启用后，init_pg_dir填入TTBR1,idmap_pg_dir填入TTBR0；
     * (2)init_pg_dir映射大小是整个内核镜像，idmap_pg_dir映射2M, 只需要过度完成MMU开启即可；
     ***************************************************************************/

	/* Remap the FDT after the kernel image */
	adrp	x1, _text
	adrp	x22, _end + SWAPPER_BLOCK_SIZE
	bic	x2, x22, #SWAPPER_BLOCK_SIZE - 1
	bfi	x22, x21, #0, #SWAPPER_BLOCK_SHIFT		// remapped FDT address
	add	x3, x2, #MAX_FDT_SIZE + SWAPPER_BLOCK_SIZE
	bic	x4, x21, #SWAPPER_BLOCK_SIZE - 1
	mov	x5, SWAPPER_RW_MMUFLAGS
	mov	x6, #SWAPPER_BLOCK_SHIFT
	bl	remap_region

	/*
	 * Since the page tables have been populated with non-cacheable
	 * accesses (MMU disabled), invalidate those tables again to
	 * remove any speculatively loaded cache lines.
	 */
	dmb	sy

	adrp	x0, init_idmap_pg_dir
	adrp	x1, init_idmap_pg_end
	bl	dcache_inval_poc
	ret	x28
SYM_FUNC_END(create_idmap)

SYM_FUNC_START_LOCAL(create_kernel_mapping)
	adrp	x0, init_pg_dir
	mov_q	x5, KIMAGE_VADDR		// compile time __va(_text)
#ifdef CONFIG_RELOCATABLE
	add	x5, x5, x23			// add KASLR displacement
#endif
	adrp	x6, _end			// runtime __pa(_end)
	adrp	x3, _text			// runtime __pa(_text)
	sub	x6, x6, x3			// _end - _text
	add	x6, x6, x5			// runtime __va(_end)
	mov	x7, SWAPPER_RW_MMUFLAGS

	map_memory x0, x1, x5, x6, x7, x3, (VA_BITS - PGDIR_SHIFT), x10, x11, x12, x13, x14

	dsb	ishst				// sync with page table walker
	ret
SYM_FUNC_END(create_kernel_mapping)

	/*
	 * Initialize CPU registers with task-specific and cpu-specific context.
	 *
	 * Create a final frame record at task_pt_regs(current)->stackframe, so
	 * that the unwinder can identify the final frame record of any task by
	 * its location in the task stack. We reserve the entire pt_regs space
	 * for consistency with user tasks and kthreads.
	 */
	.macro	init_cpu_task tsk, tmp1, tmp2
	msr	sp_el0, \tsk                ///sp_el0在EL1模式下无效，这里用来存init进程的task_struct指针是合适的


	ldr	\tmp1, [\tsk, #TSK_STACK]
	add	sp, \tmp1, #THREAD_SIZE
	sub	sp, sp, #PT_REGS_SIZE

	stp	xzr, xzr, [sp, #S_STACKFRAME]
	add	x29, sp, #S_STACKFRAME

	scs_load \tsk

	adr_l	\tmp1, __per_cpu_offset
	ldr	w\tmp2, [\tsk, #TSK_TI_CPU]
	ldr	\tmp1, [\tmp1, \tmp2, lsl #3]
	set_this_cpu_offset \tmp1
	.endm

/*
 * The following fragment of code is executed with the MMU enabled.
 *
 *   x0 = __pa(KERNEL_START)
 */
SYM_FUNC_START_LOCAL(__primary_switched)
	///已开启mmu，这里开始访问的都是虚拟地址,
	///比如init_task静态定义的虚拟地址，已经映射到对应物理内存地址
	adr_l	x4, init_task           ///init_thread_union指向thread_union数据结构，其中包含系统第一个进程(init进程)的内核栈

	init_cpu_task x4, x5, x6

	adr_l	x8, vectors			// load VBAR_EL1 with virtual
	msr	vbar_el1, x8			// vector table address
	isb

	stp	x29, x30, [sp, #-16]!
	mov	x29, sp

    ///保存设备树的地址
	str_l	x21, __fdt_pointer, x5		// Save FDT pointer

	ldr_l	x4, kimage_vaddr		// Save the offset between
	sub	x4, x4, x0			// the kernel virtual and
	str_l	x4, kimage_voffset, x5		// physical mappings

	mov	x0, x20
	bl	set_cpu_boot_mode_flag

	// Clear BSS
	///清除未初始化的数据段
	adr_l	x0, __bss_start
	mov	x1, xzr
	adr_l	x2, __bss_stop
	sub	x2, x2, x0
	bl	__pi_memset
	dsb	ishst				// Make zero page visible to PTW

#if VA_BITS > 48
	adr_l	x8, vabits_actual		// Set this early so KASAN early init
	str	x25, [x8]			// ... observes the correct value
	dc	civac, x8			// Make visible to booting secondaries
#endif

#ifdef CONFIG_RANDOMIZE_BASE
	adrp	x5, memstart_offset_seed	// Save KASLR linear map seed
	strh	w24, [x5, :lo12:memstart_offset_seed]
#endif
#if defined(CONFIG_KASAN_GENERIC) || defined(CONFIG_KASAN_SW_TAGS)
	bl	kasan_early_init
#endif
	mov	x0, x21				// pass FDT address in x0
	bl	early_fdt_map			// Try mapping the FDT early
	mov	x0, x20				// pass the full boot status
	bl	init_feature_override		// Parse cpu feature overrides
	mov	x0, x20
	bl	finalise_el2			// Prefer VHE if possible
//sp指向内核栈顶?
	ldp	x29, x30, [sp], #16
//跳转到C语言入口
	bl	start_kernel
	ASM_BUG()
SYM_FUNC_END(__primary_switched)

/*
 * end early head section, begin head code that is also used for
 * hotplug and needs to have the same protections as the text region
 */
	.section ".idmap.text","awx"

/*
 * Starting from EL2 or EL1, configure the CPU to execute at the highest
 * reachable EL supported by the kernel in a chosen default state. If dropping
 * from EL2 to EL1, configure EL2 before configuring EL1.
 *
 * Since we cannot always rely on ERET synchronizing writes to sysregs (e.g. if
 * SCTLR_ELx.EOS is clear), we place an ISB prior to ERET.
 *
 * Returns either BOOT_CPU_MODE_EL1 or BOOT_CPU_MODE_EL2 in x0 if
 * booted in EL1 or EL2 respectively, with the top 32 bits containing
 * potential context flags. These flags are *not* stored in __boot_cpu_mode.
 */
SYM_FUNC_START(init_kernel_el)
	mrs	x0, CurrentEL
	cmp	x0, #CurrentEL_EL2
	b.eq	init_el2

SYM_INNER_LABEL(init_el1, SYM_L_LOCAL)
	mov_q	x0, INIT_SCTLR_EL1_MMU_OFF ///设置大小端
	msr	sctlr_el1, x0
	isb                                ///刷新流水线
	mov_q	x0, INIT_PSTATE_EL1        ///屏蔽外部中断信号
	msr	spsr_el1, x0
	msr	elr_el1, lr                    ///设置el1返回地址
	mov	w0, #BOOT_CPU_MODE_EL1         ///返回值，ARM64当前运行等级el1 
	eret

SYM_INNER_LABEL(init_el2, SYM_L_LOCAL)
	mov_q	x0, HCR_HOST_NVHE_FLAGS
	msr	hcr_el2, x0
	isb

	init_el2_state

	/* Hypervisor stub */
	adr_l	x0, __hyp_stub_vectors
	msr	vbar_el2, x0
	isb

	mov_q	x1, INIT_SCTLR_EL1_MMU_OFF

	/*
	 * Fruity CPUs seem to have HCR_EL2.E2H set to RES1,
	 * making it impossible to start in nVHE mode. Is that
	 * compliant with the architecture? Absolutely not!
	 */
	mrs	x0, hcr_el2
	and	x0, x0, #HCR_E2H
	cbz	x0, 1f

	/* Set a sane SCTLR_EL1, the VHE way */
	msr_s	SYS_SCTLR_EL12, x1
	mov	x2, #BOOT_CPU_FLAG_E2H
	b	2f

1:
	msr	sctlr_el1, x1
	mov	x2, xzr
2:
	msr	elr_el2, lr
	mov	w0, #BOOT_CPU_MODE_EL2
	orr	x0, x0, x2
	eret
SYM_FUNC_END(init_kernel_el)

/*
 * Sets the __boot_cpu_mode flag depending on the CPU boot mode passed
 * in w0. See arch/arm64/include/asm/virt.h for more info.
 */
SYM_FUNC_START_LOCAL(set_cpu_boot_mode_flag)
	adr_l	x1, __boot_cpu_mode   ///全局变量，存放本地CPU执行等级
	cmp	w0, #BOOT_CPU_MODE_EL2
	b.ne	1f
///EL2,存放在__boot_cpu_mode[1]
	add	x1, x1, #4
// This CPU has booted in EL1  ///w0为init_kernel_el函数返回的当前CPU异常等级
1:	str	w0, [x1]			// Save CPU boot mode
	ret
SYM_FUNC_END(set_cpu_boot_mode_flag)

	/*
	 * This provides a "holding pen" for platforms to hold all secondary
	 * cores are held until we're ready for them to initialise.
	 */
SYM_FUNC_START(secondary_holding_pen)
	bl	init_kernel_el			// w0=cpu_boot_mode
	mrs	x2, mpidr_el1
	mov_q	x1, MPIDR_HWID_BITMASK
	and	x2, x2, x1
	adr_l	x3, secondary_holding_pen_release
pen:	ldr	x4, [x3]
	cmp	x4, x2
	b.eq	secondary_startup
	wfe
	b	pen
SYM_FUNC_END(secondary_holding_pen)

	/*
	 * Secondary entry point that jumps straight into the kernel. Only to
	 * be used where CPUs are brought online dynamically by the kernel.
	 */
SYM_FUNC_START(secondary_entry)
	bl	init_kernel_el			// w0=cpu_boot_mode
	b	secondary_startup
SYM_FUNC_END(secondary_entry)

SYM_FUNC_START_LOCAL(secondary_startup)
	/*
	 * Common entry point for secondary CPUs.
	 */
	mov	x20, x0				// preserve boot mode
	bl	finalise_el2
	bl	__cpu_secondary_check52bitva
#if VA_BITS > 48
	ldr_l	x0, vabits_actual
#endif
	bl	__cpu_setup			// initialise processor
	adrp	x1, swapper_pg_dir
	adrp	x2, idmap_pg_dir
	bl	__enable_mmu
	ldr	x8, =__secondary_switched
	br	x8
SYM_FUNC_END(secondary_startup)

SYM_FUNC_START_LOCAL(__secondary_switched)
	mov	x0, x20
	bl	set_cpu_boot_mode_flag
	str_l	xzr, __early_cpu_boot_status, x3
	adr_l	x5, vectors
	msr	vbar_el1, x5
	isb

	adr_l	x0, secondary_data
	ldr	x2, [x0, #CPU_BOOT_TASK]
	cbz	x2, __secondary_too_slow

	init_cpu_task x2, x1, x3

#ifdef CONFIG_ARM64_PTR_AUTH
	ptrauth_keys_init_cpu x2, x3, x4, x5
#endif

	bl	secondary_start_kernel
	ASM_BUG()
SYM_FUNC_END(__secondary_switched)

SYM_FUNC_START_LOCAL(__secondary_too_slow)
	wfe
	wfi
	b	__secondary_too_slow
SYM_FUNC_END(__secondary_too_slow)

/*
 * The booting CPU updates the failed status @__early_cpu_boot_status,
 * with MMU turned off.
 *
 * update_early_cpu_boot_status tmp, status
 *  - Corrupts tmp1, tmp2
 *  - Writes 'status' to __early_cpu_boot_status and makes sure
 *    it is committed to memory.
 */

	.macro	update_early_cpu_boot_status status, tmp1, tmp2
	mov	\tmp2, #\status
	adr_l	\tmp1, __early_cpu_boot_status
	str	\tmp2, [\tmp1]
	dmb	sy
	dc	ivac, \tmp1			// Invalidate potentially stale cache line
	.endm

/*
 * Enable the MMU.
 *
 *  x0  = SCTLR_EL1 value for turning on the MMU.
 *  x1  = TTBR1_EL1 value
 *  x2  = ID map root table address
 *
 * Returns to the caller via x30/lr. This requires the caller to be covered
 * by the .idmap.text section.
 *
 * Checks if the selected granule size is supported by the CPU.
 * If it isn't, park the CPU
 */
SYM_FUNC_START(__enable_mmu)
	mrs	x3, ID_AA64MMFR0_EL1
	ubfx	x3, x3, #ID_AA64MMFR0_EL1_TGRAN_SHIFT, 4
	cmp     x3, #ID_AA64MMFR0_EL1_TGRAN_SUPPORTED_MIN
	b.lt    __no_granule_support
	cmp     x3, #ID_AA64MMFR0_EL1_TGRAN_SUPPORTED_MAX
	b.gt    __no_granule_support
	phys_to_ttbr x2, x2
	msr	ttbr0_el1, x2			// load TTBR0
// load TTBR1   //填充两个页表基地址到TTBR0,TTBR1
	load_ttbr1 x1, x1, x3

	set_sctlr_el1	x0          //填充M域，使能MMU

	ret
SYM_FUNC_END(__enable_mmu)

SYM_FUNC_START(__cpu_secondary_check52bitva)
#if VA_BITS > 48
	ldr_l	x0, vabits_actual
	cmp	x0, #52
	b.ne	2f

	mrs_s	x0, SYS_ID_AA64MMFR2_EL1
	and	x0, x0, #(0xf << ID_AA64MMFR2_EL1_VARange_SHIFT)
	cbnz	x0, 2f

	update_early_cpu_boot_status \
		CPU_STUCK_IN_KERNEL | CPU_STUCK_REASON_52_BIT_VA, x0, x1
1:	wfe
	wfi
	b	1b

#endif
2:	ret
SYM_FUNC_END(__cpu_secondary_check52bitva)

SYM_FUNC_START_LOCAL(__no_granule_support)
	/* Indicate that this CPU can't boot and is stuck in the kernel */
	update_early_cpu_boot_status \
		CPU_STUCK_IN_KERNEL | CPU_STUCK_REASON_NO_GRAN, x1, x2
1:
	wfe
	wfi
	b	1b
SYM_FUNC_END(__no_granule_support)

#ifdef CONFIG_RELOCATABLE
SYM_FUNC_START_LOCAL(__relocate_kernel)
	/*
	 * Iterate over each entry in the relocation table, and apply the
	 * relocations in place.
	 */
	adr_l	x9, __rela_start
	adr_l	x10, __rela_end
	mov_q	x11, KIMAGE_VADDR		// default virtual offset
	add	x11, x11, x23			// actual virtual offset

0:	cmp	x9, x10
	b.hs	1f
	ldp	x12, x13, [x9], #24
	ldr	x14, [x9, #-8]
	cmp	w13, #R_AARCH64_RELATIVE
	b.ne	0b
	add	x14, x14, x23			// relocate
	str	x14, [x12, x23]
	b	0b

1:
#ifdef CONFIG_RELR
	/*
	 * Apply RELR relocations.
	 *
	 * RELR is a compressed format for storing relative relocations. The
	 * encoded sequence of entries looks like:
	 * [ AAAAAAAA BBBBBBB1 BBBBBBB1 ... AAAAAAAA BBBBBB1 ... ]
	 *
	 * i.e. start with an address, followed by any number of bitmaps. The
	 * address entry encodes 1 relocation. The subsequent bitmap entries
	 * encode up to 63 relocations each, at subsequent offsets following
	 * the last address entry.
	 *
	 * The bitmap entries must have 1 in the least significant bit. The
	 * assumption here is that an address cannot have 1 in lsb. Odd
	 * addresses are not supported. Any odd addresses are stored in the RELA
	 * section, which is handled above.
	 *
	 * Excluding the least significant bit in the bitmap, each non-zero
	 * bit in the bitmap represents a relocation to be applied to
	 * a corresponding machine word that follows the base address
	 * word. The second least significant bit represents the machine
	 * word immediately following the initial address, and each bit
	 * that follows represents the next word, in linear order. As such,
	 * a single bitmap can encode up to 63 relocations in a 64-bit object.
	 *
	 * In this implementation we store the address of the next RELR table
	 * entry in x9, the address being relocated by the current address or
	 * bitmap entry in x13 and the address being relocated by the current
	 * bit in x14.
	 */
	adr_l	x9, __relr_start
	adr_l	x10, __relr_end

2:	cmp	x9, x10
	b.hs	7f
	ldr	x11, [x9], #8
	tbnz	x11, #0, 3f			// branch to handle bitmaps
	add	x13, x11, x23
	ldr	x12, [x13]			// relocate address entry
	add	x12, x12, x23
	str	x12, [x13], #8			// adjust to start of bitmap
	b	2b

3:	mov	x14, x13
4:	lsr	x11, x11, #1
	cbz	x11, 6f
	tbz	x11, #0, 5f			// skip bit if not set
	ldr	x12, [x14]			// relocate bit
	add	x12, x12, x23
	str	x12, [x14]

5:	add	x14, x14, #8			// move to next bit's address
	b	4b

6:	/*
	 * Move to the next bitmap's address. 8 is the word size, and 63 is the
	 * number of significant bits in a bitmap entry.
	 */
	add	x13, x13, #(8 * 63)
	b	2b

7:
#endif
	ret

SYM_FUNC_END(__relocate_kernel)
#endif

SYM_FUNC_START_LOCAL(__primary_switch)
	adrp	x1, reserved_pg_dir
	adrp	x2, init_idmap_pg_dir
///参数x0->SCTLR_EL1,x1->init_pg_dir页表基地址，开启MMU
	bl	__enable_mmu
///配置重新映射内核镜像
#ifdef CONFIG_RELOCATABLE
	adrp	x23, KERNEL_START
	and	x23, x23, MIN_KIMG_ALIGN - 1
#ifdef CONFIG_RANDOMIZE_BASE
	mov	x0, x22
	adrp	x1, init_pg_end
	mov	sp, x1
	mov	x29, xzr
	bl	__pi_kaslr_early_init
	and	x24, x0, #SZ_2M - 1		// capture memstart offset seed
	bic	x0, x0, #SZ_2M - 1
	orr	x23, x23, x0			// record kernel offset
#endif
#endif
	bl	clear_page_tables
	bl	create_kernel_mapping

	adrp	x1, init_pg_dir
	load_ttbr1 x1, x1, x2
#ifdef CONFIG_RELOCATABLE
	bl	__relocate_kernel
#endif
	ldr	x8, =__primary_switched
	adrp	x0, KERNEL_START		// __pa(KERNEL_START)
///实现重映射
	br	x8
SYM_FUNC_END(__primary_switch)

