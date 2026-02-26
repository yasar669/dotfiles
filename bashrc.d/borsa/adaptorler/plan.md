# Adaptor Katmani - Plan

## 1. Genel Bakis

Adaptor katmani, farkli araci kurumlarin web arayuzlerini ortak bir `adaptor_*` arayuzune donusturur.
Her kurum icin iki dosya bulunur: `<kurum>.sh` (mantik) ve `<kurum>.ayarlar.sh` (yapilandirma).
Cekirdek (`cekirdek.sh`) adaptorleri yukler, komutlari yonlendirir ve ortak altyapiyi saglar.

Bu plan dosyasi asagidaki senaryolari kapsar:
- Sifirdan yeni araci kurum adaptoru ekleme.
- Mevcut adaptore yeni ozellik ekleme (ornek: yeni komut, yeni halka arz turu).
- Tum adaptorleri etkileyen jenerik ozellik ekleme (ornek: yeni cekirdek komutu).
- Site degisikligi durumunda adaptoru guncelleme.

## 2. Temel Ilke: Sorumluluk Ayrimi

Adaptorde **yalnizca kuruma ozgu kod** bulunur. Diger her sey cekirdekte islenir.
Bu ilke jenerikligin temelidir: yeni kurum eklerken cekirdege dokunulmaz,
yeni cekirdek ozelligi eklerken adaptore dokunulmaz.

### 2.1 Adaptore Ait Olanlar (Kuruma Ozgu)

- HTTP istek gonderimi icin URL ve form verisi hazirlama.
- HTML/JSON yanit parse etme (seciciler, regex kaliplari).
- Kuruma ozgu is kurallari (ornek: Ziraat seans disi minimum tutar kisitlamasi).
- Kuruma ozgu giris akisi (SMS dogrulama, CAPTCHA, 2FA).
- Kuruma ozgu hata mesajlarini yorumlama (`_<kurum>_html_hata_cikar`).

### 2.2 Cekirdege Ait Olanlar (Ortak Altyapi)

- Oturum dizin yapisi ve dosya yonetimi (`/tmp/borsa/<kurum>/<hesap>/`).
- Cookie dosyasi olusturma, okuma, yedekleme (`cekirdek_cookie_guvence`).
- HTTP istek motoru (`cekirdek_istek_at` — curl sarmalayicisi).
- Loglama altyapisi (`cekirdek_adaptor_log`).
- Cikti bicimlemesi (`cekirdek_yazdir_portfoy`, `cekirdek_yazdir_oturum_bilgi`, vb.).
- Oturum suresi takibi ve koruma dongusu.
- Aktif hesap yonetimi (`cekirdek_aktif_hesap`, `cekirdek_aktif_hesap_ayarla`).
- Adaptor fabrikasi — ince sarmalayici fonksiyonlarinin otomatik uretilmesi.
- CSRF token cikarma (`cekirdek_csrf_cikar`).
- Yanit boyutu ve oturum yonlendirme kontrolleri.
- JSON API yanit analizi (`cekirdek_json_sonuc_isle`).
- Saglik kontrol (`cekirdek_saglik_kontrol`).
- Veri katmanina yazma (`_BORSA_VERI_*` yapilarina kayit).
- BIST kural kontrolu (fiyat adimi, pazar-emir uyumluluk).
- Veritabani kaydi (emir, bakiye, pozisyon — robot modunda).
- Komut yonlendirme (`borsa()` fonksiyonundaki `case` blogu).

### 2.3 Karar Tablosu

Asagidaki tablo bir fonksiyonun nereye ait oldugunu belirler:

| Soru                                                  | Evet -> Adaptor | Hayir -> Cekirdek |
| ----------------------------------------------------- | --------------- | ----------------- |
| Kurum web sitesinin HTML/JSON yapisina mi bagli?       | Adaptor         |                   |
| Baska kurum eklense ayni kod tekrarlanacak mi?         |                 | Cekirdek          |
| URL, secici veya form alan adi mi?                     | Ayarlar dosyasi |                   |
| Is kurali yalnizca bu kuruma mi ait?                   | Adaptor         |                   |
| Is kurali BIST genelinde mi gecerli?                   |                 | kurallar/bist.sh  |
| Dosya sistemi veya dizin yapisiyla mi ilgili?          |                 | Cekirdek          |
| Kullaniciya gosterilen cikti bicimi mi?                |                 | Cekirdek          |

## 3. Dosya Yapisi ve Isimlendirme

### 3.1 Adaptor Dosyasi: `<kurum>.sh`

Kurumun web arayuzuyle iletisim kuran tum mantik bu dosyada bulunur.
Dosya dogrudan calistirilmaz; `cekirdek.sh` tarafindan `source` ile yuklenir.

Dosya yapisi:

```
<kurum>.sh
  BOLUM 1: DAHILI YARDIMCILAR (_<kurum>_* fonksiyonlari)
  BOLUM 2: GENEL ARABIRIM    (adaptor_* fonksiyonlari — temel islemler)
  BOLUM 3: HALKA ARZ         (adaptor_halka_arz_* — varsa)
  BOLUM 4: OTURUM CALLBACKLERI (adaptor_oturum_* fonksiyonlari)
```

- Dahili yardimcilar `_<kurum>_` oneki tasir ve disaridan cagrilmaz.
- Genel arabirim fonksiyonlari `adaptor_` oneki tasir ve cekirdek.sh tarafindan cagrilir.

### 3.2 Ayarlar Dosyasi: `<kurum>.ayarlar.sh`

Yalnizca sabitler, URL'ler, HTML secicileri ve regex kaliplari icerir.
Hicbir fonksiyon tanimlamaz. Site guncellenmesi durumunda yalnizca bu dosya duzenlenir.

Ayarlar dosyasi bolumleri:

```
<kurum>.ayarlar.sh
  BOLUM 1: SUNUCU VE OTURUM AYARLARI  (URL'ler, base URL)
  BOLUM 2: HTML SECICILER              (regex kaliplari, CSS ID'ler)
  BOLUM 3: EMIR ALANLARI              (form alan sabitleri)
  BOLUM 4: KURUM KURALLARI            (kuruma ozgu kisitlamalar)
  BOLUM 5: HALKA ARZ AYARLARI         (IPO URL ve secicileri — varsa)
```

### 3.3 Isimlendirme Konvansiyonlari

| Kapsam                 | Isimlendirme           | Ornek                          |
| ---------------------- | ---------------------- | ------------------------------ |
| Ayar sabiti            | `_<KURUM>_*`           | `_ZIRAAT_BASE_URL`             |
| HTML secici sabiti     | `_<KURUM>_SEL_*`       | `_ZIRAAT_SEL_CSRF_TOKEN`       |
| Kalip sabiti           | `_<KURUM>_KALIP_*`     | `_ZIRAAT_KALIP_BASARILI_HTML`  |
| Form alan sabiti       | `_<KURUM>_EMIR_*`      | `_ZIRAAT_EMIR_ALIS`            |
| Dahili yardimci        | `_<kurum>_*`           | `_ziraat_html_hata_cikar`      |
| Arabirim fonksiyonu    | `adaptor_*`            | `adaptor_giris`                |
| Cekirdek fonksiyonu    | `cekirdek_*`           | `cekirdek_istek_at`            |
| Cekirdek sabiti        | `_CEKIRDEK_*`          | `_CEKIRDEK_DOSYA_COOKIE`       |
| Fabrika sarmalayicisi  | `_<kurum>_*()`         | `_ziraat_log()` (otomatik)     |

## 4. Adaptor Arabirim Sozlesmesi

### 4.1 Zorunlu Fonksiyonlar

Cekirdek bu fonksiyonlarin tanimli olmasini bekler ve dogrudan cagrir.
Yeni kurum eklerken bu fonksiyonlarin **hepsi** yazilmalidir:

| Fonksiyon                    | Gorev                                     | Cekirdekteki Cagrici         |
| ---------------------------- | ----------------------------------------- | ---------------------------- |
| `adaptor_giris`              | Oturum acma (kullanici adi + sifre)       | `borsa()` — `giris` komutu  |
| `adaptor_bakiye`             | Nakit, hisse, toplam bakiye gosterme      | `borsa()` — `bakiye` komutu |
| `adaptor_emirleri_listele`   | Bekleyen emir listesi                     | `borsa()` — `emirler` komutu|
| `adaptor_emir_gonder`        | Yeni emir (alis/satis)                    | `borsa()` — `emir` komutu   |
| `adaptor_emir_iptal`         | Bekleyen emri iptal etme                  | `borsa()` — `iptal` komutu  |
| `adaptor_oturum_gecerli_mi`  | Oturum hala gecerli mi kontrolu           | `cekirdek_hesap`             |
| `adaptor_oturum_suresi_parse`| Giris yanitindan oturum suresini cikar    | `adaptor_giris` icinden      |

### 4.2 Istege Bagli Fonksiyonlar

Cekirdek `declare -f` ile varligini kontrol eder. Yoksa ya varsayilan davranis uygular ya da
"desteklenmiyor" mesaji verir. Yeni kurum eklerken bunlarin hepsini yazmak zorunlu degildir:

| Fonksiyon                    | Yoksa Ne Olur                             | Aciklama                     |
| ---------------------------- | ----------------------------------------- | ---------------------------- |
| `adaptor_portfoy`            | "Desteklenmiyor" hatasi                   | Hisse detay listesi          |
| `adaptor_halka_arz_liste`    | "Desteklenmiyor" hatasi                   | Aktif halka arz listesi      |
| `adaptor_halka_arz_talepler` | "Desteklenmiyor" hatasi                   | Taleplerim listesi           |
| `adaptor_halka_arz_talep`    | "Desteklenmiyor" hatasi                   | Yeni talep girisi            |
| `adaptor_halka_arz_iptal`    | "Desteklenmiyor" hatasi                   | Talep iptali                 |
| `adaptor_halka_arz_guncelle` | "Desteklenmiyor" hatasi                   | Talep guncelleme             |
| `adaptor_oturum_uzat`        | Koruma dongusu sessiz GET atar            | Oturum uzatma callbacki      |
| `adaptor_cikis`              | Yalnizca yerel temizlik yapilir           | LogOff istegi                |
| `adaptor_hesap`              | `cekirdek_hesap` kullanilir               | Hesap gecis                  |
| `adaptor_hesaplar`           | `cekirdek_hesaplar` kullanilir            | Kayitli oturumlar            |
| `adaptor_hisse_bilgi_al`     | Fiyat kaynagindan sorgulanir              | Sembol fiyat sorgulama       |

### 4.3 Fonksiyon Imzalari ve Cikti Sozlesmesi

Her zorunlu fonksiyonun beklenen parametreleri ve ciktisi:

```
adaptor_giris <musteri_no> <parola>
  - Basariliysa: oturum suresini cekirdek_oturum_suresi_kaydet ile kaydet
  - Basariliysa: cekirdek_son_istek_guncelle cagir
  - Donus: 0=basarili, 1=basarisiz

adaptor_bakiye
  - _borsa_veri_sifirla_bakiye cagir
  - Parse edilen degerleri _borsa_veri_kaydet_bakiye ile kaydet
  - Cikiyi cekirdek_yazdir_portfoy ile goster
  - Donus: 0=basarili, 1=basarisiz

adaptor_portfoy
  - _borsa_veri_sifirla_portfoy cagir
  - Her hisse icin _borsa_veri_kaydet_hisse cagir
  - TAB ayricli satirlar olustur: SEMBOL\tLOT\tSON_FIYAT\tPIY_DEGERI\tMALIYET\tKAR\tKAR%
  - Cikiyi cekirdek_yazdir_portfoy_detay ile goster
  - Donus: 0=basarili, 1=basarisiz

adaptor_emir_gonder <sembol> <alis|satis> <lot> <fiyat|piyasa> [bildirim]
  - _borsa_veri_sifirla_son_emir cagir
  - KURU_CALISTIR=1 modunu destekle
  - Basariliysa: _borsa_veri_kaydet_son_emir ile kaydet
  - Cikiyi cekirdek_yazdir_emir_sonuc ile goster
  - Donus: 0=basarili, 1=basarisiz

adaptor_emirleri_listele
  - _borsa_veri_sifirla_emirler cagir
  - _borsa_veri_kaydet_emir ile her emri kaydet
  - Cikiyi cekirdek_yazdir_emir_listesi ile goster
  - Donus: 0=basarili, 1=basarisiz

adaptor_emir_iptal <referans_veya_id>
  - Cikiyi cekirdek_yazdir_emir_iptal ile goster
  - Donus: 0=basarili, 1=basarisiz

adaptor_oturum_gecerli_mi [musteri_no]
  - Donus: 0=gecerli, 1=gecersiz (stdout yok)

adaptor_oturum_suresi_parse <html_icerigi>
  - stdout: saniye cinsinden oturum suresi
```

## 5. Komut Yonlendirme Mimarisi

Kullanici `borsa <kurum> <komut>` yazdiginda cekirdekteki `borsa()` fonksiyonu calir.
Bu fonksiyon adaptoru yukler ve komutu yonlendirir.

### 5.1 Yukleme Akisi

```
1. borsa() cagirilir
2. kurum adi ile adaptor dosyasi bulunur: adaptorler/<kurum>.sh
3. source "$surucu_dosyasi" ile adaptor yuklenir
4. Adaptor source edildiginde:
   a. ADAPTOR_ADI ve ADAPTOR_SURUMU set edilir
   b. <kurum>.ayarlar.sh source edilir (tum sabitler yuklenir)
   c. cekirdek_adaptor_kaydet "<kurum>" cagirilir (sarmalayicilar olusur)
5. Komut case blogunda eslestirilerek adaptor_* fonksiyonu cagirilir
```

### 5.2 Komut-Fonksiyon Esleme Tablosu

Cekirdekteki `borsa()` fonksiyonu asagidaki eslemeyi yapar.
Yeni komut eklemek icin **hem bu tabloya hem de cekirdekteki case bloguna** ekleme yapilmalidir:

| Kullanici Komutu            | Cagirilan Fonksiyon          | Ek Islem (cekirdek)                    |
| --------------------------- | ---------------------------- | --------------------------------------- |
| `borsa X giris [-o]`       | `adaptor_giris`              | VT log + oturum koruma (opsiyonel)      |
| `borsa X bakiye`           | `adaptor_bakiye`             | VT bakiye kaydi (robot modunda)         |
| `borsa X portfoy`          | `adaptor_portfoy`            | VT pozisyon kaydi (robot modunda)       |
| `borsa X emir ...`         | `adaptor_emir_gonder`        | BIST pazar kontrolu + VT emir kaydi     |
| `borsa X emirler`          | `adaptor_emirleri_listele`   | VT emir durum guncelleme (robot modunda)|
| `borsa X iptal ...`        | `adaptor_emir_iptal`         | —                                       |
| `borsa X arz liste`        | `adaptor_halka_arz_liste`    | —                                       |
| `borsa X arz talepler`     | `adaptor_halka_arz_talepler` | —                                       |
| `borsa X arz talep ...`    | `adaptor_halka_arz_talep`    | VT halka arz kaydi (robot modunda)      |
| `borsa X arz iptal ...`    | `adaptor_halka_arz_iptal`    | VT halka arz kaydi (robot modunda)      |
| `borsa X arz guncelle ...` | `adaptor_halka_arz_guncelle` | VT halka arz kaydi (robot modunda)      |
| `borsa X hesap [no]`       | `adaptor_hesap` / `cekirdek_hesap`     | —                              |
| `borsa X hesaplar`         | `adaptor_hesaplar` / `cekirdek_hesaplar`| —                             |
| `borsa X fiyat SEMBOL`     | `adaptor_hisse_bilgi_al`     | Yoksa fiyat kaynagi kullanilir          |
| `borsa X cikis HESAP`      | `adaptor_cikis`              | Koruma durdurma + VT log                |

### 5.3 Otomatik Kurum Kesfi

Cekirdek kurumlari `adaptorler/*.sh` dosyalarindan otomatik kesfeder:

```
cekirdek_kurumlari_listele()
  -> adaptorler/*.sh dosyalarini tarar
  -> *.ayarlar.sh dosyalarini atlar
  -> Kalan dosya adlarini kurum adi olarak dondurur
```

Bu sayede yeni adaptor eklendiginde `borsa` komutunun yardim metninde otomatik listelenir.
Tab tamamlama da `tamamlama.sh` uzerinden ayni mekanizmayla calisir.

## 6. Adaptor Kayit Mekanizmasi

Her adaptor dosyasinin basi asagidaki adimlar olmalidir:

