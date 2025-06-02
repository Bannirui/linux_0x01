/*
 *  head.s contains the 32-bit startup code.
 *
 * NOTE!!! Startup happens at absolute address 0x00000000, which is also where
 * the page directory will exist. The startup code will be overwritten by
 * the page directory.
 */
.text
.globl _idt,_gdt,_pg_dir
_pg_dir:
startup_32:
	# 0x10=0B 0001 0000 低3位是000 高13位是0X10 也就是到GDT表检索脚标是2的段描述符 找到数据段
	# 让ds es fs gs这几个寄存器的段选择子指向数据段描述符
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	mov %ax,%fs
	mov %ax,%gs
	# lss指令让ss:esp这个指针指向_stack_start标号位置
	lss _stack_start,%esp
	# 设置中断描述符表
	call setup_idt
	# 设置全局描述符表
	call setup_gdt
	# 那么为什么要重建idt表和gdt表呢 因为系统代码已经被搬到了0地址上 而此时cpu寄存器的idtr和gdtr都还指向在0x90200高地址上
	# 所以这个地方重建的目的就是为了让idt表和gdt表都搬到0低地址空间上
	# 下面又重新设置段寄存器的段选择子是什么意思 因为上面修改了全局描述符表 所以这个地方要重新设置一遍刷新后才能生效
	movl $0x10,%eax		# reload all the segment registers
	mov %ax,%ds		# after changing gdt. CS was already
	mov %ax,%es		# reloaded in 'setup_gdt'
	mov %ax,%fs
	mov %ax,%gs
	lss _stack_start,%esp
	xorl %eax,%eax
1:	incl %eax		# check that A20 really IS enabled
	movl %eax,0x000000
	cmpl %eax,0x100000
	je 1b
	movl %cr0,%eax		# check math chip
	andl $0x80000011,%eax	# Save PG,ET,PE
	testl $0x10,%eax
	jne 1f			# ET is set - 387 is present
	orl $4,%eax		# else set emulate bit
1:	movl %eax,%cr0
	jmp after_page_tables

/*
 *  setup_idt
 *
 *  sets up a idt with 256 entries pointing to
 *  ignore_int, interrupt gates. It then loads
 *  idt. Everything that wants to install itself
 *  in the idt-table may do so themselves. Interrupts
 *  are enabled elsewhere, when we can be relatively
 *  sure everything is ok. This routine will be over-
 *  written by the page tables.
 */
/*
 * 设置中断描述符表
 * 中断描述符表总共有256个中断描述符 每个描述符中的中断程序例程都指向了ignore_int的函数地址
 * ignore_int这个函数地址是默认的中断处理程序 后面会慢慢被具体的中断程序所覆盖
 */
setup_idt:
	lea ignore_int,%edx
	movl $0x00080000,%eax
	movw %dx,%ax		/* selector = 0x0008 = cs */
	movw $0x8E00,%dx	/* interrupt gate - dpl=0, present */

	lea _idt,%edi
	mov $256,%ecx
rp_sidt:
	movl %eax,(%edi)
	movl %edx,4(%edi)
	addl $8,%edi
	dec %ecx
	jne rp_sidt
	lidt idt_descr
	ret

/*
 *  setup_gdt
 *
 *  This routines sets up a new gdt and loads it.
 *  Only two entries are currently built, the same
 *  ones that were built in init.s. The routine
 *  is VERY complicated at two whole lines, so this
 *  rather long comment is certainly needed :-).
 *  This routine will beoverwritten by the page tables.
 */
/*重新设置全局描述符表*/
setup_gdt:
	lgdt gdt_descr
	ret

.org 0x1000
pg0:

.org 0x2000
pg1:

.org 0x3000
pg2:		# This is not used yet, but if you
		# want to expand past 8 Mb, you'll have
		# to use it.

.org 0x4000
after_page_tables:
	pushl $0		# These are the parameters to main :-)
	pushl $0
	pushl $0
	pushl $L6		# return address for main, if it decides to.
	pushl $_main
	jmp setup_paging
L6:
	jmp L6			# main should never return here, but
				# just in case, we know what happens.

/* This is the default interrupt "handler" :-) */
.align 2
ignore_int:
	incb 0xb8000+160		# put something on the screen
	movb $2,0xb8000+161		# so that we know something
	iret				# happened


/*
 * Setup_paging
 *
 * This routine sets up paging by setting the page bit
 * in cr0. The page tables are set up, identity-mapping
 * the first 8MB. The pager assumes that no illegal
 * addresses are produced (ie >4Mb on a 4Mb machine).
 *
 * NOTE! Although all physical memory should be identity
 * mapped by this routine, only the kernel page functions
 * use the >1Mb addresses directly. All "normal" functions
 * use just the lower 1Mb, or the local data space, which
 * will be mapped to some other place - mm keeps track of
 * that.
 *
 * For those with more memory than 8 Mb - tough luck. I've
 * not got it, why should you :-) The source is here. Change
 * it. (Seriously - it shouldn't be too difficult. Mostly
 * change some constants etc. I left it at 8Mb, as my machine
 * even cannot be extended past that (ok, but it was cheap :-)
 * I've tried to show which constants to change by having
 * some kind of marker at them (search for "8Mb"), but I
 * won't guarantee that's all :-( )
 */
.align 2
setup_paging:
	movl $1024*3,%ecx
	xorl %eax,%eax
	xorl %edi,%edi			/* pg_dir is at 0x000 */
	cld;rep;stosl
	movl $pg0+7,_pg_dir		/* set present bit/user r/w */
	movl $pg1+7,_pg_dir+4		/*  --------- " " --------- */
	movl $pg1+4092,%edi
	movl $0x7ff007,%eax		/*  8Mb - 4096 + 7 (r/w user,p) */
	std
1:	stosl			/* fill pages backwards - more efficient :-) */
	subl $0x1000,%eax
	jge 1b
	xorl %eax,%eax		/* pg_dir is at 0x0000 */
	movl %eax,%cr3		/* cr3 - page directory start */
	movl %cr0,%eax
	orl $0x80000000,%eax
	movl %eax,%cr0		/* set paging (PG) bit */
	ret			/* this also flushes prefetch-queue */

.align 2
.word 0
idt_descr:
	.word 256*8-1		# idt contains 256 entries
	.long _idt
.align 2
.word 0
gdt_descr:
    # 全局描述符的结构6个byte 2个byte表示gdt大小 4个byte表示gdt的基址
	.word 256*8-1		# so does gdt (not that that's any
	.long _gdt		# magic number, but it works for me :^)

	.align 3
_idt:	.fill 256,8,0		# idt is uninitialized

# gdt表有256个表项 每个表项8Byte 存放的是描述符 2个空的 1个数据段 1个代码段 252个预留
# 0号 空的
_gdt:	.quad 0x0000000000000000	/* NULL descriptor */
	# 1号 代码段
	.quad 0x00c09a00000007ff	/* 8Mb */
    # 2号 数据段
	.quad 0x00c09200000007ff	/* 8Mb */
	# 3号 空的
	.quad 0x0000000000000000	/* TEMPORARY - don't use */
	# 252个预留的
	.fill 252,8,0			/* space for LDT's and TSS's etc */
