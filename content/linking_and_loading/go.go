// Vidya — Linking and Loading in Go
//
// Demonstrates core linker concepts using Go's maps and structs:
//   - Object files with symbol tables and sections
//   - Two-pass symbol resolution across compilation units
//   - Relocation patching (absolute and PC-relative)
//   - GOT/PLT lazy binding simulation
//   - Weak vs strong symbol resolution
//
// This models what ld does when combining .o files into an executable.
// The linker's job: resolve names to addresses, patch instructions.

package main

import (
	"fmt"
	"strings"
)

// ── Relocation Types ─────────────────────────────────────────────────
// These match the x86_64 ELF relocation types.

type RelocType int

const (
	// R_X86_64_64: absolute 64-bit address, used for data pointers
	RelocAbs64 RelocType = iota
	// R_X86_64_PC32: 32-bit PC-relative, used in call/jmp
	RelocPC32
	// R_X86_64_PLT32: call through PLT for external functions
	RelocPLT32
	// R_X86_64_GOTPCRELX: load from GOT for external data
	RelocGOTPCREL
)

func (r RelocType) String() string {
	switch r {
	case RelocAbs64:
		return "R_X86_64_64"
	case RelocPC32:
		return "R_X86_64_PC32"
	case RelocPLT32:
		return "R_X86_64_PLT32"
	case RelocGOTPCREL:
		return "R_X86_64_GOTPCRELX"
	default:
		return "UNKNOWN"
	}
}

// ── Section ──────────────────────────────────────────────────────────

type Section struct {
	Name     string
	Data     []byte
	BaseAddr uint64 // assigned during layout
}

// ── Symbol ───────────────────────────────────────────────────────────
// Symbols are either defined (have a section + offset) or undefined
// (references to be resolved by the linker).

type SymbolBinding int

const (
	BindLocal  SymbolBinding = iota
	BindGlobal               // strong definition
	BindWeak                 // weak — overridden by strong
)

type Symbol struct {
	Name         string
	Section      string // which section (empty for undefined)
	Offset       uint64 // offset within section
	IsDefined    bool
	Binding      SymbolBinding
	ResolvedAddr uint64 // filled by linker
}

// ── Relocation ───────────────────────────────────────────────────────
// "Patch the bytes at Section[Offset] using Symbol's address."

type Relocation struct {
	Section   string
	Offset    uint64
	Symbol    string
	Type      RelocType
	Addend    int64 // for RELA-style (addend stored in reloc, not in instruction)
}

// ── Object File ──────────────────────────────────────────────────────

type ObjectFile struct {
	Name        string
	Sections    map[string]*Section
	Symbols     []Symbol
	Relocations []Relocation
}

func NewObject(name string) *ObjectFile {
	return &ObjectFile{
		Name:     name,
		Sections: make(map[string]*Section),
	}
}

func (o *ObjectFile) AddSection(name string, data []byte) {
	o.Sections[name] = &Section{Name: name, Data: make([]byte, len(data))}
	copy(o.Sections[name].Data, data)
}

func (o *ObjectFile) AddSymbol(name, section string, offset uint64, defined bool, binding SymbolBinding) {
	o.Symbols = append(o.Symbols, Symbol{
		Name:      name,
		Section:   section,
		Offset:    offset,
		IsDefined: defined,
		Binding:   binding,
	})
}

func (o *ObjectFile) AddRelocation(section string, offset uint64, symbol string, relocType RelocType, addend int64) {
	o.Relocations = append(o.Relocations, Relocation{
		Section: section,
		Offset:  offset,
		Symbol:  symbol,
		Type:    relocType,
		Addend:  addend,
	})
}

// ── Linker ───────────────────────────────────────────────────────────
// Two-pass model:
//   Pass 1: Collect all symbols, resolve definitions vs references
//   Pass 2: Apply relocations (patch instruction bytes)

type Linker struct {
	GlobalSymbols map[string]*Symbol
	Sections      map[string]*Section
	NextAddr      uint64 // next available virtual address
	Errors        []string
}

