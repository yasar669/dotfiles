#!/bin/bash
# shellcheck shell=bash

# Veri Katmani
# Robot motoru ve strateji katmani icin programatik veri erisim katmani.
# Global veri yapilari (declare), yardimci fonksiyonlar (temizle, sifirla,
# gecerlilik) ve merkezi kaydet fonksiyonlarini icerir.
#
# Bu dosya cekirdek.sh tarafindan adaptorlerden once yuklenir.

# =======================================================
# Global Veri Yapilari
# =======================================================
# Adaptor fonksiyonlari (bakiye, portfoy, emirler vb) parse ettikleri
# verileri merkezi kaydet fonksiyonlari araciligiyla buraya yazar.

# Bakiye verileri (nakit, hisse, toplam — nokta ayracli)
declare -gA _BORSA_VERI_BAKIYE

# Portfoy verileri (hisse bazli)
declare -ga _BORSA_VERI_SEMBOLLER
declare -gA _BORSA_VERI_HISSE_LOT
declare -gA _BORSA_VERI_HISSE_FIYAT
declare -gA _BORSA_VERI_HISSE_DEGER
declare -gA _BORSA_VERI_HISSE_MALIYET
declare -gA _BORSA_VERI_HISSE_KAR
declare -gA _BORSA_VERI_HISSE_KAR_YUZDE
declare -g  _BORSA_VERI_PORTFOY_ZAMAN

# Emir verileri
declare -ga _BORSA_VERI_EMIRLER
declare -gA _BORSA_VERI_EMIR_SEMBOL
declare -gA _BORSA_VERI_EMIR_YON
declare -gA _BORSA_VERI_EMIR_LOT
declare -gA _BORSA_VERI_EMIR_FIYAT
declare -gA _BORSA_VERI_EMIR_DURUM
declare -gA _BORSA_VERI_EMIR_IPTAL_VAR
declare -g  _BORSA_VERI_EMIRLER_ZAMAN

# Halka arz liste verileri
declare -ga _BORSA_VERI_HALKA_ARZ_LISTESI
declare -gA _BORSA_VERI_HALKA_ARZ_ADI
declare -gA _BORSA_VERI_HALKA_ARZ_TIP
declare -gA _BORSA_VERI_HALKA_ARZ_ODEME
declare -gA _BORSA_VERI_HALKA_ARZ_DURUM
declare -g  _BORSA_VERI_HALKA_ARZ_LIMIT
declare -g  _BORSA_VERI_HALKA_ARZ_ZAMAN

# Halka arz talep verileri
declare -ga _BORSA_VERI_TALEPLER
declare -gA _BORSA_VERI_TALEP_ADI
declare -gA _BORSA_VERI_TALEP_TARIH
declare -gA _BORSA_VERI_TALEP_LOT
declare -gA _BORSA_VERI_TALEP_FIYAT
declare -gA _BORSA_VERI_TALEP_TUTAR
declare -gA _BORSA_VERI_TALEP_DURUM
declare -g  _BORSA_VERI_TALEPLER_ZAMAN

# Son emir sonucu
declare -gA _BORSA_VERI_SON_EMIR

# Son halka arz islem sonucu
declare -gA _BORSA_VERI_SON_HALKA_ARZ

# =======================================================
# Alan Tip Semalari
# =======================================================
# Her alan icin beklenen veri tipi. Sema, robo/strateji katmaninin
# alanlari dogru yorumlamasini saglar.
# Tip degerleri:
#   tam_sayi  : Ondalik kismi olmayan sayi (71, 1876, 0, -3)
#   kesirli   : Ondalik kismi olabilen sayi (31.46, 0.39, 877.77)
#   metin     : Serbest metin (sembol adi, durum, mesaj)
#   zaman     : Unix epoch (tam sayi ama anlamsal olarak zaman damgasi)
#   mantiksal : 0 veya 1 degeri (bayrak)

