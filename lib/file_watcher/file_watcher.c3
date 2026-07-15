module file_watcher;

import std::core::mem;
import std::core::mem::alloc;
import std::io;

const void* INVALID_HANDLE_VALUE = (void*)(usz)-1;
const uint MIN_CAPACITY = 256;
const uint MAX_PATH_LEN = 260;

// Сигнатура функції-колбеку. ZString - це null-terminated char*
alias FileEventCb = fn void(ZString path, void* user_data);

struct FileEntry
{
    char[MAX_PATH_LEN] name; 
    uint name_len;  
    ulong last_write;
    ulong size;    
    bool is_dir;    
}

struct FileWatcher
{
    FileEntry* prev_files;
    FileEntry* current_files;
    uint prev_count;
    uint current_count;
    uint capacity; 
    Allocator allocator;
    char[MAX_PATH_LEN] watch_path; 
    bool is_initialized;

    // Вказівники на функції користувача
    FileEventCb on_created;
    FileEventCb on_deleted;
    FileEventCb on_modified;
    void* user_data;

    // Дебаунсинг (захист від подвійного спрацьовування)
    ulong debounce_ms;
    ulong last_poll_ticks;
}

// Windows API
struct Win32FindDataW
{
    uint dwFileAttributes;
    uint ftCreationTimeLow;
    uint ftCreationTimeHigh;
    uint ftLastAccessTimeLow;
    uint ftLastAccessTimeHigh;
    uint ftLastWriteTimeLow;
    uint ftLastWriteTimeHigh;
    uint nFileSizeHigh;
    uint nFileSizeLow;
    uint dwReserved0;
    uint dwReserved1;
    ushort[260] cFileName;
    ushort[14] cAlternateFileName;
}

extern fn void* find_first_file_w(ushort* file_name, Win32FindDataW* data) @cname("FindFirstFileW");
extern fn bool find_next_file_w(void* handle, Win32FindDataW* data) @cname("FindNextFileW");
extern fn bool find_close(void* handle) @cname("FindClose");
extern fn int multi_byte_to_wide_char(uint cp, uint flags, char* mb, int cb_mb, ushort* wc, int cch_wc) @cname("MultiByteToWideChar");
extern fn int wide_char_to_multi_byte(uint cp, uint flags, ushort* wc, int cch_wc, char* mb, int cb_mb, char* def, bool* used_def) @cname("WideCharToMultiByte");
// Імпортуємо функцію для отримання мілісекунд від Windows, щоб не залежати від Raylib
extern fn ulong get_tick_count_64() @cname("GetTickCount64");

alias CompareFunc = fn int(void*, void*);
extern fn void qsort(void* base, usz num, usz size, CompareFunc compar) @cname("qsort");

const uint FILE_ATTRIBUTE_DIRECTORY = 0x10;
const uint CP_UTF8 = 65001; 

// ==========================================
// Utils (без змін)
// ==========================================

fn uint utf8_to_utf16(char* src, ushort* dest, uint dest_cap)
{
    int res = multi_byte_to_wide_char(CP_UTF8, 0, src, -1, dest, (int)dest_cap);
    if (res <= 0) return 0;
    return (uint)(res - 1); 
}

fn uint utf16_to_utf8(ushort* src, char* dest, uint dest_cap)
{
    int res = wide_char_to_multi_byte(CP_UTF8, 0, src, -1, dest, (int)dest_cap, null, null);
    if (res <= 0) return 0;
    return (uint)(res - 1);
}

fn int compare_entries(void* a, void* b)
{
    FileEntry* f1 = (FileEntry*)a;
    FileEntry* f2 = (FileEntry*)b;
    
    uint min_len = f1.name_len < f2.name_len ? f1.name_len : f2.name_len;
    for (uint i = 0; i < min_len; i++)
    {
        if (f1.name[i] != f2.name[i]) return (int)f1.name[i] - (int)f2.name[i];
    }
    return (int)f1.name_len - (int)f2.name_len;
}

// ==========================================
// Main Logic FileWatcher
// ==========================================

