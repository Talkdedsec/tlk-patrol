# Oyun döngüsü (entegrasyon): `scripts/main.gd`, `scripts/game/**`

Sahibi: ana oturum (entegrasyon). Ana sahne `scenes/main.tscn` (tek `Node3D`, betik `scripts/main.gd`); tüm modüller burada bir araya gelir. Kural: başka modülün dosyasına yazılmaz; eksik API için `scripts/game/` içinde adaptör vardır ("Modüllerden istekler").

## Dosyalar (`scripts/game/`)
| Dosya | Görevi |
|---|---|
| `game_hud.gd` | `hud.gd`'yi genişletir: alt ipucu, üst sağ donanım satırı ve amber çağrı/görev satırı için tek hakem. HUD olarak `main.gd` bunu kurar |
| `vehicle_seat.gd` | Yürüyüş / binme / sürüş / inme, sürüş girdisi, kamera, araç panelleri, MDT erişimi, minimap beslemesi |
| `hud_feed.gd` | Minimap (kırpım, sarı rota, çağrı ve hedef işaretçileri), sokak/limit, kadranlar |
| `game_hooks.gd` | Trafik başlatma + aşağıdaki düğümleri kurar (`director`, `radar`, `duty`, `recycler`); `quiet()`, `clear_traffic()`, `set_calls_enabled()` |
| `call_director.gd`, `scenes/*.gd` | Çağrı döngüsü ve olay yeri sahneleri |
| `radar_feed.gd` | RADAR (hız tabancası) ve ALPR (plaka okuyucu) |
| `duty_flow.gd` | Takip → yakalama → booking zinciri, Available/Busy, artıkların temizliği |
| `foot_chase_adapter.gd` | Yaya şüpheliyi Pursuit'ün yaya aşamasına sokar |
| `traffic_recycler.gd` | Uzaklaşan sivil araçları yeniden doğurmak yerine oyuncunun çevresine taşır |
| `player_officer.gd`, `drive_input.gd`, `game_input.gd`, `auto_drive.gd`, `perf_probe.gd`, `shot_setup.gd` | Önceki geçişten, ayrıntı aşağıda |
| `demo_tools.gd` | `_demo_stop` / `_demo_pursuit` yardımcıları (bekleme, ekran görüntüsü, araç takibi, koşan şüpheli, nişan) |
| `e2e_check.gd`, `e2e_run.gd` | Gerçek giriş olaylarıyla uçtan uca kontrol (163 kontrol) |

## Açılış (`main.gd`)
1. `GameInput.register()` (ek tuşlar), `World.build(self)`.
2. Gün başlangıcı: `GameState` saat **13:13**, `Cloudy`, saat akışı açık (1 gerçek sn = 1 oyun dk), skor 0, `Available`.
3. Devriye aracı: `Vehicles.spawn(&"patrol_suv", World.spawn_point(&"hoover_st"))` (çatıda `12`; tür yoksa `patrol_sedan`, `sheriff_pickup`). `player_vehicle` grubunda, `use_els(true)`, `Vehicles.skid_parent = self`.
4. Oyuncu: `officer.tscn` örneği, betiği `player_officer.gd` ile değiştirilir (`Officer` + araç sözleşmesi); `player` grubunda. `Weapons` kendini bağlar.
5. `GameHud.new()`, `VehicleCamera` + `VehicleSeat`, `GameHooks` (trafik, çağrı yönetmeni, RADAR/ALPR, zincir).

Senaryo çalıştırıcısı için `main` özellikleri: `player` (`Officer`), `patrol_vehicle` (`Vehicle`), `hud` (`GameHud`), `seat` (`VehicleSeat`), `vehicle_camera`, `hooks` (`GameHooks`: `director`, `radar`, `duty`, `recycler`).

**Memur modeli**: `main.officer_model` (`&"police"` varsayılan | `&"sheriff"`, trafik durağı memuru) memur kurulurken okunur; sahne kurulduktan sonra (senaryolar `setup` içinde) `main.set_officer_model(&"sheriff")` yürüyen memurun yerine yenisini kurar (konum, yön ve bakış korunur; `seat.officer`, `player.seat` güncellenir; Weapons, Pursuit ve TrafficStop memuru yeniden bulur). Araçtayken çağırmayın.

**Sessiz dünya**: `main.hooks.quiet()` tek çağrıyla çağrı teklifleri (`director.enabled=false`, `Calls.auto_offers=false`), ambient telsiz (`Calls.ambient_enabled=false`), ALPR taraması (`alpr_enabled=false`), yeniden kullanım düğümü (kapatılır) ve Main'in başlattığı sivil araçlar (devralınmış `owned=false` olanlar dahil; `Traffic.ambient_target=0`) ile biten çağrı sahnelerinin artıkları silinir. `TrafficStop.auto_detect` ayrıdır. `clear_traffic()` yalnızca araçları siler.

## Kontroller
| Tuş | Ne yapar |
|---|---|
| W A S D, fare, Shift | yaya hareketi / bakış / yürüme (Officer) |
| 5, LMB, RMB, basılı R | silah çek-kılıfla, ateş, nişan, doldur (Weapons) |
| **E** | `E  Get in` ≤6 m'de (araçtan inerken de görünür): kapıya yürür, kapı açılır, oturur (~1,5 sn). Başka bir E ipucu (`E  Cuff`, `E  Process the suspect`, `E  Talk`, `E  Talk to the driver`) görünürken araca binmez |
| W / S | gaz / fren, dururken geri vites; gaz bırakınca motor freni `Vehicle`'ın kendi `coast_mph_s` değeri (`DriveInput` artık eklemiyor) |
| A / D, Boşluk | direksiyon, el freni |
| **F** | araçtan in (≤4 mph; hızlıyken `Stop the car first`). Pursuit/TrafficStop'un çıkış isteği `seat.request_exit()`: araç frenler, durunca iner (en çok 9 sn) |
| **Q**, **X**, **H** (basılı), **L** | acil ışıklar, sonraki siren, A/H kornası, farlar |
| **V** / **G** / **P** | RADAR aç-kapa / ön okumayı kilitle (`LOCK F`) / plaka okuyucu aç-kapa (`Plate reader off` bildirimi) |
| **Tab** | MDT: araçtayken (sürülebilir) ya da araca ≤6 m yakındayken; uzaktayken `The MDT is in the patrol car`. Araçtan inince ya da uzaklaşınca kapanır |
| **Alt** / Esc (araçta) | fareyi serbest bırak / yakala (ELS panelini tıklamak için) |
| Y / N | çağrıyı kabul / geç (Calls) |
| **R** (kısa basış, yayada) | silahlı şüpheliye `drop it` emri (`They're holding a gun. R to order them to drop it; 5 to draw.`). Takipte R = PIT isteği (Pursuit) |
| B, C, Z, E, LMB | takviye, katıl, vazgeç, kelepçele/işle, Taser (Pursuit) |
| M, 1-8, 4 | sahne komutları, el feneri (TrafficStop) |
| F9 | hata ayıklama: öndeki araca ALPR isabeti |
Tasarım varsayımı tuşlar: Q, X, H, L, V, G, P, F9, Alt, Boşluk, R ile silah bırakma emri. Diğer tuşlar: E, W/S/A/D, 5, R, B, C, Z, Y/N, Tab, F.

## `VehicleSeat`
`mode`: `FOOT, ENTERING, DRIVING, EXITING`; sinyal `mode_changed(mode)`. Metotlar: `enter(vehicle, instant := false)`, `exit()`, `request_exit()`, `is_driving()`, `is_on_foot()`, `at_terminal()`, `toggle_mouse()`, `next_siren()`, `set_destination(pos, street)`, `clear_destination()`, `set_target_marker(vehicle)`. `scripted_drive`: true ise klavye yok sayılır (senaryo sürer).
- Giriş: silah kılıflanır, memur kapı noktasına yürür, `open_driver_door`, `enter_vehicle` animasyonu, `set_driver`, `VehicleCamera`, `HUD.set_vehicle_hud(true)`. Giriş sırasındaki ikinci E yok sayılır.
- Çıkış: `exit_vehicle` animasyonu (0,9 sn), kapı yanına iner, araç el frenine alınır. `Officer.exit_vehicle()` (Pursuit bail, TrafficStop) `request_exit()`'e gider.
- `E  Get in`: `ENTER_RANGE` 6 m (ipucu ≈5 m'de de görünür), inme animasyonu sırasında da görünür. İpucu HUD hakeminden geçer (aşağıda).
- Minimap: `World.minimap_image` 640 m kırpım (100 m'de bir ya da rota sokağı değişince yenilenir), sarı çağrı işaretçisi uzaktaysa harita kenarına (92 m) sabitlenir, çağrının sokağı sarı çizilir, ALPR işaretli/kovalanan araç turuncu elmas.

## `GameHud` (tek hakem)
`scripts/hud/hud.gd`'ye dokunulmadı; `game_hud.gd` onu genişletir ve birden çok modülün yazdığı satırları sıraya koyar:
- **Alt ipucu**: `set_prompt(text)` doğrudan çağıranlar (Pursuit afişi) `pursuit` kaynağıdır. Öncelik: Pursuit (`E  Cuff`, `E  Process the suspect`) > çağrı sahnesi (`E  Talk`) > TrafficStop (`E  Talk to the driver`, `E  Get in`) > koltuk (`E  Get in`). `set_prompt_from(kaynak, metin)`, `prompt_text()`.
- **Sağ üst yuva**: Taser satırları > `Flashlight on   4 off` > silah satırı (`set_equipment_lines`, `set_weapon_line`/`clear_weapon_line`, `weapon_slot_text()`).
- **Amber teklif / altın görev satırı** aynı yerde: teklif görünürken görev gizlenir (`offer_text()`, `mission_text()`).
- TrafficStop teklif, ipucu ve fener satırını kendi `stop_overlay.gd` etiketlerinde tutar; `GameHud` bunları her karede okur, overlay etiketlerini şeffaflaştırır ve HUD ölçüleriyle çizer (`traffic_stop.md`'deki "tek kaynağa indirme"). TrafficStop dosyalarına yazılmadı.

## Çağrı döngüsü (`call_director.gd`)
`Calls.simulate_response = false`, `Calls.auto_offers = false` (rastgele teklifleri yönetmen verir), `Calls.ambient_enabled = true` (diğer birimlerin telsizi). Senaryolar bu üçünü ve `hooks.set_calls_enabled(false)` / `hooks.alpr_enabled` çağrılarını eskisi gibi kullanır (adlar ve anlamlar değişmedi).
- **Teklif**: ilk çağrı 10 sn sonra, sonrakiler 70-130 sn arayla (çağrı, durak, takip ya da kayıt yokken). Sıra: durak, çalıntı araç, silahlı soygun, kaza; sonra rastgele (`BAG`). Konum yol grafiğinde oyuncudan 260-650 m uzakta (`DISTRICTS`: `the Southside`, `Oak Hills`, `Eastgate`, `Davidson Blvd`; metinler telsiz kelime bankasındaki kelimelerle). `Calls.offer` sözlüğüne `position` konur: 25 m'de Calls `10-97` der.
- **Kabul (Y)**: `Calls.call_started` → sahne kurulur, minimap'te sarı halka + sarı rota sokağı, görev `Respond to the ... near ...`, durum Busy. Oyuncu 230 m'ye girince sahnenin aktörleri belirir (görüş dışı).
- **Bitiş**: sahne `finish(&"cleared"|&"cancelled")` der, yönetmen `Calls.complete(outcome)` çağırır (`clearing.`, +10 puan, Available), işaretçi silinir. Oyuncu sahneye 480 sn gitmezse çağrı başka birime verilir. Aktörler `retire()` ile oyuncu 70 m uzaklaşınca silinir.
- API: `offer(kind, opts)` (`position`, `cruise_factor`, `violation`, `flees`, `surrender_chance`), `scene`, `completed`, `cancelled`, `enabled`, `interval`, `first_delay`, sinyaller `scene_started`, `scene_resolved`.

### Sahneler (`scripts/game/scenes/`)
| Çağrı | Sahne | Akış |
|---|---|---|
| `traffic_stop` (Code 2) | `scene_stop.gd` | İhlalli sivil araç (`TrafficStop.report_violation`: speeding/lane/seatbelt/...) çağrı yolunda yavaş ya da hızlı gider (`Traffic.adopt`). Işık açıkken 40 m arkadan TrafficStop kendi algılamasıyla durdurur: çekme, sahne komutları, E ile konuşma, karar, geri biniş. `stop_finished` çağrıyı bitirir. `flees` ise ALPR işareti gibi (`Pursuit.mark_target`) ışıkta kaçar |
| `stolen_vehicle` (Code 3) | `scene_stolen.gd` | BOLO aracı (çağrıdaki plaka/renk/model, `mdt_record.stolen`) kaldırımda park halinde. ALPR isabeti → ışık açık + ≤65 ft → kaçış (`Pursuit.start`) → PIT (R) → bail → yaya takibi → Taser → kelepçe → booking. `booking_finished` çağrıyı bitirir, `lost/called_off/aborted` iptal eder |
| `armed_robbery` (Code 3) | `scene_armed.gd` | Tabancalı şüpheli yol kenarında (`Npc.equip`). Görüşte ipucu toast'ı; **R**: bırakma emri (teslim → diz çök → `has them covered`, ya da koşar); 17 m'ye girmek, 9 sn beklemek ya da ateş etmek koşturur. `foot_chase_adapter.gd` Pursuit'ün FOOT CHASE'ini başlatır; Weapons ile düşürülürse `target_downed` Pursuit'e iletilir, öldürücüyse `subject deceased` satırı |
| `traffic_collision`, `trespassing`, `disturbance`, `suspicious_person`, ... | `scene_talk.gd` | İki kişi (kazada iki hasarlı araç) yolda durur; `E  Talk` ile her birini dinle (kendi cümlelerimiz); ikisi de dinlenince çağrı biter |

## RADAR / ALPR (`radar_feed.gd`)
- **RADAR** (V): öndeki ±9° / 170 m koniden `FRONT` (en yakın), `F FAST`; arkadan `REAR`, `R FAST`; `PATROL` kendi hız; `LOCK F` (G); `TGT` = limit+10 (5'e yuvarlı). Limit+8 mph üstü giden araç `TrafficStop.report_violation(…, &"speeding")` ile işaretlenir (durakta panelin ilk satırı olur).
- **ALPR** (varsayılan açık, P): 55 m / ±22° önde okunmamış araç → `TrafficStop.record_for(araç).hits` (MDT plaka sorgusuyla aynı kayıt). İsabet: `Pursuit.alpr_hit(...)` (beyaz `ALPR HIT   PLAKA   NEDEN` satırı, araç işaretlenir), panelde kırmızı `HIT  PLAKA  neden` (en çok 2 satır), 30 sn bekleme. Aranan/çalıntı/sabıkalı araç %70 kaçar, diğerleri yan çekilir (`flees=false` → `Traffic.pull_over` → `TrafficStop.begin`). Çağrı araçları `flees` / `alpr_force` meta'sıyla her zaman okunur.
- Işık açık + işaretli araç ≤65 ft önde → Pursuit kendisi başlatır (kaçar) ya da durdurur.

## Takip → yakalama → booking zinciri (`duty_flow.gd`)
`Pursuit.started` → Busy; PIT (R, Pursuit kuralı ya da senaryo kancaları) → spin → `suspect_bailed` (Pursuit oyuncuyu `exit_vehicle` ile indirir: araç frenler, iner) → `C` → FOOT CHASE → Taser (LMB) ya da Weapons → `E  Cuff` → `Cuffing...` 3 sn → `E  Process the suspect` → `Pursuit.process_requested` → `TrafficStop.begin_booking` → `book` / `arrest_on` / `done` → `booking_finished`: skor, `my prisoner's booked, show me 10-8.`, 20,5 sn sonra Available. Zincir olayları `duty.events` listesinde (testler okur). Şüpheli ve terk edilen araç `director.retire` ile temizlenir; kaybedilen araç trafiğe döner.

## Trafik doğurma sıçramaları (`traffic_recycler.gd`)
`Vehicles.spawn_traffic` araç başına ≈15 ms yapar (model örneği, tekerlek, dışbükey gövde, ışıklar; ölçüm: kurma 4,5-10,7 ms + ilk fizik karesi 1-12 ms). Traffic 340 m ötedeki aracı silip ≈1 sn'de bir yenisini kurduğu için sürüşte kare süresi sıçrıyordu. Başlangıçtaki 14 araç `Traffic`'ten devralınır (`owned=false`, `ambient_target=0`); uzakta ve görüş dışındaki araç 90-240 m halkada boş bir şeride taşınır (yeni plaka, aynı model; yol rotası sıfırlanır). Çağrı, durak ve takip araçlarına dokunulmaz. `hooks.recycle_traffic = false` eski davranışı verir.

## Kancalar (özet)
| Modül | Ne bağlı |
|---|---|
| `Traffic` | `spawn_ambient(14)` + yeniden kullanım, `siren_source = patrol_vehicle`, devriye aracı `Registry`'de (`player`) |
| `Calls` | yukarıdaki çağrı döngüsü; Overlay metinleri `GameHud` üzerinden |
| `TrafficStop` | kendi `auto_detect`i (ışık + öndeki araç 1 sn); `Officer.exit_vehicle/enter_vehicle`; teklif/ipucu/fener `GameHud`'a yansıtılır; booking Pursuit'ten |
| `Pursuit` | ALPR → `alpr_hit`, `mark_target`; yaya aşaması `foot_chase_adapter.gd`; ipucu `GameHud` |
| `Mdt` | Tab kendisi; kullanılabilirlik `VehicleSeat.at_terminal()` |
| `Weapons` | `Officer` sözleşmesiyle otomatik; araca binerken `Weapons.holster(true)` |

## Test ve ölçüm
```
araclar/godot.sh --headless --quit-after 300
araclar/godot.sh --headless --fixed-fps 60 --script res://scripts/game/e2e_check.gd -- [--only boot,foot,drive,radar,hud,calls,stop,pursuit,flee,armed,talk,weapons,quiet]
araclar/godot.sh --headless --fixed-fps 60 res://scenes/dev/scenario_main.tscn -- --scenario _demo_stop      # mantık denemesi (görüntü yok)
araclar/kayit.sh _demo_stop ; araclar/kayit.sh _demo_pursuit                                               # 1080p60 kayıt
araclar/godot.sh res://scenes/dev/scenario_main.tscn -- --scenario _demo_pursuit --noshots 1                # gerçek zamanlı kare süresi (PERF satırları)
```
`--noshots` en sona konur. Başsız çalıştırmada fare yakalanamaz: pistol kontrolü `Weapons.equip` ile yapılır. Sonuçlar bu dosyanın sonundaki "Doğrulama" bölümünde.

## Doğrulama (bu geçiş)
- `araclar/godot.sh --headless --quit-after 300`: `SCRIPT ERROR` / `Parse Error` yok (yalnızca çıkış sızıntı gürültüsü).
- `e2e_check.gd`: **163/163** kontrol (kısa alt küme `--only boot,hud,drive`: 38/38; `quiet` ve memur modeli değişimi dahil), gerçek `InputEventKey` / `InputEventMouseButton` ile: yürüme, `E  Get in` ipucu (inerken ve 5,4 m uzakta da görünür, 7,5 m uzakta yok), E ile binme (ikinci E yok sayılır), Q/X/H/L, W/S/Boşluk, hızlıyken F reddi, motor freni, V/G/P, Tab (araçta, yakında, uzakta), HUD ipucu/yuva/teklif hakemi, çağrı teklifi → Y → sarı işaretçi + sokak → sahne → 10-97, ışıkla durak (çekme, F, `E  Talk to the driver`, karar, geri biniş, Available), çalıntı araç (ALPR → ışık → kaçış → R PIT → bail → otomatik iniş → C → Taser LMB → `E  Cuff` → 3 sn → `E  Process the suspect` → booking → çağrı biter → Available), durmayan durak aracı (`flees`), silahlı şüpheli (R emri: koşar ve teslim olur; Weapons ile vurulur), iki kişilik kaza/ifade sahnesi. Art arda üç çalıştırma da tam geçti.
- `_demo_stop` (104,7 sn) ve `_demo_pursuit` (96,3 sn): `araclar/kayit.sh` ile `kayit/_demo_stop.mp4`, `kayit/_demo_pursuit.mp4` (1920×1080, 60 fps; ekran görüntüleri `kayit/<ad>-kareler/`). Movie Maker sırasında duvar saati ≈35-38 ms/kare (kodlama sınırlı, 26-28 fps kodlama hızı; çıktı 60 fps), render CPU 1,2-1,3 ms, GPU 9,0-9,7 ms, process 2,7-4,9 ms, fizik 1,7 ms.
- Gerçek zamanlı kare süresi (`--scenario ... --noshots 1`, RTX 3050 Ti, 1920×1080, 14 sivil araç): `_demo_pursuit` 12672 kare **143,7 fps** (7,0 ms), p99 8,8 ms, render CPU 0,8 ms / GPU 2,5 ms, ≈800 çizim çağrısı; `_demo_stop` 8623 kare 143,5 fps, p99 8,9 ms. Açılış karesi hariç en kötü kareler 52,9 / 32,6 / 28,7 ms (biri tek kare; ekran sınırı 144 Hz). Önceki geçiş (`_demo_drive`): p99 15,7 ms, 26-37 ms'lik doğurma sıçramaları; yeniden kullanımla aynı sürüşte en kötü kare 18-25 ms, takip senaryosunda 26 araç yeniden yerleştirilirken hiç araç kurulmadı.
- Senaryolar mantık denemesi başsız (`--fixed-fps 60`) 4 kez art arda tamamlandı (`DEMO` satırları zincir olaylarını ve yedeklerin kullanıldığı yerleri yazar).

Senaryo notları: doğal PIT teması bot ile nadiren oluşur, `_demo_pursuit` 20 sn sonra `force_pit_success` kullanır; yaya aşamasında şüpheli bir süre sonra yorulur (`DemoTools.tired`), memur engele takılırsa kısa yan adım atar, hâlâ takılırsa şüphelinin yanına konur (günlükte `stuck`); Taser ıskalarsa `downed_externally` ile yere indirilir. Bunların her biri `DEMO ...` satırı olarak yazılır.

## Modüllerden istekler
1. **Pursuit**: `begin_foot_chase(npc, options)` (şu an `foot_chase_adapter.gd` özel üyeleri kullanıyor: `_ensure_banner`, `_set_state`, `_score_t`; `units == null` iken `on_foot_pursuit_declared` hata veriyor: `Array[String]` ← `[]` ataması, bu yüzden adaptör sessiz bir `AiUnits` veriyor).
2. **Traffic**: `recycle_far_cars()` ya da `Traffic.despawn_mode = recycle` (şu an `traffic_recycler.gd` `_pick_edge` kullanıyor); `Traffic.clear()` devralınan araçları silmiyor.
3. **Vehicles / Vehicle**: `Vehicle.set_plate(plate)` (plaka etiketi + `_plates` tablosu); araç kurma maliyeti için gövde dışbükey şeklinin türe göre önbelleğe alınması (`_build_collision`).
4. **HUD** (`hud.gd`): `_add_log_line` zamanlayıcı lambda'sı 8 satır sınırında silinen etiketi yakalıyor: `Lambda capture at index 0 was freed` motor hatası (satır `is_instance_valid` ile korunuyor ama yakalama zaten boş; `weakref` ya da `Timer` düğümü gerekir). Kullanıcıya görünür etkisi yok.
5. **TrafficStop**: `Overlay.set_offer/set_prompt/set_flashlight_line` HUD'a yönlendirilirse `GameHud` köprüsü kalkabilir; `begin()` aracı zaten duruyorsa `PULLING_OVER` durumu tek karelik.
6. **Calls**: `Calls.offer` konumlu çağrı için `position` dışında `scene`/`street` alanlarını MDT CALLS sekmesinde göstermiyor (süs).

## Bilinen sınırlar
- Yolcu koltuğu/yolcu kapısı kullanılmıyor; kelepçeli şüpheliyi arka koltuğa alma yok (booking panelinden sonra şüpheli yerinde kalır, uzaklaşınca silinir).
- Araç hasarı yok. Çağrı yeri sahneleri tek yerde ve tek aktörle sınırlı (kaza: iki kişi, iki araç; olay yerine gelen AI polis aracı yok).
- Yaya şüpheli ile oyuncu aynı hızda koşar (`4,57 m/sn`); Taser menziline girmek şüphelinin engellere takılmasına ya da oyuncunun kestirmesine bağlı. Senaryoda şüpheli bir süre sonra yorulur (`DemoTools.tired`), oyunda böyle bir kural yok.
- Doğal PIT teması güvenilir değil (Pursuit raporu); demo ve testte `force_pit_success` yedeği var.
- Başsız çalıştırma fareyi yakalayamadığı için LMB ile Weapons ateşi e2e'de elle (`Weapons.fire_at`) yapılır; Taser LMB'si (Pursuit `fire` eylemi) gerçek olayla denenir.

## Tasarım varsayımları
1. `patrol_suv` oyuncu aracı (çatıda "12"); sedan/pikap alternatifi `PATROL_TYPES` listesinde.
2. Başlangıçta memur sürücü kapısının 1,4 m gerisinde, araç Hoover St sağ şeridinde kuzeye bakıyor.
3. Q/X/H/L/V/G/P/Alt/F9/Boşluk tuşları, gaz-direksiyon rampaları, araca binme 1,5 sn, `SEAT_DROP` 0,28 m, `ENTER_RANGE` 6 m, MDT erişimi (araçta ya da ≤6 m).
4. Araçtayken fare kamerayı çevirir ve 1,2 sn sonra arkaya döner.
5. Çağrı sıklığı (ilk 10 sn, sonra 70-130 sn), uzaklık (260-650 m), sahne doğma yarıçapı 230 m, 480 sn zaman aşımı, aktörlerin 70 m'de silinmesi.
6. ALPR menzili 55 m / ±22°, 30 sn bekleme, kaçma olasılığı %70; RADAR 170 m / ±9°, `TGT` = limit+10, ihlal eşiği limit+8.
7. Silahlı şüpheli: görüş 75 m, fark etme 17 m, bekleme 9 sn, bırakma emrinin işleme olasılığı %55, `R` ile emir.
8. Talk sahneleri: ifade metinleri, 2,6 m konuşma menzili, `E  Talk` ipucu, kaza için iki hasarlı araç.
9. Takip sonrası: Busy → 1,5 sn sonra Available (booking'de 20,5 sn), şüpheli ve araç 12 sn sonra, oyuncu 70 m uzaklaşınca silinir.
10. Trafik yeniden kullanımı: halka 90-240 m, 340 m uzaklık, 0,4 sn'de bir araç (yeni plaka, aynı model ve renk).
