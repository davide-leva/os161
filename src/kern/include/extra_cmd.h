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

#endif /* _EXTRA_CMD_H_ */
