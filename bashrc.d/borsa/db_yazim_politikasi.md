# DB Yazim Politikasi - Plan

## 1. Sorun

Mevcut sistemde `_BORSA_BAGLAM_ROBOT` bayragi tum DB yazim islemlerini robot moduna
kilitliyor. Manuel terminalden yapilan hicbir islem (emir gonderme dahil) veritabanina
kaydedilmiyor. Bu yaklasim robotun verilerini korumak icin tasarlandi ancak onemli
sorunlara yol aciyor:

- Terminalden gonderilen emirler kaybolur, gecmis emirler eksik kalir.
- Halka arz islemleri kaydedilmez.
- Bakiye/portfoy verisi periyodik alinmadigi icin gecmis raporlar bos kalir.
- `borsa gecmis kar`, `borsa gecmis emirler` gibi komutlar kullanisiz hale gelir.

Bu plan, `db_baglam_bayragi.md` dosyasindaki mevcut yaklasimi revize eder ve her
tablonun dogasina uygun bir yazim politikasi tanimlar.

## 2. Tasarim Ilkesi

Her tablo icin "veri nerede uretilir, ne siklikla degisir, kaybedilirse ne olur"
sorulari cevaplanir. Buna gore uc kategori belirlenir:

- Her zaman: Gercek para hareketi olan islemler. Kaybi kabul edilemez.
- Robot ve periyodik: Sik tekrarlanan okuma islemleri. Kullanici her cagirdiginda
  yazmak gereksiz tekrar olusturur, periyodik snapshot yeterlidir.
- Sadece kendi baglami: Belirli bir alt sisteme ait veriler. Diger baglamlarda
  yazilmasi anlamsizdir.

## 3. Kategori Tablosu

### 3.1 Her Zaman Yazilsin (Manuel + Robot)

| Tablo | Gerekcesi |
|-------|-----------|
| emirler | Gercek para hareketidir. Terminalden de gonderilse robottan da gonderilse kaydedilmeli. Gecmis emirler ve kar/zarar hesabi buna baglidir. |
| emirler (durum) | Emir listesi sorgulandiginda sunucudan donen gerceklesti/iptal/bekliyor durumlari DB'deki kayitlarla eslestirilmeli. Yoksa emir durumu hic guncellenmez. |
| halka_arz_islemleri | Gercek para hareketidir. Talep, iptal ve guncelleme islemleri kaybi kabul edilemez. |
| oturum_log | Guvenlik kaydidir. Zaten her zaman yaziliyor (mevcut istisna), degismeyecek. |

Bu tablolardaki `_BORSA_BAGLAM_ROBOT` bayrak kontrolu kaldirilacak. Fonksiyon mevcutsa
(`declare -f` kontrolu) her zaman cagrilacak.

### 3.2 Robot + Periyodik Snapshot (Manuel Komutta Yazilmasin)

| Tablo | Gerekcesi |
|-------|-----------|
| bakiye_gecmisi | Kullanici gun icinde onlarca kez `bakiye` sorabilir. Her sorguda ayni veriyi tekrar yazmak kirlilik olusturur. Bunun yerine oturum koruma dongusunde periyodik snapshot (15-30 dk aralikla) alinmasi tutarli ve temiz veri saglar. |
| pozisyonlar | Ayni mantik. Portfoy pozisyonlari gun ici seyrek degisir. Periyodik snapshot yeterlidir. Her sorguda ayni lot/fiyat bilgisini tekrar yazmak anlamsizdir. |

Bu tablolarda mevcut bayrak kontrolu korunacak. Ek olarak oturum koruma dongusune
periyodik snapshot mekanizmasi eklenecek.

### 3.3 Sadece Kendi Baglami (Degismesin)

| Tablo | Baglami | Gerekcesi |
|-------|---------|-----------|
| robot_log | Robot motoru | Robot yasam dongusu olaylaridir. Manuel kullanimin loglanmasi anlamsiz. |
| fiyat_gecmisi | Tarama katmani | Zaten fiyat kaynagindan periyodik dolduruluyor, bagimsiz calisir. |
| ohlcv | Tarama katmani | OHLCV mum verileri, tarama katmanina ait. |
| backtest_sonuclari | Backtest motoru | Backtest calistirma sonuclari. |
| backtest_islemleri | Backtest motoru | Backtest sanal islem kaydi. |
| backtest_gunluk | Backtest motoru | Gunluk equity curve verisi. |

Bu tablolarda degisiklik yapilmayacak, mevcut mekanizma korunacak.

## 4. Degistirilecek Dosyalar

### 4.1 cekirdek.sh - Bayrak Kontrolu Kaldirma (Kategori 1)

`emir)`, `emirler)` ve `arz)` case bloklarindaki `_BORSA_BAGLAM_ROBOT` kontrolu
kaldirilacak. Sadece `declare -f` kontrolu kalacak.

Toplam 5 degisiklik noktasi:

