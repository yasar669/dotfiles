# shellcheck shell=bash

# Ornek Strateji — Fiyat Degisim Takibi
# Bu dosya strateji arayuz sozlesmesini gosteren bir ornektir.
# Gercek ticarette kullanilmadan once dikkatli test edilmelidir.
#
# Strateji mantigi:
# - Fiyat tabana yakinsa (taban + %2) ALIS sinyali verir
# - Fiyat tavana yakinsa (tavan - %2) SATIS sinyali verir
# - Aradaysa BEKLE

# =======================================================
# ZORUNLU: Stratejinin izleyecegi sembol listesi
# =======================================================
STRATEJI_SEMBOLLER=("THYAO" "AKBNK" "GARAN")

# =======================================================
# YAPILANDIRMA
# =======================================================
_ORNEK_ESIK_YUZDE="2.0"    # tavan/tabana yakinlik esigi (%)
_ORNEK_LOT=100              # her emirde gonderilecek lot

# =======================================================
# OPSIYONEL: Strateji basladiginda bir kez cagrilir
# =======================================================
strateji_baslat() {
    _cekirdek_log "Ornek strateji baslatildi."
    _cekirdek_log "  Semboller : ${STRATEJI_SEMBOLLER[*]}"
    _cekirdek_log "  Esik      : %${_ORNEK_ESIK_YUZDE}"
    _cekirdek_log "  Lot       : ${_ORNEK_LOT}"
}

# =======================================================
# ZORUNLU: Robot dongusunun her turunda, her sembol icin cagrilir
# Parametreler:
#   $1 = sembol (THYAO)
#   $2 = son fiyat (312.50)
#   $3 = tavan (343.75)
#   $4 = taban (281.25)
#   $5 = degisim yuzdesi (1.34)
#   $6 = hacim (1250000)
#   $7 = seans durumu (Surekli Islem)
# Donus: stdout'a tek satir — BEKLE / ALIS <lot> <fiyat> / SATIS <lot> <fiyat>
# =======================================================
strateji_degerlendir() {
    local _sembol="$1"  # strateji icerisinde sembol bazli state tutmak icin
    local fiyat="$2"
    local tavan="$3"
    local taban="$4"
    local _degisim="$5"  # ileri stratejilerde kullanilacak
    # shellcheck disable=SC2034
    local hacim="$6"
    local seans="$7"

    # Seans kapali ise islem yapma
    if [[ "$seans" != "Surekli Islem" ]] && [[ "$seans" != *"Surekli"* ]]; then
        echo "BEKLE"
        return 0
    fi

    # Tavan veya taban bos ise bekle
    if [[ -z "$tavan" ]] || [[ -z "$taban" ]] || [[ "$tavan" == "-" ]] || [[ "$taban" == "-" ]]; then
        echo "BEKLE"
        return 0
    fi

    # Esik hesapla
    local aralik esik
    aralik=$(echo "$tavan - $taban" | bc 2>/dev/null)
    esik=$(echo "scale=4; $aralik * $_ORNEK_ESIK_YUZDE / 100" | bc 2>/dev/null)

    if [[ -z "$aralik" ]] || [[ -z "$esik" ]]; then
        echo "BEKLE"
        return 0
    fi

    # Tabana yakin mi? (ALIS firsati)
    local taban_esik
    taban_esik=$(echo "$taban + $esik" | bc 2>/dev/null)
    if (( $(echo "$fiyat <= $taban_esik" | bc -l 2>/dev/null) )); then
        echo "ALIS ${_ORNEK_LOT} ${fiyat}"
        return 0
    fi

    # Tavana yakin mi? (SATIS firsati)
    local tavan_esik
    tavan_esik=$(echo "$tavan - $esik" | bc 2>/dev/null)
    if (( $(echo "$fiyat >= $tavan_esik" | bc -l 2>/dev/null) )); then
        echo "SATIS ${_ORNEK_LOT} ${fiyat}"
        return 0
    fi

    echo "BEKLE"
    return 0
}

# =======================================================
# OPSIYONEL: Robot durdugundan cagrilir
# =======================================================
strateji_temizle() {
    _cekirdek_log "Ornek strateji temizlendi."
}
