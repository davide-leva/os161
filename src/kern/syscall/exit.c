#include <types.h>
#include <syscall.h>
#include <addrspace.h>
#include <proc.h>
#include <thread.h>

/**
 * Exit System Call.
 */
void
sys__exit(int exit_code)
{
    /* Fetch address space of current process and destroy */
    struct addrspace *addr_space = proc_getas();
    as_destroy(addr_space);

    /* Thread exists. Process data structure will be lost */
    thread_exit();

    panic("thread_exit returned (should not happe)\n");
    (void)exit_code;
}
