#include <types.h>
#include <kern/errno.h>
#include <lib.h>
#include <addrspace.h>
#include <proc.h>
#include <spl.h>
#include <spinlock.h>
#include <vm.h>
#include <machine/tlb.h>

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
	struct addrspace *as;
	paddr_t paddr;
	vaddr_t vbase1, vtop1;
	vaddr_t vbase2, vtop2;
	vaddr_t stackbase, stacktop;
	int spl;

	switch (faulttype) {
	case VM_FAULT_READ:
	case VM_FAULT_WRITE:
		break;
	case VM_FAULT_READONLY:
		return EFAULT;
	default:
		return EINVAL;
	}

	as = proc_getas();
	if (as == NULL) {
		return EFAULT;
	}

	faultaddress &= PAGE_FRAME;

	vbase1 = as->reg1.as_vbase;
	vtop1 = vbase1 + as->reg1.as_npages * PAGE_SIZE;
	vbase2 = as->reg2.as_vbase;
	vtop2 = vbase2 + as->reg2.as_npages * PAGE_SIZE;
	stackbase = USERSTACK - AS_STACKPAGES * PAGE_SIZE;
	stacktop = USERSTACK;

	if (faultaddress >= vbase1 && faultaddress < vtop1) {
		paddr = as->reg1.as_pbase + (faultaddress - vbase1);
	}
	else if (faultaddress >= vbase2 && faultaddress < vtop2) {
		paddr = as->reg2.as_pbase + (faultaddress - vbase2);
	}
	else if (faultaddress >= stackbase && faultaddress < stacktop) {
		paddr = as->as_stackpbase + (faultaddress - stackbase);
	}
	else {
		return EFAULT;
	}

	if (paddr == 0) {
		return EFAULT;
	}

	KASSERT((paddr & PAGE_FRAME) == paddr);

	spl = splhigh();
	tlb_random(faultaddress, paddr | TLBLO_DIRTY | TLBLO_VALID);
	splx(spl);

	return 0;
}

void
vm_tlbshootdown(const struct tlbshootdown *ts)
{
	(void)ts;
	panic("vm_tlbshootdown is not implemented\n");
}
