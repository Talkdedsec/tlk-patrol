# Sirens: siren sesleri

Sahibi: `ui`.
Dosyalar: `scripts/audio/sirens.gd` (autoload `Sirens`), üretici `araclar/ses/sirenler.py`, çıktılar `assets/audio/sirens/*.wav`.

## Sesler (numpy ile sentezlenir)
`python araclar/ses/sirenler.py [--check]` bütün WAV'ları yeniden üretir (`--check` baskın frekans aralığını yazar). 44.1 kHz, mono, 16 bit; döngü dosyaları `smpl` döngü noktası içerir ve fazı tam devire ölçeklenmiştir (kesintisiz). `*.wav.import` dosyaları PCM (sıkıştırmasız) ve döngü ayarıyla tutulur.

| Dosya | Ölçülen | Üretilen |
|---|---|---|
| `wail` | 900 → 1630 Hz, yükseliş 2.35 s | 4.15 s döngü, 904–1637 Hz |
| `yelp` | 750–1570 Hz, periyot 0.309 s | 1.85 s (6 periyot), 754–1529 Hz |
| `prty` | 800–1570 Hz, 0.0848 s | 1.27 s (15 periyot) |
| `hilo` | A 1351 Hz, B ~602/1803 Hz, her biri 0.5 s | 1.0 s |
| `hyper_yelp` | 1010–1570 Hz, 0.080 s | 1.2 s |
| `yelp2` | 720–1770 Hz, 0.239 s | 1.67 s |
| `pierce` | 1351 + 2272 Hz, AM 13.4 Hz | 5.0 s (67 AM devri) |
| `hyper_hilo` | A 1351 / B 1809 Hz (+2272), AM 20.2 Hz, 0.5 s | 5.0 s (101 AM devri) |
| `mech_wail` | 560 → 1670 plato → 1060 Hz | 4.3 s |
| `rotor` | 215 → 730 (3.4 s) → 540 Hz | 7.4 s |
| `man`, `ah`, `rumbler` | ölçülmedi (rumbler katmanı 190–690 Hz, 0.309 s ölçüldü) | döngü |
| `blip` (tek atış 0.3 s), `click` (2.7 kHz, 50 ms: düğme tıkı, ölçüldü) | | |

## Sirens (autoload)
- `play(tone: StringName)`: `&"wail" &"yelp" &"prty" &"hilo" &"hyper_yelp" &"yelp2" &"pierce" &"hyper_hilo" &"mech_wail" &"rotor"`. Ton değişimi 0.12 sn çapraz geçişlidir; aynı tonu tekrar çağırmak bir şey yapmaz.
- `stop()` (0.12 sn söner), `set_volume_db(db)`, `is_playing()`, `tone`.
- Katmanlar: `set_rumbler(on)` (alçak testere süpürmesi), `set_horn(on)` (A/H, basılı tut), `set_manual(held)` (MAN: perde basılıyken yükselir 1.4 sn, bırakınca 2.2 sn'de düşer), `blip()`, `click()`.
- `Els` bunları kendisi çağırır (`Els.set_siren`, `Els.press`); başka modüller doğrudan `Sirens.play(&"wail")` da kullanabilir.

```gdscript
Sirens.play(&"hilo")
Sirens.set_volume_db(-6.0)
Sirens.stop()
```

## Bilinen sınırlar
- Kullanılmayan tonların (MAN, A/H, rumbler gövdesi, blip) dalga biçimi standart elektronik siren yaklaşımıdır.
- Dopler, mesafe ve iç/dış mekân filtresi yok: araç oturumu `AudioStreamPlayer3D` ile sarmak isterse WAV'ları doğrudan `assets/audio/sirens/` altından kullanabilir.

## Tasarım varsayımları
1. Wail düşüş süresi (1.8 s, toplam periyot 4.15 s): tek döngü ve kesilmiş kuyruk varsayımdır.
2. Rotor düşüşü (4.0 s, yavaş üstel) ve Mech wail düşüş tabanı (2.4 s, 560 Hz'e).
3. Dalga biçimi: tek harmonikli kare dalga ağırlıkları (1/n), ~4.2 kHz'de bant sınırlama; rotor için testere + çıngırak genlik modülasyonu.
4. Hi-lo B tonu: 601 Hz zayıf temel + baskın 3. ve 5. harmonik (1803/3009 Hz); algılanan perde `[BELİRSİZ]` kaldı.
5. Hyper hi-lo B tonuna eklenen ~301 Hz bileşeni.
6. MAN: 900 Hz sabit ton, perde `pitch_scale` ile 0.78→1.7 aralığında değişir; A/H: 420 + 535 Hz çift kornası; rumbler: ölçülen katman + 55 Hz alt ton; blip: 650→1500 Hz 0.3 s atlama; seviyeler (tepe -6 dBFS) kendi seçimim.
7. Panel metni ile ses geçişi arasındaki 0.1-0.3 sn gecikme uygulanmadı (ses anında başlar, 0.12 sn çapraz geçiş).
