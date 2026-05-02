/* Vidya — Concurrent File Access (flock) in C
 *
 * Single-process exercise of the file-lock state machine via two
 * distinct OPENs of the same path. flock is per-OPEN; the two fds
 * have independent lock state. flock(LOCK_NB) returns -1 with
 * errno = EWOULDBLOCK on conflict.
 */

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/file.h>
#include <unistd.h>

int main(void) {
    const char *path = "/tmp/vidya_cfa_c.bin";
    unlink(path);

    /* Test 1: exclusive write */
    int fd1 = open(path, O_RDWR | O_CREAT, 0644);
    assert(fd1 >= 0 && "open fd1");
    assert(flock(fd1, LOCK_EX) == 0 && "fd1 LOCK_EX");

    uint64_t val = 0xDEADBEEF12345678ULL;
    lseek(fd1, 0, SEEK_SET);
    assert(write(fd1, &val, 8) == 8 && "wrote 8 bytes");
    assert(flock(fd1, LOCK_UN) == 0 && "fd1 LOCK_UN");

    /* Test 2: shared read with roundtrip */
    assert(flock(fd1, LOCK_SH) == 0 && "fd1 LOCK_SH");
    lseek(fd1, 0, SEEK_SET);
    uint64_t got = 0;
    assert(read(fd1, &got, 8) == 8 && "read 8 bytes");
    assert(got == val && "data roundtrip");
    flock(fd1, LOCK_UN);

    /* Test 3: exclusive contention via second OPEN of same file */
    int fd2 = open(path, O_RDWR);
    assert(fd2 >= 0 && "open fd2");
    assert(flock(fd1, LOCK_EX) == 0 && "fd1 re-acquires LOCK_EX");
    int nb = flock(fd2, LOCK_EX | LOCK_NB);
    assert(nb < 0 && (errno == EWOULDBLOCK || errno == EAGAIN) && "fd2 LOCK_NB blocked");

    /* Test 4: release fd1, fd2 acquires */
    flock(fd1, LOCK_UN);
    assert(flock(fd2, LOCK_EX | LOCK_NB) == 0 && "fd2 acquires after fd1 releases");
    flock(fd2, LOCK_UN);

    /* Test 5: shared locks coexist */
    assert(flock(fd1, LOCK_SH | LOCK_NB) == 0 && "fd1 LOCK_SH non-blocking");
    assert(flock(fd2, LOCK_SH | LOCK_NB) == 0 && "fd2 LOCK_SH non-blocking coexists");
    flock(fd1, LOCK_UN);
    flock(fd2, LOCK_UN);

    close(fd1);
    close(fd2);
    unlink(path);
    printf("concurrent_file_access: 12/12 ok\n");
    return 0;
}
