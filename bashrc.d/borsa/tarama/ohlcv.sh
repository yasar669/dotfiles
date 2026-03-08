# shellcheck shell=bash

# Tarama Katmani - OHLCV Mum Verisi
# Strateji ve robot katmaninin OHLCV verisine erisim noktasi.
# Tum mum verisi bu dosyadaki fonksiyonlar uzerinden alinir.
#
# Ana fonksiyon: mum_al "THYAO" "1G" 200
# Veri zinciri: Supabase -> tvDatafeed -> Yahoo Finance
#
# Yuklenme: cekirdek.sh tarafindan source edilir.

# =======================================================
# YAPILANDIRMA
# =======================================================

_OHLCV_ONBELLEK_DIZIN="/tmp/borsa/_ohlcv_onbellek"
_OHLCV_ONBELLEK_SURESI_1DK=300     # 5 dakika
_OHLCV_ONBELLEK_SURESI_15DK=900    # 15 dakika
_OHLCV_ONBELLEK_SURESI_1S=3600     # 1 saat
_OHLCV_ONBELLEK_SURESI_1G=86400    # 1 gun
_OHLCV_ONBELLEK_SURESI_1H=604800   # 1 hafta

# Python yollari
_TVDATAFEED_CAGIR="${BORSA_KLASORU}/tarama/_tvdatafeed_cagir.py"
_TVDATAFEED_TOPLU="${BORSA_KLASORU}/tarama/_tvdatafeed_toplu.py"
_BIST_SEMBOL_LISTESI="${BORSA_KLASORU}/tarama/_bist_sembol_listesi.py"

# Python calistiricisi (venv varsa onu kullan)
_OHLCV_PYTHON=""

# Desteklenen periyotlar
declare -ga _OHLCV_PERIYOTLAR=(
    "1dk" "3dk" "5dk" "15dk" "30dk" "45dk"
    "1S" "2S" "3S" "4S"
    "1G" "1H" "1A"
)

# Yahoo Finance periyot eslesmesi
declare -gA _YAHOO_PERIYOT_ESLE=(
    ["1dk"]="1m"
    ["5dk"]="5m"
    ["15dk"]="15m"
    ["30dk"]="30m"
    ["1S"]="60m"
    ["1G"]="1d"
    ["1H"]="1wk"
    ["1A"]="1mo"
)

# Yahoo Finance aralik eslesmesi
declare -gA _YAHOO_ARALIK_ESLE=(
    ["1dk"]="7d"
    ["5dk"]="60d"
    ["15dk"]="60d"
    ["30dk"]="60d"
    ["1S"]="730d"
    ["1G"]="10y"
    ["1H"]="10y"
    ["1A"]="10y"
)

# =======================================================
# BOLUM 1: PYTHON KONTROL
# =======================================================

# -------------------------------------------------------
# _ohlcv_python_bul
# Uygun Python calistiricisini bulur (venv oncelikli).
# _OHLCV_PYTHON degiskenini ayarlar.
# Donus: 0 = bulundu, 1 = bulunamadi
# -------------------------------------------------------
_ohlcv_python_bul() {
    # Onceden bulunmussa tekrar arama
    if [[ -n "$_OHLCV_PYTHON" ]] && [[ -x "$_OHLCV_PYTHON" ]]; then
        return 0
    fi

    # 1. Venv python'u
    local venv_python="${HOME}/dotfiles/.venv/bin/python"
    if [[ -x "$venv_python" ]]; then
        _OHLCV_PYTHON="$venv_python"
        return 0
    fi

    # 2. Sistem python3
    if command -v python3 > /dev/null 2>&1; then
        _OHLCV_PYTHON="python3"
        return 0
    fi

    return 1
}

# -------------------------------------------------------
# _tvdatafeed_hazir_mi
# tvDatafeed'in calisip calismadigini kontrol eder.
# Donus: 0 = hazir, 1 = eksik
# -------------------------------------------------------
_tvdatafeed_hazir_mi() {
    _ohlcv_python_bul || return 1

    # tvDatafeed import testi
    "$_OHLCV_PYTHON" -c "from _tvdatafeed_main import TvDatafeed" \
        2>/dev/null || return 1

    [[ -f "$_TVDATAFEED_CAGIR" ]] || return 1

    return 0
}

# =======================================================
# BOLUM 2: ONBELLEK FONKSIYONLARI
# =======================================================

# -------------------------------------------------------
# _ohlcv_onbellek_suresi <periyot>
# Periyoda gore onbellek suresini doner (saniye).
# stdout: saniye
# -------------------------------------------------------
_ohlcv_onbellek_suresi() {
    local periyot="$1"
    case "$periyot" in
        1dk|3dk|5dk)    echo "$_OHLCV_ONBELLEK_SURESI_1DK" ;;
        15dk|30dk|45dk) echo "$_OHLCV_ONBELLEK_SURESI_15DK" ;;
        1S|2S|3S|4S)    echo "$_OHLCV_ONBELLEK_SURESI_1S" ;;
        1G)             echo "$_OHLCV_ONBELLEK_SURESI_1G" ;;
        1H|1A)          echo "$_OHLCV_ONBELLEK_SURESI_1H" ;;
        *)              echo "300" ;;
    esac
}

# -------------------------------------------------------
# _ohlcv_onbellek_oku <sembol> <periyot> <limit>
# Oncbellekten OHLCV verisini okur.
# stdout: CSV formati (tarih,acilis,yuksek,dusuk,kapanis,hacim)
# Donus: 0 = taze, 1 = eski veya yok
# -------------------------------------------------------
_ohlcv_onbellek_oku() {
    local sembol="$1"
    local periyot="$2"
    local limit="$3"
    local dosya="${_OHLCV_ONBELLEK_DIZIN}/${sembol}_${periyot}_${limit}.csv"

    [[ ! -f "$dosya" ]] && return 1

    # Suresi dolmus mu?
    local dosya_zamani
    dosya_zamani=$(stat -c %Y "$dosya" 2>/dev/null) || return 1

    local simdi
    simdi=$(date +%s)
    local sure
    sure=$(_ohlcv_onbellek_suresi "$periyot")
    local gecen=$(( simdi - dosya_zamani ))

    if [[ "$gecen" -gt "$sure" ]]; then
        return 1
    fi

    cat "$dosya"
    return 0
}

