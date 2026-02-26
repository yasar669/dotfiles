# Canli Veri (WSS / REST Polling) - Plan

## 1. Amac

Bu belge BIST hisse senetleri icin canli (anlik) fiyat verisinin nasil elde edilecegini, mum verisine donusturulecegini ve Supabase'e yazilacagini tanimlar. tvDatafeed ile gecmis veri cekimi ayri bir belgedir (ohlcv_plani.md). Bu belge sadece seans icinde gercek zamanli veri akisini kapsar.

Temel fark:

| Ozellik | OHLCV (Gecmis Mum) | Canli Veri (Bu Belge) |
|---------|-------------------|----------------------|
| Veri tipi | Gecmis mumlar (gunluk, saatlik, dakikalik) | Anlik fiyat degisimi, tick bazli |
| Erisim | tvDatafeed ile toplu cekim | WSS veya REST polling |
| Kurum bagimliligi | Yok — TradingView bagimsiz | Var — aktif oturum gerekli |
| Gecikme | 15 dakika (seans icinde) | Milisaniye (WSS) veya 3-5 saniye (REST) |
| Kapsam | Tum BIST (1005 hisse) | Sadece takip listesi (5-50 hisse) |

## 2. Mimari Karar

### 2.1 Uc Katmanli Veride Canli Verinin Yeri

tvDatafeed'in 15 dakika gecikmeli veri vermesi nedeniyle sistem uc katmana ayrilir. Canli veri ikinci katmandir:

```
+-------------------------------------------------------------------+
|  KATMAN 1: ILK DOLUM (tek seferlik)                               |
|  tvDatafeed — tum BIST x tum periyotlar x 5000 bar               |
|  Detay: ohlcv_plani.md                                            |
+-------------------------------------------------------------------+
          |
          v
+-------------------------------------------------------------------+
|  KATMAN 2: CANLI SEANS (seans icinde, 09:40 - 18:10)  [BU BELGE] |
|  SADECE TAKIP LISTESINDEKI hisseler + secili periyotlar           |
|  Kurum WSS veya REST ile gercek zamanli veri                      |
|  tvDatafeed KULLANILMAZ (15dk gecikme nedeniyle)                  |
|  Her yeni mum kapanisinda -> Supabase'e yaz                       |
+-------------------------------------------------------------------+
          |
          v
+-------------------------------------------------------------------+
|  KATMAN 3: GUNLUK TAMIR (seans sonrasi, 18:30+)                   |
|  tvDatafeed referans — WSS'ten gelen mumlari dogrula              |
|  Detay: ohlcv_plani.md                                            |
+-------------------------------------------------------------------+
```

### 2.2 Neden Tum Hisselere WSS Acilmiyor

| Sorumluluk | Kapsam | Neden |
|------------|--------|-------|
| Ilk dolum (tvDatafeed) | 1005 hisse x 13 periyot | Backtest ve tarama icin tum evren gerekli |
| WSS canli takip | 5-50 hisse x secili periyotlar | Kullanici/robot sadece ilgilendigi hisseleri izler |
| Gunluk tamir | Takip: tum TF, diger: sadece 1G | WSS mumlarini dogrula, eksikleri tamamla |

Kaynak karsilastirmasi:

```
TUM HISSE WSS (yapilmayacak):  1005 hisse x WSS baglantisi = asiri kaynak
TAKIP LISTESI WSS (yapilacak): 5-50 hisse x WSS baglantisi = makul kaynak
```

### 2.3 Kaynak Sorumluluk Tablosu

| Veri Tipi | Kaynak | Katman | Kurum Bagimliligi |
|-----------|--------|--------|-------------------|
| OHLCV (gecmis mum) | tvDatafeed (TradingView) | Tarama | Yok — bagimsiz |
| Canli anlik fiyat | Kurum WSS veya REST | Tarama -> Adaptor | Var — aktif oturum gerekli |
| Emir gonderme | Kurum REST | Adaptor | Var — aktif oturum gerekli |
| Bakiye/portfoy | Kurum REST | Adaptor | Var — aktif oturum gerekli |

## 3. Canli Seans Veri Akisi

### 3.1 Takip Listesi

