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

# Veri katmani yukle (global veri yapilari + yardimci fonksiyonlar)
# shellcheck source=/home/yasar/dotfiles/bashrc.d/borsa/veri_katmani.sh
source "${BORSA_KLASORU}/veri_katmani.sh"

# Veritabani katmanini yukle (Supabase erisim fonksiyonlari)
if [[ -f "${BORSA_KLASORU}/veritabani/supabase.sh" ]]; then
    # shellcheck source=/dev/null
    source "${BORSA_KLASORU}/veritabani/supabase.sh"
fi

# Tarama katmanini yukle (veri kaynagi yonetimi)
if [[ -f "${BORSA_KLASORU}/tarama/veri_kaynagi.sh" ]]; then
    # shellcheck source=/dev/null
    source "${BORSA_KLASORU}/tarama/veri_kaynagi.sh"
fi

# Robot motoru yukle
if [[ -f "${BORSA_KLASORU}/robot/motor.sh" ]]; then
    # shellcheck source=/dev/null
    source "${BORSA_KLASORU}/robot/motor.sh"
fi

# =======================================================
# OTURUM SURESI TAKIBI VE KORUMA DONGUSU
# =======================================================
# Adaptor giris sirasinda oturum suresini parse eder ve
# cekirdek_oturum_suresi_kaydet ile kaydeder.
# Robot motoru veya -o parametresi koruma dongusunu baslatir.
# Dongu periyodik olarak sessiz istek atarak oturumu canli tutar.

# Oturum zaman bilgileri — associative array: [kurum:hesap]=epoch
declare -gA _CEKIRDEK_OTURUM_SURELERI       # timeout suresi (saniye)
declare -gA _CEKIRDEK_OTURUM_SON_ISTEK       # son istek epoch zamani

# -------------------------------------------------------
# cekirdek_oturum_suresi_kaydet <kurum> <hesap> <sure_saniye>
# Adaptor giris sirasinda parse edilen timeout degerini saklar.
# Ayrica diske de yazar (robot prosesleri okuyabilsin).
# -------------------------------------------------------
cekirdek_oturum_suresi_kaydet() {
    local kurum="$1"
    local hesap="$2"
    local sure="$3"

    _CEKIRDEK_OTURUM_SURELERI["${kurum}:${hesap}"]="$sure"
    local dizin
    dizin=$(cekirdek_oturum_dizini "$kurum" "$hesap")
    [[ -n "$dizin" ]] && echo "$sure" > "${dizin}/oturum_suresi"
}

# -------------------------------------------------------
# cekirdek_son_istek_guncelle <kurum> <hesap>
# Son basarili istek zamanini gunceller.
# -------------------------------------------------------
cekirdek_son_istek_guncelle() {
    local kurum="$1"
    local hesap="$2"
    local simdi
    simdi=$(date +%s)

    _CEKIRDEK_OTURUM_SON_ISTEK["${kurum}:${hesap}"]="$simdi"
    local dizin
    dizin=$(cekirdek_oturum_dizini "$kurum" "$hesap")
    [[ -n "$dizin" ]] && echo "$simdi" > "${dizin}/son_istek"
}

# -------------------------------------------------------
# cekirdek_oturum_kalan <kurum> <hesap>
# Kalan oturum suresini saniye olarak dondurur.
# stdout: kalan saniye (negatifse oturum dusmus demek)
# -------------------------------------------------------
cekirdek_oturum_kalan() {
    local kurum="$1"
    local hesap="$2"
    local anahtar="${kurum}:${hesap}"

    local sure="${_CEKIRDEK_OTURUM_SURELERI[$anahtar]:-}"
    local son_istek="${_CEKIRDEK_OTURUM_SON_ISTEK[$anahtar]:-}"

    # Bellekte yoksa diskten oku
    if [[ -z "$sure" ]] || [[ -z "$son_istek" ]]; then
        local dizin
        dizin=$(cekirdek_oturum_dizini "$kurum" "$hesap")
        [[ -z "$dizin" ]] && echo "0" && return 1

        [[ -z "$sure" ]] && [[ -f "${dizin}/oturum_suresi" ]] && \
            sure=$(cat "${dizin}/oturum_suresi" 2>/dev/null)
        [[ -z "$son_istek" ]] && [[ -f "${dizin}/son_istek" ]] && \
            son_istek=$(cat "${dizin}/son_istek" 2>/dev/null)
    fi

    [[ -z "$sure" ]] && echo "0" && return 1
    [[ -z "$son_istek" ]] && echo "$sure" && return 0

    local simdi
    simdi=$(date +%s)
    local gecen=$(( simdi - son_istek ))
    local kalan=$(( sure - gecen ))
    echo "$kalan"
}

# -------------------------------------------------------
# cekirdek_oturum_koruma_baslat <kurum> <hesap> <sahip>
# Arka planda oturum koruma dongusunu baslatir.
# sahip: "giris" veya "robot" — durdurma yetkisi icin.
# -------------------------------------------------------
cekirdek_oturum_koruma_baslat() {
    local kurum="$1"
    local hesap="$2"
    local sahip="${3:-giris}"

    local dizin
    dizin=$(cekirdek_oturum_dizini "$kurum" "$hesap")
    [[ -z "$dizin" ]] && return 1

    # Zaten calisiyor mu?
    if cekirdek_oturum_koruma_aktif_mi "$kurum" "$hesap"; then
        _cekirdek_log "Oturum koruma zaten aktif ($kurum/$hesap)."
        return 0
    fi

    local pid_dosyasi="${dizin}/oturum_koruma.pid"
    local sahip_dosyasi="${dizin}/oturum_koruma.sahip"
    local sure="${_CEKIRDEK_OTURUM_SURELERI[${kurum}:${hesap}]:-}"

    # Diskten okumaya calis
    if [[ -z "$sure" ]] && [[ -f "${dizin}/oturum_suresi" ]]; then
        sure=$(cat "${dizin}/oturum_suresi" 2>/dev/null)
    fi

    # Varsayilan sure: 25 dakika (1500 saniye)
    [[ -z "$sure" ]] && sure=1500

    # Uzatma araligi: sure / 3
    local aralik=$(( sure / 3 ))
    [[ "$aralik" -lt 60 ]] && aralik=60

    # Arka plan dongusu
    (
        trap 'exit 0' TERM INT
        while true; do
            sleep "$aralik"

            # Oturum hala gecerli mi kontrol et
            local kalan
            kalan=$(cekirdek_oturum_kalan "$kurum" "$hesap")
            if [[ "$kalan" -le 0 ]]; then
                _cekirdek_log "Oturum koruma: oturum zaten dusmus ($kurum/$hesap)."
                break
            fi

            # Adaptor uzatma fonksiyonu tanimli mi?
            if declare -f adaptor_oturum_uzat > /dev/null 2>&1; then
                if adaptor_oturum_uzat "$hesap" 2>/dev/null; then
                    cekirdek_son_istek_guncelle "$kurum" "$hesap"
                    _cekirdek_log "Oturum koruma: uzatildi ($kurum/$hesap)."
                else
                    _cekirdek_log "Oturum koruma: uzatma BASARISIZ ($kurum/$hesap)."
                fi
            else
                # Adaptorde uzatma yoksa ana sayfaya sessiz GET at
                local cookie_dosyasi
                cookie_dosyasi=$(cekirdek_dosya_yolu "$kurum" "$_CEKIRDEK_DOSYA_COOKIE" "$hesap")
                if [[ -f "$cookie_dosyasi" ]]; then
                    cekirdek_istek_at \
                        -c "$cookie_dosyasi" \
                        -b "$cookie_dosyasi" \
                        -o /dev/null \
                        "https://esube1.ziraatyatirim.com.tr/sanalsube/tr/Home/Index" 2>/dev/null
                    cekirdek_son_istek_guncelle "$kurum" "$hesap"
                    _cekirdek_log "Oturum koruma: sessiz GET ile uzatildi ($kurum/$hesap)."
                fi
            fi
        done
    ) &

    local arka_pid=$!
    echo "$arka_pid" > "$pid_dosyasi"
    echo "$sahip" > "$sahip_dosyasi"
    disown "$arka_pid" 2>/dev/null

    _cekirdek_log "Oturum koruma baslatildi: PID $arka_pid ($kurum/$hesap, sahip: $sahip)."
}