declare -gA _BORSA_ALAN_TIPLERI=(
    # Bakiye alanlari
    [bakiye.nakit]="kesirli"
    [bakiye.hisse]="kesirli"
    [bakiye.toplam]="kesirli"
    [bakiye.zaman]="zaman"

    # Portfoy alanlari (hisse bazli — lot kesirli olabilir, orn. QNBFK=0.39)
    [portfoy.lot]="kesirli"
    [portfoy.fiyat]="kesirli"
    [portfoy.deger]="kesirli"
    [portfoy.maliyet]="kesirli"
    [portfoy.kar]="kesirli"
    [portfoy.kar_yuzde]="kesirli"

    # Emir alanlari (emir lotlari her zaman tam sayidir)
    [emir.sembol]="metin"
    [emir.yon]="metin"
    [emir.lot]="tam_sayi"
    [emir.fiyat]="kesirli"
    [emir.durum]="metin"
    [emir.iptal_var]="mantiksal"

    # Halka arz alanlari
    [halka_arz.adi]="metin"
    [halka_arz.tip]="metin"
    [halka_arz.odeme]="metin"
    [halka_arz.durum]="metin"
    [halka_arz.limit]="kesirli"

    # Halka arz talep alanlari (talep lotlari her zaman tam sayidir)
    [talep.adi]="metin"
    [talep.tarih]="metin"
    [talep.lot]="tam_sayi"
    [talep.fiyat]="kesirli"
    [talep.tutar]="kesirli"
    [talep.durum]="metin"

    # Son emir alanlari
    [son_emir.basarili]="mantiksal"
    [son_emir.referans]="metin"
    [son_emir.sembol]="metin"
    [son_emir.yon]="metin"
    [son_emir.lot]="tam_sayi"
    [son_emir.fiyat]="kesirli"
    [son_emir.piyasa_mi]="mantiksal"
    [son_emir.mesaj]="metin"

    # Son halka arz alanlari
    [son_halka_arz.basarili]="mantiksal"
    [son_halka_arz.islem]="metin"
    [son_halka_arz.mesaj]="metin"
    [son_halka_arz.ipo_adi]="metin"
    [son_halka_arz.ipo_id]="metin"
    [son_halka_arz.lot]="tam_sayi"
    [son_halka_arz.fiyat]="kesirli"
    [son_halka_arz.talep_id]="metin"
)

# =======================================================
# Sayi Temizleme
# =======================================================

