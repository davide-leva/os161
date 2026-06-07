#include <types.h>
#include <copyinout.h>
#include <kern/errno.h>
#include <syscall.h>
#include <kern/unistd.h>
#include <lib.h>

/**
 * Write System Call.
 */
int
sys_write(int fd, userptr_t buffer, size_t size, int32_t *retval)
{
    size_t i;
    int result;
    char c;

    if (fd != STDOUT_FILENO && fd != STDERR_FILENO) {
        return EBADF;
    }

    for (i=0; i<size; i++) {
        result = copyin((const_userptr_t)((vaddr_t)buffer + i),
            &c, sizeof(c));
        if (result) {
            return result;
        }
        putch(c);
    }

    *retval = (int32_t)size;
    return 0;
}
