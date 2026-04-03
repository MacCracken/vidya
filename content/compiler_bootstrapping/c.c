// Compiler Bootstrapping — C Implementation
//
// Demonstrates the core bootstrap pattern: a two-pass assembler.
// This is how early C compilers bootstrapped from assembly.
// The seed reads tokens, collects labels, then emits machine code.
//
// Historical note: the original C compiler was written in B,
// B was written in TMG, TMG was written in assembly.
// Each stage only needed to compile the next stage's subset.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LABELS 256
#define MAX_CODE   4096

typedef struct {
    char name[64];
    int offset;
} Label;

typedef enum {
    OP_LOAD_IMM,  // load immediate into register
    OP_ADD,       // add two registers
    OP_JUMP,      // jump to label
    OP_LABEL,     // label definition (no code emitted)
    OP_HALT       // stop execution
} OpCode;

typedef struct {
    OpCode op;
    int reg_dst;
    int reg_src;
    long value;
    char label[64];
} Instruction;

// Pass 1: collect label offsets
int collect_labels(Instruction *insts, int count, Label *labels) {
    int nlabels = 0;
    int offset = 0;
    for (int i = 0; i < count; i++) {
        switch (insts[i].op) {
            case OP_LABEL:
                strncpy(labels[nlabels].name, insts[i].label, 63);
                labels[nlabels].offset = offset;
                nlabels++;
                break;
            case OP_LOAD_IMM: offset += 10; break;  // REX.W + opcode + imm64
            case OP_ADD:      offset += 3;  break;  // REX.W + opcode + ModR/M
            case OP_JUMP:     offset += 5;  break;  // opcode + rel32
            case OP_HALT:     offset += 1;  break;
        }
    }
    return nlabels;
}

int find_label(Label *labels, int nlabels, const char *name) {
    for (int i = 0; i < nlabels; i++) {
        if (strcmp(labels[i].name, name) == 0)
            return labels[i].offset;
    }
    fprintf(stderr, "undefined label: %s\n", name);
    exit(1);
}

// Pass 2: emit machine code with resolved addresses
int emit_code(Instruction *insts, int count, Label *labels, int nlabels,
              unsigned char *code) {
    int offset = 0;
    for (int i = 0; i < count; i++) {
        switch (insts[i].op) {
            case OP_LOAD_IMM: {
                code[offset++] = 0x48; // REX.W
                code[offset++] = 0xB8 + (unsigned char)insts[i].reg_dst;
                // little-endian imm64
                long v = insts[i].value;
                for (int b = 0; b < 8; b++) {
                    code[offset++] = (unsigned char)(v & 0xFF);
                    v >>= 8;
                }
                break;
            }
            case OP_ADD:
                code[offset++] = 0x48;
                code[offset++] = 0x01;
                code[offset++] = 0xC0
                    | ((unsigned char)insts[i].reg_src << 3)
                    | (unsigned char)insts[i].reg_dst;
                break;
            case OP_JUMP: {
                int target = find_label(labels, nlabels, insts[i].label);
                int rel = target - (offset + 5);
                code[offset++] = 0xE9;
                // little-endian rel32
                code[offset++] = (unsigned char)(rel & 0xFF);
                code[offset++] = (unsigned char)((rel >> 8) & 0xFF);
                code[offset++] = (unsigned char)((rel >> 16) & 0xFF);
                code[offset++] = (unsigned char)((rel >> 24) & 0xFF);
                break;
            }
            case OP_LABEL:
                break; // no bytes
            case OP_HALT:
                code[offset++] = 0xF4;
                break;
        }
    }
    return offset;
}

int main(void) {
    Instruction program[] = {
        { .op = OP_LABEL,    .label = "start" },
        { .op = OP_LOAD_IMM, .reg_dst = 0, .value = 10 },
        { .op = OP_LOAD_IMM, .reg_dst = 1, .value = 32 },
        { .op = OP_ADD,      .reg_dst = 0, .reg_src = 1 },
        { .op = OP_JUMP,     .label = "start" },
        { .op = OP_HALT },
    };
    int count = sizeof(program) / sizeof(program[0]);

    Label labels[MAX_LABELS];
    int nlabels = collect_labels(program, count, labels);

    unsigned char code[MAX_CODE];
    int code_size = emit_code(program, count, labels, nlabels, code);

    printf("Labels: ");
    for (int i = 0; i < nlabels; i++)
        printf("%s=%d ", labels[i].name, labels[i].offset);
    printf("\nCode (%d bytes): ", code_size);
    for (int i = 0; i < code_size; i++)
        printf("%02X ", code[i]);
    printf("\nBootstrap chain: source -> labels -> machine code\n");

    return 0;
}
