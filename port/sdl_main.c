// sdl_main.c - Kingdom Kart: Road to Glory on Android phones (and on a PC for testing). This replaces the Wii U's
// platform/wiiu_main.c: it opens the screen, plays the sound, reads the touch screen and Bluetooth controllers,
// and runs the Wii U game's own frame (game_frame) - the whole game, unchanged.
//
// Phone controls: in a race, a steering stick on the left (put your thumb down anywhere there and slide) and on the
// right GAS (A), DRIFT (R, keeps the gas on), ITEM (L) and BRAKE (B); pause at the top. In the menus your finger
// taps the screen just like the GamePad's touch screen, and a BACK button sits in the corner.
// A Bluetooth controller works like a Pro Controller: A, B, X, Y, L/ZL, R/ZR, + (Start), the left stick and d-pad.
#include <SDL.h>
#include "gles.h"
#include "port.h"
#include "render/gfx.h"
#include "game/game.h"
#include "game/save.h"
#include "audio/sfx.h"
#include "audio/music.h"
#include "third_party/stb_image.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <sys/stat.h>
#include <errno.h>

void gfx_set_logfile(FILE *f);
static SDL_Window *g_win; static SDL_GLContext g_ctx;
static int g_sw = 1280, g_sh = 720;           /* the screen */
static int g_tw = 1280, g_th = 720;           /* the game's 16:9 picture */
static int g_ox = 0, g_oy = 0;                /* where the picture sits on the screen */
static int g_racing = 0, g_touch_mode = 1;    /* in a race: show the race controls; touch used last (else a controller) */
static FILE *g_log;
static int g_shot_now; static char g_shot_path[512];   /* test runs: save this frame's picture */

void port_log(const char *fmt, ...) {
    char buf[1024]; va_list ap; va_start(ap, fmt); vsnprintf(buf, sizeof buf, fmt, ap); va_end(ap);
    SDL_Log("%s", buf);
}

/* ------------------------------------------------------------------ the picture's place on the screen */
static void layout(void) {
    SDL_GL_GetDrawableSize(g_win, &g_sw, &g_sh);
    if (g_sw * 9 > g_sh * 16) { g_th = g_sh; g_tw = g_sh * 16 / 9; } else { g_tw = g_sw; g_th = g_sw * 9 / 16; }
    /* more than full HD costs battery for no visible gain on a phone */
    if (g_th > 1080) { g_th = 1080; g_tw = 1920; }
    int dw = g_sw * 9 > g_sh * 16 ? g_sh * 16 / 9 : g_sw, dh = dw * 9 / 16;
    g_ox = (g_sw - dw) / 2; g_oy = (g_sh - dh) / 2;
}
void port_target_size(int *w, int *h) { *w = g_tw; *h = g_th; }

/* ------------------------------------------------------------------ touch controls */
typedef struct { const char *file; float cx, cy, r; int key; GLuint tex; int down; int finger; } TButton;   /* cx, cy, r: screen fractions (r of the height) */
enum { K_A, K_B, K_ZR, K_ZL, K_PLUS, K_BACK };
static TButton BTN[] = {
    {"btn_gas", 0.905f, 0.80f, 0.15f, K_A},
    {"btn_drift", 0.835f, 0.56f, 0.125f, K_ZR},
    {"btn_item", 0.705f, 0.47f, 0.095f, K_ZL},
    {"btn_brake", 0.735f, 0.86f, 0.095f, K_B},
    {"btn_pause", 0.5f, 0.07f, 0.06f, K_PLUS},
    {"btn_back", 0.06f, 0.09f, 0.07f, K_BACK},
};
#define NBTN (int)(sizeof BTN / sizeof BTN[0])
static GLuint g_stick_base, g_stick_knob; static int g_stick_finger = -1; static float g_stick_x0, g_stick_y0, g_stick_dx;
static SDL_FingerID g_fid[16]; static float g_fx[16], g_fy[16]; static int g_fdown[16], g_ftap[16];
static GLuint g_ov_prog, g_ov_vao, g_ov_vbo; static GLint g_ov_tex, g_ov_alpha;

