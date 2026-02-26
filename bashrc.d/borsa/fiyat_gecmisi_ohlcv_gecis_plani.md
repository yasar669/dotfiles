# fiyat_gecmisi Tablosundan ohlcv Tablosuna Gecis - Plan

## 1. Sorunun Tanimi

Sistem ilk yazildiginda fiyat verilerini saklamak icin `fiyat_gecmisi` adli bir tablo tasarlandi. Bu tablo tek boyutlu (sembol + fiyat + zaman) anlik fiyat kayitlari icin dusunulmustu. Daha sonra tvDatafeed entegrasyonu ile cok periyotlu OHLCV mum verisi cekme karari alindi ve `ohlcv` tablosu eklendi. Ancak eski `fiyat_gecmisi` altyapisi temizlenmedi. Sonuc olarak:

- `fiyat_gecmisi` tablosu 0 kayit iceriyor (hicbir zaman veri yazilmamis).
- `ohlcv` tablosu 24.385.137 kayit iceriyor (12 farkli periyotta gercek veri).
- `borsa gecmis fiyat` komutu bos tablo sorguluyor ve bos donuyor.
- Backtest katmani `fiyat_gecmisi`'nden veri okumaya calisiyor ve bulamiyor.
- Iki bagimsiz veri semasinin var olmasi karisikliga yol aciyor.

## 2. Etki Analizi

### 2.1 Etkilenen Kod Dosyalari

| Dosya | Satir | Fonksiyon/Kisim | Sorun |
|---|---|---|---|
| veritabani/supabase.sh | 509-535 | `vt_fiyat_kaydet()` | `fiyat_gecmisi` tablosuna yaziyor, hic cagirilmiyor |
| veritabani/supabase.sh | 767-801 | `vt_fiyat_gecmisi()` | Bos `fiyat_gecmisi`'nden okuyor |
| veritabani/supabase.sh | 807-841 | `vt_fiyat_istatistik()` | Bos `fiyat_gecmisi`'nden istatistik hesapliyor |
| veritabani/sema.sql | 108-125 | `fiyat_gecmisi` tablo tanimi | Gereksiz tablo |
| veritabani/sema.sql | 258-259 | `idx_fiyat_gecmisi_sembol_zaman` | Gereksiz indeks |
| veritabani/sema.sql | 325-329 | `fiyat_gecmisi` RLS politikasi | Gereksiz guvenlik politikasi |
| cekirdek.sh | 1607 | `borsa gecmis fiyat` komutu | `vt_fiyat_gecmisi` cagiriyor — bos donuyor |
| tarama/fiyat_kaynagi.sh | 337-338 | anlik fiyat kaydetme | `vt_fiyat_kaydet` ile bos tabloya yaziyor |
| tarama/fiyat_kaynagi.sh | 377-378 | `fiyat_kaynagi_gecmis_al()` | `vt_fiyat_gecmisi` cagiriyor — bos donuyor |
| backtest/veri.sh | 65-123 | `_backtest_supabase_oku()` | `fiyat_gecmisi` tablosundan veri cekiyor — bos |
| backtest/veri.sh | 325-386 | `backtest_veri_yukle_csv()` | CSV'yi `fiyat_gecmisi` tablosuna aktariyor |

### 2.2 Etkilenen Plan Dokumanlari

| Dokuman | Satir(lar) | Referans |
|---|---|---|
| sistem_plani.md | 887, 889, 915, 939 | `vt_fiyat_kaydet` ve `fiyat_gecmisi` tablosu veri akis diyagramlari |
| sistem_plani.md | 1181 | Realtime icin `fiyat_gecmisi INSERT` tetikleyicisi referansi |
| sistem_plani.md | 1411-1446 | Bolum 11.5.7 `fiyat_gecmisi` tablo dokumantasyonu |
| sistem_plani.md | 1478 | `vt_fiyat_kaydet` fonksiyon tablosu |
| sistem_plani.md | 1489-1490 | `vt_fiyat_gecmisi` ve `vt_fiyat_istatistik` fonksiyon tablosu |
| sistem_plani.md | 1769, 1772 | Fiyat katmani yol haritasi |
| sistem_plani.md | 2256, 2264 | Ornek sorgu ve indeks referanslari |
| backtest_plani.md | 12, 42, 60-67 | `fiyat_gecmisi` birincil veri kaynagi olarak tanimli |
| backtest_plani.md | 101 | CSV import hedefi olarak `fiyat_gecmisi` |
| backtest_plani.md | 923, 942, 979 | Fonksiyon taslak kodlari |
| backtest_plani.md | 1059 | Yol haritasi maddesi |
| backtest_plani.md | 1118, 1172-1174, 1222, 1251 | Tablo referanslari ve bilinen sorunlar |

