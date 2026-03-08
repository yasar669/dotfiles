# Canli Veri Supabase Gecis Plani

## 1. Amac

Uc degisiklik tek planda birlestirildi:

1. `/tmp/borsa/_canli/` JSON dosya tabanli canli fiyat mekanizmasi kaldirilacak.
2. Iki tablolu mimari kurulacak: `ohlcv` (tarihsel arsiv) + `canli_mum` (robot calisma tablosu).
3. Her iki tablo TimescaleDB hypertable'a cevirilecek. Sikistirma politikalari etkinlestirilecek.

Temel ilke — **Hot/Cold ayirimi**:

- `ohlcv` = **Cold** (soguk) katman. Tum BIST sembollerinin tum periyotlardaki tarihsel mum arsivi. Batch guncelleme (gunde 1-2 kere). Backtest ve tarama icin.
- `canli_mum` = **Hot** (sicak) katman. Sadece takip edilen sembollerin robotun kullandigi periyottaki son 200 mumu. Baslangicta ohlcv'den kopyalanir, seans ici WebSocket ile anlik guncellenir. Robot motoru SADECE buradan okur.

Neden iki tablo:

- ohlcv'ye WebSocket verisi yazmak tutarsizliga yol acar: 50 takip edilen hisse canli, 450+ hisse 1 gun gecikme — tarama ve backtest icin tehlikeli.
- Robot icin birlestirme (canli + tarihsel) karmasikligi tek tabloda ortadan kalkar.
- Her tablonun tek gorevi var, yol carpismasi yok.

## 2. Mevcut Mimari

```
tvDatafeed WS --> Python daemon (_tvdatafeed_canli.py)
                      |
                      +--> /tmp/borsa/_canli/THYAO.json   (dosya yazimi)
                      +--> /tmp/borsa/_canli/GARAN.json
                      |
canli_fiyat_al()  <---+--> cat + jq ile JSON okuma         (bash)

Ayri olarak:
   ohlcv.sh toplu indirme --> ohlcv tablosuna INSERT      (periyodik)
```

Sorunlar:

- `/tmp` dosyalari ucucu, stale veri tehlikesi var.
- Canli fiyat Supabase'e akmiyor — baska istemciler (web, mobil) erisamiyor.
- iki ayri veri yolu (JSON dosya + ohlcv tablosu) gereksiz karmasiklik.
- ohlcv tablosu duz PostgreSQL tablosu — buyuk veri hacminde yavasi yavas.

## 3. Hedef Mimari

```
          YAZMA TARAFI
          ===========

[ohlcv.sh batch]                       [WS daemon]
  tvDatafeed REST                        tvDatafeed WebSocket
  Gunde 1-2 kere                         Anlik (her 3-5 sn)
  Tum BIST (500+)                        Takip listesi (5-50)
       |                                       |
       v                                       v
     ohlcv                                canli_mum
  (kalici arsiv, TimescaleDB)         (gecici calisma tablosu, TimescaleDB)


          OKUMA TARAFI
          ===========

  Backtest  -------> ohlcv (dogrudan)
  Tarayici  -------> ohlcv (dogrudan)
  Robot     -------> canli_mum (tek kaynak, 200 mum hazir)
  borsa gecmis fiyat -> ohlcv (dogrudan)
  borsa veri fiyat  -> canli_mum (yoksa hata don, ohlcv'ye fallback yok)


          YASAM DONGUSU (canli_mum)
          ==========================

  Ilk kurulum      --> ohlcv'den son 200 mum kopyala --> canli_mum (bir kere)
  Seans ici        --> WS tick'leri --> canli_mum UPSERT
  Seans bitti      --> Hicbir sey yapma (veri kalir)
  Yarin            --> Daemon kaldigi yerden devam, yeni mumlar UPSERT
                       200'den eski mumlar pencere kaydirma ile silinir
```

### 3.1 canli_mum Tablosu

