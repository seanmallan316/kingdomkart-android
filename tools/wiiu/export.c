// export.c - reads the Wii U game's own code and data (seanmallan316/kingdomkart) and writes it out as JSON for
// the Android version, so both games use exactly the same roads, scenery, characters, karts, story map and cups.
// Built and run by tools/wiiu/sync.sh with the Wii U source next to it.
#include "world/theme.h"
#include "sim/race.h"
#include "game/save.h"
#include "game/cupstory.h"
#include "game/storymap_h.h"
#include "gen_story.h"      /* SM_NODE / SM_EDGE / SM_TRIP, cut out of game/storymode.h by sync.sh */
#include "gen_cups.h"       /* CUPS, cut out of game/view.c by sync.sh */
#include <stdio.h>
#include <string.h>
#include <math.h>

static FILE *f;
static void js(const char *s) {   /* a JSON string */
    fputc('"', f);
    for (; s && *s; s++) { if (*s == '"' || *s == '\\') fputc('\\', f); if (*s == '\n') { fputs("\\n", f); continue; } fputc(*s, f); }
    fputc('"', f);
}
static void fl(float v) { if (v != v || isinf(v)) v = 0; fprintf(f, "%.4g", v); }
static void farr(const char *key, const float *v, int n, int stride, int last) {
    fprintf(f, "\"%s\":[", key); for (int i = 0; i < n; i++) { if (i) fputc(',', f); fl(v[i * stride]); } fprintf(f, "]%s", last ? "" : ",");
}

