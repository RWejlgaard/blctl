BITS 64

section .data
    ; String constants
    backlight_path db '/sys/class/backlight/', 0
    brightness_file db 'brightness', 0
    max_brightness_file db 'max_brightness', 0
    
    ; Error messages
    no_device_msg db 'Error: No backlight device found', 10, 0
    invalid_percent_msg db 'Error: Percentage must be between 0 and 100.', 10, 0
    usage_msg db 'Usage: bl [percentage]', 10
              db 'Set the screen brightness to the specified percentage (0-100).', 10
              db 'If no percentage is provided, the current brightness will be displayed.', 10
              db 'Options:', 10
              db '  -h, --help        Show this help message', 10, 0
    
    ; Format strings
    current_fmt db 'Current brightness: %d%% (%d)', 10, 0
    set_fmt db 'Brightness set to %d%% (%d)', 10, 0
    
    ; Buffer for file paths and numbers
    device_path_buf times 256 db 0
    brightness_path_buf times 300 db 0
    max_brightness_path_buf times 300 db 0
    num_buf times 12 db 0
    
    ; Help strings
    help_str1 db '-h', 0
    help_str2 db '--help', 0

section .bss
    current_brightness resd 1
    max_brightness resd 1
    percentage resd 1
    new_brightness resd 1
    argv_save resq 1

section .text
    global _start
    extern printf, atoi, strcmp, strcpy, strcat, opendir, readdir, closedir
    extern open, read, write, close, exit

_start:
    ; argc is at [rsp], argv is at [rsp+8]
    mov rdi, [rsp]          ; argc
    lea rsi, [rsp+8]        ; argv
    mov [argv_save], rsi    ; save argv
    
    ; Check argument count
    cmp rdi, 1
    je show_current         ; No arguments - show current brightness
    cmp rdi, 2
    je check_help_or_set    ; One argument - check if help or set brightness
    jmp show_help           ; Too many arguments - show help

check_help_or_set:
    mov rsi, [argv_save]
    mov rdi, [rsi+8]        ; argv[1]
    mov rsi, help_str1
    call strcmp
    test eax, eax
    jz show_help
    
    mov rsi, [argv_save]
    mov rdi, [rsi+8]        ; argv[1] again
    mov rsi, help_str2  
    call strcmp
    test eax, eax
    jz show_help
    
    ; Convert argument to percentage
    mov rsi, [argv_save]
    mov rdi, [rsi+8]        ; argv[1]
    call atoi
    mov [percentage], eax
    
    ; Validate percentage (0-100)
    cmp eax, 0
    jl invalid_percentage
    cmp eax, 100
    jg invalid_percentage
    
    jmp set_brightness

show_help:
    mov rdi, usage_msg
    call printf
    mov rdi, 0
    call exit

invalid_percentage:
    mov rdi, invalid_percent_msg
    call printf
    mov rdi, 1
    call exit

show_current:
    call find_backlight_device
    test eax, eax
    jz device_not_found
    
    call read_current_brightness
    call read_max_brightness
    
    ; Calculate percentage: (current * 100) / max
    mov eax, [current_brightness]
    mov ecx, 100
    mul ecx
    mov ecx, [max_brightness]
    cmp ecx, 0
    je device_not_found         ; Avoid division by zero
    xor edx, edx
    div ecx
    
    mov rdi, current_fmt
    mov rsi, rax                    ; percentage
    mov rdx, [current_brightness]   ; raw value
    mov rax, 0                      ; clear rax for printf
    call printf
    
    mov rdi, 0
    call exit

set_brightness:
    call find_backlight_device
    test eax, eax
    jz device_not_found
    
    call read_max_brightness
    
    ; Calculate new brightness: (max * percentage) / 100
    mov eax, [max_brightness]
    mov ecx, [percentage]
    mul ecx
    mov ecx, 100
    cmp ecx, 0
    je device_not_found         ; Avoid division by zero
    xor edx, edx
    div ecx
    mov [new_brightness], eax
    
    call write_brightness
    
    mov rdi, set_fmt
    mov rsi, [percentage]
    mov rdx, [new_brightness]
    mov rax, 0                      ; clear rax for printf
    call printf
    
    mov rdi, 0
    call exit

device_not_found:
    mov rdi, no_device_msg
    call printf
    mov rdi, 1
    call exit

; Function to find backlight device
find_backlight_device:
    ; Open /sys/class/backlight/ directory
    mov rdi, backlight_path
    call opendir
    test rax, rax
    jz find_device_fail
    
    mov r12, rax                ; Save directory pointer
    
find_device_loop:
    mov rdi, r12
    call readdir
    test rax, rax
    jz find_device_fail
    
    mov r13, rax                ; Save dirent pointer
    
    ; Skip . and .. entries
    add r13, 19                 ; Offset to d_name in dirent structure
    cmp byte [r13], '.'
    je find_device_loop
    
    ; Build full device path
    mov rdi, device_path_buf
    mov rsi, backlight_path
    call strcpy
    
    mov rdi, device_path_buf
    mov rsi, r13                ; d_name
    call strcat
    
    ; Add trailing slash
    mov rdi, device_path_buf
    call strlen
    mov byte [device_path_buf + rax], '/'
    mov byte [device_path_buf + rax + 1], 0
    
    ; Check if brightness and max_brightness files exist
    call check_device_files
    test eax, eax
    jnz find_device_success
    
    jmp find_device_loop

