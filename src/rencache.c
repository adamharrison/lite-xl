#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdalign.h>

#include <lauxlib.h>
#include "rencache.h"

/* a cache over the software renderer -- all drawing operations are stored as
** commands when issued. At the end of the frame we write the commands to a grid
** of hash values, take the cells that have changed since the previous frame,
** merge them into dirty rectangles and redraw only those regions */

#define CELLS_X 80
#define CELLS_Y 50
#define CELL_SIZE 96
#define COMMAND_BUF_SIZE (1024 * 512)
#define COMMAND_BARE_SIZE offsetof(Command, text)

enum { SET_CLIP, DRAW_TEXT, DRAW_RECT };

typedef struct {
  int8_t type;
  int8_t tab_size;
  int32_t size;
  RenRect rect;
  RenColor color;
  RenFont *fonts[FONT_FALLBACK_MAX];
  float text_x;
  char text[0];
} Command;

static unsigned cells_buf1[CELLS_X * CELLS_Y];
static unsigned cells_buf2[CELLS_X * CELLS_Y];
static unsigned *cells_prev = cells_buf1;
static unsigned *cells = cells_buf2;
static RenRect rect_buf[CELLS_X * CELLS_Y / 2];
static char command_buf[COMMAND_BUF_SIZE];
static int command_buf_idx;
static RenRect screen_rect;
static bool show_debug;

static inline int min(int a, int b) { return a < b ? a : b; }
static inline int max(int a, int b) { return a > b ? a : b; }


/* 32bit fnv-1a hash */
#define HASH_INITIAL 2166136261

static void hash(unsigned *h, const void *data, int size) {
  const unsigned char *p = data;
  while (size--) {
    *h = (*h ^ *p++) * 16777619;
  }
}


static inline int cell_idx(int x, int y) {
  return x + y * CELLS_X;
}


static inline bool rects_overlap(RenRect a, RenRect b) {
  return b.x + b.width  >= a.x && b.x <= a.x + a.width
      && b.y + b.height >= a.y && b.y <= a.y + a.height;
}

static inline bool rect_encompasses(RenRect a, RenRect b) {
  return a.x <= b.x && a.y <= b.y && 
    a.x + a.width >= b.x + b.width && a.y + a.height >= b.y + b.height;
}

static RenRect intersect_rects(RenRect a, RenRect b) {
  int x1 = max(a.x, b.x);
  int y1 = max(a.y, b.y);
  int x2 = min(a.x + a.width, b.x + b.width);
  int y2 = min(a.y + a.height, b.y + b.height);
  return (RenRect) { x1, y1, max(0, x2 - x1), max(0, y2 - y1) };
}


static RenRect merge_rects(RenRect a, RenRect b) {
  int x1 = min(a.x, b.x);
  int y1 = min(a.y, b.y);
  int x2 = max(a.x + a.width, b.x + b.width);
  int y2 = max(a.y + a.height, b.y + b.height);
  return (RenRect) { x1, y1, x2 - x1, y2 - y1 };
}


static Command* push_command(int type, int size) {
  size_t alignment = alignof(max_align_t) - 1;
  size = (size + alignment) & ~alignment;
  Command *cmd = (Command*) (command_buf + command_buf_idx);
  int n = command_buf_idx + size;
  if (n > COMMAND_BUF_SIZE) {
    fprintf(stderr, "Warning: (" __FILE__ "): exhausted command buffer\n");
    return NULL;
  }
  command_buf_idx = n;
  memset(cmd, 0, size);
  cmd->type = type;
  cmd->size = size;
  return cmd;
}


static bool next_command(Command **prev) {
  if (*prev == NULL) {
    *prev = (Command*) command_buf;
  } else {
    *prev = (Command*) (((char*) *prev) + (*prev)->size);
  }
  return *prev != ((Command*) (command_buf + command_buf_idx));
}


void rencache_show_debug(bool enable) {
  show_debug = enable;
}


