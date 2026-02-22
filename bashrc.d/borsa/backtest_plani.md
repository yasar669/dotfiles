# Backtest Modulu - Plan

## 1. Amac

Bu belge borsa klasorune eklenecek backtest (gecmis veri uzerinde strateji testi)
altyapisini tanimlar. Backtest modulu, strateji katmaninda yazilan stratejilerin
gercek parayla islem yapmadan once gecmis veriler uzerinde test edilmesini saglar.

Backtest modulu mevcut sisteme sorunsuz entegre olur:
- Strateji arayuzunu (sistem_plani.md Bolum 10.2) oldugu gibi kullanir.
- Veri katmani array'lerini (veri_katmani_plani.md) simule eder.
- Supabase fiyat_gecmisi tablosunu (sistem_plani.md Bolum 11.5.7) veri kaynagi olarak kullanir.
- KURU_CALISTIR modunu (sistem_plani.md Bolum 14.3.1) temel alir ama ondan farklidir.
- Robot motorunun (sistem_plani.md Bolum 7-8) dongu yapisini taklit eder.

KURU_CALISTIR ile backtest arasindaki fark:
- KURU_CALISTIR canli piyasada gercek zamanli calisir, emir gondermez ama canli veri kullanir.
- Backtest gecmis veriyi hizli ileri sararak calisir. Zaman gecmiste, veri kaydedilmis.
- KURU_CALISTIR bir robot modudur, backtest bagimsiz bir aradir.

## 2. Mimari Konum

Backtest, 5 katmanli mimarinin (sistem_plani.md Bolum 2) yaninda bagimsiz bir arac
olarak konumlanir. Katman atlamaz cunku katmanlarin icinde degil, disinda calisir.

```
+-----------------------------------------------+
|  5. ROBOT MOTORU (robot/motor.sh)             |
|     Canli islem dongusu, gercek zamanli       |
+-----------------------------------------------+
|  4. STRATEJI (strateji/*.sh)                  |  <-- Backtest AYNI stratejileri kullanir
+-----------------------------------------------+
|  3. TARAMA + VERI KAYNAGI (tarama/*.sh)       |
+-----------------------------------------------+
|  2. ADAPTOR (adaptorler/*.sh)                 |
+-----------------------------------------------+
|  1. CEKIRDEK (cekirdek.sh + kurallar/*.sh)    |
+-----------------------------------------------+

+-----------------------------------------------+    +---------------------------+
|  BACKTEST MOTORU (backtest/motor.sh)          |    |  YEREL SUPABASE           |
|     Gecmis veri uzerinde strateji testi       |<-->|  fiyat_gecmisi tablosu    |
|     Sanal portfoy ve emir simulasyonu         |    |  backtest_sonuclari       |
|     Performans metrikleri hesaplama           |    |  backtest_islemleri       |
+-----------------------------------------------+    +---------------------------+
```

Backtest motoru:
- Strateji dosyalarini dogrudan source eder (strateji katmani).
- Cekirdek fonksiyonlarini kullanir (BIST kurallari, fiyat adimi).
- Adaptorlere DOKUNMAZ (canli baglanti yok).
- Tarama katmanini KULLANMAZ (gecmis veriyi kendisi okur).
- Robot motorundan BAGIMSIZDIR (ayri dongu, ayri proses).

## 3. Veri Kaynagi

Backtest motoru gecmis fiyat verilerini uc kaynaktan alabilir.
Kaynaklar oncelik sirasina gore denenir.

### 3.1 Birincil Kaynak: Supabase fiyat_gecmisi Tablosu

Tarama katmani her taze fiyat cekiminde fiyat_gecmisi tablosuna kayit yapar
(sistem_plani.md Bolum 11.5.7). Backtest bu tablodan gecmis verileri okur.

```
vt_fiyat_gecmisi("THYAO", "2025-01-01", "2025-06-01")
  +-> curl -s "$_SUPABASE_URL/rest/v1/fiyat_gecmisi"
        ?sembol=eq.THYAO
        &zaman=gte.2025-01-01
        &zaman=lte.2025-06-01
        &order=zaman.asc
  +-> JSON -> satirlara ayir -> backtest motoruna aktar
```

Her satir su alanlari icerir (sistem_plani.md Bolum 11.5.7 ile birebir):
- sembol, fiyat, tavan, taban, degisim, hacim, seans_durumu, zaman

Avantaj: Sistem kullanildikca veri otomatik birikir, ek islem gerekmez.
Dezavantaj: Yeni kurulumda gecmis veri yoktur, birikmesi zaman alir.

### 3.2 Ikincil Kaynak: CSV Dosyasi

Kullanici dis kaynaklardan (TCMB, EVDS, Yahoo Finance, investing.com) indirdigi
gecmis fiyat verilerini CSV formatinda yukleyebilir.

```
backtest_veri_yukle dosyalar/thyao_2024.csv
```

Beklenen CSV formati:

```
tarih,fiyat,tavan,taban,degisim,hacim
2024-01-02,312.50,325.00,300.00,1.25,45000000
2024-01-03,315.00,327.50,302.50,0.80,38000000
```

CSV yukleme islemleri:
1. Dosya okunur, baslik satiri dogrulanir (en az tarih ve fiyat zorunlu).
2. Her satir parse edilir, eksik alanlar NULL olarak isaretlenir.
3. Veriler fiyat_gecmisi tablosuna eklenir (kaynak_kurum="csv_import").
4. Mevcut verilerle catisma varsa (ayni sembol+tarih) atlanir (UPSERT degil, INSERT).

