# TacticalDark — Kod Haritası

3D top-down taktik nişancı, Godot 4.6 / GDScript 2.0, Forward+ renderer. 4 takım (5v5v5v5),
ENet multiplayer (port 7777). Karanlık harita + el feneri. Kart alıp kapıya teslim eden takım kazanır.

Bu dosya **fonksiyon/sinyal/RPC bağlantı haritasıdır** — "X nerede tetikleniyor", "Y'yi kim çağırıyor"
sorularına nokta atışı cevap vermek için. Davranış/karar gerekçeleri ve çözülen bug geçmişi için
auto-memory dosyalarına bak (özellikle `player_lighting.md`, `host_migration.md`, `known_bugs.md`).

## Autoload sırası (project.godot) — bozulursa parse hatası
`GameManager` → `TeamManager` → `RoomManager` → `NetworkManager` (RoomManager, NetworkManager'dan ÖNCE)

`scenes/ui/UITheme.gd` (**class_name, statik — autoload DEĞİL**): `UITheme.apply(get_tree())` (Main.gd + MainMenu._ready)
kodla Theme kurup `root.theme`'e atar (sahne geçişlerinde korunur, tüm sahneler etkilenir). Palet sabitleri
(`ACCENT` el feneri sarısı, `SURFACE*`, `TEXT_DIM`...), `style()`/`label()` helper'ları, fontlar (`font_bold/title/caps`).
Tip varyasyonları: Button → `PrimaryButton`/`GhostButton`/`TabButton`, Label → `TitleLabel`/`CapsLabel`/`DimLabel`.

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
| `send_chat(text, channel)` → `_chat_request` (any_peer) | ChatBox | host: gönderen = `get_remote_sender_id()` (0→1), flood koruması `CHAT_MIN_INTERVAL_MS`, `CHAT_MAX_LEN` kırpma, `"team"` ise sadece aynı takıma `_chat_receive` |
| `_chat_system(text)` (host) | `register_player` ("katıldı"), `_on_peer_disconnected` ("ayrıldı") | `channel="system"` herkese |
| `_chat_receive(msg)` (authority) | host → peer'lar | `chat_history`'ye ekler (max 60, sahne geçişinde korunur, `disconnect_all` temizler), `chat_received` sinyali |

### Host migration akışı (`_on_server_disconnected`)
1. `_saved_team_id` + `_migration_players` + `GameManager.get_migration_state()` snapshot alınır.
2. Kalan peer_id'ler sıralanır (host=1 hariç); **en küçük ID yeni host** olur.
3. Yeni host: 0.3s bekle → `create_server()` (players.clear() önemli, bkz known_bugs #28) →
   `host_migrated` sinyali → oyun `IN_GAME` ise `GameManager.restore_from_migration()`, değilse Lobby.tscn.
4. Diğerleri: 1.5s bekle → `RoomManager.start_listening()` → `_reconnect_loop()` aynı `room_name`'i bulup `join_server()`.
5. Kimse kalmadıysa → direkt Main.tscn.

**Sinyaller:** `server_created`, `joined_server`, `connection_failed`, `player_connected/disconnected`,
`player_list_updated`, `kicked(reason)`, `host_migrated`, `chat_received(msg)`.

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

**Dönüş mimarisi (ÖNEMLİ):** `look_at()` **Player ROOT'ta** uygulanır (`rotation.y` = nişan/fare), WeaponHolder+Flashlight
root'la birlikte nişana döner. **CharacterMesh** ise root'a göre `_leg_yaw` kadar ek döner (`_update_leg_facing`):
hareket ederken bacaklar hareket yönüne, `SpineTwistModifier` (Skeleton3D child, `SkeletonModifier3D`, spine_01..03)
üst gövdeyi `-_leg_yaw` ile nişana geri çevirir (max `MAX_SPINE_TWIST` ~110°); dururken bacaklar nişana döner.
Animasyon bu yüzden hep ileri oynar (geri koşu yok). `_mesh_base_basis` = tscn'deki 180° transform.
Player.gd modifier'ı `preload` ile yükler (global class cache'e bağımlı değil). Ölüm/respawn `_reset_leg_facing()`.
`_broadcast_state(pos, aim_y, mode)` ve `_interpolate_remote()` root `rotation.y` + hareket modu taşır/lerp eder.

**Hareket modları** (`MoveMode`, `_update_move_mode`): **varsayılan WALK** (×0.55, `Walk`) / RUN (Shift + hareket, ×1.0, `Run`)
/ CROUCH (Ctrl, ×0.35, `CrouchWalk`; dururken `speed_scale=0` donar). Dayanıklılık (sadece local, HUD okur):
`sprint_stamina` (`SPRINT_MAX_TIME=4s`, dolum 5s) ve `crouch_stamina` (`CROUCH_MAX_TIME=3s`, dolum 4s); bırakınca
`STAMINA_REGEN_DELAY` sonra dolar; tükenirse `*_locked` → `SPRINT_UNLOCK=0.4` / `CROUCH_UNLOCK=0.5`'e dolana kadar kullanılamaz
(çömelmesi biten otomatik kalkar). Respawn'da `_reset_stamina()`. `Input.is_physical_key_pressed` — project.godot'ya eklenmedi.
**Çömelme bağışıklığı:** `is_crouching()` → `Bullet._on_body_entered` mermiyi yok etmeden geçirir; host
`take_damage(amount, shooter, source)` `source==DAMAGE_BULLET` ise çömelmiş hedefe işlemez (host, `_broadcast_state` modunu kullanır).
Bomba `DAMAGE_EXPLOSION` (1) gönderir → çömelme korumaz.

**CharacterMesh 180° çevrili:** model yüzü +Z'ye bakıyor (Godot -Z-ileri kuralının tersi);
`Player.tscn`'de düzeltme transformu var. CharacterSelect.gd önizlemesi de buna göre ayarlı.

**CharacterMesh = `SurvivalistModel.tscn`** (eski Mixamo mankeni `anims/Breathing Idle.fbx` yerine, tüm karakterler):
`asset model/Survivalist/SK_Military_Survivalist.fbx` (UE mannequin iskeleti, 1.89 m, metre ölçekli) + `SurvivalistModel.gd`:
**`apply_outfit(character)`** — `Player.initialize()` ve `CharacterSelect._build_preview_world()` çağırır (çağrılmazsa
`DEFAULT_OUTFIT`). `OUTFITS[karakter]`: `vest` none/plain/pouches, `backpack`/`cap`/`gloves` bool, `skin` (parça → doku varyantı).
Tank siyah ağır, Visioner yeşil hafif, Runner teçhizatsız, Sniper çöl, Medic gri+zeytin çantalı.
Malzemeler kodla (`MATERIALS` → `_get_material`, `"malzeme:skin"` static cache, tüm oyuncular paylaşır):
dokular `asset model/Survivalist_Textures/Textures/{Body,Top,Bottom,Equip}` (FBX'in kendi doku yolu KULLANILMIYOR —
import'ta "Textures/Body/... bulunamadı" hataları zararsız). `.import` ayarları elle: normal map `normal_map_invert_y=true`
(UE/DirectX), renk 2K, ao/rough/metal 1K. `FPS_Arms/.gdignore`. Doku yoksa `FALLBACK_COLORS`.
FPS kolları (`ALWAYS_HIDDEN`) hep gizli. Animasyonlar `anims/survivalist_anims.res` (`tools/build_anim_library.gd` üretir):
`Idle, Walk, Run, CrouchWalk, Talk, Jump, Death` (`anims/Basic+Demo+Animations/*.FBX` — aynı UE iskelet, doğrudan uyumlu;
ik_* kemik, scale ve pelvis dışı position track'leri atılır) + yedek `Breathing Idle` (Mixamo bake, `tools/retarget_bake.gd`).
`_setup_idle()` hepsini varsayılan kütüphaneye ekler, autoplay `Idle`. Kullanılmayan: Walk/CrouchWalk/Jump/Talk (mekanik yok).

| Fonksiyon | Ne zaman | Not |
|---|---|---|
| `initialize(peer_id, team_id, character)` | spawn anında | stat/hız ayarla, `_find_anim_player`, `_play_idle`, `_add_render_layer` (BodyLight izolasyonu), `_disable_shadow_casting`, `is_local` ise `_apply_self_rim` |
| `_handle_local_input(delta)` | `_physics_process`, sadece local | WASD, `look_at` (root), ateş, reload, 20Hz `_broadcast_state.rpc()` |
| `_interpolate_remote(delta)` | `_physics_process`, uzak oyuncular | pos+rotation lerp |
| `_update_animation(delta)` | `_physics_process` (local + uzak, ölüyken çağrılmaz) | hız = konum farkı/delta (uzaklarda velocity yok) → `_update_leg_facing` + `Idle` / `MOVE_ANIMS[move_mode]` (`speed_scale` = hız/`MOVE_ANIM_REF_SPEED[mode]`), blend `ANIM_BLEND` |
| `_get_aim_target()` | `_handle_local_input` | mouse → kamera ray → Y=0.9 zemin düzlemi kesişimi |
| `take_damage(amount, shooter_id)` (any_peer RPC) | `Bullet._on_body_entered` | **sadece host işler** (`if not is_host(): return`), `_sync_health.rpc()`, 0 ise `_die()` |
| `_die(killer_id)` | `take_damage` | `_apply_death.rpc()` + `GameManager.handle_player_death()` |
| `_apply_death()` (call_local RPC) | `_die` | `Death` animasyonu oynar, mesh `_hide_corpse_later` ile anim bitince gizlenir (`_death_token` respawn'da iptal eder); flashlight/body_light/silah gizle, collision disable (deferred), card_indicator gizle |
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

- `Map.gd`: spawn noktalarını okur (`SpawnPoints/Team{0..3}/Marker3D` çocukları) → `TeamManager.register_spawn_points()`,
  ve `_build_maze_collision()`: `Maze/MazeMesh` mesh'inden `create_trimesh_shape()` ile duvar çarpışması (layer 1 →
  oyuncu + mermi takılır). Haritanın geri kalanı **editörde kullanıcı tarafından** düzenlenir.
- **Labirent:** `asset model/Maze_walls.obj` = `Maze.obj`'nin sadece `maze` objesi (zemin Plane01 atıldı), ortalanmış,
  XZ ×0.5, Y → 3 m, düz normaller (`tools/maze_convert.py` ile üretildi; nokta seçimi + minimap PNG `tools/maze_points.py`
  — orijinali değiştirme, script'le yeniden üret).
  Ayak izi x ±62, z ±46; koridor ~4 m, duvar ~2 m kalın. Zemin 126×94, `Bounds` görünmez sınır (üst girişler dışarı açılmasın).
  `Maze_minimap.png` (1 px = 1 m duvar maskesi) → Minimap `MAP_MIN/MAX` ile birebir.
- `CardPoints` / `DoorPoints` (Map.tscn Marker3D'leri): `GameManager._spawn_card_and_door()` → `_get_marker_positions()`
  rastgele birini seçer (eski sabit koordinatlar duvara denk geliyordu). `TeamManager.get_spawn_position` ofseti ±0.6 m.
- `Card.gd` (Area3D): `_on_body_entered` — sadece local oyuncu + ölü değil + kart yok + pickup-blocked değilse →
  host ise `GameManager.handle_card_pickup()` direkt, client ise `request_card_pickup.rpc_id(1,...)`.
- `Door.gd` (Area3D): aynı patern, `has_card` kontrolü → `handle_card_delivered()` / `request_card_delivery`.
- **`PowerupManager.gd`** (Map.tscn → `PowerupManager` Node; RPC'ler bu node path'iyle, tüm peer'larda aynı):
  host `_process` → `SPAWN_INTERVAL` (8-15s) aralıkla `PowerupPoints/Point*` (33 köşe, `tools/maze_corners.py`)
  üzerinde `_spawn_rpc(id, type, pos, lifetime 5-10s)`, `MAX_ACTIVE=3`, ömür dolunca `_despawn_rpc`.
  Tipler `Type {BOMB, HEAL, INTEL_SAT, ENEMY_SAT}`, görünüm/isim `INFO` (HUD/Minimap/Powerup ortak).
  Alma: `Powerup.gd` yerel oyuncu ≤1.3 m + slot boşsa `local_touched` → `_request_pickup` (host: mesafe/ölü/slot
  kontrolü) → `_set_item_rpc(peer, type)` (herkese; `inventory` peer→type, tek slot). Ölünce `kill_happened` → slot boşalır.
  Kullanma: `Q` (`_unhandled_key_input`, sohbette değilken) → `_request_use(aim)` host:
  HEAL +60 (`_sync_health`), BOMB `_throw_bomb` (maks 12 m, duvara ışınla kırpılır) → `_bomb_rpc` (Bomb.gd görsel) +
  `_detonate_later` (r=4 m, 75→%35 düşüş, duvar arkası/dost/kendisi hasarsız, `take_damage(dmg, peer)` → kill kredisi),
  INTEL_SAT/ENEMY_SAT → `_reveal_rpc(team, "objectives"/"enemies", 8/6 s)` → o takımda `reveal_until`, Minimap çizer;
  düşmanlara "konumunuz tespit edildi" uyarısı. Sinyaller: `inventory_changed`, `reveal_started`, `notice` (HUD banner).
  Geç katılan client 1.5 s sonra `_request_sync`. HUD envanter slotu oyuncu kartının sağında.
- **`WallLamps.gd`** (Map.tscn → `WallLamps` Node3D, çocukları `Lamp*` Marker3D — `tools/maze_lamps.py` üretir,
  32 adet, editörde taşınabilir): her marker'da armatür + emissive ampul + OmniLight (gölgesiz, r=6.5) +
  `LightShaft.gdshader` huzmesi (additive, kenar/aşağı sönümlü). Marker -Z'si koridora bakar, y=2.75 (duvar tepesi 3 m).
  Tip lamba sırasına göre seed'li RNG ile (her client'ta aynı): STEADY %55 sodyum, FLICKER %30 floresan patlamalı,
  DYING %15 çoğunlukla sönük. Tamamen yerel görsel, ağ yok.
- `ProximityReveal.gd` (Card.tscn + Door.tscn + Powerup child Node; alt ağacın tümünü tarar): parent'ın OmniLight3D/Label3D/MeshInstance3D'lerini SADECE
  yerel oyuncu yaklaşınca açar (`reveal_far`→`reveal_near` smoothstep + fade). Kart 12→5 m, kapı 16→7 m.
  Tamamen yerel görsel, ağ/mantık yok; Area3D çarpışması etkilenmez.
- `CameraController.gd`: Player'ın child'ı DEĞİL, Map.tscn'de bağımsız Camera3D. `GameManager.local_player_spawned`
  sinyaline bağlanır. Exponential lerp (`1-exp(-7*delta)`), OFFSET `(0,14,12)`, PITCH -50°.

---

## scenes/ui/ — menü/lobi/karakter seçimi/HUD

- **MainMenu.gd**: UI tamamen kodla (tscn sadece kök). Sol: logo + operatör adı (`user://settings.cfg`'ye kaydedilir).
  Sağ: sekmeler `browse`/`create`/`code` (`_show_tab`; `RoomManager.start_listening` SADECE browse'da açık) + şifreli oda modalı.
  Arka plan `MenuBackdrop.gdshader` (fareyi takip eden el feneri + ızgara). `NetworkManager.create_server/join_server`
  çağırır, `server_created`/`joined_server`/`connection_failed`/`kicked` sinyallerini dinler.
- **Lobby.gd**: UI tamamen kodla (tscn sadece kök), UITheme paleti + MenuBackdrop (ışık rengi kendi takımına döner).
  Üst: oda adı, oyuncu sayısı, oda kodu + Kopyala (`DisplayServer.clipboard_set`). 4 takım kartı × `TEAM_SIZE=5` slot
  (tıklanabilir → `request_change_team`; dolu/kendi takımı client tarafında engelli — host'ta takım limiti YOK).
  `_refresh_player_list()` → `player_list_updated`'e bağlı, takım seçmeyenler (team_id<0) alt şeritte.
  Hazır durumu local değişken değil `players[local]["is_ready"]`'den okunur. Start: `_are_teams_balanced()` + herkes ready.
- **Crosshair.gd** (HUD `_root`'a ekler): fare yerine nişangah, açıkken `MOUSE_MODE_HIDDEN` (`_exit_tree` geri açar).
  Boşluk = oyuncuya ekran mesafesi × tan(`weapon.spread_degrees`), atışta tepme, şarjör halkası (`reload_time`).
  Gizli: ölü / sohbete yazarken / `allowed=false` (HUD: pause/oyun sonu).
- **ChatBox.gd** (class_name, PanelContainer): `mode` LOBBY (hep açık, `chat_history` gösterir) / GAME (lobi geçmişi
  YOK, sadece maç içi mesajlar `_game_lines`; kapalıyken her mesaj `SHOW_TIME=4.5`s görünür + `FADE_TIME` söner).
  Enter aç/gönder, Tab kanal (HERKES/TAKIM), Esc kapat, T (GAME) takım kanalıyla aç, `/t` `/a` önekleri.
  `_input()` ile tuşları GUI'den önce yakalar. **`static var is_typing`** → Player.gd hareket/ateş/reload'u, HUD TAB'ı kilitler.
  Oyuncu metni BBCode'a `[`→`[lb]` ile kaçışlanır. Lobby (alt sol) + HUD (oyuncu kartı üstü) kullanır.
- **CharacterSelect.gd**: 5 karakter kartı, her biri SubViewport içinde Player.tscn önizlemesi
  (`set_script(null)` ile kodsuz, sadece görsel; kamera/ışık CharacterMesh'in 180° çevrili yönüne göre ayarlı).
  **`sv.own_world_3d = true` şart** — yoksa 5 SubViewport aynı World3D'yi paylaşır, tüm modeller her kartta üst üste görünür.
  Önizlemede `CharacterMesh.apply_outfit(char_name)` çağrılır; ana ışık nötr, karakter rengi sadece arka kenar ışığı.
  Seçim → `NetworkManager.request_select_character()`.
- **HUD.gd**: UI tamamen kodla (tscn sadece CanvasLayer), UITheme paleti, tüm katmanlar `_root` (mouse IGNORE) altında.
  Skor (sol üst, kendi takımı vurgulu), hedef çipi + uyarı bandı (üst orta; `_carrier_peer` card_picked_up/dropped ile
  güncellenir), kill feed (sağ üst), oyuncu kartı (sol alt: karakter, can, mermi; şarjör ilerlemesi `weapon.reload_time` tween'i),
  Minimap (sağ alt), düşük can/hasar vinyeti, ölüm ekranı (`_local_player.is_dead` poll + `RESPAWN_TIME=3` geri sayım),
  TAB scoreboard, ESC pause, oyun sonu (`_end_overlay`, ZAFER/YENİLGİ). "Ana Menüye Dön" → `GameManager.return_to_menu()`.
  Oyun mantığına dokunmaz — sadece sinyal dinler.

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