void rencache_set_clip_rect(RenRect rect) {
  Command *cmd = push_command(SET_CLIP, COMMAND_BARE_SIZE);
  if (cmd) { cmd->rect = intersect_rects(rect, screen_rect); }
}


void rencache_draw_rect(RenRect rect, RenColor color) {
  if (!rects_overlap(screen_rect, rect) || rect.width == 0 || rect.height == 0) {
    return;
  }
  Command *cmd = push_command(DRAW_RECT, COMMAND_BARE_SIZE);
  if (cmd) {
    cmd->rect = rect;
    cmd->color = color;
  }
}

float rencache_draw_text(lua_State *L, RenFont **fonts, const char *text, float x, int y, RenColor color)
{
  float width = ren_font_group_get_width(fonts, text);
  RenRect rect = { x, y, (int)width, ren_font_group_get_height(fonts) };
  if (rects_overlap(screen_rect, rect)) {
    int sz = strlen(text) + 1;
    Command *cmd = push_command(DRAW_TEXT, COMMAND_BARE_SIZE + sz);
    if (cmd) {
      memcpy(cmd->text, text, sz);
      cmd->color = color;
      memcpy(cmd->fonts, fonts, sizeof(RenFont*)*FONT_FALLBACK_MAX);
      cmd->rect = rect;
      cmd->text_x = x;
      cmd->tab_size = ren_font_group_get_tab_size(fonts);
    }
  }
  return x + width;
}


static void invalidate_overlapping_cells(RenRect r) {
  int x1 = r.x / CELL_SIZE;
  int y1 = r.y / CELL_SIZE;
  int x2 = (r.x + r.width) / CELL_SIZE;
  int y2 = (r.y + r.height) / CELL_SIZE;

  for (int y = y1; y <= y2; y++) {
    for (int x = x1; x <= x2; x++) {
      int idx = cell_idx(x, y);
      cells_prev[idx] = HASH_INITIAL;
    }
  }
}

static RenRect grid_align_rect(RenRect r) {
  return (RenRect){ r.x - (r.x % CELL_SIZE), r.y - (r.y % CELL_SIZE), 
    r.width + (CELL_SIZE - (r.width % CELL_SIZE)), r.height + (CELL_SIZE - (r.height % CELL_SIZE)) };
}

static const int DUMPING_CELL_X = 6;
static const int DUMPING_CELL_Y = 5;

static void update_overlapping_cells(RenRect r, unsigned* buffer, unsigned h) {
  int x1 = r.x / CELL_SIZE;
  int y1 = r.y / CELL_SIZE;
  int x2 = (r.x + r.width) / CELL_SIZE;
  int y2 = (r.y + r.height) / CELL_SIZE;

  for (int y = y1; y <= y2; y++) {
    for (int x = x1; x <= x2; x++) {
      int idx = cell_idx(x, y);
      hash(&buffer[idx], &h, sizeof(h));
    }
  }
}

static void dump_hex_command(Command* cmd) {
  char* start = (char*)cmd;
  char* end = start + cmd->size;
  fprintf(stderr, "CMDDUMP: ");
  while (start++ < end) {
    fprintf(stderr, "%02x", *start);
  }
  fprintf(stderr, "\n");
}

