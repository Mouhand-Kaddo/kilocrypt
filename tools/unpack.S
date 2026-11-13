.intel_syntax noprefix

.ifndef DEBUG
.set DEBUG, 0
.endif

.set BASE, 0x400000
.set BSS, BASE + 0x20000
.set SQUASH_C, BSS + 0x1000
.set STRETCH, BSS + 0x2000
.set STRETCH_C, STRETCH + 0x1000
.set STRIDE_HI, 0x0D
.set MODEL0, BSS + 0x20000 - NMODELS * (STRIDE_HI << 8)
.set EXPANDED, -8
.set MODEL0_HI, (MODEL0 >> 8) & 0xFF
.set OUTBUF, BSS + 0x20000
.set TABLE, BSS + 0x200000
.set MEMSZ, TABLE + (4 << HASH_BITS) - BASE

ehdr:
    .byte 0x7f, 'E', 'L', 'F', 2, 1, 1
load_seed:
    mov eax, SQUASH_SEED
    pop r13
    jmp _start
    .org ehdr + 0x10
    .word 2, 0x3e
    .long 1
    .quad BASE + load_hash_multiplier - ehdr
    .quad phdr - ehdr
load_hash_multiplier:
    movabs r15, 0x9E3779B97F4A7C15
    push 1
    jmp load_index
    .org ehdr + 0x36
    .word 56
phdr:
    .long 1, 7
    .quad 0
    .quad BASE
load_index:
    push -2048
    pop rcx
    jmp load_seed
    .org ehdr + 0x58
    .quad 0
    .quad MEMSZ

_start:
build_tables:
    mov rbx, rax
    shr rbx, 20
    inc ebx
    mov [SQUASH_C + rcx * 2], bx
fill_stretch:
    cmp edx, ebx
    ja stretch_filled
    mov [STRETCH + rdx * 2], cx
    inc edx
    jmp fill_stretch
stretch_filled:
    mov r8d, eax
    neg r8d
    imul r8, rax
    shr r8, 40
    add rax, r8
    inc rcx
    cmp ch, 8
    jne build_tables

    mov ebx, MODEL0
    mov esi, OFFSET masks + BASE - ehdr
init_model:
    lodsb
    push 8
    pop rcx
expand:
    shr al, 1
    sbb bpl, bpl
    ror rbp, 8
    loop expand
    mov [rbx + EXPANDED], rbp
    add bh, STRIDE_HI
    jnc init_model

    mov bh, MODEL0_HI
    mov edi, OUTBUF
    mov ebp, 0x101
next_bit:
    mov eax, r13d
    shr eax, 24
    jnz normalized
    shl r13d, 8
    shl r12d, 8
    lodsb
    mov r12b, al
    jmp next_bit
normalized:
    movzx r11d, byte ptr [rdi - 1]
    movzx ecx, byte ptr [rdi - 2]
    mov ch, 2
    xor r9d, r9d
predict:
    mov rax, [rdi - 8]
    mov rdx, [rbx + EXPANDED]
    test dl, dl
    cmovnz rax, r14
    and rax, rdx
    xor rax, rbp
    xor rax, rbx
    imul rax, r15
    shr rax, 64 - HASH_BITS
    lea rax, [TABLE + rax * 4]
    push rax
    movsx eax, word ptr [rax]
    sar eax, 4
    movsx eax, word ptr [STRETCH_C + eax * 2]
    push rax
    push rbx
    mov edx, [rbx + r11 * 4]
    add edx, [rbx + rbp * 4]
    add edx, [rbx + rcx * 4]
    add edx, WINIT
    imul eax, edx
    cdqe
    add r9, rax
    add bh, STRIDE_HI
    jnc predict

    sar r9, 16
    mov eax, 2047
    cmp r9, rax
    cmovg r9, rax
    not rax
    cmp r9, rax
    cmovl r9, rax
    movzx eax, word ptr [SQUASH_C + r9 * 2]

    mov edx, r13d
    shr edx, 12
    imul edx, eax
    sub r13d, edx
    sub r12d, edx
    sbb r9, r9
    jnc decoded
    add r12d, edx
    mov r13d, edx
decoded:
    imul r10d, r9d, -4096
    sub r10d, eax
    shl r9, 48
    or r10, r9

update:
    pop rbx
    pop rax
    imul eax, r10d
    sar eax, SHIFT
    add [rbx + r11 * 4], eax
    add [rbx + rbp * 4], eax
    add [rbx + rcx * 4], eax
    pop r8
    movzx r9d, word ptr [r8 + 2]
    lea r9d, [r9 + r9 * RATE_SCALE + RATE_BIAS]
    movzx eax, word ptr [r8]
    xor ah, 0x80
    mov rdx, r10
    shr rdx, 32
    add eax, edx
    lea eax, [rax + rax * RATE_SCALE]
    cdq
    idiv r9d
    sub [r8], ax
    cmp r9b, (RATE_SCALE + 1) * LIMIT + RATE_BIAS
    adc word ptr [r8 + 2], 0
    cmp bh, MODEL0_HI
    jne update

    shl r10, 1
    adc bpl, bpl
    jnc byte_pending
    mov eax, ebp
    stosb
    add r14, rax
    imul r14, r15
    or al, 0x20
    sub al, 0x61
    cmp al, 26
    jb in_word
    xor r14d, r14d
in_word:
    mov bpl, 1
byte_pending:
    cmp edi, OUTBUF + OUT_LEN
    jb next_bit

.if E8E9
    mov esi, OUTBUF
unfilter:
    lodsb
    and al, 0xFE
    cmp al, 0xE8
    jne unfilter_next
    sub [rsi], esi
    lodsd
unfilter_next:
    cmp esi, edi
    jb unfilter
.endif

.if DEBUG
    push 1
    pop rdi
    mov esi, OUTBUF
    mov edx, OUT_LEN
    mov eax, edi
    syscall
    push 60
    pop rax
    xor edi, edi
    syscall
.else
    xor esi, esi
    mov eax, 319
    syscall
    xchg eax, edi
    mov edx, OUT_LEN
    sub eax, edx
    xchg eax, esi
    inc eax
    syscall
    add esi, edx
    pop r10
    push rsp
    pop rdx
    lea r10, [rsp + r10 * 8 + 8]
    mov r8d, 0x1000
    mov eax, 322
    syscall
    push 60
    pop rax
    syscall
.endif

masks:
