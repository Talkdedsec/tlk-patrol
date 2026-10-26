# Karakterler ve oyuncu kontrolü (`characters`)

Sahip olunan yollar: `blender/characters/**`, `assets/models/characters/**`, `scripts/characters/**`, `scripts/player/**`, `scenes/characters/**`.

## Varlıklar ve üretim
Tüm modeller ve animasyonlar Blender betikleriyle üretilir (özgün low-poly):
```
E:\Blender\blender-5.2.2-windows-x64\blender.exe -b --factory-startup --python blender/characters/build_characters.py -- all
```
(`all` | `models` | `props` | `anims`). Betikler: `rig.py` (iskelet, ileri kinematik, iki kemikli IK), `meshes.py` (gövde/ekipman), `props.py`, `anims.py`, `build_characters.py`.

| Dosya (`assets/models/characters/`) | İçerik |
|---|---|
| `officer_police.glb` | Davidson City polisi: lacivert üniforma, kep, yelek ve sırtta `POLICE` plakası, kemer, kılıf, telsiz |
| `officer_sheriff.glb` | Busco County şerif memuru: haki/zeytin üniforma, koyu yeşil kep, yelek `SHERIFF` |
| `civilian.glb` | Sivil/şüpheli gövdesi; malzemeler `top, sleeve, bottom, legs, skin, hair, cap, visor`; `Hair_Short`, `Hair_Long`, `Cap` düğümleri kıyafete göre açılıp kapanır |
| `props.glb` | `Pistol`, `PatrolRifle`, `Shotgun`, `Flashlight`, `Taser`, `Handcuffs` (orijin = kavrama noktası, namlu +Y, üst +Z) |
| `animations.glb` + `animations.json` | 59 animasyon (tek `AnimationLibrary`; hepsi aynı iskelete bağlı); json: `{ad: {length, loop, group}}` |

İskelet (26 kemik, boy 1,8 m, öne bakış −Z): `Hips, Spine, Chest, Neck, Head, Shoulder_*, UpperArm_*, LowerArm_*, Hand_*, UpperLeg_*, LowerLeg_*, Foot_*` ve soket kemikleri `Socket_Hand_R/L`, `Socket_Holster_R`, `Socket_Back`, `Socket_Belt_L`, `Socket_CuffBack`. Tüm modeller aynı iskeleti paylaşır; `CharacterRig` kütüphaneyi modele bağlar.

## Sahneler
| Yol | Amaç |
|---|---|
| `res://scenes/characters/officer.tscn` | Oyuncu (`Officer`, kendini kodla kurar; `scripts/player/player.gd` bunu `extends` eder, `main.gd` `PLAYER.new()` ile çalışır) |
| `res://scenes/characters/npc.tscn` | Yaya / şüpheli / yapay zekâ polis (`Npc`) |
| `res://scenes/characters/test_characters.tscn` | Test tezgâhı (aşağıda) |

## `Officer` (`scripts/characters/officer.gd`, `class_name Officer`, `CharacterBody3D`)
Dışa açık alanlar: `model_kind` (`"police"`/`"sheriff"`), `capture_mouse`, `make_camera_current`, `auto_visuals` (true: kendi girdisine tepki verir; Weapons modülü devralınca false yapılır), `mouse_sensitivity`, `input_enabled`. Üyeler: `rig: CharacterRig`, `camera: Camera3D`, `yaw`, `pitch`.

**Sinyaller** (silah mantığı 2. dalga `Weapons` autoload'unda; bu sınıf yalnızca girdiyi iletir):
| Sinyal | Ne zaman |
|---|---|
| `fire_requested` | LMB, silah hazır/nişanda iken |
| `aim_changed(aiming: bool)` | RMB basılı + silah hazır → true; bırakınca false |
| `draw_requested` | `draw_weapon` eylemi (5 tuşu) |
| `reload_requested` | `reload` (R) `RELOAD_HOLD` sn basılı tutulunca |
| `weapon_state_changed(state)` | `unarmed drawing ready raising aiming lowering holstering reloading` |

**Metotlar:** `set_loadout(ids)` (vücutta görünen silahlar: tabanca kılıfta, uzun silah sırtta), `select_weapon(id)`, `draw_weapon(id = &"") -> bool`, `holster_weapon() -> bool`, `notify_shot()` (atış gerçekleşince çağır: tepme animasyonu + kamera tepmesi; pompalıda 0,35 sn sonra pompalama), `is_aiming()`, `weapon_state()`, `get_aim_ray() -> {origin, direction}` (ekran merkezi), `muzzle_transform() -> Transform3D`, `play_action(anim) -> float` / `release_action()` (tam vücut: `death_fall`, `kneel`, `sit_drive`, `cuffing`...). Silah kimlikleri: `pistol`, `taser` (tabanca duruşunu kullanır), `rifle`, `shotgun`.

**Senaryo / betikli kontrol** (demo senaryolarını oynatmak için; gerçek girdiyle birlikte çalışır, betik hareketi öncelik alır):
| Metot | Açıklama |
|---|---|
| `force_aim(on)` | RMB'ye bakmadan nişan duruşu + nişan kamerası; gerçek RMB ile OR'lanır. Silah çekilmiş (`ready`) olmalı |
| `force_move(direction: Vector2, run = true)` | Kameraya göre WASD benzeri girdi (x sağ, y geri; ileri = `Vector2(0, -1)`); `run=false` yürüme; `Vector2.ZERO` durdurur |
| `walk_to(pos: Vector3, run = false, arrive_radius = 0.3)` | Hedefe yürür/koşar, `arrive_radius` içine girince `arrived`; gövde hedefe döner. 0,35 m'ye kadar alçak engeller (bordür) tırmanılır, daha yüksek engeller (araç gövdesi, hidrant, korkuluk) ileri bakışla (0,9 m) yana sapılıp 0,7 sn aynı yönde duvar izlenerek aşılır; 2 sn içinde gövde 0,4 m'den az yer değiştirirse ya da süre bütçesi (mesafe/1,7 m/sn × 2 + 5 sn) aşılırsa yürüyüş iptal edilir ve `walk_blocked` sinyali gelir |
| `walk_path(points: Array, run = false, arrive_radius = 0.3)` | Ara noktalı yürüyüş (ör. aracın yanından kapıya dolanma); ara noktalar en az 0,6 m yarıçapla geçilir, son noktada `arrived` |
| `stop_scripted()` | `force_move`/`walk_to` iptal |
| `force_look(yaw, pitch)` | Kamera bakışı (radyan, pitch > 0 yukarı) |
| `hold_aim_camera(on)` | Nişan kamerasını (yakınlaşma + omuz kayması) duruş bittikten sonra da açık tutar; `false` verilince kamera çıkışı başlar (tabanca 0,22 sn, doğrusal). Örnek: kol 10,1 sn'de iner, kamera 10,78–11,0 sn'de çıkar → `force_aim(false)` + `hold_aim_camera(true)`, 0,68 sn sonra `hold_aim_camera(false)` |
| `set_recoil(weapon_id, kick_degrees, recover_seconds)` / `reset_recoil()` | Kamera tepme tablosu (`recoil_table`); varsayılan tabanca 1,56°/0,20 sn, tüfek 1,26°/0,10 sn, pompalı 1,38°/0,13 sn (≈23 px). Pompalı için ≈70 px ≈ `set_recoil(&"shotgun", 4.2, 0.5)` (65° dikey FOV, 1080 px'te 1 px ≈ 0,06°) |

**Hareket / ölçüler:** koşu `RUN_SPEED = 4,57 m/sn` (15 ft/sn; koşu döngüsü bu hıza göre üretildi); `Shift` basılı = yürüme 1,7 m/sn (silah çekiliyken 2,4 m/sn); silah çekiliyken koşu `armed_run_speed = 4,5 m/sn` (dışa açık); nişanda 1,7 m/sn (nişanda gövde kamera yönüne bakar, yan/geri yürüyüş animasyonları kullanılır).

**Kamera**: arkadan omuz kamerası; dikey FOV 65°, takip mesafesi 4,2 m (oyuncu boyu ≈350 px @1080p, ölçü 350–370 px), sağ omuz kayması 0,60 m (oyuncu ekranın solunda), bakış yüksekliği 1,65 m. RMB nişan: mesafe 4,2/1,58 = 2,66 m (boy ≈550 px, ölçü 550–600 px), omuz kayması 0,42 m. Giriş/çıkış süreleri doğrusal: tabanca 0,38 / 0,22 sn, tüfek 0,285 / 0,167 sn, pompalı 0,30 / 0,20 sn. Atış tepmesi (kamera yukarı bakar): tabanca 1,56° / 0,20 sn, tüfek 1,26° / 0,10 sn, pompalı 1,38° / 0,13 sn (ölçülen −26/−21/−23 px'in 65° FOV karşılığı).

## `CharacterRig` (`scripts/characters/character_rig.gd`) — Officer ve Npc'nin ortak animasyon katmanı
Katmanlar: **locomotion** (idle/walk/run/strafe, hıza göre zaman ölçeği) ← **üst gövde** (silah duruşu, eller yukarıda...) ← **tam vücut** (ölüm, diz çökme, araç koltuğu...).
- `setup(model_path)`, `set_motion(local_velocity, strafe)`, `set_overlay(anim)` / `clear_overlay()` (üst gövde tutuşları), `play_full(anim) -> süre` / `release_full()` + `full_finished(anim)` sinyali.
- Silah: `draw(id)`, `holster()`, `set_aiming(on)`, `fire()`, `reload()`, `pump()`, `set_flashlight(on)`, `set_loadout(ids)`, `muzzle_transform()`, `set_aim_pitch(rad)` (omurga/göğüs/baş kamera eğimine uyar, silah bakış yönünü izler). Silah modeli elde/kılıfta/sırtta `BoneAttachment3D` ile taşınır; elden çıkış/ele giriş anları: tabanca 0,27 sn / 0,52 sn, uzun silah 0,10 sn / 0,75 sn.
- `preview(anim, zaman)`: ekran görüntüsü için animasyonu dondurur.
- Statik: `anim_length(ad)`, `anim_names(grup)` (`loco`/`upper`/`full`).

## Animasyon adları
Süre sütununda **[ö]** = ölçülmüş değer, **[t]** = tahmin. Üst gövde (`upper`) animasyonları yalnızca omurga/kol/baş kemiklerini sürer; locomotion üzerine bindirilir.

| Grup | Ad | Süre (sn) | Not |
|---|---|---|---|
| loco | `idle` | 2,4 [t] | nefes, ağırlık aktarma |
| loco | `walk` | 1,0 [t] | döngü 1,7 m/sn hızına göre |
| loco | `run` | 0,62 [ö] | 4,57 m/sn (15 ft/sn); `walk_back` = `walk` geriye oynatılır |
| loco | `strafe_l/r`, `run_strafe_l/r` | 1,0 / 0,62 [t] | bacaklar yana, gövde ileri |
| upper | `pistol_ready` / `pistol_aim` | döngü 2,0 | alçak hazır / nişan (iki el) |
| upper | `pistol_raise` | **0,44** [ö] | hazır → nişan; göğüs hizası 0,17 sn, baş hizası 0,30 sn, uzatılmış poz 0,44 sn |
| upper | `pistol_lower` | 0,22 [ö] | nişan → hazır (nişan kamerası çıkışı 220 ms) |
| upper | `pistol_draw` | 0,6 [t] | eller kılıfa, çekiş, hazıra |
| upper | `pistol_holster` | 0,7 [ö/t] | kol inişi 0,15 sn [ö], silah kılıfta ≈0,6 sn sonra |
| upper | `pistol_fire`, `pistol_fire_hip` | 0,25 [t] | tepme; ateş aralığı ölçümü 0,23–0,45 sn |
| upper | `pistol_reload` | 1,7 [t] | |
| upper | `rifle_ready/aim`, `shotgun_ready/aim` | döngü 2,0 | alçak hazır / omuzda nişan |
| upper | `rifle_draw`, `shotgun_draw` | 0,85 [ö] | askıdan ele ≈600 ms + alçak hazıra ≈250 ms (pompalı tüfeğe eşit alındı [t]) |
| upper | `rifle_sling`, `shotgun_sling` | 0,85 [t] | askıya alma |
| upper | `rifle_raise` / `rifle_lower` | 0,32 / 0,167 [ö] | alçak hazır → ADS ≈320 ms; ADS çıkışı ≈167 ms |
| upper | `shotgun_raise` / `shotgun_lower` | 0,30 / 0,20 [t] | pompalı nişan süresi ölçülmedi |
| upper | `rifle_fire`, `shotgun_fire` (+ `_hip`) | 0,2 / 0,3 [t] | |
| upper | `shotgun_pump`, `rifle_reload`, `shotgun_reload` | 0,55 / 2,3 / 1,0 [t] | atış aralığı 1,35 sn ölçüldü |
| upper | `hands_up` | döngü | teslim olma (eller yukarıda) |
| upper | `hands_head`, `hands_behind`, `hands_belt` | döngü | eller başta / arkada (kelepçeli) / belde (akimbo) |
| upper | `flashlight_hold`, `flashlight_scan` | 2,0 / 3,0 [t] | el feneri tutma / tarama |
| upper | `talk_a`, `talk_b`, `listen`, `point` | 2,4 / 2,0 / 2,0 / 1,2 [t] | konuşma jestleri |
| full | `death_fall` | **0,60 + 0,15 bekleme** [ö] | vuruş 0 sn, sendeleme 0,07, dizler 0,20, öne yığılma 0,40, yüzüstü 0,60 |
| full | `taser_fall` | 0,6 [t] | sertleşip yüzüstü düşme |
| full | `prone_hold`, `cuffed_prone` | döngü | yüzüstü yatma / kelepçeli yüzüstü |
| full | `kneel`, `kneel_hold`, `kneel_cuffed` | 0,85 [t], döngü | diz çökme (eller başta), kelepçeli diz çökme |
| full | `cuffing` | 3,0 [ö] | memurun kelepçelemesi (`Cuffing...` ≈3 sn) |
| full | `patdown`, `patdown_subject` | 3,2 / 2,0 [t] | üst arama (memur / aranan) |
| full | `sit_drive`, `sit_passenger` | döngü | direksiyon / yolcu oturuşu (kaynak: kalça noktasının altındaki zemin, kalça 0,43 m) |
| full | `enter_vehicle`, `exit_vehicle` | 1,2 / 0,9 [t] | yerinde oturma/kalkma; araç tarafı karakteri koltuk noktasına taşır |

Ölçüm raporu: `araclar/godot.sh --headless res://scenes/characters/test_characters.tscn -- --mode measure` (animasyon uzunlukları ve durum makinesi süreleri). Son koşu (duvar saati, kare çözünürlüğü ±17 ms): tabanca çekme→hazır 614 ms, hazır→nişan 436 ms, nişan→hazır 219 ms, kılıf 684 ms; tüfek çekme→hazır 842 ms, hazır→nişan 319 ms, nişan→hazır 166 ms, askı 850 ms.

## `Npc` (`scripts/characters/npc.gd`, `class_name Npc`, `CharacterBody3D`)
`model_kind` (`civilian`/`police`/`sheriff`), `outfit`, `skin_index`, `height_scale`. Sivil kıyafetler `Outfits` (`outfits.gd`) tablosunda (10 adet): `purple_sweater` (mor kazak + siyah şort), `red_shirt_blue_shorts` (kırmızı gömlek + mavi şort), `maroon_runner`, `orange_driver`, `white_shirt`, `green_hoodie`, `grey_tee_cap`, `yellow_top`, `teal_jacket`, `denim_plaid`; `Outfits.SUSPECTS` şüpheli rolü için ilk dördü.
Durumlar (`state`, `state_changed`): `idle walk flee surrender kneel downed cuffed talk seated`.
Komutlar: `walk_to(pos, speed)`, `flee_from(kaynak, mesafe)`, `stop()`, `surrender()`, `kneel()`, `go_down(&"shot"|&"taser")`, `cuff()` (yerdeyse `cuffed_prone`, dizdeyse `kneel_cuffed`, ayaktaysa `hands_behind`), `talk(anim)`, `sit(driver)`, `stand_up()`, `equip(weapon_id, aim)`, `set_outfit(ad, ten)`. `follow_path(points, speed, arrive_radius)` / `run_along(points, speed = 4,57, arrive_radius)` (noktaları sırayla izler, son noktada `arrived`; hızı ≥ 3,1 m/sn ise durum `flee`), `fire(weapon_id = &"", target = null) -> bool` (silahı çeker; namlu parlaması + duman + izli mermi (`WeaponFx`), `assets/audio/weapons/<shot_sound>.wav` sesi 3B konumlu, tepme animasyonu; hasar uygulamaz; `shot_fired(weapon)` sinyali; `Weapons.fx_time_scale` varsa uyar). `arrived` sinyali hedefe varınca. `walk_to(pos, speed, arrive_radius)`; `StepUp` (`scripts/characters/step_up.gd`) yardımcısı hem `Officer` hem `Npc` için bordür tırmanma (35 cm) ve engel kaçınma yapar; 2 sn içinde 0,4 m'den az yer değişimi olursa `walk_blocked`. `flee_from(kaynak, mesafe)` kaçış yönünü 9 yönlü ışın taramasıyla (0,5 m yükseklik: bordürü değil hidrant/korkuluk/araç gövdesini görür) seçer: kaçış yönüne yakın ve önü açık yön kazanır, engel/korkuluk varsa onun boyunca koşar. Hareket: harita varsa `NavigationAgent3D` yolu, yoksa düz çizgi. Hızlar: yürüme 1,4 m/sn [t], kaçış 4,57 m/sn.

## Test
- `scenes/characters/test_characters.tscn`: varsayılan: kontrol edilen `Officer` + her durumda bir yaya (WASD, Shift, fare, 5 çek/kılıfla, RMB nişan, LMB ateş, R basılı tut reload, 1/2/3 silah seç, F el feneri).
- `--mode sheet --anims a,b@0.3,c [--model police|sheriff|civilian] [--cam 0|90|150 --rot -90 --weapon pistol --dist 6]` ile `scripts/dev/shot.gd` üzerinden dondurulmuş poz kontak sayfası.
- `scripts/characters/shot_setup.gd` (`--setup`): `--stage unarmed|ready|aim|fire|aimwalk|run --weapon pistol|rifle|shotgun`.
- `scenes/characters/preview_models.tscn`: üç modeli yan yana gösterir.

## Doğrulananlar
Kontak sayfası/ekran görüntüleriyle: yürüme/koşu döngüleri, üç silah duruşu ve nişan geçişleri, ölüm düşüşü, teslim/diz/kelepçe duruşları, oturuş, kamera mesafesi (takip boyu ≈350 px, nişan ≈550 px). Süre ölçümü yukarıda. `araclar/godot.sh --headless --quit-after 120` çıktısında karakter dosyalarından hata yok.

## Bilinen sınırlar
- Silah atışı/hasar/mermi mantığı yok (Weapons, 2. dalga). Namlu parlaması, duman, kovan, nişangâh bu modülün dışında.
- Çarpışma/iskelet fiziği yok; ölüm düşüşü animasyondur (ragdoll/sekme yok). Kafa/yüz ayrıntısı minimal (göz, burun).
- Araca binme animasyonları yerinde oynar; kapı/koltuk konumlandırması `Vehicles` tarafında yapılmalı.
- Yüz ifadesi, parmak kıvrımı, kıyafet kıvrımı yok; kelepçe modeli (`Handcuffs` prop) animasyona bağlanmadı.
- `Officer` yan yürüyüşte gövdeyi kamera yönüne çevirir; ayak kayması koşu hızına göre zaman ölçeğiyle sınırlanır, IK ile düzeltilmez.

## Tasarım varsayımları
1. Yürüme hızı 1,7 m/sn ve yürüme döngüsü 1,0 sn.
2. Hazır silahla 2,4 m/sn ve nişanda 1,7 m/sn hareket hızı; `Shift` = yürüme tuşu.
3. Pompalı nişan giriş/çıkış 0,30 / 0,20 sn (kamera ve animasyon), pompalı çekme/askı 0,85 sn, tüfek/pompalı askıya alma 0,85 sn.
4. Tabanca çekme süresi 0,6 sn; kılıf toplamı 0,7 sn (kol 0,15 sn ve ≈0,6 sn ölçüldü, arası tahmin).
5. Tüm atış tepme animasyonları (0,25 / 0,2 / 0,3 sn), pompalama 0,55 sn, reload süreleri 1,7 / 2,3 / 1,0 sn.
6. `hold R` reload tutma süresi 0,5 sn.
7. Taser düşüşü 0,6 sn, diz çökme 0,85 sn, üst arama 3,2 sn, araca binme 1,2 sn / inme 0,9 sn, tüm konuşma jestleri ve fener tarama süreleri.
8. Teslim olma (eller yukarıda) duruşu, kelepçeli duruş (eller arkada), diz çökme duruşu: olağan polis duruşlarına göre kuruldu.
9. Takip kamerası omuz kayması 0,60 m ve nişan omuz kayması 0,42 m (ekrandaki piksel konumundan kestirildi), dikey FOV 65°.
10. Sivil boy/ten çeşitliliği ve 10 kıyafet tablosu (renk seçimleri kendi tasarımımızdır).
11. Yaya yürüme hızı 1,4 m/sn, şüpheli kaçış hızı 4,57 m/sn (FOOT CHASE ölçümü: koşucu ≈15 ft/sn, ilk 0,2 sn'de ≈30 ft/sn; ivmelenme modellenmedi).
12. Atış tepmesi açısı piksel ölçümünden FOV 65° varsayımıyla derece cinsine çevrildi.
