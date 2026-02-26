# DB Baglam Bayragi - Plan

NOT: Bu plan kismi revize edilmistir. Emirler ve halka arz islemleri artik
her zaman (manuel + robot) DB'ye kaydedilecek, bakiye/portfoy icin periyodik
snapshot mekanizmasi eklenecektir. Detaylar: db_yazim_politikasi.md

## 1. Sorun

`borsa ziraat portfoy` gibi manuel komutlar calistirildiginda `borsa()` fonksiyonu
icindeki `vt_pozisyon_kaydet`, `vt_bakiye_kaydet`, `vt_emir_kaydet` gibi DB yazim
cagrisi yapiliyor. Veritabani calissa da calismasa da bu davranis hatalidir.

Manuel komutlar kullanicinin terminalde deneme, kontrol veya bilgi amacli calistirdigi
komutlardir. Bunlarin DB'ye kaydedilmesi:

- Robotun tutarli strateji kayitlarini kirletir (gereksiz/yaniltici satirlar olusur).
- Ayni veri birden fazla kez yazilir (her `portfoy` cagrisinda tekrar kayit).
- Robot performans analizi ve K/Z raporlari yanlis sonuc verir.

DB yazimi sadece robot motoru tarafindan tetiklenen islemlerde yapilmalidir.
Manuel terminal komutlarinda DB'ye yazilmamalidir.

## 2. Cozum

Tek bir global degisken ile manuel/robot ayrimi yapilir:

```bash
_BORSA_BAGLAM_ROBOT=0
```

Robot motoru basladiginda bu degiskeni 1 yapar. `borsa()` fonksiyonundaki
tum `vt_*` cagrisi bu degiskeni kontrol eder.

## 3. Davranis Tablosu

| Senaryo | Bayrak | DB Yazimi |
|---|---|---|
| borsa ziraat portfoy (terminal) | 0 | Yazilmaz |
| borsa ziraat emir AKBNK alis 10 50 (terminal) | 0 | Yazilmaz |
| Robot motoru icinden ayni komutlar | 1 | Yazilir |
| borsa ziraat giris (terminal) | 0 | Oturum log YAZILIR (istisna) |

Giris komutu istisnadir: oturum kaydi guvenlik acisindan her zaman atilir.

## 4. Degistirilecek Dosyalar

### 4.1 cekirdek.sh - Bayrak Tanimi

Oturum yonetimi bolumune bayrak eklenir:

```bash
_BORSA_BAGLAM_ROBOT=0
```

### 4.2 cekirdek.sh - borsa() Fonksiyonu

Asagidaki case bloklarinda `vt_*` cagrilari bayrak kontrolune alinir:

| Blok | Mevcut cagri | Degisiklik |
|---|---|---|
| bakiye) | vt_bakiye_kaydet | Bayrak kontrolu ekle |
| emir) | vt_emir_kaydet | Bayrak kontrolu ekle |
| emirler) | vt_emir_durum_guncelle | Bayrak kontrolu ekle |
| portfoy) | vt_pozisyon_kaydet | Bayrak kontrolu ekle |
| arz) alt bloklari | vt_halka_arz_kaydet (3 yerde) | Bayrak kontrolu ekle |
| giris) | vt_oturum_log_yaz | Degismez (istisna) |

Her blokta degisiklik sablonu aynidir:

```diff
-    if declare -f vt_pozisyon_kaydet > /dev/null 2>&1; then
+    if [[ "$_BORSA_BAGLAM_ROBOT" -eq 1 ]] && declare -f vt_pozisyon_kaydet > /dev/null 2>&1; then
```

### 4.3 robot/motor.sh - Bayragi Aktiflestirme

Robot motoru `robot_baslat()` fonksiyonunda bayragi 1 yapar.
Robot durdugunca `robot_durdur()` bayragi 0 yapar.

## 5. Dogrulama

Manuel test: `borsa ziraat portfoy` sonrasinda DB uyarisi cikmamali.
Bayrak testi: `_BORSA_BAGLAM_ROBOT=1` ile ayni komut DB yazimi denemeli.
Giris istisna testi: `borsa ziraat giris` bayrak 0 olsa bile oturum logu yazilmali.
