# shellcheck shell=bash

# Ornek OHLCV Strateji — Hareketli Ortalama Caprazlamasi
# Bu dosya OHLCV (mum_al) arayuzunu kullanan strateji ornegi.
# Gercek ticarette kullanilmadan once dikkatli test edilmelidir.
#
# Mantik:
#   - Kisa MA (10 periyot) uzun MA'yi (50 periyot) yukari kesiyor -> ALIS
#   - Kisa MA uzun MA'yi asagi kesiyor -> SATIS
#   - Aradaysa BEKLE
#
# Kullanim:
#   robot_baslat --semboller THYAO,AKBNK ziraat 123 ornek_ohlcv.sh 60

# =======================================================
# YAPILANDIRMA
# =======================================================

# Strateji ohlcv periyotlari — robot motoru bu diziyi okuyarak
# takip listesine otomatik ekler.
# shellcheck disable=SC2034
declare -ga STRATEJI_OHLCV_PERIYOTLAR=("15dk" "1G")

# Hareketli ortalama parametreleri
_OHLCV_KISA_MA=10
_OHLCV_UZUN_MA=50
_OHLCV_PERIYOT="15dk"     # Kullanilacak mum periyodu
_OHLCV_LOT=100             # Emir lotu

# Onceki MA durumunu sakla (caprazlama tespiti icin)
declare -gA _OHLCV_ONCEKI_DURUM=()

# =======================================================
# strateji_baslat — Robot basladiginda bir kez cagrilir
# =======================================================
strateji_baslat() {
    _cekirdek_log "OHLCV ornek strateji baslatildi."
    _cekirdek_log "  Periyot   : ${_OHLCV_PERIYOT}"
    _cekirdek_log "  Kisa MA   : ${_OHLCV_KISA_MA}"
    _cekirdek_log "  Uzun MA   : ${_OHLCV_UZUN_MA}"
    _cekirdek_log "  Lot       : ${_OHLCV_LOT}"
    _cekirdek_log "  Semboller : ${STRATEJI_SEMBOLLER[*]}"
}

# =======================================================
# _ohlcv_ortalama_hesapla <mumlar> <donem>
# CSV formatindaki mum verisinden hareketli ortalama hesaplar.
# CSV format: tarih,acilis,yuksek,dusuk,kapanis,hacim
# stdout: Ortalama degeri
# =======================================================
_ohlcv_ortalama_hesapla() {
    local mumlar="$1"
    local donem="$2"

    if [[ -z "$mumlar" ]]; then
        echo "0"
        return 1
    fi

    local toplam=0
    local sayi=0

    while IFS=',' read -r _tarih _acilis _yuksek _dusuk kapanis _hacim; do
        [[ -z "$kapanis" ]] && continue
        toplam=$(echo "$toplam + $kapanis" | bc 2>/dev/null)
        sayi=$((sayi + 1))
        [[ "$sayi" -ge "$donem" ]] && break
    done <<< "$mumlar"

    if [[ "$sayi" -eq 0 ]]; then
        echo "0"
        return 1
    fi

    echo "scale=4; $toplam / $sayi" | bc 2>/dev/null
    return 0
}

# =======================================================
# strateji_degerlendir — Her turda, her sembol icin cagrilir
#
# Parametreler: ayni standart arayuz
#   $1 = sembol, $2 = fiyat, $3 = tavan, $4 = taban,
#   $5 = degisim, $6 = hacim, $7 = seans
# stdout: BEKLE / ALIS <lot> <fiyat> / SATIS <lot> <fiyat>
# =======================================================
strateji_degerlendir() {
    local sembol="$1"
    local fiyat="$2"
    local _tavan="$3"
    local _taban="$4"
    local _degisim="$5"
    local _hacim="$6"
    local seans="$7"

    # Seans kapali ise bekle
    if [[ "$seans" != "Surekli Islem" ]] && [[ "$seans" != *"Surekli"* ]]; then
        echo "BEKLE"
        return 0
    fi

    # mum_al fonksiyonu mevcut mu?
    if ! declare -f mum_al > /dev/null 2>&1; then
        echo "BEKLE"
        return 0
    fi

    # OHLCV mum verisi cek
    local mumlar
    mumlar=$(mum_al "$sembol" "$_OHLCV_PERIYOT" "$_OHLCV_UZUN_MA" 2>/dev/null)

    if [[ -z "$mumlar" ]]; then
        echo "BEKLE"
        return 0
    fi

    # Satir sayisi yeterli mi?
    local satir_sayisi
    satir_sayisi=$(echo "$mumlar" | wc -l)
    if [[ "$satir_sayisi" -lt "$_OHLCV_UZUN_MA" ]]; then
        echo "BEKLE"
        return 0
    fi

    # Kisa MA hesapla
    local kisa_ma
    kisa_ma=$(_ohlcv_ortalama_hesapla "$mumlar" "$_OHLCV_KISA_MA")

    # Uzun MA hesapla
    local uzun_ma
    uzun_ma=$(_ohlcv_ortalama_hesapla "$mumlar" "$_OHLCV_UZUN_MA")

    if [[ "$kisa_ma" == "0" ]] || [[ "$uzun_ma" == "0" ]]; then
        echo "BEKLE"
        return 0
    fi

    # Mevcut durum: YUKARI (kisa > uzun) veya ASAGI (kisa < uzun)
    local mevcut_durum="YATAY"
    if (( $(echo "$kisa_ma > $uzun_ma" | bc -l 2>/dev/null) )); then
        mevcut_durum="YUKARI"
    elif (( $(echo "$kisa_ma < $uzun_ma" | bc -l 2>/dev/null) )); then
        mevcut_durum="ASAGI"
    fi

    # Onceki durumla karsilastir (caprazlama tespiti)
    local onceki
    onceki="${_OHLCV_ONCEKI_DURUM[$sembol]:-}"

    # Durumu guncelle
    _OHLCV_ONCEKI_DURUM["$sembol"]="$mevcut_durum"

    # Ilk tura onceki durum yok — sinyal verme
    if [[ -z "$onceki" ]]; then
        echo "BEKLE"
        return 0
    fi

    # Caprazlama kontrol
    if [[ "$onceki" == "ASAGI" ]] && [[ "$mevcut_durum" == "YUKARI" ]]; then
        # Altin caprazlama — ALIS sinyali
        echo "ALIS ${_OHLCV_LOT} ${fiyat}"
        return 0
    fi

    if [[ "$onceki" == "YUKARI" ]] && [[ "$mevcut_durum" == "ASAGI" ]]; then
        # Olum caprazlamasi — SATIS sinyali
        echo "SATIS ${_OHLCV_LOT} ${fiyat}"
        return 0
    fi

    echo "BEKLE"
    return 0
}

# =======================================================
# strateji_temizle — Robot durdugunda cagrilir
# =======================================================
strateji_temizle() {
    _cekirdek_log "OHLCV ornek strateji temizlendi."
    _OHLCV_ONCEKI_DURUM=()
}
