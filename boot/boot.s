|
|	boot.s
|
| boot.s is loaded at 0x7c00 by the bios-startup routines, and moves itself
| out of the way to address 0x90000, and jumps there.
|
| It then loads the system at 0x10000, using BIOS interrupts. Thereafter
| it disables all interrupts, moves the system down to 0x0000, changes
| to protected mode, and calls the start of system. System then must
| RE-initialize the protected mode in it's own tables, and enable
| interrupts as needed.
|
| NOTE! currently system is at most 8*65536 bytes long. This should be no
| problem, even in the future. I want to keep it simple. This 512 kB
| kernel size should be enough - in fact more would mean we'd have to move
| not just these start-up routines, but also do something about the cache-
| memory (block IO devices). The area left over in the lower 640 kB is meant
| for these. No other memory is assumed to be "physical", ie all memory
| over 1Mb is demand-paging. All addresses under 1Mb are guaranteed to match
| their physical addresses.
|
| NOTE1 abouve is no longer valid in it's entirety. cache-memory is allocated
| above the 1Mb mark as well as below. Otherwise it is mainly correct.
|
| NOTE 2! The boot disk type must be set at compile-time, by setting
| the following equ. Having the boot-up procedure hunt for the right
| disk type is severe brain-damage.
| The loader has been made as simple as possible (had to, to get it
| in 512 bytes with the code to move to protected mode), and continuos
| read errors will result in a unbreakable loop. Reboot by hand. It
| loads pretty fast by getting whole sectors at a time whenever possible.

| 启动盘总共有多少扇区内容
| 1.44Mb disks:
sectors = 18
| 1.2Mb disks:
| sectors = 15
| 720kB disks:
| sectors = 9

.globl begtext, begdata, begbss, endtext, enddata, endbss
.text
begtext:
.data
begdata:
.bss
begbss:
.text

| 启动段
BOOTSEG = 0x07c0
| 初始化段
INITSEG = 0x9000
| 系统段
SYSSEG  = 0x1000			| system loaded at 0x10000 (65536).
ENDSEG	= SYSSEG + SYSSIZE

| BIOS已经把启动盘第一扇区代码加载到了内存0x007c00 并且cpu也跳过去了
| 现在cs=0x07c0 ip=0
| Boot Segment启动段代码开始工作
entry start
| 重复movw指令直到cx为0 一个word是2Byte 也就是复制512Byte
| 启动段代码自己把自己从0x07c00搬到0x90000 跳到高地址执行
start:
	mov	ax,#BOOTSEG
	mov	ds,ax
	mov	ax,#INITSEG
	mov	es,ax
	mov	cx,#256
	sub	si,si
	sub	di,di
	| 重复执行movw
	| 每搬完一次数据就si+=2 di+=2
	| cx-=1直到cx为0
	rep
	| movw的作用是搬运2Byte ds:si->es:di
	| mov只复制一次时si跟di寄存器值不会步进值自增 只有搭配rep指令时才会自增
	movw
	| 执行到这时Boot Segment代码已经被拷贝到了0x90000处了并且代码的复制功能已经执行完了 要跳到高地址地方继续执行
	jmpi	go,INITSEG
| 执行到这此时CS是0x9000
| 初始化各个段寄存器ds es ss和sp
go:	mov	ax,cs
	mov	ds,ax
	mov	es,ax
	mov	ss,ax
	| 栈基地址0x9000 栈顶指针0x400 这个地方规划栈空间预留了1024K的大小
	| 栈指针增长方向是向低地址空间 入栈sp减小 出栈sp增加
	| 从0x9000:0->0x9000:0x400地址空间就是栈空间
	mov	sp,#0x400		| arbitrary value >>512

    | 通过BIOS中断拿到光标位置
    | AH设置int 0x10功能号 读取光标位置 位置行列都是0-based 行号返回到DH 列号返回到DL
    | 这个地方读取光标坐标的用途是下面要输出字符串 输出字符串的光标就是现在获取到的
	mov	ah,#0x03	| read cursor pos
	| BH是int 0x10的参数 指定显示页 0表示使用默认的显示页
	xor	bh,bh
	int	0x10

	| 通过BIOS中断打印字符串
	| 要显示的字符串长度24
	mov	cx,#24
	| BH指定页码
	| BL指定属性
	mov	bx,#0x0007	| page 0, attribute 7 (normal)
	| 要显示的字符串地址 ES:BP 现在es已经是0x9000了 只要指定段内偏移量就行了
	mov	bp,#msg1
	| AH功能号0x13
	| AL显示方式0x01
	mov	ax,#0x1301	| write string, move cursor
	int	0x10

| ok, we've written the message, now
| we want to load the system (at 0x10000)
    | es段寄存器=0x1000 下面会把磁盘中除了第一个扇区之外的其他扇区的代码加载到0x10000地方
	mov	ax,#SYSSEG
	mov	es,ax		| segment of 0x010000
	| 读盘把内核代码临时放在0x1000:0x00上
	call	read_it
	call	kill_motor