func NewLinker(baseAddr uint64) *Linker {
	return &Linker{
		GlobalSymbols: make(map[string]*Symbol),
		Sections:      make(map[string]*Section),
		NextAddr:      baseAddr,
	}
}

// Pass 1: Scan all objects, build global symbol table.
// Strong definitions win over weak. Multiple strong = error.
func (l *Linker) Pass1(objects []*ObjectFile) {
	for _, obj := range objects {
		// Merge sections — append each object's section data
		for name, sec := range obj.Sections {
			if existing, ok := l.Sections[name]; ok {
				// Record base address for this chunk
				sec.BaseAddr = uint64(len(existing.Data)) + existing.BaseAddr
				existing.Data = append(existing.Data, sec.Data...)
			} else {
				sec.BaseAddr = l.NextAddr
				l.Sections[name] = &Section{
					Name:     name,
					Data:     make([]byte, len(sec.Data)),
					BaseAddr: l.NextAddr,
				}
				copy(l.Sections[name].Data, sec.Data)
				l.NextAddr += uint64(len(sec.Data))
				// Align to 16 bytes
				if l.NextAddr%16 != 0 {
					l.NextAddr = (l.NextAddr + 15) & ^uint64(15)
				}
			}
		}

		// Collect symbols
		for i := range obj.Symbols {
			sym := obj.Symbols[i]
			if !sym.IsDefined {
				// Undefined reference — record if not already known
				if _, exists := l.GlobalSymbols[sym.Name]; !exists {
					s := sym // copy
					l.GlobalSymbols[sym.Name] = &s
				}
				continue
			}

			existing, exists := l.GlobalSymbols[sym.Name]
			if !exists || !existing.IsDefined {
				// First definition (or replaces undefined reference)
				s := sym
				l.GlobalSymbols[sym.Name] = &s
			} else if existing.Binding == BindWeak && sym.Binding == BindGlobal {
				// Strong overrides weak
				s := sym
				l.GlobalSymbols[sym.Name] = &s
			} else if existing.Binding == BindGlobal && sym.Binding == BindGlobal {
				l.Errors = append(l.Errors, fmt.Sprintf("multiple definition of '%s'", sym.Name))
			}
			// weak + weak: keep first
		}
	}

	// Resolve addresses: symbol address = section base + offset
	for _, sym := range l.GlobalSymbols {
		if sym.IsDefined {
			if sec, ok := l.Sections[sym.Section]; ok {
				sym.ResolvedAddr = sec.BaseAddr + sym.Offset
			}
		}
	}

	// Check for unresolved symbols
	for name, sym := range l.GlobalSymbols {
		if !sym.IsDefined {
			l.Errors = append(l.Errors, fmt.Sprintf("undefined reference to '%s'", name))
		}
	}
}

// Pass 2: Apply relocations — patch instruction bytes.
func (l *Linker) Pass2(objects []*ObjectFile) {
	for _, obj := range objects {
		for _, reloc := range obj.Relocations {
			sym, ok := l.GlobalSymbols[reloc.Symbol]
			if !ok || !sym.IsDefined {
				continue // already reported in pass 1
			}

			sec, ok := l.Sections[reloc.Section]
			if !ok {
				continue
			}

			target := sym.ResolvedAddr
			patchAddr := sec.BaseAddr + reloc.Offset

			switch reloc.Type {
			case RelocAbs64:
				// Patch 8 bytes with absolute address
				addr := target + uint64(reloc.Addend)
				for i := 0; i < 8; i++ {
					if int(reloc.Offset)+i < len(sec.Data) {
						sec.Data[int(reloc.Offset)+i] = byte(addr >> (i * 8))
					}
				}

			case RelocPC32, RelocPLT32:
				// Patch 4 bytes with PC-relative offset
				// PC-relative: target - (patch_address + 4) + addend
				// The +4 accounts for the instruction reading past the displacement
				rel := int64(target) - int64(patchAddr+4) + reloc.Addend
				for i := 0; i < 4; i++ {
					if int(reloc.Offset)+i < len(sec.Data) {
						sec.Data[int(reloc.Offset)+i] = byte(uint32(rel) >> (i * 8))
					}
				}
			}
		}
	}
}

