## UITheme.gd (statik sınıf — autoload DEĞİL)
## Oyunun ortak arayüz teması. Kodla bir Theme kurar ve root Window'a atar —
## böylece tüm sahnelerdeki Button/LineEdit/Panel/ScrollBar vb. otomatik bu görünümü alır.
## UITheme.apply(get_tree()) Main.gd'de (ve sahne tek başına çalıştırılırsa MainMenu'de) çağrılır;
## root.theme sahne geçişlerinde korunur.
## Ayrıca palet sabitleri ve sık kullanılan stil yardımcıları sunar (UITheme.style(), UITheme.label()).
##
## Tip varyasyonları (Control.theme_type_variation ile kullanılır):
##   Button → "PrimaryButton" (vurgu renkli), "GhostButton" (şeffaf), "TabButton" (sekme, toggle)
##   Label  → "TitleLabel", "CapsLabel" (küçük, aralıklı, soluk), "DimLabel"

class_name UITheme
extends RefCounted

# ── Palet: karanlık zemin + el feneri sarısı vurgu ──
const BG        := Color(0.03, 0.035, 0.05)
const SURFACE   := Color(0.07, 0.078, 0.105, 0.94)
const SURFACE_2 := Color(0.105, 0.115, 0.15)
const SURFACE_3 := Color(0.14, 0.152, 0.195)
const BORDER    := Color(1, 1, 1, 0.08)
const TEXT      := Color(0.93, 0.94, 0.96)
const TEXT_DIM  := Color(0.56, 0.58, 0.66)
const ACCENT    := Color(1.0, 0.74, 0.32)
const ACCENT_TEXT := Color(0.08, 0.06, 0.03)
const DANGER    := Color(0.96, 0.38, 0.33)
const SUCCESS   := Color(0.42, 0.86, 0.52)

const RADIUS := 10

static var theme: Theme
static var font_regular: Font
static var font_bold: FontVariation
static var font_title: FontVariation
static var font_caps: FontVariation


## Temayı (ilk çağrıda kurup) root Window'a atar. Birden fazla çağrılması güvenli.
static func apply(tree: SceneTree) -> void:
	if theme == null:
		theme = _build_theme()
	if tree.root.theme != theme:
		tree.root.theme = theme


static func _static_init() -> void:
	font_regular = ThemeDB.fallback_font

	font_bold = FontVariation.new()
	font_bold.base_font = font_regular
	font_bold.variation_embolden = 0.6
	font_bold.spacing_glyph = 1

	font_title = FontVariation.new()
	font_title.base_font = font_regular
	font_title.variation_embolden = 1.0
	font_title.spacing_glyph = 6

	font_caps = FontVariation.new()
	font_caps.base_font = font_regular
	font_caps.variation_embolden = 0.35
	font_caps.spacing_glyph = 3


# ─────────────────────────────────────────────
#  Yardımcılar (diğer scriptler kullanır)
# ─────────────────────────────────────────────

static func style(bg: Color, radius: int = RADIUS, border: Color = Color.TRANSPARENT, border_w: int = 0,
		margin_h: float = -1.0, margin_v: float = -1.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	if margin_h >= 0.0:
		s.content_margin_left  = margin_h
		s.content_margin_right = margin_h
	if margin_v >= 0.0:
		s.content_margin_top    = margin_v
		s.content_margin_bottom = margin_v
	return s


static func label(text: String, font_size: int = 15, color: Color = TEXT, font: Font = null) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	if font:
		lbl.add_theme_font_override("font", font)
	return lbl


# ─────────────────────────────────────────────
#  Tema
# ─────────────────────────────────────────────

static func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_regular
	t.default_font_size = 15

	# ── Label ──
	t.set_color("font_color", "Label", TEXT)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", font_title)
	t.set_font_size("font_size", "TitleLabel", 28)
	t.set_type_variation("CapsLabel", "Label")
	t.set_font("font", "CapsLabel", font_caps)
	t.set_font_size("font_size", "CapsLabel", 11)
	t.set_color("font_color", "CapsLabel", TEXT_DIM)
	t.set_type_variation("DimLabel", "Label")
	t.set_color("font_color", "DimLabel", TEXT_DIM)
	t.set_font_size("font_size", "DimLabel", 13)

	# ── Button (varsayılan) ──
	var btn_margin_h := 16.0
	var btn_margin_v := 9.0
	t.set_stylebox("normal",   "Button", style(SURFACE_2, RADIUS, BORDER, 1, btn_margin_h, btn_margin_v))
	t.set_stylebox("hover",    "Button", style(SURFACE_3, RADIUS, Color(ACCENT, 0.45), 1, btn_margin_h, btn_margin_v))
	t.set_stylebox("pressed",  "Button", style(SURFACE, RADIUS, ACCENT, 1, btn_margin_h, btn_margin_v))
	t.set_stylebox("hover_pressed", "Button", style(SURFACE_3, RADIUS, ACCENT, 1, btn_margin_h, btn_margin_v))
	t.set_stylebox("disabled", "Button", style(Color(1, 1, 1, 0.03), RADIUS, Color(1, 1, 1, 0.05), 1, btn_margin_h, btn_margin_v))
	t.set_stylebox("focus",    "Button", style(Color.TRANSPARENT, RADIUS, Color(ACCENT, 0.6), 1))
	t.set_font("font", "Button", font_bold)
	t.set_color("font_color",          "Button", TEXT)
	t.set_color("font_hover_color",    "Button", Color.WHITE)
	t.set_color("font_pressed_color",  "Button", ACCENT)
	t.set_color("font_hover_pressed_color", "Button", ACCENT)
	t.set_color("font_focus_color",    "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.6))

	# ── PrimaryButton: el feneri sarısı ──
	t.set_type_variation("PrimaryButton", "Button")
	var prim_hover := style(ACCENT.lightened(0.12), RADIUS, Color.TRANSPARENT, 0, btn_margin_h, btn_margin_v)
	prim_hover.shadow_color = Color(ACCENT, 0.35)
	prim_hover.shadow_size = 14
	t.set_stylebox("normal",   "PrimaryButton", style(ACCENT, RADIUS, Color.TRANSPARENT, 0, btn_margin_h, btn_margin_v))
	t.set_stylebox("hover",    "PrimaryButton", prim_hover)
	t.set_stylebox("pressed",  "PrimaryButton", style(ACCENT.darkened(0.15), RADIUS, Color.TRANSPARENT, 0, btn_margin_h, btn_margin_v))
	t.set_stylebox("disabled", "PrimaryButton", style(Color(ACCENT, 0.18), RADIUS, Color.TRANSPARENT, 0, btn_margin_h, btn_margin_v))
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(key, "PrimaryButton", ACCENT_TEXT)
	t.set_color("font_disabled_color", "PrimaryButton", Color(ACCENT_TEXT, 0.6))

	# ── GhostButton: şeffaf, sadece hover'da zemin ──
	t.set_type_variation("GhostButton", "Button")
	t.set_stylebox("normal",  "GhostButton", style(Color.TRANSPARENT, RADIUS, Color.TRANSPARENT, 0, 12, 7))
	t.set_stylebox("hover",   "GhostButton", style(Color(1, 1, 1, 0.06), RADIUS, Color.TRANSPARENT, 0, 12, 7))
	t.set_stylebox("pressed", "GhostButton", style(Color(1, 1, 1, 0.1), RADIUS, Color.TRANSPARENT, 0, 12, 7))
	t.set_stylebox("disabled", "GhostButton", style(Color.TRANSPARENT, RADIUS, Color.TRANSPARENT, 0, 12, 7))
	t.set_color("font_color", "GhostButton", TEXT_DIM)
	t.set_color("font_hover_color", "GhostButton", TEXT)
	t.set_color("font_pressed_color", "GhostButton", TEXT)

	# ── TabButton: toggle sekme, seçili olan altı çizgili ──
	t.set_type_variation("TabButton", "Button")
	var tab_sel := style(Color(ACCENT, 0.08), 0, Color.TRANSPARENT, 0, 18, 12)
	tab_sel.border_color = ACCENT
	tab_sel.border_width_bottom = 2
	tab_sel.corner_radius_top_left = 8
	tab_sel.corner_radius_top_right = 8
	var tab_norm := style(Color.TRANSPARENT, 0, Color.TRANSPARENT, 0, 18, 12)
	tab_norm.border_width_bottom = 2
	tab_norm.border_color = Color.TRANSPARENT
	var tab_hover := tab_norm.duplicate() as StyleBoxFlat
	tab_hover.bg_color = Color(1, 1, 1, 0.04)
	tab_hover.corner_radius_top_left = 8
	tab_hover.corner_radius_top_right = 8
	t.set_stylebox("normal", "TabButton", tab_norm)
	t.set_stylebox("hover", "TabButton", tab_hover)
	t.set_stylebox("pressed", "TabButton", tab_sel)
	t.set_stylebox("hover_pressed", "TabButton", tab_sel)
	t.set_stylebox("focus", "TabButton", StyleBoxEmpty.new())
	t.set_font("font", "TabButton", font_caps)
	t.set_font_size("font_size", "TabButton", 13)
	t.set_color("font_color", "TabButton", TEXT_DIM)
	t.set_color("font_hover_color", "TabButton", TEXT)
	t.set_color("font_pressed_color", "TabButton", ACCENT)
	t.set_color("font_hover_pressed_color", "TabButton", ACCENT)

	# ── LineEdit ──
	var le_norm := style(Color(0, 0, 0, 0.35), RADIUS, BORDER, 1, 14, 10)
	var le_focus := style(Color(0, 0, 0, 0.45), RADIUS, Color(ACCENT, 0.8), 1, 14, 10)
	t.set_stylebox("normal", "LineEdit", le_norm)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_stylebox("read_only", "LineEdit", style(Color(0, 0, 0, 0.2), RADIUS, BORDER, 1, 14, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.6))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.3))
	t.set_constant("caret_width", "LineEdit", 2)

	# ── Paneller ──
	t.set_stylebox("panel", "PanelContainer", style(SURFACE, RADIUS + 4, BORDER, 1, 0, 0))
	t.set_stylebox("panel", "Panel", style(SURFACE, RADIUS + 4, BORDER, 1))
	t.set_stylebox("panel", "PopupPanel", style(SURFACE_2, RADIUS, BORDER, 1, 12, 12))
	t.set_stylebox("panel", "TooltipPanel", style(SURFACE_3, 6, BORDER, 1, 10, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)

	# ── Ayraçlar ──
	var sep := StyleBoxLine.new()
	sep.color = BORDER
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 1)
	var vsep := StyleBoxLine.new()
	vsep.color = BORDER
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)

	# ── ScrollBar: ince, yuvarlak ──
	var grabber := style(Color(1, 1, 1, 0.14), 4)
	grabber.content_margin_left = 3
	grabber.content_margin_right = 3
	var grabber_hl := style(Color(ACCENT, 0.6), 4)
	for bar: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, style(Color(1, 1, 1, 0.02), 4, Color.TRANSPARENT, 0, 3, 3))
		t.set_stylebox("grabber", bar, grabber)
		t.set_stylebox("grabber_highlight", bar, grabber_hl)
		t.set_stylebox("grabber_pressed", bar, grabber_hl)

	# ── ProgressBar ──
	t.set_stylebox("background", "ProgressBar", style(Color(1, 1, 1, 0.07), 4))
	t.set_stylebox("fill", "ProgressBar", style(ACCENT, 4))
	t.set_color("font_color", "ProgressBar", TEXT)

	return t
