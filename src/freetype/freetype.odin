package freetype

import "core:c"

when ODIN_OS == .Windows {
  foreign import freetype {
    "freetype291.lib",
  }
} else when ODIN_OS == .Linux {
  foreign import freetype {
    "system:freetype",
  }
}

Long  :: c.long
ULong :: c.ulong

@(link_prefix="FT_", default_calling_convention="c")
foreign freetype {
  Init_FreeType   :: proc(library: ^Library) -> Error ---
  Done_FreeType   :: proc(library: Library) -> Error ---

  New_Face        :: proc(library: Library, filepathname: cstring, face_index: Long, aface: ^Face) -> Error ---
  New_Memory_Face :: proc(library: Library, file_base: ^byte, file_size: Long, face_index: Long, aface: ^Face) -> Error ---
  Done_Face       :: proc(face: Face) -> Error ---

  Set_Char_Size   :: proc(face: Face, char_width, char_height: F26Dot6, horz_resolution, vert_resolution: u32) -> Error ---
  Set_Pixel_Sizes :: proc(face: Face, pixel_width, pixel_height: u32) -> Error ---

  Get_First_Char  :: proc(face: Face, index: ^u32) -> c.ulong ---
  Get_Next_Char   :: proc(face: Face, character: c.ulong, index: ^u32) -> c.ulong ---
  Get_Char_Index  :: proc(face: Face, charcode: ULong) -> u32 ---

  Get_Kerning     :: proc(face: Face, left_glyph, right_glyph: u32, kern_mode: u32, akerning: ^Vector) -> Error ---

  Load_Char       :: proc(face: Face, char_code: u32, load_flags: i32) -> Error ---
  Load_Glyph      :: proc(face: Face, glyph_index: u32, load_flags: i32) -> Error ---

  Select_Charmap  :: proc(face: Face, encoding: Encoding) -> Error ---

  Set_Transform   :: proc(face: Face, mat: ^Matrix, delta: ^Vector) ---

  Load_Sfnt_Table :: proc(face: Face, tag: ULong, offset: Long, buffer: ^byte, length: ^ULong) -> Error ---

  Render_Glyph    :: proc(slot: GlyphSlot, render_mode: Render_Mode) -> Error ---
}

HAS_KERNING :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.KERNING in face.face_flags
}

IS_SCALABLE :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.SCALABLE in face.face_flags
}

HAS_FIXED_SIZES :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.FIXED_SIZES in face.face_flags
}

IS_FIXED_WIDTH :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.FIXED_WIDTH in face.face_flags
}

IS_SFNT :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.SFNT in face.face_flags
}

IS_HORIZONTAL :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.HORIZONTAL in face.face_flags
}

IS_VERTICAL :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.VERTICAL in face.face_flags
}

HAS_FAST_GLYPHS :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.FAST_GLYPHS in face.face_flags
}

HAS_MULTIPLE_MASTERS :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.MULTIPLE_MASTERS in face.face_flags
}

HAS_GLYPH_NAMES :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.GLYPH_NAMES in face.face_flags
}

HAS_EXTERNAL_STREAM :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.EXTERNAL_STREAM in face.face_flags
}

HAS_HINTER :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.HINTER in face.face_flags
}

IS_CID_KEYED :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.CID_KEYED in face.face_flags
}

IS_TRICKY :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.TRICKY in face.face_flags
}

HAS_COLOR :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.COLOR in face.face_flags
}

IS_VARIATION :: #force_inline proc(face: Face) -> bool {
  return FaceFlag.VARIATION in face.face_flags
}


LOAD_TARGET_NORMAL ::   (i32(Render_Mode.NORMAL) & 0x0F) << 16
LOAD_TARGET_LIGHT  ::   (i32(Render_Mode.LIGHT)  & 0x0F) << 16
LOAD_TARGET_MONO   ::   (i32(Render_Mode.MONO)   & 0x0F) << 16
LOAD_TARGET_LCD    ::   (i32(Render_Mode.LCD)    & 0x0F) << 16
LOAD_TARGET_LCD_V  ::   (i32(Render_Mode.LCD_V)  & 0x0F) << 16

