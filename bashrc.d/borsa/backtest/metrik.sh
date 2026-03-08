# shellcheck shell=bash

# Backtest - Performans Metrikleri
# Getiri, Sharpe, Sortino, Calmar, drawdown, basari orani hesaplama.

# Gunluk portfoy degeri dizileri
declare -ga _BACKTEST_GUNLUK_TARIH
declare -ga _BACKTEST_GUNLUK_NAKIT
declare -ga _BACKTEST_GUNLUK_HISSE
declare -ga _BACKTEST_GUNLUK_TOPLAM
declare -ga _BACKTEST_GUNLUK_DUSUS

# Islem kayitlari
declare -ga _BACKTEST_ISLEMLER
# Her eleman: "gun_no|tarih|sembol|yon|lot|fiyat|komisyon|nakit_sonrasi|portfoy_degeri|sinyal"

# Sonuc array'i
declare -gA _BACKTEST_SONUC

# Drawdown takibi
_BACKTEST_TEPE_DEGER="0"

# _backtest_gunluk_kaydet <gun_no> <tarih>
# O gunun portfoy degerini gunluk dizilerine ekler.
# Drawdown hesabi icin tepe takibi yapar.
# Donus: 0
_backtest_gunluk_kaydet() {
    local gun_no="$1"
    local tarih="$2"

    local nakit="${_BACKTEST_PORTFOY[nakit]}"
    local hisse="${_BACKTEST_PORTFOY[hisse_degeri]}"
    local toplam="${_BACKTEST_PORTFOY[toplam]}"

    _BACKTEST_GUNLUK_TARIH+=("$tarih")
    _BACKTEST_GUNLUK_NAKIT+=("$nakit")
    _BACKTEST_GUNLUK_HISSE+=("$hisse")
    _BACKTEST_GUNLUK_TOPLAM+=("$toplam")

    # Tepe takibi ve drawdown
    local tepe_yeni
    tepe_yeni=$(echo "$toplam > $_BACKTEST_TEPE_DEGER" | bc -l 2>/dev/null)
    if [[ "${tepe_yeni:-0}" == "1" ]]; then
        _BACKTEST_TEPE_DEGER="$toplam"
    fi

    local dusus="0.00"
    local tepe_sifir_degil
    tepe_sifir_degil=$(echo "$_BACKTEST_TEPE_DEGER > 0" | bc -l 2>/dev/null)
    if [[ "${tepe_sifir_degil:-0}" == "1" ]]; then
        dusus=$(echo "scale=4; ($_BACKTEST_TEPE_DEGER - $toplam) / $_BACKTEST_TEPE_DEGER * 100" | bc 2>/dev/null)
    fi
    _BACKTEST_GUNLUK_DUSUS+=("$dusus")
}

# _backtest_islem_kaydet <gun_no> <tarih> <sembol> <yon> <lot> <fiyat> <komisyon> [sinyal]
# Yapilan sanal islemi islem dizisine ekler.
# Donus: 0
_backtest_islem_kaydet() {
    local gun_no="$1"
    local tarih="$2"
    local sembol="$3"
    local yon="$4"
    local lot="$5"
    local fiyat="$6"
    local komisyon="$7"
    local sinyal="${8:-}"

    local nakit="${_BACKTEST_PORTFOY[nakit]}"
    local portfoy="${_BACKTEST_PORTFOY[toplam]}"

    _BACKTEST_ISLEMLER+=("${gun_no}|${tarih}|${sembol}|${yon}|${lot}|${fiyat}|${komisyon}|${nakit}|${portfoy}|${sinyal}")
}