static void track_json(int di) {
    const TrackDef *d = &TRACK_DEFS[di];
    static Track t; track_from_def(&t, d);
    static float tmp[TRACK_MAX_SAMPLES * 2];
    fprintf(f, "{\"name\":"); js(d->name);
    fprintf(f, ",\"laps\":%d,\"n\":%d,\"length\":", d->laps, t.n); fl(t.length);
    fprintf(f, ",\"sky\":["); fl(d->sky_r); fputc(',', f); fl(d->sky_g); fputc(',', f); fl(d->sky_b);
    fprintf(f, "],\"fog\":["); fl(d->fog_r); fputc(',', f); fl(d->fog_g); fputc(',', f); fl(d->fog_b); fputc(',', f); fl(d->fog_start); fputc(',', f); fl(d->fog_end);
    fprintf(f, "],\"light\":["); fl(d->light_x); fputc(',', f); fl(d->light_y); fputc(',', f); fl(d->light_z); fputc(',', f); fl(d->ambient);
    fprintf(f, "],\"sun\":["); fl(d->sun_r); fputc(',', f); fl(d->sun_g); fputc(',', f); fl(d->sun_b);
    fprintf(f, "],\"glow\":["); fl(d->glow_r); fputc(',', f); fl(d->glow_g); fputc(',', f); fl(d->glow_b);
    fprintf(f, "],\"night\":%d,\"tex\":[", d->night); js(d->tex_road); fputc(',', f); js(d->tex_dirt); fputc(',', f); js(d->tex_grass); fputc(',', f); js(d->tex_wall); fputc(',', f); js(d->tex_sky);
    fprintf(f, "],\"prefix\":"); js(d->prefix);
    fprintf(f, ",\"star\":["); fl(d->star_x); fputc(',', f); fl(d->star_y); fputc(',', f); fl(d->star_z); fputc(',', f); fl(d->star_size);
    fprintf(f, "],\"finale\":"); js(d->finale_img ? d->finale_img : "");
    fprintf(f, ",\"finale_idx\":%d,\"finale_w\":", d->finale_img ? track_def_idx(&t, d->finale_idx) : -1); fl(d->finale_w); fprintf(f, ",\"finale_h\":"); fl(d->finale_h);
    fprintf(f, ",\"bonus\":%d,\"water\":%d,\"water_y\":", d->bonus, d->water); fl(t.water_y > -1e8f ? t.water_y : -1000);
    fprintf(f, ",\"grid_idx\":%d,\"shortcut\":[%d,%d,%d],\"widen\":", t.grid_idx, t.shortcut_from, t.shortcut_to, t.shortcut_side); fl(t.widen);
    fprintf(f, ",\"checkpoints\":["); for (int c = 0; c < TRACK_CHECKPOINTS; c++) fprintf(f, "%s%d", c ? "," : "", t.checkpoint[c]); fprintf(f, "],");
    farr("x", &t.s[0].x, t.n, sizeof(TrackSample) / sizeof(float), 0);
    farr("y", &t.s[0].y, t.n, sizeof(TrackSample) / sizeof(float), 0);
    farr("z", &t.s[0].z, t.n, sizeof(TrackSample) / sizeof(float), 0);
    farr("width", &t.s[0].width, t.n, sizeof(TrackSample) / sizeof(float), 0);
    farr("bank", &t.s[0].bank, t.n, sizeof(TrackSample) / sizeof(float), 0);
    farr("dist", &t.s[0].dist, t.n, sizeof(TrackSample) / sizeof(float), 0);
    for (int i = 0; i < t.n; i++) { tmp[i] = t.field[i][0]; tmp[t.n + i] = t.field[i][1]; }
    farr("field_l", tmp, t.n, 1, 0); farr("field_r", tmp + t.n, t.n, 1, 0);
    fprintf(f, "\"pads\":["); for (int i = 0; i < t.npad; i++) { fprintf(f, "%s{\"idx\":%d,\"lat\":", i ? "," : "", t.pad[i].idx); fl(t.pad[i].lateral); fprintf(f, ",\"half\":"); fl(t.pad[i].halfw); fprintf(f, ",\"kind\":\"%s\"}", t.pad[i].kind == PAD_BOOST ? "boost" : "bounce"); }
    fprintf(f, "],\"movers\":["); for (int i = 0; i < t.nmover; i++) { const Mover *m = &t.mover[i]; fprintf(f, "%s{\"img\":", i ? "," : ""); js(m->img); fprintf(f, ",\"idx\":%d,\"lat\":", m->idx); fl(m->lateral);
        fprintf(f, ",\"amp\":"); fl(m->amp); fprintf(f, ",\"speed\":"); fl(m->speed); fprintf(f, ",\"phase\":"); fl(m->phase); fprintf(f, ",\"radius\":"); fl(m->radius); fprintf(f, ",\"height\":"); fl(m->height); fputc('}', f); }
    fprintf(f, "],\"coins\":["); for (int i = 0; i < t.ncoin; i++) { fprintf(f, "%s[%d,", i ? "," : "", t.coin[i].idx); fl(t.coin[i].lateral); fputc(']', f); }
    fprintf(f, "],\"tunnels\":["); for (int i = 0; i < t.ntunnel; i++) { fprintf(f, "%s[%d,%d,", i ? "," : "", t.tunnel[i].from, t.tunnel[i].to); fl(t.tunnel[i].height); fputc(']', f); }
    fprintf(f, "],\"gems\":["); for (int i = 0; i < t.ngem; i++) { fprintf(f, "%s[%d,", i ? "," : "", t.gem[i].idx); fl(t.gem[i].lateral); fprintf(f, ",%d]", t.gem[i].color); }
    fprintf(f, "],\"obstacles\":["); for (int i = 0; i < t.nobst; i++) { fprintf(f, "%s[", i ? "," : ""); fl(t.obst[i].x); fputc(',', f); fl(t.obst[i].z); fputc(',', f); fl(t.obst[i].r); fputc(']', f); }
    /* scenery exactly where the Wii U stands it */
    fprintf(f, "],\"scenery\":[");
    for (int i = 0; i < d->nscenery; i++) {
        const Scenery *sc = &d->scenery[i]; int idx = track_def_idx(&t, sc->idx) % t.n;
        float r = track_scenery_radius(sc->img, sc->height);
        float lat = track_scenery_lat(&t, idx, sc->side, r > 0 ? r : 0.6f);
        const TrackSample *s = &t.s[idx];
        fprintf(f, "%s{\"img\":", i ? "," : ""); js(sc->img); fprintf(f, ",\"idx\":%d,\"lat\":", idx); fl(lat);
        fprintf(f, ",\"side\":"); fl(sc->side); fprintf(f, ",\"x\":"); fl(s->x + s->nx * lat); fprintf(f, ",\"z\":"); fl(s->z + s->nz * lat);
        fprintf(f, ",\"y\":"); fl(track_surface_height(&t, idx, lat)); fprintf(f, ",\"h\":"); fl(sc->height * (sc->img[0] == '@' ? 1.0f : 1.0f));
        fprintf(f, ",\"glow\":"); fl(sc->glow); fprintf(f, ",\"r\":"); fl(r); fputc('}', f);
    }
    fprintf(f, "]}");
}

