#!/bin/bash
# shellcheck shell=bash

# Borsa Cekirdek Dosyasi
# Tum borsa adaptorlerini yoneten ana dosya.
# Kullanim: borsa <kurum> <komut> [argumanlar]
# Ornek:    borsa ziraat giris 123456 sifrem
# Ornek:    borsa ziraat bakiye

BORSA_KLASORU="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# BIST kurallar modulunu yukle (fiyat adimi, seans saatleri, limitler)
# shellcheck source=/home/yasar/dotfiles/bashrc.d/borsa/kurallar/bist.sh
source "${BORSA_KLASORU}/kurallar/bist.sh"

_cekirdek_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [cekirdek] $1"
}

# =======================================================
# OTURUM YONETIM ALTYAPISI
# =======================================================
# Tum adaptorler tarafindan ortaklasa kullanilan oturum
# fonksiyonlari. Adaptorler kendi _ziraat_oturum_dizini()
# gibi kopyalarini yazmak zorunda kalmaz.
#
# Dizin konvansiyonu: /tmp/borsa/<kurum>/<hesap_no>/
# Dosya isimleri tum kurumlar icin sabittir:
#   cookies.txt, curl.log, debug_portfolio.html,
#   emir_liste.html, emir_yanit.html, iptal_debug.json

# Oturum dosya isimleri (tum kurumlar icin ortak)
_CEKIRDEK_OTURUM_KOK="/tmp/borsa"
_CEKIRDEK_DOSYA_COOKIE="cookies.txt"
_CEKIRDEK_DOSYA_LOG="curl.log"
_CEKIRDEK_DOSYA_DEBUG="debug_portfolio.html"
_CEKIRDEK_DOSYA_EMIR_LISTE="emir_liste.html"
_CEKIRDEK_DOSYA_EMIR_YANIT="emir_yanit.html"
_CEKIRDEK_DOSYA_IPTAL_DEBUG="iptal_debug.json"

# Aktif hesap bilgisi — associative array: [kurum]=hesap_no
declare -gA _CEKIRDEK_AKTIF_HESAPLAR

# -------------------------------------------------------
# cekirdek_oturum_dizini <kurum> [hesap_no]
# Oturum dizinini dondurur. Yoksa olusturur.
# Parametresiz hesap_no: _CEKIRDEK_AKTIF_HESAPLAR[kurum] kullanilir.
# Donus: stdout'a dizin yolunu yazar, hata=1 (hesap yok)
# -------------------------------------------------------
cekirdek_oturum_dizini() {
    local kurum="$1"
    local hesap="${2:-${_CEKIRDEK_AKTIF_HESAPLAR[$kurum]:-}}"

    if [[ -z "$kurum" ]] || [[ -z "$hesap" ]]; then
        echo ""
        return 1
    fi

    local dizin="${_CEKIRDEK_OTURUM_KOK}/${kurum}/${hesap}"
    mkdir -p "$dizin" 2>/dev/null
    chmod 700 "$dizin" 2>/dev/null || true
    echo "$dizin"
}

# -------------------------------------------------------
# cekirdek_dosya_yolu <kurum> <dosya_adi> [hesap_no]
# Oturum dizini altindaki dosyanin tam yolunu dondurur.
# Ornek: cekirdek_dosya_yolu ziraat cookies.txt
#        -> /tmp/borsa/ziraat/123456/cookies.txt
# -------------------------------------------------------
cekirdek_dosya_yolu() {
    local kurum="$1"
    local dosya_adi="$2"
    local hesap="${3:-${_CEKIRDEK_AKTIF_HESAPLAR[$kurum]:-}}"
    local dizin
    dizin=$(cekirdek_oturum_dizini "$kurum" "$hesap")

    if [[ -z "$dizin" ]]; then
        echo ""
        return 1
    fi

    echo "${dizin}/${dosya_adi}"
}

# -------------------------------------------------------
# cekirdek_aktif_hesap_ayarla <kurum> <hesap_no>
# Kurumun aktif hesabini set eder.
# -------------------------------------------------------
cekirdek_aktif_hesap_ayarla() {
    local kurum="$1"
    local hesap="$2"
    _CEKIRDEK_AKTIF_HESAPLAR["$kurum"]="$hesap"
}

