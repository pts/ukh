;
; ukh.nasm: Universal Kernel Header for memtest86+-5.01
; by pts@fazekas.hu at Mon Mar 17 13:45:39 CET 2025
;
; Compile with: nasm-0.98.39 -O0 -w+orphan-labels -f bin -DMEMTEST86PLUS5 -DMEMTEST86PLUS5_BIN="'memtest86+-5.01-dist.bin'" -o memtest86+.kernel.bin ukh.nasm
; Run it with: qemu-system-i386 -M pc-1.0 -m 4 -nodefault -vga cirrus -kernel memtest86+.kernel.bin
;
; Please note that memtest86+-5.01 needs least 4 MiB of memory in QEMU 2.11.1 (QEMU fails with 3 MiB), hence the `-m 4`.
;
; This header is compatible with the old a new (>=2.00) boot protocol of the
; Linux kernel, and indicates version 2.01 to non-old-protocol Linux bootloaders.
; Linux kernel: https://docs.kernel.org/arch/x86/boot.html
;
; !! Also add compatibility with multiboot 1, switch back to real mode. (Which kernels support multiboot 1, and which bootloaders support it in addition to GRUB?)
;    See also ENTRY(prot_to_real) in grub-0l97_asm.S for switching from 32-bit protected mode to real mode.
;

%macro assert_fofs 1
  times +(%1)-($-$$) times 0 nop
  times -(%1)+($-$$) times 0 nop
%endm


bits 16
cpu 8086

BOOT_SIGNATURE equ 0xaa55

LINUX_CL_MAGIC equ 0xa33f

LOADFLAG_READ:
.HIGH: equ 1 << 0

%macro halt 0
		cli
  %%back:	hlt
		jmp short %%back
%endm

boot_sector:  ; 1 sector of 0x200 bytes. Loaded to 0x9000. GRUB 1 and QEMU load 5 sectors (0xa00 bytes).
.start:		jmp short .code
		times 0x20-($-.start) nop
.cl_magic:	times 2 nop  ; The Linux bootloader will set this to: dw 0xa33f
.cl_offset:	times 2 nop  ; The Linux bootloader will set this to the offset of the kernel command line.

.code:		mov ax, 0xe00+'b'  ; This code will be ignored by `qemu-system-i386 -kernel ...'.
		xor bx, bx
		int 0x10
		mov al, 's'
		int 0x10
		halt

		times 0x1f1-($-.start) db 0
.linux_boot_header:  ; https://docs.kernel.org/arch/x86/boot.html  . Until setup_sectors.linux_boot_header.end.
		assert_fofs 0x1f1
.setup_sects:	db 4  ; (read) The size of the setup in sectors. Must be 4 for compatibility with old-protoocl Linux bootloaders (such as old LILO).
		assert_fofs 0x1f2
.root_flags:	dw 0  ; (read, modify optional) If set, the root is mounted readonly.
		assert_fofs 0x1f4
.syssize_low:	dw (text.end-text+0xf)>>4  ; (read) The low word of size of the 32-bit code in 16-byte paras. Ignored by GRUB 1 or QEMU. Maximum size allowed: 1 MiB, but boot protocol <=2.01 supports zImage only, with its maximum size of 0x9000-0x200*(1+.setup_sects) bytes.
		assert_fofs 0x1f6
.swap_dev:
.syssize_high:	dw 0  ; (read) The high word size of the 32-bit code in 16-byte paras. For boot protocol prior to 2.04, the upper two bytes of the syssize field are unusable, which means the size of a bzImage kernel cannot be determined.
		assert_fofs 0x1f8
.ram_size:	dw 0  ; (kernel internal) DO NOT USE - for bootsect.S use only.
		assert_fofs 0x1fa
.vid_mode:	dw 0  ; (read, modify obligatory) Video mode control.
		assert_fofs 0x1fc
.root_dev:	dw 0  ; (read, modify optional) Default root device number. Neither GRUB 1 nor QEMU 2.11.1 set it. 
		assert_fofs 0x1fe
.boot_flag:	dw BOOT_SIGNATURE  ; (read) 0xaa55 magic number.
		assert_fofs 0x200

setup_sectors:  ; 2 == (.boot_sector.setup_sects) sectors of 0x800 bytes. Loaded to 0x800 bytes to 0x90200. Jumped to `jmp 0x9020:0' in real mode.
.start:		assert_fofs 0x200
.jump:		jmp short .code  ; (read) Jump instruction.
		assert_fofs 0x202
.header:	db 'HdrS'  ; (read) Protocol >=2.00 signature. Magic signature “HdrS”.
		assert_fofs 0x206
.version:	dw 0x201  ; (read) Boot protocol version supported. This is the last one which loads everything under 0xa0000.
		assert_fofs 0x208
.realmode_swtch: dd 0  ; (read, modify optional) Bootloader hook.
		assert_fofs 0x20c
