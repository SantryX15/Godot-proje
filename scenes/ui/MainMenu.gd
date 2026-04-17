## MainMenu.gd
## Oda oluştur / listele / kod ile katıl — 3 ekran + modal panel.

extends Control

# ── Ekranlar ──
@onready var screen_main:     VBoxContainer  = $ScreenMain
@onready var screen_create:   VBoxContainer  = $ScreenCreate
@onready var screen_browse:   VBoxContainer  = $ScreenBrowse
@onready var join_code_panel: PanelContainer = $JoinCodePanel

# ── ScreenMain ──
@onready var name_input:      LineEdit = $ScreenMain/NameInput
@onready var status_main:     Label    = $ScreenMain/StatusMain

# ── ScreenCreate ──
@onready var room_name_input: LineEdit = $ScreenCreate/RoomNameInput
@onready var password_input:  LineEdit = $ScreenCreate/PasswordInput
@onready var status_create:   Label    = $ScreenCreate/StatusCreate

# ── ScreenBrowse ──
@onready var room_list:       VBoxContainer = $ScreenBrowse/ScrollContainer/RoomList
@onready var no_rooms_label:  Label         = $ScreenBrowse/NoRoomsLabel
@onready var status_browse:   Label         = $ScreenBrowse/StatusBrowse

# ── JoinCodePanel ──
@onready var code_input:      LineEdit = $JoinCodePanel/PanelVBox/CodeInput
@onready var code_pw_input:   LineEdit = $JoinCodePanel/PanelVBox/CodePwInput
@onready var status_code:     Label    = $JoinCodePanel/PanelVBox/StatusCode


func _ready() -> void:
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.joined_server.connect(_on_joined_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.kicked.connect(_on_kicked)
	RoomManager.rooms_updated.connect(_refresh_room_list)
	name_input.text = "Oyuncu_%d" % randi_range(100, 999)
	_show_screen("main")


func _show_screen(which: String) -> void:
	screen_main.visible   = (which == "main")
	screen_create.visible = (which == "create")
	screen_browse.visible = (which == "browse")
	join_code_panel.visible = false


# ── ScreenMain ───────────────────────────────

func _on_btn_create_room_pressed() -> void:
	status_main.text = ""
	_show_screen("create")


func _on_btn_browse_pressed() -> void:
	status_main.text = ""
	_show_screen("browse")
	RoomManager.start_listening()
	_refresh_room_list()


# ── ScreenCreate ─────────────────────────────

func _on_btn_back_create_pressed() -> void:
	_show_screen("main")


func _on_btn_host_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		status_create.text = "Lütfen oyuncu adı girin!"
		return
	var r_name := room_name_input.text.strip_edges()
	if r_name.is_empty():
		r_name = player_name + "'nin Odası"
	status_create.text = "Sunucu oluşturuluyor..."
	NetworkManager.create_server(player_name, r_name, password_input.text)


# ── ScreenBrowse ─────────────────────────────

func _on_btn_back_browse_pressed() -> void:
	RoomManager.stop_listening()
	_show_screen("main")


func _on_btn_refresh_pressed() -> void:
	_refresh_room_list()


func _refresh_room_list() -> void:
	for child in room_list.get_children():
		child.queue_free()
	var rooms := RoomManager.discovered_rooms
	no_rooms_label.visible = rooms.is_empty()
	for code: String in rooms:
		var room: Dictionary = rooms[code]
		var hbox := HBoxContainer.new()
		var lbl := Label.new()
		var lock := "🔒 " if room.get("has_password", false) else ""
		var cnt: int = room.get("player_count", 0)
		lbl.text = "%s%s  [%d]" % [lock, room.get("room_name", code), cnt]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(lbl)
		var btn := Button.new()
		btn.text = "Gir"
		btn.custom_minimum_size = Vector2(70, 36)
		var has_pw: bool = room.get("has_password", false)
		var room_ip: String = room.get("ip", "")
		btn.pressed.connect(_on_room_join_btn.bind(code, room_ip, has_pw))
		hbox.add_child(btn)
		room_list.add_child(hbox)


func _on_room_join_btn(room_code: String, room_ip: String, has_password: bool) -> void:
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		status_browse.text = "Lütfen oyuncu adı girin!"
		return
	if has_password:
		code_input.text    = room_code
		code_pw_input.text = ""
		status_code.text   = ""
		join_code_panel.visible = true
	else:
		status_browse.text = "Bağlanıyor: %s..." % room_ip
		NetworkManager.join_server(room_ip, player_name, "")


func _on_btn_join_by_code_pressed() -> void:
	code_input.text    = ""
	code_pw_input.text = ""
	status_code.text   = ""
	join_code_panel.visible = true


# ── JoinCodePanel ────────────────────────────

func _on_btn_join_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		status_code.text = "Lütfen oyuncu adı girin!"
		return
	var code := code_input.text.strip_edges().to_upper()
	if code.is_empty():
		status_code.text = "Lütfen oda kodu girin!"
		return
	var ip := RoomManager.get_ip_for_code(code)
	status_code.text = "Bağlanıyor..."
	NetworkManager.join_server(ip, player_name, code_pw_input.text)


func _on_btn_cancel_code_pressed() -> void:
	join_code_panel.visible = false


# ── Ağ olayları ──────────────────────────────

func _on_server_created() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/Lobby.tscn")


func _on_joined_server() -> void:
	RoomManager.stop_listening()
	get_tree().change_scene_to_file.call_deferred("res://scenes/ui/Lobby.tscn")


func _on_connection_failed() -> void:
	status_browse.text = "Bağlantı başarısız!"
	status_code.text   = "Bağlantı başarısız!"
	status_main.text   = "Bağlantı başarısız!"


func _on_kicked(reason: String) -> void:
	join_code_panel.visible = false
	status_browse.text = reason
	status_code.text   = reason
	status_main.text   = reason
	_show_screen("main")
