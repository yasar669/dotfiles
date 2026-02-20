# Borsa Modulu - Plan

## 1. Genel Bakis

Bu modul BIST (Borsa Istanbul) hisse senedi islemlerini terminalden yonetmeyi saglar.
Tum altyapi saf Bash + curl ile calisir, dis bagimliligi yoktur (Python, Selenium vs. kullanilmaz).
bashrc.d/ klasorunde bulundugu icin her terminal acildiginda otomatik yuklenir.

## 2. Mevcut Durum

Sistem uc katmandan olusur: cekirdek altyapi, BIST kural motoru ve kurum adaptorleri.

### 2.1 Klasor Yapisi

```
bashrc.d/borsa/
  cekirdek.sh              # Jenerik altyapi (HTTP, oturum, yonlendirme)
  tamamlama.sh             # Bash TAB completion
  plan.md                  # Bu dosya
  kurallar/
    bist.sh                # BIST Pay Piyasasi kural motoru
  adaptorler/
    ziraat.sh              # Ziraat Yatirim adaptoru
    ziraat.ayarlar.sh      # Ziraat URL ve secici ayarlari
    sablon.sh              # Yeni adaptor sablonu
    sablon.ayarlar.sh      # Yeni adaptor ayar sablonu
```

### 2.2 Tamamlanan Islevler

| Islev | Komut | Durum |
|-------|-------|-------|
| Giris (SMS dogrulama dahil) | borsa ziraat giris | Tamam |
| Bakiye/Portfoy sorgulama | borsa ziraat bakiye | Tamam |
| Emir gonderme (limit) | borsa ziraat emir SEMBOL alis/satis LOT FIYAT | Tamam |
| Emir listeleme | borsa ziraat emirler | Tamam |
| Emir iptal | borsa ziraat iptal EMIR_ID | Tamam |
| Coklu hesap yonetimi | borsa ziraat hesap/hesaplar | Tamam |
| BIST fiyat adimi dogrulama | Emir oncesi otomatik | Tamam |
| Seans disi minimum tutar (Ziraat) | Emir oncesi otomatik | Tamam |
| Tab tamamlama | borsa TAB | Tamam |
| BIST kural sorgulama | borsa kurallar seans/fiyat/tavan/taban | Tamam |

### 2.3 Eksik Islevler

| Islev | Engel | Oncelik |
|-------|-------|---------|
| Tavan/taban fiyat kontrolu | Canli fiyat verisi lazim | Yuksek |
| Alis gucu / satilabilir lot kontrolu | Veri lazim | Yuksek |
| Sembol dogrulama | Veri lazim | Orta |
| Canli fiyat gosterme | Veri lazim | Orta |
| Portfoy detay (hisse bazli) | HTML parse lazim | Dusuk |
| Oturum kapatma (cikis) | Endpoint biliniyor | Dusuk |

## 3. Veri Cekme Mimarisi

Ziraat Yatirim'in web arayuzu AJAX ile JSON veri cekerken kullandigi endpointler kesfedildi.
Bu endpointler oturum acikken curl ile de cagrilabilir.

### 3.1 Kesfedilen Endpointler

Asagidaki endpointler emir sayfasi HTML ve JavaScript kodu analiz edilerek belirlendi.

#### 3.1.1 Hisse Bilgi Sorgulama (En Kritik)

Endpoint: /sanalsube/tr/Equity/JsonGetEquityInformation

```
Metot  : POST
Girdi  : { code: "THYAO", valueDate: "20.02.2026", transactionTypeName: "LOT", isFinInstId: false }
Cikti  : {
  InfoEQ: {
    Code, FinistId, Group,
    LastPrice,                    # Son fiyat
    BidPrice, AskPrice,           # Alis/Satis fiyati
    AvgPrice,                     # Ortalama fiyat
    HighPrice, LowPrice,          # Gun ici en yuksek/en dusuk
    UpperLimit, LowerLimit,       # Tavan / Taban
    Change,                       # Yuzde degisim
    TradingSessionDesc,           # Seans durumu metni
    MaxLot, CollateralRate,       # Maksimum lot, teminat orani
    EquityTradeLimit              # Islem limiti
  }
}
```

Bu tek endpoint ile tavan/taban kontrolu, canli fiyat gosterme ve seans durumu bilgisi saglanir.

#### 3.1.2 Alis Gucu / Satilabilir Lot

Endpoint: /sanalsube/tr/Equity/JsonGetEquityTradeLimit

```
Metot  : GET
Girdi  : ?finistId=<FinistId>  (3.1.1'den alinir)
Cikti  : {
  Data: {
    EquityTradeLimit,             # Alis gucu (TL)
    SellUnit                      # Satilabilir lot miktari
  }
}
```

Bu endpoint ile emir gondermeden once "paraniz yetmiyor" veya "elinizde bu kadar hisse yok" uyarisi verilebilir.

#### 3.1.3 Sembol Arama / Dogrulama

Endpoint: /sanalsube/tr/Equity/FindEquityOrViopCodeAutoComplete

```
Metot  : GET
Girdi  : ?subMarketName=F&type=EQ&query=THY
Cikti  : [ { value: "THYAO", data: { id: "...", category: "..." } }, ... ]
```

