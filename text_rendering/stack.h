#ifndef _STACK_GENERIC_H
#define _STACK_GENERIC_H


#define STACK_STEP 8
#define STACK_SALT 0xbabb0cac

// FIXME: find a way to not re-hash the whole stack when removing one item

// incremental hash for every grow
#define HASH(p, s, h)                                                          \
{                                                                              \
	unsigned char *v = (unsigned char *)(p);                               \
	for (int x = (s); x; x--) {                                            \
		(h) += v[x-1];                                                 \
		(h) += (h) << 10;                                              \
		(h) ^= (h) >> 6;                                               \
	}                                                                      \
	(h) += (h) << 3;                                                       \
  	(h) ^= (h) >> 11;                                                      \
  	(h) += (h) << 15;                                                      \
}


// TODO: add a rolling hash
#define STACK_DECL(stackname, type)                                            \
struct stackname {                                                             \
	type *items;                                                           \
	int size, idx, old_idx;                                                \
	unsigned int hash, old_hash;                                           \
};                                                                             \
\
\
struct stackname stackname##_init(void)                                        \
{                                                                              \
	return (struct stackname){0, .hash = STACK_SALT};                      \
}                                                                              \
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
	HASH(e, sizeof(type), stack->hash);                                    \
	return 0;                                                              \
}                                                                              \
\
\
type stackname##_pop(struct stackname *stack)                                  \
{                                                                              \
	if (!stack || stack->idx == 0 || stack->size == 0)                     \
		return (type){0};                                              \
	stack->hash = STACK_SALT;                                              \
	HASH(stack->items, sizeof(type)*(stack->idx-1), stack->hash);          \
	return stack->items[stack->idx--];                                     \
}                                                                              \
\
\
int stackname##_clear(struct stackname *stack)                                 \
{                                                                              \
	if (!stack)                                                            \
		return -1;                                                     \
	stack->old_idx = stack->idx;                                           \
	stack->old_hash = stack->hash;                                         \
	stack->hash = STACK_SALT;                                              \
	stack->idx = 0;                                                        \
	return 0;                                                              \
}                                                                              \
\
\
int stackname##_changed(struct stackname *stack)                               \
{                                                                              \
	if (!stack)                                                            \
		return -1;                                                     \
	return stack->hash != stack->old_hash;                                 \
}                                                                              \
\
\
int stackname##_size_changed(struct stackname *stack)                          \
{                                                                              \
	if (!stack)                                                            \
		return -1;                                                     \
	return stack->size != stack->old_idx;                                  \
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
