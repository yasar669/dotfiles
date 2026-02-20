#!/bin/bash
# shellcheck shell=bash

# Ziraat Yatirim Adaptoru
# Bu dosya dogrudan calistirilmaz, cekirdek.sh tarafindan yuklenir.
# Konfigürasyon ve URL: ziraat.ayarlar.sh dosyasinda.
# HTTP istekleri: cekirdek.sh'daki cekirdek_istek_at() ile yapilir.

# shellcheck disable=SC2034
[[ -v ADAPTOR_ADI ]] || readonly ADAPTOR_ADI="ziraat"
[[ -v ADAPTOR_SURUMU ]] || readonly ADAPTOR_SURUMU="1.0.0"

# Ayarlar dosyasini yukle
# shellcheck source=/home/yasar/dotfiles/bashrc.d/borsa/adaptorler/ziraat.ayarlar.sh
source "${BORSA_KLASORU}/adaptorler/ziraat.ayarlar.sh"

# =======================================================
# BOLUM 1: DAHILI YARDIMCILAR (Disaridan cagrilmaz)
# =======================================================

# Oturum yonetimi cekirdek fonksiyonlarina delege edilir.
# Asagidaki ince sarmalayicilar (thin wrappers) sadece
# kurum adini ("ziraat") gecerek cekirdek_* fonksiyonlarini cagirip
# adaptor kodunu kisa tutar.

# -------------------------------------------------------
# _ziraat_oturum_dizini [musteri_no]
# -------------------------------------------------------
_ziraat_oturum_dizini() {
    cekirdek_oturum_dizini "ziraat" "$1"
}

# -------------------------------------------------------
# _ziraat_dosya_yolu <dosya_adi> [musteri_no]
# -------------------------------------------------------
_ziraat_dosya_yolu() {
    cekirdek_dosya_yolu "ziraat" "$1" "$2"
}

# -------------------------------------------------------
# _ziraat_aktif_hesap_kontrol
# -------------------------------------------------------
_ziraat_aktif_hesap_kontrol() {
    cekirdek_aktif_hesap_kontrol "ziraat"
}

# -------------------------------------------------------
# _ziraat_log <mesaj>
# -------------------------------------------------------
_ziraat_log() {
    cekirdek_adaptor_log "ziraat" "$1"
}

# -------------------------------------------------------
# _ziraat_cookie_guvence
# -------------------------------------------------------
_ziraat_cookie_guvence() {
    cekirdek_cookie_guvence "ziraat"
}

# -------------------------------------------------------
# _ziraat_html_hata_cikar <html_icerigi>
# HTML yanit iceriginden sunucu hata mesajlarini cikarir.
# Multiline HTML'i handle eder (li ve ul farkli satirlarda olabilir).
# stdout: hata metni (varsa), bossa cikti yok.
# -------------------------------------------------------
_ziraat_html_hata_cikar() {
    local html="$1"
    local hata=""

    # Oncelik 1: validation-summary-errors icindeki li elemanlari
    # Multiline oldugu icin tr ile satirlari birlestirip parse ediyoruz
    # \r (carriage return) temizlenir, aksi halde cikti bozulur
    hata=$(echo "$html" | tr -d '\r' | tr '\n' ' ' | grep -oP 'validation-summary-errors[^<]*<ul>\K.*?(?=</ul>)' | sed 's/<li>/\n/g; s/<\/li>//g' | sed '/^[[:space:]]*$/d' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | head -3)

    # Oncelik 2: error-border li icerigi
    if [[ -z "$hata" ]]; then
        hata=$(echo "$html" | grep -oP 'id="error-border"[^<]*<li[^>]*>\K[^<]+' | head -3)
    fi

    # Oncelik 3: JSON message alani
    if [[ -z "$hata" ]]; then
        hata=$(echo "$html" | grep -oP '"message":"\K[^"]+' | head -1)
    fi

    if [[ -n "$hata" ]]; then
        echo "$hata"
    fi
}

