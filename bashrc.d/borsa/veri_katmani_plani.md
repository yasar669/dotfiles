# Veri Katmani - Plan

## 1. Amac

Adaptor fonksiyonlari su anda sadece ekrana yazdirir. Robot motoru ve strateji katmani bu verilere programatik erisemez. Bu plan, mevcut echo ciktilarini bozmadan her fonksiyonun yapisal veriyi global associative array'lere kaydetmesini tanimlar.

## 2. Mevcut Durum

Su anda adaptor fonksiyonlari sadece stdout'a yazar:

```
adaptor_bakiye       -> ekrana "Nakit: 45.230,50 TL" yazar, biter
adaptor_portfoy      -> ekrana hisse tablosu basar, biter
adaptor_emirleri_listele -> ekrana emir tablosu basar, biter
adaptor_halka_arz_liste  -> ekrana halka arz tablosu basar, biter
```

Sorunlar:
- Robot motoru bakiyeyi sayi olarak okuyamaz.
- Strateji katmani portfoydeki hisse lotlarini bilemez.
- Emir durumunu programatik kontrol edemez.
- Her bilgiye erismek icin HTML'i tekrar parse etmek gerekir.

## 3. Hedef Mimari

Her adaptor fonksiyonu iki is yapacak:
- Ekrana yazdirma (mevcut davranis, kullanici icin).
- Global degiskenlere kaydetme (robot/strateji icin).

Veri akisi:

```
adaptor_bakiye()
  |
  +-> HTML parse et
  +-> _borsa_veri_kaydet_bakiye "$nakit" "$hisse" "$toplam"  # merkezi kayit
  +-> cekirdek_yazdir_portfoy ...                            # ekrana yazdir (degismez)
```

Merkezi tasarim: Veri temizleme, normalizasyon ve array atamalari cekirdek.sh'daki `_borsa_veri_kaydet_*` fonksiyonlari tarafindan yapilir (Bolum 6.6). Adaptor sadece parse ettigi ham degerleri bu fonksiyonlara iletir. Boylece yeni bir adaptor (ornegin Is Bankasi) ayni veri katmanini tek satirlik cagrilarla kullanir; temizleme ve atama mantigi tekrarlanmaz.

## 4. Veri Yapilari

> Dosya: `bashrc.d/borsa/cekirdek.sh`
> Ekleme noktasi: `declare -gA _CEKIRDEK_AKTIF_HESAPLAR` satirindan SONRA (satir 42).
> Tum `declare -gA` / `declare -ga` / `declare -g` tanimlari burada gruplanir.

### 4.1 Bakiye Verileri

```bash
declare -gA _BORSA_VERI_BAKIYE
# Anahtarlar:
#   nakit    = "45230.50"    (ondalikli, nokta ayracli, TL)
#   hisse    = "124518.12"   (ondalikli, nokta ayracli, TL)
#   toplam   = "169748.62"   (ondalikli, nokta ayracli, TL)
#   zaman    = "1740150000"  (epoch saniye, verinin alindigi an)
```

Turkce format donusumu (virgul -> nokta) adaptor tarafinda yapilir. Array'e her zaman nokta ayracli deger yazilir. Boylece `bc` ile dogrudan karsilastirma yapilabilir.

### 4.2 Portfoy Verileri (Hisse Bazli)

```bash
declare -ga _BORSA_VERI_SEMBOLLER        # Sirayla sembol listesi
declare -gA _BORSA_VERI_HISSE_LOT        # sembol -> lot (integer)
declare -gA _BORSA_VERI_HISSE_FIYAT      # sembol -> son fiyat
declare -gA _BORSA_VERI_HISSE_DEGER      # sembol -> piyasa degeri
declare -gA _BORSA_VERI_HISSE_MALIYET    # sembol -> maliyet
declare -gA _BORSA_VERI_HISSE_KAR        # sembol -> kar/zarar TL
declare -gA _BORSA_VERI_HISSE_KAR_YUZDE  # sembol -> kar/zarar %
declare -g  _BORSA_VERI_PORTFOY_ZAMAN     # epoch saniye, verinin alindigi an
```

Ornek erisim:

```bash
for s in "${_BORSA_VERI_SEMBOLLER[@]}"; do
    echo "$s: ${_BORSA_VERI_HISSE_LOT[$s]} lot"
done
# AKBNK: 55 lot
# THYAO: 100 lot
```

### 4.3 Emir Verileri

```bash
declare -ga _BORSA_VERI_EMIRLER           # Sirayla emir referanslari
declare -gA _BORSA_VERI_EMIR_SEMBOL       # referans -> sembol
declare -gA _BORSA_VERI_EMIR_YON          # referans -> ALIS|SATIS (normalize edilmis)
declare -gA _BORSA_VERI_EMIR_LOT          # referans -> lot (tamsayi)
declare -gA _BORSA_VERI_EMIR_FIYAT        # referans -> fiyat (nokta ayracli)
declare -gA _BORSA_VERI_EMIR_DURUM        # referans -> Iletildi|Gerceklesti|Iptal|Kismi
declare -gA _BORSA_VERI_EMIR_IPTAL_VAR    # referans -> "1" iptal edilebilir, "0" degilse
declare -g  _BORSA_VERI_EMIRLER_ZAMAN     # epoch saniye, verinin alindigi an
```

Not: `_BORSA_VERI_EMIR_GERCEKLESEN` kaldirildi. Ziraat HTML'inde gerceklesen lot ayri bir alan olarak gosterilmiyor. Ileride baska araci kurum bu bilgiyi saglayabilir, o zaman eklenir.

### 4.4 Halka Arz Verileri

```bash
declare -ga _BORSA_VERI_HALKA_ARZ_LISTESI  # Sirayla IPO ID'leri
declare -gA _BORSA_VERI_HALKA_ARZ_ADI      # ipo_id -> halka arz adi
declare -gA _BORSA_VERI_HALKA_ARZ_TIP      # ipo_id -> tip
declare -gA _BORSA_VERI_HALKA_ARZ_ODEME    # ipo_id -> odeme sekli
declare -gA _BORSA_VERI_HALKA_ARZ_DURUM    # ipo_id -> durum
declare -g  _BORSA_VERI_HALKA_ARZ_LIMIT    # halka arz islem limiti (TL)
declare -g  _BORSA_VERI_HALKA_ARZ_ZAMAN   # epoch saniye, verinin alindigi an

declare -ga _BORSA_VERI_TALEPLER           # Sirayla talep ID'leri
declare -gA _BORSA_VERI_TALEP_ADI          # talep_id -> halka arz adi
declare -gA _BORSA_VERI_TALEP_TARIH        # talep_id -> talep tarihi (DD.MM.YYYY)
declare -gA _BORSA_VERI_TALEP_LOT          # talep_id -> talep edilen lot
declare -gA _BORSA_VERI_TALEP_FIYAT        # talep_id -> fiyat (nokta ayracli)
declare -gA _BORSA_VERI_TALEP_TUTAR        # talep_id -> tutar (nokta ayracli, TL)
declare -gA _BORSA_VERI_TALEP_DURUM        # talep_id -> durum
declare -g  _BORSA_VERI_TALEPLER_ZAMAN     # epoch saniye, verinin alindigi an
```

