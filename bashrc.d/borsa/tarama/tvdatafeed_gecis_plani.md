# tvDatafeed Tam Gecis Plani

## 1. Amac

Bu belge, tum veri katmaninin (hem OHLCV gecmis mum hem canli anlik fiyat) tamamen tvDatafeed uzerine tasinmasini tanimlar. Araci kurum WSS (Ziraat SignalR) ve REST polling ile fiyat cekme mekanizmasi kaldirilacak, yerine TradingView WebSocket protokolu uzerinden tek merkezli veri akisi kurulacaktir.

Temel karar: Kurum oturumuna bagimli veri cekim tamamen sona erecek. Kurumlarla iletisim yalnizca emir gonderme, bakiye/portfoy sorgulama ve halka arz islemleri icin kullanilacak.

## 2. Mevcut Durum

### 2.1 Mevcut Uc Katmanli Veri Mimarisi

Mevcut sistemde veri uc ayri kaynaktan, uc farkli yontemle cekilmektedir:

```
KATMAN 1 — GECMIS OHLCV (tvDatafeed, kurum bagimsiz)
  _tvdatafeed_cagir.py -> TradingView WS -> 5000 bar gecmis mum
  ohlcv.sh: mum_al() -> Onbellek -> Supabase -> tvDatafeed -> Yahoo Finance

KATMAN 2 — CANLI TICK (Kurum WSS / REST, kurum bagimli)
  _wss_daemon.py -> Ziraat SignalR WSS -> tick dosyalari
  fiyat_kaynagi.sh -> adaptor_hisse_bilgi_al -> Kurum REST -> tick dosyalari
  _mum_birlestirici.py -> tick dosyalarini OHLCV'ye donustur -> Supabase

KATMAN 3 — GUNLUK TAMIR (tvDatafeed, kurum bagimsiz)
  _tvdatafeed_toplu.py --tamir -> WSS mumlarini dogrula -> Supabase guncelle
```

### 2.2 Kurum Bagimli Dosyalar ve Kodlar

Asagidaki dosya ve kod bloklari kurum oturumu uzerinden veri cekmektedir:

| Dosya | Bolum/Satirlar | Islem | Satir Sayisi |
|-------|----------------|-------|--------------|
| `_wss_daemon.py` | Tumunu | Ziraat SignalR WSS canli tick | 652 |
| `_mum_birlestirici.py` | Tumunu | WSS tick -> OHLCV donusumu | 427 |
| `ziraat.sh` | Bolum 5 (satir ~2069-2487) | adaptor_wss_* fonksiyonlari | ~418 |
| `ziraat.ayarlar.sh` | Bolum 6 (satir ~186-213) | WSS sabitleri | ~27 |
| `fiyat_kaynagi.sh` | Tumunu (589 satir) | Kurum REST fiyat cekim + failover + polling | 589 |
| `ohlcv.sh` | Bolum 6 (satir ~948-1100) | mum_birlestirici bash sarmalayicilari | ~152 |
| `ohlcv.sh` | canli_veri_* (satir ~1240-1650) | WSS/REST canli veri pipeline | ~410 |
| **Toplam** | | | **~2675 satir** |

### 2.3 Kurum Bagimsiz Dosyalar (Kalacak)

| Dosya | Islem | Durum |
|-------|-------|-------|
| `_tvdatafeed_cagir.py` (139 satir) | tvDatafeed tek hisse cekim | Kalacak, genisleyecek |
| `_tvdatafeed_toplu.py` (594 satir) | Toplu OHLCV cekim + Supabase yazma | Kalacak |
| `_tvdatafeed_main.py` (345 satir) | tvDatafeed kutuphanesi (yerel kopya) | Kalacak, genisleyecek |
| `_bist_sembol_listesi.py` (?) | KAP'tan sembol listesi | Kalacak |
| `tarayici.sh` (290 satir) | Sembol listesi cozumleme | Kalacak |
| `ohlcv.sh` Bolum 1-5, 7-9 | mum_al, ilk dolum, tamir, cron | Kalacak |