Robot motorunun calisma tablosu. Her an robotun ihtiyac duydugu son 200 mumu icerir:

```sql
CREATE TABLE canli_mum (
    id          BIGSERIAL,
    sembol      VARCHAR(12)   NOT NULL,
    periyot     VARCHAR(4)    NOT NULL,
    tarih       TIMESTAMPTZ   NOT NULL,
    acilis      NUMERIC(12,4) NOT NULL,
    yuksek      NUMERIC(12,4) NOT NULL,
    dusuk       NUMERIC(12,4) NOT NULL,
    kapanis     NUMERIC(12,4) NOT NULL,
    hacim       BIGINT        NOT NULL DEFAULT 0,
    kaynak      VARCHAR(8)    DEFAULT 'tvdata',  -- 'ohlcv' veya 'canli'
    guncelleme  TIMESTAMPTZ   DEFAULT NOW(),
    PRIMARY KEY (sembol, periyot, tarih)
);
```

`kaynak` sutunu: `ohlcv` = baslangicta tarihselden kopyalandi, `canli` = WebSocket'ten geldi. Dogrulama icin faydali.

Ornek icerik (THYAO 15dk, saat 14:30):

```
tarih                 | acilis | kapanis | kaynak
----------------------+--------+---------+--------
2026-02-26 10:00      | 308.00 | 309.00  | ohlcv     <-- kopyalanan
2026-02-26 10:15      | 309.00 | 309.80  | ohlcv     <-- kopyalanan
...                   | ...    | ...     | ohlcv     (toplam ~180 eski mum)
2026-02-27 17:45      | 312.00 | 312.25  | ohlcv     <-- kopyalanan
--- bugunun verileri ---
2026-02-28 10:00      | 313.00 | 313.75  | canli     <-- WS
2026-02-28 10:15      | 313.75 | 314.20  | canli     <-- WS
...
2026-02-28 14:30      | 314.20 | 314.00  | canli     <-- acik mum (surekli guncelleniyor)
                                                  toplam: 200 satir
```

### 3.2 Baslangic Kopyalama

Robot baslatildiginda veya takip listesine yeni sembol eklendiginde:

```sql
-- THYAO 15dk son 200 mumu ohlcv'den canli_mum'e kopyala
INSERT INTO canli_mum (sembol, periyot, tarih, acilis, yuksek, dusuk, kapanis, hacim, kaynak)
SELECT sembol, periyot, tarih, acilis, yuksek, dusuk, kapanis, hacim, 'ohlcv'
FROM ohlcv
WHERE sembol = 'THYAO' AND periyot = '15dk'
ORDER BY tarih DESC
LIMIT 200
ON CONFLICT (sembol, periyot, tarih) DO NOTHING;
```

Bu islem bir kere yapilir (robot baslangici). Sonrasi WS ile guncellenir.

### 3.3 Canli Fiyat Nasil Okunur

Robot sadece canli_mum'e bakar:

```sql
SELECT kapanis, yuksek, dusuk, acilis, hacim, guncelleme
FROM canli_mum
WHERE sembol = 'THYAO' AND periyot = '15dk'
ORDER BY tarih DESC
LIMIT 1;
```

Robot icin 200 mumlu seri:

```sql
SELECT * FROM canli_mum
WHERE sembol = 'THYAO' AND periyot = '15dk'
ORDER BY tarih DESC
LIMIT 200;
```

Tek kaynak, birlestirme yok, cakisma yok.

### 3.4 Mum Biriktirme Mantigi

Daemon ici mum biriktirici. Her tick geldiginde:

```
Tick: THYAO = 123.45, saat 10:07

acik_mumlar["THYAO"] var mi?
    HAYIR --> yeni mum olustur:
        acilis = 123.45, yuksek = 123.45, dusuk = 123.45
        baslangic = 10:00 (15dk pencere basi)
    EVET --> guncelle:
        yuksek = max(yuksek, 123.45)
        dusuk  = min(dusuk, 123.45)
        hacim += hacim_farki

Her tick'te canli_mum'e UPSERT:
    sembol=THYAO, periyot=15dk, tarih=10:00
    kapanis=123.45 (son tick), yuksek, dusuk, hacim, kaynak='canli'

Saat 10:15 olunca:
    10:00 mumu kapanir (son UPSERT)
    10:15 icin yeni mum baslar
    200'den eski mum varsa en eskisi silinir (pencere kaydirma)
```

### 3.5 Seans Sonu ve Yeni Gun

Seans sonunda canli_mum'e dokunulmaz. Veriler kalir.

Yeni gun daemon basladiginda:

1. canli_mum'deki mevcut verileri kontrol et.
2. Eksik mumlar varsa (dun kapanis ile bugun acilis arasi) ohlcv'den tamamla.
3. WS baglantisini ac, kaldigi yerden devam et.
4. Yeni mumlar geldikce 200 pencere sinirini asan en eski mumlar silinir.

```sql
-- Pencere kaydirma: her sembol+periyot icin 200'den eski mumlari sil
DELETE FROM canli_mum
WHERE (sembol, periyot, tarih) NOT IN (
    SELECT sembol, periyot, tarih FROM canli_mum
    WHERE sembol = 'THYAO' AND periyot = '15dk'
    ORDER BY tarih DESC LIMIT 200
);
```

Reconciliation yok. ohlcv'ye aktarma yok. ohlcv kendi batch mekanizmasiyla (ohlcv.sh) zaten guncellenecek. Iki tablo birbirinden bagimsiz yazilir.

### 3.6 Veri Dogrulama (Robot Okumadan Once)

`robot_veri_oku()` fonksiyonu canli_mum'den veri cektikten sonra, robota vermeden once su kontrolleri yapar:

| Kontrol | Ne bakiyor | Hata ornegi |
|---------|-----------|-------------|
| **Yeterli mum** | Istenen limit kadar mum var mi | "200 mum istendi, 183 bulundu" |
| **Bosluk tespiti** | Ardisik mumlar arasinda beklenen aralik var mi | "11:45 ile 12:15 arasi bos (12:00 mumu yok)" |
| **Sifir hacim** | Seans icindeki mum hacim=0 mi | "10:30: hacim sifir" |
| **Tutar tutarsizligi** | yuksek >= dusuk, yuksek >= acilis/kapanis | "10:30: dusuk(315) > yuksek(310)" |

Bosluk tespiti mantigi: 15dk periyotta ardisik iki mumun tarih farki tam 15 dakika olmali. Degilse bosluk var. Seans araliklari (ogle arasi, gece) istisna olarak tanimlanir.

Hata durumunda robot:

1. Strateji hesaplamaz (yanlis sinyal uretmesin).
2. Emir gondermez.
3. Hatayi loglar (stderr + veritabani).
4. Sonraki dongude tekrar dener.
5. Arka arkaya N hata olursa uyari/bildirim gonderir.

Robot **asla** eksik veya bozuk veriyle karar vermez.

### 3.7 Takip Disindaki Semboller

- WebSocket **sadece** takip listesindeki sembolleri dinler (robot + kullanici listesi, 5-50 arasi).
- Takip disindaki semboller icin: mevcut `ohlcv.sh` toplu indirme zaten gunde 1-2 kere tum BIST'i dolduruyor.
- Tek seferlik sorgu: takip disindaki sembol icin tvDatafeed REST API'den anlik cekme yapilabilir.

### 3.8 Neden Performans Sorunu Olmaz

Supabase lokal Docker icinde calisiyor (`localhost:8001`). Ag gecikmesi sifir.

| Islem | Tahmini Sure |
|-------|-------------|
| PostgreSQL PK UPSERT (indeksli) | ~0.2-0.5 ms |
| PostgREST + Kong isleme | ~1-2 ms |
| Python requests (keep-alive) | toplam ~1-3 ms |
| Bash curl (surec baslatma dahil) | toplam ~3-8 ms |