```bash
#!/bin/bash
# shellcheck shell=bash

# <Kurum> Adaptoru
# Bu dosya dogrudan calistirilmaz, cekirdek.sh tarafindan yuklenir.

# shellcheck disable=SC2034
if [[ "${ADAPTOR_ADI:-}" != "<kurum>" ]]; then
    ADAPTOR_ADI="<kurum>" 2>/dev/null || true
fi
if [[ "${ADAPTOR_SURUMU:-}" != "1.0.0" ]]; then
    ADAPTOR_SURUMU="1.0.0" 2>/dev/null || true
fi

# Ayarlar dosyasini yukle
source "${BORSA_KLASORU}/adaptorler/<kurum>.ayarlar.sh"

# Ince sarmalayicilari otomatik olustur
cekirdek_adaptor_kaydet "<kurum>"
```

`cekirdek_adaptor_kaydet` cagrisi asagidaki fonksiyonlari otomatik olusturur:
- `_<kurum>_oturum_dizini` -> `cekirdek_oturum_dizini`
- `_<kurum>_dosya_yolu` -> `cekirdek_dosya_yolu`
- `_<kurum>_aktif_hesap_kontrol` -> `cekirdek_aktif_hesap_kontrol`
- `_<kurum>_log` -> `cekirdek_adaptor_log`
- `_<kurum>_cookie_guvence` -> `cekirdek_cookie_guvence`

Bu sayede adaptor icindeki fonksiyonlar `_<kurum>_log "mesaj"` gibi kisa cagrilar kullanabilir.

### 6.1 Cikti Bicimlemesi Kurali (KRITIK)

Adaptorde **kesinlikle** `echo "======..."` gibi ham cerceve/kutu/tablo ciktisi yazilmaz.
Kullaniciya gosterilen tum bicimlendirilmis ciktilar cekirdekteki `cekirdek_yazdir_*`
fonksiyonlari uzerinden yapilir. Bu kural Bolum 2.2'deki "Cikti bicimlemesi cekirdege aittir"
ilkesinin somut uygulamasidir.

**Neden:**
- Cikti formati degistiginde (ornegin cerceve karakteri, sutun genisligi) yalnizca
  cekirdek guncellenir; adaptore dokunulmaz.
- Farkli kurumlarda ayni islem (emir listesi, halka arz, 2FA istegi) tutarli gorunur.
- Yeni adaptor yazilirken echo bloklari kopyalanmaz, tek satirlik cekirdek cagrisi yapilir.

**Kurallar:**

1. `echo "========..."` ile baslik/altlik cizen bloklar adaptor icinde **YASAKTIR**.
   Bunun yerine asagidaki cekirdek fonksiyonlari kullanilir:

   | Kullanim Alani         | Cekirdek Fonksiyonu                      |
   | ---------------------- | ---------------------------------------- |
   | 2FA / SMS / OTP istegi | `cekirdek_yazdir_oturum_bilgi`           |
   | Oturum bilgi mesaji    | `cekirdek_yazdir_oturum_bilgi`           |
   | Genel bilgi kutusu     | `cekirdek_yazdir_bilgi_kutusu`           |
   | Bakiye ozeti           | `cekirdek_yazdir_portfoy`                |
   | Hisse detay tablosu    | `cekirdek_yazdir_portfoy_detay`          |
   | Emir sonucu            | `cekirdek_yazdir_emir_sonuc`             |
   | Emir iptal             | `cekirdek_yazdir_emir_iptal`             |
   | Emir listesi           | `cekirdek_yazdir_emir_listesi`           |
   | Halka arz listesi      | `cekirdek_yazdir_halka_arz_liste`        |
   | Halka arz talepler     | `cekirdek_yazdir_halka_arz_talepler`     |
   | Halka arz talep sonucu | `cekirdek_yazdir_arz_sonuc`              |
   | Giris basarili         | `cekirdek_yazdir_giris_basarili`         |
   | Portfoyde hisse yok    | `cekirdek_yazdir_portfoy_bos`            |

2. Eger mevcut cekirdek fonksiyonlari bir cikti ihtiyacini karsilamiyorsa,
   **once cekirdege yeni yazdir fonksiyonu eklenir**, sonra adaptorden cagirilir.
   Adaptor icine gecici echo blogu konulmaz.

3. Tek satirlik hata mesajlari (`echo "HATA: ..."`) ve basit kullanim bilgileri
   (`echo "Kullanim: ..."`) bu kuraldan muaftir. Bunlar bicimlendirilmis cikti
   degil, duz metin ciktisidir.

4. Adaptor icinde siralama tablosu (emir listesi, halka arz) gosterilecekse
   veriler once bir degiskende toplanir, sonra toplu olarak ilgili
   `cekirdek_yazdir_*` fonksiyonuna gonderilir.

Bu kural, mimari incelemelerde en sik ihlal edilen noktadir. Ozellikle
yapay zeka ile adaptor kodu uretilirken ham echo bloklari kopyalanma egilimindedir.
Yeni adaptor yazilirken veya mevcut adaptor duzenlenirken Bolum 10.3'teki
cikti fonksiyonlari tablosuna bakilmalidir.

### 6.2 MEVCUT FONKSIYONU KULLAN, YENISINI YARATMA (KRITIK — AI HATASI ONLEME)

**SORUN:** Yapay zeka, adaptor kodundaki bir ciktiyi duzeltirken mevcut cekirdek
fonksiyonu yerine YENI bir cekirdek fonksiyonu yaratma egilimindedir. Bu gercek
bir vaka uzerinden 5 prompt harcanarak tespit edilmistir:

- osmanli.sh'deki 2FA echo blogu duzeltilecekti.
- AI, mevcut `cekirdek_yazdir_oturum_bilgi` fonksiyonunu kullanmak yerine
  yeni `cekirdek_yazdir_2fa_istegi` fonksiyonu yaratti.
- Ayni is icin ziraat.sh zaten `cekirdek_yazdir_oturum_bilgi` kullaniyordu.
- Sonuc: Gereksiz fonksiyon, gereksiz kod, 5 prompt israf.

**KURAL — ZORUNLU ADIMLAR (SIRALAMA DEGISMEYECEK):**

1. **ONCE mevcut cekirdek fonksiyonlarini tara.** Bolum 10.3'teki tabloyu oku.
   `cekirdek_yazdir_*` ile baslayan tum fonksiyonlarin imzalarini kontrol et.
   `grep "^cekirdek_yazdir_" cekirdek.sh` calistir.

2. **REFERANS ADAPTORU KONTROL ET.** Ayni islemi yapan baska bir adaptor var mi?
   (ornek: ziraat.sh). O adaptor hangi fonksiyonu kullaniyorsa seni de onu kullan.
   Referans adaptor simdilik ziraat.sh'dir. Yeni adaptor yazilirken ziraat.sh'nin
   yaklasimi temel alinir.

3. **KESINLIKLE eslesen bir fonksiyon yoksa** ve yenisini yaratmak gerekiyorsa,
   bunu acikca kullaniciya bildir ve teyit al. Teyit almadan cekirdege yeni
   fonksiyon EKLEME.

**YASAK DAVRANISLAR:**

- Mevcut fonksiyonun isminden farkli bir isimle ayni isi yapan fonksiyon yaratmak.
  (ornek: `cekirdek_yazdir_oturum_bilgi` varken `cekirdek_yazdir_2fa_istegi` yaratmak)
- "Daha spesifik olsun" diye mevcut jenerik fonksiyonu sarmalayen yeni fonksiyon yaratmak.
- Referans adaptordeki (ziraat.sh) cozumu kontrol etmeden yeni fonksiyon olusturmak.
- Kullanicidan teyit almadan cekirdege yeni `cekirdek_yazdir_*` fonksiyonu eklemek.

**NEDEN BU KADAR ONEMLI:**

- Cekirdek her yeni fonksiyonla buyur, bakimi zorrasir.
- Ayni isi yapan iki fonksiyon adaptorler arasinda tutarsizlik yaratir.
- Kullanici bu tur hatalari tespit etmek icin zaman harcar (5 prompt = 5 duzeltme turu).
- Bu hata tekrar ederse proje uzerinde yapay zeka ile calismak verimsiz hale gelir.

## 7. Jenerik Kalip Sablonlari

Asagidaki sablonlar yeni adaptor yazarken kullanilacak standart kaliplardir.
Her sablon cekirdek fonksiyonlarini dogru sirada kullanir.

### 7.1 Giris Akisi Sablonu

Her kurumun giris akisi farklidir (form alanlari, 2FA yontemi) ancak iskelet aynidir:

```bash
adaptor_giris() {
    local musteri_no="$1"
    local parola="$2"

    # 1. Parametre kontrolu
    [[ -z "$musteri_no" || -z "$parola" ]] && { echo "Kullanim: ..."; return 1; }

    # 2. Oturum dizinini hazirla
    cekirdek_aktif_hesap_ayarla "<kurum>" "$musteri_no"
    _<kurum>_oturum_dizini "$musteri_no" > /dev/null

    # 3. Mevcut oturum gecerli mi?
    if adaptor_oturum_gecerli_mi "$musteri_no"; then
        cekirdek_yazdir_oturum_bilgi "OTURUM ZATEN ACIK" ...
        return 0
    fi

    # 4. Giris sayfasini cek (CSRF token al)
    local cookie_dosyasi
    cookie_dosyasi=$(_<kurum>_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")
    # ... sayfa cek, token parse et ...

    # 5. Giris POST istegi gonder
    # ... cekirdek_istek_at ile POST ...

    # 6. Yaniti analiz et (basari / hata / SMS / CAPTCHA)
    # ... kuruma ozgu parse ...

    # 7. Basarili giris sonrasi:
    cekirdek_oturum_suresi_kaydet "<kurum>" "$musteri_no" "$oturum_suresi"
    cekirdek_son_istek_guncelle "<kurum>" "$musteri_no"
}
```

### 7.2 Bakiye Akisi Sablonu

```bash
adaptor_bakiye() {
    # 1. Oturum kontrolu
    _<kurum>_aktif_hesap_kontrol || return 1

    # 2. Portfoy sayfasini HTTP ile cek
    local cookie_dosyasi
    cookie_dosyasi=$(_<kurum>_dosya_yolu "$_CEKIRDEK_DOSYA_COOKIE")
    local yanit
    yanit=$(cekirdek_istek_at -c "$cookie_dosyasi" -b "$cookie_dosyasi" "$_<KURUM>_PORTFOY_URL")

    # 3. Boyut ve oturum yonlendirme kontrolu
    cekirdek_boyut_kontrol "$yanit" 2000 "Portfoy sayfasi" "$ADAPTOR_ADI" || return 1

    # 4. HTML/JSON parse (kuruma ozgu secicilerle)
    _borsa_veri_sifirla_bakiye
    local nakit hisse toplam
    # ... parse ...

    # 5. Saglik kontrolu
    cekirdek_saglik_kontrol "$ADAPTOR_ADI" "200" "$yanit" "$debug_dosyasi" \
        "$nakit" "$hisse" "$toplam" "Portfoy" || return 1

    # 6. Veri katmanina kaydet + goruntule
    _borsa_veri_kaydet_bakiye "$nakit" "$hisse" "$toplam"
    cekirdek_yazdir_portfoy "$ADAPTOR_ADI" "$nakit" "$hisse" "$toplam"
}
```

### 7.3 Emir Gonderme Akisi Sablonu

```bash
adaptor_emir_gonder() {
    local sembol="$1" islem="$2" lot="$3" fiyat="$4"
    _borsa_veri_sifirla_son_emir

    # 1. Parametre dogrulama
    # 2. Emir turu tespiti (limit / piyasa)
    # 3. Sayi dogrulama: cekirdek_sayi_dogrula
    # 4. Kuruma ozgu kontroller (seans disi tutar vb.)
    # 5. BIST fiyat adimi dogrulama: bist_emir_dogrula (limit emirlerde)
    # 6. KURU_CALISTIR modu kontrolu — gercek emir gonderilmez
    # 7. Emir sayfasini cek — CSRF + hesap ID al
    # 8. Form POST et (wizard akisi varsa cok adimli)
    # 9. Yaniti kontrol et — hata / basari / onay sayfasi
    # 10. _borsa_veri_kaydet_son_emir ile kaydet
    # 11. cekirdek_yazdir_emir_sonuc ile goruntule
}
```

### 7.4 Hata Isleme Sablonu

Tum adaptor fonksiyonlari ayni hata desenini izlemelidir:

```bash
# Boyut kontrolu — yanit cok kucukse sunucu sorunu
cekirdek_boyut_kontrol "$yanit" 500 "<Baglam>" "$ADAPTOR_ADI" || return 1

# Oturum yonlendirme — login sayfasina mi yonlendi?
cekirdek_oturum_yonlendirme_kontrol "$yanit" "Account/Login" "$ADAPTOR_ADI" || return 1

# CSRF token — form icin zorunlu
local csrf
csrf=$(cekirdek_csrf_cikar "$yanit" "$_<KURUM>_SEL_CSRF_TOKEN" "<Baglam>" "$ADAPTOR_ADI") || return 1

# JSON yanit — AJAX endpoint sonucu
local mesaj
mesaj=$(cekirdek_json_sonuc_isle "$yanit")
case $? in
    0) echo "Basarili: $mesaj" ;;
    1) echo "Hata: $mesaj"; return 1 ;;
    2) echo "Belirsiz: $mesaj"; return 1 ;;
esac

# HTML hata — form dogrulama hatalari
local hata
hata=$(_<kurum>_html_hata_cikar "$yanit")
[[ -n "$hata" ]] && { echo "HATA: $hata"; return 1; }
```

## 8. Yeni Araci Kurum Ekleme Rehberi

### 8.1 Hazirlik Asamasi

Yeni kurum eklemeden once yapilmasi gerekenler:

1. Kurumun web arayuzune tarayicida giris yap.
2. Tarayicinin DevTools > Network sekmesini ac.
3. Asagidaki akislari kaydet ve analiz et:
   - Giris formu: URL, POST alanlari, CSRF token konumu, 2FA yontemi.
   - Portfoy sayfasi: URL, bakiye HTML ID'leri, hisse tablosu yapisi.
   - Emir formu: URL, form alanlari, wizard adim sayisi, AJAX endpoint'ler.
   - Emir listesi: URL, tablo yapisi, referans ID konumu.
4. Her akistaki HTML/JSON yapilarini belgele.
5. Session yonetimini anla: cookie mi, header token mi, session GUID mi.

### 8.2 Dosya Olusturma Sirasi

Yeni kurum eklerken dosyalar su sirada olusturulur:

```
Adim 1: adaptorler/<kurum>.ayarlar.sh  (tum URL ve seciciler)
Adim 2: adaptorler/<kurum>.sh          (adaptor mantigi)
Adim 3: (gerekirse) cekirdek.sh        (yeni komut varsa case bloguna ekle)
Adim 4: tamamlama.sh                   (tab tamamlama — otomatik kesfedilir)
```

Adim 1-2 disinda baska dosyaya dokunmak **gerekmez** cunku:
- Kurum kesfedilmesi otomatik (`cekirdek_kurumlari_listele`).
- Komut yonlendirme jenerik (`adaptor_*` fonksiyon adlari sabit).
- Oturum yonetimi jenerik (`cekirdek_adaptor_kaydet` ile).
- Cikti bicimlemesi jenerik (`cekirdek_yazdir_*` ile).

### 8.3 Adim Adim Uygulama

**Adim 1: Ayarlar dosyasini olustur**

`adaptorler/<kurum>.ayarlar.sh` dosyasi asagidaki bolumleri icermelidir:

```bash
#!/bin/bash
# shellcheck shell=bash
# <Kurum> Adaptoru - Ayarlar Dosyasi

# BOLUM 1: SUNUCU AYARLARI
_<KURUM>_BASE_URL="https://..."
_<KURUM>_LOGIN_URL="${_<KURUM>_BASE_URL}/..."
_<KURUM>_ANA_SAYFA_URL="${_<KURUM>_BASE_URL}/..."
_<KURUM>_PORTFOY_URL="${_<KURUM>_BASE_URL}/..."
_<KURUM>_EMIR_URL="${_<KURUM>_BASE_URL}/..."
_<KURUM>_EMIR_LISTE_URL="${_<KURUM>_BASE_URL}/..."
_<KURUM>_EMIR_IPTAL_URL="${_<KURUM>_BASE_URL}/..."

# BOLUM 2: HTML SECICILER
_<KURUM>_SEL_CSRF_TOKEN='name="__Token"[^>]*value="\K[^"]+'
_<KURUM>_SEL_SESSION_GUID='...'
_<KURUM>_KALIP_HATALI_GIRIS='...'
_<KURUM>_KALIP_BASARILI_HTML='...'

# BOLUM 3: EMIR ALANLARI
_<KURUM>_EMIR_ALIS="..."
_<KURUM>_EMIR_SATIS="..."

# BOLUM 4: KURUM KURALLARI (varsa)
# Kuruma ozgu kisitlamalar burada tanimlanir
```

**Adim 2: Adaptor dosyasini olustur**

Dosyanin basi Bolum 6'daki kayit sablonuyla baslar, sonra zorunlu fonksiyonlar yazilir.
Her fonksiyon icin Bolum 7'deki ilgili sablon kullanilir.
Minimum uygulanmasi gereken fonksiyonlar:

1. `adaptor_oturum_gecerli_mi` — en basit: cookie ile ana sayfaya GET at, session kontrol et.
2. `adaptor_giris` — giris akisi (kuruma ozgu).
3. `adaptor_bakiye` — portfoy sayfasini parse et.
4. `adaptor_emirleri_listele` — emir tablosunu parse et.
5. `adaptor_emir_gonder` — emir formunu POST et.
6. `adaptor_emir_iptal` — iptal endpoint'ine POST/AJAX at.
7. `adaptor_oturum_suresi_parse` — giris yanitindan timeout cikar.

### 8.4 Kontrol Listesi

- [ ] `ADAPTOR_ADI` ve `ADAPTOR_SURUMU` tanimli mi?
- [ ] Ayarlar dosyasi ayri mi (fonksiyon yok, yalnizca sabitler)?
- [ ] `cekirdek_adaptor_kaydet` cagrildi mi?
- [ ] Adaptor icinde `echo "===..."` ile cerceveli cikti blogu yok mu (Bolum 6.1)?
- [ ] Tum bicimlendirilmis ciktilar `cekirdek_yazdir_*` fonksiyonlariyla mi yapiliyor?
- [ ] Emir listesi, halka arz gibi tablolar cekirdek yazdir fonksiyonuna delege ediliyor mu?
- [ ] Tum 7 zorunlu `adaptor_*` fonksiyonu tanimli mi?
- [ ] `cekirdek_istek_at` uzerinden HTTP istegi atiliyor mu (dogrudan curl yok)?
- [ ] `_borsa_veri_kaydet_*` ile veri yapilarina yaziliyor mu?
- [ ] `_borsa_veri_sifirla_*` her fonksiyonun basinda cagiriliyor mu?
- [ ] Hata durumlarinda anlamli mesaj ve return 1 donuyor mu?
- [ ] `cekirdek_boyut_kontrol`, `cekirdek_csrf_cikar`, `cekirdek_oturum_yonlendirme_kontrol` kullaniliyor mu?
- [ ] Ciktilar `cekirdek_yazdir_*` fonksiyonlariyla mi gosteriliyor?
- [ ] `KURU_CALISTIR` modu destekleniyor mu (emir gonderme)?
- [ ] Shellcheck hatasi yok mu?
- [ ] Dahili fonksiyonlar `_<kurum>_` oneki tasiyor mu?
- [ ] Sabitlerin hepsi `_<KURUM>_` oneki tasiyor mu?
- [ ] Seciciler `_<KURUM>_SEL_*` oneki tasiyor mu?
- [ ] `borsa <kurum> giris` + `borsa <kurum> bakiye` testi basarili mi?

## 9. Mevcut Adaptore Yeni Ozellik Ekleme

### 9.1 Adaptore Ozgu Ozellik (tek kurumu etkiler)

Ornek: Ziraat'in halka arz modulu gibi yalnizca bir kuruma ait ozellik.

Yapilmasi gerekenler:

1. Ayarlar dosyasina yeni URL ve secicileri ekle (yeni BOLUM acilabilir).
2. Adaptor dosyasina yeni `adaptor_*` fonksiyonu ekle.
3. Cekirdekteki `borsa()` case blogunda yeni komutu esle.
4. `declare -f` kontrolu ile istege bagli yap (diger adaptorler etkilenmesin).

Cekirdege eklenmesi gereken kod ornegi (istege bagli komut):

```bash
# borsa() icinde, case blogunda:
yeni_komut)
    if declare -f adaptor_yeni_komut > /dev/null; then
        adaptor_yeni_komut "$@"
    else
        echo "HATA: '$kurum' surucusu 'yeni_komut' komutunu desteklemiyor."
        return 1
    fi
    ;;
```

### 9.2 Jenerik Ozellik (tum adaptorleri etkiler)

Ornek: tum kurumlara "transfer" komutu eklemek.

Yapilmasi gerekenler:

1. **Cekirdekte**: `borsa()` case bloguna yeni komut ekle (declare -f ile istege bagli).
2. **Cekirdekte**: `cekirdek_yazdir_*` fonksiyonu ekle (cikti bicimi).
3. **Cekirdekte**: Veri katmanina yeni kayit fonksiyonlari ekle (gerekiyorsa).
4. **Arabirim sozlesmesine**: Bu plan dosyasinin 4.2 tablosuna yeni fonksiyonu ekle.
5. **Her adaptorde**: `adaptor_yeni_komut` fonksiyonunu yaz (kuruma ozgu parse).

Onemli: Yeni jenerik ozellik eklerken `declare -f` kontrolu kullanilmalidir.
Boylece henuz guncellenmeyen adaptorler bozulmaz, sadece "desteklenmiyor" der.

### 9.3 Site Degisikligi Durumunda Guncelleme

Kurum web sitesini guncellediginde:

1. **Yalnizca ayarlar dosyasinda** secici/URL degisikligi yeterli mi kontrol et.
2. Yetersizse adaptor dosyasindaki parse mantigi guncellenir.
3. **Cekirdege dokunulmaz** — sorumluluk ayrimi bunu garantiler.

Tipik site degisikligi ornekleri:

| Degisiklik                    | Duzenlenecek Dosya        |
| ----------------------------- | ------------------------- |
| URL degisti                   | `<kurum>.ayarlar.sh`      |
| HTML ID degisti               | `<kurum>.ayarlar.sh`      |
| Yeni form alani eklendi       | `<kurum>.ayarlar.sh`      |
| Form yapisi tamamen degisti   | `<kurum>.sh` (parse)      |
| CSRF mekanizmasi degisti      | `<kurum>.sh` (parse)      |
| Yeni 2FA adimi eklendi        | `<kurum>.sh` (giris)      |
| JSON API'ye gecildi           | `<kurum>.sh` (tum parse)  |

