# Borsa Modulu - Plan

## 1. Genel Bakis

Bu modul tum borsa islemlerini terminalden yonetmeyi saglar.
bashrc.d/ klasorunde bulundugu icin her terminal acildiginda otomatik yuklenir.
GitHub'da tutuldugu icin herhangi bir bilgisayarda git pull ile hemen kullanima hazir hale gelir.

## 2. Klasor Yapisi

```
bashrc.d/
├── 04-borsa.sh                  # Ana modul (adapter yonetici, tum alt modulleri yukler)
└── borsa/
    ├── plan.md                  # Bu dosya
    ├── ayar.sh                  # API anahtarlari, genel yapilandirma
    ├── yardimci.sh              # Ortak fonksiyonlar (renk, log, format)
    ├── borsalar/
    │   ├── binance.sh           # Binance adapter (curl + jq)
    │   ├── okx.sh               # OKX adapter (curl + jq)
    │   ├── ziraat.sh            # Ziraat Yatirim adapter (python + selenium)
    │   ├── osmanli.sh           # Osmanli Yatirim adapter (python + selenium)
    │   ├── akbank.sh            # Akbank Yatirim adapter (python + selenium)
    │   └── isbank.sh            # Is Bankasi Yatirim adapter (python + selenium)
    └── strateji/
        ├── freqtrade_yonet.sh   # Freqtrade baslat/durdur/test
        └── sinyal.sh            # Alim-satim sinyal sistemi
```

## 3. Mimari

Bash her seyi yonetir, agir isi Python'a devreder. Tum borsalar adapter kalibini kullanir.

| Katman | Arac | Aciklama |
|--------|------|----------|
| Bash (yonetim) | curl, jq, openssl | API cagrisi, sonuc okuma, komut arayuzu |
| Python (hesaplama) | ccxt, selenium, pandas | Karmasik analiz, web scraping, ML |
| Freqtrade (algo) | freqtrade framework | Otomatik alim-satim botlari |

### 3.1 Adapter Kalibi

Her borsa dosyasi ayni fonksiyon arayuzunu uygulamak zorundadir. 04-borsa.sh yonetici katmani, borsa adina gore dinamik fonksiyon cagrisi yapar.

Her adapter su fonksiyonlari tanimlar:

| Fonksiyon | Aciklama |
|-----------|----------|
| BORSA_bakiye_al | Hesap bakiyesini getirir |
| BORSA_fiyat_al | Sembol fiyatini sorgular |
| BORSA_emir_ver | Alim/satim emri gonderir |
| BORSA_emir_iptal | Acik emri iptal eder |
| BORSA_emirler | Acik emirleri listeler |

### 3.2 Baglanti Yontemleri

Borsalarin hepsinin API'si yok. Her adapter kendi baglanti yontemini bilir, yonetici katman bunu umursamaz.

| Borsa | API Durumu | Baglanti Yontemi |
|-------|-----------|-----------------|
| Binance | Acik REST API | curl + jq + openssl (HMAC imza) |
| OKX | Acik REST API | curl + jq + openssl (HMAC imza) |
| Ziraat | API yok | Bash + Curl (Reverse Engineering) |
| Osmanli | API yok | Bash + Curl (Reverse Engineering) |
| Akbank | API yok | Bash + Curl (Reverse Engineering) |
| Is Bankasi | API yok | Bash + Curl (Reverse Engineering) |

API olan borsalarda adapter API dokumantasyonuna gore calisir. API olmayanlarda ise web trafigi taklit edilerek (reverse engineering) curl ile islem yapilir. HTML parse icin grep/sed/pup, JSON icin jq kullanilir.

### 3.3 Ornek Akis

