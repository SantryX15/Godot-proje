# TacticalDark — Oyun Tasarım Dokümanı (GDD)

> Bu doküman oyunun **ne olduğunu, nasıl hissettirmesi gerektiğini** ve tasarımcıların (karakter, harita, arayüz)
> uyması gereken kuralları anlatır. Kodun nasıl çalıştığı için → [DOKUMANTASYON.md](DOKUMANTASYON.md).
>
> İşaretler: **[MEVCUT]** oyunda şu an olan · **[İSTENEN]** tasarımcıdan beklenen · **[ÖNERİ]** kesinleşmemiş, tartışmaya açık.

---

## 1. Tek cümlede oyun

**Karanlık bir labirentte, sadece el fenerinin aydınlattığı kadarını gören dört takım; kartı bulup kapıya ilk ulaştıran kazanır.**

## 2. Oyunun amacı ve fantezisi

- **Oyuncu fantezisi:** Gece operasyonundaki bir özel tim üyesi. Az şey görürsün ama ışığın seni ele verir.
- **Temel gerilim:** *Görmek için ışık lazım, ışık seni görünür yapar.* Fenerin karşıdaki düşmana yerini belli eder.
  Köşeyi dönmek, lamba altından geçmek, kart taşımak hep risktir.
- **Kazanma:** Haritada saklı bir **kart** ve bir **kapı** vardır. Yerleri her maç değişir ve sadece yakına gelince
  görünürler. Kartı alan takım onu kapıya taşımalı, diğer üç takım ise durdurmalıdır. Öldürmek tek başına
  kazandırmaz; araçtır.
- **Hedef his:** Gergin, sessiz, taktiksel. Uzun bekleme ve keşif anlarının ardından kısa ve sert çatışmalar.
  "Arcade" değil, "askeri gerilim".

## 3. Temel oyun döngüsü **[MEVCUT]**

```
Spawn → karanlıkta ilerle / keşif → kartı bul → (takım taşıyıcıyı korur) → kapıyı bul → teslim et
            ↑                                                                    │
            └──────────── ölünce 3 sn sonra takım bölgesinde yeniden doğ ─────────┘
```

| Unsur | Kural |
|---|---|
| Takımlar | 4 takım: Mavi, Kırmızı, Yeşil, Sarı · 2'li – 5'li (oda ayarı) |
| Kart | Üstüne yürüyünce alınır; taşıyıcı ölünce yere düşer |
| Kapı | Kart taşıyıcısı girerse maç biter |
| Dost ateşi | Yok |
| Respawn | 3 saniye, takımın spawn bölgesinde |
| Özel güçler | Labirent köşelerinde 5–10 sn beliren güçler, tek slot, Q ile kullanılır |

### Hareket ve hayatta kalma
- **Yürüme** varsayılandır (yavaş ve kontrollü).
- **Koşu** (Shift) hızlıdır ama dayanıklılık harcar (4 sn).
- **Çömelme** (Ctrl) en fazla 3 sn sürer; çömelmiş oyuncuya **mermi isabet etmez**. Bu bir refleks savunmasıdır,
  saklanma yeri değildir. Bomba çömelmeyi umursamaz.

### Özel güçler

| Güç | Ne yapar | Tasarım amacı |
|---|---|---|
| 💣 Bomba | Atılır, alan hasarı verir | Köşede kamp yapanı çıkarmak |
| ✚ Sağlık | +60 can | Çatışma sonrası toparlanma |
| ◈ Uydu | 8 sn minimapte tüm oyuncular görünür; kart taşıyıcısı işaretlenir (kart/kapı gösterilmez) | Bilgi avantajı ama hedefi vermez |
| ◎ Takım uydusu | 6 sn sadece düşmanlar görünür | Kısa taktik bilgi |

## 4. Karakterler (sınıflar) **[MEVCUT oynanış · İSTENEN görsel]**

Her takımda bir karakter yalnızca bir kez seçilebilir. Karakterler şu an aynı temel modelin farklı kıyafetleriyle
gösteriliyor. **Her biri için ayrı ve tanınabilir bir model tasarlanmasını istiyoruz.**

| Karakter | Rol | Can | Hız | Silah karakteri | Oynanış kimliği |
|---|---|---|---|---|---|
| **Tank** | Ön hat | 150 (en yüksek) | En yavaş | Otomatik tüfek, 30 mermi, orta menzil | Önden giren, kartı taşıyan, ateşi üstüne çeken |
| **Visioner** | Keşif | 100 | Orta | Hızlı otomatik, 28 mermi | Dengeli öncü, yol bulan, ilk göz |
| **Runner** | Hızlı sızma | 75 (en düşük) | En hızlı | Çok hızlı, saçılan SMG tarzı, 40 mermi, kısa menzil | Kartı kapıp kaçan, yakın dövüşçü |
| **Sniper** | Uzun menzil | 80 | Yavaş | Tek mermili, tek atışta öldüren (120 hasar), 130 m | Uzun koridoru kilitleyen, sabırlı |
| **Medic** | Destek | 110 | Orta | Yarı otomatik, 7 mermi, isabetli | Takımın sigortası **[ÖNERİ: iyileştirme yeteneği eklenecek]** |

### 4.1 Karakter tasarım brifi **[İSTENEN]**

**Genel stil**
- Gerçekçi–yarı gerçekçi **modern askeri / özel tim** estetiği. Fantastik zırh, bilim kurgu veya çizgi film oranları yok.
- Mevcut referans model: "Military Survivalist" (gömlek, yelek, cepler, sırt çantası, şapka, eldiven).
  Yeni modeller bu dünyada yaşıyor gibi durmalı.
- Renkler **mat ve doğal** (siyah, zeytin, orman yeşili, kum, gri). Parlak renk sadece takım işaretlerinde.

**Okunabilirlik — en kritik kural**
Kamera oyuncuya **yukarıdan ve 50° eğik** bakıyor (yaklaşık 14 m yukarıda, 12 m geride). Karakter ekranda küçük
görünüyor ve **çoğu zaman karanlıkta**, sadece fener veya lamba ışığında. Bu yüzden:
1. **Üstten siluet** ayırt edilmeli: omuz genişliği, sırt çantası, kask/şapka şekli, silah boyu.
   Örnek: Tank geniş ve hacimli, Runner ince ve teçhizatsız, Sniper uzun namlulu, Medic belirgin bir sağlık çantasıyla.
2. **Baş, omuzlar ve sırt** üstten en çok görünen yüzeylerdir. Ayırt edici detaylar buraya konmalı.
3. Yüzdeki ince detaylar oyunda neredeyse görünmez; yalnızca **karakter seçim ekranında** (yakın plan, omuz ve yüz) görünür.

**Takım rengi alanı**
- Her modelde **takım rengine boyanacak bir alan** olmalı: kol bandı, omuz yaması, kask bandı ya da sırt çantası şeridi.
- Bu alan **ayrı bir malzeme** (veya maske dokusu) olarak teslim edilmeli; oyun onu koddan Mavi/Kırmızı/Yeşil/Sarı yapar.
- Alan üstten görünür olmalı (omuz/sırt/kask ideal). **[ÖNERİ]** Hafif emissive (kendinden parlayan) şerit,
  karanlıkta takım arkadaşını tanımaya yardım eder.

**Karakter bazlı ipuçları**

| Karakter | Görsel anahtar kelimeler |
|---|---|
| Tank | Ağır plaka taşıyıcı yelek, kask, dizlik/omuzluk, geniş ve ağır gövde, koyu siyah/antrasit |
| Visioner | Hafif teçhizat, kafada gece görüş/termal dürbün, anten/telsiz, orman yeşili |
| Runner | İnce ve atletik, minimal teçhizat, kapüşon veya bere, kısa namlulu silah |
| Sniper | Ghillie/peçe parçaları, kum-çöl tonları, uzun dürbünlü tüfek, sırtta çanta |
| Medic | Gri-zeytin, büyük sağlık çantası, kolda sağlık işareti (takım rengi alanıyla çakışmasın) |

### 4.2 Karakter teknik şartları **[İSTENEN]**

