## Card.gd (3D)
## Harita ortasında spawn olan kart objesi.
## Üzerine giren yerel oyuncu pickup isteği gönderir.

extends Area3D


func _on_body_entered(body: Node) -> void:
	if not visible:
		return
	if not (body is CharacterBody3D):
		return
	if body.get("peer_id") != NetworkManager.get_local_id():
		return
	if body.get("is_dead"):
		return
	if body.get("has_card"):
		return
	var _blocked = body.get("_card_pickup_blocked")
	if _blocked != null and (_blocked as float) > 0.0:
		return

	var my_id := NetworkManager.get_local_id()
	if NetworkManager.is_host():
		GameManager.handle_card_pickup(my_id)
	else:
		GameManager.request_card_pickup.rpc_id(1, my_id)
