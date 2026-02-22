# Borsa Modulu - Sistem Plani

## 1. Amac

Bu belge borsa klasorunun tamamini kapsar: mevcut altyapi, robot motoru, strateji, tarama ve oturum yonetimi.
Hangi kodun nerede yazilacagini, katmanlar arasi sorumluluk sinirlarini ve algoritmik islem dongusunu tanimlar.

## 2. Katmanli Mimari

Sistem bes katmandan olusur. Her katman sadece bir altindaki katmanla konusur, katman atlamaz.

```
+-----------------------------------------------+    +---------------------------+
|  5. ROBOT MOTORU (robot/motor.sh)             |    |  YEREL SUPABASE           |
|     Strateji calistirir, sinyal dinler,       |    |  (veritabani/supabase.sh) |
|     emir tetikler, oturum koruma baslatir      |    |                           |
+-----------------------------------------------+    |  Docker ile localhost'ta  |
|  4. STRATEJI (strateji/*.sh)                  |    |  calisan PostgreSQL +     |
|     Alis/satis karari verir, sinyal uretir    |    |  PostgREST + GoTrue +     |
+-----------------------------------------------+    |  Kong API Gateway         |
|  3. TARAMA + VERI KAYNAGI (tarama/*.sh)       |    |                           |
|     Merkezi veri kaynagi yonetimi,            |    |  Kalici kayit servisi:    |
|     onbellek, failover, fiyat/hacim toplama   |    |  - Emir gecmisi           |
+-----------------------------------------------+    |  - Bakiye anliklari       |
|  2. ADAPTOR (adaptorler/*.sh)                 |<-->|  - Pozisyon izleme        |
|     Kuruma ozgu HTTP islemleri, parse, emir   |    |  - K/Z takibi             |
+-----------------------------------------------+    |                           |
|  1. CEKIRDEK (cekirdek.sh + kurallar/*.sh)    |<-->|  curl localhost:8000      |
|     HTTP, oturum dizini, BIST kurallari       |    |  vt_* fonksiyonlari       |
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
    docker-compose.yml       # Supabase Docker Compose (projenin icinde, tak-calistir)
    .env.ornek               # Ornek ayarlar (git'e girer, sifre icermez)
    .env                     # Gercek ayarlar (git'e GIRMEZ, .gitignore)
    sema.sql                 # Tum tablo tanimlari (CREATE TABLE IF NOT EXISTS)
    supabase.sh              # Veritabani servisi: baglanti, CRUD, sema
    supabase.ayarlar.sh      # Baglanti bilgileri (git'e GIRMEZ, .gitignore)
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

### 9.3 Veri Depolama: Iki Katmanli Yapi

Fiyat verileri iki katmanda saklanir: kisa sureli onbellek (hiz) ve kalici gecmis (analiz).

#### 9.3.1 Katman 1: Kisa Sureli Onbellek (Dosya)

Ayni anda 5 robot calisiyor ve hepsi THYAO fiyatini soruyor.
Her sorguda sunucuya HTTP istegi atmak gereksizdir cunku fiyat saniyeler icinde degismez.

Cozum: Tarama katmani son cekilen veriyi kisa sureligine dosyaya saklar.

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
    |     -> sunucudan taze cek, onbellegi guncelle, Supabase'e kaydet
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

Bu katman yalnizca hiz icindir. Veri gecicidir, bilgisayar kapaninca silinir.

#### 9.3.2 Katman 2: Kalici Fiyat Gecmisi (Supabase)

Her taze fiyat cekiminde (onbellek eski veya bos oldugunda) veri ayni zamanda
Supabase'e de yazilir. Boylece tum fiyat gecmisi kalici olarak saklanir.

```
[KALICI KAYIT AKISI]
  veri_kaynagi_fiyat_al("THYAO")
    +-> Onbellek eski -> sunucudan taze cek
    +-> Dosya onbellege yaz (hiz katmani)        <- gecici
    +-> vt_fiyat_kaydet("THYAO", ...)             <- kalici (Supabase)
         |                                        
         +-> curl -s -X POST http://localhost:8001/rest/v1/fiyat_gecmisi
               -d '{"sembol":"THYAO","fiyat":312.50,...}'
         +-> Basarisiz olursa islem engellenmez (hata toleransi)
