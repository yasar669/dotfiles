#!/bin/bash
# shellcheck shell=bash

# Ziraat Yatirim Adaptoru - Ayarlar Dosyasi
# Bu dosya dogrudan calistirilmaz, ziraat.sh tarafindan yuklenir.
# Degisiklik gerektiren durum: Ziraat web sitesi guncellenmis olabilir.
# Bu dosyayi duzenlemek icin ziraat.sh'a dokunmaya gerek yok.

# =======================================================
# BOLUM 1: SUNUCU VE OTURUM AYARLARI
# =======================================================

_ZIRAAT_BASE_URL="https://esube1.ziraatyatirim.com.tr"
_ZIRAAT_LOGIN_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/Account/Login?ReturnUrl=%2fsanalsube%2f"
_ZIRAAT_ANA_SAYFA_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/Home/Index"
_ZIRAAT_PORTFOY_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/Portfolio"
_ZIRAAT_EMIR_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/Equity/AddOrder"
_ZIRAAT_EMIR_LISTE_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/Equity/ListTransactionOperation"
_ZIRAAT_EMIR_IPTAL_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/Equity/JsonDeleteOrder"
_ZIRAAT_KIYMET_LISTESI_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/Equity/ListCharacteristic"

_ZIRAAT_FALLBACK_HOSTNAME="ESUBE05"

# Oturum yonetimi artik cekirdek.sh tarafindan saglanir.
# Dizin konvansiyonu: /tmp/borsa/ziraat/<musteri_no>/
# Dosya isimleri: _CEKIRDEK_DOSYA_* sabitleri (cekirdek.sh'da tanimli)



# =======================================================
# BOLUM 2: HTML SECICILER (Site Degisince Burasi Guncellenir)
# =======================================================

# Giris sayfasi gizli alanlari
_ZIRAAT_SEL_HOSTNAME='id="HostName" value="\K[^"]+'
_ZIRAAT_SEL_CSRF_TOKEN='name="__RequestVerificationToken" type="hidden" value="\K[^"]+'

# Giris sonucu kontrol kaliplari
# NOT: Bu desenler gercek basarili giris yaniti analiz edilerek belirlenmistir.
_ZIRAAT_KALIP_HATALI_GIRIS='Hatali giris\|Lutfen bilgilerinizi kontrol'
_ZIRAAT_KALIP_SMS='SMSPassword\|SmsPassword\|Yeniden sms\|SMS Sifresi\|Dogrulama Kodu'
_ZIRAAT_KALIP_BASARILI_HTML='PortfoyWidget\|sessionTimeOutModel\|LogOutURL'
_ZIRAAT_KALIP_BASARILI_JSON='"isSuccess":true'

# Session GUID
_ZIRAAT_SEL_SESSION_GUID="var sessionGuid = '\K[^']+"

# Portfoy sayfasi HTML ID'leri
_ZIRAAT_ID_NAKIT="cash-total-amount"
_ZIRAAT_ID_HISSE="eq-total-amount"
# NOT: Sayfada "Toplam Varlıklar" yazar (ı=U+0131, Turkce dotless-i).
# ASCII eslemesi icin son harften once kesiyoruz.
_ZIRAAT_METIN_TOPLAM="Toplam Varl"

# Portfoy detay: Hisse tablosu HTML secicileri
# Her hisse bir <tr id="wdg_portfolio_HESAP_ID"> icerisinde.
# Alt alanlar: balance (lot), last (son fiyat), marketvalue, cost, profit, profit_change
_ZIRAAT_SEL_PORTFOY_SATIR='id="wdg_portfolio_[^"]*-FIN"'
_ZIRAAT_SEL_PORTFOY_HESAP_ID='id="wdg_portfolio_\K[0-9][^"]*-FIN'
# Hisse toplam degerleri (ozet satiri ustu)
_ZIRAAT_ID_HISSE_MALIYET="eq-total-cost"
_ZIRAAT_ID_HISSE_KAR="eq-total-profit"

# =======================================================
# BOLUM 3: EMIR ALANLARI (AddOrder Formu)
# =======================================================

