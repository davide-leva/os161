/**
 * Extra Commands
 */

#include <types.h>
#include <lib.h>
#include <kern/errno.h>
#include <math.h>
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

/*
 * Command for evaluating a math expression.
 */
int
cmd_eval(int nargs, char **args)
{
	char expr[256];
	int32_t result;
	int whole, frac;
	size_t len;
	int i, err;

	if (nargs < 2) {
		kprintf("Usage: eval expression\n");
		kprintf("       eval \"expression with spaces\"\n");
		return EINVAL;
	}

	len = 0;
	expr[0] = '\0';

	for (i = 1; i < nargs; i++) {
		size_t arglen;

		arglen = strlen(args[i]);
		if (len + arglen + (i > 1 ? 1 : 0) >= sizeof(expr)) {
			kprintf("Expression too long\n");
			return EINVAL;
		}

		if (i > 1) {
			expr[len++] = ' ';
			expr[len] = '\0';
		}

		strcpy(expr + len, args[i]);
		len += arglen;
	}

	err = eval_fixed(expr, &result);
	if (err) {
		kprintf("eval failed: %s\n", strerror(err));
		return err;
	}

	whole = result / 1000;
	frac = result % 1000;
	if (frac < 0) {
		frac = -frac;
	}

	kprintf("%d.%03d\n", whole, frac);
	return 0;
}

/*
 * Command for printing the ASCII code of a character.
 */
int
cmd_ascii(int nargs, char **args)
{
	if (nargs != 2 || strlen(args[1]) != 1) {
		kprintf("Usage: ascii character\n");
		return EINVAL;
	}

	kprintf("%c -> %u\n", args[1][0], (unsigned char)args[1][0]);
	return 0;
}

/*
 * Command for printing the 8-bit binary representation of a number.
 */
int
cmd_bin(int nargs, char **args)
{
	unsigned value;
	int i;

	if (nargs != 2) {
		kprintf("Usage: bin number\n");
		return EINVAL;
	}

	value = (unsigned)atoi(args[1]);
	kprintf("%u -> ", value);
	for (i = 7; i >= 0; i--) {
		kprintf("%u", (value >> i) & 1);
		if (i == 4) {
			kprintf(" ");
		}
	}
	kprintf("\n");

	return 0;
}

/*
 * Command for printing the hexadecimal representation of a number.
 */
int
cmd_hex(int nargs, char **args)
{
	unsigned value;

	if (nargs != 2) {
		kprintf("Usage: hex number\n");
		return EINVAL;
	}

	value = (unsigned)atoi(args[1]);
	kprintf("%u -> 0x%x\n", value, value);
	return 0;
}
