module onyx;

import std::core::mem;
import std::core::mem::alloc;
import std::core::mem::allocators;
import std::io;
import std::core::string;
import libc;
//
// Onyx Configuration Format 
//
// ==========================================
// 1. ТИПИ ДАНИХ ТА СТРУКТУРИ
// ==========================================

enum NodeType : uint {
    INT,
    FLOAT,
    STRING,    // Новий тип для рядкових літералів
    OBJECT,
    REFERENCE,
    MATH_EXPR
}

enum EvalState : uint {
    UNTOUCHED,
    EVALUATING,
    RESOLVED
}

struct KeyValuePair {
    String key;
    Node* value;
}

struct NodeObj {
    KeyValuePair* fields;
    sz count;
    sz capacity;
}

struct NodeMath {
    Node* left;
    Node* right;
    char op;
}

union NodeData {
    long int_val;
    double float_val;
    String string_val; // Поле для збереження значень рядків
    NodeObj obj;
    String ref_path;
    NodeMath math;
}

struct Node {
    NodeType type;
    EvalState state;
    NodeData data;
}

struct ConfigEngine {
    allocators::BackedArenaAllocator arena; // Арена, що базується на mem
    Allocator allocator;             // Інтерфейс алокатора арени
    Node* root;
}

// ==========================================
// 2. УТИЛІТИ ДЛЯ ПАМ'ЯТІ ТА РЯДКІВ
// ==========================================

fn String str_slice(String s, sz start, sz len) {
    if (len <= 0) return "";
    return (String)s[start .. start + len - 1];
}

fn String str_dup(Allocator alloc, String src) {
    if (src.len <= 0) return "";
    
    // 1. Виділяємо на 1 байт більше для нуль-термінатора
    char* ptr = (char*)alloc::malloc(alloc, (usz)(src.len + 1));
    
    // 2. Копіюємо сам текст
    mem::copy(ptr, src.ptr, (usz)src.len);
    
    // 3. Явно ставимо нуль в кінці! Це "відріже" будь-яке сміття від попередніх конфігів
    ptr[src.len] = '\0';
    
    // Повертаємо слайс (твій синтаксис залишаємо без змін)
    return (String)ptr[0 .. src.len - 1];
}

fn String join_path(Allocator alloc, String parent, String child) {
    if (parent.len <= 0) return str_dup(alloc, child);
    
    sz total_len = parent.len + 1 + child.len;
    
    // 1. Виділяємо на 1 байт більше
    char* ptr = (char*)alloc::malloc(alloc, (usz)(total_len + 1));
    
    // 2. Збираємо шлях докупи
    mem::copy(ptr, parent.ptr, (usz)parent.len);
    ptr[parent.len] = '.';
    mem::copy(ptr + parent.len + 1, child.ptr, (usz)child.len);
    
    // 3. Явно ставимо нуль в кінці
    ptr[total_len] = '\0';
    
    return (String)ptr[0 .. total_len - 1];
}

fn Node* create_node(Allocator alloc, NodeType type) {
    Node* node = (Node*)alloc::malloc(alloc, Node::size);
    mem::clear(node, Node::size);
    node.type = type;
    node.state = EvalState.UNTOUCHED;
    return node;
}

// ==========================================
// 3. ЛЕКСЕР (Токенізація)
// ==========================================

enum TokenType {
    EOF, IDENT, INT_LIT, FLOAT_LIT, STRING_LIT, ASSIGN, 
    LBRACE, RBRACE, SEMI, PLUS, MINUS, STAR, SLASH, DOT
}

struct Token {
    TokenType type;
    String text;
    long int_val;
    double float_val;
}

struct Lexer {
    String src;
    sz pos;
    sz len;
}

fn bool is_alpha(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }
fn bool is_digit(char c) { return c >= '0' && c <= '9'; }
fn bool is_alnum(char c) { return is_alpha(c) || is_digit(c); }