# -------------------------------------------------------
# cekirdek_oturum_koruma_durdur <kurum> <hesap> [sahip_filtre]
# Oturum koruma dongusunu durdurur.
# sahip_filtre verilirse sadece o sahip durdurabilir.
# -------------------------------------------------------
cekirdek_oturum_koruma_durdur() {
    local kurum="$1"
    local hesap="$2"
    local sahip_filtre="${3:-}"

    local dizin
    dizin=$(cekirdek_oturum_dizini "$kurum" "$hesap")
    [[ -z "$dizin" ]] && return 1

    local pid_dosyasi="${dizin}/oturum_koruma.pid"
    local sahip_dosyasi="${dizin}/oturum_koruma.sahip"

    [[ ! -f "$pid_dosyasi" ]] && return 0

    # Sahip kontrolu
    if [[ -n "$sahip_filtre" ]] && [[ -f "$sahip_dosyasi" ]]; then
        local mevcut_sahip
        mevcut_sahip=$(cat "$sahip_dosyasi" 2>/dev/null)
        if [[ "$mevcut_sahip" != "$sahip_filtre" ]]; then
            _cekirdek_log "Oturum koruma durdurma: sahip uyumsuz (mevcut: $mevcut_sahip, filtre: $sahip_filtre)."
            return 0
        fi
    fi

    local pid
    pid=$(cat "$pid_dosyasi" 2>/dev/null)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        _cekirdek_log "Oturum koruma durduruldu: PID $pid ($kurum/$hesap)."
    fi

    rm -f "$pid_dosyasi" "$sahip_dosyasi" 2>/dev/null
}

# -------------------------------------------------------
# cekirdek_oturum_koruma_aktif_mi <kurum> <hesap>
# Oturum koruma dongusunun calisip calismadigini kontrol eder.
# Donus: 0 = aktif, 1 = inaktif
# -------------------------------------------------------
cekirdek_oturum_koruma_aktif_mi() {
    local kurum="$1"
    local hesap="$2"

    local dizin
    dizin=$(cekirdek_oturum_dizini "$kurum" "$hesap")
    [[ -z "$dizin" ]] && return 1

    local pid_dosyasi="${dizin}/oturum_koruma.pid"
    [[ ! -f "$pid_dosyasi" ]] && return 1

    local pid
    pid=$(cat "$pid_dosyasi" 2>/dev/null)
    [[ -z "$pid" ]] && return 1

    if kill -0 "$pid" 2>/dev/null; then
        return 0
    fi

    # PID dosyasi var ama proses yok — temizle
    rm -f "$pid_dosyasi" "${dizin}/oturum_koruma.sahip" 2>/dev/null
    return 1
}

# Aktif hesap secimini diske kaydeden dosya adi
_CEKIRDEK_DOSYA_AKTIF_HESAP=".aktif_hesap"

