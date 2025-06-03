module fifo::faults;
faultdef FULL, EMPTY;

module fifo{Type};

import std::core::mem;
import std::sort;

// TODO: specify the allocator

struct Fifo {
	Type[] arr;
	usz out;
	usz count;
}

fn void? Fifo.init(&fifo, usz size)
{
	fifo.arr = mem::new_array(Type, size);
	fifo.out = 0;
	fifo.count = 0;
}

fn void Fifo.free(&fifo)
{
	(void)mem::free(fifo.arr);
}

fn void? Fifo.enqueue(&fifo, Type *elem)
{
	if (fifo.count >= fifo.arr.len) {
		return fifo::faults::FULL?;
	}
	usz in = (fifo.out + fifo.count) % fifo.arr.len;
	fifo.arr[in] = *elem;
	fifo.count++;
}

fn Type*? Fifo.dequeue(&fifo)
{
	if (fifo.count == 0) {
		return fifo::faults::EMPTY?;
	}
	Type *ret = &fifo.arr[fifo.out];
	fifo.count--;
	fifo.out = (fifo.out + 1) % fifo.arr.len;
	return ret;
}

macro Type Fifo.get(&fifo, usz i) @operator([])
{
	return fifo.arr[(fifo.out + i) % fifo.arr.len];
}

fn void Fifo.set(&fifo, usz i, Type val) @operator([]=)
{
	fifo.arr[(fifo.out + i) % fifo.arr.len] = val;
}

macro Type* Fifo.get_ref(&fifo, usz i) @operator(&[])
{
	return &fifo.arr[(fifo.out + i) % fifo.arr.len];
}

macro usz Fifo.len(&fifo) @operator(len)
{
	return fifo.count;
}

fn void? Fifo.sort(&fifo)
{
	Type[] arr = mem::new_array(Type, fifo.count);
	defer mem::free(arr);

	foreach(i, c: fifo) {
		arr[i] = c;
	}

	// doesn't keep ordering
	//sort::quicksort(arr);

	// seems to keep the right order but we will never know...
	// also since most things are already ordered the time is closer to O(n) than to O(n^2)
	sort::insertionsort(arr);

	fifo.count = 0;
	fifo.out = 0;
	foreach (&c: arr) {
		fifo.enqueue(c)!;
	}
}