## 10. Cekirdek Yardimci Fonksiyon Referansi

Adaptor gelistirirken kullanilmasi gereken cekirdek fonksiyonlari ve ne zaman kullanilacaklari:

### 10.1 HTTP ve Oturum

| Fonksiyon                           | Ne zaman                           |
| ----------------------------------- | ---------------------------------- |
| `cekirdek_istek_at [curl_args] URL` | Her HTTP isteginde (curl yerine)   |
| `cekirdek_oturum_dizini K [H]`     | Oturum dosya yolu gerektiginde     |
| `cekirdek_dosya_yolu K D [H]`      | Dosya tam yolu gerektiginde        |
| `cekirdek_aktif_hesap_ayarla K H`   | Giris sirasinda                    |
| `cekirdek_aktif_hesap K`            | Aktif hesap numarasi gerektiginde  |
| `cekirdek_aktif_hesap_kontrol K`    | Fonksiyon basinda oturum kontrolu  |
| `cekirdek_cookie_guvence K`         | Cookie yazilmasindan sonra         |

### 10.2 Dogrulama ve Parse

| Fonksiyon                                 | Ne zaman                              |
| ----------------------------------------- | ------------------------------------- |
| `cekirdek_boyut_kontrol Y E B K`          | Yanit boyutu kontrolu                 |
| `cekirdek_oturum_yonlendirme_kontrol Y P K`| Login'e redirect kontrolu            |
| `cekirdek_csrf_cikar H S B K`             | CSRF token cikarma                    |
| `cekirdek_json_sonuc_isle Y [EK]`         | JSON API yanit parse                  |
| `cekirdek_sayi_dogrula D I K`             | Sayi dogrulamasi                      |
| `cekirdek_saglik_kontrol K H Y D N Hi T ...`| Cok katmanli bakiye kontrolu        |

### 10.3 Cikti Bicimlemesi

| Fonksiyon                                   | Ne zaman                  |
| ------------------------------------------- | ------------------------- |
| `cekirdek_yazdir_portfoy K N H T`           | Bakiye ozeti              |
| `cekirdek_yazdir_portfoy_detay K N H T S`   | Hisse detay tablosu       |
| `cekirdek_yazdir_portfoy_bos N`             | Bos portfoy               |
| `cekirdek_yazdir_emir_sonuc B S I L F T D [R]`| Emir sonucu            |
| `cekirdek_yazdir_emir_iptal R T D [M]`      | Iptal sonucu              |
| `cekirdek_yazdir_oturum_bilgi B [A D ...]`   | Oturum mesaji             |
| `cekirdek_yazdir_giris_basarili K`           | Giris basari mesaji       |
| `cekirdek_yazdir_emir_listesi K S B`           | Emir listesi tablosu      |
| `cekirdek_yazdir_halka_arz_liste K L S`      | Halka arz listesi         |
| `cekirdek_yazdir_arz_sonuc B [A D ...]`      | Halka arz talep sonucu    |
| `cekirdek_yazdir_bilgi_kutusu B [A D ...]`   | Genel bilgi kutusu        |

### 10.4 Veri Katmani

| Fonksiyon                                   | Ne zaman                  |
| ------------------------------------------- | ------------------------- |
| `_borsa_veri_sifirla_bakiye`                 | `adaptor_bakiye` basinda  |
| `_borsa_veri_kaydet_bakiye N H T`            | Bakiye parse sonrasi      |
| `_borsa_veri_sifirla_portfoy`                | `adaptor_portfoy` basinda |
| `_borsa_veri_kaydet_hisse S L F D M K KY`    | Her hisse parse sonrasi   |
| `_borsa_veri_sifirla_son_emir`               | `adaptor_emir_gonder` basinda |
| `_borsa_veri_kaydet_son_emir B R S Y L F P M`| Emir sonucu sonrasi      |
| `_borsa_veri_sifirla_emirler`                | `adaptor_emirleri_listele` basinda |
| `_borsa_veri_kaydet_emir ...`                | Her emir parse sonrasi    |

### 10.5 BIST Kurallari

| Fonksiyon                        | Ne zaman                           |
| -------------------------------- | ---------------------------------- |
| `bist_emir_dogrula FIYAT`        | Emir gonderme oncesi fiyat kontrolu|
| `bist_fiyat_gecerli_mi FIYAT`    | Fiyat adimi dogrulamasi            |
| `bist_pazar_emir_kontrol P T S`  | Pazar-emir uyumluluk kontrolu      |

## 11. Mevcut Durum ve Iyilestirme Notlari

### 11.1 Ziraat Adaptoru

Tek uygulanan adaptor. 2033 satir (`ziraat.sh`) + 184 satir (`ziraat.ayarlar.sh`).
Tum zorunlu ve istege bagli fonksiyonlari uyguliyor.
Halka arz (talep, iptal, guncelle) destegi mevcut.

### 11.2 Olasi Iyilestirmeler

- Bazi parse fonksiyonlari (HTML tablo cikarma, `<tr>` blok ayristirma) birden fazla
  yerde tekrarlaniyor. Bunlar `cekirdek.sh`'a ortak yardimci olarak tasinabilir.
- Emir gonderme oncesi dogrulama adimlari (CSRF al, hesap ID cek, form doldur)
  cekirdekte soyutlanarak adaptor kodunu kisaltabilir.
- Halka arz islemleri benzer bir kalip izliyor (sayfa cek -> CSRF al -> form POST et).
  Bu kalip bir `cekirdek_form_gonder` akisina genellenebilir.
- `adaptor_oturum_uzat` tanimlanmamissa cekirdekteki koruma dongusu
  hardcode Ziraat URL'sine GET atiyor — bu jenerik hale getirilmeli.
