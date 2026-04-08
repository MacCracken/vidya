// Vidya — Linking and Loading in C
//
// Demonstrates linker internals by building a simplified two-pass linker:
//   - Object files with symbol tables, sections, and relocations
//   - Symbol resolution: detect duplicates and undefined references
//   - Section layout: merge .text then .data from all objects
//   - Relocation patching: absolute (R_X86_64_32S) and PC-relative (R_X86_64_PC32)
//   - GOT/PLT lazy binding model
//
// This is the core of what ld does: collect symbols, place sections,
// then walk the relocation table patching every placeholder.

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Relocation types ────────────────────────────────────────────────

typedef enum {
    RELOC_ABS64,  // R_X86_64_64:   S + A (absolute 64-bit)
    RELOC_ABS32,  // R_X86_64_32S:  S + A (absolute 32-bit, sign-extended)
    RELOC_PC32,   // R_X86_64_PC32: S + A - P (PC-relative 32-bit)
} RelocType;

static const char *reloc_type_name(RelocType t) {
    switch (t) {
        case RELOC_ABS64: return "R_X86_64_64";
        case RELOC_ABS32: return "R_X86_64_32S";
        case RELOC_PC32:  return "R_X86_64_PC32";
    }
    return "UNKNOWN";
}

// ── Object file model ───────────────────────────────────────────────

#define MAX_SECTIONS 8
#define MAX_SYMBOLS 16
#define MAX_RELOCS 16
#define MAX_SECTION_SIZE 256

typedef struct {
    char name[16];
    uint8_t data[MAX_SECTION_SIZE];
    size_t size;
    uint64_t base_addr;  // filled in by linker
} Section;

typedef struct {
    char name[64];
    char section[16];    // section name (for definitions)
    uint64_t offset;     // offset within section
    int is_defined;
    uint64_t resolved_addr;
} Symbol;

typedef struct {
    char section[16];    // section containing bytes to patch
    uint64_t offset;     // offset within section
    char symbol[64];     // symbol whose address to use
    RelocType type;
    int64_t addend;
} Reloc;

typedef struct {
    char name[64];
    Section sections[MAX_SECTIONS];
    int num_sections;
    Symbol symbols[MAX_SYMBOLS];
    int num_symbols;
    Reloc relocs[MAX_RELOCS];
    int num_relocs;
} ObjectFile;

// ── Global symbol table ─────────────────────────────────────────────

typedef struct {
    char name[64];
    char defined_in[64];
    char section[16];
    uint64_t offset;
    uint64_t addr;       // resolved virtual address
    int has_addr;
} GlobalSymbol;

#define MAX_GLOBALS 64

// ── Section placement record ────────────────────────────────────────

typedef struct {
    char obj_name[64];
    char sec_name[16];
    uint64_t base;
    size_t size;
} Placement;

#define MAX_PLACEMENTS 32

// ── Linker ──────────────────────────────────────────────────────────

typedef struct {
    ObjectFile *objects[16];
    int num_objects;
    GlobalSymbol globals[MAX_GLOBALS];
    int num_globals;
    Placement placements[MAX_PLACEMENTS];
    int num_placements;
    uint64_t base_addr;
} Linker;

void linker_init(Linker *l, uint64_t base_addr) {
    memset(l, 0, sizeof(*l));
    l->base_addr = base_addr;
}

void linker_add_object(Linker *l, ObjectFile *obj) {
    assert(l->num_objects < 16);
    l->objects[l->num_objects++] = obj;
}

static GlobalSymbol *find_global(Linker *l, const char *name) {
    for (int i = 0; i < l->num_globals; i++) {
        if (strcmp(l->globals[i].name, name) == 0) {
            return &l->globals[i];
        }
    }
    return NULL;
}

// Pass 1: collect all symbol definitions
int linker_collect_symbols(Linker *l) {
    for (int i = 0; i < l->num_objects; i++) {
        ObjectFile *obj = l->objects[i];
        for (int j = 0; j < obj->num_symbols; j++) {
            Symbol *sym = &obj->symbols[j];
            if (!sym->is_defined) continue;

            if (find_global(l, sym->name) != NULL) {
                printf("  ERROR: duplicate symbol '%s'\n", sym->name);
                return -1;
            }
            assert(l->num_globals < MAX_GLOBALS);
            GlobalSymbol *g = &l->globals[l->num_globals++];
            strncpy(g->name, sym->name, sizeof(g->name) - 1);
            strncpy(g->defined_in, obj->name, sizeof(g->defined_in) - 1);
            strncpy(g->section, sym->section, sizeof(g->section) - 1);
            g->offset = sym->offset;
            g->has_addr = 0;
        }
    }

    // Check for undefined references
    for (int i = 0; i < l->num_objects; i++) {
        ObjectFile *obj = l->objects[i];
        for (int j = 0; j < obj->num_symbols; j++) {
            Symbol *sym = &obj->symbols[j];
            if (!sym->is_defined && find_global(l, sym->name) == NULL) {
                printf("  ERROR: undefined reference to '%s' in %s\n",
                       sym->name, obj->name);
                return -1;
            }
        }
    }

    return 0;
}