```diff
 # emir) blogu — satir 1833
-    if [[ "${_BORSA_BAGLAM_ROBOT:-0}" -eq 1 ]] && declare -f vt_emir_kaydet > /dev/null 2>&1; then
+    if declare -f vt_emir_kaydet > /dev/null 2>&1; then
         vt_emir_kaydet ...
     fi

 # emirler) blogu — satir 1848
-    if [[ "${_BORSA_BAGLAM_ROBOT:-0}" -eq 1 ]] && declare -f vt_emir_durum_guncelle > /dev/null 2>&1; then
+    if declare -f vt_emir_durum_guncelle > /dev/null 2>&1; then
         ...emir durumlarini guncelle...
     fi

 # arz talep) blogu — satir 1907
-    if [[ "${_BORSA_BAGLAM_ROBOT:-0}" -eq 1 ]] && declare -f vt_halka_arz_kaydet > /dev/null 2>&1; then
+    if declare -f vt_halka_arz_kaydet > /dev/null 2>&1; then

 # arz iptal) blogu — satir 1928
-    if [[ "${_BORSA_BAGLAM_ROBOT:-0}" -eq 1 ]] && declare -f vt_halka_arz_kaydet > /dev/null 2>&1; then
+    if declare -f vt_halka_arz_kaydet > /dev/null 2>&1; then

 # arz guncelle) blogu — satir 1949
-    if [[ "${_BORSA_BAGLAM_ROBOT:-0}" -eq 1 ]] && declare -f vt_halka_arz_kaydet > /dev/null 2>&1; then
+    if declare -f vt_halka_arz_kaydet > /dev/null 2>&1; then
```

Yorumlar da guncellenir: "sadece robot modunda" yerine "veritabanina kaydet" yazilir.

### 4.2 cekirdek.sh - Periyodik Snapshot (Kategori 2)

`bakiye)` ve `portfoy)` bloklarindaki bayrak kontrolu korunacak (degisiklik yok).

Oturum koruma dongusune (`cekirdek_oturum_koruma_baslat` icindeki while-true) periyodik
bakiye+portfoy snapshot mekanizmasi eklenecek.

#### 4.2.1 Snapshot Araligi

Sabit sure tabanli hesaplama yapilir. Dongudeki `aralik` degiskeni hesaba gore
45-300 saniye arasi degisir. Snapshot icin sabit bir hedef sure belirlenir:

```bash
_CEKIRDEK_SNAPSHOT_ARALIK=900   # 900 saniye = 15 dakika
```

Dongude tur sayaci tutulur. Her turda `gecen_sure += aralik` hesaplanir.
`gecen_sure >= _CEKIRDEK_SNAPSHOT_ARALIK` oldugunda snapshot alinir ve sayac sifirlanir.

```bash
local snapshot_gecen=0
while true; do
    sleep "$aralik"
    # ... oturum uzatma kodu (mevcut, degismez) ...

    # Periyodik snapshot kontrolu
    snapshot_gecen=$(( snapshot_gecen + aralik ))
    if [[ "$snapshot_gecen" -ge "$_CEKIRDEK_SNAPSHOT_ARALIK" ]]; then
        _cekirdek_snapshot_al "$kurum" "$hesap"
        snapshot_gecen=0
    fi
done
```

Bu sayede dongudeki `aralik` ne olursa olsun (45s, 150s, 300s) snapshot her zaman
yaklasik 15 dakikada bir alinir.

#### 4.2.2 Aktif Hesap Izolasyonu

Oturum koruma dongusu `( ... ) &` ile fork edilmis subprocess olarak calisir.
Fork aninda shell degiskenlerinin bir kopyasini alir. Ana terminalde aktif hesap
degisse bile subprocess'in kopyasi etkilenmez.

Subprocess icinde snapshot almadan once kendi hesabini aktif olarak set eder:

```bash
_cekirdek_snapshot_al() {
    local kurum="$1"
    local hesap="$2"

    # Subprocess kendi kopyasinda aktif hesabi set eder.
    # Ana terminaldeki aktif hesabi ETKILEMEZ (fork izolasyonu).
    _CEKIRDEK_AKTIF_HESAPLAR["$kurum"]="$hesap"

    adaptor_bakiye > /dev/null 2>&1
    # ... vt_bakiye_kaydet ...

    adaptor_portfoy > /dev/null 2>&1
    # ... vt_pozisyon_kaydet ...
}
```

Fork izolasyonu sayesinde yan etki yoktur. Ana terminalde hangi hesap secili olursa
olsun subprocess her zaman kendi hesabinin verisini ceker.

#### 4.2.3 Bayrak Atlama Stratejisi

Snapshot fonksiyonu `borsa()` ana fonksiyonunu cagirmaz. Dogrudan adaptor ve
`vt_*` fonksiyonlarini cagirir. Bu sayede `_BORSA_BAGLAM_ROBOT` bayragi
kontrol edilmez, atlanmis olur.

Akis:

```
_cekirdek_snapshot_al
  -> adaptor_bakiye (veriyi bellek dizilerine yazar)
  -> vt_bakiye_kaydet (bellekteki veriyi DB'ye yazar)
  -> adaptor_portfoy (veriyi bellek dizilerine yazar)
  -> vt_pozisyon_kaydet (bellekteki veriyi DB'ye yazar, her sembol icin)
```

Bayrak sistemi sadece `borsa()` fonksiyonunun case bloklarinda kontrol edilir.
Dogrudan `vt_*` cagrisi yapildiginda bayrak devre disi kalir.

#### 4.2.4 Sessizlestirme

Adaptor fonksiyonlari stdout'a bakiye/portfoy tablosu yazdiriyor.
Oturum koruma dongusunun ciktisi `oturum_koruma.log` dosyasina yonlendiriliyor
(`exec >> ... 2>&1`). Snapshot ciktisinin log dosyasini sisirmemesi icin:

```bash
adaptor_bakiye > /dev/null 2>&1
adaptor_portfoy > /dev/null 2>&1
```

Adaptor ciktisi tamamen yutuluyor. Veri bellekteki dizilere yazildigi icin
stdout/stderr yonlendirmesi veri kaybina yol acmaz. Hata durumunda sadece
`_cekirdek_log` ile tur bilgisi loglanir:

```bash
if adaptor_bakiye > /dev/null 2>&1; then
    vt_bakiye_kaydet ...
    _cekirdek_log "Snapshot: bakiye kaydedildi ($kurum/$hesap)."
else
    _cekirdek_log "Snapshot: bakiye alinamadi ($kurum/$hesap)."
fi
```

#### 4.2.5 Snapshot Basarisizlik Toleransi

Snapshot tamamen opsiyoneldir. Basarisiz olursa:

- Dongü kesilmez (oturum koruma birincil gorev, snapshot ikincil).
- Hata loglanir.
- Sonraki snapshot doneminde tekrar denenir.
- Ardisik basarisizlik sayaci tutulmaz (oturum uzatmadaki gibi degil).

### 4.3 db_baglam_bayragi.md - Referans Notu

Mevcut plan dosyasinin basina bu dokumani referans eden bir not eklenecek.
Bayrak sistemi revize edildigi acikca belirtilecek. Bu zaten yapildi.

## 5. Etkilenen Komutlar

Degisiklik sonrasi `borsa gecmis` komutlarinin davranisi:

| Komut | Onceki Durum | Sonraki Durum |
|-------|-------------|---------------|
| borsa gecmis emirler | Bos (manuel emirler kaydedilmiyordu) | Tum emirler listelenir |
| borsa gecmis bakiye | Bos (snapshot alinmiyordu) | Periyodik snapshotlar listelenir |
| borsa gecmis kar | Hesaplanamaz | Snapshot verisiyle hesaplanir |
| borsa gecmis sembol X | Bos | Periyodik snapshotlardan dolar |
| borsa gecmis rapor | Bos | Gercek emir kayitlari ile dolar |
| borsa gecmis robot | Degisiklik yok | Degisiklik yok |
| borsa gecmis oturum | Zaten calisiyor | Degisiklik yok |

## 6. Dogrulama

### 6.1 Kategori 1 Testi (Emirler + Halka Arz)

Manuel emir testi: `borsa ziraat emir THYAO alis 1 50` sonrasi `borsa gecmis emirler`
komutu son emri gostermeli.

Manuel emir listeleme testi: `borsa ziraat emirler` sonrasi DB'deki emir durumlari
(gerceklesti/iptal/bekliyor) guncellenmeli.

Robot testi: Robot emir gonderdiginde ayni sekilde kaydedilmeli.

Halka arz testi: `borsa ziraat arz talep/iptal/guncelle` sonrasi kayit DB'de olmali.

### 6.2 Kategori 2 Testi (Periyodik Snapshot)

Oturum koruma aktifken 15 dakika beklenir, `borsa gecmis bakiye` komutu otomatik
olarak biriken snapshot'lari gostermeli.

Coklu hesap testi: Iki hesap ayni anda oturum korumaliyken her ikisinin de
snapshot'lari dogru hesap numarasiyla kaydedilmeli. Hesap1'in snapshot'inda
hesap2'nin verisi olmamali.

Manuel komut testi: `borsa ziraat bakiye` komutu sonrasi DB'ye yazilMAMALI
(bayrak kontrolu korunuyor, sadece periyodik+robot yazar).

Log kontrolu: `oturum_koruma.log` dosyasinda "Snapshot: bakiye kaydedildi" mesajlari
gorunmeli. Adaptor ciktisi (bakiye tablosu) log dosyasinda OLMAMALI.

### 6.3 Kategori 3 Testi (Degismeyenler)

`borsa gecmis robot` komutu sadece robot calisirken doldurulmus olmali.
Manuel komutlardan robot_log tablosuna hicbir sey yazilmamali.
