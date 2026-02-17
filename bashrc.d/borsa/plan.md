# Borsa Modulu - Plan

## 1. Genel Bakis

Bu modul tum borsa islemlerini terminalden yonetmeyi saglar.
bashrc.d/ klasorunde bulundugu icin her terminal acildiginda otomatik yuklenir.
GitHub'da tutuldugu icin herhangi bir bilgisayarda git pull ile hemen kullanima hazir hale gelir.

## 2. Klasor Yapisi

```
bashrc.d/
├── 04-borsa.sh                  # Ana modul (tum alt modulleri yukler)
└── borsa/
    ├── plan.md                  # Bu dosya
    ├── ayar.sh                  # API anahtarlari, genel yapilandirma
    ├── yardimci.sh              # Ortak fonksiyonlar (renk, log, format)
    ├── kripto/
    │   ├── binance.sh           # Binance API (curl + jq)
    │   ├── okx.sh               # OKX API (curl + jq)
    │   └── ortak_kripto.sh      # Ortak kripto fonksiyonlari
    ├── tr_borsa/
    │   ├── ziraat.sh            # Ziraat Yatirim (web scrape)
    │   ├── osmanli.sh           # Osmanli Yatirim (web scrape)
    │   ├── akbank.sh            # Akbank Yatirim
    │   └── isbank.sh            # Is Bankasi Yatirim
    └── strateji/
        ├── freqtrade_yonet.sh   # Freqtrade baslat/durdur/test
        └── sinyal.sh            # Alim-satim sinyal sistemi
```

## 3. Mimari

Bash her seyi yonetir, agir isi Python'a devreder.

| Katman | Arac | Aciklama |
|--------|------|----------|
| Bash (yonetim) | curl, jq, openssl | API cagrisi, sonuc okuma, komut arayuzu |
| Python (hesaplama) | ccxt, selenium, pandas | Karmasik analiz, web scraping, ML |
| Freqtrade (algo) | freqtrade framework | Otomatik alim-satim botlari |

### 3.1 Ornek Akis

```
borsa_bakiye binance         -> curl ile Binance API -> jq ile parse -> terminale yaz
borsa_bakiye ziraat          -> python3 scraper -> sonucu bash'e dondur
borsa_emir binance al BTC 100 -> curl ile API cagrisi
borsa_strateji baslat fisher -> freqtrade calistir
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

ayar.sh bu dosyayi source eder. Repo sadece fonksiyonlari tutar.

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
