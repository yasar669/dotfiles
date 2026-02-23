#!/bin/bash
# shellcheck shell=bash

# Ziraat Yatirim Adaptoru
# Bu dosya dogrudan calistirilmaz, cekirdek.sh tarafindan yuklenir.
# Konfigürasyon ve URL: ziraat.ayarlar.sh dosyasinda.
# HTTP istekleri: cekirdek.sh'daki cekirdek_istek_at() ile yapilir.

# shellcheck disable=SC2034
# Degisken onceki source'dan readonly kalabilir — hatadan kacinmak
# icin sadece farkli degerde veya tanimsizsa ata.
if [[ "${ADAPTOR_ADI:-}" != "ziraat" ]]; then
    ADAPTOR_ADI="ziraat" 2>/dev/null || true
fi
if [[ "${ADAPTOR_SURUMU:-}" != "1.0.0" ]]; then
    ADAPTOR_SURUMU="1.0.0" 2>/dev/null || true
fi

# Ayarlar dosyasini yukle
# shellcheck source=/home/yasar/dotfiles/bashrc.d/borsa/adaptorler/ziraat.ayarlar.sh
source "${BORSA_KLASORU}/adaptorler/ziraat.ayarlar.sh"

# =======================================================
# BOLUM 1: DAHILI YARDIMCILAR (Disaridan cagrilmaz)
# =======================================================

# Oturum yonetimi cekirdek fonksiyonlarina delege edilir.
# cekirdek_adaptor_kaydet ince sarmalayicilari (thin wrappers) otomatik olusturur:
#   _ziraat_oturum_dizini, _ziraat_dosya_yolu, _ziraat_aktif_hesap_kontrol,
#   _ziraat_log, _ziraat_cookie_guvence
cekirdek_adaptor_kaydet "ziraat"

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
    fi
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
        # Oturum suresini parse et ve kaydet
        local _oturum_suresi
        _oturum_suresi=$(adaptor_oturum_suresi_parse "$sms_sonuc")
        cekirdek_oturum_suresi_kaydet "ziraat" "$musteri_no" "$_oturum_suresi"
        cekirdek_son_istek_guncelle "ziraat" "$musteri_no"
    elif echo "$sms_sonuc" | grep -q "$_ZIRAAT_KALIP_BASARILI_JSON"; then
        _ziraat_log "BASARILI: Giris tamamlandi (JSON)."
        local redirect_url
        redirect_url=$(echo "$sms_sonuc" | grep -oP '"url":"\K[^"]+')
        _ziraat_log "Yonlendirilecek URL: $redirect_url"
        # JSON basarida da oturum suresini kaydet
        cekirdek_oturum_suresi_kaydet "ziraat" "$musteri_no" "1500"
        cekirdek_son_istek_guncelle "ziraat" "$musteri_no"
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
        cekirdek_yazdir_oturum_bilgi "OTURUM ZATEN ACIK" \
            "Musteri" "$musteri_no" \
            "Durum" "Cookie gecerli, SMS gerekmedi."
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

