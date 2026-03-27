// SPDX-License-Identifier: GPL-2.0
#include <linux/debugfs.h>
#include <linux/memory_hotplug.h>
#include <linux/seq_file.h>

#include <asm/ptdump.h>

//cat /sys/kernel/debug/kernel_page_tables
///open节点，调用ptdump_walk
static int ptdump_show(struct seq_file *m, void *v)
{
	struct ptdump_info *info = m->private;

	get_online_mems();
	pr_info("---test0.before ptdump_walk\n");
	ptdump_walk(m, info);
	pr_info("---test0.after ptdump_walk\n");
	put_online_mems();
	return 0;
}
/// 定义了ptdump_fops, 关联ptdump_show 
DEFINE_SHOW_ATTRIBUTE(ptdump);

void __init ptdump_debugfs_register(struct ptdump_info *info, const char *name)
{
	/// 注册了 debugfs 节点
	debugfs_create_file(name, 0400, NULL, info, &ptdump_fops);
}
