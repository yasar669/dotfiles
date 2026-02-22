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
  +-> _BORSA_VERI_BAKIYE["nakit"]="45230.50"       # yapisal kayit
  +-> _BORSA_VERI_BAKIYE["hisse"]="124518.12"       # yapisal kayit
  +-> _BORSA_VERI_BAKIYE["toplam"]="169748.62"       # yapisal kayit
  +-> cekirdek_yazdir_portfoy ...                    # ekrana yazdir (degismez)
```

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
    local deger="$1"
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
    local deger="$1"
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
    local grup="$1"
    local max_saniye="$2"

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

## 7. Adaptor Degisiklikleri

> Dosya: `bashrc.d/borsa/adaptorler/ziraat.sh` (tum 7.x bolumleri)

Mevcut fonksiyonlara ekleme yapilir. Hicbir echo satiri silinmez veya degistirilmez.

### 7.1 adaptor_bakiye Degisikligi

> Fonksiyon: `adaptor_bakiye()` — satir 441

Fonksiyon baslangicinda sifirlama, `cekirdek_yazdir_portfoy` cagrisindan ONCE array'e kayit eklenir:

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 452):
#   if echo "$portfoy_yaniti" | grep -q 'Toplam'; then
_borsa_veri_sifirla_bakiye

# VERI KAYDI — asagidaki satirdan HEMEN ONCE eklenir (satir 471):
#   cekirdek_yazdir_portfoy "$ADAPTOR_ADI" "$nakit" "$hisse" "$toplam"
_BORSA_VERI_BAKIYE[nakit]=$(_borsa_sayi_temizle "$nakit")
_BORSA_VERI_BAKIYE[hisse]=$(_borsa_sayi_temizle "$hisse")
_BORSA_VERI_BAKIYE[toplam]=$(_borsa_sayi_temizle "$toplam")
_BORSA_VERI_BAKIYE[zaman]=$(date +%s)
```

### 7.2 adaptor_portfoy Degisikligi

> Fonksiyon: `adaptor_portfoy()` — satir 483

Fonksiyon baslangicinda sifirlama, hisse parse dongusu icerisinde array'e kayit eklenir:

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 494):
#   local portfoy_yaniti="$_ziraat_portfoy_html"
_borsa_veri_sifirla_portfoy

# DONGU ICINDE — asagidaki satirdan HEMEN SONRA eklenir (satir 557):
#   printf -v satir_fmt "%s\t%s\t%s\t%s\t%s\t%s\t%s" \
#       "$sembol" "$lot" "$son_fiyat" "$piy_degeri" "$maliyet" "$kar_zarar" "$kar_yuzde"
_BORSA_VERI_SEMBOLLER+=("$sembol")
_BORSA_VERI_HISSE_LOT["$sembol"]=$(_borsa_sayi_temizle "$lot")
_BORSA_VERI_HISSE_FIYAT["$sembol"]=$(_borsa_sayi_temizle "$son_fiyat")
_BORSA_VERI_HISSE_DEGER["$sembol"]=$(_borsa_sayi_temizle "$piy_degeri")
_BORSA_VERI_HISSE_MALIYET["$sembol"]=$(_borsa_sayi_temizle "$maliyet")
_BORSA_VERI_HISSE_KAR["$sembol"]=$(_borsa_sayi_temizle "$kar_zarar")
_BORSA_VERI_HISSE_KAR_YUZDE["$sembol"]=$(_borsa_yuzde_temizle "$kar_yuzde")