tavan ve taban bilgisi CSV'de yoksa onceki kapanistan hesaplanir:
- tavan = onceki_kapanis * 1.10 (yuzde 10 ust sinir)
- taban = onceki_kapanis * 0.90 (yuzde 10 alt sinir)
- Bu hesaplama yaklasiktir, BIST kural motoru (kurallar/bist.sh) ile
  kesin deger hesaplanabilir ama backtest icin yaklasik deger yeterlidir.

### 3.3 Ucuncu Kaynak: Sentetik Veri

Test ve gelistirme amacli yapay fiyat verisi uretir. Gercek piyasa
analizi icin KULLANILMAZ, sadece backtest motorunun dogrulugunu test
etmek icindir.

```
backtest_sentetik_uret "TEST01" 100 250 0.02
# Sembol: TEST01, baslangic: 100 TL, gun sayisi: 250, volatilite: %2
```

Uretim algoritmasi:
- Geometric Brownian Motion (GBM) ile rastgele fiyat yolu uretir.
- Parametreler: baslangic_fiyat, gun_sayisi, gunluk_volatilite, drift
- tavan/taban onceki kapanistan +/-%10 olarak hesaplanir.
- hacim rastgele uretilir (normal dagilim, ortalama 10M, std 3M).
- Uretilen veriler gecici bir dosyaya yazilir, Supabase'e kaydedilmez.

### 3.4 Veri Dogrulama

Hangi kaynaktan gelirse gelsin veri kullanilmadan once dogrulanir:

| Kontrol | Aciklama | Basarisizsa |
|---------|----------|-------------|
| Bos veri | Hic satir yok | HATA, backtest baslamaz |
| Eksik fiyat | Fiyat alani bos veya sifir | Satir atlanir, uyari |
| Tarih sirasi | Tarihler artarak mi siralanmis | Otomatik yeniden siralama |
| Fiyat araligi | Fiyat <= 0 veya > 100000 | Satir atlanir, uyari |
| Minimum gun | En az 5 islem gunu verisi | HATA, backtest baslamaz |
| Boşluk tespiti | Ardisik islem gunleri arasinda 5+ gun bosluk | Uyari (backtest devam eder) |

## 4. Simulasyon Motoru

Backtest motorunun cekirdegi, gecmis veriyi kronolojik olarak isleyip
strateji kararlarini sanal bir portfoyde uygulamaktir.

### 4.1 Sanal Portfoy

Backtest baslangicinda sanal bir portfoy olusturulur:

```bash
declare -gA _BACKTEST_PORTFOY
_BACKTEST_PORTFOY[baslangic_nakit]="100000.00"    # varsayilan 100K TL
_BACKTEST_PORTFOY[nakit]="100000.00"
_BACKTEST_PORTFOY[hisse_degeri]="0.00"
_BACKTEST_PORTFOY[toplam]="100000.00"
_BACKTEST_PORTFOY[islem_sayisi]=0
_BACKTEST_PORTFOY[basarili_islem]=0
_BACKTEST_PORTFOY[basarisiz_islem]=0
```

Hisse pozisyonlari gercek veri katmanindaki (veri_katmani_plani.md) yapiya
paralel olarak tutulur:

```bash
declare -gA _BACKTEST_LOT            # _BACKTEST_LOT[THYAO]=100
declare -gA _BACKTEST_MALIYET        # _BACKTEST_MALIYET[THYAO]="312.50"
declare -gA _BACKTEST_PIYASA         # _BACKTEST_PIYASA[THYAO]="315.00"
declare -gA _BACKTEST_DEGER          # _BACKTEST_DEGER[THYAO]="31500.00"
declare -gA _BACKTEST_KZ             # _BACKTEST_KZ[THYAO]="250.00"
declare -gA _BACKTEST_KZ_YUZDE       # _BACKTEST_KZ_YUZDE[THYAO]="0.80"
```

Bu array'ler veri_katmani_plani.md'deki _BORSA_VERI_HISSE_* array'leri ile
ayni yapiyi kullanir. Tek fark isimlendirmedir (_BACKTEST_ oneki).
Gercek hesap verileriyle karismayi onlemek icin ayri isim alani kullanilir.

### 4.2 Sanal Emir Motoru

Strateji "ALIS 100 312.50" veya "SATIS 50 315.00" sinyali urettiginde
sanal emir motoru bu emri gecmis veriye gore degerlendirir.

#### 4.2.1 Emir Eslestirme

```
strateji_degerlendir() -> "ALIS 100 312.50"
  |
  +-> [1] BIST fiyat adimi kontrolu
  |       bist_emir_dogrula("312.50")                    (kurallar/bist.sh)
  |       Gecersizse -> emir reddedilir, log
  |
  +-> [2] Tavan/taban kontrolu
  |       fiyat > tavan || fiyat < taban -> reddedilir
  |
  +-> [3] Bakiye kontrolu (alis icin)
  |       gerekli = lot * fiyat + komisyon
  |       nakit < gerekli -> reddedilir
  |
  +-> [4] Pozisyon kontrolu (satis icin)
  |       _BACKTEST_LOT[sembol] < lot -> reddedilir
  |
  +-> [5] Eslestirme
  |       Limit emri: fiyat <= tavan && fiyat >= taban -> eslesti
  |       Piyasa emri: gunun kapanis fiyatindan eslestir
  |
  +-> [6] Portfoy guncelle
  |       nakit -= lot * fiyat + komisyon  (alis)
  |       nakit += lot * fiyat - komisyon  (satis)
  |       _BACKTEST_LOT, _BACKTEST_MALIYET guncelle
  |
  +-> [7] Islem kaydini tut
```

#### 4.2.2 Komisyon Hesabi

BIST islem komisyonlari simulasyona dahil edilir:

```bash
_BACKTEST_KOMISYON_ALIS="0.00188"     # Alis komisyonu (binde 1.88, varsayilan)
_BACKTEST_KOMISYON_SATIS="0.00188"    # Satis komisyonu (binde 1.88, varsayilan)
```