# _ziraat_portfoy_sayfasi_cek
# Ortak yardimci: Oturum + portfoy sayfasi HTTP istegini yapar.
# Hem adaptor_bakiye hem adaptor_portfoy bu fonksiyonu kullanir.
# Basariliysa portfoy HTML'ini _ziraat_portfoy_html degiskenine yazar.
# Donus: 0 = basarili (HTML _ziraat_portfoy_html'de), 1 = hata (mesaj yazildi)
_ziraat_portfoy_sayfasi_cek() {
    if ! _ziraat_aktif_hesap_kontrol; then
        return 1
    fi

    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")

    if [[ ! -f "$cookie_dosyasi" ]]; then
        echo "HATA: Oturum bulunamadi. Once giris yapin: borsa ziraat giris ..."
        return 1
    fi

    # Ana sayfaya git (session guid kontrolu + cookie yenileme)
    local ana_yanit
    ana_yanit=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_ANA_SAYFA_URL")

    local session_guid
    session_guid=$(echo "$ana_yanit" | grep -oP "$_ZIRAAT_SEL_SESSION_GUID")

    # Oturum sonlanma tespiti
    if [[ -z "$session_guid" ]]; then
        if echo "$ana_yanit" | grep -qP "$_ZIRAAT_SEL_CSRF_TOKEN"; then
            _ziraat_log "OTURUM SONLANDI: Sunucu giris sayfasina yonlendirdi."
            cekirdek_yazdir_oturum_bilgi "OTURUM SURESI DOLDU" \
                "Tekrar giris yapin: borsa ziraat giris"
            return 1
        fi
        _ziraat_log "UYARI: Session GUID bulunamadi ancak login formu yok. Devam ediliyor."
    fi

    # Portfoy sayfasini cek
    local ham_yanit
    ham_yanit=$(cekirdek_istek_at \
        -w "\nHTTP_CODE:%{http_code}" \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Referer: $_ZIRAAT_ANA_SAYFA_URL" \
        "$_ZIRAAT_PORTFOY_URL")

    local http_kodu
    http_kodu=$(echo "$ham_yanit" | grep -oP 'HTTP_CODE:\K[0-9]+' | tail -n 1)
    _ziraat_portfoy_html="${ham_yanit//HTTP_CODE:${http_kodu}/}"
    _ziraat_portfoy_http_kodu="$http_kodu"

    if [[ "$http_kodu" != "200" ]]; then
        local debug_dosyasi
        debug_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_DEBUG")
        _ziraat_log "HATA: Portfoy sayfasi alinamadi (Kod: $http_kodu)."
        echo "HATA: Portfoy sayfasi alinamadi (HTTP $http_kodu)."
        echo "$_ziraat_portfoy_html" > "$debug_dosyasi"
        return 1
    fi

    return 0
}

adaptor_bakiye() {
    if ! _ziraat_portfoy_sayfasi_cek; then
        return 1
    fi

    local portfoy_yaniti="$_ziraat_portfoy_html"
    local http_kodu="$_ziraat_portfoy_http_kodu"
    local debug_dosyasi
    debug_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_DEBUG")

    if echo "$portfoy_yaniti" | grep -q 'Toplam'; then
        _borsa_veri_sifirla_bakiye
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

        _borsa_veri_kaydet_bakiye "$nakit" "$hisse" "$toplam"
        cekirdek_yazdir_portfoy "$ADAPTOR_ADI" "$nakit" "$hisse" "$toplam"
    else
        _ziraat_log "HATA: Portfoy sayfasi beklenen formatta degil (Kod: $http_kodu)."
        echo "UYARI: Portfoy sayfasi beklenen formatta degil (Kod: $http_kodu)."
        echo "Debug: $debug_dosyasi inceleyin."
        echo "$portfoy_yaniti" > "$debug_dosyasi"
        return 1
    fi
}

adaptor_portfoy() {
    # Portfoydeki hisse senetlerini detayli listeler.
    # Her hisse icin: sembol, lot, son fiyat, piyasa degeri, maliyet, kar/zarar, kar %
    # HTML yapisi: <tr id="wdg_portfolio_HESAP_ID"> icerisinde:
    #   1. <td> Sembol (ilk td)
    #   2. <span id="wdg_portfolio_balance_*"> Lot
    #   3. <span id="wdg_portfolio_last_*"> Son fiyat
    #   4. <td id="wdg_portfolio_marketvalue_*"> Piyasa degeri
    #   5. <td id="wdg_portfolio_cost_*"> Maliyet
    #   6. <span id="profit_total"> Kar/Zarar
    #   7. <span id="profit_change"> Kar %

    if ! _ziraat_portfoy_sayfasi_cek; then
        return 1
    fi

    local portfoy_yaniti="$_ziraat_portfoy_html"
    _borsa_veri_sifirla_portfoy

    # Nakit ve toplam degerleri cek
    local nakit hisse_toplam toplam
    nakit=$(echo "$portfoy_yaniti" | grep -oP "id=\"${_ZIRAAT_ID_NAKIT}\"[^>]*>\K[^<]+" | tr -d ' \n\t')
    hisse_toplam=$(echo "$portfoy_yaniti" | grep -oP "id=\"${_ZIRAAT_ID_HISSE}\"[^>]*>\K[^<]+" | tr -d ' \n\t')
    toplam=$(echo "$portfoy_yaniti" | grep -A 10 "$_ZIRAAT_METIN_TOPLAM" | grep -oP '[0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}' | head -n 1 | tr -d ' \n\t')

    _borsa_veri_sifirla_bakiye
    _borsa_veri_kaydet_bakiye "$nakit" "$hisse_toplam" "$toplam"

    # Hisse satir ID'lerini bul
    local hesap_idler
    hesap_idler=$(grep -oP "$_ZIRAAT_SEL_PORTFOY_HESAP_ID" <<< "$portfoy_yaniti")

    if [[ -z "$hesap_idler" ]]; then
        cekirdek_yazdir_portfoy_bos "${nakit:-0.00}"
        return 0
    fi

    # HTML'i satir-bazli parse icin hazirla (newline gerektigi icin sed zorunlu)
    local temiz_html
    # shellcheck disable=SC2001
    temiz_html=$(sed 's/></>\n</g' <<< "$portfoy_yaniti")

    # Her hisse icin veri cikar
    # Strateji: Her hisse icin <tr>...</tr> blogunu bir kez cikar, tum alanlari ondan parse et.
    # Boylece ayri ayri grep/sed cagrilari azalir ve desen carpismasi onlenir.
    local satirlar=""
    local hesap_id
    while IFS= read -r hesap_id; do
        [[ -z "$hesap_id" ]] && continue

        # TR blogunu cikar: <tr id="wdg_portfolio_HESAP_ID">...</tr>
        local tr_blok
        tr_blok=$(sed -n "/wdg_portfolio_${hesap_id}\"/,/<\/tr/p" <<< "$temiz_html")

        # Sembol: ilk <td> icindeki metin
        local sembol
        sembol=$(grep -A1 '<td' <<< "$tr_blok" | head -2 | tail -1 | tr -d ' \t\n\r')

        # Lot: <span id="wdg_portfolio_balance_*"> sonraki satir
        local lot
        lot=$(grep -A1 "wdg_portfolio_balance_" <<< "$tr_blok" | tail -1 | tr -d ' \t\n\r')

        # Son fiyat: <span id="wdg_portfolio_last_*"> sonraki satir
        local son_fiyat
        son_fiyat=$(grep -A1 "wdg_portfolio_last_" <<< "$tr_blok" | tail -1 | tr -d ' \t\n\r')

        # Piyasa degeri: <td id="wdg_portfolio_marketvalue_*"> sonraki satir
        local piy_degeri
        piy_degeri=$(grep -A1 "wdg_portfolio_marketvalue_" <<< "$tr_blok" | tail -1 | tr -d ' \t\n\r')

        # Maliyet: <td id="wdg_portfolio_cost_*"> sonraki satir
        local maliyet
        maliyet=$(grep -A1 "wdg_portfolio_cost_" <<< "$tr_blok" | tail -1 | tr -d ' \t\n\r')

        # Kar/Zarar: <span id="profit_total"> icindeki sayi
        local kar_zarar
        kar_zarar=$(grep -oP '(?<=>)-?[0-9,.]+(?=</span)' <<< "$tr_blok" | head -1)

        # Kar yuzde: <span id="profit_change"> icindeki %-X,X
        local kar_yuzde
        kar_yuzde=$(tr -d '\n' <<< "$tr_blok" | grep -oP '%-?[0-9,.]+')

        if [[ -n "$sembol" ]]; then
            # Tab karakteri ile ayir (literal tab, echo -e gerekmez)
            printf -v satir_fmt "%s\t%s\t%s\t%s\t%s\t%s\t%s" \
                "$sembol" "$lot" "$son_fiyat" "$piy_degeri" "$maliyet" "$kar_zarar" "$kar_yuzde"
            _borsa_veri_kaydet_hisse "$sembol" "$lot" "$son_fiyat" "$piy_degeri" "$maliyet" "$kar_zarar" "$kar_yuzde"
            if [[ -n "$satirlar" ]]; then
                satirlar+=$'\n'"$satir_fmt"
            else
                satirlar="$satir_fmt"
            fi
        fi
    done <<< "$hesap_idler"
    _BORSA_VERI_PORTFOY_ZAMAN=$(date +%s)

    if [[ -z "$satirlar" ]]; then
        cekirdek_yazdir_portfoy_bos "${nakit:-0.00}"
        return 0
    fi

    cekirdek_yazdir_portfoy_detay "$ADAPTOR_ADI" "$nakit" "$hisse_toplam" "$toplam" "$satirlar"
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
    csrf=$(cekirdek_csrf_cikar "$sayfa" "$_ZIRAAT_SEL_CSRF_TOKEN" "Emir sayfasi" "$ADAPTOR_ADI") || {
        echo "HATA: Oturum acik degil. Oncelikle: borsa ziraat giris"; return 1; }

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
    _borsa_veri_sifirla_emirler
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
        _borsa_veri_kaydet_emir "$ext_id" "${sembol_p:-}" "${islem_p:-}" "${adet_p:-}" "${fiyat_p:-}" "$durum_p" "$iptal_var"

        printf " %-12s %-8s %-6s %-10s %-6s %-12s %s\n" \
            "${ext_id:-?}" "${sembol_p:-?}" "${islem_p:-?}" \
            "${fiyat_p:-?}" "${adet_p:-?}" "$durum_p" "$iptal_var"
        bulunan=$((bulunan + 1))
    done <<< "$birlesik"
    _BORSA_VERI_EMIRLER_ZAMAN=$(date +%s)

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
    _borsa_veri_sifirla_son_emir

    # Trap: fonksiyon nasil biterse bitsin son emir kaydedilir
    local _vk_basarili="0" _vk_mesaj="Iptal basarisiz"
    trap '_borsa_veri_kaydet_son_emir "$_vk_basarili" "$ext_id" "" "IPTAL" "" "" "0" "$_vk_mesaj"' RETURN

    _ziraat_cookie_guvence

    # CSRF token gerekiyor
    local sayfa
    sayfa=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_EMIR_URL")
    _ziraat_cookie_guvence

    local csrf
    csrf=$(cekirdek_csrf_cikar "$sayfa" "$_ZIRAAT_SEL_CSRF_TOKEN" "Emir iptal sayfasi" "$ADAPTOR_ADI") || {
        echo "HATA: Oturum acik degil. Oncelikle: borsa ziraat giris"; return 1; }

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
    # "SILMEOK" Data alaninda ozel basari gostergesi.
    local json_mesaj
    json_mesaj=$(cekirdek_json_sonuc_isle "$iptal_yaniti" "SILMEOK")
    case $? in
        0)  # Basari
            _ziraat_log "BASARILI: Emir iptal edildi. Referans: $ext_id"
            cekirdek_yazdir_emir_iptal "$ext_id" "$transaction_id" "IPTAL TALEBI ALINDI" "$json_mesaj"
            _vk_basarili="1"; _vk_mesaj="${json_mesaj:-Emir iptal edildi}"
            return 0
            ;;
        1)  # Hata
            _ziraat_log "HATA: Emir iptal basarisiz. Yanit: $iptal_yaniti"
            echo "HATA: ${json_mesaj:-Emir iptal edilemedi.}"
            _vk_mesaj="${json_mesaj:-Iptal basarisiz}"
            return 1
            ;;
        *)  # Bilinmeyen durum
            _ziraat_log "UYARI: Iptal yaniti beklenmeyen formatta. Yanit: $iptal_yaniti"
            echo "$iptal_yaniti" > "$iptal_debug_dosyasi"
            if [[ -n "$json_mesaj" ]]; then
                echo "UYARI: $json_mesaj"
                echo "Sonucu dogrulamak icin: borsa ziraat emirler"
            else
                echo "UYARI: Beklenmeyen yanit. Debug: $iptal_debug_dosyasi"
            fi
            _vk_mesaj="${json_mesaj:-Bilinmeyen iptal sonucu}"
            return 1
            ;;
    esac
}

