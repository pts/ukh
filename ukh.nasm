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

%ifdef UKH_PAYLOAD_16A_FILE  ; Must be a filename in quotes.
  %define UKH_PAYLOAD_16A
  %define __UKH_PAYLOAD_FILE UKH_PAYLOAD_16A_FILE
%endif

%ifdef UKH_PAYLOAD_16B_FILE  ; Must be a filename in quotes.
  %define UKH_PAYLOAD_16B
  %define __UKH_PAYLOAD_FILE UKH_PAYLOAD_16B_FILE
%endif

%ifdef UKH_PAYLOAD_16A
  %define UKH_PAYLOAD_16
%endif
%ifdef UKH_PAYLOAD_16B
  %define UKH_PAYLOAD_16
%endif

%ifdef UKH_PAYLOAD_16
  %ifdef UKH_PAYLOAD_32
    %error ERROR_CONFIG_CONFLICT_PAYLOAD_16_32
    db 1/0
  %endif
  %ifdef UKH_PAYLOAD_16A
    %ifdef UKH_PAYLOAD_16B
      %error ERROR_CONFIG_CONFLICT_PAYLOAD_16_SUBTYPE
      db 1/0
    %endif
  %elifndef UKH_PAYLOAD_16B
    %error ERROR_CONFIG_MISSING_PAYLOAD_16_SUBTYPE
    db 1/0
  %endif
  %error ERROR_UNSUPPORTED_PAYLOAD_16
%elifndef UKH_PAYLOAD_32
  %error ERROR_MISSING_PAYLOAD_TYPE  ; Add e.g. `%define UKH_PAYLOAD_32'.
%endif

%ifdef UKH_PAYLOAD_FILE_SKIP  ; Number of bytes to skip near the beginning. Nonnegative integer constant.
  %assign UKH_PAYLOAD_FILE_SKIP UKH_PAYLOAD_FILE_SKIP
%else
  %define UKH_PAYLOAD_FILE_SKIP 0
%endif

%ifndef UKH_VERSION_STRING
  %define UKH_VERSION_STRING 'ukh'
%endif

; --- Implementation for the UKH header (boot_sector: 0x200 bytes, setup_sector: 0x200 bytes).

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

UKH_KERNEL_CMDLINE_MAGIC_VALUE equ 0xa33f  ; See above.
;LINUX_CL_MAGIC equ 0xa33f
OUR_LINUX_BOOT_PROTOCOL_VERSION equ 0x201  ; 0x201 is the last one which loads everything under 0xa0000 (even 0x9a000). Later versions load code32 above 1 MiB (linear address >=0x100000).

MULTIBOOT_MAGIC equ 0x1badb002
MULTIBOOT_FLAG_AOUT_KLUDGE equ 1<<16
MULTIBOOT_INFO_BOOTDEV equ 1<<1
MULTIBOOT_INFO_CMDLINE equ 1<<2
OUR_MULTIBOOT_FLAGS equ MULTIBOOT_FLAG_AOUT_KLUDGE
OUR_MULTIBOOT_LOAD_ADDR equ 0x100000  ; The minimum value is 0x100000 (1 MiB), otherwise GRUB 1 0.97 fails with: Error 7: Loading below 1MB is not supported
OUR_MULTIBOOT_HEADER_SIZE equ 0x20

BXS_SIZE equ 0x400  ; Total size of boot sector and setup sectors.
KERNELSEG equ 0x1000
INITSEG equ 0x9000  ; We assume that BXS_SIZE bytes at boot_sector (including us) have been loaded to linear address INITSEG<<4.
BOOT_ENTRY_ADDR equ 0x7c00

org (KERNELSEG<<4)-BXS_SIZE  ; This is for the payload .nasm source. The code in ukh.nasm works with arbitrary `org', because it always subtracts boot_sector etc.

LOADFLAG_READ:
.HIGH: equ 1 << 0

%macro ukh_halt 0  ; Works in both protected mode and real mode. This is part of the API.
  cli
  %%back: hlt
  jmp short %%back
%endm