static void dump_commands(int x, int y, const char* prefix) {
  RenRect cr = screen_rect;
  Command* cmd = NULL;
  unsigned h = HASH_INITIAL;
  while (next_command(&cmd)) {
    if (cmd->type == SET_CLIP) { cr = cmd->rect; }
    RenRect r = intersect_rects(cmd->rect, cr);
    if (r.width == 0 || r.height == 0) { continue; }
    if (!rects_overlap(r, (RenRect){ x*CELL_SIZE, y*CELL_SIZE, CELL_SIZE, CELL_SIZE }))
      continue;
    unsigned i = HASH_INITIAL;
    hash(&i, cmd, cmd->size);
    hash(&h, &i, sizeof(i));
    switch (cmd->type) {
      case SET_CLIP:
        fprintf(stderr, "DUMP %s [SET CLIP][%10u][%10u]: %d %d %d %d\n", prefix, h, i, cmd->rect.x, cmd->rect.y, cmd->rect.width, cmd->rect.height);
        break;
      case DRAW_RECT:
        fprintf(stderr, "DUMP %s [DRAW RECT][%10u][%10u]: %d %d %d %d\n", prefix, h, i, cmd->rect.x, cmd->rect.y, cmd->rect.width, cmd->rect.height);
        break;
      case DRAW_TEXT:
        fprintf(stderr, "DUMP %s [DRAW TEXT][%10u][%10u]: %d %d %d %d %f (%u)\n", prefix, h, i, cmd->rect.x, cmd->rect.y, cmd->rect.width, cmd->rect.height, cmd->text_x, *(unsigned*)((float*)&cmd->text_x));
        break;
    }
  }
  fprintf(stderr, "DUMP %s [HASH]: %u %u %u\n\n\n\n", prefix, h, cells_prev[cell_idx(x, y)], cells[cell_idx(x, y)]);
}


/* provide a hint about where to move pixels. if accurate
will make things much faster, if inaccurate, will make things
much slower, but should be entirely unecessary to actually draw
things correctly. used primarily for scrolling enhancement.

src should be identical in size to dst. src and dst should also
be adjacent.

should be called before rencache_begin_frame  */
int rencache_blit_hint(RenRect src, RenRect dst) {
  if (src.width != dst.width || src.height != dst.height ||
    !(src.x + src.width >= dst.x || dst.x + dst.width >= src.x) ||
    !(src.y + src.height >= dst.y || dst.y + dst.height >= src.y)) {
      return -1;
  }
  RenRect grid_aligned_dst = grid_align_rect(dst);
  ren_blit_rect(src, dst);
  ren_update_rects(&grid_aligned_dst, 1);
  
  RenRect cr = screen_rect;
  RenRect tcr = screen_rect;
  Command *cmd = NULL;
  // go through each command, and for any that contains commands that are entirely contained within the hint,
  // recompute their hash values, as if we just redrew that cell.
  RenRect merged = grid_align_rect(merge_rects(src, dst));
  invalidate_overlapping_cells(merged);
  
  //fprintf(stderr, "CELL PREVA: %u\n", cells_prev[cell_idx(DUMPING_CELL_X, DUMPING_CELL_Y)]);
  dump_commands(DUMPING_CELL_X, DUMPING_CELL_Y, "PREBLIT");
  while (next_command(&cmd)) {
    if (cmd->type == SET_CLIP) { cr = cmd->rect; tcr = cr; }
    RenRect r = intersect_rects(cmd->rect, cr);
    if (r.width == 0 || r.height == 0) { continue; }
    if (rect_encompasses(src, r)) {
      if (cmd->type == DRAW_TEXT && dst.x - src.x)
        cmd->text_x += (dst.x - src.x);
      cmd->rect.x += (dst.x - src.x);
      cmd->rect.y += (dst.y - src.y);
      if (cmd->type == SET_CLIP)
        tcr = cmd->rect;
      r = intersect_rects(cmd->rect, tcr);
    } else if (!rects_overlap(grid_aligned_dst, r)) {
      continue;
    }
    unsigned h = HASH_INITIAL;
    hash(&h, cmd, cmd->size);
    update_overlapping_cells(r, cells_prev, h);
    if (rects_overlap(r, (RenRect){ DUMPING_CELL_X*CELL_SIZE, DUMPING_CELL_Y*CELL_SIZE, CELL_SIZE, CELL_SIZE })) {
      fprintf(stderr, "WAT: %d %u %f %u (%u)\n", cmd->type, cells_prev[cell_idx(DUMPING_CELL_X, DUMPING_CELL_Y)], cmd->text_x, h, *(unsigned*)((float*)&cmd->text_x));
    }
  }
  //fprintf(stderr, "CELL PREVB: %u\n", cells_prev[cell_idx(DUMPING_CELL_X, DUMPING_CELL_Y)]);
  dump_commands(DUMPING_CELL_X, DUMPING_CELL_Y, "POSTBLIT");
  return 0;
}


