# shellcheck shell=bash

# Backtest - Sanal Portfoy Yonetimi
# Sanal portfoy olusturma, emir eslestirme, bakiye guncelleme, komisyon hesabi.

# Sanal portfoy array'leri
declare -gA _BACKTEST_PORTFOY
declare -gA _BACKTEST_LOT
declare -gA _BACKTEST_MALIYET
declare -gA _BACKTEST_PIYASA
declare -gA _BACKTEST_DEGER
declare -gA _BACKTEST_KZ
declare -gA _BACKTEST_KZ_YUZDE

# Komisyon oranlari (varsayilan: binde 1.88)
_BACKTEST_KOMISYON_ALIS="0.00188"
_BACKTEST_KOMISYON_SATIS="0.00188"

# _backtest_portfoy_olustur <baslangic_nakit>
# Sanal portfoy array'lerini sifirlar ve baslangic nakitini atar.
# Donus: 0
_backtest_portfoy_olustur() {
    local nakit="${1:-100000.00}"

    _BACKTEST_PORTFOY=()
    _BACKTEST_LOT=()
    _BACKTEST_MALIYET=()
    _BACKTEST_PIYASA=()
    _BACKTEST_DEGER=()
    _BACKTEST_KZ=()
    _BACKTEST_KZ_YUZDE=()

    _BACKTEST_PORTFOY[baslangic_nakit]="$nakit"
    _BACKTEST_PORTFOY[nakit]="$nakit"
    _BACKTEST_PORTFOY[hisse_degeri]="0.00"
    _BACKTEST_PORTFOY[toplam]="$nakit"
    _BACKTEST_PORTFOY[islem_sayisi]=0
    _BACKTEST_PORTFOY[basarili_islem]=0
    _BACKTEST_PORTFOY[basarisiz_islem]=0

    _BACKTEST_KOMISYON_ALIS="${_BACKTEST_AYAR_KOMISYON_ALIS:-0.00188}"
    _BACKTEST_KOMISYON_SATIS="${_BACKTEST_AYAR_KOMISYON_SATIS:-0.00188}"
}