# -------------------------------------------------------
# _cekirdek_aktif_hesaplari_yukle
# Disk uzerinde kayitli aktif hesap secimlerini yukler.
# Her kurum icin /tmp/borsa/<kurum>/.aktif_hesap dosyasindan
# hesap numarasini okuyup _CEKIRDEK_AKTIF_HESAPLAR dizisine atar.
# Source sirasinda otomatik cagrilir.
# -------------------------------------------------------
_cekirdek_aktif_hesaplari_yukle() {
    local kurum_dizini hesap_dosyasi kurum hesap
    for kurum_dizini in "${_CEKIRDEK_OTURUM_KOK}"/*/; do
        [[ ! -d "$kurum_dizini" ]] && continue
        hesap_dosyasi="${kurum_dizini}${_CEKIRDEK_DOSYA_AKTIF_HESAP}"
        [[ ! -f "$hesap_dosyasi" ]] && continue
        hesap=$(cat "$hesap_dosyasi" 2>/dev/null)
        [[ -z "$hesap" ]] && continue
        kurum=$(basename "$kurum_dizini")
        _CEKIRDEK_AKTIF_HESAPLAR["$kurum"]="$hesap"
    done
}

# Source sirasinda kayitli aktif hesaplari yukle
_cekirdek_aktif_hesaplari_yukle

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
# Hem bellekte hem diskte saklar, boylece diger
# terminaller ve MCP subprocess'leri de okuyabilir.
# -------------------------------------------------------
cekirdek_aktif_hesap_ayarla() {
    local kurum="$1"
    local hesap="$2"
    _CEKIRDEK_AKTIF_HESAPLAR["$kurum"]="$hesap"

    # Diske de kaydet
    local kurum_dizini="${_CEKIRDEK_OTURUM_KOK}/${kurum}"
    mkdir -p "$kurum_dizini" 2>/dev/null
    echo "$hesap" > "${kurum_dizini}/${_CEKIRDEK_DOSYA_AKTIF_HESAP}"
    chmod 600 "${kurum_dizini}/${_CEKIRDEK_DOSYA_AKTIF_HESAP}" 2>/dev/null
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
# cekirdek_kurumlari_listele
# adaptorler/ klasorundeki kurumlari satirlar halinde dondurur.
# Sessiz calisir, log yok. Boru hattina uyumlu.
# -------------------------------------------------------
cekirdek_kurumlari_listele() {
    local surucu ad
    for surucu in "$BORSA_KLASORU/adaptorler"/*.sh; do
        [[ ! -f "$surucu" ]] && continue
        ad=$(basename "$surucu" .sh)
        [[ "$ad" == *.ayarlar ]] && continue
        echo "$ad"
    done
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
        if [[ ! -f "$cookie_yolu" ]]; then
            durum="COOKIE YOK"
        elif declare -f adaptor_oturum_gecerli_mi > /dev/null && adaptor_oturum_gecerli_mi "$no"; then
            durum="GECERLI"
        else
            durum="GECERSIZ"
        fi

        if [[ "$no" == "$aktif" ]]; then
            isaret="->"
        fi

        printf " %s %-15s  %-12s\n" "$isaret" "$no" "$durum"
        sayac=$((sayac + 1))
    done <<< "$dizinler"

    echo "========================================="
    echo " Toplam: $sayac oturum"
    echo " -> = secili hesap"
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

# Standart portfoy detay (hisse listesi) yazici.
# Adaptorler hisse verilerini satirlar halinde gonderir (TAB ayricli).
# Her satir formati: SEMBOL\tLOT\tSON_FIYAT\tPIYASA_DEGERI\tMALIYET\tKAR_ZARAR\tKAR_YUZDE
# Kullanim: cekirdek_yazdir_portfoy_detay <kurum_adi> <nakit> <hisse_toplam> <toplam> <satirlar>
cekirdek_yazdir_portfoy_detay() {
    local kurum="$1"
    local nakit="$2"
    local hisse_toplam="$3"
    local toplam="$4"
    local satirlar="$5"
    local kurum_buyuk
    kurum_buyuk=$(echo "$kurum" | tr '[:lower:]' '[:upper:]')

    echo ""
    echo "========================================================================="
    printf "  %s - PORTFOY DETAY\n" "$kurum_buyuk"
    echo "========================================================================="
    printf " %-8s %10s %10s %13s %10s %12s %7s\n" \
        "Sembol" "Lot" "Son Fiy." "Piy. Deg." "Maliyet" "Kar/Zarar" "K/Z %"
    echo "-------------------------------------------------------------------------"

    local satir
    while IFS= read -r satir; do
        [[ -z "$satir" ]] && continue
        local sembol lot son_fiyat piy_degeri maliyet kar_zarar kar_yuzde
        IFS=$'\t' read -r sembol lot son_fiyat piy_degeri maliyet kar_zarar kar_yuzde <<< "$satir"
        printf " %-8s %10s %10s %13s %10s %12s %7s\n" \
            "$sembol" "$lot" "$son_fiyat" "$piy_degeri" "$maliyet" "$kar_zarar" "$kar_yuzde"
    done <<< "$satirlar"

    echo "-------------------------------------------------------------------------"
    printf " %-8s %10s %10s %13s %10s\n" "" "" "" "Hisse Top." "$hisse_toplam"
    printf " %-8s %10s %10s %13s %10s\n" "" "" "" "Nakit" "$nakit"
    echo "========================================================================="
    printf " %-8s %10s %10s %13s %10s\n" "" "" "" "TOPLAM" "$toplam"
    echo "========================================================================="
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

# Standart halka arz listesi yazici.
# Adaptorler halka arz verilerini satirlar halinde gonderir (TAB ayricli).
# Her satir formati: AD\tTIP\tODEME\tDURUM\tIPO_ID
# Kullanim: cekirdek_yazdir_halka_arz_liste <kurum_adi> <limit> <satirlar>
cekirdek_yazdir_halka_arz_liste() {
    local kurum="$1"
    local limit="$2"
    local satirlar="$3"
    local kurum_buyuk
    kurum_buyuk=$(echo "$kurum" | tr '[:lower:]' '[:upper:]')

    echo ""
    echo "========================================================================="
    printf "  %s - HALKA ARZ LISTESI\n" "$kurum_buyuk"
    echo "========================================================================="
    if [[ -n "$limit" ]]; then
        echo "  Halka Arz Islem Limiti: $limit TL"
        echo "-------------------------------------------------------------------------"
    fi

    if [[ -z "$satirlar" ]]; then
        echo "  Tanimli halka arz bulunmamaktadir."
        echo "========================================================================="
        echo ""
        return 0
    fi

    printf " %-25s %-12s %-15s %-10s\n" \
        "Halka Arz" "Tip" "Odeme Sekli" "Durum"
    echo "-------------------------------------------------------------------------"

    local satir
    while IFS= read -r satir; do
        [[ -z "$satir" ]] && continue
        local ad tip odeme durum ipo_id
        # shellcheck disable=SC2034
        IFS=$'\t' read -r ad tip odeme durum ipo_id <<< "$satir"
        printf " %-25s %-12s %-15s %-10s\n" \
            "$ad" "$tip" "$odeme" "$durum"
    done <<< "$satirlar"

    echo "========================================================================="
    echo " Talep icin: borsa $kurum arz talep <IPO_ADI> <LOT>"
    echo "========================================================================="
    echo ""
}

# Standart halka arz talepler listesi yazici.
# Adaptorler talep verilerini satirlar halinde gonderir (TAB ayricli).
# Her satir formati: AD\tTARIH\tLOT\tFIYAT\tTUTAR\tDURUM\tTALEP_ID
# Kullanim: cekirdek_yazdir_halka_arz_talepler <kurum_adi> <satirlar>
cekirdek_yazdir_halka_arz_talepler() {
    local kurum="$1"
    local satirlar="$2"
    local kurum_buyuk
    kurum_buyuk=$(echo "$kurum" | tr '[:lower:]' '[:upper:]')

    echo ""
    echo "========================================================================="
    printf "  %s - HALKA ARZ TALEPLERIM\n" "$kurum_buyuk"
    echo "========================================================================="

    if [[ -z "$satirlar" ]]; then
        echo "  Gosterilecek kayit bulunamadi."
        echo "========================================================================="
        echo ""
        return 0
    fi

    printf " %-20s %-12s %8s %10s %12s %-12s\n" \
        "Halka Arz" "Tarih" "Lot" "Fiyat" "Tutar" "Durum"
    echo "-------------------------------------------------------------------------"

    local satir
    while IFS= read -r satir; do
        [[ -z "$satir" ]] && continue
        local ad tarih lot fiyat tutar durum talep_id
        # shellcheck disable=SC2034
        IFS=$'\t' read -r ad tarih lot fiyat tutar durum talep_id <<< "$satir"
        printf " %-20s %-12s %8s %10s %12s %-12s\n" \
            "$ad" "$tarih" "$lot" "$fiyat" "$tutar" "$durum"
    done <<< "$satirlar"

    echo "========================================================================="
    echo " Iptal icin : borsa $kurum arz iptal <TALEP_ID>"
    echo " Guncelle   : borsa $kurum arz guncelle <TALEP_ID> <YEN_LOT>"
    echo "========================================================================="
    echo ""
}

# -------------------------------------------------------
# ISLEM SONUC YAZDIRICILARI
# Adaptorlerin tekrarlayan echo bloklarini merkezilestiren fonksiyonlar.
# Her adaptor (ziraat, is_bankasi, ...) islem sonuclarini bu fonksiyonlar
# ile yazdirir; boylece cikti formati tek noktada yonetilir.
# -------------------------------------------------------

# Genel bilgi kutusu yazici.
# Baslik ve anahtar-deger ciftlerini cerceveli kutu icinde gosterir.
# Kullanim: cekirdek_yazdir_bilgi_kutusu "BASLIK" "Anahtar1" "Deger1" "Anahtar2" "Deger2" ...
# Not: Bos deger iceren alanlar otomatik olarak atlanir.
cekirdek_yazdir_bilgi_kutusu() {
    local baslik="$1"
    shift

    echo ""
    echo "========================================="
    echo " $baslik"
    echo "========================================="

    while [[ $# -ge 2 ]]; do
        local anahtar="$1"
        local deger="$2"
        shift 2
        [[ -z "$deger" ]] && continue
        printf " %-10s : %s\n" "$anahtar" "$deger"
    done

    echo "========================================="
    echo ""
}

# Emir sonucu yazici (gonder / kuru calistirma).
# Kullanim: cekirdek_yazdir_emir_sonuc "BASLIK" <sembol> <islem> <lot> <fiyat> <tur> <durum> [referans]
cekirdek_yazdir_emir_sonuc() {
    local baslik="$1"
    local sembol="$2"
    local islem="$3"
    local lot="$4"
    local fiyat="$5"
    local tur="$6"
    local durum="$7"
    local referans="${8:-}"

    echo ""
    echo "========================================="
    echo " $baslik"
    echo "========================================="
    echo " Sembol    : $sembol"
    echo " Islem     : $islem"
    echo " Lot       : $lot"
    echo " Fiyat     : $fiyat"
    echo " Tur       : $tur"
    if [[ -n "$referans" ]]; then
        echo " Referans  : $referans"
    fi
    echo " Durum     : $durum"
    echo "========================================="
    echo ""
}

# Emir iptal sonucu yazici.
# Kullanim: cekirdek_yazdir_emir_iptal <referans> <transaction_id> <durum> [mesaj]
cekirdek_yazdir_emir_iptal() {
    local referans="$1"
    local transaction_id="$2"
    local durum="$3"
    local mesaj="${4:-}"

    echo ""
    echo "========================================="
    echo " EMIR IPTAL EDILDI"
    echo "========================================="
    echo " Referans : $referans"
    echo " Trans.ID : $transaction_id"
    echo " Durum    : $durum"
    if [[ -n "$mesaj" ]]; then
        echo " Mesaj    : $mesaj"
    fi
    echo "========================================="
    echo ""
}

# Halka arz talep sonucu yazici (talep / kuru calistirma).
# Esnek alan destegi: anahtar-deger ciftleri parametre olarak gonderilir.
# Kullanim: cekirdek_yazdir_arz_sonuc "BASLIK" "Alan1" "Deger1" "Alan2" "Deger2" ...
cekirdek_yazdir_arz_sonuc() {
    cekirdek_yazdir_bilgi_kutusu "$@"
}

# Portfoyde hisse bulunamadi bilgi kutusu.
# Kullanim: cekirdek_yazdir_portfoy_bos <nakit>
cekirdek_yazdir_portfoy_bos() {
    local nakit="$1"
    echo ""
    echo "========================================="
    echo " Portfoyde hisse senedi bulunamadi."
    echo " Nakit Bakiye: ${nakit:-0.00} TL"
    echo "========================================="
    echo ""
}

# Oturum bilgi/uyari kutusu.
# Kullanim: cekirdek_yazdir_oturum_bilgi "BASLIK" [anahtar1 deger1 ...]
cekirdek_yazdir_oturum_bilgi() {
    local baslik="$1"
    shift

    echo ""
    echo "========================================="
    echo " $baslik"
    echo "========================================="
    while [[ $# -ge 2 ]]; do
        local anahtar="$1"
        local deger="$2"
        shift 2
        [[ -z "$deger" ]] && continue
        printf " %-10s : %s\n" "$anahtar" "$deger"
    done
    if [[ $# -eq 1 ]]; then
        echo " $1"
    fi
    echo "========================================="
    echo ""
}

# -------------------------------------------------------
# ADAPTOR FABRIKASI
# Yeni adaptor eklerken tekrarlanan ince sarmalayici (thin wrapper)
# fonksiyonlari otomatik olusturur. Adaptor dosyasi source edildikten
# sonra cagirilmali.
#
# Ornekler:
#   cekirdek_adaptor_kaydet "ziraat"
#   -> _ziraat_log, _ziraat_dosya_yolu, _ziraat_aktif_hesap_kontrol,
#      _ziraat_oturum_dizini, _ziraat_cookie_guvence fonksiyonlari olusur.
#
#   cekirdek_adaptor_kaydet "isbankasi"
#   -> _isbankasi_log, _isbankasi_dosya_yolu, ... fonksiyonlari olusur.
# -------------------------------------------------------

# Kullanim: cekirdek_adaptor_kaydet <kurum>
# shellcheck disable=SC2086,SC2154
cekirdek_adaptor_kaydet() {
    local kurum="$1"
    if [[ -z "$kurum" ]]; then
        _cekirdek_log "HATA: cekirdek_adaptor_kaydet — kurum adi bos."
        return 1
    fi

    eval "_${kurum}_oturum_dizini() { cekirdek_oturum_dizini '${kurum}' \"\$1\"; }"
    eval "_${kurum}_dosya_yolu()    { cekirdek_dosya_yolu '${kurum}' \"\$1\" \"\$2\"; }"
    eval "_${kurum}_aktif_hesap_kontrol() { cekirdek_aktif_hesap_kontrol '${kurum}'; }"
    eval "_${kurum}_log()           { cekirdek_adaptor_log '${kurum}' \"\$1\"; }"
    eval "_${kurum}_cookie_guvence() { cekirdek_cookie_guvence '${kurum}'; }"
}

# -------------------------------------------------------
# ADAPTOR YARDIMCI FONKSIYONLARI
# Adaptorlerde tekrarlanan kontrol ve parse desenlerini
# merkezilestiren fonksiyonlar.
# -------------------------------------------------------

# Yanit boyutu kontrolu.
# Yanit belirtilen esik degerinden kucukse hata mesaji yazdirir.
# Kullanim: cekirdek_boyut_kontrol "$yanit" 500 "Halka arz sayfasi" "$ADAPTOR_ADI" || return 1
cekirdek_boyut_kontrol() {
    local yanit="$1"
    local esik="$2"
    local baglam="$3"
    local kurum="$4"

    if [[ "${#yanit}" -lt "$esik" ]]; then
        cekirdek_adaptor_log "$kurum" "HATA: $baglam cok kucuk (${#yanit} bayt)."
        echo "HATA: $baglam alinamadi. Oturum sonlanmis olabilir."
        return 1
    fi
}

# Login sayfasina yonlendirme kontrolu.
# Sunucu oturumu sonlanmis kullanicilari login sayfasina yonlendirir.
# Bu fonksiyon yanitda verilen kalibi arar.
# Kullanim: cekirdek_oturum_yonlendirme_kontrol "$yanit" "Account/Login" "$ADAPTOR_ADI" || return 1
cekirdek_oturum_yonlendirme_kontrol() {
    local yanit="$1"
    local kalip="$2"
    local kurum="$3"

    if echo "$yanit" | grep -q "$kalip"; then
        cekirdek_adaptor_log "$kurum" "HATA: Oturum sonlanmis. Giris yapin."
        echo "HATA: Oturum sonlanmis. Once giris yapin: borsa $kurum giris"
        return 1
    fi
}

# HTML/form iceriginden CSRF token cikarir.
# Token bulunamazsa hata mesaji yazdirir ve return 1 yapar.
# stdout: token degeri (basariliysa)
# Kullanim: local csrf; csrf=$(cekirdek_csrf_cikar "$html" "$selektor" "emir formu" "$ADAPTOR_ADI") || return 1
cekirdek_csrf_cikar() {
    local html="$1"
    local selektor="$2"
    local baglam="$3"
    local kurum="$4"

    local token
    token=$(echo "$html" | grep -oP "$selektor" | tail -n 1)

    if [[ -z "$token" ]]; then
        cekirdek_adaptor_log "$kurum" "HATA: CSRF token bulunamadi ($baglam)."
        echo ""
        return 1
    fi
    echo "$token"
}

# JSON API yaniti analiz eder (IsSuccess / IsError / Data / Message).
# Adaptorler JSON endpoint'lerinden gelen yanitlari bu fonksiyonla parse eder.
#
# stdout: Message alani icerigi (bossa bos string)
# Donus kodu:
#   0 = Basari (IsSuccess=true veya Data==ek_basari_kalip)
#   1 = Hata (IsError=true)
#   2 = Bilinmeyen (ne basari ne hata tespit edilemedi)
#
# Kullanim:
#   local mesaj
#   mesaj=$(cekirdek_json_sonuc_isle "$yanit" "SILMEOK")
#   case $? in
#       0) echo "Basarili: $mesaj" ;;
#       1) echo "Hata: $mesaj" ;;
#       2) echo "Belirsiz: $mesaj" ;;
#   esac
cekirdek_json_sonuc_isle() {
    local yanit="$1"
    local ek_basari_kalip="${2:-}"

    local mesaj
    mesaj=$(echo "$yanit" | grep -oP '"[Mm]essage"\s*:\s*"\K[^"]+' | head -1)

    # Basari: IsSuccess=true
    if echo "$yanit" | grep -qiE '"[Ii]s[Ss]uccess"\s*:\s*true'; then
        echo "${mesaj:-}"
        return 0
    fi

    # Ek basari kalıbı (Data alaninda ozel deger, orn: "SILMEOK")
    if [[ -n "$ek_basari_kalip" ]]; then
        local veri_alani
        veri_alani=$(echo "$yanit" | grep -oP '"Data"\s*:\s*"\K[^"]+' | head -1)
        if [[ "$veri_alani" == "$ek_basari_kalip" ]]; then
            echo "${mesaj:-}"
            return 0
        fi
    fi

    # Hata: IsError=true
    if echo "$yanit" | grep -qiE '"[Ii]s[Ee]rror"\s*:\s*true'; then
        echo "${mesaj:-Islem basarisiz}"
        return 1
    fi

    # Bilinmeyen durum
    echo "${mesaj:-Beklenmeyen yanit}"
    return 2
}

# HTML hata mesaji cikarici ile hata gosterme deseni.
# Adaptore ozel hata cikarma fonksiyonunu cagirip sonucu gosterir.
# Kullanim: cekirdek_html_hata_goster "_ziraat_html_hata_cikar" "$yanit" "Emir reddedildi" "$debug_dosyasi"
cekirdek_html_hata_goster() {
    local hata_cikar_fonk="$1"
    local yanit="$2"
    local varsayilan_mesaj="$3"
    local debug_dosyasi="${4:-}"

    local hata_metni
    hata_metni=$("$hata_cikar_fonk" "$yanit")

    if [[ -n "$hata_metni" ]]; then
        echo "HATA: $hata_metni"
    elif [[ -n "$debug_dosyasi" ]]; then
        echo "HATA: $varsayilan_mesaj. Debug: $debug_dosyasi"
    else
        echo "HATA: $varsayilan_mesaj"
    fi
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

    return 0
}

# =============================================================================
# BOLUM 11 - UST SEVIYE FONKSIYONLAR
# Tum acik oturumlari tarayarak birlesik bilgi sunar.
# =============================================================================

# Tum acik hesaplarin bakiyelerini tek tabloda gosterir.
tum_bakiyeler() {
    local toplam_nakit=0
    local toplam_hisse=0
    local toplam_genel=0
    local satir_var=0

    printf "%-12s %-10s %15s %15s %15s\n" \
        "KURUM" "HESAP" "NAKIT" "HISSE" "TOPLAM"
    printf "%s\n" "-------------------------------------------------------------------"

    local kurum_klasoru
    for kurum_klasoru in /tmp/borsa/*/; do
        [[ -d "$kurum_klasoru" ]] || continue
        local kurum_adi
        kurum_adi=$(basename "$kurum_klasoru")
        [[ "$kurum_adi" == "_vt_yedek" ]] && continue
        [[ "$kurum_adi" == "_veri_durum" ]] && continue

        local hesap_klasoru
        for hesap_klasoru in "${kurum_klasoru}"*/; do
            [[ -d "$hesap_klasoru" ]] || continue
            local hesap_no
            hesap_no=$(basename "$hesap_klasoru")

            # Oturum acik mi kontrol et
            [[ -f "${hesap_klasoru}oturum.cookie" ]] || continue

            # Adaptor yukle ve bakiye al
            local surucu="${BORSA_KLASORU}/adaptorler/${kurum_adi}.sh"
            [[ -f "$surucu" ]] || continue

            # shellcheck source=/dev/null
            source "$surucu"

            local bakiye_ciktisi
            bakiye_ciktisi=$(adaptor_bakiye "$hesap_no" 2>/dev/null) || continue

            # Basit ayristirma: nakit ve toplam satirlari ara
            local nakit hisse toplam
            nakit=$(echo "$bakiye_ciktisi" | grep -i "nakit\|TL" | head -1 | grep -oP '[\d,.]+' | tail -1 | tr -d '.' | tr ',' '.' || echo "0")
            toplam=$(echo "$bakiye_ciktisi" | grep -i "toplam\|Genel" | head -1 | grep -oP '[\d,.]+' | tail -1 | tr -d '.' | tr ',' '.' || echo "0")
            hisse=$(echo "$toplam - $nakit" | bc 2>/dev/null || echo "0")

            printf "%-12s %-10s %15s %15s %15s\n" \
                "$kurum_adi" "$hesap_no" "$nakit" "$hisse" "$toplam"

            toplam_nakit=$(echo "$toplam_nakit + $nakit" | bc 2>/dev/null || echo "$toplam_nakit")
            toplam_hisse=$(echo "$toplam_hisse + $hisse" | bc 2>/dev/null || echo "$toplam_hisse")
            toplam_genel=$(echo "$toplam_genel + $toplam" | bc 2>/dev/null || echo "$toplam_genel")
            satir_var=1
        done
    done

    if [[ $satir_var -eq 0 ]]; then
        echo "(Acik oturum bulunamadi)"
        return 0
    fi

    printf "%s\n" "-------------------------------------------------------------------"
    printf "%-12s %-10s %15s %15s %15s\n" \
        "TOPLAM" "" "$toplam_nakit" "$toplam_hisse" "$toplam_genel"
}