# -------------------------------------------------------
# cekirdek_aktif_hesap_kontrol <kurum>
# Aktif hesap set edilmis mi kontrol eder.
# Set edilmemisse hata mesaji yazdirir.
# Donus: 0=set, 1=set edilmemis
# -------------------------------------------------------
cekirdek_aktif_hesap_kontrol() {
    local kurum="$1"
    if [[ -z "${_CEKIRDEK_AKTIF_HESAPLAR[$kurum]:-}" ]]; then
        echo "HATA: Aktif hesap yok."
        echo "Once giris yapin : borsa $kurum giris <MUSTERI_NO> <PAROLA>"
        echo "Veya hesap secin : borsa $kurum hesap <MUSTERI_NO>"
        return 1
    fi
    return 0
}

# -------------------------------------------------------
# cekirdek_aktif_hesap <kurum>
# Kurumun aktif hesap numarasini dondurur.
# -------------------------------------------------------
cekirdek_aktif_hesap() {
    local kurum="$1"
    echo "${_CEKIRDEK_AKTIF_HESAPLAR[$kurum]:-}"
}

# -------------------------------------------------------
# cekirdek_cookie_guvence <kurum>
# Cookie dosyasinin izinlerini kisitla (chmod 600).
# Dosya yoksa sessizce devam eder.
# -------------------------------------------------------
cekirdek_cookie_guvence() {
    local kurum="$1"
    local cookie_dosyasi
    cookie_dosyasi=$(cekirdek_dosya_yolu "$kurum" "$_CEKIRDEK_DOSYA_COOKIE")
    [[ -f "$cookie_dosyasi" ]] && chmod 600 "$cookie_dosyasi" 2>/dev/null
}

# -------------------------------------------------------
# cekirdek_adaptor_log <kurum> <mesaj>
# Hesap-duyarli loglama. Aktif hesap yoksa genel.log'a yazar.
# -------------------------------------------------------
cekirdek_adaptor_log() {
    local kurum="$1"
    local mesaj="$2"
    local log_dosyasi
    log_dosyasi=$(cekirdek_dosya_yolu "$kurum" "$_CEKIRDEK_DOSYA_LOG")
    if [[ -z "$log_dosyasi" ]]; then
        log_dosyasi="${_CEKIRDEK_OTURUM_KOK}/${kurum}/genel.log"
        mkdir -p "${_CEKIRDEK_OTURUM_KOK}/${kurum}" 2>/dev/null
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$kurum] $mesaj" | tee -a "$log_dosyasi"
}

# -------------------------------------------------------
# cekirdek_hesap <kurum> [hesap_no]
# Varsayilan adaptor_hesap implementasyonu.
# Adaptor kendi adaptor_hesap() tanimlamamissa bu kullanilir.
# Oturum gecerliligini kontrol etmek icin adaptor
# adaptor_oturum_gecerli_mi <hesap_no> callback'i saglamalidir.
# -------------------------------------------------------
cekirdek_hesap() {
    local kurum="$1"
    local musteri_no="$2"
    local oturum_kok="${_CEKIRDEK_OTURUM_KOK}/${kurum}"

    if [[ -z "$musteri_no" ]]; then
        # Parametre yoksa aktif hesabi goster
        local aktif
        aktif="${_CEKIRDEK_AKTIF_HESAPLAR[$kurum]:-}"
        if [[ -z "$aktif" ]]; then
            echo "Aktif hesap yok. Kullanim:"
            echo "  borsa $kurum giris        -> yeni giris yap"
            echo "  borsa $kurum hesap <NO>   -> mevcut oturuma gec"
            echo "  borsa $kurum hesaplar     -> kayitli oturumlari listele"
            return 1
        fi
        echo "Aktif hesap: $aktif"
        local cookie_dosyasi
        cookie_dosyasi=$(cekirdek_dosya_yolu "$kurum" "$_CEKIRDEK_DOSYA_COOKIE")
        if [[ -f "$cookie_dosyasi" ]] && declare -f adaptor_oturum_gecerli_mi > /dev/null && adaptor_oturum_gecerli_mi "$aktif"; then
            echo "Oturum durumu: GECERLI"
        else
            echo "Oturum durumu: GECERSIZ (tekrar giris gerekli)"
        fi
        return 0
    fi

    # Musteri numarasina gecis yap
    local oturum_dizini="${oturum_kok}/${musteri_no}"

    if [[ ! -d "$oturum_dizini" ]]; then
        echo "UYARI: $musteri_no icin kayitli oturum bulunamadi."
        echo "Yeni giris icin: borsa $kurum giris"
        echo "(Giris sirasinda musteri numaraniz otomatik kaydedilir.)"
        return 1
    fi

    cekirdek_aktif_hesap_ayarla "$kurum" "$musteri_no"

    local cookie_yolu="${oturum_dizini}/${_CEKIRDEK_DOSYA_COOKIE}"
    if [[ -f "$cookie_yolu" ]] && declare -f adaptor_oturum_gecerli_mi > /dev/null && adaptor_oturum_gecerli_mi "$musteri_no"; then
        echo "Hesap degistirildi: $musteri_no (oturum gecerli)"
    else
        echo "Hesap degistirildi: $musteri_no (oturum suresi dolmus, tekrar giris gerekli)"
        echo "Giris icin: borsa $kurum giris"
    fi
    return 0
}