// ── GOT/PLT Simulation ──────────────────────────────────────────────
// The GOT (Global Offset Table) holds addresses of external symbols.
// The PLT (Procedure Linkage Table) provides lazy binding stubs.
//
// First call to printf@plt:
//   1. PLT stub jumps to GOT[printf] (initially points back to resolver)
//   2. Resolver finds printf's real address via the dynamic linker
//   3. Resolver patches GOT[printf] with the real address
//   4. Subsequent calls jump directly to printf (one indirection)

type GOTEntry struct {
	Symbol   string
	Address  uint64
	Resolved bool
}

type PLTStub struct {
	Symbol   string
	GOTIndex int
}

type DynamicLinker struct {
	GOT          []GOTEntry
	PLT          []PLTStub
	SymbolLookup map[string]uint64 // simulated shared library symbols
	BindCount    int               // how many lazy bindings performed
}

func NewDynamicLinker() *DynamicLinker {
	return &DynamicLinker{
		SymbolLookup: make(map[string]uint64),
	}
}

func (dl *DynamicLinker) AddSharedSymbol(name string, addr uint64) {
	dl.SymbolLookup[name] = addr
}

// AddPLTEntry creates a GOT slot (initially unresolved) and a PLT stub.
func (dl *DynamicLinker) AddPLTEntry(symbol string) int {
	gotIdx := len(dl.GOT)
	dl.GOT = append(dl.GOT, GOTEntry{
		Symbol:   symbol,
		Address:  0, // unresolved — points to resolver on first call
		Resolved: false,
	})
	dl.PLT = append(dl.PLT, PLTStub{
		Symbol:   symbol,
		GOTIndex: gotIdx,
	})
	return gotIdx
}

// CallPLT simulates calling a function through the PLT.
// Returns the resolved address. Lazy binding happens on first call.
func (dl *DynamicLinker) CallPLT(pltIdx int) (uint64, bool) {
	stub := dl.PLT[pltIdx]
	got := &dl.GOT[stub.GOTIndex]

	if !got.Resolved {
		// Lazy binding: look up the symbol now
		addr, ok := dl.SymbolLookup[got.Symbol]
		if !ok {
			return 0, false
		}
		got.Address = addr
		got.Resolved = true
		dl.BindCount++
	}

	return got.Address, true
}

// ── Display Helpers ──────────────────────────────────────────────────

func printSymbolTable(l *Linker) {
	fmt.Printf("  %-15s %-10s %s\n", "Symbol", "Address", "Binding")
	fmt.Printf("  %-15s %-10s %s\n", "------", "-------", "-------")
	for name, sym := range l.GlobalSymbols {
		binding := "global"
		if sym.Binding == BindWeak {
			binding = "weak"
		}
		if sym.IsDefined {
			fmt.Printf("  %-15s 0x%08x %s\n", name, sym.ResolvedAddr, binding)
		} else {
			fmt.Printf("  %-15s %-10s %s\n", name, "UNDEF", binding)
		}
	}
}