# Tum acik hesaplarin portfoylerini birlesik gosterir.
tum_portfoyler() {
    local satir_var=0
    local kurum_klasoru

    for kurum_klasoru in /tmp/borsa/*/; do
        [[ -d "$kurum_klasoru" ]] || continue
        local kurum_adi
        kurum_adi=$(basename "$kurum_klasoru")
        [[ "$kurum_adi" == "_vt_yedek" ]] && continue

        local hesap_klasoru
        for hesap_klasoru in "${kurum_klasoru}"*/; do
            [[ -d "$hesap_klasoru" ]] || continue
            local hesap_no
            hesap_no=$(basename "$hesap_klasoru")
            [[ -f "${hesap_klasoru}oturum.cookie" ]] || continue

            local surucu="${BORSA_KLASORU}/adaptorler/${kurum_adi}.sh"
            [[ -f "$surucu" ]] || continue

            # shellcheck source=/dev/null
            source "$surucu"

            if declare -f adaptor_portfoy > /dev/null; then
                echo "=== $kurum_adi / $hesap_no ==="
                adaptor_portfoy "$hesap_no" 2>/dev/null || echo "(Portfoy alinamadi)"
                echo ""
                satir_var=1
            fi
        done
    done

    if [[ $satir_var -eq 0 ]]; then
        echo "(Acik oturum bulunamadi)"
    fi
}