### 4.5 Son Emir Sonucu

```bash
declare -gA _BORSA_VERI_SON_EMIR
# Anahtarlar:
#   basarili   = "1" veya "0"   (boolean)
#   referans   = "ABC123"       (emir referans no, bulunamazsa bos)
#   sembol     = "THYAO"
#   yon        = "ALIS"
#   lot        = "100"
#   fiyat      = "312.50"       (piyasa emrinde "0")
#   piyasa_mi  = "1" veya "0"   (piyasa emri gostergesi)
#   mesaj      = "Emiriniz kaydedilmistir" (hata durumunda hata metni)
```

### 4.6 Son Halka Arz Islem Sonucu

Halka arz talep, iptal ve guncelleme islemleri icin:

```bash
declare -gA _BORSA_VERI_SON_HALKA_ARZ
# Anahtarlar:
#   basarili   = "1" veya "0"   (boolean)
#   islem      = "talep" | "iptal" | "guncelle"
#   ipo_adi    = "XYZ HOLDING"  (halka arz adi)
#   ipo_id     = "12345"        (halka arz ID)
#   lot        = "100"          (talep/guncelle lot)
#   fiyat      = "25.50"        (fiyat, nokta ayracli)
#   mesaj      = "Talep basariyla kaydedildi" (sunucu mesaji)
#   talep_id   = "67890"        (iptal/guncelle islemlerinde)
```

## 5. Format Kurallari

### 5.1 Sayi Formati

Tum sayisal degerler nokta ayracli olarak saklanir. Turkce format (virgul ayracli) sadece ekran ciktisinda kullanilir.

```
Ekranda:  45.230,50 TL    (Turkce, kullanici icin)
Array'de: 45230.50         (nokta ayracli, bc/awk icin)
```

Donusum fonksiyonu:

```bash
# Turkce formattan sayi formatina cevirir
# 45.230,50 -> 45230.50
# 1.234.567,89 -> 1234567.89
_borsa_sayi_temizle() {
    echo "$1" | tr -d '.' | tr ',' '.'
}
```

### 5.2 Negatif Sayilar

Kar/zarar degerleri negatif olabilir. `_borsa_sayi_temizle` negatif sayilari dogru isler cunku `tr` komutlari eksi isaretini koruyor:

```
Girdi:  -1.234,56
tr -d '.':  -1234,56
tr ',' '.': -1234.56   (dogru)
```

Negatif degerlerin `bc` ile karsilastirilmasi sorunsuz calisir:

```bash
echo "-1234.56 < 0" | bc -l    # 1 (dogru)
```

### 5.3 Yuzde Degerleri

`kar_yuzde` gibi yuzde degerleri `%` on eki olmadan, sadece sayi olarak saklanir. Adaptor, HTML'den gelen `%12,50` veya `%-3,25` degerinden `%` isaretini soyar ve virgulden noktaya cevirir:

```
HTML:    %12,50   veya   %-3,25
Array:   12.50    veya   -3.25
```

Donusum:

```bash
_borsa_yuzde_temizle() {
    local deger
    deger="$1"
    deger="${deger#%}"              # Bastaki % soy
    deger="${deger#±}"              # Bastaki ± soy (varsa)
    echo "$deger" | tr -d '.' | tr ',' '.'
}
```

### 5.4 Bos ve Bilinmeyen Degerler

Parse basarisiz oldugunda adaptor kodlari fallback degerler kullanir (`${var:-0.00}`, `${var:-?}`, `"Bilinmiyor"` vb). Veri katmaninda su kurallar gecerlidir:

- Sayisal deger parse edilemezse array'e **bos string `""`** yazilir. `"bilinmiyor"` gibi string yazilmaz.
- Robot motoru bos degeri kontrol etmeli: `[[ -n "${_BORSA_VERI_BAKIYE[nakit]:-}" ]]`
- `_borsa_sayi_temizle` fonksiyonuna sayisal olmayan string girmemek adaptorun sorumlulugudur. Parse basarisiz ise array atamasini atla.

Ornek guvenli atama:

```bash
local temiz
temiz=$(_borsa_sayi_temizle "$fiyat_p")
# Sadece sayisal sonucta ata
if [[ "$temiz" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
    _BORSA_VERI_EMIR_FIYAT["$ext_id"]="$temiz"
else
    _BORSA_VERI_EMIR_FIYAT["$ext_id"]=""
fi
```

### 5.5 Boolean

Return kodlari POSIX standardi: 0 = basarili/evet, 1 = basarisiz/hayir.
Array icinde string olarak: "1" = evet, "0" = hayir.

### 5.6 Zaman Damgasi

Her veri grubuna `zaman` anahtari eklenir. Epoch saniye olarak (`date +%s`). Robot motoru verinin ne kadar eski oldugunu kontrol eder.

## 6. Cekirdek Yardimci Fonksiyonlar

> Dosya: `bashrc.d/borsa/cekirdek.sh`
> Ekleme noktasi: `declare -gA _CEKIRDEK_AKTIF_HESAPLAR` satirindan SONRA (satir 42 civari), diger declare satirlariyla birlikte tanimlanir.
> Fonksiyonlar ise `borsa()` ana fonksiyonundan ONCE eklenir (satir 635 civari).

### 6.1 Veri Temizleme

```bash
_borsa_sayi_temizle() {
    # Turkce format stringi bc-uyumlu sayiya cevirir.
    # 45.230,50 -> 45230.50
    # 1.234.567,89 -> 1234567.89
    # -1.234,56 -> -1234.56
    echo "$1" | tr -d '.' | tr ',' '.'
}
```

### 6.2 Yuzde Temizleme

```bash
_borsa_yuzde_temizle() {
    # Yuzde stringinden % ve ± isaretlerini soyar, bc-uyumlu sayiya cevirir.
    # %12,50 -> 12.50
    # %-3,25 -> -3.25
    # ±0,00 -> 0.00
    local deger
    deger="$1"
    deger="${deger#%}"
    deger="${deger#±}"
    echo "$deger" | tr -d '.' | tr ',' '.'
}
```

### 6.3 Sayi Dogrulama

```bash
_borsa_sayi_gecerli_mi() {
    # Temizlenmis degerin gecerli bir sayi olup olmadigini kontrol eder.
    # Gecerliyse 0, degilse 1 doner (POSIX return kodu).
    # Ornek: _borsa_sayi_gecerli_mi "45230.50" -> 0
    # Ornek: _borsa_sayi_gecerli_mi "abc" -> 1
    [[ "$1" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]
}
```

### 6.4 Veri Sifirla

```bash
_borsa_veri_sifirla_bakiye() {
    # Bakiye array'ini temizler (yeni sorgu oncesi).
    unset _BORSA_VERI_BAKIYE
    declare -gA _BORSA_VERI_BAKIYE
}
```