## 3. Hedef Mimari

### 3.1 Yeni Tek Katmanli Veri Kaynagi

Gecis sonrasi tum veri ihtiyaci tek kaynaktan karsilanacaktir:

```
+-------------------------------------------------------------------+
|  TEK KAYNAK: tvDatafeed (TradingView WebSocket)                   |
|                                                                    |
|  1. GECMIS OHLCV        : get_hist() ile 5000 bar cekim           |
|     [mevcut, calisiyor]    Seans disi, kurum bagimsiz              |
|                                                                    |
|  2. CANLI FIYAT AKISI   : quote_create_session ile canli stream    |
|     [yeni, eklenecek]      Seans ici, 15dk gecikmeli (anonim mod)  |
|                            veya gecikmeisiz (girisli mod)           |
|                                                                    |
|  3. GUNLUK TAMIR         : get_hist() ile dogrulama               |
|     [mevcut, calisiyor]    Seans sonrasi, kurum bagimsiz           |
+-------------------------------------------------------------------+
```

### 3.2 Kurumlarin Yeni Sorumluluk Alani

Gecis sonrasi araci kurum adaptorlerinin sorumlulugu daraltilacaktir:

```
ONCEKI (genis):
  Kurum = Emir + Bakiye + Portfoy + Halka Arz + Canli Fiyat + WSS

SONRAKI (dar):
  Kurum = Emir + Bakiye + Portfoy + Halka Arz
  tvDatafeed = Gecmis OHLCV + Canli Fiyat Akisi + Tamir
```

Sorumluluk tablosu:

| Islem | Onceki Kaynak | Yeni Kaynak |
|-------|--------------|-------------|
| OHLCV gecmis mum | tvDatafeed | tvDatafeed (degismez) |
| Canli anlik fiyat | Kurum REST (adaptor_hisse_bilgi_al) | tvDatafeed canli stream |
| Canli tick -> mum | Kurum WSS + mum_birlestirici | tvDatafeed canli stream (dogrudan OHLCV) |
| Emir gonderme | Kurum REST | Kurum REST (degismez) |
| Bakiye sorgulama | Kurum REST | Kurum REST (degismez) |
| Portfoy sorgulama | Kurum REST | Kurum REST (degismez) |
| Halka arz islemleri | Kurum REST | Kurum REST (degismez) |
| Gunluk tamir | tvDatafeed | tvDatafeed (degismez) |

## 4. TradingView WebSocket Canli Veri Destegi

### 4.1 TradingView WS Protokolunde Canli Veri

TradingView'in WebSocket protokolu (`wss://data.tradingview.com/socket.io/websocket`) sadece gecmis veri degil, canli fiyat akisi da destekler. tvDatafeed'in kullandigi ayni baglanti uzerinden su mesajlar gonderilebilir:

```
[CANLI FIYAT STREAM PROTOKOLU]

  1. quote_create_session    -> Canli fiyat oturumu olustur
  2. quote_set_fields        -> Hangi alanlari almak istedigini belirt
                                (lp=LastPrice, ch=Change, chp=ChangePercent,
                                 volume=Volume, high_price, low_price, open_price vb.)
  3. quote_add_symbols       -> Sembolleri ekle ("BIST:THYAO", "BIST:GARAN")
  4. quote_fast_symbols      -> Hizli guncelleme modu (daha sik tick)

  Sunucudan gelen yanit (her fiyat degisiminde):
  {
    "n": "qsd",              // quote session data
    "v": {
      "BIST:THYAO": {
        "lp": 315.75,        // son fiyat
        "ch": 3.25,          // degisim (TL)
        "chp": 1.04,         // degisim (%)
        "volume": 4521000,   // hacim
        "open_price": 312.50,// acilis
        "high_price": 316.00,// gun ici en yuksek
        "low_price": 310.25, // gun ici en dusuk
        "prev_close_price": 312.50  // onceki kapanis
      }
    }
  }
```