# -------------------------------------------------------
# _ohlcv_onbellek_yaz <sembol> <periyot> <limit> <veri>
# Onbellege OHLCV verisini yazar.
# -------------------------------------------------------
_ohlcv_onbellek_yaz() {
    local sembol="$1"
    local periyot="$2"
    local limit="$3"
    local veri="$4"

    mkdir -p "$_OHLCV_ONBELLEK_DIZIN" 2>/dev/null
    local dosya="${_OHLCV_ONBELLEK_DIZIN}/${sembol}_${periyot}_${limit}.csv"
    echo "$veri" > "$dosya"
}

# =======================================================
# BOLUM 3: VERI KAYNAKLARI
# =======================================================

# -------------------------------------------------------
# _ohlcv_supabase_cek <sembol> <periyot> <limit>
# Supabase'den OHLCV verisini ceker ve CSV formatina cevirir.
# stdout: CSV (tarih,acilis,yuksek,dusuk,kapanis,hacim)
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
_ohlcv_supabase_cek() {
    local sembol="$1"
    local periyot="$2"
    local limit="$3"

    # vt_ohlcv_oku fonksiyonu tanimli mi?
    if ! declare -f vt_ohlcv_oku > /dev/null 2>&1; then
        return 1
    fi

    local yanit
    yanit=$(vt_ohlcv_oku "$sembol" "$periyot" "$limit") || return 1

    # Bos JSON dizisi kontrolu
    if [[ "$yanit" == "[]" ]] || [[ -z "$yanit" ]]; then
        return 1
    fi

    # JSON -> CSV donusumu
    if command -v jq > /dev/null 2>&1; then
        echo "$yanit" | jq -r '.[] | [.tarih, .acilis, .yuksek, .dusuk, .kapanis, .hacim] | @csv' \
            2>/dev/null | tr -d '"'
    else
        # jq yoksa basit grep/sed ile ayristir
        echo "$yanit" | grep -oP '\{[^}]+\}' | while IFS= read -r satir; do
            local tarih acilis yuksek dusuk kapanis hacim
            tarih=$(echo "$satir" | grep -oP '"tarih"\s*:\s*"\K[^"]+')
            acilis=$(echo "$satir" | grep -oP '"acilis"\s*:\s*\K[0-9.]+')
            yuksek=$(echo "$satir" | grep -oP '"yuksek"\s*:\s*\K[0-9.]+')
            dusuk=$(echo "$satir" | grep -oP '"dusuk"\s*:\s*\K[0-9.]+')
            kapanis=$(echo "$satir" | grep -oP '"kapanis"\s*:\s*\K[0-9.]+')
            hacim=$(echo "$satir" | grep -oP '"hacim"\s*:\s*\K[0-9]+')
            echo "${tarih},${acilis},${yuksek},${dusuk},${kapanis},${hacim}"
        done
    fi

    return 0
}

# -------------------------------------------------------
# _ohlcv_tvdatafeed_cek <sembol> <periyot> <limit>
# tvDatafeed ile OHLCV verisini ceker.
# stdout: CSV (tarih,acilis,yuksek,dusuk,kapanis,hacim)
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
_ohlcv_tvdatafeed_cek() {
    local sembol="$1"
    local periyot="$2"
    local limit="$3"

    _tvdatafeed_hazir_mi || return 1

    local tarama_dizin
    tarama_dizin=$(dirname "$_TVDATAFEED_CAGIR")

    local sonuc
    sonuc=$(cd "$tarama_dizin" && "$_OHLCV_PYTHON" "$_TVDATAFEED_CAGIR" \
        "$sembol" "$periyot" "$limit" 2>/dev/null) || return 1

    if [[ -z "$sonuc" ]]; then
        return 1
    fi

    echo "$sonuc"
    return 0
}