Komisyon oranlari kullanici tarafindan degistirilebilir:

```
borsa backtest ornek.sh --komisyon-alis 0.002 --komisyon-satis 0.002
```

Komisyon hesabi:

```
alis_maliyeti  = lot * fiyat * (1 + komisyon_alis)
satis_getirisi = lot * fiyat * (1 - komisyon_satis)
```

#### 4.2.3 Eslestirme Modelleri

Backtest motorunda iki eslestirme modeli desteklenir:

| Model | Aciklama | Kullanim |
|-------|----------|----------|
| KAPANIS | Emir gunun kapanis fiyatindan eslesir | Varsayilan, basit |
| LIMIT | Emir belirtilen fiyattan eslesir (tavan/taban icindeyse) | Gercekci |

KAPANIS modeli: Strateji hangi fiyati soylerse soylesin, o gunun kapanis fiyati
kullanilir. Basittir ama gercekciligi dusuktur.

LIMIT modeli: Strateji belirtilen fiyat o gunun taban-tavan araliginda ise
belirtilen fiyattan eslesir. Aralik disindaysa emir reddedilir.

```
borsa backtest ornek.sh --eslestirme LIMIT
borsa backtest ornek.sh --eslestirme KAPANIS
```

### 4.3 Ana Dongu

Backtest motorunun ana dongusu, robot motorunun (sistem_plani.md Bolum 4.1)
dongusunu taklit eder. Temel fark: gercek zamanda degil, veri satirlari
uzerinde iterasyon yapar.

```
[BASLATMA]
  backtest_baslat <strateji_dosyasi> [secenekler]
    |
    +-> Strateji dosyasini source et                (strateji katmani)
    +-> strateji_baslat() cagir                     (strateji baslangiclari)
    +-> Sanal portfoyu olustur                      (baslangic nakiti)
    +-> Gecmis verileri yukle                       (veri kaynagi)
    +-> Verileri dogrula                            (bos, siralama, aralik)

[ANA DONGU - her veri satiri icin]
    |
    +-> [1] Veri satirini oku
    |       tarih, fiyat, tavan, taban, degisim, hacim, seans
    |
    +-> [2] _BORSA_VERI_* array'lerini simule et
    |       _BACKTEST_PIYASA[sembol]="$fiyat"
    |       Portfoy degerlerini guncelle
    |
    +-> [3] strateji_degerlendir() cagir
    |       strateji_degerlendir "$sembol" "$fiyat" "$tavan" "$taban" \
    |                            "$degisim" "$hacim" "$seans"
    |       Cikti: "BEKLE" / "ALIS lot fiyat" / "SATIS lot fiyat"
    |
    +-> [4] Sinyal degerlendirmesi
    |       BEKLE -> bir sey yapma
    |       ALIS/SATIS -> sanal emir motoruna gonder
    |
    +-> [5] Sanal emir islemi
    |       Bakiye/pozisyon kontrolu
    |       Eslestirme modeline gore islem yap
    |       Portfoyu guncelle
    |
    +-> [6] Gunluk metrikleri guncelle
    |       Portfoy degeri, dusus (drawdown), K/Z

[BITIRME]
    |
    +-> strateji_temizle() cagir (varsa)
    +-> Metrikleri hesapla
    +-> Sonuclari goster
    +-> Supabase'e kaydet (varsa)
```

### 4.4 Coklu Sembol Destegi

Strateji birden fazla sembol icin karar verebilir (sistem_plani.md Bolum 10.2.2).
Backtest motorunda coklu sembol su sekilde desteklenir:

```
borsa backtest ornek.sh --semboller THYAO,AKBNK,GARAN --tarih 2024-01-01:2025-01-01
```

Coklu sembol modunda:
- Her sembol icin ayri veri serisi yuklenir.
- Her veri noktasinda tum semboller kronolojik sirada islenir.
- Portfoy tum semboller icin ortaktir (nakit paylasilir).
- strateji_degerlendir her sembol icin ayri cagrilir.
- Tarih cakistirmasi yapilir: tum sembollerde ortak olan tarihler kullanilir.

```
[GUN: 2024-03-15]
  for sembol in THYAO AKBNK GARAN; do
      veri = o gunun fiyat verisi
      sinyal = strateji_degerlendir "$sembol" ...
      sinyal != BEKLE ise -> sanal emir isle
  done
  gunluk_metrikleri_guncelle
```

## 5. Strateji Entegrasyonu

Backtest motoru, strateji katmaninda (sistem_plani.md Bolum 10.2) tanimlanan
arayuzu HICBIR DEGISIKLIK yapmadan kullanir.

### 5.1 Strateji Arayuzu (Tekrar)

sistem_plani.md Bolum 10.2.1'deki arayuz:

```bash
strateji_baslat() {
    # Baslangic ayarlari, degisken tanimlari
}

strateji_degerlendir() {
    local sembol="$1" fiyat="$2" tavan="$3" taban="$4"
    local degisim="$5" hacim="$6" seans="$7"
    # stdout'a: "BEKLE" / "ALIS lot fiyat" / "SATIS lot fiyat"
    echo "BEKLE"
}

strateji_temizle() {
    # Opsiyonel: temizlik, ozet
}
```

Ayni strateji dosyasi hem robot motorunda hem backtest motorunda calisir.
Strateji kendi ortaminin robot mu yoksa backtest mi oldugunu bilmez ve
bilmesine gerek yoktur.

### 5.2 Strateji Degiskenleri

Bazi stratejiler ortam degiskenlerine ihtiyac duyabilir. Backtest motoru
su degiskenleri strateji icin set eder:

```bash
_BACKTEST_MOD=1                        # 1=backtest, 0=canli (robot set eder)
_BACKTEST_TARIH="2024-03-15"           # Simule edilen tarih
_BACKTEST_GUN_NO=45                    # Baslangictan beri kacinci islem gunu
```

Strateji bu degiskenlere erisebilir ama kullanimii opsiyoneldir.
Iyi yazilmis bir strateji bu degiskenlere BAGIMLI OLMAZ.

### 5.3 Walk-Forward Destegi

Strateji baslangicta bir "isitma donemi" (warm-up period) gerektirebilir.
Ornegin 20 gunluk hareketli ortalama hesaplayan bir strateji en az 20 gun
veriye ihtiyac duyar.

```
borsa backtest hareketli_ort.sh --isitma 20 --tarih 2024-01-01:2025-01-01
```

Isitma donemi:
- Ilk N gun boyunca strateji_degerlendir cagrilir ama sinyaller YOKSAYILIR.
- Strateji kendi icerisinde gerekli veriyi biriktirir (orn: fiyat dizisi).
- Isitma bittikten sonra sinyaller isleme alinir.
- Isitma donemi performans metriklerine DAHIL EDILMEZ.

## 6. Performans Metrikleri

Backtest tamamlandiginda asagidaki metrikler hesaplanir ve raporlanir.

### 6.1 Temel Metrikler

| Metrik | Aciklama | Formul |
|--------|----------|--------|
| Toplam Getiri | Portfoy deger degisimi | (son_deger - baslangic) / baslangic * 100 |
| Yillik Getiri | Yilliga cevirilmis getiri | ((1 + toplam_getiri)^(252/gun) - 1) * 100 |
| Toplam Islem | Yapilan alis+satis sayisi | alis_sayisi + satis_sayisi |
| Basarili Islem | Karli kapanan pozisyon | kar > 0 olan satislar |
| Basari Orani | Karli islem yuzdesi | basarili / toplam * 100 |
| Toplam Komisyon | Odenen komisyon tutari | sum(her islem komisyonu) |

### 6.2 Risk Metrikleri

| Metrik | Aciklama | Formul |
|--------|----------|--------|
| Maks Dusus | En buyuk tepe-dip deger kaybi | max((tepe - dip) / tepe) * 100 |
| Sharpe Orani | Riske gore duzeltilmis getiri | (ort_getiri - risksiz) / std_getiri * sqrt(252) |
| Sortino Orani | Asagi yonlu riske gore getiri | (ort_getiri - risksiz) / std_negatif * sqrt(252) |
| Maks Ardisik Kayip | En uzun kayip serisi | ardisik negatif islem sayisi |
| Calmar Orani | Getiri / maks dusus | yillik_getiri / maks_dusus |

Risksiz faiz orani varsayilan olarak yuzde 40 (TCMB politika faizi yakininda)
kabul edilir. Kullanici degistirebilir:

```
borsa backtest ornek.sh --risksiz 0.40
```

### 6.3 Detay Metrikleri

| Metrik | Aciklama |
|--------|----------|
| Ort Kar/Islem | Karli islemlerin ortalama kari |
| Ort Zarar/Islem | Zarari islemlerin ortalama zarari |
| Kar/Zarar Orani | Ort kar / Ort zarar (mutlak deger) |
| Maks Tek Islem Kari | En buyuk tek islem kari |
| Maks Tek Islem Zarari | En buyuk tek islem zarari |
| Ort Pozisyon Suresi | Pozisyonlarin ortalama tutulma gunu |
| En Uzun Pozisyon | En uzun tutulan pozisyon (gun) |
| Portfoy Kullanimi | Ortalama (hisse_degeri / toplam_deger) |

### 6.4 Rapor Ciktisi

Backtest tamamlandiginda rapor terminale ozetlenir:

```
=== BACKTEST SONUCU ===
Strateji:        ornek.sh
Sembol:          THYAO
Donem:           2024-01-02 / 2024-12-31 (248 islem gunu)
Baslangic:       100,000.00 TL
Bitis:           118,450.00 TL
---
Toplam Getiri:   %18.45
Yillik Getiri:   %18.72
Maks Dusus:      %8.32
Sharpe Orani:    1.24
Sortino Orani:   1.68
---
Toplam Islem:    47 (28 alis, 19 satis)
Basari Orani:    %63.16 (12/19 karli)
Kar/Zarar Orani: 2.15
Toplam Komisyon: 1,245.80 TL
---
Ort Pozisyon:    8.3 gun
Maks Kayip Seri: 3 islem
```

## 7. Veritabani Entegrasyonu

Backtest sonuclari ve islem detaylari Supabase'e kaydedilir.
Bu tablo tanimlari sistem_plani.md Bolum 11.5'teki mevcut tablolarin
yanina eklenir.

### 7.1 backtest_sonuclari Tablosu

Her backtest calistirmasinin ozet sonucunu tutar.

```
backtest_sonuclari tablosu:
  id              BIGINT       PRIMARY KEY (otomatik)
  strateji        TEXT         NOT NULL    (strateji dosya adi)
  semboller       TEXT[]       NOT NULL    (test edilen semboller)
  baslangic_tarih DATE         NOT NULL    (test baslangic tarihi)
  bitis_tarih     DATE         NOT NULL    (test bitis tarihi)
  islem_gunu      INTEGER      NOT NULL    (toplam islem gunu sayisi)
  baslangic_nakit NUMERIC(14,2) NOT NULL   (TL)
  bitis_deger     NUMERIC(14,2) NOT NULL   (TL)
  toplam_getiri   NUMERIC(8,4)             (yuzde)
  yillik_getiri   NUMERIC(8,4)             (yuzde)
  maks_dusus      NUMERIC(8,4)             (yuzde)
  sharpe_orani    NUMERIC(8,4)
  sortino_orani   NUMERIC(8,4)
  calmar_orani    NUMERIC(8,4)
  toplam_islem    INTEGER
  basarili_islem  INTEGER
  basari_orani    NUMERIC(6,2)             (yuzde)
  kz_orani        NUMERIC(8,4)             (kar/zarar orani)
  toplam_komisyon NUMERIC(14,2)            (TL)
  ort_pozisyon_gun NUMERIC(6,2)            (gun)
  maks_kayip_seri INTEGER
  eslestirme      TEXT         DEFAULT 'KAPANIS' (KAPANIS veya LIMIT)
  komisyon_alis   NUMERIC(8,6)             (oran)
  komisyon_satis  NUMERIC(8,6)             (oran)
  parametreler    JSONB                    (strateji parametreleri, serbest format)
  zaman           TIMESTAMPTZ  DEFAULT NOW()
```