_borsa_sayi_temizle() {
    # Hem Turkce (45.230,50) hem Ingilizce (2,233.66) formatini
    # bc-uyumlu sayiya (45230.50) cevirir.
    # Otomatik format tespiti: son ayirici ondalik kabul edilir.
    # Son asama: sondaki gereksiz sifirlar ve nokta silinir.
    #   71.00 -> 71 | 31.460 -> 31.46 | 0.39 -> 0.39 | 100 -> 100
    local girdi="$1"
    girdi="${girdi//[[:space:]]/}"

    local sonuc
    if [[ "$girdi" == *,* && "$girdi" == *.* ]]; then
        # Her iki ayirici var — son gelen ondalik ayiricidir
        local virgulsuz="${girdi%,*}"
        local noktasiz="${girdi%.*}"
        if (( ${#virgulsuz} < ${#noktasiz} )); then
            # Son ayirici nokta — Ingilizce: 2,233.66 -> 2233.66
            sonuc="${girdi//,/}"
        else
            # Son ayirici virgul — Turkce: 45.230,50 -> 45230.50
            local tmp="${girdi//./}"
            sonuc="${tmp//,/.}"
        fi
    elif [[ "$girdi" == *,* ]]; then
        # Sadece virgul — ondalik ayirici: 45,50 -> 45.50
        sonuc="${girdi//,/.}"
    else
        # Sadece nokta veya saf sayi — zaten dogru format
        sonuc="$girdi"
    fi

    # Normalizasyon: sondaki gereksiz sifirlar ve noktayi sil
    # 71.00 -> 71 | 31.460 -> 31.46 | 0.39 -> 0.39 | -5804.350 -> -5804.35
    if [[ "$sonuc" == *.* ]]; then
        sonuc="${sonuc%%*(0)}"
        sonuc="${sonuc%.}"
    fi
    # bc uyumluluk: ".5" -> "0.5", "-.5" -> "-0.5"
    [[ "$sonuc" == .* ]] && sonuc="0$sonuc"
    [[ "$sonuc" == -.* ]] && sonuc="-0${sonuc#-}"
    echo "$sonuc"
}

_borsa_yuzde_temizle() {
    # Yuzde stringinden % ve +/- isaretlerini soyar, bc-uyumlu sayiya cevirir.
    # %12,50 -> 12.50 | %-3,25 -> -3.25 | %114,0 -> 114.0
    local deger
    deger="$1"
    deger="${deger#%}"
    deger="${deger#±}"
    _borsa_sayi_temizle "$deger"
}

_borsa_sayi_gecerli_mi() {
    # Temizlenmis degerin gecerli bir sayi olup olmadigini kontrol eder.
    # Gecerliyse 0, degilse 1 doner (POSIX return kodu).
    [[ "$1" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]
}

# =======================================================
# Tip Sorgulama Fonksiyonlari
# =======================================================

_borsa_alan_tipi() {
    # Sema tabanli alan tipi sorgulama.
    # $1: grup (bakiye, portfoy, emir, talep, halka_arz, son_emir, son_halka_arz)
    # $2: alan (nakit, lot, fiyat, ...)
    # Dondu: tam_sayi, kesirli, metin, zaman veya mantiksal
    echo "${_BORSA_ALAN_TIPLERI["$1.$2"]:-metin}"
}

_borsa_deger_tipi() {
    # Calisma zamaninda degerin gercek tipini tespit eder.
    # $1: deger
    # Dondu: tam_sayi, kesirli, metin veya bos
    local deger="$1"
    if [[ -z "$deger" ]]; then
        echo "bos"
    elif [[ "$deger" =~ ^-?[0-9]+$ ]]; then
        echo "tam_sayi"
    elif [[ "$deger" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
        echo "kesirli"
    else
        echo "metin"
    fi
}

_borsa_tam_sayi_mi() {
    # Degerin tam sayi olup olmadigini kontrol eder.
    # $1: deger — Dondu: 0 (evet) veya 1 (hayir)
    [[ "$1" =~ ^-?[0-9]+$ ]]
}

_borsa_kesirli_mi() {
    # Degerin ondalikli sayi olup olmadigini kontrol eder.
    # $1: deger — Dondu: 0 (evet) veya 1 (hayir)
    [[ "$1" =~ ^-?[0-9]+\.[0-9]+$ ]]
}

# =======================================================
# Veri Erisim Katmani
# =======================================================
# Robot ve strateji motoru icin tip-farkindali veri erisim fonksiyonlari.
# Duz degisken erisimine gerek kalmadan, tek fonksiyonla deger + tip bilgisi.
# Sayisal alanlar uzerinde toplama, siralama, agirlik hesabi yapilabilir.

_borsa_veri_degisken_bul() {
    # Grup ve alan adini ic degisken adina cevirir.
    # $1: grup  $2: alan
    # Dondu: degisken adi (stdout) veya 1 (bilinmeyen alan)
    case "$1.$2" in
        bakiye.nakit|bakiye.hisse|bakiye.toplam|bakiye.zaman)
            echo "_BORSA_VERI_BAKIYE" ;;
        portfoy.lot)       echo "_BORSA_VERI_HISSE_LOT" ;;
        portfoy.fiyat)     echo "_BORSA_VERI_HISSE_FIYAT" ;;
        portfoy.deger)     echo "_BORSA_VERI_HISSE_DEGER" ;;
        portfoy.maliyet)   echo "_BORSA_VERI_HISSE_MALIYET" ;;
        portfoy.kar)       echo "_BORSA_VERI_HISSE_KAR" ;;
        portfoy.kar_yuzde) echo "_BORSA_VERI_HISSE_KAR_YUZDE" ;;
        emir.sembol)       echo "_BORSA_VERI_EMIR_SEMBOL" ;;
        emir.yon)          echo "_BORSA_VERI_EMIR_YON" ;;
        emir.lot)          echo "_BORSA_VERI_EMIR_LOT" ;;
        emir.fiyat)        echo "_BORSA_VERI_EMIR_FIYAT" ;;
        emir.durum)        echo "_BORSA_VERI_EMIR_DURUM" ;;
        emir.iptal_var)    echo "_BORSA_VERI_EMIR_IPTAL_VAR" ;;
        halka_arz.adi)     echo "_BORSA_VERI_HALKA_ARZ_ADI" ;;
        halka_arz.tip)     echo "_BORSA_VERI_HALKA_ARZ_TIP" ;;
        halka_arz.odeme)   echo "_BORSA_VERI_HALKA_ARZ_ODEME" ;;
        halka_arz.durum)   echo "_BORSA_VERI_HALKA_ARZ_DURUM" ;;
        talep.adi)         echo "_BORSA_VERI_TALEP_ADI" ;;
        talep.tarih)       echo "_BORSA_VERI_TALEP_TARIH" ;;
        talep.lot)         echo "_BORSA_VERI_TALEP_LOT" ;;
        talep.fiyat)       echo "_BORSA_VERI_TALEP_FIYAT" ;;
        talep.tutar)       echo "_BORSA_VERI_TALEP_TUTAR" ;;
        talep.durum)       echo "_BORSA_VERI_TALEP_DURUM" ;;
        son_emir.*)        echo "_BORSA_VERI_SON_EMIR" ;;
        son_halka_arz.*)   echo "_BORSA_VERI_SON_HALKA_ARZ" ;;
        *)                 return 1 ;;
    esac
}

