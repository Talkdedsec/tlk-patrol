# Silah sistemi (`weapons`)

Sahip olunan yollar: `scripts/weapons/**`, `scenes/weapons/**`, `assets/audio/weapons/**`, `araclar/ses/silah_*`, bu dosya.

Giriş: `Weapons` autoload'u (`scripts/weapons/weapons.gd`). Başka bir şey kurmak gerekmez: `Officer` sahneye girince otomatik bağlanır (`auto_bind`), nişangâh sahnesi ilk silah çekilişinde kurulur, HUD satırı `set_weapon_line` / `clear_weapon_line` ile güncellenir.

## Dosyalar
| Yol | İçerik |
|---|---|
| `scripts/weapons/weapons.gd` | Autoload: durum makinesi, ateş/raycast, hasar, yeniden doldurma, kamera tepmesi, girdi köprüsü |
| `scripts/weapons/weapon_def.gd` | Silah verileri (sayaç, süre, hasar, nişangâh, efekt, ses); ölçülen/tahmin ayrımı satır yorumlarında |
| `scripts/weapons/adapters.gd` | Officer / Npc / HUD / kamera bağdaştırıcısı (duck-typing); gerçek API değişirse yalnızca bu dosya değişir |
| `scripts/weapons/crosshair.gd` + `scenes/weapons/crosshair.tscn` | Nişangâh (`CanvasLayer`, katman 9): 4 çubuk + elmas nokta, yayılma, kırmızı, isabet işareti |
| `scripts/weapons/weapon_fx.gd` | Namlu alevi + sıcak ışık flaşı, duman, mermi izi, kovan, vuruş tozu (hepsi kodla üretilir) |
| `scripts/weapons/weapon_audio.gd` | `assets/audio/weapons/*.wav` çalıcı (havuz, hafif perde oynaması) |
| `scripts/weapons/target_health.gd` | Hasar API'si olmayan hedefler için yedek can bileşeni (`WeaponHealth` alt düğümü) |
| `scenes/weapons/test_range.tscn` | Atış poligonu (yer tutucu kapsül hedefler 8–40 m, siper blokları, arka duvar, HUD, test memuru) |
| `scripts/weapons/test_officer.gd`, `test_dummy.gd`, `officer_stub.gd`, `hud_spy.gd` | Poligon ve test yardımcıları |
| `scenes/weapons/selftest.tscn`, `selftest_chars.tscn` | Otomatik doğrulama (bkz. Test) |
| `scripts/weapons/shot_setup.gd` | `scripts/dev/shot.gd` için ekran görüntüsü kurulumu |
| `araclar/ses/silah_sesleri.py` | Ses sentezi (numpy) |

## Genel API (`Weapons`)
**Silah kimlikleri:** `pistol` (HUD adı `Pistol`, 17/34), `rifle` (`Patrol rifle`, 29/56), `shotgun` (`Shotgun`, 6/18). Metotlar "Pistol", "Patrol rifle", "patrol_rifle", "rifle" gibi gevşek yazımı kabul eder.

**Durum:** `equipped: StringName` (çekili silah, kılıfta `&""`), `selected` (5 tuşunun çekeceği), `state` (`Weapons.State.HOLSTERED | DRAWING | READY | RELOADING | HOLSTERING`), `aiming`, `inventory`, `officer`, `time` (birikimli oyun zamanı).

**Sinyaller:**
| Sinyal | Ne zaman |
|---|---|
| `shot_fired(origin, dir, weapon)` | her atışta (mermi çıkışı; `weapon` = kimlik) |
| `target_hit(npc, damage, part)` | hedefe isabet (kurşun/saçma toplamı); `part`: `head torso arms legs` |
| `target_downed(npc, weapon, lethal)` | hedef bu atışla yere düştü (`Pursuit`/`Calls` dinler; FOOT CHASE kapatma ve "subject deceased" satırı onların işi) |
| `ammo_changed(weapon, magazine, reserve)` | şarjör/yedek değişti |
| `equipped_changed(weapon)` | çekildi / kılıfa girdi (`&""`) |
| `aim_changed(aiming)`, `state_changed(state)`, `reload_started(w)`, `reload_finished(w)`, `dry_fired(w)`, `impact(position, normal, collider)` | |

