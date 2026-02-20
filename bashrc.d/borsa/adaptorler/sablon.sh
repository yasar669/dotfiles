#!/bin/bash
# shellcheck shell=bash

# Yeni Borsa/Kurum Adaptor Sablonu
# Kullanim:
#   1. Bu dosyayi kopyala: cp sablon.sh garanti.sh
#   2. sablon.ayarlar.sh'i kopyala: cp sablon.ayarlar.sh garanti.ayarlar.sh
#   3. Iki dosyadaki "sablon" kelimelerini kurum adiyla degistir.
#   4. Fonksiyon govdelerini doldur.

# shellcheck disable=SC2034
readonly ADAPTOR_ADI="sablon"
# shellcheck disable=SC2034
readonly ADAPTOR_SURUMU="1.0.0"

# Ayarlar dosyasini yukle (URL'ler, CSS seciciler burada)
# shellcheck source=/dev/null
source "${BORSA_KLASORU}/adaptorler/sablon.ayarlar.sh"

# =======================================================
# BOLUM 1: DAHILI YARDIMCILAR (Isim oneki: _sablon_)
# =======================================================

# Oturum yonetimi cekirdek fonksiyonlarina delege edilir.
# Asagidaki ince sarmalayicilar (thin wrappers) sadece kurum adini
# gecerek cekirdek_* fonksiyonlarini cagirip adaptor kodunu kisa tutar.

_sablon_log() {
    cekirdek_adaptor_log "sablon" "$1"
}

_sablon_dosya_yolu() {
    cekirdek_dosya_yolu "sablon" "$1" "$2"
}

_sablon_aktif_hesap_kontrol() {
    cekirdek_aktif_hesap_kontrol "sablon"
}

_sablon_cookie_guvence() {
    cekirdek_cookie_guvence "sablon"
}

adaptor_oturum_gecerli_mi() {
    # TODO: Kuruma ozgu oturum gecerlilik kontrolu.
    # Cookie dosyasini okuyup sunucuya GET atarak oturumun
    # hala acik olup olmadigini kontrol edin.
    # Donus: 0 = gecerli, 1 = gecersiz
    return 1
}

_sablon_sayfa_hazirla() {
    # 1. Giris sayfasini GET ile cek.
    # 2. CSRF token ve diger gizli alanlari parse et.
    # 3. "HOSTNAME|TOKEN" formatinda dondur.
    echo "NOT_IMPLEMENTED|NOT_IMPLEMENTED"
}

# =======================================================
# BOLUM 2: GENEL ARABIRIM (cekirdek.sh tarafindan cagrilir)
# =======================================================

adaptor_giris() {
    local kullanici_adi="$1"
    local parola="$2"

    if [[ -z "$kullanici_adi" ]] || [[ -z "$parola" ]]; then
        echo "Kullanim: borsa ${ADAPTOR_ADI} giris [KullaniciAdi] [Parola]"
        return 1
    fi

    # TODO: Gercek giris mantigi buraya yazilir.
    echo "HATA: adaptor_giris henuz uygulanmadi ($ADAPTOR_ADI)"
    return 1
}

adaptor_bakiye() {
    _sablon_aktif_hesap_kontrol || return 1

    # TODO: Parse islemi burada yapilir.
    local nakit=""
    local hisse=""
    local toplam=""

    # Standart cekirdek yazici cagrilir (hic dokunma! bu patterni koru).
    cekirdek_yazdir_portfoy "$ADAPTOR_ADI" "$nakit" "$hisse" "$toplam"
}

adaptor_portfoy() {
    # TODO: Detayli portfoy gosterimi (hisse bazli liste)
    # Geri donus: ekrana hisse listesini yazdirir.
    echo "HATA: adaptor_portfoy henuz uygulanmadi ($ADAPTOR_ADI)"
    return 1
}

adaptor_emir_gonder() {
    local yon="$1"       # ALIS veya SATIS
    local sembol="$2"    # Ornek: THYAO
    local miktar="$3"    # Lot miktari
    local fiyat="$4"     # Birim fiyat (TL)

    if [[ -z "$yon" ]] || [[ -z "$sembol" ]] || [[ -z "$miktar" ]] || [[ -z "$fiyat" ]]; then
        echo "Kullanim: borsa $ADAPTOR_ADI emir <ALIS|SATIS> <SEMBOL> <MIKTAR> <FIYAT>"
        return 1
    fi

    # TODO: Gercek emir gonderme mantigi buraya yazilir.
    # bist_emir_dogrula "$fiyat" fonksiyonunu cagirmayi unutmayin.
    echo "HATA: adaptor_emir_gonder henuz uygulanmadi ($ADAPTOR_ADI)"
    return 1
}

adaptor_emirleri_listele() {
    # TODO: Bekleyen/gerceklesen emirleri listeler.
    # Geri donus: ekrana emir tablosunu yazdirir.
    echo "HATA: adaptor_emirleri_listele henuz uygulanmadi ($ADAPTOR_ADI)"
    return 1
}

adaptor_emir_iptal() {
    local referans="$1"  # Emir referans numarasi

    if [[ -z "$referans" ]]; then
        echo "Kullanim: borsa $ADAPTOR_ADI iptal <REFERANS_NO>"
        return 1
    fi

    # TODO: Emir iptal mantigi buraya yazilir.
    echo "HATA: adaptor_emir_iptal henuz uygulanmadi ($ADAPTOR_ADI)"
    return 1
}

# adaptor_hesap() ve adaptor_hesaplar() tanimlanmiyor.
# cekirdek.sh'daki cekirdek_hesap() ve cekirdek_hesaplar()
# jenerik implementasyonlari otomatik olarak kullanilir.
# Oturum gecerlilik kontrolu icin adaptor_oturum_gecerli_mi()
# callback'ini yukarida uygulayin.
