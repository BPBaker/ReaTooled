// ReaTooled Starter - a tiny REAPER extension that ReaBoot / ReaPack installs.
//
// When REAPER starts and ReaTooled hasn't been set up yet, it starts
// "Set up ReaTooled" (Scripts/ReaTooled/Startup/ReaTooled_Set up ReaTooled.lua),
// so buyers don't have to import anything. Once Set up has finished (it saves
// the ExtState ReaTooled/SetupVersion), this does nothing at all.
//
// It waits until REAPER has finished starting (about 1.5 seconds) and while another REAPER
// window is in front (the audio device or plug-in scan questions, the evaluation notice), but
// never more than about 8 seconds, then starts Set up once. Until ReaTooled is set up it keeps
// checking about once a second, so installing the package again after a No starts it again
// in the same session.
// If the "Install ReaTooled" first-run file already started Set up in this
// session (ExtState ReaTooled/SetupStarted), it does nothing. After
// "Restore settings from a backup", or answering No to "Set up ReaTooled now?" (both write
// Data/ReaTooled/starter_off.txt and delete Data/ReaTooled/package_installed.txt) it stays
// quiet too; running Set up again removes that file. Installing the ReaTooled package again
// puts package_installed.txt back: that means the user wants ReaTooled after all, so the
// "stay quiet" file is removed and Set up starts (it asks again).
//
// No REAPER SDK needed: the few declarations it uses are below.

#include <cstdio>
#include <cstring>
#include <string>
#ifdef _WIN32
  #include <windows.h>
#endif

#ifdef _WIN32
  #define RT_EXPORT extern "C" __declspec(dllexport)
#else
  #define RT_EXPORT extern "C" __attribute__((visibility("default")))
#endif

#define REAPER_PLUGIN_VERSION 0x20E

typedef void *HWND_t;

struct reaper_plugin_info_t {
  int caller_version;
  HWND_t hwnd_main;
  int (*Register)(const char *name, void *infostruct);
  void *(*GetFunc)(const char *name);
};

static const char *SECTION = "ReaTooled";
static const char *SETUP_REL = "/Scripts/ReaTooled/Startup/ReaTooled_Set up ReaTooled.lua";
static const char *OFF_REL   = "/Data/ReaTooled/starter_off.txt";
static const char *MARK_REL  = "/Data/ReaTooled/package_installed.txt";   // installed by the package
static const int MIN_TICKS = 45;     // about 1.5 seconds after REAPER starts (timer runs ~30x a second)
static const int STABLE_TICKS = 9;   // no other REAPER window in front for about a third of a second
static const int MAX_TICKS = 240;    // but never wait more than about 8 seconds
// (1.0 waited for the main window itself to be in front, up to 30 seconds. On macOS the window
// js_ReaScriptAPI reports in front isn't always the same handle as the main window, so it often
// waited the whole 30 seconds before the Welcome window.)

static reaper_plugin_info_t *g_rec = nullptr;
static int g_ticks = 0, g_stable = 0;
static bool g_done = false;

static const char *(*GetResourcePath)();
static bool (*HasExtState)(const char *section, const char *key);
static const char *(*GetExtState)(const char *section, const char *key);
static void (*SetExtState)(const char *section, const char *key, const char *value, bool persist);
static int (*AddRemoveReaScript)(bool add, int sectionID, const char *scriptfn, bool commit);
static void (*Main_OnCommand)(int command, int flag);
static HWND_t (*GetMainHwnd)();
static bool (*file_exists)(const char *path);
static void *(*JS_Window_GetForeground)();   // from js_ReaScriptAPI, if installed
static void *(*JS_Window_GetParent)(void *hwnd);
static bool (*JS_Window_IsChild)(void *parent, void *child);
static void (*JS_Window_GetTitle)(void *hwnd, char *buf, int buf_sz);

static void on_timer();

// Delete a file (UTF-8 path)
static void remove_file(const std::string &path) {
#ifdef _WIN32
  int n = MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, nullptr, 0);
  if (n <= 0) return;
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, &w[0], n);
  _wremove(w.c_str());
#else
  std::remove(path.c_str());
#endif
}

// Is a REAPER window other than the main one (a dialog, a question) in front?
// The main window, anything inside it (a docker, the arrange view), or nothing in front
// (another app) doesn't count.
static bool other_window_in_front() {
  void *fg = JS_Window_GetForeground();
  if (!fg) return false;
  void *main_w = (void *)GetMainHwnd();
  if (!main_w || fg == main_w) return false;
  if (JS_Window_IsChild && JS_Window_IsChild(main_w, fg)) return false;
  if (JS_Window_GetParent) {
    void *p = fg;
    for (int i = 0; i < 16 && p; ++i) { p = JS_Window_GetParent(p); if (p == main_w) return false; }
  }
  if (JS_Window_GetTitle) {                    // the same window under another handle (macOS)
    char a[512] = "", b[512] = "";
    JS_Window_GetTitle(fg, a, (int)sizeof a);
    JS_Window_GetTitle(main_w, b, (int)sizeof b);
    if (a[0] && !strcmp(a, b)) return false;
  }
  return true;
}

