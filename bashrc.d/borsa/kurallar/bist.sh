#!/bin/bash
# shellcheck shell=bash

# =======================================================
# Borsa Istanbul (BIST) Pay Piyasasi Kural Seti
# =======================================================
#
# Bu dosya BIST Pay Piyasasi'nin islem kurallarini icerir.
# Adaptor modulleri emir vermeden once bu fonksiyonlari
# cagirarak fiyat, saat ve emir kontrolu yapar.
#
# Kaynak: BIST resmi dokumanlari, Genelge No: 1525 ve guncellemeleri.
# Son guncelleme: 2026-02-20
#
# UYARI: BIST kurallari degisebilir. Degisiklik durumunda
# sadece bu dosyadaki sabitler guncellenir, adaptor kodlarina
# dokunulmaz.
#
# Yuklenme: cekirdek.sh tarafindan otomatik source edilir.
# Kullanim: bist_fiyat_adimi 85.45  -> 0.05
#           bist_seans_acik_mi      -> 0 (acik) / 1 (kapali)

# =======================================================
# BOLUM 1: SEANS SAATLERI (Pay Piyasasi - Normal Seans)
# =======================================================
#
# Pay Piyasasi gun ici seans yapisi:
#
#   09:40 - 10:00  Acilis Seansi (Acilis Muzayedesi)
#                  09:40-09:55 emir toplama
#                  09:55-10:00 eslesme (rastgele 30sn offset)
#
#   10:00 - 12:40  1. Seans (Surekli Muzayede)
#                  Emirler anlik eslestirilerek islem gorur.
#
#   12:40 - 14:00  Ogle Arasi (Tek Fiyat Seansi)
#                  12:40-13:55 emir toplama
#                  13:55-14:00 eslesme
#                  NOT: Ogle arasi tek fiyat seansi opsiyoneldir,
#                  bazi donem ve kosullarda uygulanmayabilir.
#
#   14:00 - 18:00  2. Seans (Surekli Muzayede)
#
#   18:00 - 18:10  Kapanis Seansi (Kapanis Muzayedesi)
#                  18:00-18:05 emir toplama
#                  18:05-18:10 eslesme + kapanis fiyatindan islem
#
# Tatil, yari gun, ozel seans durumlari:
#   - Cumartesi ve Pazar: KAPALI
#   - Resmi tatiller: KAPALI (29 Ekim, 19 Mayis, 23 Nisan, vb.)
#   - Ramazan ve Kurban Bayrami arife gunu: yari gun (sadece 1. seans)
#   - 31 Aralik: yari gun (bazi yillarda)

# Seans saatleri — SAAT:DAKIKA formatinda (HH:MM)
# Degisiklik olursa sadece bu degerleri guncelleyin.
_BIST_ACILIS_EMIR_TOPLAMA="09:40"
_BIST_ACILIS_ESLESME="09:55"
_BIST_SEANS1_BASLANGIC="10:00"
_BIST_SEANS1_BITIS="12:40"
_BIST_OGLE_EMIR_TOPLAMA="12:40"
_BIST_OGLE_ESLESME="13:55"
_BIST_SEANS2_BASLANGIC="14:00"
_BIST_SEANS2_BITIS="18:00"
_BIST_KAPANIS_EMIR_TOPLAMA="18:00"
_BIST_KAPANIS_ESLESME="18:05"
_BIST_KAPANIS_BITIS="18:10"

# Emir verilebilir seans araliklari (surekli muzayede + emir toplama)
# Her elemanin formati: "BASLANGIC BITIS ACIKLAMA"
_BIST_EMIR_ARALIKLARI=(
    "09:40 10:00 Acilis seansi (emir toplama)"
    "10:00 12:40 1. Seans (surekli muzayede)"
    "12:40 14:00 Ogle arasi (tek fiyat)"
    "14:00 18:00 2. Seans (surekli muzayede)"
    "18:00 18:05 Kapanis seansi (emir toplama)"
)

# =======================================================
# BOLUM 2: FIYAT ADIM TABLOSU (Tick Size)
# =======================================================
#
# BIST Pay Piyasasi'nda fiyatlar belirli adimlarda hareket eder.
# Fiyat araliklarina gore gecerli fiyat adimlari:
#
#   Fiyat Araligi (TL)    | Fiyat Adimi (TL)
#   ----------------------+------------------
#     0.01 -    19.99     |   0.01
#    20.00 -    49.99     |   0.02
#    50.00 -    99.99     |   0.05
#   100.00 -   249.99     |   0.10
#   250.00 -   499.99     |   0.25
#   500.00 -   999.99     |   0.50
#  1000.00 -  2499.99     |   1.00
#  2500.00 -     ...      |   2.50
#
# Ornek: AKBNK fiyati 85.45 TL ise adim 0.05'tir.
#        85.45, 85.50, 85.55 gecerlidir.
#        85.47 GECERSIZ (0.05'in kati degil).

# Fiyat adim tablosu — "TABAN_FIYAT TAVAN_FIYAT ADIM" formatinda
# bc ile karsilastirilir (kesirli sayi destegi).
_BIST_FIYAT_ADIM_TABLOSU=(
    "0.01     19.99     0.01"
    "20.00    49.99     0.02"
    "50.00    99.99     0.05"
    "100.00   249.99    0.10"
    "250.00   499.99    0.25"
    "500.00   999.99    0.50"
    "1000.00  2499.99   1.00"
    "2500.00  999999.99 2.50"
)