_borsa_veri_al() {
    # Tek fonksiyonla deger erisimi.
    # Bakiye/son_emir/son_halka_arz icin: _borsa_veri_al grup alan
    # Portfoy/emir/halka_arz/talep icin:  _borsa_veri_al grup alan anahtar
    # Dondu: degerin kendisi (stdout)
    local grup="$1" alan="$2" anahtar="${3:-}"
    local degisken
    degisken=$(_borsa_veri_degisken_bul "$grup" "$alan") || return 1

    local ref
    case "$grup" in
        bakiye|son_emir|son_halka_arz)
            ref="${degisken}[$alan]"
            ;;
        *)
            [[ -z "$anahtar" ]] && return 1
            ref="${degisken}[$anahtar]"
            ;;
    esac
    echo "${!ref}"
}

_borsa_veri_bilgi() {
    # Degeri tipiyle birlikte dondurur.
    # $1: grup  $2: alan  $3: anahtar (opsiyonel)
    # Dondu: "deger|sema_tipi|gercek_tip" formati
    local grup="$1" alan="$2" anahtar="${3:-}"
    local deger
    deger=$(_borsa_veri_al "$grup" "$alan" "$anahtar") || return 1

    local sema_tipi
    sema_tipi=$(_borsa_alan_tipi "$grup" "$alan")
    local gercek_tip
    gercek_tip=$(_borsa_deger_tipi "$deger")
    echo "${deger}|${sema_tipi}|${gercek_tip}"
}

_borsa_veri_listesi() {
    # Bir grubun tum anahtarlarini dondurur.
    # $1: grup (portfoy, emir, halka_arz, talep)
    # Dondu: boslukla ayrilmis anahtar listesi
    case "$1" in
        portfoy)   echo "${_BORSA_VERI_SEMBOLLER[*]}" ;;
        emir)      echo "${_BORSA_VERI_EMIRLER[*]}" ;;
        halka_arz) echo "${_BORSA_VERI_HALKA_ARZ_LISTESI[*]}" ;;
        talep)     echo "${_BORSA_VERI_TALEPLER[*]}" ;;
        *)         return 1 ;;
    esac
}