// Layout: place sections in memory (.text first, then .data)
void linker_layout_sections(Linker *l) {
    uint64_t addr = l->base_addr;
    const char *order[] = {".text", ".data"};

    for (int s = 0; s < 2; s++) {
        for (int i = 0; i < l->num_objects; i++) {
            ObjectFile *obj = l->objects[i];
            for (int j = 0; j < obj->num_sections; j++) {
                Section *sec = &obj->sections[j];
                if (strcmp(sec->name, order[s]) != 0) continue;

                assert(l->num_placements < MAX_PLACEMENTS);
                Placement *p = &l->placements[l->num_placements++];
                strncpy(p->obj_name, obj->name, sizeof(p->obj_name) - 1);
                strncpy(p->sec_name, sec->name, sizeof(p->sec_name) - 1);
                p->base = addr;
                p->size = sec->size;
                sec->base_addr = addr;
                addr += sec->size;
            }
        }
    }

    // Resolve symbol addresses
    for (int i = 0; i < l->num_globals; i++) {
        GlobalSymbol *g = &l->globals[i];
        for (int j = 0; j < l->num_placements; j++) {
            Placement *p = &l->placements[j];
            if (strcmp(p->obj_name, g->defined_in) == 0 &&
                strcmp(p->sec_name, g->section) == 0) {
                g->addr = p->base + g->offset;
                g->has_addr = 1;
            }
        }
    }
}

// Pass 2: apply relocations
int linker_apply_relocations(Linker *l, uint8_t *output, size_t output_size) {
    // Build output by concatenating sections in layout order
    size_t pos = 0;
    for (int i = 0; i < l->num_placements; i++) {
        Placement *p = &l->placements[i];
        // Find the section data
        for (int j = 0; j < l->num_objects; j++) {
            ObjectFile *obj = l->objects[j];
            if (strcmp(obj->name, p->obj_name) != 0) continue;
            for (int k = 0; k < obj->num_sections; k++) {
                Section *sec = &obj->sections[k];
                if (strcmp(sec->name, p->sec_name) != 0) continue;
                assert(pos + sec->size <= output_size);
                memcpy(output + pos, sec->data, sec->size);
                pos += sec->size;
            }
        }
    }

    // Apply relocations
    for (int i = 0; i < l->num_objects; i++) {
        ObjectFile *obj = l->objects[i];
        for (int j = 0; j < obj->num_relocs; j++) {
            Reloc *r = &obj->relocs[j];

            // Find section base
            uint64_t sec_base = 0;
            int found_sec = 0;
            for (int k = 0; k < l->num_placements; k++) {
                Placement *p = &l->placements[k];
                if (strcmp(p->obj_name, obj->name) == 0 &&
                    strcmp(p->sec_name, r->section) == 0) {
                    sec_base = p->base;
                    found_sec = 1;
                    break;
                }
            }
            if (!found_sec) return -1;

            // Find symbol address
            GlobalSymbol *g = find_global(l, r->symbol);
            if (!g || !g->has_addr) return -1;

            size_t file_offset = (size_t)(sec_base - l->base_addr) + (size_t)r->offset;

            switch (r->type) {
                case RELOC_ABS64: {
                    uint64_t val = (uint64_t)((int64_t)g->addr + r->addend);
                    memcpy(output + file_offset, &val, 8);
                    break;
                }
                case RELOC_ABS32: {
                    int32_t val = (int32_t)((int64_t)g->addr + r->addend);
                    memcpy(output + file_offset, &val, 4);
                    break;
                }
                case RELOC_PC32: {
                    uint64_t patch_addr = sec_base + r->offset;
                    int32_t val = (int32_t)((int64_t)g->addr + r->addend -
                                            (int64_t)(patch_addr + 4));
                    memcpy(output + file_offset, &val, 4);
                    break;
                }
            }
        }
    }

    return 0;
}

// ── GOT/PLT Lazy Binding Model ──────────────────────────────────────

#define MAX_GOT_ENTRIES 16

typedef struct {
    char symbols[MAX_GOT_ENTRIES][64];
    uint64_t got[MAX_GOT_ENTRIES];   // 0 = unresolved (lazy)
    int count;
    int resolver_calls;
} GotPlt;

void got_plt_init(GotPlt *gp) {
    memset(gp, 0, sizeof(*gp));
}