### 4.2 Mevcut tvDatafeed Kutuphanesinin Durumu

`_tvdatafeed_main.py` (yerel kopya) su anda yalnizca `get_hist()` fonksiyonunu destekler. Canli stream icin `quote_create_session` mesajlari gondermiyor. Ancak altyapi ayni:

```
[MEVCUT — _tvdatafeed_main.py]
  TvDatafeed.__create_connection()
    -> wss://data.tradingview.com/socket.io/websocket
    -> chart_create_session  (gecmis veri icin)
    -> resolve_symbol
    -> create_series          (bar verisi iste)
    -> Yanit bekle -> DataFrame dondur -> WS kapat

[EKLENECEK — ayni WS baglantisi uzerinden]
  TvDatafeed.canli_baslat(semboller)
    -> wss://data.tradingview.com/socket.io/websocket
    -> quote_create_session   (canli stream icin)
    -> quote_set_fields       (lp, ch, chp, volume, open_price, high_price, low_price)
    -> quote_add_symbols      (BIST:THYAO, BIST:GARAN, ...)
    -> Surekli dinle -> her mesajda callback cagir
```

### 4.3 Kritik Kisit: 15 Dakika Gecikme

TradingView anonim modda (giris yapmadan) 15 dakika gecikmeli veri sunar. Bu gecikme canli fiyat akisini da etkiler.

| Mod | OHLCV Gecikmesi | Canli Fiyat Gecikmesi | Uygunluk |
|-----|----------------|----------------------|----------|
| Anonim (mevcut) | 15 dk (seans disi onemli degil) | 15 dk (seans ici sorunlu) | OHLCV icin yeterli, canli icin yetersiz |
| Girisli (TradingView hesabi) | Gercek zamanli | Gercek zamanli | Her ikisi icin yeterli |

Gecikme cozumu icin secenekler:

```
SECENEK A — TradingView Hesabi ile Giris (Onerilen)
  Ucretsiz TradingView hesabi acilir.
  tvDatafeed'e kullanici adi ve sifre verilerek giris yapilir:
    tv = TvDatafeed(username="kullanici", password="sifre")
  Bu modda veri gercek zamanli gelir, 15dk gecikme kalkar.
  Risk: TradingView hesap politikasi degisebilir.

SECENEK B — Anonim Mod ile 15dk Gecikmeyi Kabul Et
  OHLCV icin sorun yok (seans disi cekim).
  Canli fiyat icin: 15dk gecikmeli fiyatla robot calistirilir.
  Kisa vadeli stratejiler (1dk-5dk) icin uygun degildir.
  Gunluk ve ustu stratejiler icin yeterlidir.

SECENEK C — Hibrit Yaklasim
  OHLCV: Anonim mod (15dk gecikme, seans disi onemli degil).
  Canli fiyat: Girisli mod (gercek zamanli).
  Avantaj: OHLCV icin hesap bilgisi gerekmez.
  Dezavantaj: Iki ayri TvDatafeed nesnesi yonetilir.
```

### 4.4 tvDatafeed Canli Stream vs Eski Ziraat WSS Karsilastirmasi

| Ozellik | Ziraat WSS (eski) | tvDatafeed Canli (yeni) |
|---------|-------------------|------------------------|
| Protokol | SignalR WebSocket | TradingView WebSocket |
| Kurum bagimliligi | Evet (cookie, oturum) | Hayir (bagimsiz) |
| Gecikme (girisli) | ~50-200ms | ~200-500ms |
| Gecikme (girissiz) | Mumkun degil | 15 dakika |
| Sembol limiti | Kurum tarafindan belirli | Bilinmiyor (~50-100 sembol) |
| Baglanti guvenilirligi | Dusuk (cookie suresi, domain kilidi) | Orta (TradingView degistirebilir) |
| Ek veri alanlari | LastPrice, Volume | LastPrice, Volume, O/H/L/C, Change, ChangePercent |
| Mum birlestirici ihtiyaci | Evet (tick -> OHLCV) | Hayir (O/H/L/C dogrudan gelir) |
| Bakim yukuu | Yuksek (adaptor + daemon + birlestirici) | Dusuk (tek Python modulu) |

