# Dotfiles - Kullanim Egitim Rehberi

Bu belge, dotfiles projesindeki tum modulleri, komutlari ve kullanim senaryolarini A'dan Z'ye kapsamli olarak anlatir. Cikti alinmaya uygun profesyonel formatta hazirlanmistir.

Tarih: Subat 2026


## 1. Projeye Genel Bakis

Bu dotfiles projesi, Linux masaustu ortaminda gunluk islemleri terminalden hizlica yonetmek icin tasarlanmis bir arac setidir. Dort ana modulden olusur:

| Modul | Dosya | Islem Alani |
|-------|-------|-------------|
| Genel Ayarlar | 01-genel.sh | Terminal gorunumu, renkler, alias tanimlari |
| Yazdirma | 02-yazdir.sh | PDF ve Markdown dosyalarini yaziciya gonderme |
| Zamanlayici | 03-zamanlayici.sh | Geri sayim, alarm ve zamanlayici yonetimi |
| Borsa | borsa/ | Araci kurum hesap yonetimi, BIST kurallari, robot, backtest |

Tum dosyalar `bashrc.d/` klasoru altinda bulunur ve `~/.bashrc` araciligiyla otomatik yuklenir.


## 2. Kurulum

### 2.1 Hizli Kurulum

Projeyi kurmak icin tek komut yeterlidir:

```
bash kur.sh
```

### 2.2 Kurulum Bayraklari

| Bayrak | Aciklama |
|--------|----------|
| `-v` veya `--verbose` | Ayrintili cikti gosterir |
| `-e` veya `--evet` | Tum teyit sorularini atlar (otomatik kurulum) |

### 2.3 Kurulum Adimlari

Kurulum betigi asagidaki adimlari sirasiya uygular:

1. Sistem bagimliliklari kontrolu (git, curl, jq, docker, python3)
2. Dotfiles dizin baglantisi (`~/dotfiles` symlink)
3. `.bashrc` dosyasinin guncellenmesi
4. Python sanal ortami olusturma (MCP sunucusu icin)
5. Supabase veritabani kurulumu (Docker ile)
6. Hassas dosya izinlerinin ayarlanmasi (chmod 600)
7. `.gitignore` kontrolu

### 2.4 Sistem Gereksinimleri

**Zorunlu:**
- git
- curl

**Opsiyonel (modullere gore):**
- jq (Supabase islemleri icin)
- docker ve docker-compose (veritabani icin)
- python3 (3.10+, MCP sunucusu icin)
- pdfjam (yazdirma icin)
- google-chrome (Markdown PDF donusumu icin)
- zenity (GUI zamanlayici icin)
- xdotool (pencere konumlandirma icin)
- bc (matematik islemler icin)
- paplay (alarm sesi icin)
- notify-send (masaustu bildirimleri icin)


## 3. Genel Terminal Ayarlari (01-genel.sh)

Bu dosya terminali actiginizda otomatik olarak yuklenir ve temel calisma ortamini hazirlar.

### 3.1 Gecmis (History) Ayarlari

| Ayar | Deger | Aciklama |
|------|-------|----------|
| HISTCONTROL | ignoreboth | Tekrar eden ve boslukla baslayan satirlari gecmise yazmaz |
| HISTSIZE | 1000 | Bellekte tutulan gecmis satir sayisi |
| HISTFILESIZE | 2000 | Dosyada tutulan gecmis satir sayisi |
| histappend | acik | Gecmis dosyasina ekler, uzerine yazmaz |

### 3.2 Renk Ayarlari ve Alias Tanimlari

Terminalde renkli cikti icin su alias'lar otomatik tanimlidir:

| Alias | Aciklama |
|-------|----------|
| `ls` | Renkli dosya listesi |
| `ll` | Uzun formatta dosya listesi (`ls -l`) |
| `la` | Gizli dosyalar dahil liste (`ls -A`) |
| `l` | Kisaltilmis liste (`ls -CF`) |
| `grep` | Renkli metin arama |
| `diff` | Renkli fark gosterimi |
| `ip` | Renkli ag bilgisi |
| `joplin` | Joplin CLI, masaustu profili ile |

### 3.3 Prompt (Komut Satiri Gorunumu)

Terminal iki satirli Kali tarzinda gorunur:

```
+--(kullanici@makine)-[~/dizin]
+-$ _
```

Prompt degiskenleri:

| Degisken | Deger | Aciklama |
|----------|-------|----------|
| PROMPT_ALTERNATIVE | twoline | Iki satirli prompt |
| NEWLINE_BEFORE_PROMPT | yes | Her komut oncesi bos satir |


## 4. Yazdirma Modulu (02-yazdir.sh)

