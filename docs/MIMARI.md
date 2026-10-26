# Mimari ve iş bölümü

Oyun: `Blue Line Patrol`, kişisel kullanım için üçüncü şahıs polis devriye simülasyonu. Motor: Godot 4.7.2, Jolt Physics, Forward+. Tuval 1920x1080, birim: 1 Godot birimi = 1 metre, hız mph olarak gösterilir.

## İlkeler
1. **Tutarlı davranış ve düzen:** HUD yerleşimi, panel düğme adları, banner metinleri, PIT durum makinesi, FOOT CHASE yuvarlama kuralı, animasyon süreleri ve siren frekansları modül belgelerinde (`docs/api/`) sabittir. Belirsiz kalan şey için makul bir varsayım yap, kodda `# TODO(tahmin): ...` yaz ve `docs/api/<modul>.md` içindeki "Tasarım varsayımları" listesine ekle.
2. **Varlıklar özgün üretilir.** Model, doku, ses ve harita düzeni kendi geometrin ve sentezinle (low-poly, düz gölgeli) yapılır. Uzun diyalog ve telsiz metinleri kendi yazımındır; kısa arayüz etiketleri (düğme adları, banner metinleri, standart telsiz kodları) sabit kalır.
3. **Doğrulanabilirlik:** her özellik bir selftest, ekran görüntüsü ya da headless çalıştırma ile doğrulanır; doğrulamadan bitti deme.

## Dizin sahipliği (her dosyanın tek sahibi var)
| Modül | Sahip olduğu yollar |
|---|---|
| `ui` (HUD, ELS, siren sesleri) | `scripts/hud/**`, `scripts/els/**`, `scripts/audio/**`, `scenes/ui/**`, `assets/audio/sirens/**`, `araclar/ui_*` |
| `vehicles` (araçlar) | `blender/vehicles/**`, `assets/models/vehicles/**`, `assets/audio/engine/**`, `scripts/vehicles/**`, `scenes/vehicles/**` |
| `world` (dünya, ışık) | `blender/world/**`, `assets/models/world/**`, `scripts/world/**`, `scenes/world/**` |
| `characters` (karakterler, oyuncu) | `blender/characters/**`, `assets/models/characters/**`, `scripts/characters/**`, `scripts/player/**`, `scenes/characters/**` |
| `integration` | `project.godot`, `scripts/autoload/**`, `scripts/main.gd`, `scenes/main.tscn`, `scripts/dev/**`, `docs/MIMARI.md`, `DEVAM.md`, `araclar/` (ortak) |
| `props` (iç mekân eşyaları) | `blender/props/**`, `assets/models/props/**`, `scripts/props/**`, `scenes/props/**`, `docs/api/props.md` |
| `world` (genişletildi: girilebilir binalar) | ek olarak `scripts/world/interiors/**`, `scenes/world/interiors/**`, `docs/api/interiors.md` |
| `weapons` (silah sistemi) | `scripts/weapons/**`, `scenes/weapons/**`, `assets/audio/weapons/**`, `araclar/ses/silah_*`, `docs/api/weapons.md` |
| `mdt` (MDT, trafik durağı, çağrılar, telsiz) | `scripts/mdt/**`, `scripts/traffic_stop/**`, `scripts/calls/**`, `scenes/mdt/**`, `scenes/traffic_stop/**`, `assets/audio/radio/**`, `araclar/ses/telsiz_*`, `docs/api/{mdt,traffic_stop,calls}.md` |
| `pursuit` (takip, yaya takibi, sivil trafik) | `scripts/pursuit/**`, `scripts/traffic/**`, `scenes/pursuit/**`, `docs/api/{pursuit,traffic}.md` |

Kendi yollarının dışına yazma. Başka modülde değişiklik gerekiyorsa kendi tarafında bir adaptör yaz ya da raporunda yaz.

## Modül girişleri (autoload iskeletleri kayıtlı, sahipler doldurur)
`World`, `Vehicles`, `Els`, `Sirens` (1. dalga); `Weapons`, `Pursuit`, `Traffic`, `TrafficStop`, `Mdt`, `Calls` (2. dalga). `GameState`, `Dispatch`, `InputSetup` hazır. `project.godot` değişmez: yeni autoload gerekirse ana oturuma söyle (yalnızca kendi modülündeki düğümleri ve sahneleri kendin kur).

Her sahip bitirdiğinde `docs/api/<modul>.md` yazar: genel API (sinyal, metot, sahne yolu), kullanım örneği, bilinen sınırlar, Tasarım varsayımları listesi. Diğer modüller yalnızca bu API'yi kullanır.

