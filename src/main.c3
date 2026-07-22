module main;
import std::io;
import raylib6::rl;
import std::math;
import std::core::mem::allocators;
import onyx;
import file_watcher;
import main::player;
import std::core::string;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
const int SPEED = 90;
Assets assets;
Config config;
Core core;
ConfigEngine ce;
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
enum Direction
{
	UP,
	DOWN,
	LEFT,
	RIGHT,
}

struct Core 
{
	Entity*        player;
	Assets*        assets;
	FileWatcher*   fw;
	ConfigEngine*  ce;
	Config*        config;
	RLVector2      window_size;
	RLVector2      half_window;
	UIState 	   state;
	int            current_fps;
	int            frame_counter;
	int            current_frame;
	int            frame_speed;
	float          delta;
}
struct Config
{
	ZString window_title;
	int     x;
	int     y;
}
enum UIState
{
	MAIN_MENU,
	ESCAPE_MENU,
	OPTIONS_MENU,
	GAME
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
	rl::set_config_flags(MSAA_4X_HINT);
	rl::set_config_flags(WINDOW_HIGHDPI);
	rl::set_target_fps((int)onyx::ce_get_int_def(core.ce,"config.fps", 32));
	rl::init_window(800, 600, core.config.window_title);
	rl::set_exit_key(NONE);
}

fn void load_config()
{
	
	onyx::ce_init(&ce);
	core.ce = &ce;
	//TODO: виявляється якщо <type>? можна задати значення заумовчання через ??
	//char[] config_data =  file::load_temp("configs/config.onx") ?? "Cringe";
	//onyx::ce_parse(&ce, (String)config_data);
	onyx::ce_parse_file(&ce, "configs/config.onx");
	core.config.window_title = onyx::ce_get_string_def(core.ce,"config.window.window_title", "Default");
	core.player.camera.zoom = (float)onyx::ce_get_float_def(core.ce,"config.player.zoom", 0.10);
	core.player.animation_speed = (float)onyx::ce_get_float_def(core.ce,"config.player.animation_speed", 0.10);

}

fn void reload_config()
{
	//onyx::ce_free(core.ce);
	char[]? config_data =  file::load(tmem, "configs/config.onx");
	onyx::ce_parse(core.ce, (String)config_data)!!;
	core.player.camera.zoom = (float)onyx::ce_get_float_def(core.ce,"config.player.zoom", 0.10);
	rl::set_target_fps((int)onyx::ce_get_int_def(core.ce,"config.fps", 32));

	core.config.window_title = (ZString)onyx::ce_get_string_def(core.ce,"config.window.window_title", "Default");
	rl::set_window_title((ZString)core.config.window_title);

	core.player.animation_speed = (float)onyx::ce_get_float_def(core.ce,"config.player.animation_speed", 0.10);
}

ButtonStyle standart_style = {
    .normal  = rl::GRAY,
    .hover   = rl::LIGHTGRAY,
    .pressed = rl::DARKGRAY,
    .text    = rl::WHITE
};
ButtonStyle danger_style = {
    .normal  = (RLColor){ 180, 40, 40, 255 },  
    .hover   = (RLColor){ 220, 50, 50, 255 },  
    .pressed = (RLColor){ 120, 20, 20, 255 },
    .text    = rl::RAYWHITE
};

