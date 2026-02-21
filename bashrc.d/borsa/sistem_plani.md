# Borsa Modulu - Sistem Plani

## 1. Amac

Bu belge borsa klasorunun tamamini kapsar: mevcut altyapi, robot motoru, strateji, tarama ve oturum yonetimi.
Hangi kodun nerede yazilacagini, katmanlar arasi sorumluluk sinirlarini ve algoritmik islem dongusunu tanimlar.

## 2. Katmanli Mimari

Sistem bes katmandan olusur. Her katman sadece bir altindaki katmanla konusur, katman atlamaz.

```
+-----------------------------------------------+
|  5. ROBOT MOTORU (motor.sh)                   |
|     Strateji calistirir, sinyal dinler,       |
|     emir tetikler, oturum koruma baslatir      |
+-----------------------------------------------+
|  4. STRATEJI (strateji/*.sh)                  |
|     Alis/satis karari verir, sinyal uretir    |
+-----------------------------------------------+
|  3. TARAMA (tarama/*.sh)                      |
|     Fiyat/hacim verisi toplar, filtreler      |
+-----------------------------------------------+
|  2. ADAPTOR (adaptorler/*.sh)                 |
|     Kuruma ozgu HTTP islemleri, parse, emir   |
+-----------------------------------------------+
|  1. CEKIRDEK (cekirdek.sh + kurallar/*.sh)    |
|     HTTP, oturum dizini, BIST kurallari       |
+-----------------------------------------------+
```

### 2.1 Katman Kurallari

- Strateji adaptoru bilmez, sadece "emir gonder" der.
- Tarama adaptoru bilmez, sadece "fiyat ver" der.
- Robot motoru strateji ve taramayi koordine eder, adaptor detayini bilmez.
- Oturum uzatma robot motorunun sorumlulugundadir cunku uzun sureli calisan tek katman odur.

## 3. Hedef Klasor Yapisi

```
bashrc.d/borsa/
  cekirdek.sh                # Katman 1: HTTP, oturum dizini, kurum listeleme, yazicilar
  tamamlama.sh               # Tab tamamlama
  plan.md                    # Adaptor katmani plani (mevcut, degismiyor)
  sistem_plani.md            # Bu dosya
  kurallar/
    bist.sh                  # BIST fiyat adimi, seans, tavan/taban
  adaptorler/
    ziraat.sh                # Katman 2: Ziraat islemleri
    ziraat.ayarlar.sh        # Ziraat URL ve secicileri
  tarama/
    (henuz yok)              # Katman 3: Fiyat/hacim veri toplama
  strateji/
    (henuz yok)              # Katman 4: Alis/satis karar mantigi
  robot/
    (henuz yok)              # Katman 5: Otomasyon motoru
```

## 4. Algoritmik Islem Dongusu

Robot calisirken tek bir dongu tekrar eder. Asagida bu dongudeki her adim ve hangi katmanin sorumlu oldugu gosterilir.

### 4.1 Tam Dongu

```
[BASLATMA]
  robot_baslat <kurum>
    |
    +-> Kurum gecerli mi?                          (cekirdek)
    +-> Oturum acik mi?                            (adaptor callback)
    +-> Oturum suresini oku                        (adaptor callback)
    +-> Oturum koruma dongusunu baslat              (robot motoru)
    +-> Stratejiyi yukle                            (robot motoru)

[ANA DONGU - her tur]
    |
    +-> [1] Oturum hala gecerli mi?                (adaptor callback)
    |       Gecersizse -> HATA, dongu dur
    |
    +-> [2] Tarama: Fiyat/veri topla               (tarama katmani)
    |       tarama fonksiyonu hedef sembollerin
    |       son fiyat, hacim, tavan, taban bilgisini getirir
    |       Veri kaynagi: adaptor uzerinden kurum endpointi
    |
    +-> [3] Strateji: Karar ver                    (strateji katmani)
    |       Taramadan gelen veriyi analiz et
    |       Sinyal uret: ALIS / SATIS / BEKLE
    |
    +-> [4] Sinyal varsa: Emir gonder              (cekirdek -> adaptor)
    |       borsa <kurum> emir SEMBOL yon LOT FIYAT
    |       Tum dogrulamalar (fiyat adimi, tavan/taban,
    |       bakiye/lot yeterliligi) adaptor icinde yapilir
    |
    +-> [5] Bekleme suresi                         (robot motoru)
    |       Bir sonraki tura kadar bekle
    |       (ornek: 30 saniye, 1 dakika)
    |
    +-> [1]'e don

[DURDURMA]
  robot_durdur
    |
    +-> Oturum koruma dongusunu durdur              (robot motoru)
    +-> Strateji temizlik                           (strateji katmani)
    +-> Ozet goster                                 (robot motoru)
```

