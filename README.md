# Universal Kernel Header (UKH)

The Universal Kernel Header (UKH) is a 1024-byte header that can be added
in front of i386+ 32-bit protected mode kernel images to make them
bootable using a multitude of bootloaders (hence the qualifier
*universal*). Currently the type of kernel support is limited, the first
one that has been finished is memtest86+-5.01.

UKH supports 32-bit compressed payloads compressed with `upxbc --flat32`
(see [upxpbc](https://github.com/pts/upxbc)).

The Universal Kernel Header (UKH) supports multiple load protocols:

* Linux: In our supported version, load first 2 sectors (2*0x200 == 0x400 bytes) to 0x90000, load remaining sectors to 0x10000, don't store the the BIOS drive number anywhere, jump to 0x:9020:0 (file offset 0x200). There are some Linux-specific header fields in file offset range 0x1f1...0x230 read and/or written by the bootloader, including BOOT_SIGNATURE. It can receive a command line. Specification: https://docs.kernel.org/arch/x86/boot.html
  * Actually, the Linux load protocol (2.01 and earlier) loads 5 sectors (number hardcoded to the old Linux load protocol) to 0x90000 and the remaining sectors to 0x10000, but to avoid waste 3 sectors worth of space, UKH will move 0x10000 3 sectors later, and then it copy over 3 sectors from 0x90000+2*0x200 to 0x10000.
  * Subtype Linux kernel old (<2.00) protocol: It doesn't check for the `HdrS` header at file offset 0x202. It always loads 5 sectors. Very old Linux bootloaders can load this, but not version 2.00 or 2.01.
  * Subtype Linux kernel protocol version 2.01 (also applies to 2.00): This implementation simulates the old protocol, but specifies more headers so that QEMU 2.11.1 is able to load it with `qemu-system-i386 -kernel`. There are some Linux-specific header fields in file byte range 0x1f1...0x230, including BOOT_SIGNATURE. It can receive a command line. Specification: https://docs.kernel.org/arch/x86/boot.html
  * Bootloaders supported: GRUBs (non-UEFI GRUB 2, GRUB 1 (GRUB Legacy), GRUB4DOS) with the *kernel* command (but GRUBs will use Multiboot instead if Multiboot was enabled at UKH compilation time; practically both work, but Multiboot also passes the BIOS drive number); SYSLINUX (and ISOLINUX and PXELINUX) with the *linux* command (or with the *kernel* command, but with a filename extension other than .com, .cbr, .c32, .img, .bss, .bin, .bs, .0); QEMU `qemu-system-i386 -kernel`; loadlin; LILO, and possibly others. The GRUBs recognize it as Multiboot first (if compiled with -DMULTIBOOT) rather than Linux.
* chain: Load entire kernel file (not only the first sector) to some base address (0x600, 0x700, 0x7c00 or 0x20000), set BL or DL to the BIOS drive number, jump to the beginning (0x60:0, 0x70:0, 0:0x7c00 or 0x2000:0). It can't receive a command line. The BOOT_SIGNATURE in file offset range 0x1fe...0x200 is needed by GRUB 1 0.97 `chainloader`, but not `chainloader --force`. It can't receive a command line.
  * UKH boot code autodetects the subtype by looking at CS:IP upon entry.
  * Please note that this boot mode works only if the bootloader loads the entire kernel file. Universal Kernel Header has a best-effort check for having loaded the first sector only. If the check fails, then it hangs with the message *bF*. There is no check for loading more than 29 KiB.
  * Subtype PXE: Load entire kernel file (in PXE terminology, NBP == Network Boot Program) to 0x7c00, don't set DL to the BIOS drive numbe, jump to 0:0x7c00. The maximum kernel file size depends on the PXE version: 2.0 (1999): 32 KiB; 2.1 (2003): 64 KiB; 2.2 (2008): unlimited. More info about PXE: https://wiki.osdev.org/PXE
  * Subtype FreeDOS (FreeDOS and SvarDOS *kernel.sys*): Load kernel file to 0x600, set BL to BIOS drive number, make one SS:BP (FreeDOS for the command line, between SS:SP (smaller) and SS:BP) and DS:BP (SvarDOS for .hidden_sector_count) point to the boot sector (we don't care), jump to 0x60:0. No header fields used. Both FreeDOS 1.3 and SvarDOS 20240915 kernel.sys kernels use BL only, and both boot sectors set BL and DL to the BIOS drive number. Maximum file size, limited by the FreeDOS and SvarDOS boot sectors: 134.5 KiB.
  * Subtype EDR-DOS (EDR-DOS 7.01.07--7.01.08 *drbio.sys*): load entire kernel file to 0x700, set DL to BIOS drive number, make DS:BP (EDR-DOS for .hidden_sector_count) point to the boot sector (we don't care), jump to 0x70:0. Maximum file size, limited by the EDR-DOS boot sector: 134.5 KiB.
  * Subtype DR-DOS (EDR-DOS 7.01.01--7.01.06 *ibmbio.com*, DR-DOS --7.0--7.01--7.02--7.03--7.05 *ibmbio.com*): They use the same load protocol as EDR-DOS (but with filename *ibmbio.com*), but the boot maximum kernel size its boot sector supports is 29 KiB (way too small for memtest86+), with its *ibmbio.com* being <24.25 KiB.
  * Subtype NTLDR (Windows NTLDR *ntldr* and GRUB4DOS bootlace.com *grldr*): Load at least first 0x24 bytes (.hidden_sector_count or the entire 0x24 byte substring, see https://retrocomputing.stackexchange.com/a/31399) of the boot partition (boot sector) to 0x7c00, load kernel file to 0x20000, set DL to the BIOS drive number, jump to 0x2000:0. No header fields used. The GRUB4DOS boot sector (installed with *bootlace.com*) uses the same protocol, looking for kernel file *grldr* rather than *ntldr*.
  * Bootloaders supported: non-UEFI GRUB 2 and GRUB4DOS (but not GRUB 1, because it loads only 512 bytes) with the *chainloader* command, SYSLINUX (and ISOLINUX and PXELINUX) with the *boot* command (or with the *kernel* command and a filename extensions .bin, .bs and .0); PXE network boot 2.0 and 2.1 (with small kernel file size limit), PXE network boot >=2.2; FreeDOS boot sector with filename *kernel.sys*; SvarDOS boot sector with filename *kernel*.sys*; EDR-DOS >=7.01.07 boot sector with filename *drbio.sys*; DR-DOS boot sector with filename *ibmbio.com*; Windows NT 3.1--3.5--3.51--4.0 boot sector with filename *ntldr*; Windows 2000--XP boot sector with filename *ntldr*; maybe Windows Vista-- boot sector with filename *bootmgr* (untested); * NTLDR from Windows NT boot.ini (`C:\NTLDR="label"`): maximum file size is 8 KiB, because it loads only the first 16 sectors (0x2000 == 8192 bytes) of the *ntldr* file, otherwise the same as the supported NTLDR above.
* Multiboot: It works according to the Multiboot v1 specification. It switches immediately to i386 32-bit protected mode. No code is run in real mode unless the kernel explicitly switches back to real mode. It can receive both command line and BIOS drive number, which is populated by GRUBs, but not QEMU 2.11.1. SYSLINUX supports it only with its *mboot.c32* file. Specification: https://www.gnu.org/software/grub/manual/multiboot/multiboot.html
  * With Multiboot v1, the kernel command line (passed in the Multiboot info struct) is respected. Test it by passing *btrace* to memtest86+-5.01 (will show the *Press any key to advance to the next trace point* message at startup) from GRUB: `kernel /m.mb btrace` and `boot`.
  * To disable Multiboot support in UKH, compile it without the `-DMULTIBOOT` NASM flag. (To enable it, compile it with the flag.)
  * GRUB 1 0.97 and GRUB4DOS detect Multiboot v1 signature first in the first 0x8000 bytes, overriding any other type of detection, such as the Linux kernel protocol >=2.00. It looks like that `kernel --type=multiboot` and `kernel --type=linux` can force the type, but in these cases, it can't, and the autodetected type is enforced.
  * Tested with GRUB 1 0.97-29ubuntu68 and GRUB4DOS 0.4.4. Tested with and without the Multiboot v1 header, also with *chainloader* (*chainloader* doesn't work with GRUB 1 0.97, because it only reads 1 sector). Also tested With SYSLINUX 4.07 *linux* and *boot*.
  * QEMU 2.11.1 `qemu-system-i386 -kernel` detects the Linux kernel protocol >=2.00 signature (`HdrS`) first, and then it detects the Multiboot v1 header.
  * Bootloaders supported: GRUBs (non-UEFI GRUB 2, GRUB 1 (GRUB Legacy), GRUB4DOS) with the *kernel* command, >=QEMU 2.11.1 with the `qemu-system-i386 -kernel` flag (it passes 0xff as the BIOS drive number), and possibly others.

Support may be added later for these load protocols:

* !! floppy without filesystem: Make the boot_sector read the rest of the file from floppy image, using `qemu-system-i386 -fda'. QEMU 2.11.1 detects floppy geometry using the image file size, and falls back to a prefix of 144OK (C*H*S == 80*2*18). See also: https://retrocomputing.stackexchange.com/q/31431 . See also RaWrite 1.3 autodetection (https://ridl.cfd.rit.edu/products/manuals/sunix/scsi/2203/html/RAWRITE.HTM), memtest86+-5.01 autodetection, Linux kernel floppy boot code autodetection.
* !! DOS MZ .exe, just to report that this is a kernel file which cannot be executed in DOS
* !! bootable CD (what are the options for preloading? or does it have to load emulated floppy sectors)?
* UEFI PE .exe: The latest memtest86+ (>=7.20) supports it: https://github.com/memtest86plus/memtest86plus/blob/a10664a2515a81b07ab8ae999f91e8151a87eec6/boot/x86/header.S#L798-L824
* MS-DOS and Windows 95--98--ME io.sys: The boot sector loads only the first 3 (MS-DOS --6.22) or 4 sectors of *io.sys*. Also a file named *msdos.sys* must be present for MS-DOS --6.22 boot code.
  * MS-DOS v6: MS-DOS 3.30--6.22, IBM PC DOS 3.30--6.x. IBM PC DOS 7.0--7.1 is almost identical. This loads only the first 3 sectors of the *io.sys* or *ibmbio.com* file, passing some info on how to find the rest, jumps to 0x70:0. It passes some info in registers and memory.
  * MS-DOS v7: MS-DOS 7.0--7.1--8.0, Windows 95--98--ME. This loads only the first 4 sectors of the *io.sys* or *ibmbio.com* file, passing some info on how to find the rest, jumps to 0x70:0x200. It passes some info in registers and memory.
* IBM PC DOS ibmbio.com: The boot sector loads only the first 3 sectors of *ibmbio.com*. Also a file named *ibmbio.com* must be present for IBM PC DOS boot code.

Limitations of UKH:

* No UEFI support, it can boot using only PC BIOS (legacy). No secure boot support.
* No booting from CD (.iso image) yet.
* Maximum kernel file size (excluding the boot sector and the setup sectors) is 512 KiB, maximum kernel code, data and uninitialized data size is 512 KiB total.
* Only i386+ 32-bit protected mode kernels supported. No support for switching to long mode (64-bit, amd64, x86_64). No support for earlier Intel CPUs (such as 8086, 186, 286).
* No support for architectures other than Intel (e.g. ARM, RISC-V, PowerPC, m68k).

The UKH load protocol for the 32-bit kernel (code32):

* The 32-bit kernel (code and data) is loaded to absolute linear address 0x10000, and the CPU is jumped to this address in i386+ 32-bit protected mode.
* The maximum kernel size (including code, data and uninitialized data) is 512 KiB == 0x80000 bytes. (This corresponds to the maximum file size of a Linux zImage kernel.)
* Uninitialized data after the loaded kernel code and data is not initialized, and can contain arbitary values. (This differs from C global variables in .bss, which are zero-initialized.)
* The A20 gate (A20 line) is enabled. See also: https://en.wikipedia.org/wiki/A20_line
* BIOS functionality is still available if the kernel switches back to real (8086) mode.
* Interrupts are disabled on entry (IF == 0, cli). The contents of the IDT is undefined.
* In EFLAGS, OF=0, DF=0, IF=0, SF=0, ZF=1, AF=0, PF=1, CF=0, other flags are in an undefined state.
* ESP is set to 0x10000, this gives the program an initial stack of 0x10000-0x600 == 0xfa00 == 64000 bytes after the BIOS data area.
* EAX, EBX, ECX, EDX, ESI, EDI and EBP are set to 0.
* CS is a read-execute full 4 GiB linear code segment, DS, ES, FS, GS and SS are the same read-write full 4 GiB linear data segment. Actual available memory may be less.
* If there was a kernel command line, word [0x90020] is set to 0xa33f, and dword [0x90022] points to the command line (NUL-terminated byte string). The high word of the dword is always 0.
  * This is compatible with Linux kernel load protocol <=2.01, in which the pointer value is 0x90000 + word [0x90022].
  * Some bootloaders prepend a string to the kernel command line, for example GRUB 1 0.97 and GRUB4DOS prepend the pathname and the space (so the command line will have all the arguments of the *kernel* command), and SYSLINUX 4.07 prepends `BOOT_IMAGE=`, the kernel filename and a space. QEMU 2.11.1 doesn't prepend anything.
* The initial GDT is stored as 0x18 bytes at linear address 0x90000.
* The bottom 16 bits of CR0 (i.e. the MSW) is 0x0001 (bit 0 PE is 1, the high 15 bits are 0).
* The BIOS drive number (or 0xff if unknown) is available at byte [0x90007]. It is unknown for the Linux load protocol, unknown for Multiboot via QEMU (unused, QEMU recognizes Linux first), known for Multiboot via GRUB, and known for chain.
* Calling software interrupts (such as BIOS video services wit int 10h) is not supported in protected mode. Call it like this: call ukh_real_mode, do sti, do the *int ...* instruction, and then call ukh_protected_mode_far.
* UKH provides the following API functions:
  * API function ukh_real_mode and NASM macro ukh_real_mode. Switches from 32-bit protected mode to real mode. Call it from 32-bit protected mode at 0x90232. Doesn't enable (sti) or disable (cli) interrupts.
  * API function ukh_protected_mode_far and NASM macro ukh_protected_mode. Switches from real mode to 32-bit protected mode. Call it from real mode as far call at 0x9000:0x230. Disables interrupts (cli).
  * API function ukh_a20_gate_far and NASM macro ukh_a20_gate_al. Call it from real mode with interrupts disabled as far call at 0x9000:4. AL=0 disables the A20 gate (allows less than 1 MiB of memory), AL=1 enables the A20 gate.
  * NASM macro ukh_halt. Halts the system in an infinite loop. Works in both protected mode and real mode.

SYSLINUX 4.07 supports these file formats:

|command  |symbol     |ID|description         |extensions |
|---------|-----------|--|--------------------|-----------|
|kernel   |VK_KERNEL  | 0|choose by extension |choose by extension|
|linux    |VK_LINUX   | 1|Linux kernel image  |any other than .com, .cbt, .c32, .img, .bss, .bin, .bs, .0|
|boot     |VK_BOOT    | 2|Boot sector         |.bin, .bs, .0|
|bss      |VK_BSS     | 3|BSS boot sector     |.bss|
|pxe      |VK_PXE     | 4|PXE NBP             ||
|fdimage  |VK_FDIMAGE | 5|Floppy disk image   |.img, forced error by SYSLINUX 4.07 (is_disk_image)|
|comboot  |VK_COMBOOT | 6|COMBOOT image       |.com, .cbt|
|com32    |VK_COM32   | 7|COM32 image         |.c32|
|config   |VK_CONFIG  | 8|configuration file  ||

In SYSLINUX, *bss* is like *boot*, but after loading to kernel file, bytes 0xb..0x25 of the kernel file are ignored (good enough for FAT12 and FAT16, too short for FAT32), and the bytes from the boot sector are used instead of them.

Testing notes:

* memtest86+-5.01 needs least 4 MiB of memory in QEMU 2.11.1 (QEMU fails with 3 MiB), hence the `qemu-system-i386 -m 4` flag.
* Test command line support (even with Multiboot v1) by passing `btrace' in the memtest86+4.01 command line. It should show the *Press any key to advance to the next trace point* message at startup.

TODOs:

* Copy the kernel command line to linear address 0x903e0. That's the smallest, because earlier bytes are used by the .protected_mode_far and .real_mode library functions.
* Compress the 32-bit payload with `upxbc --flat32`. This will also make the kernel shorter than 134.5 KiB, and original FreeDOS, SvarDOS and EDR-DOS boot sectors will work.
* Make the 4 setup sectors shorter, *rep movsd* code and data around. We have to keep .setup_sects == 4, for compatibility with the Linux kernel old protocol.
* Add progress indicator to the LZMA decompressor.
* Add support for 16-bit payload.
* Add support for multiboot with 16-bit payload. Switch back to real mode.
* Add `upxbc --flat16x` and `apack1p -1 -x` compressor for the 16-bit payload. Make this compression without a prefix.
* Apply some Ubuntu bugfix patches to the memtest86+-5.01-dist.bin binary.
* Instead of halting, wait for keypress and reboot.
* See how much better memtest86+-5.01.bin compresses (uncompressed size is about 32 KiB larger).
* Simplfy jumps in upxbc --flat32 decompress and lxunfilter functions.
* Add GRUB 1 0.97-29ubuntu68 as an UKH image.
* Add SYSLINUX 4.07 as an UKH image.
* Add a modified Liigboot as an UKH image.
* Add --ukh format support (an extension of --flat32, and later --flat16) to upxbc. This will be tricky, because the payload size is everywhere.
