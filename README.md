# Universal Kernel Header (UKH)

The Universal Kernel Header (UKH) is a library in NASM assembly which makes
easy to write i386 (32-bit protected mode) operating system kernels. A
kernel image file built with UKH is bootable using a multitude of
bootloaders (hence the qualifier *universal*) such as GRUB, SYSLINUX, LILO,
NTLDR, QEMU *-kernel*, PXE, FreeDOS boot sector. UKH can be used for writing
i86 (Intel 16-bit real mode) kernels as well, because it can switch back to
real mode. UKH provides an API for switching between modes (32-bit protected
mode and 16-bit real mode), receiving the kernel command-line string, and
receiving the BIOS boot drive number. UKH supports specifying a version
string (displayed by the *file* command and GRUB). UKH can compress the
kernel payload with LZMA or LZSS. UKH adds an 1024-byte header header to the
kernel payload code written by the kernel programmer. UKH is suitable for
beginners kernel developers: they can start writing their kernel code in a
combination of 32-bit protected mode and (16-bit) real mode, without even
knowing how to switch between modes.

## Tutorial

Example kernel source (copy it to file example.nasm):

```
%define UKH_PAYLOAD_32
;%define UKH_VERSION_VERSION_STRING '...'  ; Optional.
;%define UKH_... ...  ; Optional.
%include 'ukh.nasm'

; This is the payload code of your kernel. It starts in 32-bit protected
; mode, see more info later.
mov word [0xb8000], 0x1700|'1'  ; Write to the top left corner to the text screen. It works.
ukh_real_mode  ; Switch back to real mode.
mov bx, 0xb800
mov es, bx
mov word [es:2], 0x1700|'2'  ; Write just after the top left corner to the text screen. It works.
ukh_protected_mode  ; Switch to 32-bit protected mode.
mov word [0xb8004], 0x1700|'3'  ; Write just 2 characetrs after the top left corner to the text screen. It works.
ukh_real_mode  ; Switch back to real mode.
mov ax, 0xe00+'B'  ; Set up printing character 'B'.
xor bx, bx  ; Set up printing.
int 0x10  ; Print character 'B' to the screen.
xor ax, ax
int 0x16  ; Wait for user keypress.
int 0x19  ; Reboot.

ukh_end  ; This must always be at the end your kernel source file.
```

Compile the example kernel above with: `nasm -O0 -w+orphan-labels -f bin -o example.multiboot.bin example.nasm`

Minimum NASM version required 0.98.39.

Run the example kernel above with: `qemu-system-i386 -M pc-1.0 -m 4 -nodefault -vga cirrus -kernel example.multiboot.bin`

Compile the test kernel ([testk1.nasm](testk1.nasm)) with: `nasm -O0
-w+orphan-labels -f bin -o testk1.multiboot.bin testk1.nasm`.

Run the test kernel with: `qemu-system-i386 -M pc-1.0 -m 4 -nodefault -vga cirrus -kernel testk1.multiboot.bin`

## The UKH API

The general model of kernel development with UKH is:

* You write your kernel payload code as a NASM source file containing mostly
  i386 (32-bit protected mode) code.
* The kernel starts executing at the first code byte, i.e. the entry point
  is right after the `%include 'ukh.nasm'` in protected mode. Use the API
  instruction *ukh_real_mode* to switch to real mode (also does a NASM *bits
  16*) any time. Use the API instruction *ukh_protected_mode* to switch to
  protected mode (also does a NASM *bits 32*) any time.
* When switching to protected mode, interrupts are disabled (i.e. automatic
  *cli*). To handle the interrupts, switch back to real mode, and then
  enable interrupts with *sti*.
  Alternatively, set up your own interrupt handling in protected mode.
* To call BIOS services (such as *int 10h* for video, *int 13h* for disk
  read and write, *int 16h* for keyboard), switch to real mode first. You
  can switch back to protected mode right after the call.
* Use the UKH API (see below) to receive the kernel command-line string.
* Use the UKH API (see below) to receive the BIOS boot drive number.
* To use uninitialized data in your kernel (such as global variables,
  especially larger arrays, which will be initialized from code), add
  `absolute $` above `ukh_end`, and add your variables as labels and `resb`
  instructions in-between. Example:
  ```
  absolute $  ; Uninitialized data follows.
  resb ($$-$)&3  ; Align to multiple of 4.
  myvar1: resb 4
  myvar2: resb 2
  ukh_end
  ```