# -------------------------------------------------------
# cekirdek_hesaplar <kurum>
# Varsayilan adaptor_hesaplar implementasyonu.
# /tmp/borsa/<kurum>/ altindaki dizinleri tarar.
# -------------------------------------------------------
cekirdek_hesaplar() {
    local kurum="$1"
    local oturum_kok="${_CEKIRDEK_OTURUM_KOK}/${kurum}"

    if [[ ! -d "$oturum_kok" ]]; then
        echo "Kayitli oturum bulunamadi."
        echo "Ilk giris icin: borsa $kurum giris"
        return 0
    fi

    local dizinler
    dizinler=$(find "$oturum_kok" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

    if [[ -z "$dizinler" ]]; then
        echo "Kayitli oturum bulunamadi."
        echo "Ilk giris icin: borsa $kurum giris"
        return 0
    fi

    local aktif="${_CEKIRDEK_AKTIF_HESAPLAR[$kurum]:-}"

    echo ""
    echo "========================================="
    echo " KAYITLI OTURUMLAR ($kurum)"
    echo "========================================="

    local sayac=0
    while IFS= read -r dizin; do
        local no
        no=$(basename "$dizin")
        local durum="GECERSIZ"
        local isaret="  "

        local cookie_yolu="${dizin}/${_CEKIRDEK_DOSYA_COOKIE}"
        if [[ -f "$cookie_yolu" ]]; then
            local dosya_yasi
            dosya_yasi=$(( $(date +%s) - $(stat -c %Y "$cookie_yolu" 2>/dev/null || echo 0) ))
            if [[ "$dosya_yasi" -lt 1800 ]]; then
                durum="MUHTEMELEN GECERLI"
            else
                durum="SURESI DOLMUS OLABILIR"
            fi
        else
            durum="COOKIE YOK"
        fi

        if [[ "$no" == "$aktif" ]]; then
            isaret="->"
            durum="$durum (AKTIF)"
        fi

        printf " %s %-12s  %s\n" "$isaret" "$no" "$durum"
        sayac=$((sayac + 1))
    done <<< "$dizinler"

    echo "========================================="
    echo " Toplam: $sayac oturum"
    echo ""
    echo " Gecis icin : borsa $kurum hesap <NO>"
    echo " Giris icin : borsa $kurum giris"
    echo "========================================="
    echo ""
    return 0
}

# Tum HTTP isteklerinde kullanilan ortak User-Agent sabiti.
# Cloudflare veya TLS gereksinimleri degisirse sadece bu dosya guncellenir.
_CEKIRDEK_USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Merkezi HTTP istek fonksiyonu.
# Tum adaptorler ham curl yerine bu fonksiyonu kullanir.
#
# Ortak seçenekler buradadir (User-Agent, Accept, Sec-Fetch headerleri).
# Cloudflare, yeni TLS gereksinimleri veya bot korumasi degisirse
# YALNIZCA bu fonksiyon guncellenir. Hicbir adaptore dokunulmaz.
#
# Kullanim: cekirdek_istek_at [adaptore-ozgu-curl-parametreleri] <URL>
# Ornek:    cekirdek_istek_at -c "$COOKIE" -b "$COOKIE" "$URL"
# Ornek:    cekirdek_istek_at -w "\nHTTP_CODE:%{http_code}" -c "$COOKIE" "$URL"
cekirdek_istek_at() {
    curl \
        -s \
        -L \
        --compressed \
        -H "User-Agent: $_CEKIRDEK_USER_AGENT" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        -H "Accept-Language: tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7" \
        -H "Accept-Encoding: gzip, deflate, br" \
        -H "Sec-Fetch-Site: same-origin" \
        -H "Sec-Fetch-Mode: navigate" \
        -H "Sec-Fetch-User: ?1" \
        -H "Sec-Fetch-Dest: document" \
        "$@"
}

# Standart portfoy ozeti yazici.
# Tum adaptorler bu fonksiyonu cagirir.
# Kullanim: cekirdek_yazdir_portfoy <kurum_adi> <nakit> <hisse> <toplam>
cekirdek_yazdir_portfoy() {
    local kurum="$1"
    local nakit="$2"
    local hisse="$3"
    local toplam="$4"
    local kurum_buyuk
    kurum_buyuk=$(echo "$kurum" | tr '[:lower:]' '[:upper:]')

    echo ""
    echo "========================================="
    echo "  $kurum_buyuk - PORTFOY OZETI"
    echo "========================================="
    echo " Nakit Bakiye  : $nakit TL"
    echo " Hisse Senedi  : $hisse TL"
    echo "-----------------------------------------"
    echo " TOPLAM VARLIK : $toplam TL"
    echo "========================================="
    echo ""
}

# Standart basarili giris mesaji yazici.
# Kullanim: cekirdek_yazdir_giris_basarili <kurum_adi>
cekirdek_yazdir_giris_basarili() {
    local kurum="$1"
    echo ""
    echo "========================================="
    echo " GIRIS BASARILI: $kurum"
    echo " Cerez dosyasi guncellendi."
    echo "========================================="
    echo ""
}

# -------------------------------------------------------
# SAGLIK KONTROL SISTEMI
# -------------------------------------------------------

# Tek bir degerin sayisal ve dolu olup olmadigini kontrol eder.
# Donus: 0 = gecerli, 1 = gecersiz
# Kullanim: cekirdek_sayi_dogrula "$nakit" "Nakit" "ziraat"
cekirdek_sayi_dogrula() {
    local deger="$1"
    local isim="$2"
    local kurum="$3"

    if [[ -z "$deger" ]]; then
        _cekirdek_log "HATA [$kurum]: '$isim' bos geldi. HTML secici artik calismıyor olabilir."
        return 1
    fi

    # 275.47 veya 185,243.41 formatlarinin ikisini de kabul et
    if [[ ! "$deger" =~ ^[0-9]+(\.[0-9]+)?$ ]] && \
       [[ ! "$deger" =~ ^[0-9]{1,3}(,[0-9]{3})*(\.[0-9]+)?$ ]]; then
        _cekirdek_log "HATA [$kurum]: '$isim' sayisal degil ('$deger'). Site degismis olabilir."
        return 1
    fi

    return 0
}

# Cok katmanli saglik kontrolu.
# Tum adaptorler adaptor_bakiye icinde bu fonksiyonu cagirabilir.
# Katmanlar:
#   1. HTTP kodu kontrolu
#   2. Sayfa boyutu kontrolu
#   3. HTML isaret noktasi (landmark) kontrolu
#   4. Veri kalite kontrolu (sayisal mi?)
#   5. Matematik tutarlilik kontrolu (nakit + hisse ~ toplam)
#
# Kullanim:
#   cekirdek_saglik_kontrol \
#       "$kurum" "$http_kodu" "$sayfa_icerik" "$debug_dosyasi" \
#       "$nakit" "$hisse" "$toplam" \
#       "Portfoy" "Hesap" "Cikis"   # isaret noktalari (varargs)
#
# Donus: 0 = saglikli, 1 = sorun var (debug dosyasina kayit yapilir)
cekirdek_saglik_kontrol() {
    local kurum="$1"
    local http_kodu="$2"
    local sayfa_icerik="$3"
    local debug_dosyasi="$4"
    local nakit="$5"
    local hisse="$6"
    local toplam="$7"
    shift 7
    # Geriye kalan argumanlar HTML isaret noktalari
    local isaret_noktalari=("$@")

    local hata_sayisi=0

    # --- Katman 1: HTTP Kodu ---
    if [[ "$http_kodu" != "200" ]]; then
        _cekirdek_log "SAGLIK [$kurum] K1-HTTP: Beklenen 200, gelen $http_kodu."
        hata_sayisi=$((hata_sayisi + 1))
    fi

    # --- Katman 2: Sayfa Boyutu ---
    local boyut="${#sayfa_icerik}"
    if [[ "$boyut" -lt 5000 ]]; then
        _cekirdek_log "SAGLIK [$kurum] K2-BOYUT: Sayfa cok kucuk ($boyut bayt). Hata sayfasi olabilir."
        hata_sayisi=$((hata_sayisi + 1))
    fi

    # --- Katman 3: HTML Isaret Noktalari ---
    local nokta eksik_sayisi
    eksik_sayisi=0
    for nokta in "${isaret_noktalari[@]}"; do
        if ! echo "$sayfa_icerik" | grep -q "$nokta"; then
            _cekirdek_log "SAGLIK [$kurum] K3-ISARETCI: '$nokta' sayfada bulunamadi."
            eksik_sayisi=$((eksik_sayisi + 1))
        fi
    done
    if [[ "$eksik_sayisi" -gt 0 ]]; then
        hata_sayisi=$((hata_sayisi + 1))
    fi

    # --- Katman 4: Veri Kalite Kontrolu ---
    cekirdek_sayi_dogrula "$nakit"  "Nakit"  "$kurum" || hata_sayisi=$((hata_sayisi + 1))
    cekirdek_sayi_dogrula "$hisse"  "Hisse"  "$kurum" || hata_sayisi=$((hata_sayisi + 1))
    cekirdek_sayi_dogrula "$toplam" "Toplam" "$kurum" || hata_sayisi=$((hata_sayisi + 1))

    # --- Katman 5: Matematik Tutarlilik (nakit + hisse ~ toplam) ---
    # Sayilardaki virgulleri kaldir, bc ile hesapla
    if [[ -n "$nakit" ]] && [[ -n "$hisse" ]] && [[ -n "$toplam" ]]; then
        local nakit_temiz hisse_temiz toplam_temiz hesaplanan fark fark_abs esik
        nakit_temiz="${nakit//,/}"
        hisse_temiz="${hisse//,/}"
        toplam_temiz="${toplam//,/}"
        hesaplanan=$(echo "$nakit_temiz + $hisse_temiz" | bc 2>/dev/null)
        if [[ -n "$hesaplanan" ]]; then
            # Fark mutlak degeri %1'den buyukse uyar
            esik=$(echo "scale=2; $toplam_temiz * 0.01" | bc 2>/dev/null)
            fark=$(echo "$hesaplanan - $toplam_temiz" | bc 2>/dev/null)
            fark_abs=$(echo "if ($fark < 0) -1*$fark else $fark" | bc 2>/dev/null)
            if [[ -n "$fark_abs" ]] && [[ -n "$esik" ]]; then
                if (( $(echo "$fark_abs > $esik" | bc -l 2>/dev/null) )); then
                    _cekirdek_log "SAGLIK [$kurum] K5-MATEMATIK: nakit+hisse=$hesaplanan, toplam=$toplam_temiz. Tutarsizlik tespit edildi."
                    hata_sayisi=$((hata_sayisi + 1))
                fi
            fi
        fi
    fi

    # --- Sonuc ---
    if [[ "$hata_sayisi" -gt 0 ]]; then
        _cekirdek_log "SAGLIK [$kurum]: $hata_sayisi katman basarisiz. Debug: $debug_dosyasi"
        echo "$sayfa_icerik" > "$debug_dosyasi"
        return 1
    fi

    _cekirdek_log "SAGLIK [$kurum]: Tum katmanlar gecti. Veri guvenilir."
    return 0
}

borsa() {
    local kurum="$1"
    local komut="$2"
    shift 2 2>/dev/null

    if [[ -z "$kurum" ]]; then
        echo "Kullanim: borsa <kurum> <komut> [argumanlar]"
        echo "         borsa kurallar [seans|fiyat|pazar|takas]"
        echo "         borsa <kurum> hesap|hesaplar"
        echo ""
        echo "Kurumlar:"
        local surucu
        for surucu in "$BORSA_KLASORU/adaptorler"/*.sh; do
            local ad
            ad=$(basename "$surucu" .sh)
            [[ "$ad" == "sablon" ]] && continue
            echo "  - $ad"
        done
        echo ""
        echo "Komutlar: giris, bakiye, portfoy, emir, emirler, iptal"
        echo "Kurallar: borsa kurallar [seans|fiyat|pazar [PAZAR_KODU]|takas|adim <FIYAT>|tavan <FIYAT>|taban <FIYAT>]"
        return 0
    fi

    # Ozel komut: borsa kurallar — BIST kurallarini goster
    if [[ "$kurum" == "kurallar" ]]; then
        case "$komut" in
            seans)
                bist_seans_bilgi
                ;;
            fiyat)
                bist_fiyat_adimi_bilgi
                ;;
            adim)
                local _f="$1"
                if [[ -z "$_f" ]]; then
                    echo "Kullanim: borsa kurallar adim <FIYAT>"
                    return 1
                fi
                local _a
                _a=$(bist_fiyat_adimi "$_f")
                echo "Fiyat: $_f TL -> Adim: $_a TL"
                bist_fiyat_gecerli_mi "$_f"
                ;;
            pazar)
                bist_pazar_bilgi "$1"
                ;;
            takas)
                bist_takas_bilgi
                ;;
            tavan)
                local _f="$1"
                if [[ -z "$_f" ]]; then
                    echo "Kullanim: borsa kurallar tavan <KAPANIS_FIYATI>"
                    return 1
                fi
                echo "Kapanis: $_f TL -> Tavan: $(bist_tavan_hesapla "$_f") TL"
                ;;
            taban)
                local _f="$1"
                if [[ -z "$_f" ]]; then
                    echo "Kullanim: borsa kurallar taban <KAPANIS_FIYATI>"
                    return 1
                fi
                echo "Kapanis: $_f TL -> Taban: $(bist_taban_hesapla "$_f") TL"
                ;;
            *)
                bist_seans_bilgi
                bist_fiyat_adimi_bilgi
                bist_pazar_bilgi
                bist_takas_bilgi
                ;;
        esac
        return 0
    fi

    local surucu_dosyasi="${BORSA_KLASORU}/adaptorler/${kurum}.sh"

    if [[ ! -f "$surucu_dosyasi" ]]; then
        echo "HATA: '$kurum' surucusu bulunamadi."
        echo "Gecerli kurumlar:"
        local s
        for s in "$BORSA_KLASORU/adaptorler"/*.sh; do
            local n
            n=$(basename "$s" .sh)
            [[ "$n" == "sablon" ]] && continue
            echo "  - $n"
        done
        return 1
    fi

    # shellcheck source=/dev/null
    source "$surucu_dosyasi"

    case "$komut" in
        giris)
            adaptor_giris "$@"
            ;;
        bakiye)
            adaptor_bakiye "$@"
            ;;
        emir)
            adaptor_emir_gonder "$@"
            ;;
        emirler)
            adaptor_emirleri_listele "$@"
            ;;
        iptal)
            adaptor_emir_iptal "$@"
            ;;
        portfoy)
            if declare -f adaptor_portfoy > /dev/null; then
                adaptor_portfoy "$@"
            else
                echo "HATA: '$kurum' surucusu 'portfoy' komutunu desteklemiyor."
                return 1
            fi
            ;;
        hesap)
            if declare -f adaptor_hesap > /dev/null; then
                adaptor_hesap "$@"
            else
                cekirdek_hesap "$kurum" "$@"
            fi
            ;;
        hesaplar)
            if declare -f adaptor_hesaplar > /dev/null; then
                adaptor_hesaplar "$@"
            else
                cekirdek_hesaplar "$kurum" "$@"
            fi
            ;;
        "")
            echo "Kullanim: borsa $kurum <komut>"
            echo "Komutlar: giris, bakiye, portfoy, emir, emirler, iptal, hesap, hesaplar"
            echo "Ayrica:  borsa kurallar [seans|fiyat|pazar|takas|adim|tavan|taban]"
            ;;
        *)
            echo "HATA: Bilinmeyen komut: '$komut'"
            echo "Gecerli komutlar: giris, bakiye, portfoy, emir, emirler, iptal, hesap, hesaplar"
            return 1
            ;;
    esac
}

export -f borsa

# Tab tamamlama (completion) yukleme
# shellcheck source=/home/yasar/dotfiles/bashrc.d/borsa/tamamlama.sh
source "${BORSA_KLASORU}/tamamlama.sh"
