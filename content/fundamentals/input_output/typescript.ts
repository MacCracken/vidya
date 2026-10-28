// Vidya — Input/Output in TypeScript
//
// Node.js/Deno I/O uses streams (Readable, Writable), the fs module
// for files, and Buffers for binary data. Async I/O is the default —
// synchronous variants exist but block the event loop. The *Sync calls
// below keep the basics short (fine in a one-shot script); the async
// section shows what a server should use.

import * as fs from "node:fs";
import * as fsp from "node:fs/promises";
import * as path from "node:path";
import * as os from "node:os";
import { Readable, Writable } from "node:stream";
import { pipeline } from "node:stream/promises";

async function main(): Promise<void> {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "vidya-"));
    const tmpFile = path.join(tmpDir, "test.txt");

    try {
        // ── Writing to files ───────────────────────────────────────
        fs.writeFileSync(tmpFile, "line 1\nline 2\nline 3\n");

        // ── Reading entire file ────────────────────────────────────
        const content = fs.readFileSync(tmpFile, "utf-8");
        assert(content === "line 1\nline 2\nline 3\n", "read all");

        // ── Reading as Buffer (binary) ─────────────────────────────
        const buf = fs.readFileSync(tmpFile);
        assert(Buffer.isBuffer(buf), "is Buffer");
        assert(buf.length > 0, "buffer has data");

        // ── Line-by-line (split) ───────────────────────────────────
        // Holds the whole file in memory; see readLines() below for
        // streaming a file of any size.
        const lines = content.trimEnd().split("\n");
        assert(lines.length === 3, "split lines");
        assert(lines[0] === "line 1", "first line");

        // ── Append mode ────────────────────────────────────────────
        fs.appendFileSync(tmpFile, "line 4\n");
        const updated = fs.readFileSync(tmpFile, "utf-8");
        assert(updated.includes("line 4"), "append");

        // ── Binary I/O ────────────────────────────────────────────
        const binFile = path.join(tmpDir, "test.bin");
        const binData = Buffer.from([0x00, 0x01, 0x02, 0xff]);
        fs.writeFileSync(binFile, binData);

        const readBin = fs.readFileSync(binFile);
        assert(readBin[0] === 0x00, "binary byte 0");
        assert(readBin[3] === 0xff, "binary byte 3");

        // ── Buffer operations ──────────────────────────────────────
        const b1 = Buffer.from("hello ");
        const b2 = Buffer.from("world");
        const combined = Buffer.concat([b1, b2]);
        assert(combined.toString() === "hello world", "buffer concat");

        // ── TextEncoder/TextDecoder: encoding ──────────────────────
        const encoder = new TextEncoder();
        const encoded = encoder.encode("café");
        assert(encoded.length === 5, "UTF-8 bytes");

        const decoder = new TextDecoder("utf-8");
        const decoded = decoder.decode(encoded);
        assert(decoded === "café", "decode roundtrip");

        // ── File stats ─────────────────────────────────────────────
        const stats = fs.statSync(tmpFile);
        assert(stats.isFile(), "is file");
        assert(stats.size > 0, "has size");

        // ── Directory operations ───────────────────────────────────
        const subDir = path.join(tmpDir, "sub");
        fs.mkdirSync(subDir);
        assert(fs.statSync(subDir).isDirectory(), "mkdir");
        fs.rmdirSync(subDir);

        // ── Path manipulation ──────────────────────────────────────
        assert(path.basename("/foo/bar.txt") === "bar.txt", "basename");
        assert(path.extname("file.txt") === ".txt", "extname");
        assert(path.join("a", "b", "c") === "a/b/c", "join");

        // ── In-memory streams ──────────────────────────────────────
        const chunks: string[] = [];
        const writable = new Writable({
            write(chunk, _encoding, callback) {
                chunks.push(chunk.toString());
                callback();
            },
        });
        writable.write("hello ");
        writable.write("world");
        writable.end();
        assert(chunks.join("") === "hello world", "writable stream");

        // ── Async I/O: fs/promises + streams ──────────────────────
        // Nothing here blocks the event loop.
        const asyncFile = path.join(tmpDir, "async.txt");
        await fsp.writeFile(asyncFile, "a\nb\nc\n");
        assert((await fsp.readFile(asyncFile, "utf-8")) === "a\nb\nc\n", "async read");

        // Streaming line-by-line: memory is bounded by the longest line,
        // not the file size. `await using` closes the handle on scope exit.
        {
            await using fh = await fsp.open(asyncFile);
            const streamed: string[] = [];
            for await (const line of fh.readLines()) streamed.push(line);
            assert(streamed.join(",") === "a,b,c", "readLines streams lines");
        }

        // Readable → Writable with backpressure and error propagation
        const piped: string[] = [];
        await pipeline(
            Readable.from(["chunk1 ", "chunk2"]),
            new Writable({
                write(chunk, _encoding, callback) {
                    piped.push(chunk.toString());
                    callback();
                },
            }),
        );
        assert(piped.join("") === "chunk1 chunk2", "pipeline Readable → Writable");

        // ── Error handling ─────────────────────────────────────────
        // Check the error code: a bare catch would also "pass" on
        // EACCES, EISDIR, or a typo in the code above.
        let code: string | undefined;
        try {
            fs.readFileSync("/nonexistent/path.txt");
        } catch (e) {
            code = (e as NodeJS.ErrnoException).code;
        }
        assert(code === "ENOENT", "file not found error is ENOENT");

        // ── Cleanup ────────────────────────────────────────────────
        fs.unlinkSync(tmpFile);
        fs.unlinkSync(binFile);
        await fsp.unlink(asyncFile);
    } finally {
        fs.rmSync(tmpDir, { recursive: true, force: true });
    }

    console.log("All input/output examples passed.");
}

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

main().catch((err: unknown) => {
    console.error(err);
    process.exit(1);
});
