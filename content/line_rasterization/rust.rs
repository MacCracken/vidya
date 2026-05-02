// Vidya — Line Rasterization (Bresenham) in Rust
//
// All-octant integer Bresenham on a 16x16 byte framebuffer.

const FB_W: i32 = 16;
const FB_H: i32 = 16;
const FB_BYTES: usize = (FB_W * FB_H) as usize;

struct Fb { buf: [u8; FB_BYTES] }

impl Fb {
    fn new() -> Self { Fb { buf: [0; FB_BYTES] } }
    fn clear(&mut self) { self.buf.fill(0); }
    fn set(&mut self, x: i32, y: i32, val: u8) {
        if x < 0 || x >= FB_W || y < 0 || y >= FB_H { return; }
        self.buf[(y * FB_W + x) as usize] = val;
    }
    fn get(&self, x: i32, y: i32) -> u8 {
        if x < 0 || x >= FB_W || y < 0 || y >= FB_H { return 0; }
        self.buf[(y * FB_W + x) as usize]
    }
    fn count_lit(&self) -> usize { self.buf.iter().filter(|&&v| v != 0).count() }
}

fn draw_line(fb: &mut Fb, x0: i32, y0: i32, x1: i32, y1: i32, val: u8) {
    let dx = (x1 - x0).abs();
    let dy = (y1 - y0).abs();
    let sx = if x1 > x0 { 1 } else if x1 < x0 { -1 } else { 0 };
    let sy = if y1 > y0 { 1 } else if y1 < y0 { -1 } else { 0 };
    let mut err = dx - dy;
    let (mut x, mut y) = (x0, y0);
    loop {
        fb.set(x, y, val);
        if x == x1 && y == y1 { return; }
        let e2 = err * 2;
        if e2 > -dy { err -= dy; x += sx; }
        if e2 < dx { err += dx; y += sy; }
    }
}

fn main() {
    let mut fb = Fb::new();

    // 1: horizontal
    fb.clear();
    draw_line(&mut fb, 2, 5, 8, 5, 1);
    assert_eq!(fb.count_lit(), 7);
    assert_eq!(fb.get(2, 5), 1);
    assert_eq!(fb.get(8, 5), 1);
    assert_eq!(fb.get(5, 5), 1);
    assert_eq!(fb.get(5, 6), 0);

    // 2: vertical
    fb.clear();
    draw_line(&mut fb, 5, 2, 5, 8, 1);
    assert_eq!(fb.count_lit(), 7);
    assert_eq!(fb.get(5, 2), 1);
    assert_eq!(fb.get(5, 8), 1);
    assert_eq!(fb.get(5, 5), 1);
    assert_eq!(fb.get(6, 5), 0);

    // 3: +diagonal
    fb.clear();
    draw_line(&mut fb, 2, 2, 7, 7, 1);
    assert_eq!(fb.count_lit(), 6);
    assert_eq!(fb.get(2, 2), 1);
    assert_eq!(fb.get(7, 7), 1);
    assert_eq!(fb.get(5, 5), 1);
    assert_eq!(fb.get(5, 4), 0);

    // 4: -diagonal
    fb.clear();
    draw_line(&mut fb, 2, 7, 7, 2, 1);
    assert_eq!(fb.count_lit(), 6);
    assert_eq!(fb.get(2, 7), 1);
    assert_eq!(fb.get(7, 2), 1);
    assert_eq!(fb.get(5, 4), 1);

    // 5: steep
    fb.clear();
    draw_line(&mut fb, 3, 1, 5, 11, 1);
    assert_eq!(fb.count_lit(), 11);
    assert_eq!(fb.get(3, 1), 1);
    assert_eq!(fb.get(5, 11), 1);

    // 6: single point
    fb.clear();
    draw_line(&mut fb, 8, 8, 8, 8, 1);
    assert_eq!(fb.count_lit(), 1);
    assert_eq!(fb.get(8, 8), 1);

    // 7: reversed
    fb.clear();
    draw_line(&mut fb, 8, 5, 2, 5, 1);
    assert_eq!(fb.count_lit(), 7);
    assert_eq!(fb.get(2, 5), 1);
    assert_eq!(fb.get(8, 5), 1);

    println!("line_rasterization: 27/27 ok");
}
