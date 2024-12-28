import std::io;

struct Color { short r,g,b,a; }

macro Color uint.to_rgba(uint u)
{
	return Color{
		.r = (char)((u >> 24) & 0xff),
		.g = (char)((u >> 16) & 0xff),
		.b = (char)((u >> 8) & 0xff),
		.a = (char)((u >> 0) & 0xff)
	};
}

fn void main(String[] args)
{
	uint col = args[1].to_uint()!!;
	io::printn(col.to_rgba());
}