# ZAMAN — asagidaki satirdan HEMEN SONRA eklenir (satir 567):
#   done <<< "$hesap_idler"
_BORSA_VERI_PORTFOY_ZAMAN=$(date +%s)
```

Not: `kar_yuzde` degeri HTML'den `%12,50` veya `%-3,25` seklinde gelir. `_borsa_yuzde_temizle` fonksiyonu `%` isaretini soyar ve ondalik formatina cevirir (Bolum 5.3).

### 7.2.1 adaptor_portfoy Bakiye Verisi

> Fonksiyon: `adaptor_portfoy()` — satir 483

`adaptor_portfoy` fonksiyonu icinde de `nakit`, `hisse_toplam`, `toplam` degerleri parse edilir. Bu degerler `_BORSA_VERI_BAKIYE` array'ine de yazilir — boylece kullanici `adaptor_portfoy` cagirdiginda bakiye verisi de guncellenmis olur. Ayri bir `adaptor_bakiye` cagrisi gerekmez.

```bash
# BAKIYE KAYDI — asagidaki satirdan HEMEN SONRA eklenir (satir 502):
#   toplam=$(echo "$portfoy_yaniti" | grep -A 10 "$_ZIRAAT_METIN_TOPLAM" ...
# ve asagidaki satirdan ONCE (satir 505):
#   local hesap_idler
_borsa_veri_sifirla_bakiye
_BORSA_VERI_BAKIYE[nakit]=$(_borsa_sayi_temizle "$nakit")
_BORSA_VERI_BAKIYE[hisse]=$(_borsa_sayi_temizle "$hisse_toplam")
_BORSA_VERI_BAKIYE[toplam]=$(_borsa_sayi_temizle "$toplam")
_BORSA_VERI_BAKIYE[zaman]=$(date +%s)
```

Bu sayede robot motoru tek bir `adaptor_portfoy > /dev/null` cagrisiyla hem hisse hem bakiye verisine erisir.

### 7.3 adaptor_emirleri_listele Degisikligi

> Fonksiyon: `adaptor_emirleri_listele()` — satir 584

Dongu oncesinde sifirlama, dongu icerisinde her emir icin array'e kayit eklenir:

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN ONCE eklenir (satir 654):
#   while IFS= read -r blok; do
_borsa_veri_sifirla_emirler

# DONGU ICINDE — asagidaki satirdan HEMEN ONCE eklenir (satir 701):
#   iptal_var=""
#   echo "$blok" | grep -q 'btnListDailyDelete' && iptal_var="[*]"
_BORSA_VERI_EMIRLER+=("$ext_id")
_BORSA_VERI_EMIR_SEMBOL["$ext_id"]="${sembol_p:-}"

# Yon normalizasyonu: HTML'den gelen "Alış"/"Satış" -> "ALIS"/"SATIS"
local yon_normalize
case "${islem_p,,}" in
    al*) yon_normalize="ALIS" ;;
    sat*) yon_normalize="SATIS" ;;
    *) yon_normalize="${islem_p:-}" ;;
esac
_BORSA_VERI_EMIR_YON["$ext_id"]="$yon_normalize"

_BORSA_VERI_EMIR_LOT["$ext_id"]="${adet_p:-}"

# Fiyat: Turkce formatli olabilir, _borsa_sayi_temizle uygula
local fiyat_temiz
fiyat_temiz=$(_borsa_sayi_temizle "${fiyat_p:-0}")
if _borsa_sayi_gecerli_mi "$fiyat_temiz"; then
    _BORSA_VERI_EMIR_FIYAT["$ext_id"]="$fiyat_temiz"
else
    _BORSA_VERI_EMIR_FIYAT["$ext_id"]=""
fi

_BORSA_VERI_EMIR_DURUM["$ext_id"]="$durum_p"

# Iptal edilebilirlik gostergesi
if [[ -n "$iptal_var" ]]; then
    _BORSA_VERI_EMIR_IPTAL_VAR["$ext_id"]="1"
else
    _BORSA_VERI_EMIR_IPTAL_VAR["$ext_id"]="0"
fi

# ZAMAN — asagidaki satirdan HEMEN ONCE eklenir (satir 713):
#   if [[ "$bulunan" -eq 0 ]]; then
_BORSA_VERI_EMIRLER_ZAMAN=$(date +%s)
```