_borsa_veri_sayisi() {
    # Bir grubun eleman sayisini dondurur.
    # $1: grup (portfoy, emir, halka_arz, talep)
    case "$1" in
        portfoy)   echo "${#_BORSA_VERI_SEMBOLLER[@]}" ;;
        emir)      echo "${#_BORSA_VERI_EMIRLER[@]}" ;;
        halka_arz) echo "${#_BORSA_VERI_HALKA_ARZ_LISTESI[@]}" ;;
        talep)     echo "${#_BORSA_VERI_TALEPLER[@]}" ;;
        *)         echo "0" ;;
    esac
}

_borsa_veri_topla() {
    # Sayisal bir alanin tum degerlerini toplar (tip-farkindali).
    # $1: grup  $2: alan
    # Dondu: toplam (bc hassasiyetinde, normalize edilmis)
    # Metin alanlari reddedilir.
    local grup="$1" alan="$2"
    local tip
    tip=$(_borsa_alan_tipi "$grup" "$alan")
    [[ "$tip" == "metin" ]] && return 1

    local anahtarlar
    anahtarlar=$(_borsa_veri_listesi "$grup") || return 1
    local -a anahtarlar_dizi
    read -ra anahtarlar_dizi <<< "$anahtarlar"

    local toplam="0"
    local deger
    for anahtar in "${anahtarlar_dizi[@]}"; do
        deger=$(_borsa_veri_al "$grup" "$alan" "$anahtar")
        if _borsa_sayi_gecerli_mi "$deger"; then
            toplam=$(echo "$toplam + $deger" | bc)
        fi
    done
    _borsa_sayi_temizle "$toplam"
}

_borsa_veri_en() {
    # Bir alanin en buyuk veya en kucuk degerini bulur (tip-farkindali).
    # $1: grup  $2: alan  $3: "buyuk" veya "kucuk"
    # Dondu: "anahtar:deger" formati
    local grup="$1" alan="$2" yon="${3:-buyuk}"
    local tip
    tip=$(_borsa_alan_tipi "$grup" "$alan")
    [[ "$tip" == "metin" ]] && return 1

    local anahtarlar
    anahtarlar=$(_borsa_veri_listesi "$grup") || return 1
    local -a anahtarlar_dizi
    read -ra anahtarlar_dizi <<< "$anahtarlar"

    local en_anahtar="" en_deger=""
    local deger karsilastir
    for anahtar in "${anahtarlar_dizi[@]}"; do
        deger=$(_borsa_veri_al "$grup" "$alan" "$anahtar")
        _borsa_sayi_gecerli_mi "$deger" || continue

        if [[ -z "$en_deger" ]]; then
            en_anahtar="$anahtar"
            en_deger="$deger"
            continue
        fi

        if [[ "$yon" == "buyuk" ]]; then
            karsilastir=$(echo "$deger > $en_deger" | bc)
        else
            karsilastir=$(echo "$deger < $en_deger" | bc)
        fi
        if [[ "$karsilastir" == "1" ]]; then
            en_anahtar="$anahtar"
            en_deger="$deger"
        fi
    done

    [[ -z "$en_anahtar" ]] && return 1
    echo "$en_anahtar:$en_deger"
}

_borsa_veri_sirala() {
    # Anahtarlari bir alanin degerine gore siralar (tip-farkindali).
    # $1: grup  $2: alan  $3: "artan" veya "azalan" (varsayilan: azalan)
    # Dondu: her satir "anahtar:deger" formati, siralanmis
    local grup="$1" alan="$2" yon="${3:-azalan}"
    local tip
    tip=$(_borsa_alan_tipi "$grup" "$alan")
    [[ "$tip" == "metin" ]] && return 1

    local anahtarlar
    anahtarlar=$(_borsa_veri_listesi "$grup") || return 1
    local -a anahtarlar_dizi
    read -ra anahtarlar_dizi <<< "$anahtarlar"

    local satirlar deger
    satirlar=$(
        for anahtar in "${anahtarlar_dizi[@]}"; do
            deger=$(_borsa_veri_al "$grup" "$alan" "$anahtar")
            _borsa_sayi_gecerli_mi "$deger" || continue
            printf '%s:%s\n' "$deger" "$anahtar"
        done
    )
    [[ -z "$satirlar" ]] && return 1

    local siralanmis
    if [[ "$yon" == "artan" ]]; then
        siralanmis=$(echo "$satirlar" | sort -t: -k1,1n)
    else
        siralanmis=$(echo "$satirlar" | sort -t: -k1,1rn)
    fi

    while IFS=: read -r d a; do
        echo "$a:$d"
    done <<< "$siralanmis"
}

