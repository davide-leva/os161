/*
 * Small expression evaluator for kernel code.
 *
 * The kernel must not execute floating point instructions on OS/161/MIPS.
 * Keep the arithmetic fixed-point internally; eval() only writes IEEE-754
 * float bits into the caller's object.
 */

#include <types.h>
#include <kern/errno.h>
#include <lib.h>
#include <math.h>

#define EVAL_SCALE 1000

struct parser {
	const char *p;
	int error;
};

static
void
skip_spaces(struct parser *parser)
{
	while (*parser->p == ' ' || *parser->p == '\t' ||
	    *parser->p == '\n' || *parser->p == '\r') {
		parser->p++;
	}
}

static
bool
is_digit(char ch)
{
	return ch >= '0' && ch <= '9';
}

static
int32_t
scaled_multiply(int32_t left, int32_t right)
{
	return (int32_t)(((int64_t)left * (int64_t)right) / EVAL_SCALE);
}

static
int32_t
scaled_divide(int32_t left, int32_t right)
{
	return (int32_t)(((int64_t)left * EVAL_SCALE) / right);
}

static
int32_t
parse_expression(struct parser *parser);

static
int32_t
parse_number(struct parser *parser)
{
	int32_t value;
	int32_t place;
	bool digits;

	value = 0;
	place = EVAL_SCALE / 10;
	digits = false;

	while (is_digit(*parser->p)) {
		digits = true;
		value = value * 10 + (*parser->p - '0') * EVAL_SCALE;
		parser->p++;
	}

	if (*parser->p == '.') {
		parser->p++;
		while (is_digit(*parser->p)) {
			digits = true;
			if (place > 0) {
				value += (*parser->p - '0') * place;
				place /= 10;
			}
			parser->p++;
		}
	}

	if (!digits) {
		parser->error = EINVAL;
	}

	return value;
}

static
int32_t
parse_factor(struct parser *parser)
{
	int32_t value;

	skip_spaces(parser);

	if (*parser->p == '+') {
		parser->p++;
		return parse_factor(parser);
	}

	if (*parser->p == '-') {
		parser->p++;
		return -parse_factor(parser);
	}

	if (*parser->p == '(') {
		parser->p++;
		value = parse_expression(parser);
		skip_spaces(parser);
		if (*parser->p != ')') {
			parser->error = EINVAL;
			return 0;
		}
		parser->p++;
		return value;
	}

	return parse_number(parser);
}

static
int32_t
parse_term(struct parser *parser)
{
	int32_t value;
	int32_t rhs;

	value = parse_factor(parser);

	for (;;) {
		skip_spaces(parser);

		if (*parser->p == '*') {
			parser->p++;
			value = scaled_multiply(value, parse_factor(parser));
		}
		else if (*parser->p == '/') {
			parser->p++;
			rhs = parse_factor(parser);
			if (rhs == 0) {
				parser->error = EDOM;
				return 0;
			}
			value = scaled_divide(value, rhs);
		}
		else {
			return value;
		}

		if (parser->error) {
			return 0;
		}
	}
}

static
int32_t
parse_expression(struct parser *parser)
{
	int32_t value;

	value = parse_term(parser);

	for (;;) {
		skip_spaces(parser);

		if (*parser->p == '+') {
			parser->p++;
			value += parse_term(parser);
		}
		else if (*parser->p == '-') {
			parser->p++;
			value -= parse_term(parser);
		}
		else {
			return value;
		}

		if (parser->error) {
			return 0;
		}
	}
}

static
bool
scaled_at_least_power(int64_t value, int exponent)
{
	uint64_t threshold;

	if (exponent >= 0) {
		if (exponent >= 54) {
			return false;
		}
		threshold = (uint64_t)EVAL_SCALE << exponent;
		return (uint64_t)value >= threshold;
	}

	exponent = -exponent;
	if (exponent >= 54) {
		return false;
	}
	return ((uint64_t)value << exponent) >= EVAL_SCALE;
}

static
uint32_t
scaled_to_float_bits(int32_t scaled)
{
	uint32_t sign, exponent_bits, mantissa;
	uint64_t value, significand, divisor, remainder;
	int exponent, shift;

	if (scaled == 0) {
		return 0;
	}

	sign = 0;
	if (scaled < 0) {
		sign = 0x80000000;
		value = (uint64_t)-(int64_t)scaled;
	}
	else {
		value = (uint64_t)scaled;
	}

	for (exponent = 30; exponent > -31; exponent--) {
		if (scaled_at_least_power((int64_t)value, exponent)) {
			break;
		}
	}

	shift = 23 - exponent;
	if (shift >= 0) {
		significand = value << shift;
		divisor = EVAL_SCALE;
	}
	else {
		significand = value;
		divisor = (uint64_t)EVAL_SCALE << -shift;
	}

	remainder = significand % divisor;
	significand /= divisor;
	if (remainder * 2 >= divisor) {
		significand++;
	}

	if (significand >= (1ULL << 24)) {
		significand >>= 1;
		exponent++;
	}

	exponent_bits = (uint32_t)(exponent + 127) << 23;
	mantissa = (uint32_t)significand & 0x7fffff;

	return sign | exponent_bits | mantissa;
}

int
eval_fixed(char *input, int32_t *result)
{
	struct parser parser;
	int32_t value;

	if (input == NULL || result == NULL) {
		return EINVAL;
	}

	parser.p = input;
	parser.error = 0;

	value = parse_expression(&parser);
	if (parser.error) {
		return parser.error;
	}

	skip_spaces(&parser);
	if (*parser.p != '\0') {
		return EINVAL;
	}

	*result = value;
	return 0;
}

int
eval(char *input, float *result)
{
	int32_t fixed;
	uint32_t bits;
	int err;

	if (result == NULL) {
		return EINVAL;
	}

	err = eval_fixed(input, &fixed);
	if (err) {
		return err;
	}

	bits = scaled_to_float_bits(fixed);
	memcpy(result, &bits, sizeof(bits));
	return 0;
}
