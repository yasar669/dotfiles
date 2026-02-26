# OHLCV Veri Kaynagi - Plan

## 1. Amac

Bu belge BIST hisse senetleri icin OHLCV (Open-High-Low-Close-Volume) mum verisi kaynagi mimarisini tanimlar. Strateji ve backtest katmanlarinin ihtiyac duydugu gecmis ve canli mum verisinin nereden, nasil cekilecegini belirler.

## 2. Problem Tespiti

### 2.1 Araci Kurum Web Siteleri ile OHLCV Cekilemez

Tum araci kurum web sitelerinde ayni sorun mevcuttur: OHLCV mum verisi scraping yoluyla cekilemez.

Yapilan arastirma ve denemeler:

| Kurum / Kaynak | Yontem | Sonuc |
|----------------|--------|-------|
| Ziraat E-Sube | Angular + D3 + techan.js grafik analizi | `chartSettings.FullURL = null` — grafik API'si sunucu tarafinda devre disi birakilmis |
| Ziraat E-Sube | SignalR WebSocket deneme | Negotiate basarili ama connect 401 — cookie domain uyumsuzlugu |
| Ziraat E-Sube | getInstrument REST | Sadece anlik fiyat donuyor, OHLCV yok |
| Foreks | Web erisim denemesi | Erisilemez |
| Matriks | Web erisim denemesi | HTTP 403 |
| IS Yatirim | Web erisim denemesi | Bos yanit |
| ZPro (Ziraat) | DNS cozumleme | DNS basarisiz |

Ortak sorunlar:
- Grafik verileri genellikle JavaScript framework'leri (Angular, React) icinde render edilir, saf HTML'de yoktur.
- Chart API endpointleri CORS, cookie, token veya IP kisitiyla korumali calisir.
- WebSocket baglantilari domain'e bagli cookie dogrulamasi gerektirir, dis erisime kapalidir.
- Her kurumun altyapisi farkli oldugu icin her biri icin ayri scraper yazmak surdurulemez bir yaklasimdir.

Sonuc: Araci kurum web sitelerinden OHLCV cekmek pratik degildir.

### 2.2 WebSocket (WSS) Icin Durum Farkli

OHLCV (gecmis mum verisi) ile canli fiyat akisi (WebSocket) farkli problemlerdir ve farkli kaynaklardan karsilanir.

Detay: `canli_veri_plani.md` Bolum 1.

## 3. Mimari Karar

### 3.1 OHLCV Icin: Merkezi tvDatafeed Cozumu

Tum OHLCV ihtiyaci tek merkezden karsilanir: TradingView verileri uzerine kurulu tvDatafeed kutuphanesi.

Gerekceleri:
- BIST dahil tum dunya borsalarina erisim saglar (BIST:THYAO, BIST:GARAN vb).
- Giris gerektirmez (anonim mod ile calisir).
- 13 farkli periyot destekler (1dk, 3dk, 5dk, 15dk, 30dk, 45dk, 1S, 2S, 3S, 4S, 1G, 1H, 1A).
- Tek istekte 5000 bar cekilebilir — gunluk veride 20 yil geriye gider.
- Araci kurum oturumuna bagimli degildir, 7/24 cekilebilir.
- Kurum degistiginde veya oturum dustugunde etkilenmez.

### 3.2 Canli Fiyat Icin: Kuruma Ozgu WSS

Canli (anlik) fiyat akisi icin araci kurumlarin kendi WebSocket servisleri kullanilir.

Detay: `canli_veri_plani.md` Bolum 2 ve 5.

## 4. tvDatafeed Test Sonuclari

### 4.1 Kutuphane Bilgisi

- Kaynak: `timeth7799/tvDatafeed` (GitHub fork, orijinal StreamAlpha reposu kapali)
- Protokol: WebSocket (`wss://data.tradingview.com/socket.io/websocket`)
- Kimlik dogrulama: Gereksiz (unauthorized_user_token modu)
- Bagimlilikllar: Python 3, websocket-client, pandas, requests
- Cikti: pandas DataFrame (symbol, open, high, low, close, volume)
- Borsa kodu: `BIST`, sembol formati: `BIST:THYAO`

#### 4.1.1 Kurulum Adimlari

tvDatafeed pip ile yayinlanmamistir (orijinal repo kapali). Fork'tan dogrudan kurulur:

```
[ON KOSUL]
  python3 --version   # Python 3.10+ gerekli
  pip --version        # pip mevcut olmali

[KURULUM — sistem venv'i icine]
  # 1. Repodan kaynak kodu indir
  pip install --upgrade "git+https://github.com/timeth7799/tvDatafeed.git"

  # Bu komut su paketleri kurar:
  #   tvDatafeed (ana kutuphane)
  #   websocket-client (TradingView WS baglantisi)
  #   pandas (DataFrame ciktisi)
  #   requests (HTTP islemleri)

  # 2. Kurulumu dogrula
  python3 -c "from tvDatafeed import TvDatafeed, Interval; print('tvDatafeed kuruldu')"

  # 3. Hizli test (THYAO gunluk 5 bar)
  python3 -c "
from tvDatafeed import TvDatafeed, Interval
tv = TvDatafeed()
df = tv.get_hist('THYAO', 'BIST', Interval.in_daily, 5)
print(df)
"
```

Alternatif kurulum (pip basarisiz olursa):

