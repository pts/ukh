;
; ukh.nasm: Universal Kernel Header for memtest86+-5.01
; by pts@fazekas.hu at Mon Mar 17 13:45:39 CET 2025
;
; Compile with: nasm-0.98.39 -O0 -w+orphan-labels -f bin -DMEMTEST86PLUS5 -DMEMTEST86PLUS5_BIN="'memtest86+-5.01-dist.bin'" -o memtest86+.kernel.bin ukh.nasm
; Run it with: qemu-system-i386 -M pc-1.0 -m 4 -nodefault -vga cirrus -kernel memtest86+.kernel.bin
;
; Please note that memtest86+-5.01 needs least 4 MiB of memory in QEMU 2.11.1 (QEMU fails with 3 MiB), hence the `-m 4`.
;
; !! Make the 4 setup sectors shorter, *rep movsd* code and data around. We have to keep .setup_sects == 4, for compatibility with the Linux kerenel old protocol.
; !! Compress the 32-bit payload (better than liigboot 16-bit UPX memtest.bs). `upxbc --flat32` compression is better than `upcbc --flat16`, but *flat32* fails to boot. !! Why? Is it because of ESP? !! Currently memtest86+.lzma.kernel.bin doesn't work.
;
; The Universal Kernel Header emitted by this file supports multiple load protocols:
;
; * Linux kernel old (<2.00) protocol: Load first 4 sectors (4*0x200 bytes) to 0x90000, load remaining sectors to 0x10000, don't store the the BIOS drive number anywhere, jump to 0x:9020:0 (file offset 0x200). There are some Linux-specific header fields in file offset range 0x1f1...0x230, including BOOT_SIGNATURE. It can receive a command line.
; * Linux kernel protocol version 2.01: This implementation simulates the old protocol, but specifies more headers so that QEMU 2.11.1 is able to load it with `qemu-system-i386 -kernel`. There are some Linux-specific header fields in file byte range 0x1f1...0x230, including BOOT_SIGNATURE. It can receive a command line.
; * !! bs (GRUB chainloader, SYSLINUX boot): load entire kernel file (not only the first sector) to 0x7c00, set DL to the BIOS drive number, jump to 0:0x7c00. The BOOT_SIGNATURE in file offset range 0x1fe...0x200 is needed by GRUB 1 0.97 `chainloader`, but not `chainloader --force`. It can't receive a command line.
; * !! FreeDOS and SvarDOS kernel.sys: load kernel file to 0x600, set BL to BIOS drive number, make one SS:BP (FreeDOS for the command line, between SS:SP (smaller) and SS:BP) and DS:BP (SvarDOS for .hidden_sector_count) point to the boot sector (we don't care), jump to 0x60:0. No header fields used. Both FreeDOS 1.3 and SvarDOS 20240915 kernel.sys kernels use BL only, and both boot sectors set BL and DL to the BIOS drive number.
; * !! EDR-DOS drbio.sys: load entire kernel file to 0x700, set DL to BIOS drive number, make DS:BP (EDR-DOS for .hidden_sector_count) point to the boot sector (we don't care), jump to 0x70:0.
; * !! NTLDR: load at least first 0x24 bytes (.hidden_sector_count or the entire 0x24 byte substring, see https://retrocomputing.stackexchange.com/a/31399) of the boot partition (boot sector) to 0x7c00, load kernel file to 0x20000, set DL to the BIOS drive number, jump to 0x2000:0. No header fields used.
; * Multiboot v1: It switches immediately to i386 32-bit protected mode. That could work if we set up the header. No need to switch back to real mode. It can receive both command line and BIOS drive number. SYSLINUX supports it only with mboot.c32. See also https://www.gnu.org/software/grub/manual/multiboot/multiboot.html
;   * GRUB 1 0.97 detects Multiboot v1 signature first in the first 0x8000 bytes, overriding any other type of detection. Multiboot can also be forced with `kernel --type=multiboot`.
;   * Tested with GRUB4DOS 0.4.4 with and without the Multiboot v1 header. Also tested With SYSLINUX 4.07 linux and boot. !! Test with GRUB 1 0.97.
;
; This Universal Kernel Header doesn't support these load protocols yet:
;
; * NTLDR from Windows NT boot.ini (`C:\NTLDR="label"`): It loads only the first 0x10 (== 16) sectors of the *ntldr* file, otherwise the same as the supported NTLDR above.
; * MS-DOS v6: MS-DOS 3.30--6.22, IBM PC DOS 3.30--6.x. IBM PC DOS 7.0--7.1 is almost identical. This loads only the first 3 sectors of the *io.sys* or *ibmbio.com* file, passing some info on how to find the rest, jumps to 0x70:0. It passes some info in registers and memory.
; * MS-DOS v7: MS-DOS 7.0--7.1--8.0, Windows 95--98--ME. This loads only the first 4 sectors of the *io.sys* or *ibmbio.com* file, passing some info on how to find the rest, jumps to 0x70:0x200. It passes some info in registers and memory.
;
; SYSLINUX 4.07 supports these file formats:
;
; * ```
;    kernel   | VK_KERNEL  | 0 | choose by extension |
;    linux    | VK_LINUX   | 1 | Linux kernel image  | any other than .com, .cbt, .c32, .img, .bss, .bin, .bs, .0
;    boot     | VK_BOOT    | 2 | Boot sector         | .bin, .bs, .0
;    bss      | VK_BSS     | 3 | BSS boot sector     | .bss
;    pxe      | VK_PXE     | 4 | PXE NBP             |
;    fdimage  | VK_FDIMAGE | 5 | Floppy disk image   | .img, forced error by SYSLINUX 4.07 (is_disk_image)
;    comboot  | VK_COMBOOT | 6 | COMBOOT image       | .com, .cbt
;    com32    | VK_COM32   | 7 | COM32 image         | .c32
;    config   | VK_CONFIG  | 8 | configuration file  |
;    ```
;  * *bss* is like *boot*, but after loading to kernel file, bytes 0xb..0x25 of the kernel file are ignored (good enough for FAT12 and FAT16, too short for FAT32), and the bytes from the boot sector are used instead of them.
;

%macro assert_fofs 1
  times +(%1)-($-$$) times 0 nop
  times -(%1)+($-$$) times 0 nop
%endm
%macro assert_at 1
  times +(%1)-$ times 0 nop
  times -(%1)+$ times 0 nop
%endm

bits 16
cpu 8086

BOOT_SIGNATURE equ 0xaa55

LINUX_CL_MAGIC equ 0xa33f

MULTIBOOT_MAGIC equ 0x1badb002
MULTIBOOT_FLAG_AOUT_KLUDGE equ 1<<16
OUR_MULTIBOOT_FLAGS equ MULTIBOOT_FLAG_AOUT_KLUDGE
OUR_MULTIBOOT_LOAD_ADDR equ 0x100000
OUR_MULTIBOOT_COPY_CODE32_SIZE equ 0x14
OUR_MULTIBOOT_HEADER_SIZE equ 0x20

KERNELSEG equ 0x1000
INITSEG equ 0x9000  ; We assume that 5*0x200 bytes at boot_sector (including us) have been loaded to linear address INITSEG<<4.

LOADFLAG_READ:
.HIGH: equ 1 << 0

%macro halt 0
		cli
  %%back:	hlt
		jmp short %%back
%endm

boot_sector:  ; 1 sector of 0x200 bytes. Loaded to 0x9000. GRUB 1 and QEMU load 5 sectors (0xa00 bytes).
.start:		jmp short .code
.cl_magic equ .start+0x20  ; The Linux bootloader will set this to: dw 0xa33f
.cl_offset equ .start+0x22  ; The Linux bootloader will set this to (dw) the offset of the kernel command line.
; !! .align_signagure: dw 'MK'  ; Align to a multiple of 4 bytes. Also a signature for our kernel type.

.code:		mov ax, 0xe00+'b'  ; This code will be ignored by `qemu-system-i386 -kernel ...'.
		xor bx, bx
		int 0x10
		mov al, 's'
		int 0x10
		mov al, dl  ; Good: 0x80 by both GRUB4DOS
		int 0x10
		halt

		times 0x1f1-($-.start) db 0
.linux_boot_header:  ; https://docs.kernel.org/arch/x86/boot.html  . Until setup_sectors.linux_boot_header.end.
		assert_fofs 0x1f1
.setup_sects:	db 4  ; (read) The size of the setup in sectors. Must be 4 for compatibility with old-protoocl Linux bootloaders (such as old LILO).
		assert_fofs 0x1f2
.root_flags:	dw 0  ; (read, modify optional) If set, the root is mounted readonly.
		assert_fofs 0x1f4
.syssize_low:	dw (code32.end-code32+0xf)>>4  ; (read) The low word of size of the 32-bit code in 16-byte paras. Ignored by GRUB 1 or QEMU. Maximum size allowed: 1 MiB, but boot protocol <=2.01 supports zImage only, with its maximum size of 0x9000-0x200*(1+.setup_sects) bytes.
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
.start_sys_seg: dw KERNELSEG  ; (read) The load-low segment (0x1000), i.e. linear address >> 4 (obsolete). Ignored by both GRUB 1 0.97 and QEMU 2.11.1. In Linux kernel mode, they don't set root= either, and they don't pass the boot drive (boot_drive, saved_drive, current_drive, is saved_drive the result of `rootnoverify'?) number anywhere. Also GRUB 1 0.97 passes the boot drive in DL in `chainloader' (stage1) mode only.
		assert_fofs 0x20e
.kernel_version: dw .kernel_version_string-setup_sectors  ; (read) Pointer to kernel version string or 0 to indicate no version. Relative to .setup_sectors.
		assert_fofs 0x210
.type_of_loader: db 0  ; (write obligatory) Bootloader identifier.
		assert_fofs 0x211
.loadflags:	db 0  ; Boot protocol option flags. Not specifying LOADFLAG.HIGH, so the the protected-mode code is will be loaded at 0x10000 (== .start_sys_seg<<4 == KERNELSEG<<4).
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
  %ifndef MEMTEST86PLUS5_BIN
    %define MEMTEST86PLUS5_BIN  'memtest86+-5.01-dist.bin'  ; Works. ~150 KiB.
    ;%define MEMTEST86PLUS5_BIN  'memtest86+-5.01.bin'  ; Works. Ubuntu. ~182 KiB. Larger probably because of different C compiler or flags.
    ;%define MEMTEST86PLUS5_BIN  'memtest86+-5.31b-dist.bin'  ; Works.
  %endif

  cpu 386

  base: equ setup_sectors

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
		mov al, 0x80  ; disable NMI for the bootup sequence !! Why is this needed?
		out 0x70, al

		; The system will move itself to its rightful place.
		; reload the segment registers and the stack since the 
		; APs also execute this code
		mov ax, INITSEG
		mov ds, ax
		mov es, ax
		mov ss, ax  ; reset the stack to setup_stack...setup_stack+0x200.
		mov esp, setup_stack+0x200-boot_sector  ; 0x200 bytes of stack. We set ESP because we'd need all 32 bits of it in protected mode.
		; !! Can we do without a stack here (ESP == 0) if we get rid of the pushes and pops (including `push edi', `call' and `ret') below?
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
		dd (INITSEG<<4)+gdt-boot_sector  ; gdt base = 0X9xxxx; !! Relocate this if the setup code above works at any segment other than INITSEG.

%ifdef MULTIBOOT
		times 4*0x200-($-setup_sectors)-OUR_MULTIBOOT_COPY_CODE32_SIZE-OUR_MULTIBOOT_HEADER_SIZE db 0
		assert_fofs 0xa00-OUR_MULTIBOOT_COPY_CODE32_SIZE-OUR_MULTIBOOT_HEADER_SIZE
multiboot:
  .multiboot_copy_code32:  ; Used by multiboot only.
		; If you change code here, update MULTIBOOT_COPY_CODE32_SIZE accordingly.
  cpu 386  ; !! Do it with `db' instead, avoiding the mode change.
  bits 32
		mov esi, OUR_MULTIBOOT_LOAD_ADDR+OUR_MULTIBOOT_COPY_CODE32_SIZE+OUR_MULTIBOOT_HEADER_SIZE  ; Linear address of code32.
		mov edi, KERNELSEG<<4
		push edi
		mov ecx, (code32.end-code32+3)>>2
		rep movsd
		ret  ; Jump to KERNELSEG<<4.
		nop  ; Align to multiple of 4.
  bits 16
  cpu 8086
		assert_fofs 0xa00-OUR_MULTIBOOT_HEADER_SIZE
  .multiboot_align_check: times -(($-boot_sector.start)&3) nop  ; Check alignment of the .multiboot_v1 below. GRUN 1 0.97
  .multiboot:  ; Multiboot v1 header, 0x20 bytes. i386 is hardcoded.
  .multiboot.magic: dd MULTIBOOT_MAGIC
  .multiboot.flags: dd OUR_MULTIBOOT_FLAGS
  .multiboot.checksum: dd -MULTIBOOT_MAGIC-OUR_MULTIBOOT_FLAGS
  .multiboot.header_addr: dd OUR_MULTIBOOT_LOAD_ADDR-(.multiboot_copy_code32-.multiboot)  ; This is smaller than OUR_MULTIBOOT_LOAD_ADDR. It would be ERR_EXEC_FORMAT if .multiboot came before load_addr.
  .multiboot.load_addr: dd OUR_MULTIBOOT_LOAD_ADDR  ; Linear address. ERR_BELOW_1MB for KERNELSEG<<4, thus we use OUR_MULTIBOOT_LOAD_ADDR and multiboot_copy_code32 instead.
  .multiboot.load_end_addr: dd OUR_MULTIBOOT_LOAD_ADDR+code32.end-.multiboot_copy_code32
  .multiboot.bss_end_addr:  dd OUR_MULTIBOOT_LOAD_ADDR+code32.end-.multiboot_copy_code32  ; No specific .bss to be cleared by the bootloader.
  .multiboot.entry_addr: dd OUR_MULTIBOOT_LOAD_ADDR
  .multiboot_size_check: assert_at .multiboot+0x20  ; !!! Try Multiboot v1.
%else
		times 4*0x200-($-setup_sectors) db 0  ; !! Omit (most of) these bytes, do two `rep movsd's instead.
%endif
		assert_fofs 0xa00
setup_stack:  ; 0x200 bytes.

code32:		; 32-bit kernel code (zImage, maximum 512 KiB), but it can be anything. Loaded to 0x10000.
		; It starts with cld, cli.
		incbin MEMTEST86PLUS5_BIN, 0xa00
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
		mov al, [es:0]  ; 'T' in code32.
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

code32:		; (Should be) 32-bit kernel code (zImage, maximum 512 KiB), but it can be anything. Loaded to 0x10000.
		db 'T'
.end:
%endif
