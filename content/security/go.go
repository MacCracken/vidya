// Vidya — Security Practices in Go
//
// Go's standard library provides crypto/subtle for constant-time
// comparison, crypto/rand for secure randomness, html/template for
// auto-escaping, and path/filepath for safe path resolution. Input
// validation is manual — there's no framework magic.

package main

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"unicode"
)

func main() {
	testInputValidation()
	testAllowlistRegex()
	testConstantTimeComparison()
	testSecureRandomGeneration()
	testPathTraversalPrevention()
	testParameterizedQueryPattern()
	testIntegerOverflowChecks()
	testSafeDeserialization()

	fmt.Println("All security examples passed.")
}

// ── Input validation at the boundary ──────────────────────────────────
func validateUsername(input string) error {
	if len(input) == 0 {
		return fmt.Errorf("username cannot be empty")
	}
	if len(input) > 32 {
		return fmt.Errorf("username too long")
	}
	for _, r := range input {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '_' {
			return fmt.Errorf("invalid character: %c", r)
		}
	}
	return nil
}

func testInputValidation() {
	assert(validateUsername("alice_42") == nil, "valid username")

	badInputs := []string{"", strings.Repeat("a", 33), "alice; DROP TABLE", "../etc/passwd", "<script>"}
	for _, bad := range badInputs {
		assert(validateUsername(bad) != nil, "should reject: "+bad)
	}
}

// ── Allowlist regex ───────────────────────────────────────────────────
var safeInputRe = regexp.MustCompile(`^[a-zA-Z0-9 .,!?]{1,200}$`)

func isSafeInput(text string) bool {
	return safeInputRe.MatchString(text)
}

func testAllowlistRegex() {
	assert(isSafeInput("Hello, world!"), "safe input")
	assert(!isSafeInput(""), "empty")
	assert(!isSafeInput("<script>alert(1)</script>"), "xss attempt")
	assert(!isSafeInput(strings.Repeat("a", 201)), "too long")
}

// ── Constant-time comparison ──────────────────────────────────────────
func testConstantTimeComparison() {
	secret := []byte("super_secret_token_2024")
	correct := []byte("super_secret_token_2024")
	wrong := []byte("super_secret_token_2025")

	// BAD: bytes.Equal or == short-circuits on first difference
	//   if string(userToken) == string(storedToken) { ... }

	// GOOD: subtle.ConstantTimeCompare examines every byte
	assert(subtle.ConstantTimeCompare(secret, correct) == 1, "matching tokens")
	assert(subtle.ConstantTimeCompare(secret, wrong) == 0, "different tokens")

	// Also checks length in constant time
	short := []byte("short")
	assert(subtle.ConstantTimeCompare(secret, short) == 0, "different lengths")
}

// ── Secure random generation ──────────────────────────────────────────
func testSecureRandomGeneration() {
	// BAD: math/rand is deterministic (seeded PRNG, not crypto)
	//   import "math/rand"; token := rand.Int63()

	// GOOD: crypto/rand reads from OS entropy (/dev/urandom)
	token := make([]byte, 32) // 256 bits
	_, err := rand.Read(token)
	assertNoErr(err)

	hexToken := hex.EncodeToString(token)
	assert(len(hexToken) == 64, "hex token length")

	// Two tokens should never be equal
	token2 := make([]byte, 32)
	_, err = rand.Read(token2)
	assertNoErr(err)
	assert(subtle.ConstantTimeCompare(token, token2) == 0, "tokens differ")
}

// ── Path traversal prevention ─────────────────────────────────────────
func safeResolve(baseDir, userInput string) (string, error) {
	// Clean and join
	candidate := filepath.Clean(filepath.Join(baseDir, userInput))
	baseResolved := filepath.Clean(baseDir)

	// Verify the result stays within the base directory
	if !strings.HasPrefix(candidate, baseResolved+string(filepath.Separator)) &&
		candidate != baseResolved {
		return "", fmt.Errorf("path traversal detected: %s", userInput)
	}
	return candidate, nil
}

func testPathTraversalPrevention() {
	base, err := os.MkdirTemp("", "vidya-sec-")
	assertNoErr(err)
	defer os.RemoveAll(base)

	// Safe paths
	p, err := safeResolve(base, "photo.jpg")
	assertNoErr(err)
	assert(strings.HasSuffix(p, "photo.jpg"), "safe file")

	// Traversal attempts
	attacks := []string{"../../etc/passwd", "../secret", "normal/../../escape"}
	for _, attack := range attacks {
		_, err := safeResolve(base, attack)
		assert(err != nil, "should reject: "+attack)
	}
}

// ── Parameterized query pattern ───────────────────────────────────────
func testParameterizedQueryPattern() {
	userInput := "'; DROP TABLE users; --"

	// BAD: string concatenation
	badQuery := fmt.Sprintf("SELECT * FROM users WHERE name = '%s'", userInput)
	assert(strings.Contains(badQuery, "DROP TABLE"), "injection in bad query")

	// GOOD: parameterized query — db.Query handles escaping
	// db.Query("SELECT * FROM users WHERE name = ?", userInput)
	template := "SELECT * FROM users WHERE name = ?"
	params := []string{userInput}
	assert(!strings.Contains(template, "DROP TABLE"), "template is safe")
	assert(params[0] == userInput, "param preserved as data")
}

// ── Integer overflow checks ───────────────────────────────────────────
func safeMultiply(a, b uint32) (uint32, error) {
	if b != 0 && a > ^uint32(0)/b {
		return 0, fmt.Errorf("overflow: %d * %d", a, b)
	}
	return a * b, nil
}

func testIntegerOverflowChecks() {
	result, err := safeMultiply(1000, 1000)
	assertNoErr(err)
	assert(result == 1_000_000, "safe multiply")

	// Overflow: 65536 * 65536 * 4 exceeds uint32
	_, err = safeMultiply(65536, 65536)
	assert(err != nil, "overflow detected")
}

// ── Safe deserialization ──────────────────────────────────────────────
func testSafeDeserialization() {
	// Go's encoding/json is safe — it only produces data, no code execution
	// Unlike Python's pickle or Java's ObjectInputStream

	type User struct {
		Name string `json:"name"`
		Age  int    `json:"age"`
	}

	var user User
	err := json.Unmarshal([]byte(`{"name": "alice", "age": 30}`), &user)
	assertNoErr(err)
	assert(user.Name == "alice", "name")
	assert(user.Age == 30, "age")

	// Reject unknown fields when strict parsing is needed
	decoder := json.NewDecoder(strings.NewReader(`{"name": "alice", "admin": true}`))
	decoder.DisallowUnknownFields()
	var strict User
	err = decoder.Decode(&strict)
	assert(err != nil, "unknown fields rejected")
}

// ── Helpers ───────────────────────────────────────────────────────────
func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}

func assertNoErr(err error) {
	if err != nil {
		panic("unexpected error: " + err.Error())
	}
}
