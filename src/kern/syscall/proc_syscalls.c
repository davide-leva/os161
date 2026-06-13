#include <types.h>
#include <syscall.h>
#include <addrspace.h>
#include <proc.h>
#include <thread.h>
#include <current.h>
#include <machine/trapframe.h>
#include <kern/errno.h>
#include <kern/wait.h>
#include <copyinout.h>

#include <opt-waitpid.h>
#include <opt-fork.h>

/**
 * Exit System Call.
 */
void
sys__exit(int exit_code)
{
#if OPT_WAITPID
	struct proc *p = curproc;
	proc_remthread(curthread);

	lock_acquire(p->p_waitlock);
	p->p_status = _MKWAIT_EXIT(exit_code & 0xff);
	p->p_exited = true;
	cv_broadcast(p->p_waitcv, p->p_waitlock);
	lock_release(p->p_waitlock);
#else
    /* Fetch address space of current process and destroy */
    struct addrspace *addr_space = proc_getas();
    as_destroy(addr_space);
#endif

    /* Thread exists. Process data structure will be lost */
    thread_exit();

    panic("thread_exit returned (should not happen)\n");
    (void)exit_code;
}

int
sys_waitpid(pid_t pid, userptr_t statusp, int options, pid_t *retval)
{
#if OPT_WAITPID
	int exit_code;
	int result;
	    
	struct proc *proc = proc_search_pid(pid);
	if (proc == NULL) {
		return ESRCH;
	}

	if (options != 0) {
		return EINVAL;
	}

	exit_code = proc_wait(proc);
	if (statusp != NULL) {
		result = copyout(&exit_code, statusp, sizeof(exit_code));
		if (result) {
			return result;
		}
	}
	    
	*retval = pid;
	return 0;
#else
	(void)options;
	(void)pid;
	(void)statusp;
	(void)retval;
	return ENOSYS;
#endif
}

int
sys_getpid(pid_t *retval)
{
#if OPT_WAITPID
    KASSERT(curproc != NULL);
    *retval = curproc->p_pid;
    return 0;
#else
    (void)retval;
    return ENOSYS;
#endif
}

#if OPT_FORK
static
void
call_enter_forked_process(void *tfv, unsigned long dummy)
{
    struct trapframe *tf = (struct trapframe *)tfv;
    (void)dummy;

    enter_forked_process(tf);

    panic("enter_forked_process returned (should not happen)\n");
}
#endif

int
sys_fork(struct trapframe *ctf, pid_t *retval)
{
#if OPT_FORK
    struct trapframe *tf_child;
    struct proc *newp;
    int exit_code;

    KASSERT(curproc != NULL);

    newp = proc_create_runprogram(curproc->p_name);
    if (newp == NULL) {
        return ENOMEM;
    }

    as_copy(curproc->p_addrspace, &(newp->p_addrspace));
    if (newp->p_addrspace == NULL) {
        proc_destroy(newp);
        return ENOMEM;
    }

    tf_child = kmalloc(sizeof(struct trapframe));
    if (tf_child == NULL) {
        proc_destroy(newp);
        return ENOMEM;
    }

    memcpy(tf_child, ctf, sizeof(struct trapframe));

    /* TO BE DONE: linking parent/child, so that child retminated on parent exit */
    exit_code = thread_fork(
        curthread->t_name,
        newp,
        call_enter_forked_process,
        (void *)tf_child,
        (unsigned long)0 /* unused */
    );

    if (exit_code) {
        proc_destroy(newp);
        kfree(tf_child);
        return ENOMEM;
    }

    *retval = newp->p_pid;

    return 0;
#else
    (void)ctf;
    (void)retval;
    return ENOSYS;
#endif
}