; With the Linux load protocol, the bootloader loads the first 5 sectors
; (0xa00 bytes) (boot_sector and setup sector) to INITSEG<<4 (== 0x90000),
; the rest (code32) to KERNELSEG<<4 (== 0x10000) and then jumps to 0x9020:0
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
; What is near 0xa0000 (64 KiB after INITSEG == 0x9000): EBDA (Extended BIOS
; Data Area). Its segment is referenced by a word at 0x40e (in real-mode
; memory), which is typically 1 KiB 0x9fc00..0xa0000.
boot_sector:  ; 1 sector of 0x200 bytes.
.start:
.gdt:  ; The first GDT entry (segment descriptor, 8 bytes) can contain arbitrary bytes, so we overlap it with boot code. https://stackoverflow.com/a/33198311
		; https://wiki.osdev.org/Global_Descriptor_Table#Segment_Descriptor
		; The GDT has to remain valid until the next lgdt instruction (potentially long), so we'll keep it at linear address 0x90000.
.code:		cld
		call .code2
.here:		; Not reached, .code2 will pop the return address.
; API function ukh_a20_gate_far. Call it from real mode at 0x9000:4.
.a20_gate_far:	jmp near setup_sector.a20_gate_far_low
.drive_number:  db 0xff  ; byte [0x90007]. Default value of 0xff indicates unknown, and it remains this way for the Linux load protocol and for the Multiboot load protocol via QEMU.
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
		EMIT_CODE_SEGMENT_DESCRIPTOR(INITSEG<<4, 0xffff, 1, 1, 0, 0, 1, 0, 0, 0)  ; dw 0xffff, ..., 0x9b00|..., 0|...  ; 16-bit, code, base 0. pts-grub1-port stage2/asm.S also has these values. This is the initial contents of the shadow descriptor (except for base=0 there) in CS in QEMU 2.11.1 boot sector load time.
		;EMIT_CODE_SEGMENT_DESCRIPTOR(0, 0xffff, 1, 1, 0, 0, 1, 0, 0, 0)  ; dw 0xffff, 0, 0x9b00, 0  ; 16-bit, code, base 0. pts-grub1-port stage2/asm.S also has these values. This is the initial contents of the shadow descriptor in CS in QEMU 2.11.1 boot sector load time.
		;EMIT_CODE_SEGMENT_DESCRIPTOR(0, 0xffff, 0, 1, 1, 0, 1, 0, 0, 0)  ; dw 0xffff, 0, 0x9e00, 0  ; 16-bit, code, base 0. GRUB 1 0.97 stage2/asm.S also has these values.
		__ukh_assert_at .gdt+4*8  ; Must be at most .cl_magic-.start, so that the GDT doesn' get overwritten.
.cl_magic:  ; equ .start+0x20  ; (dw) The Linux bootloader will set this to: dw UKH_KERNEL_CMDLINE_MAGIC_VALUE (== 0xa33f).
.cl_offset: equ $+2  ; equ .start+0x22  ; (dw) The Linux bootloader will set this to (dw) the offset of the kernel command line. The segment is INITSEG.
.cl_offset_high_word: equ $+4  ; equ .start+0x24  ; (dw) Will be set to 9, so that dword [0x90022] can be used as a pointer to the kernel command line.
.code2:		pop si  ; SI := actual offset of .here. Self-modifying code: 6 bytes here overlap with word [.cl_magic], word [.cl_offset], word [.cl_offset_high_word].
		sub si, byte .here-.start  ; SI := actual offset of .start.
		mov cx, cs
		jmp short .code3
		__ukh_assert_at .gdt+5*8