# NOT: _ZIRAAT_EMIR_URL zaten BOLUM 1'de tanimli. Tekrar tanimlamayiniz.

# Form alan sabitleri - Site degistirirse bunlar guncellenir
# DebitCreditH: Alis=A, Satis=S
_ZIRAAT_EMIR_ALIS="A"
_ZIRAAT_EMIR_SATIS="S"

# TimeInForce: 0=Gunluk, 3=Kalani Iptal Et (KIE)
_ZIRAAT_EMIR_GUNLUK="0"
_ZIRAAT_EMIR_KIE="3"

# SpecialOrderType: Normal limit emir
_ZIRAAT_EMIR_NORMAL="Normal"

# AmountType (EquityOrderType): Emir turu
# Ziraat AJAX endpoint'inden (JsonGetEQEquityOrderTypeDropbox) alinan degerler:
#   LOT = Limit Fiyatli   (TimeInForce: 0=Gunluk, 3=KIE)
#   MKT = Piyasa           (TimeInForce: 3=KIE tek secenek)
#   MTL = Piyasadan Limite (TimeInForce: 0=Gunluk, 3=KIE)
#   IO  = Denge Emri       (TimeInForce: 3=KIE tek secenek)
#   MPM = Orta Nokta Piyasa (TimeInForce: 0=Gunluk tek secenek)
#   MPL = Orta Nokta Limit  (TimeInForce: 0=Gunluk tek secenek)
_ZIRAAT_EMIR_BIRIM="LOT"
_ZIRAAT_EMIR_BIRIM_PIYASA="MKT"

# WizardPageName: Emir formu uc adimlidir.
# Adim 1: GET sayfasindan WizardPageName=LayoutWizardSecondPage alinir.
# Adim 2: NextButton POST ile onay ozet sayfasi (LayoutWizardResultPage) gelir.
# Adim 3: FinishButton POST ile emir tamamlanir.
_ZIRAAT_EMIR_WIZARD_ADIM1="LayoutWizardFirstPage"
_ZIRAAT_EMIR_WIZARD_ADIM2="LayoutWizardSecondPage"

# NotificationType: Emir gerceklestiginde bildirim turu.
# Form HTML'den kesinlesen degerler (id="eqNotificationType" select, 2 option):
#   N   = Mobil Bildirim - Zborsa uygulamasi push bildirimi (cep telefonu)
#   E   = E-Posta
#   N,E = Ikisi birden (varsayilan; form bu degerle geliyor)
#   " " = Bildirim yok (bos deger)
# NOT: SMS secenegi YOKTUR. Ziraat bu formda SMS desteklemiyor.
_ZIRAAT_BILDIRIM_MOBIL="N"
_ZIRAAT_BILDIRIM_EPOSTA="E"
_ZIRAAT_BILDIRIM_HEPSI="N,E"
_ZIRAAT_BILDIRIM_YOK=" "
# Emir gonderiminde kullanilacak varsayilan bildirim turu:
_ZIRAAT_BILDIRIM_VARSAYILAN="$_ZIRAAT_BILDIRIM_HEPSI"

# =======================================================
# BOLUM 4: KURUM KURALLARI (Ziraat'e Ozgu Kisitlamalar)
# =======================================================
#
# Ziraat Yatirim seans disi (17:30-10:45) saatlerinde
# 1000 TL altindaki emirleri kabul etmiyor.
# Bu BIST kurali degil, Ziraat'in kendi kisitlamasidir.
#
# Uyari metni: "17:30-10:45 saatleri arasinda 1000 TL
# altinda emir girisi yapilamamaktadir."
_ZIRAAT_SEANS_DISI_BASLANGIC="17:30"   # Bu saatten sonra kisitlama baslar
_ZIRAAT_SEANS_DISI_BITIS="10:45"       # Bu saate kadar kisitlama devam eder
_ZIRAAT_SEANS_DISI_MIN_TUTAR=1000       # Minimum emir tutari (TL)

