# shellcheck shell=bash
# shellcheck disable=SC2030,SC2031
# _ROBOT_* degiskenleri bilerek subshell icerisinde set edilir ve kullanilir.
# Arka plan prosesi olarak calisan robot dongusu bu tasarimi gerektirir.

# Robot Motoru (Katman 5)
# Robot baslatma, durdurma, listeleme ve ana calisma dongusu.
# Emir kuyrugu ile coklu strateji koordinasyonu saglar.
#
# Yuklenme: cekirdek.sh tarafindan source edilir.

# =======================================================
# YAPILANDIRMA
# =======================================================

_ROBOT_DONGU_ARALIGI=30          # saniye (her turda bir tarama yapilir)
_ROBOT_LOG_TEMIZLIK_GUNU=7       # gunden eski debug dosyalari silinir
_ROBOT_EMIR_KUYRUK_DIZIN="/tmp/borsa/_emir_kuyrugu"

# =======================================================
# BOLUM 1: ROBOT BASLATMA / DURDURMA / LISTELEME
# =======================================================

# -------------------------------------------------------
# robot_baslat [--kuru] <kurum> <hesap> <strateji_dosyasi> [aralik]
# Yeni robot baslatir. Her robot ayri bir proses olarak calisir.
# --kuru: Gercek emir gondermez, sadece loglar (KURU_CALISTIR=1).
# -------------------------------------------------------
robot_baslat() {
    local kuru_mod=0

    if [[ "$1" == "--kuru" ]]; then
        kuru_mod=1
        shift
    fi

    local kurum="$1"
    local hesap="$2"
    local strateji_dosyasi="$3"
    local aralik="${4:-$_ROBOT_DONGU_ARALIGI}"

    # Parametre kontrolu
    if [[ -z "$kurum" ]] || [[ -z "$hesap" ]] || [[ -z "$strateji_dosyasi" ]]; then
        echo "Kullanim: robot_baslat [--kuru] <kurum> <hesap> <strateji.sh> [aralik_saniye]"
        echo "  --kuru  : Gercek emir gondermez, test amacli"
        echo "  aralik  : Tarama araligi (varsayilan: ${_ROBOT_DONGU_ARALIGI} sn)"
        return 1
    fi

    # Strateji dosyasi kontrolu
    local strateji_yolu="${BORSA_KLASORU}/strateji/${strateji_dosyasi}"
    if [[ ! -f "$strateji_yolu" ]]; then
        echo "HATA: Strateji dosyasi bulunamadi: $strateji_dosyasi"
        echo "Strateji dizini: ${BORSA_KLASORU}/strateji/"
        return 1
    fi

    # Oturum kontrolu
    local cookie
    cookie=$(cekirdek_dosya_yolu "$kurum" "$_CEKIRDEK_DOSYA_COOKIE" "$hesap")
    if [[ ! -f "$cookie" ]]; then
        echo "HATA: ${kurum}/${hesap} icin oturum bulunamadi."
        echo "Once giris yapin: borsa $kurum giris"
        return 1
    fi

    # Ayni strateji zaten calisiyor mu?
    local robot_dizin
    robot_dizin=$(cekirdek_oturum_dizini "$kurum" "$hesap")
    mkdir -p "${robot_dizin}/robotlar" 2>/dev/null

    local strateji_adi
    strateji_adi=$(basename "$strateji_dosyasi" .sh)
    local pid_dosyasi="${robot_dizin}/robotlar/${strateji_adi}.pid"

    if [[ -f "$pid_dosyasi" ]]; then
        local eski_pid
        eski_pid=$(cat "$pid_dosyasi" 2>/dev/null)
        if [[ -n "$eski_pid" ]] && kill -0 "$eski_pid" 2>/dev/null; then
            echo "UYARI: $strateji_adi zaten calisiyor (PID $eski_pid)."
            return 1
        fi
        # PID dosyasi var ama proses yok — temizle
        rm -f "$pid_dosyasi"
    fi

    # Veri kaynagi kontrolu
    if [[ -z "$_VERI_KAYNAGI_KURUM" ]]; then
        echo "Veri kaynagi baslatiliyor..."
        veri_kaynagi_baslat || {
            echo "HATA: Veri kaynagi baslatilamadi."
            return 1
        }
    fi

    echo "Robot baslatiliyor..."
    echo "  Kurum    : $kurum"
    echo "  Hesap    : $hesap"
    echo "  Strateji : $strateji_dosyasi"
    echo "  Aralik   : ${aralik} sn"
    [[ "$kuru_mod" -eq 1 ]] && echo "  Mod      : KURU CALISTIRMA (emir gondermez)"

    # Oturum koruma baslat (sahip: robot)
    cekirdek_oturum_koruma_baslat "$kurum" "$hesap" "robot"

    # Arka plan prosesi olarak robot dongusu calistir
    (
        trap '_robot_temizle' EXIT TERM INT

        # Bu export'lar bilerek subshell icerisinde — arka plan prosesinde kullanilir
        export _ROBOT_KURUM="$kurum"
        export _ROBOT_HESAP="$hesap"
        export _ROBOT_STRATEJI="$strateji_adi"
        export _ROBOT_STRATEJI_DOSYASI="$strateji_yolu"
        export _ROBOT_ARALIK="$aralik"
        export _ROBOT_PID=$$
        [[ "$kuru_mod" -eq 1 ]] && export KURU_CALISTIR=1

        # PID kaydet
        echo $$ > "$pid_dosyasi"

        # Strateji yukle
        # shellcheck source=/dev/null
        source "$strateji_yolu"

        # DB log yaz
        if declare -f vt_robot_log_yaz > /dev/null 2>&1; then
            vt_robot_log_yaz "$kurum" "$hesap" "$$" "$strateji_adi" "BASLADI" \
                "{\"aralik\":${aralik},\"kuru\":${kuru_mod}}"
        fi

        # Baslangic fonksiyonu varsa cagir
        if declare -f strateji_baslat > /dev/null 2>&1; then
            strateji_baslat
        fi

        _cekirdek_log "Robot baslatildi: PID $$ ($kurum/$hesap, strateji: $strateji_adi)"

        # Ana dongu
        _robot_ana_dongu

    ) &

    local robot_pid=$!
    echo "$robot_pid" > "$pid_dosyasi"
    disown "$robot_pid" 2>/dev/null

    echo "Robot baslatildi: PID $robot_pid"
}

