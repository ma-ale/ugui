bitstruct Bits : uint {
	bool a : 0;
	bool b : 1;
	bool c : 2;
}

fn int main()
{
	Bits a = {false, true, false};
	Bits b = {true, true, false};
	Bits c = a | b;

	return 0;
}
