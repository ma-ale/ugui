#ifndef _STACK_GENERIC_H
#define _STACK_GENERIC_H


#define STACK_STEP 8


// TODO: add a rolling hash
#define STACK_DECL(stackname, type)                                            \
struct stackname {                                                             \
	type *items;                                                           \
	int size, idx;                                                         \
};                                                                             \
\
\
struct stackname stackname##_init(void) { return (struct stackname){0}; }      \
\
\
int stackname##_grow(struct stackname *stack, int step)                        \
{                                                                              \
	if (!stack)                                                            \
		return -1;                                                     \
	stack->items = realloc(stack->items, (stack->size+step)*sizeof(type)); \
	if(!stack->items)                                                      \
		return -1;                                                     \
	memset(&(stack->items[stack->size]), 0, step*sizeof(*(stack->items))); \
	stack->size += step;                                                   \
	return 0;                                                              \
}                                                                              \
\
\
int stackname##_push(struct stackname *stack, type *e)                         \
{                                                                              \
	if (!stack || !e)                                                      \
		return -1;                                                     \
	if (stack->idx >= stack->size)                                         \
		if (stackname##_grow(stack, STACK_STEP))                       \
			return -1;                                             \
	stack->items[stack->idx++] = *e;                                       \
	return 0;                                                              \
}                                                                              \
\
\
type stackname##_pop(struct stackname *stack)                                  \
{                                                                              \
	if (!stack || stack->idx == 0 || stack->size == 0)                     \
		return (type){0};                                              \
	return stack->items[stack->idx--];                                     \
}                                                                              \
\
\
int stackname##_clear(struct stackname *stack)                                 \
{                                                                              \
	if (!stack)                                                            \
		return -1;                                                     \
	stack->idx = 0;                                                        \
	return 0;                                                              \
}                                                                              \
\
\
int stackname##_free(struct stackname *stack)                                  \
{                                                                              \
	if (stack) {                                                           \
		stackname##_clear(stack);                                      \
		if (stack->items)                                              \
			free(stack->items);                                    \
	}                                                                      \
	return 0;                                                              \
}                                                                              \


#endif
