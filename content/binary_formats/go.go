// Vidya — Binary Formats in Go
//
// Builds a minimal ELF binary in memory, models PE and Mach-O headers,
// and compares all three executable formats. Demonstrates:
//   1. ELF64 header and program header construction as raw bytes
//   2. Magic number detection for ELF, PE, and Mach-O
//   3. PE COFF header and optional header layout
//   4. Mach-O header and load command structure
//   5. Format comparison — field sizes, alignment, entry points
//
// Go can't produce raw structs with exact layout like C, so we work
// with byte slices and encoding/binary — the same approach you'd use
// to write a linker or binary analysis tool in Go.

package main

import (
	"encoding/binary"
	"fmt"
)

func main() {
	testElfMagicAndConstants()
	testBuildMinimalElf()
	testElfHeaderParsing()
	testPEHeaderLayout()
	testMachOHeaderLayout()
	testFormatDetection()
	testFormatComparison()

	fmt.Println("All binary format examples passed.")
}

// ── ELF Constants ────────────────────────────────────────────────────

const (
	EI_NIDENT = 16
	ELFCLASS64  = 2
	ELFDATA2LSB = 1
	EV_CURRENT  = 1
	ET_EXEC     = 2
	EM_X86_64   = 62

	PT_NULL    = 0
	PT_LOAD    = 1
	PT_DYNAMIC = 2
	PT_INTERP  = 3
	PT_PHDR    = 6

	PF_X = 1
	PF_W = 2
	PF_R = 4

	ELF_EHDR_SIZE = 64
	ELF_PHDR_SIZE = 56
)

// ── ELF64 Header (modeled as Go struct for readability) ──────────────
// The real layout is defined by the ELF spec. We serialize manually
// to control byte order and alignment exactly.

type Elf64Ehdr struct {
	Ident     [EI_NIDENT]byte
	Type      uint16
	Machine   uint16
	Version   uint32
	Entry     uint64
	Phoff     uint64
	Shoff     uint64
	Flags     uint32
	Ehsize    uint16
	Phentsize uint16
	Phnum     uint16
	Shentsize uint16
	Shnum     uint16
	Shstrndx  uint16
}

type Elf64Phdr struct {
	Type   uint32
	Flags  uint32
	Offset uint64
	Vaddr  uint64
	Paddr  uint64
	Filesz uint64
	Memsz  uint64
	Align  uint64
}

func (e *Elf64Ehdr) Serialize() []byte {
	buf := make([]byte, ELF_EHDR_SIZE)
	copy(buf[0:EI_NIDENT], e.Ident[:])
	binary.LittleEndian.PutUint16(buf[16:], e.Type)
	binary.LittleEndian.PutUint16(buf[18:], e.Machine)
	binary.LittleEndian.PutUint32(buf[20:], e.Version)
	binary.LittleEndian.PutUint64(buf[24:], e.Entry)
	binary.LittleEndian.PutUint64(buf[32:], e.Phoff)
	binary.LittleEndian.PutUint64(buf[40:], e.Shoff)
	binary.LittleEndian.PutUint32(buf[48:], e.Flags)
	binary.LittleEndian.PutUint16(buf[52:], e.Ehsize)
	binary.LittleEndian.PutUint16(buf[54:], e.Phentsize)
	binary.LittleEndian.PutUint16(buf[56:], e.Phnum)
	binary.LittleEndian.PutUint16(buf[58:], e.Shentsize)
	binary.LittleEndian.PutUint16(buf[60:], e.Shnum)
	binary.LittleEndian.PutUint16(buf[62:], e.Shstrndx)
	return buf
}

func (p *Elf64Phdr) Serialize() []byte {
	buf := make([]byte, ELF_PHDR_SIZE)
	binary.LittleEndian.PutUint32(buf[0:], p.Type)
	binary.LittleEndian.PutUint32(buf[4:], p.Flags)
	binary.LittleEndian.PutUint64(buf[8:], p.Offset)
	binary.LittleEndian.PutUint64(buf[16:], p.Vaddr)
	binary.LittleEndian.PutUint64(buf[24:], p.Paddr)
	binary.LittleEndian.PutUint64(buf[32:], p.Filesz)
	binary.LittleEndian.PutUint64(buf[40:], p.Memsz)
	binary.LittleEndian.PutUint64(buf[48:], p.Align)
	return buf
}

