/**
 * Extra Commands
 */

#include <types.h>
#include <lib.h>
#include <kern/errno.h>
#include "extra_cmd.h"

/*
 * Command for reversing a string.
 */
int
cmd_rev(int nargs, char **args)
{
	const char *str;
	size_t len;

	if (nargs != 2) {
		kprintf("Usage: rev string\n");
		kprintf("       rev \"string with spaces\"\n");
		return EINVAL;
	}

	str = args[1];
	len = strlen(str);

	while (len > 0) {
		len--;
		kprintf("%c", str[len]);
	}
	kprintf("\n");

	return 0;
}

/*
 * Command for finding one string inside another.
 */
int
cmd_find(int nargs, char **args)
{
	const char *needle, *haystack;
	size_t needlelen, haystacklen;
	size_t i, j;
	bool found;

	if (nargs != 3) {
		kprintf("Usage: find needle haystack\n");
		kprintf("       find \"needle with spaces\" \"haystack with spaces\"\n");
		return EINVAL;
	}

	needle = args[1];
	haystack = args[2];
	needlelen = strlen(needle);
	haystacklen = strlen(haystack);
	found = false;

	if (needlelen == 0) {
		kprintf("found at index 0\n");
		return 0;
	}

	if (needlelen > haystacklen) {
		kprintf("not found\n");
		return 0;
	}

	for (i = 0; i <= haystacklen - needlelen; i++) {
		for (j = 0; j < needlelen; j++) {
			if (haystack[i+j] != needle[j]) {
				break;
			}
		}
		if (j == needlelen) {
			kprintf("found at index %u\n", (unsigned)i);
			found = true;
		}
	}

	if (!found) {
		kprintf("not found\n");
	}

	return 0;
}