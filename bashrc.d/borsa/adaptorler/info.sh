#!/bin/bash
# shellcheck shell=bash

# Info Yatirim Menkul Degerler A.S. Adaptoru
# Bu dosya dogrudan calistirilmaz, cekirdek.sh tarafindan yuklenir.
#
# Site: https://esube.infoyatirim.com
# Mimari: UmiJS 3.5.41 React SPA, REST JSON API
# Backend: Microsoft IIS 10.0, ASP.NET
# Oturum: Cookie-based (sunucu Set-Cookie ile oturum yonetir)
# Login: POST /webapi/login {Username, Password}
# 2FA: SMS (statusCode=5640005) veya OTP/Info PASS (statusCode=5640006)
# Veri API: /webapi/ApiCall/{SP_ADI} (stored procedure proxy)

# shellcheck disable=SC2034
if [[ "${ADAPTOR_ADI:-}" != "info" ]]; then
    ADAPTOR_ADI="info" 2>/dev/null || true
fi
if [[ "${ADAPTOR_SURUMU:-}" != "1.0.0" ]]; then
    ADAPTOR_SURUMU="1.0.0" 2>/dev/null || true
fi

# Ayarlar dosyasini yukle
# shellcheck source=info.ayarlar.sh
source "${BORSA_KLASORU}/adaptorler/info.ayarlar.sh"

# Ince sarmalayicilari otomatik olustur
cekirdek_adaptor_kaydet "info"


# =======================================================
# BOLUM 1: DAHILI YARDIMCILAR (_info_* fonksiyonlari)
# Disaridan cagrilmaz. Adaptor icindeki fonksiyonlar kullanir.
# =======================================================

# -------------------------------------------------------
# _info_sms_durumu_kaydet <musteri_no> <parola> <dogrulama_tipi>
# Giris istegi sonrasi SMS/OTP bekleme durumunu kaydeder.
# Ikinci denemede kullanicidan tekrar sifre istenmesini onler.
# dogrulama_tipi: "SMS" veya "OTP" — dogrulama payload'i farkli.
# -------------------------------------------------------
_info_sms_durumu_kaydet() {
    local musteri_no="$1"
    local parola="$2"
    local dogrulama_tipi="${3:-SMS}"

    local dizin
    dizin=$(_info_oturum_dizini "$musteri_no")
    [[ -z "$dizin" ]] && return 1

    local dosya="${dizin}/sms_bekleme"
    echo "${musteri_no}|${parola}|$(date +%s)|${dogrulama_tipi}" > "$dosya"
}

# -------------------------------------------------------
# _info_sms_durumu_oku
# Bekleyen SMS/OTP durumunu okur.
# Varsayilan zaman asimi: 300 saniye (5 dakika).
# stdout: "musteri_no|parola|kalan_saniye|dogrulama_tipi" veya bos
# -------------------------------------------------------
_info_sms_durumu_oku() {
    local hesap
    hesap=$(cekirdek_aktif_hesap "info")
    [[ -z "$hesap" ]] && return 1

    local dizin
    dizin=$(_info_oturum_dizini "$hesap")
    [[ -z "$dizin" ]] && return 1

    local dosya="${dizin}/sms_bekleme"
    [[ ! -f "$dosya" ]] && return 1

    local icerik
    icerik=$(cat "$dosya" 2>/dev/null)
    [[ -z "$icerik" ]] && return 1

    local musteri_no parola zaman_damgasi dogrulama_tipi
    musteri_no=$(echo "$icerik" | cut -d'|' -f1)
    parola=$(echo "$icerik" | cut -d'|' -f2)
    zaman_damgasi=$(echo "$icerik" | cut -d'|' -f3)
    dogrulama_tipi=$(echo "$icerik" | cut -d'|' -f4)
    # Eski format uyumlulugu (tip alani yoksa SMS varsay)
    [[ -z "$dogrulama_tipi" ]] && dogrulama_tipi="SMS"

    local simdi
    simdi=$(date +%s)
    local gecen=$(( simdi - zaman_damgasi ))

    # 5 dakikadan eski ise temizle
    if [[ "$gecen" -gt 300 ]]; then
        rm -f "$dosya"
        return 1
    fi

    local kalan=$(( 300 - gecen ))
    echo "${musteri_no}|${parola}|${kalan}|${dogrulama_tipi}"
    return 0
}

# -------------------------------------------------------
# _info_sms_durumu_temizle
# SMS/OTP bekleme durumunu siler (basarili giris veya iptal).
# -------------------------------------------------------
_info_sms_durumu_temizle() {
    local hesap
    hesap=$(cekirdek_aktif_hesap "info")
    [[ -z "$hesap" ]] && return 0

    local dizin
    dizin=$(_info_oturum_dizini "$hesap")
    rm -f "${dizin}/sms_bekleme" 2>/dev/null
}