fn Token lex_next(Lexer* lex) {
    Token tok = {};

    while (lex.pos < lex.len) {
        char c = lex.src[lex.pos];

        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            lex.pos++;
            continue;
        }

        if (c == '/' && lex.pos + 1 < lex.len && lex.src[lex.pos+1] == '/') {
            while (lex.pos < lex.len && lex.src[lex.pos] != '\n') lex.pos++;
            continue;
        }

        break;
    }

    if (lex.pos >= lex.len) {
        tok.type = TokenType.EOF;
        return tok;
    }

    char c = lex.src[lex.pos];

    if (c == '=') { tok.type = TokenType.ASSIGN; tok.text = str_slice(lex.src, lex.pos, 1); lex.pos++; return tok; }
    if (c == '{') { tok.type = TokenType.LBRACE; tok.text = str_slice(lex.src, lex.pos, 1); lex.pos++; return tok; }
    if (c == '}') { tok.type = TokenType.RBRACE; tok.text = str_slice(lex.src, lex.pos, 1); lex.pos++; return tok; }
    if (c == ';') { tok.type = TokenType.SEMI;   tok.text = str_slice(lex.src, lex.pos, 1); lex.pos++; return tok; }
    if (c == '+') { tok.type = TokenType.PLUS;   tok.text = str_slice(lex.src, lex.pos, 1); lex.pos++; return tok; }
    if (c == '-') { tok.type = TokenType.MINUS;  tok.text = str_slice(lex.src, lex.pos, 1); lex.pos++; return tok; }
    if (c == '*') { tok.type = TokenType.STAR;   tok.text = str_slice(lex.src, lex.pos, 1); lex.pos++; return tok; }
    if (c == '/') { tok.type = TokenType.SLASH;  tok.text = str_slice(lex.src, lex.pos, 1); lex.pos++; return tok; }
    if (c == '.') { tok.type = TokenType.DOT;    tok.text = str_slice(lex.src, lex.pos, 1); lex.pos++; return tok; }

    // Парсинг рядкових літералів у подвійних лапках "..."
    if (c == '"') {
        lex.pos++; // Пропускаємо відкриваючу лапку
        sz start = lex.pos;
        while (lex.pos < lex.len && lex.src[lex.pos] != '"') {
            lex.pos++;
        }
        sz token_len = lex.pos - start;
        tok.text = str_slice(lex.src, start, token_len);
        tok.type = TokenType.STRING_LIT;
        if (lex.pos < lex.len) lex.pos++; // Пропускаємо закриваючу лапку
        return tok;
    }

    if (is_alpha(c)) {
        sz start = lex.pos;
        while (lex.pos < lex.len && is_alnum(lex.src[lex.pos])) lex.pos++;
        tok.text = str_slice(lex.src, start, lex.pos - start);
        tok.type = TokenType.IDENT;
        return tok;
    }

    if (is_digit(c)) {
        sz start = lex.pos;
        bool is_float = false;
        while (lex.pos < lex.len && (is_digit(lex.src[lex.pos]) || lex.src[lex.pos] == '.')) {
            if (lex.src[lex.pos] == '.') is_float = true;
            lex.pos++;
        }
        tok.text = str_slice(lex.src, start, lex.pos - start);

        char[64] temp_buf;
        mem::clear(&temp_buf[0], 64);
        sz copy_len = tok.text.len < 63 ? tok.text.len : 63;
        mem::copy(&temp_buf[0], tok.text.ptr, (usz)copy_len);

        if (is_float) {
            tok.type = TokenType.FLOAT_LIT;
            tok.float_val = libc::strtod(&temp_buf[0], null);
        } else {
            tok.type = TokenType.INT_LIT;
            tok.int_val = libc::strtol(&temp_buf[0], null, 10);
        }
        return tok;
    }

    lex.pos++;
    return lex_next(lex);
}

// ==========================================
// 4. ПАРСЕР (Побудова AST)
// ==========================================

struct Parser {
    Lexer* lex;
    Token curr;
    Allocator alloc;
}

fn void parser_advance(Parser* p) {
    p.curr = lex_next(p.lex);
}

fn bool parser_match(Parser* p, TokenType type) {
    if (p.curr.type == type) {
        parser_advance(p);
        return true;
    }
    return false;
}

