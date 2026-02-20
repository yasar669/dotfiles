#!/bin/bash
# shellcheck shell=bash

# Yeni Borsa/Kurum Adaptoru Ayarlar Sablonu
# Kullanim: Bu dosyayi kopyala, kurum adiyla yeniden adlandir.
#           Ornek: cp sablon.ayarlar.sh garanti.ayarlar.sh

# =======================================================
# BOLUM 1: SUNUCU VE OTURUM AYARLARI
# =======================================================

_SABLON_BASE_URL="https://..."
_SABLON_LOGIN_URL="${_SABLON_BASE_URL}/login"
_SABLON_ANA_SAYFA_URL="${_SABLON_BASE_URL}/home"
_SABLON_PORTFOY_URL="${_SABLON_BASE_URL}/portfolio"

_SABLON_FALLBACK_HOSTNAME=""

# Oturum yonetimi artik cekirdek.sh tarafindan saglanir.
# Dizin konvansiyonu: /tmp/borsa/sablon/<musteri_no>/
# Dosya isimleri: _CEKIRDEK_DOSYA_* sabitleri (cekirdek.sh'da tanimli)

# =======================================================
# BOLUM 2: HTML SECICILER (Site Degisince Burasi Guncellenir)
# =======================================================

_SABLON_SEL_HOSTNAME=''
_SABLON_SEL_CSRF_TOKEN=''

_SABLON_KALIP_HATALI_GIRIS=''
_SABLON_KALIP_SMS=''
_SABLON_KALIP_BASARILI_HTML=''
_SABLON_KALIP_BASARILI_JSON=''

_SABLON_SEL_SESSION_GUID=''

_SABLON_ID_NAKIT=""
_SABLON_ID_HISSE=""
_SABLON_METIN_TOPLAM=""
