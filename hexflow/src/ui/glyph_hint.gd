## "Which button is this?", answered the way the player's own hardware answers it.
##
## §11.4 forbids hardcoding Xbox glyphs, and the first half of that was done long
## ago: [InputGlyphs] resolves an action to the *word* the connected pad uses, so a
## Deck player reads "View" where an Xbox player reads "View" and a DualSense player
## reads "Create". This is the second half — the picture, when there is one.
##
## It is one control rather than an `if` at every call site because the fallbacks
## are the hard part and there are three of them. No controller: the answer is a key
## name, and a picture of a key is worse than the word. No binding: nothing is drawn
## at all. No file for that family: the word, again. A HUD that went blank because
## one PNG was missing would be a worse bug than the one this fixes, so **text is
## the floor and the icon is the improvement** — the same shape as every other
## placeholder in this project.
##
## The icon is sized from a [Typography] role rather than in pixels, so §21's
## 1.0–1.5 text scale moves it with the words beside it. It is tinted through
## `text_primary`, because the files are drawn white on transparent (§13.2) — which
## is also what lets §21's palettes reach them.
##
## A hold gesture keeps its word. §11.3 draws a real distinction between "R" and
## "hold R", and an icon on its own cannot carry it.
class_name GlyphHint
extends HBoxContainer

## The role the hint is set in, and therefore the height the icon is drawn at.
const ROLE := Typography.Role.CAPTION

const SEPARATION := 6

var palette: Palette = null

var _prefix: Label = null
var _icon: TextureRect = null
var _word: Label = null

var _action: String = ""


func _init() -> void:
	add_theme_constant_override("separation", SEPARATION)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END


func _ready() -> void:
	if palette == null:
		palette = Palette.current()
	_build()
	show_action(_action)


## Shows the binding for [param action]. Safe to call before the control enters the
## tree, and safe to call every frame's worth of HUD refresh — the nodes are built
## once and only their properties change (C4).
func show_action(action: String) -> void:
	_action = action
	if _icon == null:
		return  # not built yet; `_ready` will apply it

	var texture: Texture2D = InputGlyphs.texture_for(action)
	var hold: bool = InputBindings.is_hold(action)

	if texture != null:
		_icon.texture = texture
		_icon.custom_minimum_size = Vector2.ONE * float(_size_px())
		_icon.visible = true
		_word.visible = false
		# §11.3's distinction, kept: "hold R" and "R" are different promises, and a
		# picture of a button says nothing about how long to press it.
		_prefix.visible = hold
		return

	_icon.visible = false
	# `label_for` already carries the "hold " prefix in the text form, so the
	# separate word would double it.
	_prefix.visible = false
	var word: String = InputGlyphs.label_for(action)
	_word.text = word
	_word.visible = word != ""


## What is on screen, for a test that should not have to reach into three nodes.
## Returns the word when there is one, otherwise the texture's own file name.
func reads_as() -> String:
	if _icon != null and _icon.visible and _icon.texture != null:
		var name: String = _icon.texture.resource_path.get_file().get_basename()
		return "hold " + name if _prefix.visible else name
	return _word.text if _word != null and _word.visible else ""


func showing_icon() -> bool:
	return _icon != null and _icon.visible


func _size_px() -> int:
	return Typography.size_of(ROLE, float(SettingsService.get_value("text_scale")))


func _build() -> void:
	_prefix = Label.new()
	_prefix.text = "hold"
	_prefix.theme_type_variation = Typography.variation_for(ROLE)
	_prefix.add_theme_color_override("font_color", palette.text_secondary)
	_prefix.visible = false
	add_child(_prefix)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.modulate = palette.text_primary
	_icon.visible = false
	add_child(_icon)

	_word = Label.new()
	_word.theme_type_variation = Typography.variation_for(ROLE)
	_word.add_theme_color_override("font_color", palette.text_primary)
	add_child(_word)