void rencache_invalidate(void) {
  memset(cells_prev, 0xff, sizeof(cells_buf1));
}


void rencache_begin_frame(lua_State *L) {
  /* reset all cells if the screen width/height has changed */
  int w, h;
  ren_get_size(&w, &h);
  if (screen_rect.width != w || h != screen_rect.height) {
    screen_rect.width = w;
    screen_rect.height = h;
    rencache_invalidate();
  }
  command_buf_idx = 0;
}


static void push_rect(RenRect r, int *count) {
  /* try to merge with existing rectangle */
  for (int i = *count - 1; i >= 0; i--) {
    RenRect *rp = &rect_buf[i];
    if (rects_overlap(*rp, r)) {
      *rp = merge_rects(*rp, r);
      return;
    }
  }
  /* couldn't merge with previous rectangle: push */
  rect_buf[(*count)++] = r;
}


void rencache_end_frame(lua_State *L) {
  /* update cells from commands */
  Command *cmd = NULL;
  RenRect cr = screen_rect;
  while (next_command(&cmd)) {
    if (cmd->type == SET_CLIP) { cr = cmd->rect; }
    RenRect r = intersect_rects(cmd->rect, cr);
    if (r.width == 0 || r.height == 0) { continue; }
    unsigned h = HASH_INITIAL;
    hash(&h, cmd, cmd->size);
    update_overlapping_cells(r, cells, h);
  }

  /* push rects for all cells changed from last frame, reset cells */
  int rect_count = 0;
  int max_x = screen_rect.width / CELL_SIZE + 1;
  int max_y = screen_rect.height / CELL_SIZE + 1;
  for (int y = 0; y < max_y; y++) {
    for (int x = 0; x < max_x; x++) {
      /* compare previous and current cell for change */
      int idx = cell_idx(x, y);
      if (cells[idx] != cells_prev[idx]) {
        push_rect((RenRect) { x, y, 1, 1 }, &rect_count);
      }
      cells_prev[idx] = HASH_INITIAL;
    }
  }

  /* expand rects from cells to pixels */
  for (int i = 0; i < rect_count; i++) {
    RenRect *r = &rect_buf[i];
    r->x *= CELL_SIZE;
    r->y *= CELL_SIZE;
    r->width *= CELL_SIZE;
    r->height *= CELL_SIZE;
    *r = intersect_rects(*r, screen_rect);
  }

  /* redraw updated regions */
  for (int i = 0; i < rect_count; i++) {
    /* draw */
    RenRect r = rect_buf[i];
    ren_set_clip_rect(r);

    cmd = NULL;
    while (next_command(&cmd)) {
      switch (cmd->type) {
        case SET_CLIP:
          ren_set_clip_rect(intersect_rects(cmd->rect, r));
          break;
        case DRAW_RECT:
          ren_draw_rect(cmd->rect, cmd->color);
          break;
        case DRAW_TEXT:
          ren_font_group_set_tab_size(cmd->fonts, cmd->tab_size);
          ren_draw_text(cmd->fonts, cmd->text, cmd->text_x, cmd->rect.y, cmd->color);
          break;
      }
    }

    if (show_debug) {
      RenColor color = { rand(), rand(), rand(), 50 };
      ren_draw_rect(r, color);
    }
  }

  /* update dirty rects */
  if (rect_count > 0) {
    ren_update_rects(rect_buf, rect_count);
    //fprintf(stderr, "CELL PREVC: %u\n", cells[cell_idx(DUMPING_CELL_X, DUMPING_CELL_Y)]);
    dump_commands(DUMPING_CELL_X, DUMPING_CELL_Y, "DIRTY");
  }

  /* swap cell buffer and reset */
  unsigned *tmp = cells;
  cells = cells_prev;
  cells_prev = tmp;
}
