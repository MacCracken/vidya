// Vidya — IPC in Zig
//
// In-memory simulation: shared memory, pipe, named channel.

const std = @import("std");

const SHM_REGION_CAP: usize = 4;
const SHM_BYTES: usize = 64;
const PIPE_CAP: usize = 8;
const CHAN_CAP: usize = 4;
const CHAN_QUEUE_CAP: usize = 8;

const Ipc = struct {
    shm: [SHM_REGION_CAP][SHM_BYTES]u8 = [_][SHM_BYTES]u8{[_]u8{0} ** SHM_BYTES} ** SHM_REGION_CAP,
    pipe_buf: [PIPE_CAP]u8 = [_]u8{0} ** PIPE_CAP,
    pipe_head: usize = 0,
    pipe_count: usize = 0,
    chan_open: [CHAN_CAP]bool = [_]bool{false} ** CHAN_CAP,
    chan_queue: [CHAN_CAP][CHAN_QUEUE_CAP]u64 = [_][CHAN_QUEUE_CAP]u64{[_]u64{0} ** CHAN_QUEUE_CAP} ** CHAN_CAP,
    chan_count: [CHAN_CAP]usize = [_]usize{0} ** CHAN_CAP,

    fn shmWrite(self: *Ipc, region: i32, offset: i32, byte: u8) bool {
        if (region < 0 or region >= @as(i32, SHM_REGION_CAP) or offset < 0 or offset >= @as(i32, SHM_BYTES)) return false;
        self.shm[@intCast(region)][@intCast(offset)] = byte;
        return true;
    }

    fn shmRead(self: *const Ipc, region: i32, offset: i32) i32 {
        if (region < 0 or region >= @as(i32, SHM_REGION_CAP) or offset < 0 or offset >= @as(i32, SHM_BYTES)) return -1;
        return self.shm[@intCast(region)][@intCast(offset)];
    }

    fn pipeWrite(self: *Ipc, byte: u8) bool {
        if (self.pipe_count >= PIPE_CAP) return false;
        const tail = (self.pipe_head + self.pipe_count) % PIPE_CAP;
        self.pipe_buf[tail] = byte;
        self.pipe_count += 1;
        return true;
    }

    fn pipeRead(self: *Ipc) i32 {
        if (self.pipe_count == 0) return -1;
        const b = self.pipe_buf[self.pipe_head];
        self.pipe_head = (self.pipe_head + 1) % PIPE_CAP;
        self.pipe_count -= 1;
        return b;
    }

    fn chanListen(self: *Ipc, endpoint: usize) bool {
        if (endpoint >= CHAN_CAP) return false;
        self.chan_open[endpoint] = true;
        return true;
    }

    fn chanSend(self: *Ipc, dst: usize, msg: u64) bool {
        if (dst >= CHAN_CAP or !self.chan_open[dst]) return false;
        if (self.chan_count[dst] >= CHAN_QUEUE_CAP) return false;
        self.chan_queue[dst][self.chan_count[dst]] = msg;
        self.chan_count[dst] += 1;
        return true;
    }

    fn chanRecv(self: *Ipc, endpoint: usize) i64 {
        if (endpoint >= CHAN_CAP or !self.chan_open[endpoint]) return -1;
        if (self.chan_count[endpoint] == 0) return -1;
        const msg = self.chan_queue[endpoint][0];
        var k: usize = 0;
        while (k < self.chan_count[endpoint] - 1) : (k += 1) {
            self.chan_queue[endpoint][k] = self.chan_queue[endpoint][k + 1];
        }
        self.chan_count[endpoint] -= 1;
        return @intCast(msg);
    }
};

pub fn main() !void {
    var ipc = Ipc{};

    if (!ipc.shmWrite(1, 5, 0xA1)) return error.ShmWrite;
    if (ipc.shmRead(1, 5) != 0xA1) return error.ShmRead;
    if (ipc.shmRead(2, 5) != 0) return error.OtherRegion;
    if (ipc.shmWrite(1, 99, 0xFF)) return error.OobWrite;
    if (ipc.shmRead(1, 99) != -1) return error.OobRead;

    _ = ipc.pipeWrite(65);
    _ = ipc.pipeWrite(66);
    _ = ipc.pipeWrite(67);
    if (ipc.pipeRead() != 65) return error.Pipe1;
    if (ipc.pipeRead() != 66) return error.Pipe2;
    if (ipc.pipeRead() != 67) return error.Pipe3;
    if (ipc.pipeRead() != -1) return error.PipeEmpty;

    var ipc2 = Ipc{};
    var k: usize = 0;
    while (k < PIPE_CAP) : (k += 1) _ = ipc2.pipeWrite(@intCast(k + 100));
    if (ipc2.pipeWrite(99)) return error.PipeFullNotRejected;
    _ = ipc2.pipeRead();
    if (!ipc2.pipeWrite(99)) return error.PostDrain;

    var ipc3 = Ipc{};
    if (ipc3.chanSend(1, 0xDEADBEEF)) return error.SendToClosed;
    _ = ipc3.chanListen(1);
    if (!ipc3.chanSend(1, 0xCAFE)) return error.Send1;
    if (!ipc3.chanSend(1, 0xBABE)) return error.Send2;
    if (ipc3.chanRecv(1) != 0xCAFE) return error.Recv1;
    if (ipc3.chanRecv(1) != 0xBABE) return error.Recv2;
    if (ipc3.chanRecv(1) != -1) return error.RecvEmpty;
    if (ipc3.chanRecv(2) != -1) return error.RecvUnopened;

    std.debug.print("ipc: 18/18 ok\n", .{});
}
