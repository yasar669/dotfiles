#!/bin/bash
# shellcheck shell=bash

# Osmanli Yatirim Menkul Degerler A.S. Adaptoru
# Bu dosya dogrudan calistirilmaz, cekirdek.sh tarafindan yuklenir.
# Konfigürasyon ve URL: osmanli.ayarlar.sh dosyasinda.
# HTTP istekleri: cekirdek.sh'daki cekirdek_istek_at() ile yapilir.
#
# ONEMLI MIMARI FARKI:
# Ziraat HTML form + AJAX kullanirken, Osmanli tamamen REST JSON API kullanir.
# CSRF token yok, JWT token ile kimlik dogrulama yapilir.
# Bu sayede parse mantigi cok daha basittir (HTML yerine jq/grep ile JSON).

# shellcheck disable=SC2034
if [[ "${ADAPTOR_ADI:-}" != "osmanli" ]]; then
    ADAPTOR_ADI="osmanli" 2>/dev/null || true
fi
if [[ "${ADAPTOR_SURUMU:-}" != "1.0.0" ]]; then
    ADAPTOR_SURUMU="1.0.0" 2>/dev/null || true
fi

# Ayarlar dosyasini yukle
# shellcheck source=/home/yasar/dotfiles/bashrc.d/borsa/adaptorler/osmanli.ayarlar.sh
source "${BORSA_KLASORU}/adaptorler/osmanli.ayarlar.sh"

# =======================================================
# BOLUM 1: DAHILI YARDIMCILAR (Disaridan cagrilmaz)
# =======================================================

# Ince sarmalayicilari otomatik olustur:
#   _osmanli_oturum_dizini, _osmanli_dosya_yolu, _osmanli_aktif_hesap_kontrol,
#   _osmanli_log, _osmanli_cookie_guvence
cekirdek_adaptor_kaydet "osmanli"

# -------------------------------------------------------
# _osmanli_otp_durumu_kaydet <musteri_no> <parola>
# Step1 basarili olup SMS gonderdikten sonra durumu kaydeder.
# Boylece kullanici tekrar giris dediginde Step1'i atlar.
# -------------------------------------------------------
_osmanli_otp_durumu_kaydet() {
    local musteri_no="$1"
    local parola="$2"
    local durum_dosyasi
    durum_dosyasi=$(_osmanli_dosya_yolu "otp_beklemede")
    # Musteri no, parola hash, zaman damgasi kaydet
    local simdi
    simdi=$(date +%s)
    printf '%s\n%s\n%s\n' "$musteri_no" "$parola" "$simdi" > "$durum_dosyasi"
    _osmanli_log "OTP bekleme durumu kaydedildi (zaman: $simdi)."
}

# -------------------------------------------------------
# _osmanli_otp_durumu_oku
# Bekleyen OTP durumunu okur. Cooldown suresi gecmisse siler.
# stdout: "musteri_no|parola" (gecerliyse), bos (degilse)
# Donus: 0 = gecerli bekleme var, 1 = yok/suresi dolmus
# -------------------------------------------------------
_osmanli_otp_durumu_oku() {
    local durum_dosyasi
    durum_dosyasi=$(_osmanli_dosya_yolu "otp_beklemede")
    if [[ ! -f "$durum_dosyasi" ]]; then
        return 1
    fi

    local mn parola zaman
    { read -r mn; read -r parola; read -r zaman; } < "$durum_dosyasi"

    if [[ -z "$mn" || -z "$zaman" ]]; then
        rm -f "$durum_dosyasi"
        return 1
    fi

    local simdi
    simdi=$(date +%s)
    local gecen=$(( simdi - zaman ))

    if [[ "$gecen" -ge "$_OSMANLI_SMS_COOLDOWN_SURESI" ]]; then
        # Cooldown dolmus — dosyayi sil
        rm -f "$durum_dosyasi"
        return 1
    fi

    local kalan=$(( _OSMANLI_SMS_COOLDOWN_SURESI - gecen ))
    echo "${mn}|${parola}|${kalan}"
    return 0
}

# -------------------------------------------------------
# _osmanli_otp_durumu_temizle
# Bekleme durumunu siler (basarili giris veya iptal sonrasi).
# -------------------------------------------------------
_osmanli_otp_durumu_temizle() {
    local durum_dosyasi
    durum_dosyasi=$(_osmanli_dosya_yolu "otp_beklemede")
    [[ -f "$durum_dosyasi" ]] && rm -f "$durum_dosyasi"
}

# -------------------------------------------------------
# _osmanli_hisse_listesi_guncelle
# /Stock/StockList endpoint'inden tum hisse listesini ceker,
# oturum dizinine onbellek dosyasi olarak kaydeder.
# Her satir: menkulno|menkulkod
# Yanit ~6 MB (11000+ enstruman), bu nedenle degiskene atamak
# yerine dogrudan dosyaya yazilir ve dosyadan grep yapilir.
# -------------------------------------------------------
_osmanli_hisse_listesi_guncelle() {
    local onbellek_dosyasi
    onbellek_dosyasi=$(_osmanli_dosya_yolu "hisse_listesi")

    # Onbellek suresi kontrolu
    if [[ -f "$onbellek_dosyasi" ]]; then
        local dosya_zamani
        dosya_zamani=$(stat -c %Y "$onbellek_dosyasi" 2>/dev/null || echo "0")
        local simdi
        simdi=$(date +%s)
        local gecen=$(( simdi - dosya_zamani ))
        if [[ "$gecen" -lt "$_OSMANLI_HISSE_ONBELLEK_SURESI" ]]; then
            return 0
        fi
    fi

    _osmanli_log "Hisse listesi sunucudan cekiliyor..."

    # 6 MB yanit — degiskene atamak yerine dogrudan dosyaya yaz.
    # Cookie kullanilMAZ: TS* (F5/WAF) cookie'leri bu buyuk yanitla
    # birlikte curl'un takilmasina yol acar. Token auth yeterli.
    local ham_dosya="${onbellek_dosyasi}.ham"
    local token
    token=$(_osmanli_token_oku)

    local http_kodu
    http_kodu=$(curl \
        -s \
        --compressed \
        --connect-timeout 15 \
        --max-time 60 \
        -X POST \
        -H "Content-Type: application/json" \
        -H "$_OSMANLI_HEADER_KAYNAK" \
        -H "$_OSMANLI_HEADER_TOKEN_ADI: $token" \
        -d '{}' \
        -o "$ham_dosya" \
        -w "%{http_code}" \
        "$_OSMANLI_HISSE_LISTESI_URL")

    if [[ "$http_kodu" != "200" ]] || [[ ! -s "$ham_dosya" ]]; then
        _osmanli_log "UYARI: Hisse listesi alinamadi (HTTP: ${http_kodu})."
        rm -f "$ham_dosya"
        return 1
    fi

    # JSON dosyasindan menkulno ve menkulkod cikar
    # Yanit yapisi: {"data":{"r1":[{"menkulno":123,"menkulkod":"THYAO",...},...]}}
    local tum_mno tum_mkod
    tum_mno=$(grep -oP '"menkulno"\s*:\s*\K[0-9]+' "$ham_dosya")
    tum_mkod=$(grep -oP '"menkulkod"\s*:\s*"\K[^"]*' "$ham_dosya")

    local sonuc=""
    if [[ -n "$tum_mno" && -n "$tum_mkod" ]]; then
        sonuc=$(paste -d'|' <(echo "$tum_mno") <(echo "$tum_mkod"))
    fi

    if [[ -z "$sonuc" ]]; then
        _osmanli_log "UYARI: Hisse listesinden veri cikarilamadi."
        return 1
    fi

    echo "$sonuc" > "$onbellek_dosyasi"
    local adet
    adet=$(wc -l < "$onbellek_dosyasi")
    _osmanli_log "Hisse listesi guncellendi: $adet hisse."
    rm -f "$ham_dosya"
    return 0
}

