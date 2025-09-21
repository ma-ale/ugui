module mtree{Type};

import std::core::mem;
import std::core::mem::allocator;
import std::io;
import std::bits;
import std::collections::list;


alias Bitmap = ulong;
const BITS = Bitmap.sizeof*8;

alias IdxList = list::List{int};

// more: if positive it contains the index of the next node that contains the children information
struct Node {
	int more;
	int parent;
	Bitmap children;
}

struct MTree {
	usz elements;
	Allocator allocator;
	IdxList  queue;
	Bitmap[] used;
	Type[]   elem_mat; // element matrix
	Node[]   refs_mat;  // relationship matrix
}


fn void MTree.init(&tree, usz size, Allocator allocator = mem)
{
	// round size to the nearest multiple of BITS
	size = size + size%BITS;

	tree.elements = 0;
	tree.allocator = allocator;
	tree.queue.init(allocator, size);
	tree.used     = allocator::new_array(tree.allocator, Bitmap, size/BITS);
	tree.elem_mat = allocator::new_array(tree.allocator, Type, size);
	tree.refs_mat = allocator::new_array(tree.allocator, Node, size);
	
	foreach (&r: tree.refs_mat) {
		r.more = -1;
	}
}


fn void MTree.free(&tree)
{
	tree.elements = 0;
	tree.queue.free();
	(void)allocator::free(tree.allocator, tree.used);
	(void)allocator::free(tree.allocator, tree.elem_mat);
	(void)allocator::free(tree.allocator, tree.refs_mat);
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
fn void MTree.set_used(&tree, int idx)
{
	int r = idx % BITS;
	int q = idx / BITS;
	tree.used[q] |= (1l << r);
}

<* @require idx >= 0 *>
fn void MTree.unset_used(&tree, int idx)
{
	int r = idx % BITS;
	int q = idx / BITS;
	tree.used[q] &= ~(1l << r);
}

<* @require idx >= 0 *>
fn bool MTree.is_used(&tree, int idx)
{
	int r = idx % BITS;
	int q = idx / BITS;
	return !!(tree.used[q] & (1l << r));
}


// get the last node in the "more" chain
<* @require tree.is_used(parent) == true *>
fn int MTree.last_node(&tree, int parent)
{
	while(tree.refs_mat[parent].more >= 0) {
		parent = tree.refs_mat[parent].more;
	}
	return parent;
}


<* @require tree.elements == 0 || tree.is_used(parent) == true *>
fn int MTree.add(&tree, int parent, Type t)
{
	int idx = tree.get_free_spot();
	int subtree = idx / BITS;

	tree.set_used(idx);
	tree.elem_mat[idx] = t;
	tree.refs_mat[idx] = (Node){
		.parent = parent,
		.more = -1,
	};
	
	tree.elements++;
	// root element, has no parent
	if (tree.elements == 1) {
		tree.refs_mat[idx].parent = -1;
		return idx;
	}
	

	// if the parent already has a node in the same subtree as the child then update that node's
	// children bitmap
	bool done;
	for (int p = parent; p >= 0; p = tree.refs_mat[p].more) {
		int ps = p/BITS;
		if (ps == subtree) {
			tree.refs_mat[p].children |= (1l << (idx%BITS));
			done = true;
			break;
		}
	}
	// on fail we need to create another parent node
	if (!done) {
		int new_more = tree.get_free_spot();
		// if the new node does not land in the same subtree as the child we cannot do
		// anything since the references are immutable
		if (new_more/BITS != subtree) {
			unreachable("cannot allocate new child for parent");
		}
		tree.set_used(new_more);
		tree.elements++;
		// update the "more" chain
		int last_link = tree.last_node(parent);
		tree.refs_mat[last_link].more = new_more;
		tree.refs_mat[new_more].more = -1;
		tree.refs_mat[new_more].children |= (long)(1 << (idx%BITS));
		tree.refs_mat[new_more].parent = last_link;
		// FIXME: the elem_mat is not updated, do we need to?
	}

	return idx;
}


// get the index of the n-th children of parent, -1 otherwise
// usage: for (int i, c; (c = tree.children_it(parent, i)) >= 0; i++) { ... }
fn int MTree.children_it(&tree, int parent, int n)
{
	int tot_children;
	int child;
	for (int p = parent; p >= 0; p = tree.refs_mat[p].more) {
		int cn = (int)tree.refs_mat[p].children.popcount();
		tot_children += cn;

		// we are in the right subtree
		if (tot_children > n) {
			child = (p/BITS) * BITS; // start at the parent's subtree index
			int j = cn - (tot_children - n); // we need the j-th children of this node
			Bitmap u = tree.refs_mat[p].children;

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
	for (int p = parent; p >= 0; p = tree.refs_mat[p].more) {
		n += (int)tree.refs_mat[p].children.popcount();
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

		// delete all children including their more chain
		for (int p = c; p >= 0;) {
			int next = tree.refs_mat[p].more;
			tree.unset_used(p);
			tree.refs_mat[p] = {.more = -1};
			p = next;
		}

	}

	// finally delete the parent
	for (int p = parent; p >= 0;) {
		int next = tree.refs_mat[p].more;
		tree.unset_used(p);
		tree.elements--;
		tree.refs_mat[p] = {.more = -1};
		p = next;
	}

}


macro bool MTree.is_root(&t, int i) => t.refs_mat[i].parent == -1;

fn void MTree.print(&tree)
{
	foreach (idx, c: tree.elem_mat) {
		if (tree.is_used((int)idx)) {
			io::printfn("[%d](%s) parent:%d more:%d children:%b",
			             idx, c, tree.refs_mat[idx].parent, tree.refs_mat[idx].more,
			             tree.refs_mat[idx].children
			           );
		}
	}
}


module foo;

import std::io;
import mtree;

alias Tree = mtree::MTree{int};

fn int main()
{
	Tree t;
	t.init(256);
	defer t.free();
/*
	int root = t.add(0, 0);
	int c1 = t.add(root, 1);
	int c2 = t.add(root, 2);
	
	int c11 = t.add(c1, 11);
	int c12 = t.add(c1, 12);
	
	int c3 = t.add(root, 3);

	for (int x = 0;  x < 70; x++) {
		t.add(c2, x);
	}
	
	int c31 = t.add(c3, 31);
	int c32 = t.add(c3, 32);

	int c4 = t.add(root, 4);
	
	int c13 = t.add(c1, 13);
	int c14 = t.add(c1, 14);
	int c15 = t.add(c1, 15);

	t.prune(c2);

	io::printn("printing tree");
	t.print();
	
	usz x;
	foreach_r (u: t.used) {
		x += u.popcount();
		io::printf("%b ", u);
	}
	io::printfn("TOT:%d/%d",x,t.elements);

	io::printn(t.subtree_size(root));

	io::printn();
*/

	int root = t.add(0, 0);
	int c1 = t.add(root, 1);
	int c2 = t.add(root, 2);
	int c3 = t.add(root, 3);
	
	int c11 = t.add(c1, 11);
	int c12 = t.add(c1, 12);
	
	int c111 = t.add(c11, 111);
	int c121 = t.add(c12, 121);
	
	int c31 = t.add(c3, 31);

	int c;
	for (int i; (c = t.level_order_it(root, i)) >= 0; i++) {
		io::printfn("%d-th: [%d](%d)", i, c, t.elem_mat[c]);
	}

	return 0;
}