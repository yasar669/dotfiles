# shellcheck shell=bash

# Tarama Katmani - Veri Kaynagi Yonetimi
# Fiyat verilerini toplar, onbellek yonetimi yapar, failover saglar.
# Robot ve strateji katmani bu dosyadaki fonksiyonlari kullanir.
#
# Yuklenme: cekirdek.sh tarafindan source edilir.

# =======================================================
# YAPILANDIRMA
# =======================================================

_VERI_ONBELLEK_DIZIN="/tmp/borsa/_veri_onbellek"
_VERI_ONBELLEK_SURESI=10    # saniye
_VERI_DURUM_DOSYASI="/tmp/borsa/_veri_durum"

# Aktif veri kaynagi bilgileri
declare -g _VERI_KAYNAGI_KURUM=""
declare -g _VERI_KAYNAGI_HESAP=""
declare -ga _VERI_KAYNAGI_YEDEKLER=()

# =======================================================
# BOLUM 1: ONBELLEK FONKSIYONLARI
# =======================================================

# -------------------------------------------------------
# _veri_onbellek_oku <sembol>
# Dosya onbelleginden fiyat verisini okur.
# stdout: epoch|fiyat|tavan|taban|degisim|hacim|seans
# Donus: 0 = taze veri var, 1 = eski veya yok
# -------------------------------------------------------
_veri_onbellek_oku() {
    local sembol="$1"
    local dosya="${_VERI_ONBELLEK_DIZIN}/${sembol}.dat"

    [[ ! -f "$dosya" ]] && return 1

    local icerik
    icerik=$(cat "$dosya" 2>/dev/null) || return 1
    [[ -z "$icerik" ]] && return 1

    # Epoch kontrolu — taze mi?
    local kayit_zamani
    kayit_zamani=$(echo "$icerik" | cut -d'|' -f1)
    local simdi
    simdi=$(date +%s)

    local gecen=$(( simdi - kayit_zamani ))
    if [[ "$gecen" -gt "$_VERI_ONBELLEK_SURESI" ]]; then
        return 1    # suresi dolmus
    fi

    echo "$icerik"
    return 0
}

# -------------------------------------------------------
# _veri_onbellek_yaz <sembol> <fiyat> <tavan> <taban>
#                    <degisim> <hacim> <seans>
# Dosya onbellegine fiyat verisini yazar.
# flock ile yaris kosulunu onler.
# -------------------------------------------------------
_veri_onbellek_yaz() {
    local sembol="$1"
    local fiyat="$2"
    local tavan="${3:-}"
    local taban="${4:-}"
    local degisim="${5:-}"
    local hacim="${6:-}"
    local seans="${7:-}"

    mkdir -p "$_VERI_ONBELLEK_DIZIN" 2>/dev/null

    local dosya="${_VERI_ONBELLEK_DIZIN}/${sembol}.dat"
    local epoch
    epoch=$(date +%s)

    # flock ile atomik yazma (race condition onlemi)
    (
        flock -n 200 || return 0
        echo "${epoch}|${fiyat}|${tavan}|${taban}|${degisim}|${hacim}|${seans}" > "$dosya"
    ) 200>"${dosya}.lock"
}

# =======================================================
# BOLUM 2: VERI KAYNAGI SECIMI VE YONETIMI
# =======================================================