# -------------------------------------------------------
# _osmanli_menkul_no_bul <sembol>
# Sembol adini (THYAO) menkulNo sayisal ID'sine cevirir.
# Onbellek dosyasini kullanir.
# stdout: menkulNo (sayisal) veya bos
# -------------------------------------------------------
_osmanli_menkul_no_bul() {
    local sembol="${1^^}"  # Buyuk harfe cevir

    local onbellek_dosyasi
    onbellek_dosyasi=$(_osmanli_dosya_yolu "hisse_listesi")

    # Onbellek yoksa veya eskiyse guncelle
    if [[ ! -f "$onbellek_dosyasi" ]]; then
        _osmanli_hisse_listesi_guncelle || return 1
    fi

    if [[ ! -f "$onbellek_dosyasi" ]]; then
        _osmanli_log "HATA: Hisse listesi dosyasi bulunamadi."
        return 1
    fi

    # FORMAT: menkulno|menkulkod
    local eslesen
    eslesen=$(grep -i "|${sembol}$" "$onbellek_dosyasi" | head -1)
    if [[ -n "$eslesen" ]]; then
        echo "${eslesen%%|*}"
        return 0
    fi

    # Bulunamadi — listeyi yenile ve tekrar dene
    _osmanli_hisse_listesi_guncelle
    eslesen=$(grep -i "|${sembol}$" "$onbellek_dosyasi" | head -1)
    if [[ -n "$eslesen" ]]; then
        echo "${eslesen%%|*}"
        return 0
    fi

    _osmanli_log "HATA: '$sembol' sembolu hisse listesinde bulunamadi."
    return 1
}

# -------------------------------------------------------
# _osmanli_token_oku
# Oturum dizinindeki JWT token dosyasindan tokeni okur.
# stdout: JWT token metni (bossa bos string)
# -------------------------------------------------------
_osmanli_token_oku() {
    local token_dosyasi
    token_dosyasi=$(_osmanli_dosya_yolu "token")
    if [[ -f "$token_dosyasi" ]]; then
        cat "$token_dosyasi"
    fi
}

# -------------------------------------------------------
# _osmanli_token_kaydet <jwt_token>
# JWT token'i oturum dizinine kaydeder.
# -------------------------------------------------------
_osmanli_token_kaydet() {
    local token="$1"
    local token_dosyasi
    token_dosyasi=$(_osmanli_dosya_yolu "token")
    echo "$token" > "$token_dosyasi"
}

# -------------------------------------------------------
# _osmanli_json_istek <metod> <url> [json_govde]
# Osmanli API'sine JSON istek atar. Token header'i otomatik eklenir.
# stdout: Sunucu yaniti (JSON)
# <metod>: GET veya POST
# -------------------------------------------------------
_osmanli_json_istek() {
    local metod="$1"
    local url="$2"
    local govde="${3:-}"

    local token
    token=$(_osmanli_token_oku)

    local cookie_dosyasi
    cookie_dosyasi=$(_osmanli_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")

    if [[ "$metod" == "POST" ]]; then
        if [[ -n "$govde" ]]; then
            cekirdek_istek_at \
                -X POST \
                -c "$cookie_dosyasi" \
                -b "$cookie_dosyasi" \
                -H "Content-Type: application/json" \
                -H "$_OSMANLI_HEADER_KAYNAK" \
                -H "$_OSMANLI_HEADER_TOKEN_ADI: $token" \
                -d "$govde" \
                "$url"
        else
            cekirdek_istek_at \
                -X POST \
                -c "$cookie_dosyasi" \
                -b "$cookie_dosyasi" \
                -H "Content-Type: application/json" \
                -H "$_OSMANLI_HEADER_KAYNAK" \
                -H "$_OSMANLI_HEADER_TOKEN_ADI: $token" \
                "$url"
        fi
    else
        cekirdek_istek_at \
            -c "$cookie_dosyasi" \
            -b "$cookie_dosyasi" \
            -H "$_OSMANLI_HEADER_KAYNAK" \
            -H "$_OSMANLI_HEADER_TOKEN_ADI: $token" \
            "$url"
    fi
}

# -------------------------------------------------------
# _osmanli_json_deger_cikar <json> <alan>
# JSON yanitindan basit alan degeri cikarir (jq gerektirmez).
# Ic ice alanlari desteklemez, yalnizca ust seviye string/sayi.
# stdout: alan degeri
# -------------------------------------------------------
_osmanli_json_deger_cikar() {
    local json="$1"
    local alan="$2"
    echo "$json" | grep -oP "\"${alan}\"\s*:\s*\"\K[^\"]*" | head -1
}

# -------------------------------------------------------
# _osmanli_json_objeleri_cikar <json>
# Pretty-printed JSON yanitindaki en ic seviye {...} objelerini
# ayri satirlar halinde cikarir. Cok satirli JSON desteklenir.
# API'den gelen yanit once tek satira dusurulur, sonra
# },{ ayiricisi ile objelere bolunur.
# stdout: her satir bir JSON objesi
# -------------------------------------------------------
_osmanli_json_objeleri_cikar() {
    local json="$1"
    # Tek satira dusur (pretty-printed JSON icin)
    local tek_satir
    tek_satir=$(echo "$json" | tr -d '\n' | tr -s ' ')
    # En ic seviye objeleri cikar (ic ice {} olmayan)
    echo "$tek_satir" | grep -oP '\{[^{}]+\}'
}

# -------------------------------------------------------
# _osmanli_json_sayi_cikar <json> <alan>
# JSON yanitindan sayisal alan degeri cikarir (tirnak icinde olmayan).
# stdout: sayi degeri
# -------------------------------------------------------
_osmanli_json_sayi_cikar() {
    local json="$1"
    local alan="$2"
    echo "$json" | grep -oP "\"${alan}\"\s*:\s*\K-?[0-9]+\.?[0-9]*" | head -1
}

# -------------------------------------------------------
# _osmanli_json_bool_kontrol <json> <alan> <beklenen>
# JSON'daki boolean alanin beklenen degerle eslesip eslesmedigini kontrol eder.
# Donus: 0 = eslesiyor, 1 = eslesmiyor
# -------------------------------------------------------
_osmanli_json_bool_kontrol() {
    local json="$1"
    local alan="$2"
    local beklenen="$3"
    echo "$json" | grep -qiP "\"${alan}\"\s*:\s*${beklenen}"
}

# -------------------------------------------------------
# _osmanli_json_dizi_parcala <json> <dizi_alani>
# JSON dizisini satirlara ayirir. Her obje ayri satirda.
# Basit yaklasim: },{ ayiricisini kullanir.
# stdout: Her satir bir JSON objesi
# -------------------------------------------------------
_osmanli_json_dizi_parcala() {
    local json="$1"
    local alan="$2"
    # Dizi alanini cikar
    local dizi
    dizi=$(echo "$json" | grep -oP "\"${alan}\"\s*:\s*\[\K[^\]]*")
    # Her objeyi ayri satira koy
    local sonuc="${dizi//\},\{/$'}\n{'}"
    echo "$sonuc"
}

# -------------------------------------------------------
# _osmanli_hata_mesaji_cikar <json_yanit>
# API hata yanitindan mesaj cikarir.
# stdout: hata metni (varsa)
# -------------------------------------------------------
_osmanli_hata_mesaji_cikar() {
    local yanit="$1"
    local mesaj
    # Oncelik 1: message alani
    mesaj=$(_osmanli_json_deger_cikar "$yanit" "message")
    # Oncelik 2: statusMessage alani
    if [[ -z "$mesaj" ]]; then
        mesaj=$(_osmanli_json_deger_cikar "$yanit" "statusMessage")
    fi
    # Oncelik 3: errorMessage alani
    if [[ -z "$mesaj" ]]; then
        mesaj=$(_osmanli_json_deger_cikar "$yanit" "errorMessage")
    fi
    if [[ -n "$mesaj" ]]; then
        echo "$mesaj"
    fi
}

# =======================================================
# BOLUM 2: GENEL ARABIRIM (cekirdek.sh tarafindan cagrilir)
# =======================================================

# -------------------------------------------------------
# adaptor_oturum_gecerli_mi [musteri_no]
# Osmanli API'sine basit GET atarak token gecerliligini kontrol eder.
# -------------------------------------------------------
adaptor_oturum_gecerli_mi() {
    local hesap="${1:-$(cekirdek_aktif_hesap "osmanli")}"

    local token_dosyasi
    token_dosyasi=$(cekirdek_dosya_yolu "osmanli" "token" "$hesap")

    if [[ -z "$token_dosyasi" ]] || [[ ! -f "$token_dosyasi" ]]; then
        return 1
    fi

    local token
    token=$(cat "$token_dosyasi")
    if [[ -z "$token" ]]; then
        return 1
    fi

    # Portfoy endpoint'ine GET at — 401 donerse oturum dusmus
    local cookie_dosyasi
    cookie_dosyasi=$(cekirdek_dosya_yolu "osmanli" "$_CEKIRDEK_DOSYA_COOKIE" "$hesap")

    local kontrol_yaniti
    kontrol_yaniti=$(cekirdek_istek_at \
        -b "$cookie_dosyasi" \
        -H "$_OSMANLI_HEADER_KAYNAK" \
        -H "$_OSMANLI_HEADER_TOKEN_ADI: $token" \
        -w "\nHTTP_CODE:%{http_code}" \
        "$_OSMANLI_PORTFOY_URL" 2>/dev/null)

    local http_kod
    http_kod=$(echo "$kontrol_yaniti" | grep -oP 'HTTP_CODE:\K[0-9]+')

    if [[ "$http_kod" == "200" ]]; then
        return 0
    fi

    return 1
}

# -------------------------------------------------------
# adaptor_oturum_suresi_parse <yanit_icerigi>
# Giris yanitindan oturum suresini saniye cinsinden cikarir.
# Osmanli varsayilan: 3600 saniye (1 saat)
# stdout: saniye cinsinden oturum suresi
# -------------------------------------------------------
adaptor_oturum_suresi_parse() {
    local yanit="$1"
    local sure
    # sessionTimeout veya tokenExpire alani varsa kullan
    sure=$(_osmanli_json_sayi_cikar "$yanit" "sessionTimeout")
    if [[ -z "$sure" ]]; then
        sure=$(_osmanli_json_sayi_cikar "$yanit" "tokenExpire")
    fi
    if [[ -z "$sure" ]] || [[ "$sure" == "0" ]]; then
        sure="$_OSMANLI_OTURUM_SURESI"
    fi
    echo "$sure"
}

# -------------------------------------------------------
# adaptor_giris <musteri_no> <parola>
# Osmanli E-Sube'ye giris yapar (2 adimli: Step1 + OTP/Push Step2).
# -------------------------------------------------------
adaptor_giris() {
    local musteri_no="$1"
    local parola="$2"

    if [[ -z "$musteri_no" ]] || [[ -z "$parola" ]]; then
        echo "Kullanim: borsa osmanli giris <TC_KIMLIK_VEYA_MUSTERI_NO> <PAROLA>"
        return 1
    fi

    # Oturum dizinini hazirla
    cekirdek_aktif_hesap_ayarla "osmanli" "$musteri_no"
    _osmanli_oturum_dizini "$musteri_no" > /dev/null

    # Mevcut oturum gecerli mi?
    if adaptor_oturum_gecerli_mi "$musteri_no"; then
        cekirdek_yazdir_oturum_bilgi "OTURUM ZATEN ACIK" \
            "Musteri" "$musteri_no" \
            "Durum" "Token gecerli, yeniden giris gerekmedi."
        return 0
    fi

    local cookie_dosyasi
    cookie_dosyasi=$(_osmanli_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")
    local debug_dosyasi
    debug_dosyasi=$(_osmanli_dosya_yolu "$_CEKIRDEK_DOSYA_DEBUG")

    # ---- COOLDOWN KONTROLU ----
    # Osmanli SMS gonderdikten sonra 180 sn bekleme uygular.
    # Eger daha once Step1 yapilmis ve SMS gonderilmisse,
    # Step1'i tekrar cagirmak yerine dogrudan OTP sormaya gec.
    local otp_durumu
    if otp_durumu=$(_osmanli_otp_durumu_oku); then
        local onceki_mn onceki_parola kalan_sure
        IFS='|' read -r onceki_mn onceki_parola kalan_sure <<< "$otp_durumu"
        if [[ "$onceki_mn" == "$musteri_no" && "$onceki_parola" == "$parola" ]]; then
            _osmanli_log "Onceki SMS hala gecerli (kalan: ${kalan_sure}sn). Step1 atlaniyor."
            echo "SMS daha once gonderildi (kalan bekleme: ${kalan_sure} saniye)."
            echo "Yeni SMS icin ${kalan_sure} saniye bekleyiniz."
            _osmanli_otp_dogrula "$musteri_no" "$parola"
            return $?
        fi
        # Farkli musteri/parola — eski durumu temizle
        _osmanli_otp_durumu_temizle
    fi

    # ---- ADIM 1: Kullanici adi + sifre gonder ----
    _osmanli_log "Step1: Giris istegi gonderiliyor (Musteri: $musteri_no)..."

    local step1_govde
    step1_govde=$(printf '{"Username":"%s","Password":"%s"}' "$musteri_no" "$parola")

    local step1_yanit
    step1_yanit=$(cekirdek_istek_at \
        -X POST \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Content-Type: application/json" \
        -H "$_OSMANLI_HEADER_KAYNAK" \
        -d "$step1_govde" \
        "$_OSMANLI_LOGIN_STEP1_URL")
    _osmanli_cookie_guvence

    # Debug kaydi
    echo "$step1_yanit" > "$debug_dosyasi"

    # Yanit bos mu?
    if [[ -z "$step1_yanit" ]]; then
        _osmanli_log "HATA: Step1 yaniti bos. Sunucu erisilemez."
        echo "HATA: Osmanli sunucusundan yanit alinamadi."
        cekirdek_aktif_hesap_ayarla "osmanli" ""
        return 1
    fi

    # Sunucu yanit yapisi (gercek test ile teyit edildi):
    # {"data":{"value":null},"success":false,"message":"...",
    #  "statuscode":5640005,"responsestatuscode":200,
    #  "integration":"Optimus","integrationEndpoint":"webapi/Login"}

    # Basarili mi kontrol et
    if _osmanli_json_bool_kontrol "$step1_yanit" "success" "true"; then
        # Step1 basarili — dogrudan token aldik (nadir, 2FA olmadan giris)
        # NOT: Sunucu alan adlarini tamamen kucuk harf kullanir
        local token
        token=$(_osmanli_json_deger_cikar "$step1_yanit" "accesstoken")
        if [[ -n "$token" ]]; then
            _osmanli_token_kaydet "$token"
            local oturum_suresi
            oturum_suresi=$(adaptor_oturum_suresi_parse "$step1_yanit")
            cekirdek_oturum_suresi_kaydet "osmanli" "$musteri_no" "$oturum_suresi"
            cekirdek_son_istek_guncelle "osmanli" "$musteri_no"
            _osmanli_log "BASARILI: Dogrudan giris (2FA atlamali)."
            cekirdek_yazdir_giris_basarili "$ADAPTOR_ADI"
            return 0
        fi
    fi

    # Durum kodunu kontrol et — 2FA turu belirle
    # NOT: Sunucu "statuscode" (tamamen kucuk harf) ve sayi (tirnaksiz) donduruyor
    local durum_kodu
    durum_kodu=$(_osmanli_json_sayi_cikar "$step1_yanit" "statuscode")
    # Alternatif camelCase formati da dene
    if [[ -z "$durum_kodu" ]]; then
        durum_kodu=$(_osmanli_json_sayi_cikar "$step1_yanit" "statusCode")
    fi
    if [[ -z "$durum_kodu" ]]; then
        durum_kodu=$(_osmanli_json_deger_cikar "$step1_yanit" "statuscode")
    fi

    _osmanli_log "Step1 durum kodu: $durum_kodu"

    case "$durum_kodu" in
        "$_OSMANLI_KOD_SMS"|"$_OSMANLI_KOD_OTP")
            _osmanli_log "SMS/OTP dogrulama gerekiyor."
            # Cooldown durumunu kaydet — tekrar giris denemesinde Step1 atlansin
            _osmanli_otp_durumu_kaydet "$musteri_no" "$parola"
            _osmanli_otp_dogrula "$musteri_no" "$parola"
            return $?
            ;;
        "$_OSMANLI_KOD_PUSH")
            _osmanli_log "Push bildirim onay bekleniyor."
            _osmanli_push_bekle "$musteri_no" "$parola" "$step1_yanit"
            return $?
            ;;
        "$_OSMANLI_KOD_YANLIS_SIFRE")
            _osmanli_log "HATA: Kullanici adi veya parola yanlis."
            local hata_mesaji
            hata_mesaji=$(_osmanli_hata_mesaji_cikar "$step1_yanit")
            echo "HATA: ${hata_mesaji:-Kullanici adi veya parola yanlis.}"
            cekirdek_aktif_hesap_ayarla "osmanli" ""
            return 1
            ;;
        "$_OSMANLI_KOD_YENI_KULLANICI")
            _osmanli_log "HATA: Yeni kullanici — ilk giris web uzerinden yapilmali."
            echo "HATA: Ilk giris islemini esube.osmanlimenkul.com.tr uzerinden yapiniz."
            cekirdek_aktif_hesap_ayarla "osmanli" ""
            return 1
            ;;
        "$_OSMANLI_KOD_COK_SIK_ISTEK")
            # Rate-limit: Cooldown suresi icinde tekrar Step1 cagrildi
            local hata_mesaji
            hata_mesaji=$(_osmanli_hata_mesaji_cikar "$step1_yanit")
            _osmanli_log "UYARI: Cok sik giris denemesi (cooldown). Mesaj: $hata_mesaji"
            echo "UYARI: ${hata_mesaji:-Cok sik giris denemesi. Lutfen bekleyip tekrar deneyin.}"
            # Mevcut OTP durumu varsa dogrudan koda yonlendir
            if _osmanli_otp_durumu_oku > /dev/null 2>&1; then
                echo "Daha once gonderilen SMS kodu hala gecerli olabilir."
                _osmanli_otp_dogrula "$musteri_no" "$parola"
                return $?
            fi
            return 1
            ;;
        "$_OSMANLI_KOD_HESAP_PASIF")
            local hata_mesaji
            hata_mesaji=$(_osmanli_hata_mesaji_cikar "$step1_yanit")
            echo "HATA: ${hata_mesaji:-Hesap aktif degil.}"
            cekirdek_aktif_hesap_ayarla "osmanli" ""
            return 1
            ;;
        *)
            # Bilinmeyen durum
            local hata_mesaji
            hata_mesaji=$(_osmanli_hata_mesaji_cikar "$step1_yanit")
            _osmanli_log "HATA: Bilinmeyen Step1 yaniti. Kod: ${durum_kodu:-bos}, Mesaj: $hata_mesaji"
            echo "HATA: ${hata_mesaji:-Giris basarisiz (kod: ${durum_kodu:-?}).}"
            echo "Debug: $debug_dosyasi"
            cekirdek_aktif_hesap_ayarla "osmanli" ""
            return 1
            ;;
    esac
}

# -------------------------------------------------------
# _osmanli_otp_dogrula <musteri_no> <parola>
# SMS/OTP kodunu kullanicidan alip Step2'ye gonderir.
# -------------------------------------------------------
_osmanli_otp_dogrula() {
    local musteri_no="$1"
    local parola="$2"

    cekirdek_yazdir_oturum_bilgi "DIKKAT: Osmanli 2FA Dogrulama Kodu" \
        "Bilgi" "SMS veya Osmanli Sifre uygulamasindaki 6 haneli kodu girin (tire olmadan)."
    local otp_kodu
    read -r otp_kodu

    if [[ -z "$otp_kodu" ]]; then
        _osmanli_log "OTP kodu girilmedi, islem iptal."
        return 1
    fi

    # Tire varsa temizle
    otp_kodu="${otp_kodu//-/}"

    _osmanli_log "Step2: OTP dogrulama gonderiliyor..."

    local cookie_dosyasi
    cookie_dosyasi=$(_osmanli_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")
    local debug_dosyasi
    debug_dosyasi=$(_osmanli_dosya_yolu "$_CEKIRDEK_DOSYA_DEBUG")

    local step2_govde
    step2_govde=$(printf '{"Username":"%s","Password":"%s","Otp":"%s"}' \
        "$musteri_no" "$parola" "$otp_kodu")

    local step2_yanit
    step2_yanit=$(cekirdek_istek_at \
        -X POST \
        -c "$cookie_dosyasi" \
        -b "$cookie_dosyasi" \
        -H "Content-Type: application/json" \
        -H "$_OSMANLI_HEADER_KAYNAK" \
        -d "$step2_govde" \
        "$_OSMANLI_LOGIN_STEP2_URL")

    echo "$step2_yanit" > "$debug_dosyasi"

    if [[ -z "$step2_yanit" ]]; then
        _osmanli_log "HATA: Step2 yaniti bos."
        echo "HATA: Sunucudan yanit alinamadi."
        return 1
    fi

    # Token'i cikar
    local token
    token=$(_osmanli_json_deger_cikar "$step2_yanit" "accesstoken")

    if [[ -n "$token" ]]; then
        _osmanli_token_kaydet "$token"
        _osmanli_otp_durumu_temizle
        local oturum_suresi
        oturum_suresi=$(adaptor_oturum_suresi_parse "$step2_yanit")
        cekirdek_oturum_suresi_kaydet "osmanli" "$musteri_no" "$oturum_suresi"
        cekirdek_son_istek_guncelle "osmanli" "$musteri_no"
        _osmanli_log "BASARILI: OTP dogrulama tamamlandi."
        echo "Tebrikler! Oturum acildi."
        cekirdek_yazdir_giris_basarili "$ADAPTOR_ADI"
        return 0
    fi

    # Basarisiz — ama OTP durumunu silme, kullanici tekrar deneyebilir
    local hata_mesaji
    hata_mesaji=$(_osmanli_hata_mesaji_cikar "$step2_yanit")
    _osmanli_log "HATA: OTP dogrulama basarisiz. Mesaj: $hata_mesaji"
    echo "HATA: ${hata_mesaji:-OTP kodu yanlis veya suresi dolmus.}"
    echo "Tekrar denemek icin: borsa osmanli giris $musteri_no <PAROLA>"
    return 1
}

# -------------------------------------------------------
# _osmanli_push_bekle <musteri_no> <parola> <step1_yanit>
# Push bildirim onayini bekler (polling yapar).
# -------------------------------------------------------
_osmanli_push_bekle() {
    local musteri_no="$1"
    local parola="$2"
    local step1_yanit="$3"

    # Step1 yanitindan customerId ve authenticationKey cikar
    local musteri_id
    musteri_id=$(_osmanli_json_deger_cikar "$step1_yanit" "customerId")
    if [[ -z "$musteri_id" ]]; then
        musteri_id=$(_osmanli_json_sayi_cikar "$step1_yanit" "customerId")
    fi
    local auth_key
    auth_key=$(_osmanli_json_deger_cikar "$step1_yanit" "authenticationKey")

    cekirdek_yazdir_oturum_bilgi "PUSH BILDIRIM ONAY BEKLENIYOR" \
        "Bilgi" "Telefonunuzdaki Osmanli Sifre uygulamasindan giris onayini veriniz." \
        "Bekleme" "Maks. 120 saniye..."

    local cookie_dosyasi
    cookie_dosyasi=$(_osmanli_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")

    local push_govde
    push_govde=$(printf '{"Username":"%s","Password":"%s","CustomerId":%s,"AuthenticationKey":"%s"}' \
        "$musteri_no" "$parola" "${musteri_id:-0}" "${auth_key:-}")

    local deneme=0
    local maks_deneme=24   # 24 x 5sn = 120 saniye

    while [[ "$deneme" -lt "$maks_deneme" ]]; do
        deneme=$((deneme + 1))
        sleep 5

        local push_yanit
        push_yanit=$(cekirdek_istek_at \
            -X POST \
            -c "$cookie_dosyasi" \
            -b "$cookie_dosyasi" \
            -H "Content-Type: application/json" \
            -H "$_OSMANLI_HEADER_KAYNAK" \
            -d "$push_govde" \
            "$_OSMANLI_LOGIN_CHECK_PUSH_URL")

        local token
        token=$(_osmanli_json_deger_cikar "$push_yanit" "accesstoken")

        if [[ -n "$token" ]]; then
            _osmanli_token_kaydet "$token"
            _osmanli_otp_durumu_temizle
            local oturum_suresi
            oturum_suresi=$(adaptor_oturum_suresi_parse "$push_yanit")
            cekirdek_oturum_suresi_kaydet "osmanli" "$musteri_no" "$oturum_suresi"
            cekirdek_son_istek_guncelle "osmanli" "$musteri_no"
            _osmanli_log "BASARILI: Push onay alindi."
            echo ""
            echo "Tebrikler! Oturum acildi."
            cekirdek_yazdir_giris_basarili "$ADAPTOR_ADI"
            return 0
        fi

        printf "."
    done

    echo ""
    _osmanli_log "HATA: Push bildirim zaman asimi (120 sn)."
    echo "HATA: Push bildirim onay suresi doldu."
    echo "Tekrar deneyin veya SMS dogrulamayi kullanin."
    return 1
}

# -------------------------------------------------------
# adaptor_bakiye
# Nakit bakiye, hisse toplam ve genel toplam gosterir.
# -------------------------------------------------------
adaptor_bakiye() {
    _osmanli_aktif_hesap_kontrol || return 1

    _borsa_veri_sifirla_bakiye
    _osmanli_log "Portfoy bilgisi sorgulanıyor..."

    local debug_dosyasi
    debug_dosyasi=$(_osmanli_dosya_yolu "$_CEKIRDEK_DOSYA_DEBUG")

    # 1. Nakit bakiye — LimitCalculate
    # API yanit yapisi: {"data":{"output":[{"netbakiyeCompiled":-2899.99,"bakiye":-5799.98,...}]}}
    # netbakiyeCompiled = gercek TL bakiye, bakiye = alis limiti
    local limit_yanit
    limit_yanit=$(_osmanli_json_istek "POST" "$_OSMANLI_LIMIT_URL" '{}')

    local nakit="0"
    if [[ -n "$limit_yanit" ]]; then
        nakit=$(_osmanli_json_sayi_cikar "$limit_yanit" "netbakiyeCompiled")
        if [[ -z "$nakit" ]]; then
            # Alternatif: bakiye alani
            nakit=$(_osmanli_json_sayi_cikar "$limit_yanit" "bakiye")
        fi
        if [[ -z "$nakit" ]]; then
            nakit="0"
        fi
    fi

    # 2. Portfoy — hisse toplam degeri
    # API yanit yapisi: {"data":[{hisse1},{hisse2},...]} (bos ise {"data":[]})
    local portfoy_yanit
    portfoy_yanit=$(_osmanli_json_istek "GET" "$_OSMANLI_PORTFOY_URL")

    echo "$portfoy_yanit" > "$debug_dosyasi"

    # Boyut kontrolu — JSON API'de bos portfoy {"data":[]} gecerlidir
    if [[ -z "$portfoy_yanit" ]]; then
        _osmanli_log "HATA: Portfoy yaniti bos."
        echo "HATA: Portfoy bilgisi alinamadi."
        return 1
    fi

    # 401 kontrolu
    if echo "$portfoy_yanit" | grep -qP "$_OSMANLI_KALIP_OTURUM_DUSTU"; then
        _osmanli_log "HATA: Oturum dustu (401)."
        echo "HATA: Oturum suresi dolmus. Tekrar giris yapin: borsa osmanli giris"
        return 1
    fi

    # Hisse degerlerini topla
    local hisse_toplam="0"
    local satirlar=""

    # JSON obje parcalama: portfoy verileri data dizisinde
    # Her hisse objesi {...} seklinde
    while IFS= read -r hisse; do
        [[ -z "$hisse" ]] && continue
        # Bos obje veya sadece whitespace atla
        [[ "$hisse" =~ ^[[:space:]]*$ ]] && continue

        local sembol
        sembol=$(_osmanli_json_deger_cikar "$hisse" "menkulkod")
        if [[ -z "$sembol" ]]; then
            sembol=$(_osmanli_json_deger_cikar "$hisse" "hissekodu")
        fi
        if [[ -z "$sembol" ]]; then
            sembol=$(_osmanli_json_deger_cikar "$hisse" "hisseKodu")
        fi
        [[ -z "$sembol" ]] && continue

        local lot
        lot=$(_osmanli_json_sayi_cikar "$hisse" "miktar")
        [[ -z "$lot" || "$lot" == "0" ]] && continue

        local son_fiyat
        son_fiyat=$(_osmanli_json_sayi_cikar "$hisse" "kapanis")
        if [[ -z "$son_fiyat" ]]; then
            son_fiyat=$(_osmanli_json_sayi_cikar "$hisse" "sonFiyat")
        fi

        local piy_degeri
        piy_degeri=$(_osmanli_json_sayi_cikar "$hisse" "t2bakiye")
        if [[ -z "$piy_degeri" ]]; then
            piy_degeri=$(_osmanli_json_sayi_cikar "$hisse" "piyasaDegeri")
        fi
        if [[ -z "$piy_degeri" ]]; then
            # Alternatif: lot * son fiyat
            if [[ -n "$lot" && -n "$son_fiyat" ]]; then
                piy_degeri=$(echo "$lot * $son_fiyat" | bc 2>/dev/null)
            fi
        fi

        local maliyet
        maliyet=$(_osmanli_json_sayi_cikar "$hisse" "maliyet")
        if [[ -z "$maliyet" ]]; then
            maliyet=$(_osmanli_json_sayi_cikar "$hisse" "maliyetToplam")
        fi

        local kar_zarar="0"
        local kar_yuzde="0"
        if [[ -n "$piy_degeri" && -n "$maliyet" ]] && \
           [[ "$maliyet" != "0" ]]; then
            kar_zarar=$(echo "$piy_degeri - $maliyet" | bc 2>/dev/null)
            kar_yuzde=$(echo "scale=2; ($kar_zarar / $maliyet) * 100" | bc 2>/dev/null)
        fi

        # Hisse toplam degeri guncelle
        if [[ -n "$piy_degeri" ]]; then
            hisse_toplam=$(echo "$hisse_toplam + $piy_degeri" | bc 2>/dev/null)
        fi

        _borsa_veri_kaydet_hisse "$sembol" "${lot:-0}" "${son_fiyat:-0}" \
            "${piy_degeri:-0}" "${maliyet:-0}" "${kar_zarar:-0}" "${kar_yuzde:-0}"

        # TAB ayricli satir formatinda ekle
        satirlar+=$(printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$sembol" "${lot:-0}" "${son_fiyat:-0}" \
            "${piy_degeri:-0}" "${maliyet:-0}" "${kar_zarar:-0}" "${kar_yuzde:-0}%")
    done < <(_osmanli_json_objeleri_cikar "$portfoy_yanit")

    # Toplam
    local toplam
    toplam=$(echo "$nakit + $hisse_toplam" | bc 2>/dev/null)
    [[ -z "$toplam" ]] && toplam="$nakit"

    # Veri katmanina kaydet
    _borsa_veri_kaydet_bakiye "$nakit" "$hisse_toplam" "$toplam"

    # JSON API saglik kontrolu (cekirdek_saglik_kontrol HTML icin tasarlanmis,
    # JSON API'de boyut ve isaret noktasi kontrolleri gecersiz).
    # Kendi JSON-spesifik kontrolumuzu yapariz:
    if [[ "$nakit" == "0" && "$hisse_toplam" == "0" ]]; then
        # Limit yaniti basarisiz mi?
        if [[ -n "$limit_yanit" ]] && ! _osmanli_json_bool_kontrol "$limit_yanit" "success" "true"; then
            local hata
            hata=$(_osmanli_hata_mesaji_cikar "$limit_yanit")
            _osmanli_log "UYARI: LimitCalculate basarisiz: $hata"
        fi
    fi

    # Goster
    if [[ -n "$satirlar" ]]; then
        cekirdek_yazdir_portfoy_detay "$ADAPTOR_ADI" "$nakit" "$hisse_toplam" "$toplam" "$satirlar"
    else
        cekirdek_yazdir_portfoy "$ADAPTOR_ADI" "$nakit" "$hisse_toplam" "$toplam"
    fi

    cekirdek_son_istek_guncelle "osmanli" "$(cekirdek_aktif_hesap "osmanli")"
    return 0
}

# -------------------------------------------------------
# adaptor_portfoy
# Hisse detay tablosu gosterir.
# -------------------------------------------------------
adaptor_portfoy() {
    # adaptor_bakiye zaten portfoy detayini da gosteriyor
    adaptor_bakiye
}

# -------------------------------------------------------
# adaptor_emirleri_listele
# Bekleyen hisse emirlerini listeler.
# -------------------------------------------------------
adaptor_emirleri_listele() {
    _osmanli_aktif_hesap_kontrol || return 1

    _osmanli_log "Bekleyen emirler sorgulanıyor..."

    # NOT: Bu endpoint POST istiyor (GET -> 405), bos govde ile
    local yanit
    yanit=$(_osmanli_json_istek "POST" "$_OSMANLI_EMIR_BEKLEYEN_URL" '{}')

    if [[ -z "$yanit" ]]; then
        _osmanli_log "HATA: Emir listesi yaniti bos."
        echo "HATA: Emir listesi alinamadi."
        return 1
    fi

    # 401 kontrolu
    if echo "$yanit" | grep -qP "$_OSMANLI_KALIP_OTURUM_DUSTU"; then
        _osmanli_log "HATA: Oturum dustu (401)."
        echo "HATA: Oturum suresi dolmus. Tekrar giris yapin: borsa osmanli giris"
        return 1
    fi

    local debug_dosyasi
    debug_dosyasi=$(_osmanli_dosya_yolu "$_CEKIRDEK_DOSYA_EMIR_LISTE")
    echo "$yanit" > "$debug_dosyasi"

    local bulunan=0
    local satirlar=""
    _borsa_veri_sifirla_emirler

    # API yanit yapisi: {"data":{"r1":[{emir1},{emir2},...], "output":[{"returnvalue":0}]}}
    # Emirler r1 dizisinde gelir
    while IFS= read -r emir; do
        [[ -z "$emir" ]] && continue
        [[ "$emir" =~ ^[[:space:]]*$ ]] && continue
        # returnvalue objelerini atla
        echo "$emir" | grep -q '"returnvalue"' && continue

        local ext_id sembol_p islem_p fiyat_p adet_p durum_p iptal_var

        # Referans
        ext_id=$(_osmanli_json_deger_cikar "$emir" "referansNo")
        if [[ -z "$ext_id" ]]; then
            ext_id=$(_osmanli_json_deger_cikar "$emir" "emirNo")
        fi
        if [[ -z "$ext_id" ]]; then
            ext_id=$(_osmanli_json_sayi_cikar "$emir" "id")
        fi

        # Sembol
        sembol_p=$(_osmanli_json_deger_cikar "$emir" "hissekodu")
        if [[ -z "$sembol_p" ]]; then
            sembol_p=$(_osmanli_json_deger_cikar "$emir" "hisseKodu")
        fi
        if [[ -z "$sembol_p" ]]; then
            sembol_p=$(_osmanli_json_deger_cikar "$emir" "menkulkod")
        fi

        # Islem yonu
        islem_p=$(_osmanli_json_deger_cikar "$emir" "islemYonu")
        if [[ -z "$islem_p" ]]; then
            islem_p=$(_osmanli_json_deger_cikar "$emir" "islemyonu")
        fi
        case "${islem_p:-}" in
            A|a|ALIS|alis) islem_p="Alis" ;;
            S|s|SATIS|satis) islem_p="Satis" ;;
            T|t) islem_p="AcSat" ;;
            *) islem_p="${islem_p:-?}" ;;
        esac

        # Fiyat
        fiyat_p=$(_osmanli_json_sayi_cikar "$emir" "fiyat")

        # Adet
        adet_p=$(_osmanli_json_sayi_cikar "$emir" "miktar")
        if [[ -z "$adet_p" ]]; then
            adet_p=$(_osmanli_json_sayi_cikar "$emir" "adet")
        fi

        # Durum
        durum_p=$(_osmanli_json_deger_cikar "$emir" "durumAciklama")
        if [[ -z "$durum_p" ]]; then
            durum_p=$(_osmanli_json_deger_cikar "$emir" "durum")
        fi
        [[ -z "$durum_p" ]] && durum_p="Beklemede"

        # Bekleyen emir = iptal edilebilir
        iptal_var="[*]"
        _borsa_veri_kaydet_emir "${ext_id:-?}" "${sembol_p:-}" "${islem_p:-}" \
            "${adet_p:-}" "${fiyat_p:-}" "$durum_p" "$iptal_var"

        satirlar+=$(printf " %-12s %-8s %-6s %-10s %-6s %-12s %s\n" \
            "${ext_id:-?}" "${sembol_p:-?}" "${islem_p:-?}" \
            "${fiyat_p:-?}" "${adet_p:-?}" "$durum_p" "$iptal_var")
        satirlar+=$'\n'
        bulunan=$((bulunan + 1))
    done < <(_osmanli_json_objeleri_cikar "$yanit")
    _BORSA_VERI_EMIRLER_ZAMAN=$(date +%s)

    cekirdek_yazdir_emir_listesi "$ADAPTOR_ADI" "$satirlar" "$bulunan"
    _osmanli_log "Toplam $bulunan bekleyen emir listelendi."
    cekirdek_son_istek_guncelle "osmanli" "$(cekirdek_aktif_hesap "osmanli")"
    return 0
}

