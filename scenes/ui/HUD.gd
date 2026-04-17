## HUD.gd
## Oyun içi ekran: takım skorları, oyuncu sağlığı.

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


func _ready() -> void:
	TeamManager.score_updated.connect(_on_score_updated)
	GameManager.game_ended.connect(_on_game_ended)
	end_panel.hide()
	_refresh_scores()


func _refresh_scores() -> void:
	for i in range(4):
		var score := TeamManager.scores.get(i, 0)
		score_labels[i].text = "%s: %d" % [TeamManager.get_team_name(i), score]
		score_labels[i].modulate = TeamManager.get_color(i)


func _on_score_updated(_team_id: int, _score: int) -> void:
	_refresh_scores()


func _on_game_ended(winning_team: int) -> void:
	end_panel.show()
	winner_label.text = "%s Takımı Kazandı!" % TeamManager.get_team_name(winning_team)
	winner_label.modulate = TeamManager.get_color(winning_team)


func _on_back_btn_pressed() -> void:
	GameManager.return_to_menu()
