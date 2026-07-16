module main::assets;
import raylib6::rl;
import std::io;
import main::player;

struct Assets
{
	RLTexture2D player_atlas;
	RLTexture2D background;
}

fn void get_assets() 
{
	main::core.assets.player_atlas = rl::load_texture("assets/player/character.png");
	main::core.assets.player_atlas.set_filter(ANISOTROPIC_16X);
	main::core.player.texture = main::core.assets.player_atlas;

}