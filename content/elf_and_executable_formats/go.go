// Vidya — ELF and Executable Formats in Go
//
// Demonstrates ELF64 binary format structure using encoding/binary:
//   - ELF header (e_ident magic, class, endianness, type, machine)
//   - Program headers (PT_LOAD segments with permissions)
//   - Section headers (SHT types, flags, sizes)
//   - Field offset and size verification
//   - Building a minimal valid ELF header in memory
//
// ELF (Executable and Linkable Format) has two views:
//   - Linker view: sections (.text, .data, .bss, .symtab, etc.)
//   - Loader view: segments (PT_LOAD, PT_INTERP, PT_DYNAMIC, etc.)
// The kernel only reads the ELF header and program headers to load a binary.

package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"unsafe"
)

// ── ELF64 Header ─────────────────────────────────────────────────────
// First 64 bytes of every ELF file. The kernel reads this to find
// the program header table, which describes memory mappings.

type Elf64Header struct {
	Ident     [16]byte // ELF magic + class + endianness + version + OS/ABI
	Type      uint16   // ET_EXEC=2, ET_DYN=3, ET_REL=1
	Machine   uint16   // EM_X86_64=0x3E, EM_AARCH64=0xB7
	Version   uint32   // EV_CURRENT=1
	Entry     uint64   // Virtual address of _start (entry point)
	PhOff     uint64   // Program header table offset in file
	ShOff     uint64   // Section header table offset in file
	Flags     uint32   // Processor-specific flags (usually 0)
	EhSize    uint16   // Size of this header (64 bytes for ELF64)
	PhEntSize uint16   // Size of one program header entry
	PhNum     uint16   // Number of program header entries
	ShEntSize uint16   // Size of one section header entry
	ShNum     uint16   // Number of section header entries
	ShStrNdx  uint16   // Index of the section name string table
}

// ELF magic bytes: 0x7F 'E' 'L' 'F'
var elfMagic = [4]byte{0x7F, 'E', 'L', 'F'}

// ELF ident field indices
const (
	eiClass   = 4  // 1=32-bit, 2=64-bit
	eiData    = 5  // 1=little-endian, 2=big-endian
	eiVersion = 6  // 1=EV_CURRENT
	eiOSABI   = 7  // 0=ELFOSABI_NONE (System V)
)

// ELF type constants
const (
	etNone = 0 // No file type
	etRel  = 1 // Relocatable (.o)
	etExec = 2 // Executable
	etDyn  = 3 // Shared object / PIE
	etCore = 4 // Core dump
)

// ELF machine constants
const (
	emX86_64  = 0x3E
	emAArch64 = 0xB7
	emRISCV   = 0xF3
)

// ── Program Header ───────────────────────────────────────────────────
// Describes a segment — the loader's view of the binary.
// PT_LOAD segments are mapped into memory with mmap().

type Elf64Phdr struct {
	Type   uint32 // Segment type (PT_LOAD, PT_INTERP, etc.)
	Flags  uint32 // Permissions: PF_R=4, PF_W=2, PF_X=1
	Offset uint64 // Offset of segment data in file
	VAddr  uint64 // Virtual address in memory
	PAddr  uint64 // Physical address (usually same as VAddr)
	FileSz uint64 // Size of segment in file (can be < MemSz for .bss)
	MemSz  uint64 // Size of segment in memory
	Align  uint64 // Alignment (usually page size: 0x1000)
}

// Program header types
const (
	ptNull    = 0 // Unused entry
	ptLoad    = 1 // Loadable segment (mapped by kernel)
	ptDynamic = 2 // Dynamic linking info
	ptInterp  = 3 // Path to dynamic linker (/lib64/ld-linux-x86-64.so.2)
	ptNote    = 4 // Auxiliary info (build-id, ABI version)
	ptPhdr    = 6 // Program header table itself
	ptGnuEhFrame = 0x6474E550 // Exception handling frame
	ptGnuStack   = 0x6474E551 // Stack executability (NX bit)
	ptGnuRelro   = 0x6474E552 // Read-only after relocation (RELRO)
)

// Permission flags
const (
	pfX = 1 // Execute
	pfW = 2 // Write
	pfR = 4 // Read
)

func permString(flags uint32) string {
	r, w, x := "-", "-", "-"
	if flags&pfR != 0 {
		r = "r"
	}
	if flags&pfW != 0 {
		w = "w"
	}
	if flags&pfX != 0 {
		x = "x"
	}
	return r + w + x
}