// Додано параметр debounce_ms (наприклад, 250 мс), щоб уникнути подвійних подій
fn bool fw_init(FileWatcher* fw, Allocator allocator, char* path, ulong debounce_ms)
{
    fw.is_initialized = false;
    fw.allocator = allocator;
    fw.prev_count = 0;
    fw.current_count = 0;
    fw.capacity = MIN_CAPACITY;
    
    fw.debounce_ms = debounce_ms;
    fw.last_poll_ticks = 0;

    // Явно скидаємо колбеки, щоб перше сканування було "тихим"
    fw.on_created = null;
    fw.on_deleted = null;
    fw.on_modified = null;
    fw.user_data = null;

    fw.prev_files = (FileEntry*)alloc::malloc(allocator, FileEntry::size * fw.capacity);
    fw.current_files = (FileEntry*)alloc::malloc(allocator, FileEntry::size * fw.capacity);

    if (fw.prev_files == null || fw.current_files == null)
    {
        if (fw.prev_files != null) alloc::free(allocator, fw.prev_files);
        if (fw.current_files != null) alloc::free(allocator, fw.current_files);
        return false;
    }

    uint i = 0;
    while (path[i] != '\0' && i < MAX_PATH_LEN - 1)
    {
        fw.watch_path[i] = path[i];
        i++;
    }
    fw.watch_path[i] = '\0';
    
    fw.is_initialized = true;
    
    // Робимо перший знімок директорії. Оскільки колбеки == null, події не відправляться.
    fw_poll(fw); 
    fw.last_poll_ticks = get_tick_count_64();
    return true;
}

// Функція для встановлення обробників подій ПІСЛЯ ініціалізації
fn void fw_set_callbacks(
    FileWatcher* fw, 
    FileEventCb on_created, 
    FileEventCb on_deleted, 
    FileEventCb on_modified, 
    void* user_data
) {
    fw.on_created = on_created;
    fw.on_deleted = on_deleted;
    fw.on_modified = on_modified;
    fw.user_data = user_data;
}

