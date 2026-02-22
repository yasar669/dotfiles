# Borsa Modulu - Sistem Plani

## 1. Amac

Bu belge borsa klasorunun tamamini kapsar: mevcut altyapi, robot motoru, strateji, tarama ve oturum yonetimi.
Hangi kodun nerede yazilacagini, katmanlar arasi sorumluluk sinirlarini ve algoritmik islem dongusunu tanimlar.

## 2. Katmanli Mimari

Sistem bes katmandan olusur. Her katman sadece bir altindaki katmanla konusur, katman atlamaz.

```
+-----------------------------------------------+    +---------------------------+
|  5. ROBOT MOTORU (robot/motor.sh)             |    |  SUPABASE VERITABANI      |
|     Strateji calistirir, sinyal dinler,       |    |  (veritabani/supabase.sh) |
|     emir tetikler, oturum koruma baslatir      |    |                           |
+-----------------------------------------------+    |  Kalici kayit servisi:    |
|  4. STRATEJI (strateji/*.sh)                  |    |  - Emir gecmisi           |
|     Alis/satis karari verir, sinyal uretir    |    |  - Bakiye anliklari       |
+-----------------------------------------------+    |  - Pozisyon izleme        |
|  3. TARAMA + VERI KAYNAGI (tarama/*.sh)       |    |  - K/Z takibi             |
|     Merkezi veri kaynagi yonetimi,            |    |  - Halka arz islemleri    |
|     onbellek, failover, fiyat/hacim toplama   |    |  - Robot log              |
+-----------------------------------------------+    |                           |
|  2. ADAPTOR (adaptorler/*.sh)                 |<-->|  curl ile REST API        |
|     Kuruma ozgu HTTP islemleri, parse, emir   |    |  (PostgREST)              |
+-----------------------------------------------+    |                           |
|  1. CEKIRDEK (cekirdek.sh + kurallar/*.sh)    |<-->|  vt_* fonksiyonlari       |
|     HTTP, oturum dizini, BIST kurallari       |    |  cekirdekten cagrilir     |
+-----------------------------------------------+    +---------------------------+
```

Veritabani bir katman degildir. Dikey bir servis olarak tum katmanlardan erisilir.
Katman sirasi degismez — veritabani katmanlarin yaninda durur, aralarinda degil.

### 2.1 Katman Kurallari

- Strateji adaptoru bilmez, sadece "emir gonder" der.
- Tarama adaptoru bilmez, sadece "fiyat ver" der. Veriyi merkezi kaynaktan alir.
- Robot motoru strateji ve taramayi koordine eder, adaptor detayini bilmez.
- Oturum uzatma robot motorunun sorumlulugundadir cunku uzun sureli calisan tek katman odur.
- Veri kaynagi tum robotlar tarafindan ortaklasa kullanilir. Tek oturumdan cekilir, onbelleklenir.
- Emir kanali her robota ozeldir. Her robot kendi kurum+hesabindan emir gonderir.
- Veritabani tum katmanlardan erisilebilen dikey bir servistir. Katman atlamasi sayilmaz.
- Her emir, bakiye degisimi ve pozisyon hareketi veritabanina ZORUNLU olarak kaydedilir.
- Veritabani yazimi basarisiz olsa bile islem (emir gonderme vb) engellenmez, log yazilir.

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
    (henuz yok)              # Katman 3: Veri kaynagi, onbellek, fiyat/hacim toplama
  strateji/
    (henuz yok)              # Katman 4: Alis/satis karar mantigi
  robot/
    (henuz yok)              # Katman 5: Otomasyon motoru
  veritabani/
    supabase.sh              # Veritabani servisi: baglanti, CRUD, sema
    supabase.ayarlar.sh      # Proje URL, API anahtari, tablo isimleri
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

### 5.3 Coklu Kurum ve Coklu Hesap Senaryosu

Sistem ayni anda birden fazla kurumda birden fazla hesabi destekler.
Her hesap bagimsiz bir oturumdur. Oturum dizini konvansiyonu:

```
/tmp/borsa/<kurum>/<hesap_no>/cookies.txt
```

Ornek: 2 Ziraat, 3 Garanti, 5 Isbank hesabi acilmis durumda:

```
/tmp/borsa/ziraat/111111/cookies.txt     # Ziraat hesap 1
/tmp/borsa/ziraat/222222/cookies.txt     # Ziraat hesap 2
/tmp/borsa/garanti/333333/cookies.txt    # Garanti hesap 1
/tmp/borsa/garanti/444444/cookies.txt    # Garanti hesap 2
/tmp/borsa/garanti/555555/cookies.txt    # Garanti hesap 3
/tmp/borsa/isbank/666666/cookies.txt     # Isbank hesap 1
/tmp/borsa/isbank/677777/cookies.txt     # Isbank hesap 2
/tmp/borsa/isbank/688888/cookies.txt     # Isbank hesap 3
/tmp/borsa/isbank/699999/cookies.txt     # Isbank hesap 4
/tmp/borsa/isbank/600000/cookies.txt     # Isbank hesap 5
```

#### 5.3.1 Giris Asamasi (Manuel, Terminal 1)

Tum hesaplara tek terminalden sirayla giris yapilir:

```
Terminal 1:
  borsa ziraat giris 111111 parola1       -> oturum acildi
  borsa ziraat giris 222222 parola2       -> oturum acildi
  borsa garanti giris 333333 parola3      -> oturum acildi
  borsa garanti giris 444444 parola4      -> oturum acildi
  borsa garanti giris 555555 parola5      -> oturum acildi
  borsa isbank giris 666666 parola6       -> oturum acildi
  ...
```

Her giris kendi cookie dosyasini olusturur. Birbirini ezmez cunku dizin yolu kurum+hesap ikilisine ozeldir.

#### 5.3.2 Robot Baslatma

Robotlar arka plan prosesi olarak calisir. Hangi terminalden baslatilirsa baslatilsin
terminalden bagimsizdirlar. Terminal kapatilsa bile robot calismaya devam eder.
Herhangi bir terminalden durdurulabilir.

Her robot tam olarak bir kurum+hesap ikilisine kilitlenir:

```
Terminal 1:
  robot_baslat ziraat 111111 strateji_a.sh   -> PID 4501, arka planda
  robot_baslat ziraat 222222 strateji_b.sh   -> PID 4502, arka planda

Terminal 2:
  robot_baslat garanti 333333 strateji_c.sh  -> PID 4503, arka planda
  robot_baslat garanti 444444 strateji_d.sh  -> PID 4504, arka planda
  robot_baslat garanti 555555 strateji_e.sh  -> PID 4505, arka planda

# Terminal 1 ve 2 kapatilsa bile 5 robot calismaya devam eder
```

Her robot basladiginda PID'si oturum dizinine kaydedilir:

```
/tmp/borsa/ziraat/111111/robot.pid      # icerik: 4501
/tmp/borsa/ziraat/222222/robot.pid      # icerik: 4502
/tmp/borsa/garanti/333333/robot.pid     # icerik: 4503
/tmp/borsa/garanti/444444/robot.pid     # icerik: 4504
/tmp/borsa/garanti/555555/robot.pid     # icerik: 4505
```

#### 5.3.3 Robot Yonetimi (Herhangi Bir Terminalden)

Robotlar PID dosyasi uzerinden yonetilir. Baslatildiklari terminale bagimli degildir.
Herhangi bir terminal acilir ve su komutlar calistirilir:

```
Terminal 6 (veya herhangi biri):
  robot_listele
    PID    KURUM     HESAP    STRATEJI         DURUM
    4501   ziraat    111111   strateji_a.sh    CALISIYOR
    4502   ziraat    222222   strateji_b.sh    CALISIYOR
    4503   garanti   333333   strateji_c.sh    CALISIYOR
    4504   garanti   444444   strateji_d.sh    CALISIYOR
    4505   garanti   555555   strateji_e.sh    CALISIYOR

  robot_durdur ziraat 111111
    -> PID 4501 durduruldu, /tmp/borsa/ziraat/111111/robot.pid silindi

  robot_durdur garanti 555555
    -> PID 4505 durduruldu, /tmp/borsa/garanti/555555/robot.pid silindi

  robot_listele
    PID    KURUM     HESAP    STRATEJI         DURUM
    4502   ziraat    222222   strateji_b.sh    CALISIYOR
    4503   garanti   333333   strateji_c.sh    CALISIYOR
    4504   garanti   444444   strateji_d.sh    CALISIYOR
```

Bu calisiyor cunku:
- Robotlar nohup ile baslatilir, terminal kapatilinca olmezler.
- PID dosyasi dosya sisteminde durur, herhangi bir proses okuyabilir.
- robot_listele tum kurum/hesap dizinlerini tarar, robot.pid dosyasi olan yerleri listeler.
- robot_durdur PID dosyasini okuyup kill ile prosesi sonlandirir.

#### 5.3.4 Carpisma Olmaz

Her robot kendi proses-lokal degiskenlerini tasir:

```
PID 4501 icinde:
  _ROBOT_KURUM="ziraat"
  _ROBOT_HESAP="111111"

PID 4502 icinde:
  _ROBOT_KURUM="ziraat"
  _ROBOT_HESAP="222222"
```

Ayni kurumdaki iki farkli hesap bile birbirini etkilemez cunku:
- Cookie dosyalari farkli dizinlerdedir.
- Oturum koruma donguleri farkli PID'lerle calisir.
- Degiskenler farkli Bash proseslerinde yasarlar.
- Her proses kendi log dosyasina yazar.

#### 5.3.5 Robot Calismazsa Ne Olur

Robotu olmayan hesaplarin oturumu uzatilmaz. Bu beklenen davranistir:

```
# isbank/666666-600000 icin robot baslatilmadi
# -> oturum koruma dongusu yok
# -> sunucu timeout suresinden sonra oturumu kapatir
# -> cookie dosyasi kalir ama gecersizdir
# -> tekrar kullanilmak istenirse: borsa isbank giris 666666 parola
```

#### 5.3.6 Ozet Tablo

| Kurum | Hesap | Robot PID | Oturum Koruma | Durum |
|-------|-------|-----------|---------------|-------|
| ziraat | 111111 | 4501 | Aktif | Oturum canli, emir gonderilebilir |
| ziraat | 222222 | 4502 | Aktif | Oturum canli, emir gonderilebilir |
| garanti | 333333 | 4503 | Aktif | Oturum canli, emir gonderilebilir |
| garanti | 444444 | 4504 | Aktif | Oturum canli, emir gonderilebilir |
| garanti | 555555 | 4505 | Aktif | Oturum canli, emir gonderilebilir |
| isbank | 666666-600000 | yok | yok | Oturum suresi dolunca duser |

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

## 9. Veri Kaynagi Mimarisi

### 9.1 Temel Prensip: Veri ve Emir Ayrilir

BIST tek bir borsadir. THYAO'nun fiyati ister Ziraat'ten iste Garanti'den bak aynidir.
Bu yuzden her robotun kendi kurumundan ayri ayri veri cekmesi israftir.
Ayni zamanda tek bir kuruma bagimli kalmak da kirilgandir.

Cozum: Veri kaynagi ve emir kanali tamamen ayri kavramlardir.

| Kavram | Sorumluluk | Kaynak |
|--------|-----------|--------|
| Veri kaynagi | Fiyat, hacim, tavan, taban | Merkezi, paylasimli, tek kaynak |
| Emir kanali | Alis/satis emri gonder | Her robot kendi kurum+hesabindan |

```
                     [MERKEZI VERI KAYNAGI]
                     Tek oturum uzerinden cekilir
                     THYAO: 312.50, AKBNK: 42.80
                              |
              +---------------+---------------+
              |               |               |
         Robot 1          Robot 2          Robot 3
         ziraat/111       ziraat/222       garanti/333
         strateji_a       strateji_b       strateji_c
         VERI <- merkez   VERI <- merkez   VERI <- merkez
         EMIR -> ziraat   EMIR -> ziraat   EMIR -> garanti
```

### 9.2 Veri Kaynagi Secimi

Veri kaynagi acik oturumlardan biri secilerek belirlenir. Hangi kurum oldugu onemli degildir
cunku BIST verisi tum kurumlarda aynidir.

