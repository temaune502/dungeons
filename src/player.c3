module main::player;
import raylib6::rl;
import std::math;

enum EntityType
{
	PLAYER,
	ENEMY
}
enum AnimationState
{
	IDLE,
	WALKING
}
struct Entity 
{	
	EntityType type;
	RLVector2 pos;
	RLVector2 d;
	RLCamera2D camera;
	RLTexture2D texture;
	int current_frame;
	int frames_count;
	int speed;
	Direction direction;
	AnimationState animation_state;
	bool is_active;
	float frame_timer;
	float animation_speed;
	int animation_padding;

}

fn Entity init()
{
	RLCamera2D camera;
	camera.target = {0.0,0.0};

	Entity player;
	player.type = PLAYER;
	player.pos = {100,100};
	player.camera = camera;
	player.camera.target = player.pos;
	player.camera.zoom = 0.9;
	player.speed= main::SPEED;
	player.animation_speed = 1.9;
	player.current_frame = 0;
	player.animation_state = IDLE;
	player.is_active = true;

	return player;
}


fn void Entity.update(Entity* self, float delta)
{ 
    // Перевірка на активність гравця
    if (self.type != EntityType.PLAYER || !self.is_active) {
        return;
    }

    // 1. Збір вводу (використовуємо 1.0 як базовий одиничний крок)
    float dx = 0.0;
    float dy = 0.0;

    if (rl::is_key_down(D)) { dx += 1.0; self.direction = RIGHT; }
    if (rl::is_key_down(A)) { dx -= 1.0; self.direction = LEFT;  }
    if (rl::is_key_down(W)) { dy -= 1.0; self.direction = UP;    }
    if (rl::is_key_down(S)) { dy += 1.0; self.direction = DOWN;  }

    // Логіка скидання
    if (rl::is_key_down(R)) {
        self.pos = {0.0, 0.0};
        main::core.config.temp = 0.0;
    }

    // 2. Нормалізація та застосування швидкості
    if (dx != 0.0 || dy != 0.0) {
        // Рахуємо довжину вектора (без урахування часу)
        float length = (float)math::sqrt((float)(dx * dx + dy * dy));
        self.animation_state = WALKING;
        // Нормалізуємо (отримуємо вектор довжиною 1.0)
        dx /= length;
        dy /= length;

        // Тепер множимо на швидкість та час (delta)
        dx *= self.speed * delta;
        dy *= self.speed * delta;
	} 
	else {
		self.animation_state = IDLE;
		self.current_frame = 0;
	}

    self.pos.x += dx;
    self.pos.y += dy;

    self.camera.target = self.pos;
    self.camera.offset = {
        (float)main::core.window_size.x / 2.0, 
        (float)main::core.window_size.y / 2.0
    };
}