# Vidya — Linking and Loading in x86_64 Assembly
#
# At the assembly level, linking resolves symbols to addresses. This file
# demonstrates: global vs local symbols, RIP-relative addressing (the
# foundation of position-independent code), calling local functions,
# section placement, and the relocation patterns the linker must resolve.
#
# Key concepts:
# - .globl makes a symbol visible to the linker (exported)
# - Local labels (no .globl) are file-scoped — invisible to other objects
# - RIP-relative addressing: lea rax, [rip + symbol] generates a
#   relocation (R_X86_64_PC32) the linker patches with the offset
# - Absolute addresses (movabs rax, symbol) generate R_X86_64_64
#   relocations — not PIC-compatible

.intel_syntax noprefix
.global _start                  # .global exports _start to the linker
                                # The linker needs this as the entry point

.section .rodata
msg_pass:   .ascii "All linking and loading examples passed.\n"
msg_len = . - msg_pass

local_str:  .ascii "local"      # no .globl — only visible in this file
local_str_len = . - local_str

.section .data
.align 8
# ── Global data symbol ─────────────────────────────────────────────
.global exported_value
exported_value: .quad 42        # visible to other object files

# ── File-local data ────────────────────────────────────────────────
internal_counter:   .quad 0     # no .globl — file-private
another_local:      .quad 100

.section .bss
.align 4096
# ── BSS: zero-initialized, occupies no space in object file ────────
# The loader allocates and zeros this at load time
.global bss_buffer
bss_buffer:     .skip 4096      # 4KB zero-initialized buffer

.section .text

# ════════════════════════════════════════════════════════════════════
# _start — entry point (global symbol, linker resolves this)
# ════════════════════════════════════════════════════════════════════
_start:
    # ── RIP-relative addressing ─────────────────────────────────────
    # In x86_64, [symbol] in Intel syntax defaults to RIP-relative
    # for static data. The assembler emits a R_X86_64_PC32 relocation
    # that the linker resolves: final_offset = symbol - (rip + 4)
    #
    # This is how position-independent code (PIC) accesses data:
    # the offset is relative to the instruction pointer, so the code
    # works regardless of where it's loaded in memory.

    # RIP-relative load: linker fills in displacement
    lea     rax, [exported_value]   # R_X86_64_PC32 relocation
    mov     rax, [rax]
    cmp     rax, 42
    jne     fail

    # Direct RIP-relative mov:
    mov     rax, [exported_value]   # also RIP-relative
    cmp     rax, 42
    jne     fail

    # ── LEA for address computation (no memory access) ──────────────
    # LEA computes the address; MOV would dereference it
    # Both generate relocations the linker must resolve
    lea     r12, [exported_value]   # r12 = &exported_value
    lea     r13, [internal_counter] # r13 = &internal_counter

    # Verify they point to different locations
    cmp     r12, r13
    je      fail

    # Verify we can dereference both
    mov     rax, [r12]
    cmp     rax, 42
    jne     fail
    mov     rax, [r13]
    cmp     rax, 0
    jne     fail

    # ── Call to local function (file-private symbol) ────────────────
    # The assembler resolves this to a relative offset.
    # In the object file, this is a R_X86_64_PLT32 relocation
    # (or R_X86_64_PC32 for direct calls in static linking).
    mov     rdi, 10
    mov     rsi, 20
    call    local_helper            # linker resolves to relative offset
    cmp     rax, 30
    jne     fail

    # ── Call to another local function ──────────────────────────────
    call    increment_counter
    call    increment_counter
    call    increment_counter
    mov     rax, [internal_counter]
    cmp     rax, 3
    jne     fail

    # ── Demonstrate section placement ───────────────────────────────
    # .rodata, .data, .bss, .text go into different segments.
    # The linker script (or default layout) determines their order.
    # Typically: .text (rx) | .rodata (r) | .data (rw) | .bss (rw)

    # Verify .rodata is readable
    lea     rsi, [local_str]
    movzx   eax, byte ptr [rsi]
    cmp     al, 'l'             # first byte of "local"
    jne     fail

    # Verify .bss is zero-initialized
    lea     rsi, [bss_buffer]
    mov     rax, [rsi]
    test    rax, rax
    jnz     fail                # must be zero

    # Write to .bss (it's in a writable segment)
    mov     rax, 0xDEADBEEF
    mov     [rsi], rax
    cmp     [rsi], rax
    jne     fail

    # ── Demonstrate symbol address relationships ────────────────────
    # Symbols in the same section have fixed relative offsets.
    # The linker preserves these offsets when laying out the section.
    lea     rax, [exported_value]
    lea     rcx, [internal_counter]
    # The difference is fixed at link time (8 bytes if contiguous)
    sub     rcx, rax
    cmp     rcx, 8              # exported_value is 8 bytes, followed by counter
    jne     fail

    # ── Weak vs strong symbols (concept) ────────────────────────────
    # .weak symbol — linker won't error if undefined (resolves to 0)
    # .globl symbol — strong symbol, linker errors on duplicates
    # We demonstrate with a weak symbol:
.weak optional_plugin
    lea     rax, [optional_plugin]
    # If not defined elsewhere, this resolves to 0
    # (Linker may or may not zero it — behavior is defined for .weak)
    # In static linking with no other object, it's typically 0

    # ── Print success ───────────────────────────────────────────────
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

# ════════════════════════════════════════════════════════════════════
# local_helper — file-private function (not exported)
# No .globl directive = invisible to the linker from other objects
# ════════════════════════════════════════════════════════════════════
local_helper:
    lea     rax, [rdi + rsi]    # return a + b
    ret

# ════════════════════════════════════════════════════════════════════
# increment_counter — accesses file-local data
# Demonstrates: function modifying private module state
# ════════════════════════════════════════════════════════════════════
increment_counter:
    lock inc qword ptr [internal_counter]
    ret