Seans icinde sadece takip listesindeki hisseler icin veri cekilir. Takip listesi kullanici ve robot tarafindan yonetilir.

```
[TAKIP LISTESI ORNEGI]
  takip.json:
  {
    "THYAO": ["1dk", "5dk", "15dk", "1S", "1G"],
    "GARAN": ["5dk", "15dk", "1G"],
    "AKBNK": ["1G"]
  }

  -> 3 hisse icin WSS/REST acilir
  -> THYAO: 5 periyotta mum olusturulur
  -> GARAN: 3 periyotta mum olusturulur
  -> AKBNK: sadece gunluk mum
```

### 3.2 Seans Ici Veri Akisi

```
[SEANS ICI VERI AKISI — takip listesindeki her hisse icin]
  Kurum WSS (gercek zamanli)  veya  REST polling (200-500ms gecikme)
    |
    v
  Mum olusturucu (mum_birlestirici)
    Tick verilerini hissenin secili periyotlarina gore mumlar haline getir:
    - THYAO 1dk mum kapandiktan -> Supabase'e yaz
    - THYAO 5dk mum kapandiktan -> Supabase'e yaz
    - GARAN 15dk mum kapandiktan -> Supabase'e yaz
    - Gun sonunda tum takip listesi 1G mum -> Supabase'e yaz
    |
    v
  Supabase (kalici depo)
```

### 3.3 Takip Listesi Yonetimi

Kullanici hisse ve periyot ekleyip cikarabilir:

```
borsa takip ekle THYAO 1dk 5dk 15dk 1S 1G
  -> THYAO takip listesine eklendi
  -> Seans aciksa WSS hemen baslar
  -> Seans kapaliysa bir sonraki seansta baslar

borsa takip cikar THYAO
  -> THYAO takip listesinden cikarildi
  -> WSS kapatildi
  -> Supabase'deki veri SILINMEZ (gecmis saklanir)

borsa takip liste
  THYAO  1dk 5dk 15dk 1S 1G   [WSS: AKTIF]
  GARAN  5dk 15dk 1G           [WSS: AKTIF]
  AKBNK  1G                    [WSS: AKTIF]
```

Robot motoru tarafindan otomatik yonetim:

```
[ROBOT BASLADIGINDA]
  robot_baslat ziraat 111111 strateji_a.sh
    -> Strateji THYAO ve GARAN'da 15dk mumlarla calisiyor
    -> takip listesine otomatik eklenir: THYAO 15dk, GARAN 15dk
    -> WSS baslar

[ROBOT DURDUGUNCA]
  robot_durdur ziraat 111111 strateji_a
    -> Baska robot bu hisseleri takip ediyor mu?
       Evet -> takipte kalir
       Hayir -> takip listesinden cikarilir, WSS kapanir
```

Takip dosyalari:

```
/tmp/borsa/_takip/
    takip.json          # aktif takip listesi {sembol: [periyotlar]}
    kaynaklar.json      # her takibin kaynagi {"THYAO": ["kullanici", "strateji_a"]}
```

`kaynaklar.json` bir hisseyi kimin ekledigini takip eder. Hem kullanici hem robot eklemis olabilir. Hisse ancak tum kaynaklar cikarildiginda takipten duser.

## 4. Mum Birlestirici Algoritmasi

### 4.1 Tick'ten Mum Olusturma

Kurum WSS veya REST'ten gelen tick (fiyat degisimi) verileri ham haldedir. Bunlari OHLCV mumuna donusturmek icin `mum_birlestirici` algoritmasi kullanilir.