# -------------------------------------------------------
# adaptor_emir_gonder <sembol> <alis|satis> <lot> <fiyat|piyasa> [bildirim]
# Hisse alim/satim emri gonderir.
# -------------------------------------------------------
adaptor_emir_gonder() {
    local sembol="$1"
    local islem="$2"
    local lot="$3"
    local fiyat="$4"
    # shellcheck disable=SC2034
    local bildirim_turu="$5"   # Osmanli'da geribildirim kanali (opsiyonel)
    _borsa_veri_sifirla_son_emir

    # --- Parametre Kontrolu ---
    if [[ -z "$sembol" || -z "$islem" || -z "$lot" || -z "$fiyat" ]]; then
        echo "Kullanim: $ADAPTOR_ADI emir SEMBOL alis|satis LOT FIYAT|piyasa"
        return 1
    fi

    # Sembol buyuk harf
    sembol="${sembol^^}"

    # --- Emir turu tespiti: piyasa vs limit ---
    local emir_tipi
    local emir_seans
    local piyasa_mi=0

    if [[ "${fiyat,,}" == "piyasa" ]]; then
        piyasa_mi=1
        emir_tipi="$_OSMANLI_EMIR_TIP_PIYASA"
        emir_seans="$_OSMANLI_EMIR_SEANS_KIE"
        fiyat="0"
    else
        emir_tipi="$_OSMANLI_EMIR_TIP_LIMIT"
        emir_seans="$_OSMANLI_EMIR_SEANS_GUNLUK"
    fi

    # Islem turu ve hedef URL
    local hedef_url
    case "$islem" in
        alis)
            hedef_url="$_OSMANLI_EMIR_ALIS_URL"
            ;;
        satis)
            hedef_url="$_OSMANLI_EMIR_SATIS_URL"
            ;;
        *)
            echo "HATA: Gecersiz islem turu '$islem'. Kullanim: alis | satis"
            return 1
            ;;
    esac

    # Lot sayisal mi?
    if ! cekirdek_sayi_dogrula "$lot" "Lot" "$ADAPTOR_ADI"; then
        return 1
    fi

    # Limit emirlerde fiyat ve BIST adim kontrolu
    if [[ "$piyasa_mi" -eq 0 ]]; then
        if ! cekirdek_sayi_dogrula "$fiyat" "Fiyat" "$ADAPTOR_ADI"; then
            return 1
        fi
        if ! bist_emir_dogrula "$fiyat"; then
            return 1
        fi
    fi

    # Trap: fonksiyon nasil biterse bitsin son emir kaydedilir
    local _vk_basarili="0" _vk_referans="" _vk_mesaj="Emir reddedildi"
    trap '_borsa_veri_kaydet_son_emir "$_vk_basarili" "$_vk_referans" "$sembol" "${islem^^}" "$lot" "$fiyat" "$piyasa_mi" "$_vk_mesaj"' RETURN

    # Fiyat gosterimi
    local fiyat_gosterim
    if [[ "$piyasa_mi" -eq 1 ]]; then
        fiyat_gosterim="PIYASA"
    else
        fiyat_gosterim="$fiyat TL"
    fi

    # Kuru calistirma modu
    if [[ "${KURU_CALISTIR:-0}" == "1" ]]; then
        _osmanli_log "KURU CALISTIR: $islem $lot lot $sembol @ $fiyat_gosterim (emir GONDERILMEDI)"
        cekirdek_yazdir_emir_sonuc "[KURU CALISTIR] EMIR BILGISI" \
            "$sembol" "$islem ($emir_tipi)" "$lot" "$fiyat_gosterim" "$emir_tipi" "GONDERILMEDI"
        _vk_basarili="1"; _vk_referans="KURU"
        _vk_mesaj="Kuru calistirma — emir gonderilmedi"
        return 0
    fi

    # --- Gercek emir gonderimi ---
    _osmanli_aktif_hesap_kontrol || return 1

    _osmanli_log "Emir gonderiliyor: $islem $lot lot $sembol @ $fiyat_gosterim..."

    # MenkulNo: Osmanli API sayisal ID istiyor, sembol kodu degil.
    # Oncelikle hisse listesinden menkulNo'yu bul.
    local menkul_no
    menkul_no=$(_osmanli_menkul_no_bul "$sembol")
    if [[ -z "$menkul_no" ]]; then
        echo "HATA: '$sembol' sembolu icin MenkulNo bulunamadi."
        echo "Hisse kodu dogru mu kontrol edin."
        _vk_mesaj="MenkulNo bulunamadi: $sembol"
        return 1
    fi
    _osmanli_log "Sembol: $sembol -> MenkulNo: $menkul_no"

    # JSON payload olustur
    local payload
    if [[ "$islem" == "alis" ]]; then
        # Alis: AltPazarRBF dahil
        payload=$(printf '{"EmirTipi":"%s","Fiyat":%s,"MenkulNo":"%s","Miktar":%s,"Seans":"%s","GeriBildirimKanali":" ","AltPazarRBF":0}' \
            "$emir_tipi" "$fiyat" "$menkul_no" "$lot" "$emir_seans")
    else
        # Satis: AltPazarRBF yok
        payload=$(printf '{"EmirTipi":"%s","Fiyat":%s,"MenkulNo":"%s","Miktar":%s,"Seans":"%s","GeriBildirimKanali":" "}' \
            "$emir_tipi" "$fiyat" "$menkul_no" "$lot" "$emir_seans")
    fi

    local yanit
    yanit=$(_osmanli_json_istek "POST" "$hedef_url" "$payload")

    local debug_dosyasi
    debug_dosyasi=$(_osmanli_dosya_yolu "$_CEKIRDEK_DOSYA_EMIR_YANIT")
    echo "$yanit" > "$debug_dosyasi"

    if [[ -z "$yanit" ]]; then
        _osmanli_log "HATA: Emir yaniti bos."
        echo "HATA: Sunucudan yanit alinamadi."
        return 1
    fi

    # 401 kontrolu
    if echo "$yanit" | grep -qP "$_OSMANLI_KALIP_OTURUM_DUSTU"; then
        _osmanli_log "HATA: Oturum dustu (401)."
        echo "HATA: Oturum suresi dolmus. Tekrar giris yapin: borsa osmanli giris"
        return 1
    fi

    # Basari kontrolu
    if _osmanli_json_bool_kontrol "$yanit" "success" "true"; then
        local referans
        referans=$(_osmanli_json_deger_cikar "$yanit" "referansNo")
        if [[ -z "$referans" ]]; then
            referans=$(_osmanli_json_deger_cikar "$yanit" "emirNo")
        fi
        _osmanli_log "BASARILI: Emir gonderildi. Referans: ${referans:-?}"
        cekirdek_yazdir_emir_sonuc "EMIR GONDERILDI" \
            "$sembol" "$islem ($emir_tipi)" "$lot" "$fiyat_gosterim" \
            "$emir_tipi" "ILETILDI" "${referans:-}"
        _vk_basarili="1"; _vk_referans="${referans:-}"
        _vk_mesaj="Emir basariyla iletildi"
        cekirdek_son_istek_guncelle "osmanli" "$(cekirdek_aktif_hesap "osmanli")"
        return 0
    fi

    # Hata
    local hata_mesaji
    hata_mesaji=$(_osmanli_hata_mesaji_cikar "$yanit")
    _osmanli_log "HATA: Emir basarisiz. Yanit: $hata_mesaji"
    echo "HATA: ${hata_mesaji:-Emir gonderilemedi.}"
    echo "Debug: $debug_dosyasi"
    _vk_mesaj="${hata_mesaji:-Emir basarisiz}"
    return 1
}

