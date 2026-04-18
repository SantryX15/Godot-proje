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
var _pause_panel: PanelContainer = null
var _health_bar: ProgressBar = null
var _health_value_label: Label = null
var _ammo_label_hud: Label = null
var _scoreboard_panel: PanelContainer = null
var _scoreboard_grid: GridContainer = null
var _scoreboard_visible: bool = false

const KILL_FEED_MAX := 5


func _ready() -> void:
	TeamManager.score_updated.connect(_on_score_updated)
	GameManager.game_ended.connect(_on_game_ended)
	GameManager.card_picked_up.connect(_on_card_picked_up)
	GameManager.card_dropped.connect(_on_card_dropped)
	GameManager.kill_happened.connect(_on_kill_happened)
	GameManager.local_player_spawned.connect(_on_local_player_spawned)
	end_panel.hide()
	_refresh_scores()
	_setup_minimap()
	_setup_alert_banner()
	_setup_kill_feed()
	_setup_health_display()
	_setup_ammo_display()
	_setup_scoreboard()
	_setup_pause_menu()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		# Oyun bitmişse ESC menüsü açılmasın (end_panel görünürdür)
		if end_panel.visible:
			return
		_toggle_pause_menu()
		get_viewport().set_input_as_handled()


func _toggle_pause_menu() -> void:
	_pause_panel.visible = not _pause_panel.visible