| Konu | Şart |
|---|---|
| Format | FBX (tercihen) veya glTF 2.0 (.glb) |
| Ölçek | Metre, gerçek boyut. Referans boy **~1.85–1.90 m** (Tank biraz daha iri olabilir) |
| İskelet | **Unreal Engine 4 mannequin uyumlu** (pelvis, spine_01–03, clavicle, hand_l/r … isimleri). Mevcut tüm animasyonlar (yürüme, koşu, çömelme, tüfek pozları, ölüm) doğrudan çalışır. Farklı iskelet ek retarget işi demektir. |
| Poz | T-pose veya A-pose, yüz +Z ya da −Z (belirtilmeli) |
| Poligon | **[ÖNERİ]** 15k–35k üçgen (ekranda 20 karakter aynı anda olabilir) |
| Dokular | PBR: Base Color, Normal (OpenGL veya DirectX, belirtilmeli), Roughness, Metallic, AO. Karakter başı 2K yeterli |
| Parçalar | Kask/şapka, çanta, yelek gibi parçalar **ayrı mesh** ise varyant üretmek kolaylaşır |
| Silah | Ayrı model; tutma noktası (sağ el) ve namlu ucu (muzzle) referansı ile. Karakter başına 1 silah |
| Teslim | Model + dokular + karakter seçim ekranı için bir yakın plan render/konsept |

## 5. Harita tasarımı **[MEVCUT: 1 harita · İSTENEN: yeni haritalar]**

### 5.1 Mevcut harita: "Labirent"
- Kare ızgaraya yakın, dar koridorlu bir labirent. ~124 × 92 m, koridorlar ~4 m geniş, duvarlar 3 m yüksek.
- 4 takımın spawn bölgeleri haritanın farklı köşelerinde.
- 32 duvar lambası: bir kısmı sabit (sodyum sarısı), bir kısmı titreyen floresan, bir kısmı neredeyse sönük.
- Kart ve kapı her maç rastgele bir aday noktada çıkıyor.

### 5.2 Harita tasarım ilkeleri **[İSTENEN]**

1. **Adalet:** 4 takım spawn'ı kart adaylarına ve birbirine **yaklaşık eşit uzaklıkta** olmalı (dönel simetri en kolay yol).
2. **Karanlık ana malzemedir:** Harita bilerek karanlık. Işık bir **ödül ve tuzak** olarak yerleştirilmeli:
   lamba altı kavşaklar tehlikeli, karanlık koridorlar sinsi.
3. **Görüş çizgisi karışımı:** Karakterler farklı menzillerde güçlü:
   - Runner 25 m, kısa köşeler, kıvrımlar.
   - Tank/Visioner 35–45 m, orta koridorlar.
   - Sniper 130 m, uzun koridorlar.
   Her harita **birkaç uzun koridor** (Sniper'a yer), **çok sayıda kısa dönemeç** (Runner'a yer) ve orta açıklıklar içermeli.
   Hiçbir uzun koridor bir spawn'ı doğrudan görmemeli.
4. **Kart ve kapı adayları:** En az 6–8 kart, 6–8 kapı adayı. Hiçbiri bir spawn'a çok yakın olmamalı.
   Kart–kapı arası her zaman haritanın önemli bir kısmını geçmeyi gerektirmeli.
5. **Köşeler ve güçler:** Özel güçler köşelerde/çıkmazlarda doğuyor. Riskli ama ödüllendirici küçük cepler bırakılmalı.
6. **Okunabilirlik:** Kamera yukarıdan eğik baktığı için duvarlar oyuncuyu **örtmemeli**. Duvar yüksekliği ~3 m, tavan yok.
   Duvarın üst yüzeyi koridordan ayırt edilmeli (minimap ve yön bulma için).
7. **Yön bulma:** Karanlıkta kaybolmak eğlenceli olmalı, sinir bozucu değil. Bölgelere ayırt edici işaretler konmalı:
   renkli lamba tonu, duvar boyası, yer işaretleri, enkaz.

### 5.3 Harita teknik şartları **[İSTENEN]**