_borsa_veri_agirlik() {
    # Portfoyde bir hissenin agirligini hesaplar (% olarak).
    # $1: sembol
    # Dondu: yuzde degeri (orn. "45.3")
    local sembol="$1"
    local deger
    deger=$(_borsa_veri_al portfoy deger "$sembol")
    _borsa_sayi_gecerli_mi "$deger" || return 1

    local toplam_deger
    toplam_deger=$(_borsa_veri_topla portfoy deger)
    _borsa_sayi_gecerli_mi "$toplam_deger" || return 1
    [[ "$toplam_deger" == "0" ]] && return 1

    local sonuc
    sonuc=$(echo "scale=1; $deger * 100 / $toplam_deger" | bc)
    _borsa_sayi_temizle "$sonuc"
}

_borsa_veri_nakit_orani() {
    # Portfoydeki nakit oranini hesaplar (% olarak).
    # Dondu: yuzde degeri (orn. "0.4")
    local nakit toplam
    nakit=$(_borsa_veri_al bakiye nakit)
    toplam=$(_borsa_veri_al bakiye toplam)
    _borsa_sayi_gecerli_mi "$nakit" || return 1
    _borsa_sayi_gecerli_mi "$toplam" || return 1
    [[ "$toplam" == "0" ]] && return 1

    local sonuc
    sonuc=$(echo "scale=1; $nakit * 100 / $toplam" | bc)
    _borsa_sayi_temizle "$sonuc"
}

_borsa_veri_ozet() {
    # Robot icin portfoy ozeti: hisse basina agirlik + kar durumu.
    # Her satir: SEMBOL:agirlik:kar:kar_yuzde
    # Ornek: BESTE:1.1:1189.96:114
    local toplam_deger
    toplam_deger=$(_borsa_veri_topla portfoy deger) || return 1

    local deger kar kar_yuzde agirlik
    for sembol in "${_BORSA_VERI_SEMBOLLER[@]}"; do
        deger=$(_borsa_veri_al portfoy deger "$sembol")
        kar=$(_borsa_veri_al portfoy kar "$sembol")
        kar_yuzde=$(_borsa_veri_al portfoy kar_yuzde "$sembol")
        if _borsa_sayi_gecerli_mi "$deger" \
            && _borsa_sayi_gecerli_mi "$toplam_deger" \
            && [[ "$toplam_deger" != "0" ]]; then
            agirlik=$(echo "scale=1; $deger * 100 / $toplam_deger" | bc)
            agirlik=$(_borsa_sayi_temizle "$agirlik")
        else
            agirlik="0"
        fi
        echo "$sembol:$agirlik:${kar:-0}:${kar_yuzde:-0}"
    done
}

# =======================================================
# Veri Sifirlama Fonksiyonlari
# =======================================================

_borsa_veri_sifirla_bakiye() {
    unset _BORSA_VERI_BAKIYE
    declare -gA _BORSA_VERI_BAKIYE
}

