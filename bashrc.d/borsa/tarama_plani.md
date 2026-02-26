# Tarama Modulu - Plan

## 1. Amac

Robot baslatilirken hangi hisselerin izlenecegi kullanici tarafindan belirlenir.
Sembol listesi strateji dosyasina gomulu degildir. Strateji sadece karar verir, neyi izleyecegini bilmez.
Bu belge sembol secim yontemlerini, tarama altyapisini ve motor entegrasyonunu tanimlar.

## 2. Mevcut Durum ve Sorun

Simdi semboller strateji dosyasinin icerisinde sabit olarak tanimli:

```bash
# strateji/ornek.sh (mevcut — yanlis)
STRATEJI_SEMBOLLER=("THYAO" "AKBNK" "GARAN")
```

Bu tasarimin sorunlari:

- Ayni strateji farkli hisse gruplariyla calistirilamaz.
- Her hisse grubu icin ayri strateji dosyasi kopyalamak gerekir.
- Kullanici strateji kodunu duzenlemeden sembol degistiremez.
- Portfoydeki veya endeksteki hisselerle otomatik calisma mumkun degil.

## 3. Hedef Tasarim

### 3.1 Temel Ilke

Sembol listesi robot baslatma aninda dis kaynaktan gelir. Strateji dosyasi sembol tanimlamaz.
Motor sembolleri alir, strateji fonksiyonuna tek tek iletir.

```
robot_baslat --semboller THYAO,AKBNK ziraat 123 strateji.sh
robot_baslat --liste bist30 ziraat 123 strateji.sh
robot_baslat --portfoy ziraat 123 strateji.sh
robot_baslat --dosya /yol/hisselerim.txt ziraat 123 strateji.sh
```

### 3.2 Sembol Kaynaklari

Dort farkli kaynaktan sembol alinabilir. Oncelik sirasi: CLI > dosya > liste > portfoy.

| Kaynak | Parametre | Aciklama |
|--------|-----------|----------|
| Dogrudan | `--semboller THYAO,AKBNK,GARAN` | Virgul ile ayrilmis sembol listesi |
| Dosya | `--dosya /yol/hisselerim.txt` | Her satirda bir sembol olan metin dosyasi |
| Endeks listesi | `--liste bist30` | Onceden hazirlanmis endeks dosyalari |
| Portfoy | `--portfoy` | Hesaptaki mevcut pozisyonlardan otomatik okunur |

### 3.3 Oncelik ve Birlesim

- Birden fazla kaynak ayni anda verilebilir. Listeler birlestirilerek tekrarlar silinir.
- Ornek: `--portfoy --semboller THYAO` dediginde portfoydeki hisseler + THYAO birlikte izlenir.
- Hicbir kaynak verilmezse robot baslamaz ve hata mesaji gosterir.

## 4. Klasor Yapisi

```
tarama/
  fiyat_kaynagi.sh          # Mevcut — fiyat cekme, onbellek, failover
  tarayici.sh               # Yeni — sembol kaynagi cozumleme, dogrulama
  endeksler/
    bist30.txt              # BIST-30 bilesenleri (30 sembol)
    bist100.txt             # BIST-100 bilesenleri (100 sembol)
    bist_tem.txt            # BIST Temettuu endeksi
    bist_banka.txt          # BIST Banka endeksi
    favori.txt              # Kullanicinin kendi listesi (ornek)
```

