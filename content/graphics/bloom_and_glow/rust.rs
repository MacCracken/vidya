// Vidya — Bloom and Glow in Rust
//
// 1-pixel additive bloom on a 16x16 single-channel intensity buffer.
// Threshold + per-channel saturation clamp mirrors cyrius.cyr.

const FB_W: i32 = 16;
const FB_H: i32 = 16;
const FB_BYTES: usize = (FB_W * FB_H) as usize;
const THRESHOLD: u8 = 128;
const GLOW_FRAC: u8 = 2;

fn fb_set(fb: &mut [u8], x: i32, y: i32, v: u8) {
    if x < 0 || x >= FB_W || y < 0 || y >= FB_H { return; }
    fb[(y * FB_W + x) as usize] = v;
}

fn fb_get(fb: &[u8], x: i32, y: i32) -> u8 {
    if x < 0 || x >= FB_W || y < 0 || y >= FB_H { return 0; }
    fb[(y * FB_W + x) as usize]
}

fn fb_add(fb: &mut [u8], x: i32, y: i32, delta: u8) {
    if x < 0 || x >= FB_W || y < 0 || y >= FB_H { return; }
    let idx = (y * FB_W + x) as usize;
    fb[idx] = fb[idx].saturating_add(delta);
}

fn apply_bloom(src: &[u8], dst: &mut [u8], threshold: u8) {
    dst.copy_from_slice(src);
    for y in 0..FB_H {
        for x in 0..FB_W {
            let v = src[(y * FB_W + x) as usize];
            if v >= threshold {
                let glow = v / GLOW_FRAC;
                fb_add(dst, x - 1, y, glow);
                fb_add(dst, x + 1, y, glow);
                fb_add(dst, x, y - 1, glow);
                fb_add(dst, x, y + 1, glow);
            }
        }
    }
}

fn count_lit(fb: &[u8]) -> usize { fb.iter().filter(|&&v| v != 0).count() }

fn main() {
    let mut src = [0u8; FB_BYTES];
    let mut dst = [0u8; FB_BYTES];

    // 1
    apply_bloom(&src, &mut dst, THRESHOLD);
    assert_eq!(count_lit(&dst), 0, "empty");

    // 2: single bright at center
    src.fill(0);
    fb_set(&mut src, 8, 8, 200);
    apply_bloom(&src, &mut dst, THRESHOLD);
    assert_eq!(fb_get(&dst, 8, 8), 200);
    assert_eq!(fb_get(&dst, 7, 8), 100);
    assert_eq!(fb_get(&dst, 9, 8), 100);
    assert_eq!(fb_get(&dst, 8, 7), 100);
    assert_eq!(fb_get(&dst, 8, 9), 100);
    assert_eq!(fb_get(&dst, 7, 7), 0);
    assert_eq!(count_lit(&dst), 5);

    // 3: saturation clamp
    src.fill(0);
    fb_set(&mut src, 8, 8, 200);
    fb_set(&mut src, 9, 8, 250);
    apply_bloom(&src, &mut dst, THRESHOLD);
    assert_eq!(fb_get(&dst, 9, 8), 255, "clamp");
    assert_eq!(fb_get(&dst, 8, 8), 255, "summed clamp");

    // 4: threshold cutoff
    src.fill(0);
    fb_set(&mut src, 8, 8, 100);
    apply_bloom(&src, &mut dst, THRESHOLD);
    assert_eq!(fb_get(&dst, 8, 8), 100);
    assert_eq!(fb_get(&dst, 7, 8), 0);
    assert_eq!(count_lit(&dst), 1);

    // 5: edge pixel
    src.fill(0);
    fb_set(&mut src, 0, 0, 200);
    apply_bloom(&src, &mut dst, THRESHOLD);
    assert_eq!(fb_get(&dst, 0, 0), 200);
    assert_eq!(fb_get(&dst, 1, 0), 100);
    assert_eq!(fb_get(&dst, 0, 1), 100);
    assert_eq!(count_lit(&dst), 3);

    // 6: two adjacent bright sum at midpoint
    src.fill(0);
    fb_set(&mut src, 4, 8, 200);
    fb_set(&mut src, 6, 8, 200);
    apply_bloom(&src, &mut dst, THRESHOLD);
    assert_eq!(fb_get(&dst, 5, 8), 200);
    assert_eq!(fb_get(&dst, 3, 8), 100);
    assert_eq!(fb_get(&dst, 7, 8), 100);

    println!("bloom_and_glow: 20/20 ok");
}