Robot motoru 3-5 saniye aralikla fiyat okuyor. 3 ms okuma suresi tamamen onemsiz. canli_mum tablosu en fazla 50 sembol x 200 mum = 10.000 satir — minik tablo, her sorgu anlik doner.

### 3.9 Kim Nereden Okur/Yazar — Standart Tablo

| Bilesen | ohlcv | canli_mum |
|---------|-------|-----------|
| **ohlcv.sh batch** | YAZAR | -- |
| **Baslangic kopyalama** | OKUR | YAZAR |
| **WS daemon** | -- | YAZAR |
| **Robot motoru** | -- | **SADECE OKUR** |
| **Backtest** | OKUR | -- |
| **Tarayici** | OKUR | -- |
| **borsa veri fiyat** | -- | OKUR (yoksa hata) |
| **Pencere kaydirma** | -- | 200'den eski mumlari siler |

## 4. TimescaleDB Gecisi

### 4.1 Neden TimescaleDB

Her iki tablo da zaman serisi verisi tasiyor — TimescaleDB tam olarak bu is icin tasarlandi.

Kullanilacak ozellikler:

- **Hypertable**: Otomatik zaman bazli bolmeleme (chunking). Sorgular sadece ilgili parcalara dokunur.
- **Sikistirma** (sadece ohlcv): Eski veriler otomatik sikistirilir (10-20x oran). 1 GB → 50-100 MB.

Kullanilmayacak ozellikler:

- **Continuous Aggregates**: tvDatafeed zaten farkli periyotlari (15dk, 1s, 1g) ayri ayri sunuyor. Periyot donusturmeye gerek yok.
- **Saklama politikasi (retention)**: Hicbir veri otomatik silinmeyecek. Backtest icin tarihsel derinlik kritik.

### 4.2 Docker Imaji Degisikligi

`docker-compose.yml` dosyasinda PostgreSQL imaji TimescaleDB ile degistirilecek:

```yaml
db:
    image: timescale/timescaledb:latest-pg15    # eski: supabase/postgres:15.1.1.61
```

TimescaleDB imaji standart PostgreSQL ustune insa edilir. Supabase'in ihtiyac duydugu tum ozellikler (PostgREST, RLS, pg_cron vb.) aynen calisir.

### 4.3 Sema Degisiklikleri

`sema.sql` dosyasina eklenecekler:

```sql
-- TimescaleDB uzantisini etkinlestir
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- ============================================
-- ohlcv tablosu: tarihsel arsiv (hypertable)
-- ============================================

-- Mevcut ohlcv tablosunu hypertable'a cevir
-- migrate_data => true: mevcut 24M+ satir otomatik parcalanir
-- if_not_exists => true: tekrar calistirmada hata vermez
SELECT create_hypertable('ohlcv', 'tarih',
    migrate_data => true,
    if_not_exists => true
);

-- ============================================
-- canli_mum tablosu: robot calisma tablosu (hypertable)
-- ============================================

CREATE TABLE IF NOT EXISTS canli_mum (
    id          BIGSERIAL,
    sembol      VARCHAR(12)   NOT NULL,
    periyot     VARCHAR(4)    NOT NULL,
    tarih       TIMESTAMPTZ   NOT NULL,
    acilis      NUMERIC(12,4) NOT NULL,
    yuksek      NUMERIC(12,4) NOT NULL,
    dusuk       NUMERIC(12,4) NOT NULL,
    kapanis     NUMERIC(12,4) NOT NULL,
    hacim       BIGINT        NOT NULL DEFAULT 0,
    kaynak      VARCHAR(8)    DEFAULT 'tvdata',
    guncelleme  TIMESTAMPTZ   DEFAULT NOW(),
    PRIMARY KEY (sembol, periyot, tarih)
);

SELECT create_hypertable('canli_mum', 'tarih',
    if_not_exists => true
);

-- canli_mum icin indeks: robot sorgusu (sembol + periyot + tarih)
CREATE INDEX IF NOT EXISTS idx_canli_mum_sembol_periyot
    ON canli_mum (sembol, periyot, tarih DESC);
```