```
[MANUEL KURULUM — kaynak kodu dogrudan indir]
  # 1. Kaynak kodu indir
  curl -sL "https://raw.githubusercontent.com/timeth7799/tvDatafeed/main/tvDatafeed/main.py" \
    -o /tmp/tvdatafeed_main.py

  # 2. Bagimliliklari kur
  pip install websocket-client pandas requests

  # 3. main.py'yi projeye kopyala
  cp /tmp/tvdatafeed_main.py bashrc.d/borsa/tarama/_tvdatafeed_main.py

  # 4. Import yolu: from _tvdatafeed_main import TvDatafeed, Interval
```

Kritik ayarlar:

```
[WEBSOCKET TIMEOUT]
  Varsayilan timeout 5 saniyedir. 5000 bar cekiminde yetersiz kalir.
  _tvdatafeed_cagir.py icinde timeout 20 saniyeye cikarilir:

    tv = TvDatafeed()
    tv._TvDatafeed__ws_timeout = 20  # 5sn -> 20sn

[RATE LIMIT]
  TradingView rate limit uygulamaz ancak asiri istekte WS kopar.
  Guvenli aralik: istekler arasi 1-2 saniye bekleme.
  Toplu cekimde (_tvdatafeed_toplu.py) her istek arasina time.sleep(1.5) eklenir.

[ANONIM MOD]
  Giris yapmadan kullanim (varsayilan):
    tv = TvDatafeed()  # kullanici adi ve sifre yok
  Bu modda veri 15 dakika gecikmelidir. Seans disinda sorun teskil etmez.

[HATALI SEMBOL]
  Varolmayan sembol icin get_hist() bos DataFrame doner (hata firlatmaz).
  len(df) == 0 kontrolu yapilmalidir.
```

Sistem entegrasyonu:

```
[DOSYA YOLU]
  bashrc.d/borsa/tarama/_tvdatafeed_cagir.py
    Bu dosya tvDatafeed'i sarar ve bash'ten cagirilabilir CSV ciktisi verir.
    Bash arayuzu (ohlcv.sh) bu Python dosyasini su sekilde cagririr:

    sonuc=$(python3 "$_TVDATAFEED_CAGIR" "$sembol" "$periyot" "$bar_sayisi")

    Python yoksa veya tvDatafeed import basarisiz olursa:
    -> Yahoo Finance yedegine duser (curl ile, Python gerektirmez)

[PYTHON KONTROLU — ohlcv.sh icinde]
  _tvdatafeed_hazir_mi() {
      # 1. python3 mevcut mu?
      command -v python3 >/dev/null 2>&1 || return 1
      # 2. tvDatafeed import edilebiliyor mu?
      python3 -c "from tvDatafeed import TvDatafeed" 2>/dev/null || return 1
      return 0
  }
```

### 4.2 Periyot Bazli Kapasite — 5000 Bar Testi (THYAO)

Tum 13 periyotta 5000 bar istenerek test edildi. Sonuclar:

| Periyot | Istenen | Gelen | Tarih Araligi | Derinlik | Sure |
|---------|---------|-------|---------------|----------|------|
| 1dk | 5000 | 5000 | 2026-02-09 ~ 2026-02-23 | ~10 is gunu | 3.1s |
| 3dk | 5000 | 5000 | 2026-01-12 ~ 2026-02-23 | ~6 hafta | 3.2s |
| 5dk | 5000 | 5000 | 2025-12-12 ~ 2026-02-23 | ~2.5 ay | 2.8s |
| 15dk | 5000 | 5000 | 2025-07-29 ~ 2026-02-23 | ~7 ay | 12.6s |
| 30dk | 5000 | 5000 | 2025-01-15 ~ 2026-02-23 | ~13 ay | 18.1s |
| 45dk | 5000 | 5000 | 2024-06-27 ~ 2026-02-23 | ~20 ay | 16.4s |
| 1S | 5000 | 5000 | 2024-02-20 ~ 2026-02-23 | ~2 yil | 3.8s |
| 2S | 5000 | 5000 | 2022-02-17 ~ 2026-02-23 | ~4 yil | 4.1s |
| 3S | 5000 | 5000 | 2021-02-16 ~ 2026-02-23 | ~5 yil | 4.3s |
| 4S | 5000 | 5000 | 2019-06-14 ~ 2026-02-23 | ~6.7 yil | 2.7s |
| 1G | 5000 | 5000 | 2006-03-21 ~ 2026-02-23 | 20 yil | 2.6s |
| 1H | 5000 | 1686 | 1993-08-09 ~ 2026-02-23 | 32 yil (maks) | 2.4s |
| 1A | 5000 | 391 | 1993-08-02 ~ 2026-02-02 | 32 yil (maks) | 1.7s |

Not: 1dk-1G arasi 11 periyotta tam 5000 bar doluyor. Haftalik ve ayliktaki dusuk rakamlar THYAO'nun tum borsa gecmisinin siniridir (1993).

### 4.3 Kritik Kisit: 15 Dakika Gecikme

tvDatafeed giris yapmadan (anonim mod) kullanildiginda TradingView 15 dakika gecikmeli veri sunar. Bu su anlama gelir:

- Seans icinde tvDatafeed'den alinan son mum 15 dakika eskidir.
- Seans icinde tvDatafeed ile guncelleme yapmak veri kaymasina neden olur.
- Seans disinda (borsa kapandiktan sonra) bu gecikme onemini yitirir cunku tum mumlar zaten kapanmistir.

Bu kisit tum mimari kararlarin temelini olusturur (Bolum 5 ve 6).

### 4.4 Capraz Dogrulama (GARAN)