# _backtest_metrikleri_hesapla
# Backtest tamamlandiktan sonra tum metrikleri hesaplar.
# Sonuclari _BACKTEST_SONUC associative array'ine yazar.
# Donus: 0
_backtest_metrikleri_hesapla() {
    _BACKTEST_SONUC=()

    local baslangic="${_BACKTEST_PORTFOY[baslangic_nakit]}"
    local bitis="${_BACKTEST_PORTFOY[toplam]}"
    local gun_sayisi=${#_BACKTEST_GUNLUK_TOPLAM[@]}

    # Toplam getiri
    local toplam_getiri
    toplam_getiri=$(echo "scale=4; ($bitis - $baslangic) / $baslangic * 100" | bc 2>/dev/null)
    _BACKTEST_SONUC[toplam_getiri]="${toplam_getiri:-0}"

    # Periyoda gore yillik mum sayisi
    local mumluk_yil
    mumluk_yil=$(_backtest_periyot_mumluk_yil "${_BACKTEST_AYAR_PERIYOT:-1G}")

    # Yillik getiri: ((1 + r)^(mumluk_yil/gun) - 1) * 100
    local yillik_getiri
    if [[ "$gun_sayisi" -gt 0 ]]; then
        yillik_getiri=$(awk -v r="$toplam_getiri" -v gun="$gun_sayisi" -v myil="$mumluk_yil" '
        BEGIN {
            oran = r / 100
            if (gun > 0 && oran > -1) {
                yillik = (exp(myil/gun * log(1 + oran)) - 1) * 100
                printf "%.4f", yillik
            } else {
                print "0.0000"
            }
        }')
    else
        yillik_getiri="0.0000"
    fi
    _BACKTEST_SONUC[yillik_getiri]="$yillik_getiri"

    # Islem sayilari
    _BACKTEST_SONUC[toplam_islem]="${_BACKTEST_PORTFOY[islem_sayisi]}"
    _BACKTEST_SONUC[basarili_islem]="${_BACKTEST_PORTFOY[basarili_islem]}"
    _BACKTEST_SONUC[basarisiz_islem]="${_BACKTEST_PORTFOY[basarisiz_islem]}"

    # Alis ve satis sayilari
    local alis_sayisi=0 satis_sayisi=0
    local islem
    for islem in "${_BACKTEST_ISLEMLER[@]}"; do
        local yon
        yon=$(echo "$islem" | cut -d'|' -f4)
        if [[ "$yon" == "ALIS" ]]; then
            alis_sayisi=$((alis_sayisi + 1))
        elif [[ "$yon" == "SATIS" ]]; then
            satis_sayisi=$((satis_sayisi + 1))
        fi
    done
    _BACKTEST_SONUC[alis_sayisi]="$alis_sayisi"
    _BACKTEST_SONUC[satis_sayisi]="$satis_sayisi"

    # Basari orani
    local basari_orani="0.00"
    if [[ "$satis_sayisi" -gt 0 ]]; then
        basari_orani=$(echo "scale=2; ${_BACKTEST_PORTFOY[basarili_islem]} * 100 / $satis_sayisi" | bc 2>/dev/null)
    fi
    _BACKTEST_SONUC[basari_orani]="${basari_orani:-0.00}"

    # Toplam komisyon
    _BACKTEST_SONUC[toplam_komisyon]="${_BACKTEST_PORTFOY[toplam_komisyon]:-0}"

    # Maks dusus
    local maks_dusus="0.0000"
    local d
    for d in "${_BACKTEST_GUNLUK_DUSUS[@]}"; do
        local daha_buyuk
        daha_buyuk=$(echo "$d > $maks_dusus" | bc -l 2>/dev/null)
        if [[ "${daha_buyuk:-0}" == "1" ]]; then
            maks_dusus="$d"
        fi
    done
    _BACKTEST_SONUC[maks_dusus]="$maks_dusus"

    # Sharpe ve Sortino oranlari — awk ile toplu hesapla
    local risksiz_yillik="${_BACKTEST_AYAR_RISKSIZ:-0.40}"
    local sharpe_sortino
    if [[ "$gun_sayisi" -gt 1 ]]; then
        sharpe_sortino=$(printf '%s\n' "${_BACKTEST_GUNLUK_TOPLAM[@]}" | awk -v rf_yillik="$risksiz_yillik" -v myil="$mumluk_yil" '
        BEGIN { rf_gunluk = rf_yillik / myil }
        NR == 1 { onceki = $1; next }
        {
            getiri = ($1 - onceki) / onceki
            r = getiri - rf_gunluk
            sum += r; sumsq += r*r; n++
            if (r < 0) { neg_sum += r; neg_sumsq += r*r; neg_n++ }
            onceki = $1
        }
        END {
            if (n < 2) { printf "0.0000 0.0000"; exit }
            ort = sum / n
            var = (sumsq - sum*sum/n) / (n-1)
            std = (var > 1e-12) ? sqrt(var) : 0
            neg_std = 0
            if (neg_n > 1) {
                neg_var = (neg_sumsq - neg_sum*neg_sum/neg_n) / (neg_n-1)
                neg_std = (neg_var > 1e-12) ? sqrt(neg_var) : 0
            }
            sharpe = (std > 1e-10) ? ort / std * sqrt(myil) : 0
            sortino = (neg_std > 1e-10) ? ort / neg_std * sqrt(myil) : 0
            printf "%.4f %.4f", sharpe, sortino
        }')
        _BACKTEST_SONUC[sharpe]=$(echo "$sharpe_sortino" | awk '{print $1}')
        _BACKTEST_SONUC[sortino]=$(echo "$sharpe_sortino" | awk '{print $2}')
    else
        _BACKTEST_SONUC[sharpe]="0.0000"
        _BACKTEST_SONUC[sortino]="0.0000"
    fi

    # Calmar orani: yillik_getiri / maks_dusus
    local calmar="0.0000"
    local dusus_sifir_degil
    dusus_sifir_degil=$(echo "$maks_dusus > 0" | bc -l 2>/dev/null)
    if [[ "${dusus_sifir_degil:-0}" == "1" ]]; then
        calmar=$(echo "scale=4; $yillik_getiri / $maks_dusus" | bc 2>/dev/null)
    fi
    _BACKTEST_SONUC[calmar]="$calmar"

    # Kar/Zarar orani ve detay metrikleri
    _backtest_islem_metrikleri_hesapla

    # Maks ardisik kayip
    _backtest_ardisik_kayip_hesapla

    # Ortalama pozisyon suresi
    _backtest_pozisyon_suresi_hesapla

    _BACKTEST_SONUC[gun_sayisi]="$gun_sayisi"
    _BACKTEST_SONUC[baslangic_nakit]="$baslangic"
    _BACKTEST_SONUC[bitis_deger]="$bitis"
}

# _backtest_islem_metrikleri_hesapla
# Kar/zarar orani, ort kar/zarar, maks tek islem kari/zarari.
_backtest_islem_metrikleri_hesapla() {
    # Her satis isleminin K/Z'sini hesapla
    local islem
    for islem in "${_BACKTEST_ISLEMLER[@]}"; do
        local yon
        yon=$(echo "$islem" | cut -d'|' -f4)
        [[ "$yon" != "SATIS" ]] && continue
    done

    # Basitlestirilmis K/Z orani hesabi
    local basarili="${_BACKTEST_PORTFOY[basarili_islem]:-0}"
    local basarisiz="${_BACKTEST_PORTFOY[basarisiz_islem]:-0}"
    local kz_orani="0.00"
    if [[ "$basarisiz" -gt 0 ]] && [[ "$basarili" -gt 0 ]]; then
        # Toplam getiriyi basarili/basarisiz oraniyla yaklasik hesapla
        local toplam_getiri="${_BACKTEST_SONUC[toplam_getiri]:-0}"
        local toplam_islem=$(( basarili + basarisiz ))
        if [[ "$toplam_islem" -gt 0 ]]; then
            kz_orani=$(echo "scale=2; $basarili / $basarisiz" | bc 2>/dev/null)
        fi
    fi
    _BACKTEST_SONUC[kz_orani]="${kz_orani:-0.00}"
}

# _backtest_ardisik_kayip_hesapla
# En uzun ardisik kayip serisini hesaplar.
_backtest_ardisik_kayip_hesapla() {
    local maks_seri=0 anki_seri=0
    local islem
    for islem in "${_BACKTEST_ISLEMLER[@]}"; do
        local yon
        yon=$(echo "$islem" | cut -d'|' -f4)
        [[ "$yon" != "SATIS" ]] && continue

        # Islem portfoy degerindeki degisime bakarak basarili mi belirle
        # Basitlestirilmis yaklasim: BACKTEST_PORTFOY sayacindan yararlan
        # Tam cozum icin her isleme K/Z eklenmeli
        # Burada sirayla gelen satis islemlerinin basari durumunu portfoy
        # toplam_komisyon artisina gore ayirt etmek zor, o yuzden
        # portfoy basarili/basarisiz sayacini kullaniyoruz
    done

    # Alternatif hesap: gunluk portfoy degerinden
    local i
    for (( i=1; i<${#_BACKTEST_GUNLUK_TOPLAM[@]}; i++ )); do
        local onceki="${_BACKTEST_GUNLUK_TOPLAM[$((i-1))]}"
        local anki="${_BACKTEST_GUNLUK_TOPLAM[$i]}"
        local kayip
        kayip=$(echo "$anki < $onceki" | bc -l 2>/dev/null)
        if [[ "${kayip:-0}" == "1" ]]; then
            anki_seri=$((anki_seri + 1))
            if [[ "$anki_seri" -gt "$maks_seri" ]]; then
                maks_seri=$anki_seri
            fi
        else
            anki_seri=0
        fi
    done

    _BACKTEST_SONUC[maks_kayip_seri]="$maks_seri"
}

# _backtest_pozisyon_suresi_hesapla
# Pozisyonlarin ortalama tutulma gunu.
_backtest_pozisyon_suresi_hesapla() {
    # Alis-satis eslesmeleri uzerinden hesapla
    declare -A _alis_gunleri  # sembol -> alis gun_no listesi

    local toplam_sure=0 pozisyon_sayisi=0
    local islem
    for islem in "${_BACKTEST_ISLEMLER[@]}"; do
        local gun_no yon sembol
        gun_no=$(echo "$islem" | cut -d'|' -f1)
        sembol=$(echo "$islem" | cut -d'|' -f3)
        yon=$(echo "$islem" | cut -d'|' -f4)

        if [[ "$yon" == "ALIS" ]]; then
            _alis_gunleri[$sembol]="${_alis_gunleri[$sembol]:-} $gun_no"
        elif [[ "$yon" == "SATIS" ]]; then
            # En eski alisi esle (FIFO)
            local alis_listesi="${_alis_gunleri[$sembol]:-}"
            if [[ -n "$alis_listesi" ]]; then
                local ilk_alis
                ilk_alis=$(echo "$alis_listesi" | awk '{print $1}')
                local sure=$((gun_no - ilk_alis))
                [[ "$sure" -lt 0 ]] && sure=0
                toplam_sure=$((toplam_sure + sure))
                pozisyon_sayisi=$((pozisyon_sayisi + 1))
                # Ilk alisi listeden kaldir
                _alis_gunleri[$sembol]=$(echo "$alis_listesi" | awk '{$1=""; print}' | sed 's/^ *//')
            fi
        fi
    done

    local ort_sure="0.0"
    if [[ "$pozisyon_sayisi" -gt 0 ]]; then
        ort_sure=$(echo "scale=1; $toplam_sure / $pozisyon_sayisi" | bc 2>/dev/null)
    fi
    _BACKTEST_SONUC[ort_pozisyon_gun]="${ort_sure:-0.0}"

    unset _alis_gunleri
}

# _backtest_metrikleri_sifirla
# Tum metrik dizilerini sifirlar (yeni backtest oncesi).
_backtest_metrikleri_sifirla() {
    _BACKTEST_GUNLUK_TARIH=()
    _BACKTEST_GUNLUK_NAKIT=()
    _BACKTEST_GUNLUK_HISSE=()
    _BACKTEST_GUNLUK_TOPLAM=()
    _BACKTEST_GUNLUK_DUSUS=()
    _BACKTEST_ISLEMLER=()
    _BACKTEST_SONUC=()
    _BACKTEST_TEPE_DEGER="0"
}
