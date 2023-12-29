#ifndef _VECTREE_H
#define _VECTREE_H

#ifdef VTREE_DTYPE

typedef struct {
	int size, elements;
	VTREE_DTYPE *vector;
	int *refs;
} Vtree;

int vtree_init(Vtree *tree, unsigned int size); 
int vtree_pack(Vtree *tree);
int vtree_resize(Vtree *tree, unsigned int newsize);
int vtree_add(Vtree *tree, VTREE_DTYPE elem, int parent);
int vtree_prune(Vtree *tree, int ref);
int vtree_subtree_size(Vtree *tree, int ref);
int vtree_children_it(Vtree *tree, int parent, int *cursor);
int vtree_level_order_it(Vtree *tree, int ref, int **queue_p, int *cursor);
int vtree_destroy(Vtree *tree);

#ifdef VTREE_IMPL

#define IS_VALID_REF(t, r) ((r) >= 0 && (r) < (t)->size)
#define REF_IS_PRESENT(t, r) ((t)->refs[r] >= 0)

int vtree_init(Vtree *tree, unsigned int size) 
{
	if (tree == NULL) {
		return -1;
	}

	tree->vector = malloc(sizeof(VTREE_DTYPE) * size);
	if (tree->vector == NULL) {
		return -1;
	}

	tree->refs = malloc(sizeof(int) * size);
	if (tree->refs == NULL) {
		free(tree->vector);
		return -1;
	}

	// set all refs to -1, meaning invalid (free) element
	for (unsigned int i = 0; i < size; i++) {
		tree->refs[i] = -1;
	}

	// fill vector with zeroes
	memset(tree->vector, 0, size * sizeof(VTREE_DTYPE));

	tree->size = size;
	tree->elements = 0;
	
	return 0;
}

int vtree_destroy(Vtree *tree)
{
	if (tree == NULL) {
		return -1;
	}

	free(tree->vector);
	free(tree->refs);

	return 0;
}

int vtree_pack(Vtree *tree)
{
	if (tree == NULL) {
		return -1;
	}

	// TODO: add a PACKED flag to skip this

	int free_spot = -1;
	for (int i = 0; i < tree->size; i++) {
		if (tree->refs[i] == -1) {
			free_spot = i;
			continue;
		}

		// find a item that can be packed
		if (free_spot >= 0 && tree->refs[i] >= 0) {
			int old_ref = i;

			// move the item
			tree->vector[free_spot] = tree->vector[i];
			tree->refs[free_spot] = tree->refs[i];

			tree->vector[i] = (VTREE_DTYPE){0};
			tree->refs[i] = -1;

			// and move all references
			for (int x = 0; x < tree->size; x++) {
				if (tree->refs[x] == old_ref) {
					tree->refs[x] = free_spot;
				}
			}

			// mark the free spot as used
			free_spot = -1;
		}
	}
	
	return 0;
}

int vtree_resize(Vtree *tree, unsigned int newsize) 
{
	if (tree == NULL) {
		return -1;
	}

	// return error when shrinking with too many elements
	if ((int)newsize < tree->elements) {
		return -1;
	}

	// pack the vector when shrinking to avoid data loss
	if ((int)newsize < tree->size) {
		//if (vtree_pack(tree) < 0) {
		//	return -1;
		//}
		// TODO: allow shrinking, since packing destroys all references
		return -1;
	}

	VTREE_DTYPE *newvec = realloc(tree->vector, newsize * sizeof(VTREE_DTYPE));
	if (newvec == NULL) {
		return -1;
	}

	int *newrefs = realloc(tree->refs, newsize * sizeof(int));
	if (newrefs == NULL) {
		return -1;
	}

	tree->vector = newvec;
	tree->refs = newrefs;
	if ((int)newsize > tree->size) {
		for (int i = tree->size; i < (int)newsize; i++) {
			tree->vector[i] = (VTREE_DTYPE){0};
			tree->refs[i] = -1;
		}
	}

	tree->size = newsize;

	return 0;
}

