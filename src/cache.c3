module cache(<Key, Value, SIZE>);

/* LRU Cache
 * The cache uses a pool (array) to store all the elements, each element has
 * a key (id) and a value. A HashMap correlates the ids to an index in the pool.
 * To keep track of which items were recently used two bit arrays are kept, one
 * stores the "used" flag for each index and anothe the "present" flag.
 * Every NCYCLES operations the present and used arrays are updated to free up
 * the elements that were not recently used.
 */

// FIXME: this module should really allocate all resources on an arena or temp
//        allocator, since all memory allocations are connected and freeing
//        happens at the same time

import std::core::mem;
import std::collections::bitset;
import std::collections::map;

def BitArr = bitset::BitSet(<SIZE>) @private;
def IdTable = map::Map(<Key, usz>) @private;
def IdTableEntry = map::Entry(<Key, usz>) @private;

const usz CACHE_NCYCLES = (usz)(SIZE * 2.0/3.0);

struct Cache {
    BitArr present, used;
    IdTable table;
    Value[] pool;
    usz cycle_count;
}

// Every CACHE_CYCLES operations mark as not-present the unused elements
macro Cache.cycle(&cache) @private {
    cache.cycle_count++;
	if (cache.cycle_count > CACHE_NCYCLES) {
		for (usz i = 0; i < cache.present.data.len; i++) {
			cache.present.data[i] &= cache.used.data[i];
			cache.used.data[i] = 0;
		}
		cache.cycle_count = 0;
	}
}

fn void! Cache.init(&cache)
{
    cache.table = map::new(<Key, usz>)(SIZE);
    // FIXME: this shit is SLOW
    foreach (idx, bit : cache.used) { cache.used[idx] = false; }
    foreach (idx, bit : cache.present) { cache.present[idx] = false; }
    cache.pool = mem::new_array(Value, SIZE);
}

fn void Cache.free(&cache)
{
    (void)cache.table.free();
    (void)mem::free(cache.pool);
}

fn Value*! Cache.search(&cache, Key id)
{
    // get_entry() faults on miss
	IdTableEntry* entry = cache.table.get_entry(id)!;

	/* MISS */
	if (entry.key != id) {
	   return SearchResult.MISSING?;
	}

	/* MISS, the data is not valid (not present) */
	if (!cache.present[entry.value]) {
	    // if the data is not present but it is still in the table, remove it
		cache.table.remove(id)!;
		return SearchResult.MISSING?;
	}

	/* HIT, set as recently used */
	cache.used[entry.value] = true;
	return &(cache.pool[entry.value]);
}

/* Look for a free spot in the present bitmap and return its index */
/* If there is no free space left then just return the first position */
fn usz Cache.get_free_spot(&cache) @private
{
    // FIXME: This shit is SLOW, especially when clz() exists
	foreach (idx, bit: cache.present) {
		if (bit == false) {
			return idx;
		}
	}
	return 0;
}

fn Value*! Cache.insert_at(&cache, Value *g, Key id, usz index) @private
{
    // TODO: verify index, g and id
	Value* spot;

	/* Set used and present */
	cache.present.set(index);
	cache.used.set(index);
	cache.cycle();

	spot = &(cache.pool[index]);
	*spot = *g;
	cache.table.set(id, index);
	return spot;
}

// Insert an element in the cache, returns the index
fn Value*! Cache.insert_new(&cache, Value* g, Key id)
{
	usz index = cache.get_free_spot();
	return cache.insert_at(g, id, index);
}

fn Value*! Cache.get_or_insert(&cache, Value* g, Key id, bool *is_new = null)
{
    Value*! c = cache.search(id);
    if (catch e = c) {
        if (e != SearchResult.MISSING) {
            return e?;
        } else {
        	// if the element is new (inserted) set the is_new flag
         	if (is_new) *is_new = true;
        	return cache.insert_new(g, id);
        }
    } else {
    	if (is_new) *is_new = false;
        return c;
    }
}