Kod, mevcut `durum_p` case blogunun sonucunu kullanir (Iletildi, Iptal, Gerceklesti, Kismi). Normalize edilmis haliyle array'e yazilir.

### 7.4 adaptor_emir_gonder Degisikligi

> Fonksiyon: `adaptor_emir_gonder()` — satir 879

Fonksiyonun baslangicinda sifirlama, her basari/basarisizlik yolunda kayit yapilir:

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 883):
#   local bildirim_turu="$5"
_borsa_veri_sifirla_son_emir

# KURU CALISTIR — asagidaki satirdan HEMEN ONCE eklenir (satir 982):
#   return 0
# (KURU CALISTIR blogu icindeki return 0)
_BORSA_VERI_SON_EMIR[basarili]="1"
_BORSA_VERI_SON_EMIR[referans]="KURU"
_BORSA_VERI_SON_EMIR[sembol]="$sembol"
_BORSA_VERI_SON_EMIR[yon]="${islem^^}"
_BORSA_VERI_SON_EMIR[lot]="$lot"
_BORSA_VERI_SON_EMIR[fiyat]="$fiyat"
_BORSA_VERI_SON_EMIR[piyasa_mi]="$piyasa_mi"
_BORSA_VERI_SON_EMIR[mesaj]="Kuru calistirma — emir gonderilmedi"

# BASARI YOLU 1 — Redirect tespiti
# Asagidaki satirdan HEMEN ONCE eklenir (satir 1104):
#   return 0
# (son_url redirect kontrolu blogu icindeki return 0)
_BORSA_VERI_SON_EMIR[basarili]="1"
_BORSA_VERI_SON_EMIR[referans]=""
_BORSA_VERI_SON_EMIR[sembol]="$sembol"
_BORSA_VERI_SON_EMIR[yon]="${islem^^}"
_BORSA_VERI_SON_EMIR[lot]="$lot"
_BORSA_VERI_SON_EMIR[fiyat]="$fiyat"
_BORSA_VERI_SON_EMIR[piyasa_mi]="$piyasa_mi"
_BORSA_VERI_SON_EMIR[mesaj]="Emir kabul edildi (redirect)"

# BASARI YOLU 2 — FinishButton sonrasi "kaydedilmis" tespiti
# Asagidaki satirdan HEMEN ONCE eklenir (satir 1177):
#   return 0
# (kaydedilmis/iletilmis grep blogu icindeki return 0)
_BORSA_VERI_SON_EMIR[basarili]="1"
_BORSA_VERI_SON_EMIR[referans]="${referans_no:-}"
_BORSA_VERI_SON_EMIR[sembol]="$sembol"
_BORSA_VERI_SON_EMIR[yon]="${islem^^}"
_BORSA_VERI_SON_EMIR[lot]="$lot"
_BORSA_VERI_SON_EMIR[fiyat]="$fiyat"
_BORSA_VERI_SON_EMIR[piyasa_mi]="$piyasa_mi"
_BORSA_VERI_SON_EMIR[mesaj]="Emiriniz kaydedilmistir"

