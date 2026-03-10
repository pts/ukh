;
; ukh.nasm: Universal Kernel Header (UKH)
; by pts@fazekas.hu at Mon Mar 17 13:45:39 CET 2025
;
; Example kernel source (copy it to file example.nasm):
;
;   %define UKH_PAYLOAD_32
;   ;%define UKH_VERSION_VERSION_STRING '...'  ; Optional.
;   ;%define UKH_... ...  ; Optional.
;   %include 'ukh.nasm'
;
;   ; This is the payload code of your kernel. It starts in 32-bit protected
;   ; mode, see more info later.
;   mov word [0xb8000], 0x1700|'1'  ; Write to the top left corner to the text screen. It works.
;   ukh_real_mode  ; Switch back to real mode.
;   mov bx, 0xb800
;   mov es, bx
;   mov word [es:2], 0x1700|'2'  ; Write just after the top left corner to the text screen. It works.
;   ukh_protected_mode  ; Switch to 32-bit protected mode.
;   mov word [0xb8004], 0x1700|'3'  ; Write just 2 characetrs after the top left corner to the text screen. It works.
;   ukh_real_mode  ; Switch back to real mode.
;   mov ax, 0xe00+'B'  ; Set up printing character 'B'.
;   xor bx, bx  ; Set up printing.
;   int 0x10  ; Print character 'B' to the screen.
;   xor ax, ax
;   int 0x16  ; Wait for user keypress.
;   int 0x19  ; Reboot.
;
; Compile the example kernel above with: nasm -O0 -w+orphan-labels -f bin -o example.multiboot.bin example.nasm
; Minimum NASM version required 0.98.39.
; Run the example kernel with: qemu-system-i386 -M pc-1.0 -m 4 -nodefault -vga cirrus -kernel example.multiboot.bin
;
; Compile the test kernel with: nasm -O0 -w+orphan-labels -f bin -o testk1.multiboot.bin testk1.nasm  # Includes ukh.nasm.
; Run the test kernel with: qemu-system-i386 -M pc-1.0 -m 4 -nodefault -vga cirrus -kernel testk1.multiboot.bin
;
; See more documentation (including the API and the load protocol) in README.md.
;

; --- Configuration.

%ifdef UKH_MULTIBOOT
  %ifdef UKH_NO_MULITBOOT
    %error ERROR_CONFIG_CONFLICT_MULTIBOOT
    db 1/0
  %endif
%elifndef UKH_NO_MULTIBOOT
  %define UKH_MULTIBOOT  ; Enable it by default.
%endif

%ifdef UKH_PAYLOAD_32_FILE  ; Must be a filename in quotes.
  %define UKH_PAYLOAD_32
  %define __UKH_PAYLOAD_FILE UKH_PAYLOAD_32_FILE
%endif

%ifdef UKH_PAYLOAD_16_FILE  ; Must be a filename in quotes.
  %define UKH_PAYLOAD_16
  %define __UKH_PAYLOAD_FILE UKH_PAYLOAD_16A_FILE
%endif

%ifdef UKH_PAYLOAD_16
  %ifdef UKH_PAYLOAD_32
    %error ERROR_CONFIG_CONFLICT_PAYLOAD_16_32
    db 1/0
  %endif
%elifndef UKH_PAYLOAD_32
  %error ERROR_MISSING_PAYLOAD_TYPE  ; Add e.g. `%define UKH_PAYLOAD_32'.
  db 1/0
%endif

%ifdef UKH_PAYLOAD_FILE_SKIP  ; Number of bytes to skip near the beginning. Nonnegative integer constant.
  %assign UKH_PAYLOAD_FILE_SKIP UKH_PAYLOAD_FILE_SKIP
%else
  %define UKH_PAYLOAD_FILE_SKIP 0
%endif

%ifndef UKH_VERSION_STRING
  %define UKH_VERSION_STRING 'ukh'
%endif

%ifndef UKH_PAYLOAD_SEG
  %define UKH_PAYLOAD_SEG 0x1000
%elif (UKH_PAYLOAD_SEG)<((0x520+0x80+0xf)>>4)  ; 0x520 bytes for the interrupt table and BIOS data area, 0x80 bytes stack. https://stanislavs.org/helppc/bios_data_area.html
  %assign __UKH_VALUE (UKH_PAYLOAD_SEG)
  %error ERROR_UKH_PAYLOAD_SEG_TOO_SMALL __UKH_VALUE
  db 1/0
%elif (UKH_PAYLOAD_SEG)>0x8000  ; A larger value would leave less than 64 KiB for the payload.
  %assign __UKH_VALUE (UKH_PAYLOAD_SEG)
  %error ERROR_UKH_PAYLOAD_SEG_TOO_LARGE __UKH_VALUE
  db 1/0
%endif

; --- Implementation for the UKH header (boot_sector: 0x200 bytes, setup_sector: 0x200 bytes).

%ifnidn __OUTPUT_FORMAT__, bin
  %error ERROR_NASM_OUTPUT_FORMAT_MUST_BE_BIN
  times -1 nop
%endif

%macro __ukh_assert_fofs 1
  times +(%1)-($-$$) times 0 nop
  times -(%1)+($-$$) times 0 nop
%endm
%macro __ukh_assert_at 1
  times +(%1)-$ times 0 nop
  times -(%1)+$ times 0 nop
%endm

bits 16
cpu 8086

BOOT_SIGNATURE equ 0xaa55

OUR_LINUX_BOOT_PROTOCOL_VERSION equ 0x201  ; 0x201 is the last one which loads everything under 0xa0000 (even 0x9a000). Later versions load ukh_payload above 1 MiB (linear address >=0x100000).

MULTIBOOT_MAGIC equ 0x1badb002
MULTIBOOT_FLAG_AOUT_KLUDGE equ 1<<16
MULTIBOOT_INFO_BOOTDEV equ 1<<1
MULTIBOOT_INFO_CMDLINE equ 1<<2
OUR_MULTIBOOT_FLAGS equ MULTIBOOT_FLAG_AOUT_KLUDGE
OUR_MULTIBOOT_LOAD_ADDR equ 0x100000  ; The minimum value is 0x100000 (1 MiB), otherwise GRUB 1 0.97 fails with: Error 7: Loading below 1MB is not supported
OUR_MULTIBOOT_HEADER_SIZE equ 0x20

BXS_SIZE equ 0x400  ; Total size of boot sector and setup sectors.
PAYLOADSEG equ UKH_PAYLOAD_SEG
LINUXKERNELSEG equ 0x1000  ; This is always 0x1000, that's where the bootloader loads the bytes starting at file offset 0xa00 to.
APISEG equ 0x9000  ; This mustn't be changed, other code parts depend on this value. We assume that BXS_SIZE bytes at boot_sector (including the 0x200-byte boot_sector and the 0x200-byte setup_sector) have been loaded to linear address APISEG<<4.
BOOT_ENTRY_ADDR equ 0x7c00

org (PAYLOADSEG<<4)-BXS_SIZE  ; This is for 32-bit protected-mode code in the payload .nasm source. The 32-bit protected-mode code in ukh.nasm works with arbitrary `org', because it always subtracts boot_sector etc. Example: `mov esi, message'.
ukh_base16 equ -(PAYLOADSEG<<4)  ; This is for real-mode code in the payload .nasm source. Example: `mov si, message+ukh_base16'. If (UKH_PAYLOAD_SEG&0xfff)==0 (default), then it can be omitted: `mov si, message'.

LOADFLAG_READ:
.HIGH: equ 1<<0

%macro ukh_halt 0  ; Works in both protected mode and real mode. This is part of the API.
  cli
  %%back: hlt
  jmp short %%back
%endm