..@BACK16_DS: equ $-.gdt  ; Segment ..@BACK16_DS == 0x28 descriptor. Used for switching back to real mode. Its flags will be reused when back in real mode. Won't actually be used to reference memory while switching.
		EMIT_DATA_SEGMENT_DESCRIPTOR(0,        0xffff, 1, 1, 0, 0, 1, 0, 0, 0)  ; dw 0xffff, 0, 0x9300, 0  ; 16-bit, data, base 0. pts-grub1-port stage2/asm.S also has these values. This is the initial contents of the shadow descriptor in DS, ES, FS, GS, SS in QEMU 2.11.1 boot sector load time.
		;EMIT_DATA_SEGMENT_DESCRIPTOR(0,       0xffff, 0, 1, 0, 0, 1, 0, 0, 0)  ; dw 0xffff, 0, 0x9200, 0  ; 16-bit, data, base 0. GRUB 1 0.97 stage2/asm.S also has these values.
		;EMIT_DATA_SEGMENT_DESCRIPTOR(0xfffff, 0xffff, 1, 1, 0, 0, 1, 0, 0, 0)  ; dw 0xffff, 0, 0x9300, 0  ; 16-bit, data, read-write, base arbitrary (0xfffff, arbitrary, unused, unusual), limit 0xffff, limit limit granularity 0 (1 byte). upfx_32.nasm has these values.