HP DeskJet 2540 yazicisi icin optimize edilmis arkalionlu (duplex) baski araci.

### 4.1 Temel Kullanim

```
yazdir [SECENEK] "dosya" aralik
```

### 4.2 Desteklenen Dosya Turleri

| Uzanti | Islem |
|--------|-------|
| `.pdf` | Dogrudan yaziciya gonderilir |
| `.md` / `.markdown` | Otomatik olarak HTML uzerinden PDF'e cevrilir |

### 4.3 Secenekler

| Secenek | Aciklama |
|---------|----------|
| `-r` veya `--renkli` | Renkli baski (RGB modu) |
| `-s` veya `--siyahbeyaz` | Siyah-beyaz baski (varsayilan, ekonomik) |
| `-h` veya `--yardim` | Yardim mesajini gosterir |

### 4.4 PDF Dosyalari icin Sayfa Araligi

PDF dosyalarinda aralik her zaman sayfa numarasini ifade eder.

| Ornek | Aciklama |
|-------|----------|
| `5-10` | Sayfa 5'ten 10'a kadar |
| `157,159` | Sadece sayfa 157 ve 159 |
| `3,7,12-15` | Sayfa 3, 7 ve 12-15 arasi |

### 4.5 Markdown Dosyalari icin Aralik Tipleri

Markdown dosyalarinda aralik varsayilan olarak SATIR numarasini ifade eder.

| Aralik | Anlami | Aciklama |
|--------|--------|----------|
| `tumu` | Tum dosya | Tum satirlar PDF'e cevrilip basilir |
| `hepsi` | Tum dosya | `tumu` ile ayni |
| `10-85` | Satir 10-85 | Varsayilan: satir araligi |
| `satir:10-85` | Satir 10-85 | Acik belirtme ile satir araligi |
| `sayfa:1-3` | Sayfa 1-3 | PDF'e cevrildikten sonra sayfa araligi |

### 4.6 Ornek Komutlar

**PDF yazdirma:**

```
yazdir "kitap.pdf" 1-20
```
20 sayfayi siyah-beyaz yazdirir.

```
yazdir -r "harita.pdf" 5-8
```
4 sayfayi renkli yazdirir.

**Markdown yazdirma:**

```
yazdir "plan.md" tumu
```
Tum Markdown dosyasini PDF'e cevirip yazdirir.

```
yazdir "plan.md" 1-50
```
Markdown dosyasinin ilk 50 satirini yazdirir.

```
yazdir -r "notlar.md" satir:30-80
```
30-80 arasi satirlari renkli yazdirir.

```
yazdir "notlar.md" sayfa:1-3
```
PDF'e cevrildikten sonra 1-3 sayfalarini yazdirir.

### 4.7 Yazdirma Sureci (Arkalionlu Baski)

Yazdirma islemi su adimlarda gerceklesir:

1. PDF hazirlama: `pdfjam` ile 2 sayfa/A4 yatay duzende birlestirme
2. On yuzlerin yazdirilmasi (tek numarali A4 sayfalari)
3. Kullanicidan kagitlari ters cevirip tepsiye koymasi istenir
4. Arka yuzlerin yazdirilmasi (cift numarali A4 sayfalari)

Tek kagitlik baskilarda arka yuz adimi atlanir.


## 5. Zamanlayici Modulu (03-zamanlayici.sh)

Terminal tabanli alarm ve geri sayim araci. Tum zamanlayicilar arka planda calisir, terminal kapatilsa bile devam eder.

### 5.1 Yapilandirma Dosyalari

| Dosya/Dizin | Konum | Aciklama |
|-------------|-------|----------|
| Kayit dizini | `~/.zamanlayici/` | Alarm kayitlari ve PID dosyalari |
| Alarm kayitlari | `~/.zamanlayici/alarmlar.json` | Kayitli alarmlar (JSON) |
| Alarm sesi | `/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga` | Varsayilan ses dosyasi |

### 5.2 Geri Sayim (Countdown)

**Komut:** `gerisayim`

**Sure Formatlari:**

| Format | Ornek | Anlami |
|--------|-------|--------|
| Sadece sayi | `40` | 40 dakika |
| SA:DK:SN | `1:30:00` | 1 saat 30 dakika |
| DK:SN | `5:00` | 5 dakika |
| SA:DK:SN | `0:0:30` | 30 saniye |

**Secenekler:**