# -------------------------------------------------------
# veri_kaynagi_baslat
# Otomatik veri kaynagi secer ve koruma dongusunu baslatir.
# Acik oturumlari tarar, ilk gecerli olanı kaynak yapar.
# -------------------------------------------------------
veri_kaynagi_baslat() {
    # Zaten aktif mi?
    if [[ -n "$_VERI_KAYNAGI_KURUM" ]] && [[ -n "$_VERI_KAYNAGI_HESAP" ]]; then
        echo "Veri kaynagi zaten aktif: ${_VERI_KAYNAGI_KURUM}/${_VERI_KAYNAGI_HESAP}"
        return 0
    fi

    echo "Acik oturumlar taraniyor..."

    local secildi=0
    _VERI_KAYNAGI_YEDEKLER=()

    local kurum_dizini hesap_dizini kurum hesap
    for kurum_dizini in "${_CEKIRDEK_OTURUM_KOK}"/*/; do
        [[ ! -d "$kurum_dizini" ]] && continue
        kurum=$(basename "$kurum_dizini")
        [[ "$kurum" == _* ]] && continue    # _vt_yedek gibi ozel dizinleri atla

        for hesap_dizini in "${kurum_dizini}"*/; do
            [[ ! -d "$hesap_dizini" ]] && continue
            hesap=$(basename "$hesap_dizini")

            # Cookie dosyasi var mi?
            [[ ! -f "${hesap_dizini}/${_CEKIRDEK_DOSYA_COOKIE}" ]] && continue

            if [[ "$secildi" -eq 0 ]]; then
                # Adaptor yukle ve oturum kontrol et
                local surucu="${BORSA_KLASORU}/adaptorler/${kurum}.sh"
                if [[ -f "$surucu" ]]; then
                    # shellcheck source=/dev/null
                    source "$surucu"
                    if declare -f adaptor_oturum_gecerli_mi > /dev/null 2>&1 && \
                       adaptor_oturum_gecerli_mi "$hesap" 2>/dev/null; then
                        _VERI_KAYNAGI_KURUM="$kurum"
                        _VERI_KAYNAGI_HESAP="$hesap"
                        secildi=1
                        continue
                    fi
                fi
            fi

            # Yedek listeye ekle
            _VERI_KAYNAGI_YEDEKLER+=("${kurum}:${hesap}")
        done
    done

    if [[ "$secildi" -eq 0 ]]; then
        echo "UYARI: Gecerli oturum bulunamadi. Once giris yapin."
        return 1
    fi

    echo "Veri kaynagi: ${_VERI_KAYNAGI_KURUM}/${_VERI_KAYNAGI_HESAP}"

    if [[ ${#_VERI_KAYNAGI_YEDEKLER[@]} -gt 0 ]]; then
        echo "Yedekler: ${_VERI_KAYNAGI_YEDEKLER[*]}"
    fi

    # Veri durum dosyasina yaz (robotlar okuyabilsin)
    mkdir -p "$(dirname "$_VERI_DURUM_DOSYASI")" 2>/dev/null
    echo "AKTIF" > "$_VERI_DURUM_DOSYASI"

    # Oturum koruma baslatilir (sahip: veri_kaynagi)
    cekirdek_oturum_koruma_baslat "$_VERI_KAYNAGI_KURUM" "$_VERI_KAYNAGI_HESAP" "veri_kaynagi"

    echo "Veri kaynagi hazir."
    return 0
}

# -------------------------------------------------------
# veri_kaynagi_durdur
# Veri kaynagi koruma dongusunu durdurur.
# -------------------------------------------------------
veri_kaynagi_durdur() {
    if [[ -z "$_VERI_KAYNAGI_KURUM" ]]; then
        echo "Aktif veri kaynagi yok."
        return 0
    fi

    cekirdek_oturum_koruma_durdur "$_VERI_KAYNAGI_KURUM" "$_VERI_KAYNAGI_HESAP" "veri_kaynagi"

    echo "Veri kaynagi durduruldu: ${_VERI_KAYNAGI_KURUM}/${_VERI_KAYNAGI_HESAP}"

    _VERI_KAYNAGI_KURUM=""
    _VERI_KAYNAGI_HESAP=""
    _VERI_KAYNAGI_YEDEKLER=()

    echo "YOK" > "$_VERI_DURUM_DOSYASI" 2>/dev/null
}

# -------------------------------------------------------
# veri_kaynagi_ayarla <kurum> <hesap>
# Manuel veri kaynagi secimi. Otomatik secimin onune gecer.
# -------------------------------------------------------
veri_kaynagi_ayarla() {
    local kurum="$1"
    local hesap="$2"

    if [[ -z "$kurum" ]] || [[ -z "$hesap" ]]; then
        echo "Kullanim: veri_kaynagi_ayarla <kurum> <hesap>"
        return 1
    fi

    # Oturum kontrolu
    local cookie
    cookie=$(cekirdek_dosya_yolu "$kurum" "$_CEKIRDEK_DOSYA_COOKIE" "$hesap")
    if [[ ! -f "$cookie" ]]; then
        echo "HATA: ${kurum}/${hesap} icin oturum bulunamadi."
        return 1
    fi

    # Onceki kaynak varsa durdur
    if [[ -n "$_VERI_KAYNAGI_KURUM" ]]; then
        veri_kaynagi_durdur
    fi

    _VERI_KAYNAGI_KURUM="$kurum"
    _VERI_KAYNAGI_HESAP="$hesap"

    # Koruma baslatilir
    cekirdek_oturum_koruma_baslat "$kurum" "$hesap" "veri_kaynagi"

    echo "AKTIF" > "$_VERI_DURUM_DOSYASI" 2>/dev/null

    echo "Veri kaynagi ayarlandi: ${kurum}/${hesap}"
}

# -------------------------------------------------------
# veri_kaynagi_goster
# Aktif veri kaynagini ve yedekleri gosterir.
# -------------------------------------------------------
veri_kaynagi_goster() {
    echo ""
    echo "========================================="
    echo "  VERI KAYNAGI DURUMU"
    echo "========================================="

    if [[ -z "$_VERI_KAYNAGI_KURUM" ]]; then
        echo "  Aktif veri kaynagi yok."
        echo "  Baslatmak icin: veri_kaynagi_baslat"
    else
        echo "  Kaynak : ${_VERI_KAYNAGI_KURUM}/${_VERI_KAYNAGI_HESAP}"

        local koruma="PASIF"
        if cekirdek_oturum_koruma_aktif_mi "$_VERI_KAYNAGI_KURUM" "$_VERI_KAYNAGI_HESAP"; then
            koruma="AKTIF"
        fi
        echo "  Koruma : $koruma"
    fi

    if [[ ${#_VERI_KAYNAGI_YEDEKLER[@]} -gt 0 ]]; then
        echo "  Yedekler:"
        local yedek
        for yedek in "${_VERI_KAYNAGI_YEDEKLER[@]}"; do
            echo "    - ${yedek//:/ / }"
        done
    fi

    echo "========================================="
    echo ""
}

# =======================================================
# BOLUM 3: FIYAT VERI CEKME
# =======================================================

# -------------------------------------------------------
# veri_kaynagi_fiyat_al <sembol>
# Sembol icin fiyat verisi getirir (onbellekli).
# stdout: fiyat|tavan|taban|degisim|hacim|seans
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
veri_kaynagi_fiyat_al() {
    local sembol="$1"

    [[ -z "$sembol" ]] && return 1

    # 1. Onbellek kontrolu
    local onbellek
    if onbellek=$(_veri_onbellek_oku "$sembol") && [[ -n "$onbellek" ]]; then
        # Epoch kismi haric dondur
        echo "$onbellek" | cut -d'|' -f2-
        return 0
    fi

    # 2. Veri kaynagi aktif mi?
    if [[ -z "$_VERI_KAYNAGI_KURUM" ]] || [[ -z "$_VERI_KAYNAGI_HESAP" ]]; then
        _cekirdek_log "UYARI: Veri kaynagi aktif degil — $sembol"
        return 1
    fi

    # 3. Veri durum kontrolu
    local durum
    durum=$(cat "$_VERI_DURUM_DOSYASI" 2>/dev/null)
    if [[ "$durum" == "YOK" ]]; then
        return 1
    fi

    # 4. Kurumdan taze fiyat cek
    local surucu="${BORSA_KLASORU}/adaptorler/${_VERI_KAYNAGI_KURUM}.sh"
    if [[ ! -f "$surucu" ]]; then
        _cekirdek_log "HATA: Veri kaynagi surucusu bulunamadi — $_VERI_KAYNAGI_KURUM"
        return 1
    fi

    # Adaptoru yukle (adaptor zaten yuklu olabilir)
    if [[ "${_CEKIRDEK_SON_ADAPTOR:-}" != "$_VERI_KAYNAGI_KURUM" ]]; then
        unset ADAPTOR_ADI ADAPTOR_SURUMU 2>/dev/null || true
        _CEKIRDEK_SON_ADAPTOR="$_VERI_KAYNAGI_KURUM"
        # shellcheck source=/dev/null
        source "$surucu"
    fi

    # Aktif hesabi gecici olarak ayarla
    local onceki_hesap="${_CEKIRDEK_AKTIF_HESAPLAR[$_VERI_KAYNAGI_KURUM]:-}"
    _CEKIRDEK_AKTIF_HESAPLAR["$_VERI_KAYNAGI_KURUM"]="$_VERI_KAYNAGI_HESAP"

    local sonuc=""
    if declare -f adaptor_hisse_bilgi_al > /dev/null 2>&1; then
        sonuc=$(adaptor_hisse_bilgi_al "$sembol" 2>/dev/null)
    fi

    # Aktif hesabi geri yukle
    if [[ -n "$onceki_hesap" ]]; then
        _CEKIRDEK_AKTIF_HESAPLAR["$_VERI_KAYNAGI_KURUM"]="$onceki_hesap"
    fi

    # 5. Basarili mi?
    if [[ -z "$sonuc" ]]; then
        _cekirdek_log "UYARI: Fiyat alinamadi — $sembol (${_VERI_KAYNAGI_KURUM}/${_VERI_KAYNAGI_HESAP})"
        # Failover dene
        _veri_failover
        return 1
    fi

    # Parse: fiyat|tavan|taban|degisim|hacim|seans
    local fiyat tavan taban degisim hacim seans
    IFS='|' read -r fiyat tavan taban degisim hacim seans <<< "$sonuc"

    # 6. Onbellege yaz
    _veri_onbellek_yaz "$sembol" "$fiyat" "$tavan" "$taban" "$degisim" "$hacim" "$seans"

    # 7. Supabase'e kaydet (kalici)
    if declare -f vt_fiyat_kaydet > /dev/null 2>&1; then
        vt_fiyat_kaydet "$sembol" "$fiyat" "$tavan" "$taban" "$degisim" "$hacim" "$seans" \
            "$_VERI_KAYNAGI_KURUM" "$_VERI_KAYNAGI_HESAP" &
    fi

    # Son istek zamanini guncelle
    cekirdek_son_istek_guncelle "$_VERI_KAYNAGI_KURUM" "$_VERI_KAYNAGI_HESAP"

    # 8. Robota dondur
    echo "${fiyat}|${tavan}|${taban}|${degisim}|${hacim}|${seans}"
    return 0
}

# -------------------------------------------------------
# veri_kaynagi_fiyatlar_al <sembol1> [sembol2] ...
# Birden fazla sembol icin toplu fiyat cekimi.
# stdout: her satir SEMBOL\tFIYAT\tTAVAN\tTABAN\tDEGISIM\tHACIM\tSEANS
# -------------------------------------------------------
veri_kaynagi_fiyatlar_al() {
    local sembol
    for sembol in "$@"; do
        local veri
        veri=$(veri_kaynagi_fiyat_al "$sembol" 2>/dev/null)
        if [[ -n "$veri" ]]; then
            local fiyat tavan taban degisim hacim seans
            IFS='|' read -r fiyat tavan taban degisim hacim seans <<< "$veri"
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$sembol" "$fiyat" "$tavan" "$taban" "$degisim" "$hacim" "$seans"
        fi
    done
}

# -------------------------------------------------------
# veri_kaynagi_gecmis_al <sembol> [limit]
# Belirli sembolun gecmis fiyatlarini Supabase'den getirir.
# -------------------------------------------------------
veri_kaynagi_gecmis_al() {
    local sembol="$1"
    local limit="${2:-30}"

    if declare -f vt_fiyat_gecmisi > /dev/null 2>&1; then
        vt_fiyat_gecmisi "$sembol" "$limit"
    else
        echo "Veritabani modulu yuklu degil."
        return 1
    fi
}

# =======================================================
# BOLUM 4: FAILOVER MEKANIZMASI
# =======================================================

# -------------------------------------------------------
# _veri_failover
# Aktif kaynak basarisiz olunca yedek listesinden gecerli olan
# ilk kaynaga otomatik gecer.
# -------------------------------------------------------
_veri_failover() {
    _cekirdek_log "VERI KAYNAGI: Failover baslatiliyor..."

    local eski_kurum="$_VERI_KAYNAGI_KURUM"
    local eski_hesap="$_VERI_KAYNAGI_HESAP"

    local yedek kurum hesap
    for yedek in "${_VERI_KAYNAGI_YEDEKLER[@]}"; do
        IFS=':' read -r kurum hesap <<< "$yedek"

        local surucu="${BORSA_KLASORU}/adaptorler/${kurum}.sh"
        [[ ! -f "$surucu" ]] && continue

        # Adaptoru yukle
        unset ADAPTOR_ADI ADAPTOR_SURUMU 2>/dev/null || true
        _CEKIRDEK_SON_ADAPTOR="$kurum"
        # shellcheck source=/dev/null
        source "$surucu"

        # Oturum gecerli mi?
        if declare -f adaptor_oturum_gecerli_mi > /dev/null 2>&1 && \
           adaptor_oturum_gecerli_mi "$hesap" 2>/dev/null; then

            # Eski koruma durdur
            cekirdek_oturum_koruma_durdur "$eski_kurum" "$eski_hesap" "veri_kaynagi"

            # Yeni kaynagi aktifle
            _VERI_KAYNAGI_KURUM="$kurum"
            _VERI_KAYNAGI_HESAP="$hesap"

            # Yeni koruma baslat
            cekirdek_oturum_koruma_baslat "$kurum" "$hesap" "veri_kaynagi"

            _cekirdek_log "VERI KAYNAGI DEGISTI: ${eski_kurum}/${eski_hesap} -> ${kurum}/${hesap}"
            echo "AKTIF" > "$_VERI_DURUM_DOSYASI" 2>/dev/null
            return 0
        fi
    done

    # Hicbir yedek gecerli degil
    _cekirdek_log "KRITIK: Hicbir veri kaynagi erisilebilir degil!"
    _VERI_KAYNAGI_KURUM=""
    _VERI_KAYNAGI_HESAP=""
    echo "YOK" > "$_VERI_DURUM_DOSYASI" 2>/dev/null
    return 1
}