```bash
_borsa_veri_sifirla_portfoy() {
    # Portfoy array'lerini temizler (semboller, lot, fiyat, deger, maliyet, kar, kar_yuzde).
    unset _BORSA_VERI_SEMBOLLER
    declare -ga _BORSA_VERI_SEMBOLLER
    unset _BORSA_VERI_HISSE_LOT
    declare -gA _BORSA_VERI_HISSE_LOT
    unset _BORSA_VERI_HISSE_FIYAT
    declare -gA _BORSA_VERI_HISSE_FIYAT
    unset _BORSA_VERI_HISSE_DEGER
    declare -gA _BORSA_VERI_HISSE_DEGER
    unset _BORSA_VERI_HISSE_MALIYET
    declare -gA _BORSA_VERI_HISSE_MALIYET
    unset _BORSA_VERI_HISSE_KAR
    declare -gA _BORSA_VERI_HISSE_KAR
    unset _BORSA_VERI_HISSE_KAR_YUZDE
    declare -gA _BORSA_VERI_HISSE_KAR_YUZDE
    _BORSA_VERI_PORTFOY_ZAMAN=""
}
```

```bash
_borsa_veri_sifirla_emirler() {
    # Emir array'lerini temizler.
    unset _BORSA_VERI_EMIRLER
    declare -ga _BORSA_VERI_EMIRLER
    unset _BORSA_VERI_EMIR_SEMBOL
    declare -gA _BORSA_VERI_EMIR_SEMBOL
    unset _BORSA_VERI_EMIR_YON
    declare -gA _BORSA_VERI_EMIR_YON
    unset _BORSA_VERI_EMIR_LOT
    declare -gA _BORSA_VERI_EMIR_LOT
    unset _BORSA_VERI_EMIR_FIYAT
    declare -gA _BORSA_VERI_EMIR_FIYAT
    unset _BORSA_VERI_EMIR_DURUM
    declare -gA _BORSA_VERI_EMIR_DURUM
    unset _BORSA_VERI_EMIR_IPTAL_VAR
    declare -gA _BORSA_VERI_EMIR_IPTAL_VAR
    _BORSA_VERI_EMIRLER_ZAMAN=""
}
```

```bash
_borsa_veri_sifirla_halka_arz_liste() {
    # Halka arz LISTE array'lerini temizler.
    # Talep array'lerine DOKUNMAZ.
    unset _BORSA_VERI_HALKA_ARZ_LISTESI
    declare -ga _BORSA_VERI_HALKA_ARZ_LISTESI
    unset _BORSA_VERI_HALKA_ARZ_ADI
    declare -gA _BORSA_VERI_HALKA_ARZ_ADI
    unset _BORSA_VERI_HALKA_ARZ_TIP
    declare -gA _BORSA_VERI_HALKA_ARZ_TIP
    unset _BORSA_VERI_HALKA_ARZ_ODEME
    declare -gA _BORSA_VERI_HALKA_ARZ_ODEME
    unset _BORSA_VERI_HALKA_ARZ_DURUM
    declare -gA _BORSA_VERI_HALKA_ARZ_DURUM
    _BORSA_VERI_HALKA_ARZ_LIMIT=""
    _BORSA_VERI_HALKA_ARZ_ZAMAN=""
}
```

```bash
_borsa_veri_sifirla_halka_arz_talepler() {
    # Halka arz TALEP array'lerini temizler.
    # Liste array'lerine DOKUNMAZ.
    unset _BORSA_VERI_TALEPLER
    declare -ga _BORSA_VERI_TALEPLER
    unset _BORSA_VERI_TALEP_ADI
    declare -gA _BORSA_VERI_TALEP_ADI
    unset _BORSA_VERI_TALEP_TARIH
    declare -gA _BORSA_VERI_TALEP_TARIH
    unset _BORSA_VERI_TALEP_LOT
    declare -gA _BORSA_VERI_TALEP_LOT
    unset _BORSA_VERI_TALEP_FIYAT
    declare -gA _BORSA_VERI_TALEP_FIYAT
    unset _BORSA_VERI_TALEP_TUTAR
    declare -gA _BORSA_VERI_TALEP_TUTAR
    unset _BORSA_VERI_TALEP_DURUM
    declare -gA _BORSA_VERI_TALEP_DURUM
    _BORSA_VERI_TALEPLER_ZAMAN=""
}
```

Not: Iki ayri sifirlama fonksiyonu gereklidir. `adaptor_halka_arz_liste` cagrildiginda talep verileri silinmemelidir, cunku kullanici once listeyi sonra talepleri sorgulayabilir. Tek fonksiyon (`_borsa_veri_sifirla_halka_arz`) her ikisini de silerse veri kaybi olur.

```bash
_borsa_veri_sifirla_son_emir() {
    # Son emir sonuc array'ini temizler.
    unset _BORSA_VERI_SON_EMIR
    declare -gA _BORSA_VERI_SON_EMIR
}
```

```bash
_borsa_veri_sifirla_son_halka_arz() {
    # Son halka arz islem sonuc array'ini temizler.
    unset _BORSA_VERI_SON_HALKA_ARZ
    declare -gA _BORSA_VERI_SON_HALKA_ARZ
}
```

### 6.5 Veri Gecerlilik

```bash
_borsa_veri_gecerli_mi() {
    # Verinin belirtilen sureden eski olup olmadigini kontrol eder.
    # Ornek: _borsa_veri_gecerli_mi "bakiye" 60
    # 60 saniyeden yeniyse 0, eskiyse 1 doner.
    local grup
    grup="$1"
    local max_saniye
    max_saniye="$2"

    local zaman=""
    case "$grup" in
        bakiye)    zaman="${_BORSA_VERI_BAKIYE[zaman]:-}" ;;
        portfoy)   zaman="${_BORSA_VERI_PORTFOY_ZAMAN:-}" ;;
        emirler)   zaman="${_BORSA_VERI_EMIRLER_ZAMAN:-}" ;;
        halka_arz) zaman="${_BORSA_VERI_HALKA_ARZ_ZAMAN:-}" ;;
        talepler)  zaman="${_BORSA_VERI_TALEPLER_ZAMAN:-}" ;;
        *)         return 1 ;;
    esac

    # Zaman damgasi yoksa veri gecersiz
    [[ -z "$zaman" ]] && return 1

    local simdi
    simdi=$(date +%s)
    local fark=$((simdi - zaman))

    # fark negatifse (saat degisimi vb) gecersiz say
    [[ "$fark" -lt 0 ]] && return 1

    # max_saniye'den eskiyse gecersiz
    [[ "$fark" -gt "$max_saniye" ]] && return 1

    return 0
}
```

### 6.6 Veri Kayit Fonksiyonlari

Merkezi kayit fonksiyonlari. Adaptor parse ettigi ham degerleri bu fonksiyonlara iletir; temizleme, normalizasyon ve array atamalari burada yapilir. Yeni adaptor eklendiginde bu fonksiyonlar oldugu gibi kullanilir.

> Dosya: `bashrc.d/borsa/cekirdek.sh`
> Ekleme noktasi: Diger yardimci fonksiyonlarla birlikte, `borsa()` fonksiyonundan ONCE (satir 635 civari).

