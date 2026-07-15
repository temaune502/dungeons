module main::render;
import main::player;
import raylib6::rl;

fn void Entity.draw(Entity* self)
{

	RLRectangle source_rec = {
		.x = 0+main::core.config.temp, 
		.y = 0,  
		.width = 18, 
		.height = 32
		};

	rl::draw_texture_rec(self.texture, source_rec, self.pos, rl::WHITE);
	if (main::core.config.temp <= 128) 
	{
		main::core.config.temp += 8/main::core.delta;
	}
	else {
		main::core.config.temp = 0.0;
	}
}