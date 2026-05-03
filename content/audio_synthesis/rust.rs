// Vidya — Audio Synthesis — Rust port. Q15 fixed-point.
//
// Mirrors naad's API surface (Waveform, EnvelopeState, Adsr,
// Voice, gate_on/off). naad uses f32 + PolyBLEP for production;
// this port uses Q15 + naive waveforms for cross-port portability.

const SCALE: i32 = 15;
const ONE: i32 = 32768;
const PHASE_MASK: u32 = 65535;
const PHASE_HALF: u32 = 32768;

fn q_mul(a: i32, b: i32) -> i32 {
    let p = a as i64 * b as i64;
    if p < 0 { -((-p >> SCALE) as i32) } else { (p >> SCALE) as i32 }
}

fn phase_advance(current: u32, inc: u32) -> u32 {
    (current + inc) & PHASE_MASK
}

const SINE_TABLE: [i32; 16] = [
    0, 12540, 23170, 30274, 32767, 30274, 23170, 12540,
    0, -12540, -23170, -30274, -32767, -30274, -23170, -12540,
];

fn osc_sine(phase: u32) -> i32 { SINE_TABLE[(phase >> 12) as usize] }
fn osc_saw(phase: u32) -> i32 { phase as i32 - PHASE_HALF as i32 }
fn osc_square(phase: u32) -> i32 { if phase < PHASE_HALF { 32767 } else { -32767 } }

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
enum EnvelopeState { Idle, Attack, Decay, Sustain, Release }

struct Adsr {
    state: EnvelopeState,
    level: i32,
    stage_samples: i32,
    release_start: i32,
    attack_samples: i32,
    decay_samples: i32,
    sustain_level: i32,
    release_samples: i32,
}

impl Adsr {
    fn new() -> Self {
        Adsr {
            state: EnvelopeState::Idle, level: 0, stage_samples: 0, release_start: 0,
            attack_samples: 0, decay_samples: 0, sustain_level: 0, release_samples: 0,
        }
    }
    fn set_params(&mut self, attack: i32, decay: i32, sustain: i32, release: i32) {
        self.attack_samples = attack;
        self.decay_samples = decay;
        self.sustain_level = sustain;
        self.release_samples = release;
    }
    fn gate_on(&mut self) {
        self.state = EnvelopeState::Attack;
        self.stage_samples = 0;
    }
    fn gate_off(&mut self) -> bool {
        if self.state == EnvelopeState::Idle { return false; }
        self.release_start = self.level;
        self.state = EnvelopeState::Release;
        self.stage_samples = 0;
        true
    }
    fn step(&mut self) -> i32 {
        match self.state {
            EnvelopeState::Idle => { self.level = 0; 0 }
            EnvelopeState::Attack => {
                let inc = ONE / self.attack_samples;
                self.level += inc;
                self.stage_samples += 1;
                if self.stage_samples >= self.attack_samples {
                    self.level = ONE;
                    self.state = EnvelopeState::Decay;
                    self.stage_samples = 0;
                }
                self.level
            }
            EnvelopeState::Decay => {
                let dec = (ONE - self.sustain_level) / self.decay_samples;
                self.level -= dec;
                self.stage_samples += 1;
                if self.stage_samples >= self.decay_samples {
                    self.level = self.sustain_level;
                    self.state = EnvelopeState::Sustain;
                    self.stage_samples = 0;
                }
                self.level
            }
            EnvelopeState::Sustain => { self.level = self.sustain_level; self.level }
            EnvelopeState::Release => {
                let dec = self.release_start / self.release_samples;
                self.level -= dec;
                self.stage_samples += 1;
                if self.stage_samples >= self.release_samples {
                    self.level = 0;
                    self.state = EnvelopeState::Idle;
                    self.stage_samples = 0;
                }
                self.level
            }
        }
    }
}

#[derive(Copy, Clone)]
enum Waveform { Sine, Saw, Square }