static GLuint load_png(const char *name) {
    char path[256]; snprintf(path, sizeof path, KK_CONTENT_DIR "port_ui/%s.png", name);
    FILE *f = fopen(path, "rb"); if (!f) { port_log("no picture %s", path); return 0; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET); unsigned char *raw = malloc((size_t)n); fread(raw, 1, (size_t)n, f); fclose(f);
    int w, h, c; unsigned char *px = stbi_load_from_memory(raw, (int)n, &w, &h, &c, 4); free(raw); if (!px) return 0;
    GLuint t; glGenTextures(1, &t); glBindTexture(GL_TEXTURE_2D, t); glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, px); glGenerateMipmap(GL_TEXTURE_2D);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR); glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE); glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    stbi_image_free(px); return t;
}
static void overlay_init(void) {
    const char *vs = "#version 300 es\nlayout(location=0) in vec2 p; layout(location=1) in vec2 uv; out vec2 v; void main(){ v = uv; gl_Position = vec4(p, 0.0, 1.0); }\n";
    const char *fs = "#version 300 es\nprecision mediump float; in vec2 v; uniform sampler2D t; uniform float a; out vec4 o; void main(){ o = texture(t, v) * vec4(1.0, 1.0, 1.0, a); }\n";
    GLuint s1 = glCreateShader(GL_VERTEX_SHADER); glShaderSource(s1, 1, &vs, NULL); glCompileShader(s1);
    GLuint s2 = glCreateShader(GL_FRAGMENT_SHADER); glShaderSource(s2, 1, &fs, NULL); glCompileShader(s2);
    g_ov_prog = glCreateProgram(); glAttachShader(g_ov_prog, s1); glAttachShader(g_ov_prog, s2); glLinkProgram(g_ov_prog);
    g_ov_tex = glGetUniformLocation(g_ov_prog, "t"); g_ov_alpha = glGetUniformLocation(g_ov_prog, "a");
    glGenVertexArrays(1, &g_ov_vao); glBindVertexArray(g_ov_vao); glGenBuffers(1, &g_ov_vbo); glBindBuffer(GL_ARRAY_BUFFER, g_ov_vbo);
    glBufferData(GL_ARRAY_BUFFER, 16 * sizeof(float) * 6, NULL, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(0); glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void *)0);
    glEnableVertexAttribArray(1); glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void *)(2 * sizeof(float)));
    glBindVertexArray(0);
    for (int i = 0; i < NBTN; i++) BTN[i].tex = load_png(BTN[i].file);
    g_stick_base = load_png("stick_base"); g_stick_knob = load_png("stick_knob");
}
static void quad(GLuint tex, float cx, float cy, float r, float alpha) {   /* screen pixels: centre and radius */
    if (!tex) return;
    float x0 = (cx - r) / g_sw * 2 - 1, x1 = (cx + r) / g_sw * 2 - 1, y0 = 1 - (cy - r) / g_sh * 2, y1 = 1 - (cy + r) / g_sh * 2;
    float v[24] = {x0, y0, 0, 0, x1, y0, 1, 0, x1, y1, 1, 1, x0, y0, 0, 0, x1, y1, 1, 1, x0, y1, 0, 1};
    glBindBuffer(GL_ARRAY_BUFFER, g_ov_vbo); glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof v, v);
    glBindTexture(GL_TEXTURE_2D, tex); glUniform1f(g_ov_alpha, alpha); glDrawArrays(GL_TRIANGLES, 0, 6);
}
static int btn_visible(int i) { if (!g_touch_mode) return 0; if (BTN[i].key == K_BACK) return !g_racing; return g_racing; }
static float bx(int i) { return BTN[i].cx * g_sw; }
static float by(int i) { return BTN[i].cy * g_sh; }
static float br(int i) { return BTN[i].r * g_sh; }

