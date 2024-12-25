import rl;
import std::io;

fn int main(String[] args)
{
	short width = 800;
	short height = 450;
	rl::set_config_flags(rl::FLAG_WINDOW_RESIZABLE);
	rl::init_window(width, height, "Ugui Test");
	rl::set_target_fps(60);
	rl::enable_event_waiting();

	// Main loop
	KeyboardKey k;
	while (!rl::window_should_close()) {
		do {
			k = rl::get_char_pressed();
			io::printfn("%s", k);
		} while (k != 0);
	}

	rl::close_window();

	return 0;
}

