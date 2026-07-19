module main::gui;
import std::io;
import raylib6::rl;

enum ButtonState {
    NORMAL,
    HOVERED,
    PRESSED
}

// Нова структура для кастомізації кольорів кнопки
struct ButtonStyle {
    RLColor normal;
    RLColor hover;
    RLColor pressed;
    RLColor text;
}

fn bool do_button(RLRectangle rec, ZString title, int font_size, ButtonStyle style)
{
    RLRectangle bounds = {
        .x = rec.x - (rec.width / 2.0),
        .y = rec.y - (rec.height / 2.0),
        .width = rec.width,
        .height = rec.height
    };

    RLVector2 mouse_pos = rl::get_mouse_position();

    ButtonState state = NORMAL;
    bool is_clicked = false;

    if (rl::check_collision_point_rec(mouse_pos, bounds)) 
    {
        state = HOVERED;

        if (rl::is_mouse_button_down(LEFT)) 
        {
            state = PRESSED;
        }

        if (rl::is_mouse_button_released(LEFT)) 
        {
            is_clicked = true;
        }
    }

    // 1. Динамічно обираємо колір із переданої структури стилю
    RLColor btn_color = style.normal;    
    if (state == HOVERED) {
        btn_color = style.hover;     
    } else if (state == PRESSED) {
        btn_color = style.pressed;      
    }

    // Малюємо фон кнопки
    rl::draw_rectangle((int)bounds.x, (int)bounds.y, (int)bounds.width, (int)bounds.height, btn_color);

    // 2. Малюємо текст, використовуючи колір із налаштувань стилю
    int text_width = rl::measure_text(title, font_size);
    int text_x = (int)(rec.x - (text_width / 2.0));
    int text_y = (int)(rec.y - (font_size / 2.0)); 
    rl::draw_text(title, text_x, text_y, font_size, style.text);

    return is_clicked;
}