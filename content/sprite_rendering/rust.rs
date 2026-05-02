// Vidya — Sprite Rendering in Rust
//
// Software sprite blitting to a flat 8-bit palette framebuffer.
// The framebuffer is a `Vec<u8>` indexed `y * SCREEN_W + x`.
// `Vec<u8>` gives us bounds-checked indexing in debug builds and a
// contiguous heap allocation that maps directly to the C/Cyrius
// `uint8_t*` layout — matching every other port byte-for-byte.

#![allow(dead_code)]

const SCREEN_W: usize = 320;
const SCREEN_H: usize = 240;
const FB_SIZE: usize = SCREEN_W * SCREEN_H; // 76_800
const COLOR_KEY: u8 = 0;
const FX_SHIFT: u32 = 16;

struct Framebuffer {
    pixels: Vec<u8>,
}

impl Framebuffer {
    fn new() -> Self {
        Framebuffer { pixels: vec![0u8; FB_SIZE] }
    }

    fn clear(&mut self, color: u8) {
        for p in self.pixels.iter_mut() {
            *p = color;
        }
    }

    fn get(&self, x: i32, y: i32) -> u8 {
        if x < 0 || x >= SCREEN_W as i32 || y < 0 || y >= SCREEN_H as i32 {
            return 0;
        }
        self.pixels[y as usize * SCREEN_W + x as usize]
    }

    fn set(&mut self, x: i32, y: i32, color: u8) {
        if x < 0 || x >= SCREEN_W as i32 || y < 0 || y >= SCREEN_H as i32 {
            return;
        }
        self.pixels[y as usize * SCREEN_W + x as usize] = color;
    }
}

struct Sprite<'a> {
    data: &'a [u8],
    width: i32,
    height: i32,
}

fn blit(fb: &mut Framebuffer, sprite: &Sprite, mut dst_x: i32, mut dst_y: i32) {
    let mut start_x: i32 = 0;
    let mut start_y: i32 = 0;
    let mut end_x: i32 = sprite.width;
    let mut end_y: i32 = sprite.height;

    if dst_x < 0 {
        start_x = -dst_x;
        dst_x = 0;
    }
    if dst_y < 0 {
        start_y = -dst_y;
        dst_y = 0;
    }
    if dst_x + (end_x - start_x) > SCREEN_W as i32 {
        end_x = start_x + (SCREEN_W as i32 - dst_x);
    }
    if dst_y + (end_y - start_y) > SCREEN_H as i32 {
        end_y = start_y + (SCREEN_H as i32 - dst_y);
    }

    let mut sy = start_y;
    while sy < end_y {
        let mut sx = start_x;
        while sx < end_x {
            let pixel = sprite.data[(sy * sprite.width + sx) as usize];
            if pixel != COLOR_KEY {
                let dx = dst_x + (sx - start_x);
                let dy = dst_y + (sy - start_y);
                fb.pixels[dy as usize * SCREEN_W + dx as usize] = pixel;
            }
            sx += 1;
        }
        sy += 1;
    }
}

fn blit_scaled(fb: &mut Framebuffer, sprite: &Sprite, dst_x: i32, dst_y: i32, dst_w: i32, dst_h: i32) {
    if dst_w <= 0 || dst_h <= 0 {
        return;
    }
    let step_x: i32 = ((sprite.width as i64) << FX_SHIFT) as i32 / dst_w;
    let step_y: i32 = ((sprite.height as i64) << FX_SHIFT) as i32 / dst_h;

    let mut src_y: i32 = 0;
    for dy in 0..dst_h {
        let screen_y = dst_y + dy;
        if screen_y >= 0 && screen_y < SCREEN_H as i32 {
            let row_base = ((src_y >> FX_SHIFT) * sprite.width) as usize;
            let mut src_x: i32 = 0;
            for dx in 0..dst_w {
                let screen_x = dst_x + dx;
                if screen_x >= 0 && screen_x < SCREEN_W as i32 {
                    let pixel = sprite.data[row_base + (src_x >> FX_SHIFT) as usize];
                    if pixel != COLOR_KEY {
                        fb.pixels[screen_y as usize * SCREEN_W + screen_x as usize] = pixel;
                    }
                }
                src_x += step_x;
            }
        }
        src_y += step_y;
    }
}

fn test_sprite_data() -> [u8; 16] {
    // 4x4 sprite: rounded square with two color levels.
    [
        0, 1, 1, 0,
        1, 2, 2, 1,
        1, 2, 2, 1,
        0, 1, 1, 0,
    ]
}

fn main() {
    let data = test_sprite_data();
    let sprite = Sprite { data: &data, width: 4, height: 4 };
    let mut fb = Framebuffer::new();

    // clear
    fb.clear(42);
    assert_eq!(fb.get(100, 100), 42, "clear fills framebuffer");
    assert_eq!(fb.get(0, 0), 42, "clear fills corner");
    assert_eq!(fb.get(319, 239), 42, "clear fills last pixel");

    // blit opaque
    fb.clear(0);
    blit(&mut fb, &sprite, 10, 10);
    assert_eq!(fb.get(11, 11), 2, "blit writes center pixel");
    assert_eq!(fb.get(12, 11), 2, "blit writes adjacent center pixel");

    // transparency
    fb.clear(99);
    blit(&mut fb, &sprite, 10, 10);
    assert_eq!(fb.get(10, 10), 99, "transparent corner preserves bg");
    assert_eq!(fb.get(13, 10), 99, "top-right transparent");
    assert_eq!(fb.get(11, 10), 1, "non-transparent written");

    // clipping right
    fb.clear(0);
    blit(&mut fb, &sprite, 318, 0);
    assert_eq!(fb.get(319, 1), 2, "clipped sprite visible at right edge");
    assert_eq!(fb.get(318, 0), 0, "clipped transparent pixel");

    // clipping left
    fb.clear(0);
    blit(&mut fb, &sprite, -2, 0);
    assert_eq!(fb.get(0, 1), 2, "left-clipped sprite visible");

    // scaled blit
    fb.clear(0);
    blit_scaled(&mut fb, &sprite, 20, 20, 8, 8);
    assert_eq!(fb.get(22, 22), 2, "2x scaled center pixel");
    assert_eq!(fb.get(23, 23), 2, "2x scaled adjacent center");

    // depth sort (painter's algorithm)
    fb.clear(0);
    blit(&mut fb, &sprite, 50, 50);
    assert_eq!(fb.get(51, 51), 2, "first sprite drawn");
    fb.set(51, 51, 7);
    assert_eq!(fb.get(51, 51), 7, "later draw overwrites");

    // scaled shrink
    fb.clear(0);
    blit_scaled(&mut fb, &sprite, 100, 100, 2, 2);
    let any = fb.get(100, 100) != 0
        || fb.get(101, 100) != 0
        || fb.get(100, 101) != 0
        || fb.get(101, 101) != 0;
    assert!(any, "shrunk sprite has visible pixels");

    println!("All sprite_rendering examples passed.");
}
