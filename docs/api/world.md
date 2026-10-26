# World API (`scripts/world/**`)

Dünya, ışıklandırma, yol grafiği, trafik ışıkları. Sahibi: `world`.
Autoload: `World` (`scripts/world/world.gd`). Test sahnesi: `scenes/world/test_world.tscn`.

## Kullanım
```gdscript
# main.gd
World.build(self)                         # "CityWorld" düğümünü self altına kurar (~0,2 sn); Lighting + TrafficSignals dahil
var t := World.spawn_point(&"hoover_st")  # yer hizası Transform3D, ileri = -Z
vehicle.global_transform = t
var s := World.street_at(vehicle.global_position)   # {name, speed_limit_mph, kind, edge_id, distance}
World.set_time(18.5); World.set_weather("Cloudy")   # ya da GameState.minutes / GameState.weather (Lighting kendisi izler)
```
`World.build` yalnızca bir kez çağrılır; tekrar çağrılırsa eski `CityWorld` silinir.

## API
| Üye | Açıklama |
|---|---|
| `World.build(root: Node3D)` | Şehri üretir; ardından `built` sinyali. |
| `World.spawn_point(name) -> Transform3D` | Adlı doğma noktası (aşağıdaki liste); sağ şeritte, yola paralel. Bilinmeyen ad: uyarı + orijin. `World.spawn_names()`. |
| `World.street_at(pos) -> Dictionary` | `{name, speed_limit_mph, kind, edge_id, distance}`. Yol kenarı + 6 m içinde en yakın yol; Davidson Plaza otoparkı `{name:"Davidson Plaza", limit 10, kind "lot"}`; yol dışı `{name:"", limit 25, kind "none"}`. |
| `World.road_graph: RoadGraph` | Düğüm/kenar verisi (aşağıda). |
| `World.set_time(hours: float)` | Oyun saatini (0–24) ayarlar (`GameState.minutes` günceller). |
| `World.set_weather("Clear"/"Cloudy")` | `GameState.weather` günceller; `weather_changed` sinyali. Gökyüzü geçişi, `GameState` üzerinden değiştirilirse ~6 sn'de yumuşak olur. |
| `World.traffic_light_state(node_id, axis) -> String` | `"green"/"yellow"/"red"`; `axis` `"ns"` (Z boyunca) / `"ew"` (X boyunca). Sinyalsiz düğüm: `"green"`. `traffic_light_state_for_heading(node_id, heading_vec)`. |
| `World.signals.state_changed(node_id, ns, ew)` | Işık durumu değişince. |
| `World.lane_transform(edge_id, s, forward := true, lane := 0) -> Transform3D` | Kenarın `s` metresindeki şerit noktası ve yönü (trafik doğurmak için). |
| `World.map_texture() -> Texture2D` | Tüm harita tepeden (0,5 px/m, 1500x760); `World.map_uv(pos) -> Vector2` (0..1). Sınırlar `CityLayout.MAP_BOUNDS`. |
| `World.minimap_image(center, extent_m, px, highlight := "") -> Image` | Kuzey yukarı kırpım (HUD minimap için; yollar gri `#8E9298`, `highlight` adlı sokak sarı `#D8C070`, zemin `#0B0E14`). Dönüşü HUD yapar (TextureRect döndür). |
| `World.camera_preset(name) -> Transform3D` | Ön ayar sahnesini kuran kamera dönüşü (`ScenePresets`, aşağıdaki liste). |
| `World.apply_scene_preset(name) -> Dictionary` | Ön ayarın saat, hava ve lamba stilini uygular; `{fov, hours, weather, lamp, car?, els?, ref}` döner. `World.scene_preset_names()`. |
| `World.lighting: Lighting` | `set_time/set_weather`, `hours`, `weather`, `lamp_factor` (0 gündüz … 1 gece), `is_night()`, `lamp_style = "white"/"sodium"`, `focus_node` (varsayılan aktif kamera), `lamps_changed` sinyali. |

### Araç/ELS modülü için ışık yardımcıları (statik, `Lighting`)
- `Lighting.make_headlight() -> SpotLight3D`: alçak huzme (enerji 7, menzil 28, yarım açı 30°, 9° aşağı eğik, gölgesiz). Aracın far konumuna çocuk olarak ekle, `-Z` ileri bakar. Tek yumuşak beyaz oval, ≈8 m.
- `Lighting.make_els_light(color, shadows := true) -> OmniLight3D`: zemine kırmızı/mavi leke (enerji 4,5, menzil 10 m). Işığı çatıdan en az ~0,5 m yukarıya koy (gövdenin içinde kalırsa gölge zemini karartır); araç gövdesi renkli gölge düşürür. Hücre renklerini `Els.cell_colors(t)` ile eşleyip ışığı açıp kapamak araç modülünün işi. Aynı anda kırmızı+mavi ışık = mor zemin.
- Sokak lambası ışıkları: kameraya en yakın 14 lamba `SpotLight3D` (en yakın 4'ü gölgeli), uzaktakiler additive yer lekesi (MultiMesh). Gerçek ışık yarıçapı 65 m.

## Harita özeti (Davidson City)
X doğu, Z güney (kuzey = -Z), metre. Yerleşim özgündür; sokak adları ve hız limitleri düzende sabittir.
- **Hoover St** (x=0, 25 mph; güney ucu 30): z -350 … 700. Konut: gri-mavi/bej tek katlı evler, veranda, çit, ağaç, hidrant, posta kutusu. Kuzeyde **Busco Rd** (45) I-40'a bağlanır.
- Izgara: **Maple St** (x=-120), **Elm St** (x=120), **8th St** (z=-350), **9th St** (z=-150), **Western Ave** (z=50, 30 mph, x -400…400). Kavşaklar 4 yönlü STOP + `ALL WAY` plakası, zebra yaya geçidi, durma çizgisi.
- **Davidson Blvd** (z=250, 45 mph, 1+1 şerit, 13 m, çift sarı): Hoover'ın doğusunda ticari yapılar, batısında (x<-140) kahverengi tahta çit, uzun çamlar ve evler. Uzakta (z≈90) downtown silueti. `Hoover×Davidson` ve `Kiln×Davidson` **trafik ışıklı** (kırmızı/sarı/yeşil, 49 sn döngü), Maple/Elm'de yan yol STOP. Uçlarda **Davidson Beltway** (65).
- **Davidson Plaza** (x 50…380, z 290…520): park çizgili otopark, direk lambalar, doğu kenarda **şerit mağaza** (cam vitrinler sıcak beyaz) ve arkada apartmanlar; Hoover boyunca batı yakada evler.
- **Kiln Rd** (x=600, 35 mph) + **Foundry Rd** (z=450, 30): depolar, tel örgü çit, konteynerler, `SMELTER METALS` tabelası, lambalar.
- Konut sokaklarında yol | bordür | 2 m çim şeridi | kaldırım | ev düzeni; evler mavi-gri/kırmızı tuğla/bej, 1–2 katlı, beyaz pencere çerçeveli, korkuluklu verandalı; ağaçlar kümeli low-poly yuvarlak (≈8–10 m) ve katmanlı çam.
- Hoover×Western köşelerinde **Discount Liquors** (mavi tabela, doğu köşe) ve **Last Call Saloon** (yeşil tabela, güney-batı köşe).
- **I-40** (z=-690, 65 mph, 2+2 şerit, ortada tan beton bariyer + sarı kenar çizgisi; üstte `I-40 WEST` / `I-40 EAST` portal tabelaları), **Route 7** (x=-1100, 65), **Lakeview Rd** (x=1000, 45), **County Rd 18** (z=700, 45): ışıksız gece yolu, korkuluk, 65/45 limit levhaları, kırsal tarla/ahır/ağaç.
- Yeşil sokak adı tabelaları kavşak köşelerinde; limit levhaları (`SPEED LIMIT 45`) arterial/kırsal yollarda.

### Doğma noktaları (`World.spawn_names()`)
`hoover_st`, `hoover_9th`, `western_ave`, `ninth_st`, `davidson_blvd`, `davidson_plaza`, `parking_lot`, `kiln_rd`, `foundry_rd`, `highway`, `beltway`, `route_7`, `pursuit_start`.

### RoadGraph
`nodes[id] = {id, pos, control, edges}` (`control`: `"none"`, `"all_way"`, `"minor_stop"`, `"signal"`),
`edges[i] = {id, name, a, b, points, lanes (yön başına), limit_mph, width, kind, oneway, length}`.
`kind`: `residential`, `arterial`, `industrial`, `highway`, `rural`. Metotlar: `nearest_edge(pos)`, `point_on_edge(edge, s)`, `direction_from(edge, node_id)`, `neighbors(id)`, `shortest_path(a, b)` (sürüş süresi), `other_end`. Kavşak düğümü adları: `m8 h8 e8 m9 h9 e9 mw hw ew md hd ed` (Maple/Hoover/Elm × 8th/9th/Western/Davidson), `kd` (Kiln×Davidson), `kf` (Kiln×Foundry), `hi` (Hoover/I-40), …
Sağdan trafik (ABD). Fizik: tüm yüzeyler `StaticBody3D "Colliders"` (katman 1); zemin üst yüzü y=0,03.

## Sahne ön ayarları (`scripts/world/scene_presets.gd`)
Her ön ayar kamera, saat, hava ve lamba stili içerir. Adlar: `town_a_hoover_day`, `town_a_hoover_house`, `town_b_davidson_day`, `town_b_davidson_pines`, `town_c_kiln_night`, `night_western_night`, `night_hoover_night`, `night_stop_night` (sodyum lamba), `chase_street_night`, `chase_highway_0515`, `chase_highway_0605`, `chase_highway_0645`, `chase_highway_0815`, `dusk_beltway_1727`, `dusk_beltway_1747`, `plaza_lot_front`, `plaza_lot_rear` (ELS açık).
- Tek ön ayarı görüntüle: `WS_PRESET=town_a_hoover_day araclar/godot.sh --script res://scripts/dev/shot.gd -- --scene res://scenes/world/test_world.tscn --out x.png --setup res://scripts/world/shot_setup.gd`.
- Toplu görüntü alma: `scripts/world/compare_presets.sh <çıktı_klasörü> [ön ayar ...]`. `test_world.show_preset(name)` sahnede aynısını yapar (yer tutucu kutu araç ve ELS ışıklarıyla).
- Not: yeni `class_name` eklendiğinde `araclar/godot.sh --headless --import` çalıştırılmalı, yoksa ekran görüntüsü boş gri çıkar.

### Karşılaştırma sonuçları (2–3 tur) ve kapanan farklar
Tam kare MAD (HUD/karakter/araç farkı dahil, bu yüzden yalnızca göreli): konut gündüz ≈49, Davidson ≈74, Kiln gece ≈19, Western gece ≈26, otoyol 05:15 ≈26.
Kapatılanlar: ağaç biçimi (kümeli low-poly yaprak, katmanlı çam), kaldırım-çim şeridi düzeni, ev biçim/renkleri (beyaz çerçeve, korkuluk, 2 kat, tuğla), çim ve gökyüzü tonları (ölçülen `#77845B` çimen, `#8A96A3` bulutlu gökyüzü), Davidson'un 2 şeritli yola indirilmesi, otoyol beton bariyeri/sarı çizgi/portal tabelası/skyline, Hoover köşe mağazaları ve tabelaları, sodyum sıcak ortam.
Dalga 3b: gündüz güneş/ortam enerjisi ve gökyüzü düşürüldü (`Lighting.KEYS`, gökyüzü çarpanı 0,78), gece ortam rengi `#4A5A8A` / enerji 0,17, lamba spotları 14 enerji (gece zemini siyah + lamba havuzları). Kiln Rd 25 mph. Ağaçlar ≈×1,3 büyütüldü ve koyulaştırıldı. Sokak ızgarası 5x5'e sıklaştırıldı (Cedar St x=-240, Oak St x=240, Birch St z=-250, Ash St z=-50) ve `minimap_image` çizgi kalınlığı artırıldı (min 5 px, yol genişliğinin ×0,6'sı); minimapta yoğun ızgara için `extent_m` ≈ 250–300 kullanın. Hoover×9th köşesinde (doğu, z≈-175) mavi verandalı tek katlı ev sabitlendi. Gündüz pozu `Lighting` içinde (`tonemap_exposure` Clear 0,76 / Cloudy 0,9). Senaryolardaki elle `tonemap_exposure` ayarı sıfırlanmalı (çift kısma olur).
Dalga 3c: otoyol/Beltway boyunca iki yanda sık ağaç sıraları (banketten 3–8 m içeride, 15–28 m aralık), Beltway ve Route 7 orta bariyerinde 60 m aralıklı yüksek bükülü kollu lambalar (I-40 ışıksız kalır), I-40 üzerinde 3 üst geçit (x=-700, -250, 300; yalnız görsel + ayak çarpışması) ve yeşil çıkış tabelaları (`I-40 EAST 1/2 MILE`, `SUDS CITY LAUNDROMAT`, `I-40 WEST`). Davidson Beltway 4,4 km oldu (x -2200…-500 ve 800…2200; `beltway` doğma noktası x=-1900, `pursuit_start` x=-2000; `CityLayout.MAP_BOUNDS` x ±2300). Cloudy alacakaranlık (17:00–18:20) sıcak kahverengi-gri ve loş (`Lighting` anahtarları 17.2–18.05 daha karanlık, gökyüzü/ufuk/ortam sıcak). Lamba rengi hafif mavimsi beyaz (`#EAF0FF`). Şerit mağaza 2 katlı, panel parlaklığı ve sıcak/soğuk renk rastgele. `World.minimap_image` Davidson Plaza otopark kenar/koridor/giriş yollarını çizer (`highlight = "Davidson Plaza"` sarı).
Dalga 3d (durak/takip uyum istekleri): sodyum gecede ambiyan `#8A6A58`'e çekilir ve ×2,4 güçlenir (Western gece ortalama parlaklık 27→30, ref 32). `Lighting.night_boost` (gece ambiyan çarpanı) ve `Lighting.window_energy` eklendi; ön ayarlarda `night_boost` / `window_energy` alanları (takip gecesi `chase_street_night`, `chase_highway_0515`: 4,5 / 1,9; parlaklık 32→36, ref 48). Gündoğumu öne çekildi: ilk ışık 05:30, pembe 05:57, turuncu 06:24, gündüz 06:51 (lambalar 06:51'de sönük). Bordür çarpışması 6 cm basamak (görsel 14 cm), beton orta bariyer çarpışması 36 m parça + 4 m yaya geçidi aralığı (korkuluğun çarpışması yok). Downtown pencereleri %22 yanık ve %45 parlaklık. Açık: `chase_highway_0645` ortalama parlaklık 64 (ref 108, 06:45 kare), gündoğumu aydınlığı hâlâ düşük.
Açık kalanlar: daha dolgun/koyu yeşil ağaç kümeleri, ev çatıları, Kiln duvar dokusu, yaya geçidi ve çizgi kalınlıkları ince ayar.

## Zaman/hava (ışık)
Gökyüzü ve ışık anahtar saatlere göre interpolasyon (bkz. `Lighting.KEYS`): gece 18:18–05:00 neredeyse siyah (`#020204`) + soğuk mavi ortam; 05:40 ilk ışık; 06:45 pembe-turuncu ufuk; 07:00+ mavi gökyüzü; 17:45 turuncu akşam; 18:18'de tam gece. Sokak lambaları 17:00–18:00 yanar, 06:00–07:00 söner; pencere ışıkları gece açık. `Cloudy`: gri-mavi örtü (`#8FA3B8` / `#B9C4CF`), zayıf güneş, hafif sis. Sis/god-ray yok.

## Test / geliştirme
- Sahne: `scenes/world/test_world.tscn` (WASD, SHIFT hızlı, sağ fare bak, F5/F6 saat ∓1, F7 hava, F8 sonraki nokta, F9 test aracı ELS).
- Doğrulama: `araclar/godot.sh --headless --script res://scripts/world/selftest.gd` (hepsi `PASS` olmalı).
- Görüntü: `WS_SPOT=parking_lot WS_HOURS=18.75 WS_ELS=1 araclar/godot.sh --script res://scripts/dev/shot.gd -- --scene res://scenes/world/test_world.tscn --out x.png --setup res://scripts/world/shot_setup.gd` (ortam değişkenleri `shot_setup.gd` başlığında: `WS_CAM`, `WS_AZIM`, `WS_DIST`, `WS_HEIGHT`, `WS_PITCH`, `WS_WEATHER`).
- Performans (RTX 3050 Ti, 1920x1080, gece, test sahnesi): `-- --fps-test` ile yedi nokta ≈ 2–2,6 ms kare süresi (cpu+gpu ölçümü), 17–183 çizim çağrısı.
- Modeller: `blender/world/make_props.py` → `assets/models/world/*.glb` (lamba, çam, yuvarlak ağaç, hidrant, stop levhası, sinyal direği, korkuluk, posta kutusu).

