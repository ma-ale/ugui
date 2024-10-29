module fifo(<Type>);

import std::core::mem;

fault FifoErr {
	FULL,
	EMPTY,
}

// TODO: specify the allocator

struct Fifo {
	Type[] arr;
	usz out;
	usz count;
}

fn void! Fifo.init(&fifo, usz size)
{
	fifo.arr = mem::new_array(Type, size);
	fifo.out = 0;
	fifo.count = 0;
}

fn void Fifo.free(&fifo)
{
	(void)mem::free(fifo.arr);
}

fn void! Fifo.enqueue(&fifo, Type *elem)
{
	if (fifo.count >= fifo.arr.len) {
		return FifoErr.FULL?;
	}
	usz in = (fifo.out + fifo.count) % fifo.arr.len;
	fifo.arr[in] = *elem;
	fifo.count++;
}

fn Type*! Fifo.dequeue(&fifo)
{
	if (fifo.count == 0) {
		return FifoErr.EMPTY?;
	}
	Type *ret = &fifo.arr[fifo.out];
	fifo.count--;
	fifo.out = (fifo.out + 1) % fifo.arr.len;
	return ret;
}