## Sözleşmeler (kaba; sahip ayrıntıyı belirler ve `docs/api` içinde belgeler)
- **Els** (autoload): `stage` (0..3), `siren_tone`, `pattern`, `lights_on`, `changed` sinyali, `cell_colors(t: float) -> PackedColorArray` (ışık hücrelerinin o andaki renkleri). `Sirens`: `play(tone)`, `stop()`, `set_volume_db()`; sesler `assets/audio/sirens/` altında.
- **Vehicles**: `Vehicle` taban sınıfı (`VehicleBody3D` tabanlı): `type_id`, `plate`, `set_throttle/steer/brake`, `speed_mph()`, `set_headlights(on)`, `set_els_source(Callable)` (ışık hücre renklerini okur), kapı aç/kapat, sürücü/yolcu koltuğu işaretleri. `Vehicles.spawn(type_id, transform) -> Vehicle`.
- **World**: `World.build(root: Node3D)`, `World.spawn_point(name: StringName) -> Transform3D`, `World.set_time(hours: float)`, `World.set_weather(name: String)`, yol grafiği (`World.road_graph`) ve kavşak/trafik ışığı durumu.
- **Characters**: `Officer` (oyuncu: üçüncü şahıs hareket, omuz kamerası, nişan kamerası), `Npc` (kıyafet çeşitleri, durum makinesi kancaları: idle/walk/flee/surrender/downed/cuffed), animasyon adları `docs/api/characters.md` içinde.
- **Weapons**: `equipped`, `fire/aim/reload` mantığı, sinyaller `shot_fired(origin, dir, weapon)`, `target_hit(npc, damage, part)`, `ammo_changed`; HUD silah satırını HUD API'siyle günceller; nişangâh çizimi silah modülünün sahnesindedir.
- **Calls / TrafficStop / Mdt**: `Calls.offer(call)`, `Calls.respond()` (Y), sinyaller `call_started/ended`; `TrafficStop.begin(vehicle)`, `TrafficStop.begin_booking(npc, charges: Array)`; `Mdt.open()/close()`; telsiz: `Dispatch.say(text)` (günlük) + konuşma sesi `Calls`'tadır.
- **Pursuit / Traffic**: `Pursuit.start(target_vehicle)`, `Pursuit.state`, sinyaller `state_changed`, `suspect_bailed(npc)`, `suspect_cuffed(npc)` (bunu `TrafficStop.begin_booking` dinler); `Traffic.spawn_ambient(count)`, trafik yol grafiğini `World.road_graph` üzerinden kullanır.
- **HUD** (`scripts/hud/hud.gd`, sahibi `ui`): mevcut genel API korunur (`set_emergency`, `set_foot_chase`, `set_mission`, `set_weapon_line`, `set_street`), genişletilir.

## Kurallar
- Godot'u doğrudan çalıştırma; birden çok oturum aynı `.godot/` önbelleğini paylaşır. Hep `araclar/godot.sh <argümanlar>` kullan (çalıştırmaları sıraya koyan kilitli sarmalayıcı; `--path .` kendisi ekler). Hata denetimi: `araclar/godot.sh --headless --quit-after 120` çıktısında `SCRIPT ERROR`/`Parse Error` olmamalı (çıkıştaki "BUG: Unreferenced static string" ve "RID allocations leaked" satırları motor gürültüsüdür, yok say). Ekran görüntüsü: `araclar/godot.sh --script res://scripts/dev/shot.gd -- --scene ... --out ...` (başlığındaki kullanım), GPU penceresi gerekir (`--headless` verme).
- Blender: `E:\Blender\blender-5.2.2-windows-x64\blender.exe -b --factory-startup --python <betik>`; modeller Python betikleriyle üretilir, `.glb` olarak `assets/models/<alan>/` altına yazılır. Betikler `blender/<alan>/` altında kalır (tekrar üretilebilir).
- Ses: Python/numpy ile sentezle (betikler `araclar/ses/` ya da kendi alanında), WAV olarak `assets/audio/<alan>/`.
- Kod: GDScript tipli, girinti tab, tanımlayıcı ve yorumlar İngilizce, her dosyada kısa üst yorum. `class_name` yalnızca sahibi kullanır.

## Bitti tanımı (tüm oyun)
1. Her modülün selftest'i geçiyor ve `docs/api/` belgeleri güncel.
2. `scenarios/` altındaki demo senaryoları oyunda baştan sona çalışıyor.
3. Oynanış kayıtları (Godot Movie Maker) `araclar/kayit.sh` ile alınabiliyor.

## Bağımlılıklar ve çalışma sırası
1. dalga (arayüz, araçlar, dünya, karakterler) ile 2. dalga (silah, MDT/durak/çağrılar, takip) aynı anda çalışır. 2. dalga oturumları `docs/api/<modul>.md` henüz yoksa MIMARI.md sözleşmelerine göre kendi `adapters.gd` katmanını ve yer tutucu test sahnesini kullanır; işin ortasında ve sonunda `docs/api/` klasörünü tekrar kontrol edip gerçek API'ye bağlanır.