## Bilinen sınırlar
- Yaya ve trafik yapay zekâsı yok (yalnızca `road_graph`, `lane_transform`, sinyal durumları sağlanır).
- Otoyol–Busco Rd/Beltway kavşakları seviyeli (üst geçit/rampa yok). Kavşak dönüş şeritleri/oklar yok.
- Binalar içi boş kutular; yalnızca dış cephe. Araç çarpışması: lamba direği, ağaç gövdesi, bina, kaldırım var; çit/hidrant/tabela yok.
- Ağaç ve evler MultiMesh ile 250 m hücrelerde; görünürlük menzili 380–450 m.
- Şerit mağaza/apartman cepheleri basit (kutu + pencere paneli).

## Tasarım varsayımları (kodda `TODO(tahmin)`)
1. Sokak lambası rengi: nötr beyaz (`#F2EEE4`), trafik durağında sodyum turuncu da olabilir → varsayılan beyaz, `lamp_style = "sodium"` seçeneği var.
2. Gündüz gökyüzü renkleri (Clear: `#3F7FCE`/`#A9CCEA` civarı) ve gün doğumu/batımı zamanlaması (sabah 06:45 pembe, akşam 17:45); `Cloudy` gündüz renkleri `main.gd`'deki yer tutucu değerlerden.
3. Trafik ışığı süreleri (22 / 18 sn yeşil, 3 sn sarı, 1,5 sn hepsi kırmızı).
4. Far konisi açıları/menzili, ELS yer ışığı enerjisi ve menzili, lamba spot parametreleri (gözle ayarlandı).
5. Tüm yerleşim düzeni, bina boyutları, kavşak aralıkları, Davidson Plaza ölçüleri, kırsal bölge (özgün tasarım).
6. Konut renk paleti ("gri-mavi" + bej/beyaz/gri/kahve)
7. Mağaza adları (`Discount Liquors`, `Last Call Saloon`) için tabela yok (yalnızca genel ticari yapılar); `SMELTER METALS` tabelası vardır.
8. Ön ayar kamera konumları gözle seçildi; `wf_*` ön ayarları sodyum lamba (`lamp_style = "sodium"`) kullanır, diğer gece sahneleri beyaz.
9. Davidson Blvd 2 şerit/13 m, otoyolun bölünmüş + tan beton bariyerli olması, Beltway/I-40 portal tabela metinleri.
10. Ay, yıldız, sis, bulut dokusu yok (`Lighting.moon_enabled` kapalı).