_borsa_veri_sifirla_portfoy() {
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

_borsa_veri_sifirla_emirler() {
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

_borsa_veri_sifirla_halka_arz_liste() {
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

_borsa_veri_sifirla_halka_arz_talepler() {
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

_borsa_veri_sifirla_son_emir() {
    unset _BORSA_VERI_SON_EMIR
    declare -gA _BORSA_VERI_SON_EMIR
}

_borsa_veri_sifirla_son_halka_arz() {
    unset _BORSA_VERI_SON_HALKA_ARZ
    declare -gA _BORSA_VERI_SON_HALKA_ARZ
}

# =======================================================
# Veri Gecerlilik
# =======================================================

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

    [[ -z "$zaman" ]] && return 1

    local simdi
    simdi=$(date +%s)
    local fark=$((simdi - zaman))

    [[ "$fark" -lt 0 ]] && return 1
    [[ "$fark" -gt "$max_saniye" ]] && return 1

    return 0
}

# =======================================================
# Merkezi Veri Kayit Fonksiyonlari
# =======================================================

_borsa_veri_kaydet_bakiye() {
    # $1: nakit (Turkce format)   $2: hisse   $3: toplam
    _BORSA_VERI_BAKIYE[nakit]=$(_borsa_sayi_temizle "$1")
    _BORSA_VERI_BAKIYE[hisse]=$(_borsa_sayi_temizle "$2")
    _BORSA_VERI_BAKIYE[toplam]=$(_borsa_sayi_temizle "$3")
    _BORSA_VERI_BAKIYE[zaman]=$(date +%s)
}

_borsa_veri_kaydet_hisse() {
    # $1: sembol  $2: lot  $3: son fiyat  $4: piyasa degeri
    # $5: maliyet  $6: kar/zarar  $7: kar/zarar yuzde
    local sembol="$1"
    _BORSA_VERI_SEMBOLLER+=("$sembol")
    _BORSA_VERI_HISSE_LOT["$sembol"]=$(_borsa_sayi_temizle "$2")
    _BORSA_VERI_HISSE_FIYAT["$sembol"]=$(_borsa_sayi_temizle "$3")
    _BORSA_VERI_HISSE_DEGER["$sembol"]=$(_borsa_sayi_temizle "$4")
    _BORSA_VERI_HISSE_MALIYET["$sembol"]=$(_borsa_sayi_temizle "$5")
    _BORSA_VERI_HISSE_KAR["$sembol"]=$(_borsa_sayi_temizle "$6")
    _BORSA_VERI_HISSE_KAR_YUZDE["$sembol"]=$(_borsa_yuzde_temizle "$7")
}

_borsa_veri_kaydet_emir() {
    # $1: ext_id  $2: sembol  $3: islem (ham)  $4: adet  $5: fiyat
    # $6: durum  $7: iptal_var (bos olmayan = "1")
    local ext_id="$1"
    _BORSA_VERI_EMIRLER+=("$ext_id")
    _BORSA_VERI_EMIR_SEMBOL["$ext_id"]="${2:-}"

    local yon_normalize
    case "${3,,}" in
        al*) yon_normalize="ALIS" ;;
        sat*) yon_normalize="SATIS" ;;
        *) yon_normalize="${3:-}" ;;
    esac
    _BORSA_VERI_EMIR_YON["$ext_id"]="$yon_normalize"

    local lot_temiz
    lot_temiz=$(_borsa_sayi_temizle "${4:-0}")
    lot_temiz="${lot_temiz%%.*}"
    if _borsa_sayi_gecerli_mi "$lot_temiz"; then
        _BORSA_VERI_EMIR_LOT["$ext_id"]="$lot_temiz"
    else
        _BORSA_VERI_EMIR_LOT["$ext_id"]=""
    fi

    local fiyat_temiz
    fiyat_temiz=$(_borsa_sayi_temizle "${5:-0}")
    if _borsa_sayi_gecerli_mi "$fiyat_temiz"; then
        _BORSA_VERI_EMIR_FIYAT["$ext_id"]="$fiyat_temiz"
    else
        _BORSA_VERI_EMIR_FIYAT["$ext_id"]=""
    fi

    _BORSA_VERI_EMIR_DURUM["$ext_id"]="$6"

    if [[ -n "${7:-}" ]]; then
        _BORSA_VERI_EMIR_IPTAL_VAR["$ext_id"]="1"
    else
        _BORSA_VERI_EMIR_IPTAL_VAR["$ext_id"]="0"
    fi
}