```

Bu katmanin sagladigi avantajlar:

| Avantaj | Aciklama |
|---------|----------|
| Gecmis analiz | "THYAO son 30 gunde ne yapti?" sorusuna SQL ile cevap |
| Strateji gelistirme | Gecmis veriler uzerinden strateji test etme (backtesting) |
| Grafik ve raporlama | Supabase Studio'dan gorsel analiz |
| Robotlar arasi tutarlilik | Tum robotlar ayni tablodan okuyabilir |
| Veri madenciligi | Hacim, fiyat korelasyonu gibi ileri analizler |

#### 9.3.3 Iki Katmanin Birlikte Calismasi

```
[FIYAT ISTEGI]
  Robot -> veri_kaynagi_fiyat_al("THYAO")
           |
           +-> [1] Dosya onbellek kontrol (/tmp/borsa/_veri_onbellek/THYAO.dat)
           |     Taze (< 10 sn) -> onbellekten dondur, Supabase'e yazma
           |     Eski veya yok ->
           |       +-> [2] Kurumdan taze fiyat cek (adaptor_hisse_bilgi_al)
           |       +-> [3] Dosya onbellege yaz (gecici, hiz icin)
           |       +-> [4] vt_fiyat_kaydet (kalici, Supabase'e)
           |       +-> [5] Robota dondur
```

Onemli: Supabase'e yazma sadece taze cekim aninda yapilir. Onbellekten
okunan tekrar isteklerde DB'ye yazilmaz (ayni veriyi tekrar yazmak gereksiz).

### 9.4 Veri Kaynagi ile Adaptor Arasindaki Iliski

Veri kaynaginin bir adaptoru vardir. Tarama katmani bu adaptoru soyutlar.
Ne robot ne strateji hangi adaptorun kullanildigini bilir.

```
Robot: "THYAO fiyatini ver"
  |
  +-> Tarama katmani: veri_kaynagi_fiyat_al("THYAO")
        |
        +-> Dosya onbellek kontrol -> yok veya eski
        +-> _VERI_KAYNAGI_KURUM = "ziraat"
        +-> _VERI_KAYNAGI_HESAP = "111111"
        +-> source adaptorler/ziraat.sh
        +-> adaptor_hisse_bilgi_al "THYAO"  (ziraat/111111 cookie ile)
        +-> Sonuc: "312.50  343.75  281.25  1.34  Surekli Islem"
        +-> Dosya onbellege yaz (gecici, hiz icin)
        +-> vt_fiyat_kaydet("THYAO", ...) (kalici, Supabase'e)
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
| veri_kaynagi_gecmis_al | Tarama | Belirli sembolun gecmis fiyatlarini Supabase'den getirir |
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

### 11.2 Neden Supabase (Yerel Kurulum)

Supabase acik kaynakli bir projedir. Bulut hizmeti olarak da sunulur ama biz
bulut KULLANMIYORUZ. Supabase'i kendi bilgisayarimizda Docker ile calistiriyoruz.
Veri disariya cikmaz, internet gerekmez, sinir yok, ucret yok.

Supabase, PostgreSQL veritabani uzerine otomatik REST API sunar (PostgREST).
Bu demek ki veritabanina erismek icin sadece `curl` yeterlidir.
Yeni dil, yeni bagimlili, yeni calisma ortami gerekmez.

```
Mevcut:   curl -> araci kurum sunucusu (Ziraat, Garanti vb)
Yeni:     curl -> localhost:8000/rest/v1/... (ayni mekanizma, yerel)
```

Secim nedenleri:
- Mevcut mimariyle %100 uyumlu: Bash + curl.
- PostgreSQL guclu, ACID uyumlu, iliskisel veritabani.
- Row Level Security (RLS) ile guvenlik.
- Tamamen yerel: veri bilgisayardan cikmaz, internet gerekmez.
- Sifir gecikme: localhost uzerinden ~1-5ms.
- Sifir maliyet: sinir yok, istedigin kadar satir.
- Docker ile tek komutla baslar, tek komutla durur.
- Baska bir projede zaten kullaniliyor, altyapi hazir.

#### 11.2.1 Yerel Supabase Mimarisi

Supabase Docker Compose ile su bilesenleri calistirir:

```
+----------------------------------+
|  Kong API Gateway (:8000)        |  <- curl istekleri buraya gelir
|    |                             |
|    +-> PostgREST (:3000)         |  <- SQL'e REST API olarak cevirir
|    +-> GoTrue (:9999)            |  <- kimlik dogrulama (opsiyonel)
|    +-> Realtime (:4000)          |  <- canli dinleme (ileride kullanilabilir)
|    +-> Storage (:5000)           |  <- dosya depolama (kullanmiyoruz)
|    |                             |
|  PostgreSQL (:5432)              |  <- asil veritabani
|  Supabase Studio (:3001)         |  <- web arayuzu (tablo yonetimi)
+----------------------------------+
```

Biz sadece su bilesenleri aktif kullaniyoruz:
- PostgreSQL: veritabani motoru
- PostgREST: REST API (curl ile erisim)
- Kong: API Gateway (tek giris noktasi)
- Studio: tablo olusturma ve veri inceleme (opsiyonel, tarayicidan)

Su an aktif kullanmadigimiz bilesenler (Docker'da calisir ama biz istek atmayiz):
- GoTrue (kimlik dogrulama - tek kullanici oldugumuz icin gereksiz)
- Realtime (canli bildirim - su an Bash'ten kullanilmiyor. Ileride Python veya
  JavaScript istemci ile canli fiyat akisi dinleme yapilabilir. PostgreSQL
  tarafinda fiyat_gecmisi tablosuna INSERT yapildiginda Realtime otomatik
  olarak yayin yapar, ek bir ayar gerektirmez.)
- Storage (dosya depolama - ihtiyacimiz yok)

#### 11.2.2 Kurulum: Tak-Calistir Yaklasimi

Supabase'in tum reposunu (500 MB) klonlamaya gerek yok. Calistirmak icin sadece
`docker-compose.yml` ve `.env` dosyasi yeterli. Bu dosyalar dogrudan bu projenin
icinde `veritabani/` klasorunde bulunur.

Bu sayede dotfiles reposunu herhangi bir Linux makineye klonlayip 3 komutla
her seyi calistirmak mumkundur:

```bash
# Yeni makine - ilk kurulum:
git clone <dotfiles-repo>
cd dotfiles/bashrc.d/borsa/veritabani
cp .env.ornek .env          # ayarlari kopyala (bir kez)
docker compose up -d         # Supabase baslar, eksik image'lar otomatik iner

# Artik calisiyor:
curl http://localhost:8001/rest/v1/   # REST API hazir
# Tarayicida: http://localhost:3002   # Studio hazir
```

Gunluk kullanim:

```bash
# Supabase baslat (bilgisayar acildiginda):
cd ~/dotfiles/bashrc.d/borsa/veritabani && docker compose up -d

# Supabase durdur (veri KORUNUR):
cd ~/dotfiles/bashrc.d/borsa/veritabani && docker compose stop

# Tamamen sil (veri dahil):
cd ~/dotfiles/bashrc.d/borsa/veritabani && docker compose down -v
```

Neden projenin icinde:
- Tek repo, tek clone. Baska bir yere git clone gerekmez.
- docker-compose.yml 50 KB — repo boyutunu etkilemez.
- .env.ornek git'e girer (sifre icermez), .env git'e girmez (.gitignore).
- Yeni makinede cp .env.ornek .env + docker compose up -d = calisiyor.

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
         +-> curl -s -X POST http://localhost:8001/rest/v1/emirler
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
    +-> curl -s http://localhost:8001/rest/v1/bakiye_gecmisi
          ?kurum=eq.ziraat&hesap=eq.111111
          &order=zaman.desc&limit=30
    +-> JSON yanit parse et (jq ile)
    +-> stdout'a tablo bas
```

### 11.4 Baglanti Ayarlari

Yerel Supabase erisim bilgileri `veritabani/supabase.ayarlar.sh` dosyasinda saklanir.
Bu dosya git'e EKLENMEZ (.gitignore). Her makinede yerel olarak olusturulur.

```bash
# veritabani/supabase.ayarlar.sh
_SUPABASE_URL="http://localhost:8001"   # Kong API Gateway (yerel, port 8001)
_SUPABASE_ANAHTAR="eyJhbGc..."          # anon key (.env dosyasindan)
_SUPABASE_SERVIS_ANAHTAR=""             # bos birak, kullanilmaz
```

Not: `_SUPABASE_ANAHTAR` degeri ayni klasordeki `.env` dosyasindaki `ANON_KEY` ile
ayni olmalidir. Bu anahtar JWT formatindadir ve PostgREST tarafindan dogrulanir.

Guvenlik:
- Tamamen yerel: disaridan erisim yok, veri bilgisayardan cikmaz.
- Sadece `anon` anahtar kullanilir, `service_role` KULLANILMAZ.
- RLS politikalari tum tablolarda aktiftir (tek kullanici olsak bile).
- `.gitignore` dosyasinda `supabase.ayarlar.sh` satiri bulunur.
- Dosya izinleri `chmod 600` ile korunur.
- Docker agı sadece localhost'a baglidir, dis ag erisimi kapatilir.

#### 11.4.1 Supabase Saglik Kontrolu

Veritabani islemleri oncesinde Supabase'in calisip calismadigini kontrol eder:

```bash
vt_baglanti_kontrol()
  +-> curl -sf http://localhost:8001/rest/v1/ > /dev/null
  |     Basarili -> return 0
  |     Basarisiz ->
  |       +-> Docker container'lari kontrol et
  |       +-> Kapaliysa uyari: "Supabase calismyor. Baslatmak icin:"
  |       +->   "cd $(dirname $0)/veritabani && docker compose up -d"
  |       +-> return 1
```

Robot baslangicinda ve periyodik olarak cagrilir.
Supabase kapaliysa islem engellenmez, sadece DB yazimi atlanir.

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

#### 11.5.7 fiyat_gecmisi

Tarama katmanindan cekilen fiyat verilerinin kalici kaydini tutar.
Her taze cekim aninda (onbellek eski veya bos oldugunda) bir satir eklenir.
Strateji gelistirme, backtesting ve gecmis analiz icin kullanilir.

```
fiyat_gecmisi tablosu:
  id              BIGINT       PRIMARY KEY (otomatik)
  sembol          TEXT         NOT NULL    (THYAO, AKBNK vb)
  fiyat           NUMERIC(12,4) NOT NULL   (son islem fiyati)
  tavan           NUMERIC(12,4)            (gunluk tavan fiyat)
  taban           NUMERIC(12,4)            (gunluk taban fiyat)
  degisim         NUMERIC(8,4)             (gunluk degisim yuzdesi)
  hacim           BIGINT                   (islem hacmi, lot)
  seans_durumu    TEXT                     (Surekli Islem, Kapali, Tek Fiyat vb)
  kaynak_kurum    TEXT                     (veriyi hangi kurum oturumundan aldik)
  kaynak_hesap    TEXT                     (hangi hesap oturumundan aldik)
  zaman           TIMESTAMPTZ  DEFAULT NOW()
```

Ornek sorgular:

```sql
-- THYAO son 30 gunluk kapanislar
SELECT sembol, fiyat, zaman FROM fiyat_gecmisi
  WHERE sembol = 'THYAO'
  ORDER BY zaman DESC LIMIT 30;

-- Bugunun tum fiyat hareketleri
SELECT sembol, fiyat, degisim, hacim, zaman FROM fiyat_gecmisi
  WHERE zaman::date = CURRENT_DATE
  ORDER BY zaman;

-- En cok islem goren semboller (bugun)
SELECT sembol, MAX(hacim) as maks_hacim FROM fiyat_gecmisi
  WHERE zaman::date = CURRENT_DATE
  GROUP BY sembol ORDER BY maks_hacim DESC LIMIT 10;
```

Not: Bu tablo zamanla buyuyebilir. Gunluk ortalama 50 sembol x 6 saat x
6 cekim/saat = ~1800 satir/gun. Yillik ~450.000 satir — PostgreSQL icin
cok kucuk bir boyut.

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
| vt_fiyat_kaydet | veri_kaynagi_fiyat_al taze cekim aninda | Fiyat verisini fiyat_gecmisi tablosuna yazar |

#### 11.6.3 Okuma Fonksiyonlari

| Fonksiyon | Aciklama |
|-----------|----------|
| vt_emir_gecmisi | Belirli kurum/hesap icin emir gecmisini getirir |
| vt_bakiye_gecmisi | Belirli kurum/hesap icin bakiye zaman serisini getirir |
| vt_pozisyon_gecmisi | Belirli sembol ve hesap icin pozisyon degisimlerini getirir |
| vt_gun_sonu_rapor | Gunun tum islemlerini ozetler |
| vt_kar_zarar_rapor | Belirli donem icin toplam K/Z hesaplar |
| vt_fiyat_gecmisi | Belirli sembol ve donem icin fiyat gecmisini getirir |
| vt_fiyat_istatistik | Belirli sembol icin ort/min/maks/hacim istatistikleri |

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

### 12.3 Asama 3 - Veritabani Altyapisi (Yerel Supabase)

veritabani/ klasorune docker-compose.yml ve .env.ornek dosyalari eklenir.
Supabase resmi docker-compose.yml'den sadeletirilir (portlar 8001/5433/3002).
.env.ornek icinde varsayilan JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY bulunur.
.gitignore'a .env ve supabase.ayarlar.sh eklenir.
supabase.sh ve supabase.ayarlar.sh dosyalari yazilir.
Yerel Supabase'de tablolar olusturulur (Studio veya SQL ile).
vt_istek_at (localhost:8001'e curl), vt_baglanti_kontrol, _vt_json_olustur yazilir.
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
Iki katmanli veri depolama yazilir:
  - Dosya onbellek: /tmp/borsa/_veri_onbellek/ (gecici, hiz icin).
  - Kalici gecmis: vt_fiyat_kaydet ile fiyat_gecmisi tablosuna yazma.
Failover mekanizmasi yazilir (otomatik yedege gecis).
Veri kaynagi oturum koruma dongusu yazilir.
vt_fiyat_gecmisi ve vt_fiyat_istatistik okuma fonksiyonlari yazilir.

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

### 12.11 Asama 11 - Otomatik Kurulum Betigi

kur.sh dosyasi repo kokune yazilir.
Bolum 13'teki tasarima uygun olarak tum adimlar tek betikle calistirilir.
Her adim bagimsizdik kontrolu yapar, eksik olanlar kurulur veya uyari verilir.
Idempotent calisir: tekrar calistirildiginda zaten yapilmis adimlari atlar.
Test icin temiz bir Docker konteynerinde veya sanal makinede dogrulanir.

## 13. Otomatik Kurulum Sistemi

Repo baska bir makineye klonlandiginda tek bir komutla her seyin hazir hale gelmesi hedeflenir.
Kullanici repoyu klonlar, `bash kur.sh && source ~/.bashrc` calistirir — sistem hazirdir.
Terminal kapatip acmaya gerek yoktur. `&&` sayesinde kurulum basarili oldugunda
`source` komutu ayni kabukta calisir ve tum fonksiyonlar aninda aktif olur.

### 13.1 Genel Akis

```
git clone <repo> ~/dotfiles
cd ~/dotfiles
bash kur.sh && source ~/.bashrc
# Hazir.
```

Betik asagidaki adimlari sirayla calistirir.
Her adim basinda kontrol yapar: zaten yapilmissa atlar, eksikse yapar.
Betik idempotent calisir — tekrar calistirmak guvenlidir.

### 13.2 Adimlar

#### 13.2.1 Sistem Bagimliliklari

Gerekli komut satiri araclari kontrol edilir, eksik olanlar icin uyari verilir.

| Bagimlilik      | Zorunluluk | Aciklama                              |
|-----------------|------------|---------------------------------------|
| git             | Zorunlu    | Repo yonetimi                         |
| curl            | Zorunlu    | HTTP istekleri (borsa + supabase)      |
| jq              | Zorunlu    | JSON parse (supabase + adaptor)        |
| docker          | Opsiyonel  | Supabase icin gerekli                  |
| docker compose  | Opsiyonel  | Supabase icin gerekli                  |
| python3 (3.10+) | Opsiyonel  | MCP sunucusu icin gerekli              |

Zorunlu bagimliliklar eksikse betik hata verir ve durur.
Opsiyonel bagimliliklar eksikse uyari yazar ama devam eder.

**Ornek kontrol mantigi:**

```bash
kontrol_et() {
    local komut="$1"iz
    if ! command -v "$komut" &>/dev/null; then
        echo "HATA: '$komut' bulunamadi. Kurun: sudo apt install $komut"
        return 1
    fi
}
```

#### 13.2.2 Dotfiles Dizin Baglantisi

.bashrc icinde `DOTFILES_DIZIN="$HOME/dotfiles"` sabit kodlu oldugu icin
repo `$HOME/dotfiles` konumunda olmalidir.

- Repo zaten `$HOME/dotfiles` konumundaysa: islem yapma, atla.
- Repo baska bir konumdaysa (orn: `~/Masaustu/dotfiles`):
  `$HOME/dotfiles` olarak sembolik link olustur.
- `$HOME/dotfiles` zaten varsa ve baska bir yere isaret ediyorsa:
  uyari ver, kullanicidan teyit al.

```bash
# Sembolik link olusturma mantigi
repo_dizin="$(cd "$(dirname "$0")" && pwd)"
hedef="$HOME/dotfiles"
if [ "$repo_dizin" != "$hedef" ]; then
    ln -sfn "$repo_dizin" "$hedef"
fi
```

#### 13.2.3 Bashrc Yukleme

Mevcut `$HOME/.bashrc` dosyasi yedeklenir ve repo icindeki `.bashrc` ile degistirilir.

- `$HOME/.bashrc` zaten repo dosyasiyla ayni icerikse: atla.
- Farkliysa: `$HOME/.bashrc.yedek.TARIH` olarak yedekle, sonra kopyala.
- Sembolik link yerine kopyalama tercih edilir (bazi sistemler login sirasinda
  sembolik linki takip etmekte sorun yasayabilir).

```bash
if ! diff -q "$repo_dizin/.bashrc" "$HOME/.bashrc" &>/dev/null; then
    cp "$HOME/.bashrc" "$HOME/.bashrc.yedek.$(date +%Y%m%d%H%M%S)"
    cp "$repo_dizin/.bashrc" "$HOME/.bashrc"
fi
```

#### 13.2.4 Python Ortami (MCP Sunucusu)

MCP sunucusu Python 3.10+ ve `mcp[cli]` paketine ihtiyac duyar.

- `python3 --version` kontrol edilir. 3.10'dan dusukse uyari verilir.
- `bashrc.d/mcp_sunucular/.venv` klasoru yoksa olusturulur.
- `.venv` icine `pip install -e .` ile bagimliliklar kurulur
  (pyproject.toml dosyasi zaten mevcut).

```bash
mcp_dizin="$repo_dizin/bashrc.d/mcp_sunucular"
if [ -f "$mcp_dizin/pyproject.toml" ] && command -v python3 &>/dev/null; then
    if [ ! -d "$mcp_dizin/.venv" ]; then
        python3 -m venv "$mcp_dizin/.venv"
        "$mcp_dizin/.venv/bin/pip" install -e "$mcp_dizin"
    fi
fi
```

#### 13.2.5 Supabase Kurulumu

veritabani/ klasoru varsa Supabase yerel kurulumu yapilir.

- Docker ve Docker Compose kontrolu yapilir. Yoksa uyari verilir ve bu adim atlanir.
- `.env` dosyasi yoksa `.env.ornek` kopyalanarak olusturulur.
- `.env` dosyasi olusturuldugunda rastgele JWT_SECRET uretilir (openssl rand).
- `docker compose up -d` calistirilarak konteynerler ayaga kaldirilir.
- Konteynerlerin saglikli (healthy) olmasini bekler (maks 60 saniye).
- PostgREST'e baglanti testi yapilir (curl localhost:8001).

```bash
vt_dizin="$repo_dizin/bashrc.d/borsa/veritabani"
if [ -f "$vt_dizin/docker-compose.yml" ]; then
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        if [ ! -f "$vt_dizin/.env" ]; then
            cp "$vt_dizin/.env.ornek" "$vt_dizin/.env"
            # Rastgele JWT secret uret
            jwt_secret="$(openssl rand -base64 32)"
            sed -i "s|JWT_SECRET=.*|JWT_SECRET=$jwt_secret|" "$vt_dizin/.env"
        fi
        cd "$vt_dizin" && docker compose up -d
    else
        echo "UYARI: Docker bulunamadi. Supabase kurulmadi."
        echo "Supabase icin: sudo apt install docker.io docker-compose-v2"
    fi
fi
```

#### 13.2.6 Hassas Dosya Izinleri

Sifre ve anahtar iceren dosyalar sadece sahibi tarafindan okunabilir olmalidir.

```bash
# 600 izni verilecek dosyalar
hassas_dosyalar=(
    "$vt_dizin/.env"
    "$repo_dizin/bashrc.d/borsa/veritabani/supabase.ayarlar.sh"
    "$repo_dizin/bashrc.d/borsa/adaptorler/ziraat.ayarlar.sh"
)
for dosya in "${hassas_dosyalar[@]}"; do
    [ -f "$dosya" ] && chmod 600 "$dosya"
done
```

#### 13.2.7 Gitignore Kontrolu

`.gitignore` dosyasinda hassas dosyalarin listelendigini dogrular.

Olmasi gereken satirlar:

```
.env
*.ayarlar.sh
```

Eksik satirlar varsa otomatik olarak eklenir.

#### 13.2.8 Dogrulama ve Ozet

Betik sonunda tum adimlarin durumunu ozetleyen bir tablo yazdirir.

```
=== Kurulum Ozeti ===
[TAMAM]  Sistem bagimliliklari (git, curl, jq)
[TAMAM]  Dotfiles baglantisi ($HOME/dotfiles)
[TAMAM]  Bashrc yuklendi
[TAMAM]  Python ortami (.venv)
[UYARI]  Supabase kurulmadi (Docker yok)
[TAMAM]  Dosya izinleri ayarlandi
[TAMAM]  Gitignore guncellendi

Kurulum tamamlandi. "source ~/.bashrc" ile fonksiyonlar yukleniyor...
```

### 13.3 Tasarim Ilkeleri

- **Idempotent**: Betik kac kere calistirilirsa calistirilsin sonuc aynidir.
  Zaten yapilmis adimlar tekrar yapilmaz.
- **Yumusak basarisizlik**: Opsiyonel adimlarin basarisizligi betigi durdurmaz.
  Zorunlu adimlarin basarisizligi betigi durdurur.
- **Sessiz varsayilan**: Betik varsayilan olarak sadece onemli mesajlari gosterir.
  `-v` (verbose) parametresi ile her adimin detayi gosterilir.
- **Kullanici teyidi**: Mevcut dosyalarin ustune yazma durumlarinda kullanicidan
  teyit alinir. `-e` (evet-hepsine) parametresi ile teyitsiz calisir.
- **Sifir bagimlilik**: kur.sh dosyasi sadece bash ve coreutils gerektirir.
  Hicbir harici paket olmadan calisabilir (kontrol fonksiyonlari harici paket
  gerektirmez, sadece kurulum asamalari gerektirir).

### 13.4 Dosya Konumu

```
dotfiles/               # Repo koku
  kur.sh                # Otomatik kurulum betigi
  .bashrc               # Bash yapilandirmasi
  .gitignore            # Git dislamalari
  bashrc.d/             # Moduler yapilandirma dosyalari
    ...
```

kur.sh repo kokunde bulunur ve `bash kur.sh` ile calistirilir.
Betik kendi konumunu `$0` ile tespit eder, mutlak yol gerektirmez.

## 14. Bilinen Sorunlar ve Riskler

Bu bolum mevcut kod ile plan arasindaki uyumsuzluklari, eksik tanimlari ve
kodlamaya baslandiginda hata cikarabilecek noktalari listeler.
Her sorun oncelik seviyesine gore siniflandirilmistir.

### 14.1 Kritik Sorunlar

Kodlamaya baslanmadan once cozulmesi gereken sorunlar.
Bu sorunlar cozulmezse sistem calisma zamaninda bozulur.

#### 14.1.1 ADAPTOR_ADI readonly Carpmasi

**Dosya:** adaptorler/ziraat.sh satir 10
**Sorun:** `readonly ADAPTOR_ADI="ziraat"` ifadesi ilk source'da set ediliyor.
`borsa()` fonksiyonu her cagrildiginda adaptor dosyasini tekrar source ediyor
(cekirdek.sh satir 774). Eger kullanici ardisik iki farkli kurum cagirirsa:

```
borsa ziraat bakiye       # ADAPTOR_ADI="ziraat" readonly olarak set
borsa garanti bakiye      # garanti.sh source edilir ama ADAPTOR_ADI readonly
                          # "ziraat" olarak kalir, garanti ASLA atanamaz
```

**Etki:** Coklu kurum destegi tamamen bozulur. Ikinci kurum birinci kurumun
kimligiyle calisir.

**Cozum secenekleri:**
1. `readonly` yerine normal degisken kullan (her source'da ustune yazilir).
2. Adaptor fonksiyonlarini bir alt kabukta (subshell) calistir.
3. Adaptor yukleme sirasinda onceki degiskenleri temizle (unset).

**Hangi asamada cozulmeli:** Asama 1'den once (mevcut kodda zaten sorun).

#### 14.1.2 Supabase JWT Token Uretimi

**Dosya:** Bolum 13.2.5 (kur.sh Supabase kurulumu)
**Sorun:** Plan sadece `JWT_SECRET` icin `openssl rand` ile rastgele deger
uretiyor. Ancak `ANON_KEY` ve `SERVICE_ROLE_KEY` rastgele string degildir —
bunlar `JWT_SECRET` ile **imzalanmis JWT tokenlaridir**.

```
JWT_SECRET  = rastgele string (openssl rand -base64 32)     <- dogru
ANON_KEY    = JWT_SECRET ile imzalanmis, role=anon JWT       <- uretilmeli
SERVICE_KEY = JWT_SECRET ile imzalanmis, role=service JWT    <- uretilmeli
```

Sadece JWT_SECRET degistirip ANON_KEY'i eski .env.ornek'ten kopyalamak
PostgREST'in tum istekleri reddetmesine yol acar (imza dogrulanamaz).

**Cozum secenekleri:**
1. .env.ornek'teki JWT_SECRET, ANON_KEY ve SERVICE_KEY uyumlu olarak birakilir
   (hepsi varsayilan deger). Guvenlik yerel oldugu icin kabul edilebilir.
2. kur.sh icinde yeni JWT_SECRET uretilir ve bu secret ile yeni JWT tokenlar
   olusturulur. Bunun icin `python3 -c "import jwt; ..."` veya baska bir
   JWT araci gerekir — sifir bagimlilik ilkesiyle celisir.

**Onerilen cozum:** Secenek 1. Yerel Supabase icin varsayilan anahtarlari
oldugu gibi kullanmak guvenlidir cunku dis ag erisimi yoktur. .env.ornek
icinde uyumlu uc deger sabit olarak bulunur, kur.sh bunlari kopyalar.

**Hangi asamada cozulmeli:** Asama 3 (Veritabani Altyapisi).

#### 14.1.3 SQL Migration Stratejisi Tanimlanmamis

**Dosya:** Bolum 11.5 (tablo yapilari), Bolum 12.3 (yol haritasi)
**Sorun:** Planda 7 tablo tanimlanmis ama su sorulara cevap yok:

- Tablolar nasil olusturulacak? SQL dosyasi mi, Studio'dan manuel mi?
- kur.sh tabloları otomatik olusturacak mi?
- Tablo semasi degistiginde migration nasil yapilacak?
- `veritabani/` klasorunde bir `sema.sql` dosyasi olmali.

**Cozum:** veritabani/ klasorune `sema.sql` dosyasi eklenir. Tum CREATE TABLE
ifadeleri bu dosyada bulunur. kur.sh Supabase ayaga kalktiktan sonra bu
dosyayi PostgREST uzerinden veya dogrudan psql ile calistirir.

```
veritabani/
  docker-compose.yml
  .env.ornek
  .env
  sema.sql              # Tum tablo tanimlari (CREATE TABLE IF NOT EXISTS)
  supabase.sh
  supabase.ayarlar.sh
```

Migration icin basit yaklasim: `CREATE TABLE IF NOT EXISTS` kullanmak.
Tablo zaten varsa atlar, yoksa olusturur. Kolon ekleme gibi degisiklikler
icin ayri migration dosyalari yazilabilir (ileride).

**Hangi asamada cozulmeli:** Asama 3 (Veritabani Altyapisi).

#### 14.1.4 borsa() Fonksiyonuna Yeni Komut Yonlendirmesi

**Dosya:** cekirdek.sh satir 635-834
**Sorun:** Mevcut `borsa()` fonksiyonu her zaman `borsa <kurum> <komut>` seklinde
kurum bekliyor. Plan su kurumsuz komutlari tanimliyor:

```
borsa gecmis emirler 10         # kurum yok, genel sorgu
borsa mutabakat ziraat 111111   # kurum var ama farkli format
borsa kurallar seans             # zaten calisiyor (kurallar ozel case)
```

`gecmis` ve `mutabakat` icin mevcut yonlendirme mantigi calismaz cunku
bu kelimeleri kurum adi olarak yorumlar ve adaptor dosyasi arar.

**Cozum:** `borsa()` fonksiyonunun basina kurumsuz komutlar icin on-kontrol
eklenir (kurallar icin yapildigi gibi):

```bash
case "$kurum" in
    kurallar) ... ;;        # zaten var
    gecmis)   ... ;;        # YENi: vt_* fonksiyonlarini cagir
    mutabakat) ... ;;       # YENi: vt_mutabakat_kontrol cagir
    *) # normal kurum yonlendirmesi