| Secenek | Aciklama |
|---------|----------|
| `-s` | Sessiz mod — sure dolunca ses calma |
| `-d` | Dongulu ses — kullanici durdurana kadar ses calsin |
| `-b` | Arka plan modu — terminal kapansa bile calisir |
| `-k KOMUT` | Sure dolunca belirtilen komutu calistir |
| `-t SAYI` | Sesi kac kez tekrarla (varsayilan: 1) |
| `-a SANIYE` | Ses tekrarlari arasi bekleme suresi (varsayilan: 3 sn) |
| `-i ISIM` | Zamanlayiciya isim ver |

**Ornek Komutlar:**

```
gerisayim 40
```
40 dakika geri sayim (terminalde canli ilerleme cubugu).

```
gerisayim 1:30:00
```
1 saat 30 dakika geri sayim.

```
gerisayim 0:0:30
```
30 saniye geri sayim.

```
gerisayim 5 -d
```
5 dakika sonra kullanici durdurana kadar ses cal.

```
gerisayim 5 -s
```
5 dakika sessiz geri sayim (sadece bildirim gonderir).

```
gerisayim 5 -k "echo 'Bitti!'"
```
5 dakika sonra belirtilen komutu calistir.

```
gerisayim 5 -t 3 -a 5
```
5 dakika sonra sesi 3 kez, 5'er saniye arayla tekrarla.

```
gerisayim 40 -b
```
40 dakika arka planda geri sayim — terminal kapatilsa bile calisir.

### 5.3 Alarm (Belirli Saatte)

**Komut:** `alarm`

Alarm her zaman otomatik olarak arka planda calisir. Terminal kapatilsa bile calismaya devam eder.

**Ornek Komutlar:**

```
alarm 14:30
```
Saat 14:30'da alarm calar.

```
alarm 14:30 -i "Ogle Yemegi"
```
14:30 alarmi "Ogle Yemegi" ismiyle.

```
alarm 08:00 -d
```
08:00'de dongulu ses (kullanici durdurana kadar).

```
alarm 14:30 -k "echo 'Toplanti!'"
```
14:30'da belirtilen komutu calistir.

**Onemli:** Belirtilen saat gecmisse, alarm otomatik olarak ertesi gune kurulur.

### 5.4 Alarm Yonetimi (Kaydet / Yukle / Listele / Sil)

**Kayitli alarm olusturma:**

```
alarm_kaydet "Cay Molasi" 0:3:00 -d
```
"Cay Molasi" isimli, 3 dakikalik, dongulu sesli bir alarm kaydeder.

```
alarm_kaydet "Toplanti" 14:30 -saat
```
"Toplanti" isimli saat alarmi kaydeder.

**Kayitli alarmlari listeleme:**

```
alarm_listele
```

Cikti ornegi:
```
============================================
  Kayitli Alarmlar
============================================
  [1] Cay Molasi       | Geri Sayim   | 0:3:00   | Ses: Dongulu
  [2] Toplanti         | Saat Alarmi  | 14:30    | Ses: Normal
============================================
  Toplam: 2 alarm
============================================
```

**Kayitli alarmi calistirma:**

```
alarm_calistir 1
```
Listeden 1 numarali alarmi calistirir.

```
alarm_calistir "Cay Molasi"
```
Ismiyle de calistirilabilir.

**Alarm silme:**

```
alarm_sil 1
```
1 numarali alarmi siler.

```
alarm_sil hepsi
```
Tum alarmlari siler.

### 5.5 Aktif Zamanlayici Yonetimi

**Calisanlari listeleme:**

```
aktif_listele
```

Cikti ornegi:
```
Aktif zamanlayicilar:
  PID: 12345
  PID: 12678
```

**Durdurma:**

```
zamanlayici_durdur 12345
```
Belirtilen PID'yi durdurur.

```
zamanlayici_durdur hepsi
```
Tum aktif zamanlayicilari durdurur.

### 5.6 GUI Modu (Zenity Penceresi)

`zamanlayici` komutu parametre ile cagrildiginda zenity penceresi acar:

```
zamanlayici 40
```
40 dakika GUI zamanlayici baslatir (ekranin sag ust kosesinde kucuk pencere).

```
zamanlayici 40 -i "KPSS"
```
"KPSS" baslikli GUI zamanlayici.

GUI penceresi:
- Terminal bagimsiz calisir
- Ilerleme cubugu gosterir
- Sure dolunca bildirim gonderir
- Sesi durdurmak icin "Sesi Durdur" butonu cikar

**Parametresiz cagrildiginda:**

```
zamanlayici
```
Tum komutlarin rehberini gosterir (yardim ekrani).


## 6. Borsa Modulu

Borsa modulu, Borsa Istanbul (BIST) Pay Piyasasi'nda islem yapmak icin terminalden araci kurum hesaplarini yonetir. Moduler adaptor mimarisi sayesinde farkli araci kurumlari ayni arayuzle kullanilir.

