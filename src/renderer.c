#include <stdio.h>
#include <stdbool.h>
#include <assert.h>
#include <math.h>
#include "renderer.h"
#include "font_renderer.h"

#define MAX_GLYPHSET 256
#define REPLACEMENT_CHUNK_SIZE 8

struct RenImage {
  RenColor *pixels;
  int width, height;
};

struct GlyphSet {
  FR_Bitmap *image;
  FR_Bitmap_Glyph_Metrics glyphs[256];
};
typedef struct GlyphSet GlyphSet;

/* The field "padding" below must be there just before GlyphSet *sets[MAX_GLYPHSET]
   because the field "sets" can be indexed and writted with an index -1. For this
   reason the "padding" field must be there but is never explicitly used. */
struct RenFont {
  GlyphSet *padding;
  GlyphSet *sets[MAX_GLYPHSET];
  float size;
  int height;
  int space_advance;
  FR_Renderer *renderer;
};


static SDL_Window *window;
static FR_Clip_Area clip;

static void* check_alloc(void *ptr) {
  if (!ptr) {
    fprintf(stderr, "Fatal error: memory allocation failed\n");
    exit(EXIT_FAILURE);
  }
  return ptr;
}


static const char* utf8_to_codepoint(const char *p, unsigned *dst) {
  unsigned res, n;
  switch (*p & 0xf0) {
    case 0xf0 :  res = *p & 0x07;  n = 3;  break;
    case 0xe0 :  res = *p & 0x0f;  n = 2;  break;
    case 0xd0 :
    case 0xc0 :  res = *p & 0x1f;  n = 1;  break;
    default   :  res = *p;         n = 0;  break;
  }
  while (n--) {
    res = (res << 6) | (*(++p) & 0x3f);
  }
  *dst = res;
  return p + 1;
}


void ren_init(SDL_Window *win) {
  assert(win);
  window = win;
  SDL_Surface *surf = SDL_GetWindowSurface(window);
  ren_set_clip_rect( (RenRect) { 0, 0, surf->w, surf->h } );
}


void ren_update_rects(RenRect *rects, int count) {
  SDL_UpdateWindowSurfaceRects(window, (SDL_Rect*) rects, count);
  static bool initial_frame = true;
  if (initial_frame) {
    SDL_ShowWindow(window);
    initial_frame = false;
  }
}


void ren_set_clip_rect(RenRect rect) {
  clip.left   = rect.x;
  clip.top    = rect.y;
  clip.right  = rect.x + rect.width;
  clip.bottom = rect.y + rect.height;
}


void ren_get_size(int *x, int *y) {
  SDL_Surface *surf = SDL_GetWindowSurface(window);
  *x = surf->w;
  *y = surf->h;
}


RenImage* ren_new_image(int width, int height) {
  assert(width > 0 && height > 0);
  RenImage *image = malloc(sizeof(RenImage) + width * height * sizeof(RenColor));
  check_alloc(image);
  image->pixels = (void*) (image + 1);
  image->width = width;
  image->height = height;
  return image;
}

void ren_free_image(RenImage *image) {
  free(image);
}

static GlyphSet* load_glyphset(RenFont *font, int idx) {
  GlyphSet *set = check_alloc(calloc(1, sizeof(GlyphSet)));

  set->image = FR_Bake_Font_Bitmap(font->renderer, font->height, idx << 8, 256, set->glyphs);
  check_alloc(set->image);

  return set;
}


static GlyphSet* get_glyphset(RenFont *font, int codepoint) {
  int idx = (codepoint >> 8) % MAX_GLYPHSET;
  if (!font->sets[idx]) {
    font->sets[idx] = load_glyphset(font, idx);
  }
  return font->sets[idx];
}


RenFont* ren_load_font(const char *filename, float size, unsigned int renderer_flags) {
  RenFont *font = NULL;

  /* init font */
  font = check_alloc(calloc(1, sizeof(RenFont)));
  font->size = size;

  unsigned int fr_renderer_flags = 0;
  if ((renderer_flags & RenFontAntialiasingMask) == RenFontSubpixel) {
    fr_renderer_flags |= FR_SUBPIXEL;
  }
  if ((renderer_flags & RenFontHintingMask) == RenFontHintingSlight) {
    fr_renderer_flags |= (FR_HINTING | FR_PRESCALE_X);
  } else if ((renderer_flags & RenFontHintingMask) == RenFontHintingFull) {
    fr_renderer_flags |= FR_HINTING;
  }
  font->renderer = FR_Renderer_New(fr_renderer_flags);
  if (FR_Load_Font(font->renderer, filename)) {
    free(font);
    return NULL;
  }
  font->height = FR_Get_Font_Height(font->renderer, size);

  FR_Bitmap_Glyph_Metrics *gs = get_glyphset(font, ' ')->glyphs;
  font->space_advance = gs[' '].xadvance;

  /* make tab and newline glyphs invisible */
  FR_Bitmap_Glyph_Metrics *g = get_glyphset(font, '\n')->glyphs;
  g['\t'].x1 = g['\t'].x0;
  g['\n'].x1 = g['\n'].x0;

  font->replace_table.size = 0;
  font->replace_table.replacements = NULL;

  return font;
}