| Periyot | Istenen | Gelen | Tarih Araligi | Sure |
|---------|---------|-------|---------------|------|
| Gunluk | 5000 | 5000 | 2006-03-30 ~ 2026-02-23 | 2.5s |

### 4.5 Mevcut Periyotlar (13 Adet)

```
1dk  3dk  5dk  15dk  30dk  45dk  1S  2S  3S  4S  1G  1H  1A
```

### 4.6 tvDatafeed ile Yahoo Finance Karsilastirmasi

| Ozellik | tvDatafeed | Yahoo Finance |
|---------|-----------|---------------|
| Protokol | WebSocket | REST (curl) |
| Kimlik dogrulama | Gereksiz | Gereksiz |
| Periyot sayisi | 13 | 9 |
| Maks bar / istek | 5000 | Range bazli limit |
| Gunluk derinlik | 5000 bar = 20 yil | Sinirsiz |
| 1 saat derinlik | ~5000 bar = ~2.5 yil | 730 gun = ~2 yil |
| 1dk derinlik | ~5000 bar = ~10 is gunu | ~486 bar/gun, max 7 gun |
| Hiz (tek istek) | 1.4-2.5 sn | 0.3-0.8 sn |
| Bash uyumlulugu | Python gerekli | curl yeterli |
| Bakim durumu | Fork, aktif bakim yok | Stabil |

tvDatafeed secim gerekceleri: daha fazla periyot, daha derin intraday gecmis, tek cagri ile 5000 bar. Yahoo Finance bash'ten curl ile kullanilabilir olmasi nedeniyle yedek kaynak olarak saklanir.

### 4.7 BIST Sembol Envanteri

KAP (Kamuyu Aydinlatma Platformu) verisine gore BIST'te 1005 adet hisse senedi islem goruyor. Tum hisselerin sembol listesi KAP'tan cekilebilir:

```
curl -sL "https://www.kap.org.tr/tr/bist-sirketler" | parse -> 1005 sembol
```

### 4.8 Toplu Cekim Lojistigi

1005 hisse x 13 periyot x 5000 bar = 13.065 istek.

| Periyot | Sure/hisse | 1005 hisse | Saat |
|---------|-----------|------------|------|
| 1dk | 3.1sn | 3.116sn | 0.9 |
| 3dk | 3.2sn | 3.216sn | 0.9 |
| 5dk | 2.8sn | 2.814sn | 0.8 |
| 15dk | 12.6sn | 12.663sn | 3.5 |
| 30dk | 18.1sn | 18.190sn | 5.1 |
| 45dk | 16.4sn | 16.482sn | 4.6 |
| 1S | 3.8sn | 3.819sn | 1.1 |
| 2S | 4.1sn | 4.120sn | 1.1 |
| 3S | 4.3sn | 4.322sn | 1.2 |
| 4S | 2.7sn | 2.714sn | 0.8 |
| 1G | 2.6sn | 2.613sn | 0.7 |
| 1H | 2.4sn | 2.412sn | 0.7 |
| 1A | 1.7sn | 1.708sn | 0.5 |
| **Toplam** | | **78.189sn** | **21.7** |

- Rate limit korumasiyla (+1sn/istek): ~25.3 saat (tek islem)
- 3 paralel WebSocket ile: ~8.4 saat
- Sadece gunluk (1G) tum hisseler: ~1 saat

Ilk dolum tek seferlik bir islemdir. Sonrasinda sadece yeni mumlar guncellenir.

## 5. Teknik Mimari

### 5.1 Mevcut Sistemdeki Yeri

sistem_plani.md'deki 5 katmanli mimariye gore OHLCV veri kaynagi tarama katmaninin (Katman 3) bir parcasidir.

```
Katman 5: Robot Motoru
    |
Katman 4: Strateji -----> mum_al("THYAO", "1G", 200)
    |                            |
Katman 3: Tarama                 |
    |                            v
    +--[OHLCV]------> tvDatafeed (Python, WS)  [kurum bagimsiz]
    |                            |
    +--[Canli Fiyat]--> Kurum WSS/REST          [kurum bagimli]
    |
Katman 2: Adaptor (emir, bakiye, portfoy)
    |
Katman 1: Cekirdek
```

OHLCV akisi adaptor katmanini ATLAMAZ — cunku araci kurum oturumuna ihtiyaci yoktur. TradingView'e dogrudan baglantir. Bu, sistem_plani.md'deki "katman atlama yasagi" kuralinin istisnasi degildir cunku tvDatafeed bir adaptor degildir, dis bir veri servisidir.

### 5.2 Dosya Yapisi

```
bashrc.d/borsa/tarama/
    ohlcv_plani.md              # Bu dosya
    ohlcv.sh                    # OHLCV cekim fonksiyonlari (bash arayuz)
    _tvdatafeed_cagir.py        # tvDatafeed Python sarmalayici (tek hisse cekim)
    _tvdatafeed_toplu.py        # Toplu cekim (ilk dolum + gunluk tamir)
    _bist_sembol_listesi.py     # KAP'tan BIST sembol listesi cekme
```

### 5.2.1 Supabase OHLCV Tablo Semasi

OHLCV verileri tek bir tabloda saklanir. Partition ve index tanimlari buyuk veri setinde performansi garanti eder.