find_device_success:
    mov rdi, r12
    call closedir
    mov rax, 1
    ret

find_device_fail:
    test r12, r12
    jz find_device_ret
    mov rdi, r12
    call closedir
find_device_ret:
    mov rax, 0
    ret

; Function to check if device files exist
check_device_files:
    ; Build brightness file path
    mov rdi, brightness_path_buf
    mov rsi, device_path_buf
    call strcpy
    
    mov rdi, brightness_path_buf
    mov rsi, brightness_file
    call strcat
    
    ; Try to open brightness file
    mov rdi, brightness_path_buf
    mov rsi, 0                  ; O_RDONLY
    call open
    cmp eax, -1
    je check_files_fail
    
    mov r13, rax                ; Save fd
    call close
    
    ; Build max_brightness file path
    mov rdi, max_brightness_path_buf
    mov rsi, device_path_buf
    call strcpy
    
    mov rdi, max_brightness_path_buf
    mov rsi, max_brightness_file
    call strcat
    
    ; Try to open max_brightness file
    mov rdi, max_brightness_path_buf
    mov rsi, 0                  ; O_RDONLY
    call open
    cmp eax, -1
    je check_files_fail
    
    mov rdi, rax
    call close
    mov rax, 1
    ret

check_files_fail:
    mov rax, 0
    ret

; Function to read current brightness
read_current_brightness:
    mov rdi, brightness_path_buf
    mov rsi, 0                  ; O_RDONLY
    call open
    cmp eax, -1
    je read_current_fail
    
    mov r13, rax                ; Save fd
    
    mov rdi, r13
    mov rsi, num_buf
    mov rdx, 11
    call read
    cmp rax, 0
    jle read_current_fail
    
    mov r14, rax                ; Save bytes read
    
    mov rdi, r13
    call close
    
    ; Null terminate
    mov byte [num_buf + r14], 0
    
    ; Convert to integer
    mov rdi, num_buf
    call atoi
    mov [current_brightness], eax
    ret

read_current_fail:
    mov rdi, 1
    call exit

; Function to read max brightness
read_max_brightness:
    mov rdi, max_brightness_path_buf
    mov rsi, 0                  ; O_RDONLY
    call open
    cmp eax, -1
    je read_max_fail
    
    mov r13, rax                ; Save fd
    
    mov rdi, r13
    mov rsi, num_buf
    mov rdx, 11
    call read
    cmp rax, 0
    jle read_max_fail
    
    mov r14, rax                ; Save bytes read
    
    mov rdi, r13
    call close
    
    ; Null terminate
    mov byte [num_buf + r14], 0
    
    ; Convert to integer
    mov rdi, num_buf
    call atoi
    mov [max_brightness], eax
    ret

read_max_fail:
    mov rdi, 1
    call exit

; Function to write brightness
write_brightness:
    ; Convert new_brightness to string
    mov eax, [new_brightness]
    call int_to_str
    mov r14, rax                ; Save string length
    
    mov rdi, brightness_path_buf
    mov rsi, 1                  ; O_WRONLY
    call open
    cmp eax, -1
    je write_brightness_fail
    
    mov r13, rax                ; Save fd
    
    mov rdi, r13
    mov rsi, num_buf
    mov rdx, r14                ; Length from int_to_str
    call write
    
    mov rdi, r13
    call close
    ret

write_brightness_fail:
    mov rdi, 1
    call exit

; Function to convert integer to string
; Input: eax = integer
; Output: rax = string length, num_buf contains string
int_to_str:
    mov r8d, 10                 ; Base 10
    mov r9, num_buf
    add r9, 11                  ; Start at end of buffer
    mov byte [r9], 0            ; Null terminator
    dec r9
    
    test eax, eax
    jz int_to_str_zero
    
int_to_str_loop:
    xor edx, edx
    div r8d                     ; Divide by 10
    add dl, '0'                 ; Convert remainder to ASCII
    mov [r9], dl
    dec r9
    test eax, eax
    jnz int_to_str_loop
    
    inc r9                      ; Move back to first character
    
    ; Copy to beginning of buffer
    mov rsi, r9
    mov rdi, num_buf
    
int_to_str_copy:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz int_to_str_copy
    
    ; Calculate length
    mov rax, rdi
    sub rax, num_buf
    dec rax                     ; Don't count null terminator
    ret

int_to_str_zero:
    mov byte [r9], '0'
    mov rsi, r9
    mov rdi, num_buf
    mov al, [rsi]
    mov [rdi], al
    mov byte [rdi+1], 0
    mov rax, 1
    ret

; Simple strlen implementation
strlen:
    mov rax, 0
strlen_loop:
    cmp byte [rdi + rax], 0
    je strlen_done
    inc rax
    jmp strlen_loop
strlen_done:
    ret