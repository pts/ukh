;
; ukh.nasm: Universal Kernel Header (UKH) for memtest86+-5.01
; by pts@fazekas.hu at Mon Mar 17 13:45:39 CET 2025
;
; Compile with: nasm-0.98.39 -O0 -w+orphan-labels -f bin -DMEMTEST86PLUS5 -DMEMTEST86PLUS5_BIN="'memtest86+-5.01-dist.bin'" -o memtest86+.kernel.bin ukh.nasm
; Run it with: qemu-system-i386 -M pc-1.0 -m 4 -nodefault -vga cirrus -kernel memtest86+.kernel.bin
;
; Please note that memtest86+-5.01 needs least 4 MiB of memory in QEMU 2.11.1 (QEMU fails with 3 MiB), hence the `-m 4`.
;
; !! Compress the 32-bit payload with `upxbc --flat32`. This will also make the kernel shorter than 134.5 KiB, and original FreeDOS, SvarDOS and EDR-DOS boot sectors will work.
; !! Make the 4 setup sectors shorter, *rep movsd* code and data around. We have to keep .setup_sects == 4, for compatibility with the Linux kernel old protocol.
; !! Add progress indicator to the LZMA decompressor.
; !! Add support for 16-bit payload.
; !! Add support for multiboot with 16-bit payload. Switch back to real mode.
; !! Add `upxbc --flat16x` and `apack1p -1 -x` compressor for the 16-bit payload. Make this compression without a prefix.
; !! Apply some Ubuntu bugfix patches to the memtest86+-5.01 binary.
; !! Instead of halting, wait for keypress and reboot.
;
; The Universal Kernel Header (UKH) emitted by this file supports multiple load protocols:
;
; * Linux kernel old (<2.00) protocol: Load first 4 sectors (4*0x200 bytes) to 0x90000, load remaining sectors to 0x10000, don't store the the BIOS drive number anywhere, jump to 0x:9020:0 (file offset 0x200). There are some Linux-specific header fields in file offset range 0x1f1...0x230, including BOOT_SIGNATURE. It can receive a command line. Specification: https://docs.kernel.org/arch/x86/boot.html
; * Linux kernel protocol version 2.01: This implementation simulates the old protocol, but specifies more headers so that QEMU 2.11.1 is able to load it with `qemu-system-i386 -kernel`. There are some Linux-specific header fields in file byte range 0x1f1...0x230, including BOOT_SIGNATURE. It can receive a command line. Specification: https://docs.kernel.org/arch/x86/boot.html
; * bs (GRUB *chainloader* command, SYSLINUX *boot* command, PXE network boot): load entire kernel file (not only the first sector) to 0x7c00, set DL to the BIOS drive number, jump to 0:0x7c00. The BOOT_SIGNATURE in file offset range 0x1fe...0x200 is needed by GRUB 1 0.97 `chainloader`, but not `chainloader --force`. It can't receive a command line.
;   * Please note that this boot mode works only if the bootloader loads the entire kernel file. Universal Kernel Header has a best-effort check for having loaded the first sector only. If the check fails, then it hangs with the message *bF*.
; * FreeDOS and SvarDOS *kernel.sys*: load kernel file to 0x600, set BL to BIOS drive number, make one SS:BP (FreeDOS for the command line, between SS:SP (smaller) and SS:BP) and DS:BP (SvarDOS for .hidden_sector_count) point to the boot sector (we don't care), jump to 0x60:0. No header fields used. Both FreeDOS 1.3 and SvarDOS 20240915 kernel.sys kernels use BL only, and both boot sectors set BL and DL to the BIOS drive number.
; * EDR-DOS 7.01.07--7.01.08 *drbio.sys*: load entire kernel file to 0x700, set DL to BIOS drive number, make DS:BP (EDR-DOS for .hidden_sector_count) point to the boot sector (we don't care), jump to 0x70:0.
; * (impossible to make it work) EDR-DOS 7.01.01--7.01.06 and DR-DOS 7.0--7.01--7.02--7.03--7.05 *ibmbio.com*: They use the same load protocol as EDR-DOS (but with filename *ibmbio.com*), but the boot maximum kernel size its boot sector supports is 29 KiB (way too small for memtest86+), with its *ibmbio.com* being <24.25 KiB.
; * Windows NTLDR *ntldr* and GRUB4DOS bootlace.com *grldr*: Load at least first 0x24 bytes (.hidden_sector_count or the entire 0x24 byte substring, see https://retrocomputing.stackexchange.com/a/31399) of the boot partition (boot sector) to 0x7c00, load kernel file to 0x20000, set DL to the BIOS drive number, jump to 0x2000:0. No header fields used. The GRUB4DOS boot sector (installed with *bootlace.com*) uses the same protocol, looking for kernel file *grldr* rather than *ntldr*.
; * Multiboot v1: It switches immediately to i386 32-bit protected mode. That could work if we set up the header. No need to switch back to real mode. It can receive both command line and BIOS drive number. SYSLINUX supports it only with mboot.c32. Specification: https://www.gnu.org/software/grub/manual/multiboot/multiboot.html
;   * With Multiboot v1, the kernel command line (passed in the Multiboot info struct) is respected. Test it by passing the btrace (will show the *Press any key to advance to the next trace point* message at startup) from GRUB: `kernel /m.mb btrace` and `boot`.
;   * GRUB 1 0.97 detects Multiboot v1 signature first in the first 0x8000 bytes, overriding any other type of detection. Multiboot can also be forced with `kernel --type=multiboot`.
;   * Tested with GRUB4DOS 0.4.4 with and without the Multiboot v1 header, also with chainloader (bs). Also tested With SYSLINUX 4.07 linux and boot (bs). !! Test with GRUB 1 0.97. chainloader doesn't work, it loads only 1 sector.
;   * QEMU 2.11.1 `qemu-system-i386 -kernel` tries to find the Linux kernel protocol >=2.00 header (`HdrS`) first, and then it tries to find the Multiboot v1 header. GRUB 1 0.97 and GRUB4DOS do the opposite order.
;
; Support may be added later:
;
; * !! floopy without filesystem: Make the boot_sector read the rest of the file from floppy image, using `qemu-system-i386 -fda'. QEMU 2.11.1 detects floppy geometry using the image file size, and falls back to a prefix of 144OK (C*H*S == 80*2*18). See also: https://retrocomputing.stackexchange.com/q/31431/3494
; * UEFI PE .exe: The latest memtest86+ supports it: https://github.com/memtest86plus/memtest86plus/blob/a10664a2515a81b07ab8ae999f91e8151a87eec6/boot/x86/header.S#L798-L824
; * MS-DOS and Windows 95--98--ME io.sys: The boot sector loads only the first 3 or 4 sectors of *io.sys*. Also a file named *msdos.sys* must be present for MS-DOS --6.22 boot code.
; * IBM PC DOS ibmbio.com: The boot sector loads only the first 3 sectors of *ibmbio.com*. Also a file named *ibmbio.com* must be present for IBM PC DOS boot code.
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
OUR_LINUX_BOOT_PROTOCOL_VERSION equ 0x201  ; 0x201 is the last one which loads everything under 0xa0000. Later versions load code32 above 1 MiB (linear address >=0x100000).

MULTIBOOT_MAGIC equ 0x1badb002
MULTIBOOT_FLAG_AOUT_KLUDGE equ 1<<16
MULTIBOOT_INFO_CMDLINE equ 1<<2
OUR_MULTIBOOT_FLAGS equ MULTIBOOT_FLAG_AOUT_KLUDGE
OUR_MULTIBOOT_LOAD_ADDR equ 0x100000
OUR_MULTIBOOT_STARTUP_CODE_SIZE equ 0x44
OUR_MULTIBOOT_HEADER_SIZE equ 0x20

KERNELSEG equ 0x1000
INITSEG equ 0x9000  ; We assume that 5*0x200 bytes at boot_sector (including us) have been loaded to linear address INITSEG<<4.
BOOT_ENTRY_ADDR equ 0x7c00

LOADFLAG_READ:
.HIGH: equ 1 << 0

%macro halt 0
		cli
  %%back:	hlt
		jmp short %%back
%endm

; With the Linux kernel protocols, the bootloader loads the first 5*0x200
; bytes (boot_sector and setup_sectors) to INITSEG<<4 (== 0x90000), the rest
; (code32) to KERNELSEG<<4 (== 0x10000) and jumps to 0x9020:0
; (setup_sectors) in real mode.
;
; With the bs load protocol, the bootloader loads everything to
; BOOT_ENTRY_ADDR (0x7c00), and jumps to 0:BOOT_ENTRY_ADDR.
;
; Info about the BIOS drive number:
;
; * First floppy: 0, second floppy: 1 etc. First HDD: 0x80, second HDD: 0x81 etc.
; * The bs, DR-DOS, EDR-DOS and NTLDR load protocols pass it in DL.
; * The FreeDOS load protocol passes it in BL.
; * The DR-DOS 7.03 boot sector passes it in DL only.
; * The EDR-DOS 7.01.08 boot sector passes it in both BL and DL (BL is unnecessary).
; * The FreeDOS (checked versions 1.0--1.1--1.2--1.3) and SvarDOS (checked version 20240915) boot sector passes it in both BL and DL (DL is unnecessary).
; * The FreeDOS (checked version 1.3) kernel gets it from BL.
; * The SvarDOS (checked version 20240915) gets it from BL if the initial CS is 0x60 (FreeDOS load protocol), and from DL if the initial CS is 0x70 (DR-DOS load protocol).
boot_sector:  ; 1 sector of 0x200 bytes. Loaded to 0x9000. GRUB 1 and QEMU load 5 sectors (0xa00 bytes).
.start:		;jmp short .code  ; Not needed.
.cl_magic equ .start+0x20  ; The Linux bootloader will set this to: dw LINUX_CL_MAGIC (== 0xa33f).
.cl_offset equ .start+0x22  ; The Linux bootloader will set this to (dw) the offset of the kernel command line.

.code:		cld
		mov ax, 0xe00+'?'  ; Set up error message.
		call .here
.here:		pop si  ; SI := actual offset of .here.
		sub si, byte .here-.start  ; SI := actual offset of .start.
		mov cx, cs
		test cx, cx
		jnz short .not_bs_protocol
		cmp si, BOOT_ENTRY_ADDR
		je short .bs_protocol
.not_bs_protocol:
		test si, si
		jnz short .not_protocol_with_offset_zero
		cmp cx, byte 0x60
		jne short .not_freedos_protocol
.freedos_protocol:  ; Used by FreeDOS and SvarDOS.
		mov dl, bl  ; Save BIOS drive number.
		mov al, 'F'  ; Indicate FreeDOS.
		jmp short .any_supported_protocol  ; !! Also receive the FreeDOS (bleeding edge, more reent than the kernel in FreeDOS 1.3) command line.
.not_freedos_protocol:
		cmp cx, byte 0x70
		jne short .not_drdos_protocol
.drdos_protocol:  ; Used by DR-DOS, EDR-DOS. SvarDOS can also boot from it.
		mov al, 'D'  ; Indicate DR-DOS.
		jmp short .any_supported_protocol
.not_drdos_protocol:
		cmp cx, 0x2000
		jne short .not_ntldr_protocol
.ntldr_protocol:  ; NTLDR, used by Windows NT 3.1--4.0, Windows 2000--XP. Later releases of Windows may use a similar protocol, but the filename is *bootmgr* rather than *ntldr*.
		mov al, 'N'  ; Indicate Windows NTLDR.
		jmp short .any_supported_protocol
.not_ntldr_protocol:
.not_protocol_with_offset_zero:
.fatal_unknown_protocol:
		xor bx, bx  ; Set up error message.
		int 0x10  ; Print character in AL.
.halt:		halt
.bs_protocol:  ; Now: CX == 0; DS == 0; SI == 0x7c00 == BOOT_ENTRY_ADDR; DL is the bios drive number.
		xor bx, bx  ; Set up error message.
		mov al, 'b'
		int 0x10  ; Print character in AL.

		mov ds, cx  ; DS := 0.
		mov es, cx  ; ES := 0.
		mov si, BOOT_ENTRY_ADDR+.copy_of_setup_sectors-.start
		inc byte [si+2]  ; 'GdrS' --> 'HdrS'.
		mov di, BOOT_ENTRY_ADDR+setup_sectors-.start
		mov cx, (.copy_of_setup_sectors.end-.copy_of_setup_sectors)>>1
		repe cmpsw
		je .cmp_matches
		mov al, 'F'  ; Indicate fatal error: `bF' means that the bootloader has loaded only he first sector.
		int 0x10
		jmp short .halt
.cmp_matches:
		;xor cx, cx  ; CX := 0. Not needed, CX is now 0.
		mov al, 's'
		mov cx, BOOT_ENTRY_ADDR>>4
.any_supported_protocol:  ; Now: DS:SI points to the loaded boot_sector+setup_sectors; AL is character to print; DL is the BIOS drive number.
		xor bx, bx  ; Set up error message.
		int 0x10  ; Print character in AL.
		mov al, dl  ; Good: YSLINUX 4.07 boot, GRUB4DOS chainloader and FreeDOS boot sector pass the BIOS drive number (e.g. 0x80 for first HDD) in DL.
		int 0x10  ; Print BIOS boot drive character. !! No need to print these.

		; Set up some segments and stack.
		mov ds, cx  ; After this (until we break DS again) global variables work.
		mov es, [.initseg_const-.start]  ; ES := INITSEG.
		cli
		mov ax, INITSEG
		mov ss, ax
		mov sp, 0xa000  ; Set SS:SP to INITSEG:0x9000 (== 0x9000:0xa000), similarly to how QEMU 2.11.1 `-kernel' acts as a Linux bootloader, it sets 0x9000:(0xa000-cmdline_size-0x10).
		sti

		; Copy 5*0x200 bytes from DS:SI (actually loaded boot_sector+setup_sectors) to INITSEG<<4 == 0x90000. There is no overlap.
		xor si, si
		xor di, di
		mov cx, (5*0x200)>>1  ; Number of words to copy.
		rep movsw
		jmp INITSEG:.after_far_jmp-.start  ; Jump to .after_far_jmp in the copy, to avoid overwriting the code doing the copy below (to KERNELSEG). Needed for the NTLDR load protocol.
.initseg_const equ $-2
.after_far_jmp:

		; Copy code32.end-code32 bytes from BOOT_ENTRY_ADDR+5*0x200
		; == 0x8600 to KERNELSEG<<4 == 0x10000. Copy them in
		; reverse, because they may overlap.
		;
		; We copy one sector (0x200) bytes at a time. This is
		; arbitrary. But we can't copy in one go, because the data
		; size is >=64 KiB, so we have to modify some segment registers.
		mov dx, 0x200>>4  ; Number of paragraphs per sector.
		mov bx, (code32.end-code32+0x1ff)>>9  ; Number of 0x200-byte sectors to copy. Positive.
		mov cx, ds
		mov ax, KERNELSEG
		; Now: CX == segment of first source sector (with offset 0 it points to code32), minus (5*0x200)>>4; AX == KERNELSEG.
		cmp cx, ax
		jae .after_setup_copy  ; Copy them in forward (ascending), because the destination comes before the source, and they may overlap.
.setup_backward_copy:  ; Copy them in backward (descending), because the destination comes after the source, and they may overlap.
		neg dx  ; DX := -(0x200)>>4. Change copy direction to descending.
		add ax, strict word (((code32.end-code32+0x1ff)>>9)-1)<<5  ; Adjust destination segment to point to the last sector.
		add cx, strict word (((code32.end-code32+0x1ff)>>9)-1)<<5  ; Adjust source      segment to point to the last sector.
		;jmp short .after_setup_copy  ; Not needed, falls through.
;.setup_forward_copy:
		;mov dx, 0x200>>4  ; Already set.
		;mov ax, KERNELSEG  ; Already set. AX := segment of first destination sector.
		;mov es, ax  ; Already set. ES := segment of first destination sector.
		;add cx, 0 ; Already set. CX := segment of first source sector (with offset 0 it points to code32), minus (5*0x200)>>4.
		;mov ds, cx  ; Already set. DS := segment of first source sector (with offset 0 it points to code32), minus (5*0x200)>>4.
.after_setup_copy:
		mov ds, cx
		mov es, ax
.copy_sector:	mov cx, 0x200>>1  ; Number of words in a sector.
		mov si, 5*0x200  ; Skip over boot_sector+setup_sectors.
		xor di, di
		rep movsw
		mov ax, ds
		add ax, dx ; [+-] (0x200>>4)
		mov ds, ax
		mov ax, es
		add ax, dx ; [+-] (0x200>>4)
		mov es, ax
		dec bx
		jnz short .copy_sector

		mov ax, 0xe00+'&'
		xor bx, bx
		int 0x10  ; Print character in AL.

		push ss  ; INITSEG (== 0x9000).
		pop ds
		push ss  ; INITSEG (== 0x9000).
		pop es
		jmp (INITSEG+0x20):0  ; Jump to the relocated setup_sectors.start (0x9020:0), simulating a Linux bootloader.

		times (.start-$)&1 nop  ; Align to even.
.copy_of_setup_sectors:  ; Extra bytes from the beginning of setup_sectors, so that we can figure out that it has been loaded (not only the boot_sector).
		db 0xeb, setup_sectors.code-(setup_sectors.jump+2)
		db 'GdrS'  ; Like 'HdrS', but obfuscate it from hex editors.
		dw OUR_LINUX_BOOT_PROTOCOL_VERSION
		dd 0
		dw KERNELSEG
		dw setup_sectors.kernel_version_string-setup_sectors
.copy_of_setup_sectors.end:
		times -((.copy_of_setup_sectors.end-.copy_of_setup_sectors)&1) nop  ; Fail if size is not even. Evenness needed by cmpsw above.

		times 0x1f1-($-.start) db 0
.linux_boot_header:  ; https://docs.kernel.org/arch/x86/boot.html  . Until setup_sectors.linux_boot_header.end.
		assert_fofs 0x1f1
.setup_sects:	db 4  ; (read) The size of the setup in sectors. Must be 4 for compatibility with old-protoocl Linux bootloaders (such as old LILO).
		assert_fofs 0x1f2
.root_flags:	dw 0  ; (read, modify optional) If set, the root is mounted readonly.
		assert_fofs 0x1f4
.syssize_low:	dw (code32.end-code32+0xf)>>4  ; (read) The low word of size of the 32-bit code in 16-byte paras. Ignored by GRUB 1 or QEMU. Maximum size allowed: 1 MiB, but Linux kernel protocol <=2.01 supports zImage only, with its maximum size of 0x9000-0x200*(1+.setup_sects) bytes.
		assert_fofs 0x1f6
.swap_dev:
.syssize_high:	dw 0  ; (read) The high word size of the 32-bit code in 16-byte paras. For Linux kernel protocol prior to 2.04, the upper two bytes of the syssize field are unusable, which means the size of a bzImage kernel cannot be determined.
		assert_fofs 0x1f8
.ram_size:	dw 0  ; (kernel internal) DO NOT USE - for bootsect.S use only.
		assert_fofs 0x1fa
.vid_mode:	dw 0  ; (read, modify obligatory) Video mode control.
		assert_fofs 0x1fc
.root_dev:	dw 0  ; (read, modify optional) Default root device number. Neither GRUB 1 nor QEMU 2.11.1 set it.
		assert_fofs 0x1fe
.boot_flag:	dw BOOT_SIGNATURE  ; (read) 0xaa55 magic number.
		assert_fofs 0x200

setup_sectors:  ; 2 == (.boot_sector.setup_sects) sectors of 0x800 bytes. Loaded to 0x800 bytes to 0x90200. Jumped to `jmp 0x9020:0' in real mode for the Linux boot protocools.
.start:		assert_fofs 0x200
.jump:		jmp short .code  ; (read) Jump instruction. Entry point.
		assert_fofs 0x202
.header:	db 'HdrS'  ; (read) Protocol >=2.00 signature. Magic signature “HdrS”.
		assert_fofs 0x206
.version:	dw OUR_LINUX_BOOT_PROTOCOL_VERSION  ; (read) Linux kernel protocol version supported. 0x201 is the last one which loads everything under 0xa0000.
		assert_fofs 0x208
.realmode_swtch: dd 0  ; (read, modify optional) Bootloader hook.
		assert_fofs 0x20c
.start_sys_seg: dw KERNELSEG  ; (read) The load-low segment (0x1000), i.e. linear address >> 4 (obsolete). Ignored by both GRUB 1 0.97 and QEMU 2.11.1. In Linux kernel mode, they don't set root= either, and they don't pass the boot drive (boot_drive, saved_drive, current_drive, is saved_drive the result of `rootnoverify'?) number anywhere. Also GRUB 1 0.97 passes the boot drive in DL in `chainloader' (stage1) mode only.
		assert_fofs 0x20e
.kernel_version: dw .kernel_version_string-setup_sectors  ; (read) Pointer to kernel version string or 0 to indicate no version. Relative to .setup_sectors.
		assert_fofs 0x210
.type_of_loader: db 0  ; (write obligatory) Bootloader identifier.
		assert_fofs 0x211
.loadflags:	db 0  ; Linux kernel protocol option flags. Not specifying LOADFLAG.HIGH, so the the protected-mode code is will be loaded at 0x10000 (== .start_sys_seg<<4 == KERNELSEG<<4).
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

  .kernel_version_string: db 'memtest86+-5.01', 0  ; Can be anywhere in the first 0x800 bytes (setup_sects * 0x200 bytes). !! Make this configurable.
  %if $-.start<0x30
		times 0x30-($-.start) db 0  ; QEMU 2.11.1 overwrites some bytes within the .linux_boot_header. Offset 0x30 seems to be the minimum bytes left intact.
  %endif
  .code:  ; The entry point jumps here.

%if 0  ; For debugging.
		mov ax, 0xe00+'S'
		xor bx, bx
		int 0x10  ; Print character in AL.
%endif

		cli ; no interrupts allowed
		jmp INITSEG:.ck-boot_sector  ; Make `org 0' work. Otherwise CS:IP would remain: 0x9020:.ck-setup_sectors.
.ck:		cld

		; now we want to move to protected mode ... !! Consider alternatives, such as how SYSLINUX 4.07 does it or how GRUB 1 0.97 does it.
		mov al, 0x80  ; disable NMI for the bootup sequence !! Why is this needed? https://wiki.osdev.org/Protected_Mode
		out 0x70, al

		; The system will move itself to its rightful place.
		; reload the segment registers and the stack since the
		; APs also execute this code
		mov ax, cs  ; INITSEG.
		mov ds, ax
		mov es, ax
		mov ss, ax  ; reset the stack to setup_stack...setup_stack+0x200.
		mov esp, setup_stack+0x200-boot_sector  ; 0x200+0xa00-0x24 bytes of stack. We set ESP because we'd need all 32 bits of it in protected mode. !! Extend the stack all the way to INITSEG:0xa000-cmdline_size.
		; !! Can we do without a stack here (ESP == 0, memtest86+-5.01 code32 change ESP from 0 to something valid) if we get rid of the pushes and pops (including `push edi', `call' and `ret') below?
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
		mov ah, [esp+4]  ; !!! Where does this come from? Who puts this value to ESP?
		test ah, ah
		jz short alt_a20_cont1
		or al, 2
		jmp short alt_a20_cont2
alt_a20_cont1:
		and al, ~2

		; clear the INIT_NOW bit; don't accidently reset the machine
alt_a20_cont2:
		and al, ~1
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

		mov ax, 0x0001  ; protected mode (PE) bit
		lmsw ax
		; Note that the short jump isn't strictly needed, althought there are
		; reasons why it might be a good idea. It won't hurt in any case.
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
		dw 0,0,0,0  ; Segment 8. Unused. !! Remove it.

		; KERNEL_CS == segment 0x10. https://wiki.osdev.org/Global_Descriptor_Table#Segment_Descriptor
		dw 0xffff  ; limit full 4 GiB.
		dw 0x0000  ; base address=0
		dw 0x9a00  ; code read/exec
		dw 0x00cf  ; granularity=4096, 386
		; QEMU 2.11.1 has here: dw 0xffff, 0, 0x9a00, 0xcf  ; Only the limit is different (it has less than full 4 GiB).

		; KERNEL_DS == segment 0x18. https://wiki.osdev.org/Global_Descriptor_Table#Segment_Descriptor
		dw 0x7fff  ; limit full 4 GiB.
		dw 0x0000  ; base address=0
		dw 0x9200  ; data read/write
		dw 0x00cf  ; granularity=4096, 386
		; QEMU 2.11.1 has here: dw 0xffff, 0, 0x9200, 0xcf  ; Only the limit is different (it has less than full 4 GiB).

.end:

idt_48:		dw 0  ; idt limit=0
		dd 0  ; idt base=0L

gdt_48:		dw gdt.end-gdt-1
		dd (INITSEG<<4)+gdt-boot_sector  ; gdt base = 0X9xxxx

%ifdef MULTIBOOT
		times 4*0x200-($-setup_sectors)-OUR_MULTIBOOT_STARTUP_CODE_SIZE-OUR_MULTIBOOT_HEADER_SIZE db 0
		assert_fofs 0xa00-OUR_MULTIBOOT_STARTUP_CODE_SIZE-OUR_MULTIBOOT_HEADER_SIZE
multiboot:
  .multiboot_entry:  ; If you change code below, update MULTIBOOT_STARTUP_CODE_SIZE accordingly.
  cpu 386
  bits 32
		cld
		;cmp eax, 0x2badb002  ; We ignore this signature.

		xor ecx, ecx  ; Empty command line by default.
		test byte [ebx], MULTIBOOT_INFO_CMDLINE  ; multiboot_info.flags.
		jz short .got_cmdline_length
		mov esi, [ebx+4*4]  ; ESI: pointer to the command line from multiboot_info.cmdline.
  .next_cmdline_char:
		cmp byte [esi+ecx], 0
		je short .got_cmdline_length
		inc ecx
		jmp short .next_cmdline_char
  .got_cmdline_length:  ; Now: ECX == length of the command line without the trailing NUL, ESI: address of the command line (invalid if ECX == 0).
		mov edi, (INITSEG<<4)+0xa000-1
		sub edi, ecx  ; TODO(pts): Abort if too long (>=0xa000-0x30), to avoid buffer overflow.
		mov eax, (0xa000-1)|LINUX_CL_MAGIC<<16
		sub eax, ecx
		ror eax, 16  ; Swap low and high words.
		mov [(INITSEG<<4)+boot_sector.cl_magic-boot_sector.start], eax  ; Also sets boot_sector.cl_offset.
		rep movsb  ; Test it by passing `btrace' in the memtest86+4.01 command line. It should show the *Press any key to advance to the next trace point* message at startup.
		mov al, 0
		stosb  ; Add terminating NUL.

		mov esi, OUR_MULTIBOOT_LOAD_ADDR+OUR_MULTIBOOT_STARTUP_CODE_SIZE+OUR_MULTIBOOT_HEADER_SIZE  ; Linear address of code32.
		mov edi, KERNELSEG<<4
		push edi
		mov ecx, (code32.end-code32+3)>>2
		rep movsd  ; We need this move, the memtest86+-5.x 32-bit kernel is not position-independent.
		ret  ; Jump to KERNELSEG<<4.

		times (boot_sector.start-$)&3 nop  ; Align to multiple of 4.
  bits 16
  cpu 8086
		assert_fofs 0xa00-OUR_MULTIBOOT_HEADER_SIZE
  .multiboot_align_check: times -(($-boot_sector.start)&3) nop  ; Check alignment of the .multiboot_v1 below. GRUN 1 0.97
  .multiboot:  ; Multiboot v1 header, 0x20 bytes. i386 is hardcoded.
  .multiboot.magic: dd MULTIBOOT_MAGIC
  .multiboot.flags: dd OUR_MULTIBOOT_FLAGS
  .multiboot.checksum: dd -MULTIBOOT_MAGIC-OUR_MULTIBOOT_FLAGS
  .multiboot.header_addr: dd OUR_MULTIBOOT_LOAD_ADDR-(.multiboot_entry-.multiboot)  ; This is smaller than OUR_MULTIBOOT_LOAD_ADDR. It would be ERR_EXEC_FORMAT if .multiboot came before load_addr.
  .multiboot.load_addr: dd OUR_MULTIBOOT_LOAD_ADDR  ; Linear address. ERR_BELOW_1MB for KERNELSEG<<4, thus we use OUR_MULTIBOOT_LOAD_ADDR and multiboot_copy_code32 instead.
  .multiboot.load_end_addr: dd OUR_MULTIBOOT_LOAD_ADDR+code32.end-.multiboot_entry
  .multiboot.bss_end_addr:  dd OUR_MULTIBOOT_LOAD_ADDR+code32.end-.multiboot_entry  ; No specific .bss to be cleared by the bootloader.
  .multiboot.entry_addr: dd OUR_MULTIBOOT_LOAD_ADDR
  .multiboot_size_check: assert_at .multiboot+0x20
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
  .char:	db 'k'  ; Preserved.
  .code:	; QEMU 2.11.1 sets DL=0, no way to communicate the BIOS boot drive number (root device). !! try root=? !! What does GRUB 1 pass?
		; These are already set by QEMU 2.11.1, GRUB 1 0.97 and SYSLINUX 4.07.
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
  .next:	lodsb
		test al, al
		jz short .printed
		int 0x10  ; Print character AL to console.
		jmp short .next
  .printed:	mov al, '.'
		int 0x10

  .halt:	halt

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
		%if code32.end==code32
		  %error FATAL_EMPTY_CODE32
		  times -1 nop
		%endif
