# TacticalDark — Kod Haritası

3D top-down taktik nişancı, Godot 4.6 / GDScript 2.0, Forward+ renderer. 4 takım (5v5v5v5),
ENet multiplayer (port 7777). Karanlık harita + el feneri. Kart alıp kapıya teslim eden takım kazanır.

Bu dosya **fonksiyon/sinyal/RPC bağlantı haritasıdır** — "X nerede tetikleniyor", "Y'yi kim çağırıyor"
sorularına nokta atışı cevap vermek için. Davranış/karar gerekçeleri ve çözülen bug geçmişi için
auto-memory dosyalarına bak (özellikle `player_lighting.md`, `host_migration.md`, `known_bugs.md`).

## Autoload sırası (project.godot) — bozulursa parse hatası
`GameManager` → `TeamManager` → `RoomManager` → `NetworkManager` (RoomManager, NetworkManager'dan ÖNCE)

---

## autoload/NetworkManager.gd — ağ/lobi/oyuncu kaydı, host migration

**State:** `players: Dictionary` (peer_id → `{name, team_id, is_ready, character}`), `_local_id_cache`,
`_is_migrating`, `_saved_team_id`, `_migration_players`, `_pending_migration_state`.

| Fonksiyon | Çağıran | Ne yapar |
|---|---|---|
| `create_server(name, room, pw)` | MainMenu, migration (yeni host) | ENet server kurar, **`players.clear()`** sonra `players[1]=...`, `RoomManager.create_room()` |
| `join_server(ip, name, pw)` | MainMenu, migration (reconnect) | ENet client kurar, `_on_connected_to_server` ile `register_player` RPC tetikler |
| `disconnect_all()` | `GameManager.return_to_menu()` | peer kapat + tüm state sıfırla + RoomManager durdur |
| `_on_server_disconnected()` | ENet sinyali (host çöktü/ayrıldı) | **host migration başlangıcı** — bkz aşağı |
| `register_player.rpc_id(1,...)` (any_peer) | client → host | host: şifre kontrolü, `players[peer_id]` ekler, `receive_player_list` + `_accept_player` geri yollar |
| `_accept_player(migration_state,...)` (authority) | host → client | `IN_GAME` ise `GameManager.restore_from_migration()`, değilse `joined_server` sinyali |
| `request_change_team(team_id)` / `_change_team` | Lobby panel click | takım değiştir, broadcast |
| `set_ready(bool)` / `_set_ready_rpc` | Lobby "Hazır" butonu | ready flag, broadcast |
| `_are_teams_balanced()` | Lobby, start butonu guard | en az 2 takımda eşit sayı |
| `request_select_character(name)` / `_apply_character_selection` | CharacterSelect | takım-içi benzersizlik kontrolü, `GameManager.check_all_characters_selected()` çağırır |

### Host migration akışı (`_on_server_disconnected`)
1. `_saved_team_id` + `_migration_players` + `GameManager.get_migration_state()` snapshot alınır.
2. Kalan peer_id'ler sıralanır (host=1 hariç); **en küçük ID yeni host** olur.
3. Yeni host: 0.3s bekle → `create_server()` (players.clear() önemli, bkz known_bugs #28) →
   `host_migrated` sinyali → oyun `IN_GAME` ise `GameManager.restore_from_migration()`, değilse Lobby.tscn.
4. Diğerleri: 1.5s bekle → `RoomManager.start_listening()` → `_reconnect_loop()` aynı `room_name`'i bulup `join_server()`.
5. Kimse kalmadıysa → direkt Main.tscn.

**Sinyaller:** `server_created`, `joined_server`, `connection_failed`, `player_connected/disconnected`,
`player_list_updated`, `kicked(reason)`, `host_migrated`.

---

## autoload/GameManager.gd — oyun durumu, spawn, kart/kapı, ölüm

**State enum:** `MENU, LOBBY, CHARACTER_SELECT, IN_GAME, ENDED`.
`active_players: Dictionary` (peer_id → Player node), `player_stats` (peer_id → {kills,deaths}),
`card_carrier_peer_id` (-1 = kart yerde), `card_instance`, `door_instance`.

| Fonksiyon | Tetikleyen | Akış |
|---|---|---|
| `start_game()` | Lobby "Oyunu Başlat" (host) | `TeamManager.reset()` → `_start_game_rpc` → CharacterSelect sahnesi |
| `check_all_characters_selected()` | `NetworkManager._apply_character_selection` | herkes seçtiyse `_begin_actual_game_rpc` |
| `_begin_actual_game_rpc()` | kendi | Map.tscn yükle → `_spawn_local_player()` → host ise `_spawn_card_and_door()` → `game_started` sinyali |
| `_spawn_local_player()` | `_begin_actual_game_rpc`, `restore_from_migration` | Player instantiate, `initialize()`, `_notify_player_spawned.rpc()` broadcast, client ise `_request_active_players.rpc_id(1)` |
| `handle_card_pickup(peer_id)` | `Card.gd._on_body_entered` (host) veya `request_card_pickup` RPC | `_apply_card_pickup_rpc` broadcast → `card_picked_up` sinyali |
| `handle_card_drop(pos)` | ölüm sırasında taşıyıcı öldüyse, veya host | `_apply_card_drop_rpc` broadcast → `card_dropped` sinyali |
| `handle_card_delivered(peer_id)` | `Door.gd._on_body_entered` (host) | `state=ENDED`, `_end_game_rpc.rpc(team_id)` |
| `handle_player_death(dead, killer)` | `Player._die()` (host) | kill sayısı artır, `_announce_kill_rpc` broadcast, kart taşıyıcıysa düşür, `_schedule_respawn()` |
| `_schedule_respawn(peer_id)` | kendi | 3s bekle, `is_instance_valid()` kontrolü, `TeamManager.get_spawn_position()`, `player.respawn()` |
| `on_player_disconnected(peer_id)` | `NetworkManager._on_peer_disconnected` (host+client) | kart düşür, node temizle, `_check_last_team_standing()` |
| `_check_last_team_standing()` | `on_player_disconnected`, migration sonrası | tek takım kaldıysa `_end_game_rpc` |
| `get_migration_state()` / `restore_from_migration()` | host migration | kart/kapı pozisyonu + skor snapshot → yeni sahnede geri yükleme |
| `return_to_menu()` | HUD "Ana Menüye Dön" / pause menü | state temizle, `NetworkManager.disconnect_all()`, Main.tscn |

**Sinyaller:** `game_started`, `game_ended(team_id)`, `local_player_spawned(player)`,
`card_picked_up(peer,pos,team)`, `card_dropped(pos,team)`, `kill_happened(killer,victim)`.

**Önemli:** Hasar/kill/kart/respawn mantığının TÜMÜ host guard'lı (`if not NetworkManager.is_host(): return`).
Client'lar sadece `request_*` RPC'leriyle host'a istek yollar.

---

## autoload/TeamManager.gd — takım renk/isim/skor/spawn

- `TEAM_COLORS[4]`, `TEAM_NAMES[4]` (Mavi/Kırmızı/Yeşil/Sarı) — sabit index 0-3.
- `scores: Dictionary`, `add_kill(team_id)` → `_sync_score_rpc.rpc()` → `score_updated` sinyali.
- `spawn_points: Dictionary` — `Map.gd._register_spawn_points()` tarafından doldurulur (editörde yapılan haritadan).
- `get_spawn_position(team_id)`: rastgele nokta + ±2.5 XZ ofset (üst üste doğmayı engeller).
- `team_won(team_id)` sinyali → `GameManager._on_team_won()` dinler (MAX_SCORE artık kazanma koşulu DEĞİL, sadece referans — gerçek kazanma kart/kapı).

---

## autoload/RoomManager.gd — LAN keşif + oda kodu

- UDP broadcast port 7778, 2s aralık. Host `_send_broadcast()`, client `_receive_broadcasts()`.
- Oda kodu: host IPv4 → base-32 7 hane (`_ip_to_code`/`_code_to_ip`), alfabe `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (0/1/I/O yok).
- `get_ip_for_code(code)`: önce keşfedilen listede ara, yoksa decode et, yoksa direkt IP kabul et (localhost testi).
- `create_room()`/`stop_hosting()`/`start_listening()`/`stop_listening()` — NetworkManager tarafından çağrılır.

---

## scenes/player/Player.gd — hareket/nişan/hasar/ölüm (CharacterBody3D)

**Dönüş mimarisi (ÖNEMLİ):** `look_at()` **Player ROOT'ta** uygulanır (`rotation.y`), WeaponHolder+Flashlight+
CharacterMesh hepsi child olarak BİRLİKTE döner — ayrı ayrı döndürülmüyor (asker gibi gövdeyle nişan).
`_broadcast_state(pos, aim_y)` ve `_interpolate_remote()` de root `rotation.y` taşır/lerp eder.

**CharacterMesh 180° çevrili:** Mixamo FBX yüzü Godot'un -Z-ileri kuralının tersine import edilmiş;
`Player.tscn`'de düzeltme transformu var. CharacterSelect.gd önizlemesi de buna göre ayarlı.

| Fonksiyon | Ne zaman | Not |
|---|---|---|
| `initialize(peer_id, team_id, character)` | spawn anında | stat/hız ayarla, `_find_anim_player`, `_play_idle`, `_add_render_layer` (BodyLight izolasyonu), `_disable_shadow_casting`, `is_local` ise `_apply_self_rim` |
| `_handle_local_input(delta)` | `_physics_process`, sadece local | WASD, `look_at` (root), ateş, reload, 20Hz `_broadcast_state.rpc()` |
| `_interpolate_remote(delta)` | `_physics_process`, uzak oyuncular | pos+rotation lerp |
| `_get_aim_target()` | `_handle_local_input` | mouse → kamera ray → Y=0.9 zemin düzlemi kesişimi |
| `take_damage(amount, shooter_id)` (any_peer RPC) | `Bullet._on_body_entered` | **sadece host işler** (`if not is_host(): return`), `_sync_health.rpc()`, 0 ise `_die()` |
| `_die(killer_id)` | `take_damage` | `_apply_death.rpc()` + `GameManager.handle_player_death()` |
| `_apply_death()` (call_local RPC) | `_die` | mesh/flashlight/body_light gizle, collision disable (deferred), card_indicator gizle |
| `respawn(pos)` → `_apply_respawn()` (call_local RPC) | `GameManager._schedule_respawn` | can/visibility/collision resetle, `reset_physics_interpolation()`, `_card_pickup_blocked=0.5` |
| `pick_up_card()` / `drop_card()` | `GameManager._apply_card_pickup_rpc` / `_apply_card_drop_rpc` | `card_indicator` sadece aynı takıma görünür |

**Aydınlatma/görünürlük helper'ları (recursive, node ağacında gezer):**
- `_add_render_layer(node, bit)` — `BODY_LIGHT_LAYER_BIT=20`: BodyLight sadece CharacterMesh+silaha değsin, zemine ışık taşmasın.
- `_disable_shadow_casting(node)` — Flashlight kendi gövdesinden/silahtan dev gölge atmasın (`cast_shadow=OFF`).
- `_apply_self_rim(node)` — SADECE `is_local`: `SelfVisibility.gdshader` ile `material_overlay` ekler, karanlıkta kendi karakterini görünür kılar. Gerçek ışık değil, diğer client'lar görmez.

**Friendly fire kapalı:** Bu dosyada değil, bkz `Bullet.gd`.

**CHARACTER_STATS / WEAPON_CONFIGS** (const dict, karakter adıyla key'li): Tank/Visioner/Runner/Sniper/Medic
— can, hız, hasar, ateş hızı, mermi sayısı, saçılma, menzil, semi/full-auto.

---

## scenes/weapons/Weapon.gd + Bullet.gd — ateş/mermi

- `Weapon.try_shoot(shooter_peer, shooter_team)`: ammo/fire_rate/reload kontrolü → `holder.global_transform.basis.z`
  ters yönü (forward) + saçılma açısı → `_spawn_bullet.rpc()` (call_local).
- `Bullet.initialize(dir, speed, dmg, shooter_peer, shooter_team, max_dist)`: yatay düzlemde hareket.
- `Bullet._on_body_entered(body)`:
  1. `body.peer_id == shooter_peer_id` → `return` (kendi mermisi, spawn anı self-hit önlenir, queue_free YOK).
  2. `body.team_id == shooter_team_id` → **friendly fire yok**, `queue_free()` (hasarsız yok olur).
  3. Diğer: SADECE atan oyuncunun client'ı hasar bildirir (`NetworkManager.get_local_id()==shooter_peer_id`) —
     host ise direkt `take_damage()`, değilse `take_damage.rpc_id(1,...)`. Çift hasar böyle önlenir.
- `Weapon.configure(config)`: karakter silah ayarlarını uygular, `ammo_changed` sinyali emit eder.

---

## scenes/world/ — harita, kart, kapı

- `Map.gd`: SADECE spawn noktalarını okur (`SpawnPoints/Team{0..3}/Marker3D` çocukları) →
  `TeamManager.register_spawn_points()`. Haritanın geri kalanı (duvar/zemin) **editörde kullanıcı tarafından** yapılıyor.
- `Card.gd` (Area3D): `_on_body_entered` — sadece local oyuncu + ölü değil + kart yok + pickup-blocked değilse →
  host ise `GameManager.handle_card_pickup()` direkt, client ise `request_card_pickup.rpc_id(1,...)`.
- `Door.gd` (Area3D): aynı patern, `has_card` kontrolü → `handle_card_delivered()` / `request_card_delivery`.
- `CameraController.gd`: Player'ın child'ı DEĞİL, Map.tscn'de bağımsız Camera3D. `GameManager.local_player_spawned`
  sinyaline bağlanır. Exponential lerp (`1-exp(-7*delta)`), OFFSET `(0,14,12)`, PITCH -50°.

---

## scenes/ui/ — menü/lobi/karakter seçimi/HUD

- **MainMenu.gd**: 3 ekran (main/create/browse) + JoinCodePanel modal. `NetworkManager.create_server/join_server`
  çağırır, `server_created`/`joined_server`/`kicked` sinyallerini dinler.
- **Lobby.gd**: `_setup_team_panels()` kodla 4 panel oluşturur (tıklanabilir → `request_change_team`).
  `_refresh_player_list()` → `NetworkManager.player_list_updated` sinyaline bağlı, spectator (team_id<0) ayrı listelenir.
  Start butonu: `_are_teams_balanced()` + herkes ready ise aktif.
- **CharacterSelect.gd**: 5 karakter kartı, her biri SubViewport içinde Player.tscn önizlemesi
  (`set_script(null)` ile kodsuz, sadece görsel; kamera/ışık CharacterMesh'in 180° çevrili yönüne göre ayarlı).
  Seçim → `NetworkManager.request_select_character()`.
- **HUD.gd**: Kill feed (sağ üst), Minimap (sağ alt, `Minimap.gd` script atanır), kart banner (üst merkez),
  skor paneli (sol üst), HP/ammo (sol alt), TAB scoreboard (`_refresh_scoreboard`, takım bazlı kill/death grid),
  ESC pause menü. `GameManager.game_ended` → `end_panel.show()`. "Ana Menüye Dön" → `GameManager.return_to_menu()`.

---

## Kritik GDScript/Godot 4.6 tuzakları (tekrar düşmemek için)

- `Object.get(key)` — Dictionary.get'in aksine **tek argüman alır**, varsayılan değer parametresi yok.
- `absf/clampf/minf/maxf` kullan (strict variant tipi, Godot 4.6).
- Sahne geçişi `_ready()` içindeyse `change_scene_to_file.call_deferred(...)`.
- `global_position` ayarlamadan önce `add_child()` çağrılmış olmalı (tree içinde olmalı).
- `await` sonrası node kontrolü: `queue_free()` sonrası obje null DEĞİL, `is_instance_valid()` kullan.
- Collision disable'ı physics callback içinde yaparken `set_deferred("disabled", true)`.
- RPC çağırmadan önce `multiplayer.get_peers().size() > 0` kontrolü (bağlı peer yoksa hata).
- Hasar/skor/kart gibi yetkili state değişiklikleri SADECE host'ta işlenir — host guard'ı unutma.

Detaylı "neden böyle yapıldı" gerekçeleri ve kronolojik bug geçmişi: auto-memory
(`architecture_decisions.md`, `player_lighting.md`, `host_migration.md`, `known_bugs.md`).