# Tum acik hesaplardaki bekleyen emirleri listeler.
tum_emirler() {
    local satir_var=0
    local kurum_klasoru

    for kurum_klasoru in /tmp/borsa/*/; do
        [[ -d "$kurum_klasoru" ]] || continue
        local kurum_adi
        kurum_adi=$(basename "$kurum_klasoru")
        [[ "$kurum_adi" == "_vt_yedek" ]] && continue

        local hesap_klasoru
        for hesap_klasoru in "${kurum_klasoru}"*/; do
            [[ -d "$hesap_klasoru" ]] || continue
            local hesap_no
            hesap_no=$(basename "$hesap_klasoru")
            [[ -f "${hesap_klasoru}oturum.cookie" ]] || continue

            local surucu="${BORSA_KLASORU}/adaptorler/${kurum_adi}.sh"
            [[ -f "$surucu" ]] || continue

            # shellcheck source=/dev/null
            source "$surucu"

            echo "=== $kurum_adi / $hesap_no ==="
            adaptor_emirleri_listele "$hesap_no" 2>/dev/null || echo "(Emir listesi alinamadi)"
            echo ""
            satir_var=1
        done
    done

    if [[ $satir_var -eq 0 ]]; then
        echo "(Acik oturum bulunamadi)"
    fi
}

# Acik oturumlari, kalan surelerini ve robot durumlarini gosterir.
tum_oturumlar() {
    printf "%-12s %-10s %10s %8s %s\n" \
        "KURUM" "HESAP" "KALAN" "KORUMA" "ROBOTLAR"
    printf "%s\n" "-----------------------------------------------------------"

    local satir_var=0
    local kurum_klasoru
    for kurum_klasoru in /tmp/borsa/*/; do
        [[ -d "$kurum_klasoru" ]] || continue
        local kurum_adi
        kurum_adi=$(basename "$kurum_klasoru")
        [[ "$kurum_adi" == "_vt_yedek" ]] && continue

        local hesap_klasoru
        for hesap_klasoru in "${kurum_klasoru}"*/; do
            [[ -d "$hesap_klasoru" ]] || continue
            local hesap_no
            hesap_no=$(basename "$hesap_klasoru")
            [[ -f "${hesap_klasoru}oturum.cookie" ]] || continue

            # Kalan sure
            local kalan="?"
            if declare -f cekirdek_oturum_kalan > /dev/null; then
                kalan=$(cekirdek_oturum_kalan "$kurum_adi" "$hesap_no" 2>/dev/null || echo "?")
            fi

            # Koruma durumu
            local koruma="YOK"
            if [[ -f "${hesap_klasoru}oturum_koruma.pid" ]]; then
                local pid
                pid=$(cat "${hesap_klasoru}oturum_koruma.pid" 2>/dev/null)
                if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                    koruma="AKTIF"
                fi
            fi

            # Robot sayisi
            local robot_bilgi="YOK"
            if [[ -d "${hesap_klasoru}robotlar" ]]; then
                local robot_sayisi
                robot_sayisi=$(find "${hesap_klasoru}robotlar" -name "*.pid" 2>/dev/null | wc -l)
                if [[ "$robot_sayisi" -gt 0 ]]; then
                    robot_bilgi="${robot_sayisi} adet"
                fi
            fi

            printf "%-12s %-10s %10s %8s %s\n" \
                "$kurum_adi" "$hesap_no" "$kalan" "$koruma" "$robot_bilgi"
            satir_var=1
        done
    done

    if [[ $satir_var -eq 0 ]]; then
        echo "(Acik oturum bulunamadi)"
    fi
}