```sql
-- OHLCV ana tablosu
CREATE TABLE IF NOT EXISTS ohlcv (
    id          BIGSERIAL,
    sembol      VARCHAR(12)   NOT NULL,   -- THYAO, GARAN, AKBNK vb.
    periyot     VARCHAR(4)    NOT NULL,   -- 1dk, 5dk, 15dk, 1S, 1G, 1H, 1A
    tarih       TIMESTAMPTZ   NOT NULL,   -- Mum acilis zamani (UTC+3)
    acilis      NUMERIC(12,4) NOT NULL,   -- Open
    yuksek      NUMERIC(12,4) NOT NULL,   -- High
    dusuk       NUMERIC(12,4) NOT NULL,   -- Low
    kapanis     NUMERIC(12,4) NOT NULL,   -- Close
    hacim       BIGINT        NOT NULL,   -- Volume
    kaynak      VARCHAR(8)    DEFAULT 'tvdata',  -- tvdata, wss, yahoo, tamir
    guncelleme  TIMESTAMPTZ   DEFAULT NOW(),
    PRIMARY KEY (sembol, periyot, tarih)
) PARTITION BY RANGE (tarih);

-- Yillik partition'lar (ornek)
CREATE TABLE ohlcv_2024 PARTITION OF ohlcv
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE ohlcv_2025 PARTITION OF ohlcv
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE ohlcv_2026 PARTITION OF ohlcv
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
-- Gecmis yillar icin toplu: 1993-2023 arasi tek partition
CREATE TABLE ohlcv_gecmis PARTITION OF ohlcv
    FOR VALUES FROM ('1993-01-01') TO ('2024-01-01');

-- Performans indexleri
CREATE INDEX idx_ohlcv_sembol_periyot ON ohlcv (sembol, periyot, tarih DESC);
CREATE INDEX idx_ohlcv_tarih ON ohlcv (tarih DESC);
```

Tablo tasarimindaki kararlar:

| Karar | Gerekce |
|-------|--------|
| `sembol+periyot+tarih` PK | Ayni mumun tekrar eklenmesini onler (UPSERT icin) |
| Yillik partition | Son yil verileri sicak, eski yillar soguk. Sorgu sadece ilgili partition'i tarar |
| `kaynak` sutunu | Mumun nereden geldigi izlenebilir (ilk dolum: tvdata, canli seans: wss, tamir: tamir) |
| `guncelleme` zamani | Gunluk tamir sirasinda mumun ne zaman guncellendigini gosterir |
| `NUMERIC(12,4)` | BIST fiyatlari kusurat icerebilir (lot alti islemler nedeniyle) |

UPSERT stratejisi (cakisan mumda guncelleme):

```sql
INSERT INTO ohlcv (sembol, periyot, tarih, acilis, yuksek, dusuk, kapanis, hacim, kaynak)
VALUES ('THYAO', '1G', '2026-02-24 10:00:00+03', 312.00, 316.50, 310.25, 315.75, 4521000, 'wss')
ON CONFLICT (sembol, periyot, tarih)
DO UPDATE SET
    acilis = EXCLUDED.acilis,
    yuksek = EXCLUDED.yuksek,
    dusuk  = EXCLUDED.dusuk,
    kapanis = EXCLUDED.kapanis,
    hacim  = EXCLUDED.hacim,
    kaynak = EXCLUDED.kaynak,
    guncelleme = NOW();
```

Bash'ten Supabase erisimi (curl ile):

```
[OKUMA — son 200 gunluk mum]
  curl -s "http://localhost:8001/rest/v1/ohlcv?\
    sembol=eq.THYAO&periyot=eq.1G&\
    order=tarih.desc&limit=200" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SUPABASE_ANON_KEY"

[YAZMA — tek mum ekle/guncelle]
  curl -s -X POST "http://localhost:8001/rest/v1/ohlcv" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates" \
    -d '{"sembol":"THYAO","periyot":"1G","tarih":"2026-02-24T10:00:00+03:00",
         "acilis":312.00,"yuksek":316.50,"dusuk":310.25,"kapanis":315.75,
         "hacim":4521000,"kaynak":"tvdata"}'

[TOPLU YAZMA — Python'dan batch insert]
  _tvdatafeed_toplu.py icinden Supabase REST API'ye 1000'er satirlik batch POST
  Header: "Prefer: resolution=merge-duplicates" (UPSERT modu)
```

Tablodan beklenen veri boyutu:

| Hesaplama | Deger |
|-----------|-------|
| 1005 hisse x 1G x 5000 bar | ~5 milyon satir |
| 1005 hisse x 13 periyot x 5000 bar (maks) | ~65 milyon satir |
| Ortalama satir boyutu | ~120 byte |
| Toplam tahmini boyut | ~7.8 GB (index dahil ~12 GB) |
| Gunluk artis (tum periyotlar, takip listesi) | ~5.000-50.000 satir/gun |

### 5.3 Uc Katmanli Veri Mimarisi

tvDatafeed'in 15 dakika gecikmeli veri vermesi nedeniyle sistem uc katmana ayrilir.
Temel prensip: Ilk dolum GENIS (tum hisseler, tum periyotlar), canli takip DAR (sadece secili hisseler, secili periyotlar).

