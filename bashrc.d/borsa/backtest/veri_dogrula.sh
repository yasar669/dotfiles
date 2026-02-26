# shellcheck shell=bash

# Backtest - Veri Dogrulama
# Yuklenen gecmis fiyat verilerinin butunluk kontrollerini yapar.
# Kontroller: bos veri, eksik fiyat, tarih sirasi, fiyat araligi,
# minimum gun, bosluk tespiti.

# _backtest_veriyi_dogrula
# _BACKTEST_VERI_* dizilerindeki verilere 6 kontrolu uygular.
# Basarisiz satirlari atlar, uyari loglar.
# Donus: 0 = en az 5 gecerli gun var, 1 = yetersiz veri
_backtest_veriyi_dogrula() {
    local toplam=${#_BACKTEST_VERI_TARIH[@]}

    # 1. Bos veri kontrolu
    if [[ "$toplam" -eq 0 ]]; then
        echo "HATA: Veri bos, hic satir yok. Backtest baslatilemiyor." >&2
        return 1
    fi

    # 2-4. Eksik fiyat, fiyat araligi kontrolleri + gecerli satirlari filtrele
    local gecerli_tarih=()
    local gecerli_fiyat=()
    local gecerli_tavan=()
    local gecerli_taban=()
    local gecerli_degisim=()
    local gecerli_hacim=()
    local gecerli_seans=()
    local atlanan=0
    local i

    for (( i=0; i<toplam; i++ )); do
        local fiyat="${_BACKTEST_VERI_FIYAT[$i]}"
        local tarih="${_BACKTEST_VERI_TARIH[$i]}"

        # Eksik fiyat kontrolu
        if [[ -z "$fiyat" ]] || [[ "$fiyat" == "0" ]] || [[ "$fiyat" == "0.00" ]]; then
            echo "UYARI: Satir $((i+1)) (tarih: $tarih) — fiyat bos veya sifir, atlaniyor." >&2
            atlanan=$((atlanan + 1))
            continue
        fi

        # Fiyat araligi kontrolu: fiyat > 0 ve fiyat <= 100000
        local gecerli_mi
        gecerli_mi=$(awk -v f="$fiyat" 'BEGIN { print (f > 0 && f <= 100000) ? 1 : 0 }')
        if [[ "$gecerli_mi" != "1" ]]; then
            echo "UYARI: Satir $((i+1)) (tarih: $tarih) — fiyat aralik disi ($fiyat), atlaniyor." >&2
            atlanan=$((atlanan + 1))
            continue
        fi

        gecerli_tarih+=("${_BACKTEST_VERI_TARIH[$i]}")
        gecerli_fiyat+=("$fiyat")
        gecerli_tavan+=("${_BACKTEST_VERI_TAVAN[$i]:-}")
        gecerli_taban+=("${_BACKTEST_VERI_TABAN[$i]:-}")
        gecerli_degisim+=("${_BACKTEST_VERI_DEGISIM[$i]:-0}")
        gecerli_hacim+=("${_BACKTEST_VERI_HACIM[$i]:-0}")
        gecerli_seans+=("${_BACKTEST_VERI_SEANS[$i]:-}")
    done

    if [[ "$atlanan" -gt 0 ]]; then
        echo "UYARI: $atlanan satir dogrulama basarisizligi nedeniyle atlandi." >&2
    fi

    # Gecerli satirlari geri yaz
    _BACKTEST_VERI_TARIH=("${gecerli_tarih[@]}")
    _BACKTEST_VERI_FIYAT=("${gecerli_fiyat[@]}")
    _BACKTEST_VERI_TAVAN=("${gecerli_tavan[@]}")
    _BACKTEST_VERI_TABAN=("${gecerli_taban[@]}")
    _BACKTEST_VERI_DEGISIM=("${gecerli_degisim[@]}")
    _BACKTEST_VERI_HACIM=("${gecerli_hacim[@]}")
    _BACKTEST_VERI_SEANS=("${gecerli_seans[@]}")

    # 5. Minimum gun kontrolu
    local gecerli_toplam=${#_BACKTEST_VERI_TARIH[@]}
    if [[ "$gecerli_toplam" -lt 5 ]]; then
        echo "HATA: Gecerli veri $gecerli_toplam gun, en az 5 gun gerekli. Backtest baslatilemiyor." >&2
        return 1
    fi

    # 3. Tarih sirasi kontrolu — otomatik yeniden siralama
    _backtest_tarih_sirala

    # 6. Bosluk tespiti
    _backtest_bosluk_kontrol

    return 0
}

# _backtest_tarih_sirala
# _BACKTEST_VERI_* dizilerini tarih sirasina gore yeniden siralar.
# awk ile tum dizileri tek seferde isler.
# Donus: 0
_backtest_tarih_sirala() {
    local toplam=${#_BACKTEST_VERI_TARIH[@]}
    [[ "$toplam" -le 1 ]] && return 0

    # Zaten sirali mi kontrol et
    local sirali=1
    local i
    for (( i=1; i<toplam; i++ )); do
        if [[ "${_BACKTEST_VERI_TARIH[$i]}" < "${_BACKTEST_VERI_TARIH[$((i-1))]}" ]]; then
            sirali=0
            break
        fi
    done
    [[ "$sirali" -eq 1 ]] && return 0

    echo "UYARI: Tarihler sirali degil, otomatik siralaniyor." >&2

    # Tum verileri indeks ile birlestirip sirala
    local sirali_cikti
    sirali_cikti=$(
        for (( i=0; i<toplam; i++ )); do
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "${_BACKTEST_VERI_TARIH[$i]}" \
                "${_BACKTEST_VERI_FIYAT[$i]}" \
                "${_BACKTEST_VERI_TAVAN[$i]}" \
                "${_BACKTEST_VERI_TABAN[$i]}" \
                "${_BACKTEST_VERI_DEGISIM[$i]}" \
                "${_BACKTEST_VERI_HACIM[$i]}" \
                "${_BACKTEST_VERI_SEANS[$i]}"
        done | sort -t$'\t' -k1,1
    )

    # Dizileri sifirla ve yeniden doldur
    _BACKTEST_VERI_TARIH=()
    _BACKTEST_VERI_FIYAT=()
    _BACKTEST_VERI_TAVAN=()
    _BACKTEST_VERI_TABAN=()
    _BACKTEST_VERI_DEGISIM=()
    _BACKTEST_VERI_HACIM=()
    _BACKTEST_VERI_SEANS=()

    while IFS=$'\t' read -r t f tv tb dg hc sn; do
        _BACKTEST_VERI_TARIH+=("$t")
        _BACKTEST_VERI_FIYAT+=("$f")
        _BACKTEST_VERI_TAVAN+=("$tv")
        _BACKTEST_VERI_TABAN+=("$tb")
        _BACKTEST_VERI_DEGISIM+=("$dg")
        _BACKTEST_VERI_HACIM+=("$hc")
        _BACKTEST_VERI_SEANS+=("$sn")
    done <<< "$sirali_cikti"
}

# _backtest_bosluk_kontrol
# Ardisik islem gunleri arasinda 5+ gunluk bosluk olup olmadigini kontrol eder.
# Bosluk varsa uyari yazar ama backtest'i durdurmaz.
# Donus: 0
_backtest_bosluk_kontrol() {
    local toplam=${#_BACKTEST_VERI_TARIH[@]}
    [[ "$toplam" -le 1 ]] && return 0

    local i onceki_epoch anki_epoch fark_gun
    for (( i=1; i<toplam; i++ )); do
        onceki_epoch=$(date -d "${_BACKTEST_VERI_TARIH[$((i-1))]}" +%s 2>/dev/null) || continue
        anki_epoch=$(date -d "${_BACKTEST_VERI_TARIH[$i]}" +%s 2>/dev/null) || continue
        fark_gun=$(( (anki_epoch - onceki_epoch) / 86400 ))
        if [[ "$fark_gun" -ge 5 ]]; then
            echo "UYARI: ${_BACKTEST_VERI_TARIH[$((i-1))]} ile ${_BACKTEST_VERI_TARIH[$i]} arasinda ${fark_gun} gunluk bosluk var." >&2
        fi
    done

    return 0
}
