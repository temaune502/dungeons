module main::assets;
import raylib6::rl;
import std::io;
import main::player;

fn void get_assets(Entity* entity) 
{
	entity.texture = rl::load_texture("assets/player/character.png");
}