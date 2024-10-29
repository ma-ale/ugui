module vtree(<ElemType>);

import std::core::mem;
import std::io;

struct VTree {
	usz elements;
	ElemType[] vector; // vector of element ids
	isz[] refs, ordered_refs;
}

fault VTreeError {
    CANNOT_SHRINK,
    INVALID_REFERENCE,
    TREE_FULL,
    REFERENCE_NOT_PRESENT,
    INVALID_ARGUMENT,
}

macro VTree.ref_is_valid(&tree, isz ref) { return (ref >= 0 && ref < tree.refs.len); }
macro VTree.ref_is_present(&tree, isz ref) { return tree.refs[ref] >= 0; }
macro VTree.size(&tree) { return tree.refs.len; }

// macro to zero an elemen
macro @zero()
{
	$if $assignable(0, ElemType):
		return 0;
	$else
		return ElemType{0};
	$endif
}

fn void! VTree.init(&tree, usz size)
{
	tree.vector = mem::new_array(ElemType, size);
	defer catch { (void)mem::free(tree.vector); }

	tree.refs = mem::new_array(isz, size);
	defer catch { (void)mem::free(tree.refs); }

	tree.ordered_refs = mem::new_array(isz, size);
	defer catch { (void)mem::free(tree.ordered_refs); }

	// set all refs to -1, meaning invalid (free) element
	tree.refs[..] = -1;

	tree.elements = 0;
}

fn void VTree.free(&tree)
{
	(void)mem::free(tree.vector);
	(void)mem::free(tree.refs);
	(void)mem::free(tree.ordered_refs);
}

fn void VTree.pack(&tree)
{
	// TODO: add a PACKED flag to skip this

	isz free_spot = -1;
	for (usz i = 0; i < tree.size(); i++) {
		if (tree.refs[i] == -1) {
			free_spot = i;
			continue;
		}

		// find a item that can be packed
		if (free_spot >= 0 && tree.refs[i] >= 0) {
			isz old_ref = i;

			// move the item
			tree.vector[free_spot] = tree.vector[i];
			tree.refs[free_spot]   = tree.refs[i];

			tree.vector[i] = @zero();
			tree.refs[i]   = -1;

			// and move all references
			for (usz j = 0; j < tree.size(); j++) {
				if (tree.refs[j] == old_ref) {
				    tree.refs[j] = free_spot;
				}
			}

			// mark the free spot as used
			free_spot = -1;
		}
	}
}

fn void! VTree.resize(&tree, usz newsize)
{
	// return error when shrinking with too many elements
	if (newsize < tree.elements) {
		return VTreeError.CANNOT_SHRINK?;
	}

	// pack the vector when shrinking to avoid data loss
	if ((int)newsize < tree.size()) {
		// FIXME: packing destroys all references to elements of vec
		//        so shrinking may cause dangling pointers
		return VTreeError.CANNOT_SHRINK?;
	}

	usz old_size = tree.size();

	tree.vector = ((ElemType*)mem::realloc(tree.vector, newsize*ElemType.sizeof))[:newsize];
	defer catch { (void)mem::free(tree.vector); }

	tree.refs = ((isz*)mem::realloc(tree.refs, newsize*isz.sizeof))[:newsize];
	defer catch { (void)mem::free(tree.refs); }

	tree.ordered_refs = ((isz*)mem::realloc(tree.ordered_refs, newsize*isz.sizeof))[:newsize];
	defer catch { (void)mem::free(tree.ordered_refs); }

	if (newsize > tree.size()) {
	   tree.vector[old_size..newsize-1] = @zero();
	   tree.refs[old_size..newsize-1] = -1;
	}
}

// add an element to the tree, return it's ref
fn isz! VTree.add(&tree, ElemType elem, isz parent)
{
	// invalid parent
	if (!tree.ref_is_valid(parent)) {
		return VTreeError.INVALID_REFERENCE?;
	}

	// no space left
	if (tree.elements >= tree.size()) {
	   return VTreeError.TREE_FULL?;
	}

	// check if the parent exists
	// if there are no elements in the tree the first add will set the root
	if (!tree.ref_is_present(parent) && tree.elements != 0) {
	   return VTreeError.REFERENCE_NOT_PRESENT?;
	}

	// get the first free spot
	isz free_spot = -1;
	for (usz i = 0; i < tree.size(); i++) {
		if (tree.refs[i] == -1) {
			free_spot = i;
			break;
		}
	}
	if (free_spot < 0) {
		return VTreeError.TREE_FULL?;
	}

	// finally add the element
	tree.vector[free_spot] = elem;
	tree.refs[free_spot]   = parent;
	tree.elements++;

	return free_spot;
}