# _backtest_emir_isle <yon> <sembol> <lot> <fiyat> <tavan> <taban>
# Sanal emri BIST kurallarina gore degerlendirir ve eslestirir.
# yon: "ALIS" veya "SATIS"
# Donus: 0 = eslesti, 1 = reddedildi. stdout'a sonuc mesaji yazar.
_backtest_emir_isle() {
    local yon="$1"
    local sembol="$2"
    local lot="$3"
    local istenen_fiyat="$4"
    local tavan="$5"
    local taban="$6"

    # Lot gecerlilik kontrolu
    if [[ -z "$lot" ]] || [[ "$lot" -le 0 ]] 2>/dev/null; then
        echo "REDDEDILDI: Gecersiz lot sayisi ($lot)"
        return 1
    fi

    # Eslestirme modeline gore fiyat belirle
    local eslestirme_fiyati="$istenen_fiyat"
    if [[ "${_BACKTEST_AYAR_ESLESTIRME:-KAPANIS}" == "KAPANIS" ]]; then
        # KAPANIS modeli: gunun kapanis fiyati kullanilir
        # (strateji hangi fiyati soylerse soylesin, o gunun fiyati kullanilir)
        eslestirme_fiyati="${_BACKTEST_ANKI_FIYAT:-$istenen_fiyat}"
    else
        # LIMIT modeli: fiyat tavan-taban araliginda mi?
        if [[ -n "$tavan" ]] && [[ -n "$taban" ]]; then
            local tavan_icinde taban_icinde
            tavan_icinde=$(echo "$istenen_fiyat <= $tavan" | bc -l 2>/dev/null)
            taban_icinde=$(echo "$istenen_fiyat >= $taban" | bc -l 2>/dev/null)
            if [[ "${tavan_icinde:-0}" != "1" ]] || [[ "${taban_icinde:-0}" != "1" ]]; then
                echo "REDDEDILDI: Fiyat ($istenen_fiyat) tavan/taban disinda (taban=$taban, tavan=$tavan)"
                return 1
            fi
        fi
    fi

    # BIST fiyat adimi kontrolu (kurallar/bist.sh)
    if declare -f bist_fiyat_gecerli_mi > /dev/null 2>&1; then
        local adim_sonuc
        adim_sonuc=$(bist_fiyat_gecerli_mi "$eslestirme_fiyati" 2>&1)
        if [[ "$adim_sonuc" == *"GECERSIZ"* ]]; then
            echo "REDDEDILDI: BIST fiyat adimi gecersiz ($eslestirme_fiyati)"
            return 1
        fi
    fi

    # Komisyon hesapla
    local komisyon
    komisyon=$(_backtest_komisyon_hesapla "$lot" "$eslestirme_fiyati" "$yon")

    if [[ "$yon" == "ALIS" ]]; then
        # Bakiye kontrolu
        local gerekli
        gerekli=$(echo "scale=2; $lot * $eslestirme_fiyati + $komisyon" | bc 2>/dev/null)
        local nakit="${_BACKTEST_PORTFOY[nakit]}"
        local yeterli
        yeterli=$(echo "$nakit >= $gerekli" | bc -l 2>/dev/null)
        if [[ "${yeterli:-0}" != "1" ]]; then
            echo "REDDEDILDI: Yetersiz bakiye (gerekli=$gerekli, nakit=$nakit)"
            return 1
        fi
    elif [[ "$yon" == "SATIS" ]]; then
        # Pozisyon kontrolu
        local mevcut_lot="${_BACKTEST_LOT[$sembol]:-0}"
        if [[ "$mevcut_lot" -lt "$lot" ]] 2>/dev/null; then
            echo "REDDEDILDI: Yetersiz pozisyon ($sembol: mevcut=$mevcut_lot, istenen=$lot)"
            return 1
        fi
    else
        echo "REDDEDILDI: Gecersiz yon ($yon)"
        return 1
    fi

    # Eslestirme basarili — portfoyu guncelle
    _backtest_portfoy_guncelle "$yon" "$sembol" "$lot" "$eslestirme_fiyati" "$komisyon"
    echo "ESLESTI: $yon $lot $sembol @ $eslestirme_fiyati (komisyon: $komisyon)"
    return 0
}

# _backtest_portfoy_guncelle <yon> <sembol> <lot> <fiyat> <komisyon>
# Eslesen emrin portfoy etkisini uygular.
# ALIS: nakit azalir, lot artar, maliyet guncellenir.
# SATIS: nakit artar, lot azalir, K/Z hesaplanir.
# Donus: 0
_backtest_portfoy_guncelle() {
    local yon="$1"
    local sembol="$2"
    local lot="$3"
    local fiyat="$4"
    local komisyon="$5"

    local nakit="${_BACKTEST_PORTFOY[nakit]}"
    local mevcut_lot="${_BACKTEST_LOT[$sembol]:-0}"
    local mevcut_maliyet="${_BACKTEST_MALIYET[$sembol]:-0}"

    if [[ "$yon" == "ALIS" ]]; then
        # Nakit azalt
        local maliyet
        maliyet=$(echo "scale=2; $lot * $fiyat + $komisyon" | bc 2>/dev/null)
        nakit=$(echo "scale=2; $nakit - $maliyet" | bc 2>/dev/null)

        # Ortalama maliyet hesapla
        local yeni_lot yeni_maliyet
        yeni_lot=$((mevcut_lot + lot))
        if [[ "$mevcut_lot" -eq 0 ]]; then
            yeni_maliyet="$fiyat"
        else
            yeni_maliyet=$(echo "scale=4; ($mevcut_maliyet * $mevcut_lot + $fiyat * $lot) / $yeni_lot" | bc 2>/dev/null)
        fi

        _BACKTEST_LOT[$sembol]=$yeni_lot
        _BACKTEST_MALIYET[$sembol]="$yeni_maliyet"

    elif [[ "$yon" == "SATIS" ]]; then
        # Nakit artir
        local gelir
        gelir=$(echo "scale=2; $lot * $fiyat - $komisyon" | bc 2>/dev/null)
        nakit=$(echo "scale=2; $nakit + $gelir" | bc 2>/dev/null)

        # K/Z hesapla (bu satis icin)
        local satis_kz
        satis_kz=$(echo "scale=2; ($fiyat - $mevcut_maliyet) * $lot - $komisyon" | bc 2>/dev/null)

        # Basarili/basarisiz islem takibi
        local karli
        karli=$(echo "$satis_kz > 0" | bc -l 2>/dev/null)
        if [[ "${karli:-0}" == "1" ]]; then
            # shellcheck disable=SC2004
            _BACKTEST_PORTFOY[basarili_islem]=$(( ${_BACKTEST_PORTFOY[basarili_islem]} + 1 ))
        else
            # shellcheck disable=SC2004
            _BACKTEST_PORTFOY[basarisiz_islem]=$(( ${_BACKTEST_PORTFOY[basarisiz_islem]} + 1 ))
        fi

        # Lot azalt
        local yeni_lot
        yeni_lot=$((mevcut_lot - lot))
        _BACKTEST_LOT[$sembol]=$yeni_lot

        # Tum pozisyon kapandiysa maliyeti sifirla
        if [[ "$yeni_lot" -le 0 ]]; then
            _BACKTEST_MALIYET[$sembol]="0"
            _BACKTEST_LOT[$sembol]=0
        fi
    fi

    _BACKTEST_PORTFOY[nakit]="$nakit"
    # shellcheck disable=SC2004
    _BACKTEST_PORTFOY[islem_sayisi]=$(( ${_BACKTEST_PORTFOY[islem_sayisi]} + 1 ))

    # Komisyon toplami
    local toplam_kom="${_BACKTEST_PORTFOY[toplam_komisyon]:-0}"
    toplam_kom=$(echo "scale=2; $toplam_kom + $komisyon" | bc 2>/dev/null)
    _BACKTEST_PORTFOY[toplam_komisyon]="$toplam_kom"
}

