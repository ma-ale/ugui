//#!/usr/bin/tcc -run

#include <stdio.h>
#include <stdlib.h>
#include <string.h>


#define HASH_SALT (0xbabb0cac)
#define HASH_RATIO64 ((unsigned long int)11400714819322457583u)


struct ntree_node
{
	unsigned int id;
	const char *name;
	int children_no, children_size;
	struct ntree_node *children, *parent;
};


static char tmp_name_buffer[16] = {"node:"};


unsigned int hash_str_to_uint(const char *s)
{
	unsigned int h = HASH_SALT;
	const unsigned char *v = (const unsigned char *)(s);
	for (int x = *s; x; x--) {
		h += v[x-1];
		h += h << 10;
		h ^= h >> 6;
	}
	h += h << 3;
  	h ^= h >> 11;
  	h += h << 15;
	return h;
}


unsigned int hash_u32(unsigned int c)
{
	return (unsigned int)((((unsigned long int)c<<31)*HASH_RATIO64)>>32);
}


const char * generate_new_name(void)
{
	static int count = 0;
	unsigned int h = hash_u32(count++);
	snprintf(tmp_name_buffer+sizeof("node:"), 16-sizeof("node:"), "%x", h);
	return tmp_name_buffer;
}


int tree_prune(struct ntree_node *node)
{
	if (node == NULL)
		return 0;

	if ((node->children_no == 0 && node->children != NULL) ||
	    (node->children_no != 0 && node->children == NULL)) {
		printf("ERR: (%x %s) Inconsistent node children", node->id, node->name);
	} else for (int i = 0; i < node->children_no; i++) {
		tree_prune(&(node->children[i]));
	}

	if (node->children != NULL) {
		free(node->children);
	}
	free((void *)node->name);
	if (node->parent != NULL)
		node->parent->children_no--;
	*node = (struct ntree_node){0};

	return 0;
}


struct ntree_node * tree_append(struct ntree_node *parent, const char *name)
{
	if (name == NULL)
		return NULL;
	if (strlen(name) == 0)
		name = generate_new_name();

	// generate the children information
	unsigned int id = hash_str_to_uint(name);
	char *str = malloc(strlen(name)+1);
	if (str == NULL)
		return NULL;
	strcpy(str, name);

	// grow the parent buffer if necessary
	if (parent->children_no >= parent->children_size) {
		struct ntree_node *temp = NULL;
		temp = realloc(parent->children, (parent->children_size+1)*sizeof(struct ntree_node));
		if (temp == NULL) {
			free(str);
			return NULL;
		}

		parent->children = temp;
 		parent->children[parent->children_size] = (struct ntree_node){0};
		parent->children_size++;
	}

	// find an open spot for the child
	struct ntree_node *child = NULL;
	for (int i = 0; i < parent->children_size; i++) {
		if (parent->children[i].id == 0)
			child = &(parent->children[i]);
	}
	if (child == NULL)
		return NULL;

	child->name = str;
	child->id = id;
	child->children = NULL;
	child->children_no = 0;
	child->parent = parent;
	parent->children_no++;
	//printf("append to %s, children: %d\n", parent->name, parent->children_no);
	return child;
}


struct ntree_node * tree_find_id(struct ntree_node *root, unsigned int id)
{
	if (id == 0 || root == NULL)
		return NULL;

	if (root->id == id)
		return root;

	else for (int i = 0; i < root->children_size; i++) {
		if (root->children[i].id != 0 && tree_find_id(&(root->children[i]), id) != NULL)
			return &(root->children[i]);
	}
	return NULL;
}


// TODO: add a foreach_child function
struct ntree_node * tree_find(struct ntree_node *root, const char *name)
{
	if (name == NULL || strlen(name) == 0 || root == NULL)
		return NULL;
	unsigned int id = hash_str_to_uint(name);
	return tree_find_id(root, id);
}


int tree_size(struct ntree_node *root)
{
	if (root == NULL)
		return 0;

	int count = root->children_no;
	if (count > 0) {
		for (int i = 0; i < root->children_size;  i++) {
			if (root->children[i].id != 0)
				count += tree_size(&(root->children[i]));
		}
	}

	return count;
}


static int tree_print_ind(struct ntree_node *node, int dd)
{
	for (int i = 0; i < dd; i++) printf("  ");
	printf("[%s]\n", node->name);
	for (int i = 0; i < node->children_size; i++) {
		if (node->children[i].id == 0) continue;
			tree_print_ind(&(node->children[i]), dd+1);
	}
	return node->children_no;
}


int tree_print(struct ntree_node *root)
{
	if (root == NULL)
		return 1;

	tree_print_ind(root, 0);

	return 0;
}


int main(void)
{
	char *root_name = malloc(sizeof("root"));
	strcpy(root_name, "root");
	struct ntree_node root = {.name = root_name};
	struct ntree_node *n;

	n = tree_append(&root, "node 0:0");
	tree_append(n, "node 0:0:0");
	tree_append(&root, "node 0:1");
	tree_append(&root, "node 0:2");
	printf("Number of nodes %d\n", tree_size(&root));
	tree_print(&root);

	tree_prune(tree_find(&root, "node 0:0"));
	printf("Number of nodes %d\n", tree_size(&root));

	tree_prune(&root);
	printf("Number of nodes %d\n", tree_size(&root));

	return 0;
}