### 6.1 Ana Komut Yapisi

```
borsa <kurum> <komut> [argumanlar]
```

| Parametre | Aciklama |
|-----------|----------|
| `<kurum>` | Araci kurum adi (ornegin: ziraat) |
| `<komut>` | Yapilacak islem |
| `[argumanlar]` | Komuta ozgu ek parametreler |

### 6.2 Hesap Islemleri

**Giris yapma:**

```
borsa ziraat giris
```
Interaktif giris baslayir. (Guvenlik notu: giris islemleri terminalde yapilir, yapay zeka uzerinden parola gonderilmez.)

```
borsa ziraat giris -o
```
Giris yapar ve oturum koruma dongusunu baslatir (oturumun dusmesini onler).

**Aktif hesabi gorme:**

```
borsa ziraat hesap
```
Aktif hesap numarasini ve oturum durumunu gosterir.

**Baska hesaba gecis:**

```
borsa ziraat hesap 123456
```
123456 numarali hesaba gecer (daha once giris yapilmis olmalidir).

**Kayitli oturumlari listeleme:**

```
borsa ziraat hesaplar
```

Cikti ornegi:
```
=========================================
 KAYITLI OTURUMLAR (ziraat)
=========================================
 -> 123456           GECERLI
    789012           GECERSIZ
=========================================
 Toplam: 2 oturum
 -> = secili hesap
=========================================
```

**Oturumu kapatma:**

```
borsa ziraat cikis 123456
```
Oturumu kapatir, oturum korumayi durdurur.

### 6.3 Bakiye ve Portfoy Sorgulama

**Bakiye:**

```
borsa ziraat bakiye
```

Cikti ornegi:
```
=========================================
  ZIRAAT - PORTFOY OZETI
=========================================
 Nakit Bakiye  : 5,432.10 TL
 Hisse Senedi  : 12,345.67 TL
-----------------------------------------
 TOPLAM VARLIK : 17,777.77 TL
=========================================
```

**Portfoy detay (hisse bazinda):**

```
borsa ziraat portfoy
```

Cikti ornegi:
```
=========================================================================
  ZIRAAT - PORTFOY DETAY
=========================================================================
 Sembol        Lot    Son Fiy.    Piy. Deg.    Maliyet    Kar/Zarar   K/Z %
-------------------------------------------------------------------------
 THYAO         100      285.50     28,550.00   27,000.00    1,550.00   5.74
 AKBNK          50       45.80      2,290.00    2,100.00      190.00   9.05
=========================================================================
```

### 6.4 Emir Islemleri

**Alis emri:**

```
borsa ziraat emir THYAO alis 100 285.50
```
THYAO hissesinden 100 lot, 285.50 TL fiyatla alis emri gonderir.

**Satis emri:**

```
borsa ziraat emir THYAO satis 50 290.00
```
THYAO hissesinden 50 lot, 290.00 TL fiyatla satis emri gonderir.

**Piyasa emri:**

```
borsa ziraat emir THYAO alis 100 piyasa
```
Piyasa fiyatindan alis emri gonderir. (Piyasa emri, eslesme anindaki en iyi fiyattan islenir.)

**Emir parametreleri:**

| Parametre | Sira | Aciklama |
|-----------|------|----------|
| SEMBOL | 1 | Hisse sembol kodu (THYAO, AKBNK, GARAN...) |
| YON | 2 | `alis` veya `satis` |
| LOT | 3 | Adet (tam sayi) |
| FIYAT | 4 | TL fiyat veya `piyasa` |
| BILDIRIM | 5 (opsiyonel) | `mobil`, `eposta`, `hepsi` veya `yok` |

**Bekleyen emirleri listeleme:**

```
borsa ziraat emirler
```

**Emir iptal etme:**

```
borsa ziraat iptal <REFERANS_NO>
```

### 6.5 Halka Arz Islemleri

**Halka arz listesini gorme:**

```
borsa ziraat arz liste
```

**Taleplerinizi gorme:**

```
borsa ziraat arz talepler
```

**Talep gonderme:**

```
borsa ziraat arz talep <IPO_ADI> <LOT>
```

**Talep iptal etme:**

```
borsa ziraat arz iptal <TALEP_ID>
```

**Talep guncelleme:**

```
borsa ziraat arz guncelle <TALEP_ID> <YENI_LOT>
```

### 6.6 Fiyat Sorgulama

```
borsa ziraat fiyat THYAO
```
THYAO hissesinin guncel fiyat bilgisini gosterir.

### 6.7 Oturum Koruma

Araci kurum oturumlari belirli bir sure sonra duser. Oturum koruma dongusu, periyodik olarak sessiz istek atarak oturumu canli tutar.