LOAD_DEFAULT                     :: 0
LOAD_NO_SCALE                    :: 1 << 0
LOAD_NO_HINTING                  :: 1 << 1
LOAD_RENDER                      :: 1 << 2
LOAD_NO_BITMAP                   :: 1 << 3
LOAD_VERTICAL_LAYOUT             :: 1 << 4
LOAD_FORCE_AUTOHINT              :: 1 << 5
LOAD_CROP_BITMAP                 :: 1 << 6
LOAD_PEDANTIC                    :: 1 << 7
LOAD_IGNORE_GLOBAL_ADVANCE_WIDTH :: 1 << 9
LOAD_NO_RECURSE                  :: 1 << 10
LOAD_IGNORE_TRANSFORM            :: 1 << 11
LOAD_MONOCHROME                  :: 1 << 12
LOAD_LINEAR_DESIGN               :: 1 << 13
LOAD_NO_AUTOHINT                 :: 1 << 15
// Bits 16-19 are used by `FT_LOAD_TARGET_'
LOAD_COLOR                       :: 1 << 20
LOAD_COMPUTE_METRICS             :: 1 << 21
LOAD_BITMAP_METRICS_ONLY         :: 1 << 22


// used internally only by certain font drivers
LOAD_ADVANCE_ONLY                :: 1 << 8
LOAD_SBITS_ONLY                  :: 1 << 14


KERNING_DEFAULT  :: 0
KERNING_UNFITTED :: 1
KERNING_UNSCALED :: 2

TTAG_GSUB :: 0x47535542

Error :: distinct c.int

F26Dot6 :: Long

Handle :: struct{rawptr}

Library       :: distinct Handle
CharMap       :: ^CharMapRec
Size          :: ^SizeRec
Face          :: ^FaceRec
GlyphSlot     :: ^GlyphSlotRec
Face_Internal :: distinct Handle
Driver        :: distinct Handle
Memory        :: distinct Handle
Stream        :: distinct Handle
SubGlyph      :: distinct Handle
Slot_Internal :: distinct Handle
Size_Internal :: distinct Handle

Generic_Finalizer :: #type proc "c" (object: rawptr)
Generic :: struct {
  data: rawptr,
  finalizer: Generic_Finalizer,
}

Pos :: distinct Long
Fixed :: distinct Long


pos6_to_f32 :: proc(p: Pos) -> f32 {
  return f32(p >> 6) + f32(p & 0b111111)/64
}
pos6_to_i16 :: proc(p: Pos) -> i16 {
  return i16(p >> 6)
}


Vector :: struct{
  x, y: Pos,
}
Matrix :: struct{
  xx, xy: Fixed,
  yx, yy: Fixed,
}

Encoding :: enum u32 {
  NONE = 0,

  MS_SYMBOL = 's'<<24 | 'y'<<16 | 'm'<<8 | 'b',
  UNICODE   = 'u'<<24 | 'n'<<16 | 'i'<<8 | 'c',

  SJIS =    's'<<24 | 'j'<<16 | 'i'<<8 | 's',
  PRC =     'g'<<24 | 'b'<<16 | ' '<<8 | ' ',
  BIG5 =    'b'<<24 | 'i'<<16 | 'g'<<8 | '5',
  WANSUNG = 'w'<<24 | 'a'<<16 | 'n'<<8 | 's',
  JOHAB =   'j'<<24 | 'o'<<16 | 'h'<<8 | 'a',

  // for backward compatibility
  GB2312     = PRC,
  MS_SJIS    = SJIS,
  MS_GB2312  = PRC,
  MS_BIG5    = BIG5,
  MS_WANSUNG = WANSUNG,
  MS_JOHAB   = JOHAB,

  ADOBE_STANDARD = 'A'<<24 | 'D'<<16 | 'O'<<8 | 'B',
  ADOBE_EXPERT   = 'A'<<24 | 'D'<<16 | 'B'<<8 | 'E',
  ADOBE_CUSTOM   = 'A'<<24 | 'D'<<16 | 'B'<<8 | 'C',
  ADOBE_LATIN_1  = 'l'<<24 | 'a'<<16 | 't'<<8 | '1',

  OLD_LATIN_2 = 'l'<<24 | 'a'<<16 | 't'<<8 | '2',

  APPLE_ROMAN = 'a'<<24 | 'r'<<16 | 'm'<<8 | 'n',
}

Glyph_Format :: enum c.int {
  NONE      = 0,

  COMPOSITE = 'c'<<24 | 'o'<<16 | 'm'<<8 | 'p',
  BITMAP    = 'b'<<24 | 'i'<<16 | 't'<<8 | 's',
  OUTLINE   = 'o'<<24 | 'u'<<16 | 't'<<8 | 'l',
  PLOTTER   = 'p'<<24 | 'l'<<16 | 'o'<<8 | 't',
}

CharMapRec :: struct {
  face:        Face,
  encoding:    Encoding,
  platform_id: u16,
  encoding_id: u16,
}

Glyph_Metrics :: struct {
  width:        Pos,
  height:       Pos,

  horiBearingX: Pos,
  horiBearingY: Pos,
  horiAdvance:  Pos,

  vertBearingX: Pos,
  vertBearingY: Pos,
  vertAdvance:  Pos,
}