# =======================================================
# BOLUM 3: GUNLUK FIYAT DEGISIM LIMITLERI (Tavan/Taban)
# =======================================================
#
# BIST Pay Piyasasi'nda bir hissenin gunu icinde
# bir onceki kapanis fiyatina gore hareket edebilecegi
# maksimum oran sinirlidir.
#
# Pazar bazinda gunluk fiyat degisim limitleri:
#   Yildiz Pazar  : %10
#   Ana Pazar     : %10
#   Alt Pazar     : %10
#   Yakin Izleme  : %10
#   Piyasa Oncesi : %10
#
# NOT: SPK karari ile gecici olarak %7.5, %5, %15 vb.
# farkli limitler uygulanabilir. Boyle bir durumda
# asagidaki sabiti guncelleyin.

_BIST_GUNLUK_LIMIT_YUZDE="10"

# =======================================================
# BOLUM 4: PAZAR YAPISI VE PAZAR BAZLI KURALLAR
# =======================================================
#
# BIST Pay Piyasasi birden fazla pazardan olusur.
# Her pazarda islem saatleri, emir kabul kurallari ve kota farkliliklari vardir.
#
# --- PAZAR TANIMLARI ---
#
# 1) YILDIZ PAZAR (Star Market)
#    - BIST-30 ve BIST-100 endekslerindeki buyuk sirketler.
#    - Tam gun islem gorur: 1. Seans + 2. Seans.
#    - Tum emir turleri gecerlidir (LIMIT, PIYASA, KIE, GIE, TAR).
#    - Aciga satis SERBEST.
#    - Fiyat degisim limiti: %10.
#    - Ornek hisseler: THYAO, AKBNK, GARAN, EREGL, TUPRS, BIMAS.
#
# 2) ANA PAZAR (Main Market)
#    - Orta ve buyuk olcekli sirketler (BIST-100 disinda kalanlar).
#    - Tam gun islem gorur: 1. Seans + 2. Seans.
#    - Tum emir turleri gecerlidir.
#    - Aciga satis SERBEST.
#    - Fiyat degisim limiti: %10.
#
# 3) ALT PAZAR (Sub Market)
#    - Kucuk olcekli sirketler.
#    - Tam gun islem gorur: 1. Seans + 2. Seans.
#    - Tum emir turleri gecerlidir.
#    - Aciga satis SERBEST.
#    - Fiyat degisim limiti: %10.
#    - Dusuk likidite nedeniyle spread genis olabilir.
#
# 4) YAKIN IZLEME PAZARI (Watchlist Market)
#    -----------------------------------------------------------
#    EN ONEMLI FARK: SADECE TEK FIYAT SEANSI (Tek Seans)
#    -----------------------------------------------------------
#    - SPK veya BIST tarafindan izlemeye alinan sorunlu sirketler.
#    - Nedenler: iflas, tasfiye, agirlastirilmis denetim, tehiri, kotasyon kosullarini
#      saglamama, yatirimci zararini onleme.
#    - SADECE TEK FIYAT SEANSLARI ile islem gorur:
#        14:00 - 14:30  Emir Toplama
#        14:30 - 14:32  Eslesme (rastgele offset)
#      Yani gun icerisinde toplam ~32 dakika emir verilebilir.
#    - Surekli muzayede YOKTUR. Emirler anlık eslesmez,
#      tek fiyat belirlenip toplu eslesme yapilir.
#    - PIYASA emri kullanilamaz, sadece LIMIT emir gecerlidir.
#    - Aciga satis YASAKTIR.
#    - KIE ve GIE emirleri kullanilamaz, sadece GUN emri gecerlidir.
#    - Tarihli (TAR) emir de kullanilamaz.
#    - Fiyat degisim limiti: %10.
#    - Ornek: BRMEN, METUR, DGATE gibi gozalti/yakin izleme hisseleri.
#    - Bu pazardaki hisseler cok risklidir. Likiditesi dusuktur.
#
# 5) PIYASA ONCESI ISLEM PLATFORMU (POIP / Pre-Market)
#    - Halka arz oncesi islem goren paylar.
#    - Sadece tek fiyat seansi ile islem gorur.
#    - Sinirli emir turleri.
#    - Fiyat degisim limiti: %10.
#
# 6) NITELIKLI YATIRIMCI ISLEMI PAZARI (NYI)
#    - Sadece nitelikli yatirimcilara acik.
#    - Ozel islem kosullari vardir.
#
# 7) LOT ALTI PAZAR (Odd Lot Market)
#    - 1 lotun altindaki kusurat islemler icin.
#    - Sadece satis yapilabilir (satin alma YAPILMAZ).
#    - Guncelleme: 2024'ten itibaren bazi donemler lot alti
#      alim da acilmistir. Kontrol ediniz.

# --- Pazar bazli fiyat degisim limitleri ---
# Format: "PAZAR_KODU LIMIT_YUZDE"
_BIST_PAZAR_LIMITLERI=(
    "YILDIZ   10"
    "ANA      10"
    "ALT      10"
    "YAKIN    10"
    "POIP     10"
)

# --- Pazar bazli islem saatleri ---
# Normal pazarlar (Yildiz, Ana, Alt): tam gun seans
# Yakin Izleme: sadece tek fiyat seansi
# Format: "PAZAR_KODU BASLANGIC BITIS SEANS_TURU"
_BIST_PAZAR_SEANSLARI=(
    "YILDIZ  09:40  18:10  TAMGUN"
    "ANA     09:40  18:10  TAMGUN"
    "ALT     09:40  18:10  TAMGUN"
    "YAKIN   14:00  14:32  TEKFIYAT"
    "POIP    14:00  14:32  TEKFIYAT"
)

# --- Yakin Izleme Pazari ozel seans araliklari ---
# Yakin Izleme'de SADECE asagidaki zaman dilimlerinde emir verilebilir.
_BIST_YAKIN_IZLEME_ARALIKLARI=(
    "14:00 14:30 Emir toplama (tek fiyat)"
    "14:30 14:32 Eslesme"
)

