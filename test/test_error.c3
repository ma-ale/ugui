import std::io;

struct FaultStack {
	usz elem;
	anyfault[16] v;
}

fn void FaultStack.push(&fs, anyfault f)
{
	if (fs.elem < fs.v.len) {
		fs.v[fs.elem++] = f;
	}
}

fn anyfault FaultStack.pop(&fs)
{
	return fs.elem > 0 ? fs.v[fs.elem-- - 1] : anyfault{};
}

FaultStack fs;

fn int! err1()
{
	return IoError.OUT_OF_SPACE?;
}

fn void! err2()
{
	return IoError.EOF?;
}

/*
macro @unwrap(#f)
{
	$if ($typeof(#f).typeid == void!.typeid) {
		if (catch err = #f) { fs.push(err); }
		return;
	} $else {
		$typeof(#f) x = #f;
		if (catch err = x) {
			fs.push(err);
			return $typeof(#f!!){};
		} else {return x;}
	}
}
*/

<*
@require @typekind(#func) == OPTIONAL : `@unwrap requires an optional value`
*>
macro @unwrap(#func)
{
	anyfault exc = @catch(#func);
	if (exc != anyfault{}) {
		fs.push(exc);
		$if $typeof(#func!!).typeid != void.typeid:
			return $typeof(#func!!){};
		$else
			return;
		$endif
	} else {
		return #func!!;
	}
}

fn void main()
{
	@unwrap(err1());
	@unwrap(err2());

	io::printfn("%s", fs.v);
}
