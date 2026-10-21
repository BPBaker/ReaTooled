// ReaTooled Starter - a tiny REAPER extension that ReaBoot / ReaPack installs.
//
// When REAPER starts and ReaTooled hasn't been set up yet, it starts
// "Set up ReaTooled" (Scripts/ReaTooled/Startup/ReaTooled_Set up ReaTooled.lua),
// so buyers don't have to import anything. Once Set up has finished (it saves
// the ExtState ReaTooled/SetupVersion), this does nothing at all.
//
// It waits until REAPER has finished starting and its main window is in front
// (not REAPER's audio device or plug-in scan questions), then starts Set up once.
// If the "Install ReaTooled" first-run file already started Set up in this
// session (ExtState ReaTooled/SetupStarted), it does nothing. After
// "Restore settings from a backup" (which writes Data/ReaTooled/starter_off.txt)
// it stays quiet too; running Set up again removes that file.
//
// No REAPER SDK needed: the few declarations it uses are below.

#include <cstring>
#include <string>

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
static const int MIN_TICKS = 90;     // about 3 seconds after REAPER starts (timer runs ~30x a second)
static const int STABLE_TICKS = 15;  // main window in front for about half a second
static const int MAX_TICKS = 990;    // but never wait more than about 30 seconds

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

static void on_timer();

static void finish() {
  if (g_done) return;
  g_done = true;
  if (g_rec) g_rec->Register("-timer", (void *)on_timer);
}

static void on_timer() {
  if (g_done) return;
  if (++g_ticks < MIN_TICKS) return;

  // Wait while a REAPER dialog (audio device, plug-in scan ...) or another app is in front
  if (!JS_Window_GetForeground && g_rec)
    *(void **)&JS_Window_GetForeground = g_rec->GetFunc("JS_Window_GetForeground");
  if (JS_Window_GetForeground && GetMainHwnd) {
    if (g_ticks < MAX_TICKS) {
      if (JS_Window_GetForeground() != GetMainHwnd()) { g_stable = 0; return; }
      if (++g_stable < STABLE_TICKS) return;
    }
  }

  finish();

  if (HasExtState(SECTION, "SetupVersion")) return;          // already set up
  const char *started = GetExtState(SECTION, "SetupStarted");  // started this session already
  if (started && !strcmp(started, "1")) return;

  std::string res = GetResourcePath(), path = res + SETUP_REL, off = res + OFF_REL;
#ifdef _WIN32
  for (auto &c : path) if (c == '/') c = '\\';
  for (auto &c : off) if (c == '/') c = '\\';
#endif
  if (file_exists(off.c_str())) return;                        // turned off by a restore
  if (!file_exists(path.c_str())) return;                      // ReaTooled not installed (yet)

  SetExtState(SECTION, "SetupStarted", "1", false);
  int id = AddRemoveReaScript(true, 0, path.c_str(), true);
  if (id > 0) Main_OnCommand(id, 0);
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
