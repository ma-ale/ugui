module mtree{Type};

/* ================================================================================================
 * MTree, Bitmap-based tree
 * ================================================================================================
 *
 *  Overview
 *  --------
 *  The MTree is a bitmap-based tree structure composed of three core elements:
 *    - Element Vector: Stores user data.
 *    - Reference Node Vector: Manages node relationships.
 *    - Bitmap: Marks used indices.
 *
 *  The name "MTree" originates from "Matrix Tree," where the vector is divided into
 *  sectors of power-of-two sizes. Each node's bitmap marks the positions of its
 *  children within the same sector.
 *
 *  If a parent and its children are in different sectors, a new node is created.
 *  The parent's "next" field points to this new node, forming a chain that must
 *  be traversed during iteration.
 *
 *
 *  Example (sector size = 8)
 *  -------------------------
 *
 *             _________________________________
 *            |__ __ _______________________    |
 *            |  |  |                       | _ |
 *            |  v  v                       vv |v
 *           +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
 *  refs_vec:| 0| 1| 2| 3| 4| 5| 6| 7| 8| 9|10|11|12|13|14|15|16|...
 *           +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
 *            \__________ __________/ \__________ __________/ \__
 *                       V                       V
 *                    sector 0                sector 1
 *
 *
 *  Node Relationships:
 *  -------------------
 *    - Root (Element 0) has three direct children: 1, 2, and 10.
 *    - Node 10 is in a different sector than the root, so root.next points to Node 11.
 *    - Node 11 has Node 10 as a direct child and Node 0 (root) as its parent.
 *
 *  Bitmap Representation:
 *  ---------------------
 *
 *       root = {
 *         .parent = -1;           // Root has no parent
 *         .next    = 11;          // Points to Node 11
 *         .children = 0b00000110; // [0|1|1|0|0|0|0|0] (Children: 1, 2)
 *       }
 *
 *       node11 = {
 *         .parent   = 0;          // Parent is root (Node 0)
 *         .next     = -1;         // Last in the chain
 *         .children = 0b00000100; // [0|0|1|0|0|0|0|0] (Child: 10)
 *       }
 *
 * ================================================================================================
 */

import std::core::mem;
import std::core::mem::allocator;
import std::io;
import std::bits;
import std::collections::list;


alias Bitmap = ulong;
const BITS = Bitmap.sizeof*8;

alias IdxList = List{int};

// next: if positive it contains the index of the next node that contains the children information
struct RefNode {
	int next;
	int parent;
	Bitmap children;
}

struct MTree {
	usz elements;
	Allocator allocator;
	IdxList  queue;
	Bitmap[]  used;
	Type[]    elem_vec; // element vector
	RefNode[] refs_vec; // relationship vector
}


fn void MTree.init(&tree, usz size, Allocator allocator = mem)
{
	// round size to the nearest multiple of BITS
	size = size + size%BITS;

	tree.elements = 0;
	tree.allocator = allocator;
	tree.queue.init(tree.allocator, size);
	tree.used     = allocator::new_array(tree.allocator, Bitmap, size/BITS);
	tree.elem_vec = allocator::new_array(tree.allocator, Type, size);
	tree.refs_vec = allocator::new_array(tree.allocator, RefNode, size);

	foreach (&r: tree.refs_vec) {
		r.next = -1;
	}
}


fn void MTree.free(&tree)
{
	tree.elements = 0;
	tree.queue.free();
	(void)allocator::free(tree.allocator, tree.used);
	(void)allocator::free(tree.allocator, tree.elem_vec);
	(void)allocator::free(tree.allocator, tree.refs_vec);
}


fn int MTree.get_free_spot(&tree)
{
	foreach (idx, d: tree.used) {
		if (d != $typeof(d).max) {
			int spot = (int)idx*BITS + BITS-(int)d.clz();
			return spot;
		}
	}
	unreachable("no free spots left");
}

<* @require idx >= 0 *>
macro void MTree.set_used(&tree, int idx)
{
	int r = idx % BITS;
	int q = idx / BITS;
	tree.used[q] |= (1l << r);
}

<* @require idx >= 0 *>
macro void MTree.unset_used(&tree, int idx)
{
	int r = idx % BITS;
	int q = idx / BITS;
	tree.used[q] &= ~(1l << r);
}

<* @require idx >= 0 *>
macro bool MTree.is_used(&tree, int idx)
{
	int r = idx % BITS;
	int q = idx / BITS;
	return !!(tree.used[q] & (1l << r));
}


// get the last node in the "next" chain
<* @require tree.is_used(parent) == true *>
fn int MTree.last_node(&tree, int parent)
{
	while(tree.refs_vec[parent].next >= 0) {
		parent = tree.refs_vec[parent].next;
	}
	return parent;
}