adaptor_emir_gonder() {
    local sembol="$1"          # Ornek: THYAO, AKBNK
    local islem="$2"           # alis | satis
    local lot="$3"             # Lot adedi
    local fiyat="$4"           # Limit fiyat veya "piyasa"
    local bildirim_turu="$5"   # Bildirim turu (opsiyonel): mobil | eposta | hepsi | yok
    _borsa_veri_sifirla_son_emir

    # --- Parametre Kontrolu ---
    if [[ -z "$sembol" || -z "$islem" || -z "$lot" || -z "$fiyat" ]]; then
        echo "Kullanim: $ADAPTOR_ADI emir SEMBOL alis|satis LOT FIYAT|piyasa [mobil|eposta|hepsi|yok]"
        return 1
    fi

    # Sembol buyuk harf
    sembol="${sembol^^}"

    # --- Emir turu tespiti: piyasa vs limit ---
    local emir_birim
    local emir_sure
    local piyasa_mi=0

    if [[ "${fiyat,,}" == "piyasa" ]]; then
        piyasa_mi=1
        emir_birim="$_ZIRAAT_EMIR_BIRIM_PIYASA"  # MKT
        emir_sure="$_ZIRAAT_EMIR_KIE"             # 3 (tek secenek)
        fiyat="0"
    else
        emir_birim="$_ZIRAAT_EMIR_BIRIM"          # LOT
        emir_sure="$_ZIRAAT_EMIR_GUNLUK"          # 0 (Gunluk)
    fi

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

    # Lot sayisal mi?
    if ! cekirdek_sayi_dogrula "$lot" "Lot" "$ADAPTOR_ADI"; then
        return 1
    fi

    # Limit emirlerde fiyat, seans disi tutar ve BIST adim kontrolu yapilir.
    # Piyasa emirlerinde fiyat sunucu tarafindan belirlendigi icin atlanir.
    if [[ "$piyasa_mi" -eq 0 ]]; then
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
    fi

    # Trap: fonksiyon nasil biterse bitsin son emir kaydedilir
    local _vk_basarili="0" _vk_referans="" _vk_mesaj="Emir reddedildi"
    trap '_borsa_veri_kaydet_son_emir "$_vk_basarili" "$_vk_referans" "$sembol" "${islem^^}" "$lot" "$fiyat" "$piyasa_mi" "$_vk_mesaj"' RETURN

    # Kuru calistirma modu (KURU_CALISTIR=1 ile aktif edilir)
    local fiyat_gosterim
    if [[ "$piyasa_mi" -eq 1 ]]; then
        fiyat_gosterim="PIYASA"
    else
        fiyat_gosterim="$fiyat TL"
    fi

    if [[ "${KURU_CALISTIR:-0}" == "1" ]]; then
        _ziraat_log "KURU CALISTIR: $islem $lot lot $sembol @ $fiyat_gosterim (emir GONDERILMEDI)"
        cekirdek_yazdir_emir_sonuc "[KURU CALISTIR] EMIR BILGISI" \
            "$sembol" "$islem ($islem_kodu)" "$lot" "$fiyat_gosterim" "$emir_birim" "GONDERILMEDI"
        _vk_basarili="1"; _vk_referans="KURU"
        _vk_mesaj="Kuru calistirma — emir gonderilmedi"
        return 0
    fi

    # --- Emir Sayfasini Cek (Taze CSRF Token + Hesap ID) ---
    _ziraat_aktif_hesap_kontrol || return 1

    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")
    local emir_yanit_dosyasi
    emir_yanit_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_EMIR_YANIT")

    _ziraat_log "Emir formu hazirlaniyor: $sembol $islem $lot lot @ $fiyat_gosterim..."

    local emir_sayfasi
    emir_sayfasi=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_EMIR_URL")

    local emir_csrf
    # Sayfada 2 CSRF token var: layout tokeni ve wizardForm tokeni.
    # Son eslesme (tail -n 1) wizardForm'un tokenini alir.
    emir_csrf=$(cekirdek_csrf_cikar "$emir_sayfasi" "$_ZIRAAT_SEL_CSRF_TOKEN" "Emir formu" "$ADAPTOR_ADI") || return 1

    local hesap_id
    hesap_id=$(echo "$emir_sayfasi" | grep -oP "$_ZIRAAT_SEL_HESAP_ID" | head -1)
    if [[ -z "$hesap_id" ]]; then
        _ziraat_log "HATA: Hesap ID bulunamadi. Oturum sonlamis olabilir."
        return 1
    fi

    local hostname_val
    hostname_val=$(echo "$emir_sayfasi" | grep -oP "$_ZIRAAT_SEL_HOSTNAME")
    [[ -z "$hostname_val" ]] && hostname_val="$_ZIRAAT_FALLBACK_HOSTNAME"

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

    _ziraat_log "Emir gonderiliyor: $islem $lot lot $sembol @ $fiyat_gosterim"
    

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
        --data-urlencode "AmountType=$emir_birim" \
        --data-urlencode "TimeInForce=$emir_sure" \
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
        cekirdek_yazdir_emir_sonuc "EMIR KABUL EDILDI" \
            "$sembol" "$islem" "$lot" "$fiyat_gosterim" "$emir_birim" "ILETILDI"
        _vk_basarili="1"; _vk_mesaj="Emir kabul edildi (redirect)"
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
            --data-urlencode "AmountType=$emir_birim" \
            --data-urlencode "TimeInForce=$emir_sure" \
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
            cekirdek_yazdir_emir_sonuc "EMIR KABUL EDILDI" \
                "$sembol" "$islem" "$lot" "$fiyat_gosterim" "$emir_birim" "ILETILDI" \
                "${referans_no:-HTML icin bakin: $emir_yanit_dosyasi}"
            _vk_basarili="1"; _vk_referans="${referans_no:-}"
            _vk_mesaj="Emiriniz kaydedilmistir"
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
        _vk_mesaj="${hata_metni:-${hata_metni2:-Emir reddedildi}}"
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
    _vk_mesaj="${hata_metni:-${hata_metni2:-Emir reddedildi}}"
    return 1
}

# =======================================================
# BOLUM 3: HALKA ARZ (IPO) FONKSIYONLARI
# =======================================================