void ren_free_font(RenFont *font) {
  for (int i = 0; i < MAX_GLYPHSET; i++) {
    GlyphSet *set = font->sets[i];
    if (set) {
      FR_Bitmap_Free(set->image);
      free(set);
    }
  }
  free(font->replace_table.replacements);
  FR_Renderer_Free(font->renderer);
  free(font);
}


void ren_font_clear_replacements(RenFont *font) {
  free(font->replace_table.replacements);
  font->replace_table.replacements = NULL;
  font->replace_table.size = 0;
}


void ren_font_add_replacement(RenFont *font, const char *src, const char *dst, RenColor *color) {
  int table_size = font->replace_table.size;
  if (table_size % REPLACEMENT_CHUNK_SIZE == 0) {
    CPReplace *old_replacements = font->replace_table.replacements;
    const int new_size = (table_size / REPLACEMENT_CHUNK_SIZE + 1) * REPLACEMENT_CHUNK_SIZE;
    font->replace_table.replacements = malloc(new_size * sizeof(CPReplace));
    if (!font->replace_table.replacements) {
      font->replace_table.replacements = old_replacements;
      return;
    }
    memcpy(font->replace_table.replacements, old_replacements, table_size * sizeof(CPReplace));
    free(old_replacements);
  }
  CPReplace *rep = &font->replace_table.replacements[table_size];
  utf8_to_codepoint(src, &rep->codepoint_src);
  utf8_to_codepoint(dst, &rep->codepoint_dst);
  if (color) {
    rep->replace_color = true;
    rep->color = (FR_Color) { .r = color->r, .g = color->g, .b = color->b };
  } else {
    rep->replace_color = false;
    rep->color = (FR_Color) { .r = 0, .g = 0, .b = 0 };
  }
  font->replace_table.size = table_size + 1;
}


void ren_set_font_tab_size(RenFont *font, int n) {
  GlyphSet *set = get_glyphset(font, '\t');
  set->glyphs['\t'].xadvance = font->space_advance * n;
}


int ren_get_font_tab_size(RenFont *font) {
  GlyphSet *set = get_glyphset(font, '\t');
  return set->glyphs['\t'].xadvance / font->space_advance;
}


int ren_get_font_width(RenFont *font, const char *text, int *subpixel_scale) {
  int x = 0;
  const char *p = text;
  unsigned codepoint;
  while (*p) {
    p = utf8_to_codepoint(p, &codepoint);
    GlyphSet *set = get_glyphset(font, codepoint);
    FR_Bitmap_Glyph_Metrics *g = &set->glyphs[codepoint & 0xff];
    x += g->xadvance;
  }
  if (subpixel_scale) {
    *subpixel_scale = FR_Subpixel_Scale(font->renderer);
  }
  return x;
}


int ren_get_font_height(RenFont *font) {
  return font->height;
}


static inline RenColor blend_pixel(RenColor dst, RenColor src) {
  int ia = 0xff - src.a;
  dst.r = ((src.r * src.a) + (dst.r * ia)) >> 8;
  dst.g = ((src.g * src.a) + (dst.g * ia)) >> 8;
  dst.b = ((src.b * src.a) + (dst.b * ia)) >> 8;
  return dst;
}


static inline RenColor blend_pixel2(RenColor dst, RenColor src, RenColor color) {
  src.a = (src.a * color.a) >> 8;
  int ia = 0xff - src.a;
  dst.r = ((src.r * color.r * src.a) >> 16) + ((dst.r * ia) >> 8);
  dst.g = ((src.g * color.g * src.a) >> 16) + ((dst.g * ia) >> 8);
  dst.b = ((src.b * color.b * src.a) >> 16) + ((dst.b * ia) >> 8);
  return dst;
}


#define rect_draw_loop(expr)        \
  for (int j = y1; j < y2; j++) {   \
    for (int i = x1; i < x2; i++) { \
      *d = expr;                    \
      d++;                          \
    }                               \
    d += dr;                        \
  }

