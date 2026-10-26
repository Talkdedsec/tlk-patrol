# Mdt: Mobile Data Terminal

Sahibi: `mdt`. Autoload `Mdt` (`scripts/mdt/mdt.gd`), pencere `scenes/mdt/mdt_window.tscn` (`scripts/mdt/mdt_window.gd`), ortak görünüm `scripts/mdt/ui_kit.gd` (yazı tipi Open Sans, renk paleti).

## Kullanım
```gdscript
Mdt.open()                 # Tab
Mdt.open(&"plates")        # sekme: &"dispatch" &"calls" &"plates" &"unit"
Mdt.close()                # Tab ya da Esc (InputSetup: toggle_mdt, close_menu)
Mdt.run_plate_ahead()      # PLATES düğmesi: duran araç (TrafficStop.vehicle) ya da oyuncu aracının önündeki araç
await Mdt.run_plate(vehicle)   # radyo isteği + dispatch yanıtı + MDT sonucu (≈3,5 sn); sinyal plate_result(record)
Mdt.add_traffic("Dispatch: 10-4, 6-Adam-15.", "00:35")   # RADIO TRAFFIC geçmişi (senaryo tohumu); damga "" = oyun saati
Mdt.add_plate_line("[b]KEA-9291[/b], Halvorsen Ranger SUV")  # PLATES sonuç günlüğüne satır (BBCode)
```
MDT açıkken oyun durmaz (`the car can still be driven`): ağaçta yalnızca fare görünür olur (`Adapters.cursor_push/pop`); araç/oyuncu girdisi etkilenmez. Tab/Esc `_input` içinde tüketilir (oyuncunun Esc fare kilidi geçişi çalışmaz). Diyalog paneli açıkken Tab MDT açmaz (`TrafficStop.dialog_open`); `Mdt.open()` doğrudan çağrısı her zaman çalışır.

## Pencere (1920x1080 tuvalde)
Pencere `x402 y12 1116x538` (gri çerçeve 10 px, içte lacivert). Başlık `MOBILE DATA TERMINAL  ·  COMPUTER AIDED DISPATCH`; sağda `1-ADAM-12   AVAILABLE` (yeşil) ve oyun saati; dört sekme `DISPATCH CALLS PLATES UNIT` (150x38, 152 px adım, aktif `#58BDFF`, pasif `#112948`, hover `#1E3E67`); alt yazı `Tab or Esc to close  ·  the car can still be driven`.
- **DISPATCH**: solda `NO CALL ASSIGNED` + `Patrol your area. New calls show here and come in over the radio.` (çağrı atanmışsa `CODE n: TÜR`, metin, konum, durum); sağda `RADIO TRAFFIC`: `HH:MM  <satır>` (damga gri, Dispatch açık mavi, diğer birimler gri, oyuncu yeşil), kaydırma çubuklu, yeni satırda alta iner. Liste `Dispatch.line_added`'i izler (başlangıçta mevcut `Dispatch.lines` yüklenir).
- **PLATES**: tek geniş düğme `RUN THE PLATE OF THE VEHICLE AHEAD`; altında sonuç günlüğü: `02:30  Running plate KEA-9291...` (gri), ≈3,5 sn sonra `**KEA-9291**, Halvorsen Ranger SUV` / `Owner: Darnell Foster` / `No hits.` (isabette kırmızı `HIT  registered owner has a warrant`). Düğme çalışırken pasif. Diyalogdaki `Run the plate / Run their name on the MDT` seçenekleri de bu günlüğe yazar. Araç yoksa `HH:MM  No vehicle ahead.`
- **CALLS** (özgün tasarım): bekleyen teklif satırı + `RESPOND (Y)` / `PASS (N)` düğmeleri ve son 15 çağrının tablosu (saat, kod, tür, konum, durum).
- **UNIT** (özgün tasarım): çağrı işareti, durum, araç + ELS özeti, vardiya sayaçları (`Calls.stats`), skor; sağda `UNITS ON DUTY`.

## API
| Üye | Açıklama |
|---|---|
| `open(tab = &"")`, `close()`, `toggle()`, `show_tab(tab)`, `is_open`, `tab` | |
| `run_plate_ahead()`, `run_plate(vehicle)`, `plate_busy` | Plaka sorgusu; kaydı `TrafficStop.record_for(vehicle)` verir (araçta `mdt_record` meta'sı varsa o, yoksa plakadan türetilir). |
| `add_traffic(text, stamp = "")`, `clear_traffic()`, `traffic` | Telsiz trafiği listesi. |
| `add_plate_line(bbcode)`, `clear_plate_log()` | PLATES günlüğü. |
| `ui_parent` | Pencerenin ekleneceği düğüm (varsayılan ağaç kökü; ekran görüntüsü aracında `scene`). |
| `window()` | `MdtWindow` düğümü. |
| Sinyaller | `opened`, `closed`, `tab_changed(tab)`, `plate_result(record)` |

Plaka kaydı (`scripts/traffic_stop/records.gd`): `plate, model, color, first, last, owner, dob, licence_no, licence (valid|suspended|none), registration (valid|expired), insurance, warrant, stolen, evading, hits`. KEA-9291 her zaman `Halvorsen Ranger SUV / Darnell Foster / No hits`. Diğer plakalarda isabet olasılığı ≈%27 (`warrant`, `suspended`, `stolen`, `expired`, `evading`); senaryo `vehicle.set_meta("mdt_record", Records.for_plate("ABC-1234"))` ya da elle bir sözlük ile belirler.

## Test
`scripts/dev/shot.gd --scene res://scenes/traffic_stop/test_stage.tscn --setup res://scripts/traffic_stop/dev/shot_mdt_dispatch.gd` (`shot_mdt_plates.gd`, `shot_mdt_calls.gd`, `shot_mdt_unit.gd`); iki görüntüyü yan yana kırpmak için: `python scripts/traffic_stop/dev/side_by_side.py <a.png> <b.png> <out.png> x y w h`.

## Bilinen sınırlar
- `RADIO TRAFFIC` ve oyun saati `GameState` / `Dispatch`'e bağlıdır; saat durdurulmuşsa damga hep aynı kalır (`GameState.clock_running`).
- Başka birimlerin durumu (UNIT) süsleme amaçlıdır.

## Tasarım varsayımları
1. **CALLS ve UNIT sekmeleri** (özgün içerik): tablo/kart düzeni ve metinler özgün tasarım; sütun konumları ve `RESPOND/PASS` düğmeleri tahmin.
2. **Pencere çerçevesi** ve renkler kare örneklemesi (±8 renk); 10 px gri çerçeve, köşe yarıçapları, kaydırma çubuğu genişliği (6 px) tahmin. Yazı ağırlıkları motorun Open Sans'ı (kareden ≈%2-5 daha geniş çıkıyor) ile genişlik eşlemesine göre ayarlandı: başlık 15/600, sekme 15/600, gövde 16/500, telsiz satırı 14/450, alt yazı 13/350.
3. Plaka sonucu gecikmeleri: dispatch yanıtı 2,0 sn, MDT sonucu 3,5 sn.
4. Önündeki araç algısı: 80 m, 25° koni (`Adapters.vehicle_ahead`).
5. Plaka isabet metinleri (`owner has prior arrests for evading`, `registration expired`, `vehicle reported stolen`) ALPR örneklerinden ve tahmin.