// prune the tree starting from the ref
// returns the number of pruned elements
fn usz! VTree.prune(&tree, isz ref)
{
    if (!tree.ref_is_valid(ref)) {
		return VTreeError.INVALID_REFERENCE?;
	}

	if (!tree.ref_is_present(ref)) {
		return 0;
	}

	tree.vector[ref] = @zero();
	tree.refs[ref]   = -1;
	tree.elements--;

	usz count = 1;
	for (usz i = 0; tree.elements > 0 && i < tree.size(); i++) {
		if (tree.refs[i] == ref) {
			count += tree.prune(i)!;
		}
	}

	return count;
}

// find the size of the subtree starting from ref
fn usz! VTree.subtree_size(&tree, isz ref)
{
    if (!tree.ref_is_valid(ref)) {
		return VTreeError.INVALID_REFERENCE?;
	}

	if (!tree.ref_is_present(ref)) {
		return 0;
	}

	usz count = 1;
	for (usz i = 0; i < tree.size(); i++) {
		// only root has the reference to itself
		if (tree.refs[i] == ref && ref != i) {
			count += tree.subtree_size(i)!;
		}
	}

	return count;
}

// iterate through the first level children, use a cursor like strtok_r
fn isz! VTree.children_it(&tree, isz parent, isz *cursor)
{
	if (cursor == null) {
		return VTreeError.INVALID_ARGUMENT?;
	}

	// if the cursor is out of bounds then we are done for sure
	if (!tree.ref_is_valid(*cursor)) {
		return VTreeError.INVALID_REFERENCE?;
	}

	// same for the parent, if it's invalid it can't have children
	if (!tree.ref_is_valid(parent) || !tree.ref_is_present(parent)) {
		return VTreeError.INVALID_REFERENCE?;
	}

	// find the first child, update the cursor and return the ref
	for (isz i = *cursor; i < tree.size(); i++) {
		if (tree.refs[i] == parent) {
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
fn isz! VTree.level_order_it(&tree, isz ref, isz *cursor)
{
	if (cursor == null) {
	   return VTreeError.INVALID_ARGUMENT?;
	}

	isz[] queue = tree.ordered_refs;

	// TODO: this could also be done when adding or removing elements
	// first call, create a ref array ordered like we desire
	if (*cursor == -1) {
		*cursor = 0;
		queue[..] = -1;

		// iterate through the queue appending found children
		isz pos, off;
		do {
			// printf ("ref=%d\n", ref);
			for (isz i = 0; i < tree.size(); i++) {
				if (tree.refs[i] == ref) {
					queue[pos++] = i;
				}
			}

			for (; ref == queue[off] && off < tree.size(); off++);
			ref = queue[off];

		} while (tree.ref_is_valid(ref));
		// This line is why tree.ordered_refs has to be size+1
		queue[off + 1] = -1;
	}

	// PRINT_ARR(queue, tree.size());
	// return -1;

	// on successive calls just iterate through the queue until we find an
	// invalid ref, if the user set the cursor to -1 it means it has found what
	// he needed, so free
	if (*cursor < 0) {
		return -1;
	} else if (tree.ref_is_valid(*cursor)) {
		return queue[(*cursor)++];
	}

	return -1;
}

fn isz! VTree.parentof(&tree, isz ref)
{
	if (!tree.ref_is_valid(ref)) {
		return VTreeError.INVALID_REFERENCE?;
	}

	if (!tree.ref_is_present(ref)) {
	   return VTreeError.REFERENCE_NOT_PRESENT?;
	}

	return tree.refs[ref];
}

fn ElemType! VTree.get(&tree, isz ref)
{
    if (!tree.ref_is_valid(ref)) {
		return VTreeError.INVALID_REFERENCE?;
	}

	if (!tree.ref_is_present(ref)) {
	   return VTreeError.REFERENCE_NOT_PRESENT?;
	}

	return tree.vector[ref];
}

fn void VTree.print(&tree)
{
	for (isz i = 0; i < tree.size(); i++) {
		if (tree.refs[i] == -1) {
			continue;
		}
		io::printf("[%d] {parent=%d, data=", i, tree.refs[i]);
		io::print(tree.vector[i]);
		io::printn("}");
	}
}
