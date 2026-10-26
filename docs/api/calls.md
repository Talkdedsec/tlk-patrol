# Calls: çağrı teklifleri, durum, EMERGENCY bandı, telsiz sesi

Sahibi: `mdt`. Autoload `Calls` (`scripts/calls/calls.gd`).
Yan dosyalar: `call_catalog.gd` (çağrı türleri), `radio_voice.gd` (konuşma kuyruğu), `speech_text.gd` (konuşma biçimi/anahtar). Üst orta istemler `scripts/traffic_stop/stop_overlay.gd` (`Overlay.of(tree)`).

## Çağrı akışı
```gdscript
Calls.offer(&"stolen_vehicle")        # tür kimliği; ya da Calls.offer(Calls.make_call(&"trespassing", {"location": "Oak Hills"}))
# Dispatch metni okur, üst ortada amber istem: "Code 3: Stolen vehicle.   Y respond   N pass   (25)" (25 sn geri sayım, üç boşluklu ayraçlar)
Calls.respond()      # Y: "1-Adam-12: show me 10-76." + "Dispatch: 10-4, 1-Adam-12 responding Code 3." -> atanır, durum Busy
Calls.pass_offer()   # N: "1-Adam-12: unable, I'm tied up." + "Dispatch: 10-22, another unit will handle the stolen vehicle."
# süre dolarsa: "Dispatch: 1-Adam-14, take the stolen vehicle. Code 3." / "1-Adam-14: 10-4, responding." (başka birim)
Calls.arrive(); Calls.complete()      # 10-97, "clearing." + durum Available + CALL_SCORE
```
Tuşlar: **Y** `call_respond`, **N** `call_pass` (eylemleri `Calls` kendisi ekler), **C** `join_chase`, **Z** `call_off` (InputSetup'ta var). Y/N yalnızca teklif varken, C/Z yalnızca "Chase nearby" istemi açıkken tüketilir.

### API
| Üye | Açıklama |
|---|---|
| `offer(call = null) -> Dictionary` | Teklif başlatır. `call`: sözlük, tür kimliği (`StringName`) ya da `null` (rastgele). Yeni teklif eskiyi `expired` yapar. |
| `make_call(type_id, opts = {}) -> Dictionary` | Katalogdan çağrı üretir. `opts`: `location`, `text`, `plate`, `code`. Elle `"position": Vector3` eklenirse varış 25 m yarıçapla algılanır ve HUD minimap'e `&"call"` işareti konur. |
| `respond()`, `pass_offer()` | Y / N. |
| `assign(call)` | Çağrıyı doğrudan oyuncuya atar (acil çağrı, senaryo). `status = busy`, HUD görev metni, `call_started`. |
| `arrive()`, `complete(outcome = &"cleared")` | 10-97; "clearing." + Available + `CALL_SCORE` (10). |
| `emergency(location = "the Southside", auto_respond = true)` | "all units, shots fired, officer needs assistance..." + uyarı bipi + HUD `set_emergency` bandı (4 sn) + diğer birimler "en route." + oyuncu `show me 10-76.` (1 sn sonra, `auto_respond`). |
| `start_emergency_band()` | Yalnızca bip + bant. |
| `chase_nearby(miles)`, `set_chase_distance(miles)`, `clear_chase_notice()` | Kırmızı `Chase nearby, 0.2 mi   C join   Z call off`. **C** `join_chase()`: `Pursuit.join_chase()` çağrılır, `chase_join_requested`. **Z** `call_off_chase()`: toast `Chase called off` + `1-Adam-12: terminate the pursuit.` + `Dispatch: 10-4, all units, pursuit terminated.` |
| `play_nearby_chase(seconds, lead_unit, reporter)` | Başka birimlerin takibinin telsiz akışı: `Joining in.`, `I've got the lead.`, yön/hız bildirimleri, `Requesting permission to PIT.` |
| `unit_report(mph, direction, prefix = "Still")`, `speed_phrase(mph)` | `Still northbound, at thirty.` biçimi; hız sözcükleri `at twenty/at thirty/slow/moderate/very fast/speeds over a hundred`. |
| `set_status(&"busy"/&"available", announce = true)` | `GameState.duty_status` + `Status: Busy` toast'ı + `show me 10-6.` / `10-4`. |
| `add_score(points)` | `GameState.score` değiştirir. |
| `radio(speaker, text)`, `radio_unit(text)`, `radio_dispatch(text)` | Günlüğe anında yazar (`Dispatch.say("<speaker>: <text>")`). |
| `play_script([[gecikme, konuşmacı, metin], ...])` | Zamanlı telsiz dizisi (senaryolarda sabit bir zaman çizelgesini oynatmak için). |
| `stamp() -> String` | Oyun saati `HH:MM` (MDT damgası). |
| Alanlar | `unit_name` (`1-Adam-12`), `status`, `offer_call`, `offer_left`, `current`, `history`, `stats` (`calls passed stops warnings citations arrests`), `ambient_enabled`, `auto_offers`, `simulate_response`, `voice`. |
| Sinyaller | `changed`, `offer_started(call)`, `offer_ended(call, result)` (`responded/passed/expired`), `call_started(call)`, `call_ended(call, outcome)`, `emergency_started(call)`, `status_changed(status)`, `chase_notice_changed(active)`, `chase_join_requested`, `chase_called_off`. |

Çağrı sözlüğü: `id, type, code (2|3), title, noun, location, text, head, line, emergency, status, plate, time` (+ isteğe bağlı `position`). `head`: `Code 2, Trespassing.` / `Code 3: Stolen vehicle.` (yazım farkı bilinçli).
Türler (`call_catalog.gd`): `trespassing`, `suspicious_person`, `noise_complaint`, `shoplifting`, `traffic_collision`, `disturbance`, `welfare_check` (Code 2); `stolen_vehicle`, `armed_robbery`, `burglary` (Code 3). Foot chase, takip ve acil çağrı kendi modüllerinden (`Pursuit`, `emergency()`) gelir.

`ambient_enabled = true`: diğer birimler arada çağrı alır (`Dispatch: <birim>, take the ... Code 2.` / `10-4, 10-76.` / `10-97.` / `clearing.`). `auto_offers = true`: 90-170 sn'de bir rastgele teklif. İkisi de varsayılan kapalı; ana oturum oyun başlatırken açar. `simulate_response = true` (varsayılan): konumsuz çağrıda 25-45 sn sonra `10-97`, 30-60 sn sonra `clearing.`; senaryo `arrive()/complete()` çağıracaksa kapatın.

## Telsiz sesi (`Calls.voice`, `radio_voice.gd`)
`Dispatch.line_added` her satırı dinlenir: **`Dispatch.say` ile günlüğe düşen her telsiz satırı sıraya girip seslendirilir** (başka modüllerin satırları dahil). Biçim `<konuşmacı>: <metin>`; `Dispatch:` dispatch sesi, oyuncunun çağrı işareti memur sesi, diğerleri birim sesi. Günlük satırı anında yazılır, ses sırayla çalar (log ile ses arası açılabilir); her konuşmanın önünde kısa bip (1,1 + 2,2 kHz) ve sonunda kısa gürültü kuyruğu vardır. Kuyruk en fazla 12 satır (eskiler düşer).

Konuşma yöntemi (sırayla, `RadioVoice.method_for(text)` hangisinin seçileceğini verir):
1. **clip**: `assets/audio/radio/manifest.json` içinde satırın anahtarı varsa tam satır klibi (264 satır: çağrı metinleri, sabit telsiz satırları, sürücü ve memur replikleri, takip/silah modüllerinin `say()` satırları).
2. **words**: satırdaki her sözcük kelime bankasındaysa (547 sözcük: tüm satırlardaki sözcükler, çağrı işaretleri, plaka harfleri `King Edward Adam`, rakamlar 0-99, isimler/modeller) sözcük sözcük birleştirilir; plaka, çağrı işareti ve `10-xx` kodları okunur biçime çevrilir (`speech_text.gd`: `1-Adam-12` -> `one Adam twelve`, `KEA-9291` -> `King, Edward, Adam, nine two nine one`).
3. **tts**: Godot `DisplayServer.tts_speak`.
4. **silent**: kelime bankasında olmayan sözcük varsa ses yok (günlük satırı yine görünür).

**TTS testi (bu makine, Windows 11):** `DisplayServer.tts_get_voices()` yalnızca OneCore sesini görüyor: `Microsoft Tolga` (`tr_TR`). İngilizce ses yok (`tts_get_voices_for_language("en")` boş), Godot SAPI'nin masaüstü sesi `Microsoft Zira (en-US)`'yı listelemiyor; başsız çalıştırmada TTS hiç yok. Sonuç: **çalışma zamanı TTS yedeği devre dışı** (yalnızca bir İngilizce ses varsa devreye girer), konuşma **önceden üretilmiş kliplerle** çalışır:
`scripts/traffic_stop/dev/dump_lines.gd` (satır listesi -> `araclar/ses/telsiz_satirlar.json`) -> `araclar/ses/telsiz_uret.py` (PowerShell `System.Speech` ile Zira, 22,05 kHz) -> numpy telsiz süzgeci (350-3000 Hz bant geçiren, yumuşak kırpma, hafif statik, sessizlik kırpma) -> 8 kHz mono WAV + `manifest.json` (~20 MB, 264 satır + 547 sözcük, ≈1200 sn). Konuşmacı farkı çalışma zamanında `pitch_scale` ile (dispatch 1,0, birim 0,90, memur 0,84, sürücü 0,94, `you` 0,86, PA 0,80); tek ses olduğundan kadın sesi alçaltılmış hâlde erkek sesi benzetir. Yeniden üretim:
```
araclar/godot.sh --headless --script res://scripts/traffic_stop/dev/dump_lines.gd
python araclar/ses/telsiz_uret.py            # tümü; --only chirp|alert|voices
```
Yeni bir telsiz cümlesi eklenince dökümü yeniden alıp betiği çalıştırın (yalnızca yeni satırlar SAPI'ye gider, ham önbellek `%TEMP%\telsiz_raw`). Kontrol: `araclar/godot.sh --script res://scripts/traffic_stop/dev/voice_test.gd` (pencere gerekir).

WAV'lar `.import` olmadan da yüklenir (`RadioVoice.load_wav` RIFF başlığını kendisi okur).

## Uyarı bipi
`Calls.start_emergency_band()` önce `res://assets/audio/weapons/alert_beep.wav` (silah oturumu), yoksa `res://assets/audio/radio/alert_beep.wav` çalar. Üretilen bip: dört vuruş, 0,28 sn, 0,5 sn ızgara, ≈1,05 / 1,7 kHz dönüşümlü + 2,65/4,2/5,9 kHz kısmi sesler, toplam 1,8 sn.

## Bilinen sınırlar
- Yalnızca tek TTS sesi (Zira) var; farklı konuşmacılar pitch ile ayrılıyor. Kelime bankasında olmayan sözcük içeren yeni satır sessiz kalır (kayıt yeniden üretilmeli).
- Takip modülünün `Dispatch.say` satırları sesi olduğu gibi alır (ayrı ses çağrısı yok): `Pursuit.say` gecikmesi (`delay`) günlük satırı gecikmesidir, ses ek olarak sıraya girer.
- Çağrı konumu (`position`) World ile bağlı değil: çağrılar konumsuz üretilir (yalnızca bölge adı), varış simüle edilir (`simulate_response`).

## Tasarım varsayımları
1. **Y sonucu**: atama, `Busy`, `show me 10-76.` + `10-4, 1-Adam-12 [responding Code 3].`, görev metni (`Respond to the ... near ...`).
2. **Varış/bitiş**: konumsuz çağrıda 10-97 25-45 sn, `clearing.` 30-60 sn sonra; tamamlanan çağrı +10 puan. Geçilen (N) ya da süresi dolan çağrıda skor değişmiyor.
3. **Acil çağrı**: bant 4,0 sn, diğer birimlerin `en route.` satırı, oyuncunun otomatik atanması ("1-Adam-12, the Southside, respond Code 3" yanıtı oyuncu adına otomatik kabul sayılır).
4. **Çağrı türleri** `disturbance`, `welfare_check`, `traffic_collision`, `armed_robbery`, `burglary` ve **tüm çağrı cümleleri** (kısa etiketler `Code 2, Trespassing.` sabit; ayrıntı cümleleri özgün). Konum adları (`the Southside`, `Oak Hills`, `Eastgate`, `Davidson Blvd`) 01/03 raporlarından.
5. **Hız sözcüğü eşikleri** (≤ ~38 mph "at twenty/thirty", 38-50 slow, 50-75 moderate, 75-100 very fast, 100+ speeds over a hundred).
6. **Ambiyans telsiz** sıklığı (25-55 sn) ve otomatik teklif sıklığı (90-170 sn); başka birimlerin çağrı atamaları MDT listesine benzer biçimde.
7. **Ses**: tek Zira sesi + pitch ile konuşmacı ayrımı; telsiz süzgeci bandı (350-3000 Hz), kuyruk gürültüsü, bip genliği
8. **Chase nearby** mesafe aralığı 0,2-0,4 mil.
