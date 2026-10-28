# Vidya — Explicit GPU Synchronization in Python
#
# Timeline semaphores — monotonic counters with signal/wait/wait_all.


class Timelines:
    def __init__(self):
        self.compute = 0
        self.transfer = 0

    def signal(self, sem, value):
        if sem == 0:
            if value <= self.compute:
                return False
            self.compute = value
            return True
        if sem == 1:
            if value <= self.transfer:
                return False
            self.transfer = value
            return True
        return False

    def wait_for(self, sem, target):
        if sem == 0:
            return self.compute >= target
        if sem == 1:
            return self.transfer >= target
        return False

    def wait_all(self, c_target, t_target):
        return self.wait_for(0, c_target) and self.wait_for(1, t_target)


def main():
    t = Timelines()

    assert t.compute == 0
    assert t.transfer == 0
    assert t.wait_for(0, 0)

    assert t.signal(0, 5)
    assert t.compute == 5

    assert t.wait_for(0, 3)
    assert t.wait_for(0, 5)
    assert not t.wait_for(0, 10)

    assert not t.signal(0, 3)
    assert t.compute == 5
    assert not t.signal(0, 5)

    t.signal(1, 3)
    assert t.transfer == 3
    assert t.wait_all(5, 3)
    assert not t.wait_all(5, 4)
    assert not t.wait_all(6, 3)
    assert t.wait_all(0, 0)

    t2 = Timelines()
    for i in range(1, 11):
        t2.signal(0, i)
    assert t2.compute == 10
    assert t2.wait_for(0, 10)
    assert not t2.wait_for(0, 11)

    print("explicit_gpu_synchronization: 19/19 ok")


main()