```
[TICK -> MUM DONUSUMU]

  Gelen tick verisi formati (kurum REST veya WSS'ten):
    {sembol: "THYAO", fiyat: 315.75, hacim: 12500, zaman: 1740393600}

  Mum olusturma mantigi (her periyot icin ayri tutulan durum):

    mum_durumu[sembol][periyot] = {
        acilis_zamani: periyot baslangic zamani,
        acilis: ilk tick fiyati,
        yuksek: simdiye kadarki en yuksek fiyat,
        dusuk: simdiye kadarki en dusuk fiyat,
        kapanis: son tick fiyati,
        hacim: toplam hacim
    }

    her_tick_geldiginde(tick):
        periyot_baslangici = tick.zaman - (tick.zaman % periyot_saniye)

        eger mum_durumu[sembol][periyot].acilis_zamani != periyot_baslangici:
            # Yeni periyot basladi — onceki mumu kapat ve kaydet
            onceki_mum = mum_durumu[sembol][periyot]
            supabase_yaz(onceki_mum)  # UPSERT
            # Yeni mum baslat
            mum_durumu[sembol][periyot] = {
                acilis_zamani: periyot_baslangici,
                acilis: tick.fiyat,
                yuksek: tick.fiyat,
                dusuk: tick.fiyat,
                kapanis: tick.fiyat,
                hacim: tick.hacim
            }
        degilse:
            # Mevcut mumu guncelle
            mum.yuksek = max(mum.yuksek, tick.fiyat)
            mum.dusuk  = min(mum.dusuk, tick.fiyat)
            mum.kapanis = tick.fiyat
            mum.hacim  += tick.hacim
```

### 4.2 Periyot Saniye Karsiliklari

| Periyot | Saniye | Aciklama |
|---------|--------|----------|
| 1dk | 60 | Her dakika basinda yeni mum |
| 5dk | 300 | 09:40, 09:45, 09:50... |
| 15dk | 900 | 09:40, 09:55, 10:10... |
| 30dk | 1800 | 09:40, 10:10, 10:40... |
| 1S | 3600 | 09:40, 10:40, 11:40... |
| 1G | - | Seans sonunda tek mum |

### 4.3 Gunluk Mum Ozel Durumu

- 1G mumu seans boyunca acik kalir, her tick'te guncellenir.
- Seans kapanisinda (18:10) otomatik kapatilir ve Supabase'e yazilir.
- Acilis fiyati ilk tick'ten alinir (genellikle 09:40:00).

### 4.4 Birden Fazla Periyot

- THYAO takipte 1dk, 5dk, 1G ile ise her tick 3 ayri mum durumunu gunceller.
- 1dk kapanis zamani geldiginde 1dk mum kapatilir ama 5dk ve 1G devam eder.
- Bu islem bellek icinde (Python dict veya bash assoc array) yapilir, her mum kapanisinda Supabase'e yazilir.

## 5. WSS (Canli Fiyat) Stratejisi

### 5.1 Mevcut Durum ve Calisan Altyapi

sistem_plani.md Bolum 9'da tanimlanan veri kaynagi mimarisi canli/anlik fiyat icin halihazirda bir cozum sunuyor:
- Acik oturumlardan biri veri kaynagi olarak secilir.
- REST polling ile `adaptor_hisse_bilgi_al` uzerinden fiyat cekilir.
- Failover mekanizmasi ile yedek kaynaga gecilir.
- 10 saniyelik dosya onbellegi ayni hisse icin tekrar istek atilmasini onler.

Calisan REST endpointi (Ziraat ornegi):

```
[MEVCUT CALISAN YONTEM — REST POLLING]
  Fonksiyon: adaptor_hisse_bilgi_al("THYAO")
  Endpoint:  POST https://esube1.ziraatyatirim.com.tr/sanalsube/tr/Equity/ListCharacteristic
  Parametre: FilterText=THYAO
  Yanit:     JSON -> LastPrice, CeilingPrice, FloorPrice, ChangePercent, Volume
  Cikti:     "315.75|340.00|290.00|1.25|4521000"
  Gecikme:   200-500ms (istek-yanit dongusu)
  Onbellek:  /tmp/borsa/_veri_onbellek/THYAO.dat (10sn TTL)
  Durum:     CALISIYOR — uretimde aktif
```

Bu mimari calisiyor ancak REST polling gecikme yaratir. WSS ile bu gecikme milisaniye seviyesine duser.

### 5.2 Kurum WSS Arastirma Sonuclari

Her araci kurumun canli fiyat aktarimi icin kullandigi WebSocket altyapisi arastirildi. Mevcut bulgular:

#### 5.2.1 Ziraat E-Sube — SignalR WebSocket

Ziraat E-Sube canli fiyat icin ASP.NET SignalR teknolojisini kullanir. Angular uygulamasi icinden SignalR hub'ina baglanilir.

Yapilan denemeler:

```
[DENEME 1: SignalR Negotiate]
  URL: https://esube1.ziraatyatirim.com.tr/signalr/negotiate
  Yontem: curl ile POST, oturum cookie'leri gonderildi
  Sonuc: BASARILI — ConnectionId ve ConnectionToken dondu
  Not: Hub mevcut ve yanit veriyor

[DENEME 2: SignalR Connect (WS Upgrade)]
  URL: wss://esube1.ziraatyatirim.com.tr/signalr/connect?transport=webSockets&connectionToken=...
  Yontem: websocat ile WS baglantisi
  Sonuc: BASARISIZ — HTTP 401 Unauthorized
  Sebep: Cookie domain dogrulamasi

[DENEME 3: SignalR Connect (curl ile Long Polling)]
  URL: https://esube1.ziraatyatirim.com.tr/signalr/connect?transport=longPolling&connectionToken=...
  Sonuc: BASARISIZ — 401
```

Basarisizlik nedeni — teknik analiz:

```
[NEDEN 401 ALIYOR]
  1. Tarayici ortaminda SignalR su akisi izler:
     Kullanici giris -> ASP.NET oturum cookie'si -> negotiate -> connectionToken -> WS upgrade
     Tum bu islemler ayni tarayici Origin'inden gelir.

  2. curl/websocat ile yapildiginda:
     - Cookie'nin Domain ve Path ozellikleri tarayici gibi otomatik eslestirilemez
     - Origin header'i "https://esube1.ziraatyatirim.com.tr" olmali
       curl Origin spoof etse bile sunucu ek dogrulama yapiyor
     - SignalR negotiate token'i oturum cookie'sine baglidir
       WS upgrade sirasinda bu token eslestirilemiyor
     - Sunucu muhtemelen X-Requested-With, Sec-WebSocket-Protocol gibi
       tarayiciya ozgu headerlari da kontrol ediyor

  3. Sonuc: Tarayici disinda SignalR'a baglanmak pratik olarak mumkun degil.
     Ziraat bu korumayi bilerek uyguluyor — dis istemcilere izin verilmiyor.
```

#### 5.2.2 Diger Kurumlar — Bilinen Durum

| Kurum | WSS Durumu | Detay |
|-------|-----------|-------|
| Ziraat E-Sube | SignalR — 401 | Tarayici disinda erisim engeli |
| Foreks | Erisilemez | Web sitesine erisim basarisiz |
| Matriks | HTTP 403 | Web sitesi bloklu |
| IS Yatirim | Bos yanit | API yanit vermiyor |
| ZPro (Ziraat Pro) | DNS basarisiz | DNS cozumleme yapilmiyor |
| Garanti BBVA | Arastirilmadi | Potansiyel aday |
| Yapi Kredi | Arastirilmadi | Potansiyel aday |

Henuz calisan bir WSS baglantisi mevcut degil.

#### 5.2.3 Olasi WSS Cozum Yollari

Yol 1 — Headless Browser (en yuksek basari sansi):

```
[HEADLESS BROWSER YAKLASIMI]
  Arac: Playwright veya Puppeteer (Node.js) veya Selenium (Python)
  Akis:
    1. Headless Chrome baslatilir
    2. Ziraat E-Sube'ye giris yapilir (gercek tarayici oturumu)
    3. Tarayici icinden SignalR baglantisi kurulur (otomatik olarak dogrulanir)
    4. SignalR hub'indan gelen mesajlar (fiyat degisimleri) yakalanir
    5. Yakalanan mesajlar Python/bash'e aktarilir -> mum_birlestirici

  Avantaj: Tarayici ortami aynen taklit edilir, 401 sorunu olmaz
  Dezavantaj: Agir kaynak tuketimi (Chrome prosesi), kirilgan (UI degisikligi bozar)
  Karmasiklik: Yuksek
  Durum: PLANLANMADI — son care olarak saklaniyor
```

Yol 2 — REST Polling Optimizasyonu (mevcut sistemin iyilestirilmesi):