| if the read went well we get current cursor position ans save it for
| posterity.

	mov	ah,#0x03	| read cursor pos
	xor	bh,bh
	int	0x10		| save it in known place, con_init fetches
	mov	[510],dx	| it from 0x90510.
		
| now we want to move to protected mode ...

    | 禁用掉CPU的中断响应
	cli			| no interrupts allowed !

| first we move the system to it's rightful place

	mov	ax,#0x0000
	cld			| 'direction'=0, movs moves forward
do_move:
    | es=0x1000
	mov	es,ax		| destination segment
	add	ax,#0x1000
	cmp	ax,#0x9000
	jz	end_move
	mov	ds,ax		| source segment
	sub	di,di
	sub	si,si
	mov 	cx,#0x8000
	rep
	movsw
	j	do_move

| then we load the segment descriptors

end_move:

	mov	ax,cs		| right, forgot this at first. didn't work :-)
	mov	ds,ax
	lidt	idt_48		| load idt with 0,0
	lgdt	gdt_48		| load gdt with whatever appropriate

| that was painless, now we enable A20

	call	empty_8042
	mov	al,#0xD1		| command write
	out	#0x64,al
	call	empty_8042
	mov	al,#0xDF		| A20 on
	out	#0x60,al
	call	empty_8042

| well, that went ok, I hope. Now we have to reprogram the interrupts :-(
| we put them right after the intel-reserved hardware interrupts, at
| int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
| messed this up with the original PC, and they haven't been able to
| rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
| which is used for the internal hardware interrupts as well. We just
| have to reprogram the 8259's, and it isn't fun.

	mov	al,#0x11		| initialization sequence
	out	#0x20,al		| send it to 8259A-1
	.word	0x00eb,0x00eb		| jmp $+2, jmp $+2
	out	#0xA0,al		| and to 8259A-2
	.word	0x00eb,0x00eb
	mov	al,#0x20		| start of hardware int's (0x20)
	out	#0x21,al
	.word	0x00eb,0x00eb
	mov	al,#0x28		| start of hardware int's 2 (0x28)
	out	#0xA1,al
	.word	0x00eb,0x00eb
	mov	al,#0x04		| 8259-1 is master
	out	#0x21,al
	.word	0x00eb,0x00eb
	mov	al,#0x02		| 8259-2 is slave
	out	#0xA1,al
	.word	0x00eb,0x00eb
	mov	al,#0x01		| 8086 mode for both
	out	#0x21,al
	.word	0x00eb,0x00eb
	out	#0xA1,al
	.word	0x00eb,0x00eb
	mov	al,#0xFF		| mask off all interrupts for now
	out	#0x21,al
	.word	0x00eb,0x00eb
	out	#0xA1,al

| well, that certainly wasn't fun :-(. Hopefully it works, and we don't
| need no steenking BIOS anyway (except for the initial loading :-).
| The BIOS-routine wants lots of unnecessary data, and it's less
| "interesting" anyway. This is how REAL programmers do it.
|
| Well, now's the time to actually move into protected mode. To make
| things as simple as possible, we do no register set-up or anything,
| we let the gnu-compiled 32-bit programs do that. We just jump to
| absolute address 0x00000, in 32-bit protected mode.

	mov	ax,#0x0001	| protected mode (PE) bit
	lmsw	ax		| This is it!
	jmpi	0,8		| jmp offset 0 of segment 8 (cs)

| This routine checks that the keyboard command queue is empty
| No timeout is used - if this hangs there is something wrong with
| the machine, and we probably couldn't proceed anyway.
empty_8042:
	.word	0x00eb,0x00eb
	in	al,#0x64	| 8042 status port
	test	al,#2		| is input buffer full?
	jnz	empty_8042	| yes - loop
	ret

| This routine loads the system at address 0x10000, making sure
| no 64kB boundaries are crossed. We try to load it as fast as
| possible, loading whole tracks whenever we can.
|
| in:	es - starting address segment (normally 0x1000)
|
| This routine has to be recompiled to fit another drive type,
| just change the "sectors" variable at the start of the file
| (originally 18, for a 1.44Mb drive)
|
| 启动盘第一个扇区内容就是当前代码 是由BIOS负责加载到内存的 也就是说当前程序执行的时候已经意味着有一个扇区内容加载完成了 1-based
sread:	.word 1			| sectors read of current track
head:	.word 0			| current head
| 读盘时的柱面
track:	.word 0			| current track

| 函数read_it 把磁盘里面的内核程序代码读到了内存 临时放在0x1000:0x00的地方
| 入参 ES ES:BX是BIOS中断程序读盘后将内容放到的缓冲区地址
read_it:
	mov ax,es
	| 参数校验 ES是入参0x1000 这行代码是保证地址4KB对齐 如果地址没有对齐就会陷入死循环
	| 看看低12位 test不改变值 低12位按位与结果是0 ZF标志位就打上1
	test ax,#0x0fff
	| 一旦ZF是1 jne(jump not equals zero)就会生效进行跳转
die:	jne die			| es must be at 64kB boundary
    | bx清0 为什么要清0 下面会计算出启动盘总共要加载多少代码到内存
    | 因为此时还在16位实模式下 也就是段空间最大就是(0xFFFF-0+1)个Byte 64KB
    | 所以要保证加载的代码不要撑爆段空间
    | 怎么判断呢 扇区代码量+0看看会不会进位
    | 并且BIOS中断程序把磁盘内容放到内存后会通过ES:BX告诉我们缓冲区地址
	xor bx,bx		| bx is starting address within segment
rp_read:
	mov ax,es
	cmp ax,#ENDSEG		| have we loaded all yet?
	| jb指令 cmp比较ax<#ENDSEG就执行jb跳转 也就是需要进行读盘
	jb ok1_read
	ret
ok1_read:
    | 总共sectors个扇区 已经加载了sread个扇区 还剩(sectors-sread)个扇区要加载
	mov ax,#sectors
	| AX中保存了要读多少个扇区
	sub ax,sread
	| CX=要读多少个扇区
	mov cx,ax
	| 每个扇区512Byte CX=计算出还要加载多少字节
	shl cx,#9
	| 上面已经提前把bx置0了 这个地方相加 通过看CF位判断出是不是溢出进位了 并没有真正改变两个寄存器的值
	add cx,bx
	| CF=0 没有产生进位
	jnc ok2_read
	| ZF=1执行跳转
	je ok2_read
	xor ax,ax
	sub ax,bx
	shr ax,#9
| 发起真正的读盘 把代码加载到内存
| 入参 AX=要读多少个扇区
|     BX=ES:BX=缓冲区地址
|     CX=要读多少Byte内容
ok2_read:
	call read_track
	| 发起中断调用读盘后 AX寄存器中依然保存着中断调用的入参=要读多少个扇区
	mov cx,ax
	| sread是已经读完的最后一个扇区号 1-based 也就是已经读了多少个扇区
	add ax,sread
	| 已经读了的扇区数量+这次读的扇区数 vs 总扇区数 看一下ZF寄存器就知道磁盘有没有读完 两个值相等ZF被设置成1
	cmp ax,#sectors
	| 上面中断调用读盘没有读完 继续磁
	jne ok3_read
	mov ax,#1
	sub ax,head
	jne ok4_read
	inc track
ok4_read:
	mov head,ax
	xor ax,ax
ok3_read:
	mov sread,ax
	shl cx,#9
	add bx,cx
	jnc rp_read
	mov ax,es
	add ax,#0x1000
	mov es,ax
	xor bx,bx
	jmp rp_read

| 定义一个函数 发起真正的读盘行为
| 入参 AX=要从磁盘读多少个扇区read_track
|     BX=ES:BX=缓冲区地址
|     CX=要从磁盘读多少Byte内容
read_track:
	push ax
	push bx
	push cx
	push dx
	| ch=track的低8位=柱面号
	mov dx,track
	mov cx,sread
	| CL=要读的扇区号
	inc cx
	mov ch,dl
	| dh=head的低8位=磁头号
	mov dx,head
	mov dh,dl
	| dl=驱动器号=0表示软盘
	mov dl,#0
	and dx,#0x0100
	mov ah,#2
	| 13号中断调用功能号AH=0x02
	int 0x13
	| 出参 CF=0表示成功 CF不等于0说明异常
	jc bad_rt
	pop dx
	pop cx
	pop bx
	pop ax
	ret
bad_rt:	mov ax,#0
	mov dx,#0
	int 0x13
	pop dx
	pop cx
	pop bx
	pop ax
	jmp read_track

/*
 * This procedure turns off the floppy drive motor, so
 * that we enter the kernel in a known state, and
 * don't have to worry about it later.
 */
kill_motor:
	push dx
	mov dx,#0x3f2
	mov al,#0
	outb
	pop dx
	ret

gdt:
	.word	0,0,0,0		| dummy

	.word	0x07FF		| 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		| base address=0
	.word	0x9A00		| code read/exec
	.word	0x00C0		| granularity=4096, 386

	.word	0x07FF		| 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		| base address=0
	.word	0x9200		| data read/write
	.word	0x00C0		| granularity=4096, 386

idt_48:
	.word	0			| idt limit=0
	.word	0,0			| idt base=0L

gdt_48:
	.word	0x800		| gdt limit=2048, 256 GDT entries
	.word	gdt,0x9		| gdt base = 0X9xxxx
	
msg1:
	.byte 13,10
	.ascii "Loading system ..."
	.byte 13,10,13,10

.text
endtext:
.data
enddata:
.bss
endbss:
