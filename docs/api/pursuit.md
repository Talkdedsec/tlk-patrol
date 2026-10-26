# Takip (`Pursuit`) — araç takibi, PIT, yaya takibi, Taser, kelepçeleme

Sahibi: `pursuit`. Autoload: `Pursuit` (`scripts/pursuit/pursuit.gd`). Sivil trafik ve yol sürücüsü: `traffic.md`.

## Dosyalar
| Yol | İçerik |
|---|---|
| `scripts/pursuit/pursuit.gd` | Autoload: durum makinesi, otomatik başlangıç, PIT, birimler, yaya aşaması, skor, sinyaller, girdi |
| `scripts/pursuit/pit.gd` | PIT yetki makinesi (4 durum) + köşe teması geometrisi (`Pit.contact`) |
| `scripts/pursuit/suspect_driver.gd` | Kaçan sürücü yapay zekâsı (`LaneDriver` alt sınıfı) |
| `scripts/pursuit/chase_driver.gd` | Takip eden arabayı süren bot (test sahnesi, yapay zekâ birimleri): şüphelinin rotasını izler, `FOLLOW / PIT / STOP` |
| `scripts/pursuit/ai_units.gd`, `radio.gd` | Telsiz birimleri: katılma, konum/hız raporu, düşme, roadblock duyurusu, takviye; hız/yön sözcükleri |
| `scripts/pursuit/foot_chase.gd` | Yaya aşaması: kaçış, `Chase nearby` / FOOT CHASE, Taser, kelepçeleme |
| `scripts/pursuit/banner.gd` | Üst orta bildirim katmanı (`CanvasLayer` 11); HUD'un `show_toast / set_pursuit / set_foot_chase` yöntemleri varsa onları kullanır |
| `scripts/pursuit/adapters.gd` | Diğer modüllere köprü (Vehicles, World, Els, HUD, Officer/Npc); yer tutucular |
| `scripts/pursuit/placeholder_vehicle.gd`, `placeholder_npc.gd`, `test_road.gd` | Yer tutucu araç/yaya/yol (gerçek modüller yokken ya da `--fallback 1`) |
| `scripts/pursuit/test_pursuit.gd`, `scenes/pursuit/test_pursuit.tscn` | Test sahnesi (senaryolu 59 kontrol, elle oynama, ekran görüntüsü durakları) |

## Durum makinesi
```
IDLE ──start()/alpr_hit+ışık──▶ PURSUIT ──PIT teması ≥4 sn──▶ SUSPECT_DOWN ──durup 1,2 sn──▶ BAILED ─C─▶ FOOT_CHASE
                                   │                                                          │  Taser / Weapons.target_downed
                                   │ (>0,5 mi, 12 sn)                                         ▼
                                   └──────────▶ end(&"lost")                              SUBDUED ─E─▶ CUFFING ─3 sn─▶ CUFFED ─E─▶ end(&"processed")
PIT alt makinesi (PURSUIT içinde):
 IDLE "R request PIT" ─R─▶ REQUESTED "PIT requested" ─4–7 sn─▶ DENIED "PIT denied: speeds are too high" ─20 sn─▶ IDLE
                                                           └──▶ AUTHORIZED "PIT authorized" (takip bitene dek kalıcı)
```
`Pursuit.State`: `IDLE, PURSUIT, SUSPECT_DOWN, BAILED, FOOT_CHASE, SUBDUED, CUFFING, CUFFED`. `Pursuit.PitState`: `IDLE, REQUESTED, DENIED, AUTHORIZED`.