<* @require tree.elements == 0 || tree.is_used(parent) == true *>
fn int MTree.add(&tree, int parent, Type t)
{
	int idx = tree.get_free_spot();
	int subtree = idx / BITS;

	tree.set_used(idx);
	tree.elem_vec[idx] = t;
	tree.refs_vec[idx] = (RefNode){
		.parent = parent,
		.next = -1,
	};

	tree.elements++;
	// root element, has no parent
	if (tree.elements == 1) {
		tree.refs_vec[idx].parent = -1;
		return idx;
	}


	// if the parent already has a node in the same subtree as the child then update that node's
	// children bitmap
	bool done;
	for (int p = parent; p >= 0; p = tree.refs_vec[p].next) {
		int ps = p/BITS;
		if (ps == subtree) {
			tree.refs_vec[p].children |= (1l << (idx%BITS));
			done = true;
			break;
		}
	}
	// on fail we need to create another parent node
	if (!done) {
		int new_next = tree.get_free_spot();
		// if the new node does not land in the same subtree as the child we cannot do
		// anything since the references are immutable
		if (new_next/BITS != subtree) {
			unreachable("cannot allocate new child for parent");
		}
		tree.set_used(new_next);
		tree.elements++;
		// update the "next" chain
		int last_link = tree.last_node(parent);
		tree.refs_vec[last_link].next = new_next;
		tree.refs_vec[new_next].next = -1;
		tree.refs_vec[new_next].children |= (long)(1 << (idx%BITS));
		tree.refs_vec[new_next].parent = last_link;
		// FIXME: the elem_vec is not updated, do we need to?
	}

	return idx;
}


// get the index of the n-th children of parent, -1 otherwise
// usage: for (int i, c; (c = tree.children_it(parent, i)) >= 0; i++) { ... }
fn int MTree.children_it(&tree, int parent, int n)
{
	int tot_children;
	int child;
	for (int p = parent; p >= 0; p = tree.refs_vec[p].next) {
		int cn = (int)tree.refs_vec[p].children.popcount();
		tot_children += cn;

		// we are in the right subtree
		if (tot_children > n) {
			child = (p/BITS) * BITS; // start at the parent's subtree index
			int j = cn - (tot_children - n); // we need the j-th children of this node
			Bitmap u = tree.refs_vec[p].children;

			child += j; // add the children number
			do {
				child += (int)u.ctz(); // increment by the skipped zeroes
				u >>= u.ctz() + 1;
				j--;
			} while (j >= 0);

			return child;
		}
	}
	return -1;
}

fn int MTree.children_num(&tree, int parent)
{
	int n;
	for (int p = parent; p >= 0; p = tree.refs_vec[p].next) {
		n += (int)tree.refs_vec[p].children.popcount();
	}
	return n;
}

fn int MTree.subtree_size(&tree, int parent)
{
	int x = tree.children_num(parent);
	int c;
	for (int n; (c = tree.children_it(parent, n)) >= 0; n++) {
		x += tree.subtree_size(c);
	}
	return x;
}



fn int MTree.level_order_it(&tree, int parent, int i)
{
	if (i == 0) {
		tree.queue.clear();
		tree.queue.push(parent);
	}

	if (tree.queue.len() == 0) return -1;

	int p = tree.queue.pop_first()!!;
	int c;
	for (int n; (c = tree.children_it(p, n)) >= 0; n++) {
		tree.queue.push(c);
	}
	return p;
}

fn void MTree.prune(&tree, int parent)
{
	int c;
	for (int i = 0; (c = tree.children_it(parent, i)) >= 0; i++) {
		tree.prune(c); // prune the subtree

		// delete all children including their next chain
		for (int p = c; p >= 0;) {
			int next = tree.refs_vec[p].next;
			tree.unset_used(p);
			tree.refs_vec[p] = {.next = -1};
			p = next;
		}

	}

	// finally delete the parent
	for (int p = parent; p >= 0;) {
		int next = tree.refs_vec[p].next;
		tree.unset_used(p);
		tree.elements--;
		tree.refs_vec[p] = {.next = -1};
		p = next;
	}

}

<* @require ref >= 0 , ref < tree.elem_vec.len *>
fn Type? MTree.get(&tree, int ref) @operator([])
{
	if (tree.is_used(ref)) return tree.elem_vec[ref];
	return NOT_FOUND?;
}

<* @require tree.is_used(ref) *>
fn Type MTree.parentof(&tree, int ref) => tree.refs_vec[ref].parent;

fn void MTree.nuke(&tree)
{
	foreach (idx, &b: tree.used) {
		*b = 0;
		tree.refs_vec[idx] = {.next = -1};
	}
	tree.elements = 0;
}


macro bool MTree.is_root(&t, int i) => t.refs_vec[i].parent == -1;

fn void MTree.print(&tree)
{
	foreach (idx, c: tree.elem_vec) {
		if (tree.is_used((int)idx)) {
			io::printfn("[%d](%s) parent:%d next:%d children:%b",
			             idx, c, tree.refs_vec[idx].parent, tree.refs_vec[idx].next,
			             tree.refs_vec[idx].children
			           );
		}
	}
}