static void finish() {
  if (g_done) return;
  g_done = true;
  if (g_rec) g_rec->Register("-timer", (void *)on_timer);
}

// Launch Set up (or, from the package, the installer that leads to it)
static void launch(const std::string &path) {
  SetExtState(SECTION, "SetupStarted", "1", false);
  int id = AddRemoveReaScript(true, 0, path.c_str(), true);
  if (id > 0) Main_OnCommand(id, 0);
}

// After the first check it keeps an eye out (about once a second) until ReaTooled is set up:
// if package_installed.txt goes (No, or a restore) and then comes back (the package was
// installed again in this session), it asks again straight away instead of at the next start.
static bool g_watching = false, g_armed = false, g_relaunch = false;

static void on_timer() {
  if (g_done) return;
  ++g_ticks;

  if (g_watching) {
    if (g_ticks % 30) return;
    if (HasExtState(SECTION, "SetupVersion")) { finish(); return; }   // set up: nothing more to do
    std::string res = GetResourcePath(), mark = res + MARK_REL;
#ifdef _WIN32
    for (auto &c : mark) if (c == '/') c = '\\';
#endif
    bool there = file_exists(mark.c_str());
    if (!there) { g_armed = true; return; }
    if (!g_armed) return;
    g_armed = false;                         // the package was installed again: wait as at a start
    g_watching = false; g_relaunch = true; g_ticks = 0; g_stable = 0;
    return;
  }

  if (g_ticks < MIN_TICKS) return;

  // Wait while another REAPER window (audio device, plug-in scan ...) is in front
  if (!JS_Window_GetForeground && g_rec) {
    *(void **)&JS_Window_GetForeground = g_rec->GetFunc("JS_Window_GetForeground");
    *(void **)&JS_Window_GetParent = g_rec->GetFunc("JS_Window_GetParent");
    *(void **)&JS_Window_IsChild = g_rec->GetFunc("JS_Window_IsChild");
    *(void **)&JS_Window_GetTitle = g_rec->GetFunc("JS_Window_GetTitle");
  }
  if (JS_Window_GetForeground && GetMainHwnd && g_ticks < MAX_TICKS) {
    if (other_window_in_front()) { g_stable = 0; return; }
    if (++g_stable < STABLE_TICKS) return;
  }

  if (HasExtState(SECTION, "SetupVersion")) { finish(); return; }   // already set up
  g_watching = true;                                               // from here on: keep an eye out
  g_armed = false;

  std::string res = GetResourcePath(), path = res + SETUP_REL, off = res + OFF_REL, mark = res + MARK_REL;
#ifdef _WIN32
  for (auto &c : path) if (c == '/') c = '\\';
  for (auto &c : off) if (c == '/') c = '\\';
  for (auto &c : mark) if (c == '/') c = '\\';
#endif
  bool relaunch = g_relaunch;
  g_relaunch = false;
  if (!relaunch) {
    const char *started = GetExtState(SECTION, "SetupStarted");  // started this session already
    if (started && !strcmp(started, "1")) return;
  }
  if (file_exists(off.c_str())) {
    if (!file_exists(mark.c_str())) { g_armed = true; return; }  // turned off (a restore, or "No")
    remove_file(off);                                            // the package was installed again: ask again
  }
  if (!file_exists(path.c_str())) return;                        // ReaTooled not installed (yet)
  launch(path);
}

template <typename T> static bool get(T &fn, const char *name) {
  *(void **)&fn = g_rec->GetFunc(name);
  return fn != nullptr;
}

RT_EXPORT int ReaperPluginEntry(void *hInstance, reaper_plugin_info_t *rec) {
  (void)hInstance;
  if (!rec) {                       // REAPER is unloading the extension
    finish();
    return 0;
  }
  if (rec->caller_version != REAPER_PLUGIN_VERSION || !rec->GetFunc) return 0;
  g_rec = rec;

  bool ok = get(GetResourcePath, "GetResourcePath") && get(HasExtState, "HasExtState") &&
            get(GetExtState, "GetExtState") && get(SetExtState, "SetExtState") &&
            get(AddRemoveReaScript, "AddRemoveReaScript") && get(Main_OnCommand, "Main_OnCommand") &&
            get(file_exists, "file_exists");
  get(GetMainHwnd, "GetMainHwnd");
  if (!ok) return 0;

  // Nothing to do on an installation that is already set up
  if (HasExtState(SECTION, "SetupVersion")) return 1;

  rec->Register("timer", (void *)on_timer);
  return 1;
}
