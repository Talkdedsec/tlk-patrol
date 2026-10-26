# Sivil trafik (`Traffic`) ve yol sürücüsü

Sahibi: `pursuit`. Autoload: `Traffic` (`scripts/traffic/traffic.gd`). Yol grafiği `World.road_graph` (`world.md`), araçlar `Vehicles.spawn_traffic` (`vehicles.md`). Şüpheli sürücü aynı sürücü altyapısını kullanır.

## Dosyalar
| Yol | İçerik |
|---|---|
| `scripts/traffic/traffic.gd` | Autoload: doğurma/silme halkası, yoğunluk, bölgeler, `hold/release`, `pull_over`, `adopt` |
| `scripts/traffic/lane_driver.gd` | Şerit izleyen sürücü (taban sınıf): rota, hız planı (viraj, kavşak, öndeki araç), direksiyon, sıkışma kurtarma |
| `scripts/traffic/traffic_car.gd` | Sivil sürücü: limit, ışık/STOP uyumu, siren için sağa çekilme, bölge sınırı |
| `scripts/traffic/route.gd` | Kenar zinciri → şerit çokgeni (kavşaklarda Bezier köşe), yakın viraj/kavşak sorguları |
| `scripts/traffic/registry.gd` | Sürülen araç listesi: öndeki araç, şerit boş mu, kavşak doluluğu/rezervasyonu, yan trafik tehdidi |
| `scripts/traffic/signals.gd` | Yedek ışık döngüsü (yalnızca `World` ışık durumu yoksa) |

