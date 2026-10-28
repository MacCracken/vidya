// Vidya — Input/Output in Rust
//
// Rust I/O is built on the Read and Write traits. BufReader/BufWriter
// add buffering. File, TcpStream, stdin/stdout all implement these
// traits — making I/O composable and generic. Errors are explicit
// via io::Result.

use std::io::{self, BufRead, BufReader, BufWriter, Read, Write};

fn main() {
    // ── Writing to a buffer (simulates file/stdout) ────────────────
    let mut output = Vec::new();
    write!(output, "hello ").unwrap();
    write!(output, "world").unwrap();
    assert_eq!(String::from_utf8(output).unwrap(), "hello world");

    // ── BufWriter: batch small writes ──────────────────────────────
    let mut buf = BufWriter::new(Vec::new());
    for i in 0..100 {
        writeln!(buf, "line {i}").unwrap();
    }
    buf.flush().unwrap();
    let content = String::from_utf8(buf.into_inner().unwrap()).unwrap();
    assert!(content.starts_with("line 0\n"));
    assert!(content.contains("line 99\n"));

    // ── BufReader: line-by-line reading ────────────────────────────
    let data = "first\nsecond\nthird\n";
    let reader = BufReader::new(data.as_bytes());
    let lines: Vec<String> = reader.lines().map(|l| l.unwrap()).collect();
    assert_eq!(lines, vec!["first", "second", "third"]);

    // ── Read trait: read_to_string, read_exact ─────────────────────
    let mut reader = "hello world".as_bytes();
    let mut buf = String::new();
    reader.read_to_string(&mut buf).unwrap();
    assert_eq!(buf, "hello world");

    // read_exact: demands exactly N bytes
    let mut reader = "hello".as_bytes();
    let mut exact = [0u8; 5];
    reader.read_exact(&mut exact).unwrap();
    assert_eq!(&exact, b"hello");

    // ── Cursor: in-memory Read+Write+Seek ──────────────────────────
    use std::io::{Cursor, Seek, SeekFrom};
    let mut cursor = Cursor::new(Vec::new());
    cursor.write_all(b"hello world").unwrap();
    cursor.seek(SeekFrom::Start(6)).unwrap();

    let mut rest = String::new();
    cursor.read_to_string(&mut rest).unwrap();
    assert_eq!(rest, "world");

    // ── Chain readers ──────────────────────────────────────────────
    let part1 = "hello ".as_bytes();
    let part2 = "world".as_bytes();
    let mut chained = part1.chain(part2);
    let mut result = String::new();
    chained.read_to_string(&mut result).unwrap();
    assert_eq!(result, "hello world");

    // ── Write to multiple destinations ─────────────────────────────
    // std::io doesn't have tee built-in, but you can implement it
    struct Tee<A: Write, B: Write>(A, B);
    impl<A: Write, B: Write> Write for Tee<A, B> {
        fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
            let n = self.0.write(buf)?;     // may be a short write...
            self.1.write_all(&buf[..n])?;   // ...so mirror exactly those n bytes
            Ok(n)
        }
        fn flush(&mut self) -> io::Result<()> {
            self.0.flush()?;
            self.1.flush()
        }
    }
    let mut tee = Tee(Vec::new(), Vec::new());
    tee.write_all(b"shared data").unwrap();
    assert_eq!(tee.0, b"shared data");
    assert_eq!(tee.1, b"shared data");

    // ── Formatting with write! ─────────────────────────────────────
    let mut buf = Vec::new();
    write!(buf, "{:>10}", "right").unwrap();
    assert_eq!(String::from_utf8(buf).unwrap(), "     right");

    // ── Bytes iterator ─────────────────────────────────────────────
    let reader = "abc".as_bytes();
    let bytes: Vec<u8> = reader.bytes().map(|b| b.unwrap()).collect();
    assert_eq!(bytes, vec![b'a', b'b', b'c']);

    // ── Error handling: io::Result ─────────────────────────────────
    fn read_exact_or_eof(reader: &mut &[u8], n: usize) -> io::Result<Vec<u8>> {
        let mut buf = vec![0u8; n];
        reader.read_exact(&mut buf)?;
        Ok(buf)
    }

    let mut data = "hi".as_bytes();
    let result = read_exact_or_eof(&mut data, 5);
    assert!(result.is_err()); // only 2 bytes available

    let mut data = "hello".as_bytes();
    let result = read_exact_or_eof(&mut data, 5);
    assert!(result.is_ok());

    println!("All input/output examples passed.");
}
