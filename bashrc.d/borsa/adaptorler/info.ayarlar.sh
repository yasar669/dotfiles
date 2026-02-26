#!/bin/bash
# shellcheck shell=bash

# Info Yatirim Menkul Degerler A.S. Adaptoru - Ayarlar Dosyasi
# Bu dosya dogrudan calistirilmaz, info.sh tarafindan yuklenir.
# Degisiklik gerektiren durum: Info E-Sube sitesi guncellenmis olabilir.
# Bu dosyayi duzenlemek icin info.sh'a dokunmaya gerek yok.

# =======================================================
# BOLUM 1: SUNUCU VE OTURUM AYARLARI
# =======================================================

# E-Sube: UmiJS 3.5.41 React SPA, REST JSON API
# Backend: Microsoft IIS 10.0, ASP.NET
_INFO_BASE_URL="https://esube.infoyatirim.com"
_INFO_API_URL="${_INFO_BASE_URL}/webapi"

# Giris endpoint'i (tek adimli POST, SMS/OTP ayri akis)
_INFO_LOGIN_URL="${_INFO_API_URL}/login"

# Giris sonrasi kullanici bilgisi
_INFO_USERS_URL="${_INFO_API_URL}/users"

# Portfoy & bakiye (generic ApiCall — stored procedure isimleri)
_INFO_APICALL_URL="${_INFO_API_URL}/ApiCall"
_INFO_APICALL_ANON_URL="${_INFO_API_URL}/ApiCall/anonymous"

# Bilinen stored procedure isimleri (ApiCall endpointine symbolName olarak gonderilir)
_INFO_SP_MUSTERI_INFO="ESUBE_MUSTERI_INFO"
_INFO_SP_BEKLEYEN_EMIRLER="INT_BEKLEYEN_EMIRLER"
_INFO_SP_GERCEKLESEN_EMIRLER="INT_GERCEKLESEN_EMIRLER"
_INFO_SP_IPTAL_EMIRLER="INT_IPTAL_EMIRLER"
_INFO_SP_EMIR_ALIS="INT_EMIR_EKLE_HISSE_ALIS"
_INFO_SP_EMIR_ALIS_ESUBE="INT_EMIR_EKLE_HISSE_ALIS_ESUBE"
_INFO_SP_EMIR_SATIS="INT_EMIR_EKLE_HISSE_SATIS"
_INFO_SP_EMIR_ACIGA="INT_EMIR_EKLE_HISSE_ACIGA_SATIS"
_INFO_SP_EMIR_IPTAL="INT_EMIR_IPTAL"
_INFO_SP_EMIR_DUZELT="INT_HISSE_EMIR_DUZELT"
# Portfoy: R1 dizisi doner (bos olabilir — hisse yoksa)
_INFO_SP_PORTFOY="INT_PORTFOY"
# Bakiye/hesap ozeti: R2=cari bakiye, R3=hisse detay, R5=ozet satirlari
_INFO_SP_BAKIYE="INT_OVERALL_OZET"
_INFO_SP_INTERNET_MENKULLERI="INT_INTERNET_MENKULLERI"
_INFO_SP_GUN_BILGISI="INT_GUN_BILGISI"
_INFO_SP_HALKA_ARZ_LISTE="INT_HALKA_ARZLAR_LISTE"
_INFO_SP_HALKA_ARZ_TALEPLER="INT_HALKA_ARZLAR_INTERNET_TALEPLERI_LISTESI"
_INFO_SP_HALKA_ARZ_EMIR="INT_HA_BAGLI_EMIR_GIRISI"
_INFO_SP_HALKA_ARZ_DUZELTME="INT_HA_DUZELTME_ISTEK"
_INFO_SP_HALKA_ARZ_FIYAT="INT_HA_HISSE_FIYAT"
_INFO_SP_MUSTERI_YETKILERI="INT_SC_KANAL_MUSTERI_YETKILERI_OKU"
_INFO_SP_AYARLAR="INTERNET_SUBE_AYARLAR"
_INFO_SP_SMS_SURE="SMS_YENIDEN_GONDERIM_SURE"

# Oturum yonetimi
_INFO_PING_URL="${_INFO_API_URL}/Ping/0"
_INFO_CIKIS_URL="${_INFO_API_URL}/Logout"

# Oturum suresi varsayilan (saniye) — sunucu yaniti ile guncellenecek
_INFO_OTURUM_SURESI=3600

# =======================================================
# BOLUM 2: API ISTEK AYARLARI (Site Degisince Burasi Guncellenir)
# =======================================================

# Auth tipi: Cookie-based oturum (sunucu Set-Cookie ile oturum id gonderir)
# Ping endpoint'i www-authenticate: Bearer doner ama gercek mekanizma cookie
# Not: accessToken/Bearer header kullanilmiyor, cookie yeterli

# Giris yaniti durum kodlari (statusCode alani)
_INFO_KOD_BASARILI=0
_INFO_KOD_SIFRE_DEGISTIR=5640003
_INFO_KOD_YANLIS_SIFRE=5640004
_INFO_KOD_SMS=5640005
_INFO_KOD_OTP=5640006
_INFO_KOD_HATALI_GIRIS=5640012

# SMS form: 6 haneli OTP kodu, alan adi "otpCode"
_INFO_OTP_UZUNLUK=6
_INFO_OTP_ALAN_ADI="otpCode"

# Login POST JSON alan adlari
# NOT: JS kaynak kodu kucuk harf kullaniyor (username, password).
# Sunucu buyuk harfi de kabul ediyor ama JS ile birebir eslesmesi icin
# kucuk harf kullaniyoruz.
_INFO_GIRIS_KULLANICI_ALANI="username"
_INFO_GIRIS_SIFRE_ALANI="password"

# SMS modu icin ek alan (OTP modunda bu alan OLMAMALI)
_INFO_SMS_BAYRAK_ALANI="loginBySMS"
_INFO_SMS_BAYRAK_DEGERI="1"

# Basari kontrolu
_INFO_KALIP_BASARILI='"success"\s*:\s*true'
_INFO_KALIP_HATALI='"success"\s*:\s*false'
_INFO_KALIP_OTURUM_DUSTU='401\|Unauthorized\|www-authenticate.*Bearer'

# =======================================================
# BOLUM 3: EMIR ALANLARI (ApiCall JSON Payload)
# =======================================================

# Emir parametreleri ApiCall'a JSON data olarak gonderilir.
# Alan adlari sunucu stored procedure'una bagli —
# gercek alan isimleri canli oturumda teyit edilecek.

# Bilinen emir tipleri
_INFO_EMIR_TIP_LIMIT="L"
_INFO_EMIR_TIP_PIYASA="P"

# Seans (sure) tipleri
_INFO_EMIR_SEANS_GUNLUK="GUN"
_INFO_EMIR_SEANS_KIE="KIE"

# =======================================================
# BOLUM 4: KURUM KURALLARI (Info'ya Ozgu Kisitlamalar)
# =======================================================

# Info Yatirim'e ozgu bilinen bir kisitlama su an icin yok.
# Genel BIST kurallari cekirdek tarafindan uygulanir.

# =======================================================
# BOLUM 5: HALKA ARZ (IPO) AYARLARI
# =======================================================

# Halka arz endpoint'leri yukaridaki stored procedure
# isimleriyle (INT_HALKA_ARZLAR_*) ApiCall uzerinden cagrilir.
