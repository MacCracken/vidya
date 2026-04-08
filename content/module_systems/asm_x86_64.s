# Vidya — Module Systems in x86_64 Assembly
#
# Assembly has no modules, but it has the linker's namespace: symbols.
# .global (or .globl) makes a symbol visible to the linker — it becomes
# "public". Without .global, a symbol is file-local — "private". Local
# labels (.L prefix or numeric labels) are never exported. Sections
# (.text, .rodata, .data, .bss) organize code and data by permission
# and lifetime. This is the foundation that all module systems compile to.

.intel_syntax noprefix
.global _start

# ── .global: public symbols (exported to the linker) ───────────────
# _start is the only symbol we MUST export (the entry point).
# In a multi-file project, you'd .global every function other
# files need. Everything else stays private.

.section .rodata
# ── .section .rodata: read-only data segment ───────────────────────
# The OS maps this read-only. Writing to it would segfault.
# Constants, string literals, lookup tables go here.
msg_pass:   .ascii "All module systems examples passed.\n"
msg_len = . - msg_pass

ro_value:   .long 42

# ── Section for lookup tables ──────────────────────────────────────
.align 8
lookup:
    .quad   10, 20, 30, 40
lookup_count = 4

.section .data
# ── .section .data: read-write initialized data ───────────────────
# Global mutable state. Writable at runtime.
counter:    .long 0
flag:       .byte 0

.section .bss
# ── .section .bss: uninitialized data (zero-filled by OS) ─────────
# No bytes in the binary — just a size reservation. Cheaper than .data
# for large buffers.
buffer:     .skip 128

.section .text
# ── .section .text: executable code segment ────────────────────────

_start:
    # ── Test public symbol: _start is reachable (we're running) ────
    # If _start weren't .global, the linker couldn't find the entry point.

    # ── Test .rodata: read constant ────────────────────────────────
    lea     rax, [ro_value]
    cmp     dword ptr [rax], 42
    jne     fail

    # ── Test .data: read-write variable ────────────────────────────
    lea     rax, [counter]
    mov     dword ptr [rax], 0
    inc     dword ptr [rax]
    inc     dword ptr [rax]
    inc     dword ptr [rax]
    cmp     dword ptr [rax], 3
    jne     fail

    # ── Test .bss: zero-initialized buffer ─────────────────────────
    lea     rax, [buffer]
    cmp     dword ptr [rax], 0      # BSS is zero
    jne     fail
    mov     dword ptr [rax], 0xAA
    cmp     dword ptr [rax], 0xAA   # now writable
    jne     fail

    # ── Local labels: private to this scope ────────────────────────
    # Labels starting with . are local — they don't pollute the global
    # symbol table. The linker never sees them.
    call    .local_helper
    cmp     eax, 77
    jne     fail

    # ── Private function: not .global, invisible to linker ─────────
    call    private_add
    # private_add returns 30 (10 + 20)
    cmp     eax, 30
    jne     fail

    # ── Numeric local labels: reusable within a file ───────────────
    # 1:, 2:, etc. can be reused. Reference with 1f (forward) or 1b (back).
    mov     ecx, 3
1:
    dec     ecx
    jnz     1b              # jump back to nearest "1:" label
    cmp     ecx, 0
    jne     fail

    # Forward reference
    jmp     2f
    jmp     fail            # skipped
2:

    # ── Test lookup table in .rodata ───────────────────────────────
    lea     rsi, [lookup]
    cmp     qword ptr [rsi + 0*8], 10
    jne     fail
    cmp     qword ptr [rsi + 1*8], 20
    jne     fail
    cmp     qword ptr [rsi + 2*8], 30
    jne     fail
    cmp     qword ptr [rsi + 3*8], 40
    jne     fail

    # ── Section placement: verify symbols are in expected sections ──
    # We can call functions from .text, read from .rodata, write to .data.
    # The separation is enforced by the OS memory map, not the assembler.

    # Set and read the flag in .data
    lea     rax, [flag]
    mov     byte ptr [rax], 1
    cmp     byte ptr [rax], 1
    jne     fail

    # ── Encapsulation pattern: accessor functions ──────────────────
    # Without modules, the convention is to provide functions that
    # access private data — hiding the layout behind a call interface.
    call    get_counter
    cmp     eax, 3              # we set counter to 3 above
    jne     fail

    mov     edi, 10
    call    set_counter
    call    get_counter
    cmp     eax, 10
    jne     fail

    # ── Print success ──────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall

# ── Local label helper: only visible within this file ──────────────
.local_helper:
    mov     eax, 77
    ret

# ── Private function (not .global — linker won't export it) ────────
# In a multi-file build, other .o files cannot call this.
private_add:
    mov     eax, 10
    add     eax, 20
    ret

# ── Accessor functions: encapsulation over private data ────────────
# These could be .global in a multi-file project — they form the
# "public API" while counter itself stays private.

get_counter:
    lea     rax, [counter]
    mov     eax, dword ptr [rax]
    ret

set_counter:
    lea     rax, [counter]
    mov     dword ptr [rax], edi
    ret