# -------------------------------------------------------
# _info_json_istek <metod> <url> [json_govde]
# Info API'sine JSON istek atar. Cookie otomatik eklenir.
# stdout: Sunucu yaniti (JSON)
# -------------------------------------------------------
_info_json_istek() {
    local metod="$1"
    local url="$2"
    local govde="${3:-}"

    local cookie_dosyasi
    cookie_dosyasi=$(_info_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")

    if [[ "$metod" == "POST" ]]; then
        if [[ -n "$govde" ]]; then
            cekirdek_istek_at \
                -X POST \
                -c "$cookie_dosyasi" \
                -b "$cookie_dosyasi" \
                -H "Content-Type: application/json" \
                -d "$govde" \
                "$url"
        else
            cekirdek_istek_at \
                -X POST \
                -c "$cookie_dosyasi" \
                -b "$cookie_dosyasi" \
                -H "Content-Type: application/json" \
                -d '{}' \
                "$url"
        fi
    else
        cekirdek_istek_at \
            -c "$cookie_dosyasi" \
            -b "$cookie_dosyasi" \
            "$url"
    fi
}

# -------------------------------------------------------
# _info_apicall <sp_adi> [json_data]
# Generic ApiCall endpoint'ine stored procedure cagrisi yapar.
# POST /webapi/ApiCall/{sp_adi}
# Body: {"symbolName": "sp_adi", ...ek_parametreler}
# JS kaynagi: Object(i.a)("/webapi/ApiCall/".concat(p.symbolName),
#             {method:"POST", data: p})
# stdout: JSON yanit
# -------------------------------------------------------
_info_apicall() {
    local sp_adi="$1"
    local ek_veri="${2:-}"

    # symbolName her zaman payload'da olmali
    local payload
    if [[ -n "$ek_veri" ]] && [[ "$ek_veri" != "{}" ]]; then
        # Mevcut JSON'a symbolName ekle: {"symbolName":"X", ...mevcut}
        local sn_eki
        sn_eki="\"symbolName\":\"${sp_adi}\","
        payload="{${sn_eki}${ek_veri#\{}"
    else
        payload="{\"symbolName\":\"${sp_adi}\"}"
    fi

    _info_json_istek "POST" "${_INFO_APICALL_URL}/${sp_adi}" "$payload"
}

# -------------------------------------------------------
# _info_json_deger_cikar <json> <alan>
# JSON yanitindan basit string alan degeri cikarir (jq gerektirmez).
# stdout: alan degeri
# -------------------------------------------------------
_info_json_deger_cikar() {
    local json="$1"
    local alan="$2"
    echo "$json" | grep -oP "\"${alan}\"\s*:\s*\"\K[^\"]*" | head -1
}

# -------------------------------------------------------
# _info_json_sayi_cikar <json> <alan>
# JSON'dan sayisal (tirnak olmayan) alan degerini cikarir.
# stdout: sayi
# -------------------------------------------------------
_info_json_sayi_cikar() {
    local json="$1"
    local alan="$2"
    echo "$json" | grep -oP "\"${alan}\"\s*:\s*\K[0-9]+(\.[0-9]+)?" | head -1
}

# -------------------------------------------------------
# _info_json_objeleri_cikar <json>
# JSON dizisindeki objeleri ayri satirlara boler.
# stdout: her satir bir JSON objesi
# -------------------------------------------------------
_info_json_objeleri_cikar() {
    local json="$1"
    # Tek satira dusur, },{  ile bol
    echo "$json" | tr -d '\n' | sed 's/},{/}\n{/g' | \
        grep -oP '\{[^{}]*\}'
}

# -------------------------------------------------------
# _info_hata_mesaji_cikar <json>
# API hata yanitindan mesaj cikarir.
# Hangi alan varsa onu doner: message, title, errorMessage
# stdout: hata mesaji veya bos
# -------------------------------------------------------
_info_hata_mesaji_cikar() {
    local json="$1"
    local mesaj

    # Oncelik sirasi: message -> title -> errors
    mesaj=$(_info_json_deger_cikar "$json" "message")
    [[ -n "$mesaj" ]] && { echo "$mesaj"; return 0; }

    mesaj=$(_info_json_deger_cikar "$json" "title")
    [[ -n "$mesaj" ]] && { echo "$mesaj"; return 0; }

    # errors objesi varsa ilk hatay cikar
    mesaj=$(echo "$json" | grep -oP '"errors"\s*:\s*\{[^}]*\}' | head -1)
    [[ -n "$mesaj" ]] && { echo "$mesaj"; return 0; }

    return 1
}


# =======================================================
# BOLUM 2: GENEL ARABIRIM (adaptor_* fonksiyonlari)
# cekirdek.sh tarafindan cagrilir.
# =======================================================

# -------------------------------------------------------
# adaptor_oturum_gecerli_mi [musteri_no]
# Cookie ile Ping endpoint'ine GET atarak oturum gecerliligini kontrol eder.
# Donus: 0=gecerli, 1=gecersiz
# -------------------------------------------------------
adaptor_oturum_gecerli_mi() {
    local hesap="${1:-$(cekirdek_aktif_hesap "info")}"
    [[ -z "$hesap" ]] && return 1

    local cookie_dosyasi
    cookie_dosyasi=$(cekirdek_dosya_yolu "info" "$_CEKIRDEK_DOSYA_COOKIE" "$hesap")

    [[ ! -f "$cookie_dosyasi" ]] && return 1

    # Ping endpoint'i: 200 = gecerli, 401 = dustu
    local http_kod
    http_kod=$(cekirdek_istek_at \
        -o /dev/null \
        -w "%{http_code}" \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_INFO_PING_URL" 2>/dev/null)

    if [[ "$http_kod" == "200" ]]; then
        return 0
    fi

    return 1
}

# -------------------------------------------------------
# adaptor_oturum_suresi_parse <yanit_json>
# Giris yanitindan oturum suresini saniye cinsinden cikarir.
# Info sitesi oturum suresini acikca donmuyor, varsayilan kullanilir.
# stdout: saniye cinsinden oturum suresi
# -------------------------------------------------------
adaptor_oturum_suresi_parse() {
    local yanit="$1"

    # sessionTimeout veya tokenExpires alani varsa kullan
    local sure
    sure=$(_info_json_sayi_cikar "$yanit" "sessionTimeout")
    if [[ -n "$sure" ]] && [[ "$sure" -gt 0 ]]; then
        echo "$sure"
        return 0
    fi

    # expiresIn (saniye) alani varsa
    sure=$(_info_json_sayi_cikar "$yanit" "expiresIn")
    if [[ -n "$sure" ]] && [[ "$sure" -gt 0 ]]; then
        echo "$sure"
        return 0
    fi

    # Varsayilan: 1 saat
    echo "$_INFO_OTURUM_SURESI"
    return 0
}

# -------------------------------------------------------
# adaptor_giris <musteri_no> <parola>
# Info Yatirim e-subeye giris yapar.
# Akis: POST /webapi/login -> Basari/SMS/OTP
# -------------------------------------------------------
adaptor_giris() {
    local musteri_no="$1"
    local parola="$2"

    # 1. Parametre kontrolu
    if [[ -z "$musteri_no" ]] || [[ -z "$parola" ]]; then
        echo "Kullanim: borsa info giris <musteri_no> <parola>"
        return 1
    fi

    # 2. Oturum dizinini hazirla
    cekirdek_aktif_hesap_ayarla "info" "$musteri_no"
    _info_oturum_dizini "$musteri_no" > /dev/null

    # 3. Mevcut oturum gecerli mi?
    if adaptor_oturum_gecerli_mi "$musteri_no"; then
        cekirdek_yazdir_oturum_bilgi \
            "OTURUM ZATEN ACIK" \
            "Info Yatirim" \
            "Hesap: $musteri_no" \
            "Zaten aktif bir oturum var."
        return 0
    fi

    # 4. Cookie dosyasini hazirla
    local cookie_dosyasi
    cookie_dosyasi=$(_info_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")
    : > "$cookie_dosyasi"

    # 4.5. Cooldown kontrolu — onceki SMS hala gecerliyse Step1 atlaniyor
    local sms_durumu
    if sms_durumu=$(_info_sms_durumu_oku); then
        local onceki_mn onceki_parola kalan_sure onceki_tip
        IFS='|' read -r onceki_mn onceki_parola kalan_sure onceki_tip <<< "$sms_durumu"
        if [[ "$onceki_mn" == "$musteri_no" && "$onceki_parola" == "$parola" ]]; then
            _info_log "Onceki SMS hala gecerli (kalan: ${kalan_sure}sn, tip: ${onceki_tip}). Login atlaniyor."
            echo "SMS daha once gonderildi (kalan bekleme: ${kalan_sure} saniye)."
            _info_otp_dogrula "$musteri_no" "$parola" "$onceki_tip"
            return $?
        fi
        # Farkli kullanici/parola — eski durumu temizle
        _info_sms_durumu_temizle
    fi

    _info_log "Giris istegi gonderiliyor: $musteri_no"

    # 5. Login POST istegi: {Username: ..., Password: ...}
    local giris_yanit
    giris_yanit=$(cekirdek_istek_at \
        -X POST \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Content-Type: application/json" \
        -d "{\"${_INFO_GIRIS_KULLANICI_ALANI}\": \"${musteri_no}\", \"${_INFO_GIRIS_SIFRE_ALANI}\": \"${parola}\"}" \
        "$_INFO_LOGIN_URL" 2>/dev/null)

    local yanit_boyut="${#giris_yanit}"
    if [[ "$yanit_boyut" -lt 10 ]]; then
        _info_log "HATA: Giris yaniti cok kucuk ($yanit_boyut bayt). Sunucu erisilemez."
        echo "HATA: Sunucu erisilemez veya yanit bos."
        return 1
    fi

    _info_log "Giris yaniti alindi ($yanit_boyut bayt)."

    # Debug: ham giris yanitini her zaman kaydet (tani icin)
    local debug_dosyasi
    debug_dosyasi=$(_info_dosya_yolu "$_CEKIRDEK_DOSYA_DEBUG")
    echo "[$(date '+%H:%M:%S')] Giris yaniti:" > "$debug_dosyasi"
    echo "$giris_yanit" >> "$debug_dosyasi"

    # 6. Yanit analizi
    local durum_kodu
    durum_kodu=$(_info_json_sayi_cikar "$giris_yanit" "statusCode")
    local basari
    basari=$(echo "$giris_yanit" | grep -oP '"success"\s*:\s*\K(true|false)' | head -1)

    _info_log "statusCode=$durum_kodu, success=$basari"

    # 7. Basarili giris (statusCode=0, success=true)
    if [[ "$basari" == "true" ]] && [[ "$durum_kodu" == "0" ]]; then
        _info_log "BASARILI: Giris tamamlandi."
        _info_sms_durumu_temizle

        # Cookie dosyasini kilitle
        _info_cookie_guvence

        # Oturum suresini kaydet
        local oturum_suresi
        oturum_suresi=$(adaptor_oturum_suresi_parse "$giris_yanit")
        cekirdek_oturum_suresi_kaydet "info" "$musteri_no" "$oturum_suresi"
        cekirdek_son_istek_guncelle "info" "$musteri_no"

        echo "Tebrikler! Oturum acildi."
        return 0
    fi

    # 8. SMS dogrulama gerekli (statusCode=5640005)
    if [[ "$durum_kodu" == "$_INFO_KOD_SMS" ]]; then
        _info_log "SMS dogrulama gerekli. Sunucu SMS gondermis olmali."
        _info_sms_durumu_kaydet "$musteri_no" "$parola" "SMS"
        _info_otp_dogrula "$musteri_no" "$parola" "SMS"
        return $?
    fi

    # 9. OTP / Info PASS (statusCode=5640006)
    #    Kullanici Info PASS yerine SMS tercih ettiginden,
    #    sunucuya loginBySMS:"1" gonderip SMS moduna geciriyoruz.
    if [[ "$durum_kodu" == "$_INFO_KOD_OTP" ]]; then
        _info_log "OTP (Info PASS) dondu — SMS moduna geciliyor."
        echo "Sunucu Info PASS istedi, SMS moduna geciliyor..."
        if _info_sms_tetikle "$musteri_no" "$parola" "$cookie_dosyasi"; then
            _info_sms_durumu_kaydet "$musteri_no" "$parola" "SMS"
            _info_otp_dogrula "$musteri_no" "$parola" "SMS"
            return $?
        else
            echo "HATA: SMS moduna gecilemedi. Info PASS ile deneyin."
            return 1
        fi
    fi

    # 10. Telefon bulunamadi (statusCode=5640011)
    if [[ "$durum_kodu" == "5640011" ]]; then
        _info_log "HATA: Telefon bulunamadi (5640011)."
        echo "HATA: Hesaba kayitli telefon numarasi bulunamadi."
        echo "Info Yatirim musteri hizmetleri ile iletisime gecin."
        return 1
    fi

    # 11. Sifre degistirme zorunlu (statusCode=5640003)
    if [[ "$durum_kodu" == "$_INFO_KOD_SIFRE_DEGISTIR" ]]; then
        _info_log "HATA: Sifre degistirme zorunlu."
        echo "HATA: Sifre degistirmeniz gerekiyor. Siteden degistirin: ${_INFO_BASE_URL}/user/change-password"
        return 1
    fi

    # 12. Yanlis sifre (statusCode=5640004)
    if [[ "$durum_kodu" == "$_INFO_KOD_YANLIS_SIFRE" ]]; then
        _info_log "HATA: Yanlis sifre."
        echo "HATA: Musteri no veya sifre yanlis."
        return 1
    fi

    # 13. Diger hatalar
    local hata_mesaji
    hata_mesaji=$(_info_hata_mesaji_cikar "$giris_yanit")
    if [[ -n "$hata_mesaji" ]]; then
        _info_log "HATA: statusCode=$durum_kodu mesaj=$hata_mesaji"
        echo "HATA: $hata_mesaji (kod: $durum_kodu)"
    else
        _info_log "HATA: Bilinmeyen giris hatasi. statusCode=$durum_kodu"
        echo "HATA: Giris basarisiz (kod: $durum_kodu)."
    fi
    echo "Debug yaniti: $(cat "$debug_dosyasi" 2>/dev/null | head -5)"

    return 1
}

# -------------------------------------------------------
# _info_sms_tetikle <musteri_no> <parola> <cookie_dosyasi>
# OTP modu yerine SMS gondermesini tetikler.
# JS kaynagi: "SMS ile gonder" butonu -> {username, password, loginBySMS: "1"}
# Sunucu bu istegi alinca kayitli telefona SMS atar.
# -------------------------------------------------------
_info_sms_tetikle() {
    local musteri_no="$1"
    local parola="$2"
    local cookie_dosyasi="$3"

    _info_log "SMS tetikleme istegi gonderiliyor: $musteri_no"

    local payload
    payload="{\"${_INFO_GIRIS_KULLANICI_ALANI}\": \"${musteri_no}\""
    payload+=", \"${_INFO_GIRIS_SIFRE_ALANI}\": \"${parola}\""
    payload+=", \"${_INFO_SMS_BAYRAK_ALANI}\": \"${_INFO_SMS_BAYRAK_DEGERI}\"}"

    local sms_yanit
    sms_yanit=$(cekirdek_istek_at \
        -X POST \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$_INFO_LOGIN_URL" 2>/dev/null)

    local yanit_boyut="${#sms_yanit}"
    _info_log "SMS tetikleme yaniti ($yanit_boyut bayt): $sms_yanit"

    # Debug dosyasina kaydet
    local debug_dosyasi
    debug_dosyasi=$(_info_dosya_yolu "$_CEKIRDEK_DOSYA_DEBUG")
    echo "[$(date '+%H:%M:%S')] SMS tetikleme yaniti:" >> "$debug_dosyasi"
    echo "$sms_yanit" >> "$debug_dosyasi"

    # Basari kontrolu: statusCode=5640005 (SMS gonderildi) veya success=true
    local durum_kodu
    durum_kodu=$(_info_json_sayi_cikar "$sms_yanit" "statusCode")

    if [[ "$durum_kodu" == "$_INFO_KOD_SMS" ]]; then
        _info_log "SMS basariyla tetiklendi (statusCode=$durum_kodu)."
        echo "SMS gonderildi. Telefonunuzu kontrol edin."
        return 0
    fi

    # Bazi sunucular statusCode=0 ile de SMS gonderebilir
    local basari
    basari=$(echo "$sms_yanit" | grep -oP '"success"\s*:\s*\K(true|false)' | head -1)
    if [[ "$basari" == "true" ]]; then
        _info_log "SMS tetikleme basarili (success=true, statusCode=$durum_kodu)."
        echo "SMS gonderildi. Telefonunuzu kontrol edin."
        return 0
    fi

    # Telefon bulunamadi ozel durumu
    if [[ "$durum_kodu" == "5640011" ]]; then
        _info_log "HATA: Telefon bulunamadi (5640011)."
        echo "HATA: Hesaba kayitli telefon numarasi bulunamadi."
        return 1
    fi

    local hata_mesaji
    hata_mesaji=$(_info_hata_mesaji_cikar "$sms_yanit")
    _info_log "HATA: SMS tetikleme basarisiz. statusCode=$durum_kodu mesaj=${hata_mesaji:-yok}"
    echo "HATA: SMS gonderilemedi. ${hata_mesaji:+(Sunucu: $hata_mesaji)}"
    return 1
}

# -------------------------------------------------------
# _info_otp_dogrula <musteri_no> <parola> <dogrulama_tipi>
# SMS/OTP kodunu kullanicidan alip login istegine ekleyerek gonderir.
# dogrulama_tipi: "SMS" -> payload'a loginBySMS:"1" eklenir
#                 "OTP" -> yalnizca otpCode gonderilir
# JS kaynagi: handleOTPSubmit fonksiyonu
#   q==="SMS" && ($e.loginBySMS = "1")
# -------------------------------------------------------
_info_otp_dogrula() {
    local musteri_no="$1"
    local parola="$2"
    local dogrulama_tipi="${3:-SMS}"

    local tip_aciklama
    if [[ "$dogrulama_tipi" == "SMS" ]]; then
        tip_aciklama="Telefonunuza gelen SMS'teki"
    else
        tip_aciklama="Info PASS uygulamasindaki"
    fi

    cekirdek_yazdir_oturum_bilgi \
        "DIKKAT: Info Yatirim 2FA Dogrulama Kodu" \
        "Mod" "$dogrulama_tipi" \
        "Bilgi" "${tip_aciklama} $_INFO_OTP_UZUNLUK haneli kodu girin."
    local otp_kodu
    read -r otp_kodu

    if [[ -z "$otp_kodu" ]]; then
        _info_log "OTP kodu girilmedi, islem iptal."
        return 1
    fi

    if [[ ${#otp_kodu} -ne "$_INFO_OTP_UZUNLUK" ]]; then
        echo "HATA: Kod $_INFO_OTP_UZUNLUK haneli olmali."
        return 1
    fi

    _info_log "OTP dogrulama gonderiliyor: $musteri_no (tip: $dogrulama_tipi)"

    # Cookie dosyasini hazirla
    local cookie_dosyasi
    cookie_dosyasi=$(_info_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")

    # Payload olustur — SMS vs OTP farki burada
    local payload
    payload="{\"${_INFO_GIRIS_KULLANICI_ALANI}\": \"${musteri_no}\""
    payload+=", \"${_INFO_GIRIS_SIFRE_ALANI}\": \"${parola}\""
    payload+=", \"${_INFO_OTP_ALAN_ADI}\": \"${otp_kodu}\""
    # SMS modunda loginBySMS:"1" ZORUNLU, OTP modunda OLMAMALI
    if [[ "$dogrulama_tipi" == "SMS" ]]; then
        payload+=", \"${_INFO_SMS_BAYRAK_ALANI}\": \"${_INFO_SMS_BAYRAK_DEGERI}\""
        _info_log "SMS modu: loginBySMS bayragi eklendi."
    fi
    payload+="}"

    _info_log "OTP payload: $(echo "$payload" | sed "s/${parola}/****/g")"

    # Login POST + otpCode alani ile tekrar gonder
    local otp_yanit
    otp_yanit=$(cekirdek_istek_at \
        -X POST \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$_INFO_LOGIN_URL" 2>/dev/null)

    local yanit_boyut="${#otp_yanit}"
    _info_log "OTP yaniti alindi ($yanit_boyut bayt)."

    # Debug: ham yaniti her zaman kaydet
    local debug_dosyasi
    debug_dosyasi=$(_info_dosya_yolu "$_CEKIRDEK_DOSYA_DEBUG")
    echo "[$(date '+%H:%M:%S')] OTP dogrulama yaniti ($dogrulama_tipi):" > "$debug_dosyasi"
    echo "$otp_yanit" >> "$debug_dosyasi"

    local durum_kodu
    durum_kodu=$(_info_json_sayi_cikar "$otp_yanit" "statusCode")
    local basari
    basari=$(echo "$otp_yanit" | grep -oP '"success"\s*:\s*\K(true|false)' | head -1)

    _info_log "OTP sonuc: statusCode=$durum_kodu, success=$basari"

    if [[ "$basari" == "true" ]] && [[ "$durum_kodu" == "0" ]]; then
        _info_log "BASARILI: OTP dogrulama tamamlandi."
        _info_sms_durumu_temizle
        _info_cookie_guvence

        local oturum_suresi
        oturum_suresi=$(adaptor_oturum_suresi_parse "$otp_yanit")
        cekirdek_oturum_suresi_kaydet "info" "$musteri_no" "$oturum_suresi"
        cekirdek_son_istek_guncelle "info" "$musteri_no"

        echo "Tebrikler! Oturum acildi."
        return 0
    fi

    # Basarisiz — ama OTP durumunu silme, kullanici tekrar deneyebilir
    local hata_mesaji
    hata_mesaji=$(_info_hata_mesaji_cikar "$otp_yanit")
    _info_log "HATA: OTP dogrulama basarisiz. Mesaj: ${hata_mesaji:-bilinmeyen}"
    echo "HATA: ${hata_mesaji:-OTP kodu yanlis veya suresi dolmus.}"
    echo "Tekrar denemek icin: borsa info giris $musteri_no <PAROLA>"
    return 1
}

# -------------------------------------------------------
# adaptor_bakiye
# Nakit bakiye ve hisse portfoyu sorgular.
# INT_OVERALL_OZET: R2=cari bakiye, R3=hisse detay, R5=ozet satirlari
# INT_PORTFOY: R1=portfoy listesi (hisse bazli)
# -------------------------------------------------------
adaptor_bakiye() {
    _info_aktif_hesap_kontrol || return 1

    _info_log "Bakiye sorgulamasi basliyor."
    _borsa_veri_sifirla_bakiye

    local tarih
    tarih=$(date +%Y-%m-%d)

    # 1. Hesap ozeti: INT_OVERALL_OZET
    local bakiye_yanit
    bakiye_yanit=$(_info_apicall "$_INFO_SP_BAKIYE" \
        "{\"OverallTarihi\":\"${tarih}\",\"OzetOverall\":1,\"T2_TEK_GUN\":1,\"KULLANIM_AMACI\":5}")

    local bakiye_boyut="${#bakiye_yanit}"
    cekirdek_boyut_kontrol "$bakiye_yanit" 20 "Bakiye sorgusu" "$ADAPTOR_ADI" || return 1
    _info_log "Bakiye yaniti alindi ($bakiye_boyut bayt)."

    # Debug kaydi
    local debug_dosyasi
    debug_dosyasi=$(_info_dosya_yolu "$_CEKIRDEK_DOSYA_DEBUG")
    echo "[$(date '+%H:%M:%S')] Bakiye yaniti:" > "$debug_dosyasi"
    echo "$bakiye_yanit" >> "$debug_dosyasi"

    # 2. Parse: R2[0].ADET = cari nakit bakiye
    # R5 icinde "Net Bakiye" (TIP=NTPL) = nakit, "OVERALL(TL)" (TIP=OVRL) = toplam
    local nakit hisse toplam

    # R5 → Net Bakiye TL (TIP:NTPL) = nakit
    # R5 satirlarini ayirip NTPL icereni bul
    nakit=$(echo "$bakiye_yanit" | grep -oP '"R5"\s*:\s*\[[^]]*\]' | \
        sed 's/},{/}\n{/g' | grep '"NTPL"' | \
        grep -oP '"TBAKIYE"\s*:\s*\K[0-9]+(\.[0-9]+)?' | head -1)
    # R5'te NTPL yoksa R2'deki ADET'e dustle
    [[ -z "$nakit" ]] && nakit=$(echo "$bakiye_yanit" | grep -oP '"R2"\s*:\s*\[\s*\{[^]]*"ADET"\s*:\s*\K[0-9]+(\.[0-9]+)?' | head -1)
    [[ -z "$nakit" ]] && nakit="0"

    # R5 → OVERALL(TL) = toplam varlik (TIP:OVRL)
    # R5 icindeki JSON sirasi: ..., "TBAKIYE":0.510, ..., "TIP":"OVRL"
    # Her R5 satirini ayri satirlara bolup OVRL icereni bul
    toplam=$(echo "$bakiye_yanit" | grep -oP '"R5"\s*:\s*\[[^]]*\]' | \
        sed 's/},{/}\n{/g' | grep '"OVRL"' | \
        grep -oP '"TBAKIYE"\s*:\s*\K[0-9]+(\.[0-9]+)?' | head -1)
    [[ -z "$toplam" ]] && toplam="$nakit"

    # Hisse degeri = toplam - nakit
    hisse=$(echo "$toplam - $nakit" | bc 2>/dev/null || echo "0")
    # Negatif ise 0 yap
    if echo "$hisse" | grep -q '^-'; then
        hisse="0"
    fi

    _info_log "Bakiye: nakit=$nakit, hisse=$hisse, toplam=$toplam"

    # 3. Veri katmanina kaydet + goruntule
    _borsa_veri_kaydet_bakiye "$nakit" "$hisse" "$toplam"
    cekirdek_yazdir_portfoy "$ADAPTOR_ADI" "$nakit" "$hisse" "$toplam"

    # 4. Hisse detaylari: R3 dizisinden parse et (hisse bakiye satirlari)
    # R3 yapisi: [{ACIKLAMA:"THYAO", TBAKIYE:100, MALIYET:50.00, KAPANIS:55.00,
    #             TUTAR3:5500.00, KAR_ZARAR:500.00, KAR_ZARAR_YUZDE:10.00, ADET:100}]
    local r3_bolumu
    r3_bolumu=$(echo "$bakiye_yanit" | grep -oP '"R3"\s*:\s*\[[^]]*\]' | head -1)

    if [[ -n "$r3_bolumu" ]] && [[ "$r3_bolumu" != *'"R3":[]'* ]]; then
        _borsa_veri_sifirla_portfoy

        local satirlar
        satirlar=$(echo "$r3_bolumu" | tr -d '\n' | sed 's/},{/}\n{/g' | grep -oP '\{[^{}]*\}')

        local detay_satirlari=""
        while IFS= read -r satir; do
            [[ -z "$satir" ]] && continue

            local sembol lot son_fiyat piy_degeri maliyet kar kar_yuzdesi

            sembol=$(_info_json_deger_cikar "$satir" "ACIKLAMA")
            [[ -z "$sembol" ]] && continue

            lot=$(_info_json_sayi_cikar "$satir" "TBAKIYE")
            [[ -z "$lot" ]] && lot=$(_info_json_sayi_cikar "$satir" "ADET")
            [[ -z "$lot" ]] && lot="0"

            son_fiyat=$(_info_json_sayi_cikar "$satir" "KAPANIS")
            [[ -z "$son_fiyat" ]] && son_fiyat="0"

            piy_degeri=$(_info_json_sayi_cikar "$satir" "TUTAR3")
            [[ -z "$piy_degeri" ]] && piy_degeri="0"

            maliyet=$(_info_json_sayi_cikar "$satir" "MALIYET")
            [[ -z "$maliyet" ]] && maliyet="0"

            kar=$(_info_json_sayi_cikar "$satir" "KAR_ZARAR")
            [[ -z "$kar" ]] && kar="0"

            kar_yuzdesi=$(_info_json_sayi_cikar "$satir" "KAR_ZARAR_YUZDE")
            [[ -z "$kar_yuzdesi" ]] && kar_yuzdesi="0"

            _borsa_veri_kaydet_hisse "$sembol" "$lot" "$son_fiyat" "$piy_degeri" "$maliyet" "$kar" "$kar_yuzdesi"
            detay_satirlari+="${sembol}\t${lot}\t${son_fiyat}\t${piy_degeri}\t${maliyet}\t${kar}\t${kar_yuzdesi}\n"
        done <<< "$satirlar"

        if [[ -n "$detay_satirlari" ]]; then
            cekirdek_yazdir_portfoy_detay "$ADAPTOR_ADI" "$nakit" "$hisse" "$toplam" "$detay_satirlari"
        fi
    fi

    cekirdek_son_istek_guncelle "info" "$(cekirdek_aktif_hesap "info")"
    return 0
}

# -------------------------------------------------------
# adaptor_portfoy
# Hisse detay listesi — adaptor_bakiye ile ayni endpoint.
# -------------------------------------------------------
adaptor_portfoy() {
    adaptor_bakiye "$@"
}

# -------------------------------------------------------
# adaptor_emirleri_listele
# Bekleyen emirleri listeler.
# INT_BEKLEYEN_EMIRLER stored procedure'u ile cagrilir.
# -------------------------------------------------------
adaptor_emirleri_listele() {
    _info_aktif_hesap_kontrol || return 1

    _info_log "Emir listesi sorgulamasi."
    _borsa_veri_sifirla_emirler

    local yanit
    yanit=$(_info_apicall "$_INFO_SP_BEKLEYEN_EMIRLER" '{}')

    local yanit_boyut="${#yanit}"
    cekirdek_boyut_kontrol "$yanit" 10 "Emir listesi" "$ADAPTOR_ADI" || return 1

    # Parse — emir objeleri
    local satirlar
    satirlar=$(_info_json_objeleri_cikar "$yanit")

    local emir_verileri=""
    local emir_sayisi=0

    while IFS= read -r satir; do
        [[ -z "$satir" ]] && continue

        local referans sembol islem lot fiyat durum tarih

        referans=$(_info_json_deger_cikar "$satir" "EMIR_NO")
        [[ -z "$referans" ]] && referans=$(_info_json_sayi_cikar "$satir" "emirNo")
        [[ -z "$referans" ]] && referans=$(_info_json_sayi_cikar "$satir" "EMIR_REF")

        sembol=$(_info_json_deger_cikar "$satir" "MENKUL_KOD")
        [[ -z "$sembol" ]] && sembol=$(_info_json_deger_cikar "$satir" "menkulKod")

        islem=$(_info_json_deger_cikar "$satir" "ISLEM_TIPI")
        [[ -z "$islem" ]] && islem=$(_info_json_deger_cikar "$satir" "islemTipi")
        [[ -z "$islem" ]] && islem=$(_info_json_deger_cikar "$satir" "AL_SAT")

        lot=$(_info_json_sayi_cikar "$satir" "MIKTAR")
        [[ -z "$lot" ]] && lot=$(_info_json_sayi_cikar "$satir" "miktar")
        [[ -z "$lot" ]] && lot=$(_info_json_sayi_cikar "$satir" "adet")

        fiyat=$(_info_json_sayi_cikar "$satir" "FIYAT")
        [[ -z "$fiyat" ]] && fiyat=$(_info_json_sayi_cikar "$satir" "fiyat")

        durum=$(_info_json_deger_cikar "$satir" "DURUM")
        [[ -z "$durum" ]] && durum=$(_info_json_deger_cikar "$satir" "durum")
        [[ -z "$durum" ]] && durum="Bekliyor"

        tarih=$(_info_json_deger_cikar "$satir" "EMIR_TARIHI")
        [[ -z "$tarih" ]] && tarih=$(_info_json_deger_cikar "$satir" "emirTarihi")

        [[ -z "$sembol" ]] && continue

        _borsa_veri_kaydet_emir "$referans" "$sembol" "$islem" "$lot" "$fiyat" "$durum" "$tarih"
        emir_verileri+="${referans}\t${sembol}\t${islem}\t${lot}\t${fiyat}\t${durum}\t${tarih}\n"
        emir_sayisi=$((emir_sayisi + 1))
    done <<< "$satirlar"

    cekirdek_yazdir_emir_listesi "$ADAPTOR_ADI" "$emir_verileri" "$emir_sayisi"
    cekirdek_son_istek_guncelle "info" "$(cekirdek_aktif_hesap "info")"
    return 0
}

# -------------------------------------------------------
# adaptor_emir_gonder <sembol> <alis|satis> <lot> <fiyat|piyasa>
# Hisse alim/satim emri gonderir.
# INT_EMIR_EKLE_HISSE_ALIS / INT_EMIR_EKLE_HISSE_SATIS
# -------------------------------------------------------
adaptor_emir_gonder() {
    local sembol="$1"
    local islem="$2"
    local lot="$3"
    local fiyat="$4"

    _borsa_veri_sifirla_son_emir

    # 1. Parametre dogrulama
    if [[ -z "$sembol" ]] || [[ -z "$islem" ]] || [[ -z "$lot" ]]; then
        echo "Kullanim: borsa info emir <SEMBOL> <alis|satis> <lot> <fiyat|piyasa>"
        return 1
    fi

    _info_aktif_hesap_kontrol || return 1

    sembol=$(echo "$sembol" | tr '[:lower:]' '[:upper:]')

    # 2. Islem tipi kontrolu
    local sp_adi
    case "$islem" in
        alis|al)
            sp_adi="$_INFO_SP_EMIR_ALIS"
            islem="ALIS"
            ;;
        satis|sat)
            sp_adi="$_INFO_SP_EMIR_SATIS"
            islem="SATIS"
            ;;
        *)
            echo "HATA: Islem tipi 'alis' veya 'satis' olmali."
            return 1
            ;;
    esac

    # 3. Lot sayi dogrulama
    cekirdek_sayi_dogrula "$lot" "Lot" "tam" || return 1

    # 4. Fiyat / piyasa kontrolu
    local emir_tipi="$_INFO_EMIR_TIP_LIMIT"
    if [[ "$fiyat" == "piyasa" ]] || [[ -z "$fiyat" ]]; then
        emir_tipi="$_INFO_EMIR_TIP_PIYASA"
        fiyat="0"
    else
        cekirdek_sayi_dogrula "$fiyat" "Fiyat" "ondalik" || return 1
        # BIST fiyat adimi dogrulamasi
        bist_emir_dogrula "$fiyat" 2>/dev/null
    fi

    # 5. KURU_CALISTIR modu
    if [[ "${KURU_CALISTIR:-0}" == "1" ]]; then
        echo "[KURU] Emir gonderilmedi: $islem $sembol x$lot @ $fiyat ($emir_tipi)"
        _borsa_veri_kaydet_son_emir "KURU" "" "$sembol" "$islem" "$lot" "$fiyat" "" ""
        cekirdek_yazdir_emir_sonuc "KURU" "$sembol" "$islem" "$lot" "$fiyat" "" "" ""
        return 0
    fi

    _info_log "Emir gonderiliyor: $islem $sembol x$lot @ $fiyat ($emir_tipi)"

    # 6. Emir payload olustur ve gonder
    # NOT: Gercek alan adlari (MENKUL_KOD, MIKTAR, FIYAT vb.) canli oturumda
    # teyit edilecek. Simdilik beklenen formatta gonderiyoruz.
    local payload
    payload="{\"MENKUL_KOD\": \"${sembol}\", \"MIKTAR\": ${lot}, \"FIYAT\": ${fiyat}, \"EMIR_TIPI\": \"${emir_tipi}\"}"

    local yanit
    yanit=$(_info_apicall "$sp_adi" "$payload")

    local yanit_boyut="${#yanit}"
    _info_log "Emir yaniti alindi ($yanit_boyut bayt)."

    # 7. Yanit analizi
    local basari
    basari=$(echo "$yanit" | grep -oP '"success"\s*:\s*\K(true|false)' | head -1)

    local referans=""
    referans=$(_info_json_deger_cikar "$yanit" "EMIR_NO")
    [[ -z "$referans" ]] && referans=$(_info_json_sayi_cikar "$yanit" "emirNo")

    if [[ "$basari" == "true" ]] || [[ -n "$referans" ]]; then
        _info_log "BASARILI: Emir kabul edildi. Ref: $referans"
        _borsa_veri_kaydet_son_emir "BASARILI" "$referans" "$sembol" "$islem" "$lot" "$fiyat" "" ""
        cekirdek_yazdir_emir_sonuc "BASARILI" "$sembol" "$islem" "$lot" "$fiyat" "" "" "$referans"
        cekirdek_son_istek_guncelle "info" "$(cekirdek_aktif_hesap "info")"
        return 0
    fi

    # Hata
    local hata_mesaji
    hata_mesaji=$(_info_hata_mesaji_cikar "$yanit")
    [[ -z "$hata_mesaji" ]] && hata_mesaji="Bilinmeyen hata"

    _info_log "HATA: Emir basarisiz. $hata_mesaji"
    echo "HATA: $hata_mesaji"

    # Debug kaydi
    local debug_dosyasi
    debug_dosyasi=$(_info_dosya_yolu "$_CEKIRDEK_DOSYA_DEBUG")
    echo "$yanit" > "$debug_dosyasi"

    return 1
}

# -------------------------------------------------------
# adaptor_emir_iptal <referans>
# Bekleyen emri referans numarasiyla iptal eder.
# INT_EMIR_IPTAL stored procedure'u ile cagrilir.
# -------------------------------------------------------
adaptor_emir_iptal() {
    local referans="$1"

    if [[ -z "$referans" ]]; then
        echo "Kullanim: borsa info iptal <emir_referans>"
        return 1
    fi

    _info_aktif_hesap_kontrol || return 1

    _info_log "Emir iptal istegi: $referans"

    local payload
    payload="{\"EMIR_NO\": \"${referans}\"}"

    local yanit
    yanit=$(_info_apicall "$_INFO_SP_EMIR_IPTAL" "$payload")

    local basari
    basari=$(echo "$yanit" | grep -oP '"success"\s*:\s*\K(true|false)' | head -1)

    if [[ "$basari" == "true" ]]; then
        _info_log "BASARILI: Emir iptal edildi. Ref: $referans"
        cekirdek_yazdir_emir_iptal "$referans" "" "" ""
        cekirdek_son_istek_guncelle "info" "$(cekirdek_aktif_hesap "info")"
        return 0
    fi

    local hata_mesaji
    hata_mesaji=$(_info_hata_mesaji_cikar "$yanit")
    [[ -z "$hata_mesaji" ]] && hata_mesaji="Bilinmeyen hata"

    echo "HATA: Iptal basarisiz. $hata_mesaji"
    return 1
}


# =======================================================
# BOLUM 3: HALKA ARZ (Istege Bagli)
# =======================================================

# -------------------------------------------------------
# adaptor_halka_arz_liste
# Aktif halka arzlari listeler.
# INT_HALKA_ARZLAR_LISTE stored procedure'u ile cagrilir.
# -------------------------------------------------------
adaptor_halka_arz_liste() {
    _info_aktif_hesap_kontrol || return 1

    _info_log "Halka arz listesi sorgulamasi."

    local yanit
    yanit=$(_info_apicall "$_INFO_SP_HALKA_ARZ_LISTE" '{}')

    local yanit_boyut="${#yanit}"
    cekirdek_boyut_kontrol "$yanit" 10 "Halka arz listesi" "$ADAPTOR_ADI" || return 1

    local satirlar
    satirlar=$(_info_json_objeleri_cikar "$yanit")

    local liste_verileri=""

    while IFS= read -r satir; do
        [[ -z "$satir" ]] && continue

        local arz_adi baslangic bitis fiyat

        arz_adi=$(_info_json_deger_cikar "$satir" "TANIM")
        [[ -z "$arz_adi" ]] && arz_adi=$(_info_json_deger_cikar "$satir" "tanim")
        [[ -z "$arz_adi" ]] && continue

        baslangic=$(_info_json_deger_cikar "$satir" "BASLANGIC_TARIHI")
        [[ -z "$baslangic" ]] && baslangic=$(_info_json_deger_cikar "$satir" "baslangicTarihi")

        bitis=$(_info_json_deger_cikar "$satir" "BITIS_TARIHI")
        [[ -z "$bitis" ]] && bitis=$(_info_json_deger_cikar "$satir" "bitisTarihi")

        fiyat=$(_info_json_sayi_cikar "$satir" "FIYAT")
        [[ -z "$fiyat" ]] && fiyat=$(_info_json_sayi_cikar "$satir" "fiyat")

        liste_verileri+="${arz_adi}\t${baslangic}\t${bitis}\t${fiyat}\n"
    done <<< "$satirlar"

    cekirdek_yazdir_halka_arz_liste "$ADAPTOR_ADI" "$liste_verileri" ""
    cekirdek_son_istek_guncelle "info" "$(cekirdek_aktif_hesap "info")"
    return 0
}

# -------------------------------------------------------
# adaptor_halka_arz_talepler
# Kullanicinin mevcut halka arz taleplerini listeler.
# INT_HALKA_ARZLAR_INTERNET_TALEPLERI_LISTESI
# -------------------------------------------------------
adaptor_halka_arz_talepler() {
    _info_aktif_hesap_kontrol || return 1

    _info_log "Halka arz taleplerim sorgulamasi."

    local yanit
    yanit=$(_info_apicall "$_INFO_SP_HALKA_ARZ_TALEPLER" '{}')

    local yanit_boyut="${#yanit}"
    cekirdek_boyut_kontrol "$yanit" 10 "Halka arz talepler" "$ADAPTOR_ADI" || return 1

    local satirlar
    satirlar=$(_info_json_objeleri_cikar "$yanit")

    local talepler_verileri=""

    while IFS= read -r satir; do
        [[ -z "$satir" ]] && continue

        local arz_adi miktar fiyat durum tarih

        arz_adi=$(_info_json_deger_cikar "$satir" "TANIM")
        [[ -z "$arz_adi" ]] && arz_adi=$(_info_json_deger_cikar "$satir" "tanim")

        miktar=$(_info_json_sayi_cikar "$satir" "MIKTAR")
        [[ -z "$miktar" ]] && miktar=$(_info_json_sayi_cikar "$satir" "miktar")

        fiyat=$(_info_json_sayi_cikar "$satir" "FIYAT")
        [[ -z "$fiyat" ]] && fiyat=$(_info_json_sayi_cikar "$satir" "fiyat")

        durum=$(_info_json_deger_cikar "$satir" "DURUM")
        [[ -z "$durum" ]] && durum=$(_info_json_deger_cikar "$satir" "durum")

        tarih=$(_info_json_deger_cikar "$satir" "ISLEM_TARIHI")
        [[ -z "$tarih" ]] && tarih=$(_info_json_deger_cikar "$satir" "islemTarihi")

        talepler_verileri+="${arz_adi}\t${miktar}\t${fiyat}\t${durum}\t${tarih}\n"
    done <<< "$satirlar"

    cekirdek_yazdir_halka_arz_talepler "$ADAPTOR_ADI" "$talepler_verileri" ""
    cekirdek_son_istek_guncelle "info" "$(cekirdek_aktif_hesap "info")"
    return 0
}


# =======================================================
# BOLUM 4: OTURUM CALLBACKLERI
# =======================================================

# -------------------------------------------------------
# adaptor_oturum_uzat <kurum> <hesap>
# Oturum canli tutma callback'i — koruma dongusu cagrir.
# Ping endpoint'ine GET atarak oturumu uzatir.
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
adaptor_oturum_uzat() {
    local hesap="${2:-$(cekirdek_aktif_hesap "info")}"

    local cookie_dosyasi
    cookie_dosyasi=$(cekirdek_dosya_yolu "info" "$_CEKIRDEK_DOSYA_COOKIE" "$hesap")

    [[ ! -f "$cookie_dosyasi" ]] && return 1

    # Ping endpoint'i: 200 = gecerli, 401 = dustu
    local http_kod
    http_kod=$(cekirdek_istek_at \
        -o /dev/null \
        -w "%{http_code}" \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        "$_INFO_PING_URL" 2>/dev/null)

    if [[ "$http_kod" == "200" ]]; then
        return 0
    fi

    _info_log "Oturum uzatma basarisiz (HTTP $http_kod)."
    return 1
}

# -------------------------------------------------------
# adaptor_cikis [hesap]
# Oturumu kapatir (Logout istegi gonderir).
# -------------------------------------------------------
adaptor_cikis() {
    local hesap="${1:-$(cekirdek_aktif_hesap "info")}"

    if [[ -z "$hesap" ]]; then
        echo "HATA: Aktif hesap yok."
        return 1
    fi

    _info_log "Cikis istegi gonderiliyor..."

    # Logout POST istegi
    _info_json_istek "POST" "$_INFO_CIKIS_URL" '{}' > /dev/null 2>&1

    # Oturum koruma dongusunu durdur
    cekirdek_oturum_koruma_durdur "info" "$hesap"

    # Cookie dosyasini temizle
    local cookie_dosyasi
    cookie_dosyasi=$(cekirdek_dosya_yolu "info" "$_CEKIRDEK_DOSYA_COOKIE" "$hesap")
    [[ -f "$cookie_dosyasi" ]] && rm -f "$cookie_dosyasi"

    _info_log "Oturum kapatildi."
    echo "Oturum kapatildi."
}
