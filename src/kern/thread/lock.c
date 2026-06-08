#include <types.h>
#include <lib.h>
#include <spinlock.h>
#include <wchan.h>
#include <thread.h>
#include <current.h>
#include <synch.h>

struct lock *
lock_create(const char *name)
{
    struct lock *lk;
    
    lk = kmalloc(sizeof *lk);
    if (lk == NULL) {
        return NULL;
    }

    lk->lk_name = kstrdup(name);
    if (lk->lk_name == NULL) {
        kfree(lk);
        return NULL;
    }

    lk->lk_wchan = wchan_create(lk->lk_name);
    if (lk->lk_wchan == NULL) {
        kfree(lk->lk_name);
        kfree(lk);
        return NULL;
    }

    HANGMAN_LOCKABLEINIT(&lk->lk_hangman, lk->lk_name);

    lk->lk_owner = NULL;

    spinlock_init(&lk->lk_lock);
    lk->lk_free = true;

    return lk;
}

void
lock_destroy(struct lock *lk)
{
    KASSERT(lk != NULL);
    KASSERT(lk->lk_free);
    KASSERT(lk->lk_owner == NULL);

    spinlock_cleanup(&lk->lk_lock);
    wchan_destroy(lk->lk_wchan);
    kfree(lk->lk_name);
    kfree(lk);
}

 /**
  * Get the lock. Only one thread can hold the lock at the
  * same time.
  */
void 
lock_acquire(struct lock *lk)
{
    KASSERT(lk != NULL);

    KASSERT(curthread->t_in_interrupt == false);
    
    spinlock_acquire(&lk->lk_lock);

    KASSERT(lk->lk_owner != curthread);

    while(!lk->lk_free) {
        HANGMAN_WAIT(&curthread->t_hangman, &lk->lk_hangman);
        wchan_sleep(lk->lk_wchan, &lk->lk_lock);
    }
    KASSERT(lk->lk_free);

    lk->lk_free = false;
    lk->lk_owner = curthread;
    HANGMAN_ACQUIRE(&curthread->t_hangman, &lk->lk_hangman);

    spinlock_release(&lk->lk_lock);
}

/**
 * Free the lock. Only the thread holding the lock may do
 * this.
 */
void
lock_release(struct lock *lk)
{
    KASSERT(lk != NULL);
    
    spinlock_acquire(&lk->lk_lock);
    
    KASSERT(lk->lk_owner == curthread);
    KASSERT(lk->lk_free == false);

    HANGMAN_RELEASE(&curthread->t_hangman, &lk->lk_hangman);
    lk->lk_free = true;
    lk->lk_owner = NULL;
    wchan_wakeone(lk->lk_wchan, &lk->lk_lock);

    spinlock_release(&lk->lk_lock);
}

/**
 * Return true if the current thread holds the lock;
 * false otherwise.
 */
bool
lock_do_i_hold(struct lock *lk)
{
    bool result;

    KASSERT(lk != NULL);

    spinlock_acquire(&lk->lk_lock);
    result = (curthread == lk->lk_owner);
    spinlock_release(&lk->lk_lock);

    return result;
}
