# ReaTooled Starter

A tiny REAPER extension, installed by ReaBoot/ReaPack like SWS or ReaImGui.
On the first start after installing, it starts **Set up ReaTooled** by itself,
so buyers don't need to import anything. After setup it does nothing.

- Waits about 3 seconds after REAPER starts, and until REAPER's main window is
  in front (so it doesn't jump in front of REAPER's audio device or plug-in
  scan questions), but never more than about 30 seconds.
- Does nothing if ReaTooled is already set up (`ReaTooled/SetupVersion`), if the
  Install ReaTooled file already started Set up this session
  (`ReaTooled/SetupStarted`), after "Restore settings from a backup"
  (`Data/ReaTooled/starter_off.txt`), or if Set up isn't installed.

## Changing it

1. Edit `reatooled_starter.cpp` and raise the number in `VERSION`.
2. Commit and push in GitHub Desktop. GitHub builds Mac, Windows and Linux
   files (Actions tab, "Build ReaTooled Starter", about 3 minutes) and commits
   them to `UserPlugins/`.
3. In GitHub Desktop, click **Pull origin** to get the built files.
4. Run `ReaTooled_Build_release.lua`, then commit and push as usual.