// add an element to the tree, return it's ref
int vtree_add(Vtree *tree, VTREE_DTYPE elem, int parent)
{
	if (tree == NULL) {
		return -1;
	}

	// invalid parent
	if (!IS_VALID_REF(tree, parent)) {
		return -1;
	}

	// no space left
	if (tree->elements >= tree->size) {
		return -1;
	}

	// check if the parent exists
	// if there are no elements in the tree the first add will set the root
	if (!REF_IS_PRESENT(tree, parent) && tree->elements != 0) {
		return -1;
	}

	// get the first free spot
	int free_spot = -1;
	for (int i = 0; i < tree->size; i++) {
		if (tree->refs[i] == -1) {
			free_spot = i;
			break;
		}
	}
	if (free_spot < 0) {
		return -1;
	}

	// finally add the element
	tree->vector[free_spot] = elem;
	tree->refs[free_spot] = parent;
	tree->elements++;
	
	return free_spot;
}

// prune the tree starting from the ref
// returns the number of pruned elements
int vtree_prune(Vtree *tree, int ref)
{
	if (tree == NULL) {
		return -1;
	}

	if (!IS_VALID_REF(tree, ref)) {
		return -1;
	}

	if (!REF_IS_PRESENT(tree, ref)) {
		return 0;
	}

	tree->vector[ref] = (VTREE_DTYPE){0};
	tree->refs[ref] = -1;

	int count = 1;
	for (int i = 0; i < tree->size; i++) {
		if (tree->refs[i] == ref) {
			count += vtree_prune(tree, i);
		}
	}
	
	return count;
}

// find the size of the subtree starting from ref
int vtree_subtree_size(Vtree *tree, int ref)
{
	if (tree == NULL) {
		return -1;
	}

	if (!IS_VALID_REF(tree, ref)) {
		return -1;
	}

	if (!REF_IS_PRESENT(tree, ref)) {
		return 0;
	}

	int count = 1;
	for (int i = 0; i < tree->size; i++) {
		// only root has the reference to itself
		if (tree->refs[i] == ref && ref != i) {
			count += vtree_subtree_size(tree, i);
		}
	}

	return count;
}

// iterate through the first level children, use a cursor like strtok_r
int vtree_children_it(Vtree *tree, int parent, int *cursor)
{
	if (tree == NULL || cursor == NULL) {
		return -1;
	}

	// if the cursor is out of bounds then we are done for sure
	if (!IS_VALID_REF(tree, *cursor)) {
		return -1;
	}

	// same for the parent, if it's invalid it can't have children
	if (!IS_VALID_REF(tree, parent) || !REF_IS_PRESENT(tree, parent)) {
		return -1;
	}

	// find the first child, update the cursor and return the ref
	for (int i = *cursor; i < tree->size; i++)  {
		if (tree->refs[i] == parent) {
			*cursor = i + 1;
			return i;
		}
	}

	// if no children are found return -1
	*cursor = -1;
	return -1;
}

/* iterates trough every leaf of the subtree in the following manner 
 * node [x], x: visit order
 *              [0]
 *             / | \
 *            / [2] [3]
 *          [1]      |
 *         /   \    [6]
 *       [4]   [5]
 */
int vtree_level_order_it(Vtree *tree, int ref, int **queue_p, int *cursor)
{
	if (tree == NULL || queue_p == NULL || cursor == NULL) {
		return -1;
	}

	int *queue = *queue_p;
	
	// TODO: this could also be done when adding or removing elements
	// first call, create a ref array ordered like we desire
	if (queue == NULL) {
		*cursor = 0;
		// create a queue of invalid refs, size is the worst case
		queue = malloc(sizeof(int) * tree->size);
		if (queue == NULL) {
			return -1;
		}
		for (int i = 0; i < tree->size; i++) {
			queue[i] = -1;
		}
		*queue_p = queue;

		// iterate through the queue appending found children
		int pos = 0, off = 0;
		do {
			//printf ("ref=%d\n", ref);
			
			for (int i = 0; i < tree->size; i++) {
				if (tree->refs[i] == ref) {
					queue[pos++] = i;
				}
			}

			for (;ref == queue[off] && off < tree->size; off++);
			ref = queue[off];
	
		} while (IS_VALID_REF(tree, ref));
	}

	//PRINT_ARR(queue, tree->size);
	//return -1;

	// on successive calls just iterate through the queue until we find an 
	// invalid ref
	int ret = queue[(*cursor)++];
	if (!IS_VALID_REF(tree, ret)) {
		free(queue);
	}

	return ret;
}
#endif // VTREE_IMPL

#endif // VTREE_DTYPE

#endif