```bash
_borsa_veri_kaydet_bakiye() {
    # Bakiye verilerini array'e kaydeder ve zaman damgasi basar.
    # $1: nakit (Turkce format, orn: "45.230,50")
    # $2: hisse (Turkce format)
    # $3: toplam (Turkce format)
    _BORSA_VERI_BAKIYE[nakit]=$(_borsa_sayi_temizle "$1")
    _BORSA_VERI_BAKIYE[hisse]=$(_borsa_sayi_temizle "$2")
    _BORSA_VERI_BAKIYE[toplam]=$(_borsa_sayi_temizle "$3")
    _BORSA_VERI_BAKIYE[zaman]=$(date +%s)
}
```

```bash
_borsa_veri_kaydet_hisse() {
    # Tek hisse verisini portfoy array'lerine ekler. Dongu icinden cagrilir.
    # Zaman damgasi BASILMAZ — dongu sonrasinda adaptor _BORSA_VERI_PORTFOY_ZAMAN'i yazar.
    # $1: sembol
    # $2: lot (Turkce format)
    # $3: son fiyat (Turkce format)
    # $4: piyasa degeri (Turkce format)
    # $5: maliyet (Turkce format)
    # $6: kar/zarar (Turkce format)
    # $7: kar/zarar yuzde (Turkce format, orn: "%12,50" veya "%-3,25")
    local sembol="$1"
    _BORSA_VERI_SEMBOLLER+=("$sembol")
    _BORSA_VERI_HISSE_LOT["$sembol"]=$(_borsa_sayi_temizle "$2")
    _BORSA_VERI_HISSE_FIYAT["$sembol"]=$(_borsa_sayi_temizle "$3")
    _BORSA_VERI_HISSE_DEGER["$sembol"]=$(_borsa_sayi_temizle "$4")
    _BORSA_VERI_HISSE_MALIYET["$sembol"]=$(_borsa_sayi_temizle "$5")
    _BORSA_VERI_HISSE_KAR["$sembol"]=$(_borsa_sayi_temizle "$6")
    _BORSA_VERI_HISSE_KAR_YUZDE["$sembol"]=$(_borsa_yuzde_temizle "$7")
}
```

```bash
_borsa_veri_kaydet_emir() {
    # Tek emir verisini emir array'lerine ekler. Dongu icinden cagrilir.
    # Zaman damgasi BASILMAZ — dongu sonrasinda adaptor _BORSA_VERI_EMIRLER_ZAMAN'i yazar.
    # $1: ext_id (referans no)
    # $2: sembol
    # $3: islem (HTML'den gelen ham deger, orn: "Alis"/"Satis" — normalize edilir)
    # $4: adet (Turkce format)
    # $5: fiyat (Turkce format)
    # $6: durum (Iletildi/Iptal/Gerceklesti/Kismi)
    # $7: iptal_var (bos olmayan deger = "1", bos = "0")
    local ext_id="$1"
    _BORSA_VERI_EMIRLER+=("$ext_id")
    _BORSA_VERI_EMIR_SEMBOL["$ext_id"]="${2:-}"

    # Yon normalizasyonu: "Alis" -> "ALIS", "Satis" -> "SATIS"
    local yon_normalize
    case "${3,,}" in
        al*) yon_normalize="ALIS" ;;
        sat*) yon_normalize="SATIS" ;;
        *) yon_normalize="${3:-}" ;;
    esac
    _BORSA_VERI_EMIR_YON["$ext_id"]="$yon_normalize"

    # Lot: tamsayi olmali — ondalik kismi at
    local lot_temiz
    lot_temiz=$(_borsa_sayi_temizle "${4:-0}")
    lot_temiz="${lot_temiz%%.*}"
    if _borsa_sayi_gecerli_mi "$lot_temiz"; then
        _BORSA_VERI_EMIR_LOT["$ext_id"]="$lot_temiz"
    else
        _BORSA_VERI_EMIR_LOT["$ext_id"]=""
    fi

    # Fiyat
    local fiyat_temiz
    fiyat_temiz=$(_borsa_sayi_temizle "${5:-0}")
    if _borsa_sayi_gecerli_mi "$fiyat_temiz"; then
        _BORSA_VERI_EMIR_FIYAT["$ext_id"]="$fiyat_temiz"
    else
        _BORSA_VERI_EMIR_FIYAT["$ext_id"]=""
    fi

    _BORSA_VERI_EMIR_DURUM["$ext_id"]="$6"

    # Iptal edilebilirlik: bos olmayan deger (orn: "[*]") = iptal var
    if [[ -n "${7:-}" ]]; then
        _BORSA_VERI_EMIR_IPTAL_VAR["$ext_id"]="1"
    else
        _BORSA_VERI_EMIR_IPTAL_VAR["$ext_id"]="0"
    fi
}
```

```bash
_borsa_veri_kaydet_son_emir() {
    # Son emir sonucunu kaydeder. Basari, hata veya iptal yolundan cagrilir.
    # Tum degerler zaten islenilmis formatta gelir — temizleme yapilmaz.
    # $1: basarili ("1" veya "0")
    # $2: referans (bos olabilir)
    # $3: sembol (bos olabilir — iptal durumunda bilinmez)
    # $4: yon ("ALIS"/"SATIS"/"IPTAL")
    # $5: lot (bos olabilir)
    # $6: fiyat (bos olabilir)
    # $7: piyasa_mi ("1" veya "0")
    # $8: mesaj
    _BORSA_VERI_SON_EMIR[basarili]="$1"
    _BORSA_VERI_SON_EMIR[referans]="${2:-}"
    _BORSA_VERI_SON_EMIR[sembol]="${3:-}"
    _BORSA_VERI_SON_EMIR[yon]="${4:-}"
    _BORSA_VERI_SON_EMIR[lot]="${5:-}"
    _BORSA_VERI_SON_EMIR[fiyat]="${6:-}"
    _BORSA_VERI_SON_EMIR[piyasa_mi]="${7:-0}"
    _BORSA_VERI_SON_EMIR[mesaj]="${8:-}"
}
```

```bash
_borsa_veri_kaydet_halka_arz() {
    # Tek halka arz kaydini array'e ekler. Dongu icinden cagrilir.
    # Zaman damgasi BASILMAZ — dongu sonrasinda _borsa_veri_kaydet_halka_arz_limit cagirir.
    # $1: ipo_id
    # $2: ipo_adi
    # $3: arz_tip (string, temizleme yapilmaz)
    # $4: odeme (string, temizleme yapilmaz)
    # $5: durum (varsayilan: "AKTIF")
    local ipo_id="$1"
    _BORSA_VERI_HALKA_ARZ_LISTESI+=("$ipo_id")
    _BORSA_VERI_HALKA_ARZ_ADI["$ipo_id"]="${2:-}"
    _BORSA_VERI_HALKA_ARZ_TIP["$ipo_id"]="${3:-}"
    _BORSA_VERI_HALKA_ARZ_ODEME["$ipo_id"]="${4:-}"
    _BORSA_VERI_HALKA_ARZ_DURUM["$ipo_id"]="${5:-AKTIF}"
}
```

