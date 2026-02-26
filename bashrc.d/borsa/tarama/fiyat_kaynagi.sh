# shellcheck shell=bash

# Tarama Katmani - Fiyat Kaynagi
# Fiyat kaynaklarini yonetir: kurum secimi, failover, onbellek.
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

# Aktif fiyat kaynagi bilgileri
declare -g _FIYAT_KAYNAGI_KURUM=""
declare -g _FIYAT_KAYNAGI_HESAP=""
declare -ga _FIYAT_KAYNAGI_YEDEKLER=()

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
# BOLUM 2: FIYAT KAYNAGI SECIMI VE YONETIMI
# =======================================================

# -------------------------------------------------------
# fiyat_kaynagi_baslat
# Otomatik fiyat kaynagi secer ve koruma dongusunu baslatir.
# Acik oturumlari tarar, ilk gecerli olanı kaynak yapar.
# -------------------------------------------------------
fiyat_kaynagi_baslat() {
    # Zaten aktif mi?
    if [[ -n "$_FIYAT_KAYNAGI_KURUM" ]] && [[ -n "$_FIYAT_KAYNAGI_HESAP" ]]; then
        echo "Fiyat kaynagi zaten aktif: ${_FIYAT_KAYNAGI_KURUM}/${_FIYAT_KAYNAGI_HESAP}"
        return 0
    fi

    echo "Acik oturumlar taraniyor..."

    local secildi=0
    _FIYAT_KAYNAGI_YEDEKLER=()

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
                        _FIYAT_KAYNAGI_KURUM="$kurum"
                        _FIYAT_KAYNAGI_HESAP="$hesap"
                        secildi=1
                        continue
                    fi
                fi
            fi

            # Yedek listeye ekle
            _FIYAT_KAYNAGI_YEDEKLER+=("${kurum}:${hesap}")
        done
    done

    if [[ "$secildi" -eq 0 ]]; then
        echo "UYARI: Gecerli oturum bulunamadi. Once giris yapin."
        return 1
    fi

    echo "Fiyat kaynagi: ${_FIYAT_KAYNAGI_KURUM}/${_FIYAT_KAYNAGI_HESAP}"

    if [[ ${#_FIYAT_KAYNAGI_YEDEKLER[@]} -gt 0 ]]; then
        echo "Yedekler: ${_FIYAT_KAYNAGI_YEDEKLER[*]}"
    fi

    # Veri durum dosyasina yaz (robotlar okuyabilsin)
    mkdir -p "$(dirname "$_VERI_DURUM_DOSYASI")" 2>/dev/null
    echo "AKTIF" > "$_VERI_DURUM_DOSYASI"

    # Oturum koruma baslatilir (sahip: fiyat_kaynagi)
    cekirdek_oturum_koruma_baslat "$_FIYAT_KAYNAGI_KURUM" "$_FIYAT_KAYNAGI_HESAP" "fiyat_kaynagi"

    echo "Fiyat kaynagi hazir."
    return 0
}

# -------------------------------------------------------
# fiyat_kaynagi_durdur
# Fiyat kaynagi koruma dongusunu durdurur.
# -------------------------------------------------------
fiyat_kaynagi_durdur() {
    if [[ -z "$_FIYAT_KAYNAGI_KURUM" ]]; then
        echo "Aktif fiyat kaynagi yok."
        return 0
    fi

    cekirdek_oturum_koruma_durdur "$_FIYAT_KAYNAGI_KURUM" "$_FIYAT_KAYNAGI_HESAP" "fiyat_kaynagi"

    echo "Fiyat kaynagi durduruldu: ${_FIYAT_KAYNAGI_KURUM}/${_FIYAT_KAYNAGI_HESAP}"

    _FIYAT_KAYNAGI_KURUM=""
    _FIYAT_KAYNAGI_HESAP=""
    _FIYAT_KAYNAGI_YEDEKLER=()

    echo "YOK" > "$_VERI_DURUM_DOSYASI" 2>/dev/null
}

# -------------------------------------------------------
# fiyat_kaynagi_ayarla <kurum> <hesap>
# Manuel fiyat kaynagi secimi. Otomatik secimin onune gecer.
# -------------------------------------------------------
fiyat_kaynagi_ayarla() {
    local kurum="$1"
    local hesap="$2"

    if [[ -z "$kurum" ]] || [[ -z "$hesap" ]]; then
        echo "Kullanim: fiyat_kaynagi_ayarla <kurum> <hesap>"
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
    if [[ -n "$_FIYAT_KAYNAGI_KURUM" ]]; then
        fiyat_kaynagi_durdur
    fi

    _FIYAT_KAYNAGI_KURUM="$kurum"
    _FIYAT_KAYNAGI_HESAP="$hesap"

    # Koruma baslatilir
    cekirdek_oturum_koruma_baslat "$kurum" "$hesap" "fiyat_kaynagi"

    echo "AKTIF" > "$_VERI_DURUM_DOSYASI" 2>/dev/null

    echo "Fiyat kaynagi ayarlandi: ${kurum}/${hesap}"
}

# -------------------------------------------------------
# fiyat_kaynagi_goster
# Aktif fiyat kaynagini ve yedekleri gosterir.
# -------------------------------------------------------
fiyat_kaynagi_goster() {
    echo ""
    echo "========================================="
    echo "  FIYAT KAYNAGI DURUMU"
    echo "========================================="

    if [[ -z "$_FIYAT_KAYNAGI_KURUM" ]]; then
        echo "  Aktif fiyat kaynagi yok."
        echo "  Baslatmak icin: fiyat_kaynagi_baslat"
    else
        echo "  Kaynak : ${_FIYAT_KAYNAGI_KURUM}/${_FIYAT_KAYNAGI_HESAP}"

        local koruma="PASIF"
        if cekirdek_oturum_koruma_aktif_mi "$_FIYAT_KAYNAGI_KURUM" "$_FIYAT_KAYNAGI_HESAP"; then
            koruma="AKTIF"
        fi
        echo "  Koruma : $koruma"
    fi

    if [[ ${#_FIYAT_KAYNAGI_YEDEKLER[@]} -gt 0 ]]; then
        echo "  Yedekler:"
        local yedek
        for yedek in "${_FIYAT_KAYNAGI_YEDEKLER[@]}"; do
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
# fiyat_kaynagi_fiyat_al <sembol>
# Sembol icin fiyat verisi getirir (onbellekli).
# stdout: fiyat|tavan|taban|degisim|hacim|seans
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
fiyat_kaynagi_fiyat_al() {
    local sembol="$1"

    [[ -z "$sembol" ]] && return 1

    # 1. Onbellek kontrolu
    local onbellek
    if onbellek=$(_veri_onbellek_oku "$sembol") && [[ -n "$onbellek" ]]; then
        # Epoch kismi haric dondur
        echo "$onbellek" | cut -d'|' -f2-
        return 0
    fi

    # 2. Fiyat kaynagi aktif mi?
    if [[ -z "$_FIYAT_KAYNAGI_KURUM" ]] || [[ -z "$_FIYAT_KAYNAGI_HESAP" ]]; then
        _cekirdek_log "UYARI: Fiyat kaynagi aktif degil — $sembol"
        return 1
    fi

    # 3. Veri durum kontrolu
    local durum
    durum=$(cat "$_VERI_DURUM_DOSYASI" 2>/dev/null)
    if [[ "$durum" == "YOK" ]]; then
        return 1
    fi

    # 4. Kurumdan taze fiyat cek
    local surucu="${BORSA_KLASORU}/adaptorler/${_FIYAT_KAYNAGI_KURUM}.sh"
    if [[ ! -f "$surucu" ]]; then
        _cekirdek_log "HATA: Fiyat kaynagi surucusu bulunamadi — $_FIYAT_KAYNAGI_KURUM"
        return 1
    fi

    # Adaptoru yukle (adaptor zaten yuklu olabilir)
    if [[ "${_CEKIRDEK_SON_ADAPTOR:-}" != "$_FIYAT_KAYNAGI_KURUM" ]]; then
        unset ADAPTOR_ADI ADAPTOR_SURUMU 2>/dev/null || true
        _CEKIRDEK_SON_ADAPTOR="$_FIYAT_KAYNAGI_KURUM"
        # shellcheck source=/dev/null
        source "$surucu"
    fi

    # Aktif hesabi gecici olarak ayarla
    local onceki_hesap="${_CEKIRDEK_AKTIF_HESAPLAR[$_FIYAT_KAYNAGI_KURUM]:-}"
    _CEKIRDEK_AKTIF_HESAPLAR["$_FIYAT_KAYNAGI_KURUM"]="$_FIYAT_KAYNAGI_HESAP"

    local sonuc=""
    if declare -f adaptor_hisse_bilgi_al > /dev/null 2>&1; then
        sonuc=$(adaptor_hisse_bilgi_al "$sembol" 2>/dev/null)
    fi

    # Aktif hesabi geri yukle
    if [[ -n "$onceki_hesap" ]]; then
        _CEKIRDEK_AKTIF_HESAPLAR["$_FIYAT_KAYNAGI_KURUM"]="$onceki_hesap"
    fi

    # 5. Basarili mi?
    if [[ -z "$sonuc" ]]; then
        _cekirdek_log "UYARI: Fiyat alinamadi — $sembol (${_FIYAT_KAYNAGI_KURUM}/${_FIYAT_KAYNAGI_HESAP})"
        # Failover dene
        _veri_failover
        return 1
    fi

    # Parse: fiyat|tavan|taban|degisim|hacim|seans
    local fiyat tavan taban degisim hacim seans
    IFS='|' read -r fiyat tavan taban degisim hacim seans <<< "$sonuc"

    # 6. Onbellege yaz
    _veri_onbellek_yaz "$sembol" "$fiyat" "$tavan" "$taban" "$degisim" "$hacim" "$seans"

    # 7. Supabase kayit islemi ohlcv tablosu uzerinden yapilir.
    #    Anlik fiyat kaydi ohlcv akisinda (tvdatafeed) zaten yonetiliyor.

    # Son istek zamanini guncelle
    cekirdek_son_istek_guncelle "$_FIYAT_KAYNAGI_KURUM" "$_FIYAT_KAYNAGI_HESAP"

    # 8. Robota dondur
    echo "${fiyat}|${tavan}|${taban}|${degisim}|${hacim}|${seans}"
    return 0
}

# -------------------------------------------------------
# fiyat_kaynagi_fiyatlar_al <sembol1> [sembol2] ...
# Birden fazla sembol icin toplu fiyat cekimi.
# stdout: her satir SEMBOL\tFIYAT\tTAVAN\tTABAN\tDEGISIM\tHACIM\tSEANS
# -------------------------------------------------------
fiyat_kaynagi_fiyatlar_al() {
    local sembol
    for sembol in "$@"; do
        local veri
        veri=$(fiyat_kaynagi_fiyat_al "$sembol" 2>/dev/null)
        if [[ -n "$veri" ]]; then
            local fiyat tavan taban degisim hacim seans
            IFS='|' read -r fiyat tavan taban degisim hacim seans <<< "$veri"
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$sembol" "$fiyat" "$tavan" "$taban" "$degisim" "$hacim" "$seans"
        fi
    done
}

# -------------------------------------------------------
# fiyat_kaynagi_gecmis_al <sembol> [limit] [periyot]
# Belirli sembolun gecmis fiyatlarini ohlcv tablosundan getirir.
# -------------------------------------------------------
fiyat_kaynagi_gecmis_al() {
    local sembol="$1"
    local limit="${2:-30}"
    local periyot="${3:-1G}"

    if declare -f vt_fiyat_gecmisi > /dev/null 2>&1; then
        vt_fiyat_gecmisi "$sembol" "$limit" "$periyot"
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
    _cekirdek_log "FIYAT KAYNAGI: Failover baslatiliyor..."

    local eski_kurum="$_FIYAT_KAYNAGI_KURUM"
    local eski_hesap="$_FIYAT_KAYNAGI_HESAP"

    local yedek kurum hesap
    for yedek in "${_FIYAT_KAYNAGI_YEDEKLER[@]}"; do
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
            cekirdek_oturum_koruma_durdur "$eski_kurum" "$eski_hesap" "fiyat_kaynagi"

            # Yeni kaynagi aktifle
            _FIYAT_KAYNAGI_KURUM="$kurum"
            _FIYAT_KAYNAGI_HESAP="$hesap"

            # Yeni koruma baslat
            cekirdek_oturum_koruma_baslat "$kurum" "$hesap" "fiyat_kaynagi"

            _cekirdek_log "FIYAT KAYNAGI DEGISTI: ${eski_kurum}/${eski_hesap} -> ${kurum}/${hesap}"
            echo "AKTIF" > "$_VERI_DURUM_DOSYASI" 2>/dev/null
            return 0
        fi
    done

    # Hicbir yedek gecerli degil
    _cekirdek_log "KRITIK: Hicbir fiyat kaynagi erisilebilir degil!"
    _FIYAT_KAYNAGI_KURUM=""
    _FIYAT_KAYNAGI_HESAP=""
    echo "YOK" > "$_VERI_DURUM_DOSYASI" 2>/dev/null
    return 1
}

# =======================================================
# BOLUM 5: TAKIP LISTESI PARALEL CEKIM
# Takipteki hisseler icin optimize edilmis REST polling.
# Kisa onbellek (3sn), paralel istekler, mum birlestirici.
# =======================================================

_TAKIP_ONBELLEK_SURESI=3    # saniye — takip listesi icin kisa TTL
_TAKIP_TICK_DIZIN="/tmp/borsa/_wss/tickler"

# -------------------------------------------------------
# _takip_paralel_fiyat_al
# Takip listesindeki tum hisselerin fiyatini paralel ceker.
# Her basarili cekim sonrasi tick dosyasina yazar.
# -------------------------------------------------------
_takip_paralel_fiyat_al() {
    # Takip listesi fonksiyonu tanimli mi?
    if ! declare -f _takip_semboller > /dev/null 2>&1; then
        return 1
    fi

    local semboller
    semboller=$(_takip_semboller 2>/dev/null)
    [[ -z "$semboller" ]] && return 0

    # Fiyat kaynagi aktif mi?
    if [[ -z "$_FIYAT_KAYNAGI_KURUM" ]] || [[ -z "$_FIYAT_KAYNAGI_HESAP" ]]; then
        return 1
    fi

    mkdir -p "$_TAKIP_TICK_DIZIN" 2>/dev/null

    # Paralel cekim: her sembol icin arka plan is parcacigi
    local sembol pids=()
    while IFS= read -r sembol; do
        [[ -z "$sembol" ]] && continue
        (
            # Kisa TTL onbellek kontrolu
            local onbellek_dosya="${_VERI_ONBELLEK_DIZIN}/${sembol}.dat"
            if [[ -f "$onbellek_dosya" ]]; then
                local dosya_zamani
                dosya_zamani=$(stat -c %Y "$onbellek_dosya" 2>/dev/null)
                local simdi
                simdi=$(date +%s)
                local gecen=$(( simdi - dosya_zamani ))
                if [[ "$gecen" -lt "$_TAKIP_ONBELLEK_SURESI" ]]; then
                    exit 0  # Hala taze, atlsa
                fi
            fi

            local veri
            veri=$(fiyat_kaynagi_fiyat_al "$sembol" 2>/dev/null)
            if [[ -n "$veri" ]]; then
                # Tick dosyasina yaz (mum birlestirici icin)
                local fiyat hacim
                fiyat=$(echo "$veri" | cut -d'|' -f1)
                hacim=$(echo "$veri" | cut -d'|' -f5)

                local epoch
                epoch=$(date +%s)
                echo "${epoch}|${fiyat}|${hacim:-0}" \
                    >> "${_TAKIP_TICK_DIZIN}/${sembol}.tick"
            fi
        ) &
        pids+=($!)
    done <<< "$semboller"

    # Tum paralel islemlerin bitmesini bekle
    local pid
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
}

# -------------------------------------------------------
# _takip_polling_dongusu
# Takip listesi icin surekli REST polling dongusu.
# Arka planda calisir.
# PID: /tmp/borsa/_takip/polling.pid
# -------------------------------------------------------
_takip_polling_dongusu() {
    local pid_dosya="${_TAKIP_DIZIN:-/tmp/borsa/_takip}/polling.pid"
    mkdir -p "$(dirname "$pid_dosya")" 2>/dev/null

    # Onceki donguyu durdur
    if [[ -f "$pid_dosya" ]]; then
        local eski_pid
        eski_pid=$(cat "$pid_dosya" 2>/dev/null)
        if [[ -n "$eski_pid" ]] && kill -0 "$eski_pid" 2>/dev/null; then
            kill "$eski_pid" 2>/dev/null
            wait "$eski_pid" 2>/dev/null || true
        fi
    fi

    echo $$ > "$pid_dosya"

    _cekirdek_log "Takip polling dongusu basladi (PID: $$)"

    while true; do
        _takip_paralel_fiyat_al 2>/dev/null || true
        sleep "$_TAKIP_ONBELLEK_SURESI"

        # PID dosyasi silinmisse donguden cik
        [[ ! -f "$pid_dosya" ]] && break
    done

    _cekirdek_log "Takip polling dongusu durdu (PID: $$)"
}

# -------------------------------------------------------
# takip_polling_baslat
# Takip listesi icin arka plan polling dongusunu baslatir.
# -------------------------------------------------------
takip_polling_baslat() {
    if [[ -z "$_FIYAT_KAYNAGI_KURUM" ]]; then
        echo "UYARI: Once fiyat kaynagi baslatilmali: fiyat_kaynagi_baslat"
        return 1
    fi

    _takip_polling_dongusu &
    disown

    local pid_dosya="${_TAKIP_DIZIN:-/tmp/borsa/_takip}/polling.pid"
    echo "Takip polling baslatildi (PID dosyasi: $pid_dosya)"
}

# -------------------------------------------------------
# takip_polling_durdur
# Takip listesi polling dongusunu durdurur.
# -------------------------------------------------------
takip_polling_durdur() {
    local pid_dosya="${_TAKIP_DIZIN:-/tmp/borsa/_takip}/polling.pid"

    if [[ ! -f "$pid_dosya" ]]; then
        echo "Aktif polling dongusu yok."
        return 0
    fi

    local pid
    pid=$(cat "$pid_dosya" 2>/dev/null)
    rm -f "$pid_dosya"

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        echo "Takip polling durduruldu (PID: $pid)"
    else
        echo "Takip polling zaten durmus."
    fi
}