# Bugunku tum islemleri, K/Z ve bakiye degisimini ozetler.
gunluk_ozet() {
    echo "=== Gunluk Ozet: $(date '+%Y-%m-%d') ==="
    echo ""

    # Acik oturumlar
    echo "--- Oturumlar ---"
    tum_oturumlar
    echo ""

    # Gun sonu raporu (DB'den)
    if declare -f vt_gun_sonu_rapor > /dev/null; then
        echo "--- Gun Sonu Rapor ---"
        vt_gun_sonu_rapor
        echo ""
    fi

    # Bakiyeler
    echo "--- Bakiyeler ---"
    tum_bakiyeler
    echo ""

    # Bekleyen DB yazmalari
    local yedek_dosya="/tmp/borsa/_vt_yedek/bekleyen.jsonl"
    if [[ -f "$yedek_dosya" ]]; then
        local bekleyen_sayisi
        bekleyen_sayisi=$(wc -l < "$yedek_dosya" 2>/dev/null || echo "0")
        if [[ "$bekleyen_sayisi" -gt 0 ]]; then
            echo "UYARI: $bekleyen_sayisi adet bekleyen DB yazisi var."
            echo "       Gonderme icin: _vt_bekleyenleri_gonder"
        fi
    fi
}

export -f tum_bakiyeler tum_portfoyler tum_emirler tum_oturumlar gunluk_ozet