GlyphSlotRec :: struct {
  library:  Library,
  face:     Face,
  next:     GlyphSlot,
  reserved: u32, // retained for binary compatibility
  generic:  Generic,

  metrics:           Glyph_Metrics,
  linearHoriAdvance: Fixed,
  linearVertAdvance: Fixed,
  advance:           Vector,

  format: Glyph_Format,

  bitmap:      Bitmap,
  bitmap_left: c.int,
  bitmap_top:  c.int,

  outline: Outline,

  num_subglyphs: u32,
  subglyphs:     SubGlyph,

  control_data: rawptr,
  control_len:  Long,

  lsb_delta: Pos,
  rsb_delta: Pos,

  other: rawptr,

  internal: Slot_Internal,
}

Outline :: struct {
  n_contours: i16,     // number of contours in glyph
  n_points:   i16,     // number of points in the glyph

  points:     ^Vector, // the outline's points
  tags:       cstring, // the points flags
  contours:   ^i16,    // the contour end points

  flags:      i32,     // outline masks
}

Bitmap :: struct {
  rows:         u32,
  width:        u32,
  pitch:        i32,
  buffer:       ^byte,
  num_grays:    u16,
  pixel_mode:   u8,
  palette_mode: u8,
  palette:      rawptr,
}

Bitmap_Size :: struct {
  height: i16,
  width:  i16,

  size:   Pos,

  x_ppem: Pos,
  y_ppem: Pos,
}

BBox :: struct {
  xMin, yMin: Pos,
  xMax, yMax: Pos,
}

ListNode :: distinct rawptr

ListRec :: struct {
  head: ListNode,
  tail: ListNode,
}


FaceFlag :: enum Long {
  SCALABLE          =  0,
  FIXED_SIZES       =  1,
  FIXED_WIDTH       =  2,
  SFNT              =  3,
  HORIZONTAL        =  4,
  VERTICAL          =  5,
  KERNING           =  6,
  FAST_GLYPHS       =  7,
  MULTIPLE_MASTERS  =  8,
  GLYPH_NAMES       =  9,
  EXTERNAL_STREAM   = 10,
  HINTER            = 11,
  CID_KEYED         = 12,
  TRICKY            = 13,
  COLOR             = 14,
  VARIATION         = 15,
}

FaceRec :: struct {
  num_faces:           Long,
  face_index:          Long,

  face_flags:          bit_set[FaceFlag; Long],
  style_flags:         Long,

  num_glyphs:          Long,

  family_name:         cstring,
  style_name:          cstring,

  num_fixed_sizes:     c.int,
  available_sizes:     ^Bitmap_Size,

  num_charmaps:        c.int,
  charmaps:            ^CharMap,

  generic:             Generic,

  // The following member variables (down to `underline_thickness')
  // are only relevant to scalable outlines; cf. @FT_Bitmap_Size
  // for bitmap fonts.
  bbox:                BBox,

  units_per_EM:        u16,
  ascender:            i16,
  descender:           i16,
  height:              i16,

  max_advance_width:   i16,
  max_advance_height:  i16,

  underline_position:  i16,
  underline_thickness: i16,

  glyph:               GlyphSlot,
  size:                Size,
  charmap:             CharMap,

  driver:              Driver,
  memory:              Memory,
  stream:              Stream,

  sizes_list:          ListRec,

  autohint:            Generic, // face-specific auto-hinter data
  extensions:          rawptr,  // unused

  internal:            Face_Internal,
}

Size_Metrics :: struct {
  x_ppem:      u16,     /* horizontal pixels per EM               */
  y_ppem:      u16,     /* vertical pixels per EM                 */
  x_scale:     Fixed,   /* scaling values used to convert font    */
  y_scale:     Fixed,   /* units to 26.6 fractional pixels        */
  ascender:    Pos,     /* ascender in 26.6 frac. pixels          */
  descender:   Pos,     /* descender in 26.6 frac. pixels         */
  height:      Pos,     /* text height in 26.6 frac. pixels       */
  max_advance: Pos,     /* max horizontal advance, in 26.6 pixels */
}

SizeRec :: struct {
  face:     Face,           /* parent face object              */
  generic:  Generic,        /* generic pointer for client uses */
  metrics:  Size_Metrics,   /* size metrics                    */
  internal: Size_Internal,
}

Render_Mode :: enum Long {
  NORMAL = 0,
  LIGHT,
  MONO,
  LCD,
  LCD_V,
  MAX,
}

Pixel_Mode :: enum u8 {
  NONE = 0,
  MONO,
  GRAY,
  GRAY2,
  GRAY4,
  LCD,
  LCD_V,
  BGRA,
  MAX,
}