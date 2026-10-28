// Vidya — Audio DSP — Rust port. Q15 fixed-point throughout.

const SCALE: i64 = 15;
const ONE: i64 = 32768;
const SMAX: i64 = 32767;
const SMIN: i64 = -32767;

fn q_mul(a: i64, b: i64) -> i64 {
    let p = a * b;
    if p < 0 { -((-p) >> SCALE) } else { p >> SCALE }
}

fn clip(s: i64) -> i64 {
    if s > SMAX { SMAX }
    else if s < SMIN { SMIN }
    else { s }
}

struct Biquad {
    b0: i64, b1: i64, b2: i64, a1: i64, a2: i64,
    x1: i64, x2: i64, y1: i64, y2: i64,
}

impl Biquad {
    fn new() -> Self {
        Biquad { b0:0, b1:0, b2:0, a1:0, a2:0, x1:0, x2:0, y1:0, y2:0 }
    }
    fn set(&mut self, b0: i64, b1: i64, b2: i64, a1: i64, a2: i64) {
        self.b0=b0; self.b1=b1; self.b2=b2; self.a1=a1; self.a2=a2;
        self.x1=0; self.x2=0; self.y1=0; self.y2=0;
    }
    fn lowpass_1pole(&mut self, a_q15: i64) {
        self.set(a_q15, 0, 0, a_q15 - ONE, 0);
    }
    fn step(&mut self, x: i64) -> i64 {
        let y = q_mul(self.b0, x) + q_mul(self.b1, self.x1) + q_mul(self.b2, self.x2)
              - q_mul(self.a1, self.y1) - q_mul(self.a2, self.y2);
        self.x2 = self.x1; self.x1 = x;
        self.y2 = self.y1; self.y1 = y;
        y
    }
}

fn fir_step(taps: &[i64], history: &mut [i64], x_new: i64) -> i64 {
    for i in (1..history.len()).rev() {
        history[i] = history[i - 1];
    }
    history[0] = x_new;
    taps.iter().zip(history.iter()).map(|(t, h)| q_mul(*t, *h)).sum()
}

fn peak(buffer: &[i64]) -> i64 {
    buffer.iter().map(|s| s.abs()).max().unwrap_or(0)
}

fn mean_absolute(buffer: &[i64]) -> i64 {
    buffer.iter().map(|s| s.abs()).sum::<i64>() / buffer.len() as i64
}

fn main() {
    assert_eq!(q_mul(ONE, 100), 100);
    assert_eq!(q_mul(ONE/2, ONE/2), ONE/4);
    let r = q_mul(ONE/2, SMAX);
    assert!(r >= 16383 && r <= 16384);

    assert_eq!(clip(50000), SMAX);
    assert_eq!(clip(-50000), SMIN);
    assert_eq!(clip(1234), 1234);

    {
        let mut b = Biquad::new();
        b.lowpass_1pole(3277);
        for _ in 0..200 { b.step(30000); }
        assert!(b.y1 >= 29900 && b.y1 <= 30100, "DC settled: {}", b.y1);
    }
    {
        let mut b = Biquad::new();
        b.lowpass_1pole(3277);
        for i in 0..200 {
            let x = if i & 1 == 0 { 20000 } else { -20000 };
            b.step(x);
        }
        assert!(b.y1.abs() < 2000, "Nyquist: {}", b.y1);
    }
    {
        let taps = [ONE, 0, 0];
        let mut history = [0i64; 3];
        assert_eq!(fir_step(&taps, &mut history, 1234), 1234);
        assert_eq!(fir_step(&taps, &mut history, 5678), 5678);
    }
    {
        let third = ONE / 3;
        let taps = [third, third, third];
        let mut history = [0i64; 3];
        fir_step(&taps, &mut history, 9000);
        fir_step(&taps, &mut history, 9000);
        let y = fir_step(&taps, &mut history, 9000);
        assert!(y >= 8990 && y <= 9010, "moving avg: {}", y);
    }
    assert_eq!(peak(&[100, -5000, 200, 3000, -1500]), 5000);
    assert_eq!(mean_absolute(&[4000; 8]), 4000);
    {
        let buf: Vec<i64> = (0..8).map(|i| if i & 1 == 0 { 4000 } else { -4000 }).collect();
        assert_eq!(mean_absolute(&buf), 4000);
    }

    println!("audio_dsp: 9 tests, 14 assertions ok");
}
