;
; grub1_bs.nasm: bs (PXE) header for GRUB 1 0.97 stage2
; by pts@fazekas.hu at Thu Mar 20 03:35:23 CET 2025
;
; Compile with: nasm-0.98.39 -O0 -w+orphan-labels -f bin -DSTAGE2_IN="'ubuntu-16.04-grub-0.97-29ubuntu68-stage2'" -o grub1.bs grub1_bs.nasm
; !! incorrect: Run it with: qemu-system-i386 -M pc-1.0 -m 4 -nodefault -vga cirrus -kernel memtest86+.kernel.bin
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
;cpu 8086
cpu 386

BOOT_SIGNATURE equ 0xaa55

bs_boot_sector:  ; The bootloader loads the file to 0:0x7c00 and jumps to 0:0x7c00.
.start:
		or ebp, byte -1  ; Make sure install_second_sector is invalid.
		;mov dl, 0x81
		test dl, dl
		jns .after_partition  ; For floppy, keep the install_partition == 0xffffff default.
		mov dword [0x8208], 0x0ffff  ; Set install_partition to (hd?,0). TODO(pts): Set it to the first active partition, or leave it if no partition table (Liigboot).
.after_partition:
		jmp near stage2
		times 0x200-2-($-.start) db 0
		dw BOOT_SIGNATURE  ; To make the GRUB chainloader command work without --force.
		times 0x8200-0x7c00-($-.start) db 0  ; Entry point of GRUB 1 stage2 is 0:0x8200 (the segment-offset split doesn't mater).

stage2:
%ifdef PATCH
  %define PATCH_IN 'ubuntu-16.04-grub-0.97-29ubuntu68-stage2'
  %macro incbin_rest 0
    incbin PATCH_IN, $-$$-(0x8200-0x7c00)+0x200
  %endm
  %macro incbin_until_infofs 1
    incbin PATCH_IN, $-$$-(0x8200-0x7c00)+0x200, (%1)-($-$$-(0x8200-0x7c00)+0x200)
    assert_at (%1)-(-$$-(0x8200-0x7c00)+0x200)
  %endm
  cpu 386
  bits 32

  %if 0
    ; Original:
    ;00006CCC  52                push edx  ; Just for call alignment.
    ;00006CCD  52                push edx  ; Just for call alignment.
    ;00006CCE  6800020000        push dword 0x200  ; SECTOR_SIZE.
    ;00006CD3  68007C0000        push dword 0x7c00  ; BOOTSEC_LOCATION.
    ;00006CD8  E80B350000        call 0xa1e8  ; grub_read.
    ;00006CDD  83C410            add esp,byte +0x10
    ;00006CE0  3D00020000        cmp eax,0x200  ; SECTOR_SIZE.
    ;00006CE5  7430              je 0x6d17  ; Success.
    ;00006CE7
    incbin_until_infofs 0x6ccc
    push edx
    push edx
    ;push strict dword -1  ; Crashes to a reboot.
    ;push strict dword 0x200  ; Unpatched, loads 0x200 bytes only.
    push strict dword 150024  ; Too much, it also crashes. Probably it overwrites some GRUB data structures.
    ;
    push strict dword 0x7c00
    call $$+0x400+0xa1e8  ; grub_read.
    add esp, byte 0x10
    cmp eax, strict dword 0x200
    jae short $$+0x400+0x6d17
  %endif

  incbin_rest
%else
  %ifndef STAGE2_IN
    %define STAGE2_IN 'stage2'  ; Input filename.
  %endif
		incbin STAGE2_IN, 0x200
%endif
