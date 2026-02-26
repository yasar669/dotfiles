# shellcheck shell=bash

# Backtest - Veri Katmani
# Gecmis fiyat verilerini Supabase, CSV veya sentetik kaynaklardan yukler.
# Verileri _BACKTEST_VERI_* dizilerine yazar.

# Veri dizileri (indexed arrays)
declare -ga _BACKTEST_VERI_TARIH
declare -ga _BACKTEST_VERI_FIYAT
declare -ga _BACKTEST_VERI_TAVAN
declare -ga _BACKTEST_VERI_TABAN
declare -ga _BACKTEST_VERI_DEGISIM
declare -ga _BACKTEST_VERI_HACIM
declare -ga _BACKTEST_VERI_SEANS

# _backtest_veri_yukle <sembol> <baslangic_tarih> <bitis_tarih> <kaynak>
# Belirtilen kaynaktan gecmis fiyat verilerini yukler.
# Donus: 0 = veri yuklendi, 1 = veri bulunamadi
_backtest_veri_yukle() {
    local sembol="$1"
    local bas_tarih="$2"
    local bit_tarih="$3"
    local kaynak="${4:-supabase}"

    # Dizileri sifirla
    _BACKTEST_VERI_TARIH=()
    _BACKTEST_VERI_FIYAT=()
    _BACKTEST_VERI_TAVAN=()
    _BACKTEST_VERI_TABAN=()
    _BACKTEST_VERI_DEGISIM=()
    _BACKTEST_VERI_HACIM=()
    _BACKTEST_VERI_SEANS=()

    case "$kaynak" in
        supabase)
            _backtest_supabase_oku "$sembol" "$bas_tarih" "$bit_tarih"
            ;;
        csv)
            _backtest_csv_oku "${_BACKTEST_AYAR_CSV_DOSYA:-}" "$sembol"
            ;;
        sentetik)
            # Tarih araligina gore gun sayisini hesapla
            local _st_gun=250
            if [[ -n "$bas_tarih" ]] && [[ -n "$bit_tarih" ]]; then
                local _st_bas _st_bit _st_fark
                _st_bas=$(date -d "$bas_tarih" +%s 2>/dev/null)
                _st_bit=$(date -d "$bit_tarih" +%s 2>/dev/null)
                if [[ -n "$_st_bas" ]] && [[ -n "$_st_bit" ]]; then
                    _st_fark=$(( (_st_bit - _st_bas) / 86400 ))
                    # Takvim gunlerini islem gunune cevir (~5/7 orani)
                    _st_gun=$(( _st_fark * 5 / 7 ))
                    [[ "$_st_gun" -lt 5 ]] && _st_gun=5
                fi
            fi
            _backtest_sentetik_uret "$sembol" 100 "$_st_gun" 0.02 "$bas_tarih"
            ;;
        *)
            echo "HATA: Bilinmeyen veri kaynagi: $kaynak" >&2
            return 1
            ;;
    esac
}