# --- Pazar bazli emir kisitlamalari ---
# Hangi pazarda hangi emir turu/suresi kullanilamaz?
#
# YAKIN IZLEME KISITLAMALARI:
#   - PIYASA emri: YASAK (sadece LIMIT gecerli)
#   - KIE emri: YASAK
#   - GIE emri: YASAK
#   - TAR emri: YASAK
#   - Aciga satis: YASAK
#   - Surekli muzayede: YOK (sadece tek fiyat seansi)

# Her pazar icin izin verilen emir turleri
# Format: "PAZAR_KODU EMIR_TURLERI_VIRGULLU"
_BIST_PAZAR_EMIR_TURLERI=(
    "YILDIZ  LIMIT,PIYASA"
    "ANA     LIMIT,PIYASA"
    "ALT     LIMIT,PIYASA"
    "YAKIN   LIMIT"
    "POIP    LIMIT"
)

# Her pazar icin izin verilen emir sureleri
# Format: "PAZAR_KODU SURELER_VIRGULLU"
_BIST_PAZAR_EMIR_SURELERI=(
    "YILDIZ  GUN,KIE,GIE,TAR"
    "ANA     GUN,KIE,GIE,TAR"
    "ALT     GUN,KIE,GIE,TAR"
    "YAKIN   GUN"
    "POIP    GUN"
)

# Her pazar icin aciga satis durumu
# Format: "PAZAR_KODU ACIGA_SATIS"   (SERBEST veya YASAK)
_BIST_PAZAR_ACIGA_SATIS=(
    "YILDIZ  SERBEST"
    "ANA     SERBEST"
    "ALT     SERBEST"
    "YAKIN   YASAK"
    "POIP    YASAK"
)

# =======================================================
# BOLUM 5: TAKAS KURALLARI (T+2 / NET TAKAS / BRUT TAKAS)
# =======================================================
#
# BIST Pay Piyasasi'nda islemler MKK (Merkezi Kayit Kurulusu)
# ve Takasbank uzerinden takasa alinir.
#
# --- TAKAS SURESI ---
#
#   Normal takas suresi: T+2 (2 is gunu)
#   Yani bugun (T) alinan hisseler, 2 is gunu sonra (T+2)
#   resmi olarak hesabiniza gecer.
#   Bugun satilan hissenin parasi da T+2'de hesabiniza yatar.
#
# --- NET TAKAS (Normal Durum) ---
#
#   Cogu hisse NET TAKAS ile islem gorur.
#   Net takasta:
#   - Ayni gun al-sat (gun ici / intraday) SERBESTTIR.
#   - Henuz takas tamamlanmamis (T gun) hisselerinizi satabilirsiniz.
#   - Kredili islem yapilabilir.
#   - Aciga satis yapilabilir (Yildiz, Ana, Alt Pazar).
#   - Teminata verilebilir.
#   - Takas neti alindiktan sonra (T+2) gercek devir yapilir.
#
# --- BRUT TAKAS (Kisitli Durum) ---
#
#   SPK veya BIST karariyla belirli hisselere uygulanan
#   ozel (agirlastirilmis) takas yontemidir.
#
#   Brut takasta:
#   - Aldiginiz hisseyi AYNI GUN SATAMAZSINIZ.
#     Hisse T+2'de hesabiniza gecene kadar beklemeniz gerekir.
#   - Sattiginiz hisseyi AYNI GUN ALAMAZSINIZ.
#     Para T+2'de hesabiniza gecene kadar beklemeniz gerekir.
#   - Gun ici (intraday) alis-satis YASAKTIR.
#   - Kredili islem YAPILAMAZ.
#   - Aciga satis YASAKTIR.
#   - Teminat olarak kullanilamaz.
#   - Para aninda tahsil edilir (kredisiz).
#
#   Brut takas uygulanan durumlar:
#   - Yakin Izleme Pazari'ndaki TUM hisseler.
#   - SPK tarafindan "C Grubu" olarak belirlenen hisseler.
#   - Manipulasyon suphesi, asiri volatilite, kotasyon ihlali,
#     mali tablo gecmistirmesi gibi nedenlerle SPK kararlarinda
#     brut takasa alinabilir.
#   - SPK periyodik olarak listeyi gunceller; bir hisse brut
#     takasa alinabilir veya cikartilabilir.
#
#   Pratikte ne anlama gelir:
#   - Gun ici trade yapamazsiniz. Swing/pozisyon trader
#     olmak zorundasiniz.
#   - Ornek: 100 lot BRMEN aldiniz, en erken 2 is gunu sonra
#     satabilirsiniz.
#   - Likidite cok dusuktur, spread genis olur.
#   - Araci kurum emir ekraninda "Brut Takas" veya "C Grubu"
#     uyarisi gosterir.
#
#   Araci kurum entegrasyonu:
#   - Araci kurumlar brut takas listesini kendi sunucularindan
#     saglar. Her adaptorun ayarlar dosyasinda ilgili URL
#     tanimlanmalidir.
#   - Emir verirken sunucu otomatik kontrol yapar ve brut
#     takastaki bir hisseyi ayni gun satmaniza izin vermez.
#   - Adaptor tarafinda ek kontrol opsiyoneldir cunku sunucu
#     zaten engelleyecektir. Ancak kullaniciya onceden bilgi
#     vermek icin bu liste sorgulanabilir.
#
# --- TAKAS SABITLERI ---

_BIST_TAKAS_SURESI=2          # T+2 (is gunu)
_BIST_TAKAS_TURU_NET="NET"    # Normal takas
_BIST_TAKAS_TURU_BRUT="BRUT"  # Agirlastirilmis takas

