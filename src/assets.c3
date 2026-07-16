module main::assets;
import raylib6::rl;
import std::io;
import main::player;

struct Assets
{
	RLTexture2D player_atlas;
	RLTexture2D background;
}

fn void load_basick_assets() 
{
	// Player texture atlas
	main::core.assets.player_atlas = rl::load_texture("assets/player/character.png");
	main::core.assets.player_atlas.set_filter(ANISOTROPIC_16X);
	main::core.player.texture = main::core.assets.player_atlas;


	//World texture atlas
	main::core.assets.background = rl::load_texture("assets/Overworld.png");
	main::core.assets.background.set_filter(ANISOTROPIC_16X);
	rl::gen_texture_mipmaps(&main::core.assets.background);

}

fn void unload_assets()
{
	rl::unload_texture(main::core.assets.player_atlas);
	rl::unload_texture(main::core.assets.background);
}