# _backtest_supabase_oku <sembol> <baslangic_tarih> <bitis_tarih> [periyot]
# Supabase ohlcv tablosundan veri ceker.
# Donus: 0 = veri var, 1 = bos veya hata
_backtest_supabase_oku() {
    local sembol="$1"
    local bas_tarih="$2"
    local bit_tarih="$3"
    local periyot="${4:-1G}"

    # Supabase ayarlari yuklu mu?
    if [[ -z "${_SUPABASE_URL:-}" ]] || [[ -z "${_SUPABASE_ANAHTAR:-}" ]]; then
        echo "HATA: Supabase ayarlari yuklu degil. CSV veya sentetik kaynak kullanin." >&2
        return 1
    fi

    local url="${_SUPABASE_URL}/rest/v1/ohlcv"
    url="${url}?sembol=eq.${sembol}"
    url="${url}&periyot=eq.${periyot}"
    url="${url}&tarih=gte.${bas_tarih}"
    url="${url}&tarih=lte.${bit_tarih}"
    url="${url}&order=tarih.asc"
    url="${url}&select=sembol,tarih,acilis,yuksek,dusuk,kapanis,hacim"

    local yanit
    yanit=$(curl -s -X GET "$url" \
        -H "apikey: ${_SUPABASE_ANAHTAR}" \
        -H "Authorization: Bearer ${_SUPABASE_ANAHTAR}" \
        -H "Content-Type: application/json" 2>/dev/null)

    if [[ -z "$yanit" ]] || [[ "$yanit" == "[]" ]]; then
        echo "HATA: Supabase'de $sembol icin $bas_tarih - $bit_tarih arasinda veri bulunamadi (periyot: $periyot)." >&2
        return 1
    fi

    # JSON parse — jq varsa kullan
    local satir_sayisi=0
    if command -v jq > /dev/null 2>&1; then
        while IFS=$'\t' read -r tarih acilis yuksek dusuk kapanis hacim_d; do
            [[ -z "$kapanis" ]] && continue
            _BACKTEST_VERI_TARIH+=("$tarih")
            _BACKTEST_VERI_FIYAT+=("$kapanis")
            _BACKTEST_VERI_ACILIS+=("${acilis:-0}")
            _BACKTEST_VERI_YUKSEK+=("${yuksek:-0}")
            _BACKTEST_VERI_DUSUK+=("${dusuk:-0}")
            _BACKTEST_VERI_HACIM+=("${hacim_d:-0}")
            satir_sayisi=$((satir_sayisi + 1))
        done < <(echo "$yanit" | jq -r '.[] | "\(.tarih)\t\(.acilis)\t\(.yuksek)\t\(.dusuk)\t\(.kapanis)\t\(.hacim)"' 2>/dev/null)
    else
        while IFS= read -r satir; do
            [[ -z "$satir" ]] && continue
            local tarih kapanis acilis yuksek dusuk hacim_d
            tarih=$(echo "$satir" | awk -F'"' '{ for(i=1;i<=NF;i++) if($i=="tarih") print $(i+2) }' | cut -c1-10)
            kapanis=$(echo "$satir" | awk -F'[:,}]' '{ for(i=1;i<=NF;i++) if($i ~ /"kapanis"/) print $(i+1) }' | tr -d ' "')
            acilis=$(echo "$satir" | awk -F'[:,}]' '{ for(i=1;i<=NF;i++) if($i ~ /"acilis"/) print $(i+1) }' | tr -d ' "')
            yuksek=$(echo "$satir" | awk -F'[:,}]' '{ for(i=1;i<=NF;i++) if($i ~ /"yuksek"/) print $(i+1) }' | tr -d ' "')
            dusuk=$(echo "$satir" | awk -F'[:,}]' '{ for(i=1;i<=NF;i++) if($i ~ /"dusuk"/) print $(i+1) }' | tr -d ' "')
            hacim_d=$(echo "$satir" | awk -F'[:,}]' '{ for(i=1;i<=NF;i++) if($i ~ /"hacim"/) print $(i+1) }' | tr -d ' "')

            [[ -z "$kapanis" ]] && continue
            _BACKTEST_VERI_TARIH+=("$tarih")
            _BACKTEST_VERI_FIYAT+=("$kapanis")
            _BACKTEST_VERI_ACILIS+=("${acilis:-0}")
            _BACKTEST_VERI_YUKSEK+=("${yuksek:-0}")
            _BACKTEST_VERI_DUSUK+=("${dusuk:-0}")
            _BACKTEST_VERI_HACIM+=("${hacim_d:-0}")
            satir_sayisi=$((satir_sayisi + 1))
        done < <(echo "$yanit" | tr '[{' '\n' | grep '"kapanis"')
    fi

    if [[ "$satir_sayisi" -eq 0 ]]; then
        echo "HATA: Supabase yanitindan veri parse edilemedi." >&2
        return 1
    fi

    return 0
}

