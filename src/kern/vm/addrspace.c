/*
 * Copyright (c) 2000, 2001, 2002, 2003, 2004, 2005, 2008, 2009
 *	The President and Fellows of Harvard College.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE UNIVERSITY AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE UNIVERSITY OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <types.h>
#include <kern/errno.h>
#include <lib.h>
#include <addrspace.h>
#include <vm.h>
#include <proc.h>
#include <spl.h>
#include <machine/tlb.h>

static void
as_zero_region(struct addrregion *reg)
{
	reg->as_vbase = 0;
	reg->as_pbase = 0;
	reg->as_npages = 0;
}

static void
as_free_region(struct addrregion *reg)
{
	if (reg->as_pbase != 0) {
		free_kpages(PADDR_TO_KVADDR(reg->as_pbase));
	}
	as_zero_region(reg);
}

static int
as_alloc_region(struct addrregion *reg)
{
	vaddr_t kvaddr;

	if (reg->as_npages == 0 || reg->as_pbase != 0) {
		return 0;
	}

	kvaddr = alloc_kpages(reg->as_npages);
	if (kvaddr == 0) {
		return ENOMEM;
	}

	reg->as_pbase = KVADDR_TO_PADDR(kvaddr);
	bzero((void *)kvaddr, reg->as_npages * PAGE_SIZE);

	return 0;
}

static int
as_copy_region(const struct addrregion *old, struct addrregion *new)
{
	int result;

	*new = *old;
	new->as_pbase = 0;

	result = as_alloc_region(new);
	if (result) {
		return result;
	}

	if (old->as_pbase != 0 && old->as_npages != 0) {
		memmove((void *)PADDR_TO_KVADDR(new->as_pbase),
			(const void *)PADDR_TO_KVADDR(old->as_pbase),
			old->as_npages * PAGE_SIZE);
	}

	return 0;
}

static void
as_flush_tlb(void)
{
	int spl;
	unsigned i;

	spl = splhigh();

	for (i = 0; i < NUM_TLB; i++) {
		tlb_write(TLBHI_INVALID(i), TLBLO_INVALID(), i);
	}

	splx(spl);
}

struct addrspace *
as_create(void)
{
	struct addrspace *as;

	as = kmalloc(sizeof(struct addrspace));
	if (as == NULL) {
		return NULL;
	}

	as_zero_region(&as->reg1);
	as_zero_region(&as->reg2);
	as->as_stackpbase = 0;

	return as;
}

int
as_copy(struct addrspace *old, struct addrspace **ret)
{
	struct addrspace *newas;
	vaddr_t kvaddr;
	int result;

	newas = as_create();
	if (newas==NULL) {
		return ENOMEM;
	}

	result = as_copy_region(&old->reg1, &newas->reg1);
	if (result) {
		as_destroy(newas);
		return result;
	}

	result = as_copy_region(&old->reg2, &newas->reg2);
	if (result) {
		as_destroy(newas);
		return result;
	}

	newas->as_stackpbase = 0;
	if (old->as_stackpbase != 0) {
		kvaddr = alloc_kpages(AS_STACKPAGES);
		if (kvaddr == 0) {
			as_destroy(newas);
			return ENOMEM;
		}

		newas->as_stackpbase = KVADDR_TO_PADDR(kvaddr);
		memmove((void *)kvaddr,
			(const void *)PADDR_TO_KVADDR(old->as_stackpbase),
			AS_STACKPAGES * PAGE_SIZE);
	}

	*ret = newas;

	return 0;
}

void
as_destroy(struct addrspace *as)
{
	if (as == NULL) {
		return;
	}

	as_free_region(&as->reg1);
	as_free_region(&as->reg2);

	if (as->as_stackpbase != 0) {
		free_kpages(PADDR_TO_KVADDR(as->as_stackpbase));
	}

	kfree(as);
}

void
as_activate(void)
{
	struct addrspace *as;

	as = proc_getas();
	if (as == NULL) {
		/*
		 * Kernel thread without an address space; leave the
		 * prior address space in place.
		 */
		return;
	}

	(void)as;
	as_flush_tlb();
}

void
as_deactivate(void)
{
	as_flush_tlb();
}

/*
 * Set up a segment at virtual address VADDR of size MEMSIZE. The
 * segment in memory extends from VADDR up to (but not including)
 * VADDR+MEMSIZE.
 *
 * The READABLE, WRITEABLE, and EXECUTABLE flags are set if read,
 * write, or execute permission should be set on the segment. At the
 * moment, these are ignored. When you write the VM system, you may
 * want to implement them.
 */
int
as_define_region(struct addrspace *as, vaddr_t vaddr, size_t memsize,
		 int readable, int writeable, int executable)
{
	struct addrregion *reg;
	size_t offset;

	(void)readable;
	(void)writeable;
	(void)executable;

	if (as->reg1.as_npages == 0) {
		reg = &as->reg1;
	}
	else if (as->reg2.as_npages == 0) {
		reg = &as->reg2;
	}
	else {
		return ENOSYS;
	}

	offset = vaddr & ~(vaddr_t)PAGE_FRAME;
	vaddr &= PAGE_FRAME;
	memsize += offset;

	reg->as_vbase = vaddr;
	reg->as_npages = DIVROUNDUP(memsize, PAGE_SIZE);
	reg->as_pbase = 0;

	return 0;
}

int
as_prepare_load(struct addrspace *as)
{
	vaddr_t kvaddr;
	int result;

	result = as_alloc_region(&as->reg1);
	if (result) {
		return result;
	}

	result = as_alloc_region(&as->reg2);
	if (result) {
		return result;
	}

	if (as->as_stackpbase == 0) {
		kvaddr = alloc_kpages(AS_STACKPAGES);
		if (kvaddr == 0) {
			return ENOMEM;
		}

		as->as_stackpbase = KVADDR_TO_PADDR(kvaddr);
		bzero((void *)kvaddr, AS_STACKPAGES * PAGE_SIZE);
	}

	return 0;
}

int
as_complete_load(struct addrspace *as)
{
	/*
	 * Write this.
	 */

	(void)as;
	return 0;
}

int
as_define_stack(struct addrspace *as, vaddr_t *stackptr)
{
	(void)as;

	/* Initial user-level stack pointer */
	*stackptr = USERSTACK;

	return 0;
}