// ── Build Minimal ELF ────────────────────────────────────────────────
// Structure: 64-byte ELF header + 56-byte program header + 9 bytes code
// Total: 129 bytes. This is a static binary — no libc, no dynamic linker.

func buildMinimalElf() []byte {
	baseAddr := uint64(0x400000)
	codeOffset := uint64(ELF_EHDR_SIZE + ELF_PHDR_SIZE) // 120

	// Machine code: exit(0) on x86_64 Linux
	//   xor edi, edi     (31 FF)     — exit code 0
	//   mov eax, 60      (B8 3C ...) — syscall number for exit
	//   syscall           (0F 05)     — invoke kernel
	code := []byte{0x31, 0xFF, 0xB8, 0x3C, 0x00, 0x00, 0x00, 0x0F, 0x05}
	totalSize := uint64(len(code)) + codeOffset
	entry := baseAddr + codeOffset

	ehdr := Elf64Ehdr{
		Type:      ET_EXEC,
		Machine:   EM_X86_64,
		Version:   EV_CURRENT,
		Entry:     entry,
		Phoff:     ELF_EHDR_SIZE,
		Ehsize:    ELF_EHDR_SIZE,
		Phentsize: ELF_PHDR_SIZE,
		Phnum:     1,
		Shentsize: 64,
	}
	ehdr.Ident[0] = 0x7F
	ehdr.Ident[1] = 'E'
	ehdr.Ident[2] = 'L'
	ehdr.Ident[3] = 'F'
	ehdr.Ident[4] = ELFCLASS64
	ehdr.Ident[5] = ELFDATA2LSB
	ehdr.Ident[6] = EV_CURRENT

	phdr := Elf64Phdr{
		Type:   PT_LOAD,
		Flags:  PF_R | PF_X,
		Offset: 0,
		Vaddr:  baseAddr,
		Paddr:  baseAddr,
		Filesz: totalSize,
		Memsz:  totalSize,
		Align:  0x1000,
	}

	result := make([]byte, 0, totalSize)
	result = append(result, ehdr.Serialize()...)
	result = append(result, phdr.Serialize()...)
	result = append(result, code...)
	return result
}

func testElfMagicAndConstants() {
	fmt.Println("1. ELF magic and constants:")

	// ELF magic: 0x7F 'E' 'L' 'F'
	magic := [4]byte{0x7F, 'E', 'L', 'F'}
	assert(magic[0] == 0x7F, "magic byte 0")
	assert(magic[1] == 0x45, "magic byte 1 (E)")
	assert(magic[2] == 0x4C, "magic byte 2 (L)")
	assert(magic[3] == 0x46, "magic byte 3 (F)")

	// Header sizes — fixed by the spec
	assert(ELF_EHDR_SIZE == 64, "ehdr size")
	assert(ELF_PHDR_SIZE == 56, "phdr size")

	fmt.Printf("   Magic: %02X %c %c %c\n", magic[0], magic[1], magic[2], magic[3])
	fmt.Printf("   ELF header:     %d bytes\n", ELF_EHDR_SIZE)
	fmt.Printf("   Program header: %d bytes\n", ELF_PHDR_SIZE)
}