# -------------------------------------------------------
# adaptor_halka_arz_liste
# Aktif halka arzlari ve islem limitini listeler.
# Kaynak: /sanalsube/tr/IPO/ListIPO sayfasi (HTML parse)
# -------------------------------------------------------
adaptor_halka_arz_liste() {
    _ziraat_aktif_hesap_kontrol || return 1

    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")

    _ziraat_log "Halka arz listesi sorgulanıyor..."

    local sayfa
    sayfa=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_IPO_LISTE_URL")

    cekirdek_boyut_kontrol "$sayfa" 500 "Halka arz sayfasi" "$ADAPTOR_ADI" || return 1
    cekirdek_oturum_yonlendirme_kontrol "$sayfa" "Account/Login" "$ADAPTOR_ADI" || return 1

    # Halka arz islem limitini cikar
    # Iki farkli regex denenir: IpoLimitFont class'i veya genel Limit kelimesi
    local limit
    limit=$(echo "$sayfa" | tr '\n' ' ' | grep -oP "$_ZIRAAT_IPO_SEL_LIMIT_1" | head -1)
    if [[ -z "$limit" ]]; then
        limit=$(echo "$sayfa" | tr '\n' ' ' | grep -oP "$_ZIRAAT_IPO_SEL_LIMIT_2" | head -1)
    fi

    # Aktif halka arzlari parse et
    # Her arz bir btnsubmit butonunda data-ipoid, data-name attribute'leri ile belirlenir.
    # Tablo sutunlari: Halka Arz, Basvuru Tipi, Halka Arz Tipi, Hareket Tipi, Odeme Sekli...
    local satirlar=""
    _borsa_veri_sifirla_halka_arz_liste

    # Tablo icerigini kontrol et — arz var mi?
    if echo "$sayfa" | grep -qP 'btnsubmit'; then
        # HTML'i satirlara bol, btnsubmit butonlarini isle
        local temiz_html
        # shellcheck disable=SC2001
        temiz_html=$(sed 's/></>\n</g' <<< "$sayfa")

        # Her btnsubmit'ten IpoId ve Name cikar
        local ipo_bloklari
        ipo_bloklari=$(echo "$temiz_html" | grep -P 'btnsubmit')

        while IFS= read -r blok; do
            [[ -z "$blok" ]] && continue
            local ipo_id ipo_adi
            ipo_id=$(echo "$blok" | grep -oP "$_ZIRAAT_IPO_SEL_IPOID" | head -1)
            ipo_adi=$(echo "$blok" | grep -oP "$_ZIRAAT_IPO_SEL_ADI" | head -1)
            [[ -z "$ipo_id" ]] && continue

            # Tablo satirindan tip ve odeme bilgilerini cikar
            # btnsubmit ayni tablodaki <tr> icerisinde; TR'yi bul
            local fininstid
            fininstid=$(echo "$blok" | grep -oP "$_ZIRAAT_IPO_SEL_FININSTID" | head -1)

            # Tablo icerisindeki td'lerden bilgileri cekmeyi dene
            local arz_tip="" odeme="" durum="AKTIF"

            # Eger tabloda daha detayli parse gerekiyorsa tr blogunu bul
            if [[ -n "$fininstid" ]]; then
                local tr_blok
                tr_blok=$(echo "$sayfa" | tr '\n' ' ' | grep -oP "<tr[^>]*id=\"${fininstid}\"[^>]*>.*?</tr>" | head -1)
                if [[ -n "$tr_blok" ]]; then
                    # td'leri cikar (basit sirayla)
                    local td_listesi
                    td_listesi=$(echo "$tr_blok" | grep -oP '<td[^>]*>.*?</td>' | sed 's/<[^>]*>//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    arz_tip=$(echo "$td_listesi" | sed -n '3p')
                    odeme=$(echo "$td_listesi" | sed -n '5p')
                fi
            fi

            local satir="${ipo_adi}\t${arz_tip:-Bilinmiyor}\t${odeme:-Bilinmiyor}\t${durum}\t${ipo_id}"
            _borsa_veri_kaydet_halka_arz "$ipo_id" "${ipo_adi:-}" "${arz_tip:-}" "${odeme:-}" "${durum:-AKTIF}"
            if [[ -z "$satirlar" ]]; then
                satirlar="$satir"
            else
                satirlar="${satirlar}\n${satir}"
            fi
        done <<< "$ipo_bloklari"
    fi

    local cozulmus_satirlar
    cozulmus_satirlar=$(echo -e "$satirlar")

    _borsa_veri_kaydet_halka_arz_limit "$limit"
    cekirdek_yazdir_halka_arz_liste "$ADAPTOR_ADI" "$limit" "$cozulmus_satirlar"
    _ziraat_log "Halka arz listesi tamamlandi. Limit: ${limit:-bilinmiyor} TL"
}

# -------------------------------------------------------
# adaptor_halka_arz_talepler
# Halka arz taleplerim listesini gosterir.
# Kaynak: /sanalsube/tr/IPO/IPOTransactionsList sayfasi
# -------------------------------------------------------
adaptor_halka_arz_talepler() {
    _ziraat_aktif_hesap_kontrol || return 1

    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")

    _ziraat_log "Halka arz taleplerim sorgulanıyor..."

    # Islem listesi sayfasini cek (POST formu var, tarih parametreleri gerekiyor)
    local bugun
    bugun=$(date '+%d.%m.%Y')

    # Once sayfayi GET ile cek — CSRF token ve form bilgisi icin
    local sayfa
    sayfa=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_IPO_ISLEMLER_URL")

    cekirdek_boyut_kontrol "$sayfa" 500 "Halka arz islem listesi" "$ADAPTOR_ADI" || return 1
    cekirdek_oturum_yonlendirme_kontrol "$sayfa" "Account/Login" "$ADAPTOR_ADI" || return 1

    local satirlar=""
    _borsa_veri_sifirla_halka_arz_talepler

    # Tablo bos mu kontrol et
    if echo "$sayfa" | grep -qP 'kayıt bulunamad|bulunmamaktad'; then
        _BORSA_VERI_TALEPLER_ZAMAN=$(date +%s)
        cekirdek_yazdir_halka_arz_talepler "$ADAPTOR_ADI" ""
        return 0
    fi

    # HTML tablosunu parse et
    # Tablo tek satir gelebilir — <tr'leri ayir
    local birlesik
    birlesik=$(echo "$sayfa" | tr '\n' ' ' | sed 's/<tr /\n<tr /g')

    while IFS= read -r blok; do
        # Sadece veri satirlarini isle (data-id iceren tr'ler)
        echo "$blok" | grep -qP 'data-id=|data-ipoid=' || continue
        # Header satirlarini atla
        echo "$blok" | grep -qP '<th' && continue

        # td iceriklerini cikar
        local td_listesi
        td_listesi=$(echo "$blok" | grep -oP '<td[^>]*>.*?</td>' | sed 's/<[^>]*>//g; s/&[^;]*;//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        local td_sayisi
        td_sayisi=$(echo "$td_listesi" | wc -l)
        [[ "$td_sayisi" -lt 5 ]] && continue

        local ad tarih lot fiyat tutar durum
        ad=$(echo "$td_listesi" | sed -n '1p')
        tarih=$(echo "$td_listesi" | sed -n '2p')
        lot=$(echo "$td_listesi" | sed -n '4p')
        fiyat=$(echo "$td_listesi" | sed -n '5p')
        tutar=$(echo "$td_listesi" | sed -n '6p')
        durum=$(echo "$td_listesi" | sed -n '8p')

        # Talep ID'sini cikar (iptal/guncelle icin gerekli)
        local talep_id
        talep_id=$(echo "$blok" | grep -oP 'data-id="\K[^"]+' | head -1)
        [[ -z "$talep_id" ]] && talep_id=$(echo "$blok" | grep -oP 'id="\K[^"]+' | head -1)

        [[ -z "$ad" ]] && continue

        local satir="${ad}\t${tarih}\t${lot}\t${fiyat}\t${tutar}\t${durum}\t${talep_id}"
        _borsa_veri_kaydet_talep "$talep_id" "${ad:-}" "${tarih:-}" "${lot:-}" "${fiyat:-}" "${tutar:-}" "${durum:-}"
        if [[ -z "$satirlar" ]]; then
            satirlar="$satir"
        else
            satirlar="${satirlar}\n${satir}"
        fi
    done <<< "$birlesik"

    local cozulmus_satirlar
    cozulmus_satirlar=$(echo -e "$satirlar")

    _BORSA_VERI_TALEPLER_ZAMAN=$(date +%s)
    cekirdek_yazdir_halka_arz_talepler "$ADAPTOR_ADI" "$cozulmus_satirlar"
    _ziraat_log "Halka arz talepler listesi tamamlandi."
}

# -------------------------------------------------------
# adaptor_halka_arz_talep <ipo_adi_veya_id> <lot>
# Belirtilen halka arza talep girisi yapar.
# Akis: ListIPO GET → IpoId bul → DetailIPO POST → Wizard form doldur
# -------------------------------------------------------
adaptor_halka_arz_talep() {
    local ipo_arama="$1"   # Halka arz adi veya ID
    local lot="$2"         # Talep edilen lot

    if [[ -z "$ipo_arama" || -z "$lot" ]]; then
        echo "Kullanim: borsa $ADAPTOR_ADI arz talep <IPO_ADI_veya_ID> <LOT>"
        return 1
    fi

    if ! cekirdek_sayi_dogrula "$lot" "Lot" "$ADAPTOR_ADI"; then
        return 1
    fi

    _ziraat_aktif_hesap_kontrol || return 1
    _borsa_veri_sifirla_son_halka_arz

    # Trap: fonksiyon nasil biterse bitsin son halka arz kaydedilir
    local _vk_basarili="0" _vk_mesaj="Talep reddedildi"
    trap '_borsa_veri_kaydet_son_halka_arz "$_vk_basarili" "talep" "$_vk_mesaj" "${ipo_adi:-}" "${ipo_id:-}" "$lot" "${fiyat:-}" ""' RETURN

    local cookie_dosyasi

    _ziraat_log "Halka arz talebi hazirlaniyor: $ipo_arama, $lot lot..."

    # 1. Liste sayfasindan IpoId ve form bilgilerini al
    local liste_sayfa
    liste_sayfa=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_IPO_LISTE_URL")

    cekirdek_boyut_kontrol "$liste_sayfa" 500 "Halka arz sayfasi" "$ADAPTOR_ADI" || return 1
    cekirdek_oturum_yonlendirme_kontrol "$liste_sayfa" "Account/Login" "$ADAPTOR_ADI" || return 1

    # Aktif arz var mi?
    if ! echo "$liste_sayfa" | grep -qP 'btnsubmit'; then
        echo "HATA: Tanimli halka arz bulunmamaktadir."
        return 1
    fi

    # IpoId'yi bul — isme gore veya dogrudan ID ile
    local ipo_id="" ipo_adi=""
    local temiz_ipo
    # shellcheck disable=SC2001
    temiz_ipo=$(sed 's/></>\n</g' <<< "$liste_sayfa")
    local ipo_butonlari
    ipo_butonlari=$(echo "$temiz_ipo" | grep -P 'btnsubmit')

    while IFS= read -r buton; do
        [[ -z "$buton" ]] && continue
        local gecici_id gecici_adi
        gecici_id=$(echo "$buton" | grep -oP "$_ZIRAAT_IPO_SEL_IPOID" | head -1)
        gecici_adi=$(echo "$buton" | grep -oP "$_ZIRAAT_IPO_SEL_ADI" | head -1)
        [[ -z "$gecici_id" ]] && continue

        # Arama: ID eslesmesi veya isim icinde arama (buyuk/kucuk harf duyarsiz)
        if [[ "$gecici_id" == "$ipo_arama" ]] || \
           echo "$gecici_adi" | grep -qi "$ipo_arama"; then
            ipo_id="$gecici_id"
            ipo_adi="$gecici_adi"
            break
        fi
    done <<< "$ipo_butonlari"

    if [[ -z "$ipo_id" ]]; then
        echo "HATA: '$ipo_arama' ile eslesen halka arz bulunamadi."
        echo "Mevcut halka arzlari gormek icin: borsa $ADAPTOR_ADI arz liste"
        return 1
    fi

    _ziraat_log "Halka arz bulundu: $ipo_adi (ID: $ipo_id)"

    # 2. CSRF token — liste sayfasindan al
    local csrf
    csrf=$(cekirdek_csrf_cikar "$liste_sayfa" "$_ZIRAAT_SEL_CSRF_TOKEN" "Halka arz liste" "$ADAPTOR_ADI") || {
        echo "HATA: CSRF token alinamadi. Oturum sorunu olabilir."; return 1; }

    # 3. Yatirimci tipi ve odeme sekli bilgilerini al
    local yatirimci_tipi="$_ZIRAAT_IPO_YATIRIMCI_TIPI"

    # Odeme tipi: Sayfadaki dropdown'dan ilk secenegi al
    local odeme_tipi_id=""
    local odeme_tipi_adi=""
    local odeme_dd
    odeme_dd=$(echo "$liste_sayfa" | tr '\n' ' ' | grep -oP "ddlPaymentType_${ipo_id}[^<]*<option[^>]*value=\"\K[^\"]+")
    if [[ -n "$odeme_dd" ]]; then
        odeme_tipi_id="$odeme_dd"
        odeme_tipi_adi=$(echo "$liste_sayfa" | tr '\n' ' ' | grep -oP "ddlPaymentType_${ipo_id}[^<]*<option[^>]*value=\"${odeme_dd}\"[^>]*>\K[^<]+")
    fi

    # Taksit bilgisi
    local taksit_id=""
    local taksit_dd
    taksit_dd=$(echo "$liste_sayfa" | tr '\n' ' ' | grep -oP "ddlFirstInstallment_${ipo_id}[^<]*<option[^>]*value=\"\K[^\"]+")
    [[ -n "$taksit_dd" ]] && taksit_id="$taksit_dd"

    _ziraat_log "Odeme: ${odeme_tipi_adi:-varsayilan} | Taksit: ${taksit_id:-yok}"

    # 4. DetailIPO sayfasina POST — talep formunu ac
    local detay_yanit
    detay_yanit=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Referer: $_ZIRAAT_IPO_LISTE_URL" \
        -H "Origin: $_ZIRAAT_BASE_URL" \
        --data-urlencode "__RequestVerificationToken=$csrf" \
        --data-urlencode "IpoId=$ipo_id" \
        --data-urlencode "PaymentTypeId=$odeme_tipi_id" \
        --data-urlencode "PaymentTypeName=$odeme_tipi_adi" \
        --data-urlencode "FirstInstallmentId=$taksit_id" \
        --data-urlencode "Name=$ipo_adi" \
        --data-urlencode "InvesterTypeId=$yatirimci_tipi" \
        --data-urlencode "InvestorTypeList=" \
        --data-urlencode "isHiglyInvestor=" \
        "$_ZIRAAT_IPO_DETAY_URL")

    cekirdek_boyut_kontrol "$detay_yanit" 500 "Halka arz detay sayfasi" "$ADAPTOR_ADI" || return 1

    # Hata kontrolu
    if echo "$detay_yanit" | grep -qiP 'validation-summary-errors'; then
        local hata_metni
        hata_metni=$(_ziraat_html_hata_cikar "$detay_yanit")
        if [[ -n "$hata_metni" ]]; then
            echo "HATA: $hata_metni"
        else
            echo "HATA: Halka arz detay sayfasinda dogrulama hatasi."
        fi
        echo "$detay_yanit" > "$debug_dosyasi"
        _ziraat_log "Debug: $debug_dosyasi"
        _vk_mesaj="${hata_metni:-Talep reddedildi}"
        return 1
    fi

    # 5. DetailIPO sayfasindaki talep formunu parse et
    # Bu sayfa WizardForm yapisi kullanir (emir gibi)
    local detay_csrf
    detay_csrf=$(cekirdek_csrf_cikar "$detay_yanit" "$_ZIRAAT_SEL_CSRF_TOKEN" "Detay sayfasi" "$ADAPTOR_ADI") || {
        echo "HATA: Talep formu CSRF token alinamadi."
        echo "$detay_yanit" > "$debug_dosyasi"; return 1; }

    # Hesap ID
    local hesap_id
    hesap_id=$(echo "$detay_yanit" | grep -oP "$_ZIRAAT_SEL_HESAP_ID" | head -1)

    # WizardPageName
    local wizard_adim
    wizard_adim=$(echo "$detay_yanit" | grep -oP 'name="WizardPageName"[^>]*value="\K[^"]+')
    [[ -z "$wizard_adim" ]] && wizard_adim="LayoutWizardSecondPage"

    # Fiyat bilgisi (sayfadan)
    local fiyat
    fiyat=$(echo "$detay_yanit" | tr '\n' ' ' | grep -oP 'name="Price"[^>]*value="\K[^"]+' | head -1)
    [[ -z "$fiyat" ]] && fiyat=$(echo "$detay_yanit" | tr '\n' ' ' | grep -oP 'id="Price"[^>]*value="\K[^"]+' | head -1)

    # Minimum talep (lot)
    local min_lot
    min_lot=$(echo "$detay_yanit" | tr '\n' ' ' | grep -oP 'name="MinUnit"[^>]*value="\K[^"]+' | head -1)
    [[ -z "$min_lot" ]] && min_lot=$(echo "$detay_yanit" | tr '\n' ' ' | grep -oP 'MinimumDemand[^>]*value="\K[^"]+' | head -1)

    # Minimum lot kontrolu
    if [[ -n "$min_lot" ]] && [[ "$lot" -lt "$min_lot" ]] 2>/dev/null; then
        echo "HATA: Minimum talep miktari $min_lot lot. Girilen: $lot lot."
        return 1
    fi

    _ziraat_log "Talep gonderiliyor: $ipo_adi, $lot lot, fiyat: ${fiyat:-belirsiz}"

    # Kuru calistirma modu
    if [[ "${KURU_CALISTIR:-0}" == "1" ]]; then
        _ziraat_log "KURU CALISTIR: Halka arz talebi GONDERILMEDI"
        cekirdek_yazdir_arz_sonuc "[KURU CALISTIR] HALKA ARZ TALEBI" \
            "Halka Arz" "$ipo_adi" \
            "IPO ID" "$ipo_id" \
            "Lot" "$lot" \
            "Fiyat" "${fiyat:-belirsiz}" \
            "Min. Lot" "${min_lot:-belirsiz}" \
            "Hesap" "${hesap_id:-bilinmiyor}" \
            "Durum" "GONDERILMEDI"
        _vk_basarili="1"; _vk_mesaj="Kuru calistirma — talep gonderilmedi"
        return 0
    fi

    # 6. Talep formunu POST et (NextButton — wizard adim 1)
    local ipo_yanit_dosyasi
    ipo_yanit_dosyasi=$(_ziraat_dosya_yolu "ipo_yanit.html")

    local son_url
    son_url=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Referer: $_ZIRAAT_IPO_DETAY_URL" \
        -H "Origin: $_ZIRAAT_BASE_URL" \
        --data-urlencode "__RequestVerificationToken=$detay_csrf" \
        --data-urlencode "ddlActiveAccount=$hesap_id" \
        --data-urlencode "Unit=$lot" \
        --data-urlencode "Price=$fiyat" \
        --data-urlencode "WizardPageName=$wizard_adim" \
        --data-urlencode "button=NextButton" \
        -w "\n__SONURL__:%{url_effective}" \
        -o "$ipo_yanit_dosyasi" \
        "$_ZIRAAT_IPO_DETAY_URL")
    son_url="${son_url##*__SONURL__:}"

    local ipo_yaniti
    ipo_yaniti=$(cat "$ipo_yanit_dosyasi")

    # Hata kontrolu
    if [[ "${#ipo_yaniti}" -lt 50 ]]; then
        _ziraat_log "HATA: Talep yaniti cok kucuk (${#ipo_yaniti} bayt)."
        echo "HATA: Talep yaniti bos. Debug: $ipo_yanit_dosyasi"
        return 1
    fi

    if echo "$ipo_yaniti" | grep -qiP 'validation-summary-errors'; then
        local hata2
        hata2=$(_ziraat_html_hata_cikar "$ipo_yaniti")
        echo "HATA: ${hata2:-Talep formu dogrulama hatasi.}"
        _ziraat_log "Debug: $ipo_yanit_dosyasi"
        _vk_mesaj="${hata_metni:-Talep reddedildi}"
        return 1
    fi

    # 7. Onay sayfasi kontrolu (WizardResultPage)
    local sonraki_wizard
    sonraki_wizard=$(echo "$ipo_yaniti" | grep -oP 'name="WizardPageName"[^>]*value="\K[^"]+')

    if [[ "$sonraki_wizard" == "LayoutWizardResultPage" ]]; then
        _ziraat_log "Onay sayfasi geldi. FinishButton ile tamamlaniyor..."

        local onay_csrf
        onay_csrf=$(echo "$ipo_yaniti" | grep -oP "$_ZIRAAT_SEL_CSRF_TOKEN" | tail -n 1)

        local son_url2
        son_url2=$(cekirdek_istek_at \
            -c "$cookie_dosyasi" \
            -b "$cookie_dosyasi" \
            -H "Referer: $_ZIRAAT_IPO_DETAY_URL" \
            -H "Origin: $_ZIRAAT_BASE_URL" \
            --data-urlencode "__RequestVerificationToken=$onay_csrf" \
            --data-urlencode "ddlActiveAccount=$hesap_id" \
            --data-urlencode "Unit=$lot" \
            --data-urlencode "Price=$fiyat" \
            --data-urlencode "WizardPageName=$sonraki_wizard" \
            --data-urlencode "button=FinishButton" \
            -w "\n__SONURL__:%{url_effective}" \
            -o "$ipo_yanit_dosyasi" \
            "$_ZIRAAT_IPO_DETAY_URL")
        son_url2="${son_url2##*__SONURL__:}"

        local son_yanit
        son_yanit=$(cat "$ipo_yanit_dosyasi")

        if echo "$son_yanit" | grep -qiE 'kaydedilmi|kabul edilmi|ba.ar'; then
            _ziraat_log "BASARILI: Halka arz talebi kabul edildi."
            cekirdek_yazdir_arz_sonuc "HALKA ARZ TALEBI KABUL EDILDI" \
                "Halka Arz" "$ipo_adi" \
                "Lot" "$lot" \
                "Fiyat" "${fiyat:-piyasa}" \
                "Durum" "ILETILDI"
            _vk_basarili="1"; _vk_mesaj="Talep kabul edildi"
            return 0
        fi

        local hata3
        hata3=$(_ziraat_html_hata_cikar "$son_yanit")
        if [[ -n "$hata3" ]]; then
            echo "HATA: $hata3"
        else
            echo "HATA: Talep reddedildi. Debug: $ipo_yanit_dosyasi"
        fi
        _ziraat_log "Debug: $ipo_yanit_dosyasi"
        _vk_mesaj="${hata_metni:-Talep reddedildi}"
        return 1
    fi

    # Redirect tespiti — talep kabul edilmis olabilir
    if [[ -n "$son_url" ]] && ! echo "$son_url" | grep -qP 'DetailIPO|ListIPO'; then
        _ziraat_log "BASARILI: Talep kabul edildi (redirect). URL: $son_url"
        cekirdek_yazdir_arz_sonuc "HALKA ARZ TALEBI KABUL EDILDI" \
            "Halka Arz" "$ipo_adi" \
            "Lot" "$lot" \
            "Durum" "ILETILDI"
        _vk_basarili="1"; _vk_mesaj="Talep kabul edildi"
        return 0
    fi

    # Bilinmeyen durum
    local hata4
    hata4=$(_ziraat_html_hata_cikar "$ipo_yaniti")
    if [[ -n "$hata4" ]]; then
        echo "HATA: $hata4"
    else
        echo "HATA: Talep sonucu belirsiz. Debug: $ipo_yanit_dosyasi"
    fi
    _ziraat_log "Debug: $ipo_yanit_dosyasi"
    _vk_mesaj="${hata_metni:-Talep reddedildi}"
    return 1
}

# -------------------------------------------------------
# adaptor_halka_arz_iptal <talep_id>
# Halka arz talebini iptal eder.
# Kaynak: /sanalsube/tr/Ipo/JsonCancelIpoDemand AJAX
# -------------------------------------------------------
adaptor_halka_arz_iptal() {
    local talep_id="$1"

    if [[ -z "$talep_id" ]]; then
        echo "Kullanim: borsa $ADAPTOR_ADI arz iptal <TALEP_ID>"
        echo "Talep ID'sini gormek icin: borsa $ADAPTOR_ADI arz talepler"
        return 1
    fi

    _ziraat_aktif_hesap_kontrol || return 1

    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")

    _ziraat_log "Halka arz talebi iptal ediliyor. Talep ID: $talep_id"
    _borsa_veri_sifirla_son_halka_arz

    # Trap: fonksiyon nasil biterse bitsin son halka arz kaydedilir
    local _vk_basarili="0" _vk_mesaj="Iptal basarisiz"
    trap '_borsa_veri_kaydet_son_halka_arz "$_vk_basarili" "iptal" "$_vk_mesaj" "" "${ipo_id:-}" "" "" "$talep_no"' RETURN

    # IpoId ve DemandId ayirma
    # Talep ID formati: dogrudan demandId veya ipoId:demandId olabilir
    local ipo_id="" talep_no=""
    if [[ "$talep_id" == *":"* ]]; then
        ipo_id="${talep_id%%:*}"
        talep_no="${talep_id##*:}"
    else
        talep_no="$talep_id"
        # IpoId'yi islem listesinden bulmak icin sayfa cekilmeli
        # Ama JSON endpoint sadece demandId ile de calisabilir
        # Once dogrudan deneyelim
    fi

    # CSRF token al — islem listesi sayfasindan
    local sayfa
    sayfa=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_IPO_ISLEMLER_URL")

    # AntiForgeryToken icin cookie header'i kullanilir (jsAjax.js pattern)
    # Sayfadaki token form icinde, AJAX cagrisi ise cookie'den okur

    # IpoId yoksa sayfadan bul
    if [[ -z "$ipo_id" ]]; then
        ipo_id=$(echo "$sayfa" | tr '\n' ' ' | grep -oP "data-id=\"${talep_no}\"[^>]*data-ipoid=\"\K[^\"]+")
        if [[ -z "$ipo_id" ]]; then
            # Alternatif: data-ipoid herhangi bir yerde
            ipo_id=$(echo "$sayfa" | tr '\n' ' ' | grep -oP "\"${talep_no}\"[^<]*data-ipoid=\"\K[^\"]+")
        fi
        if [[ -z "$ipo_id" ]]; then
            echo "HATA: Talep ID '$talep_id' icin IPO ID bulunamadi."
            echo "Taleplerinizi gormek icin: borsa $ADAPTOR_ADI arz talepler"
            return 1
        fi
    fi

    _ziraat_log "Iptal: IpoId=$ipo_id, DemandId=$talep_no"

    # AJAX iptal istegi
    local iptal_yaniti
    iptal_yaniti=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Referer: $_ZIRAAT_IPO_ISLEMLER_URL" \
        -H "Origin: $_ZIRAAT_BASE_URL" \
        -H "Content-Type: application/json" \
        -H "X-Requested-With: XMLHttpRequest" \
        -d "{\"ipoId\":\"$ipo_id\",\"demandId\":\"$talep_no\"}" \
        "$_ZIRAAT_IPO_IPTAL_URL")

    if [[ -z "$iptal_yaniti" ]]; then
        _ziraat_log "HATA: Iptal yaniti bos."
        echo "HATA: Sunucudan yanit alinamadi."
        return 1
    fi

    # JSON yaniti parse et
    local json_mesaj
    json_mesaj=$(cekirdek_json_sonuc_isle "$iptal_yaniti")
    case $? in
        0)  _ziraat_log "BASARILI: Talep iptal edildi."
            cekirdek_yazdir_arz_sonuc "HALKA ARZ TALEBI IPTAL EDILDI" \
                "Talep ID" "$talep_no" \
                "Mesaj" "${json_mesaj:-Talep basariyla iptal edildi}" \
                "Durum" "IPTAL EDILDI"
            _vk_basarili="1"; _vk_mesaj="${json_mesaj:-Talep iptal edildi}"
            return 0
            ;;
        1)  echo "HATA: ${json_mesaj:-Iptal islemi basarisiz.}"
            _ziraat_log "HATA: $iptal_yaniti"
            _vk_mesaj="${json_mesaj:-Iptal basarisiz}"
            return 1
            ;;
        *)  echo "UYARI: ${json_mesaj:-Beklenmeyen yanit.} Sonucu dogrulayin: borsa $ADAPTOR_ADI arz talepler"
            _ziraat_log "Beklenmeyen yanit: $iptal_yaniti"
            _vk_mesaj="${json_mesaj:-Bilinmeyen iptal sonucu}"
            return 1
            ;;
    esac
}