### 2.3 Ek Sorun: Backtest Degisken Adi Uyumsuzlugu

Backtest katmani `_SUPABASE_ANON_KEY` degiskenini kullaniyor ama asil supabase.sh katmani `_SUPABASE_ANAHTAR` degiskenini kullaniyor. Bu iki farkli isim ayni seyi ifade ediyor ancak backtest dosyalari (veri.sh, rapor.sh) hep `_SUPABASE_ANON_KEY` kullaniyor. Bu da backtest'in Supabase'e erisememesine yol aciyor.

Etkilenen dosyalar:
- `backtest/veri.sh`: satir 73, 87, 88
- `backtest/rapor.sh`: satir 103, 164, 165, 205, 206, 231, 232, 243, 270, 271, 313, 322, 323, 339, 340, 378, 386, 387

### 2.4 Ek Sorun: Backtest Veri Semasinin Eski Olmasi

`_backtest_supabase_oku()` fonksiyonu `fiyat_gecmisi` semasina gore parse yapiyor:
- `sembol, fiyat, tavan, taban, degisim, hacim, seans_durumu, zaman` alanlari istiyor.

Ancak `ohlcv` tablosunun semasi farkli:
- `sembol, periyot, tarih, acilis, yuksek, dusuk, kapanis, hacim, kaynak` alanlari var.

Bu iki sema arasinda dogrudan 1:1 esleme yok. Gecis sirasinda alan eslestirmesi yapilmasi gerekecek:

| fiyat_gecmisi alani | ohlcv karsiligi | Donusum |
|---|---|---|
| `fiyat` | `kapanis` | Dogrudan esleme |
| `tavan` | — | ohlcv'de yok, BIST kurallarindan hesaplanabilir |
| `taban` | — | ohlcv'de yok, BIST kurallarindan hesaplanabilir |
| `degisim` | — | ohlcv'de yok, onceki kapanis'tan hesaplanir |
| `hacim` | `hacim` | Dogrudan esleme |
| `seans_durumu` | — | ohlcv'de yok, gerekli degil |
| `zaman` | `tarih` | Dogrudan esleme |
| — | `acilis` | Ek bilgi (fiyat_gecmisi'nde yoktu) |
| — | `yuksek` | Ek bilgi (fiyat_gecmisi'nde yoktu) |
| — | `dusuk` | Ek bilgi (fiyat_gecmisi'nde yoktu) |
| — | `periyot` | Yeni boyut (fiyat_gecmisi'nde yoktu) |

## 3. Hedef Mimari

Gecis sonrasi tum fiyat verileri tek kaynaktan okunacak: `ohlcv` tablosu.

```
ONCEKI (BOZUK):
  borsa gecmis fiyat AKBNK
    +-> vt_fiyat_gecmisi("AKBNK", 30)
        +-> GET /rest/v1/fiyat_gecmisi?sembol=eq.AKBNK   <-- BOS TABLO
        +-> [] (bos sonuc)

SONRAKI (HEDEF):
  borsa gecmis fiyat AKBNK
    +-> vt_fiyat_gecmisi("AKBNK", 30, "1G")
        +-> GET /rest/v1/ohlcv?sembol=eq.AKBNK&periyot=eq.1G
        +-> [24 milyon kayittan filtrelenmis gercek veri]
```

Backtest icin:

```
ONCEKI (BOZUK):
  _backtest_supabase_oku "AKBNK" "2025-01-01" "2025-12-31"
    +-> GET /rest/v1/fiyat_gecmisi?sembol=eq.AKBNK   <-- BOS TABLO
    +-> HATA: veri bulunamadi

SONRAKI (HEDEF):
  _backtest_supabase_oku "AKBNK" "2025-01-01" "2025-12-31"
    +-> vt_ohlcv_oku "AKBNK" "1G" ...
    +-> [ohlcv tablosundan gercek gunluk mum verisi]
```

## 4. Degisiklik Listesi

### 4.1 Veritabani Degisiklikleri

| No | Dosya | Islem | Detay |
|---|---|---|---|
| D1 | veritabani/sema.sql | SIL | `fiyat_gecmisi` tablo tanimi (satir 108-125) |
| D2 | veritabani/sema.sql | SIL | `idx_fiyat_gecmisi_sembol_zaman` indeks tanimi (satir 258-259) |
| D3 | veritabani/sema.sql | SIL | `fiyat_gecmisi` RLS politikasi (satir 325-329) |
| D4 | veritabani/sema.sql | SIL | `fiyat_gecmisi` GRANT satirlari (dolaylidir, `ALL TABLES` kapsayici) |
| D5 | Canli veritabani | CALISTIR | `DROP TABLE IF EXISTS fiyat_gecmisi CASCADE;` |

### 4.2 supabase.sh Degisiklikleri

| No | Fonksiyon | Islem | Detay |
|---|---|---|---|
| S1 | `vt_fiyat_kaydet()` | SIL | Tamamen kaldirilacak (hic cagiran yok, tablo da kalkiyor) |
| S2 | `vt_fiyat_gecmisi()` | YENIDEN YAZ | `ohlcv` tablosundan okuyacak, periyot parametresi eklenecek |
| S3 | `vt_fiyat_istatistik()` | YENIDEN YAZ | `ohlcv` tablosundan istatistik hesaplayacak |

### 4.3 cekirdek.sh Degisiklikleri

| No | Kisim | Islem | Detay |
|---|---|---|---|
| C1 | `borsa gecmis fiyat` komutu | GUNCELLE | Periyot parametresi eklenecek, yeni imza: `borsa gecmis fiyat <SEMBOL> [PERIYOT] [GUN]` |
| C2 | Yardim metni | GUNCELLE | Fiyat komutunun yeni kullanimini yansitacak |

### 4.4 fiyat_kaynagi.sh Degisiklikleri

| No | Kisim | Islem | Detay |
|---|---|---|---|
| F1 | `vt_fiyat_kaydet` cagrisi (satir 337-338) | SIL/DEGISTIR | Fonksiyon kalkinca bu cagri da kaldirilacak |
| F2 | `fiyat_kaynagi_gecmis_al()` (satir 375-383) | GUNCELLE | `vt_fiyat_gecmisi`'nin yeni imzasini kullanacak |

### 4.5 backtest/veri.sh Degisiklikleri

| No | Kisim | Islem | Detay |
|---|---|---|---|
| B1 | `_backtest_supabase_oku()` | YENIDEN YAZ | `ohlcv` tablosundan okuyacak, OHLCV alanlarini parse edecek |
| B2 | `backtest_veri_yukle_csv()` | YENIDEN YAZ | CSV'yi `ohlcv` tablosuna yazacak (veya `vt_ohlcv_toplu_yaz` kullanacak) |
| B3 | `_SUPABASE_ANON_KEY` referanslari | DUZELT | `_SUPABASE_ANAHTAR` ile degistirilecek veya `vt_istek_at` kullanilacak |
| B4 | Veri dizisi genisletmesi | EKLE | `_BACKTEST_VERI_ACILIS`, `_BACKTEST_VERI_YUKSEK`, `_BACKTEST_VERI_DUSUK` dizileri eklenecek |

### 4.6 backtest/rapor.sh Degisiklikleri

| No | Kisim | Islem | Detay |
|---|---|---|---|
| R1 | `_SUPABASE_ANON_KEY` referanslari | DUZELT | `_SUPABASE_ANAHTAR` ile degistirilecek veya `vt_istek_at` kullanilacak |

### 4.7 Plan Dokumani Degisiklikleri

| No | Dokuman | Islem | Detay |
|---|---|---|---|
| P1 | sistem_plani.md | GUNCELLE | `fiyat_gecmisi` referanslarini `ohlcv` ile degistir |
| P2 | backtest_plani.md | GUNCELLE | `fiyat_gecmisi` referanslarini `ohlcv` ile degistir |

## 5. Yeni Fonksiyon Imzalari

### 5.1 vt_fiyat_gecmisi (yeniden yazilacak)

```bash
# vt_fiyat_gecmisi <sembol> [limit] [periyot]
# ohlcv tablosundan fiyat gecmisi gosterir.
# Varsayilan periyot: 1G (gunluk)
# Varsayilan limit: 30
vt_fiyat_gecmisi() {
    local sembol="$1"
    local limit="${2:-30}"
    local periyot="${3:-1G}"
    # ohlcv tablosundan sorgula ...
}
```

### 5.2 vt_fiyat_istatistik (yeniden yazilacak)

```bash
# vt_fiyat_istatistik <sembol> [gun_sayisi] [periyot]
# ohlcv tablosundan istatistik hesaplar.
# Varsayilan periyot: 1G (gunluk)
vt_fiyat_istatistik() {
    local sembol="$1"
    local gun="${2:-30}"
    local periyot="${3:-1G}"
    # ohlcv tablosundan sorgula ...
}
```

### 5.3 borsa gecmis fiyat (guncellenecek)

```
Kullanim: borsa gecmis fiyat <SEMBOL> [PERIYOT] [GUN]
Ornekler:
  borsa gecmis fiyat AKBNK              # Gunluk, son 30
  borsa gecmis fiyat AKBNK 1S 10        # 1 saatlik, son 10
  borsa gecmis fiyat THYAO 15dk 50      # 15 dakikalik, son 50
Gecerli periyotlar: 1dk 3dk 5dk 15dk 30dk 45dk 1S 2S 3S 4S 1G 1H 1A
```

### 5.4 _backtest_supabase_oku (yeniden yazilacak)

```bash
# _backtest_supabase_oku <sembol> <baslangic_tarih> <bitis_tarih> [periyot]
# ohlcv tablosundan gecmis mum verisi ceker.
# Varsayilan periyot: 1G (gunluk)
_backtest_supabase_oku() {
    local sembol="$1"
    local bas_tarih="$2"
    local bit_tarih="$3"
    local periyot="${4:-1G}"
    # vt_ohlcv_oku veya dogrudan REST ile sorgula ...
}
```

## 6. Uygulama Sirasi

Degisiklikler asagidaki sirada uygulanacak:

| Asama | Islem | Dosyalar | Aciklama |
|---|---|---|---|
| 1 | supabase.sh fonksiyonlarini guncelle | veritabani/supabase.sh | `vt_fiyat_gecmisi` ve `vt_fiyat_istatistik` yeniden yazilir, `vt_fiyat_kaydet` silinir |
| 2 | cekirdek.sh komutunu guncelle | cekirdek.sh | `borsa gecmis fiyat` komutu yeni imzayla guncellenir |
| 3 | fiyat_kaynagi.sh temizle | tarama/fiyat_kaynagi.sh | Eski `vt_fiyat_kaydet` cagrisi kaldirilir, gecmis fonksiyonu guncellenir |
| 4 | backtest/veri.sh yeniden yaz | backtest/veri.sh | `_backtest_supabase_oku` ve `backtest_veri_yukle_csv` guncellenir, `_SUPABASE_ANON_KEY` duzeltilir |
| 5 | backtest/rapor.sh duzelt | backtest/rapor.sh | `_SUPABASE_ANON_KEY` referanslari duzeltilir |
| 6 | sema.sql temizle | veritabani/sema.sql | `fiyat_gecmisi` tablo, indeks ve RLS tanimlari silinir |
| 7 | Canli DB'den tabloyu kaldir | terminal | `DROP TABLE IF EXISTS fiyat_gecmisi CASCADE;` |
| 8 | Plan dokumanlarini guncelle | sistem_plani.md, backtest_plani.md | `fiyat_gecmisi` referanslari duzeltilir |
| 9 | Test ve dogrulama | terminal | `borsa gecmis fiyat AKBNK` komutu ile calistigindan emin ol |

## 7. Geriye Donuk Uyumluluk

- `vt_fiyat_gecmisi` fonksiyonunun imzasi geriye uyumlu kalacak: `vt_fiyat_gecmisi <sembol> [limit]` hala calisacak (periyot varsayilan olarak `1G`).
- `borsa gecmis fiyat AKBNK 30` eski kullanim hala calisacak (periyot belirtilmezse `1G` alir, sayi verilmisse limit olarak yorumlar).
- Backtest `supabase` kaynagi secildikten sonra eski CSV ve sentetik kaynaklari aynen calismaya devam edecek.

## 8. Risk ve Dikkat Edilecekler

| Risk | Onlem |
|---|---|
| `backtest_veri_yukle_csv` artik `ohlcv`'ye yazacak; eski CSV formatinda `acilis, yuksek, dusuk` yok | CSV format dokumantasyonu guncellenecek, eksik alanlar `kapanis`'tan turetilecek (acilis=yuksek=dusuk=kapanis) |
| `_SUPABASE_ANON_KEY` degiskeni baska yerlerde de kullaniliyor olabilir | Tum backtest dosyalarinda toplu arama yapildi, sadece veri.sh ve rapor.sh'da var |
| `fiyat_gecmisi` tablosunu DROP ettikten sonra eski sema.sql tekrar calisirsa tablo geri gelir | sema.sql'den tanim silinecek, bu riski ortadan kaldirir |
| ohlcv tablosunda tavan/taban alanlari yok, backtest motoru bunlari kullaniyor olabilir | BIST kural fonksiyonlarindan (`bist_tavan_hesapla`, `bist_taban_hesapla`) hesaplanacak |