Bu endpoint ile yanlis sembol girildiginde uyari verilebilir ve TAB ile sembol tamamlama yapilabilir.

#### 3.1.4 Diger Bilinen Endpointler

| Endpoint | Amac | Oncelik |
|----------|------|---------|
| /Account/LogOff | Oturum kapatma | Dusuk |
| /Equity/ListCharacteristic | Kiymet ozellikleri listesi | Dusuk |
| /Reports/CashAccountTransactions | Hesap hareketleri | Gelecek |
| /Reports/EQTransactionVolumeDetails | Islem hacim detayi | Gelecek |

### 3.2 Veri Akis Semalari

Mevcut emir gonderme akisi:

```
kullanici -> fiyat adimi kontrolu -> seans disi tutar kontrolu -> POST emir -> sunucu yaniti
```

Hedef emir gonderme akisi:

```
kullanici -> fiyat adimi kontrolu -> seans disi tutar kontrolu
          -> JsonGetEquityInformation (tavan/taban, son fiyat)
          -> tavan/taban kontrolu
          -> JsonGetEquityTradeLimit (alis gucu / satilabilir lot)
          -> bakiye/lot yeterlilik kontrolu
          -> POST emir -> sunucu yaniti
```

### 3.3 Tasarim Kararlari

Veri cekme katmani saf adaptor isidir (Ziraat'e ozgu). Cekirdek'e eklenmez.
Her adaptor kendi veri cekme fonksiyonlarini yazabilir, arayuz zorunlulugu yoktur.

Veri cekme fonksiyonlari soyle adlandirilir:

```
_ziraat_hisse_bilgi_al <sembol>          # JsonGetEquityInformation wrapper
_ziraat_alis_gucu_al <finistid>          # JsonGetEquityTradeLimit wrapper
_ziraat_sembol_ara <sorgu>               # FindEquityOrViopCodeAutoComplete wrapper
```

JSON parse icin jq tercih edilir. jq yoksa grep/sed ile fallback yapilir.

## 4. Yol Haritasi

### 4.1 Asama 1 - Hisse Bilgi Sorgulama

JsonGetEquityInformation endpointine curl ile POST atilir.
JSON yanitindan LastPrice, UpperLimit, LowerLimit, TradingSessionDesc parse edilir.
Yeni komut eklenir: borsa ziraat fiyat SEMBOL

```
borsa ziraat fiyat THYAO
  THYAO - Son: 312.50 TL | Tavan: 343.75 | Taban: 281.25 | Degisim: %1.34
```

### 4.2 Asama 2 - Emir Oncesi Tavan/Taban Kontrolu

adaptor_emir_gonder icinde hisse bilgi sorgusu cagrilir.
Emir fiyati tavan ustunde veya taban altindaysa emir engellenir, net hata verilir.

```
HATA: Fiyat tavan ustunde. THYAO tavan: 343.75 TL, girilen: 350.00 TL
HATA: Fiyat taban altinda. THYAO taban: 281.25 TL, girilen: 250.00 TL
```

### 4.3 Asama 3 - Alis Gucu ve Lot Kontrolu

JsonGetEquityTradeLimit endpointi cagrilir.
Alis emirlerinde: emir tutari > alis gucu ise uyari.
Satis emirlerinde: emir lotu > satilabilir lot ise uyari.

```
HATA: Yetersiz bakiye. Alis gucu: 5.230 TL, emir tutari: 10.000 TL
HATA: Yetersiz lot. Satilabilir: 50 lot, girilen: 100 lot
```

### 4.4 Asama 4 - Sembol Dogrulama

FindEquityOrViopCodeAutoComplete endpointi ile sembol gecerliligi kontrol edilir.
Gecersiz sembol girildiginde yakin eslesme onerilir.

```
HATA: 'THYA' sembol bulunamadi. Bunu mu demek istediniz: THYAO
```

### 4.5 Asama 5 - Canli Fiyat ve Piyasa Durumu

borsa ziraat fiyat komutu genisletilir.
Birden fazla sembol destegi, watch modu (periyodik yenileme) eklenir.
Portfoy icerisindeki hisseler icin toplu fiyat sorgulama yapilir.

```
borsa ziraat fiyat THYAO AKBNK GARAN
borsa ziraat fiyat THYAO --canli          # Her 5 saniyede guncelle
borsa ziraat portfoy --detay              # Portfoydeki hisselerin canli fiyatlari
```

## 5. Dis Bagimliliklar

| Paket | Amac | Zorunlu mu |
|-------|------|------------|
| curl | HTTP istekleri | Evet (zaten kullaniliyor) |
| bc | Ondalikli sayi islemleri | Evet (zaten kullaniliyor) |
| jq | JSON parse | Hayir (yoksa grep/sed fallback) |
| grep -P | Perl regex (PCRE) | Evet (zaten kullaniliyor) |

## 6. Guvenlik

Kullanici bilgileri (musteri no, sifre) repoya konmaz.
Oturum cerezi /tmp/borsa/ziraat/<musteri_no>/cookies.txt icinde tutulur.
/tmp dizini reboot ile temizlenir, ek onlem gerekmez.
API anahtari veya kalici kimlik bilgisi saklanmaz, her seferinde giris yapilir.
