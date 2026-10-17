# TacticalDark — Proje Geçmişi ve Çalışma Notları (AI devir dosyası)

> **Yeni bir Claude/AI oturumu için:** Bu dosya, önceki sohbetlerde (Ekim 2026) alınan kararları, kullanıcının
> tercihlerini ve çalışma yöntemini taşır. Kod haritası → [../CLAUDE.md](../CLAUDE.md), teknik doküman →
> [../DOKUMANTASYON.md](../DOKUMANTASYON.md), oyun tasarımı → [../OYUN_TASARIM_DOKUMANI.md](../OYUN_TASARIM_DOKUMANI.md).
> Burada yazanlar o anki durumdur; koda dair iddiaları kullanmadan önce koddan doğrula.

---

## 1. Kullanıcı ve çalışma tercihleri

- Kullanıcı **Türkçe** yazar, cevaplar **Türkçe** olmalı.
- Oyunu Godot editöründe kendisi açıp test eder. Editör genelde **açıktır** (bkz. §4.1).
- İstekler genellikle oynanış hissi odaklıdır ("modern olsun", "gerçek hayattaki gibi"). Kullanıcı tasarım kararlarını
  bize bırakır ama sonucu görünce düzeltme ister. Belirsiz oynanış kararlarında (ör. uydunun neyi göstereceği)
  **önce sor**, sonra uygula.
- Geri dönüş örnekleri (kalıcı tercih olarak değerlendir):
  - Oda ayarları panel olarak değil, **sağ üstte ⚙ butonu → küçük modal, bulanık arka plan** olsun.
  - Ayar değişiklikleri **anında uygulanmasın**; taslak → **KAYDET / Kapat** düğmeleri.
  - Karakter seçiminde kamera **yakın** olsun (omuz/yüz görünsün).
  - Bacaklar hareket yönüne dönsün, nişan fareyi takip etsin (geri yürüyünce geri dönmesin).
  - Oyun içi sohbet sadece maç mesajlarını göstersin ve **~4.5 sn sonra sönsün**.
  - Uydu: tüm oyuncuları gösterir, kart/kapıyı GÖSTERMEZ; kart birinin üzerindeyse taşıyıcıyı işaretler.
- Lisansı belirsiz/ticari paketlerden (ör. Unreal "pak" build içinden) asset **çıkarmayı reddettik**. Kullanıcı bunun
  yerine kendi indirdiği Survivalist modelini ve Mixamo animasyonlarını ekledi.

## 2. Kronolojik özellik geçmişi (ne yapıldı)

1. **UI yenileme:** CharacterSelect → MainMenu (oda listesi, nick, oda kur, kodla katıl) → Lobby → HUD. Ortak tema `UITheme`
   (el feneri sarısı vurgu, koyu lacivert yüzeyler).
2. **Kodla katılırken çökme:** Geçersiz oda kodu ENet'e adres olarak gidiyordu → `NetworkManager.is_valid_address` kontrolü.
3. **Sohbet:** lobi + oyun içi, HERKES/TAKIM kanalları, sistem mesajları. **Crosshair** eklendi.
4. **Harita:** `asset model/Maze.obj` labirent olarak entegre edildi (`tools/maze_*.py`). Kart/kapı yalnızca yakına gelince görünür (`ProximityReveal`).
5. **Karakter modeli:** "Military Survivalist" FBX + doku paketi, karaktere göre kıyafet (`SurvivalistModel.OUTFITS`).
   Önceki "skinli karakterler" denemesi kullanıcı isteğiyle geri alındı.
6. **Animasyonlar:** UE Basic Demo Animations (Idle/Walk/Run/CrouchWalk/Death) + Mixamo tüfek klipleri, UE iskeletine bake
   (`tools/build_anim_library.gd`, `tools/retarget_lib.gd`). Üst gövde katmanı, omurga dönüşü, eldeki tüfek.
   Tüfek gövdenin solunda duruyordu (Mixamo AimIdle pozu) → namlu sapmasını ölçüp omurgaya geri besleyen düzeltme.
7. **Hareket:** varsayılan yürüyüş, Shift koşu (dayanıklılık), Ctrl çömelme (en fazla 3 sn, mermiler üstünden geçer).
   Dururken çömelme animasyonu için ayrı `CrouchIdle` klibi.
8. **Özel güçler:** labirent köşelerinde 5–10 sn ömürlü; Bomba, Sağlık, Uydu, Takım uydusu; tek slot, Q ile kullanma.
   Test modu F1–F5.
