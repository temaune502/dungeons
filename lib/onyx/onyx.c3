module onyx;

import std::core::mem;
import std::core::mem::alloc;
import std::core::mem::allocators;
import std::io;
import std::core::string;
import libc;

// ==========================================
// C-Binding для гарантованої роботи з файлами
// ==========================================
extern fn void* fopen(char* filename, char* mode) @cname("fopen");
extern fn int fclose(void* stream) @cname("fclose");
extern fn int fseek(void* stream, long offset, int origin) @cname("fseek");
extern fn long ftell(void* stream) @cname("ftell");
extern fn usz fread(void* ptr, usz size, usz count, void* stream) @cname("fread");
extern fn int fprintf(void* stream, char* format, ...) @cname("fprintf");

const int SEEK_SET = 0;
const int SEEK_END = 2;

// ==========================================
// 1. ТИПИ ДАНИХ ТА СТРУКТУРИ
// ==========================================

enum NodeType : uint {
    INT,
    FLOAT,
    STRING,
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
    String string_val; 
    NodeObj obj;
    String ref_path;
    NodeMath math;
}

struct Node {
    NodeType type;
    EvalState state;
    NodeData data;
    bool is_computed; // Позначає, чи був цей вузол виразом або референсом
}

struct ConfigEngine {
    DynamicArenaAllocator arena; 
    Allocator allocator;         
    Node* root;
}

// ==========================================
// 2. УТИЛІТИ ДЛЯ ПАМ'ЯТІ ТА РЯДКІВ
// ==========================================

fn bool str_eq(String a, String b) {
    if (a.len != b.len) return false;
    if (a.len == 0) return true;
    return libc::memcmp(a.ptr, b.ptr, (usz)a.len) == 0;
}

fn String str_slice(String s, sz start, sz len) {
    if (len <= 0) return "";
    return (String)s[start .. start + len - 1];
}

fn String str_dup(Allocator alloc, String src) {
    if (src.len <= 0) return "";
    
    char* ptr = (char*)alloc::malloc(alloc, (usz)(src.len + 1));
    mem::copy(ptr, src.ptr, (usz)src.len);
    ptr[src.len] = '\0'; // Гарантований нуль-термінатор!
    
    return (String)ptr[0 .. src.len - 1];
}

fn String join_path(Allocator alloc, String parent, String child) {
    if (parent.len <= 0) return str_dup(alloc, child);
    
    sz total_len = parent.len + 1 + child.len;
    char* ptr = (char*)alloc::malloc(alloc, (usz)(total_len + 1));
    
    mem::copy(ptr, parent.ptr, (usz)parent.len);
    ptr[parent.len] = '.';
    mem::copy(ptr + parent.len + 1, child.ptr, (usz)child.len);
    ptr[total_len] = '\0';
    
    return (String)ptr[0 .. total_len - 1];
}

fn Node* create_node(Allocator alloc, NodeType type) {
    Node* node = (Node*)alloc::malloc(alloc, Node::size);
    mem::clear(node, Node::size);
    node.type = type;
    node.state = EvalState.UNTOUCHED;
    node.is_computed = false;
    return node;
}

