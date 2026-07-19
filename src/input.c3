module main::input;
import raylib6::rl;

fn void handle_keys()
{
    // Обробка для стану GAME
    if (main::core.state == GAME) 
    {
        if (rl::is_key_pressed(ESCAPE)) { main::core.state = ESCAPE_MENU; return; }
        if (rl::is_key_pressed(E))      { main::core.state = MAIN_MENU;   return; }
    }
    
    // Обробка для стану ESCAPE_MENU
    else if (main::core.state == ESCAPE_MENU) 
    {
        if (rl::is_key_pressed(ESCAPE)) { main::core.state = GAME; return; }
    }
    
    // Обробка для стану MAIN_MENU
    else if (main::core.state == MAIN_MENU) 
    {
        if (rl::is_key_pressed(E))      { main::core.state = GAME; return; }
    }
    
}