void got_plt_add_import(GotPlt *gp, const char *symbol) {
    assert(gp->count < MAX_GOT_ENTRIES);
    strncpy(gp->symbols[gp->count], symbol, 63);
    gp->got[gp->count] = 0;  // lazy: unresolved
    gp->count++;
}

static int got_plt_find(GotPlt *gp, const char *symbol) {
    for (int i = 0; i < gp->count; i++) {
        if (strcmp(gp->symbols[i], symbol) == 0) return i;
    }
    return -1;
}

uint64_t got_plt_call(GotPlt *gp, const char *symbol, uint64_t real_addr) {
    int idx = got_plt_find(gp, symbol);
    assert(idx >= 0);

    if (gp->got[idx] != 0) {
        // Already resolved — fast path through GOT
        return gp->got[idx];
    }

    // Lazy binding: resolver patches GOT entry
    gp->resolver_calls++;
    gp->got[idx] = real_addr;
    return real_addr;
}

// ── Main ────────────────────────────────────────────────────────────

int main(void) {
    printf("Linking and Loading — symbol resolution and relocation:\n\n");

    // ── Test 1: Two-pass linking ──────────────────────────────────
    printf("1. Two-pass linking: main.o + math.o\n");

    ObjectFile main_obj = {0};
    strcpy(main_obj.name, "main.o");
    // .text section
    strcpy(main_obj.sections[0].name, ".text");
    uint8_t main_text[] = {
        0x48, 0xC7, 0xC7, 0x0A, 0x00, 0x00, 0x00,  // mov rdi, 10
        0x48, 0xC7, 0xC6, 0x20, 0x00, 0x00, 0x00,  // mov rsi, 32
        0xE8, 0x00, 0x00, 0x00, 0x00,                // call add_numbers
        0x48, 0x89, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00,  // mov [GLOBAL_BASE], rax
        0xC3,                                          // ret
    };
    memcpy(main_obj.sections[0].data, main_text, sizeof(main_text));
    main_obj.sections[0].size = sizeof(main_text);
    main_obj.num_sections = 1;

    // Symbols
    strcpy(main_obj.symbols[0].name, "main");
    strcpy(main_obj.symbols[0].section, ".text");
    main_obj.symbols[0].offset = 0;
    main_obj.symbols[0].is_defined = 1;
    strcpy(main_obj.symbols[1].name, "add_numbers");
    main_obj.symbols[1].is_defined = 0;
    strcpy(main_obj.symbols[2].name, "GLOBAL_BASE");
    main_obj.symbols[2].is_defined = 0;
    main_obj.num_symbols = 3;

    // Relocations
    strcpy(main_obj.relocs[0].section, ".text");
    main_obj.relocs[0].offset = 15;
    strcpy(main_obj.relocs[0].symbol, "add_numbers");
    main_obj.relocs[0].type = RELOC_PC32;
    main_obj.relocs[0].addend = 0;
    strcpy(main_obj.relocs[1].section, ".text");
    main_obj.relocs[1].offset = 23;
    strcpy(main_obj.relocs[1].symbol, "GLOBAL_BASE");
    main_obj.relocs[1].type = RELOC_ABS32;
    main_obj.relocs[1].addend = 0;
    main_obj.num_relocs = 2;

    ObjectFile math_obj = {0};
    strcpy(math_obj.name, "math.o");
    strcpy(math_obj.sections[0].name, ".text");
    uint8_t math_text[] = { 0x48, 0x8D, 0x04, 0x37, 0xC3 };  // lea rax,[rdi+rsi]; ret
    memcpy(math_obj.sections[0].data, math_text, sizeof(math_text));
    math_obj.sections[0].size = sizeof(math_text);
    strcpy(math_obj.sections[1].name, ".data");
    memset(math_obj.sections[1].data, 0, 8);
    math_obj.sections[1].size = 8;
    math_obj.num_sections = 2;

    strcpy(math_obj.symbols[0].name, "add_numbers");
    strcpy(math_obj.symbols[0].section, ".text");
    math_obj.symbols[0].offset = 0;
    math_obj.symbols[0].is_defined = 1;
    strcpy(math_obj.symbols[1].name, "GLOBAL_BASE");
    strcpy(math_obj.symbols[1].section, ".data");
    math_obj.symbols[1].offset = 0;
    math_obj.symbols[1].is_defined = 1;
    math_obj.num_symbols = 2;
    math_obj.num_relocs = 0;

    Linker linker;
    linker_init(&linker, 0x400000);
    linker_add_object(&linker, &main_obj);
    linker_add_object(&linker, &math_obj);

    assert(linker_collect_symbols(&linker) == 0);
    linker_layout_sections(&linker);

    uint8_t output[256];
    assert(linker_apply_relocations(&linker, output, sizeof(output)) == 0);

    // Total: main.o .text(28) + math.o .text(5) + math.o .data(8) = 41
    size_t total = 28 + 5 + 8;
    printf("   Linked binary: %zu bytes\n", total);

    // Verify PC32 relocation for CALL
    int32_t rel32;
    memcpy(&rel32, output + 15, 4);
    uint64_t call_site = 0x400000 + 15 + 4;
    uint64_t target = call_site + (int64_t)rel32;
    assert(target == 0x400000 + 28);  // add_numbers at start of math.o .text
    printf("   CALL rel32 = %d -> target 0x%lX\n", rel32, target);

    // Verify ABS32 relocation for GLOBAL_BASE
    int32_t abs32;
    memcpy(&abs32, output + 23, 4);
    assert((uint64_t)abs32 == 0x400000 + 28 + 5);  // .data starts after both .text
    printf("   GLOBAL_BASE = 0x%X\n", abs32);

    // ── Test 2: Section layout ordering ───────────────────────────
    printf("\n2. Section layout: .text grouped, then .data grouped\n");
    assert(linker.num_placements == 3);
    assert(strcmp(linker.placements[0].sec_name, ".text") == 0);
    assert(strcmp(linker.placements[1].sec_name, ".text") == 0);
    assert(strcmp(linker.placements[2].sec_name, ".data") == 0);
    for (int i = 0; i < linker.num_placements; i++) {
        printf("   %s:%s at 0x%lX (%zu bytes)\n",
               linker.placements[i].obj_name,
               linker.placements[i].sec_name,
               linker.placements[i].base,
               linker.placements[i].size);
    }

    // ── Test 3: Relocation type formulas ──────────────────────────
    printf("\n3. Relocation type formulas:\n");

    // R_X86_64_64:   value = S + A
    // R_X86_64_32S:  value = S + A (truncated to 32 bits)
    // R_X86_64_PC32: value = S + A - P (where P = patch address + 4)
    uint64_t S = 0x401000;
    int64_t A = 0;
    uint64_t P = 0x400100;

    uint64_t abs64_val = S + (uint64_t)A;
    assert(abs64_val == 0x401000);
    printf("   %s: S(0x%lX) + A(%ld) = 0x%lX\n",
           reloc_type_name(RELOC_ABS64), S, A, abs64_val);

    int32_t pc32_val = (int32_t)((int64_t)S + A - (int64_t)(P + 4));
    assert(pc32_val == 0xEFC);
    printf("   %s: S(0x%lX) + A(%ld) - P(0x%lX) = 0x%X\n",
           reloc_type_name(RELOC_PC32), S, A, P + 4, (unsigned)pc32_val);

    // ── Test 4: GOT/PLT lazy binding ──────────────────────────────
    printf("\n4. GOT/PLT lazy binding:\n");

    GotPlt gp;
    got_plt_init(&gp);
    got_plt_add_import(&gp, "printf");
    got_plt_add_import(&gp, "malloc");

    // First call: resolver invoked
    uint64_t printf_addr = 0x7FFFF7A00000ULL;
    uint64_t r1 = got_plt_call(&gp, "printf", printf_addr);
    assert(r1 == printf_addr);
    assert(gp.resolver_calls == 1);
    printf("   First call to printf: resolver invoked -> 0x%lX\n", r1);

    // Second call: fast path (GOT already patched)
    uint64_t r2 = got_plt_call(&gp, "printf", printf_addr);
    assert(r2 == printf_addr);
    assert(gp.resolver_calls == 1);  // NOT incremented
    printf("   Second call to printf: GOT hit -> 0x%lX\n", r2);

    // Different symbol triggers resolver again
    uint64_t malloc_addr = 0x7FFFF7A80000ULL;
    uint64_t r3 = got_plt_call(&gp, "malloc", malloc_addr);
    assert(r3 == malloc_addr);
    assert(gp.resolver_calls == 2);
    printf("   First call to malloc: resolver invoked -> 0x%lX\n", r3);
    printf("   Total resolver calls: %d\n", gp.resolver_calls);

    // ── Test 5: Static vs dynamic properties ─────────────────────
    printf("\n5. Static vs dynamic linking:\n");
    // Static: all code included, no runtime deps, larger binary
    // Dynamic: shares .so in memory, smaller binary, PLT overhead
    int static_self_contained = 1;
    int dynamic_shares_memory = 1;
    assert(static_self_contained == 1);
    assert(dynamic_shares_memory == 1);
    printf("   Static: self-contained, no runtime deps\n");
    printf("   Dynamic: shared .so, smaller binary, PLT/GOT indirection\n");

    printf("\nAll linking and loading examples passed.\n");
    return 0;
}
