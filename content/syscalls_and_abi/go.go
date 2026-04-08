// Vidya — Syscalls and ABI in Go
//
// Go bridges its own internal calling convention to the kernel's
// syscall ABI. This demonstrates:
//   - Raw syscalls via syscall.Syscall and syscall.RawSyscall
//   - Linux x86_64 syscall number table
//   - System V AMD64 ABI register mapping
//   - Go's ABI differences from C
//   - Syscall error handling
//
// Go's internal ABI (since Go 1.17) passes args in registers (AX, BX,
// CX, DI, SI, R8-R11) — different from System V. But when making
// syscalls, Go's runtime translates to the kernel's register convention:
// nr=RAX, args=RDI,RSI,RDX,R10,R8,R9.

package main

import (
	"fmt"
	"os"
	"runtime"
	"syscall"
	"unsafe"
)

// ── Linux x86_64 syscall numbers ──────────────────────────────────
// These are stable kernel ABI — they never change.

const (
	SYS_READ    = 0
	SYS_WRITE   = 1
	SYS_OPEN    = 2
	SYS_CLOSE   = 3
	SYS_BRK     = 12
	SYS_GETPID  = 39
	SYS_EXIT    = 60
)

func main() {
	fmt.Println("Syscalls and ABI — Go demonstration:\n")

	// ── Syscall number table ──────────────────────────────────────
	fmt.Println("1. Linux x86_64 syscall number table:")
	numbers := []struct {
		name string
		nr   int
	}{
		{"read", SYS_READ},
		{"write", SYS_WRITE},
		{"open", SYS_OPEN},
		{"close", SYS_CLOSE},
		{"brk", SYS_BRK},
		{"getpid", SYS_GETPID},
		{"exit", SYS_EXIT},
	}
	for _, s := range numbers {
		fmt.Printf("  %8s = %d\n", s.name, s.nr)
	}

	// ── Raw syscalls via syscall.Syscall ──────────────────────────
	// syscall.Syscall(trap, a1, a2, a3) → (r1, r2, errno)
	//
	// Under the hood, Go's runtime:
	//   1. Saves goroutine state
	//   2. Transitions to a system stack (goroutine stacks are small)
	//   3. Loads registers per the kernel ABI: RAX=trap, RDI=a1, RSI=a2, RDX=a3
	//   4. Executes SYSCALL
	//   5. Checks if the goroutine's stack needs growing (preemption point)
	//
	// syscall.RawSyscall skips steps 1, 3, 5 — faster but can block
	// the entire OS thread (no preemption, no GC cooperation).

	fmt.Println("\n2. Raw syscalls via syscall.Syscall:")

	// getpid — simplest syscall, no arguments
	pid, _, _ := syscall.Syscall(syscall.SYS_GETPID, 0, 0, 0)
	osPid := os.Getpid()
	fmt.Printf("  getpid via syscall.Syscall: %d\n", pid)
	fmt.Printf("  getpid via os.Getpid():     %d\n", osPid)
	if int(pid) != osPid {
		panic("PIDs must match")
	}
	fmt.Println("  PIDs match — same underlying syscall.")

	// write — write to stdout
	msg := []byte("  Hello from raw syscall!\n")
	n, _, errno := syscall.Syscall(
		syscall.SYS_WRITE,
		uintptr(1),                       // fd = stdout
		uintptr(unsafe.Pointer(&msg[0])), // buf pointer
		uintptr(len(msg)),                // count
	)
	fmt.Printf("  write returned: %d bytes\n", n)
	if errno != 0 {
		panic(fmt.Sprintf("write failed: %v", errno))
	}
	if int(n) != len(msg) {
		panic("short write")
	}

	// write to bad fd — error demonstration
	_, _, errno = syscall.Syscall(
		syscall.SYS_WRITE,
		uintptr(999),                     // bad fd
		uintptr(unsafe.Pointer(&msg[0])),
		uintptr(len(msg)),
	)
	fmt.Printf("  write(fd=999) errno: %d (%v) (EBADF=9)\n", errno, errno)
	if errno != syscall.EBADF {
		panic("expected EBADF")
	}

	// ── RawSyscall vs Syscall ─────────────────────────────────────
	fmt.Println("\n3. RawSyscall vs Syscall:")
	fmt.Println("  syscall.Syscall:")
	fmt.Println("    - Notifies Go scheduler before/after kernel entry")
	fmt.Println("    - Allows goroutine preemption and GC cooperation")
	fmt.Println("    - Safe for potentially blocking syscalls (read, write, etc.)")
	fmt.Println("  syscall.RawSyscall:")
	fmt.Println("    - No scheduler notification — faster but dangerous")
	fmt.Println("    - Blocks the entire OS thread (other goroutines stall)")
	fmt.Println("    - Only safe for non-blocking syscalls (getpid, getuid, etc.)")

	// Demonstrate RawSyscall with getpid (safe — never blocks)
	pid2, _, _ := syscall.RawSyscall(syscall.SYS_GETPID, 0, 0, 0)
	fmt.Printf("  RawSyscall(getpid) = %d (matches: %v)\n", pid2, pid == pid2)
	if pid != pid2 {
		panic("RawSyscall PID must match")
	}

	// ── Go ABI vs System V AMD64 ABI ─────────────────────────────
	fmt.Println("\n4. Go's internal ABI vs System V AMD64:")
	fmt.Println("  System V AMD64 (C, Rust, etc.):")
	fmt.Println("    Args: RDI, RSI, RDX, RCX, R8, R9")
	fmt.Println("    Return: RAX")
	fmt.Println("    Callee-saved: RBX, RBP, R12-R15")
	fmt.Println()
	fmt.Println("  Go register ABI (since Go 1.17):")
	fmt.Println("    Integer args: RAX, RBX, RCX, RDI, RSI, R8-R11")
	fmt.Println("    Integer returns: RAX, RBX, RCX, RDI, RSI, R8-R11")
	fmt.Println("    Different order, different set of registers")
	fmt.Println()
	fmt.Println("  Key differences:")
	fmt.Println("    - Go uses its own register assignment (not System V)")
	fmt.Println("    - Go goroutine stacks start small (2-8KB) and grow dynamically")
	fmt.Println("    - Go inserts stack-growth checks at function entry (preamble)")
	fmt.Println("    - For cgo calls, Go switches to a C-sized stack and uses System V")
	fmt.Println("    - For syscalls, Go's runtime loads the kernel ABI registers directly")

	// ── Syscall register mapping ──────────────────────────────────
	fmt.Println("\n5. Kernel syscall register mapping:")
	fmt.Printf("  %-8s %-10s %-10s\n", "Arg", "Syscall", "Function(C)")
	fmt.Printf("  %-8s %-10s %-10s\n", "---", "-------", "-----------")
	sysRegs := []string{"rdi", "rsi", "rdx", "r10", "r8", "r9"}
	funRegs := []string{"rdi", "rsi", "rdx", "rcx", "r8", "r9"}
	for i := 0; i < 6; i++ {
		mark := ""
		if sysRegs[i] != funRegs[i] {
			mark = " <-"
		}
		fmt.Printf("  %-8d %-10s %-10s%s\n", i+1, sysRegs[i], funRegs[i], mark)
	}
	fmt.Println("  (<- 4th arg differs: R10 for syscall, RCX for function call)")
	fmt.Println("  SYSCALL clobbers RCX (saves RIP) and R11 (saves RFLAGS)")

	// ── Runtime info ──────────────────────────────────────────────
	fmt.Println("\n6. Runtime info:")
	fmt.Printf("  GOOS:   %s\n", runtime.GOOS)
	fmt.Printf("  GOARCH: %s\n", runtime.GOARCH)
	fmt.Printf("  Go version: %s\n", runtime.Version())
	fmt.Printf("  NumCPU: %d\n", runtime.NumCPU())
}