### 7.2 backtest_islemleri Tablosu

Backtest sirasinda yapilan her sanal islemin kaydi.

```
backtest_islemleri tablosu:
  id              BIGINT       PRIMARY KEY (otomatik)
  backtest_id     BIGINT       REFERENCES backtest_sonuclari(id)
  gun_no          INTEGER      NOT NULL    (baslangictan kacinci gun)
  tarih           DATE         NOT NULL
  sembol          TEXT         NOT NULL
  yon             TEXT         NOT NULL    (ALIS veya SATIS)
  lot             INTEGER      NOT NULL
  fiyat           NUMERIC(12,4) NOT NULL
  komisyon        NUMERIC(10,2)            (TL)
  nakit_sonrasi   NUMERIC(14,2)            (islem sonrasi nakit)
  portfoy_degeri  NUMERIC(14,2)            (islem sonrasi toplam deger)
  sinyal          TEXT                     (strateji ciktisi, ham metin)
  zaman           TIMESTAMPTZ  DEFAULT NOW()
```

### 7.3 backtest_gunluk Tablosu

Her islem gunundeki portfoy degerini tutar. Equity curve (deger egrisi)
cizmek ve drawdown hesaplamak icin kullanilir.

```
backtest_gunluk tablosu:
  id              BIGINT       PRIMARY KEY (otomatik)
  backtest_id     BIGINT       REFERENCES backtest_sonuclari(id)
  gun_no          INTEGER      NOT NULL
  tarih           DATE         NOT NULL
  nakit           NUMERIC(14,2) NOT NULL
  hisse_degeri    NUMERIC(14,2) NOT NULL
  toplam          NUMERIC(14,2) NOT NULL
  dusus           NUMERIC(8,4)             (o ana kadarki tepe'den yuzde dusus)
  UNIQUE(backtest_id, tarih)
```

### 7.4 Index Tanimlari

sema.sql dosyasina (sistem_plani.md Bolum 14.2.3) eklenmesi gereken indexler:

```sql
CREATE INDEX idx_bt_sonuc_strateji ON backtest_sonuclari(strateji);
CREATE INDEX idx_bt_sonuc_zaman ON backtest_sonuclari(zaman DESC);
CREATE INDEX idx_bt_islem_backtest ON backtest_islemleri(backtest_id);
CREATE INDEX idx_bt_islem_sembol ON backtest_islemleri(sembol, tarih);
CREATE INDEX idx_bt_gunluk_backtest ON backtest_gunluk(backtest_id, tarih);
```

### 7.5 Kayit Politikasi

- Backtest sonuclari her zaman Supabase'e kaydedilir (Supabase aciksa).
- Supabase kapaliysa sonuclar terminale yazdirilir, kayit atlanir, uyari verilir.
- Kayit basarisizligi backtest'i engellemez (sistem_plani.md Bolum 11.8 ile uyumlu).
- Ayni strateji+sembol+tarih araligi ile tekrar calistirilirsa yeni kayit eklenir
  (eski kayitlar silinmez, karsilastirma yapilabilir).

## 8. CLI Arayuzu