#### 9.2.1 Otomatik Secim Algoritmasi

Sistem baslatildiginda acik oturumlari tarar ve birini veri kaynagi olarak atar:

```
[VERI KAYNAGI SECIMI]
  1. /tmp/borsa/ altindaki tum kurum/hesap dizinlerini tara
  2. Her birinde cookies.txt var mi kontrol et
  3. Cookie olan hesaplarda adaptor_oturum_gecerli_mi() cagir
  4. Gecerli oturumlardan ilk bulunani veri kaynagi yap
  5. Veri kaynagi bilgisini kaydet:
       _VERI_KAYNAGI_KURUM="ziraat"
       _VERI_KAYNAGI_HESAP="111111"
```

Ornek:

```
Acik oturumlar:
  ziraat/111111   -> gecerli  -> VERI KAYNAGI SECILDI
  ziraat/222222   -> gecerli  -> yedek 1
  garanti/333333  -> gecerli  -> yedek 2
  garanti/444444  -> suresi dolmus -> atla
  isbank/666666   -> suresi dolmus -> atla

Sonuc: Veri kaynagi = ziraat/111111
Yedekler: [ziraat/222222, garanti/333333]
```

#### 9.2.2 Otomatik Yedekleme (Failover)

Veri kaynaginin oturumu duserse sistem otomatik olarak yedek kaynaga gecer:

```
[FAILOVER AKISI]
  veri_kaynagi_fiyat_al("THYAO")
    |
    +-> Aktif kaynak (ziraat/111111) uzerinden adaptor_hisse_bilgi_al
    |     Basarili -> veri dondur
    |     Basarisiz (oturum dusmus) ->
    |       +-> Log: "UYARI: Veri kaynagi ziraat/111111 yanitlamiyor"
    |       +-> Yedek listesinden siradakini dene: ziraat/222222
    |       +-> adaptor_oturum_gecerli_mi kontrol
    |       |     Gecerli -> yeni veri kaynagi olarak ata
    |       |     Gecersiz -> sonraki yedegi dene: garanti/333333
    |       +-> Hicbir yedek calismiyorsa:
    |             Log: "KRITIK: Hicbir veri kaynagi erisilebilir degil"
    |             Tum robotlara bildir: veri yok, bekleme moduna gec
```

#### 9.2.3 Veri Kaynagi Oturum Korumasi

Veri kaynagi olarak kullanilan oturumun dusurulmemesi kritiktir.
Bu oturum icin de oturum koruma dongusu calistirilir:

```
[VERI KAYNAGI KORUMA]
  robot_baslat ile birlikte degil, veri_kaynagi_baslat ile baslar.
  Ayri bir arka plan prosesidir.

  /tmp/borsa/ziraat/111111/veri_kaynagi.pid    # koruma dongusu PID'si

  while veri kaynagi aktif:
    +-> adaptor_oturum_uzat("ziraat", "111111")
    +-> sleep <aralik>
```

