# shellcheck shell=bash

# Veritabani Katmani (Supabase)
# Tum vt_* fonksiyonlarini icerir. Hicbir katman dogrudan
# Supabase'e curl atmaz — bu dosyadaki fonksiyonlar kullanilir.
#
# Hata toleransi: DB yazimi basarisiz olursa islem engellenmez.
# Basarisiz kayitlar /tmp/borsa/_vt_yedek/bekleyen.jsonl'e yazilir.
#
# Yuklenme: cekirdek.sh tarafindan source edilir (kosullu).

# =======================================================
# Ayarlari yukle
# =======================================================
_VT_AYARLAR_DOSYASI="${BORSA_KLASORU}/veritabani/supabase.ayarlar.sh"
_VT_YEDEK_DIZIN="/tmp/borsa/_vt_yedek"

if [[ -f "$_VT_AYARLAR_DOSYASI" ]]; then
    # shellcheck source=/dev/null
    source "$_VT_AYARLAR_DOSYASI"
else
    _SUPABASE_URL=""
    _SUPABASE_ANAHTAR=""
fi

# =======================================================
# BOLUM 1: ALTYAPI FONKSIYONLARI
# =======================================================

# -------------------------------------------------------
# vt_baglanti_kontrol
# Supabase erisimini test eder.
# Donus: 0 = erisim var, 1 = erisim yok
# -------------------------------------------------------
vt_baglanti_kontrol() {
    if [[ -z "$_SUPABASE_URL" ]] || [[ -z "$_SUPABASE_ANAHTAR" ]]; then
        return 1
    fi

    if curl -sf \
        -H "apikey: $_SUPABASE_ANAHTAR" \
        "${_SUPABASE_URL}/rest/v1/" > /dev/null 2>&1; then
        return 0
    fi

    _cekirdek_log "UYARI: Supabase erisilemedi (${_SUPABASE_URL})."
    _cekirdek_log "Baslatmak icin: cd ${BORSA_KLASORU}/veritabani && docker compose up -d"
    return 1
}

