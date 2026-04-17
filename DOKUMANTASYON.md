# TacticalDark — Kod Dokümantasyonu
**Hazırlayan:** Claude (AI)
**Proje:** TacticalDark — 4 Takımlı Online 2D Nişancı
**Motor:** Godot 4.6 / GDScript 2.0

---

## İÇİNDEKİLER

1. [Projeye Genel Bakış](#1-projeye-genel-bakış)
2. [Klasör ve Dosya Yapısı](#2-klasör-ve-dosya-yapısı)
3. [Temel Kavramlar (Okumadan Devam Etme)](#3-temel-kavramlar)
4. [Autoload / Global Scriptler](#4-autoload--global-scriptler)
   - 4.1 GameManager.gd
   - 4.2 NetworkManager.gd
   - 4.3 TeamManager.gd
5. [Oyun Sahneleri](#5-oyun-sahneleri)
   - 5.1 Main.gd
   - 5.2 MainMenu.gd
   - 5.3 Lobby.gd
   - 5.4 HUD.gd
   - 5.5 Map.gd
6. [Oyuncu Sistemi](#6-oyuncu-sistemi--playergd)
7. [Silah ve Mermi Sistemi](#7-silah-ve-mermi-sistemi)
   - 7.1 Weapon.gd
   - 7.2 Bullet.gd
8. [Işık Sistemi](#8-ışık-sistemi--streetlampgd)
9. [Ağ Mimarisi — Büyük Resim](#9-ağ-mimarisi--büyük-resim)
10. [Oyunun Akışı (Baştan Sona)](#10-oyunun-akışı-baştan-sona)
11. [Kritik Tasarım Kararları ve Nedenleri](#11-kritik-tasarım-kararları-ve-nedenleri)
12. [Bilinen Sınırlamalar ve Gelecek Geliştirme Alanları](#12-bilinen-sınırlamalar-ve-gelecek-geliştirme-alanları)

---

## 1. Projeye Genel Bakış

TacticalDark, karanlık bir haritada el feneri ile görüş sağlayan, 4 takımlı (en fazla 20 oyuncu) gerçek zamanlı çevrimiçi bir 2D nişancı oyunudur. Oyun yukarıdan aşağıya (top-down) görünümdedir.

**Temel özellikler:**
- WASD ile hareket, mouse ile nişan alma ve ateş etme
- El feneri (koni şeklinde ışık, mouse yönüne döner)
- Sokak lambaları ve bina ışıkları ile çevre aydınlatması
- 4 takım (Mavi, Kırmızı, Yeşil, Sarı) — her biri 5 oyuncuya kadar
- İlk 30 öldürmeye ulaşan takım kazanır
- ENet protokolü ile online multiplayer (Port 7777)

---

## 2. Klasör ve Dosya Yapısı

```
D:/Godot proje/
│
├── project.godot              ← Godot proje ayarları (GL Compatibility grafik modu)
├── icon.svg                   ← Geçici oyuncu sprite (Godot robot logosu)
│
├── autoload/                  ← Her yerden erişilebilen global scriptler
│   ├── GameManager.gd         ← Oyun durumu, sahne geçişleri, spawn/respawn
│   ├── NetworkManager.gd      ← Ağ bağlantısı, lobi, oyuncu kaydı
│   └── TeamManager.gd         ← 4 takım: renk, isim, puan, spawn noktaları
│
├── scenes/
│   ├── main/
│   │   ├── Main.tscn          ← Giriş noktası sahnesi
│   │   └── Main.gd            ← Sadece MainMenu'ye yönlendirir
│   │
│   ├── ui/
│   │   ├── MainMenu.tscn+gd   ← "Sunucu Kur" ve "Katıl" ekranı
│   │   ├── Lobby.tscn+gd      ← Takım seçimi ve hazır olma ekranı
│   │   └── HUD.tscn+gd        ← Oyun içi skor tablosu ve kazananı gösterir
│   │
│   ├── player/
│   │   ├── Player.tscn        ← Oyuncu sahnesi (sprite, ışık, sağlık çubuğu)
│   │   └── Player.gd          ← Hareket, nişan, ateş, hasar, ölüm, respawn
│   │
│   ├── weapons/
│   │   ├── Weapon.tscn+gd     ← Silah: ateş hızı, mermi sayısı, şarj
│   │   └── Bullet.tscn+gd     ← Mermi: hareket, çarpışma, hasar bildirimi
│   │
│   ├── lighting/
│   │   ├── StreetLamp.tscn+gd ← Sokak lambası (titreme özellikli)
│   │   └── BuildingLight.tscn ← Bina ışığı (script yok, editörde ayarlanır)
│   │
│   └── world/
│       ├── Map.tscn           ← Harita (editörde kullanıcı tarafından yapılır)
│       └── Map.gd             ← Spawn noktalarını TeamManager'a kaydeder
```

---

## 3. Temel Kavramlar

Bu bölümü okumadan kod açıklamalarını tam anlayamazsınız.

### 3.1 Autoload Nedir?

Godot'ta bazı scriptler **her yerden erişilebilir** hale getirilir. Bu `autoload` sistemidir. `GameManager`, `NetworkManager`, `TeamManager` üçü de autoload'dur. Yani herhangi bir script bunlara `GameManager.start_game()` gibi doğrudan erişebilir. Oyun çalıştığı sürece bellekte kalırlar, sahne geçişlerinde silinmezler.

### 3.2 RPC (Remote Procedure Call) Nedir?

RPC, bir bilgisayarın ağ üzerindeki başka bir bilgisayarda fonksiyon çalıştırmasıdır. Örneğin host, bütün clientlara "oyuncu öldü, sprite'ı griye boyayın" demek istediğinde `_apply_death.rpc()` çağırır — bu fonksiyon **tüm bağlı cihazlarda** otomatik olarak çalışır.

**RPC türleri bu projede:**
| Tür | Ne Zaman Kullanılır |
|-----|---------------------|
| `rpc()` | Tüm bağlı cihazlara gönder |
| `rpc_id(1, ...)` | Sadece sunucuya (host) gönder (id=1 her zaman host'tur) |
| `rpc_id(peer_id, ...)` | Sadece belirli bir oyuncuya gönder |
| `call_local` | RPC + kendi cihazında da hemen çalıştır |
| `reliable` | Paket kaybolursa tekrar gönder (önemli veriler için) |
| `unreliable_ordered` | En hızlı, kayıplar önemli değil (pozisyon güncellemeleri için) |

### 3.3 Host / Client Farkı

Bu oyun **listen server** mimarisindedir: oyunu kuran kişi (host) hem sunucu hem oyuncu olarak çalışır. Diğerleri client'tır.

- **Host'un id'si her zaman 1'dir**
- `multiplayer.is_server()` → "Ben host miyim?" sorusunun cevabı
- `multiplayer.get_unique_id()` → "Benim id'm ne?"

### 3.4 Signal (Sinyal) Nedir?

Bir script başka bir scripte "şu olay oldu" demek istediğinde signal kullanır. Örneğin `TeamManager`, 30. öldürme yapıldığında `team_won` sinyalini yayar. `GameManager` bu sinyale bağlıdır ve oyunu bitirir. Sinyaller scriptler arasında gereksiz bağımlılığı önler.

### 3.5 Authority (Yetki) Kavramı

Her oyuncu node'unun bir "sahibi" vardır. O node'un hareketi, durumu sadece sahibi tarafından kontrol edilir. `set_multiplayer_authority(peer_id)` ile atanır. Yetkisi olmayan biri o node'un `rpc("authority", ...)` fonksiyonlarını çağıramaz.

---

## 4. Autoload / Global Scriptler

### 4.1 `GameManager.gd`

**Rolü:** Oyun durumunu yönetir. Haritayı yükler, oyuncuları spawn eder, ölüm/respawn döngüsünü çalıştırır, oyun bitişini yönetir.

**Durum makinesi (State Machine):**
```
MENU → LOBBY → IN_GAME → ENDED
```
`state` değişkeni her an oyunun hangi aşamada olduğunu tutar.

**Önemli Değişkenler:**
```gdscript
var active_players: Dictionary
# peer_id → Player node referansı
# Tüm aktif oyuncuları takip eder
# Örnek: { 1: <Player_1 node>, 34521: <Player_34521 node> }
```

---

**`start_game()` — Oyunu Başlat**
```gdscript
func start_game() -> void:
    if not NetworkManager.is_host(): return   # Sadece host çalıştırabilir
    TeamManager.reset()                        # Tüm skorları sıfırla
    _start_game_rpc.rpc()                      # Tüm cihazlara "başla" komutu gönder
```
> ℹ️ Neden sadece host? Oyun mantığının tek bir yerden yönetilmesi gerekir. İki client aynı anda "başla" derse tutarsızlık çıkar.

---

**`_start_game_rpc()` — Her Cihazda Çalışan Başlatıcı**
```gdscript
@rpc("authority", "call_local", "reliable")
func _start_game_rpc() -> void:
    state = State.IN_GAME
    get_tree().change_scene_to_packed(map_scene)  # Harita sahnesine geç
    await get_tree().process_frame                 # 2 kare bekle (sahne yüklensin)
    await get_tree().process_frame
    _spawn_local_player()                          # Kendi oyuncunu oluştur
    emit_signal("game_started")
```
> ℹ️ `await process_frame`: Sahne geçişi anlık değildir; Godot bunu sonraki karede uygular. İki kare beklenmezse spawn noktaları henüz yüklenmemiş olabilir.

---

**`_spawn_local_player()` — Kendi Oyuncunu Oluştur**

Her cihaz **sadece kendi oyuncusunu** oluşturur, ardından diğerlerine "ben spawn oldum" RPC'si gönderir.

```gdscript
func _spawn_local_player() -> void:
    var local_id := NetworkManager.get_local_id()
    var player_data := NetworkManager.players.get(local_id, {})
    var team_id := player_data.get("team_id", 0)
    var spawn_pos := TeamManager.get_spawn_position(team_id)

    var player = player_scene.instantiate()
    player.name = "Player_%d" % local_id          # Benzersiz isim
    player.set_multiplayer_authority(local_id)     # Bu oyuncunun "sahibi" benim
    get_tree().current_scene.add_child(player)
    player.global_position = spawn_pos
    player.initialize(local_id, team_id)

    active_players[local_id] = player
    _notify_player_spawned.rpc(local_id, team_id, spawn_pos)  # Diğerlerine bildir
```

---

**`_notify_player_spawned()` — Başkasının Oyuncusunu Oluştur**

Diğer cihazlardan "ben spawn oldum" mesajı geldiğinde kendi sahnemize o oyuncuyu ekleriz.

```gdscript
@rpc("any_peer", "call_local", "reliable")
func _notify_player_spawned(peer_id, team_id, pos) -> void:
    if peer_id == NetworkManager.get_local_id(): return  # Kendi spawn'ımız zaten var
    if active_players.has(peer_id): return               # Zaten oluşturulmuş

    var player = player_scene.instantiate()
    player.set_multiplayer_authority(peer_id)   # Bu oyuncunun sahibi o peer
    player.initialize(peer_id, team_id)
    active_players[peer_id] = player
```

---

**`handle_player_death()` — Ölüm İşlemi (Sadece Host)**

```gdscript
func handle_player_death(dead_peer_id, killer_peer_id) -> void:
    if not NetworkManager.is_host(): return
    var killing_team = NetworkManager.players[killer_peer_id]["team_id"]
    TeamManager.add_kill(killing_team)    # Öldüren takıma puan ekle
    _schedule_respawn(dead_peer_id)       # 3 saniye sonra respawn planla
```

---

**`_schedule_respawn()` — Respawn Zamanlayıcı**

```gdscript
func _schedule_respawn(dead_peer_id) -> void:
    await get_tree().create_timer(3.0).timeout   # 3 saniye bekle
    var player = active_players.get(dead_peer_id)
    var spawn_pos = TeamManager.get_spawn_position(team_id)
    player.respawn(spawn_pos)   # player.respawn() içi RPC ile tüm cihazlara yayar
```
> ℹ️ `await`: Kodun bekleme sırasında bloklanmaması için. Diğer her şey çalışmaya devam eder, sadece bu satır 3 saniye bekler.

---

### 4.2 `NetworkManager.gd`

**Rolü:** ENet ağ bağlantısını kurar, oyuncuları kaydeder, takım değiştirme ve hazır olma mesajlarını yönetir.

**Önemli Değişken:**
```gdscript
var players: Dictionary
# peer_id → { "name": "Ali", "team_id": 2, "is_ready": true }
# Lobideki ve oyundaki tüm oyuncuların bilgisi burada
```

---

**`create_server()` — Sunucu Kur**

```gdscript
func create_server(player_name: String) -> void:
    var peer := ENetMultiplayerPeer.new()
    peer.create_server(PORT, MAX_PLAYERS)    # Port 7777, max 20 oyuncu
    multiplayer.multiplayer_peer = peer      # Godot'un ağ sistemine bağla
    players[1] = { "name": player_name, "team_id": -1, "is_ready": false }
    emit_signal("server_created")
```
> ℹ️ Host'un id'si her zaman **1**'dir. Bu Godot ENet'in sabit bir kuralıdır.

---

**`join_server()` — Sunucuya Katıl**

```gdscript
func join_server(address, player_name) -> void:
    var peer := ENetMultiplayerPeer.new()
    peer.create_client(address, PORT)         # IP:Port'a bağlan
    multiplayer.multiplayer_peer = peer
    # Bağlantı başarılı olunca _on_connected_to_server() otomatik tetiklenir
```

---

**Bağlantı Olayları Zinciri (Client için):**

```
join_server() çağrılır
    ↓
ENet bağlantı kurar
    ↓
_on_connected_to_server() tetiklenir
    ↓
register_player.rpc_id(1, ...) → Host'a "Ben Ali'yim, id'm 34521" mesajı
    ↓
Host: register_player() çalışır, players listesine ekler
    ↓
Host: receive_player_list.rpc() → Herkese güncel listeyi gönder
    ↓
Tüm cihazlar: player_list_updated sinyali → Lobi ekranı güncellenir
```

---

**`request_change_team()` — Takım Değiştir**

```gdscript
func request_change_team(team_id: int) -> void:
    var my_id := multiplayer.get_unique_id()
    if multiplayer.is_server():
        _change_team(my_id, team_id)          # Host: direkt çalıştır
    else:
        _change_team.rpc_id(1, my_id, team_id)  # Client: host'a gönder
```
> ℹ️ Neden host'a gönderilir? Tüm oyun mantığı host'ta merkezi olarak işlenir. Client kendi kendine "takım değiştirdim" diyemez.

---

**`_check_all_ready()` — Herkes Hazır mı?**

```gdscript
func _check_all_ready() -> void:
    if players.size() < 2: return       # En az 2 oyuncu gerekir
    for p in players.values():
        if not p["is_ready"]: return    # Biri bile hazır değilse dur
    GameManager.start_game()            # Herkes hazırsa oyunu başlat
```

---

### 4.3 `TeamManager.gd`

**Rolü:** 4 takımın renk, isim ve puan bilgisini tutar. Spawn noktalarını yönetir.

**Sabitler:**
```gdscript
const MAX_SCORE := 30       # Kazanmak için gereken öldürme sayısı

const TEAM_COLORS = [
    Color(0.2, 0.6, 1.0),   # Takım 0 — Mavi
    Color(1.0, 0.3, 0.3),   # Takım 1 — Kırmızı
    Color(0.3, 0.9, 0.3),   # Takım 2 — Yeşil
    Color(1.0, 0.85, 0.1),  # Takım 3 — Sarı
]
```

---

**`add_kill()` — Öldürme Ekle ve Kazanmayı Kontrol Et**

```gdscript
func add_kill(killing_team: int) -> void:
    scores[killing_team] += 1
    emit_signal("score_updated", killing_team, scores[killing_team])
    if scores[killing_team] >= MAX_SCORE:
        emit_signal("team_won", killing_team)
```

Bu sinyal → `GameManager._on_team_won()` → `_end_game_rpc.rpc()` → Tüm cihazlarda oyun biter.

---

**`get_spawn_position()` — Rastgele Spawn Noktası Al**

```gdscript
func get_spawn_position(team_id: int) -> Vector2:
    var points := spawn_points.get(team_id, [])
    return points[randi() % points.size()]   # 5 noktadan birini rastgele seç
```

---

**`register_spawn_points()` — Haritadan Spawn Noktalarını Kaydet**

Map.gd tarafından çağrılır. Haritadaki `Marker2D` node'larının pozisyonlarını buraya kaydeder.

---

## 5. Oyun Sahneleri

### 5.1 `Main.gd`

Oyunun başlangıç sahnesi. Tek satır işi var: MainMenu sahnesine geç.

```gdscript
func _ready() -> void:
    get_tree().change_scene_to_file.call_deferred("res://scenes/ui/MainMenu.tscn")
```
> ℹ️ `call_deferred`: `_ready()` fonksiyonu içinde sahne değiştirmek Godot'ta hataya yol açar. `call_deferred` komutu "bu frame bittikten sonra çalıştır" anlamına gelir.

---

### 5.2 `MainMenu.gd`

**Arayüz Elemanları:**
- `NameInput` — Oyuncu ismi
- `IPInput` — Bağlanılacak sunucu IP'si
- `HostButton` — Sunucu kur
- `JoinButton` — Sunucuya katıl
- `StatusLabel` — Durum mesajı

**Akış:**
```
Host butonu basılır
    → NetworkManager.create_server()
    → server_created sinyali
    → Lobby sahnesine geç

Join butonu basılır
    → NetworkManager.join_server(ip, isim)
    → joined_server sinyali (bağlantı başarılıysa)
    → Lobby sahnesine geç

Bağlantı başarısız
    → connection_failed sinyali
    → "Bağlantı başarısız!" mesajı göster
```

---

### 5.3 `Lobby.gd`

Oyuncuların takım seçtiği ve hazır olduğu ekran.

**Arayüz Elemanları:**
- Sol panel: Oyuncu listesi (isim, takım, hazır durumu)
- Sağ panel: 4 takım butonu + Hazır butonu + Başlat butonu (sadece host görür)

**`_refresh_player_list()` — Listeyi Güncelle**

`player_list_updated` sinyali her geldiğinde tüm etiketleri silip yeniden oluşturur:
```
Ali — Mavi ✓
Veli — Kırmızı
Ayşe — Yeşil ✓
```

**`_on_ready_btn_pressed()` — Hazır / Hazır Değil Geçiş**

```gdscript
func _on_ready_btn_pressed() -> void:
    is_ready = not is_ready                     # Tersine çevir
    ready_btn.text = "Hazır DEĞİL" if is_ready else "Hazır"
    NetworkManager.set_ready(is_ready)          # Sunucuya bildir
```

**Başlat butonu (sadece host):** Tüm oyuncular hazırsa aktif olur. Basınca `GameManager.start_game()` çağrılır.

---

### 5.4 `HUD.gd`

Oyun içi arayüz. `CanvasLayer` olduğu için kamera hareket etse bile ekranda sabit kalır.

**Elemanlar:**
- `score_labels[0..3]` — 4 takım için puan etiketleri (renklendirilmiş)
- `end_panel` — Oyun bitince açılan panel
- `winner_label` — Kazanan takım ismi
- `back_btn` — Ana menüye dön

**Sinyal Bağlantıları:**
```gdscript
TeamManager.score_updated → _refresh_scores()     # Puan değişince güncelle
GameManager.game_ended → _on_game_ended()         # Oyun bitince paneli göster
```

---

### 5.5 `Map.gd`

Haritanın script'i. Editörde yapılan haritadaki spawn noktalarını koda aktarır.

**Beklenen Node Yapısı (Map.tscn içinde):**
```
Map (Node2D)
└── SpawnPoints (Node2D)
    ├── Team0 (Node2D)
    │   ├── Marker2D  ← spawn noktası 1
    │   ├── Marker2D  ← spawn noktası 2
    │   └── ...       ← (5 adet önerilir)
    ├── Team1 (Node2D)
    ├── Team2 (Node2D)
    └── Team3 (Node2D)
```

**`_register_spawn_points()` — Spawn Noktalarını Kaydet**

```gdscript
func _register_spawn_points() -> void:
    for team_id in range(4):
        var team_node = spawn_root.get_node_or_null("Team%d" % team_id)
        var points: Array[Vector2] = []
        for child in team_node.get_children():
            if child is Marker2D:
                points.append(child.global_position)
        TeamManager.register_spawn_points(team_id, points)
```

> ℹ️ `get_node_or_null`: Node bulunamazsa null döner, hata vermez. Ardından uyarı mesajı gösterilir.

---

## 6. Oyuncu Sistemi — `Player.gd`

Bu projenin en karmaşık scripti. Yerel oyuncu ile uzak oyuncuları farklı şekilde yönetir.

### 6.1 Node Yapısı (Player.tscn)

```
Player (CharacterBody2D)          ← Fizik + hareket
├── Sprite2D                      ← Görsel (icon.svg)
├── CollisionShape2D              ← Çarpışma şekli
├── Flashlight (PointLight2D)     ← El feneri
├── HealthBar (ProgressBar)       ← Sağlık çubuğu
├── NameLabel (Label)             ← Oyuncu ismi
└── WeaponHolder (Node2D)         ← Silahı döndürmek için kap
    └── Weapon                    ← Silah (dinamik eklenir)
```

### 6.2 Değişkenler

```gdscript
var peer_id: int       # Bu oyuncunun ağ kimliği
var team_id: int       # Hangi takımda (0-3)
var is_local: bool     # Bu cihazın oyuncusu mu?
var is_dead: bool      # Şu an ölü mü?
var health: float      # Mevcut can (0-100)

# Ağ senkronizasyonu için hedef değerler (uzak oyuncular için)
var _target_position: Vector2
var _target_weapon_rotation: float
var _target_flashlight_rotation: float

const SYNC_RATE: float = 0.05   # 0.05 saniye = saniyede 20 güncelleme
```

### 6.3 `initialize()` — Oyuncuyu Hazırla

Spawn anında çağrılır. Hem yerel hem uzak oyuncular için ilk ayarları yapar.

```gdscript
func initialize(p_peer_id, p_team_id) -> void:
    peer_id = p_peer_id
    team_id = p_team_id
    is_local = (p_peer_id == NetworkManager.get_local_id())
    modulate = TeamManager.get_color(team_id)     # Sprite'ı takım rengine boya
    flashlight.texture = _make_flashlight_texture()

    if is_local:
        # Yerel oyuncu sprite'ı karanlıktan etkilenmesin
        var mat := CanvasItemMaterial.new()
        mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
        sprite.material = mat

        # Kamera ekle (sadece yerel oyuncuya kamera bağlanır)
        var cam := Camera2D.new()
        cam.zoom = Vector2(1.5, 1.5)
        add_child(cam)

    _equip_default_weapon()
```

> ℹ️ `LIGHT_MODE_UNSHADED`: Işık hesaplamasından muaf tutar. Yani harita karanlık olsa bile kendi oyuncunuzu her zaman görürsünüz. Diğer oyuncular normal görünür (karanlıkta silik).

### 6.4 Fizik Döngüsü — `_physics_process()`

Her frame (kare) çalışır. Yerel ve uzak oyuncuları farklı işler.

```gdscript
func _physics_process(delta: float) -> void:
    if is_dead: return
    if is_local:
        _handle_local_input(delta)    # Klavye/mouse ile hareket
    else:
        _interpolate_remote(delta)    # Ağdan gelen pozisyona yumuşak geçiş
```

### 6.5 `_handle_local_input()` — Yerel Giriş

```gdscript
func _handle_local_input(delta) -> void:
    # WASD hareketi
    var dir := Vector2.ZERO
    if Input.is_action_pressed("move_up"):    dir.y -= 1
    if Input.is_action_pressed("move_down"):  dir.y += 1
    if Input.is_action_pressed("move_left"):  dir.x -= 1
    if Input.is_action_pressed("move_right"): dir.x += 1
    velocity = dir.normalized() * speed   # Köşegen harekette hız normalleştirilir
    move_and_slide()                      # Duvarlara çarparak kayarak git

    # Mouse yönüne bak
    weapon_holder.look_at(get_global_mouse_position())
    flashlight.look_at(get_global_mouse_position())

    # Ateş et
    if Input.is_action_pressed("shoot") and current_weapon:
        current_weapon.try_shoot(peer_id, team_id)

    # Ağ senkronizasyonu: her 0.05 saniyede bir pozisyonu yayınla
    _sync_timer += delta
    if _sync_timer >= SYNC_RATE:
        _sync_timer = 0.0
        if multiplayer.get_peers().size() > 0:
            _broadcast_state.rpc(global_position, weapon_holder.rotation, flashlight.rotation)
```

### 6.6 `_interpolate_remote()` — Uzak Oyuncu Yumuşatma

Uzak oyuncular "ışınlanma" yerine yumuşak hareket eder.

```gdscript
func _interpolate_remote(delta) -> void:
    var t: float = minf(delta * 20.0, 1.0)    # Yumuşatma faktörü
    global_position = global_position.lerp(_target_position, t)
    # lerp: iki değer arasında belirli bir oranda geçiş yapar
    # Örn: mevcut pos ile hedef pos arası %t'lik noktası
```

> ℹ️ Pozisyon verisi ağda saniyede 20 kez gelir ama oyun genelde 60 FPS çalışır. `lerp` ile her frame arasında yumuşak animasyon yaratılır.

### 6.7 `_broadcast_state()` — Pozisyon Yayını

```gdscript
@rpc("any_peer", "unreliable_ordered")   # Hızlı, sıralı, kaybı önemli değil
func _broadcast_state(pos, weapon_rot, flash_rot) -> void:
    if is_local: return                  # Kendi pozisyonumuzu güncellemeyiz
    _target_position = pos
    _target_weapon_rotation = weapon_rot
    _target_flashlight_rotation = flash_rot
```

### 6.8 Hasar Sistemi — `take_damage()`

**Kural:** Sadece sunucu (host) hasar hesaplar.

```gdscript
@rpc("any_peer", "reliable")
func take_damage(amount, shooter_peer_id) -> void:
    if not NetworkManager.is_host(): return    # Client'ta çalışmaz
    if is_dead: return                         # Zaten ölüyse atla

    health -= amount
    health = clamp(health, 0.0, max_health)
    _sync_health.rpc(health)                   # Yeni canı herkese bildir

    if health <= 0.0:
        _die(shooter_peer_id)
```

### 6.9 Ölüm ve Respawn Zinciri

```
Bullet çarpışır
    ↓
Bullet: take_damage.rpc_id(1, ...) → Host'a hasar bildir
    ↓
Host: take_damage() çalışır, can azalır
Host: _sync_health.rpc() → Herkes canı günceller
Host: can <= 0 → _die() çağrılır
    ↓
_die():
    _apply_death.rpc()         → Tüm cihazlarda sprite grileşir, çarpışma kapanır
    GameManager.handle_player_death() → Puan eklenir, 3 saniye sayar
    ↓
3 saniye sonra:
GameManager: player.respawn(spawn_pos) çağrılır
    ↓
respawn():
    _apply_respawn.rpc(spawn_pos)  → Tüm cihazlarda can doldu, konum değişti
```

### 6.10 El Feneri Texture — `_make_flashlight_texture()`

Kod ile 256x256 piksel bir koni şekli oluşturur. Her piksel için iki hesap:
- **`cone`**: Mouse yönünden ne kadar sapıyor? (±50 derece dışı siyah)
- **`fade`**: Merkeze ne kadar uzak? (uzaklaştıkça solar)

```gdscript
static func _make_flashlight_texture() -> ImageTexture:
    var size := 256
    var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
    for x in range(size):
        for y in range(size):
            var dir := Vector2(x, y) - Vector2(size*0.5, size*0.5)
            var dist := dir.length() / (size * 0.5)
            var angle := absf(dir.angle())                        # Sağa bakan koni
            var cone := clampf(1.0 - angle / (PI * 0.28), 0.0, 1.0)
            var fade := clampf(1.0 - dist, 0.0, 1.0)
            var alpha := pow(cone, 2.5) * pow(fade, 1.2)         # Yumuşak geçiş
            img.set_pixel(x, y, Color(1.0, 0.97, 0.88, alpha))   # Sarımsı beyaz
    return ImageTexture.create_from_image(img)
```

> ℹ️ Bu texture bir kez oluşturulur (`static func` olduğu için tüm oyuncular aynı texture'ı paylaşır). Her oyuncu için ayrı texture oluşturulması gerekmez.

---

## 7. Silah ve Mermi Sistemi

### 7.1 `Weapon.gd`

**Ayarlanabilir Özellikler (`@export` — editörden değiştirilebilir):**

| Değişken | Varsayılan | Açıklama |
|----------|-----------|----------|
| `damage` | 25.0 | Her mermi kaç can alır |
| `fire_rate` | 0.15 sn | Atışlar arası minimum süre |
| `bullet_speed` | 600.0 | Mermi hızı (piksel/saniye) |
| `max_ammo` | 30 | Şarjör kapasitesi |
| `reload_time` | 1.8 sn | Yeniden şarj süresi |
| `spread_degrees` | 2.0° | Namlu sapması (mermi düz gitmez) |

---

**`try_shoot()` — Ateş Et**

```gdscript
func try_shoot(shooter_peer_id, shooter_team_id) -> void:
    # Engeller: şarj ediliyor, mermi bitti, ateş hızı bekleniyor
    if is_reloading or current_ammo <= 0 or not fire_timer.is_stopped():
        return

    current_ammo -= 1
    fire_timer.start()    # Bir sonraki atış için süreyi başlat

    # Saçılma ekle: rastgele ±2 derece sapma
    var spread := deg_to_rad(randf_range(-spread_degrees, spread_degrees))
    var direction := Vector2.RIGHT.rotated(global_rotation + spread)

    # Tüm cihazlarda mermi oluştur
    _spawn_bullet.rpc(muzzle.global_position, direction, shooter_peer_id, shooter_team_id)

    if current_ammo <= 0:
        reload()
```

---

**`_spawn_bullet()` — Mermi Oluştur (Tüm Cihazlarda)**

```gdscript
@rpc("any_peer", "call_local", "reliable")
func _spawn_bullet(spawn_pos, direction, shooter_peer_id, shooter_team_id) -> void:
    var bullet = bullet_scene.instantiate()
    get_tree().current_scene.add_child(bullet)
    bullet.global_position = spawn_pos
    bullet.initialize(direction, bullet_speed, damage, shooter_peer_id, shooter_team_id)
```

> ℹ️ Mermi **her cihazda** yerel olarak hareket eder. Merkezi senkronizasyon yok. Bu yaklaşım (client-side mermi) gecikmeyi gizlemek için yaygın kullanılır.

---

**`reload()` — Şarj Et**

```gdscript
func reload() -> void:
    if is_reloading or current_ammo == max_ammo: return
    is_reloading = true
    ammo_label.text = "Şarj ediliyor..."
    reload_timer.start()
    await reload_timer.timeout          # 1.8 saniye bekle
    current_ammo = max_ammo
    is_reloading = false
```

---

### 7.2 `Bullet.gd`

Mermi, `Area2D` (çarpışma algılayan alan) olarak çalışır. Fizik nesnesi değildir; her frame elle hareket ettirilir.

**Değişkenler:**
```gdscript
var direction: Vector2    # Hangi yöne gidecek (normalize edilmiş)
var speed: float          # Hız
var damage: float         # Hasar miktarı
var shooter_peer_id: int  # Kimin attığı (çift hasar önlemi için)
var shooter_team_id: int  # Hangi takım attı (dost ateş önlemi için)
const MAX_DISTANCE = 1000 # Maks menzil (piksel)
```

---

**`_physics_process()` — Merminin Hareketi**

```gdscript
func _physics_process(delta) -> void:
    var move := direction * speed * delta
    global_position += move
    _travel_distance += move.length()
    if _travel_distance >= MAX_DISTANCE:
        queue_free()    # Menzil aşılınca sil
```

---

**`_on_body_entered()` — Çarpışma**

Bu fonksiyon, mermi bir `CharacterBody2D`'ye çarptığında çalışır.

```gdscript
func _on_body_entered(body) -> void:
    if body is CharacterBody2D:
        # 1. Dost ateş kontrolü
        if body.get("team_id") == shooter_team_id:
            queue_free(); return    # Aynı takımdan biri, hasar verme

        # 2. Sadece atan oyuncunun clienti hasar bildirir
        if NetworkManager.get_local_id() == shooter_peer_id:
            if NetworkManager.is_host():
                body.take_damage(damage, shooter_peer_id)    # Direkt çağır
            else:
                body.take_damage.rpc_id(1, damage, shooter_peer_id)  # Host'a gönder

    queue_free()    # Mermiyi her koşulda sil
```

> ℹ️ **Neden sadece atan oyuncunun clienti bildirir?**
> Mermi her cihazda yerel olarak hareket eder. Tüm cihazlar aynı çarpışmayı görür. Eğer hepsi hasar bildirse 4-5 kez hasar işlenir (çift hasar). Bu nedenle sadece **silahı atan** oyuncunun cihazı hasar RPC'si gönderir.

---

## 8. Işık Sistemi — `StreetLamp.gd`

Sokak lambası, editörde sahneye yerleştirilen ve isteğe bağlı titreyen bir ışık kaynağıdır.

**Özellikler (`@export`):**
- `flicker: bool` — Titreme açık/kapalı
- `flicker_speed: float` — Titreme hızı (0.1 sn varsayılan)

**`_make_light_texture()` — Işık Texture'ı Oluştur**

Merkezden dışa doğru beyazdan şeffafa geçen radyal bir gradient texture oluşturur:

```gdscript
static func _make_light_texture() -> GradientTexture2D:
    var g := Gradient.new()
    g.set_color(0, Color(1,1,1,1))      # Merkez: tamamen beyaz
    g.add_point(1.0, Color(1,1,1,0))   # Kenar: tamamen şeffaf
    var tex := GradientTexture2D.new()
    tex.fill = GradientTexture2D.FILL_RADIAL   # Dairesel dolum
    return tex
```

**`_start_flicker()` — Titreme**

```gdscript
func _start_flicker() -> void:
    while true:                                             # Sonsuz döngü
        await get_tree().create_timer(flicker_speed + randf() * 0.2).timeout
        light.energy = randf_range(0.6, 1.2)               # Işık yoğunluğunu rastgele değiştir
```

> ℹ️ `while true` içinde `await` kullanmak Godot'ta normaldir. `await` sırasında diğer kodlar çalışmaya devam eder.

---

## 9. Ağ Mimarisi — Büyük Resim

### 9.1 Kim Neye Karar Verir?

| Karar | Kim Verir | Neden |
|-------|-----------|-------|
| Takım değişikliği | Host | Merkezi kayıt |
| Hazır olma | Host | Merkezi kayıt |
| Oyun başlatma | Host | Tek otorite |
| Hasar hesaplama | Host | Hile önleme |
| Oyuncu spawning | Her cihaz kendisi | Gecikmeyi gizleme |
| Mermi hareketi | Her cihaz kendisi | Gecikmeyi gizleme |
| Pozisyon yayını | Yerel oyuncu | Kendi pozisyonunu yayar |

### 9.2 Veri Akış Diyagramı

```
[Oyuncu A (Client)] ──────────────────── [Host (Server+Oyuncu)]
       │                                          │
       │ 1. shoot() → mermi oluştur (yerel)       │
       │                                          │
       │ 2. Mermi çarptı →                        │
       │    take_damage.rpc_id(1) ──────────────→ │ take_damage() çalışır
       │                                          │ health azalır
       │ ←──────── _sync_health.rpc(health) ───── │ (herkese yayar)
       │                                          │
       │ ←──────── _apply_death.rpc() ─────────── │ (can 0 ise)
       │                                          │
       │ 3. Pozisyon her 0.05sn →                 │
       │    _broadcast_state.rpc() ─────────────→ │ (+ diğer clientlara)
```

### 9.3 Neden `unreliable_ordered` Pozisyon İçin?

Pozisyon her saniye 20 kez gönderilir. Bir paket kaybolursa zaten 0.05 saniye sonra yenisi gelir. `reliable` kullanmak gereksiz bant genişliği ve gecikme yaratır. `unreliable_ordered` ise eski paketleri atar, sadece en yeni pozisyonu uygular.

---

## 10. Oyunun Akışı (Baştan Sona)

```
1. BAŞLANGIÇ
   Godot açılır → Main.tscn → Main.gd → MainMenu.tscn yüklenir

2. BAĞLANTI
   A. Host: NetworkManager.create_server() → ENet sunucu başlatılır
   B. Client: NetworkManager.join_server() → Sunucuya bağlanır
              → register_player RPC → Host oyuncuyu kaydeder
              → receive_player_list RPC → Herkes güncel listeyi alır
   Herkes → Lobby.tscn'e geçer

3. LOBİ
   - Oyuncular takım seçer (→ Host'ta kaydedilir → Herkese yayılır)
   - Oyuncular "Hazır" basar (→ Host'ta kaydedilir → Herkese yayılır)
   - Herkes hazır → _check_all_ready() → GameManager.start_game()

4. OYUN BAŞLAR
   _start_game_rpc.rpc() → Herkes:
     - Map.tscn yüklenir
     - Kendi oyuncusunu spawn eder
     - _notify_player_spawned.rpc() → Diğerleri de onun oyuncusunu oluşturur
   HUD devreye girer

5. OYUN
   Döngü (saniyede 60 kez):
     - Yerel oyuncu: Giriş → Hareket → Ateş → Pozisyon yayınla
     - Uzak oyuncular: Gelen pozisyona lerp ile yaklaş

   Öldürme zinciri:
     Mermi çarpar → Host hasar hesaplar → Tüm cihazlara sağlık gönderilir
     Can 0 → Ölüm RPC → 3sn bekle → Respawn RPC

6. OYUN BİTER
   Takım 30 öldürmeye ulaşır → team_won sinyali
   → GameManager._on_team_won() → _end_game_rpc.rpc()
   → HUD: "X Takımı Kazandı!" paneli açılır

7. ANA MENÜYE DÖN
   GameManager.return_to_menu()
   → active_players temizlenir
   → NetworkManager.disconnect_all()
   → Main.tscn yüklenir
```

---

## 11. Kritik Tasarım Kararları ve Nedenleri

### 11.1 Neden MultiplayerSynchronizer Kullanılmadı?

Godot 4'ün `MultiplayerSynchronizer` node'u kolay senkronizasyon sağlar, ancak config dosyası gerektirir ve olmadan sürekli hata verir. Bu projede **manuel RPC** ile pozisyon senkronizasyonu yapıldı. Daha fazla kod yazılır ama tam kontrol sağlanır.

### 11.2 Neden Host Kendine `rpc_id(1, ...)` Göndermez?

Godot'ta bir node, kendi peer_id'sine RPC gönderemez. Host her zaman id=1'dir. Bu nedenle:
```gdscript
# Yanlış (host olunca çalışmaz):
take_damage.rpc_id(1, ...)

# Doğru:
if NetworkManager.is_host():
    take_damage(...)    # Direkt çağır
else:
    take_damage.rpc_id(1, ...)   # Host'a gönder
```

### 11.3 Neden `set_deferred("disabled", true)`?

Fizik işlemi sırasında (`_physics_process` içinden çağrılan fonksiyonlarda) CollisionShape'i direkt devre dışı bırakmak Godot'ta crash'e yol açar. `set_deferred` değişikliği bir sonraki safe noktaya erteler.

### 11.4 Neden `absf`, `clampf`, `minf`, `maxf`?

Godot 4.6 strict modda `abs()`, `clamp()` gibi generic fonksiyonlar `Variant` tipinde çalışır ve uyarı verir. `float` için `absf`, `clampf` kullanmak hem uyarıyı kaldırır hem daha hızlı çalışır.

### 11.5 Neden Her Cihaz Kendi Mermisini Oluşturur?

Alternatif: Sadece host mermi oluşturur ve diğerlerine bildirir. Bu gecikme yaratır (atış anı ile görünüm arasında). Yerel mermi oluşturma ile atış anlık hissedilir. Çarpışma doğruluğu ağ gecikmesine bağlı olsa da kullanıcı deneyimi daha iyi olur.

---

## 12. Bilinen Sınırlamalar ve Gelecek Geliştirme Alanları

### 12.1 Şu An Eksik Olanlar

| Alan | Durum | Not |
|------|-------|-----|
| Harita | Editörde yapılacak | Duvarlar, objeler, ışık kaynakları |
| Oyuncu sprite | Geçici (robot logo) | Özel karakter sanatı eklenebilir |
| Ses efektleri | Yok | Ateş, ölüm, adım sesleri |
| Animasyonlar | Yok | Koşma, ateş animasyonları |
| Birden fazla silah | Yok | Silah sistemi genişletilebilir |
| Anti-cheat | Yok | Sadece host doğrulaması var |

### 12.2 Gelecekte Eklenebilecekler

**Silah çeşitliliği:** `Weapon.gd` `@export` değerleri sayesinde editörde farklı silahlar yapılabilir. Yeni sahne oluşturup değerleri ayarlamak yeterli.

**Harita sistemi:** Farklı haritalar eklemek için `map_scene` değişkeni değiştirilebilir veya rastgele seçim yapılabilir.

**Puan tablosu:** `NetworkManager.players` sözlüğüne `kills` ve `deaths` alanları eklenip lobi/HUD'da gösterilebilir.

**Ses sistemi:** `AudioStreamPlayer2D` node'ları eklenip ateş/ölüm anlarında çalıştırılabilir.

**Hasar gösterimi:** `_apply_death` içinde kırmızı yanıp sönme veya `take_damage` sırasında kısa titreme efekti eklenebilir.

---

*Bu doküman projenin tüm GDScript dosyalarını kapsamaktadır. Her ileride geliştirme kararında bu dosyaya bakarak hangi sistemi nerede değiştirmeniz gerektiğini anlayabilirsiniz.*