```
[OPTIMIZE REST POLLING]
  Mevcut: adaptor_hisse_bilgi_al -> tek hisse, 200-500ms gecikme, 10sn onbellek

  Iyilestirme 1: Paralel cekim
    Takip listesindeki 20 hissenin fiyatini ayni anda cek (bash & ile)
    20 hisse x 300ms = 6sn -> paralel ile ~500ms

  Iyilestirme 2: Onbellek suresini kisalt
    Takip listesindeki hisseler icin TTL: 10sn -> 3sn
    Diger hisseler icin TTL: 10sn (degismez)

  Iyilestirme 3: Toplu sorgu (kurum destekliyorsa)
    FilterText=THYAO,GARAN,AKBNK seklinde tek istekte birden fazla hisse
    Ziraat'in bunu destekleyip desteklemedigini test etmek gerekiyor

  Avantaj: Ek bagimlilik yok, mevcut altyapi uzerinde calisir
  Dezavantaj: Hala polling — gercek zamanli degil (en iyi 3sn araliklarla)
  Durum: ILK UYGULANACAK IYILESTIRME
```

Yol 3 — Baska kurum WSS'i arastirmasi:

```
[BASKA KURUM ARASTIRMASI]
  Hedef: WSS endpointi acik olan veya API saglayan bir kurum bulmak
  Adaylar:
    - Garanti BBVA (buyuk kurum, modern altyapi)
    - Yapi Kredi (Borsa Istanbul'un dijital ortakligi)
    - Ak Yatirim (API belgesi yayinlayabilir)
    - Midas (yeni nesil yatirim uygulamasi — API daha acik olabilir)

  Arastirma yontemi:
    1. Kurum web sitesine giris yap
    2. Chrome DevTools -> Network -> WS filtresi
    3. WebSocket URL, mesaj formati ve auth mekanizmasini kaydet
    4. curl/websocat ile dis erisim dene

  Durum: GELECEKTE ARASTIRILACAK (yeni kurum hesabi acildiginda)
```

Yol 4 — TradingView WSS (tvDatafeed uzerinden canli):

```
[TRADINGVIEW CANLI WSS]
  tvDatafeed'in get_hist() fonksiyonu gecmis veri cekerken WS kullanir.
  Ayni WS baglantisi uzerinde canli tick verisi de alinabilir mi?

  Teorik olarak TradingView WS su mesajlari destekler:
    - "quote_create_session" -> canli fiyat stream'i
    - "quote_add_symbols" -> sembol ekle
    - "quote_fast_symbols" -> hizli guncelleme modu

  Ancak:
    - Anonim modda 15dk gecikme uygulanir (canli icin anlamsiz)
    - TradingView hesabi ile giris yapilirsa gecikme kalkar
      AMA TradingView ToS buna izin vermiyor olabilir
    - tvDatafeed fork'unda canli stream destegi yok
```

### 5.3 Pragmatik WSS Stratejisi

Mevcut gerceklik: Calisan bir WSS baglantisi yok. Sistem REST polling ile calisiyor ve bu yeterli.

Uygulama plani 3 asamalidir:

```
[ASAMA 1 — SIMDI: REST POLLING IYILESTIRME]
  Mevcut adaptor_hisse_bilgi_al zaten calisiyor.
  Takip listesi icin paralel cekim ve kisaltilmis TTL eklenir.
  Sonuc: 3-5 saniyelik araliklarla tum takip listesi guncellenir.
  Bu cogu strateji icin yeterlidir (30sn-1dk robot dongusu).

[ASAMA 2 — GELECEK: KURUM WSS ENTEGRASYONU]
  Yeni bir kurum hesabi acildiginda o kurumun WSS'i arastirilir.
  WSS calisan bir kurum bulunursa:
    1. Adaptor fonksiyonlari eklenir: adaptor_wss_baglan, adaptor_wss_dinle, adaptor_wss_kapat
    2. Takip listesindeki hisseler icin WSS acilir
    3. REST polling yedek (fallback) olarak kalir
  Her kurumun WSS implementasyonu kendi adaptor dosyasinda tutulur.

[ASAMA 3 — SON CARE: HEADLESS BROWSER]
  Hicbir kurumun WSS'i dis erisime acik degilse:
    Playwright ile tarayici oturumu icinden WSS baglanir.
    Bu cozum agir ve kirilgandir, sadece zorunlu hallerde uygulanir.
```

