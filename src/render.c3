module main::render;
import main::player;
import raylib6::rl;

fn void Entity.draw(Entity* self)
{

    // Формуємо Rectangle максимально явно
    RLRectangle source_rec;
    source_rec.x = (float)self.current_frame*(float)self.texture.width/4;
    source_rec.y = 0;
    source_rec.width = (float)self.texture.width/4;
    source_rec.height = 32;
	switch (self.direction)
	{
		case DOWN:

			source_rec.y = 0;

		case RIGHT:

			source_rec.y = 32;
		
		case UP:

			source_rec.y = 64;
			
		case LEFT:
			source_rec.y = 85;
	}
	if (self.frames_count >= (60/self.animation_speed))
    {
		self.frames_count = 0;
		self.current_frame++;
		
		if (self.current_frame > 3) self.current_frame = 0;
    }
    // Малюємо
	rl::draw_rectangle_rec(source_rec, rl::BLACK);
    rl::draw_texture_rec(self.texture, source_rec, self.pos, rl::WHITE);

}