# -------------------------------------------------------
# adaptor_oturum_gecerli_mi [musteri_no]
# Ziraat'e ozgu oturum gecerlilik kontrolu.
# cekirdek_hesap() tarafindan callback olarak cagrilir.
# Yontem: Ana sayfaya GET atip session GUID kontrol edilir.
# -------------------------------------------------------
adaptor_oturum_gecerli_mi() {
    local hesap="${1:-$(cekirdek_aktif_hesap "ziraat")}"
    local cookie_dosyasi
    cookie_dosyasi=$(cekirdek_dosya_yolu "ziraat" "$_CEKIRDEK_DOSYA_COOKIE" "$hesap")

    if [[ -z "$cookie_dosyasi" ]] || [[ ! -f "$cookie_dosyasi" ]]; then
        return 1
    fi

    # Sunucuya tek GET istegi at, session GUID kontrol et
    local ana_yanit
    ana_yanit=$(cekirdek_istek_at \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_ANA_SAYFA_URL" 2>/dev/null)

    local session_guid
    session_guid=$(echo "$ana_yanit" | grep -oP "$_ZIRAAT_SEL_SESSION_GUID")

    if [[ -n "$session_guid" ]]; then
        return 0
    fi

    # Session GUID yok — login formuna yonlendirilmis mi?
    if echo "$ana_yanit" | grep -qP "$_ZIRAAT_SEL_CSRF_TOKEN"; then
        return 1   # Oturum dolmus
    fi

    # Belirsiz — cookie var ama bilinmeyen durum, gecersiz say
    return 1
}

_ziraat_sayfa_hazirla() {
    _ziraat_log "Giris sayfasi cekiliyor..."

    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")
    local debug_dosyasi
    debug_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_DEBUG")

    local sayfa_icerik
    sayfa_icerik=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_LOGIN_URL")
    _ziraat_cookie_guvence

    # Kontrol 1: Sayfa boyutu - Hata sayfasi genelde < 2KB
    local boyut="${#sayfa_icerik}"
    if [[ "$boyut" -lt 2000 ]]; then
        _ziraat_log "HATA: Giris sayfasi cok kucuk ($boyut bayt). Sunucu erisilemez veya URL degismis olabilir."
        echo "|"
        return 1
    fi

    local hostname_val
    hostname_val=$(echo "$sayfa_icerik" | grep -oP "$_ZIRAAT_SEL_HOSTNAME")
    if [[ -z "$hostname_val" ]]; then
        hostname_val="$_ZIRAAT_FALLBACK_HOSTNAME"
        _ziraat_log "UYARI: HostName bulunamadi, varsayilan ($hostname_val) kullaniliyor."
    else
        _ziraat_log "HostName bulundu: $hostname_val"
    fi

    local token_val
    token_val=$(echo "$sayfa_icerik" | grep -oP "$_ZIRAAT_SEL_CSRF_TOKEN")

    # Kontrol 2: CSRF token kritik - Yoksa devam etme
    if [[ -z "$token_val" ]]; then
        _ziraat_log "KRITIK HATA: CSRF Token bulunamadi! Giris sayfasi degismis olabilir."
        _ziraat_log "Giris sayfasi HTML'i incelemek icin: $debug_dosyasi"
        echo "$sayfa_icerik" > "$debug_dosyasi"
        echo "|"
        return 1
    fi

    _ziraat_log "Token bulundu: ${token_val:0:10}..."
    echo "${hostname_val}|${token_val}"
}

_ziraat_sms_dogrula() {
    local onceki_token="$1"
    local musteri_no="$2"
    local parola="$3"

    echo "========================================"
    echo "DIKKAT: Banka SMS Dogrulama Kodu Istiyor"
    echo "========================================"
    echo "Lutfen telefonunuza gelen kodu girin:"
    read -r sms_kodu

    if [[ -z "$sms_kodu" ]]; then
        _ziraat_log "SMS kodu girilmedi, islem iptal."
        return 1
    fi

    local sms_token_val
    sms_token_val=$(echo "$_ziraat_giris_sonuc" | grep -oP "$_ZIRAAT_SEL_CSRF_TOKEN")

    if [[ -z "$sms_token_val" ]]; then
        _ziraat_log "UYARI: SMS sayfasinda yeni token bulunamadi, eski kullaniliyor."
        sms_token_val="$onceki_token"
    else
        _ziraat_log "SMS token: ${sms_token_val:0:10}..."
    fi

    _ziraat_log "SMS kodu gonderiliyor..."
    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")
    local sms_sonuc
    sms_sonuc=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Referer: $_ZIRAAT_LOGIN_URL" \
        -H "Origin: $_ZIRAAT_BASE_URL" \
        --data-urlencode "InputCustomerNo=$musteri_no" \
        --data-urlencode "Passphrase=$parola" \
        --data-urlencode "HostName=$_ZIRAAT_FALLBACK_HOSTNAME" \
        --data-urlencode "__RequestVerificationToken=$sms_token_val" \
        --data-urlencode "ViewType=SMS" \
        --data-urlencode "SmsPassword=$sms_kodu" \
        "$_ZIRAAT_LOGIN_URL")

    # Kontrol: SMS yaniti boyutu
    local sms_boyut="${#sms_sonuc}"
    if [[ "$sms_boyut" -lt 50 ]]; then
        _ziraat_log "HATA: SMS yaniti cok kucuk ($sms_boyut bayt). Sunucu erisilemez veya oturum bozuldu."
        return 1
    fi

    if echo "$sms_sonuc" | grep -q "$_ZIRAAT_KALIP_BASARILI_HTML"; then
        _ziraat_log "BASARILI: Giris tamamlandi (HTML)."
    elif echo "$sms_sonuc" | grep -q "$_ZIRAAT_KALIP_BASARILI_JSON"; then
        _ziraat_log "BASARILI: Giris tamamlandi (JSON)."
        local redirect_url
        redirect_url=$(echo "$sms_sonuc" | grep -oP '"url":"\K[^"]+')
        _ziraat_log "Yonlendirilecek URL: $redirect_url"
    else
        _ziraat_log "HATA: SMS dogrulamasi basarisiz."
        _ziraat_log "Yanit boyutu: $sms_boyut bayt."
        local debug_dosyasi
        debug_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_DEBUG")
        echo "$sms_sonuc" > "$debug_dosyasi"
        return 1
    fi

    echo "Tebrikler! Oturum acildi."
}

# -------------------------------------------------------
# _ziraat_seans_disi_tutar_kontrol <lot> <fiyat>
# Ziraat'in seans disi minimum tutar kuralini kontrol eder.
# 17:30-10:45 arasi 1000 TL altindaki emirler reddedilir.
# Donus: 0 = uygun, 1 = tutar yetersiz
# -------------------------------------------------------
_ziraat_seans_disi_tutar_kontrol() {
    local lot="$1"
    local fiyat="$2"

    local simdi
    simdi=$(date +%H:%M)
    local simdi_dk
    simdi_dk=$(( 10#${simdi%%:*} * 60 + 10#${simdi##*:} ))

    local bas_dk bit_dk
    bas_dk=$(( 10#${_ZIRAAT_SEANS_DISI_BASLANGIC%%:*} * 60 + 10#${_ZIRAAT_SEANS_DISI_BASLANGIC##*:} ))
    bit_dk=$(( 10#${_ZIRAAT_SEANS_DISI_BITIS%%:*} * 60 + 10#${_ZIRAAT_SEANS_DISI_BITIS##*:} ))

    # Seans disi mi? (17:30 - gece yarisi - 10:45 arasi)
    # Gece yarisini gecen aralik: bas > bit demek gece yarisini kapsar
    local seans_disi=0
    if [[ "$bas_dk" -gt "$bit_dk" ]]; then
        # Gece yarisini gecen aralik (17:30~10:45)
        if [[ "$simdi_dk" -ge "$bas_dk" ]] || [[ "$simdi_dk" -lt "$bit_dk" ]]; then
            seans_disi=1
        fi
    else
        # Normal aralik
        if [[ "$simdi_dk" -ge "$bas_dk" ]] && [[ "$simdi_dk" -lt "$bit_dk" ]]; then
            seans_disi=1
        fi
    fi

    if [[ "$seans_disi" -eq 0 ]]; then
        return 0
    fi

    # Tutar hesapla: lot * fiyat
    local tutar
    tutar=$(echo "$lot * $fiyat" | bc)

    # bc sonucunu karsilastirmak icin ondalik kismini da dahil et
    local min="$_ZIRAAT_SEANS_DISI_MIN_TUTAR"
    local yetersiz
    yetersiz=$(echo "$tutar < $min" | bc)

    if [[ "$yetersiz" -eq 1 ]]; then
        echo "HATA: Seans disi saatlerde ($_ZIRAAT_SEANS_DISI_BASLANGIC - $_ZIRAAT_SEANS_DISI_BITIS) ${min} TL altinda emir girilemez."
        echo "  Emir tutari: ${lot} lot x ${fiyat} TL = ${tutar} TL (minimum: ${min} TL)"
        return 1
    fi

    return 0
}

# =======================================================
# BOLUM 2: GENEL ARABIRIM (cekirdek.sh tarafindan cagrilir)
# =======================================================

adaptor_giris() {
    local musteri_no="$1"
    local parola="$2"

    if [[ -z "$musteri_no" ]] || [[ -z "$parola" ]]; then
        echo "Kullanim: borsa ziraat giris <MUSTERI_NO> <PAROLA>"
        return 1
    fi

    # Oturum dizinini onceden hazirla (cookie dosyasi icin gerekli)
    cekirdek_aktif_hesap_ayarla "ziraat" "$musteri_no"
    _ziraat_oturum_dizini "$musteri_no" > /dev/null

    # Mevcut oturum gecerli mi kontrol et — gecerliyse SMS'e gerek yok
    if adaptor_oturum_gecerli_mi "$musteri_no"; then
        _ziraat_log "Oturum zaten acik (Musteri: $musteri_no). Tekrar giris gereksiz."
        echo ""
        echo "========================================="
        echo " OTURUM ZATEN ACIK"
        echo "========================================="
        echo " Musteri : $musteri_no"
        echo " Durum   : Cookie gecerli, SMS gerekmedi."
        echo "========================================="
        echo ""
        return 0
    fi

    local degerler
    if ! degerler=$(_ziraat_sayfa_hazirla); then
        _ziraat_log "HATA: Giris sayfasi hazirlanamadi. Giris iptal edildi."
        return 1
    fi

    local host_val="${degerler%%|*}"
    local token_val="${degerler#*|}"

    # Token bos geldiyse devam etme
    if [[ -z "$token_val" ]]; then
        _ziraat_log "HATA: Token bos, giris yapilamaz."
        return 1
    fi

    _ziraat_log "Giris istegi gonderiliyor (Musteri: $musteri_no)..."

    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")

    _ziraat_giris_sonuc=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Referer: $_ZIRAAT_LOGIN_URL" \
        -H "Origin: $_ZIRAAT_BASE_URL" \
        --data-urlencode "InputCustomerNo=$musteri_no" \
        --data-urlencode "Passphrase=$parola" \
        --data-urlencode "HostName=$host_val" \
        --data-urlencode "__RequestVerificationToken=$token_val" \
        --data-urlencode "CaptchaCodeText=" \
        "$_ZIRAAT_LOGIN_URL")

    if echo "$_ziraat_giris_sonuc" | grep -q "$_ZIRAAT_KALIP_HATALI_GIRIS"; then
        _ziraat_log "HATA: Kullanici adi veya parola yanlis."
        cekirdek_aktif_hesap_ayarla "ziraat" ""
        return 1
    elif echo "$_ziraat_giris_sonuc" | grep -q "$_ZIRAAT_KALIP_SMS"; then
        _ziraat_log "SMS dogrulama ekrani tespit edildi."
        _ziraat_sms_dogrula "$token_val" "$musteri_no" "$parola"
    else
        _ziraat_log "Giris tamamlandi (veya bilinmeyen sayfa)."
        cekirdek_yazdir_giris_basarili "$ADAPTOR_ADI"
    fi
}

adaptor_bakiye() {
    if ! _ziraat_aktif_hesap_kontrol; then
        return 1
    fi

    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")
    local debug_dosyasi
    debug_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_DEBUG")

    if [[ ! -f "$cookie_dosyasi" ]]; then
        echo "HATA: Oturum bulunamadi. Once giris yapin: borsa ziraat giris ..."
        return 1
    fi

    _ziraat_log "Portfoy bilgisi sorgulanıyor..."

    local ana_yanit
    ana_yanit=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_ANA_SAYFA_URL")

    local session_guid
    session_guid=$(echo "$ana_yanit" | grep -oP "$_ZIRAAT_SEL_SESSION_GUID")

    # Oturum sonlanma tespiti: session_guid yoksa ve login formu varsa oturum dolmuştur
    if [[ -z "$session_guid" ]]; then
        if echo "$ana_yanit" | grep -qP "$_ZIRAAT_SEL_CSRF_TOKEN"; then
            _ziraat_log "OTURUM SONLANDI: Sunucu giris sayfasina yonlendirdi."
            echo ""
            echo "========================================="
            echo " OTURUM SURESI DOLDU"
            echo " Tekrar giris yapin: borsa ziraat giris"
            echo "========================================="
            echo ""
            return 1
        fi
        _ziraat_log "UYARI: Session GUID bulunamadi ancak login formu yok. Devam ediliyor."
    else
        _ziraat_log "Session GUID: $session_guid"
    fi

    _ziraat_log "Portfoy sayfasi isteniyor: $_ZIRAAT_PORTFOY_URL"

    local ham_yanit
    ham_yanit=$(cekirdek_istek_at \
        -w "\nHTTP_CODE:%{http_code}" \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Referer: $_ZIRAAT_ANA_SAYFA_URL" \
        "$_ZIRAAT_PORTFOY_URL")

    local http_kodu
    http_kodu=$(echo "$ham_yanit" | grep -oP 'HTTP_CODE:\K[0-9]+' | tail -n 1)
    local portfoy_yaniti
    portfoy_yaniti="${ham_yanit//HTTP_CODE:${http_kodu}/}"

    _ziraat_log "HTTP Yanit Kodu: $http_kodu"

    if [[ "$http_kodu" == "200" ]] && echo "$portfoy_yaniti" | grep -q 'Toplam'; then
        local nakit hisse toplam
        nakit=$(echo "$portfoy_yaniti" | grep -oP "id=\"${_ZIRAAT_ID_NAKIT}\"[^>]*>\K[^<]+" | tr -d ' \n\t')
        hisse=$(echo "$portfoy_yaniti" | grep -oP "id=\"${_ZIRAAT_ID_HISSE}\"[^>]*>\K[^<]+" | tr -d ' \n\t')
        toplam=$(echo "$portfoy_yaniti" | grep -A 10 "$_ZIRAAT_METIN_TOPLAM" | grep -oP '[0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}' | head -n 1 | tr -d ' \n\t')

        if ! cekirdek_saglik_kontrol \
                "$ADAPTOR_ADI" "$http_kodu" "$portfoy_yaniti" "$debug_dosyasi" \
                "$nakit" "$hisse" "$toplam" \
                "Portfoy" "Hesap" "Toplam"; then
            echo "UYARI: Saglik kontrol basarisiz. Veri gosterilmiyor."
            echo "Debug icin bakin: $debug_dosyasi"
            return 1
        fi

        cekirdek_yazdir_portfoy "$ADAPTOR_ADI" "$nakit" "$hisse" "$toplam"
        _ziraat_log "Bakiye sorgusu basarili: Toplam $toplam TL"
    else
        _ziraat_log "HATA: Portfoy sayfasi beklenen formatta degil (Kod: $http_kodu)."
        echo "UYARI: Portfoy sayfasi beklenen formatta degil (Kod: $http_kodu)."
        echo "Debug: $debug_dosyasi inceleyin."
        echo "$portfoy_yaniti" > "$debug_dosyasi"
        return 1
    fi
}

adaptor_emirleri_listele() {
    # Bekleyen hisse emirlerini listeler.
    # ListTransactionOperation AJAX endpoint'i HTML fragment doner.
    # ONEMLI: Sunucu HTML'i tek satir (newline'siz) dondurur.
    #   Bu yuzden satir-bazli grep islemleri calismaz.
    #   Cozum: sed ile her <tr'den once newline ekleyerek blok-bazli parse yapmak.
    # HTML yapisi (analizden):
    #   <tr id="FOFT5U-20260220" data-id="20260220FOFT5U" data-chainno="0" ...>
    #     ...emir verileri (sembol, fiyat, adet)...
    #     <div name="btnListDailyDelete" data-id="20260220FOFT5U" data-ext-id="FOFT5U" ...>
    #   </tr>

    _ziraat_aktif_hesap_kontrol || return 1

    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")
    local emir_liste_dosyasi
    emir_liste_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_EMIR_LISTE")

    _ziraat_log "Bekleyen emirler sorgulanıyor..."
    _ziraat_cookie_guvence

    # CSRF token gerekiyor — emir sayfasindan al
    local sayfa
    sayfa=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_EMIR_URL")
    _ziraat_cookie_guvence

    local csrf
    csrf=$(echo "$sayfa" | grep -oP "$_ZIRAAT_SEL_CSRF_TOKEN" | tail -n 1)
    if [[ -z "$csrf" ]]; then
        _ziraat_log "HATA: CSRF token alinamadi. Oturum expired olmis olabilir."
        echo "HATA: Oturum acik degil. Oncelikle: borsa ziraat giris"
        return 1
    fi

    local liste_yaniti
    liste_yaniti=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Referer: $_ZIRAAT_EMIR_URL" \
        -H "X-Requested-With: XMLHttpRequest" \
        --data-urlencode "__RequestVerificationToken=$csrf" \
        --data-urlencode "listTypeEnum=DAILY" \
        "$_ZIRAAT_EMIR_LISTE_URL")

    # Debug dosyasina kaydet (her sorguda guncellenir)
    echo "$liste_yaniti" > "$emir_liste_dosyasi"

    if [[ -z "$liste_yaniti" ]]; then
        _ziraat_log "HATA: Emir listesi yaniti bos."
        echo "HATA: Emir listesi alinamadi."
        return 1
    fi

    # Sunucu bazen JSON hata donebilir (oturum dusmus veya teknik sorun)
    if echo "$liste_yaniti" | grep -qP '"Success"\s*:\s*false'; then
        local hata_mesaji
        hata_mesaji=$(echo "$liste_yaniti" | grep -oP '"Message"\s*:\s*"\K[^"]+')
        _ziraat_log "HATA: Sunucu JSON hata dondu: $hata_mesaji"
        echo "HATA: ${hata_mesaji:-Bilinmeyen sunucu hatasi}"
        echo "Oturum suresi dolmus olabilir. Tekrar giris yapin: borsa ziraat giris"
        return 1
    fi

    # HTML tek satir gelebilir — her <tr'den once newline ekle,
    # boylece her emir blogu ayri bir satira duser.
    local birlesik
    birlesik=$(echo "$liste_yaniti" | tr '\n' ' ' | sed 's/<tr /\n<tr /g')

    echo ""
    echo "=========================================================================="
    printf " %-12s %-8s %-6s %-10s %-6s %-12s\n" \
        "REFERANS" "HISSE" "A/S" "FIYAT" "ADET" "DURUM"
    echo "=========================================================================="

    local bulunan=0
    while IFS= read -r blok; do
        # Sadece emir satirlari: data-chainno iceren <tr> bloklari
        echo "$blok" | grep -q 'data-chainno' || continue

        local ext_id sembol_p islem_p fiyat_p adet_p durum_p iptal_var

        # Referans: oncelikle <tr id="FOFT5U-20260220"> seklinden al
        ext_id=$(echo "$blok" | grep -oP '<tr[^>]* id="\K[A-Za-z0-9]+(?=-)' | head -1)
        # Yoksa data-ext-id'den dene (iptal butonundan)
        if [[ -z "$ext_id" ]]; then
            ext_id=$(echo "$blok" | grep -oP 'data-ext-id="\K[^"]+' | head -1)
        fi

        # Hisse sembolu — <div style="font-weight: normal !important;">AKBNK</div>
        # NOT: <label> da ayni style'a sahip ama referans no icerir.
        #      <div etiketini spesifik olarak hedefle.
        sembol_p=$(echo "$blok" | grep -oP '<div style="font-weight: normal !important;">\K[A-Z0-9]+' | head -1)

        # Islem tipi (Alis/Satis)
        islem_p=$(echo "$blok" | grep -oP 'hidden-xs">\K[^<]+' | head -1)
        islem_p=$(echo "$islem_p" | xargs)

        # Fiyat
        fiyat_p=$(echo "$blok" | grep -oP 'class="tar">\K[0-9.,]+' | head -1)

        # Adet (oldUnits)
        adet_p=$(echo "$blok" | grep -oP 'class="oldUnits">\K[0-9]+' | head -1)

        # Durum (equityOrderStatus sinifindaki CSS siniftan)
        durum_p=$(echo "$blok" | grep -oP 'equityOrderStatus \K[a-z]+' | head -1)
        case "$durum_p" in
            forwarded)  durum_p="Iletildi" ;;
            rejected)   durum_p="Iptal" ;;
            realized)   durum_p="Gerceklesti" ;;
            partial)    durum_p="Kismi" ;;
            *)          durum_p="${durum_p:-?}" ;;
        esac

        # Iptal butonu var mi? (aktif emir gostergesi)
        iptal_var=""
        echo "$blok" | grep -q 'btnListDailyDelete' && iptal_var="[*]"

        printf " %-12s %-8s %-6s %-10s %-6s %-12s %s\n" \
            "${ext_id:-?}" "${sembol_p:-?}" "${islem_p:-?}" \
            "${fiyat_p:-?}" "${adet_p:-?}" "$durum_p" "$iptal_var"
        bulunan=$((bulunan + 1))
    done <<< "$birlesik"

    if [[ "$bulunan" -eq 0 ]]; then
        echo " (Emir bulunamadi)"
    fi

    echo "=========================================================================="
    echo " [*] = Iptal edilebilir emir"
    echo " Iptal icin: borsa ziraat iptal <REFERANS>"
    echo "=========================================================================="
    echo ""
    _ziraat_log "Toplam $bulunan emir listelendi. Debug: $emir_liste_dosyasi"
    return 0
}

adaptor_emir_iptal() {
    # Emiri iptal eder.
    # $1: referans no (ext_id) — borsa ziraat emirler ciktisinda gorunur.
    #     Ornek: FOFT5U
    # ONEMLI: HTML tek satir gelebilir, blok-bazli parse gerekir.
    local ext_id="$1"   # Orn: FOFT5U

    if [[ -z "$ext_id" ]]; then
        echo "Kullanim: $ADAPTOR_ADI iptal <REFERANS>"
        echo "Referans numarasini gormek icin once: borsa ziraat emirler"
        return 1
    fi
    _ziraat_aktif_hesap_kontrol || return 1

    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")
    local iptal_debug_dosyasi
    iptal_debug_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_IPTAL_DEBUG")
    _ziraat_log "Emir iptal ediliyor. Referans: $ext_id"
    _ziraat_cookie_guvence

    # CSRF token gerekiyor
    local sayfa
    sayfa=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_EMIR_URL")
    _ziraat_cookie_guvence

    local csrf
    csrf=$(echo "$sayfa" | grep -oP "$_ZIRAAT_SEL_CSRF_TOKEN" | tail -n 1)
    if [[ -z "$csrf" ]]; then
        _ziraat_log "HATA: CSRF token alinamadi."
        echo "HATA: Oturum acik degil. Oncelikle: borsa ziraat giris"
        return 1
    fi

    # Emir listesinden transactionId (data-id) degerini bul
    local liste_yaniti
    liste_yaniti=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Referer: $_ZIRAAT_EMIR_URL" \
        -H "X-Requested-With: XMLHttpRequest" \
        --data-urlencode "__RequestVerificationToken=$csrf" \
        --data-urlencode "listTypeEnum=DAILY" \
        "$_ZIRAAT_EMIR_LISTE_URL")

    # Sunucu JSON hata donduyse
    if echo "$liste_yaniti" | grep -qP '"Success"\s*:\s*false'; then
        local hata_mesaji
        hata_mesaji=$(echo "$liste_yaniti" | grep -oP '"Message"\s*:\s*"\K[^"]+')
        _ziraat_log "HATA: Sunucu JSON hata dondu: $hata_mesaji"
        echo "HATA: ${hata_mesaji:-Bilinmeyen sunucu hatasi}"
        echo "Oturum suresi dolmus olabilir. Tekrar giris yapin: borsa ziraat giris"
        return 1
    fi

    # HTML tek satir gelebilir — iptal butonunun oldugu blogu bul.
    # Strateji: sed ile <div bloklarini ayir, data-ext-id esleseni bul,
    # oradan data-id cek.
    local transaction_id
    # Yontem 1: Tek satirda tum HTML varsa, data-ext-id="FOFT5U" yakinindan
    # data-id cek. btnListDailyDelete div'ini ayristir.
    # Ornek: name="btnListDailyDelete" data-id="20260220FOFT5U" data-ext-id="FOFT5U"
    transaction_id=$(echo "$liste_yaniti" | \
        grep -oP "btnListDailyDelete[^>]*data-id=\"\K[^\"]+(?=[^>]*data-ext-id=\"${ext_id}\")" | head -1)
    if [[ -z "$transaction_id" ]]; then
        # Yontem 2: data-ext-id once data-id sonra gelebilir
        transaction_id=$(echo "$liste_yaniti" | \
            grep -oP "data-ext-id=\"${ext_id}\"[^>]*data-id=\"\K[^\"]+")
    fi
    if [[ -z "$transaction_id" ]]; then
        # Yontem 3: <tr id="FOFT5U-..." data-id="20260220FOFT5U" seklinden
        transaction_id=$(echo "$liste_yaniti" | \
            grep -oP "<tr[^>]* id=\"${ext_id}-[^\"]*\"[^>]*data-id=\"\K[^\"]+")
    fi

    if [[ -z "$transaction_id" ]]; then
        _ziraat_log "HATA: $ext_id referansli emir listede bulunamadi."
        echo "HATA: '$ext_id' referansli bekleyen emir bulunamadi."
        echo "Mevcut emirleri gormek icin: borsa ziraat emirler"
        return 1
    fi

    _ziraat_log "transactionId: $transaction_id | transactionExId: $ext_id"

    # Iptal istegi gonder
    local iptal_yaniti
    iptal_yaniti=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Referer: $_ZIRAAT_EMIR_URL" \
        -H "X-Requested-With: XMLHttpRequest" \
        --data-urlencode "__RequestVerificationToken=$csrf" \
        --data-urlencode "transactionId=$transaction_id" \
        --data-urlencode "transactionExId=$ext_id" \
        "$_ZIRAAT_EMIR_IPTAL_URL")

    if [[ -z "$iptal_yaniti" ]]; then
        _ziraat_log "HATA: Iptal yaniti bos."
        echo "HATA: Sunucudan yanit alinamadi."
        return 1
    fi

    # JSON yaniti analiz et.
    # Ziraat API'si basarili iptalde bile IsSuccess=false dondurur!
    # Gercek basari gostergesi: "Data":"SILMEOK" veya IsSuccess=true
    # Gercek hata gostergesi: "IsError":true
    local veri_alani
    veri_alani=$(echo "$iptal_yaniti" | grep -oP '"Data"\s*:\s*"\K[^"]+' | head -1)

    if [[ "$veri_alani" == "SILMEOK" ]] || \
       echo "$iptal_yaniti" | grep -qiE '"[Ii]s[Ss]uccess"\s*:\s*true'; then
        local mesaj
        mesaj=$(echo "$iptal_yaniti" | grep -oP '"[Mm]essage"\s*:\s*"\K[^"]+' | head -1)
        _ziraat_log "BASARILI: Emir iptal edildi. Referans: $ext_id (Data=$veri_alani)"
        echo ""
        echo "========================================="
        echo " EMIR IPTAL EDILDI"
        echo "========================================="
        echo " Referans : $ext_id"
        echo " Trans.ID : $transaction_id"
        echo " Durum    : IPTAL TALEBI ALINDI"
        if [[ -n "$mesaj" ]]; then
            echo " Mesaj    : $mesaj"
        fi
        echo "========================================="
        echo ""
        return 0
    fi

    # IsError=true ise kesin hata
    if echo "$iptal_yaniti" | grep -qiE '"[Ii]s[Ee]rror"\s*:\s*true'; then
        local hata
        hata=$(echo "$iptal_yaniti" | grep -oP '"[Mm]essage"\s*:\s*"\K[^"]+' | head -1)
        _ziraat_log "HATA: Emir iptal basarisiz. Yanit: $iptal_yaniti"
        echo "HATA: ${hata:-Emir iptal edilemedi.}"
        return 1
    fi

    # Bilinmeyen durum — mesaji goster, debug dosyasina kaydet
    local hata
    hata=$(echo "$iptal_yaniti" | grep -oP '"[Mm]essage"\s*:\s*"\K[^"]+' | head -1)
    _ziraat_log "UYARI: Iptal yaniti beklenmeyen formatta. Yanit: $iptal_yaniti"
    echo "$iptal_yaniti" > "$iptal_debug_dosyasi"
    if [[ -n "$hata" ]]; then
        echo "UYARI: $hata"
        echo "Sonucu dogrulamak icin: borsa ziraat emirler"
    else
        echo "UYARI: Beklenmeyen yanit. Debug: $iptal_debug_dosyasi"
    fi
    return 1
}

adaptor_emir_gonder() {
    local sembol="$1"          # Ornek: THYAO, AKBNK
    local islem="$2"           # alis | satis
    local lot="$3"             # Lot adedi
    local fiyat="$4"           # Limit fiyat (zorunlu)
    local bildirim_turu="$5"   # Bildirim turu (opsiyonel): mobil | eposta | hepsi | yok

    # --- Parametre Kontrolu ---
    if [[ -z "$sembol" || -z "$islem" || -z "$lot" || -z "$fiyat" ]]; then
        echo "Kullanim: $ADAPTOR_ADI emir SEMBOL alis|satis LOT FIYAT [mobil|eposta|hepsi|yok]"
        return 1
    fi

    # Sembol buyuk harf
    sembol="${sembol^^}"

    # Islem turu
    local islem_kodu
    case "$islem" in
        alis)  islem_kodu="$_ZIRAAT_EMIR_ALIS" ;;
        satis) islem_kodu="$_ZIRAAT_EMIR_SATIS" ;;
        *)
            echo "HATA: Gecersiz islem turu '$islem'. Kullanim: alis | satis"
            return 1
            ;;
    esac

    # Bildirim turu eslestirme
    local bildirim_deger
    case "${bildirim_turu:-hepsi}" in
        mobil)  bildirim_deger="$_ZIRAAT_BILDIRIM_MOBIL" ;;
        eposta) bildirim_deger="$_ZIRAAT_BILDIRIM_EPOSTA" ;;
        hepsi)  bildirim_deger="$_ZIRAAT_BILDIRIM_HEPSI" ;;
        yok)    bildirim_deger="$_ZIRAAT_BILDIRIM_YOK" ;;
        *)
            echo "HATA: Gecersiz bildirim turu '$bildirim_turu'. Secenekler: mobil | eposta | hepsi | yok"
            return 1
            ;;
    esac

    # Lot ve fiyat sayisal mi?
    if ! cekirdek_sayi_dogrula "$lot" "Lot" "$ADAPTOR_ADI"; then
        return 1
    fi
    if ! cekirdek_sayi_dogrula "$fiyat" "Fiyat" "$ADAPTOR_ADI"; then
        return 1
    fi

    # Ziraat seans disi minimum tutar kontrolu (BIST uyarisindan once yapilir,
    # aksi halde "emir islenecek" uyarisi gosterilip ardindan engellenir)
    if ! _ziraat_seans_disi_tutar_kontrol "$lot" "$fiyat"; then
        return 1
    fi

    # BIST fiyat adimi dogrulamasi
    if ! bist_emir_dogrula "$fiyat"; then
        return 1
    fi

    # Kuru calistirma modu (KURU_CALISTIR=1 ile aktif edilir)
    if [[ "${KURU_CALISTIR:-0}" == "1" ]]; then
        _ziraat_log "KURU CALISTIR: $islem $lot lot $sembol @ $fiyat TL (emir GONDERILMEDI)"
        echo ""
        echo "========================================="
        echo " [KURU CALISTIR] EMIR BILGISI"
        echo "========================================="
        echo " Sembol : $sembol"
        echo " Islem  : $islem ($islem_kodu)"
        echo " Lot    : $lot"
        echo " Fiyat  : $fiyat TL"
        echo " Durum  : GONDERILMEDI"
        echo "========================================="
        echo ""
        return 0
    fi

    # --- Emir Sayfasini Cek (Taze CSRF Token + Hesap ID) ---
    _ziraat_aktif_hesap_kontrol || return 1

    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")
    local emir_yanit_dosyasi
    emir_yanit_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_EMIR_YANIT")

    _ziraat_log "Emir formu hazirlaniyor: $sembol $islem $lot lot @ $fiyat TL..."

    local emir_sayfasi
    emir_sayfasi=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_EMIR_URL")

    local emir_csrf
    # Sayfada 2 CSRF token var: layout tokeni ve wizardForm tokeni.
    # Son eslesme (tail -n 1) wizardForm'un tokenini alir.
    emir_csrf=$(echo "$emir_sayfasi" | grep -oP "$_ZIRAAT_SEL_CSRF_TOKEN" | tail -n 1)
    if [[ -z "$emir_csrf" ]]; then
        _ziraat_log "HATA: Emir formu CSRF token bulunamadi. Oturum sonlamis olabilir."
        return 1
    fi

    local hesap_id
    hesap_id=$(echo "$emir_sayfasi" | grep -oP "$_ZIRAAT_SEL_HESAP_ID" | head -1)
    if [[ -z "$hesap_id" ]]; then
        _ziraat_log "HATA: Hesap ID bulunamadi. Oturum sonlamis olabilir."
        return 1
    fi

    local hostname_val
    hostname_val=$(echo "$emir_sayfasi" | grep -oP "$_ZIRAAT_SEL_HOSTNAME")
    [[ -z "$hostname_val" ]] && hostname_val="$_ZIRAAT_FALLBACK_HOSTNAME"

    _ziraat_log "Hesap: $hesap_id | Token: ${emir_csrf:0:10}..."

    # GET sayfasindaki WizardPageName hidden degerini parse et.
    # Sunucu GET'te bu alani LayoutWizardSecondPage olarak render eder,
    # yani tek POST ile dogrudan onay adimina gidilir.
    local wizard_adim
    wizard_adim=$(echo "$emir_sayfasi" | grep -oP 'name="WizardPageName"[^>]*value="\K[^"]+')
    if [[ -z "$wizard_adim" ]]; then
        # GET sayfasindan parse edilemezse varsayilan kullan
        wizard_adim="$_ZIRAAT_EMIR_WIZARD_ADIM2"
        _ziraat_log "UYARI: WizardPageName GET sayfasindan alinamadi, varsayilan kullaniliyor: $wizard_adim"
    else
        _ziraat_log "WizardPageName: $wizard_adim"
    fi

    _ziraat_log "Emir gonderiliyor: $islem $lot lot $sembol @ $fiyat TL"
    

    # Tarih alanlari (HTML hidden input formatina gore: DD.MM.YYYY)
    local bugun
    bugun=$(date '+%d.%m.%Y')
    local dun
    dun=$(date -d 'yesterday' '+%d.%m.%Y')

    # =========================================================
    # POST: Emir + Onay tek seferde gonderilir.
    # button=NextButton: JS'in wizardForm.submit() oncesinde
    # $('#buttonName').val('NextButton') ile set ettigi deger.
    # WizardPageName: GET sayfasindan alinan deger (SecondPage).
    # =========================================================
    local son_url
    son_url=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Referer: $_ZIRAAT_EMIR_URL" \
        -H "Origin: $_ZIRAAT_BASE_URL" \
        --data-urlencode "__RequestVerificationToken=$emir_csrf" \
        --data-urlencode "ddlActiveAccount=$hesap_id" \
        --data-urlencode "EquityCode=$sembol" \
        --data-urlencode "DebitCreditH=$islem_kodu" \
        --data-urlencode "Unit=$lot" \
        --data-urlencode "Price=$fiyat" \
        --data-urlencode "PriceEquity=$fiyat" \
        --data-urlencode "AmountType=$_ZIRAAT_EMIR_BIRIM" \
        --data-urlencode "TimeInForce=$_ZIRAAT_EMIR_GUNLUK" \
        --data-urlencode "SpecialOrderType=$_ZIRAAT_EMIR_NORMAL" \
        --data-urlencode "WizardPageName=$wizard_adim" \
        --data-urlencode "button=NextButton" \
        --data-urlencode "NotificationType=$bildirim_deger" \
        --data-urlencode "HostName=$hostname_val" \
        --data-urlencode "NowDate=$bugun" \
        --data-urlencode "ValueDate=$bugun" \
        --data-urlencode "MinDate=$dun 00:00:00" \
        --data-urlencode "virmanCheck=0" \
        --data-urlencode "ApproveRequired=false" \
        --data-urlencode "RiskApprove=False" \
        -w "\n__SONURL__:%{url_effective}" \
        -o "$emir_yanit_dosyasi" \
        "$_ZIRAAT_EMIR_URL")
    # __SONURL__: on ekini temizle
    son_url="${son_url##*__SONURL__:}"
    local emir_yaniti
    emir_yaniti=$(cat "$emir_yanit_dosyasi")

    # --- Yanit Kontrolu ---
    local emir_boyut="${#emir_yaniti}"
    if [[ "$emir_boyut" -lt 10 ]]; then
        _ziraat_log "HATA: Emir yaniti bos ($emir_boyut bayt)."
        return 1
    fi

    # Redirect tespiti: son URL AddOrder'i icermiyorsa emir kabul edildi
    if [[ -n "$son_url" ]] && ! echo "$son_url" | grep -q 'Equity/AddOrder'; then
        _ziraat_log "BASARILI: Emir kabul edildi. Redirect: $son_url"
        echo ""
        echo "========================================="
        echo " EMIR KABUL EDILDI"
        echo "========================================="
        echo " Sembol : $sembol"
        echo " Islem  : $islem"
        echo " Lot    : $lot"
        echo " Fiyat  : $fiyat TL"
        echo " Durum  : ILETILDI"
        echo "========================================="
        echo ""
        return 0
    fi

    # =========================================================
    # ONAY SAYFASI TESPITI (LayoutWizardResultPage)
    # Sunucu emir bilgilerini aldiktan sonra onay ozet sayfasini
    # doner (redirect yok, ayni URL). Bu sayfada kullanici
    # "Onay" butonuna tiklar = button=FinishButton ile POST yapilir.
    # =========================================================
    local sonraki_wizard
    sonraki_wizard=$(echo "$emir_yaniti" | grep -oP 'name="WizardPageName"[^>]*value="\K[^"]+')

    if [[ "$sonraki_wizard" == "LayoutWizardResultPage" ]]; then
        _ziraat_log "Onay ozet sayfasi geldi. FinishButton ile tamamlaniyor..."

        # Onay sayfasindaki taze CSRF token
        local onay_csrf
        onay_csrf=$(echo "$emir_yaniti" | grep -oP "$_ZIRAAT_SEL_CSRF_TOKEN" | tail -n 1)

        # Son POST: FinishButton ile emri tamamla
        local son_url2
        son_url2=$(cekirdek_istek_at \
            -c "$cookie_dosyasi" \
            -b "$cookie_dosyasi" \
            -H "Referer: $_ZIRAAT_EMIR_URL" \
            -H "Origin: $_ZIRAAT_BASE_URL" \
            --data-urlencode "__RequestVerificationToken=$onay_csrf" \
            --data-urlencode "ddlActiveAccount=$hesap_id" \
            --data-urlencode "EquityCode=$sembol" \
            --data-urlencode "DebitCreditH=$islem_kodu" \
            --data-urlencode "Unit=$lot" \
            --data-urlencode "Price=$fiyat" \
            --data-urlencode "PriceEquity=$fiyat" \
            --data-urlencode "AmountType=$_ZIRAAT_EMIR_BIRIM" \
            --data-urlencode "TimeInForce=$_ZIRAAT_EMIR_GUNLUK" \
            --data-urlencode "SpecialOrderType=$_ZIRAAT_EMIR_NORMAL" \
            --data-urlencode "WizardPageName=$sonraki_wizard" \
            --data-urlencode "button=FinishButton" \
            --data-urlencode "NotificationType=$bildirim_deger" \
            --data-urlencode "HostName=$hostname_val" \
            --data-urlencode "NowDate=$bugun" \
            --data-urlencode "ValueDate=$bugun" \
            --data-urlencode "MinDate=$dun 00:00:00" \
            --data-urlencode "virmanCheck=0" \
            --data-urlencode "ApproveRequired=false" \
            --data-urlencode "RiskApprove=False" \
            -w "\n__SONURL__:%{url_effective}" \
            -o "$emir_yanit_dosyasi" \
            "$_ZIRAAT_EMIR_URL")
        # __SONURL__: on ekini temizle
        son_url2="${son_url2##*__SONURL__:}"

        local son_yanit
        son_yanit=$(cat "$emir_yanit_dosyasi")

        # Ziraat basarili emirde redirect yapmaz, ayni URL'de kalir.
        # "kaydedilmiştir" metni ve referans numarasi basari gostergesidir.
        local referans_no
        referans_no=$(echo "$son_yanit" | grep -oP '\b[A-Z0-9]{6,}\b(?=.*referans)' | head -1)
        if [[ -z "$referans_no" ]]; then
            # Alternatif: dogrudan referans kelimesinin yanindaki buyuk harf kodu
            referans_no=$(echo "$son_yanit" | grep -oP '(?<=referans[ıi]yla kaydedilmi)[^<]*' | head -1)
            referans_no=$(echo "$son_yanit" | grep -oP '[A-Z0-9]{5,}(?=[^<]*referans)' | head -1)
        fi

        if echo "$son_yanit" | grep -qiE "kaydedilmi|iletilmi|referans"; then
            _ziraat_log "BASARILI: Emir kabul edildi. Referans: ${referans_no:-bilinmiyor}"
            echo ""
            echo "========================================="
            echo " EMIR KABUL EDILDI"
            echo "========================================="
            echo " Sembol    : $sembol"
            echo " Islem     : $islem"
            echo " Lot       : $lot"
            echo " Fiyat     : $fiyat TL"
            echo " Referans  : ${referans_no:-HTML icin bakin: $emir_yanit_dosyasi}"
            echo " Durum     : ILETILDI"
            echo "========================================="
            echo ""
            return 0
        fi

        _ziraat_log "HATA: FinishButton sonrasi emir kabul edilmedi. Son URL: $son_url2"
        local hata_metni2
        hata_metni2=$(_ziraat_html_hata_cikar "$son_yanit")
        if [[ -n "$hata_metni2" ]]; then
            echo "HATA: $hata_metni2"
        else
            echo "HATA: Emir reddedildi. Debug: $emir_yanit_dosyasi"
        fi
        _ziraat_log "Debug dosyasi: $emir_yanit_dosyasi"
        return 1
    fi

    # Ne redirect ne SMS tespiti - gercek hata var
    _ziraat_log "HATA: Emir kabul edilmedi. Son URL: $son_url | WizardPage: $sonraki_wizard"
    local hata_metni
    hata_metni=$(_ziraat_html_hata_cikar "$emir_yaniti")
    if [[ -n "$hata_metni" ]]; then
        echo "HATA: $hata_metni"
    else
        echo "HATA: Emir reddedildi. Debug icin: $emir_yanit_dosyasi"
    fi
    _ziraat_log "Debug dosyasi: $emir_yanit_dosyasi"
    return 1
}

# adaptor_hesap() ve adaptor_hesaplar() tanimlanmiyor.
# cekirdek.sh'daki cekirdek_hesap() ve cekirdek_hesaplar()
# jenerik implementasyonlari kullanilir.
# Oturum gecerlilik kontrolu icin adaptor_oturum_gecerli_mi()
# callback'i BOLUM 1'de tanimlidir.