### 4.5 Canli Stream'den Gelen Verilerin Kullanim Alanlari

tvDatafeed canli stream'i gonderdiginde her mesajda su alanlar gelir:

```
lp (LastPrice)          -> Robot motoru emir karari icin
ch (Change)             -> Fiyat degisim gosterimi
chp (ChangePercent)     -> Yuzde degisim
volume                  -> Hacim bazli strateji kararlari
open_price              -> Gun ici acilis
high_price              -> Gun ici en yuksek
low_price               -> Gun ici en dusuk
prev_close_price        -> Onceki kapanis (tavan/taban hesabi)
```

Bu veri sayesinde mum birlestirici gereksiz olur cunku TradingView gun ici OHLC bilgisini dogrudan gonderir.

## 5. Kaldirilacak Dosya ve Kodlar

### 5.1 Tamamen Kaldirilacak Dosyalar

| Dosya | Satir | Neden |
|-------|-------|-------|
| `tarama/_wss_daemon.py` | 652 | Ziraat SignalR WSS daemon — tvDatafeed canli stream ile degistirilecek |
| `tarama/_mum_birlestirici.py` | 427 | WSS tick -> OHLCV donusumu — tvDatafeed dogrudan OHLC gonderdigi icin gereksiz |
| `tarama/fiyat_kaynagi.sh` | 589 | Kurum REST fiyat cekim + onbellek + failover + polling — tvDatafeed ile degistirilecek |
| `tarama/canli_veri_plani.md` | 603 | Kurum WSS'e dayali plan — gecersiz olacak, yeni plan bu belge |
| **Toplam** | **2271** | |

### 5.2 Kismi Kaldirilacak Kod Bloklari

| Dosya | Kaldirilacak Bolum | Satir Araligi | Satir Sayisi |
|-------|-------------------|---------------|--------------|
| `ziraat.sh` | Bolum 5: WSS fonksiyonlari | ~2069-2487 | ~418 |
| `ziraat.sh` | `adaptor_hisse_bilgi_al` fonksiyonu | ~2013-2063 | ~50 |
| `ziraat.ayarlar.sh` | Bolum 6: WSS ayarlari | ~186-213 | ~27 |
| `ohlcv.sh` | Bolum 6: mum_birlestirici sarmalayicilari | ~948-1100 | ~152 |
| `ohlcv.sh` | canli_veri_baslat/durdur/durum fonksiyonlari | ~1240-1650 | ~410 |
| **Toplam** | | | **~1057** |

### 5.3 Toplam Kaldirilacak Kod

```
Tamamen kaldirilacak dosyalar:  2271 satir
Kismi kaldirilacak kodlar:      1057 satir
--------------------------------------------
TOPLAM KALDIRILACAK:           ~3328 satir
```

### 5.4 Degistirilecek Plan Dosyalari

| Dosya | Islem |
|-------|-------|
| `tarama/ohlcv_plani.md` | Bolum 5.1 ve 5.3 guncellenmeli (canli veri katmani degisti) |
| `tarama/canli_veri_plani.md` | Tamamen kaldirilacak veya arsivlenecek |
| `adaptorler/plan.md` | WSS adaptor arayuzunu (`adaptor_wss_*`) cikaracak sekilde guncellenmeli |
| `sistem_plani.md` | Bolum 9 (veri kaynagi) guncellenmeli |

## 6. Eklenecek Yeni Kodlar

### 6.1 Yeni Dosya: `tarama/_tvdatafeed_canli.py`

tvDatafeed'in WebSocket baglantisi uzerinden canli fiyat stream'i yoneten Python daemon'u.

