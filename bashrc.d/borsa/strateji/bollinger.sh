# shellcheck shell=bash

# Bollinger Bandi Stratejisi
# Bollinger bantlarinin alt ve ust sinirlarindan sinyal uretir.
#
# Mantik:
#   - Fiyat alt banda degdiginde (asiri satim) -> ALIS
#   - Fiyat ust banda degdiginde (asiri alim) -> SATIS
#   - Aradaysa -> BEKLE
#
# Bollinger Bandi = Orta Bant (SMA) +/- (K * Standart Sapma)
# Varsayilan: 20 gunluk SMA, 2 standart sapma
#
# Kullanim:
#   borsa backtest bollinger.sh AKBNK --tarih 2025-01-01:2025-06-01
#   borsa backtest bollinger.sh THYAO --kaynak sentetik --tarih 2024-01-01:2025-01-01

# =======================================================
# YAPILANDIRMA
# =======================================================
_BB_PERIYOT=20              # Bollinger bandi periyodu (SMA)
_BB_CARPAN=2                # Standart sapma carpani (K)
_BB_LOT=100                 # Her emirde gonderilecek lot
_BB_POZISYON=""              # YOK veya ACIK

# =======================================================
# strateji_baslat
# =======================================================
strateji_baslat() {
    _cekirdek_log "Bollinger bandi stratejisi baslatildi."
    _cekirdek_log "  Periyot : ${_BB_PERIYOT}"
    _cekirdek_log "  Carpan  : ${_BB_CARPAN}"
    _cekirdek_log "  Lot     : ${_BB_LOT}"
    _BB_POZISYON="YOK"
}

# =======================================================
# _bb_hesapla
# _BACKTEST_VERI_FIYAT dizisinden Bollinger bantlarini hesaplar.
# $1 = mevcut gun indeksi (0 tabanli)
# $2 = periyot
# $3 = carpan (K)
# stdout: "orta_bant ust_bant alt_bant" (boslukla ayrilmis)
# =======================================================
_bb_hesapla() {
    local gun_idx="$1"
    local periyot="$2"
    local carpan="$3"

    # Yeterli veri var mi?
    if [[ "$gun_idx" -lt "$((periyot - 1))" ]]; then
        echo ""
        return 1
    fi

    # Fiyatlari topla
    local baslangic=$((gun_idx - periyot + 1))
    local fiyatlar=""
    local j
    for ((j = baslangic; j <= gun_idx; j++)); do
        fiyatlar="${fiyatlar}${_BACKTEST_VERI_FIYAT[$j]}"$'\n'
    done

    # awk ile ortalama ve standart sapma hesapla
    echo "$fiyatlar" | awk -v k="$carpan" '
    NF > 0 && $1 != "" {
        fiyat[NR] = $1
        toplam += $1
        n++
    }
    END {
        if (n == 0) { print ""; exit }
        ortalama = toplam / n

        # Standart sapma
        varyans_toplam = 0
        for (i = 1; i <= n; i++) {
            fark = fiyat[i] - ortalama
            varyans_toplam += fark * fark
        }
        std_sapma = sqrt(varyans_toplam / n)

        ust = ortalama + (k * std_sapma)
        alt = ortalama - (k * std_sapma)
        printf "%.4f %.4f %.4f", ortalama, ust, alt
    }'
}

# =======================================================
# strateji_degerlendir — zorunlu arayuz
# $1=sembol $2=fiyat $3=tavan $4=taban $5=degisim $6=hacim $7=seans
# =======================================================
strateji_degerlendir() {
    local _sembol="$1"
    local fiyat="$2"
    # shellcheck disable=SC2034
    local _tavan="$3"
    # shellcheck disable=SC2034
    local _taban="$4"
    # shellcheck disable=SC2034
    local _degisim="$5"
    # shellcheck disable=SC2034
    local _hacim="$6"
    local seans="$7"

    # Seans kapali ise bekle
    if [[ "$seans" != "Surekli Islem" ]] && [[ "$seans" != *"Surekli"* ]]; then
        echo "BEKLE"
        return 0
    fi

    local gun_idx=$((_BACKTEST_GUN_NO - 1))

    # Bollinger bantlarini hesapla
    local bb_sonuc
    bb_sonuc=$(_bb_hesapla "$gun_idx" "$_BB_PERIYOT" "$_BB_CARPAN")

    # Yeterli veri yoksa bekle
    if [[ -z "$bb_sonuc" ]]; then
        echo "BEKLE"
        return 0
    fi

    local orta_bant ust_bant alt_bant
    orta_bant=$(echo "$bb_sonuc" | awk '{print $1}')
    ust_bant=$(echo "$bb_sonuc" | awk '{print $2}')
    alt_bant=$(echo "$bb_sonuc" | awk '{print $3}')

    # Fiyat alt bandin altinda — ALIS (asiri satim)
    local alt_sinyal
    alt_sinyal=$(awk "BEGIN { print ($fiyat <= $alt_bant) ? 1 : 0 }")
    if [[ "$alt_sinyal" == "1" ]] && [[ "$_BB_POZISYON" == "YOK" ]]; then
        _BB_POZISYON="ACIK"
        echo "ALIS ${_BB_LOT} ${fiyat}"
        return 0
    fi

    # Fiyat ust bandin ustunde — SATIS (asiri alim)
    local ust_sinyal
    ust_sinyal=$(awk "BEGIN { print ($fiyat >= $ust_bant) ? 1 : 0 }")
    if [[ "$ust_sinyal" == "1" ]] && [[ "$_BB_POZISYON" == "ACIK" ]]; then
        _BB_POZISYON="YOK"
        echo "SATIS ${_BB_LOT} ${fiyat}"
        return 0
    fi

    # Fiyat orta banda dondu ve pozisyon aciksa — alternatif cikis
    # (opsiyonel: orta bant cikisi istenirse asagidaki blok aktif edilir)
    # local orta_sinyal
    # orta_sinyal=$(awk "BEGIN { print ($fiyat >= $orta_bant) ? 1 : 0 }")
    # if [[ "$orta_sinyal" == "1" ]] && [[ "$_BB_POZISYON" == "ACIK" ]]; then
    #     _BB_POZISYON="YOK"
    #     echo "SATIS ${_BB_LOT} ${fiyat}"
    #     return 0
    # fi

    echo "BEKLE"
    return 0
}

# =======================================================
# strateji_min_mum — opsiyonel arayuz
# Stratejinin gecerli sinyal uretebilmesi icin gereken minimum mum sayisi.
# =======================================================
strateji_min_mum() {
    echo "20"
}

# =======================================================
# strateji_temizle
# =======================================================
strateji_temizle() {
    _cekirdek_log "Bollinger bandi stratejisi temizlendi."
    _BB_POZISYON=""
}