```
borsa_bakiye binance   -> binance_bakiye_al() -> curl ile Binance REST API -> jq ile parse -> terminale yaz
borsa_bakiye ziraat    -> ziraat_bakiye_al()  -> python3 scraper calistir  -> ciktiyi oku  -> terminale yaz
borsa_emir okx al BTC  -> okx_emir_ver()      -> curl ile OKX REST API    -> jq ile parse -> terminale yaz
borsa_fiyat akbank     -> akbank_fiyat_al()   -> python3 scraper calistir  -> ciktiyi oku  -> terminale yaz
```

## 4. Dis Bagimliliklar

| Paket | Amac | Kurulum |
|-------|------|---------|
| curl | API cagrisi | Genelde yuklu gelir |
| jq | JSON parse | sudo apt install jq |
| openssl | HMAC imzalama | Genelde yuklu gelir |
| python3 | Scraping ve analiz | Genelde yuklu gelir |
| ccxt (python) | Kripto borsa kutuphanesi | pip install ccxt |
| selenium (python) | Web scraping | pip install selenium |
| freqtrade | Algoritmik ticaret | pip install freqtrade |

## 5. Guvenlik

API anahtarlari repoya konmaz. Her bilgisayarda yerel dosya olusturulur.

| Dosya | Konum | Icerik |
|-------|-------|--------|
| .borsa_anahtarlar | ~/.borsa_anahtarlar | API key ve secret degerleri |
| .gitignore | repo koku | .borsa_anahtarlar satirini icerir |

ayar.sh, bashrc tarafindan otomatik yuklenir ve icinde ~/.borsa_anahtarlar dosyasini source ederek gizli API bilgilerini belleğe alir. Repo sadece fonksiyonlari tutar, anahtarlar repoya girmez.

## 6. Komut Listesi

### 6.1 Bakiye Sorgulama

```
borsa_bakiye binance         # Binance bakiyesi
borsa_bakiye okx             # OKX bakiyesi
borsa_bakiye ziraat          # Ziraat Yatirim bakiyesi
borsa_bakiye hepsi           # Tum borsalardaki bakiyeler
```

### 6.2 Emir Verme

```
borsa_emir binance al BTC/USDT 0.001
borsa_emir okx sat ETH/USDT 0.5
borsa_emir binance iptal EMIR_ID
```

### 6.3 Fiyat Takip

```
borsa_fiyat BTC              # Tum borsalardaki BTC fiyati
borsa_fiyat THYAO            # Turk borsasindaki THYAO
borsa_fiyat ETH --canli      # Canli fiyat akisi
```

### 6.4 Strateji Yonetimi

```
borsa_strateji test fisher BTC/USDT    # Backtest calistir
borsa_strateji baslat fisher           # Canli bot baslat
borsa_strateji durdur fisher           # Botu durdur
borsa_strateji durum                   # Aktif botlari goster
```

### 6.5 Portfoy Ozeti

```
borsa_portfoy                # Tum borsalardaki toplam varlik
borsa_portfoy --detay        # Borsalara gore dagilim
borsa_portfoy --gecmis 30    # Son 30 gunluk performans
```

## 7. Yol Haritasi

### 7.1 Asama 1 - Temel Iskelet

04-borsa.sh ana modulu, borsa/ayar.sh yapilandirma, borsa/yardimci.sh ortak fonksiyonlar ve bagimlilk kontrolu (jq, curl, openssl) olusturulacak.

### 7.2 Asama 2 - Binance Entegrasyonu

HMAC imzalama fonksiyonu, bakiye sorgulama, fiyat sorgulama ve emir verme (al/sat/iptal) yazilacak.

### 7.3 Asama 3 - OKX Entegrasyonu

OKX API imzalama, bakiye/emir fonksiyonlari ve fiyat sorgulama eklenecek.

### 7.4 Asama 4 - Turk Borsalari

Ziraat Yatirim, Osmanli Yatirim, Akbank ve Is Bankasi icin selenium tabanli scraper yazilacak.

### 7.5 Asama 5 - Strateji ve Otomasyon

Freqtrade entegrasyonu, sinyal sistemi ve portfoy takip/raporlama eklenecek.