# -------------------------------------------------------
# adaptor_emir_iptal <referans>
# Bekleyen emri iptal eder.
# -------------------------------------------------------
adaptor_emir_iptal() {
    local ext_id="$1"

    if [[ -z "$ext_id" ]]; then
        echo "Kullanim: $ADAPTOR_ADI iptal <REFERANS>"
        echo "Referans numarasini gormek icin once: borsa osmanli emirler"
        return 1
    fi

    _osmanli_aktif_hesap_kontrol || return 1
    _borsa_veri_sifirla_son_emir

    # Trap: fonksiyon nasil biterse bitsin son emir kaydedilir
    local _vk_basarili="0" _vk_mesaj="Iptal basarisiz"
    trap '_borsa_veri_kaydet_son_emir "$_vk_basarili" "$ext_id" "" "IPTAL" "" "" "0" "$_vk_mesaj"' RETURN

    _osmanli_log "Emir iptal ediliyor. Referans: $ext_id"

    # Iptal istegi gonder — JSON payload ile referans gonderilir
    local payload
    payload=$(printf '{"referansNo":"%s"}' "$ext_id")

    local yanit
    yanit=$(_osmanli_json_istek "POST" "$_OSMANLI_EMIR_IPTAL_URL" "$payload")

    local debug_dosyasi
    debug_dosyasi=$(_osmanli_dosya_yolu "$_CEKIRDEK_DOSYA_IPTAL_DEBUG")
    echo "$yanit" > "$debug_dosyasi"

    if [[ -z "$yanit" ]]; then
        _osmanli_log "HATA: Iptal yaniti bos."
        echo "HATA: Sunucudan yanit alinamadi."
        return 1
    fi

    # 401 kontrolu
    if echo "$yanit" | grep -qP "$_OSMANLI_KALIP_OTURUM_DUSTU"; then
        echo "HATA: Oturum suresi dolmus. Tekrar giris yapin: borsa osmanli giris"
        return 1
    fi

    # Basari kontrolu
    if _osmanli_json_bool_kontrol "$yanit" "success" "true"; then
        local mesaj
        mesaj=$(_osmanli_hata_mesaji_cikar "$yanit")
        _osmanli_log "BASARILI: Emir iptal edildi. Referans: $ext_id"
        cekirdek_yazdir_emir_iptal "$ext_id" "$ext_id" "IPTAL TALEBI ALINDI" "${mesaj:-}"
        _vk_basarili="1"; _vk_mesaj="${mesaj:-Emir iptal edildi}"
        cekirdek_son_istek_guncelle "osmanli" "$(cekirdek_aktif_hesap "osmanli")"
        return 0
    fi

    # Hata
    local hata_mesaji
    hata_mesaji=$(_osmanli_hata_mesaji_cikar "$yanit")
    _osmanli_log "HATA: Iptal basarisiz. Mesaj: $hata_mesaji"
    echo "HATA: ${hata_mesaji:-Emir iptal edilemedi.}"
    _vk_mesaj="${hata_mesaji:-Iptal basarisiz}"
    return 1
}