Backtest modulu `borsa backtest` alt komutuyla kullanilir.
borsa() fonksiyonuna yeni bir case blogu olarak eklenir
(sistem_plani.md Bolum 14.1.4'teki kurumsuz komut yapisina uygun).

### 8.1 Temel Kullanim

```bash
# Tek sembol, varsayilan ayarlar
borsa backtest ornek.sh THYAO

# Tarih araligi belirterek
borsa backtest ornek.sh THYAO --tarih 2024-01-01:2025-01-01

# Coklu sembol
borsa backtest ornek.sh THYAO,AKBNK,GARAN --tarih 2024-01-01:2025-01-01

# Tam parametreli
borsa backtest ornek.sh THYAO \
    --tarih 2024-01-01:2025-01-01 \
    --nakit 200000 \
    --komisyon-alis 0.002 \
    --komisyon-satis 0.002 \
    --eslestirme LIMIT \
    --isitma 20 \
    --risksiz 0.40
```

### 8.2 Parametre Tablosu

| Parametre | Kisaltma | Varsayilan | Aciklama |
|-----------|----------|------------|----------|
| --tarih | -t | Son 1 yil | Baslangic:bitis (YYYY-AA-GG:YYYY-AA-GG) |
| --nakit | -n | 100000 | Baslangic nakiti (TL) |
| --komisyon-alis | -ka | 0.00188 | Alis komisyon orani |
| --komisyon-satis | -ks | 0.00188 | Satis komisyon orani |
| --eslestirme | -e | KAPANIS | KAPANIS veya LIMIT |
| --isitma | -i | 0 | Isitma donemi (gun) |
| --risksiz | -r | 0.40 | Risksiz faiz orani (yillik) |
| --sessiz | -s | (yok) | Sadece ozet tabloyu goster |
| --detay | -d | (yok) | Her islemi tek tek goster |
| --kaynak | -k | supabase | supabase, csv, sentetik |

### 8.3 Diger Alt Komutlar

```bash
# Gecmis backtest sonuclarini listele
borsa backtest sonuclar
borsa backtest sonuclar --strateji ornek.sh
borsa backtest sonuclar --son 10

# Belirli bir backtest'in islem detaylarini goster
borsa backtest detay <backtest_id>

# Iki backtest sonucunu karsilastir
borsa backtest karsilastir <id_1> <id_2>

# CSV dosyasindan veri yukle
borsa backtest yukle thyao_2024.csv THYAO

# Sentetik veri uret (test amacli)
borsa backtest sentetik TEST01 100 250 0.02
```

### 8.4 borsa() Fonksiyonuna Ekleme

cekirdek.sh'deki borsa() fonksiyonuna eklenmesi gereken case blogu:

```bash
case "$kurum" in
    kurallar) ... ;;              # mevcut
    gecmis)   ... ;;              # sistem_plani.md Bolum 14.1.4
    mutabakat) ... ;;             # sistem_plani.md Bolum 14.1.4
    backtest) shift; _backtest_yonlendir "$@" ;;   # YENI
    *) # normal kurum yonlendirmesi
esac
```

`_backtest_yonlendir` fonksiyonu backtest/ klasorundeki ilgili fonksiyonu cagirir.

## 9. Dosya Yapisi

Backtest modulu asagidaki dosya yapisina sahip olacak:

```
bashrc.d/borsa/
  backtest_plani.md              # Bu dosya
  backtest/
    motor.sh                     # Ana backtest motoru: dongu, koordinasyon
    portfoy.sh                   # Sanal portfoy yonetimi: nakit, pozisyon
    metrik.sh                    # Performans metrikleri hesaplama
    rapor.sh                     # Sonuc raporlama ve formatlama
    veri.sh                      # Veri yukleme: Supabase, CSV, sentetik
    veri_dogrula.sh              # Veri dogrulama kontrolleri
```

### 9.1 Dosya Sorumluluk Dagitimi

| Dosya | Sorumluluk |
|-------|------------|
| motor.sh | Backtest ana dongusu, strateji yukleme, parametre parse, koordinasyon |
| portfoy.sh | Sanal portfoy olusturma, emir eslestirme, bakiye guncelleme, komisyon |
| metrik.sh | Getiri, Sharpe, Sortino, Calmar, drawdown, basari orani hesaplama |
| rapor.sh | Terminal cikti formatlama, tablo olusturma, Supabase'e sonuc kaydetme |
| veri.sh | Supabase'den okuma, CSV parse, sentetik veri uretme, veri birlestirme |
| veri_dogrula.sh | Veri butunluk kontrolleri, bosluk tespiti, aralik kontrolu |

### 9.2 Dosya Yuklenme Sirasi

motor.sh diger dosyalari source eder:

```bash
# motor.sh basinda
_BACKTEST_DIZIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_BACKTEST_DIZIN/portfoy.sh"
source "$_BACKTEST_DIZIN/metrik.sh"
source "$_BACKTEST_DIZIN/rapor.sh"
source "$_BACKTEST_DIZIN/veri.sh"
source "$_BACKTEST_DIZIN/veri_dogrula.sh"
```

cekirdek.sh backtest/ klasorunu otomatik tanimaz. Backtest komutu
ilk cagrildiginda motor.sh source edilir (lazy loading):

```bash
_backtest_yonlendir() {
    if [[ -z "${_BACKTEST_YUKLENDI:-}" ]]; then
        source "$BORSA_DIZIN/backtest/motor.sh"
        _BACKTEST_YUKLENDI=1
    fi
    backtest_ana "$@"
}
```

## 10. Tab Tamamlama

tamamlama.sh dosyasina (sistem_plani.md Bolum 14.3.2) eklenecek tamamlamalar:

```bash
# borsa backtest <TAB>
# -> strateji/ klasorundeki .sh dosyalari listelenir

# borsa backtest ornek.sh <TAB>
# -> sembol tamamlama (fiyat_gecmisi tablosundaki semboller)

# borsa backtest ornek.sh THYAO --<TAB>
# -> tarih, nakit, komisyon-alis, komisyon-satis, eslestirme, isitma, risksiz, sessiz, detay

# borsa backtest sonuclar --<TAB>
# -> strateji, son

# borsa backtest karsilastir <TAB>
# -> son backtest id'leri
```

## 11. Matematiksel Hesaplamalar ve Bash Sinirlamalari

Bash ondalikli aritmetik desteklemez. Backtest metrikleri icin hassas
hesaplama gerekir. Bu sorun su yaklasimlarla cozulur:

### 11.1 bc Kullanimi

Temel aritmetik (toplama, carpma, bolme, karsilastirma) icin `bc` kullanilir:

```bash
# Ornek: toplam getiri hesaplama
toplam_getiri=$(echo "scale=4; ($bitis_deger - $baslangic) / $baslangic * 100" | bc)

# Ornek: komisyon hesaplama
komisyon=$(echo "scale=2; $lot * $fiyat * $komisyon_orani" | bc)
```

### 11.2 awk Kullanimi

Dizi islemleri (standart sapma, ortalama, Sharpe orani) icin `awk` kullanilir:

```bash
# Ornek: gunluk getirilerin standart sapmasi
std_sapma=$(printf '%s\n' "${gunluk_getiriler[@]}" | awk '{
    sum += $1; sumsq += $1*$1; n++
} END {
    if (n > 1) printf "%.6f", sqrt((sumsq - sum*sum/n) / (n-1))
    else print "0"
}')
```

### 11.3 Bagimlilik Notu

`bc` hemen hemen tum Linux dagitimlarinda varsayilan olarak kurulu gelir.
`awk` (gawk veya mawk) da varsayilan olarak bulunur. Ek bagimlilik gerekmez.
Bu durum sistem_plani.md Bolum 13.2.1'deki sifir bagimlilik ilkesiyle uyumludur.

## 12. Yol Haritasi

Backtest modulu sistem_plani.md Bolum 12'deki yol haritasinin 8. asamasindan
(Strateji Katmani) sonra veya paralel olarak gelistirilebilir.
Asagidaki adimlar kendi icinde siralanmistir.

### 12.1 Adim 1 - Temel Altyapi

backtest/ klasoru ve dosya iskeleti olusturulur.
motor.sh icinde parametre parse fonksiyonu yazilir.
portfoy.sh icinde sanal portfoy array tanimlari ve temel islemler yazilir.
cekirdek.sh'deki borsa() fonksiyonuna backtest case blogu eklenir.
_backtest_yonlendir lazy loading mekanizmasi yazilir.

### 12.2 Adim 2 - Veri Katmani

veri.sh icinde Supabase'den fiyat_gecmisi okuma fonksiyonu yazilir.
veri.sh icinde CSV parse fonksiyonu yazilir.
veri.sh icinde sentetik veri uretme fonksiyonu yazilir.
veri_dogrula.sh icinde tum dogrulama kontrolleri yazilir.
Veri kaynagi secim mantigi (Supabase -> CSV -> sentetik) yazilir.

### 12.3 Adim 3 - Simulasyon Motoru

motor.sh icinde ana dongu yazilir.
portfoy.sh icinde emir eslestirme, komisyon hesabi, pozisyon guncelleme yazilir.
BIST fiyat adimi kontrolu entegre edilir (kurallar/bist.sh).
Tavan/taban kontrolu eklenir.
Bakiye ve pozisyon kontrolleri eklenir.
KAPANIS ve LIMIT eslestirme modelleri yazilir.

### 12.4 Adim 4 - Metrikler ve Raporlama

metrik.sh icinde tum temel, risk ve detay metrikleri yazilir.
rapor.sh icinde terminal cikti formatlama yazilir.
bc ve awk ile hesaplama fonksiyonlari yazilir.
Gunluk portfoy degeri takibi (equity curve verisi) yazilir.

### 12.5 Adim 5 - Veritabani Entegrasyonu

sema.sql dosyasina backtest tablolari eklenir (backtest_sonuclari, backtest_islemleri, backtest_gunluk).
rapor.sh icinde Supabase kayit fonksiyonlari yazilir.
Gecmis sonuclari sorgulama fonksiyonlari yazilir.
Karsilastirma fonksiyonu yazilir.

### 12.6 Adim 6 - Coklu Sembol ve Ileri Ozellikler

Coklu sembol destegi eklenir.
Isitma donemi (walk-forward) destegi eklenir.
Tab tamamlama guncellenir.
Strateji parametreleri destegi eklenir (parametreler JSONB alani).

### 12.7 Adim 7 - Test ve Dogrulama

Bilinen sonuclu bir senaryo ile backtest dogrulanir.
Ornek: "Her gun al, ertesi gun sat" stratejisi ile bilinen bir hissenin
gercek verisi uzerinde beklenen sonuc ile karsilastirilir.
Sentetik veri ile sinir durumlari test edilir:
- Bakiye yetmez durumu
- Sifir lot satisi
- Tavan/taban disinda emir
- Bos veri
- Tek gunluk veri

## 13. Mevcut Planlarla Uyum Tablosu

Bu bolum backtest planinin diger plan dosyalariyla nasil iliskilendigini gosterir.

### 13.1 sistem_plani.md ile Iliskiler

| Sistem Plani Bolumu | Backtest Iliskisi |
|---------------------|-------------------|
| 2. Katmanli Mimari | Backtest katman disinda bagimsiz arac |
| 4. Algoritmik Islem Dongusu | Backtest ayni donguyu gecmis veriyle uygular |
| 10.2 Strateji Arayuzu | Backtest strateji_degerlendir() oldugu gibi kullanir |
| 11.5.7 fiyat_gecmisi | Backtest birincil veri kaynagi |
| 11.8 Hata Toleransi | Backtest ayni hata toleransi ilkesini uygular |
| 12. Yol Haritasi | Backtest Asama 8 sonrasi veya paralel |
| 14.1.4 Kurumsuz komutlar | "backtest" yeni kurumsuz komut olarak eklenir |
| 14.3.1 KURU_CALISTIR | Backtest farkli bur arac, KURU_CALISTIR canli mod |
| 14.3.2 Tab tamamlama | Backtest icin tamamlama eklenir |

### 13.2 veri_katmani_plani.md ile Iliskiler

| Veri Katmani | Backtest Iliskisi |
|-------------|-------------------|
| _BORSA_VERI_HISSE_* array'leri | _BACKTEST_* paralel array'ler (ayri isim alani) |
| sayi_temizle, yuzde_temizle | Backtest ayni yardimci fonksiyonlari kullanir |
| Adaptor callback'leri | Backtest adaptor KULLANMAZ, kendi veri motorunu kullanir |

### 13.3 plan.md ile Iliskiler

| Adaptor Plani | Backtest Iliskisi |
|--------------|-------------------|
| Adaptor endpointleri | Backtest adaptor endpointlerine DOKUNMAZ |
| Emir gonderme | Backtest sanal emir kullanir, gercek emir GONDERMEZ |

## 14. Bilinen Sorunlar ve Riskler

### 14.1 Kritik Sorunlar

#### 14.1.1 Bash Ondalik Aritmetik Siniri

**Sorun:** Bash tam sayi aritmetigi kullanir. Fiyat, komisyon, getiri hesaplamalari
ondalik sayi gerektirir. Her hesaplama icin `bc` veya `awk` cagirilmasi performansi
dusurur (fork + exec her cagri icin).

**Etki:** 250 islem gunu x 5 sembol x 10+ hesaplama = 12.500+ alt proses cagrisi.
Modern donanim icin sorun olmayabilir ama yavas sistemlerde farkedilebilir.

**Cozum:** Kritik iclerin (ana dongu) mumkun oldugunca tek bir awk prosesi icinde
toplu olarak yapilmasi. Tum gunluk verilerin bir awk script'ine pipe edilmesi:

```bash
# Yerine birer birer bc cagirmak:
for gun in ...; do
    getiri=$(echo "..." | bc)    # yavas: N kez fork
done

# Toplu awk islemi:
printf '%s\n' "${fiyatlar[@]}" | awk '
    BEGIN { ... }
    { ... hesaplamalar ... }
    END { ... sonuclari bas ... }
'   # hizli: tek fork
```

**Hangi adimda cozulmeli:** Adim 3 (Simulasyon Motoru).

#### 14.1.2 fiyat_gecmisi Tablosunun Bos Olmasi

**Sorun:** Yeni kurulumlarda fiyat_gecmisi tablosunda hic veri yoktur.
Sistem kullanildikca veri birikir ama bu aylar surebilir.

**Etki:** Backtest calistirilamaz veya cok kisa doneme sinirli kalir.

**Cozum:** CSV yuklem fonksiyonu ile harici kaynaklardan veri yuklenebilir.
Dokumantasyonda ornerilecek ucretsiz veri kaynaklari:
- TCMB EVDS (gecmis kapanislar, gunluk)
- Yahoo Finance CSV indirme (yfinance Python paketi ile)
- Borsaya ozel veri saglayicilar

**Hangi adimda cozulmeli:** Adim 2 (Veri Katmani).

### 14.2 Onemli Sorunlar

#### 14.2.1 Hayatta Kalma Yanliligi (Survivorship Bias)

**Sorun:** Backtest yalnizca bugun borsada islem goren hisseleri test edebilir.
Gecmiste borsadan cikmis (iflas, birlesmis, listelenmemis) hisseler veriye
dahil edilemez. Bu durum sonuclari olumlu yonde saptirabilir.

**Etki:** Backtest sonuclari gercek piyasa performansindan daha iyi gorunur.

**Cozum:** Tamamen onlenemez ama kullaniciya uyari verilir:
- Rapor sonunda `UYARI: Hayatta kalma yanliligi icermektedir` notu.
- Dokuumantasyonda bu sinirlama aciklanir.

#### 14.2.2 Kayma (Slippage) Modeli Yok

**Sorun:** Gercek piyasada buyuk emirler istenen fiyattan degil, daha kotu
bir fiyattan eslesibelir (ozellikle dusuk hacimli hisselerde). Backtest
motorunda bu etki modellenmez.

**Etki:** Backtest sonuclari gercek performanstan daha iyi gorunur.

**Cozum:** Ileride kayma modeli eklenebilir:
- Sabit kayma: her emre +/- N kurus ekleme
- Hacim bazli kayma: dusuk hacimde daha fazla kayma
- Baslangicta bu ozellik eklenmez, gelecege birakilir.

#### 14.2.3 Gunu Icinde Islem (Intraday) Destegi Yok

**Sorun:** Backtest gunluk kapanis verileri uzerinde calisir. Gun icinde
birden fazla islem yapan stratejiler (scalping, day trading) dogru
sekilde test edilemez.

**Etki:** Gun ici stratejiler kullanilmaz.

**Cozum:** Veri kaynagi gun ici destegi saglarsa (fiyat_gecmisi tablosu
zaten anlik kayitlar icerebilir) ileri asamada eklenebilir. Baslangicta
sadece gunluk kapanis verisi desteklenir.

### 14.3 Orta Sorunlar

#### 14.3.1 Strateji Arayuzu Henuz Kesinlesmemis

**Sorun:** sistem_plani.md Bolum 14.2.6'da belirtildigi gibi strateji arayuzu
henuz kesin degil. Backtest bu arayuze bagimlidir.

**Cozum:** Strateji arayuzu (sistem_plani.md Asama 8) kesinlesince backtest
modulu buna uyumlu hale getirilir. Mevcut plandaki ornek arayuz
(Bolum 10.2.1) uzerinden ilerlenebilir.

**Hangi adimda cozulmeli:** Adim 1 oncesinde veya Adim 1 ile birlikte.

#### 14.3.2 Coklu Sembol Tarih Hizalama

**Sorun:** Farkli semboller farkli tarihlerde isleme kapanabilir (islem yasagi,
borsadan gecici cikarilma). Coklu sembol backtest'inde tarihlerin hizanmasi
gerekir.

**Cozum:** Tum sembollerde ortak olan tarihler kullanilir. Bir sembolde veri
olmayan gun icin o sembol atlanir (diger semboller islenir).

### 14.4 Sorun Ozet Tablosu

| No | Oncelik | Sorun | Adim |
|----|---------|-------|------|
| 14.1.1 | Kritik | Bash ondalik aritmetik siniri | Adim 3 |
| 14.1.2 | Kritik | fiyat_gecmisi tablosu bos | Adim 2 |
| 14.2.1 | Onemli | Hayatta kalma yanliligi | Dokumantasyon |
| 14.2.2 | Onemli | Kayma modeli yok | Gelecek |
| 14.2.3 | Onemli | Gun ici islem destegi yok | Gelecek |
| 14.3.1 | Orta | Strateji arayuzu kesinlesmemis | Adim 1 |
| 14.3.2 | Orta | Coklu sembol tarih hizalama | Adim 6 |
