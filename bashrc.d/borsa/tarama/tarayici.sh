# shellcheck shell=bash

# Tarama Katmani - Sembol Tarayici
# Sembol kaynaklarini cozumler: dogrudan, dosya, endeks listesi, portfoy.
# Robot motoru bu fonksiyonlari kullanarak STRATEJI_SEMBOLLER dizisini doldurur.
#
# Yuklenme: cekirdek.sh tarafindan source edilir.

# =======================================================
# YAPILANDIRMA
# =======================================================

_TARAYICI_ENDEKS_DIZIN="${BORSA_KLASORU}/tarama/endeksler"
_TARAYICI_KULLANICI_DIZIN="${HOME}/.config/borsa"

# =======================================================
# BOLUM 1: ANA COZUMLEME FONKSIYONU
# =======================================================

# -------------------------------------------------------
# tarayici_sembolleri_coz <parametreler...>
# Robot baslatma parametrelerini isler ve temiz sembol listesi dondurur.
# stdout: her satirda bir sembol (THYAO, AKBNK, ...).
# Donus: 0 = en az bir sembol bulundu, 1 = hicbir sembol yok.
#
# Desteklenen parametreler:
#   --semboller THYAO,AKBNK,GARAN   (virgul ile ayrilmis)
#   --liste bist30                   (endeksler/ dizininden)
#   --dosya /yol/hisselerim.txt      (her satirda bir sembol)
#   --portfoy                        (hesaptaki pozisyonlardan)
#
# Birden fazla kaynak birlestirilebilir, tekrarlar silinir.
# -------------------------------------------------------
tarayici_sembolleri_coz() {
    local tum_semboller=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --semboller)
                if [[ -z "${2:-}" ]]; then
                    _cekirdek_log "HATA: --semboller parametresi bos."
                    shift
                    continue
                fi
                local dogrudan
                dogrudan=$(_tarayici_dogrudan_parse "$2")
                tum_semboller="${tum_semboller}${dogrudan}"$'\n'
                shift 2
                ;;
            --liste)
                if [[ -z "${2:-}" ]]; then
                    _cekirdek_log "HATA: --liste parametresi bos."
                    shift
                    continue
                fi
                local endeks
                endeks=$(_tarayici_endeks_oku "$2")
                tum_semboller="${tum_semboller}${endeks}"$'\n'
                shift 2
                ;;
            --dosya)
                if [[ -z "${2:-}" ]]; then
                    _cekirdek_log "HATA: --dosya parametresi bos."
                    shift
                    continue
                fi
                local dosya_icerik
                dosya_icerik=$(_tarayici_dosya_oku "$2")
                tum_semboller="${tum_semboller}${dosya_icerik}"$'\n'
                shift 2
                ;;
            --portfoy)
                local portfoy
                portfoy=$(_tarayici_portfoy_oku)
                tum_semboller="${tum_semboller}${portfoy}"$'\n'
                shift
                ;;
            *)
                # Bilinmeyen parametre — atla (motor.sh kendi parametrelerini isle)
                shift
                ;;
        esac
    done

    # Tekrarlari sil ve dogrula
    local sonuc
    sonuc=$(_tarayici_tekrarlari_sil "$tum_semboller")

    if [[ -z "$sonuc" ]]; then
        return 1
    fi

    echo "$sonuc"
    return 0
}

# =======================================================
# BOLUM 2: KAYNAK PARSE FONKSIYONLARI
# =======================================================

