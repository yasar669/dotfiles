#!/bin/bash
# shellcheck shell=bash

# Osmanli Yatirim Menkul Degerler A.S. Adaptoru - Ayarlar Dosyasi
# Bu dosya dogrudan calistirilmaz, osmanli.sh tarafindan yuklenir.
# Degisiklik gerektiren durum: Osmanli E-Sube sitesi guncellenmis olabilir.
# Bu dosyayi duzenlemek icin osmanli.sh'a dokunmaya gerek yok.

# =======================================================
# BOLUM 1: SUNUCU VE OTURUM AYARLARI
# =======================================================

# E-Sube: Vue.js SPA, REST JSON API
_OSMANLI_BASE_URL="https://esube.osmanlimenkul.com.tr"
_OSMANLI_API_URL="${_OSMANLI_BASE_URL}/api"

# Giris endpoint'leri (3 adimli akis)
_OSMANLI_LOGIN_STEP1_URL="${_OSMANLI_API_URL}/User/Login/Step1"
_OSMANLI_LOGIN_STEP2_URL="${_OSMANLI_API_URL}/User/Login/Step2"
_OSMANLI_LOGIN_CHECK_PUSH_URL="${_OSMANLI_API_URL}/User/Login/CheckPushStatus"
_OSMANLI_CAPTCHA_URL="${_OSMANLI_API_URL}/User/Captcha"

# Portfoy & bakiye
_OSMANLI_PORTFOY_URL="${_OSMANLI_API_URL}/Stock/Custom/SharesPortfolioWithInstrumentPriceList"
_OSMANLI_LIMIT_URL="${_OSMANLI_API_URL}/Stock/Share/LimitCalculate"

# Emir islemleri
_OSMANLI_EMIR_ALIS_URL="${_OSMANLI_API_URL}/Stock/Share/Buy"
_OSMANLI_EMIR_SATIS_URL="${_OSMANLI_API_URL}/Stock/Share/Sell"
_OSMANLI_EMIR_ACIGA_SATIS_URL="${_OSMANLI_API_URL}/Stock/Share/OpenSell"
_OSMANLI_EMIR_IPTAL_URL="${_OSMANLI_API_URL}/Stock/Share/Cancel"
_OSMANLI_EMIR_GUNCELLE_URL="${_OSMANLI_API_URL}/Stock/Share/Update"

# Emir listeleme (hepsi POST)
_OSMANLI_EMIR_BEKLEYEN_URL="${_OSMANLI_API_URL}/Stock/Custom/SharePendingOrdersWithStockList"
_OSMANLI_EMIR_ISLENEN_URL="${_OSMANLI_API_URL}/Stock/Share/ProcessedOrders"
_OSMANLI_EMIR_IPTAL_EDILEN_URL="${_OSMANLI_API_URL}/Stock/Share/CancelledOrders"

# Hisse listesi (MenkulNo <-> sembol eslestirmesi icin)
_OSMANLI_HISSE_LISTESI_URL="${_OSMANLI_API_URL}/Stock/StockList"
_OSMANLI_HISSE_ONBELLEK_SURESI=3600

# Halka arz
_OSMANLI_HALKA_ARZ_LISTE_URL="${_OSMANLI_API_URL}/PublicOffers/GetList"
_OSMANLI_HALKA_ARZ_TALEPLER_URL="${_OSMANLI_API_URL}/PublicOffers/GetRequestList"
_OSMANLI_HALKA_ARZ_IPTAL_URL="${_OSMANLI_API_URL}/PublicOffers/Cancel"

# Oturum
_OSMANLI_OTURUM_SURESI=3600
_OSMANLI_CIKIS_URL="${_OSMANLI_API_URL}/User/Logout"

# Veri dagitim (canli fiyat icin ayri sunucu)
_OSMANLI_VERIDAGITIM_API_URL="https://veridagitim.osmanlimenkul.com.tr/api"

# =======================================================
# BOLUM 2: API ISTEK AYARLARI (Site Degisince Burasi Guncellenir)
# =======================================================

# Her istekte gonderilmesi gereken ozel header
_OSMANLI_HEADER_KAYNAK="From-Source: E-Sube"
# Token header adi (NOT: "Authorization: Bearer" degil, "Token: <jwt>" kullanilir)
_OSMANLI_HEADER_TOKEN_ADI="Token"

# Giris yaniti durum kodlari (statuscode alani)
# Step1 basarili degildir, 2FA turunu belirten kod doner
_OSMANLI_KOD_SMS="5640005"
_OSMANLI_KOD_OTP="5640006"
_OSMANLI_KOD_PUSH="5640014"
_OSMANLI_KOD_YENI_KULLANICI="5640003"
_OSMANLI_KOD_YANLIS_SIFRE="5640004"
_OSMANLI_KOD_COK_SIK_ISTEK="400"
_OSMANLI_KOD_HESAP_PASIF="-22"

# SMS cooldown suresi (saniye) — sunucu 180 sn bekleme uygular
_OSMANLI_SMS_COOLDOWN_SURESI=180

# Giris yaniti basari kontrolu
_OSMANLI_KALIP_BASARILI='"success"\s*:\s*true'
_OSMANLI_KALIP_HATALI='"success"\s*:\s*false'

# Oturum gecerlilik kontrolu: 401 HTTP kodu = oturum dustu
_OSMANLI_KALIP_OTURUM_DUSTU='401\|Unauthorized\|"statusCode":401'

# =======================================================
# BOLUM 3: EMIR ALANLARI (Buy/Sell JSON Payload)
# =======================================================

# EmirTipi (orderType) degerleri
_OSMANLI_EMIR_TIP_LIMIT="L"
_OSMANLI_EMIR_TIP_PIYASA="P"
# Kapanis fiyatli emir de var ama nadir: "K"

# Seans (surecilik) degerleri
_OSMANLI_EMIR_SEANS_GUNLUK="3"
_OSMANLI_EMIR_SEANS_KIE="K"

# JSON payload alan adlari (Buy/Sell endpoint'ine gonderilen)
# EmirTipi, Fiyat, MenkulNo, Miktar, Seans, GeriBildirimKanali, AltPazarRBF

# =======================================================
# BOLUM 4: KURUM KURALLARI (Osmanli'ya Ozgu Kisitlamalar)
# =======================================================

# Osmanli Menkul'e ozgu bilinen bir kisitlama su an icin yok.
# Genel BIST kurallari cekirdek tarafindan uygulanir.

# =======================================================
# BOLUM 5: HALKA ARZ (IPO) AYARLARI
# =======================================================

# Halka arz JSON alan adlari sunucu yanitindan cikarilir.
# Su an icin detay endpoint'leri teyit bekliyor,
# ancak temel liste ve talep endpoint'leri yukarda tanimli.