; With the Linux load protocol, the bootloader loads the first 5 sectors
; (0xa00 bytes) (boot_sector and setup sector) to APISEG<<4 (== 0x90000),
; the rest (ukh_payload) to PAYLOADSEG<<4 (== 0x10000) and then jumps to 0x9020:0
; (setup_sector) in real mode. Thus it starts running the code at the
; beginning of setup_sector, the sector following boot_sector.
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
; setup_sector in real mode (unless the protected-mode code explicitly
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
;
; What is near 0xa0000 (64 KiB after APISEG == 0x9000): EBDA (Extended BIOS
; Data Area). Its segment is referenced by a word at 0x40e (in real-mode
; memory), which is typically 1 KiB 0x9fc00..0xa0000.
boot_sector:  ; 1 sector of 0x200 bytes.
.start:
.gdt:  ; The first GDT entry (segment descriptor, 8 bytes) can contain arbitrary bytes, so we overlap it with boot code. https://stackoverflow.com/a/33198311
		; https://wiki.osdev.org/Global_Descriptor_Table#Segment_Descriptor
		; The GDT has to remain valid until the next lgdt instruction (potentially long), so we'll keep it at linear address 0x90000.
.code:		mov cx, cs
		mov ax, 0xe00+'?'  ; Set up error message.
		call .code3
.here:		; Not reached, .code2 will pop the return address.
		__ukh_assert_at .gdt+8  ; End if first GDT entry.
; base (32 bits): ifr e=0, then first valid linear address
; limit (20 bits): if e=0 and g=0, then last valid linear address is (base+limit)&0xffffffff; if e=0 and g=1, then the last valid linear address is (base+((limit+1)<<12)-1)&0xffffffff
; a (accessed) bit: set to 1 by the CPU when the segment is first accessed, and can be cleared by the kernel
; r (readable) bit for code segments: if r=0, then the segment is execute-only; if r=1, then the segment is read-execute
; w (writable) bit for data segments: if w=0, then the segment is read-only; if w=1, then the segment is read-write
; c (conforming) bit for code segments: iff c=1, then code in this segment may be called from less-privileged levels
; e (expand-down) bit for data segments: iff e=0, then valid addressses are base .. base+limit-1; if e=1 (typically used for stacks), then valid addresses in 32-bit mode are (base+limit+1)&0xffffffff .. (base-1)&0xffffffff
; d (descriptor privilege level) (2 bits): just use 0 in kernel mode
; p (present) bit: iff p=0, then each access triggers a segment-not-present exception; just use 1 until you implement pages in your kernel
; avl (available) bit: not used by the CPU, the kernel can use it for any purpose
; d (default operand size) bit for code segments: if d=0, then this is a 16-bit code segment executing code in the i86 encoding; if d=1, then this is a 32-bit code segment executing code in the i386 encoding
; b (big) bit for data segments: if d=0, then the offset of each access is masked to 16 bits (&0xffff); if d=1, then the offset of each access is 32 bits
; g (granularity) bit: changes the interpretation of limit
; See more info at  https://en.wikipedia.org/wiki/Segment_descriptor#The_x86_and_x86-64_segment_descriptor and https://wiki.osdev.org/Global_Descriptor_Table#Segment_Descriptor
%define EMIT_SEGMENT_DESCRIPTOR(base, limit, a, rw, ce, code, s, dpl, p, avl, db, g) dw ((limit)&0xffff), ((base)&0xffff), (((base)>>16)&0xff)|((a)&1)<<8|((rw)&1)<<9|((ce)&1)<<10|((code)&1)<<11|((s)&1)<<12|((dpl)&3)<<13|((p)&1)<<15, (((limit)>>16)&0xf)|((avl)&1)<<4|((db)&1)<<6|((g)&1)<<7|(((base)>>24)&0xff)<<8
%define EMIT_CODE_SEGMENT_DESCRIPTOR(base, limit, a, r, c, dpl, p, avl, d, g) EMIT_SEGMENT_DESCRIPTOR(base, limit, a, r, c, 1, 1, dpl, p, avl, d, g)
%define EMIT_DATA_SEGMENT_DESCRIPTOR(base, limit, a, w, e, dpl, p, avl, b, g) EMIT_SEGMENT_DESCRIPTOR(base, limit, a, w, e, 0, 1, dpl, p, avl, b, g)
..@KERNEL_CS: equ $-.gdt  ; Segment ..@KERNEL_CS == 8 descriptor. Used when running in protected mode. QEMU 2.11.1 linuxboot.S and GRUB 1 0.97 stage2/asm.S also have these values.
                EMIT_CODE_SEGMENT_DESCRIPTOR(0, -1, 0, 1, 0, 0, 1, 0, 1, 1)  ; dw 0xffff, 0, 0x9a00, 0xcf  ; 32-bit, code, read-execute, base 0, limit 4GiB-1, limit granularity 0x1000, non-conforming (c=0).
..@KERNEL_DS: equ $-.gdt  ; Segment ..@KERNEL_DS == 0x10 descriptor. used when running in protected mode. QEMU 2.11.1 linuxboot.S and GRUB 1 0.97 stage2/asm.S also have these values.
		EMIT_DATA_SEGMENT_DESCRIPTOR(0, -1, 0, 1, 0, 0, 1, 0, 1, 1)  ; dw 0xffff, 0, 0x9200, 0xcf  ; 32-bit, data, read-write, base 0, limit 4GiB-1, limit granularity 0x1000.
..@BACK16_CS: equ $-.gdt  ; Segment ..@BACK16_CS == 0x18 descriptor. Used for switching back to real mode.  Its flags will be reused when back in real mode.
		EMIT_CODE_SEGMENT_DESCRIPTOR(APISEG<<4, 0xffff, 1, 1, 0, 0, 1, 0, 0, 0)  ; dw 0xffff, ..., 0x9b00|..., 0|...  ; 16-bit, code, base 0. pts-grub1-port stage2/asm.S also has these values. This is the initial contents of the shadow descriptor (except for base=0 there) in CS in QEMU 2.11.1 boot sector load time.
		;EMIT_CODE_SEGMENT_DESCRIPTOR(0, 0xffff, 1, 1, 0, 0, 1, 0, 0, 0)  ; dw 0xffff, 0, 0x9b00, 0  ; 16-bit, code, base 0. pts-grub1-port stage2/asm.S also has these values. This is the initial contents of the shadow descriptor in CS in QEMU 2.11.1 boot sector load time.
		;EMIT_CODE_SEGMENT_DESCRIPTOR(0, 0xffff, 0, 1, 1, 0, 1, 0, 0, 0)  ; dw 0xffff, 0, 0x9e00, 0  ; 16-bit, code, base 0. GRUB 1 0.97 stage2/asm.S also has these values.
		__ukh_assert_at .gdt+4*8  ; Must be at most .cl_magic-.start, so that the GDT doesn' get overwritten.
		__ukh_assert_at .gdt+0x20
.cl_magic:	dw 0xa33f  ; equ .start+0x20  ; (dw) 0xa33f (LINUX_CL_MAGIC) The Linux bootloader will set this to the same value (LINUX_CL_MAGIC == 0xa33f) if it provides a kernel command-line string.
.cl_offset:	dw .cl_offset_high_word+1-.start  ; equ .start+0x22  ; (dw) The Linux bootloader (also in kernel load protocol <=2.01) will set this to (dw) the offset of the kernel command line. The segment is APISEG. By default it points to a NUL byte, so the kernel command-line string is empty.
.cl_offset_high_word: dw APISEG>>12  ; equ .start+0x24  ; (dw) 9. So that dword [0x90022] can be used as a pointer to the kernel command line. Also has its high byte 0, used by the default .cl_offset.
.partition: db 0xfe  ; byte [0x90026]. Partition within the BIOS boot drive, or 0xff if the entire drive should be used. Default value of 0xfe indicates unknown. Currently only the Multiboot load protocol sets it to non-unknown (but not always).
.drive_number:  db 0xff  ; byte [0x90027]. BIOS boot drive number (first floppy is 0, first HDD is 0x80). Default value of 0xff indicates unknown, and it remains this way for the Linux load protocol and for the Multiboot load protocol via QEMU.
		__ukh_assert_at .gdt+5*8
..@BACK16_DS: equ $-.gdt  ; Segment ..@BACK16_DS == 0x28 descriptor. Used for switching back to real mode. Its flags will be reused when back in real mode. Won't actually be used to reference memory while switching.
		EMIT_DATA_SEGMENT_DESCRIPTOR(0,        0xffff, 1, 1, 0, 0, 1, 0, 0, 0)  ; dw 0xffff, 0, 0x9300, 0  ; 16-bit, data, base 0. pts-grub1-port stage2/asm.S also has these values. This is the initial contents of the shadow descriptor in DS, ES, FS, GS, SS in QEMU 2.11.1 boot sector load time.
		;EMIT_DATA_SEGMENT_DESCRIPTOR(0,       0xffff, 0, 1, 0, 0, 1, 0, 0, 0)  ; dw 0xffff, 0, 0x9200, 0  ; 16-bit, data, base 0. GRUB 1 0.97 stage2/asm.S also has these values.
		;EMIT_DATA_SEGMENT_DESCRIPTOR(0xfffff, 0xffff, 1, 1, 0, 0, 1, 0, 0, 0)  ; dw 0xffff, 0, 0x9300, 0  ; 16-bit, data, read-write, base arbitrary (0xfffff, arbitrary, unused, unusual), limit 0xffff, limit limit granularity 0 (1 byte). upfx_32.nasm has these values.
.gdt_end:	__ukh_assert_at .gdt+6*8
.code3:		pop si  ; SI := actual offset of .here.
		cld
		test cx, cx
		jnz short .not_chain_protocol
		cmp si, BOOT_ENTRY_ADDR+(.here-.start)  ; 0x7c00-(...).
		jne short .not_chain_protocol  ; Jump iff CS:IP was 0:0x7c00. Some BIOSes jump to 0x7c0:0 instead when booting from floppy or HDD, but we don't support those. !! Add support (it doesn't fit).
.chain_protocol:  ; Now: CX == 0; DS == 0; DL == BIOS drive number; SS:SP is valid but unknown.
		xor bx, bx  ; Set up error message.
		mov al, 'b'
		int 0x10  ; Print character in AL.
		; Compare a few bytes of setup_sector to
		; .copy_of_setup_sector. This is a best effort check to see
		; if the bootloader has loaded setup_sector.
		mov ds, cx  ; DS := 0.
		mov es, cx  ; ES := 0.
		mov si, BOOT_ENTRY_ADDR+.copy_of_setup_sector-.start
		inc byte [si+2]  ; 'GdrS' --> 'HdrS'.
		mov di, BOOT_ENTRY_ADDR+setup_sector-.start
		mov cl, (.copy_of_setup_sector.end-.copy_of_setup_sector)>>1  ; CH is already 0.
		repe cmpsw
		je short .cmp_matches
		cmp dl, 16  ; BIOS drive number must be smaller than this.
		jb short .booting_from_floppy
		mov al, 'F'  ; Fail with fatal error: `bF' means that the bootloader has loaded only he first sector.
		; Fall through to .fatal_print_and_halt.
		;jmp short .fatal_print_and_halt
.not_protocol_with_offset_zero_al:
.not_chain_or_freedos_or_drdos_or_ntldr_protocol_al:
.fatal_unknown_protocol_al:  ; Not a jump target.
.fatal_print_and_halt:  ; Input: AH == 0xe; AL == character to print.
		xor bx, bx  ; Set up error message.
		int 0x10  ; Print character in AL.
.halt:		ukh_halt
		; Not reached.
.not_chain_protocol:
		sub si, byte .here-.start  ; SI := actual offset of .start.
		jnz short .not_protocol_with_offset_zero_al
		cmp cx, byte 0x60
		jne short .not_chain_or_freedos_protocol
.freedos_protocol:  ; Used by FreeDOS and SvarDOS.
		mov dl, bl  ; Save BIOS drive number.
		mov al, 'F'  ; Indicate FreeDOS.
		jmp short .drdos_or_freedos_protocol  ; !! Also receive the FreeDOS (bleeding edge, more reent than the kernel in FreeDOS 1.3) command line.
.not_chain_or_freedos_protocol:
		cmp cx, byte 0x70
		jne short .not_chain_or_freedos_or_drdos_protocol
.drdos_protocol:  ; Used by DR-DOS, EDR-DOS. SvarDOS can also boot from it.
		mov al, 'D'  ; Indicate DR-DOS.
.drdos_or_freedos_protocol:
		; Typical FreeDOS, EDR-DOS 7.01.08 and SvarDOS >= 20240729 values here: DS == SS == 0x17fe (or 0x27fe if increased); BP == 0x7c00.
		cmp bp, BOOT_ENTRY_ADDR  ; 0x7c00.
		jne short .any_supported_protocol
		mov si, ds
		mov di, ss
		cmp si, di
		jne short .any_supported_protocol
		mov si, [bp+0x1c  ]  ; Low  word of hidden sector count in the loaded BPB of the FAT12, FAT16 or FAT32 filesystem. Uses SS:BP.
		mov [cs:setup_sector.ramdisk_size-boot_sector  ], si  ; .ramdisk_size corresponds to ukh_hidden_sector_count16.
		mov si, [bp+0x1c+2]  ; High word of hidden sector count in the loaded BPB of the FAT12, FAT16 or FAT32 filesystem. Uses SS:BP.
		mov [cs:setup_sector.ramdisk_size-boot_sector+2], si  ; .ramdisk_size corresponds to ukh_hidden_sector_count16.
		jmp short .any_supported_protocol
.not_chain_or_freedos_or_drdos_protocol:
		cmp cx, 0x2000
		jne short .not_chain_or_freedos_or_drdos_or_ntldr_protocol_al
.ntldr_protocol:  ; NTLDR, used by Windows NT 3.1--4.0, Windows 2000--XP. Later releases of Windows may use a similar protocol, but the filename is *bootmgr* rather than *ntldr*.
		mov al, 'N'  ; Indicate Windows NTLDR.
		jmp short .any_supported_protocol

.booting_from_floppy:
		mov al, 'l'
		db 0xa9  ; Opcode byte of `test ax, strict word ...', to skip over the `mov al, 's'' instruction below.
