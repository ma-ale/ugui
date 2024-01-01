#include <stdlib.h>
#include <string.h>

#include "ugui.h"

#define IS_VALID_REF(t, r)   ((r) >= 0 && (r) < (t)->size)
#define REF_IS_PRESENT(t, r) ((t)->refs[r] >= 0)

int ug_tree_init(UgTree *tree, unsigned int size)
{
	if (tree == NULL) {
		return -1;
	}

	tree->vector = malloc(sizeof(UgId) * size);
	if (tree->vector == NULL) {
		return -1;
	}

	tree->refs = malloc(sizeof(int) * size);
	if (tree->refs == NULL) {
		free(tree->vector);
		return -1;
	}

	// ordered refs are used in the iterators
	tree->ordered_refs = malloc(sizeof(int) * size);
	if (tree->ordered_refs == NULL) {
		free(tree->vector);
		free(tree->refs);
		return -1;
	}

	// set all refs to -1, meaning invalid (free) element
	for (unsigned int i = 0; i < size; i++) {
		tree->refs[i] = -1;
	}

	// fill vector with zeroes
	memset(tree->vector, 0, size * sizeof(UgId));

	tree->size     = size;
	tree->elements = 0;

	return 0;
}

int ug_tree_destroy(UgTree *tree)
{
	if (tree == NULL) {
		return -1;
	}

	free(tree->vector);
	free(tree->refs);

	return 0;
}

int ug_tree_pack(UgTree *tree)
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
			tree->refs[free_spot]   = tree->refs[i];

			tree->vector[i] = 0;
			tree->refs[i]   = -1;

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

int ug_tree_resize(UgTree *tree, unsigned int newsize)
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
		// if (ug_tree_pack(tree) < 0) {
		//	return -1;
		// }
		//  TODO: allow shrinking, since packing destroys all references
		return -1;
	}

	UgId *newvec = realloc(tree->vector, newsize * sizeof(UgId));
	if (newvec == NULL) {
		return -1;
	}

	int *newrefs = realloc(tree->refs, newsize * sizeof(int));
	if (newrefs == NULL) {
		return -1;
	}

	int *neworrefs = realloc(tree->ordered_refs, newsize * sizeof(int));
	if (neworrefs == NULL) {
		return -1;
	}

	tree->vector       = newvec;
	tree->refs         = newrefs;
	tree->ordered_refs = neworrefs;
	if ((int)newsize > tree->size) {
		for (int i = tree->size; i < (int)newsize; i++) {
			tree->vector[i] = 0;
			tree->refs[i]   = -1;
		}
	}

	tree->size = newsize;

	return 0;
}

// add an element to the tree, return it's ref
int ug_tree_add(UgTree *tree, UgId elem, int parent)
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
	tree->refs[free_spot]   = parent;
	tree->elements++;

	return free_spot;
}

// prune the tree starting from the ref
// returns the number of pruned elements
int ug_tree_prune(UgTree *tree, int ref)
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

	tree->vector[ref] = 0;
	tree->refs[ref]   = -1;

	int count = 1;
	for (int i = 0; i < tree->size; i++) {
		if (tree->refs[i] == ref) {
			count += ug_tree_prune(tree, i);
		}
	}

	return count;
}

// find the size of the subtree starting from ref
int ug_tree_subtree_size(UgTree *tree, int ref)
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
			count += ug_tree_subtree_size(tree, i);
		}
	}

	return count;
}

// iterate through the first level children, use a cursor like strtok_r
int ug_tree_children_it(UgTree *tree, int parent, int *cursor)
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
	for (int i = *cursor; i < tree->size; i++) {
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
int ug_tree_level_order_it(UgTree *tree, int ref, int *cursor)
{
	if (tree == NULL || cursor == NULL) {
		return -1;
	}

	int *queue = tree->ordered_refs;

	// TODO: this could also be done when adding or removing elements
	// first call, create a ref array ordered like we desire
	if (queue == NULL) {
		*cursor = 0;
		for (int i = 0; i < tree->size; i++) {
			queue[i] = -1;
		}

		// iterate through the queue appending found children
		int pos = 0, off = 0;
		do {
			// printf ("ref=%d\n", ref);

			for (int i = 0; i < tree->size; i++) {
				if (tree->refs[i] == ref) {
					queue[pos++] = i;
				}
			}

			for (; ref == queue[off] && off < tree->size; off++)
				;
			ref = queue[off];

		} while (IS_VALID_REF(tree, ref));
	}

	// PRINT_ARR(queue, tree->size);
	// return -1;

	// on successive calls just iterate through the queue until we find an
	// invalid ref, if the user set the cursor to -1 it means it has found what
	// he needed, so free
	if (*cursor < 0) {
		return -1;
	} else if (IS_VALID_REF(tree, *cursor)) {
		return queue[(*cursor)++];
	}

	return -1;
}

int ug_tree_parentof(UgTree *tree, int node)
{
	if (tree == NULL || !IS_VALID_REF(tree, node) ||
	    !REF_IS_PRESENT(tree, node)) {
		return -1;
	}
	return tree->refs[node];
}
