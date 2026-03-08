# shellcheck shell=bash

# RSI (Relative Strength Index) Stratejisi
# Klasik RSI gostergesiyle asiri alim/asiri satim bolgelerine gore islem yapar.
#
# Mantik:
#   - RSI 30'un altina dustugunde (asiri satim) -> ALIS
#   - RSI 70'in ustune ciktiginda (asiri alim) -> SATIS
#   - Aradaysa -> BEKLE
#
# RSI hesabi: 14 gunluk varsayilan periyot kullanir.
# Gecmis fiyatlara _BACKTEST_VERI_FIYAT dizisinden erisilir.
#
# Kullanim:
#   borsa backtest rsi.sh AKBNK --tarih 2025-01-01:2025-06-01
#   borsa backtest rsi.sh THYAO --kaynak sentetik --tarih 2025-01-01:2025-06-01

# =======================================================
# YAPILANDIRMA
# =======================================================
_RSI_PERIYOT=14             # RSI periyodu (varsayilan 14 gun)
_RSI_ASIRI_SATIM=30         # Bu seviyenin altinda ALIS
_RSI_ASIRI_ALIM=70          # Bu seviyenin ustunde SATIS
_RSI_LOT=100                # Her emirde gonderilecek lot
_RSI_POZISYON=""            # YOK veya ACIK

# =======================================================
# strateji_baslat
# =======================================================
strateji_baslat() {
    _cekirdek_log "RSI stratejisi baslatildi."
    _cekirdek_log "  Periyot     : ${_RSI_PERIYOT}"
    _cekirdek_log "  Asiri satim : ${_RSI_ASIRI_SATIM}"
    _cekirdek_log "  Asiri alim  : ${_RSI_ASIRI_ALIM}"
    _cekirdek_log "  Lot         : ${_RSI_LOT}"
    _RSI_POZISYON="YOK"
}

# =======================================================
# _rsi_hesapla
# _BACKTEST_VERI_FIYAT dizisinden RSI hesaplar.
# $1 = mevcut gun indeksi (0 tabanli)
# $2 = periyot
# stdout: RSI degeri (0-100) veya bos (yetersiz veri)
# =======================================================
_rsi_hesapla() {
    local gun_idx="$1"
    local periyot="$2"

    # Yeterli veri var mi?
    if [[ "$gun_idx" -lt "$periyot" ]]; then
        echo ""
        return 1
    fi

    # awk ile tek seferde hesapla (bc dongusu yerine)
    local baslangic=$((gun_idx - periyot))
    local fiyatlar=""
    local j
    for ((j = baslangic; j <= gun_idx; j++)); do
        fiyatlar="${fiyatlar}${_BACKTEST_VERI_FIYAT[$j]}"$'\n'
    done

    echo "$fiyatlar" | awk '
    NF > 0 && $1 != "" {
        fiyat[NR] = $1
        n = NR
    }
    END {
        if (n < 2) { print ""; exit }
        ort_yukselis = 0
        ort_dusus = 0
        sayac = 0
        for (i = 2; i <= n; i++) {
            fark = fiyat[i] - fiyat[i-1]
            if (fark > 0) {
                ort_yukselis += fark
            } else {
                ort_dusus += (-fark)
            }
            sayac++
        }
        if (sayac == 0) { print "50"; exit }
        ort_yukselis = ort_yukselis / sayac
        ort_dusus = ort_dusus / sayac
        if (ort_dusus == 0) { print "100"; exit }
        rs = ort_yukselis / ort_dusus
        rsi = 100 - (100 / (1 + rs))
        printf "%.2f", rsi
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

    # Gun indeksi (0 tabanli)
    local gun_idx=$((_BACKTEST_GUN_NO - 1))

    # RSI hesapla
    local rsi
    rsi=$(_rsi_hesapla "$gun_idx" "$_RSI_PERIYOT")

    # Yeterli veri yoksa bekle
    if [[ -z "$rsi" ]]; then
        echo "BEKLE"
        return 0
    fi

    # Asiri satim bolgesi — ALIS firsati
    local asiri_satim
    asiri_satim=$(awk "BEGIN { print ($rsi < $_RSI_ASIRI_SATIM) ? 1 : 0 }")
    if [[ "$asiri_satim" == "1" ]] && [[ "$_RSI_POZISYON" == "YOK" ]]; then
        _RSI_POZISYON="ACIK"
        echo "ALIS ${_RSI_LOT} ${fiyat}"
        return 0
    fi

    # Asiri alim bolgesi — SATIS firsati
    local asiri_alim
    asiri_alim=$(awk "BEGIN { print ($rsi > $_RSI_ASIRI_ALIM) ? 1 : 0 }")
    if [[ "$asiri_alim" == "1" ]] && [[ "$_RSI_POZISYON" == "ACIK" ]]; then
        _RSI_POZISYON="YOK"
        echo "SATIS ${_RSI_LOT} ${fiyat}"
        return 0
    fi

    echo "BEKLE"
    return 0
}

# =======================================================
# strateji_min_mum — opsiyonel arayuz
# Stratejinin gecerli sinyal uretebilmesi icin gereken minimum mum sayisi.
# =======================================================
strateji_min_mum() {
    echo "14"
}

# =======================================================
# strateji_temizle
# =======================================================
strateji_temizle() {
    _cekirdek_log "RSI stratejisi temizlendi."
    _RSI_POZISYON=""
}