# -------------------------------------------------------
# adaptor_halka_arz_guncelle <talep_id> <yeni_lot>
# Mevcut halka arz talebini gunceller (lot degistirir).
# Kaynak: /sanalsube/tr/Ipo/JsonEditIpoDemand AJAX
# -------------------------------------------------------
adaptor_halka_arz_guncelle() {
    local talep_id="$1"
    local yeni_lot="$2"

    if [[ -z "$talep_id" || -z "$yeni_lot" ]]; then
        echo "Kullanim: borsa $ADAPTOR_ADI arz guncelle <TALEP_ID> <YENI_LOT>"
        echo "Talep ID'sini gormek icin: borsa $ADAPTOR_ADI arz talepler"
        return 1
    fi

    if ! cekirdek_sayi_dogrula "$yeni_lot" "Yeni Lot" "$ADAPTOR_ADI"; then
        return 1
    fi

    _ziraat_aktif_hesap_kontrol || return 1

    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")

    _ziraat_log "Halka arz talebi guncelleniyor. Talep: $talep_id, Yeni lot: $yeni_lot"
    _borsa_veri_sifirla_son_halka_arz

    # Trap: fonksiyon nasil biterse bitsin son halka arz kaydedilir
    local _vk_basarili="0" _vk_mesaj="Guncelleme basarisiz"
    trap '_borsa_veri_kaydet_son_halka_arz "$_vk_basarili" "guncelle" "$_vk_mesaj" "" "${ipo_id:-}" "$yeni_lot" "${fiyat:-}" "$talep_no"' RETURN

    # IpoId ve DemandId ayir
    local ipo_id="" talep_no=""
    if [[ "$talep_id" == *":"* ]]; then
        ipo_id="${talep_id%%:*}"
        talep_no="${talep_id##*:}"
    else
        talep_no="$talep_id"
    fi

    # Islem listesi sayfasindan bilgileri al
    local sayfa
    sayfa=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_IPO_ISLEMLER_URL")

    # IpoId yoksa sayfadan bul
    if [[ -z "$ipo_id" ]]; then
        ipo_id=$(echo "$sayfa" | tr '\n' ' ' | grep -oP "data-id=\"${talep_no}\"[^>]*data-ipoid=\"\K[^\"]+")
        if [[ -z "$ipo_id" ]]; then
            ipo_id=$(echo "$sayfa" | tr '\n' ' ' | grep -oP "\"${talep_no}\"[^<]*data-ipoid=\"\K[^\"]+")
        fi
        if [[ -z "$ipo_id" ]]; then
            echo "HATA: Talep ID '$talep_id' icin IPO ID bulunamadi."
            echo "Taleplerinizi gormek icin: borsa $ADAPTOR_ADI arz talepler"
            return 1
        fi
    fi

    # Fiyat bilgisini sayfadan al (mevcut talebin fiyati)
    local fiyat
    fiyat=$(echo "$sayfa" | tr '\n' ' ' | grep -oP "id=\"${talep_no}\"[^<]*" | grep -oP 'data-price="\K[^"]+' | head -1)
    # Fiyat bulunamazsa, DisplayOrEdit endpoint'inden al
    if [[ -z "$fiyat" ]]; then
        local goruntule_yanit
        goruntule_yanit=$(cekirdek_istek_at \
            -c "$cookie_dosyasi" \
            -b "$cookie_dosyasi" \
            -H "Content-Type: application/json" \
            -H "X-Requested-With: XMLHttpRequest" \
            -d "{\"displayOrEdit\":\"Edit\",\"ipoId\":\"$ipo_id\",\"ipoDemandId\":\"$talep_no\",\"eq\":\"\"}" \
            "$_ZIRAAT_IPO_GORUNTULE_URL")

        fiyat=$(echo "$goruntule_yanit" | grep -oP '"Price"\s*:\s*\K[0-9.]+' | head -1)
    fi
    [[ -z "$fiyat" ]] && fiyat="0"

    # Minimum lot
    local min_lot
    min_lot=$(echo "$sayfa" | tr '\n' ' ' | grep -oP "id=\"${talep_no}\".*?item_minimum_demand[^>]*value=\"\K[^\"]+")
    [[ -z "$min_lot" ]] && min_lot="1"

    if [[ "$yeni_lot" -lt "$min_lot" ]] 2>/dev/null; then
        echo "HATA: Minimum talep miktari $min_lot lot. Girilen: $yeni_lot lot."
        return 1
    fi

    _ziraat_log "Guncelleme: IpoId=$ipo_id, DemandId=$talep_no, Lot=$yeni_lot, Fiyat=$fiyat"

    # Tutar hesapla
    local tutar
    tutar=$(echo "$yeni_lot * $fiyat" | bc 2>/dev/null)
    [[ -z "$tutar" ]] && tutar="0"

    # AJAX guncelleme istegi
    local price_items="[{\"UNIT\":$yeni_lot,\"PRICE\":$fiyat,\"AMOUNT\":$tutar}]"
    local guncelle_yaniti
    guncelle_yaniti=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Referer: $_ZIRAAT_IPO_ISLEMLER_URL" \
        -H "Origin: $_ZIRAAT_BASE_URL" \
        -H "Content-Type: application/json" \
        -H "X-Requested-With: XMLHttpRequest" \
        -d "{\"IPO_ID\":\"$ipo_id\",\"DEMAND_ID\":\"$talep_no\",\"MIN_UNITS\":$min_lot,\"PRICE_ITEMS\":$price_items,\"EQ\":\"\"}" \
        "$_ZIRAAT_IPO_GUNCELLE_URL")

    if [[ -z "$guncelle_yaniti" ]]; then
        _ziraat_log "HATA: Guncelleme yaniti bos."
        echo "HATA: Sunucudan yanit alinamadi."
        return 1
    fi

    # JSON yaniti parse et
    local json_mesaj
    json_mesaj=$(cekirdek_json_sonuc_isle "$guncelle_yaniti")
    case $? in
        0)  _ziraat_log "BASARILI: Talep guncellendi."
            cekirdek_yazdir_arz_sonuc "HALKA ARZ TALEBI GUNCELLENDI" \
                "Talep ID" "$talep_no" \
                "Yeni Lot" "$yeni_lot" \
                "Fiyat" "$fiyat" \
                "Mesaj" "${json_mesaj:-Talep basariyla guncellendi}" \
                "Durum" "GUNCELLENDI"
            _vk_basarili="1"; _vk_mesaj="${json_mesaj:-Talep guncellendi}"
            return 0
            ;;
        1)  echo "HATA: ${json_mesaj:-Guncelleme basarisiz.}"
            _ziraat_log "HATA: $guncelle_yaniti"
            _vk_mesaj="${json_mesaj:-Guncelleme basarisiz}"
            return 1
            ;;
        *)  echo "UYARI: ${json_mesaj:-Beklenmeyen yanit.} Sonucu dogrulayin: borsa $ADAPTOR_ADI arz talepler"
            _ziraat_log "Beklenmeyen yanit: $guncelle_yaniti"
            _vk_mesaj="${json_mesaj:-Bilinmeyen guncelleme sonucu}"
            return 1
            ;;
    esac
}