### 4.4 Sikistirma Politikasi (Sadece ohlcv)

ohlcv tablosunda 30 gundan eski veriler otomatik sikistirilir. Sikistirilan veriler okunabilir ama tek satir UPDATE edilemez (gerek de yok — tarihsel veri sabittir):

```sql
ALTER TABLE ohlcv SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'sembol,periyot',
    timescaledb.compress_orderby = 'tarih DESC'
);

-- 30 gundan eski parcalari otomatik sikistir
SELECT add_compression_policy('ohlcv', INTERVAL '30 days');
```

Segmentby = `sembol, periyot`: ayni sembol ve periyottaki veriler bir arada sikistirilir. Sorgu performansi korunur.

canli_mum icin sikistirma **uygulanmayacak**: tablo zaten kucuk (maks ~10.000 satir), surekli UPSERT yapiliyor. Sikistirmanin faydasi yok, zarari var (UPSERT'u engeller).

### 4.5 Saklama Politikasi — UYGULANMAYACAK

Saklama politikasi (retention policy) hicbir tabloya uygulanmayacak. Hicbir periyottaki veri otomatik silinmeyecek.

Gerekce:

- Backtest katmani mumkun oldugunca derin tarihsel veriye ihtiyac duyar. 20 yillik gunluk mum verisi stratejilerin uzun vadeli dogrulanmasi icin kritiktir.
- Kisa periyot verileri (15dk, 1S) de intraday backtest senaryolari icin degerlidir.
- TimescaleDB sikistirma politikasi (Bolum 4.4) zaten eski verileri 10-20x oraninda sikistiriyor. Disk alani sorunu sikistirma ile cozuluyor, veri silmeye gerek yok.
- Silinen veri geri getirilemez. Gereksiz risk.

Disk alani ileriki yillarda sorun olursa, o zaman sadece en kisa periyotlar (1dk, 3dk, 5dk) icin manuel temizlik degerlendirilir. Bu karar simdi degil, ihtiyac dogdugunda verilir.

### 4.6 Performans Kazanimi

ohlcv tablosu — 500 sembol x 2 yil x 15dk mum = ~7 milyon satir senaryosu:

| Sorgu | Duz PG | TimescaleDB |
|-------|--------|-------------|
| Son 1 ay, 1 sembol | ~150 ms | ~5-15 ms |
| Son 1 yil, 1 sembol | ~800 ms | ~30-50 ms |
| Tum semboller, bugun | ~400 ms | ~10-20 ms |
| UPSERT (mum yazma) | ~1 ms | ~1 ms (ayni) |
| Disk alani | ~1 GB | ~50-100 MB |

canli_mum tablosu — maks 50 sembol x 200 mum = 10.000 satir:

| Sorgu | Sure |
|-------|------|
| 1 sembol, 200 mum | ~0.5-1 ms |
| UPSERT (tick yazma) | ~0.3-0.5 ms |
| Pencere kaydirma (200'den eski sil) | ~1-2 ms |

canli_mum zaten minik, hypertable olmasa da hizli. Hypertable'in buradaki faydasi tutarli mimari ve ileride buyume esnekligi.

### 4.7 Mevcut Indeksler

TimescaleDB hypertable olusturulurken `tarih` sutununa otomatik indeks olusturur. Mevcut ve yeni indeksler:

ohlcv:
- `idx_ohlcv_sembol_periyot (sembol, periyot, tarih DESC)`: Korunacak. Tarihsel sorgular icin kritik.
- `idx_ohlcv_tarih (tarih DESC)`: TimescaleDB zaten bunu icsel olarak yapiyor. Kalabilir, zarar vermez.

canli_mum:
- `idx_canli_mum_sembol_periyot (sembol, periyot, tarih DESC)`: Yeni. Robot sorgusu icin.

## 5. Python Daemon Degisiklikleri

Etkilenen dosya: `tarama/_tvdatafeed_canli.py`

### 5.1 Kaldirilacaklar

- `_fiyat_yaz()` metodu: JSON dosyasina yazma islemi tamamen kaldirilacak.
- `_durum_yaz()` metodu: `/tmp` dosyasina durum yazma islemi kaldirilacak.
- `CANLI_DIZIN`, `DURUM_DOSYASI`, `LOG_DOSYASI` sabitleri (dosya yolu referanslari).
- JSON dosya olusturma, gecici dosya (`.tmp`) yazma ve rename mekanizmasi.

### 5.2 Eklenecekler

- **Mum biriktirici**: `MumBiriktirici` sinifi — her sembol icin acik mum takibi, periyot pencere yonetimi.
- **Baslangic kopyalama**: `_baslangic_kopyala()` metodu — ohlcv'den son 200 mumu canli_mum'e kopyalar.
- **`_canli_mum_yaz()` metodu**: `requests.patch()` ile canli_mum tablosuna UPSERT.
- **Pencere kaydirma**: Mum sayisi 200'u asinca en eski mumu siler.
- **HTTP oturumu**: `requests.Session()` ile keep-alive baglanti (connection pooling).
- **Hata toleransi**: Supabase erisilemediyse stderr'e loglama, daemon durmasin.
- **Pencere kaydirma**: Mum sayisi 200'u asinca en eski mumlari silme.

### 5.3 Baslangic Kopyalama Mekanizmasi

Daemon basladiginda, takip listesindeki her sembol icin:

```python
def _baslangic_kopyala(self, sembol: str, periyot: str, limit: int = 200) -> None:
    """ohlcv'den son N mumu canli_mum'e kopyalar."""
    # 1. ohlcv'den son 200 mumu cek
    yanit = self._oturum.get(
        f"{self._url}/rest/v1/ohlcv",
        params={
            "sembol": f"eq.{sembol}",
            "periyot": f"eq.{periyot}",
            "order": "tarih.desc",
            "limit": str(limit),
        },
        headers=self._basliklar,
    )
    # 2. canli_mum'e toplu INSERT (kaynak='ohlcv')
    satirlar = yanit.json()
    for satir in satirlar:
        satir["kaynak"] = "ohlcv"
    self._oturum.post(
        f"{self._url}/rest/v1/canli_mum",
        json=satirlar,
        headers={**self._basliklar, "Prefer": "resolution=merge-duplicates"},
    )
```

### 5.4 UPSERT Mekanizmasi

Her tick canli_mum tablosuna yazilir (ohlcv'ye degil):

```
PATCH /rest/v1/canli_mum
Headers:
    apikey: <anahtar>
    Prefer: resolution=merge-duplicates
Body:
    {
        "sembol": "THYAO",
        "periyot": "15dk",
        "tarih": "2026-02-27T10:00:00+03:00",
        "acilis": 123.00,
        "yuksek": 125.50,
        "dusuk": 122.80,
        "kapanis": 124.30,
        "hacim": 158000,
        "kaynak": "canli",
        "guncelleme": "2026-02-27T10:07:03+03:00"
    }
```

PostgREST'in `resolution=merge-duplicates` ozelligiyle PK (`sembol, periyot, tarih`) uzerinden otomatik INSERT veya UPDATE yapilir, ayni mumdaki veriler guncellenir.

### 5.5 PID ve Durum Yonetimi

PID dosyasi (`daemon.pid`) hala `/tmp` altinda kalacak — surec kontrolu icin gerekli, veri depolama ile ilgisi yok.

## 6. Bash Tarafindaki Degisiklikler

Etkilenen dosya: `tarama/canli_veri.sh`

### 6.1 canli_fiyat_al() Fonksiyonu

Mevcut hali `cat + jq` ile `/tmp` JSON dosyasi okuyor. Yeni hali canli_mum tablosundan son mumu cekecek:

```bash
curl -sf --max-time 2 \
    -H "apikey: $_SUPABASE_ANAHTAR" \
    "${_SUPABASE_URL}/rest/v1/canli_mum?sembol=eq.THYAO&periyot=eq.15dk&select=*&order=tarih.desc&limit=1" \
    | jq -r '.[0]'
```

Eger canli_mum'de veri yoksa (daemon calismiyorsa) hata doner. ohlcv'ye fallback yapilmaz — kullanici eski veriyi guncel sanmasin.

Cikti formati degismeyecek: `fiyat|tavan|taban|degisim|hacim|seans` — geriye uyumluluk korunacak. `fiyat` = son mumdaki `kapanis`.

### 6.2 robot_veri_oku() Fonksiyonu (Yeni)

Robot motoru icin tek okuma noktasi. Sadece canli_mum'den okur:

```bash
robot_veri_oku() {
    local sembol="$1"
    local periyot="$2"
    local limit="${3:-200}"

    # canli_mum'den son N mumu cek
    local veri
    veri=$(curl -sf --max-time 5 \
        -H "apikey: $_SUPABASE_ANAHTAR" \
        "${_SUPABASE_URL}/rest/v1/canli_mum?sembol=eq.${sembol}&periyot=eq.${periyot}&order=tarih.desc&limit=${limit}")

    # Dogrulama
    local sayi
    sayi=$(echo "$veri" | jq 'length')

    if [[ "$sayi" -lt "$limit" ]]; then
        echo "HATA: ${sembol} ${periyot}: ${limit} mum istendi, ${sayi} bulundu" >&2
        return 1
    fi

    # Bosluk kontrolu (Bolum 3.6'daki kurallar)
    # ...

    echo "$veri"
}
```

### 6.3 Stale Veri Kontrolu

Eski yontem: `stat -c %Y dosya` ile dosya yasina bakiyordu (60 saniye esigi).
Yeni yontem: canli_mum satirindaki `guncelleme` sutununu kontrol edecek.

### 6.4 Kaldirilacak Yapilandirmalar

canli_veri.sh'den silinecek:

- `_CANLI_DIZIN="/tmp/borsa/_canli"` (dizin referansi)
- `_CANLI_DURUM_DOSYASI`, `_CANLI_LOG_DOSYASI`, `_CANLI_SEMBOL_DOSYASI`
- `canli_veri_durum()` icindeki JSON dosya okuma blogu

### 6.5 Kalacak Yapilandirmalar

- `_CANLI_PID_DOSYASI`: Daemon PID yonetimi dosya tabanli kalacak (surec kontrolu).
- `_CANLI_SEANS_PID`: Seans bekleyici PID dosyasi (ayni sebep).

## 7. Etkilenen Diger Dosyalar

| Dosya | Degisiklik |
|-------|-----------|
| `veritabani/docker-compose.yml` | PostgreSQL imaji → TimescaleDB imaji |
| `veritabani/sema.sql` | TimescaleDB uzantisi, ohlcv + canli_mum hypertable, sikistirma politikasi, canli_mum tablo tanimi |
| `veritabani/supabase.sh` | `vt_canli_fiyat_oku` fonksiyonu (canli_mum'den son mum), `robot_veri_oku` fonksiyonu |
| `tarama/canli_veri.sh` | `canli_fiyat_al()` icerigi (canli_mum'den), `/tmp` referanslari |
| `tarama/_tvdatafeed_canli.py` | Mum biriktirici, baslangic kopyalama, canli_mum UPSERT, pencere kaydirma, JSON yazimi kaldirma |
| `cekirdek.sh` | Arayuz degismiyor, ic degisiklik yok |
| `robot/motor.sh` | `robot_veri_oku()` kullanacak (canli_mum tek kaynak) |
| `sistem_plani.md` | Mimari dokumaninda iki tablolu yapi guncelleme |

## 8. Uygulama Adimlari

### 8.1 Asamali Yol Haritasi

1. Git tag olustur: `canli-veri-supabase-oncesi`
2. `docker-compose.yml` → TimescaleDB imaji ile degistir.
3. `sema.sql` → TimescaleDB uzantisi, canli_mum tablo tanimi, her iki tablo icin hypertable donusumu, ohlcv sikistirma politikasi ekle.
4. Docker konteynerleri yeniden olustur, sema.sql calistir.
5. `_tvdatafeed_canli.py` → Baslangic kopyalama + mum biriktirici sinifi ekle, `_fiyat_yaz()` → `_canli_mum_yaz()` ile degistir, pencere kaydirma ekle.
6. `canli_veri.sh` → `canli_fiyat_al()` fonksiyonunu canli_mum REST sorgusu ile degistir, `robot_veri_oku()` fonksiyonu ekle.
7. `canli_veri.sh` → `/tmp` referanslarini temizle (PID haric).
8. `supabase.sh` → `vt_canli_fiyat_oku` fonksiyonu ekle.
9. Shellcheck ve ruff dogrulamasi.
10. Test: `borsa veri baslat`, `borsa veri fiyat THYAO`, `borsa veri durum`.

### 8.2 Geri Donus Plani

`canli-veri-supabase-oncesi` tag'ine donulebilir. TimescaleDB imaji kaldirilip eski imaja donulebilir — hypertable olmadan da tablolar normal calismaya devam eder. canli_mum tablosu DROP edilebilir, eski JSON mekanizmasi geri yuklenebilir.

## 9. Sembol Yonetimi Karari

Mevcut SIGUSR1 mekanizmasi dosya tabanli calisiyor: sembol dosyasina yaz, daemon'a sinyal gonder, daemon dosyayi yeniden okur. Bu mekanizma sade ve etkili oldugu icin aynen korunacak. Surec ici iletisim dosya tabanli kalacak, veri ciktisi Supabase'den okunacak.

Yeni sembol eklendiginde daemon ayrica o sembol icin ohlcv'den son 200 mumu canli_mum'e kopyalar (Bolum 5.3).

## 10. Ozet

| Degisiklik | Onceki | Sonraki |
|-----------|--------|---------|
| Veri mimarisi | Tek tablo (ohlcv) | Iki tablo: ohlcv (arsiv) + canli_mum (robot) |
| Fiyat yazimi (WS daemon) | `/tmp` JSON dosyasi | canli_mum tablosuna UPSERT |
| Fiyat okuma (robot) | Tanimli degil | canli_mum'den tek kaynak (200 mum hazir) |
| Fiyat okuma (backtest) | ohlcv | ohlcv (degismez) |
| Canli fiyat (bash) | `cat + jq` ile dosya | canli_mum'den son mum, yoksa hata (ohlcv'ye fallback yok) |
| Stale kontrolu | `stat -c %Y` dosya yasi | `guncelleme` sutunu |
| Veri dogrulama | Yok | Robot okumadan once bosluk/tutarlilik kontrolu |
| Depolama motoru | Duz PostgreSQL | TimescaleDB hypertable (her iki tablo) |
| Sikistirma | Yok | ohlcv: otomatik, 30 gun sonrasi (10-20x). canli_mum: yok (gereksiz) |
| Saklama politikasi | Yok | Yok — hicbir veri silinmeyecek, sikistirma yeterli |
| Seans sonu | Tanimsiz | Hicbir sey yapma (veri kalir, pencere kaydirma ile 200 mum siniri korunur) |
| Baslangic | Tanimsiz | ohlcv'den 200 mum → canli_mum kopyalama |
| PID yonetimi | `/tmp` dosyasi | `/tmp` dosyasi (degismez) |
| Sembol listesi | Dosya + SIGUSR1 | Dosya + SIGUSR1 (degismez) |
| Uzak erisim | Yok | Supabase REST + Realtime WS |