func testBuildMinimalElf() {
	fmt.Println("\n2. Minimal ELF binary (exit(0)):")

	elf := buildMinimalElf()
	assert(len(elf) == 129, "total size 64+56+9=129")

	// Verify magic
	assert(elf[0] == 0x7F && elf[1] == 'E' && elf[2] == 'L' && elf[3] == 'F', "magic")
	assert(elf[4] == ELFCLASS64, "64-bit class")
	assert(elf[5] == ELFDATA2LSB, "little-endian")

	// Verify entry point at offset 24 (little-endian u64)
	entry := binary.LittleEndian.Uint64(elf[24:32])
	assert(entry == 0x400000+120, "entry point")

	// Verify program header at offset 64
	pType := binary.LittleEndian.Uint32(elf[64:68])
	assert(pType == PT_LOAD, "segment type")
	pFlags := binary.LittleEndian.Uint32(elf[68:72])
	assert(pFlags == PF_R|PF_X, "segment flags R+X")

	// Verify code bytes at offset 120
	assert(elf[120] == 0x31 && elf[121] == 0xFF, "xor edi,edi")
	assert(elf[127] == 0x0F && elf[128] == 0x05, "syscall")

	fmt.Printf("   Size: %d bytes (64 ehdr + 56 phdr + 9 code)\n", len(elf))
	fmt.Printf("   Entry: 0x%X\n", entry)
	fmt.Println("   1 PT_LOAD segment (R+X), no sections, no symbols")
}

func testElfHeaderParsing() {
	fmt.Println("\n3. ELF header field parsing:")

	elf := buildMinimalElf()

	// Parse header fields from raw bytes — this is what readelf does
	eType := binary.LittleEndian.Uint16(elf[16:18])
	machine := binary.LittleEndian.Uint16(elf[18:20])
	version := binary.LittleEndian.Uint32(elf[20:24])
	entry := binary.LittleEndian.Uint64(elf[24:32])
	phoff := binary.LittleEndian.Uint64(elf[32:40])
	phnum := binary.LittleEndian.Uint16(elf[56:58])

	assert(eType == ET_EXEC, "type ET_EXEC")
	assert(machine == EM_X86_64, "machine x86_64")
	assert(version == EV_CURRENT, "version current")
	assert(entry == 0x400078, "entry address")
	assert(phoff == 64, "phoff after ehdr")
	assert(phnum == 1, "one program header")

	fmt.Printf("   Type:    ET_EXEC (%d)\n", eType)
	fmt.Printf("   Machine: EM_X86_64 (%d)\n", machine)
	fmt.Printf("   Entry:   0x%X\n", entry)
	fmt.Printf("   Phoff:   %d (program headers start here)\n", phoff)
	fmt.Printf("   Phnum:   %d\n", phnum)
}

// ── PE (Portable Executable) Header Layout ───────────────────────────
// Windows executables: DOS stub + PE signature + COFF header + optional header

type PESignature [4]byte // "PE\x00\x00"

type CoffHeader struct {
	Machine              uint16
	NumberOfSections     uint16
	TimeDateStamp        uint32
	PointerToSymbolTable uint32
	NumberOfSymbols      uint32
	SizeOfOptionalHeader uint16
	Characteristics      uint16
}

const (
	PE_MAGIC         = 0x00004550 // "PE\0\0" as little-endian uint32
	IMAGE_FILE_MACHINE_AMD64 = 0x8664
	IMAGE_FILE_MACHINE_ARM64 = 0xAA64
	COFF_HEADER_SIZE = 20
	PE_OPT_HDR64_MAGIC = 0x020B // PE32+ (64-bit)
)

func testPEHeaderLayout() {
	fmt.Println("\n4. PE (Windows) header layout:")

	// DOS header magic: "MZ" (0x4D5A) — Mark Zbikowski
	dosMagic := [2]byte{'M', 'Z'}
	assert(dosMagic[0] == 0x4D, "MZ byte 0")
	assert(dosMagic[1] == 0x5A, "MZ byte 1")

	// Build PE signature
	var peSig [4]byte
	binary.LittleEndian.PutUint32(peSig[:], PE_MAGIC)
	assert(peSig[0] == 'P' && peSig[1] == 'E', "PE signature")
	assert(peSig[2] == 0 && peSig[3] == 0, "PE null padding")

	// COFF header for x86_64
	coff := CoffHeader{
		Machine:              IMAGE_FILE_MACHINE_AMD64,
		NumberOfSections:     3,  // .text, .rdata, .data
		SizeOfOptionalHeader: 240, // PE32+ optional header
		Characteristics:      0x0022, // EXECUTABLE | LARGE_ADDRESS_AWARE
	}
	assert(coff.Machine == 0x8664, "AMD64 machine type")
	assert(COFF_HEADER_SIZE == 20, "COFF header is 20 bytes")

	// PE optional header magic distinguishes PE32 from PE32+
	assert(PE_OPT_HDR64_MAGIC == 0x020B, "PE32+ magic")

	fmt.Printf("   DOS magic:       MZ (0x%02X%02X)\n", dosMagic[0], dosMagic[1])
	fmt.Printf("   PE signature:    %s (0x%08X)\n", string(peSig[:2]), PE_MAGIC)
	fmt.Printf("   COFF header:     %d bytes\n", COFF_HEADER_SIZE)
	fmt.Printf("   Machine:         0x%04X (AMD64)\n", coff.Machine)
	fmt.Printf("   Sections:        %d (.text, .rdata, .data)\n", coff.NumberOfSections)
	fmt.Printf("   Optional header: %d bytes (PE32+)\n", coff.SizeOfOptionalHeader)
}

