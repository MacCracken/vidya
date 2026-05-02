// Vidya — Framebuffer Rendering in Rust
//
// 16×16 BGRA8888 framebuffer (1024 bytes) — small enough for byte-
// exact assertions, large enough to exercise stride math and the
// bounds-check gotcha called out in concept.toml.

const FB_W: usize = 16;
const FB_H: usize = 16;
const FB_BPP: usize = 4;
const FB_BYTES: usize = FB_W * FB_H * FB_BPP;

struct FrameBuffer { buf: [u8; FB_BYTES] }

impl FrameBuffer {
    fn new() -> Self { FrameBuffer { buf: [0u8; FB_BYTES] } }

    fn clear(&mut self) { self.buf.fill(0); }

    /// Returns true on write, false on bounds reject.
    fn set(&mut self, x: i32, y: i32, color: u32) -> bool {
        if x < 0 || x >= FB_W as i32 || y < 0 || y >= FB_H as i32 { return false; }
        let off = (y as usize * FB_W + x as usize) * FB_BPP;
        self.buf[off] = (color & 0xFF) as u8;            // B
        self.buf[off + 1] = ((color >> 8) & 0xFF) as u8; // G
        self.buf[off + 2] = ((color >> 16) & 0xFF) as u8;// R
        self.buf[off + 3] = 255;                         // A
        true
    }

    fn get(&self, x: i32, y: i32) -> u32 {
        if x < 0 || x >= FB_W as i32 || y < 0 || y >= FB_H as i32 { return 0; }
        let off = (y as usize * FB_W + x as usize) * FB_BPP;
        let b = self.buf[off] as u32;
        let g = self.buf[off + 1] as u32;
        let r = self.buf[off + 2] as u32;
        (r << 16) | (g << 8) | b
    }

    fn draw_hline(&mut self, x: i32, y: i32, len: i32, color: u32) {
        for i in 0..len { self.set(x + i, y, color); }
    }

    fn draw_vline(&mut self, x: i32, y: i32, len: i32, color: u32) {
        for i in 0..len { self.set(x, y + i, color); }
    }

    fn count_lit(&self) -> usize {
        let mut n = 0;
        for px in self.buf.chunks_exact(FB_BPP) {
            if px[0] != 0 || px[1] != 0 || px[2] != 0 { n += 1; }
        }
        n
    }
}

fn main() {
    let mut fb = FrameBuffer::new();

    // Test 1
    fb.clear();
    assert_eq!(fb.count_lit(), 0, "clear → 0 lit pixels");

    // Test 2: red at (5, 7); BGRA byte check
    fb.set(5, 7, 0xFF0000);
    let off = (7 * FB_W + 5) * FB_BPP;
    assert_eq!(fb.buf[off], 0, "B=0");
    assert_eq!(fb.buf[off + 1], 0, "G=0");
    assert_eq!(fb.buf[off + 2], 255, "R=255");
    assert_eq!(fb.buf[off + 3], 255, "A=255");

    // Test 3
    assert_eq!(fb.get(5, 7), 0xFF0000, "get returns 0xFF0000");

    // Test 4: bounds check
    let lit_before = fb.count_lit();
    fb.set(-1, 5, 0x00FF00);
    fb.set(16, 5, 0x00FF00);
    fb.set(5, -1, 0x00FF00);
    fb.set(5, 16, 0x00FF00);
    assert_eq!(fb.count_lit(), lit_before, "OOB writes rejected");

    // Test 5: return value contract
    assert!(fb.set(3, 3, 0x0000FF), "in-bounds returns true");
    assert!(!fb.set(-5, 3, 0x0000FF), "OOB returns false");

    // Test 6: hline
    fb.clear();
    fb.draw_hline(2, 8, 4, 0x00FF00);
    assert_eq!(fb.count_lit(), 4, "hline: 4 pixels");
    assert_eq!(fb.get(2, 8), 0x00FF00);
    assert_eq!(fb.get(5, 8), 0x00FF00);
    assert_eq!(fb.get(6, 8), 0, "stops at len");

    // Test 7: vline
    fb.clear();
    fb.draw_vline(7, 2, 4, 0x0000FF);
    assert_eq!(fb.count_lit(), 4, "vline: 4 pixels");
    assert_eq!(fb.get(7, 2), 0x0000FF);
    assert_eq!(fb.get(7, 5), 0x0000FF);
    assert_eq!(fb.get(7, 6), 0, "stops at len");

    // Test 8: hline clipped to screen edge
    fb.clear();
    fb.draw_hline(14, 5, 4, 0xFF0000);
    assert_eq!(fb.count_lit(), 2, "hline clipped");

    println!("framebuffer_rendering: 18/18 ok");
}