func _setup_pause_menu() -> void:
	# Arka plan overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.45)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	_pause_panel = PanelContainer.new()
	_pause_panel.anchor_left   = 0.5
	_pause_panel.anchor_right  = 0.5
	_pause_panel.anchor_top    = 0.5
	_pause_panel.anchor_bottom = 0.5
	_pause_panel.offset_left   = -140.0
	_pause_panel.offset_right  = 140.0
	_pause_panel.offset_top    = -110.0
	_pause_panel.offset_bottom = 110.0
	_pause_panel.add_child(overlay)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_pause_panel.add_child(vbox)

	var title := Label.new()
	title.text = "— MENÜ —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	var resume_btn := Button.new()
	resume_btn.text = "Devam Et"
	resume_btn.custom_minimum_size = Vector2(220, 42)
	resume_btn.pressed.connect(_toggle_pause_menu)
	vbox.add_child(resume_btn)

	var leave_btn := Button.new()
	leave_btn.text = "Ana Menüye Dön"
	leave_btn.custom_minimum_size = Vector2(220, 42)
	leave_btn.pressed.connect(_on_leave_pressed)
	vbox.add_child(leave_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Oyunu Kapat"
	quit_btn.custom_minimum_size = Vector2(220, 42)
	quit_btn.pressed.connect(get_tree().quit)
	vbox.add_child(quit_btn)

	_pause_panel.hide()
	add_child(_pause_panel)


func _on_leave_pressed() -> void:
	_pause_panel.hide()
	GameManager.return_to_menu()


func _on_local_player_spawned(player: Node) -> void:
	player.health_changed.connect(_on_health_changed)
	player.ammo_changed.connect(_on_ammo_changed)
	_on_health_changed(player.health)


func _on_health_changed(new_health: float) -> void:
	_health_bar.value = new_health
	_health_value_label.text = "%d" % int(new_health)
	# Cana göre renk: yeşil → sarı → kırmızı
	var t := new_health / 100.0
	if t > 0.5:
		_health_bar.modulate = Color(1.0 - (t - 0.5) * 2.0, 1.0, 0.0)
	else:
		_health_bar.modulate = Color(1.0, t * 2.0, 0.0)


func _setup_health_display() -> void:
	# Sol-alt köşe container'ı
	var container := HBoxContainer.new()
	container.anchor_left   = 0.0
	container.anchor_right  = 0.0
	container.anchor_top    = 1.0
	container.anchor_bottom = 1.0
	container.offset_left   = 20.0
	container.offset_right  = 240.0
	container.offset_top    = -54.0
	container.offset_bottom = -20.0
	container.add_theme_constant_override("separation", 8)
	add_child(container)

	# Kalp ikonu
	var icon := Label.new()
	icon.text = "❤"
	icon.add_theme_font_size_override("font_size", 22)
	icon.modulate = Color(1.0, 0.25, 0.25)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	container.add_child(icon)

	# Progress bar
	_health_bar = ProgressBar.new()
	_health_bar.min_value = 0.0
	_health_bar.max_value = 100.0
	_health_bar.value     = 100.0
	_health_bar.custom_minimum_size = Vector2(140, 18)
	_health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_health_bar.show_percentage = false
	container.add_child(_health_bar)

	# Sayısal değer
	_health_value_label = Label.new()
	_health_value_label.text = "100"
	_health_value_label.add_theme_font_size_override("font_size", 16)
	_health_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_value_label.custom_minimum_size = Vector2(36, 0)
	container.add_child(_health_value_label)


func _on_ammo_changed(current: int, total: int, reloading: bool) -> void:
	if reloading:
		_ammo_label_hud.text = "Şarj ediliyor..."
	else:
		_ammo_label_hud.text = "🔫  %d / %d" % [current, total]
	_ammo_label_hud.modulate = Color(1.0, 0.55, 0.1) if current <= 5 and not reloading else Color.WHITE


func _setup_ammo_display() -> void:
	_ammo_label_hud = Label.new()
	_ammo_label_hud.text = "🔫  30 / 30"
	_ammo_label_hud.add_theme_font_size_override("font_size", 16)
	_ammo_label_hud.anchor_left   = 0.0
	_ammo_label_hud.anchor_right  = 0.0
	_ammo_label_hud.anchor_top    = 1.0
	_ammo_label_hud.anchor_bottom = 1.0
	_ammo_label_hud.offset_left   = 20.0
	_ammo_label_hud.offset_right  = 200.0
	_ammo_label_hud.offset_top    = -80.0
	_ammo_label_hud.offset_bottom = -58.0
	add_child(_ammo_label_hud)


func _setup_scoreboard() -> void:
	_scoreboard_panel = PanelContainer.new()
	_scoreboard_panel.anchor_left   = 0.5
	_scoreboard_panel.anchor_right  = 0.5
	_scoreboard_panel.anchor_top    = 0.08
	_scoreboard_panel.anchor_bottom = 0.08
	_scoreboard_panel.offset_left   = -280.0
	_scoreboard_panel.offset_right  = 280.0
	_scoreboard_panel.offset_top    = 0.0
	_scoreboard_panel.offset_bottom = 420.0

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	_scoreboard_panel.add_child(vbox)

	var title := Label.new()
	title.text = "SKOR TABLOSU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# 4 sütun: Oyuncu | Takım | Kill | Ölüm
	_scoreboard_grid = GridContainer.new()
	_scoreboard_grid.columns = 4
	_scoreboard_grid.add_theme_constant_override("h_separation", 10)
	_scoreboard_grid.add_theme_constant_override("v_separation", 5)
	vbox.add_child(_scoreboard_grid)

	_scoreboard_panel.hide()
	add_child(_scoreboard_panel)


func _refresh_scoreboard() -> void:
	for child in _scoreboard_grid.get_children():
		child.queue_free()

	var col_widths := [190.0, 90.0, 55.0, 55.0]
	var col_headers := ["Oyuncu", "Takım", "Kill", "Ölüm"]

	# Başlık satırı
	for i in range(4):
		var h := Label.new()
		h.text = col_headers[i]
		h.add_theme_font_size_override("font_size", 12)
		h.modulate = Color(0.6, 0.6, 0.6)
		h.custom_minimum_size = Vector2(col_widths[i], 0)
		if i >= 2:
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_scoreboard_grid.add_child(h)

	# Separator çizgisi (4 hücre)
	for _i in range(4):
		_scoreboard_grid.add_child(HSeparator.new())

	# Kill sayısına göre sırala
	var local_id := NetworkManager.get_local_id()
	var peers: Array = NetworkManager.players.keys()
	peers.sort_custom(func(a: int, b: int) -> bool:
		var ka: int = GameManager.player_stats.get(a, {"kills": 0})["kills"]
		var kb: int = GameManager.player_stats.get(b, {"kills": 0})["kills"]
		return ka > kb
	)

	for pid in peers:
		var data: Dictionary = NetworkManager.players[pid]
		var stats: Dictionary = GameManager.player_stats.get(pid, {"kills": 0, "deaths": 0})
		var team_id: int = data.get("team_id", -1)
		var team_color: Color = TeamManager.get_color(team_id)
		var is_me: bool = (int(pid) == local_id)

		# İsim
		var name_lbl := Label.new()
		name_lbl.text = "%s%s" % [data.get("name", "???"), "  ◄" if is_me else ""]
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.custom_minimum_size = Vector2(col_widths[0], 0)
		name_lbl.modulate = team_color if is_me else Color.WHITE
		_scoreboard_grid.add_child(name_lbl)

		# Takım
		var team_lbl := Label.new()
		team_lbl.text = TeamManager.get_team_name(team_id)
		team_lbl.add_theme_font_size_override("font_size", 14)
		team_lbl.modulate = team_color
		team_lbl.custom_minimum_size = Vector2(col_widths[1], 0)
		_scoreboard_grid.add_child(team_lbl)

		# Kill
		var k_lbl := Label.new()
		k_lbl.text = str(stats.get("kills", 0))
		k_lbl.add_theme_font_size_override("font_size", 14)
		k_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		k_lbl.custom_minimum_size = Vector2(col_widths[2], 0)
		_scoreboard_grid.add_child(k_lbl)

		# Ölüm
		var d_lbl := Label.new()
		d_lbl.text = str(stats.get("deaths", 0))
		d_lbl.add_theme_font_size_override("font_size", 14)
		d_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d_lbl.modulate = Color(0.85, 0.4, 0.4)
		d_lbl.custom_minimum_size = Vector2(col_widths[3], 0)
		_scoreboard_grid.add_child(d_lbl)


func _process(_delta: float) -> void:
	var tab := Input.is_key_pressed(KEY_TAB)
	if tab != _scoreboard_visible and not (_pause_panel and _pause_panel.visible):
		_scoreboard_visible = tab
		_scoreboard_panel.visible = tab
		if tab:
			_refresh_scoreboard()


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


func _on_card_dropped(_drop_pos: Vector3, carrier_team_id: int) -> void:
	var team_name  := TeamManager.get_team_name(carrier_team_id)
	var team_color := TeamManager.get_color(carrier_team_id)

	_alert_banner.text = "♦ %s TAKIM KARTI BIRAKTI!" % team_name.to_upper()
	_alert_banner.add_theme_color_override("font_color", team_color)

	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()

	_banner_tween = create_tween()
	_banner_tween.tween_property(_alert_banner, "modulate:a", 1.0, 0.2)
	_banner_tween.tween_interval(2.5)
	_banner_tween.tween_property(_alert_banner, "modulate:a", 0.0, 0.5)


func _on_card_picked_up(carrier_peer_id: int, _carrier_pos: Vector3, carrier_team_id: int) -> void:
	var team_name := TeamManager.get_team_name(carrier_team_id)
	var team_color := TeamManager.get_color(carrier_team_id)

	_alert_banner.text = "⚠ %s TAKIM KARTI ALDI!" % team_name.to_upper()
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