int main(int argc, char **argv) {
    const char *dir = argc > 1 ? argv[1] : ".";
    char path[512];
    snprintf(path, sizeof path, "%s/tracks.json", dir); f = fopen(path, "w");
    fprintf(f, "[");
    for (int di = 0; di < NUM_TRACK_DEFS; di++) { if (di) fprintf(f, ",\n"); track_json(di); fprintf(stderr, "road %d: %s\n", di, TRACK_DEFS[di].name); }
    fprintf(f, "]\n"); fclose(f);

    snprintf(path, sizeof path, "%s/game.json", dir); f = fopen(path, "w");
    fprintf(f, "{\"characters\":[");
    for (int i = 0; i < NCHARS; i++) { const Character *c = &CHARACTERS[i]; fprintf(f, "%s{\"name\":", i ? "," : ""); js(c->name); fprintf(f, ",\"short\":"); js(c->short_name);
        fprintf(f, ",\"stats\":["); fl(c->st.top_speed); fputc(',', f); fl(c->st.accel); fputc(',', f); fl(c->st.handling); fputc(',', f); fl(c->st.weight);
        fprintf(f, "],\"color\":["); fl(c->r); fputc(',', f); fl(c->g); fputc(',', f); fl(c->b); fprintf(f, "],\"bonus\":%d}", c->bonus); }
    fprintf(f, "],\n\"karts\":[");
    for (int i = 0; i < NSTYLES; i++) { const KartStyle *k = &KART_STYLES[i]; fprintf(f, "%s{\"name\":", i ? "," : ""); js(k->name);
        fprintf(f, ",\"mul\":["); fl(k->mul.top_speed); fputc(',', f); fl(k->mul.accel); fputc(',', f); fl(k->mul.handling); fputc(',', f); fl(k->mul.weight); fprintf(f, "]}"); }
    fprintf(f, "],\n\"cups\":[");
    for (int c = 0; c < NCUPS; c++) { const Cup *cp = &CUPS[c]; fprintf(f, "%s{\"name\":", c ? "," : ""); js(cp->name); fprintf(f, ",\"sub\":"); js(cp->sub); fprintf(f, ",\"roads\":[");
        for (int r = 0; r < cp->n; r++) fprintf(f, "%s%d", r ? "," : "", cp->roads[r]); fprintf(f, "],\"needs_heaven\":%d}", cp->needs_heaven); }
    fprintf(f, "],\n\"par\":["); for (int r = 0; r < SAVE_MAX_ROADS; r++) { if (r) fputc(',', f); fl(save_par_time(r)); }
    fprintf(f, "],\n\"unlocks\":["); for (int b = 0; b < UNLOCK_COUNT; b++) { if (b) fputc(',', f); js(unlock_name(1 << b)); }
    fprintf(f, "],\n\"cup_stories\":[");
    for (int pass = 0; pass < 2; pass++) for (int i = 0; i < 22; i++) { const CupStory *s = pass ? &GLORY_STORIES[i] : &CUP_STORIES[i];
        fprintf(f, "%s{\"glory\":%d,\"title\":", pass || i ? "," : "", pass); js(s->title); fprintf(f, ",\"place\":"); js(s->place); fprintf(f, ",\"set\":%d,\"guest\":%d,\"story\":[", s->set, s->guest);
        js(s->story[0]); fputc(',', f); js(s->story[1]); fprintf(f, "],\"verse\":"); js(s->verse); fprintf(f, ",\"ref\":"); js(s->ref); fprintf(f, ",\"lesson\":"); js(s->lesson); fputc('}', f); }
    fprintf(f, "],\n\"story\":{\"nodes\":[");
    for (int i = 0; i < SM_NODES; i++) { const SmNode *s = &SM_NODE[i]; fprintf(f, "%s{\"name\":", i ? "," : ""); js(s->name); fprintf(f, ",\"px\":"); fl(s->px); fprintf(f, ",\"py\":"); fl(s->py);
        fprintf(f, ",\"track\":%d,\"verse\":", s->track); js(s->verse); fputc('}', f); }
    fprintf(f, "],\"edges\":[");
    for (int i = 0; i < SM_NEDGE; i++) { const SmEdge *e = &SM_EDGE[i]; fprintf(f, "%s{\"a\":%d,\"b\":%d,\"p\":[", i ? "," : "", e->a, e->b);
        for (int k = 0; k < e->n; k++) { fprintf(f, "%s[", k ? "," : ""); fl(e->p[k][0]); fputc(',', f); fl(e->p[k][1]); fputc(']', f); } fprintf(f, "]}"); }
    fprintf(f, "],\"trips\":[");
    for (int i = 0; i < NCHARS; i++) { const SmTrip *t = &SM_TRIP[i]; fprintf(f, "%s[", i ? "," : "");
        for (int k = 0; k < t->n; k++) { fprintf(f, "%s{\"node\":%d,\"line\":", k ? "," : "", t->s[k].node); js(t->s[k].line); fputc('}', f); } fputc(']', f); }
    fprintf(f, "],\"height_nx\":%d,\"height_nz\":%d,\"height\":[", SMH_NX, SMH_NZ);
    for (int z = 0; z <= SMH_NZ; z++) for (int x = 0; x <= SMH_NX; x++) fprintf(f, "%s%d", z || x ? "," : "", SMH[z][x]);
    fprintf(f, "]}}\n"); fclose(f);
    fprintf(stderr, "export done\n");
    return 0;
}

/* the Wii U's log function, which save.c calls; not needed here */
#include <stdarg.h>
void gfx_log(const char *fmt, ...) { (void)fmt; }