## Genel API
| Üye | Açıklama |
|---|---|
| `state`, `pit_state()`, `target`, `suspect` (yayaya inen NPC), `player_vehicle`, `officer`, `callsign` (`1-Adam-12`), `distance_ft`, `elapsed`, `evidence_charges` | Durum |
| `start(target_vehicle, options := {}) -> bool` | Takibi başlatır. `options`: `player_vehicle`, `officer`, `callsign`, `drive_suspect` (false: senaryo şüpheliyi kendisi sürer), `units` (false: yapay zekâ birim telsizi kapalı), `evader`, `plate`, `announce` (false: telsiz satırları yok) |
| `alpr_hit(vehicle, plate, reason, flees := true, evader := true)` | Beyaz `ALPR HIT   <PLAKA>   <NEDEN>` satırı (4,75 sn) + aracı işaretler. Işıklar (`Els.lights_on`) açılınca ve araç ≤65 ft önde, hareketliyse: `flees` ise takip başlar (≤0,25 sn), değilse `Traffic.pull_over` + durunca `TrafficStop.begin(vehicle)` ve `target_yielded` |
| `mark_target(vehicle, plate, flees, evader)`, `clear_mark()` | ALPR ekranı başka yerde yapılıyorsa yalnızca işaretleme |
| `request_pit() -> bool` | R. Yalnızca `IDLE` PIT durumunda ve araç takibinde |
| `begin_foot_chase(npc, options := {}) -> bool` | Araçsız yaya takibi başlatır (silahlı şüpheli çağrıları, senaryo): araç takibindeki iniş sonrası ile aynı durum (`BAILED`), afiş, telsiz, skor ve zincir. Şüpheli zaten kaçıyor olmalı (`npc.flee_from`). `options`: `plate`, `cover` (kapatan birim, varsayılan `7-Sam-34`), `announce` (toast `The suspect is running! Catch them.`), `declare` (`foot pursuit` telsiz satırları, varsayılan true), `score` (+20, varsayılan true), `evidence` (suç adları dizisi, varsayılan `Fleeing a police officer on foot`), `callsign`, `officer`. Takip sürerken `false`. `units`, `driver`, `pit`, `target` null kalır; yaya aşaması buna dayanıklı. |
| `notify_target_downed(npc, weapon, lethal)` | `Weapons.target_downed` ile aynı işlev (yaya aşaması başlamadan önce vurulan şüpheli için sahne çağrısı); özel `_on_target_downed` yerine bunu çağırın |
| `force_pit_success(side := 1.0)` | Senaryo kancası: spin-out'u şimdi uygula (`PIT: The car spun out.`, durma, iniş zinciri) |
| `set_pit_decision(authorized, delay := -1.0)` | Bir sonraki kararın sonucunu (ve süresini) belirler: senaryo kancası. Doğal kural: karar anındaki oyuncu hızı ≤ 40 mph ise onay |
| `request_backup()` | B. İlk basış `need a 10-78` + `1-Lincoln-30 is on the way (B again to clear them)`, ikinci basış iptal |
| `join_chase()` (C), `call_off()` (Z), `taser_fire() -> bool` (LMB), `interact() -> bool` (E) | Yaya aşaması. `join_chase()` `Calls` modülü tarafından da çağrılır |
| `toast(text, seconds)`, `say(text, delay := 0.0)` | Üst orta tek slot; `Dispatch.say` (gecikmeli kuyruk) |
| `end(reason := &"ended")` | Takibi kapatır, bildirimleri siler, `ended(reason)` yayar |
| `bind_ui(parent)` | Bildirim katmanını başka bir ağaca taşır (alt görüntü alanına çekim yapan testler) |
| `snapshot() -> Dictionary` | Test: durum + ekrandaki metinler (toast, kırmızı satır, `Chase nearby`, FOOT CHASE, bildirim ipucu) |
| `busy_on_start` (true) | false: takip boyunca görev durumu değişmez (`Available` kalır). `started` dinleyicisi (`scripts/game/duty_flow.gd`) `Busy` yapsa bile `start()` dönmeden önce `GameState.duty_status` ve `Calls.status` eski değerine geri yazılır. Tek takip için `start(v, {"busy": false})` |
| `bail_delay` (-1) | Spin-out'tan iniş anına saniye. <0: doğal (araç 1,2 sn durunca, en az 3 sn). Örnek: `bail_delay = 10.75` ya da `start(v, {"bail_delay": 10.75})`; iniş en erken bu süre dolunca ve araç durmuşken (en geç +3 sn) olur |
| `pit_contact_push` (true) | PIT temasında `Vehicle.pit_scuff(side, seconds)` (duman + kayma izi, impulssuz) varsa o kullanılır (0,25 sn'de bir) ve itme yapılmaz. Yoksa `pit_push(side, 0,6·dt)` ile hafif itme; false: itme de yok (yalnızca sayaç) |
| `lost_enabled` (true) | false: şüpheli hiç kaybedilmez (senaryo, soak testi) |
| `auto_book` (false) | true ise `process_suspect` sırasında `TrafficStop.begin_booking(npc, charges)` çağrılır |

**Sinyaller:** `state_changed(old, new)`, `started(target)`, `ended(reason)` (`&"processed" &"lost" &"called_off" &"aborted" &"suspect_down"`), `pit_state_changed(new)`, `pit_succeeded(target)`, `suspect_bailed(npc)`, `suspect_downed(npc)`, `suspect_cuffed(npc)` (kelepçe tamamlandığında; `TrafficStop.begin_booking` bunu dinler), `process_requested(npc, charges)` (kelepçeli şüpheliye E: `E  Process the suspect`), `target_yielded(vehicle)`, `backup_changed(requested)`, `taser_fired(hit)`.

`charges` = işaretli üç kanıt suçu: `Evading police in a vehicle`, `Fleeing a police officer on foot`, `Resisting arrest` (sırasıyla takip başlayınca, inişte, yere serilince eklenir).

## Ekran (HUD)
`banner.gd` HUD'un yöntemleri varsa hepsini HUD'a devreder (`Adapters.hud()`: `hud` grubu ya da ağaçta `set_pursuit` + `show_toast` olan ilk düğüm); HUD yoksa aynı yerleşimi kendi `CanvasLayer`'ında (katman 11) çizer.
- Beyaz geçici bildirim (y≈76, tek slot, yenisi eskinin yerine geçer): **tek yol `HUD.notify(text, seconds, center_x)`** (24/600 yazı tipi; `banner.gd` kendi etiketini yalnızca HUD yokken çizer). Süreler HUD'un `NOTIFY_SECONDS` sabitinden anahtarla alınır (`driver_fleeing` 1, `pit_requested` 2,25, `backup_on_the_way` 3, `pit_spun_out` 7, `bailed_out` 0 = değişene kadar, `cuff_offer` 0, `alpr_hit` 4,75). Uzun `has them covered` satırı x≈1050'de ortalıdır (`center_x = 1051`). `Pursuit.toast(text, seconds, key, center_x)` aynı yolu dışarıya açar.
- Kırmızı `PURSUIT   <mesafe>   <PIT durumu>`: `set_pursuit(feet, status)`; mesafe merkez-merkez ft, <100 ft 1 ft adım, ≥100 ft 10'luk, ≥528 ft `0.1 mi`.
- İkinci kırmızı satır `PIT position: steer into the back corner`: `set_pursuit_hint(text)` (≤20,5 ft'te açılır).
- Yaya aşamasında `Chase nearby, 31 ft   C join   Z call off`: `set_chase_nearby(feet)`; C'den sonra `set_foot_chase(feet)` (FOOT CHASE, ≥100 ft'te 10'a yuvarlama).
- Alt ipucu `E  Cuff` / `E  Process the suspect`: `set_prompt(text)`. Taser satırları `Taser out   LMB use` + `on target, 14 ft`: `set_equipment_lines([...])` (silah satırıyla aynı yuva; yalnızca değişince yazılır).
- Gerçek HUD'a ek istek yok. (`Weapons` silah satırı ile Taser satırları aynı yuvayı paylaşır: Taser çıkarken silah satırı üzerine yazılır, Taser bitince `[]` ile kapanır.)

## Telsiz ve bildirim metinleri
Kısa kodlar ve etiketler sabit; uzun cümleler kendi yazımımız (anlam ve biçim aynı). Örnek akış: `1-Adam-12: 10-80, vehicle failing to yield.` / `Dispatch: Copy, 1-Adam-12 is 10-80. All units, be advised.` / `Dispatch: Be advised, the registered owner has prior evading arrests. Use caution.` / `7-Sam-21: I'm 10-80.`; PIT: `Requesting permission to PIT.` → `Dispatch: 1-Adam-12, stand by.` → `supervisor clears the PIT.` | `supervisor says negative on the PIT, speeds are too high. Keep following.`; PIT sonu `<birim>: Good PIT, vehicle spun out.` (4,5 sn sonra); inişte `Suspect bailed, I'm in foot pursuit.`, `Dispatch: 10-4, foot pursuit. All units, be advised.`, `<birim>: 10-97.`, `Thanks for the assist, 1-Adam-12.`, yere serilince `Code four; suspect's down.`, kelepçede `10-15.` Birim raporları: `Still northbound, at thirty.` / `Turning westbound, slow speeds.` / `Heading northbound through Busco County, very fast speeds.` / `Still northbound, speeds over a hundred.`

## Senaryo kancaları (`scenarios/`)
```gdscript
const Adapters := preload("res://scripts/pursuit/adapters.gd")
Adapters.lights_override = 1                                   # ışıklar açık (Els yerine)
Pursuit.alpr_hit(target, "TAY-6023", "registered owner has a warrant")   # 0:06.5; 0:19.5'te otomatik başlar
# ya da doğrudan:  Pursuit.start(target, {"player_vehicle": player})
Pursuit.driver.speed_override_mph = 28.0                       # şüpheliyi sabit hızda tut (sürücüyü senaryo yönetmiyorsa)
at(56.3, func(): Pursuit.set_pit_decision(false, 6.0); Pursuit.request_pit())   # 0:56.3 -> 1:02.5 red
at(289.5, func(): Pursuit.set_pit_decision(true, 7.0); Pursuit.request_pit())   # 4:49.5 -> 4:56.5 onay
at(205.5, func(): Pursuit.request_backup())                    # 3:25.5
at(331.0, func(): Pursuit.force_pit_success(1.0))             # 5:50.75 spin-out (contact sayacını beklemeden)
```
`start(target, {"drive_suspect": false, "units": false})` ile şüpheli ve AI telsizi senaryonun elindedir; `say(...)` ile kayıt satırları zamanında eklenir.

## Diğer modüllerle bağlantı
- **Vehicles:** `Vehicles.spawn`, `set_controls(throttle, steer, brake)` (steer + = sağ; adaptör çevirir), `steer_towards`, `pit_scuff(side, seconds)` (varsa; temas görseli, impulssuz), `pit_push(side, dv)`, `pit_spin(side, strength)`, `start_smoke`, `open_driver_door`, `enter_transform`, `teleport`. Oyuncu aracını `player_vehicle` grubuna ekleyin (ya da `Pursuit.start(..., {"player_vehicle": v})`).
- **World:** `World.road_graph` (şerit dizisi `Route.lane_offset` = `World.lane_transform` ile aynı), `traffic_light_state_for_heading`, `street_at` (telsiz hız sözcükleri için limit).
- **Characters:** `Npc` (`flee_from`, `go_down(&"taser")`, `cuff`, `walk_to`) ile yaya aşaması; `Officer.get_aim_ray()` ile Taser nişanı; `Officer.draw_weapon(&"taser")` çağrılır (yükte yoksa sessizce `false`). Oyuncu araçtan inişini `exit_vehicle()` yöntemiyle yapar (yoksa çağrılmaz). Şüpheli inerken gerçek `Npc` doğar.
- **Weapons:** `Weapons.target_downed(npc, weapon, lethal)` dinlenir: FOOT CHASE göstergesi hemen kapanır, öldürücüyse `end(&"suspect_down")`. Taser `Weapons` kimliklerinde yok; bu modülde LMB (`fire` eylemi) ile.
- **Calls / TrafficStop:** `Calls.join_chase` → `Pursuit.join_chase()`. `Traffic.hold_vehicle / release_vehicle / set_zone` (traffic.md).
- **Els:** `Els.lights_on` otomatik başlangıç tetiğidir (`Adapters.lights_override` ile ezilebilir). Takip boyunca `Traffic.siren_source` oyuncu aracıdır: trafik sağa çekilir.

## Test
Her Godot çalıştırmasına `--quit-after N` ekleyin (sahne betiği hata verirse başsız süreç sonsuza kadar açık kalır ve `araclar/godot.sh` kilidini tutar).
```
# yer tutucu araç/yol, senaryolu tam akış: 59/59 kontrol (seed 2, 3, 5, 6, 8, 9; doğal PIT yaklaşması botun yetişmesine bağlı, seed 1/4/10 bazen yalnızca `hint`/spin kontrolünde düşer)
araclar/godot.sh --headless res://scenes/pursuit/test_pursuit.tscn --quit-after 40000 -- --auto 1 --speed 6 --fallback 1 --seed 5
# gerçek World + Vehicles + Npc (PIT teması doğal; olmazsa --force-pit 1 oyuncu aracını şüphelinin arkasına koyup spin'i zorlar)
araclar/godot.sh --headless res://scenes/pursuit/test_pursuit.tscn --quit-after 40000 -- --auto 1 --speed 6 --force-pit 1 --seed 5
# şüpheli sürücü dayanıklılığı (--nobot: oyuncu durur, takip kaybı kapalı)
araclar/godot.sh --headless res://scenes/pursuit/test_pursuit.tscn --quit-after 20000 -- --soak 1 --nobot 1 --speed 6 --soak-seconds 150 --seed 1
araclar/godot.sh --headless res://scenes/pursuit/test_pursuit.tscn --quit-after 4000 -- --braketest 1 --brakemode steer     # gerçek aracın frenleme ölçümü
araclar/godot.sh --script res://scripts/dev/shot.gd -- --scene res://scenes/pursuit/test_pursuit.tscn --out C:/tmp/p.png --frames 400 --auto 1 --speed 4 --fallback 1 --seed 5 --hold <durak>
```
`--hold` durakları: `pursuit denied authorized hint spun bailed tased cuffing cuffed` (betik o durakta bekler, sahne akar). Elle oynama: ok tuşlarıyla araç, R/B/C/Z/E/LMB. Hata ayıklama (`--debug N`): 1 PIT yaklaşması, 2 şüpheli sürücü, 3 konum/hız, 4 Taser, 5 çarpışmalar, 6 şeritten sapma (`--dbg-from/--dbg-to`).

Sonuçlar: yer tutucu modda 59/59 (`begin_foot_chase` ve Traffic kontrolleri dahil). Gerçek modda seed 5: 43/44 (yalnızca doğal PIT teması düşmedi, kalan tüm akış geçti: iniş, `Chase nearby`, skor +20, Taser, `has them covered`, `Cuffing...`, `Suspect cuffed`, `process_requested`, telsiz satırları). Diğer gerçek-mod seed'lerinde test botu şüphelinin gerisinde kaldığı için memur Taser menziline giremedi; mantık hatası değil, bot/fizik sınırı (aşağıda). `soak` (şüpheli tek başına, 150 sn): 3 seed'de 0/1/1 kurtarma, engellenme ≤4 sn.

## Bilinen sınırlar
- Gerçek `VehicleBody3D` fiziğinde test botu (`chase_driver.gd`) ile doğal PIT yakalaması güvenilir değil: bot virajlarda şüphelinin gerisinde kalabiliyor, temas anında araçlar birbirine dolanabiliyor (seed 8'de doğal spin oldu, seed 5-7'de olmadı). Yer tutucu araçlarda 44/44. Oyuncu elle sürerken sürekli köşe teması `Pit.contact` ile ölçülür; gerçek arabanın gövde ölçüleri `Adapters.half_size` içinde sabit (1,0 × 2,45 m yarı ölçü), `Vehicle` kendi ölçülerini açarsa oradan okunur (`extents` Vector3).
- Şüpheli sürücü gerçek araçla dar kavşak köşelerinde (yarıçap ≈6–8 m) hızı yeterince düşürmezse bordüre taşabilir; sıkışma kurtarma (geri vites ×2, sonra şeride ışınlama) bunu telafi eder. Frenleme planı `a_brake` 5 m/s² (pedal 12 m/s² verse de dönerken etkisi düşük).
- AI polis birimleri yalnızca telsiz; sahnede yalnızca roadblock arabaları ve kapatan memur (`sheriff` Npc) belirir. Olay yerine araç gelişi yok.
- Takviye birimi ekrana gelmez. Roadblock şüpheliyi durdurmaz (yalnızca yan şeritten geçirir / çarptırır).
- Telsiz seslendirmesi `Calls` modülündedir (`Dispatch.line_added`); burada yalnızca metin.

## Tasarım varsayımları (kodda `TODO(tahmin)`)
1. **PIT onay eşiği:** karar anındaki oyuncu hızı ≤ 40 mph onay, üstü red (21 mph onay, 65–87 mph red; arası varsayım). Şüpheli hızı kurala katılmaz.
2. PIT karar gecikmesi 4–7 sn düzgün dağılım (ölçülen 4, 6, 7, 7 sn).
3. **Spin-out eşiği:** tek ön köşe ↔ arka bölge (gövdenin %10'undan sonrası, 0,8 m tolerans; gerçek araçta gövde ölçüsü modelin AABB'sinden kestirilir, 12–20 ft merkez aralığında fiziksel temas sayılır), baş açıları ≤45°, şüpheli ≥10 mph iken toplam 4,0 sn sürekli temas (temas kopunca sayaç 0,75×/sn düşer); 0,6 ve 2 sn temas döndürmez, 6 sn döndürür.
4. PIT ipucu satırı ≤20,5 ft'te açılır, >24 ft'te kapanır (histerezis).
5. Şüpheli sürücü: hız artışı 14 sn sonra başlar, 30 sn'de tamamlanır; yol türüne göre çarpan (`SuspectDriver.KIND_K`); denetimli kavşaklardan ≈20 mph ile geçer, yan trafik varsa 5 mph; yavaş aracı karşı/yan şeritten geçer; oyuncu >460 ft gerideyse yavaşlar.
6. Yapay zekâ birimleri: 2–4 aktif birim, ömür 35–110 sn, rapor aralığı 7–12 sn, düşünce %40 `10-22`, 8–25 sn sonra yeniden katılım; hız sözcüğü eşikleri (≤24 `at twenty`, ≤34 `at thirty`, sonra limite oranla `slow/moderate/very fast`, ≥100 `speeds over a hundred`); bölge sözcüğü yol türüne göre.
7. **Roadblock:** 45–90 sn arasında bir birim duyurur; şüphelinin 140–420 m ilerisine iki park halinde devriye aracı; şüpheli geçince birim `my unit's disabled` der, araçlar 20 sn sonra kalkar.
8. Takviye: `1-Lincoln-30` 28 sn sonra `I'm 10-80` ile katılır; iptal metni `1-Lincoln-30 cleared`.
9. **Takip kaybı:** araç aşamasında >0,5 mi uzaklık 12 sn; yaya aşamasında >800 ft 12 sn; metin `You lost the suspect.`
10. İniş zamanlaması: dönüşten ≥3 sn sonra ve 1,2 sn durunca (en geç 16 sn); `They bailed…` bildirimi 3,5 sn; "foot pursuit" telsiz satırları iniş +0,5 sn.
11. **Skor +20:** inişten 1 sn sonra (`GameState.set_score(score + 20)`); olay bağı tahmin.
12. `C join`: `Chase nearby` satırı C'ye kadar kalır, C'den sonra FOOT CHASE göstergesi; Taser ve kelepçe C'den bağımsız çalışır.
13. Taser: iniş +2 sn'de çıkar, menzil 35 ft, nişan konisi 7°, ıskada 1,5 sn bekleme; `on target, N ft` hedef konideyken.
14. Kelepçe: E ile 3 sn (menzil 6 m; 7 m'den uzaklaşınca bozulur), oyuncu dokunmazsa kapatan birim 10 sn sonra kendisi kelepçeler; kapatan birim `7-Sam-34` (aktif birim varsa o).
15. Otomatik başlangıç: ışık + hedef ≤65 ft önde (47 ft'te de başlar) + 0,25 sn; durmayan hedef kaçar (`flees`), kaçmayan yol kenarına çeker.
16. Bildirim süreleri (ölçülmeyenler): `The driver is fleeing!` 3 sn, `1-Lincoln-30 is on the way…` 3 sn, `PIT requested` 2,25 sn.
17. Şüpheli yaya hızı `Npc.FLEE_SPEED` (4,57 m/s); kaçış yönü oyuncudan uzağa ±6 m sinüs sapması.
18. `process_requested` ayrı sinyaldir (E basışı); `suspect_cuffed` kelepçe bitince yayılır. `TrafficStop` tek sinyali dinleyecekse `process_requested` önerilir (`E  Process the suspect` adımı).
19. Telsiz cümleleri kendi yazımımız; Calls'un sesli okuması bu metinleri 1–2 sn gecikmeli çalar.
20. Kanıt suçlarının otomatik eklenmesi (`[evidence]` işaretli üç kutu).