Endeks dosya formati (her satirda bir sembol, # ile yorum):

```
# BIST-30 Bilesenleri (Ocak 2026 donemi)
# Guncelleme: 2026-01-02
THYAO
AKBNK
GARAN
EREGL
SISE
KCHOL
TUPRS
ASELS
BIMAS
YKBNK
SAHOL
TAVHL
TOASO
FROTO
SASA
KOZAL
PETKM
TCELL
HEKTS
EKGYO
PGSUS
KONTR
DOHOL
TTKOM
MGROS
GESAN
OYAKC
ENKAI
CIMSA
AKSEN
```

## 5. Fonksiyon Tasarimi

### 5.1 tarayici.sh - Sembol Kaynagi Cozumleme

```
tarayici_sembolleri_coz <parametreler...>
```

Bu fonksiyon robot_baslat'a verilen parametreleri isler ve temiz bir sembol listesi dondurur.
stdout'a her satirda bir sembol yazar. Motor bu ciktiyi STRATEJI_SEMBOLLER dizisine yukler.

Alt fonksiyonlar:

| Fonksiyon | Gorev |
|-----------|-------|
| `_tarayici_dogrudan_parse` | `--semboller A,B,C` virgul ayirmasi, buyuk harfe cevirme |
| `_tarayici_dosya_oku` | `--dosya yol` satirlari okur, yorum ve bos satirlari atlar |
| `_tarayici_endeks_oku` | `--liste bist30` endeksler dizininden ilgili dosyayi bulur |
| `_tarayici_portfoy_oku` | `--portfoy` adaptor_portfoy ciktisini parse eder, sembolleri cikarir |
| `_tarayici_dogrula` | Sembolun gecerli BIST koduna benzeyip benzemedigini kontrol eder |
| `_tarayici_tekrarlari_sil` | Birden fazla kaynaktan gelen listeleri birlestirip tekrarlari siler |

### 5.2 motor.sh Degisiklikleri

Mevcut `robot_baslat` fonksiyonu degisir:

Eski imza:
```
robot_baslat [--kuru] <kurum> <hesap> <strateji.sh> [aralik]
```

Yeni imza:
```
robot_baslat [--kuru] [--semboller X,Y] [--liste ad] [--dosya yol] [--portfoy] <kurum> <hesap> <strateji.sh> [aralik]
```

Motor sembolleri cozumledikten sonra `STRATEJI_SEMBOLLER` dizisini kendisi doldurur.
Strateji dosyasinda bu dizi artik tanimlanmaz. Strateji sadece `strateji_degerlendir` fonksiyonu sunar.

### 5.3 Strateji Arayuz Degisikligi

Eski (strateji dosyasinda sembol tanimli):
```bash
STRATEJI_SEMBOLLER=("THYAO" "AKBNK")    # kaldirilacak
strateji_degerlendir() { ... }
```

Yeni (strateji dosyasinda sembol yok, sadece karar mantigi):
```bash
strateji_degerlendir() {
    local sembol="$1"
    local fiyat="$2"
    # ... karar mantigi ...
    echo "ALIS 100 312.50"
}
```

Geriye uyumluluk: Strateji dosyasinda hala STRATEJI_SEMBOLLER tanimlanmissa ve dis kaynak verilmemisse,
motor bu diziyi kullanir. Boylece eski strateji dosyalari kirilmaz.

## 6. Calisma Akisi

### 6.1 Baslatma Aninda

```
Kullanici: robot_baslat --liste bist30 --kuru ziraat 123 ornek.sh
                |
                v
      [1] Parametreleri parse et
          --liste bist30 algilandi
                |
                v
      [2] tarayici_sembolleri_coz --liste bist30
          endeksler/bist30.txt dosyasini okur
          30 sembol dondurur
                |
                v
      [3] STRATEJI_SEMBOLLER dizisine yukle
          STRATEJI_SEMBOLLER=("THYAO" "AKBNK" ... "AKSEN")
                |
                v
      [4] Strateji dosyasini source et (ornek.sh)
          strateji_degerlendir fonksiyonu tanimlanir
                |
                v
      [5] Ana donguye gir
          Her turda 30 sembolun fiyatini cek
          Her sembol icin strateji_degerlendir cagir
```

### 6.2 Portfoy Modu

```
Kullanici: robot_baslat --portfoy ziraat 123 ornek.sh
                |
                v
      [1] adaptor_portfoy ciktisini al
          BESTE  100 lot  31.46 TL
          NETCD   50 lot 106.00 TL
          QNBFK  200 lot  55.10 TL
                |
                v
      [2] Sembol sutununu cikart
          STRATEJI_SEMBOLLER=("BESTE" "NETCD" "QNBFK")
                |
                v
      [3] Ana donguye gir
```

### 6.3 Karisik Kaynak

```
Kullanici: robot_baslat --portfoy --semboller THYAO,AKBNK ziraat 123 ornek.sh
                |
                v
      [1] Portfoyden: BESTE, NETCD, QNBFK
                |
      [2] Dogrudan: THYAO, AKBNK
                |
                v
      [3] Birlestir + tekrar sil
          STRATEJI_SEMBOLLER=("BESTE" "NETCD" "QNBFK" "THYAO" "AKBNK")
```

## 7. Endeks Dosyasi Yonetimi

### 7.1 Guncelleme

BIST endeks bilesimleri yilda 4 kez degisir (Ocak, Nisan, Temmuz, Ekim).
Endeks dosyalari elle guncellenir. BIST duyurularindan alinir.

Guncelleme adresleri:
- BIST-30/100 bilesimleri: borsaistanbul.com/tr/sayfa/165/bist-30-pay-endeksi
- BIST Temettuu: borsaistanbul.com/tr/sayfa/2720/bist-temettuu-25-endeksi
- Sektorel endeksler: borsaistanbul.com/tr/sayfa/164/bist-sektorel-endeksler

### 7.2 Kullanici Listesi

Kullanici kendi dosyasini olusturabilir:

```bash
# Dosya: tarama/endeksler/favori.txt
# veya: ~/.config/borsa/favori.txt
THYAO
BESTE
NETCD
```

Kullanim: `robot_baslat --liste favori ziraat 123 ornek.sh`

Sistem once `tarama/endeksler/` altinda arar, bulamazsa `~/.config/borsa/` altinda arar.

## 8. Dogrulama Kurallari

Sembol dogrulama asagidaki kontrolleri yapar:

- Bos veya sadece bosluk olan satirlar atlanir.
- `#` ile baslayan satirlar yorum olarak atlanir.
- Sembol 1-6 karakter uzunlugunda, sadece buyuk harf ve rakam icermelidir.
- Kucuk harfle yazilmissa otomatik buyuk harfe cevrilir.
- Gecersiz semboller uyari ile loglanir, diger semboller islemeye devam eder.
- Sonuc listesi bos kalirsa robot baslamaz ve hata doner.

## 9. Uygulama Adimlari

### 9.1 Adim 1: tarayici.sh Olustur

- `tarama/tarayici.sh` dosyasi olusturulur.
- `tarayici_sembolleri_coz` ana fonksiyonu ve alt fonksiyonlar yazilir.
- `_tarayici_dogrudan_parse`, `_tarayici_dosya_oku`, `_tarayici_endeks_oku` tamamlanir.
- `_tarayici_portfoy_oku` adaptorle entegre edilir.
- `_tarayici_dogrula` ve `_tarayici_tekrarlari_sil` tamamlanir.

### 9.2 Adim 2: Endeks Dosyalari

- `tarama/endeksler/` dizini olusturulur.
- `bist30.txt` ve `bist100.txt` guncel bilesenlerle doldurulur.
- Opsiyonel: `bist_tem.txt`, `bist_banka.txt` eklenir.
- `favori.txt` bos sablonla eklenir.

### 9.3 Adim 3: motor.sh Guncelle

- `robot_baslat` parametreleri genisletilir (--semboller, --liste, --dosya, --portfoy).
- Parametre parse mekanizmasi eklenir (while + case + shift).
- `tarayici_sembolleri_coz` cagrisi eklenir.
- STRATEJI_SEMBOLLER motor tarafindan doldurulur.
- Strateji dosyasinda STRATEJI_SEMBOLLER varsa ve dis kaynak yoksa geriye uyumlu calisir.

### 9.4 Adim 4: ornek.sh Guncelle

- `STRATEJI_SEMBOLLER` satiri kaldirilir.
- Dosya basligi guncellenir (semboller dis kaynaktan gelir notu eklenir).

### 9.5 Adim 5: cekirdek.sh Entegrasyonu

- cekirdek.sh fiyat_kaynagi.sh'dan sonra `tarama/tarayici.sh` dosyasini source eder.
- `borsa robot baslat` komutu yeni parametreleri kabul eder.

### 9.6 Adim 6: tamamlama.sh Guncelle

- Tab tamamlamaya yeni parametreler eklenir (--semboller, --liste, --dosya, --portfoy).
- `--liste` sonrasi endeksler/ dizinindeki dosya adlari tamamlanir.

## 10. Ornek Kullanim Senaryolari

Senaryo 1 — BIST30 taramasi (kuru calistirma):
```
borsa robot baslat --liste bist30 --kuru ziraat 10203145668 ornek.sh
```

Senaryo 2 — Portfoydeki hisseler icin satis robotu:
```
borsa robot baslat --portfoy ziraat 10203145668 satis_takip.sh
```

Senaryo 3 — Belirli 3 hisse, 15 saniye aralikla:
```
borsa robot baslat --semboller THYAO,AKBNK,GARAN ziraat 10203145668 ornek.sh 15
```

Senaryo 4 — Kendi listem + portfoy birlikte:
```
borsa robot baslat --portfoy --dosya ~/hisselerim.txt ziraat 10203145668 ornek.sh
```

Senaryo 5 — Kuru modda favori listem:
```
borsa robot baslat --liste favori --kuru ziraat 10203145668 ornek.sh
```
