package com.seanmallan.kingdomkart;

import org.libsdl.app.SDLActivity;

/** Kingdom Kart: the game itself is the Wii U game's code, started by SDL. */
public class MainActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] { "SDL2", "main" };
    }
}
