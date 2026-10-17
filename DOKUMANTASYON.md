# TacticalDark — Teknik Dokümantasyon

**Motor:** Godot 4.6+ / GDScript 2.0 · Forward+ renderer
**Tür:** 3D top-down (yukarıdan, eğik kamera) taktik nişancı · 4 takım · LAN/online multiplayer (ENet)
**İlgili dosyalar:** Oyunun amacı ve sanat/tasarım yönü için → [OYUN_TASARIM_DOKUMANI.md](OYUN_TASARIM_DOKUMANI.md).
Fonksiyon/sinyal/RPC bağlantı haritası (geliştirici referansı) için → [CLAUDE.md](CLAUDE.md).

---

## İçindekiler

1. [Projeye genel bakış](#1-projeye-genel-bakış)
2. [Klasör yapısı](#2-klasör-yapısı)
3. [Temel kavramlar](#3-temel-kavramlar)
4. [Global sistemler (autoload)](#4-global-sistemler-autoload)
5. [Oyun akışı (baştan sona)](#5-oyun-akışı-baştan-sona)
6. [Oyuncu sistemi](#6-oyuncu-sistemi)
7. [Karakter modeli ve animasyon](#7-karakter-modeli-ve-animasyon)
8. [Silah ve mermi](#8-silah-ve-mermi)
9. [Harita, kart, kapı ve özel güçler](#9-harita-kart-kapı-ve-özel-güçler)
10. [Işık ve görünürlük](#10-ışık-ve-görünürlük)
11. [Arayüz (UI)](#11-arayüz-ui)
12. [Ağ mimarisi ve host migration](#12-ağ-mimarisi-ve-host-migration)
13. [Asset hattı ve araçlar (tools/)](#13-asset-hattı-ve-araçlar-tools)
14. [Test ve hata ayıklama](#14-test-ve-hata-ayıklama)
15. [Godot tuzakları](#15-godot-tuzakları)
16. [Bilinen sınırlamalar ve yol haritası](#16-bilinen-sınırlamalar-ve-yol-haritası)

---

## 1. Projeye genel bakış

TacticalDark, karanlık bir labirentte geçen 4 takımlı bir nişancı oyunudur. Harita neredeyse tamamen karanlıktır;
oyuncular el feneriyle görür. Haritada bir **kart** ve bir **kapı** vardır: kartı alıp kapıya ulaştıran takım kazanır.

| Özellik | Değer |
|---|---|
| Takım sayısı | 4 (Mavi, Kırmızı, Yeşil, Sarı) |
| Takım boyutu | Oda ayarı: 2v2v2v2 – 5v5v5v5 (en fazla 20 oyuncu) |
| Kazanma | Kartı kapıya teslim etmek (ya da tek takım kalması) |
| Karakterler | Tank, Visioner, Runner, Sniper, Medic (takım içinde benzersiz) |
| Ağ | ENet, port 7777 (oyun) + 7778 (UDP oda keşfi), host-otoriteli |
| Ölüm | 3 sn sonra takım spawn noktasında yeniden doğma |

**Kontroller**

| Tuş | Eylem |
|---|---|
| WASD | Hareket (varsayılan yürüyüş) |
| Shift | Koşu (dayanıklılık harcar) |
| Ctrl | Çömelme (en fazla 3 sn, mermiler üstünden geçer) |
| Fare | Nişan + el feneri yönü |
| Sol tık | Ateş |
| R | Şarjör değiştir |
| Q | Envanterdeki özel gücü kullan |
| Enter / T / Tab | Sohbet aç-gönder / takım sohbeti / kanal değiştir |
| TAB | Skor tablosu |
| ESC | Duraklatma menüsü |
| F1–F5 | Test modu (sadece debug build) |

---

## 2. Klasör yapısı

```
Godot-proje/
├── project.godot                ← autoload sırası burada (değiştirirken editörü kapat)
├── autoload/                    ← her sahneden erişilen global sistemler
│   ├── GameManager.gd           ← oyun durumu, spawn, kart/kapı, ölüm/respawn, migration state
│   ├── TeamManager.gd           ← takım renk/isim, skor, spawn noktaları
│   ├── RoomManager.gd           ← LAN oda keşfi (UDP yayını), oda kodu
│   └── NetworkManager.gd        ← ENet bağlantı, oyuncu kaydı, oda ayarları, sohbet, host migration
├── scenes/
│   ├── main/Main.tscn           ← giriş noktası → MainMenu
│   ├── ui/                      ← MainMenu, Lobby, CharacterSelect, HUD, ChatBox, Crosshair,
│   │                              Minimap, UITheme, MenuBackground3D + shader'lar
│   ├── player/                  ← Player, SurvivalistModel, UpperBodyLayer, SpineTwistModifier, HandRifle
│   ├── weapons/                 ← Weapon, Bullet
│   └── world/                   ← Map, Card, Door, Powerup(+Manager), Bomb, WallLamps, ProximityReveal,
│                                  CameraController
├── asset model/                 ← Maze.obj (+ işlenmiş Maze_walls.obj, minimap), Survivalist modeli + dokular
├── anims/                       ← UE/Mixamo animasyonları + üretilmiş survivalist_anims.res
└── tools/                       ← asset dönüştürme ve animasyon bake script'leri (Python + GDScript)
```

**Kural:** Tüm menü/HUD arayüzleri **kodla** kurulur; `.tscn` dosyaları çoğunlukla sadece kök node içerir.
Harita sahnesi (`Map.tscn`) ise editörde düzenlenir (spawn, kart/kapı, lamba ve güç noktaları Marker3D olarak).

---

## 3. Temel kavramlar

- **Autoload:** Oyun boyunca yaşayan, her yerden adıyla erişilen script (`GameManager.start_game()`).
  Sıra önemlidir: `GameManager → TeamManager → RoomManager → NetworkManager`.
  Yeni ortak yardımcılar autoload yerine **`class_name` + statik fonksiyon** (ör. `UITheme`) ya da `preload` ile eklenir.
- **Host / client:** Oyunu kuran (host, peer id = 1) hem sunucu hem oyuncudur. Hasar, kill, kart, skor, güçler gibi
  tüm yetkili kararlar **sadece host'ta** işlenir (`if not NetworkManager.is_host(): return`).
  Client'lar `request_*` RPC'leriyle istek yollar.
- **RPC:** `rpc()` herkese, `rpc_id(1, …)` host'a, `call_local` kendinde de çalıştırır. Pozisyon `unreliable_ordered`
  (20 Hz), önemli olaylar `reliable`.
- **Sinyal:** Sistemler arası gevşek bağlantı. HUD, oyun mantığına dokunmaz; sadece sinyal dinler.

---

## 4. Global sistemler (autoload)

### GameManager
Durumlar: `MENU → LOBBY → CHARACTER_SELECT → IN_GAME → ENDED`.
- `start_game()` (host) → herkes CharacterSelect'e geçer.
- Herkes karakter seçince `_begin_actual_game_rpc` → oda ayarındaki harita yüklenir, her cihaz **kendi** oyuncusunu
  spawn eder ve diğerlerine bildirir; host kartı ve kapıyı rastgele `CardPoints`/`DoorPoints` noktalarına koyar.
- Kart alma/düşürme/teslim, ölüm (`handle_player_death`), 3 sn respawn, oyuncu ayrılınca temizlik ve
  "tek takım kaldı" kontrolü.
- `get_migration_state()` / `restore_from_migration()` — host değişince oyunun kaldığı yerden sürmesi.

### TeamManager
Takım renkleri/isimleri (index 0–3 sabit), kill skoru (bilgi amaçlı; kazanma koşulu kart/kapıdır),
haritadan okunan spawn noktaları ve `get_spawn_position(team)` (küçük rastgele ofsetle).

### RoomManager
- Host her 2 sn'de UDP 7778'den oda bilgisini yayar: ad, kod, şifre, oyuncu sayısı, format, harita, durum (BEKLEMEDE/OYUNDA).
- **Oda kodu:** host IPv4 adresinin 7 haneli base-32 kodu (karışan 0/1/I/O harfleri yok). Kodla katılırken çözülüp
  adrese dönüştürülür; geçersiz kod ENet'e verilmeden reddedilir.

### NetworkManager
- `players` sözlüğü: `peer_id → {name, team_id, is_ready, character}`.
- Oda ayarları (`room_settings`): harita, takım boyutu (2–5), şifre var/yok. Host değiştirir, herkese senkronlanır;
  takım küçülürse fazla oyuncular takımsız kalır.
- Katılım kuralları: şifre kontrolü, oda doluysa veya oyun sürüyorsa red (migration sırasında geri dönenler hariç).
- Sohbet: `HERKES` / `TAKIM` / `system` kanalları, flood koruması, uzunluk sınırı, son 60 mesaj geçmişi.
- Host migration (bkz. bölüm 12).

---

## 5. Oyun akışı (baştan sona)

```
1. Main.tscn → MainMenu
   Operatör adı gir (kaydedilir) → ODALAR (LAN listesi) / ODA KUR / KODLA KATIL

2. Lobby
   Takım kartına tıkla → takıma geç (kapasite = takım boyutu)
   Host ⚙ ile oda ayarlarını açar (taslak → KAYDET ile uygulanır)
   Herkes HAZIR + takımlar dengeli → host OYUNU BAŞLAT

3. CharacterSelect
   5 karakterden birini seç (takım arkadaşı aynısını seçemez) → herkes seçince harita yüklenir

4. Oyun (IN_GAME)
   Spawn → karanlıkta kartı ara → kartı al → kapıyı bul → teslim et
   Ölünce kart yere düşer, 3 sn sonra yeniden doğarsın
   Köşelerde kısa süreli özel güçler belirir (tek slot, Q ile kullan)

5. Bitiş (ENDED)
   Kartı teslim eden takım (veya son kalan takım) kazanır → ZAFER / YENİLGİ ekranı → Ana menü
```

---

## 6. Oyuncu sistemi

`scenes/player/Player.gd` (CharacterBody3D) — yerel oyuncu girişle, uzak oyuncular ağdan gelen durumla (lerp) hareket eder.

### Karakter değerleri

| Karakter | Rol | Can | Hız | Hasar | Atış aralığı | Şarjör | Şarj | Saçılma | Menzil | Mod |
|---|---|---|---|---|---|---|---|---|---|---|
| Tank | Ön hat | 150 | 5.5 | 22 | 0.10 s | 30 | 2.0 s | 3.0° | 45 m | Otomatik |
| Visioner | Keşif | 100 | 8.0 | 18 | 0.09 s | 28 | 1.7 s | 2.5° | 35 m | Otomatik |
| Runner | Hızlı sızma | 75 | 13.0 | 11 | 0.06 s | 40 | 1.2 s | 4.5° | 25 m | Otomatik |
| Sniper | Uzun menzil | 80 | 7.0 | 120 | 0.50 s | 1 | 2.5 s | 0° | 130 m | Tek atış |
| Medic | Destek | 110 | 7.5 | 45 | 0.40 s | 7 | 2.0 s | 1.5° | 55 m | Tek atış |

Değerler `Player.gd` içindeki `CHARACTER_STATS` ve `WEAPON_CONFIGS`, seçim ekranındaki gösterim `CharacterSelect.gd`'dedir.

### Hareket modları

| Mod | Tuş | Hız çarpanı | Animasyon | Sınır |
|---|---|---|---|---|
| Yürüme | (varsayılan) | ×0.55 | Walk | — |
| Koşu | Shift | ×1.0 | Run | 4 sn dayanıklılık, 5 sn'de dolar |
| Çömelme | Ctrl | ×0.35 | CrouchWalk / CrouchIdle | 3 sn, 4 sn'de dolar |

Dayanıklılık tükenirse belirli bir seviyeye dolana kadar kilitlenir. **Çömelmiş oyuncuya mermi işlemez**
(mermi üstünden geçer); bomba patlaması ise çömelmeyi umursamaz.

### Dönüş mimarisi
Player kökü fareye (nişana) döner; el feneri ve silah onunla birlikte döner. Karakter modeli ise hareket ederken
**bacaklarını hareket yönüne** çevirir, omurga modifier'ı üst gövdeyi nişana geri büker (en fazla ~110°).
Böylece geri geri yürürken bile animasyon doğal kalır.

### Hasar ve ölüm
`take_damage(miktar, atan, kaynak)` sadece host'ta işlenir → can senkronlanır → 0 olursa ölüm RPC'si (Dying
animasyonu, ışıklar/çarpışma kapanır), kart taşıyıcıysa kart düşer, 3 sn sonra respawn.

---

## 7. Karakter modeli ve animasyon

- **Model:** `asset model/Survivalist/SK_Military_Survivalist.fbx` (Unreal mannequin iskeleti, 1.89 m).
  Tüm karakterler aynı modeli kullanır; fark **kıyafet setinden** gelir (`SurvivalistModel.gd → OUTFITS`):

  | Karakter | Kıyafet |
  |---|---|
  | Tank | Siyah ağır teçhizat: cepli yelek, sırt çantası, şapka, eldiven |
  | Visioner | Orman yeşili, hafif yelek, çantasız |
  | Runner | Teçhizatsız, yeleksiz, çıplak el |
  | Sniper | Çöl/kum tonları, cepli yelek, çanta |
  | Medic | Gri gömlek + zeytin yelek, sırt çantası (sağlık çantası) |

- **Malzemeler** koddan kurulur, dokular `asset model/Survivalist_Textures/` altındadır (normal map'ler DirectX → `invert_y`).
- **Animasyon kütüphanesi:** `anims/survivalist_anims.res` (`tools/build_anim_library.gd` üretir).
  UE "Basic Demo Animations": Idle, Walk, Run, CrouchWalk, Jump, Death. Mixamo tüfek klipleri UE iskeletine bake edilir:
  AimIdle, FireStand, FireWalk, Reload, Toss, HitReact, Dying.
- **Katmanlı animasyon** (Skeleton3D altında, sıra önemli):
  1. `UpperBodyLayer` — bacaklar normal animasyonu oynarken üst gövdeye tüfek pozu + aksiyonlar (ateş, şarjör, bomba atma, darbe).
  2. `SpineTwistModifier` — üst gövdeyi nişana çevirir.
  3. `HandRifle` — prosedürel tüfeği iki ele hizalar, namlu sapmasını ölçüp omurga dönüşüne geri besler
     (Mixamo pozundaki ~59° sola sapmayı düzeltir).

---

## 8. Silah ve mermi

- `Weapon.try_shoot()` mermi/ateş hızı/şarjör kontrolü yapar, saçılma ekler ve `_spawn_bullet` RPC'si ile mermiyi
  **her cihazda yerel** oluşturur (gecikme hissedilmez).
- `Bullet._on_body_entered`:
  1. Kendi mermisi → yok sayılır.
  2. Takım arkadaşı → **dost ateşi yok**, mermi hasarsız yok olur.
  3. Çömelmiş hedef → mermi geçip gider.
  4. Diğer → **sadece atan oyuncunun cihazı** hasarı host'a bildirir (çift hasarı önler).
- Eldeki tüfek görseldir; mermiler Weapon/Muzzle noktasından çıkar.

---

## 9. Harita, kart, kapı ve özel güçler

### Labirent haritası
- Kaynak: `asset model/Maze.obj` → `tools/maze_convert.py` ile duvarlar ayrılır, ortalanır, ölçeklenir → `Maze_walls.obj`.
- Ölçü: ~124 × 92 m ayak izi, koridor ~4 m, duvar ~2 m kalın ve 3 m yüksek, zemin 126 × 94 m.
- Çarpışma `Map.gd` içinde mesh'ten (trimesh) otomatik üretilir. `Maze_minimap.png` (1 px = 1 m) minimap'te kullanılır.
- `Map.tscn` içindeki işaretçiler: `SpawnPoints/Team0..3`, `CardPoints`, `DoorPoints`, `PowerupPoints` (33 köşe),
  `WallLamps/Lamp*` (32 lamba).

### Kart ve kapı
- Host oyun başında kartı ve kapıyı rastgele işaretçilere koyar.
- Kart oyuncu üstüne yürüyünce alınır; taşıyıcı ölünce olduğu yere düşer.
- Kart taşıyıcısı kapıya girerse takımı kazanır.
- `ProximityReveal`: kart ve kapının ışığı/etiketi sadece yakına gelince görünür (kart 12→5 m, kapı 16→7 m).
  Uzaktan yeri belli olmaz, aranması gerekir.

### Özel güçler (PowerupManager)
Host 8–15 sn arayla labirent köşelerinden birinde 5–10 sn ömürlü bir güç doğurur (aynı anda en fazla 3).
Oyuncunun **tek slotluk** envanteri vardır; dolu slotla yeni güç alınamaz. Ölünce slot boşalır.

| Güç | Etki |
|---|---|
| Bomba | Nişan yönüne en fazla 12 m atılır, 4 m yarıçap, merkezde 75 → kenarda ~%35 hasar. Duvar arkası, dost ve atan etkilenmez. Çömelme korumaz. Yakındakilerin ekranı mesafeye göre sarsılır (16 m'ye kadar). |
| Flaş bombası | Bomba gibi atılır, hasarsız. 11 m içinde ve görüş hattındaki herkesi (atan ve takımı dahil) kör eder: ekran beyazlar, sonra söner. Flaşa bakan tam, sırtı dönük ~%35 etkilenir. |
| Sağlık | +60 can, ekran kenarı yeşil parlar, karakter herkese yeşil parıldar |
| Uydu | 8 sn minimapte **tüm oyuncular** görünür; kart ve kapı görünmez, ama kart birinin üzerindeyse taşıyıcı işaretlenir |
| Takım uydusu | 6 sn sadece düşmanlar görünür |

Uydu kullanılınca diğer takımlara "konumunuz tespit edildi" uyarısı gider.

---

## 10. Işık ve görünürlük

- Ortam neredeyse tamamen karanlıktır. Her oyuncuda bir **el feneri** (SpotLight, ~26 m menzil) ve sadece kendi
  gövdesini aydınlatan küçük bir **gövde ışığı** bulunur (render layer 20 ile zemine taşmaz).
- Yerel oyuncu kendi karakterini bir **rim shader** (`SelfVisibility.gdshader`) ile her zaman görür; diğerleri bunu görmez.
- **Duvar lambaları** (`WallLamps.gd`): 32 lamba, her client'ta aynı seed ile:
  %55 sabit sodyum, %30 floresan gibi titreyen, %15 neredeyse sönük ("ölen" lamba). Huzme efekti `LightShaft.gdshader`.
- Kamera (`CameraController.gd`) oyuncuyu yumuşak takip eder: ofset (0, 14, 12), eğim −50°.

---

## 11. Arayüz (UI)

Ortak tema: `UITheme` (statik sınıf). Koyu lacivert-siyah yüzeyler, **el feneri sarısı vurgu** (`ACCENT`), takım renkleri.
Buton tipleri: Primary / Ghost / Tab; etiket tipleri: Title / Caps / Dim.

| Ekran | İçerik |
|---|---|
| **MainMenu** | Logo, operatör adı, sekmeler (ODALAR / ODA KUR / KODLA KATIL), oda satırlarında format, harita ve durum çipleri, şifreli oda modalı |
| **Lobby** | Oda adı/kodu (kopyala), 4 kompakt takım kartı, ⚙ oda ayarları modalı (bulanık arka plan, taslak → KAYDET/Kapat), sohbet, takımsızlar, HAZIR/BAŞLAT |
| **CharacterSelect** | 5 karakter kartı, her birinde yakın plan 3D önizleme ve stat çubukları |
| **HUD** | Skor (sol üst), hedef çipi ve uyarı bandı (üst orta), kill feed (sağ üst), oyuncu kartı + can/mermi/dayanıklılık + güç slotu (sol alt), minimap (sağ alt), hasar vinyeti, ölüm geri sayımı, TAB skor tablosu, ESC menüsü, oyun sonu ekranı |
| **Crosshair** | Fare yerine nişangah: saçılmaya göre açılır, atışta tepir, şarjör halkası gösterir |
| **ChatBox** | Lobide sürekli açık; oyunda sadece maç mesajları, her mesaj 4.5 sn görünüp söner |

**Menü arka planı** (`MenuBackground3D.gd`): ana menü ve lobide ayrı bir 3D dünya. Karanlık ızgara zeminde 5 asker
(farklı kıyafetlerle) fener ve tüfekle yavaşça devriye gezer, ara ara durup etrafa bakar. Fareyi yukarıdan takip eden
bir fener vardır; lobide rengi oyuncunun takım rengine döner. Üstte vinyet shader'ı arayüzün okunmasını kolaylaştırır.

---

## 12. Ağ mimarisi ve host migration

### Kim neye karar verir?

| Karar | Yetkili |
|---|---|
| Takım değişimi, hazır, oda ayarları, oyun başlatma | Host |
| Hasar, ölüm, kill, kart, skor, güçler | Host |
| Kendi oyuncusunun hareketi/nişanı | Her oyuncu kendisi (20 Hz yayın) |
| Mermi hareketi ve görseli | Her cihaz yerel |
| Lamba titremesi, yakınlık görünürlüğü, menü arka planı | Tamamen yerel görsel |

### Host migration
Host oyundan çıkarsa ya da oyunu çökerse oyun bitmez:
1. Her client anlık durumu kaydeder: takım, karakter, oda ayarları, client IP'leri, kart/kapı konumu, skor,
   oyuncu konumları ve istatistikleri (peer id yeniden bağlanınca değiştiği için isimle).
2. Kalan en küçük peer id yeni host olur ve sunucuyu yeniden kurar.
3. Diğerleri yeni host'un bilinen IP'sine doğrudan bağlanır (olmazsa LAN yayınından odayı bulur, 3 deneme).
4. 20 sn'lik migration penceresinde geri dönenler oyuna kabul edilir; "tek takım kaldı" kontrolü bu pencere bitince yapılır.

---

## 13. Asset hattı ve araçlar (tools/)

| Araç | Ne yapar |
|---|---|
| `maze_convert.py` | Maze.obj → duvar mesh'i (ortalama, ölçek, yükseklik, düz normal) |
| `maze_points.py` | Spawn/kart/kapı noktaları + minimap PNG |
| `maze_corners.py` | Özel güç noktaları (köşeler) |
| `maze_lamps.py` | Duvar lambası işaretçileri |
| `build_anim_library.gd` | UE + Mixamo animasyonlarından `survivalist_anims.res` üretir |
| `retarget_lib.gd` / `retarget_bake.gd` | Mixamo → UE iskeleti retarget/bake |

Orijinal asset'ler değiştirilmez; üretilen dosyalar script'le yeniden oluşturulur.

**Yeni karakter modeli eklenecekse:** UE mannequin uyumlu iskelet en kolay yoldur (mevcut tüm animasyonlar doğrudan çalışır).
Farklı iskelette retarget araçları uyarlanmalıdır. Detaylı teknik şartlar → OYUN_TASARIM_DOKUMANI.md, bölüm 9.

---

## 14. Test ve hata ayıklama

- **Test modu** (debug build'de otomatik açık): F1 Bomba, F2 Sağlık, F3 Uydu, F4 Takım uydusu, F6 Flaş bombası verir; F5 önüne rastgele güç doğurur.
- **Çoklu oyuncu testi:** Aynı makinede birden fazla Godot penceresi açılıp `localhost` / oda koduyla bağlanılabilir.
  Host migration 3 süreçle (host + 2 client) doğrulanmıştır.
- Headless script testi: `Godot.exe --path . --script <script.gd>`.

---

## 15. Godot tuzakları

- `Object.get(key)` tek argüman alır (Dictionary.get gibi varsayılan değer yok).
- Float için `absf/clampf/minf/maxf` kullan.
- `_ready()` içinde sahne değiştirme → `change_scene_to_file.call_deferred(...)`.
- `global_position` ayarlamadan önce node ağaca eklenmiş olmalı.
- `queue_free()` sonrası `is_instance_valid()` ile kontrol et.
- Fizik callback'inde collision kapatmak → `set_deferred("disabled", true)`.
- Bağlı peer yokken RPC çağırma.
- `AnimationPlayer.speed_scale = 0` geçişi de dondurur → durağan poz için ayrı klip kullan.
- Tam ekran Control için `set_anchors_and_offsets_preset` (sadece `set_anchors_preset` boyutu 0 bırakabilir).
- Birden fazla SubViewport önizlemesinde `own_world_3d = true` şart.
- Container'lar çocukların scale'ini sıfırlar.
- Editör açıkken `project.godot`'ya autoload ekleme → `class_name` statik sınıf kullan.

---

## 16. Bilinen sınırlamalar ve yol haritası

| Alan | Durum |
|---|---|
| Karakter modelleri | Tek temel model + kıyafet varyantları. **Karaktere özel model tasarımı planlanıyor.** |
| Haritalar | Sadece "Labirent". **Yeni harita tasarımları planlanıyor** (oda ayarlarında harita seçimi hazır). |
| Silah görselleri | Prosedürel basit tüfek; karaktere özel silah modelleri yok |
| Ses | Ateş, adım, ortam, UI sesleri yok |
| Karakter yetenekleri | Karakterler şimdilik sadece stat/silahla ayrışır (ör. Medic'in iyileştirme yeteneği yok) |
| Anti-cheat | Sadece host doğrulaması |
| İnternet üzerinden oyun | LAN/doğrudan IP; NAT geçişi/relay yok |