fn int main(String[] args)
{	
	core.assets = &assets;
	core.config = &config;
	core.state = MAIN_MENU;
	io::printfn("%s",args);
	String path = rl::get_working_directory().str_view();
	String config_path = string::format(tmem,"%s/configs", path);
	

	DynamicArenaAllocator arena = {};
	arena.init(mem, 8192/2);
    FileWatcher fw;

    if (!file_watcher::fw_init(&fw, &arena, "configs/", 20))
    {
        io::printn("Помилка ініціалізації.");
        return 1;
    }
	file_watcher::fw_set_callbacks(&fw, &on_file_created, &on_file_deleted, &on_file_modified, null);
    
    io::printn("Моніторинг запущено...");

	
	Entity player = player::init();
	core.player = &player;
	main::load_config();
	main::init_game();
	
	assets::load_basick_assets();
	RLVector2  window_size = {rl::get_render_width(),rl::get_render_height()};
	RLVector2 half_window = {
		(float)window_size.x / 2.0, 
		(float)window_size.y / 2.0
	};
	core.window_size = window_size;
	core.half_window = half_window;

	
	while (!rl::window_should_close())
	{
		float delta = rl::get_frame_time();
		core.current_fps = rl::get_fps();
		core.delta = delta;
		if (core.state == MAIN_MENU || core.state == ESCAPE_MENU || core.state == OPTIONS_MENU) { core.player.is_active = false;}
		else {core.player.is_active = true;}
		
		input::handle_keys();


		window_size = {rl::get_render_width(),rl::get_render_height()};
		half_window = {
		(float)core.window_size.x / 2.0, 
		(float)core.window_size.y / 2.0
		};
		core.window_size = window_size;
		core.half_window = half_window;
		
		file_watcher::fw_poll(&fw);
		
		player.update(delta);
		
		rl::begin_drawing();
		rl::clear_background((RLColor)0x121212);
		if (core.state == GAME)
		{
			rl::begin_mode2d(player.camera);

				rl::draw_rectangle(0,0, 100*10, 200*3,rl::BLUE);
				render::draw_background();
				render::draw_player(&player);
			
			rl::end_mode2d();
			char* pos_text = rl::text_format("X: %.1f, Y: %.1f", player.pos.x, player.pos.y);
			rl::draw_text((ZString)pos_text, 80, 0, 20, rl::RED);
		}
		else  if (core.state == MAIN_MENU)
		{
			rl::draw_text((ZString)"Game of my Dream", (int)core.half_window.x-(rl::measure_text((ZString)"Game of my Dream", 22)/2), (int)core.half_window.y-80, 22,rl::WHITE);

			if(gui::do_button((RLRectangle){.x = core.half_window.x,.y = core.half_window.y,.width = 140,.height = 40},"Start Game" , 22, danger_style))
			{
				core.state = GAME;
			}
			if(gui::do_button((RLRectangle){.x = core.half_window.x,.y = core.half_window.y+50,.width = 80,.height = 40},"Exit" , 22, standart_style))
			{
				break;
			}
		} 
		else if (core.state == ESCAPE_MENU)
		{
			RLRectangle rect = {
				.x = (float)onyx::ce_get_float_def(core.ce,"atlas.x", 0.0),
				.y = (float)onyx::ce_get_float_def(core.ce,"atlas.y", 0.0),
				.width = 16,
				.height = 16
			};
			if(gui::do_button((RLRectangle){.x = core.half_window.x,.y = core.half_window.y+50,.width = 80,.height = 40},"Back" , 22, standart_style))
			{
				core.state = GAME;
			}
			// if(gui::do_button((RLRectangle){.x = core.half_window.x,.y = core.half_window.y+80,.width = 80,.height = 40},"Change config" , 22, standart_style))
			// {
			// 	Node* new_val = onyx::create_node(core.ce.allocator, NodeType.INT);
			// 	new_val.data.int_val = 8080;
			// 	new_val.state = EvalState.RESOLVED;

			// 	onyx::ce_set_path(core.ce, "config.fps", new_val);

			// 	bool success = onyx::ce_save_node_smart(core.ce, "config.fps", "configs/config.onx");
			// 	if (success) {
			// 		io::printn("Конфіг успішно оновлено у файлі!");
			// 	} else {
			// 		io::printn("Помилка: неможливо зберегти (можливо це був вираз?)");
			// 	}
			// }

			//render::draw_tiled_region(main::core.assets.background, rect, (RLVector2){0,0}, core.window_size.x, core.window_size.y);

			rl::draw_text((ZString)"Game paused!", (int)core.half_window.x-(rl::measure_text((ZString)"Game of my Dream", 22)/2), (int)core.half_window.y-120, 22,rl::WHITE);
		}
		rl::draw_fps(0, 0);
		rl::end_drawing();
		player.frames_count++;
	}
	defer onyx::ce_free(core.ce);
	defer file_watcher::fw_destroy(&fw);
	defer assets::unload_assets();
	defer rl::close_window();
	return 0;
}
