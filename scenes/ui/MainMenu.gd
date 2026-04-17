## MainMenu.gd
## Ana menü: Sunucu oluştur veya katıl.

extends Control

@onready var name_input: LineEdit = $VBoxContainer/NameInput
@onready var host_btn: Button = $VBoxContainer/HostButton
@onready var join_btn: Button = $VBoxContainer/JoinButton
@onready var ip_input: LineEdit = $VBoxContainer/IPInput
@onready var status_label: Label = $VBoxContainer/StatusLabel


func _ready() -> void:
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.joined_server.connect(_on_joined_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	name_input.text = "Oyuncu_%d" % randi_range(100, 999)


func _on_host_button_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		status_label.text = "Lütfen bir isim girin!"
		return
	status_label.text = "Sunucu oluşturuluyor..."
	NetworkManager.create_server(player_name)


func _on_join_button_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	var ip := ip_input.text.strip_edges()
	if player_name.is_empty():
		status_label.text = "Lütfen bir isim girin!"
		return
	if ip.is_empty():
		ip = "127.0.0.1"
	status_label.text = "Bağlanıyor: %s..." % ip
	NetworkManager.join_server(ip, player_name)


func _on_server_created() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")


func _on_joined_server() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")


func _on_connection_failed() -> void:
	status_label.text = "Bağlantı başarısız!"