// ── Mach-O Header Layout ─────────────────────────────────────────────
// macOS/iOS executables: header + load commands + segments

const (
	MH_MAGIC_64   = 0xFEEDFACF // 64-bit Mach-O
	MH_CIGAM_64   = 0xCFFAEDFE // 64-bit Mach-O, byte-swapped
	MH_EXECUTE    = 0x2         // executable type
	CPU_TYPE_X86_64  = 0x01000007
	CPU_TYPE_ARM64   = 0x0100000C
	MACHO_HDR_SIZE   = 32 // Mach-O 64-bit header
)

type MachOHeader struct {
	Magic      uint32
	CpuType    uint32
	CpuSubtype uint32
	Filetype   uint32
	Ncmds      uint32
	SizeOfCmds uint32
	Flags      uint32
	Reserved   uint32 // 64-bit only
}

func (h *MachOHeader) Serialize() []byte {
	buf := make([]byte, MACHO_HDR_SIZE)
	binary.LittleEndian.PutUint32(buf[0:], h.Magic)
	binary.LittleEndian.PutUint32(buf[4:], h.CpuType)
	binary.LittleEndian.PutUint32(buf[8:], h.CpuSubtype)
	binary.LittleEndian.PutUint32(buf[12:], h.Filetype)
	binary.LittleEndian.PutUint32(buf[16:], h.Ncmds)
	binary.LittleEndian.PutUint32(buf[20:], h.SizeOfCmds)
	binary.LittleEndian.PutUint32(buf[24:], h.Flags)
	binary.LittleEndian.PutUint32(buf[28:], h.Reserved)
	return buf
}

func testMachOHeaderLayout() {
	fmt.Println("\n5. Mach-O (macOS) header layout:")

	hdr := MachOHeader{
		Magic:      MH_MAGIC_64,
		CpuType:    CPU_TYPE_ARM64,
		CpuSubtype: 0, // CPU_SUBTYPE_ALL
		Filetype:   MH_EXECUTE,
		Ncmds:      4,
		SizeOfCmds: 392,
		Flags:      0x00200085, // MH_PIE | MH_DYLDLINK | MH_NOUNDEFS | MH_TWOLEVEL
	}

	raw := hdr.Serialize()
	assert(len(raw) == MACHO_HDR_SIZE, "mach-o header 32 bytes")

	// Verify magic from raw bytes
	magic := binary.LittleEndian.Uint32(raw[0:4])
	assert(magic == MH_MAGIC_64, "mach-o magic")

	// Byte-swapped magic (big-endian host reading little-endian file)
	assert(MH_CIGAM_64 == 0xCFFAEDFE, "byte-swapped magic")

	cpuType := binary.LittleEndian.Uint32(raw[4:8])
	assert(cpuType == CPU_TYPE_ARM64, "ARM64 CPU type")

	fmt.Printf("   Magic:      0x%08X (FEEDFACF = 64-bit Mach-O)\n", magic)
	fmt.Printf("   CPU type:   0x%08X (ARM64)\n", cpuType)
	fmt.Printf("   File type:  MH_EXECUTE (%d)\n", hdr.Filetype)
	fmt.Printf("   Load cmds:  %d commands, %d bytes\n", hdr.Ncmds, hdr.SizeOfCmds)
	fmt.Printf("   Header:     %d bytes\n", MACHO_HDR_SIZE)
}