void port_present(unsigned tex, int w, int h) {
    (void)tex;
    glBindFramebuffer(GL_FRAMEBUFFER, 0); glDisable(GL_SCISSOR_TEST); glViewport(0, 0, g_sw, g_sh);
    glClearColor(0.02f, 0.015f, 0.04f, 1); glClear(GL_COLOR_BUFFER_BIT);
    int dw = g_sw - 2 * g_ox, dh = g_sh - 2 * g_oy;
    extern unsigned gfx_port_resolved_fbo(void);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, gfx_port_resolved_fbo()); glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    glBlitFramebuffer(0, 0, w, h, g_ox, g_oy, g_ox + dw, g_oy + dh, GL_COLOR_BUFFER_BIT, GL_LINEAR);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    /* the touch controls over the picture */
    glDisable(GL_DEPTH_TEST); glDisable(GL_CULL_FACE); glEnable(GL_BLEND); glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glUseProgram(g_ov_prog); glUniform1i(g_ov_tex, 0); glActiveTexture(GL_TEXTURE0); glBindVertexArray(g_ov_vao);
    for (int i = 0; i < NBTN; i++) if (btn_visible(i)) quad(BTN[i].tex, bx(i), by(i), br(i), BTN[i].down ? 1.0f : 0.75f);
    if (g_touch_mode && g_racing) {
        float R = 0.16f * g_sh, sx = g_stick_finger >= 0 ? g_stick_x0 : 0.13f * g_sw, sy = g_stick_finger >= 0 ? g_stick_y0 : 0.74f * g_sh;
        quad(g_stick_base, sx, sy, R, 0.7f); quad(g_stick_knob, sx + g_stick_dx * R, sy, R * 0.5f, 0.9f);
    }
    glBindVertexArray(0);
    if (g_shot_now) {   /* a test run: save the whole screen as shown (the game's picture and the touch controls) */
        unsigned char *px = malloc((size_t)g_sw * g_sh * 4); glPixelStorei(GL_PACK_ALIGNMENT, 1);
        glReadPixels(0, 0, g_sw, g_sh, GL_RGBA, GL_UNSIGNED_BYTE, px);
        FILE *f = fopen(g_shot_path, "wb");
        if (f) { fprintf(f, "P6\n%d %d\n255\n", g_sw, g_sh);
            for (int y = g_sh - 1; y >= 0; y--) for (int x = 0; x < g_sw; x++) fwrite(px + ((size_t)y * g_sw + x) * 4, 1, 3, f);
            fclose(f); }
        free(px); port_log("picture %s - %s", g_shot_path, game_where());
    }
    { static int n; GLenum er = glGetError(); if (er && n++ < 20) port_log("GL error 0x%x after frame", er); }
    SDL_GL_SwapWindow(g_win);
}

static int finger_slot(SDL_FingerID id, int make) {
    for (int i = 0; i < 16; i++) if (g_fdown[i] && g_fid[i] == id) return i;
    if (!make) return -1;
    for (int i = 0; i < 16; i++) if (!g_fdown[i]) { g_fid[i] = id; g_fdown[i] = 1; return i; }
    return -1;
}
static void touch_event(SDL_Event *e) {
    float x = e->tfinger.x * g_sw, y = e->tfinger.y * g_sh;
    g_touch_mode = 1;
    if (e->type == SDL_FINGERDOWN) {
        int s = finger_slot(e->tfinger.fingerId, 1); if (s < 0) return;
        g_fx[s] = x; g_fy[s] = y; g_ftap[s] = 1;
        if (g_racing && g_stick_finger < 0 && x < g_sw * 0.42f && y > g_sh * 0.3f) { g_stick_finger = s; g_stick_x0 = x; g_stick_y0 = y; g_stick_dx = 0; g_ftap[s] = 0; }
    } else if (e->type == SDL_FINGERMOTION) {
        int s = finger_slot(e->tfinger.fingerId, 0); if (s < 0) return;
        g_fx[s] = x; g_fy[s] = y;
        if (s == g_stick_finger) { float d = (x - g_stick_x0) / (0.16f * g_sh); g_stick_dx = d < -1 ? -1 : d > 1 ? 1 : d; }
    } else {
        int s = finger_slot(e->tfinger.fingerId, 0); if (s < 0) return;
        g_fdown[s] = 0; if (s == g_stick_finger) { g_stick_finger = -1; g_stick_dx = 0; }
    }
}
/* which buttons are held right now: every finger on a button holds it (a thumb can slide from GAS onto DRIFT) */
static void touch_pad(Pad *p) {
    for (int i = 0; i < NBTN; i++) BTN[i].down = 0;
    int on_button[16] = {0};
    for (int s = 0; s < 16; s++) if (g_fdown[s] && s != g_stick_finger)
        for (int i = 0; i < NBTN; i++) if (btn_visible(i)) { float dx = g_fx[s] - bx(i), dy = g_fy[s] - by(i), r = br(i) * 1.12f; if (dx * dx + dy * dy < r * r) { BTN[i].down = 1; on_button[s] = 1; } }
    int any = 0;
    for (int i = 0; i < NBTN; i++) if (BTN[i].down) { any = 1; switch (BTN[i].key) {
        case K_A: p->a = 1; break; case K_B: case K_BACK: p->b = 1; break; case K_ZR: p->zr = 1; p->a = 1; break;
        case K_ZL: p->zl = 1; break; default: break; } }
    { static int was_plus = 0; int now = BTN[4].down; p->plus = now && !was_plus; was_plus = now; }   /* + is a press, not a hold */
    if (g_stick_finger >= 0) { float d = g_stick_dx; if (fabsf(d) < 0.12f) d = 0; p->sx = d < -1 ? -1 : d > 1 ? 1 : d; any = 1; }
    /* a finger anywhere else is a touch on the GamePad's screen, in its 1280 x 720 units */
    for (int s = 0; s < 16; s++) if (g_fdown[s] && s != g_stick_finger && !on_button[s]) {
        int dw = g_sw - 2 * g_ox, dh = g_sh - 2 * g_oy;
        float tx = (g_fx[s] - g_ox) / dw * 1280.0f, ty = (g_fy[s] - g_oy) / dh * 720.0f;
        if (tx >= 0 && tx < 1280 && ty >= 0 && ty < 720) { p->touch = 1; p->tx = tx; p->ty = ty; any = 1; break; } }
    p->source = 1;   /* the phone is always there, like the GamePad */
    (void)any;
}