# _backtest_csv_oku <dosya_yolu> <sembol>
# CSV dosyasindan fiyat verisini okur.
# Beklenen format: tarih,fiyat,tavan,taban,degisim,hacim
# En az tarih ve fiyat sutunlari zorunlu.
# Donus: 0 = basarili, 1 = dosya okunamadi veya format hatasi
_backtest_csv_oku() {
    local dosya="$1"
    local sembol="$2"

    if [[ -z "$dosya" ]]; then
        echo "HATA: CSV dosya yolu belirtilmedi." >&2
        return 1
    fi

    if [[ ! -f "$dosya" ]]; then
        echo "HATA: CSV dosyasi bulunamadi: $dosya" >&2
        return 1
    fi

    # Baslik satirini oku ve dogrula
    local baslik
    baslik=$(head -n 1 "$dosya")
    baslik=$(echo "$baslik" | tr '[:upper:]' '[:lower:]' | tr -d '\r')

    # En az tarih ve fiyat zorunlu
    if [[ "$baslik" != *"tarih"* ]] || [[ "$baslik" != *"fiyat"* ]]; then
        echo "HATA: CSV baslik satiri gecersiz. En az 'tarih' ve 'fiyat' sutunlari gerekli." >&2
        echo "Beklenen: tarih,fiyat,tavan,taban,degisim,hacim" >&2
        return 1
    fi

    # Sutun indekslerini bul
    local idx_tarih=-1 idx_fiyat=-1 idx_tavan=-1 idx_taban=-1 idx_degisim=-1 idx_hacim=-1
    IFS=',' read -ra sutunlar <<< "$baslik"
    local j
    for j in "${!sutunlar[@]}"; do
        local s="${sutunlar[$j]}"
        s=$(echo "$s" | tr -d '[:space:]')
        case "$s" in
            tarih)    idx_tarih=$j ;;
            fiyat)    idx_fiyat=$j ;;
            tavan)    idx_tavan=$j ;;
            taban)    idx_taban=$j ;;
            degisim)  idx_degisim=$j ;;
            hacim)    idx_hacim=$j ;;
        esac
    done

    if [[ "$idx_tarih" -eq -1 ]] || [[ "$idx_fiyat" -eq -1 ]]; then
        echo "HATA: 'tarih' veya 'fiyat' sutunu bulunamadi." >&2
        return 1
    fi

    # Satirlari oku (baslik atlaniyor)
    local satir_no=0
    local onceki_fiyat=""
    while IFS=',' read -ra alanlar; do
        satir_no=$((satir_no + 1))
        [[ "$satir_no" -eq 1 ]] && continue  # baslik satiri

        local tarih="${alanlar[$idx_tarih]:-}"
        local fiyat="${alanlar[$idx_fiyat]:-}"
        tarih=$(echo "$tarih" | tr -d '[:space:]' | tr -d '\r')
        fiyat=$(echo "$fiyat" | tr -d '[:space:]' | tr -d '\r')

        [[ -z "$tarih" ]] && continue
        [[ -z "$fiyat" ]] && continue

        local tavan="" taban="" degisim="0" hacim="0"
        [[ "$idx_tavan" -ge 0 ]] && tavan="${alanlar[$idx_tavan]:-}"
        [[ "$idx_taban" -ge 0 ]] && taban="${alanlar[$idx_taban]:-}"
        [[ "$idx_degisim" -ge 0 ]] && degisim="${alanlar[$idx_degisim]:-0}"
        [[ "$idx_hacim" -ge 0 ]] && hacim="${alanlar[$idx_hacim]:-0}"

        # Bosluklari temizle
        tavan=$(echo "$tavan" | tr -d '[:space:]' | tr -d '\r')
        taban=$(echo "$taban" | tr -d '[:space:]' | tr -d '\r')
        degisim=$(echo "$degisim" | tr -d '[:space:]' | tr -d '\r')
        hacim=$(echo "$hacim" | tr -d '[:space:]' | tr -d '\r')

        # Tavan/taban yoksa onceki kapanistan hesapla
        if [[ -z "$tavan" ]] || [[ "$tavan" == "0" ]]; then
            if [[ -n "$onceki_fiyat" ]]; then
                tavan=$(echo "scale=2; $onceki_fiyat * 1.10" | bc 2>/dev/null)
            else
                tavan=$(echo "scale=2; $fiyat * 1.10" | bc 2>/dev/null)
            fi
        fi
        if [[ -z "$taban" ]] || [[ "$taban" == "0" ]]; then
            if [[ -n "$onceki_fiyat" ]]; then
                taban=$(echo "scale=2; $onceki_fiyat * 0.90" | bc 2>/dev/null)
            else
                taban=$(echo "scale=2; $fiyat * 0.90" | bc 2>/dev/null)
            fi
        fi

        _BACKTEST_VERI_TARIH+=("$tarih")
        _BACKTEST_VERI_FIYAT+=("$fiyat")
        _BACKTEST_VERI_TAVAN+=("$tavan")
        _BACKTEST_VERI_TABAN+=("$taban")
        _BACKTEST_VERI_DEGISIM+=("${degisim:-0}")
        _BACKTEST_VERI_HACIM+=("${hacim:-0}")
        _BACKTEST_VERI_SEANS+=("Surekli Islem")

        onceki_fiyat="$fiyat"
    done < "$dosya"

    local yuklenen=${#_BACKTEST_VERI_TARIH[@]}
    if [[ "$yuklenen" -eq 0 ]]; then
        echo "HATA: CSV dosyasindan hic veri okunamadi." >&2
        return 1
    fi

    echo "$sembol: CSV'den $yuklenen satir yuklendi." >&2
    return 0
}