struct Voice {
    waveform: Waveform,
    phase: u32,
    phase_inc: u32,
}

impl Voice {
    fn new(waveform: Waveform, phase_inc: u32) -> Self {
        Voice { waveform, phase: 0, phase_inc }
    }
    fn oscillator(&self, phase: u32) -> i32 {
        match self.waveform {
            Waveform::Sine => osc_sine(phase),
            Waveform::Saw => osc_saw(phase),
            Waveform::Square => osc_square(phase),
        }
    }
    fn step(&mut self, env: &mut Adsr) -> i32 {
        let osc = self.oscillator(self.phase);
        self.phase = phase_advance(self.phase, self.phase_inc);
        let e = env.step();
        q_mul(osc, e)
    }
}

fn main() {
    // phase wrap
    assert_eq!(phase_advance(60000, 10000), 4464);
    assert_eq!(phase_advance(0, 1000), 1000);

    // sine LUT
    assert_eq!(osc_sine(0), 0);
    assert_eq!(osc_sine(16384), 32767);
    assert_eq!(osc_sine(32768), 0);
    assert_eq!(osc_sine(49152), -32767);

    // saw
    assert_eq!(osc_saw(0), -(PHASE_HALF as i32));
    assert_eq!(osc_saw(PHASE_HALF), 0);
    assert_eq!(osc_saw(65535), 32767);

    // square
    assert_eq!(osc_square(0), 32767);
    assert_eq!(osc_square(PHASE_HALF), -32767);
    assert_eq!(osc_square(32767), 32767);
    assert_eq!(osc_square(65535), -32767);

    // env attack
    {
        let mut e = Adsr::new();
        e.set_params(4, 4, 16384, 4);
        e.gate_on();
        for _ in 0..4 { e.step(); }
        assert_eq!(e.state, EnvelopeState::Decay);
        assert_eq!(e.level, ONE);
    }
    // env decay → sustain
    {
        let mut e = Adsr::new();
        e.set_params(4, 4, 16384, 4);
        e.gate_on();
        for _ in 0..8 { e.step(); }
        assert_eq!(e.state, EnvelopeState::Sustain);
        assert_eq!(e.level, 16384);
    }
    // env sustain holds
    {
        let mut e = Adsr::new();
        e.set_params(4, 4, 16384, 4);
        e.gate_on();
        for _ in 0..8 { e.step(); }
        for _ in 0..100 { e.step(); }
        assert_eq!(e.state, EnvelopeState::Sustain);
        assert_eq!(e.level, 16384);
    }
    // env release → idle
    {
        let mut e = Adsr::new();
        e.set_params(4, 4, 16384, 4);
        e.gate_on();
        for _ in 0..8 { e.step(); }
        e.gate_off();
        assert_eq!(e.release_start, 16384);
        for _ in 0..4 { e.step(); }
        assert_eq!(e.state, EnvelopeState::Idle);
        assert_eq!(e.level, 0);
    }
    // gate_off during attack — no click
    {
        let mut e = Adsr::new();
        e.set_params(8, 4, 16384, 4);
        e.gate_on();
        e.step(); e.step();
        e.gate_off();
        assert_eq!(e.release_start, 8192);
    }
    // voice silent when idle
    {
        let mut e = Adsr::new();
        e.set_params(4, 4, 16384, 4);
        let mut v = Voice::new(Waveform::Sine, 8192);
        assert_eq!(v.step(&mut e), 0);
    }
    // voice audible when gated
    {
        let mut e = Adsr::new();
        e.set_params(4, 4, 16384, 4);
        let mut v = Voice::new(Waveform::Sine, 8192);
        e.gate_on();
        let any_nonzero = (0..16).any(|_| v.step(&mut e) != 0);
        assert!(any_nonzero);
    }

    println!("audio_synthesis: 11 tests, 25 assertions ok");
}