fn Node* parse_factor(Parser* p) {
    if (p.curr.type == TokenType.INT_LIT) {
        Node* n = create_node(p.alloc, NodeType.INT);
        n.data.int_val = p.curr.int_val;
        n.state = EvalState.RESOLVED;
        parser_advance(p);
        return n;
    }
    if (p.curr.type == TokenType.FLOAT_LIT) {
        Node* n = create_node(p.alloc, NodeType.FLOAT);
        n.data.float_val = p.curr.float_val;
        n.state = EvalState.RESOLVED;
        parser_advance(p);
        return n;
    }
    if (p.curr.type == TokenType.STRING_LIT) {
        Node* n = create_node(p.alloc, NodeType.STRING);
        n.data.string_val = str_dup(p.alloc, p.curr.text);
        n.state = EvalState.RESOLVED;
        parser_advance(p);
        return n;
    }
    if (p.curr.type == TokenType.LBRACE) {
        parser_advance(p);
        Node* obj = create_node(p.alloc, NodeType.OBJECT);
        obj.data.obj.capacity = 16;
        obj.data.obj.fields = (KeyValuePair*)alloc::malloc(p.alloc, KeyValuePair::size * 16);
        obj.state = EvalState.RESOLVED;

        while (p.curr.type != TokenType.RBRACE && p.curr.type != TokenType.EOF) {
            if (p.curr.type == TokenType.IDENT) {
                String path = str_dup(p.alloc, p.curr.text);
                parser_advance(p);

                while (p.curr.type == TokenType.DOT) {
                    parser_advance(p);
                    if (p.curr.type == TokenType.IDENT) {
                        path = join_path(p.alloc, path, p.curr.text);
                        parser_advance(p);
                    }
                }

                if (parser_match(p, TokenType.ASSIGN)) {
                    Node* val = parse_expr(p);
                    parser_match(p, TokenType.SEMI);

                    bool found = false;
                    for (sz i = 0; i < obj.data.obj.count; i++) {
                        if (obj.data.obj.fields[i].key == path) {
                            obj.data.obj.fields[i].value = val;
                            found = true;
                            // Логування перевизначення в об'єкті
                            io::printfn("[Config Warn] Поле '%s' усередині об'єкта було перевизначено.", path);
                            break;
                        }
                    }
                    if (!found) {
                        obj.data.obj.fields[obj.data.obj.count].key = path;
                        obj.data.obj.fields[obj.data.obj.count].value = val;
                        obj.data.obj.count++;
                    }
                }
            } else {
                parser_advance(p);
            }
        }
        parser_match(p, TokenType.RBRACE);
        return obj;
    }

    if (p.curr.type == TokenType.IDENT) {
        String path = str_dup(p.alloc, p.curr.text);
        parser_advance(p);

        while (p.curr.type == TokenType.DOT) {
            parser_advance(p);
            if (p.curr.type == TokenType.IDENT) {
                path = join_path(p.alloc, path, p.curr.text);
                parser_advance(p);
            }
        }

        Node* n = create_node(p.alloc, NodeType.REFERENCE);
        n.data.ref_path = path;
        return n;
    }

    return null;
}

fn Node* parse_term(Parser* p) {
    Node* left = parse_factor(p);
    while (p.curr.type == TokenType.STAR || p.curr.type == TokenType.SLASH) {
        char op = p.curr.type == TokenType.STAR ? '*' : '/';
        parser_advance(p);
        Node* right = parse_factor(p);

        Node* math_node = create_node(p.alloc, NodeType.MATH_EXPR);
        math_node.data.math.left = left;
        math_node.data.math.right = right;
        math_node.data.math.op = op;
        left = math_node;
    }
    return left;
}

fn Node* parse_expr(Parser* p) {
    Node* left = parse_term(p);
    while (p.curr.type == TokenType.PLUS || p.curr.type == TokenType.MINUS) {
        char op = p.curr.type == TokenType.PLUS ? '+' : '-';
        parser_advance(p);
        Node* right = parse_term(p);

        Node* math_node = create_node(p.alloc, NodeType.MATH_EXPR);
        math_node.data.math.left = left;
        math_node.data.math.right = right;
        math_node.data.math.op = op;
        left = math_node;
    }
    return left;
}

// ==========================================
// 5. ЛІНИВИЙ ОБЧИСЛЮВАЧ 
// ==========================================

