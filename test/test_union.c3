
struct CmdA {
	int a, b;
}

struct CmdB {
	float a, b;
}

union AnyCmd {
	CmdA a;
	CmdB b;
}

struct Cmd {
	int type;
	AnyCmd cmd;
}

fn int main()
{
	Cmd c;
	c.type = 1;
	c.cmd.a = {.a = 1, .b = 2};
	return 0;
}
