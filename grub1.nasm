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
; * The sector sector (512 bytes at offset 0x200, source in stage2/asm.S),
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
; * Some other GRUB1 stage2 files (especially of PXE NBP == SYSLINUX boot
;   .bs format) have more than 1 sector before the second sector.
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
%ifdef GRUB1
  %define UKH_VERSION_STRING 'grub1-0.97-ubuntu'
  %define INCBIN_BASE 0x200
  %ifndef STAGE2_IN
    %define STAGE2_IN 'ubuntu-16.04-grub-0.97-29ubuntu68-stage2'
  %endif
%endif
%ifdef GRUB4DOS0_4_4
  %define UKH_VERSION_STRING 'grub4dos-0.4.4pts'
  %define INCBIN_BASE 0x600
  %ifndef STAGE2_IN
    %define STAGE2_IN 'grub4dos.uncompressed.bs'
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


kernel:
.header:  ; GRUB 1 stage2 header. This is between file offsets 0x200..0x270 in the stage2 file. We have it between 0x400..0x470.
		jmp strict short .code
		times 3 nop
		assert_at .header+5
		incbin STAGE2_IN, INCBIN_BASE+5, 8-5
.install_partition: dd 0xfeffff  ; The 0xfe indicates an invalid partition value which causes the GRUB 1 error: `Error 22: No such partition'.
		incbin STAGE2_IN, INCBIN_BASE+0xc, 0x17-0xc  ; Header.
.config_file:	db '/menu.lst', 0  ; Override '/boot/grub/menu.lst', 0.
		times 0x70-($-kernel) db 0
		assert_at .header+0x70  ; End of GRUB 1 header.
.code:		mov dl, [ukh_drive_number_flat]  ; BIOS drive number set up by UKH.
		test dl, dl
		jns short .use_entire_disk_no_partition  ; For floppy.
		cmp dl, 0xff
		je short .partition_error  ; The boot drive is unknown.
		; Now read the MBR from the HDD with drive number DL, detect and use the first active partition.
		mov ebx, 0x7e00  ; Read address of the MBR.
		ukh_real_mode
		xor ax, ax
		mov es, ax  ; ES := 0. Will read to ES:BX.
		mov ax, 0x201  ; Read 1 sector (0x200 bytes).
		mov cx, 1  ; Cylinder 0, sector 1.
		mov dh, 0  ; Head 0.
		int 0x13  ; BIOS disk syscall.
		sbb ax, ax  ; AX := -CF.
		ukh_protected_mode  ; Ruins flags (such as CF), that's why we've saved CF to AL.
		test al, al
		jnz short .partition_error  ; HDD read error.
		cmp dword [ebx+7], 'BOOT'  ; Liigboot (https://github.com/pts/liigboot) MBR indicating that the entire HDD should be used as a filesystem.
		je short .use_entire_disk_no_partition  ; Use the entire HDD as a filesystem.
		add bx, 0x1be  ; Partition 1 ((hdD,0)) entry in https://en.wikipedia.org/wiki/Master_boot_record#Sector_layout
		cmp [ebx-2], ax  ; Is reserved_word_0 == 0?
		jne short .use_entire_disk_no_partition  ; Partition table not recognized.
		cmp word [ebx+0x200-2-0x1be], 0xaa55  ; Is the boot signature correct?
		jne short .use_entire_disk_no_partition  ; Boot signature not recognized.
.try_next_partition:  ; Try next partition entry starting at EBX. https://en.wikipedia.org/wiki/Master_boot_record#Partition_table_entries
		cmp byte [ebx], 0x85  ;  Is the partition active? TODO(pts): Should we only check the high bit?
		je short .found_partition
		inc eax  ; Increment partition number.
		add ebx, byte 0x10  ; Size of a partition entry.
		cmp bl, 0xfe
		je short .partition_error  ; All partitions processed, no active partition found.
		jmp short .try_next_partition
.partition_error:
		db 0xb8, 0xfe, 0  ; `mov eax, 0x????00fe', effectively AL := 0xfe, fall through to the next instruction.
.use_entire_disk_no_partition:
		mov al, 0xff  ; Must be exactly 2 bytes, for .partition_error.
.found_partition:
		mov esp, 0x8200  ; Set up a low enough stack which won't be clobbered by the copies below.
		push 0x8270  ; Return address of ukh_real_mode_flat, GRUB 1 codestart entry point, as far segment:offset (0:0x8270).
		push ukh_real_mode_flat  ; Address of ukh_real_mode_flat.
		db 0x68  ; i386 opcode for `push strict dword, ...'.
		    rep movsd  ; Do the big copy.
		    pop eax  ; Pop this 4 bytes of code from the stack. This is safe because interrupts are disabled.
		    ret  ; Return to ukh_real_mode_flat.
		mov esi, kernel
		mov byte [esi+.install_partition+2-kernel], al   ; Set install_partition to (hdD,P), where P is AL (0, 1, 2 or 3), assuming the previous value was 0xffffff.
		mov edi, 0x8200
		mov ecx, 0x70>>2
		rep movsd
		;add esi, byte .grub1_codestart-(kernel+0x70)
		;mov esi, .grub1_codestart
		mov si, .grub1_codestart  ; 1 byte shorter.
		;mov edi, 0x8270  ; Already set. We assume .grub1_codestart+0x70 >= 0x8200, so we copy forward.
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
		or ebp, byte -1  ; Make sure install_second_sector is invalid for GRUB 1 0.97 stage2/asm.S.
		; Pass DL (BIOS drive number, will become boot_drive) and EBP (install_second_sector) to GRUB 1 stage2/asm.S codestart.
		jmp esp  ; Jumps to the big copy (`rep movsd'), does the copy, returns to ukh_real_mode_flat, returns to the GRUB 1 codestart entry point (0:0x8270).

		times (kernel-$)&3 hlt  ; Align to a multiple of 4, for faster copy.
.grub1_codestart:
%if 0  ; !!
  %if .grub1_codestart-(kernel+0x70)>0x7f
    %error ERROR_GLUE_CODE_TOO_LONG  ; Breaks the `add esi, byte ...' above.
    times -1 nop
  %endif
%else
  %if .grub1_codestart-kernel>0xffff
    %error ERROR_GLUE_CODE2_TOO_LONG  ; Breaks the `mov si, ...' above.
    times -1 nop
  %endif
%endif
		incbin STAGE2_IN, INCBIN_BASE+0x70
.grub1_end:

ukh_end