fn void ce_set_path(ConfigEngine* ce, String path, Node* val) {
    Node* current = ce.root;
    sz start = 0;

    for (sz i = 0; i <= path.len; i++) {
        if (i == path.len || path[i] == '.') {
            sz token_len = i - start;
            String token = str_slice(path, start, token_len);
            bool is_last = (i == path.len);

            if (is_last) {
                bool found = false;
                for (sz j = 0; j < current.data.obj.count; j++) {
                    if (current.data.obj.fields[j].key == token) {
                        current.data.obj.fields[j].value = val;
                        found = true;
                        // Логування перевизначення глобального шляху
                        io::printfn("[Config Warn] Поле за шляхом '%s' було перевизначено.", path);
                        break;
                    }
                }
                if (!found) {
                    current.data.obj.fields[current.data.obj.count].key = str_dup(ce.allocator, token);
                    current.data.obj.fields[current.data.obj.count].value = val;
                    current.data.obj.count++;
                }
            } else {
                bool found = false;
                for (sz j = 0; j < current.data.obj.count; j++) {
                    if (current.data.obj.fields[j].key == token) {
                        current = current.data.obj.fields[j].value;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    Node* new_obj = create_node(ce.allocator, NodeType.OBJECT);
                    new_obj.data.obj.capacity = 16;
                    new_obj.data.obj.fields = (KeyValuePair*)alloc::malloc(ce.allocator, KeyValuePair::size * 16);
                    new_obj.state = EvalState.RESOLVED;

                    current.data.obj.fields[current.data.obj.count].key = str_dup(ce.allocator, token);
                    current.data.obj.fields[current.data.obj.count].value = new_obj;
                    current.data.obj.count++;
                    current = new_obj;
                }
            }
            start = i + 1;
        }
    }
}

fn Node* ce_resolve_path(ConfigEngine* ce, String path) {
    Node* current = ce.root;
    sz start = 0;

    for (sz i = 0; i <= path.len; i++) {
        if (i == path.len || path[i] == '.') {
            sz token_len = i - start;
            String token = str_slice(path, start, token_len);

            if (current == null || current.type != NodeType.OBJECT) return null;

            bool found = false;
            for (sz j = 0; j < current.data.obj.count; j++) {
                if (current.data.obj.fields[j].key == token) {
                    current = current.data.obj.fields[j].value;
                    found = true;
                    break;
                }
            }
            if (!found) return null;

            start = i + 1;
        }
    }
    return current;
}

fn bool ce_evaluate(ConfigEngine* ce, Node* node) {
    if (node == null) return false;

    if (node.state == EvalState.RESOLVED) return true;
    if (node.state == EvalState.EVALUATING) {
        io::printn("[Config Error] Знайдено круговий референс!");
        return false; 
    }

    node.state = EvalState.EVALUATING;

    switch (node.type) {
        case NodeType.REFERENCE:
            Node* target = ce_resolve_path(ce, node.data.ref_path);
            if (target == null) {
                io::printfn("[Config Error] Не знайдено змінну: %s", node.data.ref_path);
                return false;
            }
            if (!ce_evaluate(ce, target)) return false;

            node.type = target.type;
            node.data = target.data;
            break;

        case NodeType.MATH_EXPR:
            if (!ce_evaluate(ce, node.data.math.left)) return false;
            if (!ce_evaluate(ce, node.data.math.right)) return false;

            Node* l = node.data.math.left;
            Node* r = node.data.math.right;
            char op = node.data.math.op;

            bool is_float = (l.type == NodeType.FLOAT || r.type == NodeType.FLOAT);
            double val_l = l.type == NodeType.FLOAT ? l.data.float_val : (double)l.data.int_val;
            double val_r = r.type == NodeType.FLOAT ? r.data.float_val : (double)r.data.int_val;

            double res_f = 0.0;
            if (op == '+') res_f = val_l + val_r;
            if (op == '-') res_f = val_l - val_r;
            if (op == '*') res_f = val_l * val_r;
            if (op == '/') res_f = val_l / val_r;

            if (is_float) {
                node.type = NodeType.FLOAT;
                node.data.float_val = res_f;
            } else {
                node.type = NodeType.INT;
                node.data.int_val = (long)res_f;
            }
            break;

        default:
            break;
    }

    node.state = EvalState.RESOLVED;
    return true;
}

// ==========================================
// 6. ПУБЛІЧНИЙ API
// ==========================================

fn void ce_init(ConfigEngine* ce) {
    // Ініціалізація BackedArenaAllocator з використанням вбудованого mem як бази
    BackedArenaAllocator* arena = allocators::new_backed_allocator(65536, mem)!!;
    ce.allocator = arena;

    ce.root = create_node(ce.allocator, NodeType.OBJECT);
    ce.root.data.obj.capacity = 32;
    ce.root.data.obj.fields = (KeyValuePair*)alloc::malloc(ce.allocator, KeyValuePair::size * 32);
    ce.root.state = EvalState.RESOLVED;
}

// Звільняє абсолютно всі ресурси рушія моментально
fn void ce_free(ConfigEngine* ce) {
    alloc::free(ce.allocator, &ce.arena); 
}

fn void ce_parse(ConfigEngine* ce, String text) {
    Lexer lex = {};
    lex.src = text;
    lex.pos = 0;
    lex.len = text.len;

    Parser p = {};
    p.lex = &lex;
    p.alloc = ce.allocator;

    parser_advance(&p);

    while (p.curr.type != TokenType.EOF) {
        if (p.curr.type == TokenType.IDENT) {
            String path = str_dup(p.alloc, p.curr.text);
            parser_advance(&p);

            while (p.curr.type == TokenType.DOT) {
                parser_advance(&p);
                if (p.curr.type == TokenType.IDENT) {
                    path = join_path(p.alloc, path, p.curr.text);
                    parser_advance(&p);
                }
            }

            if (parser_match(&p, TokenType.ASSIGN)) {
                Node* val = parse_expr(&p);
                parser_match(&p, TokenType.SEMI);
                ce_set_path(ce, path, val);
            }
        } else {
            parser_advance(&p);
        }
    }
}

// Геттери зі значеннями за замовчуванням (Default) та логуванням

fn long ce_get_int_def(ConfigEngine* ce, String path, long default_val) {
    Node* n = ce_resolve_path(ce, path);
    if (n == null) {
        io::printfn("[Config Info] Поле '%s' відсутнє. Використано default: %d", path, default_val);
        return default_val;
    }
    if (ce_evaluate(ce, n)) {
        if (n.type == NodeType.INT) return n.data.int_val;
        if (n.type == NodeType.FLOAT) return (long)n.data.float_val;
        
        io::printfn("[Config Warn] Поле '%s' має невідповідний тип (очікувався int). Використано default: %d", path, default_val);
    }
    return default_val;
}

fn long ce_get_int(ConfigEngine* ce, String path) {
    return ce_get_int_def(ce, path, 0);
}

fn double ce_get_float_def(ConfigEngine* ce, String path, double default_val) {
    Node* n = ce_resolve_path(ce, path);
    if (n == null) {
        io::printfn("[Config Info] Поле '%s' відсутнє. Використано default: %f", path, default_val);
        return default_val;
    }
    if (ce_evaluate(ce, n)) {
        if (n.type == NodeType.FLOAT) return n.data.float_val;
        if (n.type == NodeType.INT) return (double)n.data.int_val;

        io::printfn("[Config Warn] Поле '%s' має невідповідний тип (очікувався float). Використано default: %f", path, default_val);
    }
    return default_val;
}

fn double ce_get_float(ConfigEngine* ce, String path) {
    return ce_get_float_def(ce, path, 0.0);
}

fn ZString ce_get_string_def(ConfigEngine* ce, String path, ZString default_val) {
    Node* n = ce_resolve_path(ce, path);
    if (n == null) {
        io::printfn("[Config Info] Поле '%s' відсутнє. Використано default: %s", path, default_val);
        return default_val;
    }
    if (ce_evaluate(ce, n)) {
        if (n.type == NodeType.STRING) return (ZString)n.data.string_val;

        io::printfn("[Config Warn] Поле '%s' має невідповідний тип (очікувався string). Використано default: %s", path, default_val);
    }
    return default_val;
}

fn ZString ce_get_string(ConfigEngine* ce, String path) {
    return ce_get_string_def(ce, path, "");
}