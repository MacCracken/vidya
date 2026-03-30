// Vidya — Security Practices in TypeScript
//
// TypeScript's type system catches many bugs at compile time, but
// security requires runtime validation too: user input arrives as
// unknown shapes, strings carry injection payloads, and timing
// attacks bypass type safety entirely.

import * as crypto from "node:crypto";
import * as path from "node:path";
import * as os from "node:os";
import * as fs from "node:fs";

function main(): void {
    testInputValidation();
    testAllowlistRegex();
    testConstantTimeComparison();
    testSecureRandomGeneration();
    testPathTraversalPrevention();
    testParameterizedQueryPattern();
    testIntegerBounds();
    testHtmlEscaping();

    console.log("All security examples passed.");
}

// ── Input validation at the boundary ──────────────────────────────────
function validateUsername(input: string): string {
    if (!input) {
        throw new Error("username cannot be empty");
    }
    if (input.length > 32) {
        throw new Error("username too long");
    }
    if (!/^[a-zA-Z0-9_]+$/.test(input)) {
        throw new Error("invalid characters in username");
    }
    return input;
}

function testInputValidation(): void {
    assert(validateUsername("alice_42") === "alice_42", "valid username");

    for (const bad of ["", "a".repeat(33), "alice; DROP TABLE", "../etc/passwd", "<script>"]) {
        try {
            validateUsername(bad);
            assert(false, `should have rejected: ${bad}`);
        } catch {
            // expected
        }
    }
}

// ── Allowlist regex ───────────────────────────────────────────────────
function isSafeInput(text: string): boolean {
    return /^[a-zA-Z0-9 .,!?]{1,200}$/.test(text);
}

function testAllowlistRegex(): void {
    assert(isSafeInput("Hello, world!"), "safe input");
    assert(!isSafeInput(""), "empty");
    assert(!isSafeInput("<script>alert(1)</script>"), "xss");
    assert(!isSafeInput("a".repeat(201)), "too long");
    assert(!isSafeInput("line\nbreak"), "newline");
}

// ── Constant-time comparison ──────────────────────────────────────────
function testConstantTimeComparison(): void {
    const secret = Buffer.from("super_secret_token_2024");
    const correct = Buffer.from("super_secret_token_2024");
    const wrong = Buffer.from("super_secret_token_2025");

    // BAD: string === leaks timing information
    //   if (userToken === storedToken) { ... }

    // GOOD: crypto.timingSafeEqual is constant-time
    assert(crypto.timingSafeEqual(secret, correct), "matching tokens");
    assert(!crypto.timingSafeEqual(secret, wrong), "different tokens");

    // timingSafeEqual requires same length — check first
    const short = Buffer.from("short");
    assert(secret.length !== short.length, "length differs");
}

// ── Secure random generation ──────────────────────────────────────────
function testSecureRandomGeneration(): void {
    // BAD: Math.random() is not cryptographically secure
    //   const token = Math.random().toString(36);  // predictable!

    // GOOD: crypto.randomBytes uses OS entropy
    const token = crypto.randomBytes(32).toString("hex");
    assert(token.length === 64, "hex token length");

    // UUID v4 for unique identifiers
    const uuid = crypto.randomUUID();
    assert(uuid.length === 36, "uuid length");
    assert(uuid.includes("-"), "uuid format");

    // Two tokens should differ
    const token2 = crypto.randomBytes(32).toString("hex");
    assert(token !== token2, "tokens differ");
}

// ── Path traversal prevention ─────────────────────────────────────────
function safeResolve(baseDir: string, userInput: string): string {
    const resolved = path.resolve(baseDir, userInput);
    const baseResolved = path.resolve(baseDir);

    if (!resolved.startsWith(baseResolved + path.sep) && resolved !== baseResolved) {
        throw new Error(`path traversal detected: ${userInput}`);
    }
    return resolved;
}

function testPathTraversalPrevention(): void {
    const base = fs.mkdtempSync(path.join(os.tmpdir(), "vidya-sec-"));
    try {
        // Safe paths
        assert(safeResolve(base, "photo.jpg").endsWith("photo.jpg"), "safe file");

        // Traversal attacks
        for (const attack of ["../../etc/passwd", "../secret", "normal/../../escape"]) {
            try {
                safeResolve(base, attack);
                assert(false, `should reject: ${attack}`);
            } catch {
                // expected
            }
        }
    } finally {
        fs.rmSync(base, { recursive: true });
    }
}

// ── Parameterized query pattern ───────────────────────────────────────
function testParameterizedQueryPattern(): void {
    const userInput = "'; DROP TABLE users; --";

    // BAD: template literal injection
    const badQuery = `SELECT * FROM users WHERE name = '${userInput}'`;
    assert(badQuery.includes("DROP TABLE"), "injection in bad query");

    // GOOD: parameterized — use your DB driver's parameterization
    // db.query("SELECT * FROM users WHERE name = $1", [userInput])
    const template = "SELECT * FROM users WHERE name = $1";
    const params = [userInput];
    assert(!template.includes("DROP TABLE"), "template is safe");
    assert(params[0] === userInput, "param preserved as data");
}

// ── Integer / size bounds ─────────────────────────────────────────────
function testIntegerBounds(): void {
    // JavaScript numbers lose precision above 2^53
    assert(Number.MAX_SAFE_INTEGER === 9007199254740991, "max safe int");
    assert(!Number.isSafeInteger(2 ** 53), "2^53 is not safe");
    assert(Number.isSafeInteger(2 ** 53 - 1), "2^53 - 1 is safe");

    // Safe allocation with size limits
    function safeAllocate(size: number): Buffer {
        const maxSize = 100 * 1024 * 1024; // 100 MB
        if (!Number.isSafeInteger(size) || size < 0 || size > maxSize) {
            throw new Error(`allocation size ${size} out of range`);
        }
        return Buffer.alloc(size);
    }

    assert(safeAllocate(1024).length === 1024, "safe alloc");
    for (const bad of [-1, 200 * 1024 * 1024, NaN, Infinity]) {
        try {
            safeAllocate(bad);
            assert(false, `should reject size ${bad}`);
        } catch {
            // expected
        }
    }
}

// ── HTML escaping (XSS prevention) ────────────────────────────────────
function escapeHtml(input: string): string {
    return input
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#x27;");
}

function testHtmlEscaping(): void {
    // BAD: inserting user input directly into HTML
    //   element.innerHTML = userInput;  // XSS!

    // GOOD: escape special characters
    assert(
        escapeHtml('<script>alert("xss")</script>') ===
        '&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;',
        "script escaped"
    );
    assert(escapeHtml("normal text") === "normal text", "safe text unchanged");
    assert(escapeHtml("a & b < c") === "a &amp; b &lt; c", "entities escaped");
}

// ── Helpers ───────────────────────────────────────────────────────────
function assert(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

main();
