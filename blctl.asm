; blctl.asm - Backlight controller in x86-64 assembly
; Linux only, direct syscalls, no libc.

%define SYS_read       0
%define SYS_write      1
%define SYS_open       2
%define SYS_close      3
%define SYS_exit       60
%define SYS_getdents64 217

%define STDOUT 1
%define STDERR 2
%define O_WRONLY     1
%define O_TRUNC      0x200
%define O_RDONLY_DIR 0x10000        ; O_RDONLY | O_DIRECTORY
%define DENTS_SZ     1024

section .rodata
    ; String constants
    backlight_dir       db '/sys/class/backlight/', 0
    brightness_file     db 'brightness', 0
    max_brightness_file db 'max_brightness', 0

    ; Error messages
    no_device_msg       db 'Error: No backlight device found', 10, 0
    invalid_percent_msg db 'Error: Percentage must be a number between 0 and 100.', 10, 0
    write_fail_msg      db 'Error: Cannot set brightness (insufficient permissions?)', 10, 0

    usage_msg db 'Usage: blctl [percentage]', 10
              db 'Set the screen brightness to the specified percentage (0-100).', 10
              db 'If no percentage is provided, the current brightness will be displayed.', 10
              db 'Options:', 10
              db '  -h, --help        Show this help message', 10
    usage_len equ $ - usage_msg

    ; Output fragments
    current_prefix db 'Current brightness: ', 0
    set_prefix     db 'Brightness set to ', 0
    raw_open       db '% (', 0
    raw_close      db ')', 10, 0

    ; Help strings
    help_str1 db '-h', 0
    help_str2 db '--help', 0

section .bss
    current_brightness resq 1
    max_brightness     resq 1
    percentage         resq 1
    new_brightness     resq 1

    ; Directory scan
    dirfd      resq 1
    dents_len  resq 1
    dents_off  resq 1
    dirent_buf resb DENTS_SZ

    ; Path building
    path_buf     resb 256
    dev_path_len resq 1

    ; Scratch
    num_buf resb 40
    num_tmp resb 32
    out_buf resb 128

section .text
    global _start

_start:
    mov r12, [rsp]              ; argc
    lea r13, [rsp+8]            ; argv

    cmp r12, 1
    je show_current             ; No arguments - show current brightness
    cmp r12, 2
    jne show_help               ; Too many arguments - show help

    mov r14, [r13 + 8]          ; argv[1]
    mov rdi, r14
    mov rsi, help_str1
    call str_eq
    test al, al
    jnz show_help

    mov rdi, r14
    mov rsi, help_str2
    call str_eq
    test al, al
    jnz show_help

    ; Convert argument to percentage
    mov rdi, r14
    call parse_percentage
    test rdx, rdx
    jz invalid_percentage
    mov [percentage], rax
    jmp set_brightness

show_help:
    mov eax, SYS_write
    mov edi, STDOUT
    mov rsi, usage_msg
    mov edx, usage_len
    syscall
    xor edi, edi
    jmp exit_now

invalid_percentage:
    mov rsi, invalid_percent_msg
    jmp fail

device_not_found:
    mov rsi, no_device_msg
    jmp fail

write_failed:
    mov rsi, write_fail_msg
fail:
    mov rbx, out_buf
    call emit_str
    mov eax, SYS_write
    mov edi, STDERR
    mov rsi, out_buf
    mov rdx, rbx
    sub rdx, out_buf
    syscall
    mov edi, 1
exit_now:
    mov eax, SYS_exit
    syscall

show_current:
    call find_backlight_device
    test al, al
    jz device_not_found

    mov rdi, brightness_file
    call read_number
    test rdx, rdx
    jz device_not_found
    mov [current_brightness], rax

    call load_max_brightness

    ; Calculate percentage: (current * 100 + max/2) / max, rounded
    mov rax, [current_brightness]
    mov rcx, 100
    mul rcx
    mov rcx, [max_brightness]
    shr rcx, 1
    add rax, rcx
    adc rdx, 0
    mov rcx, [max_brightness]
    div rcx

    mov rsi, current_prefix
    mov rdx, [current_brightness]
    jmp report

