#include <types.h>
#include <kern/errno.h>
#include <lib.h>
#include <spinlock.h>
#include <vm.h>

struct frame_entry {
	int allocated;
	int fixed;
	unsigned block_len;
};

static struct frame_entry *frame_table;
static unsigned frame_count;
static paddr_t first_paddr;
static paddr_t last_paddr;

static struct spinlock frame_lock = SPINLOCK_INITIALIZER;

static unsigned
paddr_to_findex(paddr_t paddr)
{
	return (paddr - first_paddr) / PAGE_SIZE;
}

static paddr_t
findex_to_paddr(unsigned index)
{
	return first_paddr + index * PAGE_SIZE;
}

void
vm_bootstrap(void)
{
	paddr_t first, last;
	size_t table_bytes;
	unsigned table_pages;
	unsigned i;

	last = ram_getsize();
	first = ram_getfirstfree();

	first = ROUNDUP(first, PAGE_SIZE);
	last &= PAGE_FRAME;

	first_paddr = first;
	last_paddr = last;
	frame_count = (last - first) / PAGE_SIZE;

	table_bytes = frame_count * sizeof(struct frame_entry);
	table_pages = DIVROUNDUP(table_bytes, PAGE_SIZE);

	KASSERT(table_pages < frame_count);

	frame_table = (struct frame_entry *)PADDR_TO_KVADDR(first);

	for (i = 0; i < frame_count; i++) {
		frame_table[i].allocated = 0;
		frame_table[i].fixed = 0;
		frame_table[i].block_len = 0;
	}

	for (i = 0; i < table_pages; i++) {
		frame_table[i].allocated = 1;
		frame_table[i].fixed = 1;
	}

	frame_table[0].block_len = table_pages;
}

static paddr_t
frame_alloc(unsigned npages)
{
	unsigned i, j;

	if (npages == 0 || frame_table == NULL) {
		return 0;
	}

	spinlock_acquire(&frame_lock);

	for (i = 0; i + npages <= frame_count; i++) {
		for (j = 0; j < npages; j++) {
			if (frame_table[i + j].allocated) {
				break;
			}
		}

		if (j == npages) {
			for (j = 0; j < npages; j++) {
				frame_table[i + j].allocated = 1;
				frame_table[i + j].fixed = 0;
				frame_table[i + j].block_len = 0;
			}

			frame_table[i].block_len = npages;

			spinlock_release(&frame_lock);
			return findex_to_paddr(i);
		}

		i += j;
	}

	spinlock_release(&frame_lock);
	return 0;
}

static void
frame_dealloc(paddr_t paddr)
{
	unsigned index, len, i;

	if (paddr == 0) {
		return;
	}

	KASSERT(frame_table != NULL);
	KASSERT((paddr & PAGE_FRAME) == paddr);
	KASSERT(paddr >= first_paddr);
	KASSERT(paddr < last_paddr);

	index = paddr_to_findex(paddr);

	spinlock_acquire(&frame_lock);

	KASSERT(frame_table[index].allocated);
	KASSERT(!frame_table[index].fixed);
	KASSERT(frame_table[index].block_len > 0);

	len = frame_table[index].block_len;

	for (i = 0; i < len; i++) {
		KASSERT(frame_table[index + i].allocated);
		KASSERT(!frame_table[index + i].fixed);

		frame_table[index + i].allocated = 0;
		frame_table[index + i].block_len = 0;
	}

	spinlock_release(&frame_lock);
}

vaddr_t
alloc_kpages(unsigned npages)
{
	paddr_t paddr;

	if (frame_table == NULL) {
		paddr = ram_stealmem(npages);
	}
	else {
		paddr = frame_alloc(npages);
	}

	if (paddr == 0) {
		return 0;
	}

	return PADDR_TO_KVADDR(paddr);
}

void
free_kpages(vaddr_t addr)
{
	paddr_t paddr;

	if (addr == 0) {
		return;
	}

	paddr = KVADDR_TO_PADDR(addr);
	frame_dealloc(paddr);
}

int
vm_fault(int faulttype, vaddr_t faultaddress)
{
	(void)faulttype;
	(void)faultaddress;
	return EFAULT;
}

void
vm_tlbshootdown(const struct tlbshootdown *ts)
{
	(void)ts;
	panic("vm_tlbshootdown is not implemented\n");
}