/* ------------------------------------------------------------------ controllers */
static SDL_GameController *g_gc[4];
static void open_controllers(void) {
    for (int i = 0; i < SDL_NumJoysticks(); i++) if (SDL_IsGameController(i)) {
        int used = 0; SDL_JoystickID id = SDL_JoystickGetDeviceInstanceID(i);
        for (int k = 0; k < 4; k++) if (g_gc[k] && SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(g_gc[k])) == id) used = 1;
        if (used) continue;
        for (int k = 0; k < 4; k++) if (!g_gc[k]) { g_gc[k] = SDL_GameControllerOpen(i); port_log("controller %d: %s", k + 1, SDL_GameControllerName(g_gc[k])); break; }
    }
}
static void controller_pad(int k, Pad *w) {
    SDL_GameController *c = g_gc[k]; memset(w, 0, sizeof *w);
    if (!c || !SDL_GameControllerGetAttached(c)) { if (c) { SDL_GameControllerClose(c); g_gc[k] = NULL; } return; }
    float sx = SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_LEFTX) / 32767.0f, sy = -SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_LEFTY) / 32767.0f;
    if (SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_DPAD_LEFT)) sx = -1;
    if (SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_DPAD_RIGHT)) sx = 1;
    if (SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_DPAD_UP)) sy = 1;
    if (SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_DPAD_DOWN)) sy = -1;
    w->sx = fabsf(sx) < 0.12f ? 0 : (sx < -1 ? -1 : sx > 1 ? 1 : sx); w->sy = fabsf(sy) < 0.12f ? 0 : (sy < -1 ? -1 : sy > 1 ? 1 : sy);
    /* by the letters printed on the buttons (Nintendo, Xbox and PlayStation-style pads all work) */
    w->a = SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_A); w->b = SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_B);
    w->x = SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_X); w->y = SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_Y);
    w->zl = SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_LEFTSHOULDER) || SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_TRIGGERLEFT) > 12000;
    w->zr = SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_RIGHTSHOULDER) || SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_TRIGGERRIGHT) > 12000;
    static int was[4]; int st = SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_START); w->plus = st && !was[k]; was[k] = st;
    w->source = 2;   /* a Pro Controller */
    if (w->a || w->b || w->zr || w->zl || w->plus || w->sx || w->sy) g_touch_mode = 0;
}
static float g_rumble_left[KK_PADS];
void platform_rumble_pad(int slot, float strength, float seconds) {
    if (strength <= 0 || seconds <= 0 || slot < 0 || slot >= KK_PADS) return;
    Uint16 s = (Uint16)(strength > 1 ? 65535 : strength * 65535);
    if (slot == 0) { static SDL_Haptic *h; static int tried; if (!tried) { tried = 1; h = SDL_HapticOpen(0); if (h && SDL_HapticRumbleInit(h) != 0) { SDL_HapticClose(h); h = NULL; } }
        if (h && g_touch_mode) SDL_HapticRumblePlay(h, strength, (Uint32)(seconds * 1000)); }
    else if (g_gc[slot - 1]) SDL_GameControllerRumble(g_gc[slot - 1], s, s, (Uint32)(seconds * 1000));
    g_rumble_left[slot] = seconds;
}
void platform_rumble(float strength, float seconds) { platform_rumble_pad(0, strength, seconds); platform_rumble_pad(1, strength, seconds); }

