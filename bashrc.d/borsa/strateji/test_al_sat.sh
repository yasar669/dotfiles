# shellcheck shell=bash

# Test Stratejisi — Her 5 gunde alis, sonraki 5 gunde satis
# Backtest mekanizmasinin islem isleme/metrik hesaplama
# fonksiyonlarini dogrulamak icin kullanilir.

_TEST_LOT=50
_TEST_DURUM=""

strateji_baslat() {
    _cekirdek_log "Test al-sat stratejisi baslatildi."
    _TEST_DURUM="BOS"
}

# strateji_degerlendir — zorunlu arayuz
# Her 5 gunde bir alis/satis yapar (deterministik)
strateji_degerlendir() {
    local _sembol="$1"
    local fiyat="$2"
    local _tavan="$3"
    local _taban="$4"
    local _degisim="$5"
    local _hacim="$6"
    local _seans="$7"

    local gun_no="${_BACKTEST_GUN_NO:-0}"
    local mod=$((gun_no % 10))

    if [[ "$_TEST_DURUM" == "BOS" ]] && [[ "$mod" -eq 1 ]]; then
        _TEST_DURUM="DOLU"
        echo "ALIS ${_TEST_LOT} ${fiyat}"
        return 0
    fi

    if [[ "$_TEST_DURUM" == "DOLU" ]] && [[ "$mod" -eq 6 ]]; then
        _TEST_DURUM="BOS"
        echo "SATIS ${_TEST_LOT} ${fiyat}"
        return 0
    fi

    echo "BEKLE"
    return 0
}

strateji_temizle() {
    _cekirdek_log "Test al-sat stratejisi temizlendi."
}