# _backtest_sentetik_uret <sembol> <baslangic_fiyat> <gun_sayisi> <volatilite> [baslangic_tarih]
# GBM (Geometric Brownian Motion) ile yapay fiyat verisi uretir.
# awk kullanir (exp, log, sqrt, rand fonksiyonlari icin).
# Donus: 0
_backtest_sentetik_uret() {
    local sembol="$1"
    local bas_fiyat="${2:-100}"
    local gun="${3:-250}"
    local vol="${4:-0.02}"
    local bas_tarih="${5:-}"

    # Baslangic tarihinin yil, ay, gun parcalanmasi
    local _st_yil=2024 _st_ay=1 _st_gun=2
    if [[ -n "$bas_tarih" ]]; then
        _st_yil="${bas_tarih%%-*}"
        local _st_kalan="${bas_tarih#*-}"
        _st_ay="${_st_kalan%%-*}"
        _st_gun="${_st_kalan#*-}"
        # Bastaki sifirlari kaldir
        _st_ay="${_st_ay#0}"
        _st_gun="${_st_gun#0}"
    fi

    echo "$sembol: Sentetik veri uretiliyor ($gun gun, baslangic: $bas_fiyat TL, volatilite: $vol)..." >&2

    local cikti
    cikti=$(awk -v bas="$bas_fiyat" -v gun_sayisi="$gun" -v vol="$vol" \
        -v drift=0 -v seed="$RANDOM" \
        -v baslangic_yil="$_st_yil" -v baslangic_ay="$_st_ay" -v baslangic_gun="$_st_gun" '
BEGIN {
    srand(seed)
    fiyat = bas
    yil = baslangic_yil; ay = baslangic_ay; g = baslangic_gun
    for (i = 1; i <= gun_sayisi; i++) {
        # Box-Muller: iki uniform -> bir normal
        u1 = rand(); u2 = rand()
        if (u1 < 0.0001) u1 = 0.0001
        z = sqrt(-2 * log(u1)) * cos(2 * 3.14159265358979 * u2)
        # GBM: S(t+1) = S(t) * exp((drift - vol^2/2)*dt + vol*sqrt(dt)*z)
        fiyat = fiyat * exp((drift - vol*vol/2) + vol * z)
        if (fiyat < 0.01) fiyat = 0.01
        # Tavan/taban
        onceki = (i == 1) ? bas : onceki_fiyat
        tavan = onceki * 1.10
        taban = onceki * 0.90
        onceki_fiyat = fiyat
        # Degisim
        degisim = (i == 1) ? 0 : ((fiyat - onceki) / onceki * 100)
        # Hacim: normal dagilim (ort=10M, std=3M), minimum 100K
        h1 = rand(); h2 = rand()
        if (h1 < 0.0001) h1 = 0.0001
        hacim = int(10000000 + 3000000 * sqrt(-2*log(h1)) * cos(2*3.14159265358979*h2))
        if (hacim < 100000) hacim = 100000
        # Tarih hesapla (basit: hafta ici gunleri)
        printf "%04d-%02d-%02d,%.2f,%.2f,%.2f,%.2f,%d\n", yil, ay, g, fiyat, tavan, taban, degisim, hacim
        # Sonraki is gunu
        g++
        if (g > 28) { g = 1; ay++ }
        if (ay > 12) { ay = 1; yil++ }
        # Basitlestirilmis hafta sonu atlama (cumartesi-pazar yok)
    }
}')

    while IFS=',' read -r tarih fiyat tavan taban degisim hacim; do
        [[ -z "$tarih" ]] && continue
        _BACKTEST_VERI_TARIH+=("$tarih")
        _BACKTEST_VERI_FIYAT+=("$fiyat")
        _BACKTEST_VERI_TAVAN+=("$tavan")
        _BACKTEST_VERI_TABAN+=("$taban")
        _BACKTEST_VERI_DEGISIM+=("$degisim")
        _BACKTEST_VERI_HACIM+=("$hacim")
        _BACKTEST_VERI_SEANS+=("Surekli Islem")
    done <<< "$cikti"

    echo "$sembol: $gun gun sentetik veri olusturuldu." >&2
    return 0
}

# backtest_veri_yukle_csv <dosya_yolu> <sembol> [periyot]
# Dis komut: CSV dosyasindan ohlcv tablosuna toplu veri aktarir.
# "borsa backtest yukle" alt komutunun arka ucu.
# Donus: 0 = basarili, 1 = hata
backtest_veri_yukle_csv() {
    local dosya="$1"
    local sembol="$2"
    local periyot="${3:-1G}"

    if [[ -z "$dosya" ]] || [[ -z "$sembol" ]]; then
        echo "Kullanim: borsa backtest yukle <dosya.csv> <SEMBOL> [PERIYOT]"
        return 1
    fi

    if [[ -z "${_SUPABASE_URL:-}" ]] || [[ -z "${_SUPABASE_ANAHTAR:-}" ]]; then
        echo "HATA: Supabase ayarlari yuklu degil. Veri aktarimi icin Supabase gerekli." >&2
        return 1
    fi

    # Gecici olarak veri dizilerine yukle
    _BACKTEST_VERI_TARIH=()
    _BACKTEST_VERI_FIYAT=()
    _BACKTEST_VERI_ACILIS=()
    _BACKTEST_VERI_YUKSEK=()
    _BACKTEST_VERI_DUSUK=()
    _BACKTEST_VERI_HACIM=()

    _backtest_csv_oku "$dosya" "$sembol" || return 1

    local toplam=${#_BACKTEST_VERI_TARIH[@]}
    local eklenen=0 atlanan=0
    local i

    for (( i=0; i<toplam; i++ )); do
        local json
        json=$(printf '{"sembol":"%s","periyot":"%s","tarih":"%sT00:00:00Z","acilis":%s,"yuksek":%s,"dusuk":%s,"kapanis":%s,"hacim":%s}' \
            "$sembol" \
            "$periyot" \
            "${_BACKTEST_VERI_TARIH[$i]}" \
            "${_BACKTEST_VERI_ACILIS[$i]:-${_BACKTEST_VERI_FIYAT[$i]}}" \
            "${_BACKTEST_VERI_YUKSEK[$i]:-${_BACKTEST_VERI_FIYAT[$i]}}" \
            "${_BACKTEST_VERI_DUSUK[$i]:-${_BACKTEST_VERI_FIYAT[$i]}}" \
            "${_BACKTEST_VERI_FIYAT[$i]}" \
            "${_BACKTEST_VERI_HACIM[$i]:-0}")

        local yanit
        yanit=$(curl -s -X POST "${_SUPABASE_URL}/rest/v1/ohlcv" \
            -H "apikey: ${_SUPABASE_ANAHTAR}" \
            -H "Authorization: Bearer ${_SUPABASE_ANAHTAR}" \
            -H "Content-Type: application/json" \
            -H "Prefer: return=minimal" \
            -d "$json" 2>/dev/null)

        if [[ -z "$yanit" ]]; then
            eklenen=$((eklenen + 1))
        else
            atlanan=$((atlanan + 1))
        fi
    done

    echo "$sembol: $eklenen satir ohlcv tablosuna aktarildi, $atlanan satir atlandi."
    return 0
}
