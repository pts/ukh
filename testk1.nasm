%define UKH_PAYLOAD_32
;%define UKH_VERSION_STRING 'testk1'
%define UKH_VERSION_STRING 'memtest86+-5.01'  ; !!!
;%define UKH_MULTIBOOT  ; Enabled by default.
%include 'ukh.nasm'

;cpu 386  ; Already set up by UKH_KERNEL32.
;bits 32  ; Already set up by UKH_KERNEL32.

		mov word [0xb8000], 0x1700|'1'  ; Write to the top left corner to the text screen. It works.
		ukh_real_mode
		mov bx, 0xb800
		mov es, bx
		mov word [es:2], 0x1700|'2'  ; Write just after the top left corner to the text screen. It works.
		ukh_protected_mode
		mov word [0xb8004], 0x1700|'3'  ; Write just 2 characetrs after the top left corner to the text screen. It works.
		ukh_real_mode
		mov ax, 0xe00+'R'
		xor bx, bx  ; Set up printing.
		int 0x10  ; Print character in AL. !! Strange: changes the video mode instead in QEMU. Why
		ukh_a20_gate_al 0  ; A20 gate direction: disable.
		sti  ; Only after the call to ukh_a20_gate_far.
		xor ax, ax
		int 0x16  ; Wait for user keypress. Works.
		int 0x19  ; Reboot.

ukh_end