set_brightness:
    call find_backlight_device
    test al, al
    jz device_not_found

    call load_max_brightness

    ; Calculate new brightness: (max * percentage + 50) / 100, rounded
    mov rax, [max_brightness]
    mov rcx, [percentage]
    mul rcx
    add rax, 50
    adc rdx, 0
    mov rcx, 100
    div rcx
    mov [new_brightness], rax

    call write_brightness
    test rax, rax
    js write_failed

    mov rax, [percentage]
    mov rsi, set_prefix
    mov rdx, [new_brightness]
    ; fall through

; rax = percentage, rsi = prefix, rdx = raw value
report:
    mov rbx, out_buf
    mov r14, rax
    mov r15, rdx

    call emit_str
    mov rax, r14
    call emit_num
    mov rsi, raw_open
    call emit_str
    mov rax, r15
    call emit_num
    mov rsi, raw_close
    call emit_str

    mov eax, SYS_write
    mov edi, STDOUT
    mov rsi, out_buf
    mov rdx, rbx
    sub rdx, out_buf
    syscall

    xor edi, edi
    jmp exit_now

; ---------------------------------------------------------------------------
; Backlight device
; ---------------------------------------------------------------------------

; Find the first device under /sys/class/backlight that exposes both
; brightness and max_brightness, leaving its path in path_buf.
; -> al = 1 on success
find_backlight_device:
    mov eax, SYS_open
    mov rdi, backlight_dir
    mov esi, O_RDONLY_DIR
    xor edx, edx
    syscall
    test eax, eax
    js .fail
    mov [dirfd], rax

.next_block:
    mov eax, SYS_getdents64
    mov rdi, [dirfd]
    mov rsi, dirent_buf
    mov edx, DENTS_SZ
    syscall
    test rax, rax
    jle .close_fail
    mov [dents_len], rax
    mov qword [dents_off], 0

.entry:
    mov rax, [dents_off]
    cmp rax, [dents_len]
    jae .next_block

    lea rsi, [dirent_buf + rax]
    movzx edx, word [rsi + 16]      ; d_reclen
    add [dents_off], rdx
    lea rdi, [rsi + 19]             ; d_name

    cmp byte [rdi], '.'
    je .entry

    call set_device_path
    call check_device_files
    test al, al
    jz .entry

    mov eax, SYS_close
    mov rdi, [dirfd]
    syscall
    mov eax, 1
    ret

.close_fail:
    mov eax, SYS_close
    mov rdi, [dirfd]
    syscall
.fail:
    xor eax, eax
    ret

; rdi = device name -> path_buf = "/sys/class/backlight/<name>/"
set_device_path:
    push rdi
    mov rdi, path_buf
    mov rsi, backlight_dir
    call strcpy_z
    pop rsi
    call strcpy_z
    mov byte [rdi], '/'
    inc rdi
    mov byte [rdi], 0
    sub rdi, path_buf
    mov [dev_path_len], rdi
    ret

; -> al = 1 when both brightness files are readable
check_device_files:
    mov rdi, brightness_file
    call open_attr
    test eax, eax
    js .fail
    mov edi, eax
    mov eax, SYS_close
    syscall

    mov rdi, max_brightness_file
    call open_attr
    test eax, eax
    js .fail
    mov edi, eax
    mov eax, SYS_close
    syscall

    mov eax, 1
    ret
.fail:
    xor eax, eax
    ret

; Read max_brightness, bailing out if it is missing or zero
load_max_brightness:
    mov rdi, max_brightness_file
    call read_number
    test rdx, rdx
    jz device_not_found
    test rax, rax
    jz device_not_found         ; Avoid division by zero
    mov [max_brightness], rax
    ret