fn void fw_poll(FileWatcher* fw)
{
    if (!fw.is_initialized) return;

    // Вбудований дебаунсинг: якщо пройшло менше часу ніж треба, просто виходимо.
    ulong current_ticks = get_tick_count_64();
    if (current_ticks - fw.last_poll_ticks < fw.debounce_ms)
    {
        return;
    }
    fw.last_poll_ticks = current_ticks;

    fw.current_count = 0;

    char[MAX_PATH_LEN] search_path_utf8 = {};
    uint j = 0;
    while (fw.watch_path[j] != '\0' && j < MAX_PATH_LEN - 4)
    {
        search_path_utf8[j] = fw.watch_path[j];
        j++;
    }
    
    if (j > 0 && search_path_utf8[j-1] != '/' && search_path_utf8[j-1] != '\\')
    {
        search_path_utf8[j] = '\\';
        j++;
    }
    search_path_utf8[j] = '*';
    search_path_utf8[j+1] = '\0';

    ushort[MAX_PATH_LEN] search_path_utf16 = {};
    uint conv_res = utf8_to_utf16(&search_path_utf8[0], &search_path_utf16[0], MAX_PATH_LEN);
    if (conv_res == 0) return; 

    Win32FindDataW find_data = {}; 
    void* handle = find_first_file_w(&search_path_utf16[0], &find_data);
    
    if (handle != INVALID_HANDLE_VALUE)
    {
        do
        {
            if (find_data.cFileName[0] == (ushort)'.')
            {
                if (find_data.cFileName[1] == 0 || 
                   (find_data.cFileName[1] == (ushort)'.' && find_data.cFileName[2] == 0)) 
                {
                    continue;
                }
            }
            if (find_data.cFileName[0] == 0) continue;

            if (fw.current_count >= fw.capacity)
            {
                uint new_capacity = fw.capacity * 2;
                
                FileEntry* new_curr = (FileEntry*)alloc::malloc(fw.allocator, FileEntry::size * new_capacity);
                FileEntry* new_prev = (FileEntry*)alloc::malloc(fw.allocator, FileEntry::size * new_capacity);
                
                if (new_curr == null || new_prev == null)
                {
                    if (new_curr != null) alloc::free(fw.allocator, new_curr);
                    if (new_prev != null) alloc::free(fw.allocator, new_prev);
                    break;
                }

                mem::copy(new_curr, fw.current_files, FileEntry::size * fw.current_count);
                mem::copy(new_prev, fw.prev_files, FileEntry::size * fw.prev_count);
                
                alloc::free(fw.allocator, fw.current_files);
                alloc::free(fw.allocator, fw.prev_files);
                
                fw.current_files = new_curr;
                fw.prev_files = new_prev;
                fw.capacity = new_capacity;
            }

            uint u8_len = utf16_to_utf8(&find_data.cFileName[0], &fw.current_files[fw.current_count].name[0], MAX_PATH_LEN);
            fw.current_files[fw.current_count].name_len = u8_len;
            fw.current_files[fw.current_count].name[u8_len] = '\0'; // Гарантуємо null-термінатор для ZString
            
            fw.current_files[fw.current_count].last_write = ((ulong)find_data.ftLastWriteTimeHigh << 32) | find_data.ftLastWriteTimeLow;
            fw.current_files[fw.current_count].size = ((ulong)find_data.nFileSizeHigh << 32) | find_data.nFileSizeLow;
            fw.current_files[fw.current_count].is_dir = (find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
            
            fw.current_count++;
            
        } while (find_next_file_w(handle, &find_data));
        
        find_close(handle);
    }

    if (fw.current_count > 0)
    {
        qsort(fw.current_files, (usz)fw.current_count, FileEntry::size, &compare_entries);
    }

    uint i = 0; // current
    uint p = 0; // prev

    // Викликаємо колбеки прямо під час порівняння! Більше жодних масивів подій.
    while (i < fw.current_count || p < fw.prev_count)
    {
        if (i < fw.current_count && p < fw.prev_count)
        {
            int cmp = compare_entries(&fw.current_files[i], &fw.prev_files[p]);

            if (cmp == 0) 
            {
                if (fw.current_files[i].last_write != fw.prev_files[p].last_write ||
                    fw.current_files[i].size != fw.prev_files[p].size ||
                    fw.current_files[i].is_dir != fw.prev_files[p].is_dir)
                {
                    if (fw.on_modified != null) fw.on_modified((ZString)&fw.current_files[i].name[0], fw.user_data);
                }
                i++;
                p++;
            }
            else if (cmp < 0) 
            {
                if (fw.on_created != null) fw.on_created((ZString)&fw.current_files[i].name[0], fw.user_data);
                i++;
            }
            else 
            {
                if (fw.on_deleted != null) fw.on_deleted((ZString)&fw.prev_files[p].name[0], fw.user_data);
                p++;
            }
        }
        else if (i < fw.current_count)
        {
            if (fw.on_created != null) fw.on_created((ZString)&fw.current_files[i].name[0], fw.user_data);
            i++;
        }
        else 
        {
            if (fw.on_deleted != null) fw.on_deleted((ZString)&fw.prev_files[p].name[0], fw.user_data);
            p++;
        }
    }

    // Завжди повністю копіюємо стан, оскільки обробили всі зміни
    fw.prev_count = fw.current_count;
    mem::copy(fw.prev_files, fw.current_files, FileEntry::size * fw.current_count);

    if (fw.capacity > MIN_CAPACITY && fw.current_count < fw.capacity / 4)
    {
        uint new_capacity = fw.capacity / 2;
        if (new_capacity < MIN_CAPACITY) new_capacity = MIN_CAPACITY;

        FileEntry* new_curr = (FileEntry*)alloc::malloc(fw.allocator, FileEntry::size * new_capacity);
        FileEntry* new_prev = (FileEntry*)alloc::malloc(fw.allocator, FileEntry::size * new_capacity);

        if (new_curr != null && new_prev != null)
        {
            if (fw.current_count > 0)
            {
                mem::copy(new_curr, fw.current_files, FileEntry::size * fw.current_count);
                mem::copy(new_prev, fw.prev_files, FileEntry::size * fw.current_count);
            }
            alloc::free(fw.allocator, fw.current_files);
            alloc::free(fw.allocator, fw.prev_files);
            fw.current_files = new_curr;
            fw.prev_files = new_prev;
            fw.capacity = new_capacity;
        }
        else
        {
            if (new_curr != null) alloc::free(fw.allocator, new_curr);
            if (new_prev != null) alloc::free(fw.allocator, new_prev);
        }
    }
}

fn void fw_destroy(FileWatcher* fw)
{
    if (fw.is_initialized)
    {
        alloc::free(fw.allocator, fw.prev_files);
        alloc::free(fw.allocator, fw.current_files);
        fw.is_initialized = false;
    }
}