_borsa_veri_kaydet_son_emir() {
    # $1: basarili  $2: referans  $3: sembol  $4: yon  $5: lot
    # $6: fiyat  $7: piyasa_mi  $8: mesaj
    _BORSA_VERI_SON_EMIR[basarili]="$1"
    _BORSA_VERI_SON_EMIR[referans]="${2:-}"
    _BORSA_VERI_SON_EMIR[sembol]="${3:-}"
    _BORSA_VERI_SON_EMIR[yon]="${4:-}"
    _BORSA_VERI_SON_EMIR[lot]="${5:-}"
    _BORSA_VERI_SON_EMIR[fiyat]="${6:-}"
    _BORSA_VERI_SON_EMIR[piyasa_mi]="${7:-0}"
    _BORSA_VERI_SON_EMIR[mesaj]="${8:-}"
}

_borsa_veri_kaydet_halka_arz() {
    # $1: ipo_id  $2: ipo_adi  $3: arz_tip  $4: odeme  $5: durum
    local ipo_id="$1"
    _BORSA_VERI_HALKA_ARZ_LISTESI+=("$ipo_id")
    _BORSA_VERI_HALKA_ARZ_ADI["$ipo_id"]="${2:-}"
    _BORSA_VERI_HALKA_ARZ_TIP["$ipo_id"]="${3:-}"
    _BORSA_VERI_HALKA_ARZ_ODEME["$ipo_id"]="${4:-}"
    _BORSA_VERI_HALKA_ARZ_DURUM["$ipo_id"]="${5:-AKTIF}"
}

_borsa_veri_kaydet_halka_arz_limit() {
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

_borsa_veri_kaydet_talep() {
    # $1: talep_id  $2: ad  $3: tarih  $4: lot  $5: fiyat  $6: tutar  $7: durum
    local talep_id="$1"
    _BORSA_VERI_TALEPLER+=("$talep_id")
    _BORSA_VERI_TALEP_ADI["$talep_id"]="${2:-}"
    _BORSA_VERI_TALEP_TARIH["$talep_id"]="${3:-}"

    local lot_temiz
    lot_temiz=$(_borsa_sayi_temizle "${4:-0}")
    lot_temiz="${lot_temiz%%.*}"
    _BORSA_VERI_TALEP_LOT["$talep_id"]="$lot_temiz"

    local fiyat_temiz
    fiyat_temiz=$(_borsa_sayi_temizle "${5:-0}")
    if _borsa_sayi_gecerli_mi "$fiyat_temiz"; then
        _BORSA_VERI_TALEP_FIYAT["$talep_id"]="$fiyat_temiz"
    else
        _BORSA_VERI_TALEP_FIYAT["$talep_id"]=""
    fi

    local tutar_temiz
    tutar_temiz=$(_borsa_sayi_temizle "${6:-0}")
    if _borsa_sayi_gecerli_mi "$tutar_temiz"; then
        _BORSA_VERI_TALEP_TUTAR["$talep_id"]="$tutar_temiz"
    else
        _BORSA_VERI_TALEP_TUTAR["$talep_id"]=""
    fi

    _BORSA_VERI_TALEP_DURUM["$talep_id"]="${7:-}"
}

_borsa_veri_kaydet_son_halka_arz() {
    # $1: basarili  $2: islem  $3: mesaj  $4: ipo_adi
    # $5: ipo_id  $6: lot  $7: fiyat  $8: talep_id
    _BORSA_VERI_SON_HALKA_ARZ[basarili]="$1"
    _BORSA_VERI_SON_HALKA_ARZ[islem]="$2"
    _BORSA_VERI_SON_HALKA_ARZ[mesaj]="${3:-}"
    _BORSA_VERI_SON_HALKA_ARZ[ipo_adi]="${4:-}"
    _BORSA_VERI_SON_HALKA_ARZ[ipo_id]="${5:-}"
    _BORSA_VERI_SON_HALKA_ARZ[lot]="${6:-}"
    _BORSA_VERI_SON_HALKA_ARZ[fiyat]="${7:-}"
    _BORSA_VERI_SON_HALKA_ARZ[talep_id]="${8:-}"
}
