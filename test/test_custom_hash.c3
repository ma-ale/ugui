import std::collections::map;

def Codepoint = uint;
fn uint Codepoint.hash(Codepoint code) => code < 128 ? code : ((uint)code).hash();
def CodeMap = map::HashMap(<Codepoint, Codepoint>);


fn int main()
{
    CodeMap m;
    m.new_init();
    m.free();
    return 0;
}
