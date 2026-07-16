module main::render;
import main::player;
import raylib6::rl;

fn void Entity.draw(Entity* self)
{
    // Формуємо Rectangle максимально явно
    RLRectangle source_rec;
    source_rec.x = (float)self.current_frame*(float)self.texture.width/4;
    source_rec.y = self.animation_padding;
    source_rec.width = (float)self.texture.width/4;
    source_rec.height = 20;
	if (self.animation_state == WALKING)
	{
		switch (self.direction)
		{
			case DOWN:
				self.animation_padding = 0;
			case RIGHT:
				self.animation_padding = 32;
			case UP:
				self.animation_padding = 64;
			case LEFT:
				self.animation_padding = 96;
		}
		if (self.frames_count >= (60/self.animation_speed))
		{
			self.frames_count = 0;
			self.current_frame++;
			if (self.current_frame > 3) self.current_frame = 0;
		}
	}
    // Малюємо
	rl::draw_rectangle_rec(source_rec, rl::BLACK);
    rl::draw_texture_rec(self.texture, source_rec, self.pos, rl::WHITE);

}