| Konu | Şart |
|---|---|
| Format | OBJ / FBX / glTF. Duvar geometrisi ile zemin **ayrı obje** |
| Ölçek | Metre. Önerilen alan 80×60 – 130×100 m |
| Koridor | En az **3.5–4 m** (karakter + ateş alanı); dar geçitler en az 2.5 m |
| Duvar | ~3 m yükseklik, kalınlık en az 1 m (çarpışma mesh'ten üretilir) |
| Poligon | **[ÖNERİ]** duvarlar sade (blok), detaylar dekor olarak ayrı ve çarpışmasız |
| İşaretler (Marker) | Takım başına 5 spawn noktası, 6–8 kart, 6–8 kapı, 20–35 güç noktası (köşeler), 20–40 duvar lambası (yönüyle) |
| Minimap | Üstten duvar maskesi (1 px = 1 m, siyah-beyaz PNG) veya oyun içinde üretilmek üzere temiz duvar mesh'i |
| Teslim | Model + üstten plan çizimi (spawn/kart/kapı/lamba yerleri işaretli) |

### 5.4 Yeni harita fikirleri **[ÖNERİ]**

| Harita | Konsept | Ayırt edici mekanik/his |
|---|---|---|
| **Depo** | Terk edilmiş lojistik deposu, raf koridorları | Raflar arası dar, merkezde açık yükleme alanı (Sniper alanı) |
| **Metro** | Yeraltı istasyonu ve tüneller | Uzun ray tünelleri + peronlar, titreyen floresanlar |
| **Hastane** | Gece boşaltılmış hastane katı | Oda-koridor yapısı, cam bölmeler, acil ışıkları (kırmızı) |
| **Liman** | Konteyner yığınları | Konteynerlerden labirent, sodyum projektörler, açık rıhtım |

## 6. Görsel kimlik ve atmosfer **[MEVCUT]**

| Unsur | Yön |
|---|---|
| Genel ton | Neredeyse siyah, soğuk lacivert ortam; sıcak sarı fener ışığı |
| Ana vurgu rengi | **El feneri sarısı** `#FFBD52` — logo, butonlar, seçili öğeler |
| Arka plan | `#08090D` (lacivert-siyah) |
| Takım renkleri | Mavi `#3399FF` · Kırmızı `#FF4D4D` · Yeşil `#4DE64D` · Sarı `#FFD91A` |
| Uyarı / başarı | Kırmızı `#F56154` · Yeşil `#6BDB85` |
| Lambalar | Sodyum turuncusu (sabit), soğuk beyaz floresan (titreyen) |
| UI | Koyu yarı saydam paneller, ince çerçeve, büyük harf etiketler, sade |
| Menü arka planı | Karanlık taktik ızgara üzerinde fenerle devriye gezen askerler |

**Tasarımcılar için kural:** Yeni hiçbir asset karanlığı "bozacak" kadar parlak veya doygun olmamalı.
Parlaklık yalnızca ışık kaynakları, takım işaretleri, kart ve kapı için ayrılmıştır.

## 7. Kart ve kapı görselleri **[İSTENEN – iyileştirme]**

- **Kart:** Küçük, elde taşınan bir erişim kartı / veri çubuğu. Yerdeyken hafif parlayan, yakına gelince fark edilen bir obje.
  Taşıyıcının üstünde de küçük bir işaret görünür.
- **Kapı:** Duvara gömülü, güvenlikli bir çıkış kapısı (kart okuyuculu). Yakına gelince ışığı yanan bir panel.
- Her ikisi de **uzaktan görünmemeli**. Oyun bunu yakınlığa göre ışığı açarak sağlıyor. Tasarım bu açılmayı desteklemeli
  (emissive kısımlar ayrı malzeme olmalı).

## 8. Ses yönü **[ÖNERİ – henüz yok]**

- Ortam: uzak uğultu, havalandırma, damla, titreyen lamba vızıltısı.
- Ayak sesleri hareket moduna göre değişmeli: yürüme sessiz, koşu duyulur (koşmanın bedeli). Çömelme sessiz.
- Silah sesleri karakter başına ayrışmalı (Sniper'ın tek ağır atışı tanınmalı).
- Kart alındığında ve uydu kullanıldığında herkesin duyacağı belirgin uyarı sesleri.

## 9. Tasarım teslim kontrol listesi

**Karakter**
- [ ] Konsept (ön/arka/yan + üstten siluet)
- [ ] Takım rengi alanı ayrı malzemede ve üstten görünür
- [ ] UE mannequin uyumlu iskelet, metre ölçeği
- [ ] PBR doku seti, normal map formatı belirtilmiş
- [ ] Silah modeli (el ve namlu referansıyla)
- [ ] Karakter seçimi için yakın plan render

**Harita**
- [ ] Üstten plan: spawn (4×5), kart (6–8), kapı (6–8), güç (20–35), lamba yerleri
- [ ] Spawn'ların adalet kontrolü (mesafeler)
- [ ] Uzun, orta ve kısa görüş çizgisi karışımı
- [ ] Duvar ve zemin ayrı objeler, koridor ≥ 3.5 m
- [ ] Bölge ayırt ediciler (renk/işaret)

---

*Bu doküman yaşayan bir belgedir. Oynanış değerleri (can, hız, hasar) testlere göre değişebilir;
güncel değerler her zaman DOKUMANTASYON.md bölüm 6'dadır.*
