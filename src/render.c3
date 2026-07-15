module main::render;
import main::player;
import raylib6::rl;

fn void Entity.draw(Entity* self)
{
    // Розрахунок через float
    float f_width = (float)self.texture.width;

	

    float ry = 0.0; // Тут можна додати логіку рядків (наприклад, ry = 32.0 для 2-го рядка)

    // Формуємо Rectangle максимально явно
    RLRectangle source_rec;
    source_rec.x = (float)self.current_frame*(float)self.texture.width/4;
    source_rec.y = ry;
    source_rec.width = f_width/4;
    source_rec.height = 32;
	if (self.frames_count >= (60/self.animation_speed))
    {
		self.frames_count = 0;
		self.current_frame++;
		
		if (self.current_frame > 3) self.current_frame = 0;

		source_rec.x = (float)self.current_frame*(float)self.texture.width/4;
    }
    // Малюємо
	//rl::draw_rectangle_rec(source_rec, rl::BLACK);
    rl::draw_texture_rec(self.texture, source_rec, self.pos, rl::WHITE);

}