# =======================================================
# BOLUM 6: EMIR TURLERI VE SURELER
# =======================================================
#
# Gecerli emir turleri:
#   LIMIT   : Belirtilen fiyattan veya daha iyi fiyattan islenir.
#   PIYASA  : Emrin girildigi andaki en iyi fiyattan islenir.
#             Eslesmeyen kisim limit emre donusur.
#
# Gecerli emir sureleri:
#   GUN     : Seans sonuna kadar gecerli. Eslesmezse iptal olur.
#   KIE     : Kalani Iptal Et. Kismen eslesen kalan kisim iptal olur.
#   GIE     : Gerceklesmezse Iptal Et. Tamami eslesmezse tumu iptal.
#   TAR     : Tarihli. Belirtilen tarihe kadar gecerli (maks 365 gun).
#
# Desteklenen emir turleri (adaptor bazinda farklilik gosterebilir):
_BIST_EMIR_TURLERI=("LIMIT" "PIYASA")
_BIST_EMIR_SURELERI=("GUN" "KIE" "GIE" "TAR")

# =======================================================
# BOLUM 7: LOT VE ISLEM BIRIMLERI
# =======================================================
#
# Pay Piyasasi'nda islem birimi LOT'tur.
#   1 lot = 1 adet hisse senedi
#   Minimum emir miktari: 1 lot
#   Lot alti (kusurat) islemler: Lot Alti Pazar'da yapilir.
#   Maksimum emir miktari: Pazar bazinda degisir (genel sinir yok,
#     ancak bazi hisselerde ozel sinirlar olabilir).

_BIST_MIN_LOT=1

# =======================================================
# BOLUM 8: FONKSIYONLAR
# =======================================================

# -------------------------------------------------------
# bist_fiyat_adimi <fiyat>
# Verilen fiyat icin gecerli fiyat adimini dondurur.
# Ornek: bist_fiyat_adimi 85.45 -> 0.05
#        bist_fiyat_adimi 250   -> 0.25
# Donus: stdout'a adimi yazar. Gecersiz fiyat icin bos.
# -------------------------------------------------------
bist_fiyat_adimi() {
    local fiyat="$1"

    if [[ -z "$fiyat" ]]; then
        return 1
    fi

    local satir taban tavan adim
    for satir in "${_BIST_FIYAT_ADIM_TABLOSU[@]}"; do
        read -r taban tavan adim <<< "$satir"
        # bc ile karsilastirma: taban <= fiyat && fiyat <= tavan
        if (( $(echo "$fiyat >= $taban && $fiyat <= $tavan" | bc -l 2>/dev/null) )); then
            echo "$adim"
            return 0
        fi
    done

    # Fiyat tabloda bulunamadi (negatif veya sifir)
    return 1
}

# -------------------------------------------------------
# bist_fiyat_gecerli_mi <fiyat>
# Fiyatin dogru adimda olup olmadigini kontrol eder.
# Ornek: bist_fiyat_gecerli_mi 85.45 -> 0 (gecerli)
#        bist_fiyat_gecerli_mi 85.47 -> 1 (gecersiz)
# Donus: 0 = gecerli, 1 = gecersiz
# stdout: gecersiz ise hata mesaji yazar.
# -------------------------------------------------------
bist_fiyat_gecerli_mi() {
    local fiyat="$1"

    if [[ -z "$fiyat" ]]; then
        echo "HATA: Fiyat bos."
        return 1
    fi

    # Negatif veya sifir kontrolu
    if (( $(echo "$fiyat <= 0" | bc -l 2>/dev/null) )); then
        echo "HATA: Fiyat sifir veya negatif olamaz: $fiyat"
        return 1
    fi

    local adim
    adim=$(bist_fiyat_adimi "$fiyat")
    if [[ -z "$adim" ]]; then
        echo "HATA: Fiyat icin adim belirlenemedi: $fiyat"
        return 1
    fi

    # fiyat / adim tam sayi mi kontrolu
    # Yontem: (fiyat * 100) mod (adim * 100) == 0
    # bc'de scale=0 ile modulus aliyoruz.
    local fiyat_kurus adim_kurus kalan
    fiyat_kurus=$(echo "scale=0; $fiyat * 100 / 1" | bc 2>/dev/null)
    adim_kurus=$(echo "scale=0; $adim * 100 / 1" | bc 2>/dev/null)
    kalan=$(echo "$fiyat_kurus % $adim_kurus" | bc 2>/dev/null)

    if [[ "$kalan" -ne 0 ]]; then
        # En yakin gecerli fiyatlari hesapla
        local asagi yukari
        asagi=$(echo "scale=2; ($fiyat_kurus - $kalan) / 100" | bc 2>/dev/null)
        yukari=$(echo "scale=2; ($fiyat_kurus - $kalan + $adim_kurus) / 100" | bc 2>/dev/null)
        echo "HATA: $fiyat TL gecersiz fiyat adimi. Adim: $adim TL. En yakin gecerli fiyatlar: $asagi veya $yukari"
        return 1
    fi

    return 0
}

# -------------------------------------------------------
# bist_fiyat_yuvarla <fiyat>
# Verilen fiyati en yakin gecerli fiyata (asagi) yuvarlar.
# Ornek: bist_fiyat_yuvarla 85.47  -> 85.45
#        bist_fiyat_yuvarla 85.45  -> 85.45 (degismez)
#        bist_fiyat_yuvarla 251.30 -> 251.25
# Donus: stdout'a yuvarlanmis fiyati yazar.
# -------------------------------------------------------
bist_fiyat_yuvarla() {
    local fiyat="$1"

    if [[ -z "$fiyat" ]]; then
        return 1
    fi

    local adim
    adim=$(bist_fiyat_adimi "$fiyat")
    if [[ -z "$adim" ]]; then
        return 1
    fi

    local fiyat_kurus adim_kurus kalan yuvarlanmis
    fiyat_kurus=$(echo "scale=0; $fiyat * 100 / 1" | bc 2>/dev/null)
    adim_kurus=$(echo "scale=0; $adim * 100 / 1" | bc 2>/dev/null)
    kalan=$(echo "$fiyat_kurus % $adim_kurus" | bc 2>/dev/null)
    yuvarlanmis=$(echo "scale=2; ($fiyat_kurus - $kalan) / 100" | bc 2>/dev/null)

    echo "$yuvarlanmis"
}

