import std::io;

alias Id = uint;

fn void foo_ex(Id id)
{
	io::printfn("id = %d", id);
}


macro Id @compute_id(...)
{
	Id id = (Id)$$LINE.hash() ^ (Id)@str_hash($$FILE);
	$for var $i = 0; $i < $vacount; $i++:
		id ^= (Id)$vaconst[$i].hash();
	$endfor
	return id;
}

macro foo(...) => foo_ex(@compute_id($vasplat));

fn int main()
{
	foo_ex(1234);
	foo();
	foo();
	foo();

	return 0;
}