### 5.4 WSS Adaptor Arayuzu

Her kurum adaptorunun WSS destegi eklenecekse su fonksiyonlari implemente etmesi gerekir:

```
[WSS ADAPTOR FONKSIYONLARI — her kurum icin]

  adaptor_wss_destekliyor_mu()
    # Bu kurum WSS sunuyor mu?
    # Dondu: 0 (evet) veya 1 (hayir)

  adaptor_wss_baglan(semboller[])
    # Verilen sembollere WSS baglantisi ac
    # Arka plan prosesi olarak calisir
    # PID dosyasi olusturur: /tmp/borsa/_wss/<kurum>_<hesap>.pid
    # Gelen tick'leri /tmp/borsa/_wss/tickler/<SEMBOL>.tick'e yazar

  adaptor_wss_sembol_ekle(sembol)
    # Aktif WSS baglantisina yeni sembol ekle

  adaptor_wss_sembol_cikar(sembol)
    # Aktif WSS baglantisinden sembol cikar

  adaptor_wss_kapat()
    # WSS baglantisini kapat, PID dosyasini temizle

  adaptor_wss_durum()
    # WSS durumu: BAGLI, BAGLANIYOR, KOPUK
    # Acik sembol sayisi, son tick zamani
```

Tick dosya formati (WSS'ten gelen ham veri):

```
/tmp/borsa/_wss/tickler/THYAO.tick
  Format: epoch|fiyat|hacim
  Ornek:
    1740393600|315.75|12500
    1740393601|315.80|8300
    1740393603|316.00|22100
  Donus: Her yeni satir = yeni tick
  Okuma: tail -f ile canli dinleme (mum_birlestirici tarafindan)
```

### 5.5 WSS -> Mum Birlestirici -> Supabase Akisi

```
[WSS -> MUM BIRLESTIRICI -> SUPABASE AKISI]

  1. adaptor_wss_baglan(["THYAO", "GARAN", "AKBNK"])
     -> Arka planda WSS prosesi baslar
     -> /tmp/borsa/_wss/tickler/THYAO.tick dosyasina tick'ler akar

  2. mum_birlestirici_baslat(["THYAO": ["1dk","5dk","1G"]])
     -> Her sembol icin tick dosyasini tail -f ile dinler
     -> Gelen tick'lerden 1dk, 5dk, 1G mumlarini olusturur
     -> Mum kapandiginda Supabase'e UPSERT yapar

  3. Seans kapanisinda (18:10):
     -> Son acik mumlari kapat ve Supabase'e yaz
     -> WSS baglantisini kapat
     -> mum_birlestiriciyi durdur
```

### 5.6 WSS Kaynak Yonetimi

WSS sadece takip listesindeki hisseler icin acilir. Kaynak tuketimi kontrol altindadir:

| Senaryo | WSS Baglantisi | Kaynak |
|---------|---------------|--------|
| 5 hisse takipte | 5 WSS stream | Dusuk |
| 20 hisse takipte | 20 WSS stream | Orta |
| 50 hisse takipte | 50 WSS stream | Yuksek (makul ust sinir) |
| 1005 hisse (yapilmayacak) | 1005 WSS stream | Asiri — gereksiz |

Onerilen ust sinir: 50 hisse. Bu sinir ayarlanabilirdir.

### 5.7 WSS Oncelik Sirasi

```
[CANLI FIYAT ONCELIK SIRASI — takip listesindeki her hisse icin]
  1. Aktif kurumun WSS baglantisi (en dusuk gecikme)
     -> adaptor_wss_destekliyor_mu() == 0 ise
  2. Yedek kurumun WSS baglantisi (failover)
  3. REST polling — adaptor_hisse_bilgi_al (fallback, her zaman calisan)
     -> WSS yoksa veya kopuksa otomatik gecer
```

WSS protokolu kuruma ozeldir — her adaptor kendi WSS'ini implemente eder.
Birden fazla kurumun WSS'i aktifse failover sirasi sistem_plani.md Bolum 9'daki gibi belirlenir.

## 6. Yol Haritasi

### 6.1 Asama 6 — Takip Listesi Yonetimi

Dosya: `bashrc.d/borsa/tarama/ohlcv.sh` (icerisine eklenir)

Kapsam:
- `borsa takip ekle <SEMBOL> <periyot1> <periyot2> ...` — hisse + periyot ekle.
- `borsa takip cikar <SEMBOL>` — hisseyi takipten cikar.
- `borsa takip liste` — aktif takip listesini goster.
- `takip.json` ve `kaynaklar.json` dosya yonetimi.
- Robot motoru tarafindan `_takip_robot_ekle` / `_takip_robot_cikar` fonksiyonlari.
- Referans sayac: hisse ancak tum kaynaklar cikarildiginda takipten duser.

Dosya yapisi:

```
/tmp/borsa/_takip/
    takip.json        # {"THYAO": ["1dk","5dk","1G"], "GARAN": ["1G"]}
    kaynaklar.json    # {"THYAO": ["kullanici", "strateji_a"], "GARAN": ["strateji_b"]}
```

Tahmini sure: 2-3 saat.

### 6.2 Asama 7 — REST Polling Iyilestirme (WSS Oncesi)

Dosya: `bashrc.d/borsa/tarama/fiyat_kaynagi.sh` (mevcut dosyada guncelleme)

Kapsam:
- Takip listesindeki hisseler icin paralel REST cekim.
- Onbellek TTL'i takip listesi icin 3 saniyeye dusurulur.
- `adaptor_hisse_bilgi_al` icin toplu sorgu destegi test edilir.
- Her cekim sonrasi mum_birlestirici'ye tick olarak iletilir.
- Sonuc: REST polling ile 3-5 saniyelik araliklarla mum guncelleme.

```
[IYILESTIRILMIS REST POLLING AKISI]
  Her 3 saniyede:
    takip_listesi_oku -> ["THYAO", "GARAN", "AKBNK"]
    |
    +-> adaptor_hisse_bilgi_al "THYAO" &
    +-> adaptor_hisse_bilgi_al "GARAN" &
    +-> adaptor_hisse_bilgi_al "AKBNK" &
    wait
    |
    v
    Her sonuc icin:
      tick_yaz THYAO 315.75 12500 $(date +%s)
      -> mum_birlestirici tick'i isler
      -> Mum kapandiysa Supabase'e yaz
```

Bu asama WSS elde edilene kadar canli veri katmaninin temelini olusturur. WSS acildiginda ayni mum_birlestirici altyapisi kullanilir, sadece tick kaynagi degisir (REST -> WSS).

Tahmini sure: 2-3 saat.

### 6.3 Asama 8 — WSS Mum Olusturucu

Dosya: `bashrc.d/borsa/tarama/mum_birlestirici.sh` (veya Python ile `_mum_birlestirici.py`)

Kapsam:
- Tick dosyalarindan (`/tmp/borsa/_wss/tickler/*.tick`) canli okuma.
- Her sembol icin secili periyotlarda mum olusturma (Bolum 4.1 algoritmasi).
- Mum kapanisinda Supabase UPSERT.
- Seans basinda otomatik baslatma, seans sonunda otomatik durdurma.

WSS baglantisi mevcut degilse (Asama 7'deki REST polling calisir):
- REST polling'den gelen veriler ayni tick formatinda yazilir.
- Mum birlestirici kaynak farketmeksizin calisir.

WSS baglantisi mevcut ise:
- `adaptor_wss_baglan` tick dosyasina yazar.
- Mum birlestirici `tail -f` ile dinler.
- REST polling yedek olarak kalir (WSS kopma durumunda).

Tahmini sure: 4-5 saat.

### 6.4 Tahmini Sure ve Oncelik

| Asama | Tahmini Sure | Bagimlilik | Oncelik |
|-------|-------------|------------|--------|
| 6. Takip listesi | 2-3 saat | ohlcv.sh (Asama 5) | ILK |
| 7. REST polling iyilestirme | 2-3 saat | Takip listesi (Asama 6) | IKINCI |
| 8. WSS mum olusturucu | 4-5 saat | REST polling (Asama 7) | UCUNCU |
| **Toplam** | **~8-11 saat** | | |

Not: Asama numaralari ohlcv_plani.md'deki sirayla uyumludur (Asama 1-5 orada, 6-8 burada).