* Uninitialized data after the loaded kernel image (code and data) is not
  initialized, and can contain arbitary byte values. (This differs from C
  global variables in .bss, which are zero-initialized.)
* In the beginning, use BIOS service *int 13h* to read sectors (of 512
  bytes) from the disk (floppy or HDD). UKH doesn't provide any filesystem
  support, eventually you have to implement that yourself in your kernel.
* Your kernel payload code (starting with the entry point byte) is loaded to
  linear address 0x10000 (0x1000:0 in real mode).
* The [A20 gate](https://en.wikipedia.org/wiki/A20_line) (A20 line) is
  enabled when your kernel payload code starts running. This means that your
  kernel is able to access physical memory above the first 1 MiB. You can
  use *ukh_a20_gate_far* and *ukh_a20_gate_al* (see below) to enabled or
  disable it.
* The top of the stack (ESP) is at linear address 0xfffc (0:0xfffc in real
  mode), the bottom of the stack is at liner address 0x520 (below that there
  are some BIOS data structures and the interrupt vector table). Thus the
  stack size is 0xfffc - 0x520 == 64220 bytes.
* The 1024-byte UKH header is loaded to linear address 0x90000 (0x9000:0 in
  real mode), and it modifies some of its bytes after loading. The kernel
  command-line string is stored between linear addresses 0x90400 and
  0xa0000.
* When switching between modes, the stack remains at the same location,
  SS:ESP doesn't change, and a few bytes are used temporarily on the stack.
  In real mode, SS is 0, in protected mode, the base address of SS is 0.
* When switching to real mode, DS, ES and FS are changed to 0x100
  (so that e.g. DS:0 points to the beginning of your kernel payload code).
* When switching to real mode, EIP set to the low 16 bits of next_EIP, CS is
  set to `(next_EIP&0xf0000)>>4`. Thus CS:IP points to the next instruction
  byte. This works within the first 1 MiB of (physical) memory.
* Apart from the interrupt flag IF, CS:EIP, DS, ES, FS and GS, other
  registers are unchanged when switching between modes.
* Initial state when your kernel payload code starts running:
  * EAX == EBX == ECX == EDX == ESI == EDI == EBP == 0.
  * CR0 has bit 0 (PE) set, indicating protected mode.
  * EFLAGS:
    * IF == 0 (*cli*, interrupts disabled in protected mode).
    * DF == 0 (*cld*).
    * CF == 0 (*clc*).
    * OF == 0, SF == 0, ZF == 1, AF == 0, PF == 1.
    * Other flags are undefined.
  * CS:EIP == 8:0x10000. Segment descriptor 8 has base 0 (start of physical
    memory), and it is unlimited (full 4 GiB), and is 32-bit (i386, 32-bit
    protected mode). Actual available memory may be less than 4 GiB.
  * DS == ES == FS == GS == 0x10. Segment descriptor 0x10 has base (start of
    physical memory), and it is unlimited (full 4 GiB).
  * SS:ESP == 0x10:0xfffc.
  * The A20 gate is enabled, i.e. memory above 1 MiB is available.
  * The contents of the Interrupt Descriptor Table (IDT) is undefined. That's
    no a problem, because interrupts are disabled in protected mode.
* The maximum kernel size (including code, data and uninitialized data) is
  512 KiB == 0x80000 bytes. (This corresponds to the maximum file size of a
  Linux zImage kernel.)
* The Global Descriptor Table (GDT) is stored as 0x18 bytes (up to 0x28
  bytes) at linear address 0x90000.
* NASM `org 0x10000-0x400` is in active, so that your kernel payload code
  will have NASM virtual address 0x10000, corresponding to the initial EIP
  value, and it will also make global variables (accessed using CS, DS, ES,
  FS, GS and SS) work. The 0x400 in the formula above corresponds to the UKH
  header of 1 KiB.

The UKH API provides to following functionality to your kernel payload:

* Use the *ukh_real_mode* NASM macro to switch to real mode. It also does
  *bits 16* for you. Alternatively, you can also do *call
  ukh_real_mode_flat*, but the former is safer, because it checks that
  protected mode is active. It doesn't enable or disable interrupts. It
  doesn't enable or disable the A20 gate.
* Alternatively, to switch to real mode and then jump to a specific
  segment:offset, do `push dword (the_segment<<16)|the_offset` followed by
  `jmp ukh_real_mode_far`. Make sure you do this only in protected mode,
  and manage the NASM *bits* manually.
* Use the *ukh_protected_mode* NASM macro to switch to 32-bit protected
  *mode. It also does *bits 32* for you. It disables interrupts.
* To halt the system, use the NASM macro *ukh_halt* in either mode. It is
  equivalent to *cli* followed by *hlt* followed by an infinite loop.
* To enable (with nonzero AL) or disable (with AL == 0) the A20 gate,
  use the NASM macro *ukh_a20_gate_al* in real mode. It doesn't work in
  protected mode, and it checks for *bits* == 16 for you.
* To get the BIOS boot drive number, get the `byte [ukh_drive_number_flat]`
  in protected mode (or the eqivalent segment:offset in real mode). If this
  byte is 0xff, then the BIOS boot drive number is unknown. It's always
  unknown for the Linux load protocol, and it is known for the Multiboot load
  protocol via GRUB and it is known for the chain load protocol. (It's also
  unnown for Multiboot via QEMU, but that's not used, because the Linux load
  protocol is used instead, which also has it unavailable.)
* The BIOS boot partition number or sector offset (LBA) is not available.
* To get the kernel command-line string, first check that `word
  [ukh_kernel_cmdline_magic]` has value UKH_KERNEL_CMDLINE_MAGIC_VALUE (==
  0xa33f) in protected mode.
  (If it has a different value, then there is no kernel command-line
  string.) After that, you can filnd the kernel command-line string as a
  NUL-terminated byte string starting at linear address pointed to by `dword
  [ukh_kernel_cmdline_ptr]` in protected mode. The high word of this dword
  is always 9.
  * Please note that the address of the kernel command-line string is
    compatible with Linux kernel load protocol <=2.01, where the linear
    address is 0x90000 + word [0x90022].
  * Some bootloaders prepend a string to the kernel command-line string, for
    example GRUB 1 0.97 and GRUB4DOS prepend the pathname and the space (so
    the command line will have all the arguments of the *kernel* command),
    and SYSLINUX 4.07 prepends `BOOT_IMAGE=`, the kernel filename and a
    space. QEMU 2.11.1 doesn't prepend anything.

## Features

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
  * Subtype FreeDOS (FreeDOS and SvarDOS *kernel.sys*): Load kernel file to 0x600, set BL to BIOS drive number, make one SS:BP (FreeDOS for the command line, between SS:SP (smaller) and SS:BP) and DS:BP (SvarDOS for .hidden_sector_count) point to the boot sector (we don't care), jump to 0x60:0. No header fields used. Both FreeDOS 1.3 and SvarDOS 20240915 kernel.sys kernels use BL only, and both boot sectors set BL and DL to the BIOS drive number. There is a kernel command-line string for FreeDOS, but is there one for SvarDOS? Maximum file size, limited by the FreeDOS and SvarDOS boot sectors: 134.5 KiB.
  * Subtype EDR-DOS (EDR-DOS 7.01.07--7.01.08 *drbio.sys*): load entire kernel file to 0x700, set DL to BIOS drive number, make DS:BP (EDR-DOS for .hidden_sector_count) point to the boot sector (we don't care), jump to 0x70:0. Is there a kernel command-line string? Maximum file size, limited by the EDR-DOS boot sector: 134.5 KiB.
  * Subtype DR-DOS (EDR-DOS 7.01.01--7.01.06 *ibmbio.com*, DR-DOS --7.0--7.01--7.02--7.03--7.05 *ibmbio.com*): They use the same load protocol as EDR-DOS (but with filename *ibmbio.com*), but the boot maximum kernel size its boot sector supports is 29 KiB (way too small for memtest86+), with its *ibmbio.com* being <24.25 KiB.
  * Subtype NTLDR (Windows NTLDR *ntldr* and GRUB4DOS bootlace.com *grldr*): Load at least first 0x24 bytes (.hidden_sector_count or the entire 0x24 byte substring, see https://retrocomputing.stackexchange.com/a/31399) of the boot partition (boot sector) to 0x7c00, load kernel file to 0x20000, set DL to the BIOS drive number, jump to 0x2000:0. No header fields used. The GRUB4DOS boot sector (installed with *bootlace.com*) uses the same protocol, looking for kernel file *grldr* rather than *ntldr*.
  * Bootloaders supported: non-UEFI GRUB 2 and GRUB4DOS (but not GRUB 1, because it loads only 512 bytes) with the *chainloader* command, SYSLINUX (and ISOLINUX and PXELINUX) with the *boot* command (or with the *kernel* command and a filename extensions .bin, .bs and .0); PXE network boot 2.0 and 2.1 (with small kernel file size limit), PXE network boot >=2.2; FreeDOS boot sector with filename *kernel.sys*; SvarDOS boot sector with filename *kernel*.sys*; EDR-DOS >=7.01.07 boot sector with filename *drbio.sys*; DR-DOS boot sector with filename *ibmbio.com*; Windows NT 3.1--3.5--3.51--4.0 boot sector with filename *ntldr*; Windows 2000--XP boot sector with filename *ntldr*; maybe Windows Vista-- boot sector with filename *bootmgr* (untested); * NTLDR from Windows NT boot.ini (`C:\NTLDR="label"`): maximum file size is 8 KiB, because it loads only the first 16 sectors (0x2000 == 8192 bytes) of the *ntldr* file, otherwise the same as the supported NTLDR above.
* Multiboot: It works according to the Multiboot v1 specification. It switches immediately to i386 32-bit protected mode. No code is run in real mode unless the kernel explicitly switches back to real mode. It can receive both command line and BIOS drive number, which is populated by GRUBs, but not QEMU 2.11.1. SYSLINUX supports it only with its *mboot.c32* file. Specification: https://www.gnu.org/software/grub/manual/multiboot/multiboot.html
  * With Multiboot v1, the kernel command-line string (passed in the Multiboot info struct) is respected. Test it by passing *btrace* to memtest86+-5.01 (will show the *Press any key to advance to the next trace point* message at startup) from GRUB: `kernel /m.mb btrace` and `boot`.
  * To disable Multiboot support in UKH, compile it without the `-DMULTIBOOT` NASM flag. (To enable it, compile it with the flag.)
  * GRUB 1 0.97 and GRUB4DOS detect Multiboot v1 signature first in the first 0x8000 bytes, overriding any other type of detection, such as the Linux kernel protocol >=2.00. It looks like that `kernel --type=multiboot` and `kernel --type=linux` can force the type, but in these cases, it can't, and the autodetected type is enforced.
  * Tested with GRUB 1 0.97-29ubuntu68 and GRUB4DOS 0.4.4. Tested with and without the Multiboot v1 header, also with *chainloader* (*chainloader* doesn't work with GRUB 1 0.97, because it only reads 1 sector). Also tested With SYSLINUX 4.07 *linux* and *boot*.
  * QEMU 2.11.1 `qemu-system-i386 -kernel` detects the Linux kernel protocol >=2.00 signature (`HdrS`) first, and then (as a fallback if Linux kernel not found), it detects the Multiboot v1 header.
  * Bootloaders supported: GRUBs (non-UEFI GRUB 2, GRUB 1 (GRUB Legacy), GRUB4DOS) with the *kernel* command, >=QEMU 2.11.1 with the `qemu-system-i386 -kernel` flag (it passes 0xff as the BIOS drive number), and possibly others.

Support for these load protocols may be added later:

* floppy without filesystem: Make the boot_sector read the rest of the file from floppy image, using `qemu-system-i386 -fda'. QEMU 2.11.1 detects floppy geometry using the image file size, and falls back to a prefix of 144OK (C*H*S == 80*2*18). See also: https://retrocomputing.stackexchange.com/q/31431 . See also RaWrite 1.3 autodetection (https://ridl.cfd.rit.edu/products/manuals/sunix/scsi/2203/html/RAWRITE.HTM), memtest86+-5.01 autodetection, Linux kernel floppy boot code autodetection.
* DOS MZ .exe, just to report that this is a kernel file which cannot be executed in DOS
* bootable CD (what are the options for preloading? or does it have to load emulated floppy sectors)?
* UEFI PE .exe: The latest memtest86+ (>=7.20) supports it: https://github.com/memtest86plus/memtest86plus/blob/a10664a2515a81b07ab8ae999f91e8151a87eec6/boot/x86/header.S#L798-L824
* MS-DOS and Windows 95--98--ME io.sys: The boot sector loads only the first 3 (MS-DOS --6.22) or 4 sectors of *io.sys*. Also a file named *msdos.sys* must be present for MS-DOS --6.22 boot code.
  * MS-DOS v6: MS-DOS 3.30--6.22, IBM PC DOS 3.30--6.x. IBM PC DOS 7.0--7.1 is almost identical. This loads only the first 3 sectors of the *io.sys* or *ibmbio.com* file, passing some info on how to find the rest, jumps to 0x70:0. It passes some info in registers and memory.
  * MS-DOS v7: MS-DOS 7.0--7.1--8.0, Windows 95--98--ME. This loads only the first 4 sectors of the *io.sys* or *ibmbio.com* file, passing some info on how to find the rest, jumps to 0x70:0x200. It passes some info in registers and memory.
* IBM PC DOS ibmbio.com: The boot sector loads only the first 3 sectors of *ibmbio.com*. Also a file named *ibmbio.com* must be present for IBM PC DOS boot code.

UKH supports 32-bit compressed payloads compressed with `upxbc --flat32`
(see [upxbc](https://github.com/pts/upxbc)).

Limitations of UKH:

* No UEFI support, it can boot using only PC BIOS (legacy). No secure boot support.
* No booting from CD (.iso image) yet.
* Maximum kernel file size (excluding the boot sector and the setup sectors) is 512 KiB, maximum kernel code, data and uninitialized data size is 512 KiB total.
* Only i386+ 32-bit protected mode kernels supported. No support for switching to long mode (64-bit, amd64, x86_64). No support for earlier Intel CPUs (such as 8086, 186, 286). 16-bit real mode support may be added later.
* No support for architectures other than Intel (e.g. ARM, RISC-V, PowerPC, m68k).

## Misc notes

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

Data passing for DOS kernels (this is independent of UKH), based on https://pushbx.org/ecm/doc/ldosboot.htm :

* DR-DOS, EDR-DOS and SvarDOS from boot sector to kernel:
  * DL == BIOS drive number used for booting.
  * DS:BP points to a memory region of <=0x5a bytes containing the beginning of the boot sector.
  * SS:SP points to a top of a valid stack.
  * Is there a kernel command line?
* FreeDOS from boot sector to kernel:
  * BL == BIOS drive number used for booting.
  * SS:BP points to a memory region of <=0x5a bytes containing the beginning of the boot sector.
  * SS:SP..SS:BP contains the kernel command line if properly set up. SP <= BP.
  * SS:SP points to a top of a valid stack.
* MS-DOS v6 load protocol (MS-DOS 3.30--6.22 and IBM PC DOS 3.30--7.1) from msload (first <=0x600 bytes of io.sys) to msbio:
  * DL == BIOS drive number used for booting.
  * CH == media descriptor.
  * AX:BX == sector offset (LBA) of the clusters (i.e. cluster 2) in this FAT filesystem, from the beginning of the BIOS drive.
  * SS:SP points to a top of a valid stack.
  * IBM PC DOS 7.1 expects some values on the stack.
  * Low  word of the start cluster number of load file. For MS-DOS v7. Already filled: word [0x51a] for IBM PC DOS 7.1. Probably not needed.
  * High word of the start cluster number of load file. For MS-DOS v7. Already filled: word [0x514] for IBM PC DOS 7.1, FAT32. Probably not needed.
  * Low  word of start cluster number of 2nd load file (ibmdos.com) at word [0x53a]. For IBM PC DOS 7.1.
  * High word of start cluster number of 2nd load file (ibmdos.com) at word [0x534]. For IBM PC DOS 7.1, FAT32.
* MS-DOS v7 load protocol from msload (first 0x800 bytes of io.sys) to msbio:
  * AX == 0. `mov ax, [0x7fa]' of the original (0x800-byte) msload, the value is 0.
  * BX == 0. `mov ax, [0x7fa+2]' of the original (0x800-byte) msload, the value is 0.
  * DI == msbio_passed_para_count == load_para_count. Number of paragraphs before MSDCM (total in msload and msbio). Original Windows 98 SE msbio passed a smaller value, the exact value being very strange.
  * DL == BIOS drive number used for booting.
  * DH == media descriptor.
  * SS:SP points to a top of a valid stack.
  * SS:BP points to a memory region of <=0x5a bytes containing the beginning of the boot sector.

Testing notes:

* memtest86+-5.01 needs least 4 MiB of memory in QEMU 2.11.1 (QEMU fails with 3 MiB), hence the `qemu-system-i386 -m 4` flag.
* Test command line support (even with Multiboot v1) by passing `btrace' in the memtest86+4.01 command line. It should show the *Press any key to advance to the next trace point* message at startup.

See [this forum
thread](https://sourceforge.net/p/freedos/mailman/message/37871507/) about
passing a kernel command-line string to the FreeDOS kernel (kernel.sys).

## TODOs

* Add load protocol: floppy without filesystem.
* Add load protocol: DOS MZ .exe, just to report that this is a kernel file which cannot be executed in DOS.
* Add load protocol: bootable CD.
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