.start_sys_seg: dw 0x1000  ; (read) The load-low segment (0x1000), i.e. linear address >> 4 (obsolete). Ignored by both GRUB 1 0.97 and QEMU 2.11.1. In Linux kernel mode, they don't set root= either, and they don't pass the boot drive (boot_drive, saved_drive, current_drive, is saved_drive the result of `rootnoverify'?) number anywhere. Also GRUB 1 0.97 passes the boot drive in DL in `chainloader' (stage1) mode only.
		assert_fofs 0x20e
.kernel_version: dw .kernel_version_string-setup_sectors  ; (read) Pointer to kernel version string or 0 to indicate no version. Relative to .setup_sectors.
		assert_fofs 0x210
.type_of_loader: db 0  ; (write obligatory) Bootloader identifier.
		assert_fofs 0x211
.loadflags:	db 0  ; Boot protocol option flags. Not specifying LOADFLAG.HIGH, so the the protected-mode code is will be loaded at 0x10000 (.start_sys_seg << 4).
		assert_fofs 0x212
.setup_move_size: dw 0  ; (modify obligatory) Move to high memory size (used with hooks). When using protocol 2.00 or 2.01, if the real mode kernel is not loaded at 0x90000, it gets moved there later in the loading sequence. Fill in this field if you want additional data (such as the kernel command line) moved in addition to the real-mode kernel itself.
		assert_fofs 0x214
.code32_start:	dd 0  ; (modify, optional reloc) Bootloader hook. Unused.
		assert_fofs 0x218
.ramdisk_image: dd 0  ; initrd load address (set by bootloader). 0 (NULL) if no initrd.
		assert_fofs 0x21c
.ramdisk_size: dd 0  ; initrd size (set by bootloader). 0 if no initrd.
		assert_fofs 0x220
.bootsect_kludge: dd 0  ; (kernel internal) DO NOT USE - for bootsect.S use only.
		assert_fofs 0x224
.heap_end_ptr:	dw 0  ; (write obligatory) Free memory after setup end.
		assert_fofs 0x226
.linux_boot_header.end:

%ifdef MEMTEST86PLUS5  ; Tested and works with memtest86+-5.01*.bin and memtest85+5.31b*.bin.

cpu 386

base: equ setup_sectors

KERNELSEG equ 0x1000
INITSEG equ 0x9000  ; We assume that 5*0x200 bytes at boot_sector (including us) have been loaded to linear address INITSEG<<4.
KERNEL_CS equ 0x10
KERNEL_DS equ 0x18

.kernel_version_string: db 'memtest86+-5', 0  ; Can be anywhere in the first 0x800 bytes (setup_sects * 0x200 bytes).
%if $-.start<0x30
		times 0x30-($-.start) db 0  ; QEMU 2.11.1 overwrites some bytes within the .linux_boot_header. Offset 0x30 seems to be the minimum bytes left intact.
%endif
.code:  ; Entry point.
		cli ; no interrupts allowed
		jmp INITSEG:.ck-boot_sector  ; Make `org 0' work. Otherwise CS:IP would remain: 0x9020:.ck-setup_sectors.
.ck:		cld

		; now we want to move to protected mode ...
		mov al, 0x80  ; disable NMI for the bootup sequence
		out 0x70, al

		; The system will move itself to its rightful place.
		; reload the segment registers and the stack since the 
		; APs also execute this code
		mov ax, INITSEG
		mov ds, ax
		mov es, ax
		mov ss, ax  ; reset the stack to INITSEG:0x4000-12.
		mov sp, setup_stack+0x200-boot_sector
		push cs
		pop ds
		lidt [idt_48-boot_sector]  ; load idt with 0,0
		lgdt [gdt_48-boot_sector]  ; load gdt with whatever appropriate

		; that was painless, now we enable A20
		; start from grub-a20.patch
		;
		; try to switch gateA20 using PORT92, the "Fast A20 and Init"
		; register
		mov dx, 0x92
		in al, dx
		; skip the port92 code if it's unimplemented (read returns 0xff)
		cmp al, 0xff
		jz short alt_a20_done

		; set or clear bit1, the ALT_A20_GATE bit
		mov ah, [esp+4]
		test ah, ah
		jz short alt_a20_cont1
		or al, 2
		jmp short alt_a20_cont2
alt_a20_cont1:
		and al, 0xfd

		; clear the INIT_NOW bit; don't accidently reset the machine
alt_a20_cont2:
		and al, 0xfe
		out dx, al

alt_a20_done:
		; end from grub-a20.patch
		call empty_8042

		mov al, 0xd1  ; command write
		out 0x64, al
		call empty_8042 

		mov al, 0xdf  ; A20 on
		out 0x60, al
		call empty_8042

		; Note that the short jump isn't strictly needed, althought there are
		; reasons why it might be a good idea. It won't hurt in any case.
		mov ax, 0x0001  ; protected mode (PE) bit
		lmsw ax  ; This is it;
		jmp short .flush_instr
.flush_instr:	mov ax, KERNEL_DS
		mov ds, ax
		mov es, ax
		mov ss, ax
		mov fs, ax
		mov gs, ax
		dw 0xea66, (KERNELSEG<<4)&0xffff, (KERNELSEG<<4)>>16, KERNEL_CS  ; 32bit ljmp KERNEL_CS:(KERNELSEG<<4)

		; This routine checks that the keyboard command queue is empty
		; (after emptying the output buffers)
		;
		; No timeout is used - if this hangs there is something wrong with
		; the machine, and we probably couldn't proceed anyway.
empty_8042:	call delay
		in al, 0x64  ; 8042 status port
		cmp al, 0xff  ; from grub-a20-patch, skip if not impl
		je short .ret
		test al, 1  ; output buffer?
		jz short .no_output
		call delay
		in al, 0x60  ; read it
		jmp short empty_8042
.no_output:	test al, 2  ; is input buffer full?
		jnz short empty_8042  ; yes - loop
.ret:		ret

;
; Delay is needed after doing i/o
;
delay:		jmp short .next
.next:		ret

gdt:		dw 0,0,0,0  ; Segment 0. Dummy.
		dw 0,0,0,0  ; Segment 8. Unused.

		; KERNEL_CS == segment 0x10.
		dw 0x7fff  ; limit 128mb
		dw 0x0000  ; base address=0
		dw 0x9a00  ; code read/exec
		dw 0x00c0  ; granularity=4096, 386

		; KERNEL_CS == segment 0x18.
		dw 0x7fff  ; limit 128mb
		dw 0x0000  ; base address=0
		dw 0x9200  ; data read/write
		dw 0x00c0  ; granularity=4096, 386
.end:

idt_48:		dw 0  ; idt limit=0
		dd 0  ; idt base=0L

gdt_48:		dw gdt.end-gdt-1
		dd (INITSEG<<4)+gdt-boot_sector  ; gdt base = 0X9xxxx; !! Do we have to relocate this?

		times 4*0x200-($-setup_sectors) db 0  ; Omit these bytes, do two `rep movsd's instead.
		assert_fofs 0xa00
setup_stack:

text:		; 32-bit kernel code (zImage, maximum 512 KiB), but it can be anything. Loaded to 0x10000.
		;incbin 'memtest86+-5.01-dist.bin', 0xa00  ; Works.
		incbin 'memtest86+-5.31b-dist.bin', 0xa00  ; Works.

.end:

%else
.kernel_version_string: db 'kernel1', 0  ; Can be anywhere in the first 0x800 bytes (setup_sects * 0x200 bytes).
		times 0x30-($-.start) db 0  ; QEMU 2.11.1 overwrites some bytes within the .linux_boot_header. Offset 0x30 seems to be the minimum bytes left intact.
.char:		db 'k'  ; Preserved.
.code:		; QEMU 2.11.1 sets DL=0, no way to communicate the root device. !! try root=? !! What does GRUB 1 pass?
		; These are already set by QEMU 2.11.1. !! Try from GRUB.
		;mov ax, 0x9000
		;mov ds, ax
		;mov es, ax
		;mov ss, ax
		jmp 0x9000:.ck-boot_sector  ; Make `org 0' work. Otherwise CS:IP would remain: 0x9020:.ck-setup_sectors.
.ck:		cld
		sti
		mov ax, 0xe00 + 'e'
		xor bx, bx
		int 0x10  ; Print character AL to console.

		mov ax, 0x1000
		mov es, ax
		mov al, [es:0]  ; 'T' in text.
		mov ah, 0xe
		xor bx, bx
		int 0x10  ; Print character AL to console.

		xor bx, bx
		mov ah, 0xe
		mov al, [.char]  ; 'C'.
		int 0x10
		mov al, [.sector1]  ; '1'.
		int 0x10  ; Print character AL to console.
		mov al, [.sector2]  ; '2'.
		int 0x10  ; Print character AL to console.
		mov al, [.sector3]  ; '3'.
		int 0x10  ; Print character AL to console.
		cmp word [boot_sector.cl_magic], LINUX_CL_MAGIC
		jne .halt
		;mov al, [0xa001]
		mov si, [boot_sector.cl_offset]
.next:		lodsb
		test al, al
		jz short .printed
		int 0x10  ; Print character AL to console.
		jmp short .next
.printed:	mov al, '.'
		int 0x10

.halt:		halt

		times 0x200-($-.start) db 0
.sector1:	db '1'
		times 0x200-($-.sector1) db 0
.sector2:	db '2'
		times 0x200-($-.sector2) db 0
.sector3:	db '3'
		times 0x200-($-.sector3) db 0
		assert_fofs 0xa00

text:		; (Should be) 32-bit kernel code (zImage, maximum 512 KiB), but it can be anything. Loaded to 0x10000.
		db 'T'
.end:
%endif