# Hesap ID secici: select ve option ayni satirda, option icindeki value okunur.
# HTML: <select id="ddlActiveAccount"...><option selected="selected" value="0000-00X8CB-ACC">
_ZIRAAT_SEL_HESAP_ID='id="ddlActiveAccount"[^>]*><option[^>]*value="\K[^"]+'

# Emir sonucu kontrol kaliplari
# NOT: Ziraat basarili emirde redirect yapmaz, ayni URL'de sonuc sayfasi render eder.
# "kaydedilmiştir" metni ve referans numarasi basari gostergesidir.
_ZIRAAT_KALIP_EMIR_BASARILI='kaydedilmi\|iletilmi\|Emiriniz.*kayded'
_ZIRAAT_KALIP_EMIR_HATALI='isSuccess.*false\|Hata\|gecersiz\|insufficient\|Yetersiz'
_ZIRAAT_SEL_REFERANS_NO='referans\u0131yla\|referansiyla\|referans[^<]*\K[A-Z0-9]+'

# =======================================================
# BOLUM 5: HALKA ARZ (IPO) AYARLARI
# =======================================================

# IPO Sayfa URL'leri
_ZIRAAT_IPO_LISTE_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/IPO/ListIPO"
_ZIRAAT_IPO_DETAY_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/IPO/DetailIPO"
_ZIRAAT_IPO_ISLEMLER_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/IPO/IPOTransactionsList"

# IPO AJAX Endpoint'leri
_ZIRAAT_IPO_DETAY_JSON_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/Ipo/JsonListIpoDetail"
_ZIRAAT_IPO_IPTAL_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/Ipo/JsonCancelIpoDemand"
_ZIRAAT_IPO_GUNCELLE_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/Ipo/JsonEditIpoDemand"
_ZIRAAT_IPO_GORUNTULE_URL="${_ZIRAAT_BASE_URL}/sanalsube/tr/Ipo/JsonDisplayOrEditIpoDemandEdit"

# IPO Liste sayfasi HTML secicileri
# form-detail-ipo: Talep girisi formu. Hidden alanlara IpoId, PaymentTypeId vb doldurup POST edilir.
_ZIRAAT_IPO_SEL_FORM_ID="form-detail-ipo"

# Aktif halka arz satirlari: btnsubmit data attribute'lerinden cikarilir.
# data-ipoid: Halka arzin benzersiz ID'si
# data-name: Halka arzin adi
# data-fininstid: Mali kurum ID'si (taksit wrapper satirini bulmak icin)
_ZIRAAT_IPO_SEL_IPOID='data-ipoid="\K[^"]+'
_ZIRAAT_IPO_SEL_ADI='data-name="\K[^"]+'
_ZIRAAT_IPO_SEL_FININSTID='data-fininstid="\K[^"]+'

# IPO limit bilgisi
# HTML ornegi: <span class="IpoLimitFont">Halka Arz ... Limitiniz: <b>877,77</b> TL</span>
# Oncelik 1: IpoLimitFont class'i icindeki <b> etiketi
_ZIRAAT_IPO_SEL_LIMIT_1='IpoLimitFont[^<]*>[^<]*<b[^>]*>\K[0-9.,]+'
# Oncelik 2: "Limit" kelimesinden sonraki <b> etiketi
_ZIRAAT_IPO_SEL_LIMIT_2='[Ll]imit[^<]*<b[^>]*>\K[0-9.,]+'

# IPO InvestorTypeId: Bireysel yatirimci varsayilani
_ZIRAAT_IPO_YATIRIMCI_TIPI="0000-000002-INT"

# IPO islem listesi tablo satir secicileri
# Tablo sutunlari: Halka Arz, Tarih, Sira No, Talep Lot/Nominal, Fiyat, Tutar, Durum
_ZIRAAT_IPO_SEL_TALEP_SATIR='<tr[^>]*id="[^"]*"[^>]*>'

# IPO talep tipleri
# M = Miktar bazli (lot), T = Tutar bazli (TL)
_ZIRAAT_IPO_TALEP_MIKTAR="M"
_ZIRAAT_IPO_TALEP_TUTAR="T"
