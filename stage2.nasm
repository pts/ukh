;
; stage2.nasm: bs (PXE) header for GRUB 1 0.97 stage2
; by pts@fazekas.hu at Thu Mar 20 03:35:23 CET 2025
;
; Compile with: nasm-0.98.39 -O0 -w+orphan-labels -f bin -DSTAGE2_IN="'ubuntu-16.04-grub-0.97-29ubuntu68-stage2'" -o grub1.bs stage2.nasm
; !! incorrect: Run it with: qemu-system-i386 -M pc-1.0 -m 4 -nodefault -vga cirrus -kernel memtest86+.kernel.bin
;

bits 16
cpu 8086

BOOT_SIGNATURE equ 0xaa55

%ifndef STAGE2_IN
  %define STAGE2_IN 'stage2'  ; Input filename.
%endif

bs_boot_sector:  ; The bootloader loads the file to 0:0x7c00 and jumps to 0:0x7c00.
.start:
		jmp near stage2
		times 0x200-2-($-.start) db 0
		dw BOOT_SIGNATURE  ; To make GRUB the chainloader command work without --force.
		times 0x8200-0x7c00-($-.start) db 0  ; Entry point of GRUB 1 stage2 is 0:0x8200 (the segment-offset split doesn't mater).

stage2:		incbin STAGE2_IN, 0x200