# =======================================================
# BOLUM 4: OTURUM YONETIMI CALLBACKLERI
# =======================================================

# -------------------------------------------------------
# adaptor_oturum_suresi_parse <html_icerigi>
# Giris yaniti HTML'indeki sessionTimeOutModel degerini
# parse ederek saniye cinsinden dondurur.
# Ziraat sunucusu oturum suresini JavaScript icerisinde
# milisaniye olarak verir.
# stdout: sure (saniye)
# -------------------------------------------------------
adaptor_oturum_suresi_parse() {
    local html="$1"

    # sessionTimeOutModel: {SessionTimeOut: 1500000} seklinde (ms)
    local ms
    ms=$(echo "$html" | grep -oP 'SessionTimeOut\s*:\s*\K[0-9]+' | head -1)

    if [[ -n "$ms" ]] && [[ "$ms" -gt 0 ]]; then
        local saniye=$(( ms / 1000 ))
        echo "$saniye"
        return 0
    fi

    # Bulunamazsa varsayilan: 25 dakika
    echo "1500"
    return 0
}

# -------------------------------------------------------
# adaptor_oturum_uzat [hesap_no]
# Oturumu uzatmak icin sessiz bir GET istegi atar.
# Basari durumunda oturum zamanlayicisi sifirlanir.
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
adaptor_oturum_uzat() {
    local hesap="${1:-$(cekirdek_aktif_hesap "ziraat")}"
    local cookie_dosyasi
    cookie_dosyasi=$(cekirdek_dosya_yolu "ziraat" "$_CEKIRDEK_DOSYA_COOKIE" "$hesap")

    if [[ -z "$cookie_dosyasi" ]] || [[ ! -f "$cookie_dosyasi" ]]; then
        return 1
    fi

    # Ana sayfaya sessiz GET — oturum zamanlayicisini sifirlar
    local yanit
    yanit=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_ZIRAAT_ANA_SAYFA_URL" 2>/dev/null)

    # Session GUID varsa basarili
    if echo "$yanit" | grep -qP "$_ZIRAAT_SEL_SESSION_GUID"; then
        return 0
    fi

    return 1
}