```
+-------------------------------------------------------------------+
|  KATMAN 1: ILK DOLUM (tek seferlik)                               |
|  tvDatafeed ile tum BIST hisseleri x tum periyotlar x 5000 bar   |
|  Supabase'e yazilir. ~25 saat (tek islem) veya ~8.4 saat (3x)    |
|  Amac: Backtest ve tarama icin eksiksiz tarihsel veri deposu      |
+-------------------------------------------------------------------+
          |
          v
+-------------------------------------------------------------------+
|  KATMAN 2: CANLI SEANS (seans icinde, 09:40 - 18:10)              |
|  SADECE TAKIP LISTESINDEKI hisseler + secili periyotlar           |
|  Kurum WSS veya REST ile gercek zamanli veri                      |
|  tvDatafeed KULLANILMAZ (15dk gecikme nedeniyle)                  |
|  Her yeni mum kapanisinda -> Supabase'e yaz                       |
+-------------------------------------------------------------------+
          |
          v
+-------------------------------------------------------------------+
|  KATMAN 3: GUNLUK TAMIR (seans sonrasi, 18:30+)                   |
|  Takip listesi: tum periyotlarda detayli tamir                    |
|  Tum BIST: sadece 1G (gunluk) periyotta tamir                    |
|  tvDatafeed ile karsilastir, tutarsizligi duzelt, eksik tamamla  |
+-------------------------------------------------------------------+
```

### 5.3.1 Neden Tum Hisseleri Cekiyoruz Ama Hepsine WSS Acmiyoruz

Detay: `canli_veri_plani.md` Bolum 2.2.
Ozet: Ilk dolum tum BIST icin (backtest/tarama), WSS sadece takip listesi icin (5-50 hisse).

### 5.4 Katman 1: Ilk Dolum Sureci

Sistem ilk kurulumunda tum tarihsel veriyi Supabase'e yukler. Bu tek seferlik bir islemdir.

```
[ILK DOLUM AKISI]
  1. KAP'tan BIST sembol listesi cekilir (1005 hisse)
  2. Her sembol icin 13 periyotta 5000 bar cekilir
  3. Veri Supabase'e yazilir
  4. Ilerleme takip edilir (hangi sembol/periyot tamamlandi)
  5. Hata durumunda kaldigi yerden devam eder

  Cekim sirasi (oncelik):
    1. Once 1G (gunluk) — tum hisseler (~1 saat)
       Neden: Strateji ve backtest icin en kritik periyot
    2. Sonra 1S (saatlik) — tum hisseler (~1.1 saat)
    3. Sonra 1H, 1A (haftalik, aylik) — hizli, ~1.2 saat
    4. Son olarak intraday (1dk-45dk) — en buyuk veri, ~16 saat
```

Ilerleme dosyasi:

```
/tmp/borsa/_ohlcv_ilk_dolum/
    ilerleme.json     # {"THYAO": {"1G": "tamam", "1S": "tamam", "15dk": "devam"}}
    hatalar.json      # {"XYZHD": {"1dk": "timeout", "deneme": 2}}
```

Ilk dolum yarida kesilirse (bilgisayar kapandi, internet koptu) `ilerleme.json` sayesinde kaldigi yerden devam eder. Zaten cekilmis periyotlar tekrar cekilmez.

### 5.5 Katman 2: Canli Seans Verisi (Sadece Takip Listesi)

Seans icinde (09:40-18:10) tvDatafeed kullanilmaz. Gercek zamanli veri kurum WSS veya REST uzerinden gelir.

Detay: `canli_veri_plani.md` Bolum 3, 4 ve 5.
Kapsam: Takip listesi yonetimi, mum birlestirici algoritmasi, WSS/REST tick akisi, Supabase yazimi.

### 5.6 Katman 3: Gunluk Tamir Dongusu

Her is gunu borsa kapandiktan sonra (18:30+) otomatik calisan iki aslamali tamir sureci:

```
[GUNLUK TAMIR — her is gunu 18:30'da]

  ASAMA 1: TAKIP LISTESI — DETAYLI TAMIR (tum periyotlar)
  =========================================================
  Takip listesindeki her hisse icin tum secili periyotlarda tamir:

    THYAO (takip: 1dk, 5dk, 15dk, 1S, 1G):
      1dk: son 500 mum cek -> karsilastir -> duzelt/tamamla
      5dk: son 100 mum cek -> karsilastir -> duzelt/tamamla
      15dk: son 50 mum cek -> karsilastir -> duzelt/tamamla
      1S: son 10 mum cek -> karsilastir -> duzelt/tamamla
      1G: son 5 mum cek -> karsilastir -> duzelt/tamamla

    GARAN (takip: 5dk, 15dk, 1G):
      5dk: son 100 mum cek -> karsilastir -> duzelt/tamamla
      15dk: son 50 mum cek -> karsilastir -> duzelt/tamamla
      1G: son 5 mum cek -> karsilastir -> duzelt/tamamla

  Tahmini sure: 5-50 hisse x 3-5 periyot = 15-250 istek = ~1-15 dakika

  ASAMA 2: TUM BIST — SADECE GUNLUK (1G) TAMIR
  =========================================================
  1005 hissenin tamaminda sadece 1G (gunluk) mum tamir edilir:

    Her hisse icin:
      1G: son 5 mum cek -> karsilastir -> duzelt/tamamla

  Tahmini sure: 1005 hisse x 1 periyot = ~1 saat
  Amac: Backtest ve tarama veritabanini guncel tutmak

  ASAMA 3: TAMIR RAPORU
  =========================================================
  "23.02.2026 tamir raporu:
   Takip listesi: 3 hisse, 12 periyot, 2 mum duzeltildi, 1 eksik tamamlandi
   Genel (1G): 1005 hisse, 0 duzeltme, 3 eksik tamamlandi"
```

Neden tamir gerekli:
- WSS baglantisi kopmis olabilir — bazi mumlar eksik kalabilir.
- REST polling gecikmeleri nedeniyle mum OHLC degerleri hassas olmayabilir.
- Sistemin kapali oldugu sureler (bilgisayar kapandi vb) icin mumlar eksik kalir.
- tvDatafeed verisi TradingView'in resmi veri saglayicilarindan geldigi icin referans dogruluk kaynagi olarak kullanilir.
- 15 dakika gecikme seans disinda sifirlanir — tamir verisinin dogrulugu garantidir.