; Write new_brightness to the device -> rax = write result
write_brightness:
    mov rdi, path_buf
    add rdi, [dev_path_len]
    mov rsi, brightness_file
    call strcpy_z

    mov rax, [new_brightness]
    call number_to_string       ; rax = length, string in num_buf

    mov r8, rax
    mov eax, SYS_open
    mov rdi, path_buf
    mov esi, O_WRONLY | O_TRUNC
    xor edx, edx
    syscall
    test eax, eax
    js .ret

    mov r9d, eax
    mov eax, SYS_write
    mov edi, r9d
    mov rsi, num_buf
    mov rdx, r8
    syscall

    mov r8, rax
    mov eax, SYS_close
    mov edi, r9d
    syscall
    mov rax, r8
.ret:
    ret

; ---------------------------------------------------------------------------
; sysfs helpers
; ---------------------------------------------------------------------------

; rdi = attribute name -> rax = fd (negative on error)
open_attr:
    mov rsi, rdi
    mov rdi, path_buf
    add rdi, [dev_path_len]
    call strcpy_z

    mov eax, SYS_open
    mov rdi, path_buf
    xor esi, esi                ; O_RDONLY
    xor edx, edx
    syscall
    ret

; rdi = attribute name -> rax = value, rdx = 1 if the file was readable
read_number:
    call open_attr
    test eax, eax
    js .missing

    mov r8d, eax
    xor eax, eax                ; SYS_read
    mov edi, r8d
    mov rsi, num_buf
    mov edx, 31
    syscall
    mov r9, rax

    mov eax, SYS_close
    mov edi, r8d
    syscall

    test r9, r9
    jle .missing
    mov byte [num_buf + r9], 0

    mov rdi, num_buf
    call atou
    mov edx, 1
    ret
.missing:
    xor eax, eax
    xor edx, edx
    ret

; ---------------------------------------------------------------------------
; Conversion helpers
; ---------------------------------------------------------------------------

; rdi = string -> rax = value, rdx = 1 when it is a valid 0-100 percentage
parse_percentage:
    xor eax, eax
    xor ecx, ecx
    xor r8d, r8d
.loop:
    mov cl, [rdi]
    test cl, cl
    jz .end
    sub cl, '0'
    cmp cl, 9
    ja .bad
    lea rax, [rax + rax*4]      ; rax *= 5
    lea rax, [rcx + rax*2]      ; rax = rax*10 + digit
    cmp rax, 100
    ja .bad
    inc r8d
    inc rdi
    jmp .loop
.end:
    test r8d, r8d
    jz .bad
    mov edx, 1
    ret
.bad:
    xor eax, eax
    xor edx, edx
    ret

; rdi = null-terminated digits -> rax = value
atou:
    xor eax, eax
    xor ecx, ecx
.loop:
    mov cl, [rdi]
    sub cl, '0'
    cmp cl, 9
    ja .done
    lea rax, [rax + rax*4]
    lea rax, [rcx + rax*2]
    inc rdi
    jmp .loop
.done:
    ret

; rax = value -> num_buf holds the decimal string, rax = its length
number_to_string:
    mov rsi, num_tmp + 31
    mov byte [rsi], 0
    mov rcx, 10
.digit:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .digit

    mov rdi, num_buf
.copy:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .done
    inc rdi
    inc rsi
    jmp .copy
.done:
    mov rax, rdi
    sub rax, num_buf
    ret

; rdi = dst, rsi = src -> rdi points at the terminating null
strcpy_z:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .done
    inc rdi
    inc rsi
    jmp strcpy_z
.done:
    ret

; rdi = str1, rsi = str2 -> al = 1 when equal
str_eq:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .differ
    test al, al
    jz .equal
    inc rdi
    inc rsi
    jmp str_eq
.equal:
    mov eax, 1
    ret
.differ:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; Output primitives - rbx is the output cursor, everything else is preserved
; ---------------------------------------------------------------------------

; rsi = null-terminated string
emit_str:
    push rax
    push rsi
.loop:
    mov al, [rsi]
    test al, al
    jz .done
    mov [rbx], al
    inc rbx
    inc rsi
    jmp .loop
.done:
    pop rsi
    pop rax
    ret

; rax = value
emit_num:
    push rax
    push rcx
    push rdx
    push rsi

    mov rsi, num_tmp + 31
    mov byte [rsi], 0
    mov rcx, 10
.digit:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .digit
    call emit_str

    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret
