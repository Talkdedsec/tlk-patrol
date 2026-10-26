# TrafficStop: trafik durağı, diyalog paneli, tutuklama/booking

Sahibi: `mdt`. Autoload `TrafficStop` (`scripts/traffic_stop/traffic_stop.gd`).
Dosyalar (`scripts/traffic_stop/`): `adapters.gd` (başka modüllerle köprü), `pull_over.gd` (durdurulan aracın sürüşü), `dialog_model.gd` (konuşma durum makinesi), `dialog_panel.gd` + `option_list.gd` (panel), `driver_profiles.gd`, `records.gd`, `charges.gd`, `scoring.gd`, `stop_overlay.gd` (üst orta istemler, alt ipucu, SCENE COMMANDS kutusu), `placeholder_npc.gd`. Sahneler: `scenes/traffic_stop/{dialog_panel,stop_overlay,test_stage}.tscn`.

## Akış
1. **Başlama**: `TrafficStop.begin(vehicle, opts = {})` (senaryo) ya da otomatik: ELS ışıkları açıkken (`Els.lights_active()`) oyuncu aracı ≤45 mph iken 40 m önünde, ±14° konide bir sivil araç 1 sn kalırsa başlar (`auto_detect`; `Pursuit` aktifken ya da araç ALPR ile işaretliyse Pursuit'a bırakılır). Işık kapalıysa `begin` Stage 2'yi açar (`opts.lights = false` dokunmaz). Araç zaten duruyorsa (`Pursuit.target_yielded`, ALPR) olduğu yerde devralınır. Trafik modülünün `Traffic.pull_over(v)`'si varsa onunla sağa çeker (durunca `hold_vehicle`), yoksa `PullOver` Vehicle API'siyle (S eğrisiyle sağa kayar, sabit yavaşlamayla durur; kayma `min(3,2, yol kenarına uzaklık - 0,9)`: dar yolda araç asfaltta kalır, kenar yol grafiğinden (`World.road_graph.nearest_edge`, kenar genişliğinin yarısı) okunur, grafik yoksa 3,2 m).
2. **3 sn sonra otomatik telsiz**: `1-Adam-12: traffic stop, plate KEA-9291.` / `Dispatch: received, 1-Adam-12, traffic stop near the Southside.` (`Calls.stats.stops` artar).
3. **SCENE COMMANDS** (`M`; komutlar `1`-`8`): sol kutuda 8 komut, üst ortada `PA: "..."` toast'ı. 1 `Pull up further` (≈8 m ilerler), 2 sonraki sokağa sağa girer, 3 oyuncu aracını izler, 4 durdurur, 5-7 fişek (3/6/8 kırmızı fişek + `Traffic.set_zone(...)`: yavaşlat/kapat), 8 fişekleri toplar. Araç durmuşken ve oyuncu araçtayken açılabilir.
4. **İniş**: oyuncu araçtan inince (`F`: `scripts/game/vehicle_seat.gd`, `Officer.exit_vehicle()`) durum **Busy** olur: `Status: Busy` toast'ı + `1-Adam-12: show me 10-6.` / `Dispatch: 10-4, 1-Adam-12.`; araç HUD'u gizlenir (`HUD.set_vehicle_hud(false)`).
5. **Yaklaşma**: sürücüye `flashlight_range` (8,5 m; yürüyüşün son ≈5 sn'si) kala fener otomatik açılır, sağ üstte 4,5 sn `Flashlight on   4 off` (`4` kapatır). Genel API: `TrafficStop.set_flashlight(on, show_line = true)`, `flashlight_on`, `flashlight_range`. Alt ortada ipuçları: kapıda (≤2,6 m) `E  Talk to the driver` (sonra `E  Talk`), kendi aracının yanında (≤3,4 m) `E  Get in`.
6. **Diyalog paneli** (`E`): sağda 536x990 panel (başlık `Traffic stop: KEA-9291  (Halvorsen Ranger SUV)`, italik anlatı, bölümlü seçenekler, hover, kaydırma çubukları). Esc `Step away` (ya da `Step away (Esc)` satırı): panel kapanır, konuşma korunur, `E  Talk` aynı kayıtla açar. Tüm yanıtlar sürücü profilinden gelir ve sesli okunur (`dialog_voice`).
7. **Karar** (DECIDE) → `Good stop.  -45 points` + maddeler, `Stop complete: -45 points` toast'ı ve skor **karar anında** değişir; `Done` paneli kapatır. Sürücü arabaya döner. Oyuncu araca binince araç trafiğe döner; 8 sn sonra `show me 10-8.` ile Available.
8. **Booking**: `Pursuit` kelepçelemeden sonra `Suspect cuffed. E to process them and book the charges.` ve `E  Process the suspect` istemlerini kendisi çizer; E'ye basılınca yaydığı `Pursuit.process_requested(npc, charges)` sinyalini `TrafficStop` dinler ve `begin_booking(npc, charges)`'ı açar (`Pursuit.auto_book` açıksa ikinci çağrı yok sayılır).

## API
| Üye | Açıklama |
|---|---|
| `begin(vehicle, opts = {}) -> bool` | `opts`: `profile` (sözlük ya da `&"showcase"`), `violation` (`speeding`, `lane`, `seatbelt`, `equipment`, `phone`, `reckless`), `instant`, `lights` (false: ELS'e dokunma), `siren` (ör. `&"wail"`: Els.set_siren; varsayılan durakta siren kapalı), `announce`, `flee` (true: `Pursuit.start`'a verir). KEA-9291 plakası otomatik `showcase` profilini alır. |
| `cancel()` | Kararsız bitirir, araç trafiğe döner. |
| `command(index)`, `set_scene_commands(open)` | Sahne komutları (M menüsü). |
| `open_dialog()`, `close_dialog()`, `dialog_open`, `dialog` (`DialogModel`) | Panel. `dialog.choose(&"why")` ile tıklama simüle edilir. |
| `begin_booking(npc, charges = [], opts = {})` | Booking paneli. `charges`: kimlik ya da görünen ad (`"Evading police in a vehicle"`); boşsa `evading`, `fleeing_foot`, `resisting`. Bunlar `[evidence]` etiketli ve önceden işaretli gelir, desteklenmiş sayılır. Başlık ve araç bilgisi `Pursuit.target`/`suspect_plate`'ten alınır (`opts.plate`, `opts.model`). |
| `record_for(node) -> Dictionary` | Araç kaydı (plaka, model, sahip, doğum tarihi, ehliyet no, bayraklar). `mdt_record` meta'sında saklanır. |
| `report_violation(node, id)` | Trafik modülü, aracın ihlalini işaretler (`violation` meta); panelin ilk satırı `You saw ... before lighting this car up.` olur. |
| `set_flashlight(on, show_line = true)`, `flashlight_on`, `flashlight_range` | El feneri (4 tuşu) ve çizgisi; yaklaşma menzili (varsayılan 8,5 m). |
| `state_name()`, `state` | `idle pulling_over stopped on_foot dialog wrap_up booking`. |
| Alanlar | `vehicle`, `driver` (Npc), `record`, `profile`, `auto_detect`, `auto_available`, `own_booking_ui`, `ui_parent`, `scene_commands_open`. |
| Sinyaller | `stop_started(vehicle)`, `state_changed(state)`, `vehicle_stopped(vehicle)`, `officer_on_foot`, `dialog_opened`, `dialog_closed`, `stop_finished(result)`, `booking_started(npc)`, `booking_finished(result)`, `scene_command(index)` |

`result`: `{ruling (warning|citation|arrest), points, items [{text, points}], charges, fines, arrested, plate, name, booking}`.

### Diyalog (`dialog_model.gd`, seçenek kimlikleri)
TALK: `why headed drink whose illegal weapons consent`; PAPERS AND MDT: `docs` (kalkınca yerine `name`), `plate`; INVESTIGATE: `step_out fst breath patdown search`; DIRECTIONS (sürücü araçtaysa): `pull_up next_street follow`; DECIDE: `warn cite arrest away`; formlar: `issue`, `arrest_on`, `back`, `done`. Kurallar: tek seferlik seçenekler kalkar; `Search the vehicle` kendiliğinden `Step out of the vehicle for me, please.` + sürücüyü indirir ve `Ask them to step out`, `Pat them down` (kendiliğinden), `Search` ile tüm DIRECTIONS'ı kaldırır; `Mind if I search the vehicle?` kalır.
Aramanın dayanağı: rıza (`with their consent`), olası sebep (`on probable cause: ...`: esrar kokusu, açık şişe, başarısız ayıklık testi) ya da yok: `You search the vehicle ` + turuncu `without consent or probable cause` + `.` (skor -40).
Belgeler: `Licence: <ad>, born <gg/aa/yyyy>, no. <D#######>` / `Registration: <model>, plate <PLAKA>, owner <ad>` (+ `, tags expired`, `Insurance: no proof produced`). `Run their name on the MDT` ehliyet/arama kaydını (`suspended`, `warrant`) panele ve MDT PLATES günlüğüne yazar. FST: `PASSED` (yeşil) / `FAILED`; Breathalyzer `0.000 BAC (legal limit 0.08)` / `OVER THE LIMIT`.

### Sürücü kişilikleri (`driver_profiles.gd`)
`calm`, `nervous` (esrar şansı %60), `hostile` (rıza %10, bıçak %18), `drunk` (BAC 0,09-0,17, FST başarısız, açık şişe), `rushed` (aile acil durumu: doğum, hastane; `showcase` profili ayrı). Her profil açılış anlatısı, selam, 10 yanıt ve gizli gerçek (BAC, kaçak, silah, rıza, ehliyet/tescil/sigorta, arama emri) içerir; kayıtlar plakadan üretildiği için aynı araç hep aynı geçmişe sahiptir.

### Skor (`scoring.gd`)
Üç satır sabittir: `No visible reason for the stop (-20)`, `Search without consent or probable cause; what it found won't hold up (-40)`, `Good discretion for a family emergency (+15)` (uyarı + acil durum). Diğer satırlar tahmin (aşağı).

## Girdi eylemleri
Modül kendisi ekler (InputSetup'a dokunulmadı): `scene_commands` **M**, `flashlight` **4**, (Calls) `call_respond` **Y**, `call_pass` **N**; `exit_vehicle` **F** `scripts/game/game_input.gd` ile aynı (çıkışı VehicleSeat yapar, TrafficStop yalnızca sonucu izler). `interact` (E), `close_menu` (Esc), `toggle_mdt` (Tab), `join_chase` (C), `call_off` (Z) InputSetup'tan.

## Diğer modüllerle sözleşme (adaptörler)
`adapters.gd` aşağıdakileri dinamik arar; bulamazsa yer tutucuya düşer.
- **Officer/oyuncu**: grup `player` (ya da `officer`, ya da betik sınıfı `Officer`); araçtayken `is_in_vehicle()`/`in_vehicle`; yoksa gizli ya da sürücü koltuğuna <0,8 m ise araçta sayılır. Çıkış/biniş: `exit_vehicle()`/`enter_vehicle(v)` varsa onlar; yoksa `Vehicle.open_driver_door()`, `set_driver(null/oyuncu)`, `enter_transform(&"driver")` ile ben yaparım. **Ana oturumdan beklenen**: oyuncunun sürdüğü araç `player_vehicle` grubunda olmalı ve Officer araçtayken `visible=false`/`in_vehicle=true` işaretlenmeli.
- **Vehicle**: `set_controls(throttle, steer, brake)` (steer +1 sağ), `set_handbrake`, `speed_mph/ms`, `enter_transform`, `seat_transform`, `open/close_driver_door`, `plate`, `display_name`, `is_police`; liste `Vehicles.all`.
- **Npc** (`scenes/characters/npc.tscn`): `sit(true)`, `stand_up()`, `walk_to(pos, speed)`, `talk(anim)`; sürücü koltukta araca bağlı çocuk düğüm olur (fizik kapalı), inince dünyaya taşınır.
- **Traffic**: `is_managed`, `pull_over`, `hold_vehicle`, `release_vehicle`, `set_zone(pos, r, &"slow"|&"closed")`, `clear_zones()`; `stop_hold` meta'sı.
- **HUD**: `show_toast` (üst orta tek slot), `set_chase_nearby`/`clear_pursuit` (kırmızı `Chase nearby` satırı), `set_emergency`, `set_mission`, `set_vehicle_hud`, `minimap.add_marker(pos, &"call")`; HUD yoksa kendi etiketlerini çizer. Amber çağrı teklifi (`Code 2: Trespassing.   Y respond   N pass   (25)`: `Y respond`/`N pass` arası ve parantez öncesi 3 boşluk), alt ipucu (`E  Talk to the driver`) ve `Flashlight on   4 off` satırı `stop_overlay.gd` içinde çizilir (oyun HUD'u bu metinleri okuyup kendi yuvasında çizebilir, bkz. `scripts/game/game_hud.gd`); HUD'un `set_offer` (%11), `set_prompt` ve `set_equipment_lines` (%5) metinleri overlay'dekinden büyüktür; `ui` düzeltirse `Overlay.set_offer/set_prompt/set_flashlight_line` HUD'a yönlendirilebilir.
- **Pursuit**: `process_requested(npc, charges)` dinlenir (booking), `Pursuit.start(v)` (flee), `join_chase()`; Pursuit durup yanaşan hedef için `TrafficStop.begin(v)` çağırır (`target_yielded`).

## Senaryo kancaları
```gdscript
# zaman çizelgesini oynatma iskeleti
Calls.simulate_response = false; TrafficStop.auto_detect = false
Calls.offer(Calls.make_call(&"trespassing"))            # t9: Code 2 istemi, (25) geri sayım
Calls.pass_offer()                                      # t10: N
Mdt.open(&"plates"); Mdt.run_plate_ahead()              # t20-t28
Els.set_stage(2); Els.set_lights(true)                  # t39
TrafficStop.begin(ranger_vehicle)                       # t39-t45: sağa çeker, radyo t42
TrafficStop.command(1)                                  # t48: PA toast + ilerler
# oyuncu iner (t71: Busy), kapıya yürür, E: TrafficStop.open_dialog()
TrafficStop.dialog.choose(&"why")                       # t95 ... docs t113, search t134, fst t164, breath t170, warn t194
Calls.offer(Calls.make_call(&"stolen_vehicle"))         # t68 (cevapsız: 25 sn sonra "1-Adam-14, take the stolen vehicle. Code 3.")
Calls.play_nearby_chase(40.0)                           # t119-t151 yan takip; Calls.call_off_chase() = Z (t151)
```
`TrafficStop.ui_parent = node` ve `Overlay.reparent_to(node)` (`stop_overlay.gd`), `Mdt.ui_parent = node` arayüzü bir SubViewport'a (ekran görüntüsü) taşır.

## Test
- Başsız uçtan uca: `araclar/godot.sh --headless res://scenes/traffic_stop/test_stage.tscn -- --auto [--hud]` (63 kontrol: ışık→çekme→M komutu→iniş→E→konuşmalar→-45→binme→MDT→çağrılar→acil bant→chase→booking; son satır `E2E OK`).
- Ekran görüntüsü: `scripts/dev/shot.gd --scene res://scenes/traffic_stop/test_stage.tscn --frames 40 --setup res://scripts/traffic_stop/dev/shot_dialog_start.gd` (`shot_dialog_mid.gd`, `shot_dialog_cit.gd`, `shot_overlay.gd`, `shot_mdt_*.gd`); yan yana kırpma `scripts/traffic_stop/dev/side_by_side.py`.
- Yazı genişliği ölçümü: `araclar/godot.sh --headless --script res://scripts/traffic_stop/dev/measure_text.gd`.

## Bilinen sınırlar
- Sürücü kapısı/koltuk konumlandırması `Vehicle.enter_transform/seat_transform`'a bağlı; gerçek `Npc` oturma animasyonu aracın içinde sürücü pozundan çıkarım (kapı animasyonu `open_driver_door`).
- `PullOver` yol/şerit bilgisini okumaz; kenar taşı yoksa araç mevcut çizgisinden 3,2 m sağa kayar (`Traffic.pull_over` varsa onunla yapılır).
- Fişek ve yol kapatma yalnızca küçük görsel + `Traffic.set_zone`; kapalı yolda trafiğin yön değiştirmesi (detour) Traffic modülünde yok.
- Citation/arrest sonrası sürücünün gerçekten karakola taşınması yok: tutuklamada `one in custody, transporting to booking.` + 20 sn sonra `my prisoner's booked, show me 10-8.`; sürücü araçta kalır.

## Tasarım varsayımları (kodda `TODO(tahmin)`)
1. **Başlama koşulları**: ışık + 40 m / ±14° koni + 1 sn + oyuncu ≤45 mph; Stage 2 varsayılanı; otomatik radyo gecikmesi 3 sn.
2. **PullOver geometrisi**: en çok 3,2 m sağa kayma (dar yolda `kenar - 0,9`), 3,5 m/sn² frenleme; komut 1 ≈8 m, komut 2 L biçimli rota (yol grafiği okunmaz).
3. **Komut 2-8 sonuçları** ve PA metinleri: `Driver, pull into the next street on your right and stop.`, `Driver, follow me.`, `Driver, stop right there.`, fişek ve yol kapatma toast'ları; M açma tuşu, 1-8 seçim, `F` ile araçtan inme.
4. **Fener**: 8,5 m'de otomatik, satır süresi 4,5 sn, `4` ile kapanma.
5. **Sürücü ayrılışı**: Done sonrası sürücü arabaya biner, oyuncu binince araç 90 m ilerler ve trafiğe döner; durum Busy → Available (`show me 10-8.`) 8 sn sonra.
6. **Diğer seçeneklerin sonuçları**: `Where are you headed?`, `Whose car is this?`, `Any weapons...`, rıza sorusu, `Run their name/plate on the MDT`, pat-down, DIRECTIONS; hepsi profilden, kendi cümlelerimizle. Pat-down aramanın içinde sayılır (arama sonrası listeden kalkar).
7. **Skor satırları** (ilk üç satır sabit, diğerleri varsayım): `Let an impaired driver go -50`, `Let a wanted person go -40`, `Contraband found but no action taken -10`, `Handled by the book +5`, `Pat-down without grounds -10`, suçlama başına `supported +10` / `nothing supports it -15`, `Missed: ... -5`, `Lawful arrest +25`, `Arrest without grounds -60`. `Good stop.` başlığı puandan bağımsız sabittir.
8. **Citation/arrest**: `Issue the citation` ve `Arrest on these charges` sonrası metinler (`You issue a citation: ...`, `Total fines: $N`, `You handcuff the driver and read them their rights.`), en az bir suç seçme zorunluluğu (`Pick at least one charge first.`), kutucuk görünümü (silik kare, işaretli mavi), arrest sonrası radyo.
9. **Ceza listesi görünümü**: işaretli kutucuk mavi dolguludur.
10. **Booking**: menü `Ask for licence and registration`, `Run their name/plate on the MDT`, `Breathalyzer`, `Pat them down for weapons`, `Search the vehicle`, `Book the charges`, `Step away (Esc)`; `[evidence]` etiketi amber; evidence maddeleri otomatik işaretli ve "destekli"; booking puanı aynı skor modeli; `10-15.` + 20 sn sonra `my prisoner's booked, show me 10-8.`.
11. **Sürücü profilleri**: beş kişilik, tüm cümleler, olasılıklar (esrar %60, rıza oranları, BAC aralığı) ve ihlal türleri (`speeding`, `lane`, ...) kendi tasarımımız; `rushed` varyantları (doğum, okul kazası). Plaka isabet olasılıkları (%27).
12. Fener satırı: `Flashlight on   4 off` `Overlay` ile çiziliyor (HUD'da ayrı API yok).