### 5.7 Veri Akis Semasi (Butunlesik)

```
[STRATEJI veya BACKTEST]
  mum_al "THYAO" "1G" 500
    |
    v
[ohlcv.sh — Bash Arayuz]
  1. Supabase sorgusu: SELECT * FROM ohlcv WHERE sembol='THYAO' AND periyot='1G' ORDER BY tarih DESC LIMIT 500
     |
     +-> Veri var ve guncel -> dondur
     +-> Veri yok veya eski ->
           |
           v
  2. tvDatafeed cek (seans disi ise):
     python3 _tvdatafeed_cagir.py THYAO 1G 500
     Supabase'e yaz + dondur
     |
     VEYA
     |
  3. Yahoo Finance yedegi (tvDatafeed basarisiz ise):
     curl ile cek -> Supabase'e yaz + dondur
```

### 5.8 Onbellek Stratejisi

Supabase ana depo olmakla birlikte, sik erisilen veriler icin dosya onbellegi kullanilir:

| Periyot | Onbellek Suresi | Aciklama |
|---------|-----------------|----------|
| 1dk, 3dk, 5dk | 5 dakika | Kisa sureli mumlar hizla eski kalir |
| 15dk, 30dk, 45dk | 15 dakika | Orta vadeli mumlar |
| 1S, 2S, 3S, 4S | 1 saat | Saatlik mumlar seans icinde yenilenir |
| 1G | 1 gun (seans kapanisinda) | Gunluk mumlar gun icinde degismez (son mum haric) |
| 1H, 1A | 1 hafta | Haftalik/aylik mumlar nadiren degisir |

Onbellek dosya formati:

```
/tmp/borsa/_ohlcv_onbellek/THYAO_1G_500.csv
  icerik: tarih,acilis,yuksek,dusuk,kapanis,hacim
          2026-02-23,312.00,316.50,310.25,315.75,4521000
          2026-02-20,308.50,313.00,307.00,312.00,3890000
          ...
```

Onbellek Supabase sorgusunu azaltmak icindir. Supabase erisilemedigi durumda onbellek yedek veri kaynagi gorevi de gorur.

### 5.9 Hata Yonetimi ve Yedek Kaynak

tvDatafeed WebSocket tabanli oldugu icin baglanti kopabilir.

```
[HATA SENARYOLARI]
  mum_al "THYAO" "1G" 500
    |
    +-> tvDatafeed denemesi (1. deneme)
    |     Basarili -> dondur
    |     Basarisiz (timeout, WS hatasi) ->
    |
    +-> tvDatafeed denemesi (2. deneme, 5sn bekle)
    |     Basarili -> dondur
    |     Basarisiz ->
    |
    +-> tvDatafeed denemesi (3. deneme, 10sn bekle)
    |     Basarili -> dondur
    |     Basarisiz ->
    |
    +-> Yahoo Finance yedegi (curl ile)
    |     curl "https://query1.finance.yahoo.com/v8/finance/chart/THYAO.IS?interval=1d&range=2y"
    |     Basarili -> dondur (periyot eslestirmesi yapilir)
    |     Basarisiz ->
    |
    +-> Onbellekte eski veri var mi?
    |     Var -> eski veriyi dondur + UYARI log
    |     Yok -> HATA: OHLCV verisi alinamadi
```

Yahoo Finance periyot eslestirmesi:

| tvDatafeed Periyodu | Yahoo Finance Karsiligi |
|--------------------|------------------------|
| 1dk | 1m |
| 5dk | 5m |
| 15dk | 15m |
| 30dk | 30m |
| 1S | 60m |
| 1G | 1d |
| 1H | 1wk |
| 1A | 1mo |
| 3dk, 45dk, 2S, 3S, 4S | Yahoo'da karsiligi yok — yedek kullanilamaz |

### 5.10 Python Bagimliligi Yonetimi

tvDatafeed Python gerektirir. Mevcut sistem "saf Bash + curl" prensibiyle calisir. Bu istisna soyle yonetilir:

- Python cagirisi sadece ohlcv.sh icerisindeki tek bir noktada yapilir.
- Bash arayuzu (mum_al fonksiyonu) dis dunyaya saf Bash olarak gorunur.
- Python yoksa veya bagimlilikllar eksikse sistem otomatik olarak Yahoo Finance yedegine duser (curl ile).
- Python bagimliliklari: websocket-client, pandas (numpy otomatik gelir).

```
[PYTHON KONTROL]
  mum_al fonksiyonu cagrildiginda:
    1. python3 var mi? -> which python3
    2. Gerekli paketler var mi? -> python3 -c "import websocket; import pandas"
    3. Her ikisi de OK -> tvDatafeed kullan
    4. Eksik bir sey var -> Yahoo Finance yedegine dus, UYARI log
```

## 6. WSS (Canli Fiyat) Stratejisi

Bu bolum ayri belgeye tasindi: `canli_veri_plani.md` Bolum 5.
Icerik: Mevcut REST polling altyapisi, kurum WSS arastirma sonuclari (Ziraat SignalR 401 sorunu), olasi cozum yollari (headless browser, REST optimizasyonu, baska kurum arastirmasi, TradingView WSS), pragmatik 3 asamali strateji ve WSS adaptor arayuzu.

## 7. Yol Haritasi

### 7.1 Asama 1 — tvDatafeed Sarmalayici

