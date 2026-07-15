module main;
import std::io;
import raylib6::rl;
import std::math;
import std::core::mem::allocators;
import onyx;
import file_watcher;
import main::player;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
const int SPEED = 7;
Config config;
Core core;
ConfigEngine ce;
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct Core 
{
	Entity*        player;
	FileWatcher*   fw;
	ConfigEngine*  ce;
	Config*        config;
	RLVector2      window_size;
	float          delta;
}
struct Config
{
	ZString window_title;
	int x;
	int y;
	float temp;
}

fn void on_file_created(ZString path, void* user_data)
{
    io::printfn("--> СТВОРЕНО: %s", path);
}

fn void on_file_deleted(ZString path, void* user_data)
{
    io::printfn("--> ВИДАЛЕНО: %s", path);
}

fn void on_file_modified(ZString path, void* user_data)
{
    io::printfn("--> ЗМІНЕНО: %s", path);
	main::reload_config();
}



fn void init_game()
{
	rl::set_config_flags(VSYNC_HINT);
	rl::set_config_flags(WINDOW_RESIZABLE);
	rl::set_config_flags(WINDOW_RESIZABLE);
	rl::set_config_flags(WINDOW_HIGHDPI);
	rl::set_target_fps(60);
	rl::init_window(800, 600, core.config.window_title);
	rl::set_exit_key(NONE);
}

fn void load_config()
{
	
	onyx::ce_init(&ce);
	core.ce = &ce;
	
	char[]? config_data =  file::load_temp("configs/config.onx");
	onyx::ce_parse(&ce, (String)config_data)!!;

	core.config.window_title = (ZString)onyx::ce_get_string_def(core.ce,"config.window.window_title", "Default");
	core.player.camera.zoom = (float)onyx::ce_get_float_def(core.ce,"config.player.zoom", 0.10);

}

fn void reload_config()
{
	//onyx::ce_free(core.ce);
	char[]? config_data =  file::load(tmem, "configs/config.onx");
	onyx::ce_parse(core.ce, (String)config_data)!!;
	core.player.camera.zoom = (float)onyx::ce_get_float_def(core.ce,"config.player.zoom", 0.10);

	core.config.window_title = (ZString)onyx::ce_get_string_def(core.ce,"config.window.window_title", "Default");
	rl::set_window_title((ZString)core.config.window_title);
}

fn int main(String[] args)
{	
	core.config = &config;

	String path = rl::get_working_directory().str_view();
	String config_path = string::format(tmem,"%s/configs", path);
	

	BackedArenaAllocator* arena = allocators::new_backed_allocator(131072, mem)!!;
    FileWatcher fw;

    if (!file_watcher::fw_init(&fw, arena, "configs/", 20))
    {
        io::printn("Помилка ініціалізації.");
        return 1;
    }
	file_watcher::fw_set_callbacks(&fw, &on_file_created, &on_file_deleted, &on_file_modified, null);
    
    io::printn("Моніторинг запущено...");

	
	main::init_game();
	
	Entity player = player::init();
	core.player = &player;
	main::load_config();

	assets::get_assets(&player);
	//assets::get_assets();
	while (!rl::window_should_close())
	{
		float delta = rl::get_frame_time();
		RLVector2  window_size = {rl::get_render_width(),rl::get_render_height()};
		core.delta = delta;
		core.window_size = window_size;

		file_watcher::fw_poll(&fw);
		
		player.update(delta);
		
		rl::begin_drawing();
		rl::clear_background(rl::RAYWHITE);

		rl::begin_mode2d(player.camera);

			rl::draw_rectangle(0,0, 100*10, 200*3,rl::BLUE);
			player.draw();
		
		rl::end_mode2d();
		rl::draw_fps(0, 0);
		char* pos_text = rl::text_format("X: %.1f, Y: %.1f", player.pos.x, player.pos.y);
		rl::draw_text((ZString)pos_text, 80, 0, 20, rl::BLACK);

		rl::end_drawing();
	}
	defer onyx::ce_free(core.ce);
	defer file_watcher::fw_destroy(&fw);
	defer rl::close_window();
	return 0;
}