# -------------------------------------------------------
# bist_tavan_hesapla <kapanis_fiyati>
# Bir onceki kapanis fiyatina gore tavan fiyati hesaplar.
# Tavan = kapanis * (1 + limit_yuzde/100), fiyat adimina yuvarlanir.
# Ornek: bist_tavan_hesapla 85.00 -> 93.50
# -------------------------------------------------------
bist_tavan_hesapla() {
    local kapanis="$1"

    if [[ -z "$kapanis" ]]; then
        return 1
    fi

    local ham_tavan
    ham_tavan=$(echo "scale=4; $kapanis * (1 + $_BIST_GUNLUK_LIMIT_YUZDE / 100)" | bc 2>/dev/null)

    # Tavan yukarida olamaz, fiyat adimina asagi yuvarla
    local adim
    adim=$(bist_fiyat_adimi "$ham_tavan")
    if [[ -z "$adim" ]]; then
        echo "$ham_tavan"
        return 0
    fi

    local kurus adim_kurus kalan tavan
    kurus=$(echo "scale=0; $ham_tavan * 100 / 1" | bc 2>/dev/null)
    adim_kurus=$(echo "scale=0; $adim * 100 / 1" | bc 2>/dev/null)
    kalan=$(echo "$kurus % $adim_kurus" | bc 2>/dev/null)
    tavan=$(echo "scale=2; ($kurus - $kalan) / 100" | bc 2>/dev/null)

    echo "$tavan"
}

# -------------------------------------------------------
# bist_taban_hesapla <kapanis_fiyati>
# Bir onceki kapanis fiyatina gore taban fiyati hesaplar.
# Taban = kapanis * (1 - limit_yuzde/100), fiyat adimina yuvarlanir.
# Ornek: bist_taban_hesapla 85.00 -> 76.50
# -------------------------------------------------------
bist_taban_hesapla() {
    local kapanis="$1"

    if [[ -z "$kapanis" ]]; then
        return 1
    fi

    local ham_taban
    ham_taban=$(echo "scale=4; $kapanis * (1 - $_BIST_GUNLUK_LIMIT_YUZDE / 100)" | bc 2>/dev/null)

    # Taban asagida olamaz, fiyat adimina yukari yuvarla
    local adim
    adim=$(bist_fiyat_adimi "$ham_taban")
    if [[ -z "$adim" ]]; then
        echo "$ham_taban"
        return 0
    fi

    local kurus adim_kurus kalan taban
    kurus=$(echo "scale=0; $ham_taban * 100 / 1" | bc 2>/dev/null)
    adim_kurus=$(echo "scale=0; $adim * 100 / 1" | bc 2>/dev/null)
    kalan=$(echo "$kurus % $adim_kurus" | bc 2>/dev/null)
    if [[ "$kalan" -ne 0 ]]; then
        taban=$(echo "scale=2; ($kurus - $kalan + $adim_kurus) / 100" | bc 2>/dev/null)
    else
        taban=$(echo "scale=2; $kurus / 100" | bc 2>/dev/null)
    fi

    echo "$taban"
}