// ── Section Header ───────────────────────────────────────────────────
// Describes a section — the linker/tooling view of the binary.
// Section headers are optional for execution (the kernel ignores them).

type Elf64Shdr struct {
	Name      uint32 // Offset into section name string table (.shstrtab)
	Type      uint32 // Section type (SHT_PROGBITS, SHT_SYMTAB, etc.)
	Flags     uint64 // SHF_WRITE, SHF_ALLOC, SHF_EXECINSTR
	Addr      uint64 // Virtual address if loaded
	Offset    uint64 // Offset in file
	Size      uint64 // Section size in bytes
	Link      uint32 // Section type-dependent link
	Info      uint32 // Section type-dependent info
	AddrAlign uint64 // Alignment constraint
	EntSize   uint64 // Entry size for fixed-size entries (e.g., symtab)
}

// Section types
const (
	shtNull     = 0  // Inactive (first entry in section table)
	shtProgbits = 1  // Program data (.text, .data, .rodata)
	shtSymtab   = 2  // Symbol table
	shtStrtab   = 3  // String table
	shtRela     = 4  // Relocations with addends
	shtNobits   = 8  // No file data (.bss — zero-initialized)
	shtNote     = 7  // Note section (build-id, etc.)
	shtDynamic  = 6  // Dynamic linking information
	shtDynsym   = 11 // Dynamic symbol table
)

// Section flags
const (
	shfWrite     = 0x1 // Writable at runtime
	shfAlloc     = 0x2 // Occupies memory at runtime
	shfExecInstr = 0x4 // Contains executable instructions
)

// ── Build a Minimal ELF Header ───────────────────────────────────────

func buildMinimalELF() []byte {
	hdr := Elf64Header{
		Type:      etExec,
		Machine:   emX86_64,
		Version:   1,
		Entry:     0x401000, // typical .text start
		PhOff:     64,       // program headers right after ELF header
		ShOff:     0,        // no section headers (stripped binary)
		EhSize:    64,
		PhEntSize: 56,       // sizeof(Elf64Phdr)
		PhNum:     1,        // one PT_LOAD segment
		ShEntSize: 64,       // sizeof(Elf64Shdr)
		ShNum:     0,
		ShStrNdx:  0,
	}

	// Fill ident
	copy(hdr.Ident[0:4], elfMagic[:])
	hdr.Ident[eiClass] = 2   // ELFCLASS64
	hdr.Ident[eiData] = 1    // ELFDATA2LSB (little-endian)
	hdr.Ident[eiVersion] = 1 // EV_CURRENT
	hdr.Ident[eiOSABI] = 0   // ELFOSABI_NONE (System V)

	// One PT_LOAD segment: read+execute for .text
	phdr := Elf64Phdr{
		Type:   ptLoad,
		Flags:  pfR | pfX,
		Offset: 0x1000, // file offset (page-aligned)
		VAddr:  0x401000,
		PAddr:  0x401000,
		FileSz: 7,      // tiny program: just syscall exit(0)
		MemSz:  7,
		Align:  0x1000,
	}

	var buf bytes.Buffer
	binary.Write(&buf, binary.LittleEndian, hdr)
	binary.Write(&buf, binary.LittleEndian, phdr)
	return buf.Bytes()
}

// ── Field Offset/Size Verification ───────────────────────────────────

type fieldInfo struct {
	name   string
	offset uintptr
	size   uintptr
}