# -------------------------------------------------------
# adaptor_cikis [hesap_no]
# Oturumu kapatir: cookie dosyasini siler, koruma durdurur.
# -------------------------------------------------------
adaptor_cikis() {
    local hesap="${1:-$(cekirdek_aktif_hesap "ziraat")}"

    if [[ -z "$hesap" ]]; then
        echo "HATA: Aktif hesap yok."
        return 1
    fi

    # Oturum koruma dongusunu durdur
    cekirdek_oturum_koruma_durdur "ziraat" "$hesap"

    # Cookie dosyasini sil
    local cookie_dosyasi
    cookie_dosyasi=$(cekirdek_dosya_yolu "ziraat" "$_CEKIRDEK_DOSYA_COOKIE" "$hesap")
    if [[ -f "$cookie_dosyasi" ]]; then
        rm -f "$cookie_dosyasi"
    fi

    # Oturum log
    if declare -f vt_oturum_log_yaz > /dev/null 2>&1; then
        vt_oturum_log_yaz "ziraat" "$hesap" "CIKIS" "Manuel cikis"
    fi

    _ziraat_log "Oturum kapatildi ($hesap)."
    cekirdek_yazdir_oturum_bilgi "OTURUM KAPATILDI" \
        "Kurum" "ziraat" \
        "Hesap" "$hesap"
}

