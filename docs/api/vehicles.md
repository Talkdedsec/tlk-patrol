# Vehicles: araçlar, sürüş, ışık hücreleri, kamera Sahibi: araç oturumu.
Dosyalar: `scripts/vehicles/vehicles.gd` (autoload `Vehicles`), `vehicle.gd` (`Vehicle`), `vehicle_camera.gd` (`VehicleCamera`), modeller `assets/models/vehicles/*.glb` (betikler `blender/vehicles/`), sesler `assets/audio/engine/` (betik `synth_engine.py`), test `scenes/vehicles/test_drive.tscn`.

## Araç türleri (`Vehicles.types`)
| id | model | not |
|---|---|---|
| `sheriff_pickup` | `sheriff_pickup.glb` | lacivert/beyaz şerif pikabı, çatıda `214`, kasa kapağında `GENERAL` `T-150` `SHERIFF`, kapıda `BUSCO COUNTY SHERIFF`, kabin çatısında ışık çubuğu, kasada roll kafesi; çift kabin, uzun kaput (dingil arası 3,75 m), iri `214` |
| `sheriff_pickup_black` | aynı model | çok koyu boya (`Paint`/`Band` siyah) |
| `patrol_sedan` | `patrol_sedan.glb` | siyah-beyaz devriye sedanı (kapılarda `POLICE`, `DAVIDSON CITY`, `Police Department`, rozet), çatı ışık çubuğu |
| `patrol_sedan_unmarked` | `patrol_sedan_unmarked.glb` | tamamen siyah işaretsiz varyant, gri `GANG UNIT` yazısı, yalnızca gizli ışık hücreleri (10–19) |
| `patrol_suv` | `patrol_suv.glb` | siyah gövde, beyaz çatı ve kapılar, çatıda `12`, arkada `GENERAL`; oyuncu aracı |
| `patrol_suv_214` | `patrol_suv_214.glb` | şerif SUV'u: koyu gövde, bej kapı/çamurluk bandı, çatıda `214`, arkada küçük `GENERAL`, mavi rozet ve altın `SHERIFF`; SUV gövdeleri (üçü de) daha uzun ve arkası yuvarlak |
| `ranger_suv` | `ranger_suv.glb` | kutu SUV "Halvorsen Ranger": açık yeşil-gri, siyah çatı, çatı bagajı (trafik durağı aracı) |
| `ranger_suv_wood` | aynı model | takip şüphelisi: hardal/bej gövde, ahşap yan panel |
| `civ_wagon` | `civ_wagon.glb` | gri station wagon, çatı bagaj rafı |
| `civ_sedan`, `civ_hatchback` (Arden Compact), `civ_pickup`, `civ_van`, `civ_boxtruck` | `civ_*.glb` | trafik araçları; `Paint` malzemesi çalışma anında boyanır (`Vehicles.CIV_COLORS`: 10 renk) |

Ağırlıklı rastgele trafik seçimi: `Vehicles.random_traffic_type()`, `traffic_type_ids()`.

## GLB düğüm sözleşmesi (modelleri üreten betik ve `Vehicle` bunu bekler)
Koordinatlar Godot'ta: ön `-Z`, sağ `+X`, orijin tekerlek tabanı ortasında zemin hizasında. Düğümler:

| ad | tür | anlam |
|---|---|---|
| `Body` | mesh | sabit gövde (boya, cam, tampon, iç kapı boşlukları); çarpışma bu gövdenin 0,2 m üstündeki köşelerinden dışbükey zarf olarak üretilir; zarf ve boyutlar model dosyası başına bir kez üretilip tüm spawn'larda paylaşılır (spawn ≈1,5 ms, ilk spawn tür başına birkaç ms fazla) |
| `Interior` | mesh | koltuk, gösterge, direksiyon (camdan görünür) |
| `Wheel_FL/FR/RL/RR` | mesh | tekerlek, pivot göbek merkezinde; `Vehicle` bunları `VehicleWheel3D` altına alır, yarıçap mesh yüksekliğinden okunur |
| `Door_FL/FR/RL/RR` | mesh | menteşeli kapılar, pivot ön kenar menteşesinde; kapıdaki yazılar alt düğüm (`Decal_*`). FL = sürücü kapısı (sol direksiyon) |
| `Headlight_L/R`, `Taillight_L/R`, `BrakeLight_L/R`, `BrakeLight_High` | mesh | far / arka lamba (far açıkken sönük kırmızı, fren varken parlak) / fren lambası; her birinin kendi malzemesi var |
| `Plate_Rear`, `Plate_Front` | mesh | plaka yüzeyi; `Vehicle` üstüne `Label3D` ile plaka metnini yazar |
| `ELS_CELL_n` | mesh | ışık hücreleri, aşağıdaki numaralandırma |
| `ELS_TRAFFIC_0..7` | mesh | trafik yönlendirici (amber, ışık çubuğunun arka yüzü) |
| `LightBar_Housing` | mesh | ışık çubuğu gövdesi |
| `Seat_Driver`, `Seat_Passenger` | Node3D | oturma noktası |
| `Enter_Driver`, `Enter_Passenger` | Node3D | "E Get in" için kapı yanında durulacak nokta (zeminde) |
| `Cam_Target` | Node3D | kamera odak yüksekliği |

Boyanabilir malzeme adları: `Paint` (ana boya), `Band` (alt şerit / kapı bandı), `Roof` (çatı), `Box` (kamyonet kasası). `Vehicles.spawn(..., {"paint": Color, "colors": {"Roof": Color}})` ya da `Vehicle.set_paint(name, color)`.

## Işık hücre numaralandırması
Hücre dizisi `Els.cell_colors(t)` ile gelir (10 renk, 0–4 kırmızı, 5–9 mavi). `Vehicle` hücre `n` için `colors[n % colors.size()]` alır.

| hücre | konum |
|---|---|
| 0–9 | tavan ışık çubuğu, sürücü tarafından (sol) yolcu tarafına (sağ); 0–4 kırmızı, 5–9 mavi (ön ve arkadan görünür, sarmalayan lens) |
| 10, 11 | ızgara (sol, sağ) |
| 12, 13 | ön cam üstü "visor" (sol, sağ) |
| 14, 15 | arka cam içi / arka güverte (sol, sağ) |
| 16, 17 | ön köşe (sol, sağ) |
| 18, 19 | arka köşe (sol, sağ) |
**İşaretsiz sedan** (`patrol_sedan_unmarked`) farklıdır: 10–19 arka güvertedeki boydan boya 10 segmentli LED çubuktur (soldan sağa, `Els.cell_colors` ile 1:1), 20/25 ızgara (sol/sağ), 21/26 ön cam üstü; çatı hattı daha alçak (coupé). Çubuğu olmayan işaretsiz sedanda tavan hücreleri (0–9) yoktur; sivil araçlarda hiç hücre yok. Hücre rengi `Color(r,g,b,a)`: `max(r,g,b)*a < 0,04` sönük sayılır, yanıkken emisyon + albedo ayarlanır. Yer ışığı (yumuşatıldı: leke alfa 0,3, emisyon 0,55, omni 0,8 enerji/5 m/zayıflama 2,0): sol (0–4) ve sağ (5–9) hücre grubu için birer yumuşak, tek renkli `Decal` lekesi (radyal doku, karışmaz: sol kırmızı, sağ mavi) ve çok zayıf (5 m) birer `OmniLight3D`; çubuğu olmayan araçta 10–19'un sol/sağ hücreleri kullanılır. Lekenin rengi grup ortalamasının renk tonu, şiddeti parlaklığıdır.
Trafik yönlendirici: `ELS_TRAFFIC_0..7` (büyütüldü, emisyon 7), kaynağı `Els.traffic_colors(t)`; yanınca amber `OmniLight3D` (enerji ≈2, menzil 7 m).
Işıklar: far = iki `SpotLight3D` (dış açı 45°, enerji 10, menzil 14 m ≈ yumuşak beyaz oval), far lambası emisyonu 6; far açıkken arka lamba emisyonu 0,3 (sönük kırmızı), fren 2,6+; arkada yumuşak kırmızı yer lekesi (`Decal` + zayıf omni: far açık %25, fren %100); `def["tail_scale"]` arka lamba mesh'ini küçültür (`sheriff_pickup_black` 0,55). `ranger_suv` boyası koyulaştırıldı (gece koyu yeşil-gri); `ranger_suv_wood` (şüpheli) ivme 11 mph/sn, tepe 118 mph.

## Vehicles (autoload)
- `spawn(type_id, xform, parent = null, options = {}) -> Vehicle`: `xform` aracın zemin hizasındaki orijinin (dingil arası orta) global dönüşümüdür. `parent` verilmezse `current_scene`, o da yoksa `Vehicles`. `options`: `plate`, `paint`, `colors`, `headlights`.
- `spawn_traffic(xform, parent = null, type_id = &"") -> Vehicle`: ağırlıklı rastgele sivil tür, rastgele renk.
- `register_type(id, def)`, `has_type`, `type_ids()`, `traffic_type_ids()`, `random_traffic_type()`. `def` alanları: `name`, `model`, `mass`, `accel_mph_s`, `top_mph`, `brake_mph_s`, `police`, `traffic`, `weight`, `colors`, `knee`, `com_y`, `drag`, `angular_damp`.
- `random_plate() -> String`: `TAY-6023` biçimi (3 harf, tire, 4 rakam), canlı araçlar arasında benzersiz. `find_by_plate(plate) -> Vehicle`.
- `all: Array[Vehicle]`, sinyaller `vehicle_spawned(v)`, `vehicle_removed(v)`.
- `add_skid(from, to)`: kalıcı lastik izi (1400 parçalı halka tampon, tek MultiMesh). `skid_parent`: izlerin ekleneceği düğüm (sahne atayabilir; varsayılan `Vehicles`).

## Vehicle (`extends VehicleBody3D`)
Kontrol:
- `set_throttle(-1..1)` (eksi = geri vites; ileri giderken fren), `set_steer(-1 sol .. +1 sağ)`, **`set_brake_pedal(0..1)`**, `set_controls(throttle, steer, brake)`, `set_handbrake(bool)`.
  MIMARI.md'deki `set_brake` adı kullanılamadı: `VehicleBody3D.set_brake()` motorun kendi özelliği. Bu yüzden fren pedalı `set_brake_pedal`.
- `set_cruise_mph(mph)`: sabit hız tutucu (AI için; eksi değer kapatır). `steer_towards(world_point)`: direksiyonu hedef noktaya çevirir (her karede çağır).
- `speed_mph()` (mutlak), `forward_speed_mph()` (işaretli), `speed_ms()`, `forward_speed_ms()`, `rpm()`, `gear()`, `is_braking()`.
- Alanlar: `type_id`, `plate`, `display_name`, `is_police`, `driver`, `headlights_on`, `rear_extent`, `front_extent`, `roof_height`. `set_driver(node)` + sinyal `driver_changed`.
- `teleport(Transform3D)`, `set_paint(material_name, color)`.
- **`set_plate(text)`**: plaka metnini çalışma anında günceller (ön/arka `Label3D`, `Vehicles.find_by_plate` kaydı da güncellenir).
Işık: `set_headlights(bool)` (iki `SpotLight3D` + far/arka lamba emisyonu), fren lambaları otomatik.
Kapılar: `has_door(key)`, `set_door(key, open)`, `toggle_door(key)`, `is_door_open(key)`, `open_driver_door()`, `close_driver_door()`; `key` = `&"FL" &"FR" &"RL" &"RR"`; sinyal `door_changed(key, open)`; açılma 0,38 sn, 68°.
Koltuk: `seat_transform(&"driver"|&"passenger")`, `enter_transform(seat)` (kapı yanı, `-Z` araca bakar), `seat_near(world_pos, max_dist = 2.0) -> StringName` ("E Get in" mesafe testi), `cam_target_position()`.
ELS: `set_els_source(Callable)` (Callable `PackedColorArray` döner; bağımsız değişkeni yoksa `source.call()`, bir bağımsız değişkeni varsa araç saniyesiyle `source.call(t)`), `use_els(on = true)` (hazır: `Els.cell_colors(Els.now())` ve `Els.traffic_colors(Els.now())`), `set_traffic_source(Callable)`, `els_cell_count()`, `has_lightbar()`.
PIT: `pit_spin(side, strength = 1.0)`: arka köşeye tek itme (`side` -1 sol arka, +1 sağ arka). Kuyruğu yana iter, arka lastiklerin tutuşunu `0,35 + 0,9*strength` sn düşürür, duman başlatır. 60 mph'te ölçülen dönüş: strength 0,3 ≈ 90°, 0,6 ≈ 190°, 1,0 ≈ 285°. **`pit_scuff(side, seconds)`**: yalnızca görsel PIT teması (beyaz duman + arka lastiklerden kayma izi + lastik dumanı, impuls yok; 100 mph'te güvenli: ölçüm 99 mph, yatma 0,2°); `side` -1/+1 sol/sağ arka, 0 ikisi. Sürekli temas için `pit_push(side, dv)` (yüksek hızda aracı devirebilir) (anlık yanal hız değişimi m/sn). `start_smoke(seconds)`: beyaz yuvarlak duman ("baloncuk" parçacıklar).
Ses: `set_engine_sound(bool)`: üç motor döngüsü rpm'e göre çapraz geçişli (`engine_idle/mid/high.wav`), kayma sesi `skid.wav`; PIT darbe sesi `impact.wav` çalan tarafa bırakıldı (çalma çağrısı kod tarafında yok).
Sinyal `collided(other, speed_mph)`: 8 mph üstü çarpışma.

Sürüş modeli: arkadan itişli, gaz bırakınca (throttle 0) motor freni/yuvarlanma direnci `coast_mph_s` kadar yavaşlatır (yürüme hızının altında kademeli kapanır, araç durur; `DriveInput.COAST_BRAKE` yaması artık gerekmez), motor kuvveti `mass * accel` (diz hızı `knee` ≈ tepe hızın %78'i) sonra tepe hıza doğru söner, aerodinamik sürükleme `_integrate_forces` içinde, direksiyon açısı yanal ivme sınırına göre hıza bağlı kısılır (8,5 m/sn²), sağlam yuvarlanma önleme (düşük ağırlık merkezi, `wheel_roll_influence` 0,2). Fren: pedal 1 = `brake_mph_s` (polis 28 mph/sn). Not: VehicleBody3D'de pozitif `engine_force` araç `+Z` yönüne iter; `Vehicle` bunu kendi içinde çevirir.

## VehicleCamera
`var cam := VehicleCamera.new(); add_child(cam); cam.follow(vehicle); cam.make_current()`. Arkadan-yukarıdan takip: arka tampondan 6,3 m, 2,9 m yükseklik, 1,5 m yüksekliğe bakar, dikey FOV 58°. Yönelim gecikmeli (`yaw_follow` 3,2/sn) ve hızlıyken hız yönüne %35 çekilir (dönüşte araç hafif yandan görünür). Araç 1,4 sn durursa yavaşça yan-ön 150° yörüngeye geçer, hareket edince döner. `look_yaw` fareyle eklenebilir. **Ön ayarlar** (`apply_preset(name)`, `VehicleCamera.PRESETS`): `&"pursuit"` (takip kamerası: 5,0 m / 3,5 m / bakış 1,2) , `&"traffic_stop"` (durak: 5,4 / 3,8 / 1,5) ve `&"chase_offset"` (geniş kamera: arka tampondan 8 m, 4,2 m yükseklik, `look_yaw` 0,55 rad ≈ 30° sağdan; test sahnesinde `--cam chase_offset`). `@export` alanlarının kendi varsayılanı 6,3 / 2,9 / 1,5 kaldı; ön ayar için `apply_preset` çağır. `hold_look_yaw = true`: `apply_preset` `look_yaw`'ı değiştirmez ve durunca yan-ön yörünge kapanır. `snap()`, `camera` (iç `Camera3D`). Parametreler `@export` alanlarıdır.

## Ölçümler (`scenes/vehicles/test_drive.tscn --measure 1`, başsız, 60 Hz Jolt)
Komut: `araclar/godot.sh --headless --scene res://scenes/vehicles/test_drive.tscn -- --type patrol_suv --measure 1 [--tests accel,brake,turn,pit]`.
| büyüklük | hedef | ölçülen (`patrol_suv`) |
|---|---|---|
| 12→92 mph | ≈ 8 sn (10–12 mph/sn) | **7,9 sn**; 0→60 mph 5,8 sn |
| tepe hız | ≈ 112 mph | **111,8 mph** |
| orta fren | 12–14 mph/sn | pedal 0,45: **13,0 mph/sn** (80→20 mph) |
| sert fren | 25–30 mph/sn | pedal 1,0: **27,7 mph/sn** |
| kavşak dönüşü | 12–20 mph | tam direksiyonda yarıçap 4,8 m (12 mph), 8,8 m (20 mph) |
| gaz bırakınca yavaşlama | ≈3–4 mph/sn (entegrasyon isteği) | **2,9 mph/sn (20 mph), 3,4 (60), 4,2 (100 mph)**; `def["coast_mph_s"]` (varsayılan 2,9) motor freni + sürükleme |
| yüksek hızda geniş yay | geniş yay | yarıçap 37 m (40 mph), 86 m (60), 154 m (80), 244 m (100 mph); yanal 0,82–0,86 g, gövde yatması 2° |
Diğer türler (aynı komut): `sheriff_pickup` 12→92 mph 7,9 sn, tepe 111,8 mph, fren 13,0 / 28,6 mph/sn, yarıçap 5,7 m (12 mph) ve 234 m (100 mph); `patrol_sedan` 7,9 sn, 111,8 mph, fren 13,0 / 28,3; `civ_sedan` (1500 kg) 12→92 mph 10,7 sn, tepe 104 mph, fren 12,1 / 26,5; `civ_boxtruck` (4200 kg) 0→60 mph 15,7 sn, tepe 74,5 mph, fren 8,5 / 18,4 mph/sn. Tüm türlerde 100 mph tam direksiyonda yanal ivme 0,85 g, yatma ≤2,5°, devrilme yok. PIT dönüşü yalnızca `patrol_suv` ile ölçüldü.

## Test sahnesi ve ekran görüntüsü
`scenes/vehicles/test_drive.tscn`: düz yol, sürülebilir araç, takip kamerası. Tuşlar: W/S gaz-fren-geri, A/D direksiyon, Boşluk el freni, H far, F sürücü kapısı, G tüm kapılar, L ELS (Els autoload'u ile), P PIT, Tab sonraki araç, N gece/gündüz, R sıfırla. Argümanlar (`--` sonrası): `--type id`, `--night 1`, `--preset els_night|doors|pit|lineup`, `--cam pursuit|chase_offset`, `--sound 1`, `--fake_els 1`.
Ekran görüntüsü: `araclar/godot.sh --script res://scripts/dev/shot.gd -- --scene res://scenes/vehicles/test_drive.tscn --out x.png --frames 100 -- --type patrol_suv --night 1 --preset els_night`.
Model önizleme: `scenes/vehicles/model_view.tscn` (`--model a,b --yaw --pitch --dist --cells 1`).
Modelleri yeniden üret: `blender/vehicles/build_all.sh` (ardından `araclar/godot.sh --headless --import`). Sesleri yeniden üret: `python assets/audio/engine/synth_engine.py`.

## Bilinen sınırlar
- Hasar modeli, devrilme sonrası toparlama, tekerlek patlaması yok. Çarpışma sesi yok (sadece `collided` sinyali ve `impact.wav`).
- Kapılar çarpışma üretmez; açık kapı fizikte yok sayılır. Kapı camı gövdeyi geçip iç koltukları göstermez (cam yarı saydam, iç görünür).
- Arka lambaların ışığı yere vurmaz (yalnızca ELS hücre grupları `OmniLight3D` üretir). Far konisi gölgesizdir.
- Lastik izleri yalnızca arka tekerleklerden; iz genişliği 0,2 m sabit. Her sahne `Vehicles.skid_parent` atamalıdır (yoksa izler `Vehicles` düğümüne eklenir ve dünya kökünde görünür).
- Roadblock, çit, korkuluk ile PIT bitişi (korkuluğa çarpıp durma) dünya modülüne bağlı.
- `Vehicles.spawn` fizik çalışırken eklenir; spawn yüksekliği zeminden en az 0,1 m olmalı (süspansiyon oturur).

## Tasarım varsayımları (kodda `TODO(tahmin)` yok ama burada listelendi)
1. **Kamera** mesafe/yükseklik/FOV: arka tampondan 6,3 m, yükseklik 2,9 m, dikey FOV 58° (araç genişliği ≈%16, ufuk ≈%36).
2. Araç **kütleleri** (1150–4200 kg), sivil araçların ivme/tepe hız/fren değerleri (polis dışı), `knee` (%78), sürükleme katsayısı, yanal tutuş sınırı (8,5 m/sn²), direksiyon kilit açısı (35°) ve hızı (4 rad/sn).
3. **Vites/devir**: 5 vites, 5. vites 75 mph'te (eşikler 20/36/54/75), 5. vitesteki devir 75 mph'te 3300, 85'te 4000, 120 mph'te ≈4400; dururken 2–3, ≥90 mph'te 5 ×1000 RPM. Tepe hız 112 mph (`def["top_mph"]` ile ayarlanabilir).
4. **PIT** fiziği: kuvvet/tork ve tutuş kaybı süreleri deneysel; hedefin tam hız/yön tepkisi varsayımdır. 60 mph'te strength→dönüş eşlemesi kendi ölçümümüz.
5. **Işık hücre eşlemesi** 10–19 (ızgara, visor, arka güverte, köşeler) ve hücre→lamba bağı varsayımdır. Yer ışığı menzili 9 m, enerji katsayısı görsele göre.
6. **Kapı** açılma açısı 68° ve süre 0,38 sn; sürücü kapısı sol (ABD).
7. **Model oranları ve yazılar**: şerif pikabı (T-150, 214, BUSCO COUNTY SHERIFF), devriye sedanı ("Crusader" adı arka yazıdan), SUV beyaz çatı/kapı, `Halvorsen Ranger` renkleri; ahşap panel ve çatı bagajı. Sivil tür oranları ve renk paleti kendi seçimimiz. "GANG UNIT" yazısı yalnızca işaretsiz varyantta gri olarak var.
8. **Duman/iz**: parçacık sayısı, boyut, ömür, iz genişliği (0,2 m), iz görünürlüğü (alfa 0,55).
9. **Motor sesi**: 150–400 Hz harmonik çizgiler, hızla yükselir; V8 benzeri sentez ve 1000/3000/5200 rpm döngüleri varsayımdır.
10. Plaka yazı tipi/boyutu (Label3D), plaka konumları.