borsa() {
    local kurum="$1"
    local komut="$2"
    shift 2 2>/dev/null

    if [[ -z "$kurum" ]]; then
        echo "Kullanim: borsa <kurum> <komut> [argumanlar]"
        echo "         borsa kurallar [seans|fiyat|pazar|takas]"
        echo "         borsa gecmis [emirler|bakiye|sembol|kar|robot] [N|bugun|SEMBOL]"
        echo "         borsa mutabakat <kurum> <hesap> [sembol]"
        echo "         borsa robot [baslat|durdur|listele]"
        echo "         borsa veri [baslat|durdur|goster|ayarla]"
        echo ""
        echo "Kurumlar:"
        local ad
        while IFS= read -r ad; do
            echo "  - $ad"
        done < <(cekirdek_kurumlari_listele)
        echo ""
        echo "Kurum komutlari: giris [-o], bakiye, portfoy, emir, emirler, iptal,"
        echo "                 arz, hesap, hesaplar, fiyat, cikis, oturum-durdur"
        echo "Kurallar:        borsa kurallar [seans|fiyat|pazar|takas|adim|tavan|taban]"
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

    # Ozel komut: borsa gecmis — Veritabani gecmis sorgulari
    if [[ "$kurum" == "gecmis" ]]; then
        local alt_komut="$komut"
        case "$alt_komut" in
            emirler)
                local limit="${1:-10}"
                vt_emir_gecmisi "" "" "$limit"
                ;;
            bakiye)
                local donem="${1:-bugun}"
                vt_bakiye_gecmisi "" "" "$donem"
                ;;
            sembol)
                local sembol="$1"
                if [[ -z "$sembol" ]]; then
                    echo "Kullanim: borsa gecmis sembol <SEMBOL>"
                    return 1
                fi
                vt_pozisyon_gecmisi "" "" "$sembol"
                ;;
            kar)
                local gun="${1:-30}"
                vt_kar_zarar_rapor "" "" "$gun"
                ;;
            fiyat)
                local sembol="$1"
                local gun="${2:-30}"
                if [[ -z "$sembol" ]]; then
                    echo "Kullanim: borsa gecmis fiyat <SEMBOL> [GUN]"
                    return 1
                fi
                vt_fiyat_gecmisi "$sembol" "$gun"
                ;;
            robot)
                local pid_veya_gun="$1"
                vt_robot_log_gecmisi "$pid_veya_gun"
                ;;
            oturum)
                vt_oturum_log_gecmisi "$1" "$2"
                ;;
            rapor)
                vt_gun_sonu_rapor
                ;;
            "")
                echo "Kullanim: borsa gecmis <alt_komut>"
                echo "Alt komutlar:"
                echo "  emirler [N]         - Son N emri goster (varsayilan: 10)"
                echo "  bakiye [bugun|N]    - Bakiye gecmisi"
                echo "  sembol <SEMBOL>     - Sembol bazli pozisyon gecmisi"
                echo "  kar [GUN]           - Son N gunun K/Z raporu (varsayilan: 30)"
                echo "  fiyat <SEMBOL> [GUN]- Fiyat gecmisi"
                echo "  robot [PID]         - Robot log gecmisi"
                echo "  oturum [KURUM] [HESAP] - Oturum log gecmisi"
                echo "  rapor               - Gun sonu raporu"
                ;;
            *)
                echo "HATA: Bilinmeyen gecmis komutu: '$alt_komut'"
                return 1
                ;;
        esac
        return 0
    fi

    # Ozel komut: borsa mutabakat — Canli/DB karsilastirma
    if [[ "$kurum" == "mutabakat" ]]; then
        local mt_kurum="$komut"
        local mt_hesap="$1"
        local mt_sembol="${2:-}"

        if [[ -z "$mt_kurum" ]] || [[ -z "$mt_hesap" ]]; then
            echo "Kullanim: borsa mutabakat <kurum> <hesap> [sembol]"
            return 1
        fi

        echo "--- Bakiye Mutabakat ---"
        vt_mutabakat_kontrol "$mt_kurum" "$mt_hesap"

        if [[ -n "$mt_sembol" ]]; then
            echo ""
            echo "--- Pozisyon Mutabakat: $mt_sembol ---"
            vt_pozisyon_mutabakat "$mt_kurum" "$mt_hesap" "$mt_sembol"
        fi
        return 0
    fi

    # Ozel komut: borsa robot — Robot yonetimi
    if [[ "$kurum" == "robot" ]]; then
        local rb_komut="$komut"
        case "$rb_komut" in
            baslat)
                robot_baslat "$@"
                ;;
            durdur)
                robot_durdur "$@"
                ;;
            listele|liste)
                robot_listele
                ;;
            "")
                echo "Kullanim: borsa robot <komut>"
                echo "Komutlar:"
                echo "  baslat [--kuru] <kurum> <hesap> <strateji.sh>"
                echo "  durdur <kurum> <hesap> [strateji_adi]"
                echo "  listele"
                ;;
            *)
                echo "HATA: Bilinmeyen robot komutu: '$rb_komut'"
                return 1
                ;;
        esac
        return 0
    fi

    # Ozel komut: borsa veri — Veri kaynagi yonetimi
    if [[ "$kurum" == "veri" ]]; then
        local vr_komut="$komut"
        case "$vr_komut" in
            baslat)
                veri_kaynagi_baslat "$@"
                ;;
            durdur)
                veri_kaynagi_durdur
                ;;
            goster|durum)
                veri_kaynagi_goster
                ;;
            ayarla)
                veri_kaynagi_ayarla "$@"
                ;;
            fiyat)
                local sembol="$1"
                if [[ -z "$sembol" ]]; then
                    echo "Kullanim: borsa veri fiyat <SEMBOL>"
                    return 1
                fi
                veri_kaynagi_fiyat_al "$sembol"
                ;;
            "")
                echo "Kullanim: borsa veri <komut>"
                echo "Komutlar:"
                echo "  baslat               - Veri kaynagini otomatik sec ve baslat"
                echo "  durdur               - Veri kaynagini durdur"
                echo "  goster               - Aktif kaynagi ve yedekleri goster"
                echo "  ayarla <kurum> <hesap>- Manuel kaynak sec"
                echo "  fiyat <SEMBOL>       - Sembol fiyati sorgula"
                ;;
            *)
                echo "HATA: Bilinmeyen veri komutu: '$vr_komut'"
                return 1
                ;;
        esac
        return 0
    fi

    local surucu_dosyasi="${BORSA_KLASORU}/adaptorler/${kurum}.sh"

    if [[ ! -f "$surucu_dosyasi" ]]; then
        echo "HATA: '$kurum' surucusu bulunamadi."
        echo "Gecerli kurumlar:"
        local k
        while IFS= read -r k; do
            echo "  - $k"
        done < <(cekirdek_kurumlari_listele)
        return 1
    fi

    # Onceki adaptorunkinden farkli ise degiskenleri temizle
    if [[ "${_CEKIRDEK_SON_ADAPTOR:-}" != "$kurum" ]]; then
        unset ADAPTOR_ADI ADAPTOR_SURUMU 2>/dev/null || true
        _CEKIRDEK_SON_ADAPTOR="$kurum"
    fi

    # shellcheck source=/dev/null
    source "$surucu_dosyasi"

    case "$komut" in
        giris)
            local oturum_koru=0
            local giris_args=()
            local arg
            for arg in "$@"; do
                if [[ "$arg" == "-o" ]]; then
                    oturum_koru=1
                else
                    giris_args+=("$arg")
                fi
            done

            adaptor_giris "${giris_args[@]}"
            local giris_sonuc=$?

            if [[ $giris_sonuc -eq 0 ]] && [[ $oturum_koru -eq 1 ]]; then
                local hesap="${giris_args[0]}"
                cekirdek_oturum_koruma_baslat "$kurum" "$hesap" "giris"
            fi
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
        arz)
            local arz_alt_komut="$1"
            if [[ -n "$1" ]]; then shift; fi
            case "$arz_alt_komut" in
                liste)
                    if declare -f adaptor_halka_arz_liste > /dev/null; then
                        adaptor_halka_arz_liste "$@"
                    else
                        echo "HATA: '$kurum' surucusu 'arz liste' komutunu desteklemiyor."
                        return 1
                    fi
                    ;;
                talepler)
                    if declare -f adaptor_halka_arz_talepler > /dev/null; then
                        adaptor_halka_arz_talepler "$@"
                    else
                        echo "HATA: '$kurum' surucusu 'arz talepler' komutunu desteklemiyor."
                        return 1
                    fi
                    ;;
                talep)
                    if declare -f adaptor_halka_arz_talep > /dev/null; then
                        adaptor_halka_arz_talep "$@"
                    else
                        echo "HATA: '$kurum' surucusu 'arz talep' komutunu desteklemiyor."
                        return 1
                    fi
                    ;;
                iptal)
                    if declare -f adaptor_halka_arz_iptal > /dev/null; then
                        adaptor_halka_arz_iptal "$@"
                    else
                        echo "HATA: '$kurum' surucusu 'arz iptal' komutunu desteklemiyor."
                        return 1
                    fi
                    ;;
                guncelle)
                    if declare -f adaptor_halka_arz_guncelle > /dev/null; then
                        adaptor_halka_arz_guncelle "$@"
                    else
                        echo "HATA: '$kurum' surucusu 'arz guncelle' komutunu desteklemiyor."
                        return 1
                    fi
                    ;;
                "")
                    echo "Kullanim: borsa $kurum arz <alt_komut>"
                    echo "Alt komutlar: liste, talepler, talep, iptal, guncelle"
                    ;;
                *)
                    echo "HATA: Bilinmeyen arz komutu: '$arz_alt_komut'"
                    echo "Gecerli alt komutlar: liste, talepler, talep, iptal, guncelle"
                    return 1
                    ;;
            esac
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
        cikis)
            local hesap="$1"
            if [[ -z "$hesap" ]]; then
                echo "Kullanim: borsa $kurum cikis <hesap_no>"
                return 1
            fi

            # Adaptor cikis fonksiyonu varsa cagir (LogOff)
            if declare -f adaptor_cikis > /dev/null; then
                adaptor_cikis "$hesap"
            fi

            # Oturum korumayi durdur
            cekirdek_oturum_koruma_durdur "$kurum" "$hesap"

            # Oturum log yaz
            if declare -f vt_oturum_log_yaz > /dev/null; then
                vt_oturum_log_yaz "$kurum" "$hesap" "CIKIS" "Manuel cikis" &
            fi

            echo "Oturum kapatildi: $kurum / $hesap"
            ;;
        oturum-durdur)
            local hesap="$1"
            if [[ -z "$hesap" ]]; then
                echo "Kullanim: borsa $kurum oturum-durdur <hesap_no>"
                return 1
            fi
            cekirdek_oturum_koruma_durdur "$kurum" "$hesap"
            echo "Oturum koruma durduruldu (oturum acik kaldi): $kurum / $hesap"
            ;;
        fiyat)
            local sembol="$1"
            if [[ -z "$sembol" ]]; then
                echo "Kullanim: borsa $kurum fiyat <SEMBOL>"
                return 1
            fi
            # Adaptor varsa dogrudan adaptor ile sorgula
            if declare -f adaptor_hisse_bilgi_al > /dev/null; then
                adaptor_hisse_bilgi_al "$sembol"
            elif declare -f veri_kaynagi_fiyat_al > /dev/null; then
                veri_kaynagi_fiyat_al "$sembol"
            else
                echo "HATA: Fiyat sorgulama desteklenmiyor."
                return 1
            fi
            ;;
        "")
            echo "Kullanim: borsa $kurum <komut>"
            echo "Komutlar: giris [-o], bakiye, portfoy, emir, emirler, iptal,"
            echo "          arz, hesap, hesaplar, fiyat, cikis, oturum-durdur"
            ;;
        *)
            echo "HATA: Bilinmeyen komut: '$komut'"
            echo "Gecerli komutlar: giris, bakiye, portfoy, emir, emirler,"
            echo "  iptal, arz, hesap, hesaplar, fiyat, cikis, oturum-durdur"
            return 1
            ;;
    esac
}

export -f borsa

# Tab tamamlama (completion) yukleme
# shellcheck source=/home/yasar/dotfiles/bashrc.d/borsa/tamamlama.sh
source "${BORSA_KLASORU}/tamamlama.sh"