# =======================================================
# BOLUM 3: HALKA ARZ (Istege Bagli)
# =======================================================

# -------------------------------------------------------
# adaptor_halka_arz_liste
# Aktif halka arzlari listeler.
# -------------------------------------------------------
adaptor_halka_arz_liste() {
    _osmanli_aktif_hesap_kontrol || return 1

    _borsa_veri_sifirla_halka_arz_liste
    _osmanli_log "Halka arz listesi sorgulanıyor..."

    local yanit
    yanit=$(_osmanli_json_istek "GET" "$_OSMANLI_HALKA_ARZ_LISTE_URL")

    if [[ -z "$yanit" ]]; then
        echo "HATA: Halka arz listesi alinamadi."
        return 1
    fi

    if echo "$yanit" | grep -qP "$_OSMANLI_KALIP_OTURUM_DUSTU"; then
        echo "HATA: Oturum suresi dolmus. Tekrar giris yapin: borsa osmanli giris"
        return 1
    fi

    local satirlar=""
    local bulunan=0

    # API yanit yapisi: {"data":{"r1":[...halka_arzlar...], "r2":[...], "output":[...]}}
    # Halka arz objeleri r1 dizisinde gelir
    while IFS= read -r arz; do
        [[ -z "$arz" ]] && continue
        [[ "$arz" =~ ^[[:space:]]*$ ]] && continue
        # returnvalue ve tcKimlikNo objelerini atla
        echo "$arz" | grep -q '"returnvalue"' && continue
        echo "$arz" | grep -q '"tcKimlikNo"' && continue

        local ipo_id ipo_adi durum

        ipo_id=$(_osmanli_json_sayi_cikar "$arz" "id")
        if [[ -z "$ipo_id" ]]; then
            ipo_id=$(_osmanli_json_deger_cikar "$arz" "id")
        fi
        [[ -z "$ipo_id" ]] && continue

        ipo_adi=$(_osmanli_json_deger_cikar "$arz" "name")
        if [[ -z "$ipo_adi" ]]; then
            ipo_adi=$(_osmanli_json_deger_cikar "$arz" "ad")
        fi

        durum=$(_osmanli_json_deger_cikar "$arz" "status")
        if [[ -z "$durum" ]]; then
            durum=$(_osmanli_json_deger_cikar "$arz" "durum")
        fi

        _borsa_veri_kaydet_halka_arz "$ipo_id" "${ipo_adi:-?}" "" "" "${durum:-?}"

        # cekirdek_yazdir_halka_arz_liste beklenen format: AD\tTIP\tODEME_SEKLI\tDURUM\tIPO_ID
        satirlar+=$(printf "%s\t%s\t%s\t%s\t%s\n" "${ipo_adi:-?}" "-" "-" "${durum:-?}" "$ipo_id")
        bulunan=$((bulunan + 1))
    done < <(_osmanli_json_objeleri_cikar "$yanit")

    cekirdek_yazdir_halka_arz_liste "$ADAPTOR_ADI" "" "$satirlar"

    cekirdek_son_istek_guncelle "osmanli" "$(cekirdek_aktif_hesap "osmanli")"
    return 0
}

