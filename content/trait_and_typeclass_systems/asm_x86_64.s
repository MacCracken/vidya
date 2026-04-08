# Vidya — Trait and Typeclass Systems in x86_64 Assembly
#
# Traits/interfaces compile down to vtables: arrays of function pointers.
# Virtual dispatch = load a pointer from the table, then indirect call.
# The CPU sees no types — just addresses and data. The "object" is a
# pointer pair: [data_ptr, vtable_ptr]. This is exactly what Rust's
# dyn Trait and C++ virtual calls become at the machine level.

.intel_syntax noprefix
.global _start

.section .rodata
msg_pass:   .ascii "All trait and typeclass examples passed.\n"
msg_len = . - msg_pass

# ── Vtables: each "type" has a table of function pointers ──────────
# Our trait has two methods: area(data) → int, perimeter(data) → int.
# Vtable layout: [area_fn:8][perimeter_fn:8]

.align 8
circle_vtable:
    .quad   circle_area
    .quad   circle_perimeter

.align 8
rectangle_vtable:
    .quad   rectangle_area
    .quad   rectangle_perimeter

.section .data

# ── "Objects": data + vtable pointer ───────────────────────────────
# Circle: data = [radius:4]
circle_data:
    .long   5                   # radius = 5

# Rectangle: data = [width:4][height:4]
rectangle_data:
    .long   3                   # width = 3
    .long   7                   # height = 7

# ── Trait objects: fat pointers [data_ptr:8][vtable_ptr:8] ─────────
circle_trait_obj:
    .quad   circle_data
    .quad   circle_vtable

rectangle_trait_obj:
    .quad   rectangle_data
    .quad   rectangle_vtable

.section .text

_start:
    # ── Direct vtable dispatch: circle ─────────────────────────────
    # Load vtable, call area(data). Load function pointer into register,
    # then indirect call — this is what virtual dispatch looks like.
    lea     rsi, [circle_vtable]
    lea     rdi, [circle_data]

    # Call area: load vtable[0] into rax, then call rax
    mov     rax, qword ptr [rsi + 0]
    call    rax                     # indirect call through vtable
    # circle area = radius * radius * 3 (integer approx of pi)
    # 5 * 5 * 3 = 75
    cmp     eax, 75
    jne     fail

    # Call perimeter: vtable[1]
    lea     rsi, [circle_vtable]
    lea     rdi, [circle_data]
    mov     rax, qword ptr [rsi + 8]
    call    rax
    # circle perimeter = 2 * 3 * radius = 30
    cmp     eax, 30
    jne     fail

    # ── Direct vtable dispatch: rectangle ──────────────────────────
    lea     rsi, [rectangle_vtable]
    lea     rdi, [rectangle_data]

    mov     rax, qword ptr [rsi + 0]
    call    rax                     # area
    # 3 * 7 = 21
    cmp     eax, 21
    jne     fail

    lea     rsi, [rectangle_vtable]
    lea     rdi, [rectangle_data]
    mov     rax, qword ptr [rsi + 8]
    call    rax                     # perimeter
    # 2 * (3 + 7) = 20
    cmp     eax, 20
    jne     fail

    # ── Fat pointer dispatch (dyn Trait pattern) ───────────────────
    # Given only a trait object pointer, extract data + vtable, dispatch.
    # This is exactly what Rust does for &dyn Shape.
    lea     r12, [circle_trait_obj]
    mov     edi, 0              # method index 0 = area
    call    dispatch_trait
    cmp     eax, 75
    jne     fail

    lea     r12, [circle_trait_obj]
    mov     edi, 1              # method index 1 = perimeter
    call    dispatch_trait
    cmp     eax, 30
    jne     fail

    lea     r12, [rectangle_trait_obj]
    mov     edi, 0              # area
    call    dispatch_trait
    cmp     eax, 21
    jne     fail

    lea     r12, [rectangle_trait_obj]
    mov     edi, 1              # perimeter
    call    dispatch_trait
    cmp     eax, 20
    jne     fail

    # ── Polymorphic loop: call area on heterogeneous objects ────────
    # An array of trait object pointers — iterate and sum areas.
    # This is the runtime polymorphism pattern.
    call    sum_areas
    # circle area (75) + rectangle area (21) = 96
    cmp     eax, 96
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

# ── dispatch_trait(r12=trait_obj_ptr, edi=method_index) → eax ──────
# Loads data pointer and vtable pointer from the fat pointer,
# then does an indirect call through vtable[method_index].
dispatch_trait:
    push    rbx
    movsxd  rax, edi
    mov     rdi, qword ptr [r12 + 0]   # data pointer
    mov     rsi, qword ptr [r12 + 8]   # vtable pointer
    mov     rax, qword ptr [rsi + rax * 8]  # load function pointer
    call    rax                         # vtable[index](data)
    pop     rbx
    ret

# ── sum_areas() → eax: sum of area() across trait objects ──────────
sum_areas:
    push    rbx
    push    r12
    xor     ebx, ebx            # accumulator

    # Object 0: circle
    lea     r12, [circle_trait_obj]
    mov     edi, 0
    call    dispatch_trait
    add     ebx, eax

    # Object 1: rectangle
    lea     r12, [rectangle_trait_obj]
    mov     edi, 0
    call    dispatch_trait
    add     ebx, eax

    mov     eax, ebx
    pop     r12
    pop     rbx
    ret

# ── Circle implementations ────────────────────────────────────────
# rdi = pointer to circle_data [radius:4]

circle_area:
    mov     eax, dword ptr [rdi]    # radius
    imul    eax, eax                # radius^2
    imul    eax, 3                  # * 3 (integer pi approximation)
    ret

circle_perimeter:
    mov     eax, dword ptr [rdi]    # radius
    imul    eax, 6                  # 2 * 3 * radius
    ret

# ── Rectangle implementations ─────────────────────────────────────
# rdi = pointer to rectangle_data [width:4][height:4]

rectangle_area:
    mov     eax, dword ptr [rdi]        # width
    imul    eax, dword ptr [rdi + 4]    # * height
    ret

rectangle_perimeter:
    mov     eax, dword ptr [rdi]        # width
    add     eax, dword ptr [rdi + 4]    # + height
    shl     eax, 1                      # * 2
    ret