9. **Duvar lambaları:** sabit / titreyen / ölmekte olan lambalar, ışık huzmesi shader'ı.
10. **Oda sistemi:** host migration (host çıksa da oyun sürer), oda ayarları (harita, 2v2v2v2–5v5v5v5, şifre ekle/kaldır),
    kompakt takım kartları, ana menüde oda durumu/format/harita çipleri, ⚙ modal + taslak mantığı.
11. **Menü/lobi 3D arka planı:** ızgara zemin, fener ve tüfekle devriye gezen 5 asker, fareyi takip eden fener (`MenuBackground3D`).
12. **Dokümanlar:** `DOKUMANTASYON.md` (eski 2D sürümden baştan yazıldı) + `OYUN_TASARIM_DOKUMANI.md` (karakter/harita tasarımcıları için brif).
13. **Efektler + flaş bombası:** sağlıkta yeşil vinyet ve yeşil karakter parıltısı; hasarda miktara göre kırmızı vinyet ve
    herkesin gördüğü kırmızı parıltı; bombada yakınlığa göre kamera sarsıntısı; yeni **Flaş bombası** (hasarsız, görüş
    hattı ve bakış yönüne göre beyaz ekran, atanı ve takımını da etkiler). Test tuşu F6.
    *Not: derleme ve flaş sinyali headless test edildi; oyun içi görsel testi kullanıcı yapacak.*

## 3. Açık işler / fikirler (kullanıcı henüz istemedi, önerildi)

- Flaşın sadece düşmanları etkilemesi istenirse: `PowerupManager._on_bomb_exploded` içine takım kontrolü (tek satır).
- Lobide paneller arka planı çoğunlukla kapatıyor; istenirse paneller daha saydam yapılabilir.
- `scenes/ui/MenuBackdrop.gdshader` artık kullanılmıyor, silinebilir.
- Tasarım dokümanındaki **[ÖNERİ]**ler kesin değil: poligon limitleri, Medic iyileştirme yeteneği, takım şeridinin parlaması, yeni haritalar.
- Henüz yok: ses, karaktere özel modeller/silahlar, ikinci harita, internet üzerinden oyun (NAT/relay).

## 4. Çalışma yöntemi ve tuzaklar

### 4.1 `project.godot`'yu elle düzenleme
Editör açıkken `project.godot`'ya autoload eklemek işe yaramadı: editör dosyayı sadece açılışta okuyor ve kaydederken
kendi kopyasını geri yazıyor. Sonuç "Identifier UITheme not declared" hatası oldu.
→ Yeni autoload yerine **`class_name` + statik fonksiyon** ya da `preload` kullan. Şart ise kullanıcıdan editörü
kapatmasını veya Project Settings'ten kendisinin eklemesini iste.

### 4.2 Komut satırından test (Windows)
- Eski makinede Godot 4.7: `C:\Users\Emre Erkan\Downloads\Godot\Godot.exe` (PATH'te değil). **Yeni sistemde yol farklı olabilir.**
- Gerçek projede SceneTree test betiği çalıştırma: `Godot.exe --headless --path . --script <mutlak yol>.gd`
  - Bu betiklerde autoload adları derleme anında yok → `get_root().get_node("NetworkManager")` kullan. `multiplayer` yerine
    `get_multiplayer()`; kurulumu `call_deferred` ile ertele; `_process` içinde `await` yok.
  - `--check-only` autoload'lu betiklerde yanlış hata verir; derleme kontrolü için betik içinden `load(path).can_instantiate()`.
  - Headless'te kareler çok hızlı akar; zamana bağlı testlerde `await create_timer(t).timeout` kullan.
- Ekran görüntüsü için `--headless`'ı kaldır, birkaç kare sonra `get_root().get_texture().get_image().save_png(...)`.
- Yeni `class_name` betikleri editör yeniden tarayana kadar global cache'te yok → `preload` et.
- Ağ / host migration testi: 3 süreç (host + 2 client, 127.0.0.1), çıktılar `-RedirectStandardOutput` ile.
  Aynı makinedeki süreçler arasında UDP yayın keşfi çalışmıyor; migration bu yüzden doğrudan peer IP'si kullanıyor.
- Asset denemelerini kullanıcının açık editörünü bozmamak için ayrı bir geçici projede yap.

### 4.3 Godot tuzakları (bu projede yaşandı)
`CLAUDE.md` sonundaki listeye ek olarak:
- `set_anchors_preset` ofsetleri koruyabilir, Control boyutu 0 kalır → `set_anchors_and_offsets_preset`.
- Birden fazla SubViewport önizlemesinde `own_world_3d = true`, yoksa hepsi aynı dünyayı paylaşır.
- Container'lar çocukların scale'ini sıfırlar.
- `AnimationPlayer.speed_scale = 0` geçişi de dondurur.
- Kamera physics interpolation açık: dönüşü `_physics_process`'te değiştir.