Dosya: `bashrc.d/borsa/tarama/_tvdatafeed_cagir.py`

Kapsam:
- tvDatafeed import edilir, tek hisse icin OHLCV cekilir.
- Komut satiri argumanlari: `sembol`, `periyot`, `bar_sayisi`.
- Cikti: stdout'a CSV formati (`tarih,acilis,yuksek,dusuk,kapanis,hacim`).
- WS timeout 20 saniyeye ayarlanir.
- Hatali sembol icin bos cikti + exit 1.

Ornek kullanim:

```
python3 _tvdatafeed_cagir.py THYAO 1G 200
# Cikti:
# 2026-02-24,312.00,316.50,310.25,315.75,4521000
# 2026-02-23,308.50,313.00,307.00,312.00,3890000
# ...
```

Periyot eslestirmesi (bash periyot kodu -> Interval enum):

```python
PERIYOT_ESLE = {
    "1dk": Interval.in_1_minute,
    "3dk": Interval.in_3_minute,
    "5dk": Interval.in_5_minute,
    "15dk": Interval.in_15_minute,
    "30dk": Interval.in_30_minute,
    "45dk": Interval.in_45_minute,
    "1S": Interval.in_1_hour,
    "2S": Interval.in_2_hour,
    "3S": Interval.in_3_hour,
    "4S": Interval.in_4_hour,
    "1G": Interval.in_daily,
    "1H": Interval.in_weekly,
    "1A": Interval.in_monthly,
}
```

Tahmini sure: 1-2 saat.

### 7.2 Asama 2 — BIST Sembol Listesi

Dosya: `bashrc.d/borsa/tarama/_bist_sembol_listesi.py`

Kapsam:
- KAP API'sinden BIST hisse sembollerini cekerr.
- Cikti: `/tmp/borsa/_ohlcv/semboller.txt` (satirda bir sembol).
- Crontab veya manuel: haftada bir calistirilir (yeni halka arzlar icin).
- Sembol sayisi kontrolu: < 900 ise uyari (KAP API degismis olabilir).

KAP cekim yontemi:

```python
import requests
from html.parser import HTMLParser

yanit = requests.get("https://www.kap.org.tr/tr/bist-sirketler")
# HTML parse edilir, sembol listesi cikarilir
# Her sembol bir satir olarak dosyaya yazilir
```

Alternatif (curl ile bash — Python yoksa):

```
curl -sL "https://www.kap.org.tr/tr/bist-sirketler" | \
  grep -oP '(?<="memberCode":")[A-Z0-9]+' | sort -u > "$sembol_dosyasi"
```

Tahmini sure: 1 saat.

### 7.3 Asama 3 — Supabase Sema ve Baglanti

Dosya: `bashrc.d/borsa/veritabani/sema.sql` (mevcut dosyaya eklenir)