# -------------------------------------------------------
# adaptor_halka_arz_talepler
# Kullanicinin mevcut halka arz taleplerini listeler.
# -------------------------------------------------------
adaptor_halka_arz_talepler() {
    _osmanli_aktif_hesap_kontrol || return 1

    _borsa_veri_sifirla_halka_arz_talepler
    _osmanli_log "Halka arz talepleri sorgulanıyor..."

    local yanit
    yanit=$(_osmanli_json_istek "POST" "$_OSMANLI_HALKA_ARZ_TALEPLER_URL")

    if [[ -z "$yanit" ]]; then
        echo "HATA: Halka arz talep listesi alinamadi."
        return 1
    fi

    if echo "$yanit" | grep -qP "$_OSMANLI_KALIP_OTURUM_DUSTU"; then
        echo "HATA: Oturum suresi dolmus. Tekrar giris yapin: borsa osmanli giris"
        return 1
    fi

    local bulunan=0
    local satirlar=""

    # API yanit yapisi: {"data":{"r1":[...talepler...], "output":[...]}}
    while IFS= read -r talep; do
        [[ -z "$talep" ]] && continue
        [[ "$talep" =~ ^[[:space:]]*$ ]] && continue
        echo "$talep" | grep -q '"returnvalue"' && continue
        echo "$talep" | grep -q '"tcKimlikNo"' && continue

        local tid tadi tlot tdurum ttarih

        tid=$(_osmanli_json_sayi_cikar "$talep" "id")
        if [[ -z "$tid" ]]; then
            tid=$(_osmanli_json_deger_cikar "$talep" "id")
        fi
        [[ -z "$tid" ]] && continue

        tadi=$(_osmanli_json_deger_cikar "$talep" "name")
        if [[ -z "$tadi" ]]; then
            tadi=$(_osmanli_json_deger_cikar "$talep" "ad")
        fi

        tlot=$(_osmanli_json_sayi_cikar "$talep" "lot")
        if [[ -z "$tlot" ]]; then
            tlot=$(_osmanli_json_sayi_cikar "$talep" "miktar")
        fi

        tdurum=$(_osmanli_json_deger_cikar "$talep" "durum")
        ttarih=$(_osmanli_json_deger_cikar "$talep" "tarih")

        # cekirdek_yazdir_halka_arz_talepler beklenen format: AD\tTARIH\tLOT\tFIYAT\tTUTAR\tDURUM\tTALEP_ID
        satirlar+=$(printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "${tadi:-?}" "${ttarih:--}" "${tlot:--}" "-" "-" "${tdurum:-?}" "${tid:-?}")
        bulunan=$((bulunan + 1))
    done < <(_osmanli_json_objeleri_cikar "$yanit")

    cekirdek_yazdir_halka_arz_talepler "$ADAPTOR_ADI" "$satirlar"

    cekirdek_son_istek_guncelle "osmanli" "$(cekirdek_aktif_hesap "osmanli")"
    return 0
}

# =======================================================
# BOLUM 4: OTURUM CALLBACKLERI
# =======================================================

# -------------------------------------------------------
# adaptor_oturum_uzat <kurum> <hesap>
# Oturum canli tutma callback'i — koruma dongusu cagrir.
# Basit bir API cagrisi yaparak oturumu uzatir.
# Token gonderilerek yapilan herhangi bir istek oturumu uzatir.
# En hafif endpoint: portfoy (GET).
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
adaptor_oturum_uzat() {
    local hesap="${2:-$(cekirdek_aktif_hesap "osmanli")}"

    local yanit
    yanit=$(_osmanli_json_istek "GET" "$_OSMANLI_PORTFOY_URL" 2>/dev/null)
    local cikis_kodu=$?

    # HTTP hatasi veya bos yanit kontrolu
    if [[ "$cikis_kodu" -ne 0 ]] || [[ -z "$yanit" ]]; then
        _osmanli_log "Oturum uzatma basarisiz (HTTP hata veya bos yanit)."
        return 1
    fi

    # Yanit icerisinde hata mesaji varsa
    if echo "$yanit" | grep -qi '"error"\|"unauthorized"\|"expired"'; then
        _osmanli_log "Oturum uzatma basarisiz (sunucu hata dondurdu)."
        return 1
    fi

    return 0
}

# -------------------------------------------------------
# adaptor_cikis
# Oturumu kapatir (LogOff istegi gonderir).
# -------------------------------------------------------
adaptor_cikis() {
    _osmanli_log "Cikis istegi gonderiliyor..."
    _osmanli_json_istek "POST" "$_OSMANLI_CIKIS_URL" > /dev/null 2>&1

    # Token dosyasini temizle
    local token_dosyasi
    token_dosyasi=$(_osmanli_dosya_yolu "token")
    [[ -f "$token_dosyasi" ]] && rm -f "$token_dosyasi"

    _osmanli_log "Oturum kapatildi."
}