fn void ensure_capacity(Allocator alloc, NodeObj* obj) {
    if (obj.count >= obj.capacity) {
        sz new_cap = obj.capacity * 2;
        if (new_cap == 0) new_cap = 16;
        obj.fields = (KeyValuePair*)alloc::realloc(alloc, obj.fields, KeyValuePair::size * new_cap);
        obj.capacity = new_cap;
    }
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

    if (c == '"') {
        lex.pos++; 
        sz start = lex.pos;
        while (lex.pos < lex.len && lex.src[lex.pos] != '"') lex.pos++;
        
        sz token_len = lex.pos - start;
        tok.text = str_slice(lex.src, start, token_len);
        tok.type = TokenType.STRING_LIT;
        if (lex.pos < lex.len) lex.pos++; 
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
                        if (str_eq(obj.data.obj.fields[i].key, path)) { 
                            obj.data.obj.fields[i].value = val;
                            found = true;
                            // ВИПРАВЛЕНО: Безпечний ZString каст
                            io::printfn("[Config Warn] Поле '%s' усередині об'єкта було перевизначено.", (ZString)path.ptr);
                            break;
                        }
                    }
                    if (!found) {
                        ensure_capacity(p.alloc, &obj.data.obj);
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
        n.is_computed = true; // Маркуємо як динамічне посилання
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
        math_node.is_computed = true; // Маркуємо як вираз
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
        math_node.is_computed = true; // Маркуємо як вираз
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
                    if (str_eq(current.data.obj.fields[j].key, token)) { 
                        current.data.obj.fields[j].value = val;
                        found = true;
                        // ВИПРАВЛЕНО: Безпечний ZString каст
                        io::printfn("[Config Warn] Поле за шляхом '%s' було перевизначено.", (ZString)path.ptr);
                        break;
                    }
                }
                if (!found) {
                    ensure_capacity(ce.allocator, &current.data.obj);
                    current.data.obj.fields[current.data.obj.count].key = str_dup(ce.allocator, token);
                    current.data.obj.fields[current.data.obj.count].value = val;
                    current.data.obj.count++;
                }
            } else {
                bool found = false;
                for (sz j = 0; j < current.data.obj.count; j++) {
                    if (str_eq(current.data.obj.fields[j].key, token)) { 
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

                    ensure_capacity(ce.allocator, &current.data.obj);
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
                if (str_eq(current.data.obj.fields[j].key, token)) {
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
                // ВИПРАВЛЕНО
                io::printfn("[Config Error] Не знайдено змінну: %s", (ZString)node.data.ref_path.ptr);
                node.state = EvalState.UNTOUCHED; 
                return false;
            }
            if (!ce_evaluate(ce, target)) {
                node.state = EvalState.UNTOUCHED; 
                return false;
            }

            node.type = target.type;
            node.data = target.data;
            break;

        case NodeType.MATH_EXPR:
            if (!ce_evaluate(ce, node.data.math.left)) { node.state = EvalState.UNTOUCHED; return false; }
            if (!ce_evaluate(ce, node.data.math.right)) { node.state = EvalState.UNTOUCHED; return false; }

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
            if (op == '/') {
                if (val_r == 0.0) {
                    io::printn("[Config Error] Ділення на нуль!");
                    node.state = EvalState.UNTOUCHED;
                    return false;
                }
                res_f = val_l / val_r;
            }

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
    ce.arena.init(mem, 32768);
    ce.allocator = &ce.arena;

    ce.root = create_node(ce.allocator, NodeType.OBJECT);
    ce.root.data.obj.capacity = 32;
    ce.root.data.obj.fields = (KeyValuePair*)alloc::malloc(ce.allocator, KeyValuePair::size * 32);
    ce.root.state = EvalState.RESOLVED;
}

fn void ce_free(ConfigEngine* ce) {
    ce.arena.free(); 
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

// ------------------------------------------
// НОВЕ: Завантаження та парсинг напряму з файлу
// ------------------------------------------
fn bool ce_parse_file(ConfigEngine* ce, ZString file_path) {
    void* f = fopen((char*)file_path, "rb");
    if (f == null) {
        io::printfn("[Config Error] Не вдалося відкрити файл конфігурації: %s", file_path);
        return false;
    }
    
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);
    
    if (fsize <= 0) {
        fclose(f);
        return false;
    }
    
    // Виділяємо буфер в арені — він житиме стільки ж, скільки конфіг
    char* buffer = (char*)alloc::malloc(ce.allocator, (usz)(fsize + 1));
    fread(buffer, 1, (usz)fsize, f);
    fclose(f);
    
    buffer[fsize] = '\0';
    String text = (String)buffer[0 .. (usz)fsize - 1];
    ce_parse(ce, text);
    
    return true;
}

// ------------------------------------------
// Збереження вузла у файл (Захист від виразів)
// ------------------------------------------
fn bool ce_save_node(ConfigEngine* ce, String path, ZString file_path) {
    Node* n = ce_resolve_path(ce, path);
    if (n == null) {
        io::printfn("[Config Error] Поле '%s' не знайдено для збереження.", (ZString)path.ptr);
        return false;
    }
    
    // Якщо вузол був створений як вираз (навіть якщо він уже обчислений)
    if (n.is_computed) {
        io::printfn("[Config Error] Відмова: поле '%s' містить вираз або референс.", (ZString)path.ptr);
        return false;
    }
    
    if (!ce_evaluate(ce, n)) return false;

    void* f = fopen((char*)file_path, "w");
    if (f == null) {
        io::printfn("[Config Error] Не вдалося відкрити файл для запису: %s", file_path);
        return false;
    }

    if (n.type == NodeType.INT) {
        fprintf(f, "%s = %ld;\n", (char*)path.ptr, n.data.int_val);
    } else if (n.type == NodeType.FLOAT) {
        fprintf(f, "%s = %f;\n", (char*)path.ptr, n.data.float_val);
    } else if (n.type == NodeType.STRING) {
        fprintf(f, "%s = \"%s\";\n", (char*)path.ptr, (char*)n.data.string_val.ptr);
    } else {
        io::printfn("[Config Error] Непідтримуваний тип (наприклад об'єкт) для '%s'", (ZString)path.ptr);
        fclose(f);
        return false;
    }
    
    fclose(f);
    io::printfn("[Config Info] Змінну '%s' успішно збережено у файл %s", (ZString)path.ptr, file_path);
    return true;
}
fn bool ce_save_node_smart(ConfigEngine* ce, String path, ZString file_path) {
    Node* n = ce_resolve_path(ce, path);
    if (n == null || n.is_computed) {
        io::printn("[Config Error] Поле не знайдено або це вираз!");
        return false;
    }
    
    // Формуємо нове значення як рядок для запису
    char[128] val_buf;
    if (n.type == NodeType.INT){ libc::snprintf(&val_buf[0], 128, "%ld", n.data.int_val);}
    else if (n.type == NodeType.FLOAT) {libc::snprintf(&val_buf[0], 128, "%f", n.data.float_val);}
    else if (n.type == NodeType.STRING) {libc::snprintf(&val_buf[0], 128, "\"%s\"", (char*)n.data.string_val.ptr);}
    else {return false;}

    // Відкриваємо оригінал для читання та тимчасовий файл для запису
    void* f = fopen((char*)file_path, "r");
    if (f == null) {return false; }// Якщо файлу нема, просто записуємо в "w"
    
    ZString tmp_path = "config.tmp";
    void* tmp = fopen((char*)tmp_path, "w");
    
    char[512] line;
    bool found = false;
    
    // Читаємо рядок за рядком
    while (libc::fgets(&line[0], 512, f) != null) {
        // Перевіряємо, чи починається рядок з нашого ключа (дуже проста перевірка)
        // Для надійності краще використовувати str_slice та порівняння, як у лексері
        if (libc::memcmp(&line[0], path.ptr, (usz)path.len) == 0 && line[path.len] == ' ') {
            fprintf(tmp, "%s = %s;\n", (char*)path.ptr, &val_buf[0]);
            found = true;
        } else {
            fprintf(tmp, "%s", &line[0]);
        }
    }
    
    // Якщо не знайшли ключ у файлі, додаємо його в кінець
    if (!found) {
        fprintf(tmp, "%s = %s;\n", (ZString)path.ptr, &val_buf[0]);
    }
    
    fclose(f);
    fclose(tmp);
    
    // Замінюємо старий файл новим
    libc::remove((ZString)file_path);
    libc::rename((ZString)tmp_path, (ZString)file_path);
    
    io::printfn("[Config Info] Змінну '%s' безпечно оновлено у файлі.", (ZString)path.ptr);
    return true;
}
// ------------------------------------------
// Геттери
// ------------------------------------------

fn long ce_get_int_def(ConfigEngine* ce, String path, long default_val) {
    Node* n = ce_resolve_path(ce, path);
    if (n == null) {
        io::printfn("[Config Info] Поле '%s' відсутнє. Використано default: %d", (ZString)path.ptr, default_val);
        return default_val;
    }
    if (ce_evaluate(ce, n)) {
        if (n.type == NodeType.INT) return n.data.int_val;
        if (n.type == NodeType.FLOAT) return (long)n.data.float_val;
        
        io::printfn("[Config Warn] Поле '%s' має невідповідний тип. Використано default: %d", (ZString)path.ptr, default_val);
    }
    return default_val;
}

fn long ce_get_int(ConfigEngine* ce, String path) {
    return ce_get_int_def(ce, path, 0);
}

fn double ce_get_float_def(ConfigEngine* ce, String path, double default_val) {
    Node* n = ce_resolve_path(ce, path);
    if (n == null) {
        io::printfn("[Config Info] Поле '%s' відсутнє. Використано default: %f", (ZString)path.ptr, default_val);
        return default_val;
    }
    if (ce_evaluate(ce, n)) {
        if (n.type == NodeType.FLOAT) return n.data.float_val;
        if (n.type == NodeType.INT) return (double)n.data.int_val;

        io::printfn("[Config Warn] Поле '%s' має невідповідний тип. Використано default: %f", (ZString)path.ptr, default_val);
    }
    return default_val;
}

fn double ce_get_float(ConfigEngine* ce, String path) {
    return ce_get_float_def(ce, path, 0.0);
}

fn ZString ce_get_string_def(ConfigEngine* ce, String path, ZString default_val) {
    Node* n = ce_resolve_path(ce, path);
    if (n == null) {
        io::printfn("[Config Info] Поле '%s' відсутнє. Використано default: %s", (ZString)path.ptr, default_val);
        return default_val;
    }
    if (ce_evaluate(ce, n)) {
        if (n.type == NodeType.STRING) return (ZString)n.data.string_val.ptr;

        io::printfn("[Config Warn] Поле '%s' має невідповідний тип. Використано default: %s", (ZString)path.ptr, default_val);
    }
    return default_val;
}

fn ZString ce_get_string(ConfigEngine* ce, String path) {
    return ce_get_string_def(ce, path, "");
}