```
[YENI DOSYA: _tvdatafeed_canli.py]
Tahmini boyut: ~350-450 satir

Sorumluluklar:
  - TradingView WS'e baglan (anonim veya girisli)
  - quote_create_session ile canli fiyat oturumu olustur
  - quote_add_symbols ile sembolleri ekle
  - Gelen fiyat mesajlarini parse et
  - /tmp/borsa/_canli/<SEMBOL>.json dosyasina yaz
  - SIGUSR1 ile dinamik sembol ekleme/cikarma
  - Yeniden baglanti mekanizmasi
  - Seans otomasyonu (09:40 basla, 18:10 durdur)

Sinif yapisi:
  class CanliVeriDaemon:
      def __init__(self, semboller, kullanici=None, sifre=None)
      def baglan(self)
      def sembol_ekle(self, sembol)
      def sembol_cikar(self, sembol)
      def _mesaj_isle(self, mesaj)
      def _fiyat_yaz(self, sembol, veri)
      def _supabase_guncelle(self, sembol, veri)  # gun ici OHLCV
      def calistir(self)
      def durdur(self)
```

Cikti dosya formati (her sembol icin ayri JSON):

```
/tmp/borsa/_canli/THYAO.json
{
  "sembol": "THYAO",
  "fiyat": 315.75,
  "degisim": 3.25,
  "degisim_yuzde": 1.04,
  "hacim": 4521000,
  "acilis": 312.50,
  "yuksek": 316.00,
  "dusuk": 310.25,
  "onceki_kapanis": 312.50,
  "zaman": 1740393600
}
```

### 6.2 Yeni Dosya: `tarama/canli_veri.sh`