/* ------------------------------------------------------------------ sound */
static void audio_cb(void *ud, Uint8 *stream, int len) {
    (void)ud; int n = len / 4; static int16_t l[4096], r[4096];
    while (n > 0) { int k = n > 4096 ? 4096 : n; sfx_render(l, r, k); music_mix(l, r, k);
        int16_t *o = (int16_t *)stream; for (int i = 0; i < k; i++) { o[i * 2] = l[i]; o[i * 2 + 1] = r[i]; }
        stream += k * 4; n -= k; }
}

/* ------------------------------------------------------------------ the game's files (Android: unpacked from the app once) */
#ifdef __ANDROID__
static int unpack_content(void) {
    char marker[300]; snprintf(marker, sizeof marker, "%s.version", KK_CONTENT_DIR);
    SDL_RWops *mv = SDL_RWFromFile("content_version.txt", "rb"); char want[64] = {0};
    if (mv) { SDL_RWread(mv, want, 1, sizeof want - 1); SDL_RWclose(mv); }
    FILE *f = fopen(marker, "rb"); char have[64] = {0}; if (f) { fread(have, 1, sizeof have - 1, f); fclose(f); }
    if (want[0] && !strcmp(want, have)) return 1;
    SDL_RWops *lst = SDL_RWFromFile("content_files.txt", "rb"); if (!lst) { port_log("no content list"); return 0; }
    Sint64 n = SDL_RWsize(lst); char *list = malloc((size_t)n + 1); SDL_RWread(lst, list, 1, (size_t)n); list[n] = 0; SDL_RWclose(lst);
    int total = 0; for (char *c = list; *c; c++) if (*c == '\n') total++;
    int done = 0; char *line = strtok(list, "\n"); static char buf[1 << 16];
    while (line) {
        char src[300], dst[400]; snprintf(src, sizeof src, "content/%s", line); snprintf(dst, sizeof dst, "%s%s", KK_CONTENT_DIR, line);
        for (char *p = dst + 1; *p; p++) if (*p == '/') { *p = 0; mkdir(dst, 0755); *p = '/'; }
        SDL_RWops *in = SDL_RWFromFile(src, "rb"); FILE *out = fopen(dst, "wb");
        if (in && out) { size_t k; while ((k = SDL_RWread(in, buf, 1, sizeof buf)) > 0) fwrite(buf, 1, k, out); }
        if (in) SDL_RWclose(in); if (out) fclose(out);
        done++;
        if (done % 20 == 0 || done == total) {   /* a gold bar filling up while the game unpacks itself the first time */
            glBindFramebuffer(GL_FRAMEBUFFER, 0); glDisable(GL_SCISSOR_TEST); glViewport(0, 0, g_sw, g_sh);
            glClearColor(0.03f, 0.03f, 0.1f, 1); glClear(GL_COLOR_BUFFER_BIT); glEnable(GL_SCISSOR_TEST);
            glScissor(g_sw / 5, g_sh / 2 - 12, (int)((g_sw * 3 / 5) * (float)done / (total ? total : 1)), 24); glClearColor(1.0f, 0.82f, 0.35f, 1); glClear(GL_COLOR_BUFFER_BIT);
            glDisable(GL_SCISSOR_TEST); SDL_GL_SwapWindow(g_win); SDL_PumpEvents(); }
        line = strtok(NULL, "\n");
    }
    free(list);
    f = fopen(marker, "wb"); if (f) { fputs(want, f); fclose(f); }
    port_log("unpacked %d files", done);
    return 1;
}
#endif

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    SDL_SetHint(SDL_HINT_ANDROID_TRAP_BACK_BUTTON, "1");
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
    SDL_SetHint(SDL_HINT_MOUSE_TOUCH_EVENTS, "1");
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_GAMECONTROLLER | SDL_INIT_HAPTIC) != 0) { SDL_Log("SDL: %s", SDL_GetError()); return 1; }
    char *pref = SDL_GetPrefPath("Sean", "KingdomKart");
    if (pref) { char p[512]; snprintf(p, sizeof p, "%skingdomkart_log.txt", pref); g_log = fopen(p, "w"); gfx_set_logfile(g_log);
        snprintf(p, sizeof p, "%skingdomkart_save.txt", pref); save_set_path(p); }
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3); SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 0); SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    const char *test = getenv("KK_FRAMES");
#ifdef __ANDROID__
    g_win = SDL_CreateWindow("Kingdom Kart", 0, 0, 0, 0, SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN | SDL_WINDOW_ALLOW_HIGHDPI);