# -------------------------------------------------------
# vt_istek_at <metod> <tablo> <veri_veya_sorgu> [ek_basliklar...]
# Supabase'e HTTP istegi atar.
# metod: GET, POST, PATCH
# tablo: emirler, bakiye_gecmisi vb veya tam yol (sorgu parametreleriyle)
# veri_veya_sorgu: POST/PATCH icin JSON govde, GET icin bos
# stdout: yanit gövdesi
# Donus: 0 = basarili (2xx), 1 = basarisiz
# -------------------------------------------------------
vt_istek_at() {
    local metod="$1"
    local tablo="$2"
    local veri="${3:-}"
    shift 3 2>/dev/null
    local ek_basliklar=("$@")

    if [[ -z "$_SUPABASE_URL" ]] || [[ -z "$_SUPABASE_ANAHTAR" ]]; then
        return 1
    fi

    local url
    # Tam URL mi yoksa sadece tablo adi mi?
    if [[ "$tablo" == /* ]]; then
        url="${_SUPABASE_URL}${tablo}"
    else
        url="${_SUPABASE_URL}/rest/v1/${tablo}"
    fi

    local curl_args=(
        -s
        -w "\n%{http_code}"
        -H "apikey: $_SUPABASE_ANAHTAR"
        -H "Authorization: Bearer $_SUPABASE_ANAHTAR"
        -H "Content-Type: application/json"
        -H "Prefer: return=minimal"
        -X "$metod"
    )

    # Ek basliklar
    local baslik
    for baslik in "${ek_basliklar[@]}"; do
        curl_args+=(-H "$baslik")
    done

    # Veri gövdesi
    if [[ -n "$veri" ]] && [[ "$metod" != "GET" ]]; then
        curl_args+=(-d "$veri")
    fi

    curl_args+=("$url")

    local yanit
    yanit=$(curl "${curl_args[@]}" 2>/dev/null) || return 1

    # Son satir HTTP kodu
    local http_kodu
    http_kodu=$(echo "$yanit" | tail -n 1)
    local govde
    govde=$(echo "$yanit" | sed '$d')

    # 2xx basari
    if [[ "$http_kodu" =~ ^2[0-9]{2}$ ]]; then
        [[ -n "$govde" ]] && echo "$govde"
        return 0
    fi

    _cekirdek_log "UYARI: vt_istek_at basarisiz — $metod $tablo HTTP $http_kodu"
    [[ -n "$govde" ]] && _cekirdek_log "  Yanit: $govde"
    return 1
}

# -------------------------------------------------------
# _vt_json_olustur <anahtar1> <deger1> <anahtar2> <deger2> ...
# Bash degiskenlerinden JSON string olusturur.
# Bos degerler atlanir. jq mevcutsa onu kullanir, yoksa elle olusturur.
# stdout: JSON string
# -------------------------------------------------------
_vt_json_olustur() {
    local json="{"
    local ilk=1

    while [[ $# -ge 2 ]]; do
        local anahtar="$1"
        local deger="$2"
        shift 2

        [[ -z "$deger" ]] && continue

        if [[ "$ilk" -eq 0 ]]; then
            json+=","
        fi
        ilk=0

        # Sayi mi yoksa metin mi?
        if [[ "$deger" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
            json+="\"${anahtar}\":${deger}"
        elif [[ "$deger" == "true" ]] || [[ "$deger" == "false" ]] || [[ "$deger" == "null" ]]; then
            json+="\"${anahtar}\":${deger}"
        else
            # Ozel karakterleri escape et
            deger="${deger//\\/\\\\}"
            deger="${deger//\"/\\\"}"
            json+="\"${anahtar}\":\"${deger}\""
        fi
    done

    json+="}"
    echo "$json"
}

# -------------------------------------------------------
# _vt_yedege_yaz <tablo> <json_veri>
# DB yazimi basarisiz olursa yerel dosyaya yedek yazar.
# Sonra _vt_bekleyenleri_gonder ile yeniden denenir.
# -------------------------------------------------------
_vt_yedege_yaz() {
    local tablo="$1"
    local json_veri="$2"

    mkdir -p "$_VT_YEDEK_DIZIN" 2>/dev/null

    local zaman
    zaman=$(date '+%Y-%m-%dT%H:%M:%S%z')
    echo "{\"zaman\":\"${zaman}\",\"tablo\":\"${tablo}\",\"veri\":${json_veri}}" \
        >> "${_VT_YEDEK_DIZIN}/bekleyen.jsonl"

    _cekirdek_log "UYARI: DB kaydedilemedi, yedege yazildi — $tablo"
}

# =======================================================
# BOLUM 2: YAZMA FONKSIYONLARI
# =======================================================

# -------------------------------------------------------
# vt_emir_kaydet <kurum> <hesap> <sembol> <yon> <lot> <fiyat>
#                <referans_no> <basarili> [strateji] [robot_pid]
# Emri emirler tablosuna yazar.
# Tetik: adaptor_emir_gonder sonrasi
# -------------------------------------------------------
vt_emir_kaydet() {
    local kurum="$1"
    local hesap="$2"
    local sembol="$3"
    local yon="$4"
    local lot="$5"
    local fiyat="$6"
    local referans_no="$7"
    local basarili="$8"
    local strateji="${9:-}"
    local robot_pid="${10:-}"

    local durum="GONDERILDI"
    local piyasa_mi="false"
    local hata_mesaji=""

    if [[ "$basarili" != "1" ]]; then
        durum="REDDEDILDI"
        hata_mesaji="Emir reddedildi"
    fi

    if [[ -z "$fiyat" ]] || [[ "$fiyat" == "0" ]]; then
        piyasa_mi="true"
    fi

    local json
    json=$(_vt_json_olustur \
        "kurum" "$kurum" \
        "hesap" "$hesap" \
        "sembol" "$sembol" \
        "yon" "$yon" \
        "lot" "$lot" \
        "fiyat" "$fiyat" \
        "piyasa_mi" "$piyasa_mi" \
        "referans_no" "$referans_no" \
        "durum" "$durum" \
        "strateji" "$strateji" \
        "robot_pid" "$robot_pid" \
        "hata_mesaji" "$hata_mesaji"
    )

    if vt_istek_at "POST" "emirler" "$json"; then
        _cekirdek_log "DB: Emir kaydedildi — $sembol $yon $lot lot"
    else
        _vt_yedege_yaz "emirler" "$json"
    fi
}

# -------------------------------------------------------
# vt_emir_durum_guncelle <referans_no> <yeni_durum>
# Emir durumunu gunceller.
# Tetik: adaptor_emirleri_listele sonrasi
# -------------------------------------------------------
vt_emir_durum_guncelle() {
    local referans_no="$1"
    local yeni_durum="$2"

    [[ -z "$referans_no" ]] && return 0

    local durum_buyuk
    durum_buyuk=$(echo "$yeni_durum" | tr '[:lower:]' '[:upper:]')

    # Turkce durum eslestirme
    case "$durum_buyuk" in
        *GERCEK*|*TAMAMLA*) durum_buyuk="GERCEKLESTI" ;;
        *IPTAL*)            durum_buyuk="IPTAL" ;;
        *KISMI*)            durum_buyuk="KISMI" ;;
        *BEKLE*|*ILETIL*)   durum_buyuk="GONDERILDI" ;;
        *REDDED*)           durum_buyuk="REDDEDILDI" ;;
    esac

    local zaman
    zaman=$(date '+%Y-%m-%dT%H:%M:%S%z')

    local json
    json=$(_vt_json_olustur \
        "durum" "$durum_buyuk" \
        "guncelleme_zamani" "$zaman"
    )

    vt_istek_at "PATCH" "emirler?referans_no=eq.${referans_no}" "$json" 2>/dev/null
}

# -------------------------------------------------------
# vt_bakiye_kaydet <kurum> <hesap> <nakit> <hisse> <toplam>
# Bakiye anligini kaydeder.
# Tetik: adaptor_bakiye sonrasi
# -------------------------------------------------------
vt_bakiye_kaydet() {
    local kurum="$1"
    local hesap="$2"
    local nakit="$3"
    local hisse="$4"
    local toplam="$5"

    # Virgulleri kaldir (57,320.50 -> 57320.50)
    nakit="${nakit//,/}"
    hisse="${hisse//,/}"
    toplam="${toplam//,/}"

    local json
    json=$(_vt_json_olustur \
        "kurum" "$kurum" \
        "hesap" "$hesap" \
        "nakit" "$nakit" \
        "hisse_degeri" "$hisse" \
        "toplam" "$toplam"
    )

    if vt_istek_at "POST" "bakiye_gecmisi" "$json"; then
        _cekirdek_log "DB: Bakiye kaydedildi — $kurum/$hesap"
    else
        _vt_yedege_yaz "bakiye_gecmisi" "$json"
    fi
}

# -------------------------------------------------------
# vt_pozisyon_kaydet <kurum> <hesap> <sembol> <lot> <maliyet>
#                    <fiyat> <deger> <kar_zarar> <kar_yuzde>
# Bir hissenin anlik pozisyonunu kaydeder.
# Tetik: adaptor_portfoy sonrasi (her sembol icin)
# -------------------------------------------------------
vt_pozisyon_kaydet() {
    local kurum="$1"
    local hesap="$2"
    local sembol="$3"
    local lot="$4"
    local maliyet="$5"
    local fiyat="$6"
    local deger="$7"
    local kar_zarar="$8"
    local kar_yuzde="$9"

    # Virgulleri temizle
    lot="${lot//,/}"
    maliyet="${maliyet//,/}"
    fiyat="${fiyat//,/}"
    deger="${deger//,/}"
    kar_zarar="${kar_zarar//,/}"
    kar_yuzde="${kar_yuzde//,/}"

    local json
    json=$(_vt_json_olustur \
        "kurum" "$kurum" \
        "hesap" "$hesap" \
        "sembol" "$sembol" \
        "lot" "$lot" \
        "ortalama_maliyet" "$maliyet" \
        "piyasa_fiyati" "$fiyat" \
        "piyasa_degeri" "$deger" \
        "kar_zarar" "$kar_zarar" \
        "kar_zarar_yuzde" "$kar_yuzde"
    )

    if vt_istek_at "POST" "pozisyonlar" "$json" "Prefer: return=minimal,resolution=ignore-duplicates"; then
        _cekirdek_log "DB: Pozisyon kaydedildi — $sembol $lot lot"
    else
        _vt_yedege_yaz "pozisyonlar" "$json"
    fi
}

# -------------------------------------------------------
# vt_halka_arz_kaydet <kurum> <hesap> <islem_tipi> <basarili>
#                     [ipo_adi] [ipo_id] [lot] [fiyat] [mesaj]
# Halka arz islemini kaydeder.
# Tetik: halka arz talep/iptal/guncelle sonrasi
# -------------------------------------------------------
vt_halka_arz_kaydet() {
    local kurum="$1"
    local hesap="$2"
    local islem_tipi="$3"
    local basarili="$4"
    local ipo_adi="${5:-}"
    local ipo_id="${6:-}"
    local lot="${7:-}"
    local fiyat="${8:-}"
    local mesaj="${9:-}"

    local basarili_bool="false"
    [[ "$basarili" == "1" ]] && basarili_bool="true"

    local json
    json=$(_vt_json_olustur \
        "kurum" "$kurum" \
        "hesap" "$hesap" \
        "islem_tipi" "$islem_tipi" \
        "basarili" "$basarili_bool" \
        "ipo_adi" "$ipo_adi" \
        "ipo_id" "$ipo_id" \
        "lot" "$lot" \
        "fiyat" "$fiyat" \
        "mesaj" "$mesaj"
    )

    if vt_istek_at "POST" "halka_arz_islemleri" "$json"; then
        _cekirdek_log "DB: Halka arz kaydedildi — $islem_tipi $ipo_adi"
    else
        _vt_yedege_yaz "halka_arz_islemleri" "$json"
    fi
}

# -------------------------------------------------------
# vt_robot_log_yaz <kurum> <hesap> <robot_pid> <strateji>
#                  <olay> [detay_json]
# Robot olayini loglar.
# -------------------------------------------------------
vt_robot_log_yaz() {
    local kurum="$1"
    local hesap="$2"
    local robot_pid="$3"
    local strateji="$4"
    local olay="$5"
    local detay="${6:-}"

    local json
    if [[ -n "$detay" ]] && [[ "$detay" == "{"* ]]; then
        # Detay zaten JSON formatinda
        json="{\"kurum\":\"${kurum}\",\"hesap\":\"${hesap}\",\"robot_pid\":${robot_pid},\"strateji\":\"${strateji}\",\"olay\":\"${olay}\",\"detay\":${detay}}"
    else
        json=$(_vt_json_olustur \
            "kurum" "$kurum" \
            "hesap" "$hesap" \
            "robot_pid" "$robot_pid" \
            "strateji" "$strateji" \
            "olay" "$olay"
        )
    fi

    vt_istek_at "POST" "robot_log" "$json" 2>/dev/null
}

# -------------------------------------------------------
# vt_oturum_log_yaz <kurum> <hesap> <olay> [detay]
# Oturum olayini loglar.
# -------------------------------------------------------
vt_oturum_log_yaz() {
    local kurum="$1"
    local hesap="$2"
    local olay="$3"
    local detay="${4:-}"

    local json
    json=$(_vt_json_olustur \
        "kurum" "$kurum" \
        "hesap" "$hesap" \
        "olay" "$olay" \
        "detay" "$detay"
    )

    vt_istek_at "POST" "oturum_log" "$json" 2>/dev/null
}

# -------------------------------------------------------
# vt_fiyat_kaydet <sembol> <fiyat> <tavan> <taban> <degisim>
#                 <hacim> <seans_durumu> <kurum> <hesap>
# Fiyat verisini kaydeder.
# Tetik: veri_kaynagi_fiyat_al taze cekim aninda
# -------------------------------------------------------
vt_fiyat_kaydet() {
    local sembol="$1"
    local fiyat="$2"
    local tavan="${3:-}"
    local taban="${4:-}"
    local degisim="${5:-}"
    local hacim="${6:-}"
    local seans_durumu="${7:-}"
    local kurum="${8:-}"
    local hesap="${9:-}"

    local json
    json=$(_vt_json_olustur \
        "sembol" "$sembol" \
        "fiyat" "$fiyat" \
        "tavan" "$tavan" \
        "taban" "$taban" \
        "degisim" "$degisim" \
        "hacim" "$hacim" \
        "seans_durumu" "$seans_durumu" \
        "kaynak_kurum" "$kurum" \
        "kaynak_hesap" "$hesap"
    )

    vt_istek_at "POST" "fiyat_gecmisi" "$json" 2>/dev/null
}

# =======================================================
# BOLUM 3: OKUMA FONKSIYONLARI
# =======================================================

# -------------------------------------------------------
# vt_emir_gecmisi <kurum> <hesap> [limit]
# Emir gecmisini getirir.
# stdout: JSON dizi
# -------------------------------------------------------
vt_emir_gecmisi() {
    local kurum="$1"
    local hesap="$2"
    local limit="${3:-20}"

    local sorgu="emirler?kurum=eq.${kurum}&hesap=eq.${hesap}&order=olusturma_zamani.desc&limit=${limit}"

    local yanit
    yanit=$(vt_istek_at "GET" "$sorgu" "" "Prefer: return=representation")

    if [[ -z "$yanit" ]]; then
        echo "Emir gecmisi bulunamadi."
        return 1
    fi

    # Tablo formatinda goster
    echo ""
    echo "========================================================================="
    echo "  EMIR GECMISI ($kurum/$hesap — Son $limit)"
    echo "========================================================================="
    printf " %-8s %-6s %8s %10s %-12s %-12s\n" \
        "Sembol" "Yon" "Lot" "Fiyat" "Durum" "Zaman"
    echo "-------------------------------------------------------------------------"

    if command -v jq > /dev/null 2>&1; then
        echo "$yanit" | jq -r '.[] | "\(.sembol)\t\(.yon)\t\(.lot)\t\(.fiyat // "-")\t\(.durum)\t\(.olusturma_zamani)"' 2>/dev/null | \
        while IFS=$'\t' read -r sembol yon lot fiyat durum zaman; do
            local kisa_zaman
            kisa_zaman="${zaman:0:16}"
            printf " %-8s %-6s %8s %10s %-12s %-12s\n" \
                "$sembol" "$yon" "$lot" "$fiyat" "$durum" "$kisa_zaman"
        done
    else
        echo "$yanit"
    fi

    echo "========================================================================="
    echo ""
}

# -------------------------------------------------------
# vt_bakiye_gecmisi <kurum> <hesap> [limit]
# Bakiye zaman serisini getirir.
# -------------------------------------------------------
vt_bakiye_gecmisi() {
    local kurum="$1"
    local hesap="$2"
    local limit="${3:-30}"

    local sorgu="bakiye_gecmisi?kurum=eq.${kurum}&hesap=eq.${hesap}&order=zaman.desc&limit=${limit}"

    local yanit
    yanit=$(vt_istek_at "GET" "$sorgu" "" "Prefer: return=representation")

    if [[ -z "$yanit" ]]; then
        echo "Bakiye gecmisi bulunamadi."
        return 1
    fi

    echo ""
    echo "========================================================================="
    echo "  BAKIYE GECMISI ($kurum/$hesap — Son $limit)"
    echo "========================================================================="
    printf " %-20s %14s %14s %14s\n" "Zaman" "Nakit" "Hisse" "Toplam"
    echo "-------------------------------------------------------------------------"

    if command -v jq > /dev/null 2>&1; then
        while IFS=$'\t' read -r zaman nakit hisse toplam; do
            local kisa_zaman
            kisa_zaman="${zaman:0:16}"
            printf " %-20s %14s %14s %14s\n" "$kisa_zaman" "$nakit" "$hisse" "$toplam"
        done < <(echo "$yanit" | jq -r '.[] | "\(.zaman)\t\(.nakit)\t\(.hisse_degeri)\t\(.toplam)"' 2>/dev/null)
    else
        echo "$yanit"
    fi

    echo "========================================================================="
    echo ""
}

# -------------------------------------------------------
# vt_pozisyon_gecmisi <kurum> <hesap> <sembol> [limit]
# Belirli sembolun pozisyon degisimlerini getirir.
# -------------------------------------------------------
vt_pozisyon_gecmisi() {
    local kurum="$1"
    local hesap="$2"
    local sembol="$3"
    local limit="${4:-30}"

    local sorgu="pozisyonlar?kurum=eq.${kurum}&hesap=eq.${hesap}&sembol=eq.${sembol}&order=zaman.desc&limit=${limit}"

    local yanit
    yanit=$(vt_istek_at "GET" "$sorgu" "" "Prefer: return=representation")

    if [[ -z "$yanit" ]]; then
        echo "Pozisyon gecmisi bulunamadi."
        return 1
    fi

    echo ""
    echo "========================================================================="
    echo "  POZISYON GECMISI ($sembol — $kurum/$hesap)"
    echo "========================================================================="
    printf " %-16s %8s %10s %12s %12s %8s\n" \
        "Zaman" "Lot" "Fiyat" "Deger" "K/Z" "K/Z %"
    echo "-------------------------------------------------------------------------"

    if command -v jq > /dev/null 2>&1; then
        echo "$yanit" | jq -r '.[] | "\(.zaman)\t\(.lot)\t\(.piyasa_fiyati // "-")\t\(.piyasa_degeri // "-")\t\(.kar_zarar // "-")\t\(.kar_zarar_yuzde // "-")"' 2>/dev/null | \
        while IFS=$'\t' read -r zaman lot fiyat deger kz kzy; do
            local kisa_zaman
            kisa_zaman="${zaman:0:16}"
            printf " %-16s %8s %10s %12s %12s %8s\n" \
                "$kisa_zaman" "$lot" "$fiyat" "$deger" "$kz" "$kzy"
        done
    else
        echo "$yanit"
    fi

    echo "========================================================================="
    echo ""
}

# -------------------------------------------------------
# vt_gun_sonu_rapor [kurum] [hesap]
# Gunun tum islemlerini ozetler.
# -------------------------------------------------------
vt_gun_sonu_rapor() {
    local kurum="${1:-}"
    local hesap="${2:-}"

    local filtre=""
    [[ -n "$kurum" ]] && filtre="&kurum=eq.${kurum}"
    [[ -n "$hesap" ]] && filtre="${filtre}&hesap=eq.${hesap}"

    local bugun
    bugun=$(date '+%Y-%m-%d')

    echo ""
    echo "========================================================================="
    echo "  GUN SONU RAPORU — $bugun"
    echo "========================================================================="

    # Bugunun emirleri
    local emir_yanit
    emir_yanit=$(vt_istek_at "GET" "emirler?olusturma_zamani=gte.${bugun}T00:00:00${filtre}&order=olusturma_zamani.desc" "" "Prefer: return=representation")

    if [[ -n "$emir_yanit" ]] && command -v jq > /dev/null 2>&1; then
        local emir_sayisi
        emir_sayisi=$(echo "$emir_yanit" | jq 'length' 2>/dev/null)
        echo ""
        echo "  Toplam Emir: ${emir_sayisi:-0}"
        echo ""
        printf "  %-8s %-6s %8s %10s %-12s\n" "Sembol" "Yon" "Lot" "Fiyat" "Durum"
        echo "  -------------------------------------------------------"
        echo "$emir_yanit" | jq -r '.[] | "\(.sembol)\t\(.yon)\t\(.lot)\t\(.fiyat // "-")\t\(.durum)"' 2>/dev/null | \
        while IFS=$'\t' read -r sembol yon lot fiyat durum; do
            printf "  %-8s %-6s %8s %10s %-12s\n" "$sembol" "$yon" "$lot" "$fiyat" "$durum"
        done
    else
        echo "  Bugun emir bulunamadi."
    fi

    echo "========================================================================="
    echo ""
}

# -------------------------------------------------------
# vt_kar_zarar_rapor <kurum> <hesap> [gun_sayisi]
# Belirli donem icin toplam K/Z hesaplar.
# -------------------------------------------------------
vt_kar_zarar_rapor() {
    local kurum="$1"
    local hesap="$2"
    local gun="${3:-30}"

    local baslangic
    baslangic=$(date -d "-${gun} days" '+%Y-%m-%d' 2>/dev/null || date -v "-${gun}d" '+%Y-%m-%d' 2>/dev/null)

    echo ""
    echo "========================================================================="
    echo "  KAR/ZARAR RAPORU — Son $gun Gun ($kurum/$hesap)"
    echo "========================================================================="

    # En eski ve en yeni bakiye
    local ilk_bakiye
    ilk_bakiye=$(vt_istek_at "GET" "bakiye_gecmisi?kurum=eq.${kurum}&hesap=eq.${hesap}&zaman=gte.${baslangic}&order=zaman.asc&limit=1" "" "Prefer: return=representation")

    local son_bakiye
    son_bakiye=$(vt_istek_at "GET" "bakiye_gecmisi?kurum=eq.${kurum}&hesap=eq.${hesap}&order=zaman.desc&limit=1" "" "Prefer: return=representation")

    if command -v jq > /dev/null 2>&1 && [[ -n "$ilk_bakiye" ]] && [[ -n "$son_bakiye" ]]; then
        local ilk_toplam son_toplam
        ilk_toplam=$(echo "$ilk_bakiye" | jq -r '.[0].toplam // 0' 2>/dev/null)
        son_toplam=$(echo "$son_bakiye" | jq -r '.[0].toplam // 0' 2>/dev/null)

        if [[ -n "$ilk_toplam" ]] && [[ -n "$son_toplam" ]]; then
            local fark yuzde
            fark=$(echo "$son_toplam - $ilk_toplam" | bc 2>/dev/null)
            if [[ "$ilk_toplam" != "0" ]]; then
                yuzde=$(echo "scale=2; $fark * 100 / $ilk_toplam" | bc 2>/dev/null)
            else
                yuzde="0"
            fi

            printf "  Baslangic Toplam : %s TL\n" "$ilk_toplam"
            printf "  Son Toplam       : %s TL\n" "$son_toplam"
            printf "  Fark             : %s TL (%%%s)\n" "${fark:-0}" "${yuzde:-0}"
        fi
    else
        echo "  Yeterli bakiye verisi bulunamadi."
    fi

    echo "========================================================================="
    echo ""
}

# -------------------------------------------------------
# vt_fiyat_gecmisi <sembol> [limit]
# Belirli sembolun fiyat gecmisini getirir.
# -------------------------------------------------------
vt_fiyat_gecmisi() {
    local sembol="$1"
    local limit="${2:-30}"

    local yanit
    yanit=$(vt_istek_at "GET" "fiyat_gecmisi?sembol=eq.${sembol}&order=zaman.desc&limit=${limit}" "" "Prefer: return=representation")

    if [[ -z "$yanit" ]]; then
        echo "Fiyat gecmisi bulunamadi: $sembol"
        return 1
    fi

    echo ""
    echo "========================================================================="
    echo "  FIYAT GECMISI — $sembol (Son $limit)"
    echo "========================================================================="
    printf " %-16s %10s %10s %10s %8s %12s\n" \
        "Zaman" "Fiyat" "Tavan" "Taban" "Degisim" "Hacim"
    echo "-------------------------------------------------------------------------"

    if command -v jq > /dev/null 2>&1; then
        echo "$yanit" | jq -r '.[] | "\(.zaman)\t\(.fiyat)\t\(.tavan // "-")\t\(.taban // "-")\t\(.degisim // "-")\t\(.hacim // "-")"' 2>/dev/null | \
        while IFS=$'\t' read -r zaman fiyat tavan taban degisim hacim; do
            local kisa_zaman
            kisa_zaman="${zaman:0:16}"
            printf " %-16s %10s %10s %10s %8s %12s\n" \
                "$kisa_zaman" "$fiyat" "$tavan" "$taban" "$degisim" "$hacim"
        done
    else
        echo "$yanit"
    fi

    echo "========================================================================="
    echo ""
}

# -------------------------------------------------------
# vt_fiyat_istatistik <sembol> [gun_sayisi]
# Belirli sembol icin istatistik.
# -------------------------------------------------------
vt_fiyat_istatistik() {
    local sembol="$1"
    local gun="${2:-30}"

    local baslangic
    baslangic=$(date -d "-${gun} days" '+%Y-%m-%d' 2>/dev/null || date -v "-${gun}d" '+%Y-%m-%d' 2>/dev/null)

    local yanit
    yanit=$(vt_istek_at "GET" "fiyat_gecmisi?sembol=eq.${sembol}&zaman=gte.${baslangic}&order=zaman.desc" "" "Prefer: return=representation")

    if [[ -z "$yanit" ]] || ! command -v jq > /dev/null 2>&1; then
        echo "Istatistik hesaplanamadi: $sembol"
        return 1
    fi

    local kayit_sayisi ort_fiyat min_fiyat maks_fiyat
    kayit_sayisi=$(echo "$yanit" | jq 'length' 2>/dev/null)
    ort_fiyat=$(echo "$yanit" | jq '[.[].fiyat | tonumber] | add / length | . * 100 | round / 100' 2>/dev/null)
    min_fiyat=$(echo "$yanit" | jq '[.[].fiyat | tonumber] | min' 2>/dev/null)
    maks_fiyat=$(echo "$yanit" | jq '[.[].fiyat | tonumber] | max' 2>/dev/null)

    echo ""
    echo "========================================="
    echo "  FIYAT ISTATISTIK — $sembol (Son ${gun} gun)"
    echo "========================================="
    echo "  Kayit Sayisi : ${kayit_sayisi:-0}"
    echo "  Ortalama     : ${ort_fiyat:-?} TL"
    echo "  Minimum      : ${min_fiyat:-?} TL"
    echo "  Maksimum     : ${maks_fiyat:-?} TL"
    echo "========================================="
    echo ""
}

# -------------------------------------------------------
# vt_halka_arz_gecmisi <kurum> <hesap> [limit]
# Halka arz islem gecmisi.
# -------------------------------------------------------
vt_halka_arz_gecmisi() {
    local kurum="$1"
    local hesap="$2"
    local limit="${3:-20}"

    local yanit
    yanit=$(vt_istek_at "GET" "halka_arz_islemleri?kurum=eq.${kurum}&hesap=eq.${hesap}&order=zaman.desc&limit=${limit}" "" "Prefer: return=representation")

    if [[ -z "$yanit" ]]; then
        echo "Halka arz gecmisi bulunamadi."
        return 1
    fi

    echo ""
    echo "========================================================================="
    echo "  HALKA ARZ GECMISI ($kurum/$hesap)"
    echo "========================================================================="
    printf " %-8s %-20s %8s %10s %-10s %-16s\n" \
        "Tip" "Ad" "Lot" "Fiyat" "Durum" "Zaman"
    echo "-------------------------------------------------------------------------"

    if command -v jq > /dev/null 2>&1; then
        echo "$yanit" | jq -r '.[] | "\(.islem_tipi)\t\(.ipo_adi // "-")\t\(.lot // "-")\t\(.fiyat // "-")\t\(if .basarili then "BASARILI" else "BASARISIZ" end)\t\(.zaman)"' 2>/dev/null | \
        while IFS=$'\t' read -r tip ad lot fiyat durum zaman; do
            local kisa_zaman
            kisa_zaman="${zaman:0:16}"
            printf " %-8s %-20s %8s %10s %-10s %-16s\n" \
                "$tip" "$ad" "$lot" "$fiyat" "$durum" "$kisa_zaman"
        done
    else
        echo "$yanit"
    fi

    echo "========================================================================="
    echo ""
}

# -------------------------------------------------------
# vt_robot_log_gecmisi <robot_pid_veya_kurum> [hesap] [limit]
# Robot olaylarini getirir. Ilk parametre sayi ise PID ile filtreler.
# -------------------------------------------------------
vt_robot_log_gecmisi() {
    local param1="$1"
    local param2="${2:-}"
    local limit="${3:-50}"

    local sorgu
    if [[ "$param1" =~ ^[0-9]+$ ]] && [[ -z "$param2" ]]; then
        # PID ile filtrele
        sorgu="robot_log?robot_pid=eq.${param1}&order=zaman.desc&limit=${limit}"
    else
        # Kurum/hesap ile filtrele
        sorgu="robot_log?kurum=eq.${param1}&hesap=eq.${param2}&order=zaman.desc&limit=${limit}"
    fi

    local yanit
    yanit=$(vt_istek_at "GET" "$sorgu" "" "Prefer: return=representation")

    if [[ -z "$yanit" ]]; then
        echo "Robot log bulunamadi."
        return 1
    fi

    echo ""
    echo "========================================================================="
    echo "  ROBOT LOG GECMISI"
    echo "========================================================================="
    printf " %-16s %8s %-15s %-12s %s\n" \
        "Zaman" "PID" "Strateji" "Olay" "Detay"
    echo "-------------------------------------------------------------------------"

    if command -v jq > /dev/null 2>&1; then
        echo "$yanit" | jq -r '.[] | "\(.zaman)\t\(.robot_pid)\t\(.strateji)\t\(.olay)\t\(.detay // "")"' 2>/dev/null | \
        while IFS=$'\t' read -r zaman pid strateji olay detay; do
            local kisa_zaman
            kisa_zaman="${zaman:0:16}"
            printf " %-16s %8s %-15s %-12s %s\n" \
                "$kisa_zaman" "$pid" "$strateji" "$olay" "${detay:0:40}"
        done
    else
        echo "$yanit"
    fi

    echo "========================================================================="
    echo ""
}

# -------------------------------------------------------
# vt_oturum_log_gecmisi <kurum> <hesap> [limit]
# Oturum olaylarini getirir.
# -------------------------------------------------------
vt_oturum_log_gecmisi() {
    local kurum="$1"
    local hesap="$2"
    local limit="${3:-20}"

    local yanit
    yanit=$(vt_istek_at "GET" "oturum_log?kurum=eq.${kurum}&hesap=eq.${hesap}&order=zaman.desc&limit=${limit}" "" "Prefer: return=representation")

    if [[ -z "$yanit" ]]; then
        echo "Oturum log bulunamadi."
        return 1
    fi

    echo ""
    echo "========================================================================="
    echo "  OTURUM LOG ($kurum/$hesap)"
    echo "========================================================================="
    printf " %-20s %-12s %s\n" "Zaman" "Olay" "Detay"
    echo "-------------------------------------------------------------------------"

    if command -v jq > /dev/null 2>&1; then
        echo "$yanit" | jq -r '.[] | "\(.zaman)\t\(.olay)\t\(.detay // "")"' 2>/dev/null | \
        while IFS=$'\t' read -r zaman olay detay; do
            local kisa_zaman
            kisa_zaman="${zaman:0:16}"
            printf " %-20s %-12s %s\n" "$kisa_zaman" "$olay" "$detay"
        done
    else
        echo "$yanit"
    fi

    echo "========================================================================="
    echo ""
}

# =======================================================
# BOLUM 4: YARDIMCI FONKSIYONLAR
# =======================================================

# -------------------------------------------------------
# vt_mutabakat_kontrol <kurum> <hesap>
# Canli bakiye ile DB son bakiyeyi karsilastirir.
# -------------------------------------------------------
vt_mutabakat_kontrol() {
    local kurum="$1"
    local hesap="$2"

    echo ""
    echo "========================================="
    echo "  MUTABAKAT KONTROLU ($kurum/$hesap)"
    echo "========================================="

    # DB son bakiye
    local db_yanit
    db_yanit=$(vt_istek_at "GET" "bakiye_gecmisi?kurum=eq.${kurum}&hesap=eq.${hesap}&order=zaman.desc&limit=1" "" "Prefer: return=representation")

    if [[ -z "$db_yanit" ]] || ! command -v jq > /dev/null 2>&1; then
        echo "  DB bakiye bilgisi alinamadi."
        echo "========================================="
        return 1
    fi

    local db_toplam
    db_toplam=$(echo "$db_yanit" | jq -r '.[0].toplam // ""' 2>/dev/null)
    local db_zaman
    db_zaman=$(echo "$db_yanit" | jq -r '.[0].zaman // ""' 2>/dev/null)

    if [[ -z "$db_toplam" ]]; then
        echo "  DB'de bakiye kaydı yok."
        echo "  Once bakiye sorgulayın: borsa $kurum bakiye"
        echo "========================================="
        return 1
    fi

    echo "  DB Son Bakiye : $db_toplam TL (${db_zaman:0:16})"

    # Canli bakiye
    # Not: _BORSA_VERI_BAKIYE global dizisi adaptor tarafindan doldurulur
    local canli_toplam="${_BORSA_VERI_BAKIYE[toplam]:-}"
    if [[ -z "$canli_toplam" ]]; then
        echo "  Canli bakiye bilgisi yok (once bakiye sorgulayın)."
        echo "========================================="
        return 1
    fi

    local canli_temiz db_temiz fark fark_abs
    canli_temiz="${canli_toplam//,/}"
    db_temiz="${db_toplam//,/}"

    fark=$(echo "$canli_temiz - $db_temiz" | bc 2>/dev/null)
    fark_abs=$(echo "if ($fark < 0) -1 * $fark else $fark" | bc 2>/dev/null)

    echo "  Canli Bakiye  : $canli_toplam TL"
    echo "  Fark          : ${fark:-?} TL"

    if [[ -n "$fark_abs" ]]; then
        local esik
        esik=$(echo "scale=2; $db_temiz * 0.0001" | bc 2>/dev/null)
        if (( $(echo "$fark_abs > ${esik:-0.01}" | bc -l 2>/dev/null) )); then
            echo ""
            echo "  [!] TUTARSIZLIK TESPIT EDILDI"
            _cekirdek_log "KRITIK: Mutabakat tutarsizligi — $kurum/$hesap — fark: $fark TL"
        else
            echo ""
            echo "  [OK] TUTARLI"
        fi
    fi

    echo "========================================="
    echo ""
}

# -------------------------------------------------------
# vt_pozisyon_mutabakat <kurum> <hesap> [sembol]
# Emir gecmisi ile portfoy pozisyonlarini capraz kontrol eder.
# -------------------------------------------------------
vt_pozisyon_mutabakat() {
    local kurum="$1"
    local hesap="$2"
    local sembol="${3:-}"

    echo ""
    echo "========================================="
    echo "  POZISYON MUTABAKAT ($kurum/$hesap)"
    echo "========================================="

    if ! command -v jq > /dev/null 2>&1; then
        echo "  jq gerekli. Kurun: sudo apt install jq"
        echo "========================================="
        return 1
    fi

    local filtre=""
    [[ -n "$sembol" ]] && filtre="&sembol=eq.${sembol}"

    # Son pozisyonlari al
    local poz_yanit
    poz_yanit=$(vt_istek_at "GET" "pozisyonlar?kurum=eq.${kurum}&hesap=eq.${hesap}${filtre}&order=zaman.desc&limit=50" "" "Prefer: return=representation")

    if [[ -z "$poz_yanit" ]]; then
        echo "  Pozisyon kaydı bulunamadı."
        echo "========================================="
        return 1
    fi

    # Her sembol icin kontrol
    local semboller
    semboller=$(echo "$poz_yanit" | jq -r '.[].sembol' 2>/dev/null | sort -u)

    while IFS= read -r s; do
        [[ -z "$s" ]] && continue

        local poz_lot
        poz_lot=$(echo "$poz_yanit" | jq -r "[.[] | select(.sembol == \"$s\")] | .[0].lot // 0" 2>/dev/null)

        # Emir gecmisinden lot hesapla
        local emir_yanit
        emir_yanit=$(vt_istek_at "GET" "emirler?kurum=eq.${kurum}&hesap=eq.${hesap}&sembol=eq.${s}&durum=eq.GERCEKLESTI" "" "Prefer: return=representation")

        local hesaplanan=0
        if [[ -n "$emir_yanit" ]]; then
            local alis_lot satis_lot
            alis_lot=$(echo "$emir_yanit" | jq '[.[] | select(.yon == "ALIS") | .lot] | add // 0' 2>/dev/null)
            satis_lot=$(echo "$emir_yanit" | jq '[.[] | select(.yon == "SATIS") | .lot] | add // 0' 2>/dev/null)
            hesaplanan=$(( ${alis_lot:-0} - ${satis_lot:-0} ))
        fi

        if [[ "$poz_lot" == "$hesaplanan" ]]; then
            printf "  %-8s %8s lot  [OK] TUTARLI\n" "$s" "$poz_lot"
        else
            printf "  %-8s DB: %s lot, Hesaplanan: %s lot  [!] TUTARSIZ\n" "$s" "$poz_lot" "$hesaplanan"
            _cekirdek_log "UYARI: Pozisyon tutarsizligi — $s — DB: $poz_lot, hesaplanan: $hesaplanan"
        fi
    done <<< "$semboller"

    echo "========================================="
    echo ""
}

# -------------------------------------------------------
# _vt_bekleyenleri_gonder
# Basarisiz DB yazimlarini yeniden dener.
# Robot arka plan dongusunde periyodik cagrilir.
# -------------------------------------------------------
_vt_bekleyenleri_gonder() {
    local bekleyen="${_VT_YEDEK_DIZIN}/bekleyen.jsonl"
    [[ ! -f "$bekleyen" ]] && return 0

    local satir_sayisi
    satir_sayisi=$(wc -l < "$bekleyen" 2>/dev/null)
    [[ "${satir_sayisi:-0}" -eq 0 ]] && return 0

    if ! vt_baglanti_kontrol; then
        return 1
    fi

    _cekirdek_log "DB: $satir_sayisi bekleyen kayit yeniden deneniyor..."

    local gecici="${bekleyen}.gecici"
    local basarisiz=0

    while IFS= read -r satir; do
        [[ -z "$satir" ]] && continue

        local tablo veri
        if command -v jq > /dev/null 2>&1; then
            tablo=$(echo "$satir" | jq -r '.tablo' 2>/dev/null)
            veri=$(echo "$satir" | jq -c '.veri' 2>/dev/null)
        else
            tablo=$(echo "$satir" | grep -oP '"tablo"\s*:\s*"\K[^"]+')
            veri=$(echo "$satir" | grep -oP '"veri"\s*:\s*\K\{[^}]+\}')
        fi

        if [[ -n "$tablo" ]] && [[ -n "$veri" ]]; then
            if ! vt_istek_at "POST" "$tablo" "$veri" 2>/dev/null; then
                echo "$satir" >> "$gecici"
                basarisiz=$((basarisiz + 1))
            fi
        fi
    done < "$bekleyen"

    if [[ -f "$gecici" ]]; then
        mv "$gecici" "$bekleyen"
        _cekirdek_log "DB: $basarisiz kayit hala beklemede."
    else
        rm -f "$bekleyen"
        _cekirdek_log "DB: Tum bekleyen kayitlar gonderildi."
    fi
}
