;
; ukh.nasm: Universal Kernel Header (UKH)
; by pts@fazekas.hu at Mon Mar 17 13:45:39 CET 2025
;
; Compile with: nasm-0.98.39 -O0 -w+orphan-labels -f bin -DMEMTEST86PLUS5 -DMEMTEST86PLUS5_BIN="'memtest86+-5.01-dist.bin'" -o memtest86+.kernel.bin ukh.nasm
; Run it with: qemu-system-i386 -M pc-1.0 -m 4 -nodefault -vga cirrus -kernel memtest86+.kernel.bin
;
; Please note that memtest86+-5.01 needs least 4 MiB of memory in QEMU 2.11.1 (QEMU fails with 3 MiB), hence the `-m 4`.
;
; !! Pass the BIOS drive number for both Multiboot and non-Multiboot protocols at byte [0x90007] (already 0xff by default), or 0xff if unknown.
; !! Move the kernel command line to linear address 0x90026.
; !! Compress the 32-bit payload with `upxbc --flat32`. This will also make the kernel shorter than 134.5 KiB, and original FreeDOS, SvarDOS and EDR-DOS boot sectors will work.
; !! Make the 4 setup sectors shorter, *rep movsd* code and data around. We have to keep .setup_sects == 4, for compatibility with the Linux kernel old protocol.
; !! Add progress indicator to the LZMA decompressor.
; !! Add support for 16-bit payload.
; !! Add support for multiboot with 16-bit payload. Switch back to real mode.
; !! Add `upxbc --flat16x` and `apack1p -1 -x` compressor for the 16-bit payload. Make this compression without a prefix.
; !! Apply some Ubuntu bugfix patches to the memtest86+-5.01 binary.
; !! Instead of halting, wait for keypress and reboot.
; !! See how much better memtest86+-5.01.bin compresses (uncompressed size is about 32 KiB larger).
; !! Simplfy jumps in upxbc --flat32 decompress and lxunfilter functions.
; !! Make UKH a few bytes shorter than 2 sectors, not aligning code32 to a multiple of 0x200.
;
; The Universal Kernel Header (UKH) is a 1024-byte header that can be added
; in front of i386+ 32-bit protected mode kernel images to make them
; bootable using a multitude of bootloaders (hence the qualifier
; *universal*). Currently the type of kernel support is limited, the first
; one that was made work is memtest86+-5.01.
;
; The Universal Kernel Header (UKH) supports multiple load protocols:
;
; * Linux: In our supported version, load first 2 sectors (2*0x200 == 0x400 bytes) to 0x90000, load remaining sectors to 0x10000, don't store the the BIOS drive number anywhere, jump to 0x:9020:0 (file offset 0x200). There are some Linux-specific header fields in file offset range 0x1f1...0x230 read and/or written by the bootloader, including BOOT_SIGNATURE. It can receive a command line. Specification: https://docs.kernel.org/arch/x86/boot.html
;   * Actually, the Linux load protocol (2.01 and earlier) loads 5 sectors (number hardcoded to the old Linux load protocol) to 0x90000 and the remaining sectors to 0x10000, but to avoid waste 3 sectors worth of space, UKH will move 0x10000 3 sectors later, and then it copy over 3 sectors from 0x90000+2*0x200 to 0x10000.
;   * Subtype Linux kernel old (<2.00) protocol: It doesn't check for the `HdrS` header at file offset 0x202. It always loads 5 sectors. Very old Linux bootloaders can load this, but not version 2.00 or 2.01.
;   * Subtype Linux kernel protocol version 2.01 (also applies to 2.00): This implementation simulates the old protocol, but specifies more headers so that QEMU 2.11.1 is able to load it with `qemu-system-i386 -kernel`. There are some Linux-specific header fields in file byte range 0x1f1...0x230, including BOOT_SIGNATURE. It can receive a command line. Specification: https://docs.kernel.org/arch/x86/boot.html
;   * Bootloaders supported: GRUBs (non-UEFI GRUB 2, GRUB 1 (GRUB Legacy), GRUB4DOS) with the *kernel* command (but GRUBs will use Multiboot instead if Multiboot was enabled at UKH compilation time; practically both work, but Multiboot also passes the BIOS drive number); SYSLINUX (and ISOLINUX and PXELINUX) with the *linux* command (or with the *kernel* command, but with a filename extension other than .com, .cbr, .c32, .img, .bss, .bin, .bs, .0); QEMU `qemu-system-i386 -kernel`; loadlin; LILO, and possibly others. The GRUBs recognize it as Multiboot first (if compiled with -DMULTIBOOT) rather than Linux.
; * chain: Load entire kernel file (not only the first sector) to some base address (0x600, 0x700, 0x7c00 or 0x20000), set BL or DL to the BIOS drive number, jump to the beginning (0x60:0, 0x70:0, 0:0x7c00 or 0x2000:0). It can't receive a command line. The BOOT_SIGNATURE in file offset range 0x1fe...0x200 is needed by GRUB 1 0.97 `chainloader`, but not `chainloader --force`. It can't receive a command line.
;   * UKH boot code autodetects the subtype by looking at CS:IP upon entry.
;   * Please note that this boot mode works only if the bootloader loads the entire kernel file. Universal Kernel Header has a best-effort check for having loaded the first sector only. If the check fails, then it hangs with the message *bF*. There is no check for loading more than 29 KiB.
;   * Subtype PXE: Load entire kernel file (in PXE terminology, NBP == Network Boot Program) to 0x7c00, don't set DL to the BIOS drive numbe, jump to 0:0x7c00. The maximum kernel file size depends on the PXE version: 2.0 (1999): 32 KiB; 2.1 (2003): 64 KiB; 2.2 (2008): unlimited. More info about PXE: https://wiki.osdev.org/PXE
;   * Subtype FreeDOS (FreeDOS and SvarDOS *kernel.sys*): Load kernel file to 0x600, set BL to BIOS drive number, make one SS:BP (FreeDOS for the command line, between SS:SP (smaller) and SS:BP) and DS:BP (SvarDOS for .hidden_sector_count) point to the boot sector (we don't care), jump to 0x60:0. No header fields used. Both FreeDOS 1.3 and SvarDOS 20240915 kernel.sys kernels use BL only, and both boot sectors set BL and DL to the BIOS drive number. Maximum file size, limited by the FreeDOS and SvarDOS boot sectors: 134.5 KiB.
;   * Subtype EDR-DOS (EDR-DOS 7.01.07--7.01.08 *drbio.sys*): load entire kernel file to 0x700, set DL to BIOS drive number, make DS:BP (EDR-DOS for .hidden_sector_count) point to the boot sector (we don't care), jump to 0x70:0. Maximum file size, limited by the EDR-DOS boot sector: 134.5 KiB.
;   * Subtype DR-DOS (EDR-DOS 7.01.01--7.01.06 *ibmbio.com*, DR-DOS --7.0--7.01--7.02--7.03--7.05 *ibmbio.com*): They use the same load protocol as EDR-DOS (but with filename *ibmbio.com*), but the boot maximum kernel size its boot sector supports is 29 KiB (way too small for memtest86+), with its *ibmbio.com* being <24.25 KiB.
;   * Subtype NTLDR (Windows NTLDR *ntldr* and GRUB4DOS bootlace.com *grldr*): Load at least first 0x24 bytes (.hidden_sector_count or the entire 0x24 byte substring, see https://retrocomputing.stackexchange.com/a/31399) of the boot partition (boot sector) to 0x7c00, load kernel file to 0x20000, set DL to the BIOS drive number, jump to 0x2000:0. No header fields used. The GRUB4DOS boot sector (installed with *bootlace.com*) uses the same protocol, looking for kernel file *grldr* rather than *ntldr*.
;   * Bootloaders supported: non-UEFI GRUB 2 and GRUB4DOS (but not GRUB 1, because it loads only 512 bytes) with the *chainloader* command, SYSLINUX (and ISOLINUX and PXELINUX) with the *boot* command (or with the *kernel* command and a filename extensions .bin, .bs and .0); PXE network boot 2.0 and 2.1 (with small kernel file size limit), PXE network boot >=2.2; FreeDOS boot sector with filename *kernel.sys*; SvarDOS boot sector with filename *kernel*.sys*; EDR-DOS >=7.01.07 boot sector with filename *drbio.sys*; DR-DOS boot sector with filename *ibmbio.com*; Windows NT 3.1--3.5--3.51--4.0 boot sector with filename *ntldr*; Windows 2000--XP boot sector with filename *ntldr*; maybe Windows Vista-- boot sector with filename *bootmgr* (untested); * NTLDR from Windows NT boot.ini (`C:\NTLDR="label"`): maximum file size is 8 KiB, because it loads only the first 16 sectors (0x2000 == 8192 bytes) of the *ntldr* file, otherwise the same as the supported NTLDR above.
; * Multiboot: It works according to the Multiboot v1 specification. It switches immediately to i386 32-bit protected mode. No code is run in real mode unless the kernel explicitly switches back to real mode. It can receive both command line and BIOS drive number, which is populated by GRUBs, but not QEMU 2.11.1. SYSLINUX supports it only with its *mboot.c32* file. Specification: https://www.gnu.org/software/grub/manual/multiboot/multiboot.html
;   * With Multiboot v1, the kernel command line (passed in the Multiboot info struct) is respected. Test it by passing *btrace* to memtest86+-5.01 (will show the *Press any key to advance to the next trace point* message at startup) from GRUB: `kernel /m.mb btrace` and `boot`.
;   * To disable Multiboot support in UKH, compile it without the `-DMULTIBOOT` NASM flag. (To enable it, compile it with the flag.)
;   * GRUB 1 0.97 and GRUB4DOS detect Multiboot v1 signature first in the first 0x8000 bytes, overriding any other type of detection, such as the Linux kernel protocol >=2.00. It looks like that `kernel --type=multiboot` and `kernel --type=linux` can force the type, but in these cases, it can't, and the autodetected type is enforced.
;   * Tested with GRUB 1 0.97-29ubuntu68 and GRUB4DOS 0.4.4. Tested with and without the Multiboot v1 header, also with *chainloader* (*chainloader* doesn't work with GRUB 1 0.97, because it only reads 1 sector). Also tested With SYSLINUX 4.07 *linux* and *boot*.
;   * QEMU 2.11.1 `qemu-system-i386 -kernel` detects the Linux kernel protocol >=2.00 signature (`HdrS`) first, and then it detects the Multiboot v1 header.
;   * Bootloaders supported: GRUBs (non-UEFI GRUB 2, GRUB 1 (GRUB Legacy), GRUB4DOS) with the *kernel* command, >=QEMU 2.11.1 with the `qemu-system-i386 -kernel` flag (it passes 0xff as the BIOS drive number), and possibly others.
;
; Support may be added later for these load protocols:
;
; * !! floppy without filesystem: Make the boot_sector read the rest of the file from floppy image, using `qemu-system-i386 -fda'. QEMU 2.11.1 detects floppy geometry using the image file size, and falls back to a prefix of 144OK (C*H*S == 80*2*18). See also: https://retrocomputing.stackexchange.com/q/31431 . See also RaWrite 1.3 autodetection (https://ridl.cfd.rit.edu/products/manuals/sunix/scsi/2203/html/RAWRITE.HTM), memtest86+-5.01 autodetection, Linux kernel floppy boot code autodetection.
; * !! DOS MZ .exe, just to report that this is a kernel file which cannot be executed in DOS
; * !! bootable CD (what are the options for preloading? or does it have to load emulated floppy sectors)?
; * UEFI PE .exe: The latest memtest86+ (>=7.20) supports it: https://github.com/memtest86plus/memtest86plus/blob/a10664a2515a81b07ab8ae999f91e8151a87eec6/boot/x86/header.S#L798-L824
; * MS-DOS and Windows 95--98--ME io.sys: The boot sector loads only the first 3 (MS-DOS --6.22) or 4 sectors of *io.sys*. Also a file named *msdos.sys* must be present for MS-DOS --6.22 boot code.
;   * MS-DOS v6: MS-DOS 3.30--6.22, IBM PC DOS 3.30--6.x. IBM PC DOS 7.0--7.1 is almost identical. This loads only the first 3 sectors of the *io.sys* or *ibmbio.com* file, passing some info on how to find the rest, jumps to 0x70:0. It passes some info in registers and memory.
;   * MS-DOS v7: MS-DOS 7.0--7.1--8.0, Windows 95--98--ME. This loads only the first 4 sectors of the *io.sys* or *ibmbio.com* file, passing some info on how to find the rest, jumps to 0x70:0x200. It passes some info in registers and memory.
; * IBM PC DOS ibmbio.com: The boot sector loads only the first 3 sectors of *ibmbio.com*. Also a file named *ibmbio.com* must be present for IBM PC DOS boot code.
;
; The UKH load protocol for the 32-bit kernel (code32):
;
; * The 32-bit kernel (code and data) is loaded to absolute linear address 0x10000, and the CPU is jumped to this address in i386+ 32-bit protected mode.
; * The maximum kernel size (including code, data and uninitialized data) is 512 KiB == 0x80000 bytes. (This corresponds to the maximum file size of a Linux zImage kernel.)
; * Uninitialized data after the loaded kernel code and data is not initialized, and can contain arbitary values. (This differs from C global variables in .bss, which are zero-initialized.)
; * The A20 gate (A20 line) is enabled. See also: https://en.wikipedia.org/wiki/A20_line
; * BIOS functionality is still available if the kernel switches back to real (8086) mode.
; * Interrupts are disabled on entry (IF == 0, cli). The contents of the IDT is undefined.
; * In EFLAGS, OF=0, DF=0, IF=0, SF=0, ZF=1, AF=0, PF=1, CF=0, other flags are in an undefined state.
; * ESP is set to 0x10000, this gives the program an initial stack of 0x10000-0x600 == 0xfa00 == 64000 bytes after the BIOS data area.
; * EAX, EBX, ECX, EDX, ESI, EDI and EBP are set to 0.
; * CS is a read-execute full 4 GiB linear code segment, DS, ES, FS, GS and SS are the same read-write full 4 GiB linear data segment. Actual available memory may be less.
; * If there was a kernel command line, word [0x90020] is set to 0xa33f, and dword [0x90022] points to the command line (NUL-terminated byte string).
;   This is compatible with Linux kernel load protocol <=2.01, in which the pointer value is 0x90000 + word [0x90022].
; * The initial GDT is stored as 0x18 bytes at linear address 0x90000.
; * The bottom 16 bits of CR0 (i.e. the MSW) is 0x0001 (bit 0 PE is 1, the high 15 bits are 0).
; * The BIOS drive number (or 0xff if unknown) is available at byte [0x90007]. It is unknown for the Linux load protocol, unknown for Multiboot via QEMU (unused, QEMU recognizes Linux first), known for Multiboot via GRUB, and known for chain.
;
; Limitations of UKH:
;
; * No UEFI support, it can boot using only PC BIOS (legacy). No secure boot support.
; * No booting from CD (.iso image) yet.
; * Maximum kernel file size (excluding the boot sector and the setup sectors) is 512 KiB, maximum kernel code, data and uninitialized data size is 512 KiB total.
; * Only i386+ 32-bit protected mode kernels supported. No support for switching to long mode (64-bit, amd64, x86_64). No support for earlier Intel CPUs (such as 8086, 186, 286).
; * No support for architectures other than Intel (e.g. ARM, RISC-V, PowerPC, m68k).
;
; SYSLINUX 4.07 supports these file formats:
;
; * ```
;    kernel   | VK_KERNEL  | 0 | description         | choose by extension |
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
OUR_LINUX_BOOT_PROTOCOL_VERSION equ 0x201  ; 0x201 is the last one which loads everything under 0xa0000 (even 0x9a000). Later versions load code32 above 1 MiB (linear address >=0x100000).

MULTIBOOT_MAGIC equ 0x1badb002
MULTIBOOT_FLAG_AOUT_KLUDGE equ 1<<16
MULTIBOOT_INFO_CMDLINE equ 1<<2
OUR_MULTIBOOT_FLAGS equ MULTIBOOT_FLAG_AOUT_KLUDGE
OUR_MULTIBOOT_STARTUP_CODE_SIZE equ 0x84
OUR_MULTIBOOT_LOAD_ADDR equ 0x100000  ; The minimum value is 0x100000 (1 MiB), otherwise GRUB 1 0.97 fails with: Error 7: Loading below 1MB is not supported
OUR_MULTIBOOT_HEADER_SIZE equ 0x20

BXS_SIZE equ 0x400  ; Total size of boot sector and setup sectors.
KERNELSEG equ 0x1000
INITSEG equ 0x9000  ; We assume that BXS_SIZE bytes at boot_sector (including us) have been loaded to linear address INITSEG<<4.
BOOT_ENTRY_ADDR equ 0x7c00

LOADFLAG_READ:
.HIGH: equ 1 << 0

%macro halt 0
		cli
  %%back:	hlt
		jmp short %%back
%endm

; With the Linux load protocol, the bootloader loads the first 5 sectors
; (0xa00 bytes) (boot_sector and setup_sectors) to INITSEG<<4 (== 0x90000),
; the rest (code32) to KERNELSEG<<4 (== 0x10000) and then jumps to 0x9020:0
; (setup_sectors) in real mode. Thus it starts running the code at the
; beginning of setup_sectors, the sector following boot_sector.
;
; With the PX subtype of the chain load protocol, the bootloader loads the
; entire kernel file to BOOT_ENTRY_ADDR (0x7c00), and jumps to
; 0:BOOT_ENTRY_ADDR in real mode. Thus it starts running the code at the
; beginning of boot_sector. With other subtypes of the chain load protocol,
; the kernel file is loaded to a different address.
;
; With the Multiboot load protocol, the bootloader locates the multiboot
; header in the first 16 sectors (0x2000 == 8192 bytes), locates the
; Multiboot 1 header (`.multiboot:` in the source code), and loads a
; substring of the file to the address specified in the Multiboot v1 header,
; and jumps to the entry point (also specified there) in i386 32-bit
; protected mode. Thus it doesn't run any code in boot_sector or
; setup_sectors in real mode (unless the protected-mode code explicitly
; switches to real mode).
;
; Info about the BIOS drive number:
;
; * First floppy: 0, second floppy: 1 etc. First HDD: 0x80, second HDD: 0x81 etc.
; * The chain, DR-DOS, EDR-DOS and NTLDR load protocols pass it in DL.
; * The FreeDOS load protocol passes it in BL.
; * The DR-DOS 7.03 boot sector passes it in DL only.
; * The EDR-DOS 7.01.08 boot sector passes it in both BL and DL (BL is unnecessary).
; * The FreeDOS (checked versions 1.0--1.1--1.2--1.3) and SvarDOS (checked version 20240915) boot sector passes it in both BL and DL (DL is unnecessary).
; * The FreeDOS (checked version 1.3) kernel gets it from BL.
; * The SvarDOS (checked version 20240915) gets it from BL if the initial CS is 0x60 (FreeDOS load protocol), and from DL if the initial CS is 0x70 (DR-DOS load protocol).
boot_sector:  ; 1 sector of 0x200 bytes.
.start:
.cl_magic equ .start+0x20  ; (dw) The Linux bootloader will set this to: dw LINUX_CL_MAGIC (== 0xa33f).
.cl_offset equ .start+0x22  ; (dw) The Linux bootloader will set this to (dw) the offset of the kernel command line. The segment is INITSEG.
.cl_offset_high_word equ .start+0x24  ; (dw) Will be set to 9, so that dword [0x90022] can be used as a pointer to the kernel command line.
.gdt:  ; The first GDT entry (segment descriptor, 8 bytes) can contain arbitrary bytes, so we overlap it with boot code. https://stackoverflow.com/a/33198311
		; https://wiki.osdev.org/Global_Descriptor_Table#Segment_Descriptor
		; The GDT has to remain valid until the next lgdt instruction (potentially long), so we'll keep it at linear address 0x90000.
.code:		cld
		call .here
.here:		pop si  ; SI := actual offset of .here.
		jmp short .code2
.drive_number:  db 0xff  ; byte [0x90007]. Default value of 0xff indicates unknown, and it remains this way for the Linux load protocol and for the Multiboot load protocol via QEMU.
		assert_at .gdt+8  ; End if first GDT entry.
..@KERNEL_CS: equ $-.gdt
                dw 0xffff, 0, 0x9a00, 0xcf  ; Segment ..@KERNEL_CS == 8.    32-bit, code, read-execute, base 0, limit 4GiB-1, granularity 0x1000.  QEMU 2.11.1 linuxboot.S and GRUB 1 0.97 stage2/asm.S also have these values.
..@KERNEL_DS: equ $-.gdt
                dw 0xffff, 0, 0x9200, 0xcf  ; Segment ..@KERNEL_DS == 0x18. 32-bit, data, read-write,   base 0, limit 4GiB-1, granularity 0x1000.  QEMU 2.11.1 linuxboot.S and GRUB 1 0.97 stage2/asm.S also have these values.
                ;dw 0xffff, 0, 0x9e00, 0  ; ..@PSEUDO_RM_CS == 0x18. 16-bit, code, base 0. Used for switching back to real mode. GRUB 1 0.97 stage2/asm.S also has these values.
                ;dw 0xffff, 0, 0x9200, 0  ; ..@PSEUDO_RM_DS == 0x20. 16-bit, data, base 0. Used for switching back to real mode. GRUB 1 0.97 stage2/asm.S also has these values.
.gdt_end:	assert_at .gdt+3*8  ; Must be less than .cl_magic-.start, so that the GDT doesn' get overwritten.
.code2:		sub si, byte .here-.start  ; SI := actual offset of .start.
		mov ax, 0xe00+'?'  ; Set up error message.
		mov cx, cs
		test cx, cx
		jnz short .not_chain_protocol
		cmp si, BOOT_ENTRY_ADDR
		je short .chain_protocol
.not_chain_protocol:
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
.chain_protocol:  ; Now: CX == 0; DS == 0; SI == 0x7c00 == BOOT_ENTRY_ADDR; DL is the bios drive number.
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

		; Copy BXS_SIZE bytes from DS:SI (actually loaded boot_sector+setup_sectors) to INITSEG<<4 == 0x90000. There is no overlap.
		xor si, si
		xor di, di
		mov cx, BXS_SIZE>>1  ; Number of words to copy (even number of bytes).
		rep movsw
		jmp INITSEG:.after_far_jmp-.start  ; Jump to .after_far_jmp in the copy, to avoid overwriting the code doing the copy below (to KERNELSEG). Needed for the NTLDR load protocol.
.initseg_const equ $-2
.after_far_jmp:

		; Copy code32.end-code32 bytes from BOOT_ENTRY_ADDR+BXS_SIZE
		; == 0x8000 to KERNELSEG<<4 == 0x10000.
		;
		; We copy one sector (0x200) bytes at a time. This is
		; arbitrary. But we can't copy in one go, because the data
		; size is >=64 KiB, so we have to modify some segment registers.
		mov dx, 0x200>>4  ; Number of paragraphs per sector.
		mov bx, (code32.end-code32+0x1ff)>>9  ; Number of 0x200-byte sectors to copy. Positive.
		mov cx, ds
		add cx, strict word BXS_SIZE>>4  ; Skip over boot_sector+setup_sectors. !! Remove `strict word' if it becomes smaller.
		mov ax, KERNELSEG
		; Now: CX == segment of first source sector (with offset 0 it points to code32), minus BXS_SIZE>>4; AX == KERNELSEG.
		cmp cx, ax
		jae .after_setup_copy  ; Copy them in forward (ascending), because the destination comes before the source, and they may overlap.
.setup_backward_copy:  ; Copy them backward (descending), because the destination comes after the source, and they may overlap.
		neg dx  ; DX := -(0x200)>>4. Change copy direction to descending.
		add ax, strict word (((code32.end-code32+0x1ff)>>9)-1)<<5  ; Adjust destination segment to point to the last sector.
		add cx, strict word (((code32.end-code32+0x1ff)>>9)-1)<<5  ; Adjust source      segment to point to the last sector.
		;jmp short .after_setup_copy  ; Not needed, falls through.
;.setup_forward_copy:
		;mov dx, 0x200>>4  ; Already set.
		;mov ax, KERNELSEG  ; Already set. AX := segment of first destination sector.
		;mov es, ax  ; Already set. ES := segment of first destination sector.
		;add cx, 0 ;   Already set. CX := segment of first source sector (with offset 0 it points to code32), minus BXS_SIZE>>4.
		;mov ds, cx  ; Already set. DS := segment of first source sector (with offset 0 it points to code32), minus BXS_SIZE>>4.
.after_setup_copy:
		mov ds, cx
		mov es, ax
.copy_sector:	mov cx, 0x200>>1  ; Number of words in a sector.
		xor si, si
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
		cli
		jmp INITSEG:(setup_sectors.ck-boot_sector)

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
.setup_sects:	db 4  ; (read) The size of the setup in sectors. That is, the 32-bit kernel image starts at file offset (setup_sects+1)<<9. Must be 4 for compatibility with old-protocol Linux bootloaders (such as old LILO).
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


  cpu 386

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
		mov word [cs:jmp_offset-setup_sectors], ((INITSEG<<4)&0xffff)+linux_entry-boot_sector
		jmp INITSEG:.ck-boot_sector  ; Make `org 0' work. Otherwise CS:IP would remain: 0x9020:.ck-setup_sectors.
.ck:		cld

%ifndef MULTIBOOT  ; With Multiboot, we will do it in setup_32.
		mov word [boot_sector.cl_offset_high_word-boot_sector], 9  ; word [0x90022]. boot_sector.cl_offset_high_word.
%endif

%if 1  ; !! What's wroong if we don't bother with NMI?
		; now we want to move to protected mode ... !! Consider alternatives, such as how SYSLINUX 4.07 does it or how GRUB 1 0.97 does it.
		mov al, 0x80  ; disable NMI for the bootup sequence !! Why is this needed? https://wiki.osdev.org/Protected_Mode
		out 0x70, al
%endif

		; The system will move itself to its rightful place.
		; reload the segment registers and the stack since the
		; APs also execute this code
		mov ax, cs  ; INITSEG.
		mov ds, ax
		mov es, ax
		mov ss, ax  ; reset the stack to setup_stack...setup_stack+0x200.
		mov sp, boot_sector+6*0x200  ; 0x200 bytes of temporary real-mode stack, starting 5*0x200 bytes (loaded by the Linux bootloader) after INITSEG<<4. We need only a few bytes below for calls. !! Extend the stack all the way to INITSEG:0xa000-cmdline_size.
		; !! Can we do without a stack here (ESP == 0, memtest86+-5.01 code32 change ESP from 0 to something valid) if we get rid of the pushes and pops (including `push edi', `call' and `ret') below?
		; When switching back real mode, we want the original IDT, not an empty one like this. GRUB 1 0.97 doesn't set it. QEMU Linux boot and Multiboot v1 boot don't set it. https://stackoverflow.com/q/79526862 ; https://stackoverflow.com/a/5128933 .
		;lidt [idt_48-boot_sector]
		lgdt [gdt_48-boot_sector]  ; load gdt with whatever appropriate

%if 1  ; !! What is the best way to enable the A20 gate? Look at GRUB 1 0.97, GRUB4DOS, SYSLINUX 0.47.
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
		mov ah, [esp+4]  ; !!! Where does this come from? Who puts this value to ESP? It is surely incorrect.
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
%endif

		mov ax, 1  ; protected mode (PE) bit
		lmsw ax
		;mov eax, cr0  ; !! Why does lmsw work here but not when switching back to real mode?
		;or al, 1  ; PE := 1.
		;mov cr0, eax

		; Note that the short jump isn't strictly needed, although there are
		; reasons why it might be a good idea. It won't hurt in any case.
		jmp short .flush_instr
.flush_instr:	mov ax, ..@KERNEL_DS
		mov ds, ax
		mov es, ax
		mov ss, ax  ; This makes the stack useless, because ESP is now invalid. It's not a big problem, starts_32 will set it up soon, before that we don't use it, and interrupts are disabled.
		mov fs, ax
		mov gs, ax

		; No need to set .cl_magic, we are not passing a command line.
		jmp ..@KERNEL_CS:dword ((INITSEG<<4)+chain_entry-boot_sector)  ; Self-modifying code may change the offset here from chain_entry to linux_entry, using .jmp_offset.
jmp_offset: equ $-6

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

; These data bytes have to be valid only for the duration of the lgdt or lidt instruction. The table entries have to remain valid until the next lgdt or lidt instruction (i.e. long).
idt_48:		dw 0  ; idt limit=0. We overlap idt_base (dd 0) with gdt_48 below, since limit==0.
gdt_48:		dw boot_sector.gdt_end-boot_sector.gdt-1  ; gdt limit
		dd (INITSEG<<4)+boot_sector.gdt-boot_sector  ; gdt base = 0X9xxxx

%ifdef MULTIBOOT
		times BXS_SIZE-($-boot_sector)-OUR_MULTIBOOT_STARTUP_CODE_SIZE-OUR_MULTIBOOT_HEADER_SIZE db 0
		assert_fofs BXS_SIZE-OUR_MULTIBOOT_STARTUP_CODE_SIZE-OUR_MULTIBOOT_HEADER_SIZE
  multiboot_entry:  ; Loaded to OUR_MULTIBOOT_LOAD_ADDR by the bootloader. Works according to the Multiboot v1 specification: https://www.gnu.org/software/grub/manual/multiboot/multiboot.html
  cpu 386
  bits 32
		;cli  ; Not needed, https://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Machine-state mandates it.
		; We may not have a stack (ESP is invalid).
		cld
		;cmp eax, 0x2badb002  ; We ignore this Multiboot signature.
		;xchg ebp, eax  ; EBP := multiboot signature; EAX := junk.

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
		mov [ebx+4*4], edi  ; Change multiboot_info.cmdline back.
		mov eax, (0xa000-1)|LINUX_CL_MAGIC<<16
		sub eax, ecx
		ror eax, 16  ; Swap low and high words.
		mov [(INITSEG<<4)+boot_sector.cl_magic-boot_sector.start], eax  ; Also sets boot_sector.cl_offset.
		rep movsb  ; Test it by passing `btrace' in the memtest86+4.01 command line. It should show the *Press any key to advance to the next trace point* message at startup.
		xor eax, eax
		stosb  ; Add terminating NUL.

		mov esi, OUR_MULTIBOOT_LOAD_ADDR+OUR_MULTIBOOT_STARTUP_CODE_SIZE+OUR_MULTIBOOT_HEADER_SIZE  ; Linear address of code32.
		mov edi, KERNELSEG<<4
		mov ecx, (code32.end-code32+3)>>2
		rep movsd  ; We need this move, the memtest86+-5.x 32-bit kernel is not position-independent.

		jmp short start_32  ; With Multiboot load protocol we don't copy, the kernel is already at its right place.
  bits 16
  cpu 8086
%endif

linux_entry:  ; Setup registers and jump to kernel. We assume that already IF=0 (cli) and DF=0 (cld).
cpu 386
bits 32
		; Move code at KERNELSEG<<4 forward by 3 sectors. Copy the data backward (descending), because the destination comes after the source, and they may overlap.
		std
		mov esi, (KERNELSEG<<4)+((code32.end-code32-1-3*0x200)&~3)
		mov edi, (KERNELSEG<<4)+((code32.end-code32-1-3*0x200)&~3)+(3*0x200)
		mov ecx, (code32.end-code32+3-3*0x200)>>2
		rep movsd
		cld
		; Copy 3 sectors from (INITSEG<<4)+2*0x200 to KERNELSEG<<4.
		lea edi, [esi+4]  ; EDI := KERNELSEG<<4.
		mov esi, (INITSEG<<4)+2*0x200
		mov cx, (3*0x200)>>2  ; 1 byte shorter than `mov ecx, ...'.
		rep movsd
		; Fall through to start_32.

chain_entry:  ; Fall through to start_32.
start_32:  ; Linux, chain and Multiboot load protocols all end here.
		mov word [0x90022+2], 9  ; boot_sector.cl_offset_high_word.
		;xchg eax, ebp  ; EAX := Multiboot signature; EBP := 0.
		; EBX is still set to the address of the multiboot_info struct set up by the bootloader. https://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Boot-information-format
		mov esp, KERNELSEG<<4  ; A useful value. The Multiboot v1 specification allows any (nonworking) value in ESP.
		sub eax, eax  ; In EFLAGS, set OF=0, SF=0, ZF=1, AF=0, PF=1 and CF=0 according to the result.
		times 8 push eax
		popa  ; Set EAX, EBX, ECX, EDX, ESI, EDI and EBP to 0 (but not ESP). We do it for reproducibility.
		jmp esp  ; This works even if non-Multiboot code jumps into .setup_regs_and_jump_to_kernel.

		times (boot_sector.start-$)&3 nop  ; Align to multiple of 4.
bits 16
cpu 8086

%ifdef MULTIBOOT
  multiboot2:	assert_fofs BXS_SIZE-OUR_MULTIBOOT_HEADER_SIZE  ; If this fails, increase or decrease OUR_MULTIBOOT_STARTUP_CODE_SIZE by that amount.
  .multiboot_align_check: times -(($-boot_sector.start)&3) nop  ; Check alignment of the .multiboot_v1 below. GRUN 1 0.97
  .multiboot:  ; Multiboot v1 header, 0x20 bytes. i386 is hardcoded.
  .multiboot.magic: dd MULTIBOOT_MAGIC
  .multiboot.flags: dd OUR_MULTIBOOT_FLAGS
  .multiboot.checksum: dd -MULTIBOOT_MAGIC-OUR_MULTIBOOT_FLAGS
  .multiboot.header_addr: dd OUR_MULTIBOOT_LOAD_ADDR-(multiboot_entry-.multiboot)  ; This is smaller than OUR_MULTIBOOT_LOAD_ADDR. It would be ERR_EXEC_FORMAT if .multiboot came before load_addr.
  .multiboot.load_addr: dd OUR_MULTIBOOT_LOAD_ADDR  ; Linear address. ERR_BELOW_1MB for KERNELSEG<<4, thus we use OUR_MULTIBOOT_LOAD_ADDR and multiboot_copy_code32 instead.
  .multiboot.load_end_addr: dd OUR_MULTIBOOT_LOAD_ADDR+code32.end-multiboot_entry
  .multiboot.bss_end_addr:  dd OUR_MULTIBOOT_LOAD_ADDR+code32.end-multiboot_entry  ; No specific .bss to be cleared by the bootloader.
  .multiboot.entry_addr: dd OUR_MULTIBOOT_LOAD_ADDR
  .multiboot_end:
  .multiboot_size_check: assert_at .multiboot+0x20
%else
		times BXS_SIZE-($-boot_sector) db 0
%endif
		assert_fofs BXS_SIZE
setup_stack:  ; 0x200 bytes of stack from here.

code32:		; 32-bit kernel code (zImage, maximum 512 KiB), but it can be anything. Loaded to (KERNELSEG<<4) == 0x10000.
cpu 386
bits 32

%ifdef MEMTEST86PLUS5  ; Tested and works with memtest86+-5.01*.bin and memtest85+5.31b*.bin.
  %ifndef MEMTEST86PLUS5_BIN
    %define MEMTEST86PLUS5_BIN  'memtest86+-5.01-dist.bin'  ; Works. ~150 KiB.
    ;%define MEMTEST86PLUS5_BIN  'memtest86+-5.01.bin'  ; Works. Ubuntu. ~182 KiB. Larger probably because of different C compiler or flags.
    ;%define MEMTEST86PLUS5_BIN  'memtest86+-5.31b-dist.bin'  ; Works.
  %endif
		; It starts with cld, cli. It's not necessary, we set it up like that already.
		incbin MEMTEST86PLUS5_BIN, 0xa00
%else
  bits 32
  .back_to_real:  ; Switch back from protected mode to real mode. Code based on prot_to_real in stage2/asm.S in GRUB 1 0.97-29ubuntu68
		;cli  ; Not needed, already done.
		;mov esp, KERNELSEG<<4   ; Not needed, it already has this value. The value will be useful as SS:SP in real mode as well.
		;lgdt [.real_gdtr+((KERNELSEG<<4)-code32)]  ; Equivalent but longer than below. This seems to be needed, because the `mov cr0, eax' to leave protected mode works only in a 16-bit code segment.
		lgdt [byte esp+.real_gdtr-code32]  ; This seems to be needed, because the `mov cr0, eax' to leave protected mode works only in a 16-bit code segment. Without -code32 and byte it actually happens to work, because KERNELSEG<<4 is a multiple of 0x100.
		dw 0xea66, 0, .RM_REAL1_CS  ; Same as the jmp above, but 1 byte shorter because of the 16-bit offset.
  .real_gdt: equ $-8  ; Arbitrary values in the first segment descriptor.
  .RM_REAL1_CS: equ $-.real_gdt
  ;.real1_linear: equ (INITSEG<<4)+.real1-boot_sector  ; Linear address of .real1, as a NASM number (not label-based).
		dw 0xffff, code32.real1_linear&0xffff, 0x9e00|((code32.real1_linear>>16)&0xff), 0x8f|((code32.real1_linear>>24)&0xff)<<8  ; Segment .RM_CS == 8. 16-bit, code, read-execute, base .real1, limit 4GiB-1, granularity 0x1000.
  .real_gdt.end:
  .real_gdtr:	dw .real_gdt.end-.real_gdt-1  ; GDT limit.
		dd .real_gdt+((KERNELSEG<<4)-code32)  ; GDT base.

  .tmp_real1:  ; Now we are still in protected mode, but all segment registers point to 16-bit segments.
  .real1_linear: equ (KERNELSEG<<4)+code32.tmp_real1-code32  ; Linear address of code32.tmp_real1, as a NASM number (not label-based).
  bits 16  ; CS points to a 16-bit segment.
		mov eax, cr0
		and al, byte ~1  ; PE := 0. Leave protected mode, enter real mode.
		mov cr0, eax
		xor eax, eax
		xor esp, esp  ; This is needed (after .now_real) for subsequent QEMU 2.11.1 (and SeaBIOS) int 10h calls (but not for int 16h or int 19h), `mov sp 0' is no enough. This may be a limitation of SeaBIOS.
		;lmsw ax  ; BUGFIX: This doesn't work instead of modifyingc CR0, .tmp_real2 won't be reached. Why? (Ask on stackoverflow.com.)
		;o32 jmp KERNELSEG:dword .tmp_real2-code32  ; 8 bytes: 2 opcode, 4 offset, 2 segment.
		jmp KERNELSEG:.tmp_real2-code32  ; 5 bytes: 1 opcode, 2 offset, 2 segment. !! This only works if .tmp_real2 is close to the beginning of code32.
  .tmp_real2:  ; We are in real mode now.
		;xor ax, ax  ; No need, AX is already 0.
		mov ds, ax
		mov es, ax
		mov fs, ax
		mov gs, ax
		mov ss, ax

		mov bx, 0xb800
		mov es, bx
		mov word [es:2], 0x1700|'Q'  ; Write just after the top left corner to the text screen. It works.

		sti
  .now_real:  ; Real-mode kernel entry point CS=0x1000, AX=0, DS=ES=FS=GS=SS=0, SP=0 (stack available between 0x600 and 0x10000), IF=1 (sti).
		mov ax, 0xe00+'r'
		xor bx, bx  ; Set up printing.
		int 0x10  ; Print character in AL. !! Strange: changes the video mode instead in QEMU. Why
		xor ax, ax
		int 0x16  ; Wait for user keypress. Works.
		int 0x19  ; Reboot.
		; !! Disable the A20 gate. What does GRUB 1 0.97 do?
%endif

		%if $-boot_sector<0xa00  ; File size must be at least 5 sectors (0xa00 == 2560 bytes) for the old Linux load protocol.
		  times 0xa00-($-boot_sector) db 0
		%endif
.end:
