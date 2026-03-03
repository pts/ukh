%define UKH_PAYLOAD_16
%define UKH_VERSION_STRING 'testk16'
%define UKH_PAYLOAD_SEG 0x5a  ; The default would also work.
;%define UKH_MULTIBOOT  ; Enabled by default.
%include 'ukh.nasm'

;cpu 386  ; Already set up by UKH_KERNEL32.
;bits 32  ; Already set up by UKH_KERNEL32.

		mov bx, 0xb800
		mov es, bx
		mov word [es:2], 0x1700|'2'  ; Write just after the top left corner to the text screen. It works.
		ukh_protected_mode
		mov word [0xb8004], 0x1700|'3'  ; Write just 2 characetrs after the top left corner to the text screen. It works.
		ukh_real_mode  ; Changes ES back to UKH_PAYLOAD_SEG.
		mov ah, 0xe  ; Set up printing.
		xor bx, bx  ; Set up printing.
		;mov si, message  ; ukh.nasm has set up `org' so that this works, but only if (UKH_PAYLOAD_SEG&0xfff)==0.
		mov si, message+ukh_base16
.msg_next:	lodsb
		test al, al
		jz short .msg_done
		int 0x10  ; Print character in AL. We have to be in real mode for this to succeed.
		jmp short .msg_next
.msg_done:	mov cx, ukh_apiseg16
		mov ds, cx
		mov al, [ukh_drive_number16]  ; BIOS drive number, populated by UKH. 0xff if unknown (e.g. with the Linux load protocol).
		call drive_number_to_char_real
		int 0x10  ; Print character in AL.
		mov al, '('
		int 0x10  ; Print character in AL.
		mov si, ukh_kernel_cmdline_ptr16  ; Address of NUL-terminated kernel command line string.
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
		;!!! ukh_a20_gate_al 0  ; A20 gate direction: disable.
		;sti  ; Only after the call to ukh_a20_gate_far. !!! Automatic.
		xor ax, ax
		int 0x16  ; Wait for user keypress. Works.
		mov ax, 0xe00+13
		int 0x10  ; Print character in AL.
		mov al, 10
		int 0x10  ; Print character in AL.
		int 0x19  ; Reboot.

drive_number_to_char_real:  ; Converts BIOS drive number to a character ('0' is first floppy, 'A' is first HDD, '?' is unknown, e.g. 0xff) in AL.
		cmp al, '9'-'0'
		ja short .not_floppy
		add al, '0'
		ret
.not_floppy:	sub al, 0x80
		cmp al, 'Z'-'A'
		ja short .not_hdd
		add al, 'A'
		ret
.not_hdd:	mov al, '?'
		ret

%if 0
times 0xabc nop  ; Make it larger.
%endif

message:	db 'Welcome to testk1! ', 0

ukh_end
