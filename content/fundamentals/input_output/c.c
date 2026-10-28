// Vidya — Input/Output in C
//
// C I/O uses FILE* streams (stdio.h) or raw file descriptors (unistd.h).
// stdio is buffered and portable. File descriptors are POSIX-level.
// Always check return values — I/O errors are silent otherwise.

#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

// Every fallible call below is routed through this check. Two traps it dodges:
//   1. Ignoring the result -- a failed write is silent; the data just vanishes.
//   2. assert(fclose(f) == 0) -- under -DNDEBUG the assert expression is
//      compiled out *together with the call inside it*, so the file is never
//      closed. Passing the call as an argument keeps it in every build.
static void io_ok(int ok, const char *what) {
    if (!ok) {
        fprintf(stderr, "I/O failed: %s\n", what);
        exit(EXIT_FAILURE);
    }
}

int main(void) {
    char tmppath[] = "/tmp/vidya_io_XXXXXX";
    int tmpfd = mkstemp(tmppath);
    assert(tmpfd >= 0);
    io_ok(close(tmpfd) == 0, "close tmpfd");

    // ── stdio: fopen/fwrite/fclose ─────────────────────────────────
    FILE *f = fopen(tmppath, "w");
    assert(f != NULL);
    fprintf(f, "line 1\n");
    fprintf(f, "line 2\n");
    fprintf(f, "line 3\n");
    io_ok(fclose(f) == 0, "fclose after write");

    // ── Reading entire file ────────────────────────────────────────
    f = fopen(tmppath, "r");
    assert(f != NULL);
    io_ok(fseek(f, 0, SEEK_END) == 0, "fseek to end");
    long size = ftell(f);
    io_ok(size >= 0, "ftell"); // ftell reports failure as -1, not as 0
    io_ok(fseek(f, 0, SEEK_SET) == 0, "fseek to start");

    char *content = malloc(size + 1);
    assert(content != NULL);
    size_t nread = fread(content, 1, size, f);
    io_ok(nread == (size_t)size, "fread whole file");
    content[nread] = '\0';
    io_ok(fclose(f) == 0, "fclose after read");

    assert(strstr(content, "line 1") != NULL);
    assert(strstr(content, "line 3") != NULL);
    free(content);

    // ── Line-by-line reading with fgets ────────────────────────────
    f = fopen(tmppath, "r");
    assert(f != NULL);
    char line[256];
    int line_count = 0;
    while (fgets(line, sizeof(line), f) != NULL) {
        line_count++;
    }
    io_ok(fclose(f) == 0, "fclose after fgets");
    assert(line_count == 3);

    // ── Binary I/O ─────────────────────────────────────────────────
    char binpath[] = "/tmp/vidya_bin_XXXXXX";
    int binfd = mkstemp(binpath);
    assert(binfd >= 0);
    io_ok(close(binfd) == 0, "close binfd");

    f = fopen(binpath, "wb");
    assert(f != NULL);
    int nums[] = {10, 20, 30, 40};
    size_t nwrote = fwrite(nums, sizeof(int), 4, f);
    io_ok(nwrote == 4, "fwrite nums"); // short count is the failure signal
    io_ok(fclose(f) == 0, "fclose after fwrite");

    f = fopen(binpath, "rb");
    assert(f != NULL);
    int read_nums[4];
    size_t nitems = fread(read_nums, sizeof(int), 4, f);
    io_ok(nitems == 4, "fread nums");
    io_ok(fclose(f) == 0, "fclose after fread");
    assert(read_nums[0] == 10);
    assert(read_nums[3] == 40);
    unlink(binpath);

    // ── Buffering modes ────────────────────────────────────────────
    // _IOFBF: full buffering (files)
    // _IOLBF: line buffering (terminals)
    // _IONBF: no buffering (stderr)

    f = fopen(tmppath, "w");
    assert(f != NULL);
    // Set 4KB buffer
    char buf[4096];
    io_ok(setvbuf(f, buf, _IOFBF, sizeof(buf)) == 0, "setvbuf");
    fprintf(f, "buffered\n");
    // A buffered fprintf can succeed while the eventual write fails: the
    // error surfaces here, at the flush, or at fclose. Check both.
    io_ok(fflush(f) == 0, "fflush");
    io_ok(fclose(f) == 0, "fclose after buffered write");

    // ── sprintf: format to string (in-memory I/O) ──────────────────
    char strbuf[64];
    int n = snprintf(strbuf, sizeof(strbuf), "value: %d", 42);
    assert(n > 0);
    assert(strcmp(strbuf, "value: 42") == 0);

    // ── Low-level: file descriptors (POSIX) ────────────────────────
    int fd = open(tmppath, O_RDONLY);
    assert(fd >= 0);

    char fdbuf[32];
    ssize_t bytes = read(fd, fdbuf, sizeof(fdbuf) - 1);
    assert(bytes > 0);
    fdbuf[bytes] = '\0';
    io_ok(close(fd) == 0, "close fd");
    assert(strstr(fdbuf, "buffered") != NULL);

    // ── Seeking ────────────────────────────────────────────────────
    f = fopen(tmppath, "r");
    assert(f != NULL);
    io_ok(fseek(f, 0, SEEK_END) == 0, "fseek to end");
    long end = ftell(f);
    assert(end > 0);
    io_ok(fseek(f, 0, SEEK_SET) == 0, "fseek to start");
    long start = ftell(f);
    assert(start == 0);
    io_ok(fclose(f) == 0, "fclose after seek");

    // ── Error checking ─────────────────────────────────────────────
    f = fopen("/nonexistent/path.txt", "r");
    assert(f == NULL); // file not found

    // ── Cleanup ────────────────────────────────────────────────────
    unlink(tmppath);

    printf("All input/output examples passed.\n");
    return 0;
}
