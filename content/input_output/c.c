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

int main(void) {
    char tmppath[] = "/tmp/vidya_io_XXXXXX";
    int tmpfd = mkstemp(tmppath);
    assert(tmpfd >= 0);
    close(tmpfd);

    // ── stdio: fopen/fwrite/fclose ─────────────────────────────────
    FILE *f = fopen(tmppath, "w");
    assert(f != NULL);
    fprintf(f, "line 1\n");
    fprintf(f, "line 2\n");
    fprintf(f, "line 3\n");
    fclose(f);

    // ── Reading entire file ────────────────────────────────────────
    f = fopen(tmppath, "r");
    assert(f != NULL);
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *content = malloc(size + 1);
    assert(content != NULL);
    size_t nread = fread(content, 1, size, f);
    content[nread] = '\0';
    fclose(f);

    assert(strstr(content, "line 1") != NULL);
    assert(strstr(content, "line 3") != NULL);
    free(content);

    // ── Line-by-line reading with fgets ────────────────────────────
    f = fopen(tmppath, "r");
    char line[256];
    int line_count = 0;
    while (fgets(line, sizeof(line), f) != NULL) {
        line_count++;
    }
    fclose(f);
    assert(line_count == 3);

    // ── Binary I/O ─────────────────────────────────────────────────
    char binpath[] = "/tmp/vidya_bin_XXXXXX";
    int binfd = mkstemp(binpath);
    close(binfd);

    f = fopen(binpath, "wb");
    int nums[] = {10, 20, 30, 40};
    fwrite(nums, sizeof(int), 4, f);
    fclose(f);

    f = fopen(binpath, "rb");
    int read_nums[4];
    fread(read_nums, sizeof(int), 4, f);
    fclose(f);
    assert(read_nums[0] == 10);
    assert(read_nums[3] == 40);
    unlink(binpath);

    // ── Buffering modes ────────────────────────────────────────────
    // _IOFBF: full buffering (files)
    // _IOLBF: line buffering (terminals)
    // _IONBF: no buffering (stderr)

    f = fopen(tmppath, "w");
    // Set 4KB buffer
    char buf[4096];
    setvbuf(f, buf, _IOFBF, sizeof(buf));
    fprintf(f, "buffered\n");
    fflush(f); // explicit flush
    fclose(f);

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
    close(fd);
    assert(strstr(fdbuf, "buffered") != NULL);

    // ── Seeking ────────────────────────────────────────────────────
    f = fopen(tmppath, "r");
    fseek(f, 0, SEEK_END);
    long end = ftell(f);
    assert(end > 0);
    fseek(f, 0, SEEK_SET);
    long start = ftell(f);
    assert(start == 0);
    fclose(f);

    // ── Error checking ─────────────────────────────────────────────
    f = fopen("/nonexistent/path.txt", "r");
    assert(f == NULL); // file not found

    // ── Cleanup ────────────────────────────────────────────────────
    unlink(tmppath);

    printf("All input/output examples passed.\n");
    return 0;
}