Canli veri yonetimi icin bash arayuzu (eskiden `ohlcv.sh` icindeki `canli_veri_*` fonksiyonlari ve `fiyat_kaynagi.sh`'nin yerine gecer).

```
[YENI DOSYA: canli_veri.sh]
Tahmini boyut: ~300-400 satir

Fonksiyonlar:
  canli_veri_baslat()        -> _tvdatafeed_canli.py daemon'unu baslatir
  canli_veri_durdur()        -> daemon'u durdurur
  canli_veri_durum()         -> baglanti durumu, acik semboller, son fiyatlar
  canli_veri_sembol_ekle()   -> daemon'a sembol ekler
  canli_veri_sembol_cikar()  -> daemon'dan sembol cikarir
  canli_fiyat_al(sembol)     -> /tmp/borsa/_canli/<SEMBOL>.json'dan oku
                                (eski fiyat_kaynagi_fiyat_al'in yerine gecer)
  canli_veri_seans_bekle()   -> seans otomasyonu
```

### 6.3 `_tvdatafeed_main.py`'ye Eklenecek Fonksiyonlar

Mevcut yerel kopyaya canli stream destegi eklenir:

```
[EKLENECEK FONKSIYONLAR]

  quote_create_session(self)
    -> Canli fiyat oturumu olusturur

  quote_add_symbols(self, semboller)
    -> Sembol listesini canli izlemeye ekler

  quote_remove_symbols(self, semboller)
    -> Sembolleri canli izlemeden cikarir

  canli_dinle(self, callback)
    -> Surekli dinleme dongusu, her fiyat degisiminde callback(sembol, veri) cagirir
    -> Mevcut WS baglantisini bosaltmak yerine canli tutar
```

### 6.4 `ohlcv.sh` Guncelleme

Mevcut canli veri pipeline kodu kaldirilacak, yerine `canli_veri.sh` source edilecek.

```
[KALDIRILACAK — ohlcv.sh]
  Bolum 6: mum_birlestirici_baslat/durdur/durum  (~152 satir)
  canli_veri_baslat/durdur/durum/seans_bekle      (~410 satir)

[EKLENECEK — ohlcv.sh basina]
  source "${BORSA_KLASORU}/tarama/canli_veri.sh"
```

### 6.5 Tahmini Yeni Kod Miktari

| Dosya | Islem | Tahmini Satir |
|-------|-------|---------------|
| `_tvdatafeed_canli.py` | Yeni dosya | ~400 |
| `canli_veri.sh` | Yeni dosya | ~350 |
| `_tvdatafeed_main.py` | Fonksiyon ekleme | ~150 |
| `ohlcv.sh` | Guncelleme | ~50 (source + ufak duzenleme) |
| **Toplam** | | **~950 satir** |

Net fark: ~3328 satir kaldirilacak, ~950 satir eklenecek = **~2378 satir azalma**.

## 7. Gecis Suresince Etkilenecek Diger Moduller

### 7.1 Robot Motoru (`robot/motor.sh`)

Robot motoru canli fiyat icin `fiyat_kaynagi_fiyat_al()` cagiriyor. Gecis sonrasi:

```
ONCEKI: fiyat_kaynagi_fiyat_al "THYAO"  -> kurum REST -> fiyat|tavan|taban|degisim|hacim
SONRAKI: canli_fiyat_al "THYAO"         -> /tmp/borsa/_canli/THYAO.json -> ayni format
```

Robot motorundeki cagri noktalarInin guncellenmesi gerekir.

### 7.2 MCP Sunucu (`mcp_sunucular/araclar/borsa_veri_araclari.py`)

MCP araci fonksiyonlarinin veri kaynagi referanslarinin guncellenmesi gerekebilir.

### 7.3 Strateji Katmani (`strateji/`)

`mum_al()` fonksiyonu degismiyor (zaten tvDatafeed tabanli). Stratejiler etkilenmez.

### 7.4 Backtest Katmani (`backtest/`)

`mum_al()` fonksiyonu degismiyor. Backtest etkilenmez.

## 8. Risk ve Sorunlar

### 8.1 TradingView Canli Stream Sinirlari

| Risk | Aciklama | Onlem |
|------|----------|-------|
| Rate limit | TradingView asiri istekte WS koparabilir | Sembol sayisini 50 ile sinirla |
| Protokol degisikligi | TradingView WS protokolunu degistirebilir | _tvdatafeed_main.py yerel kopya, hizli yama |
| Hesap engeli | TradingView girisli modda hesabi engelleyebilir | Anonim mod yedek olarak kalsin |
| 15dk gecikme | Anonim modda canli veri 15dk gecikmeli | Girisli mod kullan veya kabul et |
| Veri guvenilirligi | TradingView bazen bos yanit donebilir | Yeniden deneme + son bilinen deger onbellegi |

### 8.2 Anonim vs Girisli Mod Karari

Bu karar gecis oncesinde verilmelidir:

```
ANONIM MOD:
  + Hesap bilgisi gerektirmez
  + TradingView ToS riski daha dusuk
  - 15dk gecikme (kisa vadeli stratejiler icin uygunsuz)
  - Canli fiyat guvenilemez (robot emir karari icin riskli)

GIRISLI MOD:
  + Gercek zamanli veri
  + Robot motoru icin uygun
  - TradingView hesap bilgisi saklanmali
  - Hesap engellenme riski
  - TradingView ToS ihlali olabilir
```

### 8.3 Gecis Sirasinda Kesinti

Gecis asamali yapilacak. Her asama sonunda sistem calismaya devam etmelidir. Eski ve yeni kod bir sure birlikte yasayabilir.

## 9. Yol Haritasi

### 9.1 Asama 1 — tvDatafeed Canli Stream Prototipi

Dosya: `tarama/_tvdatafeed_canli.py`

Kapsam:
- TradingView WS'e baglan, `quote_create_session` ile canli oturum ac.
- 3-5 hisse icin canli fiyat al, stdout'a yazdir.
- Baglanti kopma ve yeniden baglanti testi.
- Anonim ve girisli mod testi.
- 15dk gecikme dogrulamasi.

Cikti: Calistirildiginda terminale canli fiyat akmali.

Tahmini sure: 3-4 saat.

### 9.2 Asama 2 — Canli Daemon ve Bash Arayuzu

Dosya: `tarama/_tvdatafeed_canli.py` (daemon modu) + `tarama/canli_veri.sh`

Kapsam:
- Daemon modu: arka planda calis, PID dosyasi, SIGUSR1 sembol guncelleme.
- JSON cikti dosyalari: `/tmp/borsa/_canli/<SEMBOL>.json`.
- `canli_veri_baslat/durdur/durum` bash fonksiyonlari.
- `canli_fiyat_al()` fonksiyonu (eski `fiyat_kaynagi_fiyat_al` yerine).
- Takip listesi entegrasyonu.

Tahmini sure: 4-5 saat.

### 9.3 Asama 3 — Eski Kurum Veri Kodlarini Kaldir

Kapsam:
- `_wss_daemon.py` sil.
- `_mum_birlestirici.py` sil.
- `fiyat_kaynagi.sh` sil.
- `ziraat.sh` Bolum 5 (WSS) ve `adaptor_hisse_bilgi_al` kaldir.
- `ziraat.ayarlar.sh` Bolum 6 (WSS ayarlari) kaldir.
- `ohlcv.sh` Bolum 6 ve canli_veri fonksiyonlarini kaldir, yerine `canli_veri.sh` source et.
- `canli_veri_plani.md` arsivle veya sil.

Tahmini sure: 2-3 saat.

### 9.4 Asama 4 — Robot Motoru ve Diger Entegrasyonlar

Kapsam:
- `robot/motor.sh` icindeki `fiyat_kaynagi_fiyat_al` cagrilarini `canli_fiyat_al` ile degistir.
- MCP sunucu veri araclari guncelle.
- Plan dosyalarini guncelle (`ohlcv_plani.md`, `sistem_plani.md`, `adaptorler/plan.md`).

Tahmini sure: 2-3 saat.

### 9.5 Asama 5 — Test ve Dogrulama

Kapsam:
- Canli stream baglanti testi (5, 20, 50 sembol).
- Seans ici fiyat dogrulama (tvDatafeed vs borsaistanbul.com elle karsilastirma).
- Robot motoru uzerinden uctan uca test (canli fiyat -> strateji -> emir karari).
- Gunluk tamir hala calisiyor mu testi.
- `mum_al()` ve `ohlcv_ilk_dolum()` hala calisiyor mu testi.

Tahmini sure: 2-3 saat.

### 9.6 Sure Ozeti

| Asama | Tahmini Sure | Bagimlilik |
|-------|-------------|------------|
| 1. Canli stream prototipi | 3-4 saat | Yok |
| 2. Daemon + bash arayuzu | 4-5 saat | Asama 1 |
| 3. Eski kodlari kaldir | 2-3 saat | Asama 2 |
| 4. Entegrasyonlar | 2-3 saat | Asama 3 |
| 5. Test ve dogrulama | 2-3 saat | Asama 4 |
| **Toplam** | **13-18 saat** | |

## 10. Gecis Oncesi Kontrol Listesi

Gecise baslamadan once su adimlar tamamlanmalidir:

```
[ ] TradingView hesabi anonim mi girisli mi karar verildi
[ ] tvDatafeed canli stream'in TradingView WS protokoluyle calismasi dogrulandi
[ ] Canli stream'de sembol limiti (kac hisse ayni anda izlenebilir) test edildi
[ ] 15dk gecikme kabul edildi VEYA girisli mod icin hesap hazirlandi
[ ] Mevcut calisan sistemin yedegi alindi (git commit/tag)
[ ] Robot motoru su anda aktif degilse gecis guvenli (aktifse once durdurulmali)
```

## 11. Geri Donus Plani

Gecis basarisiz olursa eski sisteme donmek icin:

```
1. git tag ile gecis oncesi durum isaretlenir.
2. Silinen dosyalar git'ten geri alinabilir.
3. Eski canli_veri_plani.md arsivlenecek, silinmeyecek.
4. Gecis asamali yapildigi icin her asama sonunda calisan bir sistem mevcuttur.
5. En kotu durumda: git checkout <tag> ile tum gecis geri alinir.
```
