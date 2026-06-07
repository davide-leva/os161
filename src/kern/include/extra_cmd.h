#ifndef _EXTRA_CMD_H_
#define _EXTRA_CMD_H_

/*
 * Command for reversing a string.
 */
int cmd_rev(int nargs, char **args);

/*
 * Command for finding one string inside another.
 */
int cmd_find(int nargs, char **args);

/*
 * Command for evaluating a math expression.
 */
int cmd_eval(int nargs, char **args);

/*
 * Command for printing the ASCII code of a character.
 */
int cmd_ascii(int nargs, char **args);

/*
 * Command for printing the 8-bit binary representation of a number.
 */
int cmd_bin(int nargs, char **args);

/*
 * Command for printing the hexadecimal representation of a number.
 */
int cmd_hex(int nargs, char **args);

#endif /* _EXTRA_CMD_H_ */