# HATA YOLLARI — her return 1'den once eklenir.
# 3 hata noktasi var:
#   1. FinishButton sonrasi hata (satir 1193): return 1
#   2. Ne redirect ne onay sayfasi — gercek hata (satir 1207): return 1
#   3. Emir formu CSRF/hesap bulunamaz (satir 1010, 1015): return 1
_BORSA_VERI_SON_EMIR[basarili]="0"
_BORSA_VERI_SON_EMIR[sembol]="$sembol"
_BORSA_VERI_SON_EMIR[yon]="${islem^^}"
_BORSA_VERI_SON_EMIR[lot]="$lot"
_BORSA_VERI_SON_EMIR[fiyat]="$fiyat"
_BORSA_VERI_SON_EMIR[piyasa_mi]="$piyasa_mi"
_BORSA_VERI_SON_EMIR[mesaj]="${hata_metni:-Emir reddedildi}"
```

Onemli notlar:
- `piyasa_mi`: Piyasa emrinde "1", limit emirde "0". Robot motoru fiyatin anlamli olup olmadigini buradan anlar.
- `referans`: Sadece FinishButton basari yolunda parse edilir. Diger yollarda bos kalir.
- `yon`: Her zaman buyuk harf (`${islem^^}`): "ALIS" veya "SATIS".
- Hata durumunda da array doldurulur — robot motoru hangi emrin basarisiz oldugunu bilir.

### 7.4.1 adaptor_emir_iptal Degisikligi

> Fonksiyon: `adaptor_emir_iptal()` — satir 724

Hisse emri iptali sonrasinda `_BORSA_VERI_SON_EMIR` array'ine kayit yapilir. Ayni array kullanilir cunku iptal de bir emir islemidir — robot motoru `yon` anahtarindan "IPTAL" oldugunu anlar.

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 740):
#   _ziraat_log "Emir iptal ediliyor. Referans: $ext_id"
_borsa_veri_sifirla_son_emir

# BASARI — asagidaki satirdan HEMEN ONCE eklenir (satir 857):
#   return 0
# (SILMEOK veya IsSuccess=true blogu icindeki return 0)
_BORSA_VERI_SON_EMIR[basarili]="1"
_BORSA_VERI_SON_EMIR[referans]="$ext_id"
_BORSA_VERI_SON_EMIR[sembol]=""             # iptalden sembol bilinmez
_BORSA_VERI_SON_EMIR[yon]="IPTAL"
_BORSA_VERI_SON_EMIR[lot]=""
_BORSA_VERI_SON_EMIR[fiyat]=""
_BORSA_VERI_SON_EMIR[piyasa_mi]="0"
_BORSA_VERI_SON_EMIR[mesaj]="${mesaj:-Emir iptal edildi}"

# HATA — asagidaki satirdan HEMEN ONCE eklenir (satir 866):
#   return 1
# (IsError=true blogu icindeki return 1)
_BORSA_VERI_SON_EMIR[basarili]="0"
_BORSA_VERI_SON_EMIR[referans]="$ext_id"
_BORSA_VERI_SON_EMIR[yon]="IPTAL"
_BORSA_VERI_SON_EMIR[mesaj]="${hata:-Iptal basarisiz}"
```

Not: `yon="IPTAL"` ozel degeri, robot motoruna bu islemin bir emir gonderimi degil iptal oldugunu bildirir. Robot motoru `yon` degerini kontrol ederek akisi yonetir:

```bash
if [[ "${_BORSA_VERI_SON_EMIR[yon]}" == "IPTAL" ]]; then
    # iptal islemi sonucu
else
    # normal emir sonucu
fi
```

### 7.5 adaptor_halka_arz_liste Degisikligi

> Fonksiyon: `adaptor_halka_arz_liste()` — satir 1221

Parse dongusu icerisinde her halka arz icin array'e kayit eklenir:

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN ONCE eklenir (satir 1276):
#   while IFS= read -r blok; do
_borsa_veri_sifirla_halka_arz_liste

# DONGU ICINDE — asagidaki satirdan HEMEN SONRA eklenir (satir 1301):
#   local satir="${ipo_adi}\t${arz_tip:-Bilinmiyor}\t..."
_BORSA_VERI_HALKA_ARZ_LISTESI+=("$ipo_id")
_BORSA_VERI_HALKA_ARZ_ADI["$ipo_id"]="${ipo_adi:-}"
_BORSA_VERI_HALKA_ARZ_TIP["$ipo_id"]="${arz_tip:-}"
_BORSA_VERI_HALKA_ARZ_ODEME["$ipo_id"]="${odeme:-}"
_BORSA_VERI_HALKA_ARZ_DURUM["$ipo_id"]="${durum:-AKTIF}"