## Genel API (`Traffic`)
| Üye | Açıklama |
|---|---|
| `spawn_ambient(count) -> int` | Ağa şimdi `count` sivil araç koyar (en çok `max_cars` = 40) ve o sayıyı korur. Dönen: doğurulan sayı |
| `set_density(d)`, `density()` | 0..1 → `max_cars` ile çarpılan hedef sayı. 0 = sivil trafik yok (varsayılan) |
| `clear()` | Doğurulmuş sivil araçları siler, hedefi 0 yapar. **Devralınan araçlara dokunmaz**: `hold_vehicle` / `pull_over` edilmiş, `stop_hold` ya da `call_id` meta'lı, sürücüsü kapalı araçlar ve `adopt` / Pursuit şüphelisi (`owned = false`) kalır |
| `recycle_far_cars(max_moves := 1, min_distance := -1.0) -> int` | Uzaktaki (varsayılan `despawn_distance`, 340 m) ve görüş dışındaki sivil araçları silmek yerine oyuncunun çevresindeki (90–240 m) boş şerit noktalarına taşır (yeni model/fizik kurma maliyeti yok); taşınan sayıyı döner. Korumalı araçlara dokunmaz |
| `despawn_mode` | `&"free"` (varsayılan: uzaktaki araç silinir, ihtiyaç olunca yenisi kurulur) ya da `&"recycle"` (her 0,5 sn'de bir uzak araç `recycle_far_cars(1)` ile taşınır). `recycled` taşıma sayacı |
| `is_protected(vehicle) -> bool` | Silinmez/taşınmaz araç mı (hold, pull_over, `stop_hold`/`call_id` meta, kapalı sürücü) |
| `adopt(vehicle, owned := false)` | Var olan aracı trafik sürücüsüne verir (kayıp şüpheli, senaryo aracı); `owned` true ise uzakta silinebilir |
| `release(vehicle)` | Sürücüyü bırakır (Pursuit şüpheliyi bununla alır) |
| `is_managed(vehicle)` | Trafik sürücüsü var mı |
| `hold_vehicle(v)` / `release_vehicle(v)` | Trafik durağı: sürücü aracı bırakır (`stop_hold` meta de okunur) / geri alır; held araç `clear()`, silme ve taşımadan korunur, `release_vehicle` korumayı kaldırır. `TrafficStop` adaptörü çağırır |
| `pull_over(v)` | Sağa yanaşıp durur (`Pursuit.alpr_hit(..., flees = false)` kullanır); araç silme/taşımadan korunur |
| `set_zone(pos, radius, mode)`, `clear_zones()` | `&"slow"` (≈10 mph) ya da `&"closed"` (bölgeden önce durur) |
| `limit_at(pos) -> int` | Konumdaki hız limiti (`World.street_at`) |
| `focus_node`, `siren_source` | Doğurma halkasının merkezi (varsayılan: oyuncu aracı → memur → kamera), sirenine yol verilen araç (Pursuit ayarlar) |
| `max_cars`, `spawn_min` (90 m), `spawn_max` (240 m), `despawn_distance` (340 m), `enabled`, `cars` | Ayarlar / durum |
| sinyaller `car_spawned(vehicle)`, `car_despawned(vehicle)` | |

Kullanım:
```gdscript
Traffic.spawn_ambient(18)           # Davidson City'ye 18 sivil araç
Traffic.set_density(0.5)            # sonra yarım yoğunluk
Traffic.set_zone(flare_pos, 12.0, &"slow")
```

## Davranış
- Her araç sağ şeritte (`lane = lanes - 1`, `World.lane_transform` ile aynı ofset) rota izler; kavşakta rastgele dönüş (düz 3, dönüş 1,4–1,6, U dönüşü yok); köşelerde Bezier yayı (yarıçap yola göre 7/9/14/70 m).
- **Hız:** sınırın %90–102'si; viraj için yanal ivme 5 m/s² (şüpheli 7,5); frenleme planı 6,5 m/s²; öndeki araçla 1,0–1,5 sn aralık.
- **Işık:** `World.traffic_light_state_for_heading`; kırmızıda durma çizgisinde (kavşak merkezinden 7,5 m önce) bekler, sarıda rahat duramıyorsa geçer.
- **STOP:** `all_way` her yönden; `minor_stop` yalnızca yan yoldan. 1,2 sn bekler, kavşak kutusu (5,5 m) boş ve rezerve değilse geçer (9 sn sonra zorla).
- **Siren:** `siren_source` ışıkları açıkken ≤70 m arkadaysa sağa 2,4 m kayar ve ≤5 m/s'ye yavaşlar.
- **Sıkışma:** hedef hız >3 m/s iken 3,5 sn kıpırdamıyorsa 1,6 sn geri gider (iki kez), sonra şeride ışınlanır (`recoveries`, `stuck_time` sayaçları).

## Test
`araclar/godot.sh --headless res://scenes/pursuit/test_pursuit.tscn --quit-after 20000 -- --soak 1 --nobot 1 --speed 6 --soak-seconds 150 --seed N [--traffic 12]` şüpheli sürücüyü (aynı `LaneDriver`) gerçek şehirde 150 sn sürer ve `[SOAK] ...` satırı yazar: kat edilen yol, tepe hız, kurtarma sayısı, engellenme süresi, kurtarma konumları. Üç seed'de kurtarma 0/1/1, engellenme ≤4 sn. `--braketest 1` gerçek aracın frenleme ölçümüdür (ranger: pedal 1,0 ile 17 m/s'den 1,5 sn'de durur). `--traffic N` sahneye N sivil araç koyar. Sivil trafiğin kendi uzun süreli ölçümü yapılmadı (ambient araçlar yalnızca `adopt/spawn` yollarıyla elle denendi).

## Bilinen sınırlar
- Şerit değiştirme/ geçme yalnızca şüpheli sürücüde var; sivil araçlar öndeki araca kadar yaklaşıp bekler.
- Yaya geçidi, park etmiş araç, otopark yolları (`lot`) ve hizmet araçları yok; araçlar birbirini yalnızca `Registry` konumundan görür (çarpışma yapay zekâsı fizik motoruna bırakıldı).
- Karşı yönden gelen ışık bekleme kuyruğunda kavşak kutusu doluluğu basit yarıçap testidir; yoğun kavşakta kilitlenme olursa 9 sn sonra zorla geçiş çözer.
- Gerçek `VehicleBody3D`'de bordür/direkle sürtünmeler olabilir; sıkışma kurtarma bunu giderir ama görünür.

## Tasarım varsayımları (kodda `TODO(tahmin)` ya da sabit)
1. Doğurma halkası 90–240 m (kamera görüş alanında doğurmaz), silme 340 m, `max_cars` 40, doğurma aralığı 0,5 sn.
2. Sivil hız çarpanı 0,9–1,02; takip aralığı 1,0–1,5 sn; durma çizgisi 7,5 m; STOP bekleme 1,2 sn.
3. Yedek ışık döngüsü 72 sn (kuzey-güney 30 sn yeşil, 3 sn sarı; doğu-batı 30 sn yeşil, 3 sn sarı; 3 sn hepsi kırmızı), düğüme göre faz kayması. Gerçekte `World.signals` kullanılır.
4. Köşe yarıçapı ve viraj ivmesi sabitleri; sağa çekilme 2,4 m / 5 m/s; siren menzili 70 m.
5. Bölgeler: `slow` ≈10 mph, `closed` bölgeye 4 m kala durur (`TrafficStop` kullanımına göre değişebilir).
