module main::player;
import raylib6::rl;
import std::math;

enum EntityType
{
	PLAYER,
	ENEMY
}

struct Entity 
{	
	EntityType type;
	RLVector2 pos;
	RLVector2 d;
	RLCamera2D camera;
	RLTexture2D texture;
	bool is_active;
	int speed;

}

fn Entity init()
{
	RLCamera2D camera;
	camera.target = {0.0,0.0};

	Entity player;
	player.type = PLAYER;
	player.pos = {(float)rl::get_render_width()/2, (float)rl::get_render_height()/2};
	player.camera = camera;
	player.camera.target = player.pos;
	player.camera.zoom = 0.9;
	player.speed= main::SPEED;
	player.camera.offset = {(float)rl::get_render_width()/2, (float)rl::get_render_height()/2};

	player.is_active = true;

	return player;
}


fn void Entity.update (Entity* self, float delta)
{	
	if (self.type == EntityType.PLAYER) {
		if (self.is_active){
			float dx = 0.0;
        	float dy = 0.0;


			if (rl::is_key_down(D))
			{
				dx += (100.0*main::SPEED*delta);
			} 
			if (rl::is_key_down(A))
			{
				dx -= (100.0*main::SPEED*delta);
			}
			if (rl::is_key_down(W))
			{
				dy -= (100.0*main::SPEED*delta);
			}
			if (rl::is_key_down(S))
			{
				dy += (100.0*main::SPEED*delta);
			}
			if (rl::is_key_down(R))
			{
				self.pos = {0.0,0.0};
				main::core.config.temp = 0.0;
			};

			if (dx != 0.0 || dy != 0.0) {
            // Рахуємо довжину вектора
            float length = (float)math::sqrt((double)(dx * dx + dy * dy));
            
            // Робимо довжину рівною 1 і множимо на швидкість гравця
            dx = (dx / length) * self.speed;
            dy = (dy / length) * self.speed;
        	}
			self.pos.x += dx;
        	self.pos.y += dy;
			self.camera.target = self.pos;
		}
	}
}