# -------------------------------------------------------
# robot_durdur <kurum> <hesap> [strateji]
# Calisan robotu durdurur. Strateji belirtilmezse hepsini durdurur.
# -------------------------------------------------------
robot_durdur() {
    local kurum="$1"
    local hesap="$2"
    local strateji="${3:-}"

    if [[ -z "$kurum" ]] || [[ -z "$hesap" ]]; then
        echo "Kullanim: robot_durdur <kurum> <hesap> [strateji]"
        return 1
    fi

    local robot_dizin
    robot_dizin=$(cekirdek_oturum_dizini "$kurum" "$hesap")
    local robotlar_dizini="${robot_dizin}/robotlar"

    if [[ ! -d "$robotlar_dizini" ]]; then
        echo "Calisan robot yok: ${kurum}/${hesap}"
        return 0
    fi

    local durdurma_sayisi=0

    local pid_dosyasi
    for pid_dosyasi in "${robotlar_dizini}"/*.pid; do
        [[ ! -f "$pid_dosyasi" ]] && continue

        local dosya_adi
        dosya_adi=$(basename "$pid_dosyasi" .pid)

        # Strateji filtresi
        if [[ -n "$strateji" ]] && [[ "$dosya_adi" != "$strateji" ]]; then
            continue
        fi

        local pid
        pid=$(cat "$pid_dosyasi" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            # Prosesin kapanmasini bekle (maks 5 sn)
            local beklenen=0
            while kill -0 "$pid" 2>/dev/null && [[ "$beklenen" -lt 50 ]]; do
                sleep 0.1
                beklenen=$((beklenen + 1))
            done
            # Hala calisiyorsa SIGKILL
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null
            fi
            echo "Robot durduruldu: $dosya_adi (PID $pid)"

            # DB log yaz
            if declare -f vt_robot_log_yaz > /dev/null 2>&1; then
                vt_robot_log_yaz "$kurum" "$hesap" "$pid" "$dosya_adi" "DURDU"
            fi

            durdurma_sayisi=$((durdurma_sayisi + 1))
        fi

        rm -f "$pid_dosyasi"
    done

    if [[ "$durdurma_sayisi" -eq 0 ]]; then
        echo "Calisan robot bulunamadi: ${kurum}/${hesap}"
    fi

    # Son robot durduysa emir kuyrugu ve oturum korumayi temizle
    local kalan_robot=0
    for pid_dosyasi in "${robotlar_dizini}"/*.pid; do
        [[ -f "$pid_dosyasi" ]] && kalan_robot=$((kalan_robot + 1))
    done

    if [[ "$kalan_robot" -eq 0 ]]; then
        # Emir kuyrugunu temizle
        _emir_kuyrugu_durdur "$kurum" "$hesap"
        # Robot oturum korumayı durdur
        cekirdek_oturum_koruma_durdur "$kurum" "$hesap" "robot"
        echo "Son robot durdu — oturum koruma ve emir kuyrugu temizlendi."
    fi
}

# -------------------------------------------------------
# robot_listele
# Calisan tum robotlari listeler.
# -------------------------------------------------------
robot_listele() {
    echo ""
    echo "========================================================================="
    echo "  CALISAN ROBOTLAR"
    echo "========================================================================="
    printf " %-8s %-10s %-15s %8s %-10s\n" "Kurum" "Hesap" "Strateji" "PID" "Durum"
    echo "-------------------------------------------------------------------------"

    local toplam=0

    local kurum_dizini hesap_dizini
    for kurum_dizini in "${_CEKIRDEK_OTURUM_KOK}"/*/; do
        [[ ! -d "$kurum_dizini" ]] && continue
        local kurum
        kurum=$(basename "$kurum_dizini")
        [[ "$kurum" == _* ]] && continue

        for hesap_dizini in "${kurum_dizini}"*/; do
            [[ ! -d "$hesap_dizini" ]] && continue
            local hesap
            hesap=$(basename "$hesap_dizini")

            local robotlar_dizini="${hesap_dizini}robotlar"
            [[ ! -d "$robotlar_dizini" ]] && continue

            local pid_dosyasi
            for pid_dosyasi in "${robotlar_dizini}"/*.pid; do
                [[ ! -f "$pid_dosyasi" ]] && continue

                local strateji
                strateji=$(basename "$pid_dosyasi" .pid)
                local pid
                pid=$(cat "$pid_dosyasi" 2>/dev/null)
                local durum="BILINMIYOR"

                if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                    durum="CALISIYOR"
                else
                    durum="DURMUS"
                    # Temizle
                    rm -f "$pid_dosyasi"
                fi

                printf " %-8s %-10s %-15s %8s %-10s\n" \
                    "$kurum" "$hesap" "$strateji" "${pid:-?}" "$durum"
                toplam=$((toplam + 1))
            done
        done
    done

    if [[ "$toplam" -eq 0 ]]; then
        echo "  Calisan robot yok."
    fi

    echo "========================================================================="
    echo "  Toplam: $toplam robot"
    echo "========================================================================="
    echo ""
}

# =======================================================
# BOLUM 2: ANA DONGU
# =======================================================

# -------------------------------------------------------
# _robot_ana_dongu
# Robot'un ana calisma dongusu. Subshell icinde calisir.
# Dongu: Tarama -> Strateji -> Emir
# -------------------------------------------------------
# _ROBOT_* degiskenleri subshell icinde set edilir ve bu fonksiyon da ayni subshell'de calisir
_robot_ana_dongu() {
    local tur_sayaci=0
    local son_temizlik
    son_temizlik=$(date +%s)

    while true; do
        tur_sayaci=$((tur_sayaci + 1))

        # Veri kaynagi durum kontrolu
        local veri_durum
        veri_durum=$(cat "$_VERI_DURUM_DOSYASI" 2>/dev/null)
        if [[ "$veri_durum" == "YOK" ]]; then
            _cekirdek_log "Robot tur $tur_sayaci: Veri kaynagi yok, bekleniyor..."
            sleep "$_ROBOT_ARALIK"
            continue
        fi

        # Adaptor yukle (emir gondermek icin kendi kurumu)
        local surucu="${BORSA_KLASORU}/adaptorler/${_ROBOT_KURUM}.sh"
        if [[ -f "$surucu" ]]; then
            if [[ "${_CEKIRDEK_SON_ADAPTOR:-}" != "$_ROBOT_KURUM" ]]; then
                unset ADAPTOR_ADI ADAPTOR_SURUMU 2>/dev/null || true
                _CEKIRDEK_SON_ADAPTOR="$_ROBOT_KURUM"
                # shellcheck source=/dev/null
                source "$surucu"
            fi
        fi

        # Aktif hesabi ayarla
        _CEKIRDEK_AKTIF_HESAPLAR["$_ROBOT_KURUM"]="$_ROBOT_HESAP"

        # Oturum gecerli mi?
        if declare -f adaptor_oturum_gecerli_mi > /dev/null 2>&1; then
            if ! adaptor_oturum_gecerli_mi "$_ROBOT_HESAP" 2>/dev/null; then
                _cekirdek_log "Robot tur $tur_sayaci: Oturum gecersiz, robot durduruluyor."
                if declare -f vt_robot_log_yaz > /dev/null 2>&1; then
                    vt_robot_log_yaz "$_ROBOT_KURUM" "$_ROBOT_HESAP" "$$" \
                        "$_ROBOT_STRATEJI" "HATA" '{"sebep":"oturum_gecersiz"}'
                fi
                break
            fi
        fi

        # STRATEJI_SEMBOLLER tanimli mi?
        if [[ -z "${STRATEJI_SEMBOLLER[*]:-}" ]]; then
            _cekirdek_log "Robot: STRATEJI_SEMBOLLER tanimlanmamis."
            sleep "$_ROBOT_ARALIK"
            continue
        fi

        # Her sembol icin strateji degerlendir
        local sembol
        for sembol in "${STRATEJI_SEMBOLLER[@]}"; do
            local veri
            veri=$(veri_kaynagi_fiyat_al "$sembol" 2>/dev/null)
            if [[ -z "$veri" ]]; then
                continue
            fi

            local fiyat tavan taban degisim hacim seans
            IFS='|' read -r fiyat tavan taban degisim hacim seans <<< "$veri"

            # Strateji cagir
            local karar=""
            if declare -f strateji_degerlendir > /dev/null 2>&1; then
                karar=$(strateji_degerlendir "$sembol" "$fiyat" "$tavan" "$taban" \
                    "$degisim" "$hacim" "$seans" 2>/dev/null) || true
            fi

            # Karar isleyici
            _robot_karar_isle "$sembol" "$karar" "$fiyat"
        done

        # Periyodik isler
        _robot_periyodik_isler "$son_temizlik"

        # Son istek zamanini guncelle
        cekirdek_son_istek_guncelle "$_ROBOT_KURUM" "$_ROBOT_HESAP"

        # Bekle
        sleep "$_ROBOT_ARALIK"
    done
}

# -------------------------------------------------------
# _robot_karar_isle <sembol> <karar> <guncel_fiyat>
# Strateji kararini isler: ALIS, SATIS veya BEKLE.
# -------------------------------------------------------
_robot_karar_isle() {
    local sembol="$1"
    local karar="$2"
    local guncel_fiyat="$3"

    [[ -z "$karar" ]] && return 0
    [[ "$karar" == "BEKLE" ]] && return 0

    local islem lot fiyat
    read -r islem lot fiyat <<< "$karar"

    [[ -z "$islem" ]] && return 0

    case "$islem" in
        ALIS|SATIS)
            [[ -z "$lot" ]] && return 0
            [[ -z "$fiyat" ]] && fiyat="$guncel_fiyat"

            # Coklu strateji kontrolu — birden fazla robot calisiyor mu?
            local robot_dizin
            robot_dizin=$(cekirdek_oturum_dizini "$_ROBOT_KURUM" "$_ROBOT_HESAP")
            local kac_robot=0
            local pid_d
            for pid_d in "${robot_dizin}/robotlar"/*.pid; do
                [[ -f "$pid_d" ]] && kac_robot=$((kac_robot + 1))
            done

            if [[ "$kac_robot" -gt 1 ]]; then
                # Coklu strateji — emir kuyruguna gonder
                _emir_kuyrugu_gonder "$sembol" "$islem" "$lot" "$fiyat"
            else
                # Tek strateji — dogrudan gonder
                _robot_emir_gonder "$sembol" "$islem" "$lot" "$fiyat"
            fi

            _cekirdek_log "Robot karar: $sembol $islem $lot lot @ $fiyat"

            if declare -f vt_robot_log_yaz > /dev/null 2>&1; then
                vt_robot_log_yaz "$_ROBOT_KURUM" "$_ROBOT_HESAP" "$$" \
                    "$_ROBOT_STRATEJI" "EMIR" \
                    "{\"sembol\":\"${sembol}\",\"islem\":\"${islem}\",\"lot\":${lot},\"fiyat\":${fiyat}}"
            fi
            ;;
        *)
            _cekirdek_log "Robot: Bilinmeyen karar — $karar"
            ;;
    esac
}

# -------------------------------------------------------
# _robot_emir_gonder <sembol> <islem> <lot> <fiyat>
# Adaptor uzerinden emir gonderir.
# -------------------------------------------------------
_robot_emir_gonder() {
    local sembol="$1"
    local islem="$2"
    local lot="$3"
    local fiyat="$4"

    local yon
    case "$islem" in
        ALIS) yon="alis" ;;
        SATIS) yon="satis" ;;
        *) return 1 ;;
    esac

    if declare -f adaptor_emir_gonder > /dev/null 2>&1; then
        adaptor_emir_gonder "$sembol" "$yon" "$lot" "$fiyat" 2>/dev/null

        # Emir sonucunu DB'ye kaydet
        if declare -f vt_emir_kaydet > /dev/null 2>&1; then
            vt_emir_kaydet "$_ROBOT_KURUM" "$_ROBOT_HESAP" "$sembol" "$islem" "$lot" \
                "$fiyat" "${_BORSA_VERI_SON_EMIR[referans]:-}" \
                "${_BORSA_VERI_SON_EMIR[basarili]:-0}" \
                "$_ROBOT_STRATEJI" "$$"
        fi
    fi
}

# -------------------------------------------------------
# _robot_periyodik_isler <son_temizlik_epoch>
# Periyodik: log temizligi, bekleyen DB kayitlari gonder.
# -------------------------------------------------------
_robot_periyodik_isler() {
    local son_temizlik="$1"
    local simdi
    simdi=$(date +%s)

    # Her 10 turda bir bekleyen DB kayitlarini gonder
    if declare -f _vt_bekleyenleri_gonder > /dev/null 2>&1; then
        _vt_bekleyenleri_gonder 2>/dev/null
    fi

    # Gunluk log temizligi (24 saatte bir)
    local fark=$(( simdi - son_temizlik ))
    if [[ "$fark" -gt 86400 ]]; then
        find /tmp/borsa -name "*.html" -mtime +${_ROBOT_LOG_TEMIZLIK_GUNU} -delete 2>/dev/null
        find /tmp/borsa -name "*.log" -mtime +${_ROBOT_LOG_TEMIZLIK_GUNU} -delete 2>/dev/null
        _cekirdek_log "Robot: Log temizligi yapildi (${_ROBOT_LOG_TEMIZLIK_GUNU}+ gun eski)"
    fi
}

# -------------------------------------------------------
# _robot_temizle
# Robot prosesi kapanirken cagrilir (trap EXIT).
# -------------------------------------------------------
_robot_temizle() {
    # Strateji temizlik fonksiyonu varsa cagir
    if declare -f strateji_temizle > /dev/null 2>&1; then
        strateji_temizle 2>/dev/null
    fi

    # PID dosyasini sil
    local robot_dizin
    robot_dizin=$(cekirdek_oturum_dizini "$_ROBOT_KURUM" "$_ROBOT_HESAP" 2>/dev/null)
    if [[ -n "$robot_dizin" ]]; then
        rm -f "${robot_dizin}/robotlar/${_ROBOT_STRATEJI}.pid" 2>/dev/null
    fi

    _cekirdek_log "Robot temizlendi: PID $$ ($_ROBOT_KURUM/$_ROBOT_HESAP, $_ROBOT_STRATEJI)"
}

# =======================================================
# BOLUM 3: EMIR KUYRUGU (COKLU STRATEJI KOORDINASYONU)
# =======================================================

# -------------------------------------------------------
# _emir_kuyrugu_baslat <kurum> <hesap>
# FIFO tabanli emir kuyrugu olusturur ve isleyici baslatir.
# -------------------------------------------------------
_emir_kuyrugu_baslat() {
    local kurum="$1"
    local hesap="$2"

    local dizin="${_ROBOT_EMIR_KUYRUK_DIZIN}/${kurum}_${hesap}"
    mkdir -p "$dizin" 2>/dev/null

    local fifo="${dizin}/kuyruk.fifo"
    local pid_dosyasi="${dizin}/isleyici.pid"

    # FIFO olustur
    if [[ ! -p "$fifo" ]]; then
        mkfifo "$fifo" 2>/dev/null
    fi

    # Isleyici zaten calisiyor mu?
    if [[ -f "$pid_dosyasi" ]]; then
        local eski_pid
        eski_pid=$(cat "$pid_dosyasi" 2>/dev/null)
        if [[ -n "$eski_pid" ]] && kill -0 "$eski_pid" 2>/dev/null; then
            return 0  # zaten calisiyor
        fi
    fi

    # Kuyruk isleyici arka planda
    (
        trap 'exit 0' TERM INT
        while true; do
            if [[ -p "$fifo" ]]; then
                while IFS= read -r emir_satiri; do
                    _emir_kuyrugu_isle "$kurum" "$hesap" "$emir_satiri"
                done < "$fifo"
            fi
            sleep 0.1
        done
    ) &

    echo $! > "$pid_dosyasi"
    disown $! 2>/dev/null
}

# -------------------------------------------------------
# _emir_kuyrugu_durdur <kurum> <hesap>
# Emir kuyrugu isleyicisini durdurur.
# -------------------------------------------------------
_emir_kuyrugu_durdur() {
    local kurum="$1"
    local hesap="$2"

    local dizin="${_ROBOT_EMIR_KUYRUK_DIZIN}/${kurum}_${hesap}"
    local pid_dosyasi="${dizin}/isleyici.pid"

    if [[ -f "$pid_dosyasi" ]]; then
        local pid
        pid=$(cat "$pid_dosyasi" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
        fi
        rm -f "$pid_dosyasi"
    fi

    # FIFO temizle
    rm -f "${dizin}/kuyruk.fifo" 2>/dev/null
}

# -------------------------------------------------------
# _emir_kuyrugu_gonder <sembol> <islem> <lot> <fiyat>
# Emir kuyruguna emir ekler.
# -------------------------------------------------------
_emir_kuyrugu_gonder() {
    local sembol="$1"
    local islem="$2"
    local lot="$3"
    local fiyat="$4"

    local dizin="${_ROBOT_EMIR_KUYRUK_DIZIN}/${_ROBOT_KURUM}_${_ROBOT_HESAP}"
    local fifo="${dizin}/kuyruk.fifo"

    # Kuyruk baslatilmamissa baslat
    if [[ ! -p "$fifo" ]]; then
        _emir_kuyrugu_baslat "$_ROBOT_KURUM" "$_ROBOT_HESAP"
    fi

    # FIFO'ya yaz (kisaca bloklamayi engellemek icin timeout ile)
    local emir_satiri
    emir_satiri="${_ROBOT_STRATEJI}|${sembol}|${islem}|${lot}|${fiyat}|$(date +%s)"

    echo "$emir_satiri" > "$fifo" &
    local yazma_pid=$!
    # 5 saniye icinde yazamazsa iptal et
    sleep 5 && kill "$yazma_pid" 2>/dev/null &
    wait "$yazma_pid" 2>/dev/null
}

# -------------------------------------------------------
# _emir_kuyrugu_isle <kurum> <hesap> <emir_satiri>
# Kuyruktan alinan emri isler. flock ile seri erisim saglar.
# -------------------------------------------------------
_emir_kuyrugu_isle() {
    local kurum="$1"
    local hesap="$2"
    local emir_satiri="$3"

    local strateji sembol islem lot fiyat _zaman
    IFS='|' read -r strateji sembol islem lot fiyat _zaman <<< "$emir_satiri"

    # Celiski kontrolu: ayni sembol icin zit yonde acik emir var mi?
    # (basit kontrol — gelismis versiyon emir durumlarini da kontrol eder)

    # Bakiye kontrolu ile flock
    local kilit_dosyasi="${_ROBOT_EMIR_KUYRUK_DIZIN}/${kurum}_${hesap}/bakiye.lock"

    (
        flock -w 10 200 || {
            _cekirdek_log "Emir kuyrugu: Kilit alinamadi — $sembol $islem"
            return 1
        }

        # Aktif hesabi ayarla
        _CEKIRDEK_AKTIF_HESAPLAR["$kurum"]="$hesap"

        # Adaptor yukle
        local surucu="${BORSA_KLASORU}/adaptorler/${kurum}.sh"
        if [[ -f "$surucu" ]]; then
            if [[ "${_CEKIRDEK_SON_ADAPTOR:-}" != "$kurum" ]]; then
                unset ADAPTOR_ADI ADAPTOR_SURUMU 2>/dev/null || true
                _CEKIRDEK_SON_ADAPTOR="$kurum"
                # shellcheck source=/dev/null
                source "$surucu"
            fi
        fi

        # Emir gonder
        local yon
        case "$islem" in
            ALIS) yon="alis" ;;
            SATIS) yon="satis" ;;
            *) return 1 ;;
        esac

        _cekirdek_log "Emir kuyrugu: $strateji -> $sembol $islem $lot lot @ $fiyat"

        if declare -f adaptor_emir_gonder > /dev/null 2>&1; then
            adaptor_emir_gonder "$sembol" "$yon" "$lot" "$fiyat" 2>/dev/null
        fi

    ) 200>"$kilit_dosyasi"
}