**Giris sirasinda koruma baslatma:**

```
borsa ziraat giris -o
```

**Manuel durdurma:**

```
borsa ziraat oturum-durdur 123456
```

### 6.8 Coklu Hesap Yonetimi (Ust Seviye Fonksiyonlar)

Bu fonksiyonlar tum acik oturumlari tarayarak birlesik bilgi sunar:

**Tum bakiyeler:**

```
tum_bakiyeler
```

Cikti ornegi:
```
KURUM        HESAP           NAKIT          HISSE        TOPLAM
-------------------------------------------------------------------
ziraat       123456        5,432.10     12,345.67     17,777.77
-------------------------------------------------------------------
TOPLAM                     5,432.10     12,345.67     17,777.77
```

**Tum portfoyler:**

```
tum_portfoyler
```

**Tum emirler:**

```
tum_emirler
```

**Tum oturum durumlari:**

```
tum_oturumlar
```

Cikti ornegi:
```
KURUM        HESAP       KALAN    KORUMA  ROBOTLAR
-----------------------------------------------------------
ziraat       123456        845     AKTIF  YOK
```

**Gunluk ozet:**

```
gunluk_ozet
```
Oturumlar, bakiyeler ve gun sonu raporunu tek ekranda gosterir.


## 7. BIST Kurallari

BIST kural sorgulama fonksiyonlari, salt-okunur bilgi araclaridir. Gercek islem yapmazlar.

### 7.1 Seans Saatleri

```
borsa kurallar seans
```

BIST Pay Piyasasi gun ici seans yapisi:

| Baslangic | Bitis | Seans |
|-----------|-------|-------|
| 09:40 | 10:00 | Acilis seansi (emir toplama) |
| 10:00 | 12:40 | 1. Seans (surekli muzayede) |
| 12:40 | 14:00 | Ogle arasi (tek fiyat seansi) |
| 14:00 | 18:00 | 2. Seans (surekli muzayede) |
| 18:00 | 18:05 | Kapanis seansi (emir toplama) |
| 18:05 | 18:10 | Kapanis eslesmesi |

- Cumartesi ve Pazar: KAPALI
- Resmi tatiller: KAPALI
- Ramazan/Kurban Bayrami arifesi: Yari gun (sadece 1. seans)

**Anlik seans durumunu ogrenme:**

Seans tablosunun altinda otomatik olarak "Su an: ACIK/KAPALI" bilgisi gosterilir.

### 7.2 Fiyat Adim Tablosu

```
borsa kurallar fiyat
```

BIST'te fiyatlar belirli adimlarla hareket eder. Fiyat araligina gore gecerli adimlar:

| Fiyat Araligi (TL) | Fiyat Adimi (TL) |
|---------------------|-------------------|
| 0.01 - 19.99 | 0.01 |
| 20.00 - 49.99 | 0.02 |
| 50.00 - 99.99 | 0.05 |
| 100.00 - 249.99 | 0.10 |
| 250.00 - 499.99 | 0.25 |
| 500.00 - 999.99 | 0.50 |
| 1000.00 - 2499.99 | 1.00 |
| 2500.00 - ... | 2.50 |

Ornek: AKBNK fiyati 85.45 TL ise adim 0.05 TL'dir. 85.45, 85.50, 85.55 gecerlidir. 85.47 GECERSIZDIR.

**Belirli bir fiyatin adimini ogrenme:**

```
borsa kurallar adim 85.45
```
Cikti: `Fiyat: 85.45 TL -> Adim: 0.05 TL`

**Tavan fiyat hesaplama:**

```
borsa kurallar tavan 85.00
```
Cikti: `Kapanis: 85.00 TL -> Tavan: 93.50 TL`

**Taban fiyat hesaplama:**

```
borsa kurallar taban 85.00
```
Cikti: `Kapanis: 85.00 TL -> Taban: 76.50 TL`

### 7.3 Pazar Yapisi

```
borsa kurallar pazar
```

BIST Pay Piyasasi birden fazla pazardan olusur:

| Pazar | Seans | Limit | Emir Turleri | Aciga Satis |
|-------|-------|-------|--------------|-------------|
| YILDIZ | TAMGUN | %10 | LIMIT, PIYASA | SERBEST |
| ANA | TAMGUN | %10 | LIMIT, PIYASA | SERBEST |
| ALT | TAMGUN | %10 | LIMIT, PIYASA | SERBEST |
| YAKIN | TEKFIYAT | %10 | LIMIT | YASAK |
| POIP | TEKFIYAT | %10 | LIMIT | YASAK |

- TAMGUN = 1. Seans + 2. Seans (09:40 - 18:10)
- TEKFIYAT = Sadece tek fiyat seansi (14:00 - 14:32)

