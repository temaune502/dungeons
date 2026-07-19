module main::render;
import main::player;
import raylib6::rl;
import std::math;

fn void draw_tiled_region(RLTexture2D texture, RLRectangle tile_src, RLVector2 start_pos, float target_width, float target_height)
{
    // Округлюємо стартову позицію, щоб вона не мала дробів (наприклад, 10.75 стане 10.0)
    float start_x = (float)math::floor((double)start_pos.x);
    float start_y = (float)math::floor((double)start_pos.y);

    for (float y = 0.0; y < target_height; y += tile_src.height)
    {
        for (float x = 0.0; x < target_width; x += tile_src.width)
        {
            float current_w = tile_src.width;
            if (x + current_w > target_width) current_w = target_width - x;

            float current_h = tile_src.height;
            if (y + current_h > target_height) current_h = target_height - y;

            RLRectangle source_rec = {
                .x = tile_src.x,
                .y = tile_src.y,
                // Для розмірів теж краще відкидати дробову частину
                .width = (float)math::floor((double)current_w),
                .height = (float)math::floor((double)current_h)
            };

            // ФІНАЛЬНА ПОЗИЦІЯ ЖОРСТКО ПРИВ'ЯЗАНА ДО ПІКСЕЛІВ
            RLVector2 position = {
                .x = start_x + (float)math::floor((double)x),
                .y = start_y + (float)math::floor((double)y)
            };

            rl::draw_texture_rec(texture, source_rec, position, rl::WHITE);
        }
    }
}

fn void  draw_background()
{
	// RLRectangle rect = {
	// 	.x = 0,
	// 	.y =0,
	// 	.width = 32,
	// 	.height = 16
	// };
	// RLVector2 pos = {0,0};
	// rl::draw_texture_rec(main::core.assets.background, rect ,pos, rl::WHITE);


	RLRectangle rect = {
		.x = 0,
		.y =0,
		.width = 16,
		.height = 16
	};

	RLRectangle dest = {
		.x = 0,
		.y =0,
		.width = 128*10,
		.height = 128*10
	};

	// rl::draw_texture_pro(main::core.assets.background,
	// 					 rect, 
	// 					 dest, 
	// 					 (RLVector2){0,0}, 
	// 					 2.9, 
	// 					 rl::WHITE);


	render::draw_tiled_region(main::core.assets.background, rect, (RLVector2){0,0}, 16*32, 32*32);


}

fn void draw_player(Entity* self)
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
	// rl::draw_rectangle_lines_ex(
	// 							(RLRectangle){
	// 								.x = self.pos.x,
	// 								.y = self.pos.y,
	// 								.width = source_rec.width,
	// 								.height = source_rec.height,
	// 							}, 1.4, rl::ORANGE);
    rl::draw_texture_rec(self.texture, source_rec, self.pos, rl::WHITE);

}