Kapsam:
- `ohlcv` tablosu CREATE TABLE (Bolum 5.2.1'deki sema).
- Partition'lar olusturulur (1993-2023 arasi toplu, sonra yillik).
- Index tanimlari eklenir.
- UPSERT icin ON CONFLICT stratejisi test edilir.
- `supabase.sh`'a ohlcv CRUD fonksiyonlari eklenir: `vt_ohlcv_yaz`, `vt_ohlcv_oku`, `vt_ohlcv_toplu_yaz`.

Test kontrol listesi:

```
[x] Tablo olusturuldu mu?
[x] Tek mum insert calisiyor mu?
[x] Ayni mum tekrar insert -> UPSERT calisiyor mu?
[x] 1000 satirlik batch insert calisiyor mu?
[x] SELECT sembol+periyot+tarih sorgusu hizli mi? (<100ms)
[x] Partition dogru mu? (2024 verisi ohlcv_2024'e dusuyor mu?)
```

Tahmini sure: 2-3 saat.

### 7.4 Asama 4 — Ilk Dolum Araci

Dosya: `bashrc.d/borsa/tarama/_tvdatafeed_toplu.py`

Kapsam:
- 1005 hisse x 13 periyot x 5000 bar'i Supabase'e yukler.
- Cekim onceligi: 1G -> 1S -> 1H -> 1A -> intraday.
- `ilerleme.json` ile kaldigi yerden devam eder.
- Rate limit: istekler arasi 1.5 saniye bekleme.
- 3 paralel WebSocket destegi (threading veya asyncio).
- Hata yonetimi: 3 deneme, basarisiz semboller `hatalar.json`'a kaydedilir.
- Supabase'e 1000'er satirlik batch POST.
- Ilerleme ekrani: `[1G] THYAO 42/1005 -- %4.2 -- kalan: ~58dk`

Ilerleme dosyasi formati:

```json
{
  "THYAO": {"1G": "tamam", "1S": "tamam", "15dk": "devam", "1dk": "bekliyor"},
  "GARAN": {"1G": "tamam", "1S": "bekliyor"},
  "_ozet": {"toplam": 13065, "tamam": 2100, "hata": 3, "baslangic": "2026-02-25T08:00:00"}
}
```

Tahmini sure: 3-4 saat (kodlama), 8-25 saat (calisma suresi).

### 7.5 Asama 5 — Bash Arayuz

Dosya: `bashrc.d/borsa/tarama/ohlcv.sh`

Kapsam:
- `mum_al` fonksiyonu: strateji ve robot katmaninin tek erisim noktasi.
- Supabase -> tvDatafeed -> Yahoo Finance fallback zinciri.
- CSV onbellek (`/tmp/borsa/_ohlcv_onbellek/`).
- `_tvdatafeed_hazir_mi` kontrolu.

Fonksiyon imzalari:

```bash
mum_al "THYAO" "1G" 200
# Cikti: CSV formatinda OHLCV verisi (en yeni en ustte)
# Dondu: 0 (basarili), 1 (basarisiz)

mum_son_fiyat "THYAO"
# Cikti: son kapanis fiyati (tek sayi)

mum_periyotlar
# Cikti: desteklenen periyotlarin listesi
# 1dk 3dk 5dk 15dk 30dk 45dk 1S 2S 3S 4S 1G 1H 1A

_tvdatafeed_hazir_mi
# Dondu: 0 (python3 ve tvDatafeed mevcut), 1 (eksik)

_yahoo_finance_cek "THYAO" "1d" "2y"
# Yahoo Finance yedek cekim (curl ile)
```

Tahmini sure: 3-4 saat.

### 7.6 Asama 6 — Takip Listesi Yonetimi

Detay: `canli_veri_plani.md` Bolum 6.1.
Tahmini sure: 2-3 saat. Bagimlilik: Asama 5 (bash arayuz).

### 7.7 Asama 7 — REST Polling Iyilestirme (WSS Oncesi)

Detay: `canli_veri_plani.md` Bolum 6.2.
Tahmini sure: 2-3 saat. Bagimlilik: Asama 6 (takip listesi).

### 7.8 Asama 8 — WSS Mum Olusturucu

Detay: `canli_veri_plani.md` Bolum 6.3.
Tahmini sure: 4-5 saat. Bagimlilik: Asama 7 (REST polling).

### 7.9 Asama 9 — Gunluk Tamir Dongusu

Dosya: `bashrc.d/borsa/tarama/_tvdatafeed_toplu.py` (tamir modu eklenir)

Kapsam:
- Her is gunu 18:30'da crontab ile calisir.
- Asama 1: Takip listesi detayli tamir (tum secili periyotlar).
- Asama 2: Tum BIST 1G tamir.
- Karsilastirma: tvDatafeed verisi referans, Supabase verisi hedef.
- Rapor olusturma ve loglama.

Crontab kaydi:

```
30 18 * * 1-5 /home/yasar/dotfiles/.venv/bin/python3 \
  /home/yasar/dotfiles/bashrc.d/borsa/tarama/_tvdatafeed_toplu.py --tamir
```

Tamir algoritmasi:

```
[TAMIR — her sembol+periyot icin]
  1. tvDatafeed'den son N mum cek (referans)
  2. Supabase'den ayni aralikta mumlari cek (mevcut)
  3. Her mum icin karsilastir:
     a. Mevcut yoksa -> tvDatafeed mumunu ekle (kaynak: "tamir")
     b. Mevcut var ama OHLCV farkli -> tvDatafeed ile ustune yaz
     c. Mevcut var ve ayni -> degisiklik yok
  4. Istatistik kaydet: eklenen, duzeltilen, degismeyen
```

Tahmini sure: 3-4 saat.

### 7.10 Asama 10 — Strateji Katmani Entegrasyonu

Dosya: Strateji dosyalari (henuz olusturulmadi)

Kapsam:
- Strateji fonksiyonlari `mum_al` arayuzunu kullanarak teknik analiz yapar.
- Hareketli ortalama, RSI, MACD, Bollinger Bands vb.
- Robot basladiginda strateji hedefindeki hisseleri otomatik olarak takip listesine ekler.
- Robot durdugunda referans sayaci dusuruir, gerekirse takipten cikarir.

Strateji-OHLCV entegrasyon ornegi:

```bash
strateji_hareketli_ortalama() {
    local sembol="$1"
    local periyot="$2"
    local donem="$3"   # ornek: 50 (50 periyotluk MA)

    local mumlar
    mumlar=$(mum_al "$sembol" "$periyot" "$donem")
    [[ $? -ne 0 ]] && return 1

    # Kapanis fiyatlarinin ortalamasini hesapla
    local toplam=0 sayi=0
    while IFS=',' read -r _tarih _acilis _yuksek _dusuk kapanis _hacim; do
        toplam=$(echo "$toplam + $kapanis" | bc)
        ((sayi++))
    done <<< "$mumlar"

    echo "$(echo "scale=4; $toplam / $sayi" | bc)"
}
```

Tahmini sure: Strateji basina 2-4 saat, strateji katmani ayri planla detaylandirilacak.

### 7.11 Toplam Tahmini Sure ve Oncelik Sirasi

| Asama | Tahmini Sure | Bagimlilik | Oncelik |
|-------|-------------|------------|--------|
| 1. tvDatafeed sarmalayici | 1-2 saat | Yok | ILK |
| 2. BIST sembol listesi | 1 saat | Yok | ILK |
| 3. Supabase sema | 2-3 saat | Yok | ILK |
| 4. Ilk dolum araci | 3-4 saat (kod) + 8-25 saat (calisma) | 1, 2, 3 | IKINCI |
| 5. Bash arayuz (mum_al) | 3-4 saat | 1, 3 | IKINCI |
| 6. Takip listesi | 2-3 saat | 5 | UCUNCU |
| 7. REST polling iyilestirme | 2-3 saat | 5, 6 | UCUNCU |
| 8. WSS mum olusturucu | 4-5 saat | 6, 7 | DORDUNCU |
| 9. Gunluk tamir | 3-4 saat | 1, 3 | UCUNCU |
| 10. Strateji entegrasyonu | 2-4 saat/strateji | 5 | BESINCI |
| **Toplam (kodlama)** | **~24-35 saat** | | |