esac
```

**Hangi asamada cozulmeli:** Asama 9 (Veritabani Okuma ve Raporlama).

### 14.2 Onemli Sorunlar

Sistemin calismasini engellemez ama veri kaybi veya tutarsizliga yol acabilir.
Ilgili asama kodlanirken cozulmesi gerekir.

#### 14.2.1 Dosya Onbellek Yaris Kosulu (Race Condition)

**Dosya:** Bolum 9.3.1 (dosya onbellegi)
**Sorun:** 5 robot ayni anda THYAO fiyatini soruyor ve onbellek suresi dolmus.
Hepsi ayni anda `/tmp/borsa/_veri_onbellek/THYAO.dat` dosyasina yazmayi deniyor.
Yari-yazilmis dosyanin okunmasi bozuk veri dondurur.

**Cozum:** `flock` (dosya kilidi) mekanizmasi kullanilir:

```bash
(
    flock -n 200 || return 0   # kilit alinamadiysa onbellektekini kullan
    # taze veri cek ve dosyaya yaz
    echo "$epoch|$fiyat|$tavan|$taban|$degisim|$seans" > "$onbellek_dosyasi"
) 200>"$onbellek_dosyasi.lock"
```

**Hangi asamada cozulmeli:** Asama 6 (Veri Kaynagi Altyapisi).

#### 14.2.2 bist_pazar_emir_kontrol() Hic Cagrilmiyor

**Dosya:** kurallar/bist.sh satir 938-975
**Sorun:** YAKIN pazarinda PIYASA emri yasagi, KIE/GIE/TAR emir suresi yasagi,
aciga satis yasagi gibi kurallar `bist_pazar_emir_kontrol()` fonksiyonunda
tanimlanmis. Ancak `adaptor_emir_gonder()` sadece `bist_emir_dogrula()`
cagiriyor — bu fonksiyon yalnizca fiyat adimi kontrolu yapiyor.

Sonuc: YAKIN pazarindaki bir hisseye PIYASA emri gonderilebilir, sunucu
reddedocektir ama kullaniciya onceden uyari verilmez.

**Cozum:** `bist_emir_dogrula()` fonksiyonuna pazar kontrolu eklenir veya
adaptor icinden ayrica `bist_pazar_emir_kontrol()` cagrilir.

**Hangi asamada cozulmeli:** Asama 5 (Veri Cekme) ile birlikte.

#### 14.2.3 Veritabani Tablolarinda Index Tanimlari Yok

**Dosya:** Bolum 11.5 (tablo yapilari)
**Sorun:** 7 tablonun semasi tanimlanmis ama hicbirinde index yok. Sik
yapilacak sorgular icin index olmadan performans dusecek:

```sql
-- Bu sorgular index olmadan buyuk tablolarda yavaslar:
WHERE sembol = 'THYAO' ORDER BY zaman DESC          -- fiyat_gecmisi
WHERE kurum = 'ziraat' AND hesap = '111111'          -- emirler, bakiye_gecmisi
WHERE referans_no = 'ABC123'                         -- emirler
```

**Cozum:** sema.sql dosyasina indexler eklenir:

```sql
CREATE INDEX idx_fiyat_gecmisi_sembol_zaman ON fiyat_gecmisi(sembol, zaman DESC);
CREATE INDEX idx_emirler_kurum_hesap ON emirler(kurum, hesap);
CREATE INDEX idx_emirler_referans ON emirler(referans_no);
CREATE INDEX idx_bakiye_gecmisi_kurum_hesap ON bakiye_gecmisi(kurum, hesap, zaman DESC);
CREATE INDEX idx_pozisyonlar_kurum_sembol ON pozisyonlar(kurum, hesap, sembol);
```

**Hangi asamada cozulmeli:** Asama 3 (sema.sql yazilirken).

#### 14.2.4 Robot Sinyal Mekanizmasi Belirsiz

**Dosya:** Bolum 9.6 (tam senaryo)
**Sorun:** Veri kaynagi tamamen dusunce plan "Robotlara sinyal: VERI_YOK" diyor.
Ama robotlar **ayri proseslerdir** — bir prosesin baska proseslere nasil
sinyal gonderecebi tanimlanmamis.

**Cozum secenekleri:**
1. Dosya bayraklari: `/tmp/borsa/_veri_durum` dosyasina "YOK" yazilir,
   robotlar her turda bu dosyayi kontrol eder.
2. Unix sinyalleri: `kill -USR1 $robot_pid` ile robotlara bildirim.
3. Named pipe (FIFO): Robotlar bir pipe'i dinler.

**Onerilen cozum:** Dosya bayraklari (secenek 1). En basit, en guvenilir,
Bash ile dogal uyumlu. Robotlar zaten her turda dosya okuyorlar (onbellek).

**Hangi asamada cozulmeli:** Asama 6-7 (Veri Kaynagi + Robot Motoru).

#### 14.2.5 supabase.ayarlar.sh Uretimi Tanimlanmamis

**Dosya:** Bolum 11.4, Bolum 13.2.5
**Sorun:** Plan `.env.ornek -> .env` kopyalamayi tanimliyor ama
`supabase.ayarlar.sh` dosyasinin nasil uretilecebi belli degil. Icindeki
`_SUPABASE_ANAHTAR` degeri `.env` dosyasindaki `ANON_KEY` ile ayni olmali.

**Cozum:** kur.sh icinde `.env` dosyasi olusturulduktan sonra ayni dosyadan
ANON_KEY okunup `supabase.ayarlar.sh` otomatik uretilir:

```bash
anon_key=$(grep "^ANON_KEY=" "$vt_dizin/.env" | cut -d= -f2)
cat > "$vt_dizin/supabase.ayarlar.sh" << EOF
# shellcheck shell=bash
_SUPABASE_URL="http://localhost:8001"
_SUPABASE_ANAHTAR="$anon_key"
EOF
chmod 600 "$vt_dizin/supabase.ayarlar.sh"
```

**Hangi asamada cozulmeli:** Asama 3 (Veritabani Altyapisi).

#### 14.2.6 Strateji Arayuzu Belirsiz

**Dosya:** Bolum 10.2, Bolum 12.8
**Sorun:** Plan `strateji_baslat` ve `strateji_degerlendir` fonksiyonlarini
anlatyor ama asagidaki sorulara cevap yok:

- Bu fonksiyonlar hangi parametreleri alir?
- Ne dondurur? (ALIS/SATIS/BEKLE string mi, return kodu mu, array mi?)
- Strateji dosyasi nasil bir formatta yazilir? (source edilen .sh mi?)
- Birden fazla sembol icin tek karar mi yoksa sembol basina karar mi?
- Strateji kendi durumunu (state) nereye kaydeder?

**Cozum:** Asama 8 kodlanirken strateji arayuz sozlesmesi detayli
olarak tanimlanir. Asagidaki ornek sablon belirlenir:

```bash
# strateji/ornek.sh
strateji_baslat() {
    # Strateji baslangic ayarlari
}
strateji_degerlendir() {
    local sembol="$1" fiyat="$2" hacim="$3"
    # Karar mantigi
    echo "BEKLE"   # veya "ALIS 100 312.50" veya "SATIS 50"
}
```

**Hangi asamada cozulmeli:** Asama 8 (Strateji Katmani).

### 14.3 Orta Sorunlar

Sistemin isleyisini dogrudan etkilemez ama kod kalitesi ve
surdurulebilirlik icin ele alinmasi gereken konular.

#### 14.3.1 KURU_CALISTIR Modu Robot Icin Planlanmamis

**Dosya:** adaptorler/ziraat.sh (mevcut: emir ve halka arz icin var)
**Sorun:** Mevcut kodda `KURU_CALISTIR=1` ortam degiskeni ile emir
gondermeden test modu var. Robot motorunun da bu modu desteklemesi
gerekir — gercek parayla test etmeden strateji dogrulama icin kritik.

**Cozum:** Robot baslatma fonksiyonuna `--kuru` parametresi eklenir:

```bash
robot_baslat --kuru ziraat 111111 strateji_a.sh
# Tum dongu calisir ama emirler KURU_CALISTIR=1 ile gonderilir
# Log'a "KURU: THYAO ALIS 100 lot 312.50 TL" yazilir
```

**Hangi asamada cozulmeli:** Asama 7 (Robot Motoru).

#### 14.3.2 Tab Tamamlama Guncelleme Plani Eksik

**Dosya:** tamamlama.sh (91 satir)
**Sorun:** Mevcut tamamlama sadece 9 komutu biliyor: giris, bakiye,
portfoy, emir, emirler, iptal, hesap, hesaplar, arz. Yeni komutlar
(fiyat, gecmis, mutabakat, robot_baslat vb.) eklendikce tamamlama
da guncellenmeli. Yol haritasinda buna ozel bir adim yok.

**Cozum:** Her asama icin tamamlama guncellemesi kontrol listesine eklenir.
Yeni fonksiyonlar eklendikce `_borsa_tamamla()` fonksiyonu da guncellenir.

**Hangi asamada cozulmeli:** Her asamanin sonunda.

#### 14.3.3 Log Dosyasi Rotasyonu Planlanmamis

**Dosya:** /tmp/borsa/ altindaki debug dosyalari
**Sorun:** Robot uzun sure (gunler, haftalar) calistikca debug_portfolio.html,
emir_yanit.html, curl.log gibi dosyalar birikir. Disk dolabilir.

**Cozum:** Robot motoruna periyodik log temizligi eklenir:
- 7 gunden eski debug dosyalari silinir.
- Log boyutu belirli bir esigi asarsa rotasyon yapilir.
- `find /tmp/borsa -name "*.html" -mtime +7 -delete` gibi basit temizlik.

**Hangi asamada cozulmeli:** Asama 7 (Robot Motoru).

#### 14.3.4 docker-compose.yml Icerigi Tanimlanmamis

**Dosya:** Bolum 11.2.2, Bolum 12.3
**Sorun:** Plan "Supabase resmi docker-compose.yml'den sadeletirilir" diyor
ama hangi servislerin kalacagini, port eslemelerini, volume tanimlarini
ve ortam degiskenlerini belirtmiyor.

**Cozum:** Asama 3 kodlanirken docker-compose.yml icerigi su servisleri
icerecek sekilde olusturulur:

| Servis | Port | Zorunlu |
|--------|------|---------|
| PostgreSQL | 5433:5432 | Evet |
| PostgREST | 3000 (dahili) | Evet |
| Kong | 8001:8000 | Evet |
| GoTrue | 9999 (dahili) | Evet (PostgREST bagimli) |
| Realtime | 4000 (dahili) | Hayir (ileride) |
| Studio | 3002:3000 | Opsiyonel |
| Storage | kapal | Hayir |

Volume: PostgreSQL verisi icin named volume (docker compose down -v
yapilmadikca veri korunur).

**Hangi asamada cozulmeli:** Asama 3 (Veritabani Altyapisi).

#### 14.3.5 borsa() Her Cagrildiginda Adaptoru Tekrar Source Ediyor

**Dosya:** cekirdek.sh satir 774
**Sorun:** `source "$surucu_dosyasi"` — her `borsa ziraat xxx` cagrisinda
ziraat.sh'in tamami (1999 satir) tekrar parse ediliyor. Bu:
- Performans icin gereksiz (~2000 satirlik dosya her seferinde parse)
- readonly carpismasi riskini artirir (14.1.1)

Avantaj: Adaptor kodunda yapilan degisiklik hemen yururluge girer.

**Cozum secenekleri:**
1. `_CEKIRDEK_SON_YUKLENEN_ADAPTOR` degiskeni ile kontrol: ayni adaptor
   tekrar source edilmez, farkli adaptorse once unset yapilir.
2. Mevcut haliyle birakilir (basitlik), readonly sorunu ayrica cozulur.

**Hangi asamada cozulmeli:** Asama 1 (Oturum Altyapisi) sirasinda
readonly sorunu cozulurken birlikte ele alinabilir.

### 14.4 Sorun Ozet Tablosu

| No | Oncelik | Sorun | Asama |
|----|---------|-------|-------|
| 14.1.1 | Kritik | ADAPTOR_ADI readonly carpmasi | Asama 1 oncesi |
| 14.1.2 | Kritik | JWT token uretimi | Asama 3 |
| 14.1.3 | Kritik | SQL migration stratejisi yok | Asama 3 |
| 14.1.4 | Kritik | borsa() yeni komut yonlendirmesi | Asama 9 |
| 14.2.1 | Onemli | Dosya onbellek race condition | Asama 6 |
| 14.2.2 | Onemli | bist_pazar_emir_kontrol cagrilmiyor | Asama 5 |
| 14.2.3 | Onemli | Index tanimlari yok | Asama 3 |
| 14.2.4 | Onemli | Robot sinyal mekanizmasi belirsiz | Asama 6-7 |
| 14.2.5 | Onemli | supabase.ayarlar.sh uretimi | Asama 3 |
| 14.2.6 | Onemli | Strateji arayuzu belirsiz | Asama 8 |
| 14.3.1 | Orta | KURU_CALISTIR robot destegi | Asama 7 |
| 14.3.2 | Orta | Tab tamamlama guncelleme plani | Her asama |
| 14.3.3 | Orta | Log dosyasi rotasyonu | Asama 7 |
| 14.3.4 | Orta | docker-compose.yml icerigi | Asama 3 |
| 14.3.5 | Orta | Adaptor tekrar source edilmesi | Asama 1 |
