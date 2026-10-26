# HUD Sahibi: `ui`.
Giriş: `scripts/hud/hud.gd` (`CanvasLayer`, ana sahnede `HUD.new()`; 1920×1080 tuval). Alt parçalar: `els_panel.gd` (`ElsPanel`, bkz. `els.md`), `radar_panel.gd` (`RadarPanel`), `minimap_panel.gd` (`MinimapPanel`), `gauges.gd` (`Gauges`), `hud_style.gd` (`HudStyle`: yazı tipi + çizim yardımcıları).

## Genel API (`hud.gd`)
`hud.gd` ana sahnede `HUD.new()` ile kurulur ve `hud` grubuna girer. Senaryo/modül kodu HUD'u `get_tree().get_first_node_in_group("hud")` ya da `scenario_base.hud()` (alt düğümü `set_weapon_line` metoduna sahip olan) ile bulur; aşağıdaki bütün metotlar o düğümde çağrılabilir. Metin parametreleri aynen yazılır, boş metin satırı gizler.

| Metot | Ne yapar |
|---|---|
| `set_emergency(on)` | `EMERGENCY: all units responding` (üst orta, y≈76) |
| `notify(text, seconds = 3.0, center_x = 960)` | **Beyaz geçici bildirim** (aynı satır, tek slot: yeni bildirim eskisinin yerine geçer). `seconds <= 0` değişene ya da `clear_notify()` çağrısına kadar kalır. Birden çok bildirim gerekiyorsa sırayla çağrılır. `center_x`: uzun `has them covered` satırı x≈1050'de ortalanır. `show_toast` takma adıdır. |
| `clear_notify()` | Bildirimi hemen kaldırır. |
| `NOTIFY_SECONDS` (sabit) | Ölçülmüş süreler: `alpr_hit` 4.75, `alpr_hit_second` 4.5, `driver_fleeing` 1, `plate_reader_off` 1.75, `pit_requested` 2.25, `backup_on_the_way` 3, `rumbler_on` 1.5, `rush_hour` 4.5, `pit_spun_out` 7, `status_busy` 2, `pa_message` 3, `chase_called_off` 2, `stop_complete` 3, `bailed_out` ve `cuff_offer` 0 (kalıcı). |
| `set_foot_chase(feet)` / `clear_foot_chase()` | `FOOT CHASE   61 ft`, ≥100 ft'te 10'a yuvarlar, kırmızı-mercan. |
| `set_pursuit(feet, status)` / `clear_pursuit()` | `PURSUIT   510 ft   PIT requested`; ≥528 ft mil (`0.1 mi`), ≥100 ft 10'luk adımlar. Durum metinleri (`R request PIT`, `PIT requested`, `PIT authorized`, `PIT denied: speeds are too high`) çağıranın. |
| `set_chase_nearby(feet)` | Aynı yuvada kırmızı `Chase nearby, 31 ft   C join   Z call off` (yaya takibine geçişte PURSUIT yerine). |
| `set_pursuit_hint(text)` | PURSUIT altında ikinci kırmızı satır (`PIT position: steer into the back corner`). |
| `set_offer(text)` | Amber çağrı teklifi (`Code 2: Trespassing.   Y respond   N pass   (25)`, geri sayımı çağıran yazar), y≈172. |
| `set_mission(text)` | Altın görev metni (y≈176). |
| `set_prompt(text)` | Alt orta ipucu: `E  Get in`, `E  Talk to the driver`, `E  Cuff`. |
| `set_weapon_line(name, mag, reserve)` / `clear_weapon_line()` | `Pistol  17 / 34   LMB fire   RMB aim   hold R reload` (sağ üst, açık yeşil). |
| `set_equipment_lines(lines: Array)` | Aynı yuvada yeşil donanım satırları: `["Flashlight on   4 off"]`, Taser için `["Taser out   LMB use", "on target, 14 ft"]`. |
| `set_score_visible(bool)` | "Score" satırını gizler, durum satırı yukarı çıkar. Saat/hava/skor/durum metinleri `GameState`'ten gelir (`HH:MM`, `paused`, `Score N`, `Available/Busy`). |
| `set_street(street, mph)` | Minimap altı `Davidson Beltway  65 mph` (+ `Map  [,]` ipucu sabit). |
| `set_speed(mph)`, `set_rpm(thousands)`, `set_gear("N"/"1".."5")`, `set_speed_unit("MPH")` | Kadranlar (rakamlar tablo rakamlı yazı tipinde). |
| `set_map_texture(tex, world_rect)`, `set_player_state(pos, yaw)` | Minimap; işaretçiler `minimap.add_marker(pos, kind)`, `set_markers`, `clear_markers`. |
| `radar.set_radar(on, values, ant, dir, fast, target_mph)`, `radar.set_alpr(on, hit_lines)` | RADAR (ölçülmüş kapalı hal) ve ALPR paneli. |
| `set_vehicle_hud(bool)` | RADAR/ALPR, ELS paneli ve kadranlar yalnızca araçtayken görünür (başlangıçta gizli). |
| `set_vehicle_condition(vehicle_pct, engine_pct)` | Sağ altta küçük gri `Vehicle 92%   Engine 100%`; `-1` gizler. |
| `add_log_line(text, lifetime = 13.5)` / `clear_log()` | Telsiz günlüğü. Satırlar `Dispatch.line_added` ile de gelir; her satır 13.5 sn sonra silinir. `lifetime = 0` kalıcı yapar. |
| `set_els_panel_style("legacy"\|"overhaul")` | ELS paneli görünümü: `overhaul` (ELS SYSTEM, varsayılan) ya da `legacy` (eski LIGHTS & SIREN: FRONT/REAR/PODS/WIG satırları, `1 2 3` stage kutuları, AUTO/RUMBLER/MANUAL/BLIP, TRAFFIC HAZARD/CLOSED/CRUISE; ışık demosu, takip demosu ve yerel kayıtta görülen). `hud.els_panel_legacy` (`ElsPanelLegacy`) satırları `Els.row_colors(t)` ile çizer. |
| `set_street_visible(bool)` | Minimap altındaki sokak etiketi ve `Map  [,]` ipucu (eski düzende ikisi de yok). |
| `override_values({"speed", "rpm", "gear", "street": [ad, mph]})`, `clear_overrides()` | Oyunun kare başı beslemesinin (`set_speed`/`set_rpm`/`set_gear`/`set_street` çağrıları) üstüne yazılan sabit değerler; override edilen anahtar için normal çağrılar yok sayılır, `clear_overrides()` kontrolü geri verir. |
| Els bildirimleri | HUD, `Els.notice` sinyalini `notify(text, 1.4)` ile gösterir: `Stage 3: <desen>` (PTRN ya da stage değişince), `Traffic advisor: left\|right\|split\|warn\|hazard\|road closed\|off`. |
| `set_els_panel_style("legacy"\|"overhaul")` | ELS paneli görünümü: `overhaul` (ELS SYSTEM, varsayılan) ya da `legacy` (eski LIGHTS & SIREN: FRONT/REAR/PODS/WIG satırları, `1 2 3` stage kutuları, AUTO/RUMBLER/MANUAL/BLIP, TRAFFIC HAZARD/CLOSED/CRUISE; ışık demosu, takip demosu ve yerel kayıtta görülen). `hud.els_panel_legacy` (`ElsPanelLegacy`) satırları `Els.row_colors(t)` ile çizer. |
| `set_street_visible(bool)` | Minimap altındaki sokak etiketi ve `Map  [,]` ipucu (eski düzende ikisi de yok). |
| `override_values({"speed", "rpm", "gear", "street": [ad, mph]})`, `clear_overrides()` | Oyunun kare başı beslemesinin (`set_speed`/`set_rpm`/`set_gear`/`set_street` çağrıları) üstüne yazılan sabit değerler; override edilen anahtar için normal çağrılar yok sayılır, `clear_overrides()` kontrolü geri verir. |
| Els bildirimleri | HUD, `Els.notice` sinyalini `notify(text, 1.4)` ile gösterir: `Stage 3: <desen>` (PTRN ya da stage değişince), `Traffic advisor: left\|right\|split\|warn\|hazard\|road closed\|off`. |
| `reset()` | Her şeyi boş duruma getirir (durum oynatıcı ve sahneler yeni duruma geçmeden önce çağırır). |
| Alt düğümler | `hud.minimap`, `hud.radar`, `hud.els_panel`, `hud.gauges`. Hata ayıklama tuşları: mevcut eylemler + F5 sonraki siren, F6 stage. |

