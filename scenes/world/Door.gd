## Door.gd (3D)
## Harita köşesinde spawn olan kapı objesi.
## Kartı taşıyan yerel oyuncu girince teslimat isteği gönderir.

extends Area3D


func _on_body_entered(body: Node) -> void:
	if not (body is CharacterBody3D):
		return
	if body.get("peer_id") != NetworkManager.get_local_id():
		return
	if not body.get("has_card"):
		return

	var my_id := NetworkManager.get_local_id()
	if NetworkManager.is_host():
		GameManager.handle_card_delivered(my_id)
	else:
		GameManager.request_card_delivery.rpc_id(1, my_id)
