// Vidya — Concurrency in Go
//
// Go's concurrency model is built on goroutines (lightweight threads)
// and channels (typed message pipes). "Don't communicate by sharing
// memory; share memory by communicating." — Go Proverb

package main

import (
	"fmt"
	"sync"
	"sync/atomic"
)

func main() {
	// ── Goroutines: lightweight concurrent functions ────────────────
	done := make(chan bool, 1)
	go func() {
		done <- true
	}()
	assert(<-done, "goroutine ran")

	// ── Channels: typed communication ──────────────────────────────
	ch := make(chan int, 5)
	go func() {
		for i := 0; i < 5; i++ {
			ch <- i * i
		}
		close(ch)
	}()

	var squares []int
	for v := range ch {
		squares = append(squares, v)
	}
	assertSlice(squares, []int{0, 1, 4, 9, 16}, "channel squares")

	// ── Fan-out / fan-in ───────────────────────────────────────────
	results := make(chan int, 3)
	for id := 0; id < 3; id++ {
		go func(n int) {
			results <- n * 10
		}(id)
	}

	var collected []int
	for i := 0; i < 3; i++ {
		collected = append(collected, <-results)
	}
	assert(len(collected) == 3, "fan-out count")

	// ── Select: multiplexing channels ──────────────────────────────
	ch1 := make(chan string, 1)
	ch2 := make(chan string, 1)
	ch1 <- "from ch1"

	var msg string
	select {
	case msg = <-ch1:
	case msg = <-ch2:
	}
	assert(msg == "from ch1", "select")

	// Select with default (non-blocking)
	select {
	case <-ch2:
		panic("ch2 should be empty")
	default:
		// non-blocking — ch2 is empty
	}

	// ── WaitGroup: waiting for multiple goroutines ──────────────────
	var wg sync.WaitGroup
	counter := int64(0)

	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 1000; j++ {
				atomic.AddInt64(&counter, 1)
			}
		}()
	}
	wg.Wait()
	assert(counter == 4000, "waitgroup + atomic")

	// ── Mutex: protecting shared state ─────────────────────────────
	var mu sync.Mutex
	sharedData := make(map[string]int)

	var wg2 sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg2.Add(1)
		go func(n int) {
			defer wg2.Done()
			mu.Lock()
			sharedData[fmt.Sprintf("key%d", n)] = n
			mu.Unlock()
		}(i)
	}
	wg2.Wait()
	assert(len(sharedData) == 10, "mutex map")

	// ── RWMutex: multiple readers, single writer ───────────────────
	var rwmu sync.RWMutex
	data := 42

	// Multiple readers can run concurrently
	var wg3 sync.WaitGroup
	for i := 0; i < 5; i++ {
		wg3.Add(1)
		go func() {
			defer wg3.Done()
			rwmu.RLock()
			_ = data // read
			rwmu.RUnlock()
		}()
	}
	wg3.Wait()

	// ── Once: exactly-once initialization ──────────────────────────
	var once sync.Once
	initCount := 0
	for i := 0; i < 10; i++ {
		once.Do(func() { initCount++ })
	}
	assert(initCount == 1, "once ran exactly once")

	// ── Buffered vs unbuffered channels ────────────────────────────
	unbuffered := make(chan int)    // blocks until receiver ready
	buffered := make(chan int, 10)  // can hold 10 values without blocking

	// Buffered: send doesn't block until full
	buffered <- 1
	buffered <- 2
	assert(<-buffered == 1, "buffered FIFO")

	// Unbuffered: needs concurrent sender and receiver
	go func() { unbuffered <- 42 }()
	assert(<-unbuffered == 42, "unbuffered")

	// ── Done channel pattern ───────────────────────────────────────
	doneCh := make(chan struct{})
	go func() {
		// simulate work
		close(doneCh) // signal completion by closing
	}()
	<-doneCh // blocks until closed

	// ── Context would go here (covered in real apps) ───────────────
	// context.WithCancel, context.WithTimeout for cancellation
	// Not demonstrated here to keep it self-contained

	fmt.Println("All concurrency examples passed.")
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}

func assertSlice(a, b []int, msg string) {
	if len(a) != len(b) {
		panic(fmt.Sprintf("assertion failed (%s): len %d != %d", msg, len(a), len(b)))
	}
	for i := range a {
		if a[i] != b[i] {
			panic(fmt.Sprintf("assertion failed (%s): [%d] %d != %d", msg, i, a[i], b[i]))
		}
	}
}