# -------------------------------------------------------
# _tarayici_dogrudan_parse <virgul_ayrilmis_semboller>
# --semboller THYAO,AKBNK,GARAN parametresini parse eder.
# Virgul ile ayirir, buyuk harfe cevirir.
# stdout: her satirda bir sembol.
# -------------------------------------------------------
_tarayici_dogrudan_parse() {
    local girdi="$1"

    # Virgul ile ayir
    local sembol
    while IFS=',' read -r sembol; do
        sembol=$(echo "$sembol" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
        [[ -z "$sembol" ]] && continue
        echo "$sembol"
    done <<< "${girdi//,/$'\n'}"
}

# -------------------------------------------------------
# _tarayici_dosya_oku <dosya_yolu>
# Her satirda bir sembol olan metin dosyasini okur.
# Yorum satirlari (#) ve bos satirlar atlanir.
# stdout: her satirda bir sembol.
# -------------------------------------------------------
_tarayici_dosya_oku() {
    local dosya_yolu="$1"

    # ~ genisletme
    dosya_yolu="${dosya_yolu/#\~/$HOME}"

    if [[ ! -f "$dosya_yolu" ]]; then
        _cekirdek_log "HATA: Dosya bulunamadi: $dosya_yolu"
        return 1
    fi

    local satir
    while IFS= read -r satir || [[ -n "$satir" ]]; do
        # Bosluk temizle
        satir=$(echo "$satir" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # Bos satirlari atla
        [[ -z "$satir" ]] && continue
        # Yorum satirlarini atla
        [[ "$satir" == \#* ]] && continue
        # Buyuk harfe cevir
        satir=$(echo "$satir" | tr '[:lower:]' '[:upper:]')
        echo "$satir"
    done < "$dosya_yolu"
}

# -------------------------------------------------------
# _tarayici_endeks_oku <endeks_adi>
# Endeksler dizininden ilgili dosyayi bulur ve okur.
# Once tarama/endeksler/ altinda arar, bulamazsa ~/.config/borsa/ altinda arar.
# stdout: her satirda bir sembol.
# -------------------------------------------------------
_tarayici_endeks_oku() {
    local endeks_adi="$1"

    # .txt uzantisini otomatik ekle (kullanici bist30 veya bist30.txt yazabilir)
    local dosya_adi="$endeks_adi"
    [[ "$dosya_adi" != *.txt ]] && dosya_adi="${dosya_adi}.txt"

    # Once endeksler/ dizininde ara
    local dosya_yolu="${_TARAYICI_ENDEKS_DIZIN}/${dosya_adi}"
    if [[ -f "$dosya_yolu" ]]; then
        _tarayici_dosya_oku "$dosya_yolu"
        return $?
    fi

    # Bulamadiysa kullanici dizininde ara
    dosya_yolu="${_TARAYICI_KULLANICI_DIZIN}/${dosya_adi}"
    if [[ -f "$dosya_yolu" ]]; then
        _tarayici_dosya_oku "$dosya_yolu"
        return $?
    fi

    _cekirdek_log "HATA: Endeks listesi bulunamadi: $endeks_adi"
    _cekirdek_log "  Aranan: ${_TARAYICI_ENDEKS_DIZIN}/${dosya_adi}"
    _cekirdek_log "  Aranan: ${_TARAYICI_KULLANICI_DIZIN}/${dosya_adi}"
    return 1
}

# -------------------------------------------------------
# _tarayici_portfoy_oku
# Aktif hesaptaki portfoy verisinden sembolleri cikarir.
# _BORSA_VERI_SEMBOLLER dizisini kullanir (veri_katmani.sh).
# stdout: her satirda bir sembol.
# -------------------------------------------------------
_tarayici_portfoy_oku() {
    # Portfoy verisi veri katmaninda (_BORSA_VERI_SEMBOLLER) tutuluyor.
    # Eger dizi bos ise adaptor_portfoy cagirmak gerekir.
    if [[ -z "${_BORSA_VERI_SEMBOLLER[*]:-}" ]]; then
        # Aktif kurum ve hesap gerekli
        local kurum=""
        local hesap=""

        # Aktif oturumlardan ilk bulunan kurumu kullan
        local k
        for k in "${!_CEKIRDEK_AKTIF_HESAPLAR[@]}"; do
            if [[ -n "${_CEKIRDEK_AKTIF_HESAPLAR[$k]:-}" ]]; then
                kurum="$k"
                hesap="${_CEKIRDEK_AKTIF_HESAPLAR[$k]}"
                break
            fi
        done

        # Adaptor yuklu ve portfoy fonksiyonu mevcut mu?
        if [[ -n "$kurum" ]] && [[ -n "$hesap" ]]; then
            local surucu="${BORSA_KLASORU}/adaptorler/${kurum}.sh"
            if [[ -f "$surucu" ]]; then
                if [[ "${_CEKIRDEK_SON_ADAPTOR:-}" != "$kurum" ]]; then
                    # shellcheck source=/dev/null
                    source "$surucu"
                    _CEKIRDEK_SON_ADAPTOR="$kurum"
                fi
                _CEKIRDEK_AKTIF_HESAPLAR["$kurum"]="$hesap"

                if declare -f adaptor_portfoy > /dev/null 2>&1; then
                    adaptor_portfoy "$hesap" > /dev/null 2>&1
                fi
            fi
        fi
    fi

    # Sembol listesini dondur
    if [[ -n "${_BORSA_VERI_SEMBOLLER[*]:-}" ]]; then
        local sembol
        for sembol in "${_BORSA_VERI_SEMBOLLER[@]}"; do
            [[ -n "$sembol" ]] && echo "$sembol"
        done
    else
        _cekirdek_log "UYARI: Portfoyden sembol okunamadi. Portfoy bos veya oturum yok."
        return 1
    fi
}

# =======================================================
# BOLUM 3: DOGRULAMA VE YARDIMCI FONKSIYONLAR
# =======================================================

# -------------------------------------------------------
# _tarayici_dogrula <sembol>
# Sembolun gecerli bir BIST koduna benzeyip benzemedigini kontrol eder.
# Kurallar: 1-6 karakter, sadece buyuk harf (A-Z) ve rakam (0-9).
# Donus: 0 = gecerli, 1 = gecersiz.
# -------------------------------------------------------
_tarayici_dogrula() {
    local sembol="$1"

    [[ -z "$sembol" ]] && return 1

    # 1-6 karakter, sadece buyuk harf ve rakam
    if [[ "$sembol" =~ ^[A-Z0-9]{1,6}$ ]]; then
        return 0
    fi

    _cekirdek_log "UYARI: Gecersiz sembol atlandi: $sembol"
    return 1
}

# -------------------------------------------------------
# _tarayici_tekrarlari_sil <sembol_listesi>
# Birden fazla kaynaktan gelen sembolleri birlestirip tekrarlari siler.
# Gecersiz sembolleri filtreler.
# stdout: temiz sembol listesi (her satirda bir sembol).
# -------------------------------------------------------
_tarayici_tekrarlari_sil() {
    local girdi="$1"

    [[ -z "$girdi" ]] && return 0

    local -A goruldu
    local sembol

    while IFS= read -r sembol; do
        # Bosluk temizle
        sembol=$(echo "$sembol" | tr -d '[:space:]')
        [[ -z "$sembol" ]] && continue

        # Buyuk harfe cevir (garanti)
        sembol=$(echo "$sembol" | tr '[:lower:]' '[:upper:]')

        # Dogrulama
        if ! _tarayici_dogrula "$sembol"; then
            continue
        fi

        # Tekrar kontrolu
        if [[ -z "${goruldu[$sembol]:-}" ]]; then
            goruldu["$sembol"]=1
            echo "$sembol"
        fi
    done <<< "$girdi"
}