// ── Format Detection ─────────────────────────────────────────────────
// Detect binary format from the first 4 bytes.

func detectFormat(data []byte) string {
	if len(data) < 4 {
		return "unknown (too short)"
	}

	// ELF: 7F 45 4C 46
	if data[0] == 0x7F && data[1] == 'E' && data[2] == 'L' && data[3] == 'F' {
		return "ELF"
	}

	magic32 := binary.LittleEndian.Uint32(data[0:4])

	// Mach-O 64-bit (native or byte-swapped)
	if magic32 == MH_MAGIC_64 || magic32 == MH_CIGAM_64 {
		return "Mach-O 64"
	}

	// Mach-O 32-bit
	if magic32 == 0xFEEDFACE || magic32 == 0xCEFAEDFE {
		return "Mach-O 32"
	}

	// PE: starts with MZ DOS stub
	if data[0] == 'M' && data[1] == 'Z' {
		return "PE (DOS/MZ)"
	}

	return "unknown"
}

func testFormatDetection() {
	fmt.Println("\n6. Format detection from magic bytes:")

	elf := buildMinimalElf()
	assert(detectFormat(elf) == "ELF", "detect ELF")

	macho := MachOHeader{Magic: MH_MAGIC_64}
	assert(detectFormat(macho.Serialize()) == "Mach-O 64", "detect Mach-O")

	pe := []byte{'M', 'Z', 0x90, 0x00}
	assert(detectFormat(pe) == "PE (DOS/MZ)", "detect PE")

	assert(detectFormat([]byte{0, 0, 0, 0}) == "unknown", "detect unknown")

	fmt.Println("   ELF:     7F 45 4C 46 -> detected")
	fmt.Println("   Mach-O:  CF FA ED FE -> detected")
	fmt.Println("   PE:      4D 5A       -> detected")
}

// ── Format Comparison ────────────────────────────────────────────────

type FormatInfo struct {
	Name       string
	MagicSize  int
	HeaderSize int
	Platform   string
	Endian     string
}

func testFormatComparison() {
	fmt.Println("\n7. Format comparison:")

	formats := []FormatInfo{
		{"ELF",    4, 64, "Linux/BSD/Solaris", "configurable (usually LE)"},
		{"PE",     2, 24, "Windows",           "little-endian"},
		{"Mach-O", 4, 32, "macOS/iOS",         "configurable (usually LE)"},
	}

	// ELF is the largest header but most flexible
	assert(formats[0].HeaderSize == 64, "ELF header largest")
	// Mach-O is smallest header
	assert(formats[2].HeaderSize == 32, "Mach-O header smallest")
	// PE uses 2-byte magic (MZ), others use 4
	assert(formats[1].MagicSize == 2, "PE 2-byte magic")

	fmt.Printf("   %-8s %-8s %-8s %-20s %s\n",
		"Format", "Magic", "Header", "Platform", "Endianness")
	fmt.Printf("   %-8s %-8s %-8s %-20s %s\n",
		"------", "-----", "------", "--------", "----------")
	for _, f := range formats {
		fmt.Printf("   %-8s %d bytes  %d bytes %-20s %s\n",
			f.Name, f.MagicSize, f.HeaderSize, f.Platform, f.Endian)
	}

	// Minimal binary sizes
	minElf := 64 + 56 + 9  // ehdr + phdr + exit code
	minPE := 64 + 24 + 240 // DOS stub + COFF + optional (PE32+)
	fmt.Printf("\n   Minimal static binary:\n")
	fmt.Printf("   ELF:    %d bytes (ehdr+phdr+code)\n", minElf)
	fmt.Printf("   PE:     ~%d bytes (DOS stub+COFF+optional header minimum)\n", minPE)
	fmt.Printf("   Mach-O: ~%d bytes (header+LC_SEGMENT_64+code)\n", 32+72+9)
}

// ── Helpers ──────────────────────────────────────────────────────────

func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}