func main() {
	fmt.Println("ELF and Executable Formats — Go demonstration:\n")

	// ── 1. ELF header structure and sizes ────────────────────────────
	fmt.Println("1. ELF64 header structure:")

	hdrSize := unsafe.Sizeof(Elf64Header{})
	assert(hdrSize == 64, fmt.Sprintf("ELF64 header must be 64 bytes, got %d", hdrSize))
	fmt.Printf("  sizeof(Elf64Header) = %d bytes\n", hdrSize)

	// Verify critical field offsets
	var hdr Elf64Header
	hdrBase := unsafe.Pointer(&hdr)

	fields := []fieldInfo{
		{"e_ident", 0, 16},
		{"e_type", unsafe.Offsetof(hdr.Type), unsafe.Sizeof(hdr.Type)},
		{"e_machine", unsafe.Offsetof(hdr.Machine), unsafe.Sizeof(hdr.Machine)},
		{"e_version", unsafe.Offsetof(hdr.Version), unsafe.Sizeof(hdr.Version)},
		{"e_entry", unsafe.Offsetof(hdr.Entry), unsafe.Sizeof(hdr.Entry)},
		{"e_phoff", unsafe.Offsetof(hdr.PhOff), unsafe.Sizeof(hdr.PhOff)},
		{"e_shoff", unsafe.Offsetof(hdr.ShOff), unsafe.Sizeof(hdr.ShOff)},
		{"e_flags", unsafe.Offsetof(hdr.Flags), unsafe.Sizeof(hdr.Flags)},
		{"e_ehsize", unsafe.Offsetof(hdr.EhSize), unsafe.Sizeof(hdr.EhSize)},
		{"e_phentsize", unsafe.Offsetof(hdr.PhEntSize), unsafe.Sizeof(hdr.PhEntSize)},
		{"e_phnum", unsafe.Offsetof(hdr.PhNum), unsafe.Sizeof(hdr.PhNum)},
		{"e_shentsize", unsafe.Offsetof(hdr.ShEntSize), unsafe.Sizeof(hdr.ShEntSize)},
		{"e_shnum", unsafe.Offsetof(hdr.ShNum), unsafe.Sizeof(hdr.ShNum)},
		{"e_shstrndx", unsafe.Offsetof(hdr.ShStrNdx), unsafe.Sizeof(hdr.ShStrNdx)},
	}

	fmt.Printf("  %-14s %6s %4s\n", "Field", "Offset", "Size")
	fmt.Printf("  %-14s %6s %4s\n", "-----", "------", "----")
	for _, f := range fields {
		fmt.Printf("  %-14s %6d %4d\n", f.name, f.offset, f.size)
	}

	// Verify specific offsets that are ABI-critical
	assert(unsafe.Offsetof(hdr.Type) == 16, "e_type at offset 16")
	assert(unsafe.Offsetof(hdr.Machine) == 18, "e_machine at offset 18")
	assert(unsafe.Offsetof(hdr.Entry) == 24, "e_entry at offset 24")
	assert(unsafe.Offsetof(hdr.PhOff) == 32, "e_phoff at offset 32")
	assert(unsafe.Offsetof(hdr.ShOff) == 40, "e_shoff at offset 40")

	_ = hdrBase // used to establish the base for offset verification

	// ── 2. Program header structure ──────────────────────────────────
	fmt.Println("\n2. Program header (Elf64_Phdr):")

	phdrSize := unsafe.Sizeof(Elf64Phdr{})
	assert(phdrSize == 56, fmt.Sprintf("Elf64_Phdr must be 56 bytes, got %d", phdrSize))
	fmt.Printf("  sizeof(Elf64_Phdr) = %d bytes\n", phdrSize)

	var phdr Elf64Phdr
	phdrFields := []fieldInfo{
		{"p_type", unsafe.Offsetof(phdr.Type), unsafe.Sizeof(phdr.Type)},
		{"p_flags", unsafe.Offsetof(phdr.Flags), unsafe.Sizeof(phdr.Flags)},
		{"p_offset", unsafe.Offsetof(phdr.Offset), unsafe.Sizeof(phdr.Offset)},
		{"p_vaddr", unsafe.Offsetof(phdr.VAddr), unsafe.Sizeof(phdr.VAddr)},
		{"p_paddr", unsafe.Offsetof(phdr.PAddr), unsafe.Sizeof(phdr.PAddr)},
		{"p_filesz", unsafe.Offsetof(phdr.FileSz), unsafe.Sizeof(phdr.FileSz)},
		{"p_memsz", unsafe.Offsetof(phdr.MemSz), unsafe.Sizeof(phdr.MemSz)},
		{"p_align", unsafe.Offsetof(phdr.Align), unsafe.Sizeof(phdr.Align)},
	}

	fmt.Printf("  %-12s %6s %4s\n", "Field", "Offset", "Size")
	fmt.Printf("  %-12s %6s %4s\n", "-----", "------", "----")
	for _, f := range phdrFields {
		fmt.Printf("  %-12s %6d %4d\n", f.name, f.offset, f.size)
	}

	// ELF64 quirk: p_flags moved to offset 4 (after p_type),
	// unlike ELF32 where it's near the end
	assert(unsafe.Offsetof(phdr.Flags) == 4, "p_flags at offset 4 in ELF64")

	// ── 3. Section header structure ──────────────────────────────────
	fmt.Println("\n3. Section header (Elf64_Shdr):")

	shdrSize := unsafe.Sizeof(Elf64Shdr{})
	assert(shdrSize == 64, fmt.Sprintf("Elf64_Shdr must be 64 bytes, got %d", shdrSize))
	fmt.Printf("  sizeof(Elf64_Shdr) = %d bytes\n", shdrSize)

	// ── 4. Segment types ─────────────────────────────────────────────
	fmt.Println("\n4. Segment types (program header p_type):")

	segTypes := []struct {
		value uint32
		name  string
		desc  string
	}{
		{ptNull, "PT_NULL", "Unused entry"},
		{ptLoad, "PT_LOAD", "Loadable segment (mapped by kernel)"},
		{ptDynamic, "PT_DYNAMIC", "Dynamic linking info (.dynamic section)"},
		{ptInterp, "PT_INTERP", "Path to dynamic linker"},
		{ptNote, "PT_NOTE", "Auxiliary info (build-id, ABI version)"},
		{ptPhdr, "PT_PHDR", "Program header table itself"},
		{ptGnuStack, "PT_GNU_STACK", "Stack permissions (NX enforcement)"},
		{ptGnuRelro, "PT_GNU_RELRO", "Read-only after relocation"},
	}

	for _, st := range segTypes {
		fmt.Printf("  0x%08x  %-14s  %s\n", st.value, st.name, st.desc)
	}

	// ── 5. Standard sections ─────────────────────────────────────────
	fmt.Println("\n5. Standard ELF sections:")

	type sectionDesc struct {
		name  string
		stype uint32
		flags uint64
		desc  string
	}

	stdSections := []sectionDesc{
		{".text", shtProgbits, shfAlloc | shfExecInstr, "Executable code"},
		{".rodata", shtProgbits, shfAlloc, "Read-only data"},
		{".data", shtProgbits, shfAlloc | shfWrite, "Initialized read-write data"},
		{".bss", shtNobits, shfAlloc | shfWrite, "Uninitialized data (no file space)"},
		{".symtab", shtSymtab, 0, "Symbol table"},
		{".strtab", shtStrtab, 0, "String table (symbol names)"},
		{".shstrtab", shtStrtab, 0, "Section name string table"},
		{".rela.text", shtRela, 0, "Relocations for .text"},
		{".dynamic", shtDynamic, shfAlloc | shfWrite, "Dynamic linking info"},
		{".note", shtNote, shfAlloc, "Build metadata (build-id)"},
	}

	fmt.Printf("  %-14s %-6s %-5s %s\n", "Section", "Type", "Flags", "Description")
	fmt.Printf("  %-14s %-6s %-5s %s\n", "-------", "----", "-----", "-----------")
	for _, s := range stdSections {
		flagStr := ""
		if s.flags&shfAlloc != 0 {
			flagStr += "A"
		}
		if s.flags&shfWrite != 0 {
			flagStr += "W"
		}
		if s.flags&shfExecInstr != 0 {
			flagStr += "X"
		}
		if flagStr == "" {
			flagStr = "-"
		}
		fmt.Printf("  %-14s %-6d %-5s %s\n", s.name, s.stype, flagStr, s.desc)
	}

	// ── 6. Build and verify a minimal ELF ────────────────────────────
	fmt.Println("\n6. Building a minimal ELF64 binary in memory:")

	elfBytes := buildMinimalELF()
	fmt.Printf("  Generated %d bytes (header + 1 program header)\n", len(elfBytes))

	// Verify magic bytes
	assert(elfBytes[0] == 0x7F, "magic byte 0")
	assert(elfBytes[1] == 'E', "magic byte 1")
	assert(elfBytes[2] == 'L', "magic byte 2")
	assert(elfBytes[3] == 'F', "magic byte 3")
	fmt.Printf("  Magic: %02x %c%c%c\n", elfBytes[0], elfBytes[1], elfBytes[2], elfBytes[3])

	// Verify class and endianness
	assert(elfBytes[eiClass] == 2, "ELFCLASS64")
	assert(elfBytes[eiData] == 1, "ELFDATA2LSB (little-endian)")
	fmt.Printf("  Class: %d (64-bit), Data: %d (little-endian)\n",
		elfBytes[eiClass], elfBytes[eiData])

	// Parse back the header to verify roundtrip
	var parsed Elf64Header
	reader := bytes.NewReader(elfBytes)
	err := binary.Read(reader, binary.LittleEndian, &parsed)
	assert(err == nil, fmt.Sprintf("parse error: %v", err))

	assert(parsed.Type == etExec, "type must be ET_EXEC")
	assert(parsed.Machine == emX86_64, "machine must be EM_X86_64")
	assert(parsed.Entry == 0x401000, "entry point must be 0x401000")
	assert(parsed.PhOff == 64, "phoff must be 64")
	assert(parsed.EhSize == 64, "ehsize must be 64")
	assert(parsed.PhEntSize == 56, "phentsize must be 56")
	assert(parsed.PhNum == 1, "phnum must be 1")

	fmt.Printf("  Type:    %d (ET_EXEC)\n", parsed.Type)
	fmt.Printf("  Machine: 0x%02x (EM_X86_64)\n", parsed.Machine)
	fmt.Printf("  Entry:   0x%x\n", parsed.Entry)
	fmt.Printf("  PhOff:   %d (program headers at byte 64)\n", parsed.PhOff)
	fmt.Printf("  PhNum:   %d program header(s)\n", parsed.PhNum)

	// Parse the program header
	var parsedPhdr Elf64Phdr
	err = binary.Read(reader, binary.LittleEndian, &parsedPhdr)
	assert(err == nil, fmt.Sprintf("phdr parse error: %v", err))
	assert(parsedPhdr.Type == ptLoad, "segment must be PT_LOAD")
	assert(parsedPhdr.Flags == pfR|pfX, "segment must be r-x")
	assert(parsedPhdr.VAddr == 0x401000, "vaddr must match entry")
	assert(parsedPhdr.Align == 0x1000, "alignment must be page size")

	fmt.Printf("  Segment: PT_LOAD, %s, vaddr=0x%x, align=0x%x\n",
		permString(parsedPhdr.Flags), parsedPhdr.VAddr, parsedPhdr.Align)

	// ── 7. Section vs segment duality ────────────────────────────────
	fmt.Println("\n7. Section vs segment duality:")
	fmt.Println("  Sections (.text, .data, .bss) = linker's view")
	fmt.Println("    - Organize code and data by type")
	fmt.Println("    - Used for symbol resolution, relocation, linking")
	fmt.Println("    - Optional for execution (strip -s removes them)")
	fmt.Println()
	fmt.Println("  Segments (PT_LOAD) = loader's view")
	fmt.Println("    - Describe memory mappings with permissions")
	fmt.Println("    - Multiple sections map into one segment:")
	fmt.Println("      .text + .rodata → PT_LOAD (r-x)")
	fmt.Println("      .data + .bss   → PT_LOAD (rw-)")
	fmt.Println("    - Required for execution (kernel reads these)")

	// ── 8. Common ELF machine types ──────────────────────────────────
	fmt.Println("\n8. Common ELF machine types:")
	machines := []struct {
		value uint16
		name  string
	}{
		{emX86_64, "EM_X86_64 (AMD64)"},
		{emAArch64, "EM_AARCH64 (ARM 64-bit)"},
		{emRISCV, "EM_RISCV (RISC-V)"},
		{0x03, "EM_386 (x86 32-bit)"},
		{0x28, "EM_ARM (ARM 32-bit)"},
	}
	for _, m := range machines {
		fmt.Printf("  0x%04x  %s\n", m.value, m.name)
	}

	// ── 9. .bss section behavior ─────────────────────────────────────
	fmt.Println("\n9. .bss section — zero-initialized, no file space:")
	fmt.Println("  .bss has SHT_NOBITS type — no bytes stored in the ELF file.")
	fmt.Println("  The loader allocates MemSz bytes and zeros them.")
	fmt.Println("  This is why FileSz < MemSz for the data segment:")
	fmt.Println("    FileSz covers .data only")
	fmt.Println("    MemSz  covers .data + .bss")
	fmt.Println("  A 1GB zero-initialized array adds 0 bytes to the file.")

	// Demonstrate: data segment with .bss
	dataPhdr := Elf64Phdr{
		Type:   ptLoad,
		Flags:  pfR | pfW,
		Offset: 0x2000,
		VAddr:  0x402000,
		PAddr:  0x402000,
		FileSz: 256,       // .data: 256 bytes of initialized data
		MemSz:  256 + 4096, // .data + .bss: 4096 bytes of zeros
		Align:  0x1000,
	}
	bssSize := dataPhdr.MemSz - dataPhdr.FileSz
	fmt.Printf("  Example: FileSz=%d, MemSz=%d, .bss=%d bytes (zero-filled)\n",
		dataPhdr.FileSz, dataPhdr.MemSz, bssSize)
	assert(bssSize == 4096, "bss size must be 4096")

	fmt.Println("\nAll ELF and executable format examples passed.")
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}
