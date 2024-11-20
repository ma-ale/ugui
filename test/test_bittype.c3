import std::io;
import std::collections::bitset;

def Bits = bitset::BitSet(<128>);

fn void main()
{
    Bits b;
	io::printn($typeof(b.data[0]).sizeof);
}
