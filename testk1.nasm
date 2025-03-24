%define UKH_PAYLOAD_32
%define UKH_VERSION_STRING 'testk1'
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
		mov ah, 0xe  ; Set up printing.
		xor bx, bx  ; Set up printing.
		mov si, message  ; ukh.nasm has set up `org' so that this works.
.msg_next:	lodsb
		test al, al
		jz short .msg_done
		int 0x10  ; Print character in AL. We have to be in real mode for this to succeed.
		jmp short .msg_next
.msg_done:	mov cx, 0x9000
		mov ds, cx
		mov al, [7]  ; BIOS drive number, populated by UKH. 0xff if unknown (e.g. with the Linux load protocol).
		call drive_number_to_char_real
		int 0x10  ; Print character in AL.
		mov al, '('
		int 0x10  ; Print character in AL.
		mov si, 0x22  ; Address of NUL-terminated kernel command line string.
		cmp word [si-2], 0xa33f  ; Magic number indicating the presence of the command-line
		jne short .cmdline_done
		mov si, [si]  ; Follow the pointer to get the binning of the command line.
.cmdline_next:	lodsb
		test al, al
		jz short .cmdline_done
		int 0x10  ; Print character in AL.
		jmp short .cmdline_next
.cmdline_done:	mov al, ')'
		int 0x10  ; Print character in AL.
		mov al, ' '
		int 0x10  ; Print character in AL.
		ukh_a20_gate_al 0  ; A20 gate direction: disable.
		sti  ; Only after the call to ukh_a20_gate_far.
		xor ax, ax
		int 0x16  ; Wait for user keypress. Works.
		mov ax, 0xe00+13
		int 0x10  ; Print character in AL.
		mov al, 10
		int 0x10  ; Print character in AL.
		int 0x19  ; Reboot.

drive_number_to_char_real:  ; Converts BIOS drive number to a character ('a' is first floppy, 'C' is first HDD, '?' is unknown, e.g. 0xff) in AL.
		cmp al, 'z'-'a'
		ja short .not_floppy
		add al, 'a'
		ret
.not_floppy:	sub al, 0x80
		cmp al, 'Z'-'C'
		ja short .not_hdd
		add al, 'C'
		ret
.not_hdd:	mov al, '?'
		ret

message:	db 'Welcome to testk1! ', 0

ukh_end