# -------------------------------------------------------
# bist_seans_acik_mi
# Borsanin su anda emir kabul edip etmedigini kontrol eder.
# - Hafta sonu: KAPALI
# - Seans saatleri disinda: KAPALI
# - Emir kabul saatleri icinde: ACIK
# Donus: 0 = acik (emir verilebilir), 1 = kapali
# stdout: durum mesaji yazar.
# -------------------------------------------------------
bist_seans_acik_mi() {
    local gun
    gun=$(date +%u)   # 1=Pazartesi ... 7=Pazar

    if [[ "$gun" -ge 6 ]]; then
        echo "KAPALI: Hafta sonu ($(date '+%A')). Borsa Pazartesi 09:40'ta acilir."
        return 1
    fi

    local simdi
    simdi=$(date +%H:%M)

    # simdi'yi dakikaya cevir
    local simdi_dk
    simdi_dk=$(( 10#${simdi%%:*} * 60 + 10#${simdi##*:} ))

    local aralik baslangic bitis aciklama
    for aralik in "${_BIST_EMIR_ARALIKLARI[@]}"; do
        read -r baslangic bitis aciklama <<< "$aralik"
        local bas_dk bit_dk
        bas_dk=$(( 10#${baslangic%%:*} * 60 + 10#${baslangic##*:} ))
        bit_dk=$(( 10#${bitis%%:*} * 60 + 10#${bitis##*:} ))

        if [[ "$simdi_dk" -ge "$bas_dk" ]] && [[ "$simdi_dk" -lt "$bit_dk" ]]; then
            echo "ACIK: $aciklama ($baslangic - $bitis)"
            return 0
        fi
    done

    # Seans araligi disinda — bir sonraki seansi bul
    local _sonraki_seans=""
    for aralik in "${_BIST_EMIR_ARALIKLARI[@]}"; do
        read -r baslangic bitis aciklama <<< "$aralik"
        local bas_dk
        bas_dk=$(( 10#${baslangic%%:*} * 60 + 10#${baslangic##*:} ))
        if [[ "$simdi_dk" -lt "$bas_dk" ]]; then
            _sonraki_seans="$baslangic ($aciklama)"
            break
        fi
    done

    if [[ -n "$_sonraki_seans" ]]; then
        echo "KAPALI: Seans arasi. Sonraki seans: $_sonraki_seans"
    else
        echo "KAPALI: Bugunluk islemler sona erdi. Yarin 09:40'ta acilir."
    fi
    return 1
}

# -------------------------------------------------------
# bist_seans_bilgi
# Tam seans tablosunu terminale yazdirir.
# Kullanim: borsa kurallar seans (planlanmis komut)
# -------------------------------------------------------
bist_seans_bilgi() {
    echo ""
    echo "=========================================================="
    echo "  BIST PAY PIYASASI - SEANS SAATLERI"
    echo "=========================================================="
    echo ""
    printf "  %-14s  %-14s  %s\n" "BASLANGIC" "BITIS" "SEANS"
    echo "  ----------------------------------------------------------"

    local aralik baslangic bitis aciklama
    for aralik in "${_BIST_EMIR_ARALIKLARI[@]}"; do
        read -r baslangic bitis aciklama <<< "$aralik"
        printf "  %-14s  %-14s  %s\n" "$baslangic" "$bitis" "$aciklama"
    done

    echo ""
    echo "  Kapanis eslesme : $_BIST_KAPANIS_ESLESME - $_BIST_KAPANIS_BITIS"
    echo "  Hafta sonu      : KAPALI"
    echo "=========================================================="

    # Anlık durum
    echo ""
    echo -n "  Su an: "
    bist_seans_acik_mi
    echo ""
}

# -------------------------------------------------------
# bist_fiyat_adimi_bilgi
# Fiyat adim tablosunu terminale yazdirir.
# Kullanim: borsa kurallar fiyat
# -------------------------------------------------------
bist_fiyat_adimi_bilgi() {
    echo ""
    echo "=========================================================="
    echo "  BIST PAY PIYASASI - FIYAT ADIM TABLOSU"
    echo "=========================================================="
    echo ""
    printf "  %-22s  %s\n" "FIYAT ARALIGI (TL)" "FIYAT ADIMI (TL)"
    echo "  ----------------------------------------------------------"

    local satir taban tavan adim
    for satir in "${_BIST_FIYAT_ADIM_TABLOSU[@]}"; do
        read -r taban tavan adim <<< "$satir"
        if [[ "$tavan" == "999999.99" ]]; then
            printf "  %10s - %-10s  %s\n" "$taban" "..." "$adim"
        else
            printf "  %10s - %-10s  %s\n" "$taban" "$tavan" "$adim"
        fi
    done

    echo ""
    echo "  Ornek: 85.45 TL -> adim $(bist_fiyat_adimi 85.45 2>/dev/null) TL"
    echo "  Ornek: 250.00 TL -> adim $(bist_fiyat_adimi 250 2>/dev/null) TL"
    echo "=========================================================="
    echo ""
}

# -------------------------------------------------------
# bist_pazar_bilgi [pazar_kodu]
# Pazar kurallarini terminale yazdirir.
# Parametresiz: tum pazarlarin ozet tablosu.
# Parametreli : ilgili pazarin detayli kurallari.
# Kullanim: borsa kurallar pazar
#           borsa kurallar pazar YAKIN
# -------------------------------------------------------
bist_pazar_bilgi() {
    local pazar_kodu="$1"

    if [[ -z "$pazar_kodu" ]]; then
        # --- TUM PAZARLARIN OZET TABLOSU ---
        echo ""
        echo "=========================================================="
        echo "  BIST PAY PIYASASI - PAZAR YAPISI"
        echo "=========================================================="
        echo ""
        printf "  %-10s  %-10s  %-8s  %-18s  %s\n" \
            "PAZAR" "SEANS" "LIMIT" "EMIR TURLERI" "ACIGA SATIS"
        echo "  ----------------------------------------------------------"

        local satir pazar baslangic bitis seans_turu
        for satir in "${_BIST_PAZAR_SEANSLARI[@]}"; do
            read -r pazar baslangic bitis seans_turu <<< "$satir"

            # Emir turlerini bul
            local emir_turleri=""
            local et_satir et_pazar et_turler
            for et_satir in "${_BIST_PAZAR_EMIR_TURLERI[@]}"; do
                read -r et_pazar et_turler <<< "$et_satir"
                if [[ "$et_pazar" == "$pazar" ]]; then
                    emir_turleri="$et_turler"
                    break
                fi
            done

            # Aciga satisi bul
            local aciga=""
            local as_satir as_pazar as_durum
            for as_satir in "${_BIST_PAZAR_ACIGA_SATIS[@]}"; do
                read -r as_pazar as_durum <<< "$as_satir"
                if [[ "$as_pazar" == "$pazar" ]]; then
                    aciga="$as_durum"
                    break
                fi
            done

            # Limiti bul
            local limit=""
            local l_satir l_pazar l_yuzde
            for l_satir in "${_BIST_PAZAR_LIMITLERI[@]}"; do
                read -r l_pazar l_yuzde <<< "$l_satir"
                if [[ "$l_pazar" == "$pazar" ]]; then
                    limit="%${l_yuzde}"
                    break
                fi
            done

            printf "  %-10s  %-10s  %-8s  %-18s  %s\n" \
                "$pazar" "$seans_turu" "$limit" "$emir_turleri" "$aciga"
        done

        echo ""
        echo "  TAMGUN   = 1. Seans + 2. Seans (09:40 - 18:10)"
        echo "  TEKFIYAT = Sadece tek fiyat seansi (14:00 - 14:32)"
        echo ""
        echo "  Detay icin: borsa kurallar pazar <PAZAR_KODU>"
        echo "  Ornek    : borsa kurallar pazar YAKIN"
        echo "=========================================================="
        echo ""
        return 0
    fi

    # --- Buyuk harfe cevir ---
    pazar_kodu="${pazar_kodu^^}"

    # --- TEK PAZAR DETAY ---
    local bulunan=0
    local satir pazar baslangic bitis seans_turu
    for satir in "${_BIST_PAZAR_SEANSLARI[@]}"; do
        read -r pazar baslangic bitis seans_turu <<< "$satir"
        if [[ "$pazar" == "$pazar_kodu" ]]; then
            bulunan=1
            break
        fi
    done

    if [[ "$bulunan" -eq 0 ]]; then
        echo "HATA: Bilinmeyen pazar kodu: $pazar_kodu"
        echo "Gecerli pazarlar: YILDIZ, ANA, ALT, YAKIN, POIP"
        return 1
    fi

    echo ""
    echo "=========================================================="
    echo "  BIST - $pazar_kodu PAZARI DETAY"
    echo "=========================================================="
    echo ""

    # Seans bilgisi
    echo "  Seans turu     : $seans_turu"
    echo "  Seans araligi  : $baslangic - $bitis"

    # Yakin Izleme ise ozel araliklari goster
    if [[ "$pazar_kodu" == "YAKIN" ]]; then
        echo ""
        echo "  --- Yakin Izleme Seans Detayi ---"
        local aralik yi_bas yi_bit yi_aciklama
        for aralik in "${_BIST_YAKIN_IZLEME_ARALIKLARI[@]}"; do
            read -r yi_bas yi_bit yi_aciklama <<< "$aralik"
            printf "  %-8s - %-8s  %s\n" "$yi_bas" "$yi_bit" "$yi_aciklama"
        done
        echo ""
        echo "  DIKKAT: Surekli muzayede YOKTUR."
        echo "  Emirler anlik eslesmez, tek fiyat seansi sonunda"
        echo "  toplu eslesme yapilir."
    fi

    echo ""

    # Emir turleri
    local et_satir et_pazar et_turler
    for et_satir in "${_BIST_PAZAR_EMIR_TURLERI[@]}"; do
        read -r et_pazar et_turler <<< "$et_satir"
        if [[ "$et_pazar" == "$pazar_kodu" ]]; then
            echo "  Emir turleri   : $et_turler"
            break
        fi
    done

    # Emir sureleri
    local es_satir es_pazar es_sureler
    for es_satir in "${_BIST_PAZAR_EMIR_SURELERI[@]}"; do
        read -r es_pazar es_sureler <<< "$es_satir"
        if [[ "$es_pazar" == "$pazar_kodu" ]]; then
            echo "  Emir sureleri  : $es_sureler"
            break
        fi
    done

    # Aciga satis
    local as_satir as_pazar as_durum
    for as_satir in "${_BIST_PAZAR_ACIGA_SATIS[@]}"; do
        read -r as_pazar as_durum <<< "$as_satir"
        if [[ "$as_pazar" == "$pazar_kodu" ]]; then
            echo "  Aciga satis    : $as_durum"
            break
        fi
    done

    # Fiyat limiti
    local l_satir l_pazar l_yuzde
    for l_satir in "${_BIST_PAZAR_LIMITLERI[@]}"; do
        read -r l_pazar l_yuzde <<< "$l_satir"
        if [[ "$l_pazar" == "$pazar_kodu" ]]; then
            echo "  Fiyat limiti   : %$l_yuzde"
            break
        fi
    done

    echo ""

    # Yakin Izleme uyarilari
    if [[ "$pazar_kodu" == "YAKIN" ]]; then
        echo "  *** UYARILAR ***"
        echo "  - Bu pazardaki hisseler cok RISKLIDIR."
        echo "  - Likiditesi son derece DUSUKTUR."
        echo "  - PIYASA emri KULLANILAMAZ, sadece LIMIT emir gecerli."
        echo "  - KIE, GIE, TAR emirleri KULLANILAMAZ."
        echo "  - Aciga satis YASAKTIR."
        echo "  - Surekli muzayede yoktur; tek fiyat seansi ile islem gorur."
        echo ""
    fi

    echo "=========================================================="
    echo ""
}

# -------------------------------------------------------
# bist_pazar_seans_acik_mi <pazar_kodu>
# Belirtilen pazarin su anda emir kabul edip etmedigini
# kontrol eder.
# Parametresiz: normal pazar (YILDIZ) kontrol edilir.
# Donus: 0 = acik, 1 = kapali
# stdout: durum mesaji yazar.
# -------------------------------------------------------
bist_pazar_seans_acik_mi() {
    local pazar_kodu="${1:-YILDIZ}"
    pazar_kodu="${pazar_kodu^^}"

    # Hafta sonu kontrolu
    local gun
    gun=$(date +%u)
    if [[ "$gun" -ge 6 ]]; then
        echo "KAPALI: Hafta sonu. Borsa Pazartesi acilir."
        return 1
    fi

    # Seans turunu bul
    local seans_turu="" baslangic="" bitis=""
    local satir s_pazar s_bas s_bit s_tur
    for satir in "${_BIST_PAZAR_SEANSLARI[@]}"; do
        read -r s_pazar s_bas s_bit s_tur <<< "$satir"
        if [[ "$s_pazar" == "$pazar_kodu" ]]; then
            seans_turu="$s_tur"
            baslangic="$s_bas"
            bitis="$s_bit"
            break
        fi
    done

    if [[ -z "$seans_turu" ]]; then
        echo "HATA: Bilinmeyen pazar: $pazar_kodu"
        return 1
    fi

    local simdi
    simdi=$(date +%H:%M)
    local simdi_dk
    simdi_dk=$(( 10#${simdi%%:*} * 60 + 10#${simdi##*:} ))

    if [[ "$seans_turu" == "TEKFIYAT" ]]; then
        # Yakin Izleme / POIP: sadece emir toplama saatinde acik
        local aralik yi_bas yi_bit yi_aciklama
        # Yakin izleme icin ozel araliklari kontrol et
        local bas_dk bit_dk
        bas_dk=$(( 10#${baslangic%%:*} * 60 + 10#${baslangic##*:} ))
        bit_dk=$(( 10#${bitis%%:*} * 60 + 10#${bitis##*:} ))

        if [[ "$simdi_dk" -ge "$bas_dk" ]] && [[ "$simdi_dk" -lt "$bit_dk" ]]; then
            echo "ACIK: $pazar_kodu - Tek fiyat seansi ($baslangic - $bitis)"
            return 0
        else
            echo "KAPALI: $pazar_kodu sadece $baslangic - $bitis arasinda islem gorur."
            return 1
        fi
    fi

    # Normal pazar (TAMGUN): genel seans kontrolu
    bist_seans_acik_mi
}

# -------------------------------------------------------
# bist_pazar_emir_kontrol <pazar_kodu> <emir_turu> <emir_suresi>
# Verilen emir turu ve suresinin bu pazarda gecerli olup
# olmadigini kontrol eder.
# Donus: 0 = gecerli, 1 = gecersiz
# stdout: gecersiz ise hata mesaji yazar.
# -------------------------------------------------------
bist_pazar_emir_kontrol() {
    local pazar_kodu="${1:-YILDIZ}"
    local emir_turu="${2:-LIMIT}"
    local emir_suresi="${3:-GUN}"

    pazar_kodu="${pazar_kodu^^}"
    emir_turu="${emir_turu^^}"
    emir_suresi="${emir_suresi^^}"

    local hata=0

    # Emir turu kontrolu
    local et_satir et_pazar et_turler
    for et_satir in "${_BIST_PAZAR_EMIR_TURLERI[@]}"; do
        read -r et_pazar et_turler <<< "$et_satir"
        if [[ "$et_pazar" == "$pazar_kodu" ]]; then
            if [[ ",$et_turler," != *",$emir_turu,"* ]]; then
                echo "HATA: $pazar_kodu pazarinda $emir_turu emri kullanilamaz. Gecerli: $et_turler"
                hata=1
            fi
            break
        fi
    done

    # Emir suresi kontrolu
    local es_satir es_pazar es_sureler
    for es_satir in "${_BIST_PAZAR_EMIR_SURELERI[@]}"; do
        read -r es_pazar es_sureler <<< "$es_satir"
        if [[ "$es_pazar" == "$pazar_kodu" ]]; then
            if [[ ",$es_sureler," != *",$emir_suresi,"* ]]; then
                echo "HATA: $pazar_kodu pazarinda $emir_suresi suresi kullanilamaz. Gecerli: $es_sureler"
                hata=1
            fi
            break
        fi
    done

    return "$hata"
}

# -------------------------------------------------------
# bist_takas_bilgi
# Takas kurallarini terminale yazdirir.
# Kullanim: borsa kurallar takas
# -------------------------------------------------------
bist_takas_bilgi() {
    echo ""
    echo "=========================================================="
    echo "  BIST PAY PIYASASI - TAKAS KURALLARI"
    echo "=========================================================="
    echo ""
    echo "  Takas suresi          : T+${_BIST_TAKAS_SURESI} (${_BIST_TAKAS_SURESI} is gunu)"
    echo ""
    echo "  --- NET TAKAS (Normal) ---"
    echo "  Gun ici al-sat        : SERBEST"
    echo "  Kredili islem          : SERBEST"
    echo "  Aciga satis            : SERBEST (Yildiz/Ana/Alt Pazar)"
    echo "  Teminata verme         : SERBEST"
    echo ""
    echo "  --- BRUT TAKAS (Kisitli) ---"
    echo "  Gun ici al-sat        : YASAK"
    echo "  Kredili islem          : YASAK"
    echo "  Aciga satis            : YASAK"
    echo "  Teminata verme         : YASAK"
    echo ""
    echo "  Brut takasta aldiginiz hisseyi ayni gun satamazsiniz."
    echo "  En erken T+${_BIST_TAKAS_SURESI} (${_BIST_TAKAS_SURESI} is gunu sonra) satabilirsiniz."
    echo ""
    echo "  Brut takas uygulanan hisseler:"
    echo "  - Yakin Izleme Pazari'ndaki tum hisseler"
    echo "  - SPK tarafindan C Grubu olarak belirlenen hisseler"
    echo "  - Manipulasyon suphesi, asiri volatilite, kotasyon"
    echo "    ihlali gibi nedenlerle SPK karariyla brut takasa"
    echo "    alinabilen hisseler"
    echo ""
    echo "  Araci kurum emir ekraninda \"Brut Takas\" veya"
    echo "  \"C Grubu\" uyarisi gosterir."
    echo "=========================================================="
    echo ""
}

# -------------------------------------------------------
# bist_emir_dogrula <fiyat> [--sessiz]
# Emir oncesi BIST kurallarini kontrol eder:
#   1. Fiyat gecerli adimda mi?
# NOT: Seans acik/kapali kontrolu yapilmaz. Emir seans disinda
# da gonderilebilir, borsa acildiginda islenir.
# --sessiz secenegi: sadece donus kodu doner, mesaj yazmaz.
# Donus: 0 = her sey uygun, 1 = sorun var
# -------------------------------------------------------
bist_emir_dogrula() {
    local fiyat="$1"
    local sessiz="$2"
    local hata=0

    # --- Fiyat adimi kontrolu ---
    local fiyat_sonuc
    if ! fiyat_sonuc=$(bist_fiyat_gecerli_mi "$fiyat"); then
        if [[ "$sessiz" != "--sessiz" ]]; then
            echo "$fiyat_sonuc"
        fi
        hata=1
    fi

    return "$hata"
}