# LIMIT + ZAMAN — asagidaki satirdan HEMEN ONCE eklenir (satir 1311):
#   cekirdek_yazdir_halka_arz_liste "$ADAPTOR_ADI" "$limit" "$cozulmus_satirlar"
# Limit degeri icin _borsa_sayi_temizle uygula
if [[ -n "$limit" ]]; then
    local limit_temiz
    limit_temiz=$(_borsa_sayi_temizle "$limit")
    if _borsa_sayi_gecerli_mi "$limit_temiz"; then
        _BORSA_VERI_HALKA_ARZ_LIMIT="$limit_temiz"
    else
        _BORSA_VERI_HALKA_ARZ_LIMIT=""
    fi
else
    _BORSA_VERI_HALKA_ARZ_LIMIT=""
fi

_BORSA_VERI_HALKA_ARZ_ZAMAN=$(date +%s)
```

Not: `arz_tip` ve `odeme` string degerlerdir, `_borsa_sayi_temizle` UYGULANMAZ. Parse basarisiz olursa bos string kalir ("Bilinmiyor" YAZILMAZ — o sadece ekran ciktisinda kullanilir).

### 7.6 adaptor_halka_arz_talepler Degisikligi

> Fonksiyon: `adaptor_halka_arz_talepler()` — satir 1321

Parse dongusu icerisinde her talep icin array'e kayit eklenir:

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN ONCE eklenir (satir 1373):
#   while IFS= read -r blok; do
_borsa_veri_sifirla_halka_arz_talepler

# DONGU ICINDE — asagidaki satirdan HEMEN SONRA eklenir (satir 1404):
#   local satir="${ad}\t${tarih}\t${lot}\t..."
_BORSA_VERI_TALEPLER+=("$talep_id")
_BORSA_VERI_TALEP_ADI["$talep_id"]="${ad:-}"
_BORSA_VERI_TALEP_TARIH["$talep_id"]="${tarih:-}"

# Lot: tamsayi ama binlik ayracli olabilir
local lot_temiz
lot_temiz=$(_borsa_sayi_temizle "${lot:-0}")
# Lot tamsayi olmali — ondalik kismi at
lot_temiz="${lot_temiz%%.*}"
_BORSA_VERI_TALEP_LOT["$talep_id"]="$lot_temiz"

# Fiyat
local fiyat_temiz
fiyat_temiz=$(_borsa_sayi_temizle "${fiyat:-0}")
if _borsa_sayi_gecerli_mi "$fiyat_temiz"; then
    _BORSA_VERI_TALEP_FIYAT["$talep_id"]="$fiyat_temiz"
else
    _BORSA_VERI_TALEP_FIYAT["$talep_id"]=""
fi

# Tutar
local tutar_temiz
tutar_temiz=$(_borsa_sayi_temizle "${tutar:-0}")
if _borsa_sayi_gecerli_mi "$tutar_temiz"; then
    _BORSA_VERI_TALEP_TUTAR["$talep_id"]="$tutar_temiz"
else
    _BORSA_VERI_TALEP_TUTAR["$talep_id"]=""
fi

_BORSA_VERI_TALEP_DURUM["$talep_id"]="${durum:-}"

# ZAMAN — asagidaki satirdan HEMEN ONCE eklenir (satir 1410):
#   cekirdek_yazdir_halka_arz_talepler "$ADAPTOR_ADI" "$cozulmus_satirlar"
_BORSA_VERI_TALEPLER_ZAMAN=$(date +%s)
```

Not: `tarih` string olarak saklanir (DD.MM.YYYY formati, donusum YAPILMAZ).

### 7.7 adaptor_halka_arz_talep Degisikligi

> Fonksiyon: `adaptor_halka_arz_talep()` — satir 1415

Talep gonderimi sonrasinda `_BORSA_VERI_SON_HALKA_ARZ` array'ine kayit yapilir:

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 1424):
#   _ziraat_aktif_hesap_kontrol || return 1
# (parametre ve sayi kontrolunden sonra, cookie_dosyasi'ndan once)
_borsa_veri_sifirla_son_halka_arz