# _backtest_portfoy_deger_guncelle
# Tum pozisyonlarin piyasa degerlerini _BACKTEST_PIYASA'dan hesaplar.
# Donus: 0
_backtest_portfoy_deger_guncelle() {
    local toplam_hisse_degeri="0.00"
    local sembol

    for sembol in "${!_BACKTEST_LOT[@]}"; do
        local lot="${_BACKTEST_LOT[$sembol]}"
        [[ "$lot" -le 0 ]] 2>/dev/null && continue

        local piyasa="${_BACKTEST_PIYASA[$sembol]:-0}"
        local maliyet="${_BACKTEST_MALIYET[$sembol]:-0}"

        # Deger
        local deger
        deger=$(echo "scale=2; $lot * $piyasa" | bc 2>/dev/null)
        _BACKTEST_DEGER[$sembol]="$deger"

        # K/Z
        if [[ "$maliyet" != "0" ]] && [[ -n "$maliyet" ]]; then
            local kz kz_yuzde
            kz=$(echo "scale=2; ($piyasa - $maliyet) * $lot" | bc 2>/dev/null)
            kz_yuzde=$(echo "scale=2; ($piyasa - $maliyet) / $maliyet * 100" | bc 2>/dev/null)
            _BACKTEST_KZ[$sembol]="$kz"
            _BACKTEST_KZ_YUZDE[$sembol]="$kz_yuzde"
        fi

        toplam_hisse_degeri=$(echo "scale=2; $toplam_hisse_degeri + $deger" | bc 2>/dev/null)
    done

    _BACKTEST_PORTFOY[hisse_degeri]="$toplam_hisse_degeri"
    _BACKTEST_PORTFOY[toplam]=$(echo "scale=2; ${_BACKTEST_PORTFOY[nakit]} + $toplam_hisse_degeri" | bc 2>/dev/null)
}

# _backtest_komisyon_hesapla <lot> <fiyat> <yon>
# Emir icin komisyon tutarini hesaplar.
# stdout'a komisyon tutarini (TL) yazar.
_backtest_komisyon_hesapla() {
    local lot="$1"
    local fiyat="$2"
    local yon="$3"

    local oran
    if [[ "$yon" == "ALIS" ]]; then
        oran="$_BACKTEST_KOMISYON_ALIS"
    else
        oran="$_BACKTEST_KOMISYON_SATIS"
    fi

    echo "scale=2; $lot * $fiyat * $oran" | bc 2>/dev/null
}
