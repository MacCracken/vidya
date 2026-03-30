// Vidya — Strings in TypeScript
//
// TypeScript strings are immutable UTF-16 sequences (inherited from JS).
// Template literals provide interpolation. String methods return new
// strings — nothing is modified in place.

function main(): void {
    // ── Creation ────────────────────────────────────────────────────
    const literal: string = "hello";
    const template: string = `${literal} world`;
    const multiline: string = `line one
line two`;
    assert(template === "hello world", "template literal");
    assert(multiline.split("\n").length === 2, "multiline");

    // ── Immutability ───────────────────────────────────────────────
    const s: string = "hello";
    // s[0] = "H";  // ← no effect (strings are immutable)
    const modified: string = "H" + s.slice(1);
    assert(modified === "Hello", "immutable concat");

    // ── Template literals: interpolation ───────────────────────────
    const name: string = "world";
    const greeting: string = `hello, ${name}!`;
    assert(greeting === "hello, world!", "interpolation");

    // Expressions in templates
    assert(`${2 + 2}` === "4", "expression interpolation");
    assert(`${"hello".toUpperCase()}` === "HELLO", "method interpolation");

    // Tagged templates (advanced)
    function tag(strings: TemplateStringsArray, ...values: unknown[]): string {
        return strings.reduce((acc, str, i) =>
            acc + str + (values[i] !== undefined ? String(values[i]).toUpperCase() : ""), "");
    }
    assert(tag`hello ${"world"}` === "hello WORLD", "tagged template");

    // ── Common methods ─────────────────────────────────────────────
    assert("  hello  ".trim() === "hello", "trim");
    assert("hello world".split(" ").length === 2, "split");
    assert("hello".toUpperCase() === "HELLO", "upper");
    assert("HELLO".toLowerCase() === "hello", "lower");
    assert("hello world".replace("world", "ts") === "hello ts", "replace");
    assert("hello world".includes("world"), "includes");
    assert("hello".startsWith("hel"), "startsWith");
    assert("hello".endsWith("llo"), "endsWith");
    assert("hello world".indexOf("world") === 6, "indexOf");

    // ── replaceAll (ES2021) ────────────────────────────────────────
    assert("a-b-c".replaceAll("-", "_") === "a_b_c", "replaceAll");

    // ── Padding and repeating ──────────────────────────────────────
    assert("5".padStart(3, "0") === "005", "padStart");
    assert("hi".padEnd(5, ".") === "hi...", "padEnd");
    assert("ab".repeat(3) === "ababab", "repeat");

    // ── String length and character access ──────────────────────────
    assert("hello".length === 5, "length");
    assert("hello"[0] === "h", "index access");
    assert("hello".charAt(4) === "o", "charAt");
    assert("hello".charCodeAt(0) === 104, "charCodeAt");

    // ── Unicode: UTF-16 gotchas ────────────────────────────────────
    const emoji: string = "hello 🌍";
    assert(emoji.length === 8, "emoji length (UTF-16 units, not chars!)");
    // 🌍 is a surrogate pair — counts as 2 UTF-16 units

    // Use Array.from or spread for correct character counting
    assert([...emoji].length === 7, "spread character count");

    const cafe: string = "café";
    assert(cafe.length === 4, "café length");
    assert([...cafe].length === 4, "café char count");

    // ── Regex matching ─────────────────────────────────────────────
    const match = "hello123".match(/^[a-z]+(\d+)$/);
    assert(match !== null, "regex match");
    assert(match![1] === "123", "capture group");

    assert(/^\d+$/.test("42"), "regex test");
    assert(!/^\d+$/.test("abc"), "regex no match");

    // ── String conversion ──────────────────────────────────────────
    assert(String(42) === "42", "number to string");
    assert((42).toString(16) === "2a", "hex string");
    assert(parseInt("42", 10) === 42, "parse int");
    assert(parseFloat("3.14") === 3.14, "parse float");

    // ── Joining arrays ─────────────────────────────────────────────
    const words: string[] = ["hello", "world", "from", "typescript"];
    assert(words.join(" ") === "hello world from typescript", "join");

    // ── String comparison ──────────────────────────────────────────
    assert("hello" === "hello", "strict equality");
    assert("hello".localeCompare("Hello", undefined, { sensitivity: "base" }) === 0,
           "locale compare case insensitive");

    // ── Type narrowing with strings ────────────────────────────────
    type Direction = "north" | "south" | "east" | "west";
    const dir: Direction = "north";
    assert(dir === "north", "string literal type");

    console.log("All string examples passed.");
}

function assert(condition: boolean, msg: string): void {
    if (!condition) {
        throw new Error(`Assertion failed: ${msg}`);
    }
}

main();
