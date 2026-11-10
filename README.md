# Kingdom Kart: Road to Glory — Android

This is the **Wii U game itself**, running on Android phones. Every build takes the latest code and files from the
Wii U game ([seanmallan316/kingdomkart](https://github.com/seanmallan316/kingdomkart)), so everything in the Wii U
version is in the phone version: all the roads, characters, karts, the Bible Journeys story map, cups, trophies and
Bible scenes, Jericho, David vs Goliath, achievements, voices, music and multiplayer.

Only the parts that talk to the Wii U hardware are replaced (in `port/`):
- **drawing** (`port/gfx_gles.c`): the Wii U's lighting on OpenGL ES 3, at the phone's full resolution with smooth
  edges and softer sun shadows;
- **controls, sound and the screen** (`port/sdl_main.c`): touch controls for racing, taps for the menus, Bluetooth
  controllers as Pro Controllers, phone vibration.

## Getting the app
Every change is built by GitHub (`.github/workflows/android.yml`). The APK is on the **Releases** page.
The first start unpacks the game's files (a gold bar fills up); after that it starts straight away.

## Folders
- `port/` the phone parts (and `build_pc.sh`, a PC build used for testing)
- `android/` the Android app project (SDL)
- `tools/wiiu/` reads the Wii U game's data (roads, characters, story map, cups) into JSON
- `godot_prototype/` the earlier hand-made Godot version (no longer built)