```bash
_borsa_veri_kaydet_halka_arz_limit() {
    # Halka arz islem limitini kaydeder ve zaman damgasi basar.
    # Dongu disinda, cekirdek_yazdir_halka_arz_liste'den ONCE cagrilir.
    # $1: limit (Turkce format; bos olabilir)
    if [[ -n "${1:-}" ]]; then
        local limit_temiz
        limit_temiz=$(_borsa_sayi_temizle "$1")
        if _borsa_sayi_gecerli_mi "$limit_temiz"; then
            _BORSA_VERI_HALKA_ARZ_LIMIT="$limit_temiz"
        else
            _BORSA_VERI_HALKA_ARZ_LIMIT=""
        fi
    else
        _BORSA_VERI_HALKA_ARZ_LIMIT=""
    fi
    _BORSA_VERI_HALKA_ARZ_ZAMAN=$(date +%s)
}
```

```bash
_borsa_veri_kaydet_talep() {
    # Tek halka arz talebini array'e ekler. Dongu icinden cagrilir.
    # Zaman damgasi BASILMAZ — dongu sonrasinda adaptor _BORSA_VERI_TALEPLER_ZAMAN'i yazar.
    # $1: talep_id
    # $2: ad
    # $3: tarih (DD.MM.YYYY, donusum yapilmaz)
    # $4: lot (Turkce format)
    # $5: fiyat (Turkce format)
    # $6: tutar (Turkce format)
    # $7: durum
    local talep_id="$1"
    _BORSA_VERI_TALEPLER+=("$talep_id")
    _BORSA_VERI_TALEP_ADI["$talep_id"]="${2:-}"
    _BORSA_VERI_TALEP_TARIH["$talep_id"]="${3:-}"

    # Lot: tamsayi olmali
    local lot_temiz
    lot_temiz=$(_borsa_sayi_temizle "${4:-0}")
    lot_temiz="${lot_temiz%%.*}"
    _BORSA_VERI_TALEP_LOT["$talep_id"]="$lot_temiz"

    # Fiyat
    local fiyat_temiz
    fiyat_temiz=$(_borsa_sayi_temizle "${5:-0}")
    if _borsa_sayi_gecerli_mi "$fiyat_temiz"; then
        _BORSA_VERI_TALEP_FIYAT["$talep_id"]="$fiyat_temiz"
    else
        _BORSA_VERI_TALEP_FIYAT["$talep_id"]=""
    fi

    # Tutar
    local tutar_temiz
    tutar_temiz=$(_borsa_sayi_temizle "${6:-0}")
    if _borsa_sayi_gecerli_mi "$tutar_temiz"; then
        _BORSA_VERI_TALEP_TUTAR["$talep_id"]="$tutar_temiz"
    else
        _BORSA_VERI_TALEP_TUTAR["$talep_id"]=""
    fi

    _BORSA_VERI_TALEP_DURUM["$talep_id"]="${7:-}"
}
```

```bash
_borsa_veri_kaydet_son_halka_arz() {
    # Son halka arz islem sonucunu kaydeder.
    # $1: basarili ("1" veya "0")
    # $2: islem ("talep"/"iptal"/"guncelle")
    # $3: mesaj
    # $4: ipo_adi (bos olabilir)
    # $5: ipo_id (bos olabilir)
    # $6: lot (bos olabilir)
    # $7: fiyat (bos olabilir)
    # $8: talep_id (bos olabilir)
    _BORSA_VERI_SON_HALKA_ARZ[basarili]="$1"
    _BORSA_VERI_SON_HALKA_ARZ[islem]="$2"
    _BORSA_VERI_SON_HALKA_ARZ[mesaj]="${3:-}"
    _BORSA_VERI_SON_HALKA_ARZ[ipo_adi]="${4:-}"
    _BORSA_VERI_SON_HALKA_ARZ[ipo_id]="${5:-}"
    _BORSA_VERI_SON_HALKA_ARZ[lot]="${6:-}"
    _BORSA_VERI_SON_HALKA_ARZ[fiyat]="${7:-}"
    _BORSA_VERI_SON_HALKA_ARZ[talep_id]="${8:-}"
}
```

## 7. Adaptor Degisiklikleri

> Dosya: `bashrc.d/borsa/adaptorler/ziraat.sh` (tum 7.x bolumleri)

Mevcut fonksiyonlara ekleme yapilir. Hicbir echo satiri silinmez veya degistirilmez. Veri temizleme, normalizasyon ve array atamalari merkezi kaydet fonksiyonlari (Bolum 6.6) tarafindan yapilir — adaptor sadece parse ettigi ham degerleri tek satirlik fonksiyon cagrilariyla iletir.

### 7.1 adaptor_bakiye Degisikligi

> Fonksiyon: `adaptor_bakiye()` — satir 441

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 451):
#   if echo "$portfoy_yaniti" | grep -q 'Toplam'; then
_borsa_veri_sifirla_bakiye

# VERI KAYDI — asagidaki satirdan HEMEN ONCE eklenir (satir 466):
#   cekirdek_yazdir_portfoy "$ADAPTOR_ADI" "$nakit" "$hisse" "$toplam"
_borsa_veri_kaydet_bakiye "$nakit" "$hisse" "$toplam"
```

### 7.2 adaptor_portfoy Degisikligi

> Fonksiyon: `adaptor_portfoy()` — satir 476

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 492):
#   local portfoy_yaniti="$_ziraat_portfoy_html"
_borsa_veri_sifirla_portfoy

# DONGU ICINDE — asagidaki satirdan HEMEN SONRA eklenir (satir 561):
#   printf -v satir_fmt "%s\t%s\t%s\t%s\t%s\t%s\t%s" \
#       "$sembol" "$lot" "$son_fiyat" "$piy_degeri" "$maliyet" "$kar_zarar" "$kar_yuzde"
_borsa_veri_kaydet_hisse "$sembol" "$lot" "$son_fiyat" "$piy_degeri" "$maliyet" "$kar_zarar" "$kar_yuzde"

# ZAMAN — asagidaki satirdan HEMEN SONRA eklenir (satir 569):
#   done <<< "$hesap_idler"
_BORSA_VERI_PORTFOY_ZAMAN=$(date +%s)
```

### 7.2.1 adaptor_portfoy Bakiye Verisi

> Fonksiyon: `adaptor_portfoy()` — satir 476

`adaptor_portfoy` fonksiyonu icinde de `nakit`, `hisse_toplam`, `toplam` degerleri parse edilir. Bu degerler `_BORSA_VERI_BAKIYE` array'ine de yazilir — boylece kullanici `adaptor_portfoy` cagirdiginda bakiye verisi de guncellenmis olur.

```bash
# BAKIYE KAYDI — asagidaki satirdan HEMEN SONRA eklenir (satir 498):
#   toplam=$(echo "$portfoy_yaniti" | grep -A 10 "$_ZIRAAT_METIN_TOPLAM" ...
# ve asagidaki satirdan ONCE (satir 501):
#   local hesap_idler
_borsa_veri_sifirla_bakiye
_borsa_veri_kaydet_bakiye "$nakit" "$hisse_toplam" "$toplam"
```