**Detayli pazar bilgisi:**

```
borsa kurallar pazar YAKIN
```

Yakin Izleme Pazari ozel kurallari:
- SADECE tek fiyat seansi ile islem gorur (14:00 - 14:32)
- PIYASA emri KULLANILAMAZ, sadece LIMIT emir gecerli
- KIE, GIE, TAR emirleri KULLANILAMAZ, sadece GUN emri
- Aciga satis YASAK
- Surekli muzayede YOKTUR
- Tum hisseler BRUT takas ile islem gorur
- Likiditesi cok DUSUKTUR, yuksek RISK tasir

### 7.4 Takas Kurallari

```
borsa kurallar takas
```

**Takas suresi:** T+2 (2 is gunu)

**NET TAKAS (Normal):**

| Ozellik | Durum |
|---------|-------|
| Gun ici al-sat | SERBEST |
| Kredili islem | SERBEST |
| Aciga satis | SERBEST (Yildiz/Ana/Alt Pazar) |
| Teminata verme | SERBEST |

**BRUT TAKAS (Kisitli):**

| Ozellik | Durum |
|---------|-------|
| Gun ici al-sat | YASAK |
| Kredili islem | YASAK |
| Aciga satis | YASAK |
| Teminata verme | YASAK |

Brut takasta aldiginiz hisseyi ayni gun satamazsiniz. En erken T+2 (2 is gunu sonra) satabilirsiniz.

Brut takas uygulanan durumlar:
- Yakin Izleme Pazari'ndaki tum hisseler
- SPK tarafindan "C Grubu" olarak belirlenen hisseler
- Manipulasyon suphesi, asiri volatilite, kotasyon ihlali nedeniyle SPK karariyla brut takasa alinan hisseler

### 7.5 Emir Turleri ve Sureler

**Emir Turleri:**

| Tur | Aciklama |
|-----|----------|
| LIMIT | Belirtilen fiyattan veya daha iyi fiyattan islenir |
| PIYASA | Emrin girildigi andaki en iyi fiyattan islenir. Eslesmeyen kisim limit emre donusur |

**Emir Sureleri:**

| Sure | Aciklama |
|------|----------|
| GUN | Seans sonuna kadar gecerli. Eslesmezse iptal olur |
| KIE | Kalani Iptal Et. Kismen eslesen kalan kisim iptal olur |
| GIE | Gerceklesmezse Iptal Et. Tamami eslesmezse tumu iptal |
| TAR | Tarihli. Belirtilen tarihe kadar gecerli (maks 365 gun) |

### 7.6 Tum BIST Kurallarini Gorme

```
borsa kurallar
```
Parametre verilmezse seans, fiyat, pazar ve takas kurallarinin hepsini tek seferde gosterir.


## 8. Veritabani Gecmis Sorgulari

Supabase veritabanina kaydedilen islem gecmisini sorgulamak icin:

### 8.1 Emir Gecmisi

```
borsa gecmis emirler
```
Son 10 emri gosterir.

```
borsa gecmis emirler 50
```
Son 50 emri gosterir.

### 8.2 Bakiye Gecmisi

```
borsa gecmis bakiye bugun
```
Bugunun bakiye kayitlari.

```
borsa gecmis bakiye 7
```
Son 7 gunun bakiye kayitlari.

### 8.3 Sembol Bazli Pozisyon Gecmisi

```
borsa gecmis sembol THYAO
```
THYAO hissesinin tum pozisyon gecmisi.

### 8.4 Kar/Zarar Raporu

```
borsa gecmis kar
```
Son 30 gunun K/Z raporu.

```
borsa gecmis kar 7
```
Son 7 gunun K/Z raporu.

### 8.5 Fiyat Gecmisi

```
borsa gecmis fiyat THYAO
```
THYAO'nun son 30 gunluk fiyat gecmisi.

```
borsa gecmis fiyat THYAO 90
```
Son 90 gunluk gecmis.

### 8.6 Robot Log Gecmisi

```
borsa gecmis robot
```
Tum robot loglari.

```
borsa gecmis robot 12345
```
Belirli bir robot PID'inin loglari.

### 8.7 Oturum Gecmisi

```
borsa gecmis oturum
```

```
borsa gecmis oturum ziraat 123456
```

### 8.8 Gun Sonu Raporu

```
borsa gecmis rapor
```

### 8.9 Mutabakat (Canli/DB Karsilastirma)

```
borsa mutabakat ziraat 123456
```
Canli bakiye ile veritabanindaki kaydi karsilastirir.

```
borsa mutabakat ziraat 123456 THYAO
```
Belirli bir sembol icin pozisyon mutabakati.