**Metotlar:**
| Metot | Açıklama |
|---|---|
| `equip(weapon, instant := false) -> bool` | Silahı çeker; HUD satırı hemen açılır, `DRAWING` süresi sonunda `READY`. `instant` çekme süresini atlar (senaryoda "başlangıçta zaten donatılı"). |
| `holster(instant := false)` | Kol iner (`HOLSTERING`); HUD satırı ve nişangâh süre bitince kapanır (tabanca 0,6 sn). |
| `toggle_draw()` | 5 tuşu: çek / kılıfla. `cycle_weapon(dir)`: fare tekerleği ve `[` `]` (kılıftayken yalnızca seçimi değiştirir). |
| `set_ammo(mag, reserve, weapon := çekili)` / `get_ammo(weapon) -> {mag, reserve}` | Senaryo kancası; HUD'u günceller. |
| `fire() -> bool` | Oyuncu tetik çekişi (ışın ekran merkezinden, nişangâh yayılımına göre koni). |
| `fire_at(target, part := "torso", hit := true, ignore_cooldown := true) -> bool` | Senaryo kancası: `Node3D`/`Npc` ya da `Vector3`'e kesin nişanlı atış (saçma deseni sabit). `hit = false` hedefin yanından geçirir. Atış aralığı varsayılan olarak yok sayılır, kayıt zamanları aynen oynar. Çarpışma gövdesi olmayan hedefte de isabet sayılır. |
| `set_aim(on)` | RMB karşılığı (nişangâh + isabetlilik). Görsel nişan duruşunu `Officer` kendi girdisinden yapar. |
| `start_reload()` / `cancel_reload()` | `hold R` karşılığı. |
| `set_movement(speed_mps, turn_deg_per_s := 0)` | Hareket/dönüş bilgisi (nişangâh ±50–60 px'e açılır). Verilmezse kameradan kestirilir. |
| `bind_officer(node)` / `unbind_officer()` | Elle bağlama (normalde otomatik). `hud` özelliği HUD düğümünü elle atamak için. |
| `add_weapon`, `remove_weapon`, `reset()`, `get_crosshair()`, `tick(dt)` | `manual_tick = true` iken zamanı test/senaryo ilerletir. |

**Ayar bayrakları:** `hit_marker_on_dead` (varsayılan `true`), `holster_hud_time` (varsayılan `0.6`), `manual_tick`, `fx_time_scale` (efekt sürelerini uzat: ekran görüntüsü), `tracers_enabled`, `casings_enabled`, `damage_enabled`, `direct_input`, `auto_bind`, `fallback_zoom`, `officer_recoil`, `reload_hold_time`.

## Kurallar (uygulanan)
- Tabanca yarı otomatik, tık başına 1 mermi, en az 0,22 sn aralık (ölçülen en kısa 0,23, ortalama 0,31); tüfek 0,18 sn, pompalı 0,9 sn. Her atışta şarjör −1, yedek sabit. Şarjör boşken tık sesi (`dry_fired`).
- Yeniden doldurma: `start_reload()`; yedekten şarjör boşluğu kadar alınır. Tabanca/tüfek bütün şarjörü tek seferde (animasyon süresi), pompalı mermiyi tek tek (0,55 sn); pompalıda atış yeniden doldurmayı keser.
- HUD: silah satırı yalnızca silah çekiliyken görünür (çekme başında açılır). Kılıfta satır, animasyon süresinden bağımsız olarak `holster_hud_time` (0,6 sn) sonra kapanır; `Officer` `pistol_holster` animasyonu 0,7 sn sürse de satır 0,6 sn'de kapanır, `HOLSTERING` durumu animasyon bitince sona erer. `holster_hud_time < 0` satırı animasyon süresine bağlar. Metin HUD'un kendisinde üretilir (`Pistol  17 / 34   LMB fire ...`).
- Nişangâh yalnızca silah hazır ve nişan alınırken görünür; atıştan sonra tabancada 0,35 sn gizlenir; sakin ±9/11/30 px (tabanca/tüfek/pompalı), atışta ≈±50 px, ≈1 sn'de ±19 px; hareket/dönüşte ±55; canlı hedef üstünde kırmızı; isabette çubuklar yerine 4 çapraz çizgi 0,2 sn sönümlü. Yere düşmüş hedefe atılan atışta da isabet işareti çıkar; `Weapons.hit_marker_on_dead = false` bunu kapatır. Ölü hedef ek hasar/tepki almaz, `target_hit` yine yayılır, `target_downed` yayılmaz.
- Işın: ekran merkezinden hedef noktası bulunur, sonra namluyla o nokta arasında mermi ışını atılır (omuz kamerasında siper kenarları doğru çalışır). Memurun kendi gövdesi dışarıda tutulur.
- Hasar (100 can): tabanca gövde 28, tüfek 100, pompalı 8×14 saçma; kafa ×2,5, kol/bacak ×0,6; mesafeyle azalır. Kafa/bacak bölgesi `hit_part()` ile yüksekten ya da hitbox adından (`Head`, `Leg`...) çıkarılır.
- Atış anı efektleri: ≈0,05 sn sıcak ışık flaşı + alev yıldızı, 1–1,5 sn beyaz-gri duman (pompalı 2,4 sn), kovan (pompalıda pompalamayla), mermi izi (pompalı hariç), vuruş tozu (kan yok).

## Officer / Npc / HUD bağlantısı
- **Officer** (`docs/api/characters.md`): sinyaller `fire_requested`, `aim_changed`, `draw_requested`, `reload_requested` bağlanır. Bağlanınca `officer.auto_visuals = false` yapılır, `set_loadout(inventory)` çağrılır; `equip` → `draw_weapon(id)`, `holster` → `holster_weapon()`, atış → `rig.fire()`, reload → `rig.reload()`, pompalı → `rig.pump()`. Süreler `CharacterRig.anim_length` ile animasyondan alınır (çekme, kılıf, reload). Mermi çıkışı `Officer.muzzle_transform()`, kamera `Officer.camera`. Silah değiştirirken önce eskisi kılıflanır.
  İsteğe bağlı üyeler (varsa kullanılır): `get_muzzle_transform()`, `get_aim_camera()`, `get_collision_rids()`, `set_camera_kick(pitch_rad, yaw_rad)` (tepmeyi kendisi uygular), `holster_requested`, `weapon_cycle_requested(dir)`.
- **Npc**: hedef sayılır (`go_down` + `flee_from` metotları ya da `npc`/`shootable` grubu ya da `apply_weapon_hit(info)` / `take_damage(damage, part, info)`). Hasar API'si yoksa `WeaponHealth` bileşeni eklenir. Öldürücü olmayan isabette `flee_from(namlu)`, can bitince `go_down(&"shot")` (ölüm düşüşü 0,6 sn) çağrılır. `info` = `{weapon, damage, part, point, dir, distance, origin}`; `apply_weapon_hit` `{downed, lethal, hp}` döndürebilir. Yere düşmüş/kelepçeli Npc nişangâhı kırmızı yapmaz.
- **HUD**: `set_weapon_line(name, mag, reserve)` / `clear_weapon_line()`; HUD düğümü `hud` grubunda ya da sahne ağacında (metodu olan ilk düğüm) bulunur, `Weapons.hud` ile elle atanabilir. HUD yeniden kurulursa satır yeniden yazılır.
- **Officer yokken** (yer tutucu oyuncu): `direct_input` ile LMB/RMB/5/R'yi kendisi okur, nişan FOV yakınlaşması (1,6x) ve kamera tepmesi kameraya uygulanır.

## Senaryo kullanımı (`scenarios/*.gd`)
```gdscript
at(0.33, func(): Weapons.equip("Pistol", true); Weapons.set_ammo(17, 34))   # kayıt başında silah zaten çekili
at(3.6,  func(): Weapons.fire_at(suspect))                                   # 17 -> 16
at(4.0,  func(): Weapons.fire_at(suspect))                                   # 15 ...
at(18.3, func(): Weapons.equip("Patrol rifle"))                               # HUD satırı hemen açılır
at(21.4, func(): Weapons.fire_at(runner, "torso"))                            # 29 -> 28, hedef düşer (rifle 100 hasar)
at(27.85, func(): Weapons.equip("Shotgun")); at(29.48, func(): Weapons.fire_at(target))
at(34.97, func(): Weapons.holster())
```
`Weapons.target_downed` sinyali `Pursuit` için FOOT CHASE'i kapatma, `Calls`/`Dispatch` için "subject deceased" satırı tetikleyicisidir (Weapons bunları yapmaz). Uyarı bipi `assets/audio/weapons/alert_beep.wav` (1,69 sn; 1,05/1,7 kHz dört vuruş) `Calls` tarafından çalınır.

## Test
```
araclar/godot.sh --headless res://scenes/weapons/selftest.tscn --quit-after 3000          # 102 kontrol: sayaç, aralık, reload, nişangâh, hasar, senaryo zaman çizelgesi
araclar/godot.sh --headless res://scenes/weapons/selftest_chars.tscn --quit-after 3000    # gerçek Officer + Npc ile 15 kontrol
araclar/godot.sh res://scenes/weapons/test_range.tscn                                      # elle deneme (WASD, fare, LMB, RMB, 5, tekerlek, R basılı tut)
araclar/godot.sh --script res://scripts/dev/shot.gd -- --scene res://scenes/weapons/test_range.tscn \
    --setup res://scripts/weapons/shot_setup.gd --mode pistol_shot|rifle_shot|shotgun_shot|shotgun_smoke|aim --frames 4 --fx 6 --out C:/tmp/w.png
python araclar/ses/silah_sesleri.py --check                                                 # sesleri yeniden üret
```
Ses dosyaları: `pistol_shot, rifle_shot, shotgun_shot, shotgun_pump, dry_click, pistol_reload, rifle_reload, shotgun_shell, draw, holster, impact, alert_beep` (mono, 44,1 kHz; yeni dosya ekleyince `araclar/godot.sh --headless --import`).

## Bilinen sınırlar
- Nişan duruşu için `Officer` yalnızca kendi RMB girdisine bakar; senaryoda görsel nişan gerekiyorsa `Officer` tarafında bir "nişanı zorla" API'si lazım (`Weapons.set_aim` yalnızca nişangâh ve isabetliliği sürer).
- Pompalı tepmesi: görev ölçüsü 70 px / 0,5 sn uygulanır; `Officer.notify_shot()` ölçülen değeri (≈23 px) kullanır, istenirse `Weapons.officer_recoil = true`.
- Atış sesi yakın/uzak ayrımı, yankı ve konumlu (3B) ses yok; AI/şüpheli atışları bu modülde yok (şüphelinin namlu ışığı senaryoda ışıkla verilir).
- Silah modelleri `Officer`/`Npc` rig'inin propları; ADS optik halkası (tüfek) ve silah satırı yazı tipi başka modüllerde.
- Hasar/can yalnızca bu modülde; Npc'nin kendi can sistemi gelirse `apply_weapon_hit` ile devralır.
- Kayıt (Movie Maker) sırasında `fx_time_scale = 1` bırak; efektler motor zamanında akar.

## Tasarım varsayımları
1. Tabanca çekme süresi 0,45 sn (animasyon varsa `pistol_draw` uzunluğu, 0,6 sn, kullanılır); tüfek/pompalı çekme 0,85 sn ölçüldü/benzetildi; kılıf: tabanca 0,6 sn ölçüldü, tüfek/pompalı 0,8 sn tahmin.
2. Yeniden doldurma: `hold R` süresi 0,4 sn (Officer'da 0,5 sn); tabanca 1,6 sn, tüfek 2,3 sn, pompalı mermi başına 0,55 sn (animasyon varsa onun uzunluğu).
3. Reload mantığı: yedek mermi adedi (34 = 2×17), yalnızca eksik kadar alınır, atılan mermi kaybolmaz; tabanca/tüfek yeniden doldurması kesilemez, pompalı atışla kesilir; boş şarjörde otomatik reload yok.
4. Atış aralığı alt sınırı: tabanca 0,22 sn, tüfek 0,18 sn (yarı otomatik), pompalı 0,9 sn; hiçbir silah otomatik değil.
5. Hasar modeli: 100 can; tabanca gövde 28 (4 isabet), tüfek 100 (tek isabet), pompalı 8×14 saçma; kafa ×2,5, kol/bacak ×0,6; menzil azalması (tabanca 25–80 m, tüfek 60–250 m, pompalı 15–50 m).
6. Kafa/gövde/bacak ayrımı yüksekliğe göre (üst %14 kafa, alt %45 bacak).
7. Öldürücü olmayan isabette Npc kaçar (`flee_from`); ilk isabet şüpheliyi durdurmaz.
8. Gerçek mermi konisi nişangâh yayılımından türetilir (tabanca ×0,6, tüfek ×0,45, pompalı ×0,5 piksel→açı); nişansız (kalçadan) atışta yayılım en az hareket değeri kadar.
9. Nişangâh sayıları: nişan açılışında tabanca ±30, tüfek ±52 (ölçüldü), pompalı ±45 px; tüfek/pompalı atış sonrası gizlenme 0,3 / 0,5 sn; yalnızca tabancanın 0,35 sn'si ölçüldü.
10. Nişangâh merkez noktası isabet işaretinde de çizilir; isabet işareti yalnızca hedef isabetinde (dünya isabetinde yok). Ölü hedefte işaretin çıkması `Weapons.hit_marker_on_dead` ile ayarlanır.
11. Pompalı tepme açısı: 70 px (görev notu) ↔ ölçülen −23 px; yatay tepme (tüm silahlarda küçük rastgele) tahmin.
12. Kamera nişan yakınlaşması 1,6x (ölçü 1,55–1,6; Officer 1,58); Officer yokken FOV ile uygulanır.
13. Silah değiştirme: fare tekerleği ve `[` `]`; 5 tuşu seçili silahı çeker/kılıflar.
14. Silah envanteri: üç silah da sahip (kişisel kullanım).
15. Namlu alevi (8 uçlu yıldız, turuncu/açık sarı), ışık enerjisi/menzili, duman parçacık sayısı ve ölçeği, kovan ölçüleri/rengi ve fırlatma hızı, mermi izi (tabanca/tüfek 0,07 sn).
16. Ses: tüm atış, pompa, tık, reload, çekme, kılıf, vuruş sesleri özgün sentez; bant ≈2,5–7,8 kHz. Uyarı bipi dört vuruş (1,05/1,7 kHz, 0,28 sn vuruş, 0,47 sn periyot, ek kısmi sesler).
17. Vuruş tozu (asfalt kahverengisi, Npc'de açık gri) ve vuruş sesi (`impact.wav`, atış başına ilk isabette -9 dB).
18. Pompalıda kovan pompalamayla (0,35 sn sonra) atılır; pompa sesi aynı anda.
19. Hedef yerdeyken (`downed`/`cuffed`) nişangâh kırmızı olmaz, hasar/tepki işlenmez (yalnızca isabet işareti `hit_marker_on_dead` ile).
20. Senaryo atışlarında pompalı saçma deseni sabit (ayçiçeği dizilimi), rastgelelik yok.