Bu sayede robot motoru tek bir `adaptor_portfoy > /dev/null` cagrisiyla hem hisse hem bakiye verisine erisir.

### 7.3 adaptor_emirleri_listele Degisikligi

> Fonksiyon: `adaptor_emirleri_listele()` — satir 584

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN ONCE eklenir (satir 663):
#   while IFS= read -r blok; do
_borsa_veri_sifirla_emirler

# DONGU ICINDE — asagidaki satirdan HEMEN SONRA eklenir (satir 703):
#   echo "$blok" | grep -q 'btnListDailyDelete' && iptal_var="[*]"
_borsa_veri_kaydet_emir "$ext_id" "${sembol_p:-}" "${islem_p:-}" "${adet_p:-}" "${fiyat_p:-}" "$durum_p" "$iptal_var"

# ZAMAN — asagidaki satirdan HEMEN ONCE eklenir (satir 711):
#   if [[ "$bulunan" -eq 0 ]]; then
_BORSA_VERI_EMIRLER_ZAMAN=$(date +%s)
```

Yon normalizasyonu, lot/fiyat temizleme ve iptal_var donusumu `_borsa_veri_kaydet_emir` fonksiyonu tarafindan yapilir (Bolum 6.6).

### 7.4 adaptor_emir_gonder Degisikligi

> Fonksiyon: `adaptor_emir_gonder()` — satir 879

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 884):
#   local bildirim_turu="$5"
_borsa_veri_sifirla_son_emir

# KURU CALISTIR — asagidaki satirdan HEMEN ONCE eklenir (satir 980):
#   return 0
_borsa_veri_kaydet_son_emir "1" "KURU" "$sembol" "${islem^^}" "$lot" "$fiyat" "$piyasa_mi" \
    "Kuru calistirma — emir gonderilmedi"

# BASARI YOLU 1 — Redirect tespiti
# Asagidaki satirdan HEMEN ONCE eklenir (satir 1103):
#   return 0
_borsa_veri_kaydet_son_emir "1" "" "$sembol" "${islem^^}" "$lot" "$fiyat" "$piyasa_mi" \
    "Emir kabul edildi (redirect)"

# BASARI YOLU 2 — FinishButton sonrasi "kaydedilmis" tespiti
# Asagidaki satirdan HEMEN ONCE eklenir (satir 1183):
#   return 0
_borsa_veri_kaydet_son_emir "1" "${referans_no:-}" "$sembol" "${islem^^}" "$lot" "$fiyat" "$piyasa_mi" \
    "Emiriniz kaydedilmistir"

# HATA YOLLARI — her return 1'den once eklenir.
#
# KAPSAM DISI: Tum dogrulama kontrolleri (satir 889-984 arasi) kapsam
# disindadir. Bu noktada emir henuz sunucuya GONDERILMEMISTIR; sifirlanmis
# array yeterlidir. Dogrulama hatalari: parametre bos (889), gecersiz
# islem turu (917), gecersiz bildirim (930), lot/fiyat sayisal degil
# (936, 943), seans disi tutar (949), BIST adimi (954),
# aktif_hesap_kontrol (984).
#
# KAPSAM ICI: Asagidaki 5 hata noktasinin her birinden hemen once:
#   1. CSRF token bulunamadi (satir 1005): return 1
#   2. Hesap ID bulunamadi (satir 1012): return 1
#   3. Emir yaniti bos/10 bayt alti (satir 1085): return 1
#   4. FinishButton sonrasi hata (satir 1195): return 1
#   5. Ne redirect ne onay sayfasi — gercek hata (satir 1208): return 1
#
# NOT: hata_metni degiskeni satir 1195'te "hata_metni2" olarak, satir
# 1005/1012'de ise tanimsizdir. Jenerik fallback "Emir reddedildi" kullanilir.
_borsa_veri_kaydet_son_emir "0" "" "$sembol" "${islem^^}" "$lot" "$fiyat" \
    "${piyasa_mi:-0}" "${hata_metni:-${hata_metni2:-Emir reddedildi}}"
```

Onemli notlar:
- `piyasa_mi`: Piyasa emrinde "1", limit emirde "0". Robot motoru fiyatin anlamli olup olmadigini buradan anlar.
- `referans`: Sadece FinishButton basari yolunda parse edilir. Diger yollarda bos kalir.
- `yon`: Her zaman buyuk harf (`${islem^^}`): "ALIS" veya "SATIS".
- Hata durumunda da array doldurulur — robot motoru hangi emrin basarisiz oldugunu bilir.
- Sifirla yerlesimleri adaptorlere gore degisir: `adaptor_emir_gonder`'de parametre kontrolunden ONCE (satir 884), `adaptor_halka_arz_talep`'te parametre kontrolunden SONRA (satir 1428). Birincisinde parametre hatasi dahi sifirlanmis array ile doner; ikincisinde eski veri kalirmis gibi gorunse de sifirlama `_ziraat_aktif_hesap_kontrol` sonrasinda yer alir ve `adaptor_halka_arz_talep`'teki erken return'ler (satir 1421, 1425) sifirlamaDAN ONCE gerceklesir. Her iki durumda da `basarili` anahtari bos ise robot "sifirlama sonrasi erken cikis" olarak yorumlar.

### 7.4.1 adaptor_emir_iptal Degisikligi

> Fonksiyon: `adaptor_emir_iptal()` — satir 724

Hisse emri iptali sonrasinda `_BORSA_VERI_SON_EMIR` array'ine kayit yapilir. Ayni array kullanilir cunku iptal de bir emir islemidir — robot motoru `yon` anahtarindan "IPTAL" oldugunu anlar.

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 742):
#   _ziraat_log "Emir iptal ediliyor. Referans: $ext_id"
_borsa_veri_sifirla_son_emir

# ARA HATA YOLLARI — sifirla (742) ile basari/hata bloklari (853) arasinda
# 4 return 1 noktasi: CSRF bulunamadi (758), sunucu JSON hatasi (779),
# emir listede bulunamadi (806), iptal yaniti bos (826).
# Her birinden HEMEN ONCE:
_borsa_veri_kaydet_son_emir "0" "$ext_id" "" "IPTAL" "" "" "0" "Iptal basarisiz"
# Ozellikle satir 826 (iptal yaniti bos) kritiktir: POST gonderilmis olabilir.

# BASARI — asagidaki satirdan HEMEN ONCE eklenir (satir 853):
#   return 0
_borsa_veri_kaydet_son_emir "1" "$ext_id" "" "IPTAL" "" "" "0" "${mesaj:-Emir iptal edildi}"

# HATA — asagidaki satirdan HEMEN ONCE eklenir (satir 862):
#   return 1
_borsa_veri_kaydet_son_emir "0" "$ext_id" "" "IPTAL" "" "" "0" "${hata:-Iptal basarisiz}"

# BILINMEYEN DURUM — asagidaki satirdan HEMEN ONCE eklenir (satir 876):
#   return 1
_borsa_veri_kaydet_son_emir "0" "$ext_id" "" "IPTAL" "" "" "0" "${hata:-Bilinmeyen iptal sonucu}"
```

Not: `yon="IPTAL"` degerini `_borsa_veri_kaydet_son_emir` dogrudan kaydeder. Robot motoru:

```bash
if [[ "${_BORSA_VERI_SON_EMIR[yon]}" == "IPTAL" ]]; then
    # iptal islemi sonucu