## 9. Robot Motoru

Otomatik islem robotu yonetimi.

### 9.1 Robot Baslatma

```
borsa robot baslat ziraat 123456 strateji.sh
```
Belirtilen stratejiyle robot baslatir.

```
borsa robot baslat --kuru ziraat 123456 strateji.sh
```
Kuru calistirma modu — gercek emir gondermez, sadece simule eder.

### 9.2 Robot Durdurma

```
borsa robot durdur ziraat 123456
```
Tum robotlari durdurur.

```
borsa robot durdur ziraat 123456 strateji_adi
```
Belirli bir stratejiyi durdurur.

### 9.3 Robot Listeleme

```
borsa robot listele
```
Aktif robotlari listeler.


## 10. Backtest (Gecmis Veri Uzerinde Strateji Testi)

### 10.1 Backtest Calistirma

```
borsa backtest strateji.sh THYAO
```
THYAO uzerinde strateji testini calistirir.

### 10.2 Backtest Secenekleri

| Secenek | Aciklama |
|---------|----------|
| `--tarih` | Tarih araligi belirtme |
| `--nakit` | Baslangic nakdi |
| `--komisyon-alis` | Alis komisyon orani |
| `--komisyon-satis` | Satis komisyon orani |
| `--eslestirme` | Eslesme modeli |
| `--isitma` | Isitma donemi |
| `--risksiz` | Risksiz faiz orani |
| `--sessiz` | Sessiz mod |
| `--detay` | Detayli cikti |
| `--kaynak` | Veri kaynagi |
| `--csv-dosya` | Dis CSV dosyasi kullan |

### 10.3 Sonuclari Inceleme

```
borsa backtest sonuclar
```

```
borsa backtest detay
```

```
borsa backtest karsilastir
```

### 10.4 Dis Veri Yukleme

```
borsa backtest yukle veri.csv
```

### 10.5 Sentetik Veri

```
borsa backtest sentetik
```


## 11. Veri Kaynagi Yonetimi

Canli fiyat verisi icin kaynak yonetimi.

### 11.1 Veri Kaynagini Baslatma

```
borsa veri baslat
```
Otomatik olarak en uygun kaynagi secer ve baslatir.

### 11.2 Durdurma

```
borsa veri durdur
```

### 11.3 Durumu Gorme

```
borsa veri goster
```
Aktif kaynagi ve yedek kaynaklari gosterir.

### 11.4 Manuel Kaynak Secimi

```
borsa veri ayarla ziraat 123456
```
Belirli bir araci kurumu veri kaynagi olarak ayarlar.

### 11.5 Fiyat Sorgulama

```
borsa veri fiyat THYAO
```
Aktif kaynaktan THYAO fiyatini sorgular.


## 12. TAB Tamamlama (Tab Completion)

Tum borsa komutlarinda TAB tusu ile otomatik tamamlama destegi vardir:

| Girdi | TAB Sonucu |
|-------|------------|
| `borsa <TAB>` | Kurum listesi + ozel komutlar |
| `borsa ziraat <TAB>` | Komut listesi (giris, bakiye, portfoy...) |
| `borsa kurallar <TAB>` | seans, fiyat, pazar, takas, adim, tavan, taban |
| `borsa gecmis <TAB>` | emirler, bakiye, sembol, kar, fiyat, robot, oturum, rapor |
| `borsa robot <TAB>` | baslat, durdur, listele |
| `borsa veri <TAB>` | baslat, durdur, goster, ayarla, fiyat |
| `borsa ziraat emir THYAO <TAB>` | alis, satis |
| `borsa ziraat emir THYAO alis 100 <TAB>` | piyasa |
| `borsa ziraat emir THYAO alis 100 285.50 <TAB>` | mobil, eposta, hepsi, yok |
| `borsa ziraat arz <TAB>` | liste, talepler, talep, iptal, guncelle |
| `borsa ziraat giris <TAB>` | -o |


## 13. MCP Sunucusu (Yapay Zeka Entegrasyonu)

Bu proje, VS Code Copilot gibi yapay zeka asistanlarina terminal araclarini acan bir MCP (Model Context Protocol) sunucusu icerir. Sunucu Python ile yazilmistir.

### 13.1 Saglanan Arac Gruplari

| Arac Grubu | Aciklama |
|------------|----------|
| Borsa Araclari | Bakiye, portfoy, emir gonderme/iptal, halka arz |
| BIST Kurallari | Seans, fiyat adimi, pazar bilgisi, tavan/taban |
| Yazdir Araclari | PDF ve Markdown yazdirma |
| Zamanlayici Araclari | Geri sayim, alarm, zamanlayici durdurma |

