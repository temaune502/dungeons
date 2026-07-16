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
				self.animation_padding = 63;
			case LEFT:
				self.animation_padding = 96;
		}
		if (self.frames_count >= (main::core.current_fps/self.animation_speed))
		{
			self.frames_count = 0;
			self.current_frame++;
			if (self.current_frame > 3) self.current_frame = 0;
		}
	}
    // Малюємо
	//rl::draw_rectangle_rec(source_rec, rl::BLACK);
	rl::draw_rectangle_lines_ex(
								(RLRectangle){
									.x = self.pos.x,
									.y = self.pos.y,
									.width = source_rec.width,
									.height = source_rec.height,
								}, 1.4, rl::ORANGE);
    rl::draw_texture_rec(self.texture, source_rec, self.pos, rl::WHITE);

}