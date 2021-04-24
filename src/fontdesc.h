#ifndef FONT_DESC_H
#define FONT_DESC_H

#include "renderer.h"

struct FontScaled {
  RenFont *font;
  short int scale;
};
typedef struct FontScaled FontScaled;

#define FONT_SCALE_ARRAY_MAX 2

struct FontDesc {
  char *filename;
  float size;
  unsigned int options;
  short int tab_size;
  FontScaled fonts_scale[FONT_SCALE_ARRAY_MAX];
  int fonts_scale_length;
};
typedef struct FontDesc FontDesc;

#endif

