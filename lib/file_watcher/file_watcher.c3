module file_watcher;

import std::core::mem;
import std::core::mem::alloc;
import std::core::mem::allocators; // Додано імпорт алокаторів
import std::io;

const void* INVALID_HANDLE_VALUE = (void*)(usz)-1;
const uint MIN_CAPACITY = 256;
const uint MAX_PATH_LEN = 260;

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
    // ПОДВІЙНА БУФЕРИЗАЦІЯ АРЕН
    DynamicArenaAllocator[2] arenas;
    uint current_arena_idx;

    FileEntry* prev_files;
    FileEntry* current_files;
    uint prev_count;
    uint current_count;
    uint capacity; 
    
    char[MAX_PATH_LEN] watch_path; 
    bool is_initialized;

    FileEventCb on_created;
    FileEventCb on_deleted;
    FileEventCb on_modified;
    void* user_data;

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
extern fn ulong get_tick_count_64() @cname("GetTickCount64");

alias CompareFunc = fn int(void*, void*);
extern fn void qsort(void* base, usz num, usz size, CompareFunc compar) @cname("qsort");

const uint FILE_ATTRIBUTE_DIRECTORY = 0x10;
const uint CP_UTF8 = 65001; 

// ==========================================
// Utils 
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

fn bool fw_init(FileWatcher* fw, Allocator backing_allocator, char* path, ulong debounce_ms)
{
    fw.is_initialized = false;
    
    // Ініціалізуємо дві арени. Розмір сторінки 16KB (16384) або більше.
    // Арена сама запитуватиме пам'ять у backing_allocator за потреби.
    fw.arenas[0].init(backing_allocator, 16384);
    fw.arenas[1].init(backing_allocator, 16384);
    fw.current_arena_idx = 0;

    fw.prev_count = 0;
    fw.current_count = 0;
    fw.prev_files = null;
    fw.current_files = null;
    
    fw.debounce_ms = debounce_ms;
    fw.last_poll_ticks = 0;

    fw.on_created = null;
    fw.on_deleted = null;
    fw.on_modified = null;
    fw.user_data = null;

    uint i = 0;
    while (path[i] != '\0' && i < MAX_PATH_LEN - 1)
    {
        fw.watch_path[i] = path[i];
        i++;
    }
    fw.watch_path[i] = '\0';
    
    fw.is_initialized = true;
    
    // Перший знімок (без колбеків)
    fw_poll(fw); 
    fw.last_poll_ticks = get_tick_count_64();
    return true;
}

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

    ulong current_ticks = get_tick_count_64();
    if (current_ticks - fw.last_poll_ticks < fw.debounce_ms) return;
    fw.last_poll_ticks = current_ticks;

    // 1. ЛОГІКА ПІНГ-ПОНГУ: Міняємо поточний масив на попередній
    fw.prev_files = fw.current_files;
    fw.prev_count = fw.current_count;

    // Перемикаємо індекс арени (0 -> 1, або 1 -> 0)
    fw.current_arena_idx = 1 - fw.current_arena_idx;
    DynamicArenaAllocator* active_arena = &fw.arenas[fw.current_arena_idx];

    // Очищаємо нову арену! Вона звільнить масив, який був тут 2 кроки тому.
    // Reset миттєвий, пам'ять залишається закріпленою за ареною для швидкого ре-використання.
    active_arena.reset();

    // 2. Виділяємо пам'ять під новий стан в АКТИВНІЙ арені
    fw.capacity = MIN_CAPACITY;
    fw.current_count = 0;
    fw.current_files = (FileEntry*)alloc::malloc(active_arena, FileEntry::size * fw.capacity);

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
    if (utf8_to_utf16(&search_path_utf8[0], &search_path_utf16[0], MAX_PATH_LEN) == 0) return; 

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

            // Збільшення ємності в арені — це супер швидко!
            if (fw.current_count >= fw.capacity)
            {
                uint new_capacity = fw.capacity * 2;
                
                // Оскільки current_files - це ОСТАННЄ виділення в цій арені, 
                // realloc() просто пересуне вказівник розміру, без копіювання пам'яті! 
                // (це описано в логіці resize арени).
                fw.current_files = (FileEntry*)alloc::realloc(active_arena, fw.current_files, FileEntry::size * new_capacity);
                fw.capacity = new_capacity;
            }

            uint u8_len = utf16_to_utf8(&find_data.cFileName[0], &fw.current_files[fw.current_count].name[0], MAX_PATH_LEN);
            fw.current_files[fw.current_count].name_len = u8_len;
            fw.current_files[fw.current_count].name[u8_len] = '\0'; 
            
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

    // 3. Порівняння (diffing) - ЛОГІКА НЕ ЗМІНЮЄТЬСЯ
    // Ми порівнюємо current_files (з поточної арени) з prev_files (з попередньої арени)
    uint i = 0; 
    uint p = 0; 

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

    // УВАГА: Ми більше не робимо mem::copy() і ручного звільнення/зменшення буферів!
    // Вказівники просто залишаться збереженими до наступного кадру, а арена
    // подбає про ефективність. Величезний шматок коду просто зник.
}

fn void fw_destroy(FileWatcher* fw)
{
    if (fw.is_initialized)
    {
        // Повністю звільняємо пам'ять обох арен (повертаємо backing_allocator-у)
        fw.arenas[0].free();
        fw.arenas[1].free();
        fw.is_initialized = false;
    }
}