.gdt_end:	__ukh_assert_at .gdt+6*8
.code3:		mov ax, 0xe00+'?'  ; Set up error message.
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
.halt:		ukh_halt
.chain_protocol:  ; Now: CX == 0; DS == 0; SI == 0x7c00 == BOOT_ENTRY_ADDR; DL is the bios drive number.
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
		mov cx, (.copy_of_setup_sector.end-.copy_of_setup_sector)>>1
		repe cmpsw
		je short .cmp_matches
		mov al, 'F'  ; Fail with fatal error: `bF' means that the bootloader has loaded only he first sector.
		int 0x10
		jmp short .halt
.cmp_matches:
		;xor cx, cx  ; CX := 0. Not needed, CX is now 0.
		mov al, 's'
		mov cx, BOOT_ENTRY_ADDR>>4
.any_supported_protocol:  ; Now: DS:SI points to the loaded boot_sector+setup_sector; AL is character to print; DL is the BIOS drive number.
		xor bx, bx  ; Set up error message.
		int 0x10  ; Print character in AL.
		mov al, dl  ; BIOS drive number. !! Remove these debug prints (but some of them indicate progress).
		int 0x10  ; Print BIOS boot drive character. !! No need to print these.

		; Set up some segments and stack.
		mov ds, cx  ; After this (until we break DS again) global variables work.
		mov es, [.initseg_const-.start]  ; ES := INITSEG.
		cli
		push es
		pop ss  ; SS := INITSEG.
		mov sp, 0xa000  ; Set SS:SP to INITSEG:0xa000 (== 0x9000:0xa000), similarly to how QEMU 2.11.1 `-kernel' acts as a Linux bootloader, it sets 0x9000:(0xa000-cmdline_size-0x10).
		sti

		; Copy BXS_SIZE bytes (2 sectors) from DS:0 (actually loaded boot_sector+setup_sector) to INITSEG:0. There is no overlap.
		xor si, si
		xor di, di
		; Good: SYSLINUX 4.07 *boot*, GRUB4DOS *chainloader*, GRUB *kernel* with Multiboot only and the DOS boot sectors pass the BIOS drive number (e.g. 0x80 for first HDD) in DL. (Or in BL, but we've already copied it to DL.)
		mov [si+.drive_number-.start], dl  ; Save BIOD drive number to its final UKH boot protocol location.
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
		add cx, strict word BXS_SIZE>>4  ; Skip over boot_sector+setup_sector. !! Remove `strict word' if it becomes smaller.
		mov ax, KERNELSEG
		; Now: CX == segment of first source sector (with offset 0 it points to code32), minus BXS_SIZE>>4; AX == KERNELSEG.
		cmp cx, ax
		jae short .after_setup_copy  ; Copy them in forward (ascending), because the destination comes before the source, and they may overlap.
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

		jmp (INITSEG+0x20):(setup_sector.setup_chain-setup_sector)

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
		;jmp INITSEG:(.real2-boot_sector)  ; 5 bytes: 1 opcode, 2 offset, 2 segment. With this jump, we would switch to real mode CS.
;.real2:  ; We are in real mode now in terms of CS.
		xor ax, ax
		mov ss, ax  ; This updates the only base in the shadow descriptor to 0.
  %if KERNELSEG&0xff
    %error ERROR_KERNELSEG_HAS_NONZERO_LOW_BYTE  ; This prevents the `mov ah, ..' optimization below.
    times -1 nop
  %endif
		mov ah, KERNELSEG>>8  ; 1 byte shorter than `mov ax, KERNELSEG'.
		mov ds, ax  ; This updates the only base in the shadow descriptor to KERNELSEG.
		mov es, ax  ; This updates the only base in the shadow descriptor to KERNELSEG.
		mov fs, ax  ; This updates the only base in the shadow descriptor to KERNELSEG.
		mov gs, ax  ; This updates the only base in the shadow descriptor to KERNELSEG.
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
		dw KERNELSEG
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
.syssize_low:	dw (code32.end-code32+0xa00-BXS_SIZE+0xf)>>4  ; (read) The low word of size of the 32-bit code in 16-byte paras. Ignored by GRUB 1 or QEMU. Maximum size allowed: 1 MiB, but Linux kernel protocol <=2.01 supports zImage only, with its maximum size of 512 KiB.
		__ukh_assert_fofs 0x1f6
.swap_dev:
.syssize_high:	dw 0  ; (read) The high word size of the 32-bit code in 16-byte paras. For Linux kernel protocol prior to 2.04, the upper two bytes of the syssize field are unusable, which means the size of a bzImage kernel cannot be determined.
		__ukh_assert_fofs 0x1f8
.ram_size:	dw 0  ; (kernel internal) DO NOT USE - for bootsect.S use only.
		__ukh_assert_fofs 0x1fa
.vid_mode:	dw 0  ; (read, modify obligatory) Video mode control.
		__ukh_assert_fofs 0x1fc
.root_dev:	dw 0  ; (read, modify optional) Default root device number. Neither GRUB 1 nor QEMU 2.11.1 set it.
		__ukh_assert_fofs 0x1fe
.boot_flag:	dw BOOT_SIGNATURE  ; (read) 0xaa55 magic number.
		__ukh_assert_fofs 0x200

setup_sector:  ; 2 == (.boot_sector.setup_sects) sectors of 0x800 bytes. Loaded to 0x800 bytes to 0x90200. Jumped to `jmp 0x9020:0' in real mode for the Linux boot protocools.
.start:		__ukh_assert_fofs 0x200
.jump:		jmp short .setup_linux  ; (read) Jump instruction. Entry point.
		__ukh_assert_fofs 0x202
.header:	db 'HdrS'  ; (read) Protocol >=2.00 signature. Magic signature “HdrS”.
		__ukh_assert_fofs 0x206
.version:	dw OUR_LINUX_BOOT_PROTOCOL_VERSION  ; (read) Linux kernel protocol version supported. 0x201 is the last one which loads everything under 0xa0000.
		__ukh_assert_fofs 0x208
.realmode_swtch: dd 0  ; (read, modify optional) Bootloader hook.
		__ukh_assert_fofs 0x20c
.start_sys_seg: dw KERNELSEG  ; (read) The load-low segment (0x1000), i.e. linear address >> 4 (obsolete). Ignored by both GRUB 1 0.97 and QEMU 2.11.1. In Linux kernel mode, they don't set root= either, and they don't pass the boot drive (boot_drive, saved_drive, current_drive, is saved_drive the result of `rootnoverify'?) number anywhere. Also GRUB 1 0.97 passes the boot drive in DL in `chainloader' (stage1) mode only.
		__ukh_assert_fofs 0x20e
.kernel_version: dw .kernel_version_string-setup_sector  ; (read) Pointer to kernel version string or 0 to indicate no version. Relative to setup_sector.
		__ukh_assert_fofs 0x210
.type_of_loader: db 0  ; (write obligatory) Bootloader identifier.
		__ukh_assert_fofs 0x211
.loadflags:	db 0  ; Linux kernel protocol option flags. Not specifying LOADFLAG.HIGH, so the the protected-mode code is will be loaded at 0x10000 (== .start_sys_seg<<4 == KERNELSEG<<4).
		__ukh_assert_fofs 0x212
.setup_move_size: dw 0  ; (modify obligatory) Move to high memory size (used with hooks). When using protocol 2.00 or 2.01, if the real mode kernel is not loaded at 0x90000, it gets moved there later in the loading sequence. Fill in this field if you want additional data (such as the kernel command line) moved in addition to the real-mode kernel itself.
		__ukh_assert_fofs 0x214
.code32_start:	dd 0  ; (modify, optional reloc) Bootloader hook. Unused.
		__ukh_assert_fofs 0x218
.ramdisk_image: dd 0  ; initrd load address (set by bootloader). 0 (NULL) if no initrd.
		__ukh_assert_fofs 0x21c
.ramdisk_size: dd 0  ; initrd size (set by bootloader). 0 if no initrd.
		__ukh_assert_fofs 0x220
.bootsect_kludge: dd 0  ; (kernel internal) DO NOT USE - for bootsect.S use only.
		__ukh_assert_fofs 0x224
.heap_end_ptr:	dw 0  ; (write obligatory) Free memory after setup end.
		__ukh_assert_fofs 0x226
.linux_boot_header.end:

.setup_chain:
bits 16
		add word [cs:.jmp_offset-setup_sector], byte chain_entry-linux_entry  ; Change the protected mode entry point from linux_entry to chain_entry.
		jmp short .setup_linux_and_chain

		times 0x30-($-.start) db 0  ; QEMU 2.11.1 `qemu-system-i386-kernel' overwrites some bytes within the .linux_boot_header. Offset 0x30 seems to be the minimum bytes left intact.

; API function ukh_protected_mode_far. Call it from real mode at 0x9000:0x230.
.protected_mode_far:  ; Enters zero-based (flat) 32-bit protected mode. Must be called as a far call (with CS pointing to INITSEG) from real mode. SS must be 0, high 16 bits of ESP must be 0. Disables interrupts (cli). Keeps all general-purpose registers intact. Ruins EFLAGS.
		jmp short .protected_mode_far_low

cpu 386
bits 32

; API function ukh_real_mode. Call it from 32-bit protected mode at 0x90232.
		__ukh_assert_at boot_sector+0x232  ; Address part of the API.
.real_mode:  ; Enters (16-bit) real mode. Must be called as a near call from zero-based (flat) 32-bit protected mode. High 16 bits of ESP must be 0. EIP must be less than 1 MiB. Protected-mode CS will be EIP>>16<<12. Sets DS, ES, FS, GS to KERNELSEG, and SS to 0. Doesn't enable (sti) or disable (cli) interrupts. The caller may enable interrupts after the call. Keeps all general-purpose registers intact. Ruins EFLAGS.
		xchg eax, [esp]
		rol eax, 16
		shl ax, 12
		rol eax, 16
		xchg eax, [esp]  ; Converted linear address in EAX to real-mode segment:offset. Offset in AX is unchanged, segment is (orig_EAX&0xf0000)<<12.
		; Fall through to ukh_real_mode_far.
; API function ukh_real_mode_far. Push return segment:offset, and jump here from 32-bit protected mode at 0x90242.
.real_mode_far:
		__ukh_assert_at boot_sector+0x242  ; Address part of the API.
		push eax  ; Save.
		mov ax, ..@BACK16_DS
		; We must use a far jump with a 16-bit offset here (to jump to a 16-bit protected code segment), because with a 32-bit offset it doesn't work in
		; 86Box-4.2.1, Intel 430VX chipset, Pentium-S P54C 90 MHz CPU. (Both work in QEMU 2.11.1, VirtualBox and https://copy.sh/v86).
		;jmp ..@BACK16_CS:.real1-boot_sector  ; This would be a far jump with a 32-bit offset. It doesn't work in 86Box.
		dw 0xea66, boot_sector.real1-boot_sector, ..@BACK16_CS  ; This is a far jump with a 16-bit offset. It woks in 86Box, and it's 1 byte shorter.

.setup_linux:  ; The 16-bit Linux entry point jumps here from setup_sector.start, as jmp INITSEG+0x20:0.
bits 16
%if 0  ; For debugging.
		mov ax, 0xe00+'S'
		xor bx, bx
		int 0x10  ; Print character in AL.
%endif
.setup_linux_and_chain:
		cli  ; No interrupts allowed. The Linux bootloader usually provides a valid stack, but we don't rely on it.
		xor ax, ax
		mov ss, ax
		mov esp, 0xfffc  ; Aligned to 4. It's simpler to convert if we keep ESP 16-bit only (i.e. we never put 0x10000 to it). !! Maybe we can still do it if we pop early in .protected_mode_far.

%if 1  ; !! What's wroong if we don't bother with NMI?
		; now we want to move to protected mode ... !! Consider alternatives, such as how SYSLINUX 4.07 does it or how GRUB 1 0.97 does it.
		mov al, 0x80  ; disable NMI for the bootup sequence !! Why is this needed? https://wiki.osdev.org/Protected_Mode
		out 0x70, al
%endif
		mov al, 1  ; A20 gate direction: enable.
		push cs  ; Simulate far call.
		call .a20_gate_far_low  ; Enable the A20 gate. We must do this in real mode mode.

		push cs  ; Simulate far call.
		push strict word linux_entry-setup_sector  ; Self-modifying code may change the offset here from chain_entry to linux_entry, using .jmp_offset.
.jmp_offset: equ $-2
		; When switching back real mode, we want the original IDT, not an empty one like this. GRUB 1 0.97 doesn't set it. QEMU Linux boot and Multiboot v1 boot don't set it. https://stackoverflow.com/q/79526862 ; https://stackoverflow.com/a/5128933 .
		;lidt [cs:idtr-setup_sector]
		lgdt [cs:gdtr-setup_sector]
		;jmp short .protected_mode_far_low  ; Fall through.
.protected_mode_far_low:
		cli
		push eax  ; Save.
		mov eax, cr0  ; !! Save registers.
		or al, 1  ; PE := 1.
		mov cr0, eax
		mov ax, ..@KERNEL_DS
		jmp ..@KERNEL_CS:dword ((INITSEG<<4)+.prot_ret-boot_sector)  ; This is 8 bytes, without dword it jumps incorrectly. Jumps to .prot_ret (right below), activates protected mode.
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
.a20_gate_far_low:
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
  multiboot_entry:  ; Loaded to OUR_MULTIBOOT_LOAD_ADDR by the bootloader, interrupts disabled, no stack (ESP is invalid). Works according to the Multiboot v1 specification: https://www.gnu.org/software/grub/manual/multiboot/multiboot.html
		;cli  ; Not needed, https://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Machine-state mandates it.
		cld
		;cmp eax, 0x2badb002  ; We ignore this Multiboot signature.
		;xchg ebp, eax  ; EBP := multiboot signature; EAX := junk.
		mov esi, OUR_MULTIBOOT_LOAD_ADDR
		test byte [ebx], MULTIBOOT_INFO_BOOTDEV
		jz short .boot_drive_done
		mov al, [ebx+3*4+3]  ; Boot drive number in multiboot_info.boot_device.
		mov [esi+boot_sector.drive_number-boot_sector], al  ; Save BIOD drive number to its final UKH boot protocol location.
  .boot_drive_done:

		; Copy the first 2 sectors to INITSEG.
		mov edi, INITSEG<<4
		mov ecx, BXS_SIZE>>2
		rep movsd

		lgdt [byte edi-BXS_SIZE+gdtr-boot_sector]  ; Make subsequent API call ukh_real_mode work. We don't need to reload the CS, DS etc. just yet.

  .cmdline:	;xor ecx, ecx  ; Empty command line by default. No need to set it, ECX is already 0.
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
		mov eax, (0xa000-1)|UKH_KERNEL_CMDLINE_MAGIC_VALUE<<16
		sub eax, ecx
		ror eax, 16  ; Swap low and high words.
		mov [(INITSEG<<4)+boot_sector.cl_magic-boot_sector.start], eax  ; Also sets boot_sector.cl_offset.
		rep movsb
		xor eax, eax
		stosb  ; Add terminating NUL.

		; Copy code32 to KERNELSEG<<4. We must copy late, because earlier we'd overwrite the command line by GRUB 1 0.97 (but not by GRUB4DOS 0.4.4).
		mov esi, OUR_MULTIBOOT_LOAD_ADDR+BXS_SIZE
		mov edi, KERNELSEG<<4
		mov ecx, (code32.end-code32+3)>>2
		rep movsd

		jmp short start_32
%endif

linux_entry:  ; Setup registers and jump to kernel. We assume that already IF=0 (cli) and DF=0 (cld).
		; Move code at KERNELSEG<<4 forward by 3 sectors. Copy the data backward (descending), because the destination comes after the source, and they may overlap.
		std
		mov esi, (KERNELSEG<<4)+((code32.padded_end-code32-1-3*0x200)&~3)
		mov edi, (KERNELSEG<<4)+((code32.padded_end-code32-1-3*0x200)&~3)+(3*0x200)
		mov ecx, (code32.padded_end-code32+3-3*0x200)>>2
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
		; EBX is still set to the address of the multiboot_info struct set up by the bootloader. https://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Boot-information-format
		mov esp, KERNELSEG<<4  ; A useful value. The Multiboot v1 specification allows any (nonworking) value in ESP. We will subtract 4 so that it won't be truncated when we use only the low 16 bits in real mode (SP).
		push esp
		sub eax, eax  ; In EFLAGS, set OF=0, SF=0, ZF=1, AF=0, PF=1 and CF=0 according to the result.
		times 8 push eax
		popa  ; Set EAX, EBX, ECX, EDX, ESI, EDI and EBP to 0 (but not ESP). We do it for reproducibility.
		jmp dword [esp]  ; This works even if non-Multiboot code jumps into .setup_regs_and_jump_to_kernel.
bits 16
cpu 8086

; These data bytes have to be valid only for the duration of the lgdt or
; lidt instruction. The table entries have to remain valid until the next
; lgdt or lidt instruction (i.e. long).
;
; We put this very late in setup_sector, for the size saving in multiboot_entry.
gdtr:		dw boot_sector.gdt_end-boot_sector.gdt-1  ; gdt limit
		dd (INITSEG<<4)+boot_sector.gdt-boot_sector  ; gdt base = 0X9xxxx

%ifdef UKH_MULTIBOOT
		times BXS_SIZE-OUR_MULTIBOOT_HEADER_SIZE-($-boot_sector) db '-'
		__ukh_assert_fofs BXS_SIZE-OUR_MULTIBOOT_HEADER_SIZE
  multiboot:  ; Multiboot v1 header, 0x20 bytes. i386 is hardcoded.
  .multiboot.align_check: times -(($-boot_sector.start)&3) nop  ; Check alignment of the .multiboot_v1 below, in case the bootloader checks only aligned locations.
  .multiboot.magic: dd MULTIBOOT_MAGIC
  .multiboot.flags: dd OUR_MULTIBOOT_FLAGS
  .multiboot.checksum: dd -MULTIBOOT_MAGIC-OUR_MULTIBOOT_FLAGS
  .multiboot.header_addr: dd OUR_MULTIBOOT_LOAD_ADDR+(multiboot-boot_sector)  ; This is smaller than OUR_MULTIBOOT_LOAD_ADDR. It would be ERR_EXEC_FORMAT if .multiboot.magic came before .multiboot.load_addr.
  .multiboot.load_addr: dd OUR_MULTIBOOT_LOAD_ADDR  ; Linear address. ERR_BELOW_1MB for KERNELSEG<<4, thus we use OUR_MULTIBOOT_LOAD_ADDR and multiboot_copy_code32 instead.
  .multiboot.load_end_addr: dd OUR_MULTIBOOT_LOAD_ADDR+(code32.end-boot_sector)
  .multiboot.bss_end_addr:  dd OUR_MULTIBOOT_LOAD_ADDR+(code32.end-boot_sector)  ; No specific .bss to be cleared by the bootloader.
  .multiboot.entry_addr: dd OUR_MULTIBOOT_LOAD_ADDR+(multiboot_entry-boot_sector)
  .multiboot.end:
  .multiboot.size_check: __ukh_assert_at multiboot+0x20
%else
		times BXS_SIZE-($-boot_sector) db '-'
%endif
		__ukh_assert_fofs BXS_SIZE

; --- !! API

;UKH_KERNEL_CMDLINE_MAGIC_VALUE equ 0xa33f  ; Defined above.

ukh_drive_number_flat    equ 0x90007  ; Example usage: `mov dl, [ukh_drive_mumber_flat]'. It works with any org. Only valid in protected mode.
ukh_real_mode_flat       equ 0x90232  ; As `call ...', this only works with `org (KERNELSEG<<4)-BXS_SIZE'. As `push ... ++ ret', it works with any org. Only valid in protected mode.
ukh_real_mode_far        equ 0x90242  ; Don't `call ...', but push return segment:offset, and jump here from 32-bit protected mode at 0x90242.
ukh_kernel_cmdline_magic equ 0x90020  ; If word [ukh_kernel_cmdline_magic] == UKH_KERNEL_CMDLINE_MAGIC_VALUE (== 0xa33f) in protected mode, then ...
ukh_kernel_cmdline_ptr   equ 0x90022  ; ... the kernel command-line string is available as a NUL-terminated byte string starting at linear address dword [ukh_kernel_cmdline_ptr] in protected mode.

; See ukh_real_mode below.
; See ukh_protected_mode below.
; See ukh_a20_gate_al below.
; See ukh_halt defined above.

bits 16
%ifdef UKH_PAYLOAD_32  ; i386+ 32-bit protected-mode payload.
  cpu 386
  %define UKH_BITS 32
  %macro ukh_real_mode 0
    %if UKH_BITS==32
      ;call setup_sector.real_mode+(INITSEG<<4)-(KERNELSEG<<4)+BXS_SIZE  ; ukh_real_mode_flat.
      ;call $$+0x90232-(KERNELSEG<<4)+BXS_SIZE  ; ukh_real_mode_flat. Works independently of `org'.
      call ukh_real_mode_flat  ; This only works with `org (KERNELSEG<<4)-BXS_SIZE'.
      %define UKH_BITS 16
      bits 16
    %else
      %error ERROR_MUST_BE_IN_PROTECTED_MODE
      times -1 nop
    %endif
  %endm
  %macro ukh_protected_mode 0
    %if UKH_BITS==16
      ;call INITSEG:0x230  ; ukh_protected_mode_far.
      call 0x9000:0x230  ; ukh_protected_mode_far.
      %define UKH_BITS 32
      bits 32
    %else
      %error ERROR_MUST_BE_IN_REAL_MODE
      times -1 nop
    %endif
  %endm
  %macro ukh_a20_gate_al 1  ; Enables (AL == 1) or disables (AL == 0) the A20 gate. We must do this in 16-bit mode, with interrupts disabled. Ruins AL.
    %if UKH_BITS==16
      mov al, %1  ; A20 gate direction.
      ;call INITSEG:4  ; ukh_a20_gate_far.
      call 0x9000:4  ; ukh_a20_gate_far.
    %else
      %error ERROR_MUST_BE_IN_REAL_MODE
      times -1 nop
    %endif
  %endm
%elifdef UKH_PAYLOAD_16
  cpu 8086
  %define UKH_BITS 16
%endif
bits UKH_BITS

%macro ukh_end 0
  code32.end:
  %if $-boot_sector<0xa00  ; File size must be at least 5 sectors (0xa00 == 2560 bytes) for the old Linux load protocol.
    times 0xa00-($-boot_sector) db 0
  %endif
  code32.padded_end:  ; Use size based on this for some short copies.
%endm

; --- Now the comes the payload, at file offset 0x400.
;
; * The payload will be loaded to (KERNELSEG<<4) == 0x10000.
; * Maximum payload size: 512 KiB, but the bootloader may restrict it further.
;

code32:  ; !!! Rename it to ukh_payload.

%ifdef __UKH_PAYLOAD_FILE
  incbin __UKH_PAYLOAD_FILE, UKH_PAYLOAD_FILE_SKIP
  ukh_end
%endif