# KURU CALISTIR — asagidaki satirdan HEMEN ONCE eklenir (satir 1638):
#   return 0
# (KURU CALISTIR blogu icindeki return 0)
_BORSA_VERI_SON_HALKA_ARZ[basarili]="1"
_BORSA_VERI_SON_HALKA_ARZ[islem]="talep"
_BORSA_VERI_SON_HALKA_ARZ[ipo_adi]="$ipo_adi"
_BORSA_VERI_SON_HALKA_ARZ[ipo_id]="$ipo_id"
_BORSA_VERI_SON_HALKA_ARZ[lot]="$lot"
_BORSA_VERI_SON_HALKA_ARZ[fiyat]="${fiyat:-0}"
_BORSA_VERI_SON_HALKA_ARZ[mesaj]="Kuru calistirma — talep gonderilmedi"

# BASARI YOLLARI — 2 basari noktasi var:
#   1. FinishButton sonrasi "kaydedilmis" tespiti (satir 1701): return 0
#   2. Redirect tespiti (satir 1718): return 0
# Her ikisinde de asagidaki satirdan HEMEN ONCE eklenir:
#   return 0
_BORSA_VERI_SON_HALKA_ARZ[basarili]="1"
_BORSA_VERI_SON_HALKA_ARZ[islem]="talep"
_BORSA_VERI_SON_HALKA_ARZ[ipo_adi]="$ipo_adi"
_BORSA_VERI_SON_HALKA_ARZ[ipo_id]="$ipo_id"
_BORSA_VERI_SON_HALKA_ARZ[lot]="$lot"
_BORSA_VERI_SON_HALKA_ARZ[fiyat]="${fiyat:-0}"
_BORSA_VERI_SON_HALKA_ARZ[mesaj]="Talep kabul edildi"

# HATA YOLLARI — her return 1'den once eklenir.
# 5+ hata noktasi var (sayfa alinamadi, login, arz bulunamadi, CSRF, dogrulama, bilinmeyen durum).
# Hepsinde asagidaki satirdan HEMEN ONCE:
#   return 1
_BORSA_VERI_SON_HALKA_ARZ[basarili]="0"
_BORSA_VERI_SON_HALKA_ARZ[islem]="talep"
_BORSA_VERI_SON_HALKA_ARZ[ipo_adi]="${ipo_adi:-}"
_BORSA_VERI_SON_HALKA_ARZ[ipo_id]="${ipo_id:-}"
_BORSA_VERI_SON_HALKA_ARZ[lot]="$lot"
_BORSA_VERI_SON_HALKA_ARZ[mesaj]="${hata_metni:-Talep reddedildi}"
```

### 7.8 adaptor_halka_arz_iptal Degisikligi

> Fonksiyon: `adaptor_halka_arz_iptal()` — satir 1745

Iptal isleminden sonra `_BORSA_VERI_SON_HALKA_ARZ` array'ine kayit yapilir:

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 1761):
#   _ziraat_log "Halka arz talebi iptal ediliyor. Talep ID: $talep_id"
_borsa_veri_sifirla_son_halka_arz

# BASARI — asagidaki satirdan HEMEN ONCE eklenir (satir 1832):
#   return 0
# (IsSuccess=true blogu icindeki return 0)
_BORSA_VERI_SON_HALKA_ARZ[basarili]="1"
_BORSA_VERI_SON_HALKA_ARZ[islem]="iptal"
_BORSA_VERI_SON_HALKA_ARZ[talep_id]="$talep_no"
_BORSA_VERI_SON_HALKA_ARZ[ipo_id]="$ipo_id"
_BORSA_VERI_SON_HALKA_ARZ[mesaj]="${mesaj:-Talep iptal edildi}"

# HATA — asagidaki satirdan HEMEN ONCE eklenir (satir 1839):
#   return 1
# (IsError=true blogu icindeki return 1)
_BORSA_VERI_SON_HALKA_ARZ[basarili]="0"
_BORSA_VERI_SON_HALKA_ARZ[islem]="iptal"
_BORSA_VERI_SON_HALKA_ARZ[talep_id]="$talep_no"
_BORSA_VERI_SON_HALKA_ARZ[mesaj]="${hata_mesaj:-Iptal basarisiz}"
```