#else
    g_win = SDL_CreateWindow("Kingdom Kart", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, test ? 1560 : 1600, test ? 720 : 740, SDL_WINDOW_OPENGL | SDL_WINDOW_ALLOW_HIGHDPI);
#endif
    if (!g_win) { SDL_Log("window: %s", SDL_GetError()); return 1; }
    g_ctx = SDL_GL_CreateContext(g_win); if (!g_ctx) { SDL_Log("GL: %s", SDL_GetError()); return 1; }
    SDL_GL_SetSwapInterval(test ? 0 : 1);
    if (!kk_gl_load(SDL_GL_GetProcAddress)) return 1;
    layout();
#ifdef __ANDROID__
    unpack_content();
#endif
    overlay_init();
    gfx_log("Kingdom Kart %s starting on %s", KK_VERSION, SDL_GetPlatform());
    int status = gfx_init();
    game_init(status);
    SDL_AudioSpec want, have; memset(&want, 0, sizeof want); want.freq = 48000; want.format = AUDIO_S16SYS; want.channels = 2; want.samples = 1024; want.callback = audio_cb;
    sfx_init(48000); music_init(48000);
    SDL_AudioDeviceID dev = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0); if (dev) SDL_PauseAudioDevice(dev, 0); else port_log("no sound: %s", SDL_GetError());
    open_controllers();

    /* test runs (the build machine): a fixed number of frames at a fixed step, pictures saved every so often */
    int frames_left = test ? atoi(test) : -1; const char *shots = getenv("KK_SHOTS"); int shot_every = getenv("KK_SHOT_EVERY") ? atoi(getenv("KK_SHOT_EVERY")) : 300;
    Uint64 last = SDL_GetPerformanceCounter(); long frame = 0; int running = 1; Pad pads[KK_PADS];
    while (running) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            switch (e.type) {
                case SDL_QUIT: running = 0; break;
                case SDL_FINGERDOWN: case SDL_FINGERUP: case SDL_FINGERMOTION: touch_event(&e); break;
                case SDL_CONTROLLERDEVICEADDED: open_controllers(); break;
                case SDL_WINDOWEVENT: if (e.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) layout(); break;
                case SDL_APP_WILLENTERBACKGROUND: if (dev) SDL_PauseAudioDevice(dev, 1); break;
                case SDL_APP_DIDENTERFOREGROUND: if (dev) SDL_PauseAudioDevice(dev, 0); layout(); break;
                case SDL_KEYDOWN: if (e.key.keysym.sym == SDLK_AC_BACK) { static Uint32 t; t = SDL_GetTicks(); (void)t; } break;
            }
        }
        Uint64 now = SDL_GetPerformanceCounter(); float dt = (float)(now - last) / (float)SDL_GetPerformanceFrequency(); last = now;
        if (dt > 0.1f) dt = 0.1f;
        if (test) dt = 1.0f / 60.0f;
        memset(pads, 0, sizeof pads);
        touch_pad(&pads[0]);
        { const Uint8 *ks = SDL_GetKeyboardState(NULL); if (ks[SDL_SCANCODE_AC_BACK] || ks[SDL_SCANCODE_ESCAPE]) pads[0].b = 1; }
        for (int k = 0; k < 4; k++) controller_pad(k, &pads[1 + k]);
        const char *where = game_where(); g_racing = !strncmp(where, "racing", 6);
        g_shot_now = shots && (frame + 1) % shot_every == 0;
        if (g_shot_now) snprintf(g_shot_path, sizeof g_shot_path, "%s/frame_%06ld.ppm", shots, frame + 1);
        game_frame(pads, KK_PADS, dt);
        frame++;
        if (frames_left > 0 && --frames_left == 0) running = 0;
    }
    if (dev) SDL_CloseAudioDevice(dev);
    game_shutdown();
    if (g_log) fclose(g_log);
    SDL_Quit();
    return 0;
}