else
    # normal emir sonucu
fi
```

### 7.5 adaptor_halka_arz_liste Degisikligi

> Fonksiyon: `adaptor_halka_arz_liste()` — satir 1220

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 1259):
#   local satirlar=""
# Bu pozisyon `if btnsubmit` kontrolunden ONCE oldugu icin,
# hicbir arz yoksa bile array temizlenmis olur.
_borsa_veri_sifirla_halka_arz_liste

# DONGU ICINDE — asagidaki satirdan HEMEN SONRA eklenir (satir 1300):
#   local satir="${ipo_adi}\t${arz_tip:-Bilinmiyor}\t..."
_borsa_veri_kaydet_halka_arz "$ipo_id" "${ipo_adi:-}" "${arz_tip:-}" "${odeme:-}" "${durum:-AKTIF}"

# LIMIT + ZAMAN — asagidaki satirdan HEMEN ONCE eklenir (satir 1312):
#   cekirdek_yazdir_halka_arz_liste "$ADAPTOR_ADI" "$limit" "$cozulmus_satirlar"
_borsa_veri_kaydet_halka_arz_limit "$limit"
```

Not: `arz_tip` ve `odeme` string degerlerdir, `_borsa_sayi_temizle` UYGULANMAZ. Limit temizleme ve zaman damgasi `_borsa_veri_kaydet_halka_arz_limit` tarafindan yapilir (Bolum 6.6).

### 7.6 adaptor_halka_arz_talepler Degisikligi

> Fonksiyon: `adaptor_halka_arz_talepler()` — satir 1321

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 1353):
#   local satirlar=""
# Bu pozisyon "kayit bulunamadi" kontrolunden ONCE oldugu icin,
# tablo bossa bile array temizlenmis olur. "kayit bulunamadi"
# yolundaki return 0 sifirlanmis (bos) array ile doner.
_borsa_veri_sifirla_halka_arz_talepler

# DONGU ICINDE — asagidaki satirdan HEMEN SONRA eklenir (satir 1395):
#   local satir="${ad}\t${tarih}\t${lot}\t..."
_borsa_veri_kaydet_talep "$talep_id" "${ad:-}" "${tarih:-}" "${lot:-}" "${fiyat:-}" "${tutar:-}" "${durum:-}"

# ZAMAN — asagidaki satirdan HEMEN ONCE eklenir (satir 1406):
#   cekirdek_yazdir_halka_arz_talepler "$ADAPTOR_ADI" "$cozulmus_satirlar"
_BORSA_VERI_TALEPLER_ZAMAN=$(date +%s)
```

Not: `tarih` string olarak saklanir (DD.MM.YYYY formati, donusum YAPILMAZ). Lot/fiyat/tutar temizleme `_borsa_veri_kaydet_talep` tarafindan yapilir (Bolum 6.6).

### 7.7 adaptor_halka_arz_talep Degisikligi

> Fonksiyon: `adaptor_halka_arz_talep()` — satir 1415

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 1428):
#   _ziraat_aktif_hesap_kontrol || return 1
_borsa_veri_sifirla_son_halka_arz

# KURU CALISTIR — asagidaki satirdan HEMEN ONCE eklenir (satir 1615):
#   return 0
_borsa_veri_kaydet_son_halka_arz "1" "talep" \
    "Kuru calistirma — talep gonderilmedi" "$ipo_adi" "$ipo_id" "$lot" "${fiyat:-0}" ""

# BASARI YOLLARI — 2 basari noktasi:
#   1. FinishButton sonrasi (satir 1699): return 0
#   2. Redirect tespiti (satir 1725): return 0
_borsa_veri_kaydet_son_halka_arz "1" "talep" \
    "Talep kabul edildi" "$ipo_adi" "$ipo_id" "$lot" "${fiyat:-0}" ""

# HATA YOLLARI — her return 1'den once:
_borsa_veri_kaydet_son_halka_arz "0" "talep" \
    "${hata_metni:-Talep reddedildi}" "${ipo_adi:-}" "${ipo_id:-}" "$lot" "" ""
```

### 7.8 adaptor_halka_arz_iptal Degisikligi

> Fonksiyon: `adaptor_halka_arz_iptal()` — satir 1745

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 1759):
#   _ziraat_log "Halka arz talebi iptal ediliyor. Talep ID: $talep_id"
_borsa_veri_sifirla_son_halka_arz

# ARA HATA YOLLARI — sifirla (1759) ile basari/hata bloklari (1832) arasinda
# 2 return 1 noktasi: IPO ID bulunamadi (1794), iptal yaniti bos (1815).
# Her birinden HEMEN ONCE:
_borsa_veri_kaydet_son_halka_arz "0" "iptal" "Iptal basarisiz" "" "" "" "" "$talep_no"
# Ozellikle satir 1815 (yanit bos) kritiktir: POST gonderilmis olabilir.

# BASARI — satir 1832'den HEMEN ONCE:
_borsa_veri_kaydet_son_halka_arz "1" "iptal" "${mesaj:-Talep iptal edildi}" "" "$ipo_id" "" "" "$talep_no"

# HATA — satir 1840'dan HEMEN ONCE:
_borsa_veri_kaydet_son_halka_arz "0" "iptal" "${hata_mesaj:-Iptal basarisiz}" "" "" "" "" "$talep_no"

# BILINMEYEN DURUM — satir 1848'den HEMEN ONCE:
_borsa_veri_kaydet_son_halka_arz "0" "iptal" "${mesaj2:-Bilinmeyen iptal sonucu}" "" "" "" "" "$talep_no"
```

### 7.9 adaptor_halka_arz_guncelle Degisikligi

> Fonksiyon: `adaptor_halka_arz_guncelle()` — satir 1856

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 1875):
#   _ziraat_log "Halka arz talebi guncelleniyor..."
_borsa_veri_sifirla_son_halka_arz

# ARA HATA YOLLARI — sifirla (1875) ile basari/hata bloklari (1976) arasinda
# 3 return 1 noktasi: IPO ID bulunamadi (1902), minimum lot yetersiz (1931),
# guncelleme yaniti bos (1957).
# Her birinden HEMEN ONCE:
_borsa_veri_kaydet_son_halka_arz "0" "guncelle" "Guncelleme basarisiz" "" "" "$yeni_lot" "" "$talep_no"
# Ozellikle satir 1957 (yanit bos) kritiktir: POST gonderilmis olabilir.

# BASARI — satir 1976'dan HEMEN ONCE:
_borsa_veri_kaydet_son_halka_arz "1" "guncelle" \
    "${mesaj:-Talep guncellendi}" "" "$ipo_id" "$yeni_lot" "$fiyat" "$talep_no"

# HATA — satir 1984'ten HEMEN ONCE:
_borsa_veri_kaydet_son_halka_arz "0" "guncelle" \
    "${hata_mesaj:-Guncelleme basarisiz}" "" "" "$yeni_lot" "" "$talep_no"

# BILINMEYEN DURUM — satir 1991'den HEMEN ONCE:
_borsa_veri_kaydet_son_halka_arz "0" "guncelle" \
    "${mesaj2:-Bilinmeyen guncelleme sonucu}" "" "" "$yeni_lot" "" "$talep_no"
```