### 4.2 Oturum Koruma Dongusu (Ayri Arka Plan Islemi)

Ana dongu ile paralel calisan ayri bir dongudur. Robot basladiginda aktif olur, durdugundan kapanir.

```
[OTURUM KORUMA - arka plan]
  while robot calisiyor:
    |
    +-> Son istekten bu yana gecen sure hesapla     (cekirdek)
    +-> Esik asildi mi? (sure/3 veya sure/2)       (cekirdek)
    |     Evet -> adaptor_oturum_uzat()             (adaptor callback)
    |             Basarili -> son istek zamanini guncelle
    |             Basarisiz -> log yaz, uyar
    |     Hayir -> bekle, tekrar kontrol et
    +-> sleep <aralik>
```

## 5. Oturum Yonetimi Detayi

### 5.1 Sorumluluk Dagilimi

| Is | Katman | Neden |
|----|--------|-------|
| Timeout suresini HTML/JS'den parse et | Adaptor | Her kurumun timeout verisi farkli formatta |
| Parse edilen sureyi sakla | Cekirdek | Tum kurumlar icin ortak veri yapisi |
| Son istek zamanini kaydet | Cekirdek | Her HTTP isteginden sonra otomatik |
| Kalan sureyi hesapla | Cekirdek | Basit matematik, kurumdan bagimsiz |
| Sessiz uzatma istegi at | Adaptor | Her kurumun uzatma URL'si ve kontrol mekanizmasi farkli |
| Uzatma dongusunu baslat/durdur | Robot motoru | Uzun sureli calisan tek katman |
| Emir oncesi oturum kontrol | Cekirdek | Her emir gonderiminde garantili kontrol |

### 5.2 Neden Robot Motorunda?

Manuel kullanim (borsa ziraat bakiye) icin oturum uzatma gerekmez cunku:
- Her komut bir HTTP istegi yapar, bu istek oturumu zaten uzatir.
- Kullanici dakikalarca komut girmezse oturum duser ama bu beklenen davranistir.
- Kullanici tekrar giris yapar, sorun olmaz.

Robot icin oturum uzatma gerekir cunku:
- Robot sinyal beklerken dakikalarca HTTP istegi yapmayabilir.
- Bu bekleme surecinde oturum sessizce duser.
- Robot istegi geldiginde emir gonderilemez, firsat kacirilir.
- Otomatik uzatma olmadan robot guvenilir calismaz.

Bu yuzden oturum koruma dongusu robot motorunun sorumlulugudur. Manuel kullarimda calistirilmaz.

### 5.3 Coklu Kurum Senaryosu

Uc kuruma giris yapilmis, iki robot calisiyor:

```
Terminal 1: borsa ziraat giris ...        -> oturum acildi
Terminal 1: borsa isbank giris ...        -> oturum acildi
Terminal 1: borsa garanti giris ...       -> oturum acildi

Terminal 2: robot_baslat ziraat strateji_a.sh
  +-> oturum koruma: ziraat icin arka plan dongusu baslar
  +-> ana dongu: tarama -> strateji -> emir (ziraat uzerinden)

Terminal 3: robot_baslat garanti strateji_b.sh
  +-> oturum koruma: garanti icin arka plan dongusu baslar
  +-> ana dongu: tarama -> strateji -> emir (garanti uzerinden)

# isbank oturumu acik ama robot yok -> uzatma yok -> suresi dolunca duser (sorun degil)
```

Her robot kendi kurumuna kilitlidir. Birbirlerini etkilemez.

## 6. Adaptor Callback Arayuzu

Adaptorler asagidaki fonksiyonlari tanimlar. Robot motoru ve cekirdek bu fonksiyonlari cagirir.
Mevcut olanlara (M), yeni ekleneceklere (Y) isaret konmustur.

| Fonksiyon | Durum | Aciklama |
|-----------|-------|----------|
| adaptor_giris | M | Kuruma giris yapar (SMS dahil) |
| adaptor_bakiye | M | Nakit + hisse ozeti dondurur |
| adaptor_portfoy | M | Hisse bazli detay listesi |
| adaptor_emir_gonder | M | Limit emir gonderir |
| adaptor_emirleri_listele | M | Bekleyen emirleri listeler |
| adaptor_emir_iptal | M | Emri iptal eder |
| adaptor_oturum_gecerli_mi | M | Oturum acik mi kontrol eder |
| adaptor_oturum_suresi_parse | Y | Giris yanitindan timeout suresini (saniye) parse eder |
| adaptor_oturum_uzat | Y | Sessiz GET atarak oturumu uzatir, basarili=0, basarisiz=1 |
| adaptor_hisse_bilgi_al | Y | Sembol icin son fiyat, tavan, taban, seans durumu dondurur |

