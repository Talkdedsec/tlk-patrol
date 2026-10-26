# Els: ışık/siren durumu ve "ELS SYSTEM" paneli

Sahibi: `ui`.
Dosyalar: `scripts/els/els.gd` (autoload `Els`), `scripts/els/patterns.gd` (`ElsPatterns`), panel `scripts/hud/els_panel.gd` (`ElsPanel`).

## Els (autoload)
Durum:

| Alan | Anlam |
|---|---|
| `stage: int` (0..3) | Slider konumu (OFF/1/2/3). Başlangıç 3. |
| `lights_on: bool` | Işık deseni çalışıyor mu. Başlangıç `false` (Stage 3 ama hücreler sönük). `lights_active()` = `lights_on and stage > 0`. |
| `siren_tone: StringName` | `&"wail" &"yelp" &"prty" &"hilo" &"hyper_yelp" &"yelp2" &"pierce" &"hyper_hilo" &"mech_wail" &"rotor"`, kapalıyken `&""`. |
| `pattern_index: int` | -1 = otomatik (sirene bağlı), değilse `ElsPatterns.ORDER` indeksi. |
| `traffic_dir` | `&"" &"left" &"split" &"right"` |
| `toggles: Dictionary` | `take_down left_alley right_alley spot cruise dim front_cut rear_cut rumbler auto_siren prog warn haz road_clsd` → bool |
| `held: Dictionary` | basılı tutulan düğmeler: `man`, `ah`, `blip` |
| `siren_note: String` | Siren satırına eklenen parantez (ör. `"(junction ahead)"`, eski panel davranışı). |

Sinyaller: `changed` (herhangi bir durum değişti), `notice(text)` (kısa beyaz bildirim metni: `Stage 3: <desen>` desen/stage değişince, `Traffic advisor: left|right|split|warn|hazard|road closed|off`; HUD bunu 1.4 sn `notify` eder).

Metotlar:
- `set_stage(n)`, `set_lights(on)`, `set_siren(tone)` (siren seçince ışıklar açılır, stage 0 ise 3 olur, `Sirens.play/stop` ve tık sesi çağrılır), `toggle_siren(tone)` (aktif sirene tekrar basmak siren ve ışığı kapatır).
- `set_toggle(id, on)`, `toggle(id)`, `is_on(id)`; `set_traffic_dir(dir)` (aynısına tekrar basınca kapanır); `press(id)` / `release(id)` (MAN, A/H, BLIP: tutarken); `cycle_pattern(±1)`; `set_siren_note(text)`.
- `now() -> float`: Els'in kendi saati (sn). Araç tarafı `cell_colors(Els.now())` çağırır.
- **Siren kapalı + ışık açık** iken otomatik desen listede yürür (`Els.IDLE_SEQUENCE`, `idle_pattern_at(saniye)`): `Bounce` 7.5 sn → `Slow alternate` 8 sn → `Double alternate slow` 8 sn → `Slow pulse together` 8 sn → `Rotator slow` (son desen tutar). Işıklar kapalıyken `Double cross`; o ışık oturumunda bir siren çalıştıysa (otomatik siren durunca) yine `Double cross`. Geçiş süreleri ışıklar açıldıktan ≈7.5, 15.5, 23.5 ve 31.5 sn sonradır.
- `set_pattern(name, announce = false)` (elle desen, ad bilinmiyorsa otomatiğe döner), `set_auto_pattern(name)` (geçerli sirenin otomatik desenini değiştirir; eski panelde `Yelp (junction ahead)` → `Auto: Response quad cross`).
- `row_colors(t) -> Array`: 4 `PackedColorArray(10)`: FRONT, REAR, PODS, WIG (eski panel satırları; stage maskesi ve DIM uygulanır). `cell_colors(t)` = PODS satırı.
- `cell_mask(t) -> int`: yanık hücrelerin bit maskesi (bit i = hücre i, 0..9).
- **`cell_colors(t: float) -> PackedColorArray`**: 10 hücrenin o andaki rengi, sönük = `Color(0,0,0)`. Hücre 0-4 kırmızı, 5-9 mavi. DIM açıkken %40 parlaklık. Stage maskesi uygulanır (aşağı bak).
- `traffic_colors(t) -> PackedColorArray`: 8 amber hücre (yön okları süpürür; WARN/HAZ/ROAD CLSD tümünü yakıp söndürür).
- `status_lines() -> PackedStringArray`: panel durum kutusunun 3 satırı: `STAGE 3  Auto: Triple alternate`, `SIREN  Yelp`, `READY`. Elle seçilmiş desen `Auto:` öneki olmadan çıplak adıyla yazılır (eski panelde `Quad alternate`).
- `auto_pattern()`, `pattern_name()`, `siren_label()`, `lights_active()`.

Siren → ad/desen eşlemesi (`Els.SIRENS`): wail Wail/Counter-rotating, yelp Yelp/Triple alternate, prty Priority/Sparkle, hilo Hi-lo/Double cross, hyper_yelp Hyper yelp/Six-burst cross fast, rotor Mechanical rotor/Counter-rotating, mech_wail Mech wail/Bounce, yelp2 Yelp 2/Triple alternate, pierce Piercer/Sparkle, hyper_hilo Hyper hi-lo/Six-burst cross fast; kapalı: Off/Double cross.

## ElsPatterns (desen verisi)
`ElsPatterns` iki kaynaktan beslenir:
- **57 ışık deseni** (`Stage 3: <ad>` bildirimleri) `scripts/els/pattern_data.json` içinde: eski panelin FRONT/REAR/PODS/WIG satırlarının (10'ar hücre) 60 fps örneklemesi. Periyot: hücre uyuşmazlık oranı küçük olan en küçük `p`. Hücre sınıfları: `.` kapalı, `R` kırmızı, `B` mavi, `W` beyaz, `C` krem, `r`/`b` sönük, `A` amber.
- **Sirene bağlı 6 desen** (Double cross, Counter-rotating, Triple alternate, Sparkle, Six-burst cross fast, Bounce) ile `Slow alternate`: yeni panelin mavi satırından ölçülen elle kurulu zamanlama (`LEGACY`); 10 hücre sözleşmesi bunlar için aynen kaldı.

API: `ElsPatterns.ORDER` (PTRN < > sırası: 57 ad + `Slow alternate`), `mask_at(name, t)`, `colors_at(name, t)` (PODS satırı, beyaz hücreler dahil), `rows_at(name, t) -> PackedStringArray` (4 satır, 10 karakter), `row_colors(name, row, t)`, `period_of(name)`, `has_pattern(name)`. Doğrulama: `araclar/godot.sh --headless --script res://scripts/els/patterns_check.gd`.

| # | ad | periyot (s) | adım |
|---|---|---|---|
| 1 | Rear warning | 1.183 | 8 |
| 2 | Response triple | 1.800 | 15 |
| 3 | Response quad cross | 1.283 | 17 |
| 4 | Priority sweep | 3.367 | 54 |
| 5 | Scene (officer out) | 0.950 | 15 |
| 6 | Single alternate | 1.317 | 5 |
| 7 | Double alternate | 1.250 | 9 |
| 8 | Triple alternate | 1.683 | 13 |
| 9 | Quad alternate | 3.083 | 32 |
| 10 | Quint alternate | 1.817 | 21 |
| 11 | Six-burst alternate | 2.100 | 25 |
| 12 | Double alternate slow | 2.400 | 9 |
| 13 | Quad alternate fast | 1.000 | 17 |
| 14 | Triple alternate with white | 1.267 | 13 |
| 15 | Long burn alternate | 0.950 | 3 |
| 16 | Hyper burst alternate | 1.600 | 32 |
| 17 | Single together | 0.700 | 5 |
| 18 | Double together | 0.700 | 7 |
| 19 | Triple together | 1.683 | 17 |
| 20 | Quad together | 0.983 | 11 |
| 21 | Slow pulse together | 0.983 | 5 |
| 22 | Double cross | 0.833 | 9 |
| 23 | Triple cross | 1.117 | 13 |
| 24 | Quad cross | 1.400 | 17 |
| 25 | Six-burst cross fast | 1.267 | 24 |
| 26 | Front-back double | 1.400 | 17 |
| 27 | Front-back quad | 2.150 | 33 |
| 28 | Front-back crossed | 1.950 | 25 |
| 29 | Sweep driver to passenger | 0.500 | 11 |
| 30 | Sweep passenger to driver | 0.500 | 11 |
| 31 | Bounce | 1.617 | 37 |
| 32 | Centre out | 0.700 | 11 |
| 33 | Outside in | 0.700 | 13 |
| 34 | Comet | 0.400 | 12 |
| 35 | Sweep and flash | 1.983 | 53 |
| 36 | Crossing waves | 0.600 | 11 |
| 37 | Centre out and flash | 1.317 | 26 |
| 38 | Rotator | 0.950 | 19 |
| 39 | Rotator slow | 1.583 | 28 |
| 40 | Counter-rotating | 0.950 | 21 |
| 41 | Beacon | 1.250 | 21 |
| 42 | Random strobe | 3.200 | 65 |
| 43 | Chaos | 2.233 | 64 |
| 44 | Sparkle | 3.200 | 81 |
| 45 | Tri-colour alternate | 1.433 | 25 |
| 46 | Colour cycle | 2.517 | 26 |
| 47 | Colour sweep | 1.167 | 27 |
| 48 | Red, white and blue burst | 1.400 | 13 |
| 49 | White strobe split | 0.883 | 13 |
| 50 | Amber rear, colours front | 1.117 | 13 |
| 51 | Steady burn and flash | 1.250 | 5 |
| 52 | Steady burn, rear flashing | 0.200 | 1 |
| 53 | Steady dim | 0.200 | 1 |
| 54 | Rear alternate | 0.950 | 5 |
| 55 | Rear amber alternate | 0.783 | 5 |
| 56 | Rear sweep | 1.200 | 21 |
| 57 | Auto | 1.250 | 9 |
| 58 | Slow alternate | (tahmin) | |

## ElsPanel (görünüm)
`ElsPanel` (Control, 558×248, (993,766)) yalnızca `Els` durumunu çizer ve fare tıklamasını `Els`'e iletir; `HUD.els_panel` olarak erişilir, `HUD.set_vehicle_hud(true)` ile görünür. Düğme ızgarası 8×3 (58×33, adım 64×40), renk grupları arduvaz/camgöbeği/kırmızı/mor, durum kutusu, ışık hücre satırları (3. satır mavi, yalnızca o satır yanar), STAGE kaydırıcısı (tıkla/sürükle), PATTERN `PTRN < >`, TRAFFIC `« <> » WARN HAZ ROAD CLSD`.
Düğme türleri: siren (seç/bırak), toggle, basılı tut (MAN, A/H, BLIP).

Kullanım:
```gdscript
Els.set_siren(&"yelp")                       # panel, ışık deseni ve ses birlikte
var colors := Els.cell_colors(Els.now())     # araç ışık çubuğu için
Els.press(&"ah"); Els.release(&"ah")         # korna
```
Test: `araclar/godot.sh --headless --script res://scripts/hud/els_selftest.gd` (18 kontrol: tıklamalar, durum satırları, desen, stage, `cell_colors` sözleşmesi, tüm tonlar). Görsel: `scenes/ui/hud_test.tscn` (`--preset els`, `els_on`).

## Bilinen sınırlar
- Işık hücre → araç lambası eşlemesi sözleşmesi: 10 hücre, soldan sağa, 0-4 kırmızı, 5-9 mavi. Araç oturumu kendi lambalarına bunu uyarlar.
- Panel fare ister; oyun fareyi yakalıyorsa panelin tıklanması için imleç görünür olmalı (ana oturum). Hata ayıklama tuşları (HUD): F5 sonraki siren, F6 stage döngüsü.

## Tasarım varsayımları
Ölçülenler (artık tahmin değil): Stage 1/2 yerleşimi: Stage 1 FRONT'u hiç yakmaz, REAR'ın tamamını, PODS hücre 3-6'yı ve WIG'in dış bloklarını (0,1,8,9) kullanır; Stage 2 ve 3 bütün hücreleri kullanır (`Els.STAGE_ROW_MASKS`). Elle desen etiketi çıplak ad. Toast metinleri ve süresi (1.4 sn).
1. `STAGE OFF` metni (yeni panel; eski panel `Off (stage N)` yazar, ölçüldü).
2. PTRN `<` `>` hangi sırayla dolaşır: panel liste sırası + `Slow alternate`.
3. Bounce süresi 7.5 sn (ışık açılış anı ±0.5 sn belirsiz), diğer üçü 8 sn; sıra `Rotator slow` ile bitip orada kalıyor. `Slow alternate` dışındaki 57 desenin renk sınıfı ölçüldü, ama hücre başına tek renk (desen penceresinin çoğunluk rengi); renk değiştiren desenlerde (Colour cycle, Tri-colour alternate...) yalnızca en sık renk saklanır.
4. Sirene bağlı 6 desenin dört gruplu (P,Q,P,Q) yerleşimi (yeni panel) ile eski panel ölçümü farklı periyot verir (ör. Double cross 1.683 s yeni panel, 0.833 s eski panel); PODS hücre sözleşmesi yeni panelden, 4 satır eski panelden.
5. CRUISE = sabit yanma; DIM = %40; TAKE DOWN, ALLEY, SPOT, FRONT/REAR CUT, PROG yalnızca bayrak (ışığa etkisi yok); AUTO SIREN yalnızca `set_siren_note` ile bağlam notu.
6. Aktif/hover görünümleri: siren dışı düğmeler grup renginde dolu + parıltı; hover %7 beyaz katman.
7. Hücre renkleri: ölçülmemiş durumlarda sol 5 kırmızı, sağ 5 mavi.
8. Traffic advisor animasyonları (süpürme süresi 0.1 s/hücre); `Traffic advisor: hazard` / `road closed` metinleri.
9. Aktif sirene tekrar basınca siren + ışık kapanır.
10. Stage değişince `Stage N: <desen>` bildirimi (yalnızca desen değişimi görüldü).