# -------------------------------------------------------
# adaptor_hisse_bilgi_al <sembol>
# Belirli bir hissenin son fiyat, tavan, taban, hacim
# bilgilerini dondurur.
# stdout: fiyat|tavan|taban|degisim|hacim
# -------------------------------------------------------
adaptor_hisse_bilgi_al() {
    local sembol="${1^^}"

    if [[ -z "$sembol" ]]; then
        echo "HATA: Sembol belirtilmedi."
        return 1
    fi

    _ziraat_aktif_hesap_kontrol || return 1

    local cookie_dosyasi
    cookie_dosyasi=$(_ziraat_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")

    if [[ ! -f "$cookie_dosyasi" ]]; then
        echo "HATA: Oturum bulunamadi. Once giris yapin."
        return 1
    fi

    # Kiymet listesi sayfasindan hisse bilgisini cek
    local yanit
    yanit=$(cekirdek_istek_at \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Referer: $_ZIRAAT_EMIR_URL" \
        -H "X-Requested-With: XMLHttpRequest" \
        --data-urlencode "FilterText=$sembol" \
        "$_ZIRAAT_KIYMET_LISTESI_URL" 2>/dev/null)

    if [[ -z "$yanit" ]]; then
        echo "HATA: Kiymet bilgisi alinamadi."
        return 1
    fi

    # JSON yanitdan fiyat bilgilerini parse et
    local son_fiyat tavan taban degisim hacim
    son_fiyat=$(echo "$yanit" | grep -oP '"LastPrice"\s*:\s*\K[0-9.]+' | head -1)
    tavan=$(echo "$yanit" | grep -oP '"CeilingPrice"\s*:\s*\K[0-9.]+' | head -1)
    taban=$(echo "$yanit" | grep -oP '"FloorPrice"\s*:\s*\K[0-9.]+' | head -1)
    degisim=$(echo "$yanit" | grep -oP '"ChangePercent"\s*:\s*\K-?[0-9.]+' | head -1)
    hacim=$(echo "$yanit" | grep -oP '"Volume"\s*:\s*\K[0-9]+' | head -1)

    if [[ -z "$son_fiyat" ]]; then
        echo "HATA: '$sembol' icin fiyat bilgisi bulunamadi."
        return 1
    fi

    echo "${son_fiyat}|${tavan:-0}|${taban:-0}|${degisim:-0}|${hacim:-0}"
}

# adaptor_hesap() ve adaptor_hesaplar() tanimlanmiyor.
# cekirdek.sh'daki cekirdek_hesap() ve cekirdek_hesaplar()
# jenerik implementasyonlari kullanilir.
# Oturum gecerlilik kontrolu icin adaptor_oturum_gecerli_mi()
# callback'i BOLUM 1'de tanimlidir.