### 7.9 adaptor_halka_arz_guncelle Degisikligi

> Fonksiyon: `adaptor_halka_arz_guncelle()` — satir 1856

Guncelleme isleminden sonra `_BORSA_VERI_SON_HALKA_ARZ` array'ine kayit yapilir:

```bash
# SIFIRLAMA — asagidaki satirdan HEMEN SONRA eklenir (satir 1870):
#   _ziraat_log "Halka arz talebi guncelleniyor..."
_borsa_veri_sifirla_son_halka_arz

# BASARI — asagidaki satirdan HEMEN ONCE eklenir (satir 1978):
#   return 0
# (IsSuccess=true blogu icindeki return 0)
_BORSA_VERI_SON_HALKA_ARZ[basarili]="1"
_BORSA_VERI_SON_HALKA_ARZ[islem]="guncelle"
_BORSA_VERI_SON_HALKA_ARZ[talep_id]="$talep_no"
_BORSA_VERI_SON_HALKA_ARZ[ipo_id]="$ipo_id"
_BORSA_VERI_SON_HALKA_ARZ[lot]="$yeni_lot"
_BORSA_VERI_SON_HALKA_ARZ[fiyat]="$fiyat"
_BORSA_VERI_SON_HALKA_ARZ[mesaj]="${mesaj:-Talep guncellendi}"

# HATA — asagidaki satirdan HEMEN ONCE eklenir (satir 1988):
#   return 1
# (IsError=true blogu icindeki return 1)
_BORSA_VERI_SON_HALKA_ARZ[basarili]="0"
_BORSA_VERI_SON_HALKA_ARZ[islem]="guncelle"
_BORSA_VERI_SON_HALKA_ARZ[talep_id]="$talep_no"
_BORSA_VERI_SON_HALKA_ARZ[lot]="$yeni_lot"
_BORSA_VERI_SON_HALKA_ARZ[mesaj]="${hata_mesaj:-Guncelleme basarisiz}"
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
- `borsa()` fonksiyonundan once (satir 635 civari): Tum yardimci fonksiyonlar (Bolum 6)

### 9.2 Adim 2 — Bakiye ve Portfoy

`bashrc.d/borsa/adaptorler/ziraat.sh` icerisinde `adaptor_bakiye` (satir 441) ve `adaptor_portfoy` (satir 483) fonksiyonlarina veri kaydi eklenir. Ekran ciktilari degismez. Test: bakiye sonrasi `echo "${_BORSA_VERI_BAKIYE[nakit]}"` kontrolu.

### 9.3 Adim 3 — Emirler

`bashrc.d/borsa/adaptorler/ziraat.sh` icerisinde `adaptor_emirleri_listele` (satir 584), `adaptor_emir_gonder` (satir 879) ve `adaptor_emir_iptal` (satir 724) fonksiyonlarina veri kaydi eklenir.

### 9.4 Adim 4 — Halka Arz

`bashrc.d/borsa/adaptorler/ziraat.sh` icerisinde `adaptor_halka_arz_liste` (satir 1221) ve `adaptor_halka_arz_talepler` (satir 1321) fonksiyonlarina veri kaydi eklenir. `adaptor_halka_arz_talep` (satir 1415), `adaptor_halka_arz_iptal` (satir 1745) ve `adaptor_halka_arz_guncelle` (satir 1856) fonksiyonlarina `_BORSA_VERI_SON_HALKA_ARZ` kaydi eklenir.

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
