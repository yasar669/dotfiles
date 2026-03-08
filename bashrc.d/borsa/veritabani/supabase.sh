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

# Otomatik baslama bayragi (oturum basina bir kere)
_VT_KONTROL_YAPILDI=0

# -------------------------------------------------------
# _vt_otomatik_baslat
# Supabase konteynerlerinin calisip calismadigini kontrol eder.
# Calismiyorsa docker compose ile otomatik baslatir.
# Shell oturumunda sadece bir kere calisir.
# -------------------------------------------------------
_vt_otomatik_baslat() {
    # Zaten kontrol edildi mi?
    [[ "$_VT_KONTROL_YAPILDI" -eq 1 ]] && return 0

    _VT_KONTROL_YAPILDI=1

    # Ayarlar yoksa DB kullanilmiyor demek — atla
    if [[ -z "$_SUPABASE_URL" ]] || [[ -z "$_SUPABASE_ANAHTAR" ]]; then
        return 0
    fi

    # Docker kurulu mu?
    if ! command -v docker > /dev/null 2>&1; then
        return 1
    fi

    # API zaten erisilebilir mi? (hizli kontrol, 2 saniye timeout)
    if curl -sf --max-time 2 \
        -H "apikey: $_SUPABASE_ANAHTAR" \
        "${_SUPABASE_URL}/rest/v1/" > /dev/null 2>&1; then
        return 0
    fi

    # Konteynerler durdurulmus — baslatmayi dene
    local compose_dizin="${BORSA_KLASORU}/veritabani"
    if [[ ! -f "${compose_dizin}/docker-compose.yml" ]]; then
        return 1
    fi

    _cekirdek_log "Supabase konteynerleri baslatiliyor..."
    docker compose -f "${compose_dizin}/docker-compose.yml" up -d 2>/dev/null

    # PostgREST'in hazir olmasini bekle (maks 15 saniye)
    local beklenen=0
    while [[ "$beklenen" -lt 15 ]]; do
        if curl -sf --max-time 2 \
            -H "apikey: $_SUPABASE_ANAHTAR" \
            "${_SUPABASE_URL}/rest/v1/" > /dev/null 2>&1; then
            _cekirdek_log "Supabase hazir."
            return 0
        fi
        sleep 1
        beklenen=$((beklenen + 1))
    done

    _cekirdek_log "UYARI: Supabase baslatilamadi."
    return 1
}

# Shell yuklendiginde otomatik kontrol et
_vt_otomatik_baslat

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

    # Erisim yok — otomatik baslatmayi dene
    _VT_KONTROL_YAPILDI=0
    _vt_otomatik_baslat
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
# BOLUM 2: AYAR YONETIMI
# =======================================================

# -------------------------------------------------------
# vt_ayar_kaydet <anahtar> <deger> [aciklama]
# Anahtar-deger ciftini ayarlar tablosuna yazar.
# Varsa gunceller (upsert), yoksa ekler.
# -------------------------------------------------------
vt_ayar_kaydet() {
    local anahtar="$1"
    local deger="$2"
    local aciklama="${3:-}"

    if [[ -z "$anahtar" ]] || [[ -z "$deger" ]]; then
        return 1
    fi

    _vt_otomatik_baslat

    local json
    json=$(_vt_json_olustur \
        "anahtar" "$anahtar" \
        "deger" "$deger" \
        "aciklama" "$aciklama")

    # Upsert: varsa guncelle, yoksa ekle
    vt_istek_at "POST" "ayarlar" "$json" \
        "Prefer: resolution=merge-duplicates" || {
        _cekirdek_log "UYARI: Ayar kaydedilemedi — $anahtar"
        return 1
    }

    return 0
}

# -------------------------------------------------------
# vt_ayar_oku <anahtar>
# Ayarlar tablosundan degeri okur.
# stdout: deger (bos ise hicbir sey yazmaz)
# Donus: 0 = bulundu, 1 = bulunamadi
# -------------------------------------------------------
vt_ayar_oku() {
    local anahtar="$1"

    if [[ -z "$anahtar" ]]; then
        return 1
    fi

    _vt_otomatik_baslat

    local yanit
    yanit=$(vt_istek_at "GET" "ayarlar?anahtar=eq.${anahtar}&select=deger" "" \
        "Accept: application/json") || return 1

    # JSON dizisinden degeri cikar: [{"deger":"xxx"}]
    local deger=""
    if command -v jq > /dev/null 2>&1; then
        deger=$(echo "$yanit" | jq -r '.[0].deger // empty' 2>/dev/null)
    else
        deger=$(echo "$yanit" | grep -oP '"deger"\s*:\s*"\K[^"]+' 2>/dev/null | head -1)
    fi

    if [[ -n "$deger" ]]; then
        echo "$deger"
        return 0
    fi

    return 1
}

# -------------------------------------------------------
# vt_ayar_sil <anahtar>
# Ayarlar tablosundan bir kaydi siler.
# -------------------------------------------------------
vt_ayar_sil() {
    local anahtar="$1"

    if [[ -z "$anahtar" ]]; then
        return 1
    fi

    _vt_otomatik_baslat

    vt_istek_at "DELETE" "ayarlar?anahtar=eq.${anahtar}" || {
        _cekirdek_log "UYARI: Ayar silinemedi — $anahtar"
        return 1
    }

    return 0
}

# =======================================================
# BOLUM 3: YAZMA FONKSIYONLARI
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

# (vt_fiyat_kaydet kaldirildi — fiyat_gecmisi tablosu yerine ohlcv kullaniliyor.
#  Anlik fiyat yazimi icin vt_ohlcv_yaz kullanilmali.)

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
# vt_fiyat_gecmisi <sembol> [limit] [periyot]
# ohlcv tablosundan fiyat gecmisi gosterir.
# Varsayilan periyot: 1G (gunluk), varsayilan limit: 30
# Gecerli periyotlar: 1dk 3dk 5dk 15dk 30dk 45dk 1S 2S 3S 4S 1G 1H 1A
# -------------------------------------------------------
vt_fiyat_gecmisi() {
    local sembol="$1"
    local limit="${2:-30}"
    local periyot="${3:-1G}"

    local sorgu="ohlcv?sembol=eq.${sembol}&periyot=eq.${periyot}"
    sorgu+="&order=tarih.desc&limit=${limit}"
    sorgu+="&select=tarih,acilis,yuksek,dusuk,kapanis,hacim"

    local yanit
    yanit=$(vt_istek_at "GET" "$sorgu" "" "Prefer: return=representation")

    if [[ -z "$yanit" ]] || [[ "$yanit" == "[]" ]]; then
        echo "Fiyat gecmisi bulunamadi: $sembol (periyot: $periyot)"
        return 1
    fi

    echo ""
    echo "========================================================================="
    echo "  FIYAT GECMISI — $sembol / $periyot (Son $limit)"
    echo "========================================================================="
    printf " %-16s %10s %10s %10s %10s %12s\n" \
        "Tarih" "Acilis" "Yuksek" "Dusuk" "Kapanis" "Hacim"
    echo "-------------------------------------------------------------------------"

    if command -v jq > /dev/null 2>&1; then
        echo "$yanit" | jq -r '.[] | "\(.tarih)\t\(.acilis)\t\(.yuksek)\t\(.dusuk)\t\(.kapanis)\t\(.hacim)"' 2>/dev/null | \
        while IFS=$'\t' read -r tarih acilis yuksek dusuk kapanis hacim; do
            local kisa_tarih
            kisa_tarih="${tarih:0:16}"
            printf " %-16s %10s %10s %10s %10s %12s\n" \
                "$kisa_tarih" "$acilis" "$yuksek" "$dusuk" "$kapanis" "$hacim"
        done
    else
        # jq yoksa basit grep/sed ile parse et
        echo "$yanit" | grep -o '"tarih":"[^"]*"' | sed 's/"tarih":"//;s/"//' | \
        paste - \
            <(echo "$yanit" | grep -oP '"acilis":\K[0-9.]+') \
            <(echo "$yanit" | grep -oP '"yuksek":\K[0-9.]+') \
            <(echo "$yanit" | grep -oP '"dusuk":\K[0-9.]+') \
            <(echo "$yanit" | grep -oP '"kapanis":\K[0-9.]+') \
            <(echo "$yanit" | grep -oP '"hacim":\K[0-9.]+') | \
        while IFS=$'\t' read -r tarih acilis yuksek dusuk kapanis hacim; do
            local kisa_tarih
            kisa_tarih="${tarih:0:16}"
            printf " %-16s %10s %10s %10s %10s %12s\n" \
                "$kisa_tarih" "$acilis" "$yuksek" "$dusuk" "$kapanis" "$hacim"
        done
    fi

    echo "========================================================================="
    echo ""
}