## 7. Cekirdek Yeni Fonksiyonlar

| Fonksiyon | Aciklama |
|-----------|----------|
| cekirdek_kurumlari_listele | Adaptor klasorundeki kurumlari dondurur (mevcut, tamamlandi) |
| cekirdek_oturum_suresi_kaydet | Kurum icin timeout suresini kaydeder |
| cekirdek_son_istek_guncelle | Kurum icin son istek zamanini epoch olarak kaydeder |
| cekirdek_oturum_kalan | Kurum icin kalan oturum suresini saniye olarak dondurur |

## 8. Robot Motoru Fonksiyonlari

| Fonksiyon | Aciklama |
|-----------|----------|
| robot_baslat | Kurumu kilitler, oturum kontrol eder, koruma baslatir, donguyu calistirir |
| robot_durdur | Donguyu durdurur, koruma dongusunu oldurur, ozet gosterir |
| robot_oturum_koruma_baslat | Arka plan dongusunu baslatir (adaptor_oturum_uzat cagiran) |
| robot_oturum_koruma_durdur | Arka plan dongusunu PID ile oldurur |

## 9. Tarama ve Strateji Katmanlari

### 9.1 Tarama Katmani

Tarama katmani fiyat ve hacim verisini toplar. Adaptoru dogrudan cagirmaz, cekirdek uzerinden (borsa komutu ile) veya adaptore ozgu veri fonksiyonlari uzerinden calisir.

Tarama fonksiyonunun girdisi: sembol listesi.
Tarama fonksiyonunun ciktisi: her sembol icin fiyat verisi (stdout, TAB ayricli).

```
THYAO   312.50   343.75   281.25   1.34   Surekli Islem
AKBNK    42.80    47.08    38.52   0.82   Surekli Islem
```

Tarama katmani borsanin hangisi oldugunu bilmez. Robot motoru tarama fonksiyonunu cagirirken aktif kurumun adaptorunun veri fonksiyonunu arka planda baglar.

### 9.2 Strateji Katmani

Strateji bir Bash dosyasidir. Iki zorunlu fonksiyon tanimlar:

```bash
strateji_baslat()      # Baslangic ayarlari (opsiyonel)
strateji_degerlendir() # Her turda cagrilir, sinyal dondurur
                       # stdout'a: ALIS|SATIS|BEKLE SEMBOL LOT FIYAT
```

Strateji dosyasi hicbir kurum, adaptor veya HTTP detayi bilmez. Sadece veri alir, karar verir.

## 10. Yol Haritasi

### 10.1 Asama 1 - Oturum Altyapisi

Cekirdek'e oturum suresi ve son istek zamani veri yapilari eklenir.
Ziraat adaptorune sessionTimeOutModel parse fonksiyonu eklenir.
Ziraat adaptorune sessiz oturum uzatma fonksiyonu eklenir.

### 10.2 Asama 2 - Veri Cekme

Ziraat adaptorune adaptor_hisse_bilgi_al fonksiyonu eklenir.
Emir gonderme oncesi tavan/taban ve bakiye kontrolleri eklenir.
borsa ziraat fiyat SEMBOL komutu eklenir.

### 10.3 Asama 3 - Robot Motoru

robot/ klasoru olusturulur.
robot_baslat, robot_durdur, oturum koruma fonksiyonlari yazilir.
Ana dongu iskeleti kurulur (tarama -> strateji -> emir).

### 10.4 Asama 4 - Tarama Katmani

tarama/ klasoru olusturulur.
Temel tarama fonksiyonu yazilir (sembol listesi -> fiyat tablosu).
Robot motoru ile entegre edilir.

### 10.5 Asama 5 - Strateji Katmani

strateji/ klasoru olusturulur.
Strateji arayuzu (strateji_baslat, strateji_degerlendir) belirlenir.
Ornek strateji yazilir (test amacli basit kural).
Robot motoru ile entegre edilir.

### 10.6 Asama 6 - Ust Seviye Komutlar

Robottan bagimsiz, kurumsuz ust seviye fonksiyonlar eklenir.
emir_gonder, bakiye_sorgula gibi fonksiyonlar robot_baslat ile kilitli kurumu kullanir.
Bu fonksiyonlar strateji katmanindan cagrilir.
