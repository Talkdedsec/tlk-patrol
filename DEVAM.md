# Blue Line Patrol: durum ve devam rehberi

Son güncelleme: 2026-10-26. Özel repo: `Talkdedsec/tlk-patrol`. Motor: Godot 4.7.2 (`E:\Godot\`), Jolt, Forward+, 1920x1080 tuval.
Amaç: kişisel kullanım için polis devriye simülasyonu (dağıtım/satış yok). Model, ses, harita ve uzun metinler özgün üretilir; kesin olmayan mekanikler tasarım varsayımıdır ve `docs/api/<modul>.md` içinde "Tasarım varsayımları" olarak listelenir.

## Dallar
- `main`: doğrulanmış, test edilmiş durum (aşağıdaki "Tamamlanan" tablosu).
- `yarim-isler`: durdurulan yarım işler (girilebilir binalar, eşya kütüphanesi, araç ayrıntı yükseltmesi, senaryo yardımcıları). Devam etmek için `git switch yarim-isler`; doğrulanınca `main`'e birleştir.

## Oynama
- Anlık sürüm: `oyna/OYNA.bat` (git dışı; `git archive HEAD` ile yeniden üretilir, ilk açılışta içe aktarma 1-2 dk sürer).
- Doğrudan: `E:\Godot\Godot_v4.7.2-stable_win64.exe --path . --windowed --resolution 1600x900`
- Kontroller: `README.md` ve `docs/api/game.md` (5 silah çek/kılıfla, 1/2/3 tabanca/tüfek/pompalı, E araca bin, Q/X/H/L ışık-siren-korna-far, V/G/P radar-kilit-plaka okuyucu, Tab MDT, Alt fare serbest, Y/N çağrı, takipte R/B/C/Z). Önce pencereye bir kez tıkla (fare yakalanır).

## Tamamlanan (`main`)
| Modül | Durum | Belge |
|---|---|---|
| HUD, ELS SYSTEM paneli (57 desen, eski LIGHTS & SIREN paneli), RADAR/ALPR, minimap, kadranlar, sirenler | HUD durum kontrolleri geçti | `docs/api/hud.md`, `els.md`, `sirens.md` |
| Dünya: prosedürel şehir, yol grafiği, trafik ışıkları, gün/gece/hava, otoyol dekoru | `selftest` 0 hata | `docs/api/world.md` |
| Araçlar: 10+ özgün model, sürüş fiziği, ELS ışık düzeni, kamera, motor sesi | Sürüş hedefleri tutuyor (12→92 mph 7,9 sn, tepe 111,8 mph, fren 13/28 mph/sn) | `docs/api/vehicles.md` |
| Karakterler: memur/şerif/sivil modelleri, animasyonlar, `Officer`, `Npc` | `selftest_chars` 15/15 | `docs/api/characters.md` |
| Silahlar: tabanca, tüfek, pompalı, nişangâh, efektler, sesler | `selftest` 102/102 | `docs/api/weapons.md` |
| MDT, trafik durağı (21 seçenekli diyalog), çağrılar, telsiz sesi | `test_stage --auto` 71/71 | `docs/api/mdt.md`, `traffic_stop.md`, `calls.md` |
| Takip (PIT akışı), yaya takibi, Taser, kelepçe, sivil trafik | `test_pursuit` 59/59 (bazı seed'lerde doğal PIT teması düşer) | `docs/api/pursuit.md`, `traffic.md` |
| Entegrasyon: oyun döngüsü, çağrı yönetmeni, radar/ALPR, `GameHooks.quiet()` | e2e 163/163 | `docs/api/game.md` |
| Demo senaryoları (12 senaryo), kayıt hattı | `araclar/kayit.sh` ile kayıtlar | - |

## Yarım kalanlar (`yarim-isler` dalı)
1. **Girilebilir binalar** (`scripts/world/interiors/**`, `docs/api/interiors.md`): bina kabuğu, açılır kapılar, tür başına oda planı, tembel iç mekân kurulumu ve `World.building_at` API'si yazıldı. Doğrulanmadı: iç mekân selftest sonucu ve ekran görüntüleri, performans (`--fps-test`), eşya kütüphanesiyle birleşme.
2. **İç mekân eşya kütüphanesi** (`blender/props/**`, `scripts/props/**`, `assets/models/props/**`): ev, mutfak, yatak odası, banyo, likör mağazası, bar, market, çamaşırhane, ofis, depo, restoran, apartman, eczane, kuaför kategorileri için `.glb` üretildi. Eksik: `docs/api/props.md`, galeri ekran görüntüleriyle kontrol (`scenes/props/props_gallery.tscn`), eksik/çirkin propların düzeltilmesi.
3. **Araç ayrıntı yükseltmesi** (`blender/vehicles/**`, `scripts/vehicles/**`): kabin, açılır kaput/bagaj, ayrıntılı farlar, süspansiyon/direksiyon animasyonu, ek sivil türler ve hasar dumanı başladı. **Bilinen hata:** `scripts/vehicles/vehicle.gd` ≈satır 741 `_damage_smoke.amount_ratio` (`CPUParticles3D`'de yok, başlangıçta `SCRIPT ERROR`): `amount` ya da `emitting` ile değiştir. Kalan: 22 maddelik araç ayrıntı listesi (yerel notlarda).
4. **Yeni özellikler kodlanmadı:** beyaz Highway Patrol Crusader `507` ve kırmızı Calico Sedan türleri, `Vehicle 95→85→79%` hasar kademeleri, 102 mph PIT'te tek temasta ≈90° spin, kaput ≈80° açılma, kalıcı lastik izi, `Grade F+` (Score yok), Backup paneli, tam ekran harita, `Pepper spray` → `Taser`, tutuklama sonrası `E Escort` / `E Let go`, oyun saati ≈5 sn = 1 dk, tepe hız 120 mph, 5. vites ≈90 mph.
5. **Dünya ayar maddeleri:** gündüz pozu hâlâ yüksek ve kalibrasyon kancası yok, durak gecesi sodyum rengi, ışık sahnesi manzarası (5-6 katlı apartmanlar, 2 katlı mağaza cepheleri), minimap otoparkta, ağaç/kavşak düzeni, takip kenti.
6. **Kayıtları yenile:** iç mekân ve araç yükseltmesi bitince `araclar/kayit.sh <senaryo>` ile tüm senaryoları tekrar kaydet.

## Bilinen sorunlar ve sınırlar
- Oyun otomatik testler, ekran görüntüleri ve kayıtlarla doğrulandı; uzun süreli elle oynanış denenmedi. Fareli atış/sürüş hissi ve 1/2/3 tuşlarının gerçek pencerede basışı elle doğrulanmadı.
- Doğal PIT teması otomatik testte bazı seed'lerde (1, 4, 10) kararsız; takip demosu 20 sn sonra PIT'i zorluyor.
- Tuşların çoğu tasarım tercihidir (`docs/api/game.md`). Yeniden doldurma, hasar modeli, PIT hız eşiği, ceza/tutuklama dalları, CALLS/UNIT sekmeleri ve bina içleri tasarım varsayımıdır.
- Eski testlerden kalan başsız Godot süreçleri bellekte olabilir; Görev Yöneticisi'nden kapat.

## Araçlar ve komutlar
Hepsi proje kökünden. `araclar/godot.sh` çalıştırmaları sıraya koyar (aynı `.godot/` önbelleğini paylaşan çok süreç için).
```bash
araclar/godot.sh --headless --quit-after 300                                   # ana sahne açılış kontrolü
araclar/godot.sh --headless --script res://scripts/world/selftest.gd           # dünya
araclar/godot.sh --headless --scene res://scenes/vehicles/test_drive.tscn -- --type patrol_suv --measure 1
araclar/godot.sh --headless res://scenes/weapons/selftest.tscn --quit-after 3000
araclar/godot.sh --headless res://scenes/weapons/selftest_chars.tscn --quit-after 3000
araclar/godot.sh --headless --script res://scripts/hud/els_selftest.gd
araclar/godot.sh --headless res://scenes/pursuit/test_pursuit.tscn --quit-after 20000 -- --auto 1 --fallback 1 --seed 3
araclar/godot.sh --headless res://scenes/traffic_stop/test_stage.tscn --quit-after 9000 -- --auto
araclar/godot.sh --headless --fixed-fps 60 --script res://scripts/game/e2e_check.gd -- --only boot,hud,drive
araclar/godot.sh --script res://scripts/dev/shot.gd -- --scene res://scenes/main.tscn --out C:/tmp/a.png --frames 150 --no-capture
araclar/kayit.sh <senaryo>        # Movie Maker ile 1080p60 kayıt -> kayit/<ad>.mp4
araclar/yanyana.sh sol.mp4 sag.mp4 cikti.mp4
```
Blender modelleri: `E:\Blender\blender-5.2.2-windows-x64\blender.exe -b --factory-startup --python blender/<alan>/<betik>.py`, sonra `araclar/godot.sh --headless --import`.

## Yerel notlar
Yerel geliştirme notları ve ölçümler git dışı `notlar/` klasöründedir.

## Dizin ve sahiplik
Mimari, modül sınırları ve kurallar: `docs/MIMARI.md`. Modül API'leri: `docs/api/`.

## Devam etmek için önerilen sıra
1. `git switch yarim-isler`, `araclar/godot.sh --headless --quit-after 300` ile açılışı kontrol et, `vehicle.gd` `amount_ratio` hatasını gider.
2. Girilebilir binaları doğrula (selftest, ekran görüntüleri, `--fps-test`), eşya kütüphanesini bitir ve `docs/api/props.md` yaz.
3. Araç ayrıntı yükseltmesini bitir; Crusader 507, Calico Sedan, hasar kademeleri ekle.
4. Yeni özellikleri (Grade, Backup paneli, tam ekran harita, Escort/Let go, oyun saati) uygula.
5. Dünya ayar maddelerini kapat; tüm testleri çalıştır; senaryoları yeniden kaydet; `main`'e birleştir ve push et.