# -------------------------------------------------------
# vt_fiyat_istatistik <sembol> [gun_sayisi] [periyot]
# ohlcv tablosundan belirli sembol icin istatistik hesaplar.
# Varsayilan periyot: 1G (gunluk)
# -------------------------------------------------------
vt_fiyat_istatistik() {
    local sembol="$1"
    local gun="${2:-30}"
    local periyot="${3:-1G}"

    local baslangic
    baslangic=$(date -d "-${gun} days" '+%Y-%m-%d' 2>/dev/null || date -v "-${gun}d" '+%Y-%m-%d' 2>/dev/null)

    local sorgu="ohlcv?sembol=eq.${sembol}&periyot=eq.${periyot}"
    sorgu+="&tarih=gte.${baslangic}&order=tarih.desc"
    sorgu+="&select=kapanis,yuksek,dusuk,hacim"

    local yanit
    yanit=$(vt_istek_at "GET" "$sorgu" "" "Prefer: return=representation")

    if [[ -z "$yanit" ]] || [[ "$yanit" == "[]" ]] || ! command -v jq > /dev/null 2>&1; then
        echo "Istatistik hesaplanamadi: $sembol (periyot: $periyot)"
        return 1
    fi

    local kayit_sayisi ort_fiyat min_fiyat maks_fiyat
    kayit_sayisi=$(echo "$yanit" | jq 'length' 2>/dev/null)
    ort_fiyat=$(echo "$yanit" | jq '[.[].kapanis | tonumber] | add / length | . * 100 | round / 100' 2>/dev/null)
    min_fiyat=$(echo "$yanit" | jq '[.[].dusuk | tonumber] | min' 2>/dev/null)
    maks_fiyat=$(echo "$yanit" | jq '[.[].yuksek | tonumber] | max' 2>/dev/null)

    echo ""
    echo "========================================="
    echo "  FIYAT ISTATISTIK — $sembol / $periyot (Son ${gun} gun)"
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

# =======================================================
# BOLUM 5: OHLCV FONKSIYONLARI
# Mum verisinin okunmasi, yazilmasi ve toplu yuklenmesi.
# =======================================================

# -------------------------------------------------------
# vt_ohlcv_oku <sembol> <periyot> <limit> [offset]
# Supabase'den OHLCV mum verisi okur.
# Sonuc en yeni mumdan eskiye dogru siralanir.
# stdout: JSON dizisi
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
vt_ohlcv_oku() {
    local sembol="$1"
    local periyot="$2"
    local limit="${3:-200}"
    local offset="${4:-0}"

    if [[ -z "$sembol" ]] || [[ -z "$periyot" ]]; then
        return 1
    fi

    local sorgu="ohlcv?sembol=eq.${sembol}&periyot=eq.${periyot}"
    sorgu+="&order=tarih.desc&limit=${limit}&offset=${offset}"
    sorgu+="&select=tarih,acilis,yuksek,dusuk,kapanis,hacim,kaynak"

    vt_istek_at "GET" "$sorgu"
}

# -------------------------------------------------------
# vt_ohlcv_yaz <sembol> <periyot> <tarih> <acilis> <yuksek>
#              <dusuk> <kapanis> <hacim> [kaynak]
# Tek bir OHLCV mumunu Supabase'e yazar (UPSERT).
# Ayni sembol+periyot+tarih varsa gunceller.
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
vt_ohlcv_yaz() {
    local sembol="$1"
    local periyot="$2"
    local tarih="$3"
    local acilis="$4"
    local yuksek="$5"
    local dusuk="$6"
    local kapanis="$7"
    local hacim="$8"
    local kaynak="${9:-tvdata}"

    if [[ -z "$sembol" ]] || [[ -z "$kapanis" ]]; then
        return 1
    fi

    local json
    json=$(_vt_json_olustur \
        "sembol" "$sembol" \
        "periyot" "$periyot" \
        "tarih" "$tarih" \
        "acilis" "$acilis" \
        "yuksek" "$yuksek" \
        "dusuk" "$dusuk" \
        "kapanis" "$kapanis" \
        "hacim" "$hacim" \
        "kaynak" "$kaynak")

    if ! vt_istek_at "POST" "ohlcv" "$json" \
        "Prefer: resolution=merge-duplicates"; then
        _vt_yedege_yaz "ohlcv" "$json"
        return 1
    fi

    return 0
}

# -------------------------------------------------------
# vt_ohlcv_toplu_yaz <json_dizi>
# Birden fazla OHLCV mumunu tek istekte yazar (UPSERT).
# json_dizi: JSON array formati [{"sembol":..}, {"sembol":..}]
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
vt_ohlcv_toplu_yaz() {
    local json_dizi="$1"

    if [[ -z "$json_dizi" ]]; then
        return 1
    fi

    vt_istek_at "POST" "ohlcv" "$json_dizi" \
        "Prefer: resolution=merge-duplicates"
}

# -------------------------------------------------------
# vt_ohlcv_son_tarih <sembol> <periyot>
# Belirtilen sembol ve periyot icin en son mum tarihini doner.
# stdout: ISO tarih veya bos
# Donus: 0 = bulundu, 1 = veri yok
# -------------------------------------------------------
vt_ohlcv_son_tarih() {
    local sembol="$1"
    local periyot="$2"

    if [[ -z "$sembol" ]] || [[ -z "$periyot" ]]; then
        return 1
    fi

    local sorgu="ohlcv?sembol=eq.${sembol}&periyot=eq.${periyot}"
    sorgu+="&order=tarih.desc&limit=1&select=tarih"

    local yanit
    yanit=$(vt_istek_at "GET" "$sorgu") || return 1

    # JSON dizisinden tarih cikart: [{"tarih":"2026-02-24T..."}]
    local tarih=""
    if command -v jq > /dev/null 2>&1; then
        tarih=$(echo "$yanit" | jq -r '.[0].tarih // empty' 2>/dev/null)
    else
        tarih=$(echo "$yanit" | grep -oP '"tarih"\s*:\s*"\K[^"]+' | head -1)
    fi

    if [[ -n "$tarih" ]]; then
        echo "$tarih"
        return 0
    fi

    return 1
}

# -------------------------------------------------------
# vt_ohlcv_sayac <sembol> [periyot]
# Belirtilen sembol (ve istege bagli periyot) icin
# kayitli mum sayisini doner.
# stdout: sayi
# -------------------------------------------------------
vt_ohlcv_sayac() {
    local sembol="$1"
    local periyot="${2:-}"

    local sorgu="ohlcv?sembol=eq.${sembol}"
    if [[ -n "$periyot" ]]; then
        sorgu+="&periyot=eq.${periyot}"
    fi

    local yanit
    yanit=$(vt_istek_at "GET" "$sorgu" "" \
        "Prefer: count=exact" \
        "Range-Unit: items" \
        "Range: 0-0") || return 1

    # Supabase count header yerine bos yanit kontrolu
    # Basit yontem: select count ile
    local sayac_sorgu="ohlcv?sembol=eq.${sembol}&select=id"
    if [[ -n "$periyot" ]]; then
        sayac_sorgu+="&periyot=eq.${periyot}"
    fi
    sayac_sorgu+="&limit=0"

    # Prefer: count=exact header'i Content-Range doner
    yanit=$(curl -s \
        -H "apikey: $_SUPABASE_ANAHTAR" \
        -H "Authorization: Bearer $_SUPABASE_ANAHTAR" \
        -H "Prefer: count=exact" \
        "${_SUPABASE_URL}/rest/v1/${sayac_sorgu}" 2>/dev/null \
        -D /dev/stderr 2>&1 | grep -oP 'Content-Range: \K[0-9/*]+' | head -1)

    if [[ "$yanit" == *"/"* ]]; then
        echo "${yanit##*/}"
    else
        echo "0"
    fi
}
