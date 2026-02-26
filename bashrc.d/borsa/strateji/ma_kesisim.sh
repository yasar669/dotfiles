# shellcheck shell=bash

# Hareketli Ortalama Kesisim Stratejisi (Backtest Uyumlu)
# Kisa ve uzun hareketli ortalamalarin kesisiminden sinyal uretir.
#
# Mantik:
#   - Kisa MA, uzun MA'yi yukari kesiyor (altin caprazlama) -> ALIS
#   - Kisa MA, uzun MA'yi asagi kesiyor (olum caprazlamasi) -> SATIS
#   - Diger durumlarda -> BEKLE
#
# Gecmis fiyatlara _BACKTEST_VERI_FIYAT dizisinden erisilir.
# Bu versiyon ornek_ohlcv.sh'in backtest uyumlu halidir (mum_al gerektirmez).
#
# Kullanim:
#   borsa backtest ma_kesisim.sh AKBNK --tarih 2025-01-01:2025-06-01
#   borsa backtest ma_kesisim.sh THYAO --kaynak sentetik --tarih 2024-01-01:2025-01-01

# =======================================================
# YAPILANDIRMA
# =======================================================
_MA_KISA_PERIYOT=10         # Kisa hareketli ortalama periyodu
_MA_UZUN_PERIYOT=30         # Uzun hareketli ortalama periyodu
_MA_LOT=100                 # Her emirde gonderilecek lot
_MA_ONCEKI_DURUM=""          # YUKARI / ASAGI / bos
_MA_POZISYON=""              # YOK veya ACIK

# =======================================================
# strateji_baslat
# =======================================================
strateji_baslat() {
    _cekirdek_log "MA kesisim stratejisi baslatildi."
    _cekirdek_log "  Kisa MA  : ${_MA_KISA_PERIYOT}"
    _cekirdek_log "  Uzun MA  : ${_MA_UZUN_PERIYOT}"
    _cekirdek_log "  Lot      : ${_MA_LOT}"
    _MA_ONCEKI_DURUM=""
    _MA_POZISYON="YOK"
}

# =======================================================
# _ma_hesapla
# _BACKTEST_VERI_FIYAT dizisinden basit hareketli ortalama hesaplar.
# $1 = mevcut gun indeksi (0 tabanli)
# $2 = periyot
# stdout: MA degeri veya bos (yetersiz veri)
# =======================================================
_ma_hesapla() {
    local gun_idx="$1"
    local periyot="$2"

    # Yeterli veri var mi?
    if [[ "$gun_idx" -lt "$((periyot - 1))" ]]; then
        echo ""
        return 1
    fi

    # awk ile tek seferde hesapla
    local baslangic=$((gun_idx - periyot + 1))
    local fiyatlar=""
    local j
    for ((j = baslangic; j <= gun_idx; j++)); do
        fiyatlar="${fiyatlar}${_BACKTEST_VERI_FIYAT[$j]}"$'\n'
    done

    echo "$fiyatlar" | awk '
    NF > 0 && $1 != "" {
        toplam += $1
        n++
    }
    END {
        if (n == 0) { print ""; exit }
        printf "%.4f", toplam / n
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

    # Hareketli ortalamalari hesapla
    local kisa_ma uzun_ma
    kisa_ma=$(_ma_hesapla "$gun_idx" "$_MA_KISA_PERIYOT")
    uzun_ma=$(_ma_hesapla "$gun_idx" "$_MA_UZUN_PERIYOT")

    # Yeterli veri yoksa bekle
    if [[ -z "$kisa_ma" ]] || [[ -z "$uzun_ma" ]]; then
        echo "BEKLE"
        return 0
    fi

    # Mevcut durum: YUKARI (kisa > uzun) veya ASAGI (kisa < uzun)
    local mevcut_durum
    mevcut_durum=$(awk "BEGIN {
        if ($kisa_ma > $uzun_ma) print \"YUKARI\"
        else if ($kisa_ma < $uzun_ma) print \"ASAGI\"
        else print \"YATAY\"
    }")

    # Ilk turda onceki durum yok — kaydet ve bekle
    if [[ -z "$_MA_ONCEKI_DURUM" ]]; then
        _MA_ONCEKI_DURUM="$mevcut_durum"
        echo "BEKLE"
        return 0
    fi

    local onceki="$_MA_ONCEKI_DURUM"
    _MA_ONCEKI_DURUM="$mevcut_durum"

    # Altin caprazlama: ASAGI -> YUKARI (ALIS)
    if [[ "$onceki" == "ASAGI" ]] && [[ "$mevcut_durum" == "YUKARI" ]]; then
        if [[ "$_MA_POZISYON" == "YOK" ]]; then
            _MA_POZISYON="ACIK"
            echo "ALIS ${_MA_LOT} ${fiyat}"
            return 0
        fi
    fi

    # Olum caprazlamasi: YUKARI -> ASAGI (SATIS)
    if [[ "$onceki" == "YUKARI" ]] && [[ "$mevcut_durum" == "ASAGI" ]]; then
        if [[ "$_MA_POZISYON" == "ACIK" ]]; then
            _MA_POZISYON="YOK"
            echo "SATIS ${_MA_LOT} ${fiyat}"
            return 0
        fi
    fi

    echo "BEKLE"
    return 0
}

# =======================================================
# strateji_temizle
# =======================================================
strateji_temizle() {
    _cekirdek_log "MA kesisim stratejisi temizlendi."
    _MA_ONCEKI_DURUM=""
    _MA_POZISYON=""
}