func main() {
	fmt.Println("Linking and Loading — Go demonstration:\n")

	// ── 1. Build two object files ────────────────────────────────────
	fmt.Println("1. Two-pass linking:")

	// Object 1: main.o — defines main, references add and data
	main_o := NewObject("main.o")
	main_o.AddSection(".text", []byte{
		0x55,                         // push rbp
		0x48, 0x89, 0xe5,             // mov rbp, rsp
		0xe8, 0x00, 0x00, 0x00, 0x00, // call add (needs relocation at offset 5)
		0x48, 0x8b, 0x05,             // mov rax, [rip+disp32]
		0x00, 0x00, 0x00, 0x00,       // displacement for data (offset 12)
		0x5d,                         // pop rbp
		0xc3,                         // ret
	})
	main_o.AddSection(".data", []byte{0x2a, 0x00, 0x00, 0x00}) // int 42

	main_o.AddSymbol("main", ".text", 0, true, BindGlobal)
	main_o.AddSymbol("add", "", 0, false, BindGlobal)   // undefined
	main_o.AddSymbol("data", ".data", 0, true, BindGlobal)
	main_o.AddRelocation(".text", 5, "add", RelocPC32, -4)
	main_o.AddRelocation(".text", 12, "data", RelocPC32, -4)

	// Object 2: math.o — defines add
	math_o := NewObject("math.o")
	math_o.AddSection(".text", []byte{
		0x48, 0x01, 0xf7, // add rdi, rsi
		0x48, 0x89, 0xf8, // mov rax, rdi
		0xc3,             // ret
	})
	math_o.AddSymbol("add", ".text", 0, true, BindGlobal)

	// Link them
	linker := NewLinker(0x00400000)
	objects := []*ObjectFile{main_o, math_o}
	linker.Pass1(objects)

	assert(len(linker.Errors) == 0, fmt.Sprintf("link errors: %v", linker.Errors))
	assert(linker.GlobalSymbols["main"].IsDefined, "main must be defined")
	assert(linker.GlobalSymbols["add"].IsDefined, "add must be defined")
	assert(linker.GlobalSymbols["data"].IsDefined, "data must be defined")

	fmt.Println("  Symbol table after pass 1:")
	printSymbolTable(linker)

	linker.Pass2(objects)
	fmt.Println("  Relocations applied in pass 2.")

	// Verify the call instruction was patched (bytes at offset 5-8 in .text)
	textSec := linker.Sections[".text"]
	assert(textSec != nil, ".text section must exist")
	fmt.Printf("  .text section: %d bytes at 0x%08x\n", len(textSec.Data), textSec.BaseAddr)

	// ── 2. Weak vs strong symbol resolution ──────────────────────────
	fmt.Println("\n2. Weak vs strong symbol resolution:")

	weakObj := NewObject("weak.o")
	weakObj.AddSection(".text", []byte{0x90}) // nop
	weakObj.AddSymbol("handler", ".text", 0, true, BindWeak)

	strongObj := NewObject("strong.o")
	strongObj.AddSection(".text", []byte{0xcc}) // int3
	strongObj.AddSymbol("handler", ".text", 0, true, BindGlobal)

	weakLinker := NewLinker(0x00400000)
	weakLinker.Pass1([]*ObjectFile{weakObj, strongObj})
	assert(len(weakLinker.Errors) == 0, "no errors with weak + strong")
	assert(weakLinker.GlobalSymbols["handler"].Binding == BindGlobal,
		"strong must override weak")
	fmt.Println("  Strong symbol overrides weak — correct.")

	// Two strong definitions should error
	strong2 := NewObject("strong2.o")
	strong2.AddSection(".text", []byte{0x90})
	strong2.AddSymbol("handler", ".text", 0, true, BindGlobal)

	dupLinker := NewLinker(0x00400000)
	dupLinker.Pass1([]*ObjectFile{strongObj, strong2})
	assert(len(dupLinker.Errors) > 0, "multiple strong defs must error")
	fmt.Printf("  Duplicate strong symbol error: %s\n", dupLinker.Errors[0])

	// ── 3. Undefined symbol detection ────────────────────────────────
	fmt.Println("\n3. Undefined symbol detection:")

	undefObj := NewObject("undef.o")
	undefObj.AddSection(".text", []byte{0xe8, 0x00, 0x00, 0x00, 0x00})
	undefObj.AddSymbol("missing_func", "", 0, false, BindGlobal)
	undefObj.AddRelocation(".text", 1, "missing_func", RelocPC32, -4)

	undefLinker := NewLinker(0x00400000)
	undefLinker.Pass1([]*ObjectFile{undefObj})
	hasUndef := false
	for _, err := range undefLinker.Errors {
		if strings.Contains(err, "missing_func") {
			hasUndef = true
			fmt.Printf("  Detected: %s\n", err)
		}
	}
	assert(hasUndef, "must detect undefined symbol")

	// ── 4. Relocation types ──────────────────────────────────────────
	fmt.Println("\n4. Relocation types:")
	relocs := []struct {
		typ  RelocType
		desc string
	}{
		{RelocAbs64, "Absolute 64-bit address (data pointers)"},
		{RelocPC32, "32-bit PC-relative (call/jmp within module)"},
		{RelocPLT32, "PLT call (external functions, lazy bound)"},
		{RelocGOTPCREL, "GOT-relative (external data, eager bound)"},
	}
	for _, r := range relocs {
		fmt.Printf("  %-22s — %s\n", r.typ, r.desc)
	}

	// ── 5. GOT/PLT lazy binding simulation ───────────────────────────
	fmt.Println("\n5. GOT/PLT lazy binding simulation:")

	dl := NewDynamicLinker()
	// Simulate libc symbols at known addresses
	dl.AddSharedSymbol("printf", 0x7f000100)
	dl.AddSharedSymbol("malloc", 0x7f000200)
	dl.AddSharedSymbol("free", 0x7f000300)

	printfPLT := dl.AddPLTEntry("printf")
	mallocPLT := dl.AddPLTEntry("malloc")
	freePLT := dl.AddPLTEntry("free")

	// Before any calls — GOT entries are unresolved
	assert(!dl.GOT[printfPLT].Resolved, "printf GOT not yet resolved")
	assert(!dl.GOT[mallocPLT].Resolved, "malloc GOT not yet resolved")
	fmt.Println("  Before calls: all GOT entries unresolved")

	// First call to printf — triggers lazy binding
	addr, ok := dl.CallPLT(printfPLT)
	assert(ok, "printf must resolve")
	assert(addr == 0x7f000100, "printf address must match")
	assert(dl.GOT[printfPLT].Resolved, "printf GOT now resolved")
	assert(dl.BindCount == 1, "one binding performed")
	fmt.Printf("  First call to printf@plt: resolved to 0x%08x (lazy bind #%d)\n",
		addr, dl.BindCount)

	// Second call to printf — no binding needed, GOT already patched
	bindsBefore := dl.BindCount
	addr2, ok := dl.CallPLT(printfPLT)
	assert(ok, "printf must still resolve")
	assert(addr2 == addr, "same address on second call")
	assert(dl.BindCount == bindsBefore, "no new binding on cached call")
	fmt.Printf("  Second call to printf@plt: cached at 0x%08x (no new bind)\n", addr2)

	// Call malloc — separate lazy binding
	mAddr, ok := dl.CallPLT(mallocPLT)
	assert(ok, "malloc must resolve")
	assert(mAddr == 0x7f000200, "malloc address must match")
	assert(dl.BindCount == 2, "two bindings total")
	fmt.Printf("  First call to malloc@plt: resolved to 0x%08x (lazy bind #%d)\n",
		mAddr, dl.BindCount)

	// Call free
	fAddr, ok := dl.CallPLT(freePLT)
	assert(ok, "free must resolve")
	assert(fAddr == 0x7f000300, "free address")
	assert(dl.BindCount == 3, "three bindings total")
	fmt.Printf("  First call to free@plt:   resolved to 0x%08x (lazy bind #%d)\n",
		fAddr, dl.BindCount)

	// ── 6. Section layout ────────────────────────────────────────────
	fmt.Println("\n6. Standard ELF sections and permissions:")
	sections := []struct {
		name  string
		perms string
		desc  string
	}{
		{".text", "r-x", "Executable code"},
		{".rodata", "r--", "Read-only data (string literals, constants)"},
		{".data", "rw-", "Initialized read-write data"},
		{".bss", "rw-", "Uninitialized data (zero-filled, no disk space)"},
		{".got", "rw-", "Global Offset Table (external data addresses)"},
		{".plt", "r-x", "Procedure Linkage Table (external function stubs)"},
	}
	fmt.Printf("  %-10s %-5s %s\n", "Section", "Perms", "Description")
	fmt.Printf("  %-10s %-5s %s\n", "-------", "-----", "-----------")
	for _, s := range sections {
		fmt.Printf("  %-10s %-5s %s\n", s.name, s.perms, s.desc)
	}

	fmt.Println("\nAll linking and loading examples passed.")
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}