## Durum oynatıcı ve araçlar
`scenarios/data/hud_states.json` HUD durumlarını tutar: oyun durumu (saat, hava, skor, durum), HUD çağrıları (`["notify", "text", 3]`, `["radar.set_alpr", true, [...]]` gibi), telsiz satırları, sokak, kadran değerleri ve ELS durumu.
- `HudStatePlayer.load_states()`, `HudStatePlayer.find(states, id)`, `HudStatePlayer.apply(hud, state)` (`scripts/hud/hud_state_player.gd`): HUD'u, `GameState`'i ve `Els`'i o duruma getirir; senaryolar da kullanabilir.
- `scripts/hud/hud_states_shot.gd`: bütün durumları siyah 1920×1080 tuvalde çekip `<id>.png` yazar.
```bash
araclar/godot.sh --script res://scripts/hud/hud_states_shot.gd -- --out C:/tmp/hud_states
```

## Minimap
`MinimapPanel` 229×229 (17,750), dönen harita (araç yönü yukarı), sabit beyaz ok, `N` etiketi kuzey yönünde 107 px halkada. Dünya ekseni: x doğu, z güney (kuzey = -Z); `yaw` = Y ekseni dönüşü (0 = kuzeye bakar). `set_map_texture(tex, covers: Rect2)`: doku `covers` (x,z metre) alanını kaplar; varsayılan 1024×1024 m. Ölçek `pixels_per_meter = 1.15`. İşaretçiler: `&"unit"` mavi daire + beyaz halka, `&"target"` turuncu eşkenar dörtgen, `&"call"` sarı halka. Test haritası: `MinimapPanel.make_test_map()` (otoyol hakî kalın, sokak gri ince). Dünya oturumu yol grafiğinden bir doku üretip `set_map_texture` ile verir.