### 13.2 Guvenlik Notu

Giris / parola / sifre islemleri MCP sunucusu uzerinden YAPILAMAZ. Kullanici girisini terminalde yapmalidir. Bu kisitlama, parolalarin yapay zeka saglayici sunucularina iletilmesini onlemek icindir.


## 14. Dizin Yapisi

```
dotfiles/
  kur.sh                          Kurulum betigi
  bashrc.d/
    01-genel.sh                   Terminal ayarlari, renkler, alias
    02-yazdir.sh                  PDF/Markdown yazdirma
    03-zamanlayici.sh             Alarm ve geri sayim
    borsa/
      cekirdek.sh                 Ana yonetici (borsa komutu)
      tamamlama.sh                TAB tamamlama
      veri_katmani.sh             Global veri yapilari
      kurallar/
        bist.sh                   BIST kural seti
      adaptorler/
        ziraat.sh                 Ziraat Yatirim adaptoru
        ziraat.ayarlar.sh         Adaptor ayarlari (git'e girmez)
      robot/
        motor.sh                  Robot motoru
      strateji/
        ornek.sh                  Ornek strateji dosyasi
      backtest/
        motor.sh                  Backtest motoru
        veri.sh                   Backtest veri yonetimi
        metrik.sh                 Performans metrikleri
        portfoy.sh                Backtest portfoy simulasyonu
        rapor.sh                  Sonuc raporlama
        veri_dogrula.sh           Veri dogrulama
      tarama/
        fiyat_kaynagi.sh          Canli fiyat kaynagi
      veritabani/
        docker-compose.yml        Supabase container tanimlar
        sema.sql                  Veritabani tablo tanimlari
        supabase.sh               DB erisim fonksiyonlari
        supabase.ayarlar.sh       Baglanti ayarlari (git'e girmez)
    mcp_sunucular/
      sunucu.py                   MCP sunucu ana dosyasi
      yardimcilar.py              Ortak yardimci fonksiyonlar
      araclar/
        borsa_araclari.py         Borsa MCP araclari
        bist_araclari.py          BIST kural MCP araclari
        yazdir_araclari.py        Yazdir MCP araclari
        zamanlayici_araclari.py   Zamanlayici MCP araclari
```


## 15. Hizli Basvuru Tablosu

### 15.1 En Cok Kullanilan Komutlar

| Komut | Aciklama |
|-------|----------|
| `yazdir "dosya.pdf" 1-20` | PDF yazdir |
| `yazdir "dosya.md" tumu` | Markdown yazdir |
| `yazdir "dosya.md" 10-85` | MD'nin 10-85 satirlarini yazdir |
| `gerisayim 40` | 40 dakika geri sayim |
| `gerisayim 40 -b` | 40 dk arka planda |
| `alarm 14:30` | 14:30 alarmi |
| `zamanlayici 40` | 40 dk GUI zamanlayici |
| `borsa ziraat giris -o` | Giris + oturum koruma |
| `borsa ziraat bakiye` | Bakiye sorgula |
| `borsa ziraat portfoy` | Portfoy detay |
| `borsa ziraat emir THYAO alis 100 285.50` | Alis emri |
| `borsa ziraat emirler` | Bekleyen emirler |
| `borsa ziraat iptal <REF>` | Emir iptal |
| `borsa kurallar seans` | Seans saatleri |
| `borsa kurallar adim 85.45` | Fiyat adimi |
| `borsa kurallar tavan 85.00` | Tavan fiyat |
| `tum_bakiyeler` | Tum hesap bakiyeleri |
| `gunluk_ozet` | Gunluk genel ozet |

### 15.2 Yardim Komutlari

| Komut | Aciklama |
|-------|----------|
| `yazdir --yardim` | Yazdirma yardimi |
| `zamanlayici` | Zamanlayici yardimi |
| `borsa` | Borsa genel yardim |
| `borsa ziraat` | Kurum komutlari |
| `borsa kurallar` | Tum BIST kurallari |
| `borsa gecmis` | Gecmis sorgulari |
| `borsa robot` | Robot yardimi |
| `borsa veri` | Veri kaynagi yardimi |

### 15.3 Guvenlik Ilkeleri

- Hassas dosyalar (ayarlar, .env) chmod 600 ile korunur
- Parolalar yapay zeka uzerinden GONDERILMEZ
- Cookie dosyalari /tmp/borsa/ altinda izinli saklanir
- Ayarlar dosyalari .gitignore ile git disinda tutulur
- Emir gondermeden once BIST fiyat adimi ve pazar kontrolu yapilir
- DB yazma islemleri sadece robot modunda yapilir (manuel islemler DB'yi kirletmez)
