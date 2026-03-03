;
; syslinux4.nasm: UKH payload for SYSLINUX 4
; by pts@fazekas.hu at Tue Mar 25 06:01:31 CET 2025
;
; Compile with: nasm-0.98.39 -O0 -w+orphan-labels -f bin -DLDLINUX_RAW_IN="'ldlinux.raw'" -o syslinux4.multiboot.bin syslinux4.nasm
; !! To run it, create a FAT filesystem on floppy, create syslinux.cfg, and boot the kernel.
;
; This works with the Liigboot variant (https://github.com/pts/liigboot).
;
; !!! This needs fixing for the floppy.
; mov si, 255  ; Fake value for [bsHeads], unused with LBA, EDD (EBIOS).
; mov di, 63   ; Fake value for [bsSecPerTrack], unused with LBA, EDD (EBIOS).
;
; Format of ldlinux.raw:
;
; ```
; initial_padding: times 0x8000 db 0  ; @0
; ; syslinux/core/diskstart.inc starts here
; ADVSec0: dd 0  ; @0x8000
; ADVSec1: dd 0  ; @0x8004
; MaxTransfer: dw 127  ; @0x8008 Max sectors to transfer. Will be used in fs_init(...) and everywhere.
; dw 0  ; @0x0x800a
; syslinux_banner: db 13, 10  ; @0x800c
; late_banner: db 13, 'Liigboot 0x5a2af109', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ; @0xe 13, 'Liigboot ', DATE_STR, 0
; _start: ; @0x802c
; upxbc_flat16_compression_signature: db 0xeb, '"SBAFEUU_COMPRESSION_AFTER_SLASH__/' ; @0x802c. The liigmain.bin upxbc --flat16 compression signature, Harmless code (jumps over itself).
; jump_to_all_read: jmp near all_read  ; @0x8050.
; writestr_early: ... ; @0x8052.
; all_read:  ; @0x80f8.
; xor ax, ax
; mov es, ax  ; We enter here with ES scrambled...
;

%define UKH_PAYLOAD_32
%if 1
  %define UKH_VERSION_STRING 'syslinux-4.07-liigboot'
  %define INCBIN_BASE 0x8000  ; Data starts at +8, code and entry point starts at +0x2c.
  %ifndef LDLINUX_RAW_IN
    %define LDLINUX_RAW_IN 'ldlinux.raw'
  %endif
%endif

;%define UKH_MULTIBOOT  ; Enabled by default.
%include 'ukh.nasm'

%macro assert_fofs 1
  times +(%1)-($-$$) times 0 nop
  times -(%1)+($-$$) times 0 nop
%endm
%macro assert_at 1
  times +(%1)-$ times 0 nop
  times -(%1)+$ times 0 nop
%endm


kernel:		;jmp strict short .code
.code:		;cli  ; Already set.
		;cld  ; Already set.
		xor eax, eax
		;mov ss, ax  ; Don't set this in protected mode. The UMF will do it when switching back to real mode.
		mov esp, 0x7b78  ; Set up a low enough stack which won't be clobbered by the copies below.
		;sti  ; Too early, we are still in protected mode.
		xor edx, edx
		mov dl, [ukh_drive_number32]  ; BIOS drive number set up by UKH.
		;mov dl, 0  ; !!! Why isn't the correct drive 0 propagated from GRUB4DOS with `root (fd0)'? for Multiboot, is the root always the `kernel ...' drive? Yes, but for `chainloader' it is respected.
		; We have to push 12 items for the SYSLINUX .raw_entry.
		push edx  ; Save drive number, goes to 0x7b74.
		;push es  ; Save ES:DI ($PnP), goes to 0x7b72.
		;push di  ; Goes to 0x7b70.
		push eax  ; Save ES:DI ($PnP), goes to 0x7b70.
		;push ds  ; Save DS:SI (partinfo), goes to 0x7b6e.
		;push si  ; Goes to 0x7b6c.
		push eax  ; Save DS:SI (partinfo), goes to 0x7b6c.
		push eax  ; Just copy 0. Part of OrigFDCTabPtr, goes to 0x7b68.
		push eax  ; Should be 0. Part of Hidden, goes to 0x7b64. !! Get the partition start.
		push eax  ; Should be 0. Part of Hidden, goes to 0x7b60.
		; Hidden == 0x7b60  (dq)
		; OrigFDCTabPtr == 0x7b68 (dd)
		; OrigDSSI == partinfo == 0x7b6c (dd)
		; OrigESDI == $PNP == 0x7b70 (dd)
		; DriveNumber == 0x7b74 (dw)
		; StackBuf == 0x7b78
		; PartInfo == 0x7b78  (76 bytes)
		;   PartInfo.mbr == 0x7b78
		;   PartInfo.gptlen == 0x7b88
		;   PartInfo.gpt == 0x7b8c
		; FloppyTable == 0x7bc4  (16 bytes)
		; STACK_TOP == 0x7c00

		push 0x80f8  ; Return address of ukh_real_mode_jmp32, SYSLINUX entry point, as far segment:offset (0:0x80f8).
		push ukh_real_mode_jmp32  ; Address of ukh_real_mode_jmp32.
		db 0x68  ; i386 opcode for `push strict dword, ...'.
		    rep movsd  ; Do the big copy.
		    pop ebx  ; Pop this 4 bytes of code from the stack. This is safe because interrupts are disabled. Destination is ruined, value doesn't matter.
		    ret  ; Return to ukh_real_mode_jmp32.
		mov esi, .syslinux4_sys
		mov edi, 0x8000
		mov ecx, (.syslinux4_end-.syslinux4_sys+3)>>2
		;rep movsd  ; Will do it later, as part of the big copy.
%if 0  ; For debugging.
		xor eax, eax
		ukh_real_mode  ; !! BUG: changes the value of EAX.
		test eax, eax
		jz short .eax_ok
		mov ax, 0xe00|'S'
		xor bx, bx  ; Set up printing.
		int 0x10  ; Print character in AL.
		int 0x19  ; Reboot. Doesn't return.
.eax_ok:	ukh_protected_mode
%endif
		xor eax, eax  ; Will be used by `mov ds, ax' below. !! Is this needed by syslinux4? Or is it a leftover  from GRUB 1?
		jmp esp  ; Jumps to the big copy (`rep movsd'), does the copy, returns to ukh_real_mode_jmp32, returns to the SYSLINUX entry point (0:0x80f8).

		times (kernel-$)&3 hlt  ; Align to a multiple of 4, for faster copy.
.syslinux4_sys:
		incbin LDLINUX_RAW_IN, INCBIN_BASE, 0xf8
		;incbin LDLINUX_RAW_IN, INCBIN_BASE, 0x63
		;cli  ; !!! Why doesn't this print anything.
		;hlt
		;incbin LDLINUX_RAW_IN, INCBIN_BASE+0x65, 0xf8-0x65
bits 16
		mov ds, ax  ; DS := 0. !! Also where do we do: sti. !! Also fro GRUB.
		incbin LDLINUX_RAW_IN, INCBIN_BASE+0xfa
.syslinux4_end:

; !! g `kernel /' produces a disk read error now. When was this introduced?  This is normal, partition 1 is forced.

ukh_end
