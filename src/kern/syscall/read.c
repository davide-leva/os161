#include <types.h>
#include <copyinout.h>
#include <kern/errno.h>
#include <syscall.h>
#include <kern/unistd.h>
#include <lib.h>

/**
 * Read System Call.
 */
int
sys_read(int fd, userptr_t buffer, size_t size, int32_t *retval)
{
    size_t i;
    int ch, result;
    char c;

    if (fd != STDIN_FILENO) {
        return EBADF;
    }

    for (i=0; i<size; i++) {
        ch = getch();
        if (ch < 0) {
            *retval = (int32_t)i;
            return 0;
        }

        c = (char)ch;
        result = copyout(&c, (userptr_t)((vaddr_t)buffer + i), sizeof(c));
        if (result) {
            return result;
        }
    }

    *retval = (int32_t)size;
    return 0;
}