## 8. Kullanim Ornekleri

### 8.1 Robot Motorundan Bakiye Kontrolu

```bash
adaptor_bakiye > /dev/null    # ekrana yazma, sadece veriyi doldur
local kalan="${_BORSA_VERI_BAKIYE[nakit]}"
if (( $(echo "$kalan > 1000" | bc -l) )); then
    echo "Yeterli bakiye var: $kalan TL"
fi
```

### 8.2 Strateji Katmanindan Hisse Kontrolu

```bash
adaptor_portfoy > /dev/null
if [[ -n "${_BORSA_VERI_HISSE_LOT[THYAO]:-}" ]]; then
    echo "THYAO: ${_BORSA_VERI_HISSE_LOT[THYAO]} lot var"
fi
```

### 8.3 Emir Sonrasi Dogrulama

```bash
adaptor_emir_gonder "THYAO" "alis" "10" "312.50"
if [[ "${_BORSA_VERI_SON_EMIR[basarili]}" == "1" ]]; then
    echo "Emir gonderildi: ${_BORSA_VERI_SON_EMIR[referans]}"
fi
```

### 8.4 Halka Arz Talep Sonrasi Kontrol

```bash
adaptor_halka_arz_talep "XYZ" "100"
if [[ "${_BORSA_VERI_SON_HALKA_ARZ[basarili]}" == "1" ]]; then
    echo "Talep kabul: ${_BORSA_VERI_SON_HALKA_ARZ[ipo_adi]}, ${_BORSA_VERI_SON_HALKA_ARZ[lot]} lot"
fi
```

### 8.5 Bekleyen Emir Kontrolu

```bash
adaptor_emirleri_listele > /dev/null
for ref in "${_BORSA_VERI_EMIRLER[@]}"; do
    if [[ "${_BORSA_VERI_EMIR_IPTAL_VAR[$ref]}" == "1" ]]; then
        echo "Iptal edilebilir: $ref (${_BORSA_VERI_EMIR_SEMBOL[$ref]})"
    fi
done
```

### 8.6 Talep Listesi ve Tutar Toplami

```bash
adaptor_halka_arz_talepler > /dev/null
local toplam_tutar="0"
for tid in "${_BORSA_VERI_TALEPLER[@]}"; do
    local tutar="${_BORSA_VERI_TALEP_TUTAR[$tid]:-0}"
    if [[ -n "$tutar" ]]; then
        toplam_tutar=$(echo "$toplam_tutar + $tutar" | bc -l)
    fi
    echo "${_BORSA_VERI_TALEP_ADI[$tid]}: ${_BORSA_VERI_TALEP_LOT[$tid]} lot, $tutar TL"
done
echo "Toplam: $toplam_tutar TL"
```

## 9. Uygulama Sirasi

### 9.1 Adim 1 — Cekirdek Altyapi

`bashrc.d/borsa/cekirdek.sh` icerisine:
- `declare -gA _CEKIRDEK_AKTIF_HESAPLAR` satirindan sonra (satir 42): Tum `declare -gA/ga/g` veri tanimlari (Bolum 4)
- `borsa()` fonksiyonundan once (satir 635 civari): Tum yardimci fonksiyonlar — temizleme, sifirlama, gecerlilik ve merkezi veri kayit fonksiyonlari (Bolum 6)

### 9.2 Adim 2 — Bakiye ve Portfoy

`bashrc.d/borsa/adaptorler/ziraat.sh` icerisinde `adaptor_bakiye` (satir 441) ve `adaptor_portfoy` (satir 476) fonksiyonlarina merkezi kaydet cagrilari eklenir. Ekran ciktilari degismez. Test: bakiye sonrasi `echo "${_BORSA_VERI_BAKIYE[nakit]}"` kontrolu.

### 9.3 Adim 3 — Emirler

`bashrc.d/borsa/adaptorler/ziraat.sh` icerisinde `adaptor_emirleri_listele` (satir 584), `adaptor_emir_gonder` (satir 879) ve `adaptor_emir_iptal` (satir 724) fonksiyonlarina merkezi kaydet cagrilari eklenir.

### 9.4 Adim 4 — Halka Arz

`bashrc.d/borsa/adaptorler/ziraat.sh` icerisinde `adaptor_halka_arz_liste` (satir 1220) ve `adaptor_halka_arz_talepler` (satir 1321) fonksiyonlarina merkezi kaydet cagrilari eklenir. `adaptor_halka_arz_talep` (satir 1415), `adaptor_halka_arz_iptal` (satir 1745) ve `adaptor_halka_arz_guncelle` (satir 1856) fonksiyonlarina `_borsa_veri_kaydet_son_halka_arz` cagrilari eklenir.

### 9.5 Adim 5 — Entegrasyon Testi

Tum fonksiyonlar cagrilip array degerleri dogrulanir. `> /dev/null` ile sessiz calistirma test edilir.

Test kontrol listesi:

```bash
# 1. Bakiye testi
adaptor_bakiye > /dev/null
[[ -n "${_BORSA_VERI_BAKIYE[nakit]:-}" ]] && echo "GECTI: bakiye.nakit" || echo "KALDI: bakiye.nakit"
[[ "${_BORSA_VERI_BAKIYE[nakit]}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && echo "GECTI: bakiye.format" || echo "KALDI: bakiye.format"

# 2. Portfoy testi
adaptor_portfoy > /dev/null
[[ ${#_BORSA_VERI_SEMBOLLER[@]} -gt 0 ]] && echo "GECTI: portfoy.sembol" || echo "KALDI: portfoy.sembol"

# 3. Emir testi
adaptor_emirleri_listele > /dev/null
echo "Emir sayisi: ${#_BORSA_VERI_EMIRLER[@]}"

# 4. Halka arz testi
adaptor_halka_arz_liste > /dev/null
echo "Halka arz sayisi: ${#_BORSA_VERI_HALKA_ARZ_LISTESI[@]}"
echo "Limit: ${_BORSA_VERI_HALKA_ARZ_LIMIT:-bos}"

# 5. Halka arz talepler testi
adaptor_halka_arz_talepler > /dev/null
for tid in "${_BORSA_VERI_TALEPLER[@]}"; do
    echo "Talep: ${_BORSA_VERI_TALEP_ADI[$tid]}, Tarih: ${_BORSA_VERI_TALEP_TARIH[$tid]}, Lot: ${_BORSA_VERI_TALEP_LOT[$tid]}"
done

# 6. Emir gonder testi (kuru calistirma)
KURU_CALISTIR=1 adaptor_emir_gonder "TEST" "alis" "1" "10.00" > /dev/null
[[ "${_BORSA_VERI_SON_EMIR[basarili]}" == "1" ]] && echo "GECTI: kuru_emir" || echo "KALDI: kuru_emir"
```
