# Blue Line Patrol

[Web sitesi](https://talkdedsec.com) · [Lisans](LICENSE) · [Güvenlik](SECURITY.md) · [English](README.md)

![Blue Line Patrol: Hoover St üzerinde devriye SUV'unun yanındaki memur](docs/img/hero.jpg)

**Godot 4.7** (Jolt Physics, Forward+) ile yapılmış üçüncü şahıs polis devriye simülasyonu. Dispatch çağrılarını al, plaka sorgula, trafik durağı yap, şüphelileri araçla ve yaya kovala, tam bir ELS ışık ve siren paneliyle araç sür. Şehir, araçlar, karakterler, sesler ve iç mekânlar betiklerle üretilen özgün low-poly varlıklardır.

Bu özel, kişisel kullanım amaçlı bir projedir. Tüm varlıklar özgündür.

## Özellikler

- Yol grafiği, trafik ışıkları, gece/gündüz döngüsü, hava ve ışıklandırma sistemiyle prosedürel şehir
- Sürüş fiziği, ELS ışık düzeni, kapılar, hasar dumanı ve takip kamerası olan devriye araçları
- Memur kontrolcüsü, animasyonlu NPC'ler, üç silah (tabanca, devriye tüfeği, pompalı), nişangâh, tepme ve efektler
- Ayrıntılı ışık desenleriyle ELS SYSTEM paneli, RADAR, ALPR, minimap, kadranlar ve sentezlenmiş sirenler
- Telsiz sesli dispatch çağrıları, MDT terminali, trafik durağı diyaloğu, ceza ve tutuklama
- PIT yetki akışı, takviye birimleri, yaya takibi, Taser ve kelepçeleme içeren kovalamalar
- Betikli demo senaryoları ve Movie Maker kayıt hattı

![ELS paneli, radar, ALPR ve kadranlarla devriye HUD'u](docs/img/hud.jpg)

## Çalıştırma

1. [Godot 4.7.2](https://godotengine.org/download) (standart sürüm) kur.
2. Klasörü proje olarak aç ya da şunu çalıştır:

```bash
godot --path .
```

İlk açılışta varlıklar içe aktarılır, bir iki dakika sürer.

## Kontroller

| Tuş | İşlev |
|---|---|
| W A S D, fare, Shift | hareket, bakış, yürüme |
| 5 | silahı çek / kılıfla (önce pencereye bir kez tıkla, fare yakalansın) |
| 1 / 2 / 3 | tabanca / devriye tüfeği / pompalı çek |
| Sol tık, sağ tık, basılı R | ateş, nişan, doldurma |
| E | araca bin, kelepçele, işle, konuş (ipucu olarak görünür) |
| W / S, A / D, Boşluk, F | gaz-fren, direksiyon, el freni, araçtan in |
| Q, X, H, L | acil ışıklar, siren, korna, farlar |
| V, G, P | radar aç/kapa, kilit, plaka okuyucu |
| Tab | MDT |
| Alt | fareyi serbest bırak (ELS paneline tıkla), Esc ile tekrar yakala |
| Y / N | çağrıyı kabul et / geç |
| Takipte: R, B, C, Z | PIT iste, takviye, katıl, vazgeç |

## Proje yapısı

| Yol | İçerik |
|---|---|
| `scripts/` | oyun kodu (dünya, araçlar, karakterler, silahlar, HUD, ELS, MDT, takip, trafik) |
| `blender/` | modelleri üreten Blender betikleri |
| `assets/` | üretilmiş modeller ve sentezlenmiş sesler |
| `scenarios/` | betikli demo senaryoları |
| `docs/` | mimari notları (`MIMARI.md`), modül API'leri (`docs/api/`) |
| `araclar/` | yardımcı betikler (kilitli Godot çalıştırıcı, kayıt) |

Üretilen modeller Blender 5.2 ile yeniden oluşturulur (`blender/*/build_all.sh` ya da tek tek betikler).

## Durum

Oynanabilir, geliştirme sürüyor. Bazı mekanikler (doldurma süresi, hasar modeli, PIT hız eşiği, bina iç mekânları ve diğerleri) tasarım varsayımıdır; her modül bunları `docs/api/` içinde "Tasarım varsayımları" başlığı altında listeler.

## Lisans

Tüm hakları saklıdır, yalnızca kişisel kullanım. [LICENSE](LICENSE) dosyasına bak.

---

[Talkdedsec](https://talkdedsec.com) tarafından yapıldı.