void ren_draw_rect(RenRect rect, RenColor color) {
  if (color.a == 0) { return; }

  int x1 = rect.x < clip.left ? clip.left : rect.x;
  int y1 = rect.y < clip.top  ? clip.top  : rect.y;
  int x2 = rect.x + rect.width;
  int y2 = rect.y + rect.height;
  x2 = x2 > clip.right  ? clip.right  : x2;
  y2 = y2 > clip.bottom ? clip.bottom : y2;

  SDL_Surface *surf = SDL_GetWindowSurface(window);
  RenColor *d = (RenColor*) surf->pixels;
  d += x1 + y1 * surf->w;
  int dr = surf->w - (x2 - x1);

  if (color.a == 0xff) {
    rect_draw_loop(color);
  } else {
    rect_draw_loop(blend_pixel(*d, color));
  }
}

void ren_draw_image(RenImage *image, RenRect *sub, int x, int y, RenColor color) {
  if (color.a == 0) { return; }

  int n;
  if ((n = clip.left - x) > 0) { sub->width  -= n; sub->x += n; x += n; }
  if ((n = clip.top  - y) > 0) { sub->height -= n; sub->y += n; x += n; }
  if ((n = x + sub->width  - clip.right ) > 0) { sub->width  -= n; }
  if ((n = y + sub->height - clip.bottom) > 0) { sub->height -= n; }

  if (sub->width <= 0 || sub->height <= 0) {
    return;
  }

  /* draw */
  SDL_Surface *surf = SDL_GetWindowSurface(window);
  RenColor *s = image->pixels;
  RenColor *d = (RenColor*) surf->pixels;
  s += sub->x + sub->y * image->width;
  d += x + y * surf->w;
  int sr = image->width - sub->width;
  int dr = surf->w - sub->width;

  for (int j = 0; j < sub->height; j++) {
    for (int i = 0; i < sub->width; i++) {
      *d = blend_pixel2(*d, *s, color);
      d++;
      s++;
    }
    d += dr;
    s += sr;
  }
}


static unsigned codepoint_replace(CPReplaceTable *rep_table, unsigned codepoint) {
  for (int i = 0; i < rep_table->size; i++) {
    const CPReplace *rep = &rep_table->replacements[i];
    if (codepoint == rep->codepoint_src) {
      return rep->codepoint_dst;
    }
  }
  return codepoint;
}


void ren_draw_text_subpixel_repl(RenFont *font, const char *text, int x_subpixel, int y, RenColor color,
  CPReplaceTable *replacements, RenColor replace_color)
{
  const char *p = text;
  unsigned codepoint;
  SDL_Surface *surf = SDL_GetWindowSurface(window);
  const FR_Color color_fr = { .r = color.r, .g = color.g, .b = color.b };
  while (*p) {
    FR_Color color_rep;
    p = utf8_to_codepoint(p, &codepoint);
    GlyphSet *set = get_glyphset(font, codepoint);
    FR_Bitmap_Glyph_Metrics *g = &set->glyphs[codepoint & 0xff];
    const int xadvance_original_cp = g->xadvance;
    if (replacements) {
      codepoint = codepoint_replace(replacements, codepoint);
      set = get_glyphset(font, codepoint);
      g = &set->glyphs[codepoint & 0xff];
      color_rep = (FR_Color) { .r = replace_color.r, .g = replace_color.g, .b = replace_color.b};
    } else {
      color_rep = color_fr;
    }
    if (color.a != 0) {
      FR_Blend_Glyph(font->renderer, &clip,
        x_subpixel, y, (uint8_t *) surf->pixels, surf->w, set->image, g, color_rep);
    }
    x_subpixel += xadvance_original_cp;
  }
}

void ren_draw_text_subpixel(RenFont *font, const char *text, int x_subpixel, int y, RenColor color) {
  ren_draw_text_subpixel_repl(font, text, x_subpixel, y, color, NULL, (RenColor) {0})
}


void ren_draw_text(RenFont *font, const char *text, int x, int y, RenColor color) {
  const int subpixel_scale = FR_Subpixel_Scale(font->renderer);
  ren_draw_text_subpixel_repl(font, text, subpixel_scale * x, y, color, NULL, (RenColor) {0});
}


void ren_draw_text_repl(RenFont *font, const char *text, int x, int y, RenColor color,
  CPReplaceTable *replacements, RenColor replace_color)
{
  const int subpixel_scale = FR_Subpixel_Scale(font->renderer);
  ren_draw_text_subpixel_repl(font, text, subpixel_scale * x, y, color, replacements, replace_color);
}


int ren_font_subpixel_round(int width, int subpixel_scale, int orientation) {
  int w_mult;
  if (orientation < 0) {
    w_mult = width;
  } else if (orientation == 0) {
    w_mult = width + subpixel_scale / 2;
  } else {
    w_mult = width + subpixel_scale - 1;
  }
  return w_mult / subpixel_scale;
}


int ren_get_font_subpixel_scale(RenFont *font) {
  return FR_Subpixel_Scale(font->renderer);
}
