# Borsa Modulu - Plan

## Genel Bakis

Bu modul tum borsa islemlerini terminalden yonetmeyi saglar.
bashrc.d/ klasorunde bulundugu icin her terminal acildiginda otomatik yuklenir.
GitHub'da tutuldugu icin herhangi bir bilgisayarda git pull ile hemen kullanima hazir hale gelir.

## Klasor Yapisi

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

## Mimari

Bash her seyi yonetir, agir isi Python'a devreder.

| Katman | Arac | Aciklama |
|--------|------|----------|
| Bash (yonetim) | curl, jq, openssl | API cagrisi, sonuc okuma, komut arayuzu |
| Python (hesaplama) | ccxt, selenium, pandas | Karmasik analiz, web scraping, ML |
| Freqtrade (algo) | freqtrade framework | Otomatik alim-satim botlari |

Ornek akis:

```
borsa_bakiye binance         -> curl ile Binance API -> jq ile parse -> terminale yaz
borsa_bakiye ziraat          -> python3 scraper -> sonucu bash'e dondur
borsa_emir binance al BTC 100 -> curl ile API cagrisi
borsa_strateji baslat fisher -> freqtrade calistir
```

## Dis Bagimlilklar

| Paket | Amac | Kurulum |
|-------|------|---------|
| curl | API cagrisi | Genelde yuklu gelir |
| jq | JSON parse | sudo apt install jq |
| openssl | HMAC imzalama | Genelde yuklu gelir |
| python3 | Scraping ve analiz | Genelde yuklu gelir |
| ccxt (python) | Kripto borsa kutuphanesi | pip install ccxt |
| selenium (python) | Web scraping | pip install selenium |
| freqtrade | Algoritmik ticaret | pip install freqtrade |

## Guvenlik

API anahtarlari repoya konmaz. Her bilgisayarda yerel dosya olusturulur.

| Dosya | Konum | Icerik |
|-------|-------|--------|
| .borsa_anahtarlar | ~/.borsa_anahtarlar | API key ve secret degerleri |
| .gitignore | repo koku | .borsa_anahtarlar satirini icerir |

ayar.sh bu dosyayi source eder. Repo sadece fonksiyonlari tutar.

## Komut Listesi

### Bakiye Sorgulama

```
borsa_bakiye binance         # Binance bakiyesi
borsa_bakiye okx             # OKX bakiyesi
borsa_bakiye ziraat          # Ziraat Yatirim bakiyesi
borsa_bakiye hepsi           # Tum borsalardaki bakiyeler
```

### Emir Verme

```
borsa_emir binance al BTC/USDT 0.001
borsa_emir okx sat ETH/USDT 0.5
borsa_emir binance iptal EMIR_ID
```

### Fiyat Takip

```
borsa_fiyat BTC              # Tum borsalardaki BTC fiyati
borsa_fiyat THYAO            # Turk borsasindaki THYAO
borsa_fiyat ETH --canli      # Canli fiyat akisi
```

### Strateji Yonetimi

```
borsa_strateji test fisher BTC/USDT    # Backtest calistir
borsa_strateji baslat fisher           # Canli bot baslat
borsa_strateji durdur fisher           # Botu durdur
borsa_strateji durum                   # Aktif botlari goster
```

### Portfoy Ozeti

```
borsa_portfoy                # Tum borsalardaki toplam varlik
borsa_portfoy --detay        # Borsalara gore dagilim
borsa_portfoy --gecmis 30    # Son 30 gunluk performans
```

## Yol Haritasi

### Asama 1 - Temel Iskelet

04-borsa.sh ana modulu, borsa/ayar.sh yapilandirma, borsa/yardimci.sh ortak fonksiyonlar ve bagimlilk kontrolu (jq, curl, openssl) olusturulacak.

### Asama 2 - Binance Entegrasyonu

HMAC imzalama fonksiyonu, bakiye sorgulama, fiyat sorgulama ve emir verme (al/sat/iptal) yazilacak.

### Asama 3 - OKX Entegrasyonu

OKX API imzalama, bakiye/emir fonksiyonlari ve fiyat sorgulama eklenecek.

### Asama 4 - Turk Borsalari

Ziraat Yatirim, Osmanli Yatirim, Akbank ve Is Bankasi icin selenium tabanli scraper yazilacak.

### Asama 5 - Strateji ve Otomasyon

Freqtrade entegrasyonu, sinyal sistemi ve portfoy takip/raporlama eklenecek.
