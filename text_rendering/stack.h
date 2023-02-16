#ifdef _STACK_TYPE
#ifdef _STACK_NAME


#ifndef _STACK_REALLOC
	#define _STACK_REALLOC(p, s) realloc(p,s)
#endif
#ifndef _STACK_MEMSET
	#define _STACK_MEMSET(p, c, s) memset(p,c,s)
#endif
#ifndef _STACK_STEP
	#define _STACK_STEP 8
#endif
#ifndef _STACK_CAT
	#define _STACK_CAT_I(a,b) a ## b
	#define _STACK_CAT(a,b) _STACK_CAT_I(a,b)
#endif


// TODO: add a rolling hash
struct _STACK_NAME {
	_STACK_TYPE *items;
	int size, idx;
};


int _STACK_CAT(stack_grow_,_STACK_NAME)(struct _STACK_NAME *stack, int step)
{
	if (!stack)
		return -1;
	stack->items = _STACK_REALLOC(stack->items, (stack->size+step)*sizeof(_STACK_TYPE));
	if(!stack->items)
		return -1;
	_STACK_MEMSET(&(stack->items[stack->size]), 0, step*sizeof(*(stack->items)));
	stack->size += step;
	return 0;
}


int _STACK_CAT(stack_push_,_STACK_NAME)(struct _STACK_NAME *stack, _STACK_TYPE *e)
{
	if (!stack || !e)
		return -1;
	if (stack->idx >= stack->size)
		if (_STACK_CAT(stack_grow_,_STACK_NAME)(stack, _STACK_STEP))
			return -1;
	stack->items[stack->idx++] = *e;
	return 0;
}


int _STACK_CAT(stack_clear_,_STACK_NAME)(struct _STACK_NAME *stack)
{
	if (!stack)
		return -1;
	stack->idx = 0;
}


#endif
#endif