Bu demektir ki veri kaynagi olan hesabin robotu olmasa bile oturumu korunur.
(5.3.5'teki "robot yoksa oturum duser" kurali veri kaynagi icin gecerli degildir.)

#### 9.2.4 Manuel Veri Kaynagi Secimi

Kullanici isterse veri kaynagini manuel belirleyebilir:

```
veri_kaynagi_ayarla ziraat 111111     # bu hesap veri kaynagi olsun
veri_kaynagi_goster                   # aktif veri kaynagini goster
```

Manuel secim otomatik secimin onune gecer.

### 9.3 Veri Onbellegi (Cache)

Ayni anda 5 robot calisiyor ve hepsi THYAO fiyatini soruyor.
Her sorguda sunucuya HTTP istegi atmak gereksizdir cunku fiyat saniyeler icinde degismez.

Cozum: Veri onbellegi. Tarama katmani son cekilen veriyi kisa sureligine saklar.

```
[ONBELLEK AKISI]
  Robot 1: veri_kaynagi_fiyat_al("THYAO")
    +-> Onbellekte var mi? Evet, 3 saniye once cekilmis
    |     -> onbellekten dondur (HTTP istegi yapilmaz)

  Robot 3: veri_kaynagi_fiyat_al("THYAO")
    +-> Onbellekte var mi? Evet, 4 saniye once cekilmis
    |     -> onbellekten dondur

  Robot 1: veri_kaynagi_fiyat_al("THYAO")  (12 saniye sonra)
    +-> Onbellekte var mi? Evet ama 12 saniye gecmis (esik: 10 sn)
    |     -> sunucudan taze cek, onbellegi guncelle
```

Onbellek dosya tabanlidir (RAM'de degil) cunku robotlar ayri proseslerdir:

```
/tmp/borsa/_veri_onbellek/THYAO.dat
  icerik: 1740100200|312.50|343.75|281.25|1.34|Surekli Islem
  format: epoch|son_fiyat|tavan|taban|degisim|seans_durumu
```

Onbellek suresi ayarlanabilirdir:

```
_VERI_ONBELLEK_SURESI=10     # saniye (varsayilan)
```

### 9.4 Veri Kaynagi ile Adaptor Arasindaki Iliski

Veri kaynaginin bir adaptoru vardir. Tarama katmani bu adaptoru soyutlar.
Ne robot ne strateji hangi adaptorun kullanildigini bilir.

```
Robot: "THYAO fiyatini ver"
  |
  +-> Tarama katmani: veri_kaynagi_fiyat_al("THYAO")
        |
        +-> Onbellek kontrol -> yok veya eski
        +-> _VERI_KAYNAGI_KURUM = "ziraat"
        +-> _VERI_KAYNAGI_HESAP = "111111"
        +-> source adaptorler/ziraat.sh
        +-> adaptor_hisse_bilgi_al "THYAO"  (ziraat/111111 cookie ile)
        +-> Sonuc: "312.50  343.75  281.25  1.34  Surekli Islem"
        +-> Onbellege yaz
        +-> Robota dondur
```

Robot sadece `veri_kaynagi_fiyat_al("THYAO")` cagirir. Gerisini bilmez.

### 9.5 Veri Kaynagi Fonksiyonlari

| Fonksiyon | Katman | Aciklama |
|-----------|--------|----------|
| veri_kaynagi_baslat | Tarama | Otomatik veya manuel kaynak sec, koruma baslar |
| veri_kaynagi_durdur | Tarama | Koruma dongusunu durdur |
| veri_kaynagi_ayarla | Tarama | Manuel kaynak secimi |
| veri_kaynagi_goster | Tarama | Aktif kaynagi ve yedekleri goster |
| veri_kaynagi_fiyat_al | Tarama | Sembol fiyat verisi (onbellekli) |
| veri_kaynagi_fiyatlar_al | Tarama | Birden fazla sembol (toplu sorgu) |
| _veri_onbellek_oku | Tarama | Dosyadan onbellek oku |
| _veri_onbellek_yaz | Tarama | Dosyaya onbellek yaz |
| _veri_failover | Tarama | Kaynak dusunce yedege gec |

### 9.6 Tam Senaryo: 5 Robot, 3 Kurum, 10 Hesap

```
[GIRIS - Terminal 1]
  borsa ziraat giris 111111 ...     -> OK
  borsa ziraat giris 222222 ...     -> OK
  borsa garanti giris 333333 ...    -> OK
  borsa garanti giris 444444 ...    -> OK
  borsa garanti giris 555555 ...    -> OK
  borsa isbank giris 666666 ...     -> OK
  ...

[VERI KAYNAGI SECIMI - Terminal 1]
  veri_kaynagi_baslat
    -> Acik oturumlar taraniyor...
    -> Veri kaynagi: ziraat/111111 (otomatik)
    -> Yedekler: ziraat/222222, garanti/333333, garanti/444444, ...
    -> Oturum koruma baslatildi (PID 3001)
    -> /tmp/borsa/ziraat/111111/veri_kaynagi.pid = 3001

[ROBOT BASLATMA - Terminal 1]
  robot_baslat ziraat 111111 strateji_a.sh   -> PID 4501
  robot_baslat ziraat 222222 strateji_b.sh   -> PID 4502
  robot_baslat garanti 333333 strateji_c.sh  -> PID 4503
  robot_baslat garanti 444444 strateji_d.sh  -> PID 4504
  robot_baslat garanti 555555 strateji_e.sh  -> PID 4505

[CALISMA DURUMU]
  Her 5 robot da veri icin ziraat/111111 uzerinden cekim yapar.
  Ama emirlerini kendi kurum+hesaplarından gonderir.

  PID 4501 (ziraat/111111):
    VERI <- ziraat/111111 (kendisi ayni zamanda veri kaynagi)
    EMIR -> ziraat/111111

  PID 4503 (garanti/333333):
    VERI <- ziraat/111111 (merkezi kaynak)
    EMIR -> garanti/333333 (kendi kurumu)

[FAILOVER SENARYOSU]
  ziraat/111111 oturumu duser (sunucu kapatti):
    -> veri_kaynagi_fiyat_al basarisiz
    -> _veri_failover: yedek listesinden ziraat/222222 denenir
    -> adaptor_oturum_gecerli_mi("ziraat", "222222") -> gecerli
    -> Yeni veri kaynagi: ziraat/222222
    -> Oturum koruma eski PID durdurulur, yeni baslatilir
    -> Log: "VERI KAYNAGI DEGISTI: ziraat/111111 -> ziraat/222222"
    -> Robotlar kesintisiz devam eder (sadece 1-2 saniye gecikme)

[VERI KAYNAGI TAMAMEN DUSERSE]
  Tum yedekler de dusseydi:
    -> _veri_failover: hicbir yedek gecerli degil
    -> Log: "KRITIK: Hicbir veri kaynagi erisilebilir degil"
    -> Robotlara sinyal: VERI_YOK
    -> Robotlar bekleme moduna gecer (emir gondermez)
    -> Kullanici uyarilir: "Tum oturumlar dusmus, giris yapin"
```

### 9.7 Veri Kaynagi ve Oturum Koruma Iliskisi

Veri kaynagi hesabinin oturumu ozel oneme sahiptir.
Bu hesabin robotu olsa da olmasa da oturumu korunmalidir.

| Hesap | Robot var mi | Veri kaynagi mi | Oturum koruma |
|-------|-------------|-----------------|---------------|
| ziraat/111111 | Evet (PID 4501) | Evet | 2 koruma calisiyor: robot + veri kaynagi |
| ziraat/222222 | Evet (PID 4502) | Hayir (yedek) | 1 koruma: robot |
| garanti/333333 | Evet (PID 4503) | Hayir (yedek) | 1 koruma: robot |
| isbank/666666 | Hayir | Hayir | Koruma yok -> suresi dolunca duser |

Not: Veri kaynagi olan hesapta 2 koruma calismasi sorun degildir.
Ikisi de sessiz GET atar, sunucu bunu normal kullanici aktivitesi olarak gorur.
Zarar vermez, aksine daha saglamdir.

## 10. Tarama ve Strateji Katmanlari

### 10.1 Tarama Katmani

Tarama katmani fiyat ve hacim verisini toplar.
Veri kaynagi mekanizmasi (bolum 9) uzerinden calisir.
Ne adaptoru ne kurumu bilir.

Tarama fonksiyonunun girdisi: sembol listesi.
Tarama fonksiyonunun ciktisi: her sembol icin fiyat verisi (stdout, TAB ayricli).

```
THYAO   312.50   343.75   281.25   1.34   Surekli Islem
AKBNK    42.80    47.08    38.52   0.82   Surekli Islem
```

### 10.2 Strateji Katmani

Strateji bir Bash dosyasidir. Iki zorunlu fonksiyon tanimlar:

```bash
strateji_baslat()      # Baslangic ayarlari (opsiyonel)
strateji_degerlendir() # Her turda cagrilir, sinyal dondurur
                       # stdout'a: ALIS|SATIS|BEKLE SEMBOL LOT FIYAT
```

Strateji dosyasi hicbir kurum, adaptor veya HTTP detayi bilmez. Sadece veri alir, karar verir.

## 11. Veritabani Katmani (Supabase)

### 11.1 Neden Veritabani Gerekli

Sistem su anda tamamen efemer (ucucu) calisir. Her komut sunucuya istek atar,
sonucu ekrana yazar ve cikar. Hicbir islem kalici olarak kaydedilmez.
Bu durum su sorunlari yaratir:

- Hangi emrin ne zaman gonderildigi bilinmez.
- Gecmis bakiye sorgulanamaz, hesap buyumesi/erimesi izlenemez.
- Pozisyon gecmisi yok — hisse ne zaman alindi, ne zaman satildi takip edilemez.
- Gerceklesen emirlerin detayi (dolum fiyati, zaman) kaybolur.
- Halka arz talep gecmisi yok.
- Robot performansi olculemez — hangi strateji ne kazandirdi bilinmez.

MKK (Merkezi Kayit Kurulusu) duzeyinde izleme icin her alim/satim KAYIT ALTINDA
olmalidir. Istisna yok, ``unuttum`` yok. Bakiye her zaman mutabik, pozisyon her
zaman takipli.

### 11.2 Neden Supabase

Supabase, PostgreSQL veritabani uzerine otomatik REST API sunar (PostgREST).
Bu demek ki veritabanina erismek icin sadece `curl` yeterlidir.
Yeni dil, yeni bagimlili, yeni calisma ortami gerekmez.

```
Mevcut:   curl -> araci kurum sunucusu (Ziraat, Garanti vb)
Yeni:     curl -> Supabase REST API (ayni mekanizma)
```

Secim nedenleri:
- Mevcut mimariyle %100 uyumlu: Bash + curl.
- PostgreSQL guclu, ACID uyumlu, iliskisel veritabani.
- Row Level Security (RLS) ile guvenlik.
- Bulut tabanli — sunucu yonetimi gerekmez.
- Ucretsiz katman yeterli (500 MB, 50.000 satir/ay).

### 11.3 Veritabani Erisim Mekanizmasi

Veritabani islemleri `veritabani/supabase.sh` icerisindeki `vt_*` fonksiyonlari
uzerinden yapilir. Hicbir katman dogrudan curl ile Supabase'e istek atmaz.

```
[YAZMA AKISI]
  adaptor_emir_gonder() basarili
    |
    +-> _BORSA_VERI_SON_EMIR array'ine kaydet    (anlik, proses-ici)
    +-> vt_emir_kaydet(...)                       (kalici, Supabase'e)
         |
         +-> curl -s -X POST .../rest/v1/emirler
               -H "apikey: $SUPABASE_ANAHTAR"
               -H "Content-Type: application/json"
               -d '{"sembol":"THYAO","yon":"ALIS",...}'
         +-> HTTP 201 -> basarili, log yaz
         +-> HTTP 4xx/5xx -> UYARI log, islem engellenmez
```

```
[OKUMA AKISI]
  vt_bakiye_gecmisi("ziraat", "111111", 30)
    |
    +-> curl -s .../rest/v1/bakiye_gecmisi
          ?kurum=eq.ziraat&hesap=eq.111111
          &order=zaman.desc&limit=30
    +-> JSON yanit parse et (jq ile)
    +-> stdout'a tablo bas
```

### 11.4 Baglanti Ayarlari

Supabase erisim bilgileri `veritabani/supabase.ayarlar.sh` dosyasinda saklanir.
Bu dosya git'e EKLENMEZ (.gitignore). Her makinede yerel olarak olusturulur.

```bash
# veritabani/supabase.ayarlar.sh
_SUPABASE_URL="https://xxxxx.supabase.co"
_SUPABASE_ANAHTAR="eyJhbGc..."     # anon/public key (RLS ile korunur)
_SUPABASE_SERVIS_ANAHTAR=""        # bos birak, kullanilmaz
```

Guvenlik:
- Sadece `anon` anahtar kullanilir, `service_role` KULLANILMAZ.
- RLS politikalari tum tablolarda aktiftir.
- `.gitignore` dosyasinda `supabase.ayarlar.sh` satirı bulunur.
- Dosya izinleri `chmod 600` ile korunur.

### 11.5 Veritabani Semasi (Tablo Yapilari)

#### 11.5.1 emirler

Gonderilen her emrin kalici kaydi. Emir gonderildigi anda yazilir.

```
emirleri tablosu:
  id              BIGINT       PRIMARY KEY (otomatik)
  kurum           TEXT         NOT NULL    (ziraat, garanti vb)
  hesap           TEXT         NOT NULL    (hesap numarasi)
  sembol          TEXT         NOT NULL    (THYAO, AKBNK vb)
  yon             TEXT         NOT NULL    (ALIS, SATIS)
  lot             INTEGER      NOT NULL
  fiyat           NUMERIC(12,4)            (limit fiyat, piyasa emrinde NULL)
  piyasa_mi       BOOLEAN      DEFAULT FALSE
  referans_no     TEXT                     (kurum referans numarasi)
  durum           TEXT         NOT NULL    (GONDERILDI, GERCEKLESTI, IPTAL, KISMI, REDDEDILDI)
  strateji        TEXT                     (strateji dosya adi, manuel ise NULL)
  robot_pid       INTEGER                  (robot PID, manuel ise NULL)
  hata_mesaji     TEXT                     (reddedilmisse hata metni)
  olusturma_zamani TIMESTAMPTZ DEFAULT NOW()
  guncelleme_zamani TIMESTAMPTZ
```

#### 11.5.2 bakiye_gecmisi

Periyodik bakiye anlik goruntusu. Her bakiye sorgusunda yazilir.

```
bakiye_gecmisi tablosu:
  id              BIGINT       PRIMARY KEY (otomatik)
  kurum           TEXT         NOT NULL
  hesap           TEXT         NOT NULL
  nakit           NUMERIC(14,2) NOT NULL   (TL)
  hisse_degeri    NUMERIC(14,2) NOT NULL   (TL)
  toplam          NUMERIC(14,2) NOT NULL   (TL)
  zaman           TIMESTAMPTZ  DEFAULT NOW()
```

#### 11.5.3 pozisyonlar

Anlik portfoy pozisyonlari. Her portfoy sorgusunda guncellenir.

```
pozisyonlar tablosu:
  id              BIGINT       PRIMARY KEY (otomatik)
  kurum           TEXT         NOT NULL
  hesap           TEXT         NOT NULL
  sembol          TEXT         NOT NULL
  lot             INTEGER      NOT NULL
  ortalama_maliyet NUMERIC(12,4)           (hisse basi maliyet)
  piyasa_fiyati   NUMERIC(12,4)           (son fiyat)
  piyasa_degeri   NUMERIC(14,2)           (lot * fiyat)
  kar_zarar       NUMERIC(14,2)           (TL)
  kar_zarar_yuzde NUMERIC(8,4)            (%)
  zaman           TIMESTAMPTZ  DEFAULT NOW()
  UNIQUE(kurum, hesap, sembol, zaman::date) -- gun bazinda tekil
```

#### 11.5.4 halka_arz_islemleri

Halka arz talep, iptal ve guncelleme islemleri.

```
halka_arz_islemleri tablosu:
  id              BIGINT       PRIMARY KEY (otomatik)
  kurum           TEXT         NOT NULL
  hesap           TEXT         NOT NULL
  islem_tipi      TEXT         NOT NULL    (TALEP, IPTAL, GUNCELLE)
  ipo_adi         TEXT
  ipo_id          TEXT
  lot             INTEGER
  fiyat           NUMERIC(12,4)
  basarili        BOOLEAN      NOT NULL
  mesaj           TEXT
  zaman           TIMESTAMPTZ  DEFAULT NOW()
```

#### 11.5.5 robot_log

Robot yasam dongusu olaylari.

```
robot_log tablosu:
  id              BIGINT       PRIMARY KEY (otomatik)
  kurum           TEXT         NOT NULL
  hesap           TEXT         NOT NULL
  robot_pid       INTEGER      NOT NULL
  strateji        TEXT         NOT NULL
  olay            TEXT         NOT NULL    (BASLADI, DURDU, HATA, EMIR, FAILOVER vb)
  detay           JSONB                    (olay detaylari, serbest format)
  zaman           TIMESTAMPTZ  DEFAULT NOW()
```

#### 11.5.6 oturum_log

Oturum baslangic, bitis ve uzatma olaylari.

```
oturum_log tablosu:
  id              BIGINT       PRIMARY KEY (otomatik)
  kurum           TEXT         NOT NULL
  hesap           TEXT         NOT NULL
  olay            TEXT         NOT NULL    (GIRIS, CIKIS, UZATMA, DUSME)
  detay           TEXT
  zaman           TIMESTAMPTZ  DEFAULT NOW()
```

### 11.6 Veritabani Fonksiyonlari

Tum fonksiyonlar `veritabani/supabase.sh` icerisinde tanimlanir.

#### 11.6.1 Altyapi Fonksiyonlari

| Fonksiyon | Aciklama |
|-----------|----------|
| vt_istek_at | Supabase'e curl ile HTTP istegi atar (POST/GET/PATCH). Hata durumunda log yazar, islem engellenmez. |
| vt_baglanti_kontrol | Supabase erisimini test eder (basit bir SELECT). Baslatma sirasinda cagrilir. |
| _vt_json_olustur | Bash degiskenlerinden JSON string olusturur. jq kullanir. |

#### 11.6.2 Yazma Fonksiyonlari

| Fonksiyon | Tetik Noktasi | Aciklama |
|-----------|---------------|----------|
| vt_emir_kaydet | adaptor_emir_gonder sonrasi | Emri emirler tablosuna yazar |
| vt_emir_durum_guncelle | adaptor_emirleri_listele sonrasi | Emir durumunu gunceller (GERCEKLESTI, IPTAL vb) |
| vt_bakiye_kaydet | adaptor_bakiye sonrasi | Bakiye anligini bakiye_gecmisi'ne yazar |
| vt_pozisyon_kaydet | adaptor_portfoy sonrasi | Her hisse icin pozisyon kaydeder |
| vt_halka_arz_kaydet | adaptor_halka_arz_talep/iptal/guncelle sonrasi | Halka arz islemini kaydeder |
| vt_robot_log_yaz | robot_baslat/durdur, emir, hata anlarinda | Robot olayini loglar |
| vt_oturum_log_yaz | adaptor_giris, adaptor_oturum_uzat, dusme anlarinda | Oturum olayini loglar |

#### 11.6.3 Okuma Fonksiyonlari

| Fonksiyon | Aciklama |
|-----------|----------|
| vt_emir_gecmisi | Belirli kurum/hesap icin emir gecmisini getirir |
| vt_bakiye_gecmisi | Belirli kurum/hesap icin bakiye zaman serisini getirir |
| vt_pozisyon_gecmisi | Belirli sembol ve hesap icin pozisyon degisimlerini getirir |
| vt_gun_sonu_rapor | Gunun tum islemlerini ozetler |
| vt_kar_zarar_rapor | Belirli donem icin toplam K/Z hesaplar |

### 11.7 Tetik Noktalari: Ne Zaman Yazilir

Veritabanina yazma, mevcut fonksiyonlarin sonuna eklenen tek satirlik cagrilarla yapilir.
Hicbir echo satiri silinmez, hicbir mevcut davranis degismez.

```
[EMIR GONDER SONRASI]
  adaptor_emir_gonder(...) tamamlandi
    +-> _BORSA_VERI_SON_EMIR array'i dolu        (veri_katmani_plani.md)
    +-> vt_emir_kaydet \                          (YENi)
          "$_ROBOT_KURUM" "$_ROBOT_HESAP" \       
          "${_BORSA_VERI_SON_EMIR[sembol]}" \     
          "${_BORSA_VERI_SON_EMIR[yon]}" \        
          "${_BORSA_VERI_SON_EMIR[lot]}" \        
          "${_BORSA_VERI_SON_EMIR[fiyat]}" \      
          "${_BORSA_VERI_SON_EMIR[referans]}" \   
          "${_BORSA_VERI_SON_EMIR[basarili]}"

[BAKIYE SORGUSU SONRASI]
  adaptor_bakiye() tamamlandi
    +-> _BORSA_VERI_BAKIYE array'i dolu
    +-> vt_bakiye_kaydet \                        (YENI)
          "$kurum" "$hesap" \                     
          "${_BORSA_VERI_BAKIYE[nakit]}" \        
          "${_BORSA_VERI_BAKIYE[hisse]}" \        
          "${_BORSA_VERI_BAKIYE[toplam]}"

[PORTFOY SORGUSU SONRASI]
  adaptor_portfoy() tamamlandi
    +-> _BORSA_VERI_SEMBOLLER array'i dolu
    +-> for sembol in "${_BORSA_VERI_SEMBOLLER[@]}"; do
          vt_pozisyon_kaydet \                    (YENI)
            "$kurum" "$hesap" "$sembol" \          
            "${_BORSA_VERI_HISSE_LOT[$sembol]}" \  
            ...
        done

[EMIR LISTESI SONRASI]
  adaptor_emirleri_listele() tamamlandi
    +-> _BORSA_VERI_EMIRLER array'i dolu
    +-> for ref in "${_BORSA_VERI_EMIRLER[@]}"; do
          vt_emir_durum_guncelle \                (YENI)
            "$ref" "${_BORSA_VERI_EMIR_DURUM[$ref]}"
        done

[HALKA ARZ ISLEMLERI SONRASI]
  adaptor_halka_arz_talep/iptal/guncelle() tamamlandi
    +-> _BORSA_VERI_SON_HALKA_ARZ array'i dolu
    +-> vt_halka_arz_kaydet(...)                  (YENI)
```

### 11.8 Hata Toleransi

Veritabani yazimi basarisiz oldugunda islem ENGELLENMEZ.
Bu kritik bir tasarim kararidir: emir gonderme, bakiye sorgusu gibi
birincil islemler veritabanina bagimli olmadan calisabilmelidir.

```
vt_emir_kaydet()
  +-> curl basarisiz (ag hatasi, timeout)
  |     -> Log: "UYARI: Emir DB'ye kaydedilemedi: THYAO ALIS 100 lot"
  |     -> curl.log'a detay yaz
  |     -> return 0 (basari dondurmemen, arayiciya bildirmemen)
  |     -> Yerel dosyaya yedek yaz: /tmp/borsa/_vt_yedek/bekleyen.jsonl
  |
  +-> curl basarili (HTTP 201)
        -> Log: "DB: Emir kaydedildi: THYAO ALIS 100 lot"
        -> return 0
```

Bekleyen kayitlar icin yeniden deneme mekanizmasi:

```
_vt_bekleyenleri_gonder()
  +-> /tmp/borsa/_vt_yedek/bekleyen.jsonl dosyasini oku
  +-> Her satir icin curl ile tekrar dene
  +-> Basarili olanlari dosyadan sil
  +-> Robot arka plan dongusunde periyodik cagrilir
```

### 11.9 veri_katmani_plani.md ile Iliski

veri_katmani_plani.md Bash associative array'lerini planlamistir.
Bu array'ler Supabase entegrasyonuyla ORTADAN KALKMAZ, tam tersine
birlikte calisirlar:

```
                 [ADAPTOR FONKSIYONU]
                        |
          +-------------+-------------+
          |                           |
   Bash Associative Array       Supabase Veritabani
   (proses-ici, hizli)         (kalici, yavaa)
   Robot motoru okur            Gecmis sorgulanir
   Strateji okur                Rapor uretilir
   Anlik karar verir            Denetim izi olusur
   Proses olunce yok olur       Sonsuza kadar kalir
```

Iki sistem birbirinin yerine degil, birbirini tamamlar:
- Array: Robot motorunun anlik kararlari icin ("bakiye yeterli mi?" -> hemen cevap).
- Supabase: Kalici kayit icin ("son 30 gunde THYAO ile ne kazandim?" -> sorgu gonder).

### 11.10 MKK Duzeyinde Kontrol

MKK (Merkezi Kayit Kurulusu) Turkiye'nin merkezi menkul kiymet saklama kurulusudur.
MKK duzeyinde izleme su kurallari gerektirir:

#### 11.10.1 Zorunlu Kayit

Her alim/satim emri veritabanina kaydedilir. Istisna yok.
Manuel emir de robot emri de kaydedilir.
Basarisiz emirler de kaydedilir (durum: REDDEDILDI).

#### 11.10.2 Bakiye Mutabakati

Bakiye sorgulandikca snapshot alinir. Gunun sonunda:

```
vt_mutabakat_kontrol "ziraat" "111111"
  +-> Son bakiye snapshot'ini oku (DB)
  +-> adaptor_bakiye cagir (canli)
  +-> Karsilastir: fark > 0.01 TL ise UYARI
```

Bu strateji veya robot hatalarindan kaynaklanabilecek bakiye tutarsizliklarini yakalar.

#### 11.10.3 Pozisyon Mutabakati

Portfoy sorgulandikca pozisyonlar kaydedilir. Emir gecmisiyle carpraz kontrol:

```
vt_pozisyon_mutabakat "ziraat" "111111" "THYAO"
  +-> DB emir gecmisi: 3 kez 100 lot ALIS = 300 lot bekleniyor
  +-> DB pozisyon: 300 lot -> TUTARLI
  +-> DB bakiye: nakit yeterli -> TUTARLI
```

Tutarsizlik tespit edilirse:
- KRITIK log yazilir
- Robot durdurulabilir (konfigurasyona bagli)
- Manuel mudahale beklenir

#### 11.10.4 Degistirilemezlik

Kayitlar INSERT-only. UPDATE sadece durum degisimi icin (Iletildi -> Gerceklesti).
DELETE hicbir zaman yapilmaz. Hatali kayitlar IPTAL durumuyla isaretlenir.

### 11.11 Ornek Sorgular

Terminalden veritabani sorgulama ornekleri:

```bash
# Son 10 emri goster
borsa gecmis emirler 10

# Bugunku bakiye degisimini goster
borsa gecmis bakiye bugun

# THYAO ile yapilan tum islemler
borsa gecmis sembol THYAO

# Son 30 gunun K/Z raporu
borsa gecmis kar 30

# Robot performans raporu
borsa gecmis robot 4501

# Bakiye mutabakat kontrolu
borsa mutabakat ziraat 111111
```

Bu komutlar `borsa()` fonksiyonuna yeni alt komutlar olarak eklenir.

### 11.12 Tam Senaryo: Emir Yasam Dongusu

```
[1. EMIR GONDERILIR]
  robot_motoru -> adaptor_emir_gonder "THYAO" "alis" "100" "312.50"
    +-> Kurum sunucusu: emiriniz kaydedilmistir (ref: ABC123)
    +-> _BORSA_VERI_SON_EMIR doldurulur (in-memory)
    +-> vt_emir_kaydet(...) cagirilir
         DB INSERT: emirler (THYAO, ALIS, 100, 312.50, ABC123, GONDERILDI)

[2. EMIR DURUMU KONTROL EDILIR] (30 sn sonra)
  robot_motoru -> adaptor_emirleri_listele
    +-> Kurum sunucusu: ABC123 -> Gerceklesti
    +-> _BORSA_VERI_EMIR_DURUM[ABC123]="Gerceklesti" (in-memory)
    +-> vt_emir_durum_guncelle("ABC123", "GERCEKLESTI")
         DB UPDATE: emirler SET durum='GERCEKLESTI' WHERE referans_no='ABC123'

[3. BAKIYE GUNCELLENIR]
  robot_motoru -> adaptor_bakiye
    +-> Kurum sunucusu: nakit=13997.50, hisse=155768.12, toplam=169765.62
    +-> _BORSA_VERI_BAKIYE doldurulur (in-memory)
    +-> vt_bakiye_kaydet(...)
         DB INSERT: bakiye_gecmisi (ziraat, 111111, 13997.50, 155768.12, 169765.62)

[4. PORTFOY GUNCELLENIR]
  robot_motoru -> adaptor_portfoy
    +-> THYAO: 100 lot, maliyet 312.50, piyasa 315.00, K/Z +250.00
    +-> _BORSA_VERI_HISSE_* doldurulur (in-memory)
    +-> vt_pozisyon_kaydet(...)
         DB INSERT: pozisyonlar (ziraat, 111111, THYAO, 100, 312.50, 315.00, ...)

[5. GUN SONU]
  vt_mutabakat_kontrol("ziraat", "111111")
    +-> DB bakiye: 169765.62 / canli bakiye: 169765.62 -> TUTARLI
    +-> Log: "Mutabakat basarili: ziraat/111111"
```

## 12. Yol Haritasi

### 12.1 Asama 1 - Oturum Altyapisi

Cekirdek'e oturum suresi ve son istek zamani veri yapilari eklenir.
Ziraat adaptorune sessionTimeOutModel parse fonksiyonu eklenir.
Ziraat adaptorune sessiz oturum uzatma fonksiyonu eklenir.

### 12.2 Asama 2 - Veri Katmani (Bash Array)

veri_katmani_plani.md'deki tum declare -gA tanimlari ve yardimci
fonksiyonlar cekirdek'e eklenir. Adaptor fonksiyonlarina array
kaydi eklenir. Mevcut echo ciktilari degismez.

### 12.3 Asama 3 - Veritabani Altyapisi (Supabase)

veritabani/ klasoru olusturulur.
supabase.sh ve supabase.ayarlar.sh dosyalari yazilir.
Supabase projesinde tablolar olusturulur (SQL).
vt_istek_at, vt_baglanti_kontrol, _vt_json_olustur yazilir.
jq bagimliliginin varligi kontrol edilir.
Hata toleransi ve yerel yedek mekanizmasi yazilir.

### 12.4 Asama 4 - Veritabani Yazma Entegrasyonu

vt_emir_kaydet adaptor_emir_gonder sonrasina eklenir.
vt_bakiye_kaydet adaptor_bakiye sonrasina eklenir.
vt_pozisyon_kaydet adaptor_portfoy sonrasina eklenir.
vt_emir_durum_guncelle adaptor_emirleri_listele sonrasina eklenir.
vt_halka_arz_kaydet halka arz islemleri sonrasina eklenir.
vt_oturum_log_yaz giris/cikis/uzatma noktalarına eklenir.

### 12.5 Asama 5 - Veri Cekme (Adaptor)

Ziraat adaptorune adaptor_hisse_bilgi_al fonksiyonu eklenir.
Emir gonderme oncesi tavan/taban ve bakiye kontrolleri eklenir.
borsa ziraat fiyat SEMBOL komutu eklenir.

### 12.6 Asama 6 - Veri Kaynagi Altyapisi

tarama/ klasoru olusturulur.
Veri kaynagi secim algoritmasi yazilir (otomatik + manuel).
Onbellek mekanizmasi yazilir (dosya tabanli).
Failover mekanizmasi yazilir (otomatik yedege gecis).
Veri kaynagi oturum koruma dongusu yazilir.

### 12.7 Asama 7 - Robot Motoru

robot/ klasoru olusturulur.
robot_baslat, robot_durdur, robot_listele fonksiyonlari yazilir.
Oturum koruma dongusu yazilir.
Ana dongu iskeleti kurulur (tarama -> strateji -> emir).
Veri kaynagi ile entegrasyon yapilir.
vt_robot_log_yaz entegrasyonu yapilir.

### 12.8 Asama 8 - Strateji Katmani

strateji/ klasoru olusturulur.
Strateji arayuzu (strateji_baslat, strateji_degerlendir) belirlenir.
Ornek strateji yazilir (test amacli basit kural).
Robot motoru ile entegre edilir.

### 12.9 Asama 9 - Veritabani Okuma ve Raporlama

borsa gecmis alt komutu eklenir.
vt_emir_gecmisi, vt_bakiye_gecmisi, vt_pozisyon_gecmisi yazilir.
vt_gun_sonu_rapor, vt_kar_zarar_rapor yazilir.
vt_mutabakat_kontrol yazilir.
Tab tamamlama guncellenir.

### 12.10 Asama 10 - Ust Seviye Komutlar

Robottan bagimsiz, kurumsuz ust seviye fonksiyonlar eklenir.
emir_gonder, bakiye_sorgula gibi fonksiyonlar robot_baslat ile kilitli kurumu kullanir.
Bu fonksiyonlar strateji katmanindan cagrilir.