.cmp_matches:
		mov al, 's'
%if $-.cmp_matches!=2
  %error ERROR_BAD_MOV_AL_SIZE  ; Required by `db 0xa9' above.
  times -1 nop
%endif
		mov cx, BOOT_ENTRY_ADDR>>4
		; Fall through to .any_supported_protocol.

.any_supported_protocol:  ; Now: CX:0 points to the loaded, to-be-copied boot_sector+setup_sector (BXS_SIZE == 0x400 bytes in total); AL == boot mode ('l' for floppy) character to print; DL == BIOS drive number; SS:SP is still populated by the bootloader.
		xor bx, bx  ; Set up error message. Also set BX to 0 for .load_sectors_from_floppy.
		int 0x10  ; Print character in AL.
%if 1  ; !! Remove these debug prints (but some of them indicate progress).
		xchg al, dl  ; BIOS drive number.
		int 0x10  ; Print BIOS boot drive character. !! No need to print these.
		xchg al, dl
%endif

		; Initialize DS := BOOT_ENTRY_ADDR>>4; ES := APISEG; SS:SP.
		mov ds, cx  ; After this (until we break DS again) global variables work.
		mov es, [.apiseg_const-.start]  ; ES := APISEG.
		cli
		push es
		pop ss  ; SS := APISEG.  ; mov ss, ... .
		mov sp, ss  ; Set SS:SP to APISEG:APISEG (== 0x9000:0x9000), similarly to how QEMU 2.11.1 `-kernel' acts as a Linux bootloader, it sets 0x9000:(0xa000-cmdline_size-0x10).
		sti

		; Copy BXS_SIZE bytes (2 sectors) from DS:0 (actually loaded boot_sector+setup_sector) to APISEG:0. There is no overlap.
		xor si, si
		xor di, di
		; Good: SYSLINUX 4.07 *boot*, GRUB4DOS *chainloader*, GRUB *kernel* with Multiboot only and the DOS boot sectors pass the BIOS drive number (e.g. 0x80 for first HDD) in DL. (Or in BL, but we've already copied it to DL.)
		mov [si+.drive_number-.start], dl  ; Save BIOS drive number to the UKH final boot_sector.drive_number.
		mov cx, BXS_SIZE>>1  ; Number of words to copy (even number of bytes).
		rep movsw
		jmp APISEG:.after_far_jmp-.start  ; Jump to .after_far_jmp in the copy, to avoid overwriting the code doing the copy below (to PAYLOADSEG). Needed for the NTLDR load protocol.
.apiseg_const equ $-2
.after_far_jmp:  ; Input: CX == 0; BX == 0; AL == boot mode ('l' for floppy) character to print.
		cmp al, 'l'
		je short .load_sectors_from_floppy
		; Fall through to .not_load_from_floppy.

.not_load_from_floppy:
		; Copy ukh_payload_end-ukh_payload bytes (rounded up to
		; sector size) from DS:BXS_SIZE to PAYLOADSEG:0.
		mov cx, ds  ; CX := ssegment of first source sector (with offset 0 it points to ukh_payload).
		add cx, strict byte BXS_SIZE>>4  ; Skip over boot_sector+setup_sector.
		mov ax, PAYLOADSEG  ; AX := copy destination segment.
		mov bx, (ukh_payload_end-ukh_payload+0x1ff)>>9  ; Number of 0x200-byte sectors to copy. Positive.
		; Fall through to .copy_payload.

.copy_payload:
		; Copy BX sectors from CX:0 to AX:0. BX must not be 0. Then
		; jump to setup_sector.setup_chain.
		;
		; Sets BX := 0; CX := 0; SI := 0x200; DI := 0x200; DX :=
		; either 0x20 or -0x20 == 0xffe0. Makes AX == ES. Ruins AX,
		; DS, ES. Keeps BP, SS:SP.
		;
		; We copy one sector (0x200) bytes at a time. This is
		; arbitrary. But we can't copy in one go, because the data
		; size is >=64 KiB, so we have to modify some segment registers.
		mov dx, 0x200>>4  ; Number of paragraphs per sector.
		; Now: CX == copy source segment; AX == copy destination segment.
		cmp cx, ax
		jae short .after_setup_copy  ; Copy them in forward (ascending), because the destination comes before the source, and they may overlap.
.setup_backward_copy:  ; Copy them backward (descending), because the destination comes after the source, and they may overlap.
		neg dx  ; DX := -(0x200)>>4. Change copy direction to descending.
		add ax, strict word (((ukh_payload_end-ukh_payload+0x1ff)>>9)-1)<<5  ; Adjust destination segment to point to the last sector.
		add cx, strict word (((ukh_payload_end-ukh_payload+0x1ff)>>9)-1)<<5  ; Adjust source      segment to point to the last sector.
		;jmp short .after_setup_copy  ; Not needed, falls through.
;.setup_forward_copy:
		;mov dx, 0x200>>4  ; Already set.
		;mov ax, PAYLOADSEG  ; Already set. AX := segment of first destination sector.
		;mov es, ax  ; Already set. ES := segment of first destination sector.
		;add cx, 0 ;   Already set. CX := segment of first source sector (with offset 0 it points to ukh_payload), minus BXS_SIZE>>4.
		;mov ds, cx  ; Already set. DS := segment of first source sector (with offset 0 it points to ukh_payload), minus BXS_SIZE>>4.
.after_setup_copy:
		mov ds, cx
		mov es, ax
.copy_sector:	mov cx, 0x200>>1  ; Number of words in a sector.
		xor si, si
		xor di, di
		rep movsw
		mov ax, ds
		add ax, dx  ; [+-] (0x200>>4)
		mov ds, ax
		mov ax, es
		add ax, dx  ; [+-] (0x200>>4)
		mov es, ax
		dec bx
		jnz short .copy_sector
		; Now: BX == 0; CX == 0; SI == 0x200; DI == 0x200; DX == either 0x20 or -0x20 == 0xffe0; AX == ES; AX, DS and ES are ruined.
		; Fall through to .jump_to_setup_chain.

.jump_to_setup_chain:
		mov ax, 0xe00+'&'  ; Preparation for `Print character in AL' in .setup_chain.
		xor bx, bx
		jmp (APISEG+0x20):(setup_sector.setup_chain-setup_sector)  ; Self-modifying code: target offset may be changed from .setup_chain to .setup_linux_cont16.
.jmp_offset2: equ $-4
.const_apiseg_plus_0x20: equ $-2

.load_sectors_from_floppy:
.adjust_dpt:  ; Input: CX == 0; BX == 0.
; The code from here up to .not_load_from_floppy is based on linux-2.4.37.11/arch/i386/boot/bootsect.S .
		mov ds, bx  ; 0.
		mov bl, 0x1e<<2  ; BIOS Disk Parameter Table (DPT) far pointer is the `int 1eh' interrupt vector.
		lds si, [bx]  ; DS:SI := `int 1eh' interrupt vector value.
		mov cl, 14  ; Number of bytes to copy. Some sources say 11, others 12, others 14 bytes. We play it safe, and copy 14 bytes.
		sub sp, cx
		mov di, sp
		push ds  ; Save old DPT far pointer segment. Will be popped by .finish_loading.
		push si  ; Save old DPT far pointer offset.  Will be popped by .finish_loading.
		push bx  ; Save offset value 0x1e<<2. Will be popped by .finish_loading.
		push ss
		pop es
		rep movsb
		push cx  ; Save segment value 0. Will be popped by .finish_loading.
		mov ds, cx  ; 0, because of the `rep movsw' above.
		mov [bx], sp    ; New DPT far pointer offset.
		mov [bx+2], ss  ; New DPT far pointer segment.
		mov cl, 36  ; CH == 0 because of the `rep movsb' above.
		; The Disk Parameter Table (DPT) in many BIOSes will not allow multi-sector
		; reads beyond the defafult maximum of just 7 sectors. We change it
		; temporarily to our maximum of 36 (used by 2880K ED floppies).
		mov [ss:di-14+4], cl  ; Patch maximum sector count to 36 in the new DPT.
		; Fall through to .detect_sectors_per_track.

.detect_sectors_per_track:  ; Input: CH == 0 (track number); CL == highest sectors-per-track value to try; DL == BIOS drive number; CS == SS == APISEG.
		; We try these sectors-per-track values: 36, 18, 15, 9. The heads value is always 2. Floppy image sizes: 36: 2880K; 18: 1440K, 15: 1200K, 9: 720K or 360K.
		; Now: CL == sector number; CH == 0 (track number).
%if 1  ; Same size, but it doesn't modify BX.
		mov es, [cs:.const_apiseg_plus_0x20-boot_sector]  ; ES := APISEG+0x20.
%else
		mov bx, APISEG+0x20
		mov es, bx
%endif
		mov dh, 0  ; head := 0.
		xor bx, bx  ; Offset to read to. ES is the segment.
.detect_sectors_per_track_again:
		mov ax, 0x201  ; AH := 2 (Read sectors); AL := 1 (number of sectors to read).
		int 0x13  ; Read sectors.
		jnc short .found_sectors_per_track
		shr cl, 1
		; Possible values of CL now: 18 (CF == 0), 9 (CF == 0), 7 (CF == 1).
		jc short .fallback_sectors_per_track
		; Possible values of CL now: 18 (CF == 0), 9 (CF == 0).
		cmp cl, 36>>1
		je short .detect_sectors_per_track_again
		mov cl, 15
		jmp short .detect_sectors_per_track_again
.fallback_sectors_per_track:
		mov cl, 9
.found_sectors_per_track:
%if 0  ; For debugging.
		mov ah, 0xe
		mov al, cl
		xor bx, bx
		int 0x10
%endif
%if 1  ; !!! Why do we have to reset it here? We could save 4 bytes.
		xor ax, ax  ; AX := 0. Reset FDC.
		int 0x13  ; Reset FDC. Only works if DL <= 0x7f == 127.
%endif
		;mov dh, 0  ; Initialize VAR_head := 0. Not needed, DH is already 0.
		mov ah, cl  ; AH := (detected sectors-per-track).
		mov cl, 1  ; Initialize VAR_sread := 1.
		;mov ch, 0  ; Initialize VAR_track := 0. Not needed, CH is already 0.
;%define VAR_head dh  ; Current head. 0 or 1. Initialized to 0. BIOS int 14h AH == 2 (Read sectors) also expects this in DH.
;%define VAR_sectors_per_track ah  ; Initialized to the value detected by .detect_sectors_per_track. It won't be changed.
;%define VAR_track ch  ; Current track (cylinder). At most 255. Initialized to 0. BIOS int 14h AH == 2 (Read sectors) also expects this in CH.
;%define VAR_sread cl  ; Number of sectors already read within current track. Initialized to 1, because 1 sector (boot_sector) has already been read. BIOS int 13h AH == 2 (Read sectors) expects the sector index in CL.
		; Fall through to .load_setup_sector.

.load_setup_sector:  ; Inpput: ES == APISEG+0x20; DL == BIOS drive number; DH == VAR_head; AH == VAR_sectors_per_track; CL == VAR_sread; CH == VAR_track.
		mov al, 1  ; Number of setup sectors to load.
		; Now: ES == APISEG+0x20, used by .read_sectors below.
		call .read_sectors  ; Reads AL sectors. Ruins BX := 0, DH.
		mov bx, PAYLOADSEG  ; The read destination segment.
		; Now: AL == 1; BX:0 == address to read the first payload sector to; CX == 2.
		; Fall through to .load_payload_sectors.

; Loads the rest of the sectors, making sure no 64 KiB boundary is crossed,
; loading whole tracks whenever possible (for fast loading).
;
; Input: BX:0 == address to read the first payload sector to; SS:BP points to our stack frame; DL == BIOS drive number.
.load_payload_sectors:
.set_next:
		cmp cl, ah  ; AH is VAR_sectors_per_track.
		jne short .set_next3
		xor dh, 1  ; Next head. DH is VAR_head.
		jnz short .set_next4
		inc ch  ; Next track.
.set_next4:
		mov cl, 0  ; CL (VAR_sread) := 0.
.set_next3:
		mov es, bx  ; ES := PAYLOADSEG, the read destination segment.
		mov al, cl
.next_read_count:
		inc ax
		add bx, byte 0x200>>4
		test bx, 0xfff
		jz short .done_read_count  ; Stop at 64 KiB boundary.
		cmp al, ah  ; AH is VAR_sectors_per_track.
		jne short .next_read_count
.done_read_count:
		sub al, cl  ; AL := (number of sectors to read next). It's always positive.
		call .read_sectors  ; Reads AL sectors. Ruins BX := 0, DH.
		mov bx, es
.add_next:
		add bx, byte 0x200>>4
		dec al
		jnz short .add_next
		cmp bx, strict word PAYLOADSEG+((__missing_ukh_end+ukh_payload_end-ukh_payload+0xf)>>4)
		jb short .set_next
		; Fall through to .finish_loading.

.finish_loading:
		pop es  ; Restore ES := 0.
		pop di  ; Restore DI := 0x1e<<2. BIOS Disk Parameter Table (DPT) far pointer is the `int 1eh' interrupt vector.
		pop ax  ; Restore AX := old DPT far pointer offset.
		pop bx  ; Restore BX := old DPT far pointer segment.
		stosw  ; Set DPT offset to old.
		xchg ax, bx  ; Ruins BX.
		stosw  ; Set DPT segment to old.
		;lea sp, [di-14]  ; Not needed, we can waste 14 bytes of stack space temporarily.
		jmp near .jump_to_setup_chain

; Reads AL sectors (of 0x200 bytes) to ES:BX. Needs AL >= 1. Sets AL to the actual number of sectors read. Adds the number of sectors read to CL. Ruins AH, BX := 0, DH.
.read_sectors:
		; Display the progress dot.
%if 0  ; It doesn't fit, too much code in boot_sector.
		push ax  ; Save.
		mov ax, 0xe00+'.'
		xor bx, bx
		int 0x10
		pop ax  ; Restore.
%endif
		; Now: CL == VAR_sread; CH == VAR_track.
		inc cx  ; CL := sector index to read.
		xor bx, bx  ; Read sectors to ES:BX == ES:0.
		push ax  ; Save for both AH (VAR_sectors_per_track) and AL.
		mov ah, 2  ; Read sectors.
		int 0x13  ; Read sectors. CH == VAR_track; DH == VAR_head; DL == BIOS drive number.
		jc short .read_error
		dec cx  ; Undo `inc cx' above, so CL is VAR_sread again.
		add cl, al  ; CL is VAR_sread.
		pop ax  ; Restore AH := VAR_sectors_per_track; restore AL.
		ret

.read_error:
		mov ax, 0xe00+'R'
		jmp near .fatal_print_and_halt

; This code has been moved from setup_sector below to boot_sector to leave
; more free space in setup_sector for .kernel_version_string.
.real1:  ; Now we are still in protected mode, but CS points to a 16-bit segment.
bits 16
cpu 386
		; We use the movs below to copy the limit, the flags (e.g.
		; granularity) and the access byte (and also the base) from
		; gdt_chainloader to the segment register shadow
		; descriptors. It would be too late to copy them in real
		; mode, because a real-mode mov to a segment register only
		; updates the base in the shadow descriptor.
		;
		; MS-DOS 7.1 io.sys in QEMU 2.11.1 requires the correct
		; limit, flags an access byte values. Without them it hangs
		; the system at boot time about 0.1% of the time.
		mov ds, ax  ; This is required, because .prot_ret has changed the shadow descriptor of DS.
		mov es, ax  ; This is required, because .prot_ret has changed the shadow descriptor of ES.
		mov fs, ax  ; This is required, because .prot_ret has changed the shadow descriptor of FS.
		mov gs, ax  ; This is required, because .prot_ret has changed the shadow descriptor of GS.
		mov ss, ax  ; This is required, because .prot_ret has changed the shadow descriptor of SS.
		mov eax, cr0
		and al, byte ~1  ; PE := 0. Leave protected mode, enter real mode.
		mov cr0, eax
		;lmsw ax  ; This doesn't work instead of modifyingc CR0, .real2 won't be reached. Why? (Ask on stackoverflow.com.)
		; There seems to be no need to do a far jump to .real2 just
		; yet (see https://stackoverflow.com/q/79551879 for
		; details). Thus we remain in 16-bit protected mode (based
		; on the descriptor of CS) until the `retf' below.
		;jmp APISEG:(.real2-boot_sector)  ; 5 bytes: 1 opcode, 2 offset, 2 segment. With this jump, we would switch to real mode CS.
;.real2:  ; We are in real mode now in terms of CS.
		xor ax, ax
		mov ss, ax  ; This updates the only base in the shadow descriptor to 0.
%if PAYLOADSEG&0xff
		mov ax, PAYLOADSEG
%else
		mov ah, PAYLOADSEG>>8  ; 1 byte shorter than `mov ax, PAYLOADSEG'.
%endif
		mov ds, ax  ; This updates the only base in the shadow descriptor to PAYLOADSEG.
		mov es, ax  ; This updates the only base in the shadow descriptor to PAYLOADSEG.
		mov fs, ax  ; This updates the only base in the shadow descriptor to PAYLOADSEG.
		mov gs, ax  ; This updates the only base in the shadow descriptor to PAYLOADSEG.
		pop eax  ; Restore.
		;sti  ; Give the caller a chance to call .a20_gate while interrupts are still disabled.
		retf  ; This switches to real mode CS.
cpu 8086

		times (.start-$)&1 nop  ; Align to even.
.copy_of_setup_sector:  ; Extra bytes from the beginning of setup_sector, so that we can figure out that it has been loaded (not only the boot_sector).
		db 0xeb, setup_sector.setup_linux-(setup_sector.jump+2)
		db 'GdrS'  ; Like 'HdrS', but obfuscate it from hex editors.
		dw OUR_LINUX_BOOT_PROTOCOL_VERSION
		dd 0
		dw LINUXKERNELSEG  ; Copy of .start_sys_seg. This must always be 0x1000 (no matter what PAYLOADSEG is), some bootloaders require it.
		dw setup_sector.kernel_version_string-setup_sector
.copy_of_setup_sector.end:
		times -((.copy_of_setup_sector.end-.copy_of_setup_sector)&1) nop  ; Fail if size is not even. Evenness needed by cmpsw above.

		times 0x1f1-($-.start) db '-'
.linux_boot_header:  ; https://docs.kernel.org/arch/x86/boot.html  . Until setup_sector.linux_boot_header.end.
		__ukh_assert_fofs 0x1f1
.setup_sects:	db 4  ; (read) The size of the setup in sectors. That is, the 32-bit kernel image starts at file offset (setup_sects+1)<<9. Must be 4 for compatibility with old-protocol Linux bootloaders (such as old LILO).
		__ukh_assert_fofs 0x1f2
.root_flags:	dw 0  ; (read, modify optional) If set, the root is mounted readonly.
		__ukh_assert_fofs 0x1f4
.syssize_low:	dw (__missing_ukh_end+__payload_padded_end-ukh_payload-0xa00+BXS_SIZE+0xf)>>4  ; (read) The low word of size of the 32-bit code in 16-byte paras. Ignored by GRUB 1 or QEMU. Maximum size allowed: 1 MiB, but Linux kernel protocol <=2.01 supports zImage only, with its maximum size of 512 KiB.
		__ukh_assert_fofs 0x1f6
.swap_dev:
.syssize_high:	dw 0  ; (read) The high word size of the 32-bit code in 16-byte paras. For Linux kernel protocol prior to 2.04, the upper two bytes of the syssize field are unusable, which means the size of a bzImage kernel cannot be determined.
		__ukh_assert_fofs 0x1f8
.ram_size:	dw 0  ; (kernel internal) DO NOT USE - for bootsect.S use only.
		__ukh_assert_fofs 0x1fa
.vid_mode:	dw 0  ; (read, modify obligatory) Video mode control.
		__ukh_assert_fofs 0x1fc
.root_dev:	dw 0  ; (read, modify optional) Default root device number. Neither GRUB 1 nor QEMU 2.11.1 set it. In their Linux kernel mode, they don't set root= either, and they don't pass the boot drive (boot_drive, saved_drive, current_drive, is saved_drive the result of `rootnoverify'?) number anywhere. Also GRUB 1 0.97 passes the boot drive in DL in `chainloader' (stage1) mode only.
		__ukh_assert_fofs 0x1fe
.boot_flag:	dw BOOT_SIGNATURE  ; (read) 0xaa55 magic number.
		__ukh_assert_fofs 0x200

setup_sector:  ; 4 == (.boot_sector.setup_sects) sectors of 0x200 bytes each. Loaded to 0x800 bytes to 0x90200. Jumped to `jmp 0x9020:0' in real mode for the Linux load protocol.
.start:		__ukh_assert_fofs 0x200
.jump:		jmp short .setup_linux  ; (read) Jump instruction. Linux load protocol entry point, in real mode.
		__ukh_assert_fofs 0x202
.header:	db 'HdrS'  ; (read) Protocol >=2.00 signature. Magic signature “HdrS”.
		__ukh_assert_fofs 0x206
.version:	dw OUR_LINUX_BOOT_PROTOCOL_VERSION  ; (read) Linux kernel protocol version supported. 0x201 is the last one which loads everything under 0xa0000.
		__ukh_assert_fofs 0x208
.realmode_swtch: dd 0  ; (read, modify optional) Bootloader hook.
		__ukh_assert_fofs 0x20c
.start_sys_seg: dw LINUXKERNELSEG  ; (read) The load-low segment (LINUXKERNESEG == 0x1000), i.e. linear address >> 4 (obsolete). Ignored by both GRUB 1 0.97 and QEMU 2.11.1. This must always be 0x1000 (no matter what PAYLOADSEG is), some bootloaders require it.
		__ukh_assert_fofs 0x20e
.kernel_version: dw .kernel_version_string-setup_sector  ; (read) Pointer to kernel version string or 0 to indicate no version. Relative to setup_sector.
		__ukh_assert_fofs 0x210
.type_of_loader: db 0  ; (write obligatory) Bootloader identifier.
		__ukh_assert_fofs 0x211
.loadflags:	db 0  ; Linux kernel protocol option flags. Not specifying LOADFLAG.HIGH, so the the protected-mode code is will be loaded at LINUXKERNELSEG (== word [.start_sys_seg]<<4).
		__ukh_assert_fofs 0x212
.setup_move_size: dw 0  ; (modify obligatory) Move to high memory size (used with hooks). When using protocol 2.00 or 2.01, if the real mode kernel is not loaded at 0x90000, it gets moved there later in the loading sequence. Fill in this field if you want additional data (such as the kernel command line) moved in addition to the real-mode kernel itself.
		__ukh_assert_fofs 0x214
.code32_start:	dd 0  ; (modify, optional reloc) Bootloader hook. Unused.
		__ukh_assert_fofs 0x218
.ramdisk_image: dd 0  ; initrd load address (set by bootloader). 0 (NULL) if no initrd.
		__ukh_assert_fofs 0x21c
.ramdisk_size:	dd -1  ; initrd size (set by bootloader). 0 or unchanged if no initrd. UKH doesn't support initrd. UKH uses this number for ukh_hidden_sector_count32 and ukh_hidden_sector_count16 instead.
		__ukh_assert_fofs 0x220
.bootsect_kludge: dd 0  ; (kernel internal) DO NOT USE - for bootsect.S use only.
		__ukh_assert_fofs 0x224
.heap_end_ptr:	dw 0  ; (write obligatory) Free memory after setup end.
		__ukh_assert_fofs 0x226
.linux_boot_header.end:

%ifndef UKH_PAYLOAD_16  ; !!! Use this space better, for chain only. For Linux, QEMU would overwrite it.
.setup_chain:
bits 16
		int 0x10  ; Print character in AL. File identification programs can use this instruction (bytes 0xcd 0x10) to detect a 32-bit kernel payload.
		add word [cs:.jmp_offset-setup_sector], byte setup_chain32-setup_linux32  ; Self-modifying code: change the protected mode entry point from setup_linux32 to setup_chain32.
		jmp short .setup_linux_and_chain
%endif

		times 0x30-($-.start) db 0  ; QEMU 2.11.1 `qemu-system-i386 -kernel' overwrites some bytes within the .linux_boot_header. Offset 0x30 seems to be the minimum bytes left intact.

; Implementation of real-mode API function `call ukh_apiseg16:ukh_protected_mode16`.
%if ($-boot_sector)!=0x230
  %error ERROR_BAD_LOCATION_FOR_PROTECTED_MODE_FAR
  times -1 nop
%endif
.protected_mode_far:  ; Enters zero-based (flat) 32-bit protected mode. Must be called as a far call (with CS pointing to APISEG) from real mode. SS must be 0, high 16 bits of ESP must be 0. Disables interrupts (cli). Keeps all general-purpose registers intact. Ruins EFLAGS.
		jmp short .protected_mode_far_low

cpu 386
bits 32

; API function ukh_real_mode32. Call it from 32-bit protected mode at 0x90232.
		__ukh_assert_at boot_sector+0x232  ; Address part of the API.
.real_mode:  ; Enters (16-bit) real mode. Must be called as a near call from zero-based (flat) 32-bit protected mode. High 16 bits of ESP must be 0. EIP must be less than 1 MiB. Protected-mode CS will be EIP>>16<<12. Sets DS, ES, FS, GS to PAYLOADSEG, and SS to 0. Doesn't enable (sti) or disable (cli) interrupts. The caller may enable interrupts after the call. Keeps all general-purpose registers intact. Ruins EFLAGS.
		xchg eax, [esp]
		rol eax, 16
		shl ax, 12
		rol eax, 16
		xchg eax, [esp]  ; Converted linear address in EAX to real-mode segment:offset. Offset in AX is unchanged, segment is (orig_EAX&0xf0000)<<12.
		; Fall through to ukh_real_mode_jmp32.
; API function ukh_real_mode_jmp32. Push return segment:offset, and jump here from 32-bit protected mode at 0x90242.
.real_mode_jmp32:
		__ukh_assert_at boot_sector+0x242  ; Address part of the API.
		push eax  ; Save.
		mov ax, ..@BACK16_DS
		; We must use a far jump with a 16-bit offset here (to jump to a 16-bit protected code segment), because with a 32-bit offset it doesn't work in
		; 86Box-4.2.1, Intel 430VX chipset, Pentium-S P54C 90 MHz CPU. (Both work in QEMU 2.11.1, VirtualBox and https://copy.sh/v86).
		;jmp ..@BACK16_CS:.real1-boot_sector  ; This would be a far jump with a 32-bit offset. It doesn't work in 86Box.
		dw 0xea66, boot_sector.real1-boot_sector, ..@BACK16_CS  ; This is a far jump with a 16-bit offset. It woks in 86Box, and it's 1 byte shorter.

; API function ukh_a20_gate_al16.
.a20_gate_al16:
bits 16
		__ukh_assert_at boot_sector+0x24d  ; Address part of the API.
%ifdef UKH_PAYLOAD_16
		jmp near .a20_gate_al16_low
%else
		jmp short .a20_gate_al16_low
%endif

.setup_linux:  ; The Linux load protocol entry point jumps here from setup_sector.start in real mode, as `jmp APISEG+0x20:.setup_linux-setup_sector'. EAX, EBX, ECX, EDX, ESI, EDI, EBP, SS:ESP, DS, ES, FS, GS, most of EFLAGS are uninitialized.
bits 16
%ifdef UKH_PAYLOAD_16
  .setup_linux16:  ; There is some random working stack set up by the Linux bootloader. CS == 0x9020 == (APISEG<<4)+0x20. DS and ES are uninitialized.
  cpu 386
		; !! Populate boot_sector.drive_number and boot_sector.partition based on data received from a patched SYSLINUX 4.07 in *linux* mode. (No need to patch GRUB 1, it uses Multiboot by default.)
		cli
		cld
		push strict word APISEG
		pop ds
		add word [boot_sector.jmp_offset2-boot_sector], byte .setup_linux_cont16-.setup_chain  ; Self-modifying code.
		mov ax, PAYLOADSEG+((0xa00-BXS_SIZE)>>4)  ; Copy destination segment.
		mov cx, PAYLOADSEG  ; Copy source segment. !!! BUG: This should be LINUXKERNELSGEG here, and PAYLOADSEG in .setup_linux_cont16.
		push cx  ; Save.
		mov bx, (__payload_padded_end-ukh_payload-(0xa00-BXS_SIZE)+0x1ff)>>9  ; Number of 0x200-byte sectors to copy. Positive.
		jmp APISEG:(boot_sector.copy_payload-boot_sector)  ; Sets BX := 0 (in boot_sector.jump_to_setup_chan); CX := 0; SI := 0x200; DI := 0x200. Ruins AX (in boot_sector.jump_to_setup_chan), DX, DS, ES. When done, it will jump to .setup_linux_cont16, as modified above.
  .setup_linux_cont16:
		push cs
		pop ds  ; DS := APISEG+0x20.
		pop es  ; Restore ES := PAYLOADSEG.
		mov si, BXS_SIZE-0x200
		xor di, di  ; !!! Reuse the 0x200 value.
		mov ch, (0xa00-BXS_SIZE)>>1>>8  ; mov cx, (0xa00-BXS_SIZE)>>1  ; CL is already 0, as set by boot_sector.copy_payload.
		rep movsw
		db 0xa9  ; Opcode byte of `test ax, strict word ...', to skip over the `int 0x10' instruction below.
		; Fall thrugh to .setup_chain.

  .setup_chain:  ; Linux and chain load protocols both reach this. We assume that already DF=0 (cld), and that there is some randowm working stack. CS == 0x9020 == (APISEG<<4)+0x20. DS and ES are uninitialized.
  cpu 8086
		int 0x10  ; Print character in AL.
  %if $-.setup_chain!=2
    %error ERROR_BAD_INT_INSTRUCTION_SIZE  ; Required by `db 0xa9' above.
    times -1 nop
  %endif
		; Fall through to .setup_common16.

  .setup_common16:  ; Setup registers and jump to the kernel payload. Linux, chain and Multiboot load protocols all end here. We assume that already DF=0 (cld), and that there is some randowm working stack. CS == 0x9020 == (APISEG<<4)+0x20. DS and ES are uninitialized.
		xor cx, cx
		cli  ; To avoid race condition in setting SS and SP on a buggy 8086 CPU.
		mov ss, cx
  %if PAYLOADSEG>=0x1000
		mov sp, (0x10000)-4  ; Aligned to 4. We will keep ESP 16-bit only (i.e. we never put anything >=0x10000 to it after the `push esp' above) for simple compatibility with real mode, which uses the low 16 bits (SP) only.
  %else
		mov sp, PAYLOADSEG<<4  ; Aligned to 4.
  %endif
		sti
		mov bx, PAYLOADSEG
		mov ds, bx
		mov es, bx
		push bx  ; Segment PAYLOADSEG for the `retf' below.
		xor bx, bx
		push bx  ; Offset 0 for the `retf' below.
		xor dx, dx
		xor si, si
		xor di, di
		xor bp, bp
		sub ax, ax  ; In EFLAGS, set OF=0, SF=0, ZF=1, AF=0, PF=1 and CF=0 according to the result.
		retf  ; Jump to the 16-bit kernel payload entry point.
  cpu 386
%else
  %if 0  ; For debugging.
		mov ax, 0xe00+'S'
		xor bx, bx
		int 0x10  ; Print character in AL.
  %endif
		; !! Populate boot_sector.drive_number and boot_sector.partition based on data received from a patched SYSLINUX 4.07 in *linux* mode. (No need to patch GRUB 1, it uses Multiboot by default.)
  .setup_linux_and_chain:  ; EAX, EBX, ECX, EDX, ESI, EDI, EBP, SS:ESP, DS, ES, FS, GS, most of EFLAGS are uninitialized.
		cli  ; No interrupts allowed. The Linux bootloader usually provides a valid stack, but we don't rely on it.
		cld
  %if 1  ; !! What's wrong if we don't bother with NMI?
		mov al, 0x80  ; Disable NMI. !! Why is this needed? https://wiki.osdev.org/Protected_Mode
		out 0x70, al
  %endif
		xor ax, ax
		mov ss, ax
  %if PAYLOADSEG>=0x1000
		mov esp, (0x10000)-4  ; Aligned to 4. Temporary value, setup_common32 will overwrite it. We keep ESP 16-bit only (i.e. we never put anything >=0x10000 to it) for simple compatibility with real mode, which uses the low 16 bits (SP) only.
  %else
		mov esp, PAYLOADSEG<<4  ; Aligned to 4. Temporary value, setup_common32 will overwrite it.
  %endif

		mov al, 1  ; A20 gate direction: enable.
		push cs  ; Simulate far call.
		call .a20_gate_al16_low  ; Enable the A20 gate. We must do this in real mode mode.
		;
		push cs  ; Simulate far call for .protected_mode_far_low below.
		push strict word setup_linux32-setup_sector  ; Self-modifying code may change the offset here from setup_chain32 to setup_linux32, using .jmp_offset.
  .jmp_offset: equ $-2
		; When switching back real mode, we want the original IDT, not an empty one like this. GRUB 1 0.97 doesn't set it. QEMU Linux boot and Multiboot v1 boot don't set it. https://stackoverflow.com/q/79526862 ; https://stackoverflow.com/a/5128933 .
		;lidt [cs:idtr-setup_sector]
		lgdt [cs:gdtr-setup_sector]
		; Fall through to .protected_mode_far_low in 32-bit mode.
%endif
		; Fall through to .protected_mode_far_low in 32-bit mode.

.protected_mode_far_low:
		cli
%ifdef UKH_PAYLOAD_16  ; We haven't done it in .setup_linux_and_chain, so we have to do it here.
		push ds  ; Save.
		push strict word APISEG
		pop ds
		lgdt [gdtr-boot_sector]
		pop ds  ; Restore.
		and esp, 0xffff  ; Set the high word of ESP to 0.
%endif
		push eax  ; Save.
		mov eax, cr0  ; !! Save registers.
		or al, 1  ; PE := 1.
		mov cr0, eax
		mov ax, ..@KERNEL_DS
		jmp ..@KERNEL_CS:dword ((APISEG<<4)+.prot_ret-boot_sector)  ; This is 8 bytes, without dword it jumps incorrectly. Jumps to .prot_ret (right below), activates protected mode.
.prot_ret:
bits 32
		mov ds, ax
		mov es, ax
		mov ss, ax  ; Since the protected-mode SS is also zero-based, ESP remains valid.
		mov fs, ax
		mov gs, ax
		pop eax  ; Restore.
		; Magic to convert a real-mode segment*16+offset address to a linear address in dword [ESP], without modifying any general-purpose registers. (It modifies EFLAGS.)
		xchg eax, [esp]
		;
		; This would also work, but it's longer.
		;push eax
		;movzx eax, ax  ; Keep only the offset.
		;xchg eax, [esp]
		push strict word 0  ; This pushes 2 bytes in protected mode.
		push ax
		;
		shr eax, 12
		and al, 0xf0
		add [esp], eax  ; Add offset to linear segment. Keep it pushed for the `ret' below.
		pop eax  ; Discard the linear address corresponding to the segment.
		xchg eax, [esp]
		; End of linear address conversion magic.
		ret  ; This is already in protected mode, but the ret opcode is the same.
bits 16

; Enables (AL == 1 or other nonzero, no wraparound at 1 MiB) or disables (AL
; == 0, wraparound at 1 MiB) the A20 gate. Must be called in real mode
; (because it calls an interrupt: int 15h). Ruins: AX, DX.
;
; int 15h (AX == 0x2400: disable A20 gate; AX == 0x2401: enable A20 gate)
; documentation: https://fd.lod.bz/rbil/interrup/bios_vendor/152400.html and
; https://fd.lod.bz/rbil/interrup/bios_vendor/152401.html
;
; This routine is probably overconservative in what it does, but so what?
; It may also eats keystrokes in the keyboard buffer.
;
; Based on gateA20 in src/asm.S in GRUB 1 0.97-29ubuntu68. The
; implementation in GRUB4DOS is way too long. Maybe SYSLINUX 4.07 has
; something useful.
;
; It must be called with interrupts disabled, to prevent interference with
; the keyboard controller.
;
; !! TODO(pts): Replace the logic with http://wiki.osdev.org/A20_Line#Final_code_example .
.a20_gate_al16_low:
		; First, try the BIOS int 15h call.
.try_int15h:	cmp al, 1  ; CF := is_zero(AL).
		mov ax, 0x2401
		sbb al, 0  ; AX := 0x2400 if DL is 0 (disable), otherwise 0x2401 (enable).
		push ax  ; Save direction.
		stc
		int 0x15
		pop dx  ; Restore CL := direction; CH := 0x24.
		jc short .try_port92h  ; Jump on failure.
		test ah, ah
		jne short .try_port92h  ; Jump on failure.
		retf  ; This works for QEMU 2.11.1.
.try_port92h:  ; Try to switch gateA20 using PORT92, the "Fast A20 and Init" register.
		mov ah, dl  ; AH := direction.
		mov dx, 0x92
		in al, dx  ; This always overwrites the previous value of AL. https://stackoverflow.com/q/79540330
		cmp al, 0xff
		je short .try_keyboard  ; Skip the port92 code if it's unimplemented (read returns 0xff).
		or al, 2  ; Set the ALT_A20_GATE bit.
		test ah, ah
		jnz short .bit_done
		and al, ~2  ; Clear the ALT_A20_GATE bit.
.bit_done:	and al, ~1  ; Clear the INIT_NOW bit, so that we don't accidently reset the machine.
		out dx, al
		; Use the keyboard controller method anyway. !! Why? (Maybe because for disabling we need both.) https://stackoverflow.com/q/79529680
.try_keyboard:  ; Use the keyboard controller.
		call .gloop1
		mov al, 0xd1  ; KC_CMD_WOUT.
		out 0x64, al  ; K_CMD.
.gloopint1:	in al, 0x64  ; K_STATUS.
		cmp al, 0xff
		jz short .gloopint1_done
		and al, 2  ; K_IBUF_FULL.
		jnz short .gloopint1
.gloopint1_done:
		mov al, 0xdd  ; KB_OUTPUT_MASK.
		test ah, ah
		jz short .after_enable
		or al, 2  ; KB_A20_ENABLE.
.after_enable:	out 0x60, al  ; K_RDWR.
		call .gloop1
		mov al, 0xff
		out 0x64, al  ; K_CMD.
		call .gloop1
		retf
.gloop1:	in al, 0x64  ; K_STATUS.
		cmp al, 0xff
		jz short .gloop2ret
		and al, 2  ; K_IBUF_FUL.
		jnz short .gloop1
.gloop2:	in al, 0x64  ; K_STATUS.
		and al, 1  ; K_OBUF_FUL.
		jz short .gloop2ret
		in al, 0x60  ; K_RDWR.
		jmp short .gloop2
.gloop2ret:	ret

; Can be anywhere in the first 0x800 bytes (setup_sects * 0x200 bytes).
.kernel_version_string: db UKH_VERSION_STRING, 0

bits 32

%ifdef UKH_MULTIBOOT
  setup_multiboot:  ; Loaded to OUR_MULTIBOOT_LOAD_ADDR by the bootloader, interrupts disabled, no stack (ESP is invalid). Works according to the Multiboot v1 specification: https://www.gnu.org/software/grub/manual/multiboot/multiboot.html
		;cli  ; Not needed, https://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Machine-state mandates it.
		cld  ; Needed.
		;mov al, 1  ; A20 gate direction: enable.
		;push cs  ; Simulate far call.
		;call_in_real_mode .a20_gate_al16_low  ; Enable the A20 gate. We must do this in real mode mode. Not needed, https://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Machine-state mandates it.
		;cmp eax, 0x2badb002  ; We ignore this Multiboot signature.
		;xchg ebp, eax  ; EBP := multiboot signature; EAX := junk.
		mov esi, OUR_MULTIBOOT_LOAD_ADDR
		test byte [ebx], MULTIBOOT_INFO_BOOTDEV	 ; EBX is still set to the address of the multiboot_info struct set up by the bootloader. https://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Boot-information-format
		jz short .boot_drive_done
		mov eax, [ebx+3*4+2]  ; part1|drive<<8|any1<<16|any2<<32 in multiboot_info.boot_device.
		mov [esi+boot_sector.partition-boot_sector], ax  ; Save part1 to boot_sector.partition and drive to the UKH final boot_sector.drive_number.
  .boot_drive_done:
  .copy_2_sectors:
		; Copy the first 2 sectors to APISEG.
		mov edi, APISEG<<4
		mov ecx, BXS_SIZE>>2
		rep movsd
  .lgdt:
		lgdt [byte edi-BXS_SIZE+gdtr-boot_sector]  ; Make subsequent API calls to ukh_protected_mode and  ukh_real_mode work. We don't need to reload the CS, DS etc. just yet.
  .cmdline:	;xor ecx, ecx  ; Empty command line by default. No need to set it, ECX is already 0.
		test byte [ebx], MULTIBOOT_INFO_CMDLINE  ; multiboot_info.flags.
		jz short .got_cmdline_length  ; If it jumps, because of ECX == 0, an empty command-line-string will be used.
		mov esi, [ebx+4*4]  ; ESI: pointer to the command line from multiboot_info.cmdline.
  .next_cmdline_char:
		cmp byte [esi+ecx], 0
		je short .got_cmdline_length
		inc ecx
		jmp short .next_cmdline_char
  .got_cmdline_length:  ; Now: ECX == length of the command line without the trailing NUL, ESI: address of the command line (invalid if ECX == 0).
		mov eax, (APISEG<<4)+0xa000-1
		sub eax, ecx  ; TODO(pts): Abort if too long (>=0xa000-0x30), to avoid buffer overflow.
		mov [(APISEG<<4)+boot_sector.cl_offset-boot_sector.start], eax  ; Also sets boot_sector.cl_offset_high_word, but keeps it unchanged (APISEG>>12).
		xchg edi, eax  ; EDI := Start of the copy of our kernel command-line string.
		;mov [ebx+4*4], edi  ; Change multiboot_info.cmdline to our copy. This is not needed.
		rep movsb  ; !! Copy it backwards if needed on overlap.
		mov [edi], cl  ; Add terminating NUL. CL == ECX == 0.
  .copy_payload:  ; Copy the payload (ukh_payload) to PAYLOADSEG<<4. We must copy late, because earlier we'd overwrite the command line by GRUB 1 0.97 (but not by GRUB4DOS 0.4.4).
		mov esi, OUR_MULTIBOOT_LOAD_ADDR+BXS_SIZE
		mov edi, PAYLOADSEG<<4
  %ifdef UKH_PAYLOAD_16  ; Stack setup for `jmp setup_sector.real_mode_jmp32' below.
    %if PAYLOADSEG>=0x1000
		mov esp, (0x10000)-4  ; Aligned to 4. We will keep ESP 16-bit only (i.e. we never put anything >=0x10000 to it after the `push esp' above) for simple compatibility with real mode, which uses the low 16 bits (SP) only.
    %else
		mov esp, edi  ; mov esp, PAYLOADSEG<<4  ; Aligned to 4.
    %endif
  %endif
		mov ecx, (ukh_payload_end-ukh_payload+3)>>2
		rep movsd
  %if 1  ; !! What's wrong if we don't bother with NMI?
  .disable_nmi:
		mov al, 0x80  ; Disable NMI. !! Why is this needed? https://wiki.osdev.org/Protected_Mode
		out 0x70, al
  %endif

		; EBX is still set to the address of the multiboot_info struct set up by the bootloader. https://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Boot-information-format
		; The Multiboot v1 specification allows any (nonworking) value in SS:ESP now.
  %ifdef UKH_PAYLOAD_16
		push strict dword (APISEG+0x20)<<16|(setup_sector.setup_common16-setup_sector)  ; Stack set up above.
		jmp setup_sector.real_mode_jmp32
  %else
		jmp short setup_common32
  %endif
%endif

%ifndef UKH_PAYLOAD_16
  setup_linux32:  ; We assume that already IF=0 (cli) and DF=0 (cld). The stack is not usable yet.
		; Copy (move) data--code at LINUXKERNELSEG<<4 forward to (PAYLOADSEG<<4)+3*0x200 (typically by 3 sectors), to make room for 3 (of 4) setup sectors.
		mov ecx, (__payload_padded_end-ukh_payload+3-3*0x200)>>2
  %if (LINUXKERNELSEG<<4)<=((PAYLOADSEG<<4)+3*0x200)  ; Copy the data backward (descending), because the destination comes after the source, and they may overlap.
		std
		mov esi, (LINUXKERNELSEG<<4)+((__payload_padded_end-ukh_payload-1-3*0x200)&~3)
		mov edi, ((PAYLOADSEG<<4)+3*0x200)+((__payload_padded_end-ukh_payload-1-3*0x200)&~3)
		rep movsd
		cld
		lea edi, [esi+4]  ; EDI := PAYLOADSEG<<4.
  %else  ; Copy the data forward (ascending), because the destination comes before the source, and they may overlap.
		mov esi, LINUXKERNELSEG<<4
		mov edi, (PAYLOADSEG<<4)+3*0x200
		rep movsd
		mov edi, PAYLOADSEG<<4
  %endif
		; Copy the last 3 setup sectors from (APISEG<<4)+2*0x200 to PAYLOADSEG<<4.
		mov esi, (APISEG<<4)+2*0x200
		mov cx, (3*0x200)>>2  ; 1 byte shorter than `mov ecx, ...'.
		rep movsd
		; Fall through to setup_chain32.

  setup_chain32:  ; Linux and chain load protocols both reach this.
		; Fall through to setup_common32.

  setup_common32:  ; Setup registers and jump to the kernel payload. Linux, chain and Multiboot load protocols all end here. We assume that already IF=0 (cli) and DF=0 (cld). The stack is not usable yet (especially for Multiboot).
  %if PAYLOADSEG>=0x1000
		mov esp, 0x10000  ; Aligned to 4. We keep ESP 16-bit only (i.e. we never put anything >=0x10000 to it after the `push esp' above) for simple compatibility with real mode, which uses the low 16 bits (SP) only.
  %else
		mov esp, PAYLOADSEG<<4  ; Aligned to 4.
  %endif
		push esp  ; Jump target of the `jmp dword [esp]' below, the payload entry point.
		sub eax, eax  ; In EFLAGS, set OF=0, SF=0, ZF=1, AF=0, PF=1 and CF=0 according to the result.
		times 8 push eax
		popa  ; Set EAX, EBX, ECX, EDX, ESI, EDI and EBP to 0 (but not ESP). We do it for reproducibility.
		jmp dword [esp]  ; Jump to the 32-bit kernel payload entry point. !! Size-optimize this to a `ret', making esp above 4 bytes smaller.
%endif
bits 16
cpu 8086

; These data bytes have to be valid only for the duration of the lgdt or
; lidt instruction. The table entries have to remain valid until the next
; lgdt or lidt instruction (i.e. long).
;
; We put this very late in setup_sector, for the size saving in setup_multiboot.
gdtr:		dw boot_sector.gdt_end-boot_sector.gdt-1  ; GDT limit.
		dd (APISEG<<4)+boot_sector.gdt-boot_sector  ; GDT base.

%ifdef UKH_MULTIBOOT
		times BXS_SIZE-OUR_MULTIBOOT_HEADER_SIZE-($-boot_sector) db '-'
		__ukh_assert_fofs BXS_SIZE-OUR_MULTIBOOT_HEADER_SIZE
  multiboot:  ; Multiboot v1 header, 0x20 bytes. i386 is hardcoded.
  .multiboot.align_check: times -(($-boot_sector.start)&3) nop  ; Check alignment of the .multiboot_v1 below, in case the bootloader checks only aligned locations.
  .multiboot.magic: dd MULTIBOOT_MAGIC
  .multiboot.flags: dd OUR_MULTIBOOT_FLAGS
  .multiboot.checksum: dd -MULTIBOOT_MAGIC-OUR_MULTIBOOT_FLAGS
  .multiboot.header_addr: dd OUR_MULTIBOOT_LOAD_ADDR+(multiboot-boot_sector)  ; This is smaller than OUR_MULTIBOOT_LOAD_ADDR. It would be ERR_EXEC_FORMAT if .multiboot.magic came before .multiboot.load_addr.
  .multiboot.load_addr: dd OUR_MULTIBOOT_LOAD_ADDR  ; Linear address. ERR_BELOW_1MB for PAYLOADSEG<<4, thus we use OUR_MULTIBOOT_LOAD_ADDR and setup_multiboot.copy_payload instead.
  .multiboot.load_end_addr: dd OUR_MULTIBOOT_LOAD_ADDR+(ukh_payload_end-boot_sector)
  .multiboot.bss_end_addr:  dd OUR_MULTIBOOT_LOAD_ADDR+(ukh_payload_end-boot_sector)  ; No specific .bss to be cleared by the bootloader.
  .multiboot.entry_addr: dd OUR_MULTIBOOT_LOAD_ADDR+(setup_multiboot-boot_sector)
  .multiboot.end:
  .multiboot.size_check: __ukh_assert_at multiboot+0x20
%else
		times BXS_SIZE-($-boot_sector) db '-'
%endif
		__ukh_assert_fofs BXS_SIZE

; --- The UKH API.

; UKH API available in 32-bit protected mode.
ukh_partition32            equ 0x90026  ; Example usage: `mov al, [ukh_partition32]'.    It works with any org. Partition within the BIOS boot drive, or 0xff if the entire drive should be used. Default value of 0xfe indicates unknown. The first primary partition has number 0. Currently it may only be known for the Multiboot load protocol.
ukh_drive_number32         equ 0x90027  ; Example usage: `mov dl, [ukh_drive_mumber32]'. It works with any org. BIOS boot drive number (first floppy is 0, first HDD is 0x80). Default value of 0xff indicates unknown, and it remains this way for the Linux load protocol and for the Multiboot load protocol via QEMU.
ukh_real_mode32            equ 0x90232  ; Most users should use macro ukh_protected_mode instead. As `call ...', this only works with `org (PAYLOADSEG<<4)-BXS_SIZE'. As `push ... ++ ret', it works with any org.
ukh_real_mode_jmp32        equ 0x90242  ; Most users should use macro ukh_protected_mode instead. Don't `call ...', but push return segment:offset, and jump here from 32-bit protected mode at 0x90242. It works with any org.
ukh_kernel_cmdline_ptr32   equ 0x90022  ; Kernel command-line string as a NUL-terminated byte string starting at linear address dword [ukh_kernel_cmdline_ptr32]. It works with any org.
ukh_hidden_sector_count32  equ 0x9021c  ; Number of sectors (LBA) on the BIOS boot drive (byte [ukh_drive_number32]) before the boot partition for the FreeDOS and DR-DOS load protocols (-1 if unknown or for the other load protocols). Also called the partition start offset.
; See macro ukh_real_mode below.
; See macro ukh_halt defined above.

; UKH API available in real mode.
ukh_apiseg16               equ APISEG
;ukh_base16                equ -(PAYLOADSEG<<4)  ; Defined above. This is for real-mode code in the payload .nasm source. Example: `mov si, message+ukh_base16'. If (UKH_PAYLOAD_SEG&0xfff)==0 (default), then it can be omitted: `mov si, message'.
ukh_partition16            equ    0x26  ; Example usage if DS == ukh_apiseg16: `mov al, [ukh_partition16]'.    It works with any org. Partition within the BIOS boot drive, or 0xff if the entire drive should be used. Default value of 0xfe indicates unknown. The first primary partition has number 0. Currently it may only be known for the Multiboot load protocol.
ukh_drive_number16         equ    0x27  ; Example usage if DS == ukh_apiseg16: `mov dl, [ukh_drive_mumber16]'. It works with any org. BIOS boot drive number (first floppy is 0, first HDD is 0x80). Default value of 0xff indicates unknown, and it remains this way for the Linux load protocol and for the Multiboot load protocol via QEMU.
ukh_a20_gate_al16          equ   0x24d  ; Most users should use macro ukh_a20_gate_al instead. In real mode, `call ukh_apiseg16:ukh_a20_gate_al16'. It works with any org.
ukh_protected_mode16       equ   0x230  ; Most users should use macro ukh_protected_mode instead. In real mode, `call ukh_apiseg16:ukh_protected_mode16'. It works with any org.
ukh_kernel_cmdline_ptr16   equ    0x22  ; Kernel command-line string as a NUL-terminated byte string starting at ukh_apiseg16:(word [ukh_apiseg:ukh_kernel_cmdline_ptr16]). It works with any org.
ukh_hidden_sector_count16  equ   0x21c  ; Number of sectors (LBA) on the BIOS boot drive (byte [ukh_apiseg16:ukh_drive_number16]) before the boot partition for the FreeDOS and DR-DOS load protocols (-1 if unknown or for the other load protocols). Also called the partition start offset. It works with any org.
; See macro ukh_protected_mode below.
; See macro ukh_a20_gate_al below.
; See macro ukh_halt defined above.

%ifdef UKH_PAYLOAD_32  ; 32-bit kernel payload.
  %define OUR_CPU 386
  %define UKH_BITS 32
%elifdef UKH_PAYLOAD_16  ; 16-bit kernel payload.
  %define OUR_CPU 8086
  %define UKH_BITS 16
%endif
cpu OUR_CPU
bits UKH_BITS

%macro ukh_real_mode 0
  %if UKH_BITS==32
    ;call $$+ukh_real_mode32-(PAYLOADSEG<<4)+BXS_SIZE  ; ukh_real_mode32. Works independently of `org'.
    call ukh_real_mode32  ; This only works with `org (PAYLOADSEG<<4)-BXS_SIZE'.
    %define UKH_BITS 16
    bits 16
  %else
    %error ERROR_MUST_BE_IN_PROTECTED_MODE
    times -1 nop
  %endif
%endm

%macro ukh_protected_mode 0
  %if UKH_BITS==16
    call ukh_apiseg16:ukh_protected_mode16
    %define UKH_BITS 32
    %if OUR_CPU==8086 || OUR_CPU<386
      %define OUT_CPU 386
      cpu 386
    %endif
    bits 32
  %else
    %error ERROR_MUST_BE_IN_REAL_MODE
    times -1 nop
  %endif
%endm

%macro ukh_a20_gate_al 1  ; Enables (AL == 1) or disables (AL == 0) the A20 gate. We must do this in 16-bit mode, with interrupts disabled. Ruins AL.
  %if UKH_BITS==16
    mov al, %1  ; A20 gate direction.
    call ukh_apiseg16:ukh_a20_gate_al16
  %else
    %error ERROR_MUST_BE_IN_REAL_MODE
    times -1 nop
  %endif
%endm

%macro ukh_end 0
  ukh_payload_end:
  %if (PAYLOADSEG&0x1f) && ((PAYLOADSEG+0x20)&~0xfff)!=((PAYLOADSEG+((ukh_payload_end-ukh_payload+BXS_SIZE+0x1ff)>>4))&~0xfff)
    %assign __UKH_VALUE PAYLOADSEG
    %error ERROR_UKH_PAYLOAD_SEG_CROSSES_64K __UKH_VALUE  ; If we allowed this, then .load_payload_sectors wouldn't be able to load the image, because it would cross the 64 KiB boundary imposed by PC floppy BIOS (also SeaBIOS in QEMU 2.11.1).
    ; !! As a workaround, add a temporary, aligned 0x200-byte buffer.
    db 1/0
  %endif
  %if PAYLOADSEG+(((ukh_payload_end-ukh_payload+0x1ff)&~0x1ff)>>4)>APISEG
    %error ERROR_UKH_PAYLOAD_OVERLAPS_APISEG  ; Workaround: make your kernel payload shorter or decrease UKH_PAYLOAD_SEG.
    db /10
  %endif
  %if $-boot_sector<0xa01  ; File size must be at least 5 sectors (0xa00 == 2560 bytes in setup sectors) + 1 byte (in payload) for the old Linux load protocol.
    times 0xa01-($-boot_sector) db 0
  %endif
  __payload_padded_end:  ; Use size based on this for some short copies.
  __missing_ukh_end equ 0  ;  If you get a NASM error `symbol `__missing_ukh_end' undefined', then just add macro invocation `ukh_end' to the end of your .nasm source.
%endm

; --- Now comes the payload, at file offset 0x400.
;
; * The payload will be loaded to (PAYLOADSEG<<4) == 0x10000.
; * Maximum payload size: 512 KiB, but the bootloader may restrict it further.
;

ukh_payload:

%ifdef __UKH_PAYLOAD_FILE
  incbin __UKH_PAYLOAD_FILE, UKH_PAYLOAD_FILE_SKIP
  ukh_end
%endif