## Kalibrasyon
Yazı tipi: **Open Sans** (SIL OFL 1.1; `assets/fonts/OpenSans-Variable.ttf`, `OpenSans-Italic-Variable.ttf`, lisans `assets/fonts/OFL-OpenSans.txt`, kaynak google/fonts). Yükseklik `font_size` ile, genişlik değişken yazı tipinin `wdth` ekseniyle (96-100) ayarlanır. Boyutlar (boyut, ağırlık, wdth): saat 25/400/98, hava 26/400/96, skor 18/400/100, durum 19/400/98, silah satırı 18/400/97, görev 21/400/99, PURSUIT 26/500/100, sokak 16/400/99, harita ipucu 13/400/97, telsiz günlüğü 17/400/97 (satır adımı 26 px). Diğer öğeler: bildirim ve EMERGENCY 24/600/100, FOOT CHASE 26/600/100, PURSUIT ve ipucu 26/550/100, çağrı teklifi 21/600/95, alt ipucu 24/600/97, donanım satırı 19/400/96, araç durumu 15/400/97; kadran hız rakamı tablo rakamlı (`tnum`).
Telsiz günlüğü sarma genişliği: 470 px.
Sahneler: `scenes/ui/hud_test.tscn` (`scripts/hud/hud_test.gd`, `--preset silah|els|pursuit|els_on`), çekim `scripts/dev/shot.gd`:
```bash
araclar/godot.sh --script res://scripts/dev/shot.gd -- --scene res://scenes/ui/hud_test.tscn --out C:/tmp/hud_silah.png --preset silah --frames 12
```

### set_offer / set_prompt (TrafficStop için)
`set_offer`: 21 px, yarı kalın, renk `#E4D794`, y≈172, boşluklar üçer boşluk; `set_prompt`: 24 px, yarı kalın, beyaz, y≈976, koyu dış hat; `set_equipment_lines`: 19 px. Arka plan kutusu yok. **TrafficStop HUD'u kullanabilir**: `stop_overlay.gd` kendi etiketleri yerine `hud.set_offer(text)`, `hud.set_prompt(text)`, `hud.set_equipment_lines(["Flashlight on   4 off"])`, `hud.notify(text, seconds)`, `hud.set_chase_nearby(feet)` çağırabilir.

### Bildirimler (`notify`)
`hud.notify` çıktısı 24 px, yarı kalın. Oyunda beklenmedik genişlik görülüyorsa bildirim HUD'dan değil başka bir etiketten çiziliyordur (ör. `scripts/pursuit/banner.gd` kendi `_toast` etiketi: 22 px, Godot varsayılan yazı tipi). `banner.gd` `show_toast` metodunu bulunca HUD'a devreder; en güvenlisi doğrudan `hud.notify(text, seconds)` çağırmak.

## Bilinen sınırlar
- Kadran rakamlarının/vites rakamının ölçüleri gözle ayarlandı (~±2 px). Kadran ibresi yumuşatılmaz (çağıran filtreler).
- Saat metni "paused" çift boşluklu (`GameState`), ana oturumun.
- Panellerin tuş/fare etkileşimi için oyun fareyi serbest bırakmalıdır (ana oturum).

## Tasarım varsayımları
0. Telsiz günlüğü satır ömrü 13.5 sn; `Vehicle 92%   Engine 100%` yalnızca eski düzende var, anlamı (araç/motor durumu) çıkarım; `E  Cuff` ipucu alt ortada; `set_chase_nearby` yuvası PURSUIT ile aynı.
1. RADAR açık hali: sağa hizalı 22 px hız rakamı (kırmızı/amber/yeşil parlak tonlar), `ON` rozeti yeşil çerçeve; ALPR açık hali: `HIT  <plaka>  <neden>` kırmızı satırlar, boşken `scanning`.
2. Minimap ölçeği (1.15 px/m), işaretçi boyutları, çağrı işareti (sarı halka), N halkası yarıçapı (107 px).
3. Kadran geometrisi: tik uzunlukları, rakam yarıçapı, ibre/göbek ölçüleri gözle; kırmızı bölge yayı 6.5 px.
4. Toast satırı konumu/stili EMERGENCY ile aynı (y≈76).
5. PURSUIT mil geçişi 528 ft; renk #E8505A.
6. Telsiz günlüğü en çok 8 giriş; süre dolunca silme yok (`Dispatch` ile sınırlı).
7. Araç panelleri yaya iken gizli.
8. ELS panelinin tüm tasarım varsayımları `els.md` içinde.
