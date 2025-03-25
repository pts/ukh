;
; grub1.nasm: UKH payload for GRUB 1 0.97 stage2
; by pts@fazekas.hu at Mon Mar 24 23:59:32 CET 2025
;
; Compile with: nasm-0.98.39 -O0 -w+orphan-labels -f bin -DSTAGE2_IN="'ubuntu-16.04-grub-0.97-29ubuntu68-stage2'" -DGRUB1 -o grub1.multiboot.bin grub1.nasm
; Run it with: qemu-system-i386 -M pc-1.0 -m 2 -nodefault -vga cirrus -kernel grub1.multiboot.bin
;
; The GRUB 1 stage1 binary is 512 bytes, it can be written to a floppy boot sector
; or HDD MBR sector. It leaves room for the BPB and the partition table.
;
; The stage2 binary starts with:
;
; * The first sector (512 bytes at offset 0, source in stage2/start.S),
;   loaded by stage1 to 0:0x8000 (also jumped there) loads to rest of the
;   stage2 binary to 0:0x8200. (It is smart enough to increase the segment
;   before the offset would reach 64 KiB.) It sets EBP to the LBA sector
;   number where it read the next sector from. Then it jumps to 0:0x8200.
; * The next sector (512 bytes at offset 0x200, source in stage2/asm.S),
;   loaded by the first sector of stage2 to 0:0x8200 (also jumped there):
;   ```
;   .jump: jmp 0:0x8200+.code-jump  ; File offset 0x200. Jumps to 0:0x8270. This is to make every segment-offset combination work, and to skip over the header.
;   .padding: db 0
;   .compat_version_major: db 3
;   .compat_version_minor: db 2
;   .install_partition: dd 0xffffff
;   .saved_entryno: dd 0  ; This variable is here only because of a historical reason.
;   .stage2_id: db 0  ; STAGE2_ID_STAGE2.
;   .force_lba: db 0
;   .version_string) db '0.97', 0  ; Always 5 bytes.
;   .config_file: db '/boot/grub/menu.lst', 0  ; File offset 0x217.
;   .config_file_padding: times 0x70-($-.jump)  ; Leave some room for .config_file.
;   .code:  ; File offset 0x270.
;   codestart:
;   bits 16
;   cli
;   xor ax, ax
;   mov ds, ax
;   mov ss, ax
;   mov es, ax
;   mov [dword 0x90e0], ebp  ; Save the sector number of the second sector (i.e. this sector) to the variable install_second_sector. This variable seems to be unused later.
;   mov ebp, 0x1ff0  ; EBP := STACKOFF.
;   mov esp, ebp
;   sti
;   mov [dword 0x90dc], dl  ; Save DL to the variable boot_drive.
;   int 0x13  ; BIOS reset disk system.
;   ```
;
; Mapping between GRUB devices (e.g. `(fd0)`) and BIOS drive numbers (GRUB
; boot_drive, saved_drive, current_drive).
;
; * Floppy `(fd0)` is 0, `(fd1)` is 1 etc.
; * HDD (hard disk) `(hd0)` is 0x80, `(hd1)` is 0x81 etc.
;
; Mapping between partition numbers and GRUB partition numbers
; (install_partition, saved_partition, current_partition):
;
; * https://www.gnu.org/software/grub/manual/legacy/Naming-convention.html
; * No partition (e.g. for a floppy `(fd0)`) is 0xffffff.
; * Primary partition 1 (e.g. Linux `/dev/sd?1`, GRUB `(hd?,0)`) is 0x0ffff.
; * Primary partition 2 (e.g. Linux `/dev/sd?2`, GRUB `(hd?,1)`) is 0x1ffff.
; * Primary partition 3 (e.g. Linux `/dev/sd?3`, GRUB `(hd?,2)`) is 0x2ffff.
; * Primary partition 4 (e.g. Linux `/dev/sd?4`, GRUB `(hd?,3)`) is 0x3ffff.
; * Logical partition 5 (e.g. Linux `/dev/sd?5`, GRUB `(hd?,4)`) is 0x4ffff.
;

%define UKH_PAYLOAD_32
%define UKH_VERSION_STRING 'grub1-0.97-ubuntu'
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

%ifndef STAGE2_IN
  %define STAGE2_IN 'ubuntu-16.04-grub-0.97-29ubuntu68-stage2'
%endif

kernel:		jmp strict short .code
		times 3 nop
		assert_at kernel+5
		incbin STAGE2_IN, 0x200+5, 8-5
.install_partition: dd 0xffffff
		incbin STAGE2_IN, 0x200+0xc, 0x70-0xc  ; Header.
		assert_at kernel+0x70
.code:		or ebp, byte -1  ; Make sure install_second_sector is invalid.
		mov dl, [ukh_drive_number_flat]  ; BIOS drive number set up by UKH.
		test dl, dl
		jns .after_partition  ; For floppy, keep the install_partition == 0xffffff default.
		; TODO(pts): Set it to the first active partition, or leave it if no partition table (Liigboot).
		mov byte [.install_partition+2], 0   ; Set install_partition to (hd?,0), assuming the previous value was 0xffffff.
.after_partition:
		mov esp, 0x8200  ; Set up a low enough stack which won't be clobbered by the copies below.
		push 0x8270  ; Return address of ukh_real_mode_flat, GRUB 1 codestart entry point, as far segment:offset (0:0x8270).
		push ukh_real_mode_flat  ; Address of ukh_real_mode_flat.
		db 0x68  ; i386 opcode for `push strict dword, ...'.
		    rep movsd  ; Do the big copy.
		    pop eax  ; Pop this 4 bytes of code from the stack. This is safe because interrupts are disabled.
		    ret  ; Return to ukh_real_mode_flat.
		mov esi, kernel
		mov edi, 0x8200
		mov ecx, 0x70>>2
		rep movsd
		add esi, byte .grub1_codestart-(kernel+0x70) ; mov esi, .grub1_codestart.
		;mov edi, 0x8270  ; Already set. We assume .grub1_codestart+0x70 >= 0x8200, so we copy forward. !! Reuse EDI for pushing above.
		mov ecx, (.grub1_end-.grub1_codestart+3)>>2
		;rep movsd  ; Will do it later, as part of the big copy.
%if 0  ; For debugging.
		ukh_real_mode
		mov ax, 0xe00|'G'
		xor bx, bx  ; Set up printing.
		int 0x10  ; Print character in AL.
		int 0x19  ; Reboot. Doesn't return.
		ukh_protected_mode
%endif
		; Pass DL (BIOS drive number, will become boot_drive) and EBP (install_second_sector) to GRUB 1 stage2/asm.S codestart.
		jmp esp  ; Jumps to the big copy (`rep movsd'), does the copy, returns to ukh_real_mode_flat, returns to the GRUB 1 codestart entry point (0:0x8270).

		times (kernel-$)&3 hlt  ; Align to a multiple of 4, for faster copy.
.grub1_codestart:
%if .grub1_codestart-(kernel+0x70)>0x7f
  %error ERROR_GLUE_CODE_TOO_LONG  ; Breaks the `add esi, byte ...' above.
%endif
		incbin STAGE2_IN, 0x270
.grub1_end:

ukh_end
