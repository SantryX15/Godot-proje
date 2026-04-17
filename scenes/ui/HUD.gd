## HUD.gd
## Oyun içi ekran: takım skorları, oyuncu sağlığı, minimap ve kart bildirimi.

extends CanvasLayer

@onready var score_labels: Array = [
	$ScorePanel/VBox/Score0,
	$ScorePanel/VBox/Score1,
	$ScorePanel/VBox/Score2,
	$ScorePanel/VBox/Score3,
]
@onready var end_panel: PanelContainer = $EndPanel
@onready var winner_label: Label = $EndPanel/VBox/WinnerLabel
@onready var back_btn: Button = $EndPanel/VBox/BackBtn

var _minimap: Control = null
var _alert_banner: Label = null
var _banner_tween: Tween = null
var _kill_feed_root: VBoxContainer = null

const KILL_FEED_MAX := 5


func _ready() -> void:
	TeamManager.score_updated.connect(_on_score_updated)
	GameManager.game_ended.connect(_on_game_ended)
	GameManager.card_picked_up.connect(_on_card_picked_up)
	GameManager.kill_happened.connect(_on_kill_happened)
	end_panel.hide()
	_refresh_scores()
	_setup_minimap()
	_setup_alert_banner()
	_setup_kill_feed()


func _setup_minimap() -> void:
	var minimap_script := load("res://scenes/ui/Minimap.gd")
	_minimap = Control.new()
	_minimap.set_script(minimap_script)
	# Sağ-alt köşeye yerleştir
	_minimap.anchor_left   = 1.0
	_minimap.anchor_top    = 1.0
	_minimap.anchor_right  = 1.0
	_minimap.anchor_bottom = 1.0
	_minimap.offset_left   = -190.0
	_minimap.offset_top    = -190.0
	_minimap.offset_right  = -10.0
	_minimap.offset_bottom = -10.0
	add_child(_minimap)


func _setup_alert_banner() -> void:
	_alert_banner = Label.new()
	_alert_banner.anchor_left   = 0.5
	_alert_banner.anchor_right  = 0.5
	_alert_banner.anchor_top    = 0.0
	_alert_banner.anchor_bottom = 0.0
	_alert_banner.offset_left   = -200.0
	_alert_banner.offset_right  = 200.0
	_alert_banner.offset_top    = 60.0
	_alert_banner.offset_bottom = 90.0
	_alert_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_banner.add_theme_font_size_override("font_size", 18)
	_alert_banner.modulate = Color(1.0, 0.3, 0.3, 0.0)  # Başta görünmez
	add_child(_alert_banner)


func _refresh_scores() -> void:
	for i in range(4):
		var score: int = TeamManager.scores.get(i, 0)
		score_labels[i].text = "%s: %d" % [TeamManager.get_team_name(i), score]
		score_labels[i].modulate = TeamManager.get_color(i)


func _on_score_updated(_team_id: int, _score: int) -> void:
	_refresh_scores()


func _on_game_ended(winning_team: int) -> void:
	end_panel.show()
	winner_label.text = "%s Takımı Kazandı!" % TeamManager.get_team_name(winning_team)
	winner_label.modulate = TeamManager.get_color(winning_team)


func _on_card_picked_up(carrier_peer_id: int, _carrier_pos: Vector3, carrier_team_id: int) -> void:
	var team_name := TeamManager.get_team_name(carrier_team_id)
	var team_color := TeamManager.get_color(carrier_team_id)

	_alert_banner.text = "⚠ %s KARTI ALDI!" % team_name.to_upper()
	_alert_banner.add_theme_color_override("font_color", team_color)

	# Önceki tween varsa iptal et
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()

	# Banner: belirip 3 sn sonra yukarı kayarak kaybolur
	_banner_tween = create_tween()
	_banner_tween.tween_property(_alert_banner, "modulate:a", 1.0, 0.2)
	_banner_tween.tween_interval(2.5)
	_banner_tween.tween_property(_alert_banner, "modulate:a", 0.0, 0.5)


func _setup_kill_feed() -> void:
	_kill_feed_root = VBoxContainer.new()
	_kill_feed_root.anchor_left   = 1.0
	_kill_feed_root.anchor_right  = 1.0
	_kill_feed_root.anchor_top    = 0.0
	_kill_feed_root.anchor_bottom = 0.0
	_kill_feed_root.offset_left   = -310.0
	_kill_feed_root.offset_right  = -10.0
	_kill_feed_root.offset_top    = 10.0
	_kill_feed_root.offset_bottom = 10.0
	_kill_feed_root.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_kill_feed_root)


func _on_kill_happened(killer_peer_id: int, victim_peer_id: int) -> void:
	# Maksimum KILL_FEED_MAX satır — en eskiyi sil
	if _kill_feed_root.get_child_count() >= KILL_FEED_MAX:
		_kill_feed_root.get_child(0).queue_free()

	var kd: Dictionary = NetworkManager.players.get(killer_peer_id, {})
	var vd: Dictionary = NetworkManager.players.get(victim_peer_id, {})
	var kname: String = kd.get("name", "???")
	var vname: String = vd.get("name", "???")
	var kcol: Color = TeamManager.get_color(kd.get("team_id", -1))
	var vcol: Color = TeamManager.get_color(vd.get("team_id", -1))

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(300.0, 0.0)
	rtl.add_theme_font_size_override("normal_font_size", 14)
	var kc := "#" + kcol.to_html(false)
	var vc := "#" + vcol.to_html(false)
	rtl.text = "[right][color=%s]%s[/color]  [color=white]▶[/color]  [color=%s]%s[/color][/right]" \
		% [kc, kname, vc, vname]
	_kill_feed_root.add_child(rtl)

	var tw := create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(rtl, "modulate:a", 0.0, 0.6)
	tw.tween_callback(rtl.queue_free)


func _on_back_btn_pressed() -> void:
	GameManager.return_to_menu()