# -------------------------------------------------------
# _ohlcv_yahoo_cek <sembol> <periyot> <limit>
# Yahoo Finance'ten OHLCV verisini ceker (curl ile).
# stdout: CSV (tarih,acilis,yuksek,dusuk,kapanis,hacim)
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
_ohlcv_yahoo_cek() {
    local sembol="$1"
    local periyot="$2"
    local limit="$3"

    # Yahoo'da karsiligi olmayan periyotlar
    local yahoo_periyot="${_YAHOO_PERIYOT_ESLE[$periyot]:-}"
    if [[ -z "$yahoo_periyot" ]]; then
        return 1
    fi

    local yahoo_aralik="${_YAHOO_ARALIK_ESLE[$periyot]:-1y}"

    # BIST sembolleri Yahoo'da .IS uzantili
    local yahoo_sembol="${sembol}.IS"

    local url="https://query1.finance.yahoo.com/v8/finance/chart/${yahoo_sembol}"
    url+="?interval=${yahoo_periyot}&range=${yahoo_aralik}"

    local yanit
    yanit=$(curl -sf \
        -H "User-Agent: Mozilla/5.0" \
        "$url" 2>/dev/null) || return 1

    if [[ -z "$yanit" ]]; then
        return 1
    fi

    # jq ile JSON parse
    if ! command -v jq > /dev/null 2>&1; then
        return 1
    fi

    local satirlar
    satirlar=$(echo "$yanit" | jq -r '
        .chart.result[0] |
        .timestamp as $ts |
        .indicators.quote[0] |
        [range(0; ($ts | length))] |
        map(
            ($ts[.] | todate) + "," +
            (input.open[.] // 0 | tostring) + "," +
            (input.high[.] // 0 | tostring) + "," +
            (input.low[.] // 0 | tostring) + "," +
            (input.close[.] // 0 | tostring) + "," +
            (input.volume[.] // 0 | tostring)
        ) | reverse | .[]
    ' 2>/dev/null)

    # jq karmasik sorgusu basarisiz olabilir — basitlestir
    if [[ -z "$satirlar" ]]; then
        # Basit jq ile dene
        local uzunluk
        uzunluk=$(echo "$yanit" | jq '.chart.result[0].timestamp | length' 2>/dev/null)
        [[ -z "$uzunluk" ]] || [[ "$uzunluk" == "0" ]] && return 1

        local i csv_satirlar=""
        for (( i = uzunluk - 1; i >= 0 && i >= uzunluk - limit; i-- )); do
            local tarih acilis yuksek dusuk kapanis hacim
            tarih=$(echo "$yanit" | jq -r ".chart.result[0].timestamp[$i] | todate" 2>/dev/null)
            acilis=$(echo "$yanit" | jq -r ".chart.result[0].indicators.quote[0].open[$i] // 0" 2>/dev/null)
            yuksek=$(echo "$yanit" | jq -r ".chart.result[0].indicators.quote[0].high[$i] // 0" 2>/dev/null)
            dusuk=$(echo "$yanit" | jq -r ".chart.result[0].indicators.quote[0].low[$i] // 0" 2>/dev/null)
            kapanis=$(echo "$yanit" | jq -r ".chart.result[0].indicators.quote[0].close[$i] // 0" 2>/dev/null)
            hacim=$(echo "$yanit" | jq -r ".chart.result[0].indicators.quote[0].volume[$i] // 0" 2>/dev/null)

            if [[ -n "$tarih" ]] && [[ "$tarih" != "null" ]]; then
                csv_satirlar+="${tarih},${acilis},${yuksek},${dusuk},${kapanis},${hacim}"$'\n'
            fi
        done

        if [[ -z "$csv_satirlar" ]]; then
            return 1
        fi
        echo "$csv_satirlar"
        return 0
    fi

    # limit uygula
    echo "$satirlar" | head -n "$limit"
    return 0
}

# =======================================================
# BOLUM 4: ANA FONKSIYONLAR
# =======================================================

# -------------------------------------------------------
# mum_al <sembol> <periyot> <limit>
# OHLCV mum verisi cekim fonksiyonu.
# Strateji ve robot katmaninin tek erisim noktasi.
#
# Veri zinciri:
#   1. Onbellek (taze ise)
#   2. Supabase (ana depo)
#   3. tvDatafeed (Python, WS)
#   4. Yahoo Finance (curl yedegi)
#
# sembol:  THYAO, GARAN, AKBNK vb.
# periyot: 1dk 3dk 5dk 15dk 30dk 45dk 1S 2S 3S 4S 1G 1H 1A
# limit:   cekilecek mum sayisi (varsayilan 200)
#
# stdout: CSV (tarih,acilis,yuksek,dusuk,kapanis,hacim)
#         en yeni en ustte
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
mum_al() {
    local sembol="${1:-}"
    local periyot="${2:-1G}"
    local limit="${3:-200}"

    # Parametre dogrulama
    if [[ -z "$sembol" ]]; then
        _cekirdek_log "HATA: mum_al — sembol belirtilmedi"
        return 1
    fi

    sembol="${sembol^^}"  # Buyuk harfe cevir

    # Periyot dogrulama
    local gecerli=0
    local p
    for p in "${_OHLCV_PERIYOTLAR[@]}"; do
        if [[ "$p" == "$periyot" ]]; then
            gecerli=1
            break
        fi
    done
    if [[ "$gecerli" -eq 0 ]]; then
        _cekirdek_log "HATA: mum_al — gecersiz periyot: $periyot"
        return 1
    fi

    local sonuc=""

    # 1. Onbellek
    sonuc=$(_ohlcv_onbellek_oku "$sembol" "$periyot" "$limit" 2>/dev/null)
    if [[ -n "$sonuc" ]]; then
        echo "$sonuc"
        return 0
    fi

    # 2. Supabase
    sonuc=$(_ohlcv_supabase_cek "$sembol" "$periyot" "$limit" 2>/dev/null)
    if [[ -n "$sonuc" ]]; then
        _ohlcv_onbellek_yaz "$sembol" "$periyot" "$limit" "$sonuc"
        echo "$sonuc"
        return 0
    fi

    # 3. tvDatafeed (3 deneme)
    local deneme
    for deneme in 1 2 3; do
        sonuc=$(_ohlcv_tvdatafeed_cek "$sembol" "$periyot" "$limit" 2>/dev/null)
        if [[ -n "$sonuc" ]]; then
            _ohlcv_onbellek_yaz "$sembol" "$periyot" "$limit" "$sonuc"
            # Ayrica Supabase'e de yaz (arka planda)
            _ohlcv_supabase_kaydet "$sembol" "$periyot" "$sonuc" &
            echo "$sonuc"
            return 0
        fi
        sleep $(( deneme * 3 ))
    done

    # 4. Yahoo Finance yedegi
    sonuc=$(_ohlcv_yahoo_cek "$sembol" "$periyot" "$limit" 2>/dev/null)
    if [[ -n "$sonuc" ]]; then
        _ohlcv_onbellek_yaz "$sembol" "$periyot" "$limit" "$sonuc"
        echo "$sonuc"
        return 0
    fi

    # 5. Onbellekte eski veri var mi?
    local eski_dosya="${_OHLCV_ONBELLEK_DIZIN}/${sembol}_${periyot}_${limit}.csv"
    if [[ -f "$eski_dosya" ]]; then
        _cekirdek_log "UYARI: mum_al — $sembol/$periyot eski onbellek kullaniliyor"
        cat "$eski_dosya"
        return 0
    fi

    _cekirdek_log "HATA: mum_al — $sembol/$periyot icin veri alinamadi"
    return 1
}

# -------------------------------------------------------
# _ohlcv_supabase_kaydet <sembol> <periyot> <csv_veri>
# tvDatafeed'den gelen CSV verisini Supabase'e yazar.
# Arka planda calistirilir (& ile).
# -------------------------------------------------------
_ohlcv_supabase_kaydet() {
    local sembol="$1"
    local periyot="$2"
    local csv_veri="$3"

    # vt_ohlcv_yaz fonksiyonu tanimli mi?
    if ! declare -f vt_ohlcv_yaz > /dev/null 2>&1; then
        return 1
    fi

    # CSV satirlarini tek tek yaz
    local satir
    while IFS=',' read -r tarih acilis yuksek dusuk kapanis hacim; do
        [[ -z "$tarih" ]] && continue
        vt_ohlcv_yaz "$sembol" "$periyot" "$tarih" \
            "$acilis" "$yuksek" "$dusuk" "$kapanis" "$hacim" "tvdata" \
            2>/dev/null || true
    done <<< "$csv_veri"
}

# -------------------------------------------------------
# mum_son_fiyat <sembol>
# Son kapanis fiyatini doner.
# stdout: tek sayi (kapanis fiyati)
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
mum_son_fiyat() {
    local sembol="${1:-}"
    [[ -z "$sembol" ]] && return 1

    local sonuc
    sonuc=$(mum_al "$sembol" "1G" 1 2>/dev/null) || return 1

    # CSV'nin 5. sutunu kapanis fiyati
    echo "$sonuc" | head -1 | cut -d',' -f5
}

# -------------------------------------------------------
# mum_periyotlar
# Desteklenen periyotlarin listesini yazar.
# stdout: periyot listesi
# -------------------------------------------------------
mum_periyotlar() {
    echo "${_OHLCV_PERIYOTLAR[*]}"
}

# -------------------------------------------------------
# mum_durum <sembol> [periyot]
# Belirtilen sembol icin veri durumunu gosterir.
# -------------------------------------------------------
mum_durum() {
    local sembol="${1:-}"
    local periyot="${2:-1G}"

    [[ -z "$sembol" ]] && {
        echo "Kullanim: mum_durum <SEMBOL> [periyot]"
        return 1
    }

    sembol="${sembol^^}"

    echo "OHLCV Veri Durumu: $sembol / $periyot"
    echo "========================================="

    # Supabase kontrolu
    if declare -f vt_ohlcv_son_tarih > /dev/null 2>&1; then
        local son_tarih
        son_tarih=$(vt_ohlcv_son_tarih "$sembol" "$periyot" 2>/dev/null)
        if [[ -n "$son_tarih" ]]; then
            echo "  Supabase son mum:  $son_tarih"
        else
            echo "  Supabase:          veri yok"
        fi
    else
        echo "  Supabase:          baglanti yok"
    fi

    # Onbellek kontrolu
    local onbellek_dosya="${_OHLCV_ONBELLEK_DIZIN}/${sembol}_${periyot}_200.csv"
    if [[ -f "$onbellek_dosya" ]]; then
        local dosya_zamani
        dosya_zamani=$(stat -c %Y "$onbellek_dosya" 2>/dev/null)
        local simdi
        simdi=$(date +%s)
        local gecen=$(( simdi - dosya_zamani ))
        local satir_sayisi
        satir_sayisi=$(wc -l < "$onbellek_dosya" 2>/dev/null)
        echo "  Onbellek:          ${satir_sayisi} satir, ${gecen}sn once"
    else
        echo "  Onbellek:          yok"
    fi

    # tvDatafeed durumu
    if _tvdatafeed_hazir_mi 2>/dev/null; then
        echo "  tvDatafeed:        HAZIR"
    else
        echo "  tvDatafeed:        EKSIK"
    fi

    # Yahoo Finance durumu
    if [[ -n "${_YAHOO_PERIYOT_ESLE[$periyot]:-}" ]]; then
        echo "  Yahoo Finance:     MEVCUT (yedek)"
    else
        echo "  Yahoo Finance:     BU PERIYOT ICIN YOK"
    fi

    echo "========================================="
}

# -------------------------------------------------------
# ohlcv_ilk_dolum
# Tum BIST hisseleri icin toplu OHLCV dolumunu baslatir.
# -------------------------------------------------------
ohlcv_ilk_dolum() {
    _ohlcv_python_bul || {
        echo "HATA: Python bulunamadi"
        return 1
    }

    echo "OHLCV ilk dolum baslatiliyor..."
    echo "Bu islem 8-25 saat surebilir."
    echo "Kesilirse kaldigi yerden devam eder."
    echo ""

    local tarama_dizin
    tarama_dizin=$(dirname "$_TVDATAFEED_TOPLU")

    (cd "$tarama_dizin" && "$_OHLCV_PYTHON" "$_TVDATAFEED_TOPLU")
}

# -------------------------------------------------------
# ohlcv_sembol_guncelle
# KAP'tan BIST sembol listesini gunceller.
# -------------------------------------------------------
ohlcv_sembol_guncelle() {
    _ohlcv_python_bul || {
        echo "HATA: Python bulunamadi"
        return 1
    }

    "$_OHLCV_PYTHON" "$_BIST_SEMBOL_LISTESI"
}

# =======================================================
# BOLUM 5: TAKIP LISTESI YONETIMI
# =======================================================

_TAKIP_DIZIN="/tmp/borsa/_takip"
_TAKIP_DOSYASI="${_TAKIP_DIZIN}/takip.json"
_TAKIP_KAYNAKLAR="${_TAKIP_DIZIN}/kaynaklar.json"

# -------------------------------------------------------
# _takip_oku
# Takip dosyasini okur.
# stdout: JSON icerik
# -------------------------------------------------------
_takip_oku() {
    if [[ -f "$_TAKIP_DOSYASI" ]]; then
        cat "$_TAKIP_DOSYASI"
    else
        echo "{}"
    fi
}

# -------------------------------------------------------
# _takip_yaz <json_icerik>
# Takip dosyasini yazar.
# -------------------------------------------------------
_takip_yaz() {
    local icerik="$1"
    mkdir -p "$_TAKIP_DIZIN" 2>/dev/null
    echo "$icerik" > "$_TAKIP_DOSYASI"
}

# -------------------------------------------------------
# _kaynaklar_oku
# Kaynak takip dosyasini okur.
# stdout: JSON icerik
# -------------------------------------------------------
_kaynaklar_oku() {
    if [[ -f "$_TAKIP_KAYNAKLAR" ]]; then
        cat "$_TAKIP_KAYNAKLAR"
    else
        echo "{}"
    fi
}

# -------------------------------------------------------
# _kaynaklar_yaz <json_icerik>
# Kaynak takip dosyasini yazar.
# -------------------------------------------------------
_kaynaklar_yaz() {
    local icerik="$1"
    mkdir -p "$_TAKIP_DIZIN" 2>/dev/null
    echo "$icerik" > "$_TAKIP_KAYNAKLAR"
}

# -------------------------------------------------------
# takip_ekle <sembol> <periyot1> [periyot2] ...
# Hisseyi takip listesine ekler.
# Kaynak: "kullanici" (manuel cagri)
# -------------------------------------------------------
takip_ekle() {
    local sembol="${1:-}"
    shift
    local periyotlar=("$@")

    if [[ -z "$sembol" ]]; then
        echo "Kullanim: takip_ekle <SEMBOL> <periyot1> [periyot2] ..."
        echo "Ornek:    takip_ekle THYAO 1dk 5dk 15dk 1S 1G"
        return 1
    fi

    sembol="${sembol^^}"

    # Periyot yoksa varsayilan: 1G
    if [[ ${#periyotlar[@]} -eq 0 ]]; then
        periyotlar=("1G")
    fi

    # Periyot dogrulama
    local p gecerli_periyotlar=()
    for p in "${periyotlar[@]}"; do
        local gecerli=0
        local pp
        for pp in "${_OHLCV_PERIYOTLAR[@]}"; do
            if [[ "$pp" == "$p" ]]; then
                gecerli=1
                break
            fi
        done
        if [[ "$gecerli" -eq 1 ]]; then
            gecerli_periyotlar+=("$p")
        else
            echo "UYARI: Gecersiz periyot atlanacak: $p"
        fi
    done

    if [[ ${#gecerli_periyotlar[@]} -eq 0 ]]; then
        echo "HATA: Gecerli periyot bulunamadi"
        return 1
    fi

    # jq ile JSON guncelle
    if command -v jq > /dev/null 2>&1; then
        local takip
        takip=$(_takip_oku)

        # Mevcut periyotlarla birlestir
        local periyot_json
        periyot_json=$(printf '%s\n' "${gecerli_periyotlar[@]}" | jq -R . | jq -s .)

        local mevcut_periyotlar
        mevcut_periyotlar=$(echo "$takip" | jq -r ".\"${sembol}\" // []" 2>/dev/null)

        local yeni_periyotlar
        yeni_periyotlar=$(echo "$mevcut_periyotlar" "$periyot_json" | jq -s 'add | unique')

        takip=$(echo "$takip" | jq ".\"${sembol}\" = ${yeni_periyotlar}")
        _takip_yaz "$takip"

        # Kaynak guncelle
        local kaynaklar
        kaynaklar=$(_kaynaklar_oku)
        local mevcut_kaynaklar
        mevcut_kaynaklar=$(echo "$kaynaklar" | jq -r ".\"${sembol}\" // []" 2>/dev/null)
        local yeni_kaynaklar
        yeni_kaynaklar=$(echo "$mevcut_kaynaklar" '["kullanici"]' | jq -s 'add | unique')
        kaynaklar=$(echo "$kaynaklar" | jq ".\"${sembol}\" = ${yeni_kaynaklar}")
        _kaynaklar_yaz "$kaynaklar"

        echo "${sembol} takip listesine eklendi: ${gecerli_periyotlar[*]}"
    else
        # jq yoksa basit dosya yonetimi
        mkdir -p "$_TAKIP_DIZIN" 2>/dev/null
        echo "${sembol}:${gecerli_periyotlar[*]}" >> "${_TAKIP_DIZIN}/takip.txt"
        echo "${sembol} takip listesine eklendi (basit mod): ${gecerli_periyotlar[*]}"
    fi

    return 0
}

# -------------------------------------------------------
# takip_cikar <sembol>
# Hisseyi takip listesinden cikarir.
# Sadece "kullanici" kaynagini cikarir. Robot kaynaklari
# kalirsa hisse takipte kalmaya devam eder.
# -------------------------------------------------------
takip_cikar() {
    local sembol="${1:-}"

    if [[ -z "$sembol" ]]; then
        echo "Kullanim: takip_cikar <SEMBOL>"
        return 1
    fi

    sembol="${sembol^^}"

    if ! command -v jq > /dev/null 2>&1; then
        # Basit mod: takip.txt'den sembolu cikar
        local txt_dosya="${_TAKIP_DIZIN:-/tmp/borsa/_takip}/takip.txt"
        if [[ -f "$txt_dosya" ]]; then
            local gecici
            gecici=$(grep -v "^${sembol}:" "$txt_dosya" 2>/dev/null)
            echo "$gecici" > "$txt_dosya"
            echo "${sembol} takip listesinden cikarildi (basit mod)"
        else
            echo "UYARI: Takip listesi bos"
        fi
        return 0
    fi

    # Kullanici kaynagini cikar
    local kaynaklar
    kaynaklar=$(_kaynaklar_oku)
    local mevcut_kaynaklar
    mevcut_kaynaklar=$(echo "$kaynaklar" | jq -r ".\"${sembol}\" // []" 2>/dev/null)
    local kalan_kaynaklar
    kalan_kaynaklar=$(echo "$mevcut_kaynaklar" | jq 'map(select(. != "kullanici"))')

    local kalan_sayisi
    kalan_sayisi=$(echo "$kalan_kaynaklar" | jq 'length')

    if [[ "$kalan_sayisi" -gt 0 ]]; then
        # Baska kaynaklar (robot vb) hala bu hisseyi takip ediyor
        kaynaklar=$(echo "$kaynaklar" | jq ".\"${sembol}\" = ${kalan_kaynaklar}")
        _kaynaklar_yaz "$kaynaklar"
        echo "${sembol} kullanici takibinden cikarildi ama robot hala takip ediyor"
        return 0
    fi

    # Hicbir kaynak kalmadi — tamamen cikar
    local takip
    takip=$(_takip_oku)
    takip=$(echo "$takip" | jq "del(.\"${sembol}\")")
    _takip_yaz "$takip"

    kaynaklar=$(echo "$kaynaklar" | jq "del(.\"${sembol}\")")
    _kaynaklar_yaz "$kaynaklar"

    echo "${sembol} takip listesinden cikarildi"
    return 0
}

# -------------------------------------------------------
# takip_liste
# Takip listesini gosterir.
# -------------------------------------------------------
takip_liste() {
    if ! command -v jq > /dev/null 2>&1; then
        if [[ -f "${_TAKIP_DIZIN}/takip.txt" ]]; then
            cat "${_TAKIP_DIZIN}/takip.txt"
        else
            echo "Takip listesi bos"
        fi
        return 0
    fi

    local takip
    takip=$(_takip_oku)

    local sembol_sayisi
    sembol_sayisi=$(echo "$takip" | jq 'keys | length' 2>/dev/null)

    if [[ "${sembol_sayisi:-0}" -eq 0 ]]; then
        echo "Takip listesi bos"
        echo "Eklemek icin: takip_ekle THYAO 1dk 5dk 1G"
        return 0
    fi

    echo "TAKIP LISTESI ($sembol_sayisi hisse)"
    echo "========================================="

    local kaynaklar
    kaynaklar=$(_kaynaklar_oku)

    echo "$takip" | jq -r 'to_entries[] | .key + " " + (.value | join(" "))' \
    | while IFS=' ' read -r sembol periyotlar_str; do
        local sem_kaynaklar
        sem_kaynaklar=$(echo "$kaynaklar" \
            | jq -r ".\"${sembol}\" // [] | join(\",\")" 2>/dev/null)
        printf "  %-8s %-30s [%s]\n" "$sembol" "$periyotlar_str" "$sem_kaynaklar"
    done

    echo "========================================="
}

# -------------------------------------------------------
# _takip_robot_ekle <sembol> <strateji_adi> <periyot1> ...
# Robot motoru tarafindan cagrilir.
# -------------------------------------------------------
_takip_robot_ekle() {
    local sembol="${1:-}"
    local strateji="${2:-}"
    shift 2
    local periyotlar=("$@")

    [[ -z "$sembol" ]] || [[ -z "$strateji" ]] && return 1
    [[ ${#periyotlar[@]} -eq 0 ]] && return 1

    sembol="${sembol^^}"

    if ! command -v jq > /dev/null 2>&1; then
        return 1
    fi

    # Takip guncelle
    local takip
    takip=$(_takip_oku)
    local periyot_json
    periyot_json=$(printf '%s\n' "${periyotlar[@]}" | jq -R . | jq -s .)
    local mevcut
    mevcut=$(echo "$takip" | jq -r ".\"${sembol}\" // []" 2>/dev/null)
    local yeni
    yeni=$(echo "$mevcut" "$periyot_json" | jq -s 'add | unique')
    takip=$(echo "$takip" | jq ".\"${sembol}\" = ${yeni}")
    _takip_yaz "$takip"

    # Kaynak guncelle
    local kaynaklar
    kaynaklar=$(_kaynaklar_oku)
    local mevcut_k
    mevcut_k=$(echo "$kaynaklar" | jq -r ".\"${sembol}\" // []" 2>/dev/null)
    local yeni_k
    yeni_k=$(echo "$mevcut_k" "[\"${strateji}\"]" | jq -s 'add | unique')
    kaynaklar=$(echo "$kaynaklar" | jq ".\"${sembol}\" = ${yeni_k}")
    _kaynaklar_yaz "$kaynaklar"
}

# -------------------------------------------------------
# _takip_robot_cikar <sembol> <strateji_adi>
# Robot motoru tarafindan cagrilir.
# Strateji kaynagini cikarir. Hicbir kaynak yoksa
# hisseyi takipten tamamen duser.
# -------------------------------------------------------
_takip_robot_cikar() {
    local sembol="${1:-}"
    local strateji="${2:-}"

    [[ -z "$sembol" ]] || [[ -z "$strateji" ]] && return 1

    sembol="${sembol^^}"

    if ! command -v jq > /dev/null 2>&1; then
        return 1
    fi

    local kaynaklar
    kaynaklar=$(_kaynaklar_oku)
    local mevcut
    mevcut=$(echo "$kaynaklar" | jq -r ".\"${sembol}\" // []" 2>/dev/null)
    local kalan
    kalan=$(echo "$mevcut" | jq "map(select(. != \"${strateji}\"))")

    local kalan_sayisi
    kalan_sayisi=$(echo "$kalan" | jq 'length')

    if [[ "$kalan_sayisi" -gt 0 ]]; then
        kaynaklar=$(echo "$kaynaklar" | jq ".\"${sembol}\" = ${kalan}")
        _kaynaklar_yaz "$kaynaklar"
        return 0
    fi

    # Hicbir kaynak kalmadi — takipten cikar
    local takip
    takip=$(_takip_oku)
    takip=$(echo "$takip" | jq "del(.\"${sembol}\")")
    _takip_yaz "$takip"

    kaynaklar=$(echo "$kaynaklar" | jq "del(.\"${sembol}\")")
    _kaynaklar_yaz "$kaynaklar"
}

# -------------------------------------------------------
# _takip_semboller
# Takipteki sembol listesini doner (satirda bir sembol).
# stdout: sembol listesi
# -------------------------------------------------------
_takip_semboller() {
    if command -v jq > /dev/null 2>&1; then
        _takip_oku | jq -r 'keys[]' 2>/dev/null
    else
        # Basit mod: takip.txt'den sembol isimlerini oku
        local txt_dosya="${_TAKIP_DIZIN:-/tmp/borsa/_takip}/takip.txt"
        if [[ -f "$txt_dosya" ]]; then
            cut -d: -f1 "$txt_dosya" | sort -u
        fi
    fi
}

# =======================================================
# NOT: Eski Bolum 6 (Mum Birlestirici — WSS tick -> OHLCV) ve
# Seans Otomasyonu (canli_veri_baslat/durdur/durum/seans_bekle)
# tvDatafeed gecisi kapsaminda kaldirilmistir.
# Canli veri fonksiyonlari artik tarama/canli_veri.sh icerisindedir.
# =======================================================

# =======================================================
# BOLUM 7: GUNLUK TAMIR DONGUSU
# =======================================================

_TAMIR_LOG="/tmp/borsa/_ohlcv_ilk_dolum/tamir.log"

# -------------------------------------------------------
# ohlcv_tamir
# Eksik/hatali OHLCV mumlarini tamir eder.
# tvDatafeed ile eksik verileri doldurur.
# -------------------------------------------------------
ohlcv_tamir() {
    _ohlcv_python_bul || {
        echo "HATA: Python bulunamadi" >&2
        return 1
    }
    local python_yol="$_OHLCV_PYTHON"

    if [[ ! -f "$_TVDATAFEED_TOPLU" ]]; then
        echo "HATA: $_TVDATAFEED_TOPLU dosyasi bulunamadi" >&2
        return 1
    fi

    echo "OHLCV tamir dongusu baslatiliyor..."
    echo "Log: $_TAMIR_LOG"

    mkdir -p "$(dirname "$_TAMIR_LOG")"

    "$python_yol" "$_TVDATAFEED_TOPLU" --tamir 2>&1 | tee -a "$_TAMIR_LOG"
    local sonuc=$?

    if [[ $sonuc -eq 0 ]]; then
        echo "Tamir tamamlandi"
    else
        echo "HATA: Tamir basarisiz (kod: $sonuc)" >&2
    fi
    return $sonuc
}

# -------------------------------------------------------
# ohlcv_cron_kur
# Gunluk tamir icin crontab girisi ekler.
# Her is gunu 18:30'da (seans kapanisinin 20 dk sonrasi)
# -------------------------------------------------------
ohlcv_cron_kur() {
    _ohlcv_python_bul || {
        echo "HATA: Python bulunamadi" >&2
        return 1
    }
    local python_yol="$_OHLCV_PYTHON"

    local cron_komut="${python_yol} ${_TVDATAFEED_TOPLU} --tamir"
    local cron_satir="30 18 * * 1-5 ${cron_komut} >> ${_TAMIR_LOG} 2>&1"
    local cron_isaret="# borsa-ohlcv-tamir"

    # Zaten var mi kontrol et
    if crontab -l 2>/dev/null | grep -qF "$cron_isaret"; then
        echo "Cron gorevi zaten kurulu"
        crontab -l 2>/dev/null | grep -A1 "$cron_isaret"
        return 0
    fi

    # Crontab'a ekle
    local mevcut
    mevcut=$(crontab -l 2>/dev/null || true)

    {
        echo "$mevcut"
        echo ""
        echo "$cron_isaret"
        echo "$cron_satir"
    } | crontab -

    echo "Cron gorevi eklendi:"
    echo "  $cron_satir"
    echo "  Her is gunu 18:30'da calisiyor"
    return 0
}

# -------------------------------------------------------
# ohlcv_cron_kaldir
# Crontab'dan tamir gorevini cikarir.
# -------------------------------------------------------
ohlcv_cron_kaldir() {
    local cron_isaret="# borsa-ohlcv-tamir"

    if ! crontab -l 2>/dev/null | grep -qF "$cron_isaret"; then
        echo "Cron gorevi zaten yok"
        return 0
    fi

    crontab -l 2>/dev/null \
        | grep -v "$cron_isaret" \
        | grep -v "_tvdatafeed_toplu.py --tamir" \
        | crontab -

    echo "Cron gorevi kaldirildi"
    return 0
}

# -------------------------------------------------------
# ohlcv_cron_durum
# Cron gorevinin durumunu gosterir.
# -------------------------------------------------------
ohlcv_cron_durum() {
    local cron_isaret="# borsa-ohlcv-tamir"

    if crontab -l 2>/dev/null | grep -qF "$cron_isaret"; then
        echo "Cron gorevi: AKTIF"
        crontab -l 2>/dev/null | grep -A1 "$cron_isaret"
    else
        echo "Cron gorevi: PASIF"
        echo "Kurmak icin: ohlcv_cron_kur"
    fi

    # Son tamir log'u
    if [[ -f "$_TAMIR_LOG" ]]; then
        echo ""
        echo "Son tamir logu:"
        tail -5 "$_TAMIR_LOG"
    fi
    return 0
}

# =======================================================
# BOLUM 9: OTOMATIK ILK DOLUM KONTROLU
# =======================================================
# Shell yuklendiginde OHLCV tablosunun bos olup olmadigini kontrol eder.
# Bossa veya cok azsa kullaniciyi bilgilendirir ve arka planda
# ilk dolumu baslatir. Oturum basina bir kez calisir.

_OHLCV_ILK_DOLUM_KONTROL_YAPILDI=0

# -------------------------------------------------------
# _ohlcv_ilk_dolum_kontrol (dahili)
# Veritabaninda yeterli OHLCV verisi var mi kontrol eder.
# Yoksa arka planda ilk dolumu baslatir.
# Oturum basina bir kez calisir (bayrak degiskeni).
# -------------------------------------------------------
_ohlcv_ilk_dolum_kontrol() {
    # Oturum basina bir kez calistir
    [[ "$_OHLCV_ILK_DOLUM_KONTROL_YAPILDI" -eq 1 ]] && return 0
    _OHLCV_ILK_DOLUM_KONTROL_YAPILDI=1

    # Supabase ayarlari yoksa atla
    if [[ -z "${_SUPABASE_URL:-}" ]] || [[ -z "${_SUPABASE_ANAHTAR:-}" ]]; then
        return 0
    fi

    # API erisilebilir mi? (hizli kontrol, 2sn timeout)
    if ! curl -sf --max-time 2 \
        -H "apikey: $_SUPABASE_ANAHTAR" \
        "${_SUPABASE_URL}/rest/v1/" > /dev/null 2>&1; then
        return 0
    fi

    # OHLCV satir sayisini al
    local content_range
    content_range=$(curl -sI --max-time 5 \
        "${_SUPABASE_URL}/rest/v1/ohlcv?select=*&limit=0" \
        -H "apikey: $_SUPABASE_ANAHTAR" \
        -H "Authorization: Bearer $_SUPABASE_ANAHTAR" \
        -H "Prefer: count=exact" 2>/dev/null \
        | grep -i 'content-range' \
        | sed 's/.*\///' \
        | tr -d '\r\n ')

    local satir_sayisi="${content_range:-0}"

    # Sayisal degil ise atla
    if ! [[ "$satir_sayisi" =~ ^[0-9]+$ ]]; then
        return 0
    fi

    # 100.000'den fazla satir varsa yeterli say — atla
    if [[ "$satir_sayisi" -ge 100000 ]]; then
        return 0
    fi

    # Zaten arka planda dolum calisiyor mu?
    if pgrep -f "_tvdatafeed_toplu" > /dev/null 2>&1; then
        _cekirdek_log "OHLCV ilk dolum zaten arka planda calisiyor."
        return 0
    fi

    # Ilk dolum gerekli — kullaniciyi bilgilendir ve arka planda baslat
    if [[ "$satir_sayisi" -eq 0 ]]; then
        echo ""
        echo "[OHLCV] Veritabani bos — ilk dolum arka planda baslatiliyor..."
        echo "[OHLCV] 723 sembol x 13 periyot. Bu islem 8-25 saat surebilir."
    else
        echo ""
        echo "[OHLCV] Veritabaninda $satir_sayisi satir var (eksik)."
        echo "[OHLCV] Ilk dolum kaldigi yerden arka planda devam ediyor..."
    fi

    # Python kontrol
    _ohlcv_python_bul || {
        echo "[OHLCV] UYARI: Python bulunamadi — ilk dolum baslatilamadi."
        echo "[OHLCV] Elle baslatmak icin: ohlcv_ilk_dolum"
        return 1
    }

    if [[ ! -f "$_TVDATAFEED_TOPLU" ]]; then
        echo "[OHLCV] UYARI: $_TVDATAFEED_TOPLU bulunamadi."
        return 1
    fi

    # Arka planda baslat (nohup ile — terminal kapansa da devam eder)
    local tarama_dizin
    tarama_dizin=$(dirname "$_TVDATAFEED_TOPLU")
    local log_dosyasi="/tmp/borsa/_ohlcv_ilk_dolum/otomatik_dolum.log"
    mkdir -p "/tmp/borsa/_ohlcv_ilk_dolum" 2>/dev/null

    (cd "$tarama_dizin" && nohup "$_OHLCV_PYTHON" "$_TVDATAFEED_TOPLU" \
        >> "$log_dosyasi" 2>&1 &)

    echo "[OHLCV] Log: $log_dosyasi"
    echo "[OHLCV] Durum: ohlcv_ilk_dolum_durum | Durdur: pkill -f _tvdatafeed_toplu"
    echo ""
    return 0
}

# -------------------------------------------------------
# ohlcv_ilk_dolum_durum
# Ilk dolumun ilerlemesini gosterir.
# -------------------------------------------------------
ohlcv_ilk_dolum_durum() {
    local ilerleme_dosyasi="/tmp/borsa/_ohlcv_ilk_dolum/ilerleme.json"

    if ! pgrep -f "_tvdatafeed_toplu" > /dev/null 2>&1; then
        echo "Ilk dolum calismiyir."
        if [[ -f "$ilerleme_dosyasi" ]]; then
            echo "(Son ilerleme dosyasi mevcut)"
        fi
    else
        echo "Ilk dolum CALISIYOR"
        local pid_listesi
        pid_listesi=$(pgrep -f "_tvdatafeed_toplu" | tr '\n' ',' | sed 's/,$//')
        echo "PID: $pid_listesi"
    fi

    if [[ ! -f "$ilerleme_dosyasi" ]]; then
        echo "Ilerleme dosyasi bulunamadi."
        return 0
    fi

    # Python ile ilerleme ozeti
    _ohlcv_python_bul || return 0

    "$_OHLCV_PYTHON" -c "
import json, sys
try:
    with open('$ilerleme_dosyasi') as f:
        d = json.load(f)
    o = d.get('_ozet', {})
    toplam = o.get('toplam', 0)
    tamam = o.get('tamam', 0)
    hata = o.get('hata', 0)
    if toplam == 0:
        print('Ilerleme bilgisi yok.')
        sys.exit(0)
    kalan = toplam - tamam - hata
    oran = 100 * tamam / toplam
    print(f'Toplam:     {toplam}')
    print(f'Tamamlanan: {tamam} (%{oran:.1f})')
    print(f'Hata:       {hata}')
    print(f'Kalan:      {kalan}')
except Exception as e:
    print(f'Ilerleme okunamadi: {e}')
" 2>/dev/null

    return 0
}

# Shell yuklendiginde otomatik kontrol et
_ohlcv_ilk_dolum_kontrol
