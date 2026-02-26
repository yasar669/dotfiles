# Interaktif Backtest Motoru - Plan

## 1. Sorun Tanimi

Mevcut backtest motoru kullanicidan sadece strateji ve sembol alip geri kalan her seyi sessizce varsayilan degerlerle dolduruyor. Bu davranis su sorunlara yol aciyor:

- Periyot secimi yok. Veritabaninda 13 farkli periyot (1dk, 3dk, 5dk, 15dk, 30dk, 45dk, 1S, 2S, 3S, 4S, 1G, 1H, 1A) varken motor daima `1G` (gunluk) kullanir.
- Tarih araligi verilmezse sessizce son 1 yil secilir. Kullanici ne test ettigini bilmeden sonuca bakar.
- Nakit sessizce 100.000 TL varsayilir. Kullanici farketmeden hep ayni sermayeyle test eder.
- Eslestirme modu (KAPANIS/LIMIT), komisyon oranlari, risksiz faiz gibi parametreler varsayilan degerle atanir.
- `--tarih` parametresi deger olmadan girilirse (`borsa backtest rsi.sh AKBNK --tarih`) bos string olur, Supabase'den yanlis veri cekilir.
- Kullanici hatali parametre girerse (ornegin tarih formati YYYY/AA/GG) sessizce devam eder, sonra veri bulamadiginda hatanin kaynagini anlamak zor olur.

Hedef: Sistem eksik veya hatali parametre gordugunde ya kullaniciya sormali ya da acik hata vermeli. Hicbir kritik parametreyi sessizce varsaymamalı.

## 1.1 Dosya Haritasi

Bu planda adı gecen tum dosyalarin tam yollari:

| Kisaltma       | Tam Yol                                                     | Satir Sayisi |
|----------------|--------------------------------------------------------------|-------------|
| motor.sh       | `bashrc.d/borsa/backtest/motor.sh`                           | 436         |
| veri.sh        | `bashrc.d/borsa/backtest/veri.sh`                            | 444         |
| metrik.sh      | `bashrc.d/borsa/backtest/metrik.sh`                          | 326         |
| rapor.sh       | `bashrc.d/borsa/backtest/rapor.sh`                           | 419         |
| portfoy.sh     | `bashrc.d/borsa/backtest/portfoy.sh`                         | 254         |
| veri_dogrula.sh| `bashrc.d/borsa/backtest/veri_dogrula.sh`                    | 166         |
| sema.sql       | `bashrc.d/borsa/veritabani/sema.sql`                         | 387         |
| rsi.sh         | `bashrc.d/borsa/strateji/rsi.sh`                             | ~150        |
| ma_kesisim.sh  | `bashrc.d/borsa/strateji/ma_kesisim.sh`                      | ~160        |
| bollinger.sh   | `bashrc.d/borsa/strateji/bollinger.sh`                       | ~170        |

## 1.2 Onceki Oturumda Yapilan Bug Fix'ler (Dokunma)

Bu dosyalarda daha once yapilmis ve calisan yamalar vardir. Asagidaki yerler degistirilirken bu yamalara dokunulmamalidir:

**motor.sh — $() alt kabuk bug fix'i (satirlar 279-310):**
Sorun: `sinyal=$(strateji_degerlendir ...)` ve `sonuc=$(_backtest_emir_isle ...)` ifadelerinde `$()` alt kabuk olusturdugu icin strateji durum degiskenleri ve portfoy guncellemeleri kayboluyordu.
Cozum: `strateji_degerlendir ... > "$_sinyal_dosya"` ve `_backtest_emir_isle ... > "$_sinyal_dosya"` seklinde gecici dosyaya yonlendirme. Gecici dosya yolu: `/tmp/_bt_sinyal_$$`. Dongu sonunda `rm -f "/tmp/_bt_sinyal_$$"` ile temizlenir (satir 339).

**veri.sh — Tavan/taban/degisim/seans eksikligi fix'i (satirlar 146, 151-185):**
Sorun: `_backtest_supabase_oku` fonksiyonu `_BACKTEST_VERI_TAVAN`, `_BACKTEST_VERI_TABAN`, `_BACKTEST_VERI_DEGISIM` ve `_BACKTEST_VERI_SEANS` dizilerini doldurmuyordu.
Cozum: `_backtest_tavan_taban_hesapla()` fonksiyonu eklendi (satir 155). BIST kurali ile onceki_kapanis * 1.10 / 0.90 hesabi yapar. Ayrica her satir icin `_BACKTEST_VERI_SEANS+=("Surekli Islem")` eklendi (jq ve jq-siz parse yollarinin ikisine de).

## 2. Mevcut Durum Analizi

### 2.1 Parametre Cozumleme (motor.sh, satirlar 345-436)

Mevcut `_backtest_parametreleri_coz` fonksiyonu sirayla tum varsayilanlari atar, sonra `while` dongusuyle CLI argumanlarini parse eder. Verilmeyen parametreler varsayilanlariyla kalir, kullaniciya soru sorulmaz.

Mevcut fonksiyon imzasi:
```bash
_backtest_parametreleri_coz() {
    # Girdi: "$@" — CLI argumanlarinin tamami
    # Cikti: _BACKTEST_AYAR_* global degiskenlerini doldurur
    # Donus: 0 = basarili, 1 = gecersiz parametre
}
```

Tanidigi parametreler:
```
--tarih|-t <BAS:BIT>      --nakit|-n <TL>
--komisyon-alis|-ka <X>   --komisyon-satis|-ks <X>
--eslestirme|-e <MOD>     --isitma|-i <GUN>
--risksiz|-r <ORAN>       --sessiz|-s
--detay|-d                --kaynak|-k <TIP>
--csv-dosya|-cf <DOSYA>
```

NOT: `--periyot` parametresi YOKTUR.

Mevcut varsayilanlar:
| Parametre        | Varsayilan     | Sorun                                          |
|------------------|----------------|-------------------------------------------------|
| tarih_bas        | son 1 yil      | Kullanici haberdar olmadan son 1 yil test edilir |
| tarih_bit        | bugun          | Genellikle dogru ama acik olmali                |
| nakit            | 100000         | Her test ayni sermaye                           |
| komisyon_alis    | 0.00188        | Kuruma gore degisir, sessizce atanir            |
| komisyon_satis   | 0.00188        | Kuruma gore degisir, sessizce atanir            |
| eslestirme       | KAPANIS        | LIMIT modunun varligi bilinmiyor                |
| isitma           | 0              | Cogu strateji isitma ister (RSI 14, MA 30 vb.) |
| risksiz          | 0.40           | Yildan yila degisir, sessizce %40 atanir        |
| kaynak           | supabase       | Dogru varsayilan, ama acik olmali               |
| periyot          | YOK (1G sabit) | En buyuk eksik — periyot secilemiyor            |

### 2.2 Veri Katmani (veri.sh, satirlar 17-62)

Mevcut fonksiyon imzasi:
```bash
_backtest_veri_yukle(sembol, bas_tarih, bit_tarih, kaynak)
    # kaynak: "supabase" | "csv" | "sentetik"
    # Periyot parametresi YOK — _backtest_supabase_oku'ya iletilmiyor
```

`_backtest_supabase_oku` fonksiyonu aslinda 4. parametre olarak periyot ALAbiliyor:
```bash
_backtest_supabase_oku(sembol, bas_tarih, bit_tarih, periyot="${4:-1G}")
    # 4. parametre verilmezse "1G" kullanir
    # Supabase sorgusunda: periyot=eq.${periyot}
```

Ama `_backtest_veri_yukle` bu parametreyi hic gondermiyor. Duzeltme basit: `_backtest_veri_yukle`'ye 5. parametre ekle, `_backtest_supabase_oku`'ya ilet.

### 2.3 Veritabani Durumu (sema.sql, satirlar 195-212)

`ohlcv` tablosu:
```sql
CREATE TABLE IF NOT EXISTS ohlcv (
    id          BIGSERIAL,
    sembol      VARCHAR(12)   NOT NULL,
    periyot     VARCHAR(4)    NOT NULL,   -- "1G", "15dk", "1S" vb.
    tarih       TIMESTAMPTZ   NOT NULL,
    acilis      NUMERIC(12,4) NOT NULL,
    yuksek      NUMERIC(12,4) NOT NULL,
    dusuk       NUMERIC(12,4) NOT NULL,
    kapanis     NUMERIC(12,4) NOT NULL,
    hacim       BIGINT        NOT NULL DEFAULT 0,
    kaynak      VARCHAR(8)    DEFAULT 'tvdata',
    guncelleme  TIMESTAMPTZ   DEFAULT NOW(),
    PRIMARY KEY (sembol, periyot, tarih)
);
```

Desteklenen periyotlar (tvDatafeed ile doldurulmus, `_tvdatafeed_toplu.py` satirlar 66-68):
```
1dk, 3dk, 5dk, 15dk, 30dk, 45dk, 1S, 2S, 3S, 4S, 1G, 1H, 1A
```

Tum periyotlar icin veri var, motor sadece yetersiz kaliyor.

### 2.4 Sonuc Tablosu (sema.sql, satirlar 118-145)

`backtest_sonuclari` tablosu mevcut haliyle `periyot` sutunu ICERMIYOR:
```sql
CREATE TABLE IF NOT EXISTS backtest_sonuclari (
    id                  BIGSERIAL       PRIMARY KEY,
    strateji            TEXT            NOT NULL,
    semboller           TEXT[]          NOT NULL,
    baslangic_tarih     DATE            NOT NULL,
    bitis_tarih         DATE            NOT NULL,
    -- ... metrikler ...
    eslestirme          TEXT            DEFAULT 'KAPANIS',
    komisyon_alis       NUMERIC(8,6),
    komisyon_satis      NUMERIC(8,6),
    parametreler        JSONB,          -- strateji parametreleri icin
    zaman               TIMESTAMPTZ     DEFAULT NOW()
);
```

Yeni `periyot` sutunu eklenmeli. Ayrica `rapor.sh` satirlar 113-163 arasindaki `_backtest_sonuc_kaydet` fonksiyonundaki JSON sablonuna da `periyot` alani eklenmeli.

### 2.5 Metrik Hesaplamalari (metrik.sh, satirlar 78-107)

Yillik getiri hesabi sabit `252` (islem gunu/yil) kullanir:
```bash
# Satir 91-99:
yillik_getiri=$(awk -v r="$toplam_getiri" -v gun="$gun_sayisi" '
BEGIN {
    oran = r / 100
    if (gun > 0 && oran > -1) {
        yillik = (exp(252/gun * log(1 + oran)) - 1) * 100
        printf "%.4f", yillik
    } else { print "0.0000" }
}')
```

Sharpe ve Sortino hesabi da sabit `252` kullanir:
```bash
# Satir 155-156:
BEGIN { rf_gunluk = rf_yillik / 252 }
# Satir 175-176:
sharpe = (std > 1e-10) ? ort / std * sqrt(252) : 0
sortino = (neg_std > 1e-10) ? ort / neg_std * sqrt(252) : 0
```

Bu `252` degeri periyoda gore degismeli. Ornegin `15dk` periyotta gunluk ~30 mum var, yillik ~7560 mum vardir.

### 2.6 motor.sh Ana Akis (satirlar 155-241)

`_backtest_calistir` fonksiyonunun mevcut imzasi ve akisi:
```bash
_backtest_calistir(strateji_dosyasi, semboller, ...secenekler)
    1. Strateji dosyasini bul (dosya yolu veya strateji/ altinda)
    2. Sembol bos mu kontrol et
    3. _backtest_parametreleri_coz "$@"      <-- Burada varsayilanlar atanir
    4. Strateji source et
    5. strateji_baslat() cagir (varsa)
    6. Portfoy olustur
    7. Metrikleri sifirla
    8. Her sembol icin:
       a. _backtest_veri_yukle sem bas_tarih bit_tarih kaynak
       b. _backtest_veriyi_dogrula
       c. _backtest_ana_dongu sem
    9. strateji_temizle() cagir (varsa)
    10. _backtest_metrikleri_hesapla
    11. _backtest_rapor_goster
    12. _backtest_sonuc_kaydet
```

Interaktif soru ve onay adimlari 3 ile 4 arasina eklenecek.

## 3. Cozum Tasarimi

### 3.1 Interaktif Mod — Tetikleme Kurali

Interaktif mod su kosullara gore aktif olur:

```
TTY ACIK MI?  +  PARAMETRE EKSIK MI?  =  SONUC
-----------      --------------------    ------
[[ -t 0 ]]       Evet (orn: periyot)     Interaktif sorar
[[ -t 0 ]]       Hayir (hepsi tam)       Sormaz, dogrudan calisir
[[ ! -t 0 ]]     Farketmez               Sormaz, varsayilanlari kullanir (pipe modu)
--evet           Farketmez               Sormaz, varsayilanlari kullanir
```

TTY tespiti icin bash yerlesik testi:
```bash
if [[ -t 0 ]]; then
    # Terminal bagli — interaktif soru sorulabilir
else
    # Pipe veya betik — varsayilanlarla devam et
fi
```

"Parametre eksik mi" tespiti: Asagidaki parametrelerden herhangi biri CLI'da acikca verilmemisse "eksik" sayilir:
- `--periyot` (zorunlu kabul edilecek, varsayilan YOK)
- `--tarih` (zorunlu kabul edilecek, varsayilan YOK)

Diger parametrelerin (nakit, komisyon, eslestirme, isitma, risksiz) varsayilanlari makuldur. Bunlar interaktif modda "Baska bir sey degistirmek ister misiniz? [e/H]:" seklinde opsiyonel olarak sorulur. Varsayilani Hayir, yani Enter basarsa devam eder.

Akis:
```
$ borsa backtest rsi.sh AKBNK

Periyot? [1dk/3dk/5dk/15dk/30dk/45dk/1S/2S/3S/4S/1G/1H/1A]: 15dk
Tarih araligi? (YYYY-AA-GG:YYYY-AA-GG): 2025-06-01:2025-12-31

--- Backtest Parametreleri ---
Strateji   : rsi.sh
Sembol     : AKBNK
Periyot    : 15dk
Donem      : 2025-06-01 / 2025-12-31
Nakit      : 100.000 TL
Eslestirme : KAPANIS
Komisyon   : %0.188 (alis/satis)
Isitma     : 14 mum (strateji onerisi)
Risksiz    : %40
Kaynak     : supabase

Baska bir sey degistirmek ister misiniz? [e/H]:
Devam edilsin mi? [E/h]:

Backtest basliyor...
```

### 3.2 Tam CLI Modu (Parametreler Acikca Verildiginde)

Tum zorunlu parametreler komut satirinda verilmisse soru sorulmaz:
```
$ borsa backtest rsi.sh AKBNK --periyot 15dk --tarih 2025-06-01:2025-12-31 --nakit 50000
```

Bu mod mevcut davranisa benzer ama ek olarak:
- Parametre dogrulama yapilir (tarih formati, gecerli periyot, pozitif nakit vb.)
- Hatali parametre varsa acik hata mesaji verilir

### 3.3 Periyot Destegi

Yeni parametre: `--periyot, -p <KOD>`

Gecerli degerler: `1dk, 3dk, 5dk, 15dk, 30dk, 45dk, 1S, 2S, 3S, 4S, 1G, 1H, 1A`

Periyot ile "yilda kac mum" eslestirme tablosu (metrik hesabi icin):

| Periyot | 1 Gunde Kac Mum | Yilda Kac Mum (252 islem gunu) |
|---------|------------------|-------------------------------|
| 1dk     | ~510             | ~128.520                      |
| 3dk     | ~170             | ~42.840                       |
| 5dk     | ~102             | ~25.704                       |
| 15dk    | ~34              | ~8.568                        |
| 30dk    | ~17              | ~4.284                        |
| 45dk    | ~11              | ~2.772                        |
| 1S      | ~8.5             | ~2.142                        |
| 2S      | ~4               | ~1.008                        |
| 3S      | ~3               | ~756                          |
| 4S      | ~2               | ~504                          |
| 1G      | 1                | 252                           |
| 1H      | ~0.2             | 52                            |
| 1A      | ~0.05            | 12                            |

NOT: Mum sayilari BIST surekli islem seansina gore (09:40-18:10, ~510 dk) hesaplanmistir. Kesin sayi veriye gore degisir; bu tablo Sharpe/Sortino/yillik_getiri formulu icin yakinsama katsayisidir.

Etkilenen dosyalar ve satirlar:
- motor.sh satirlar 22-35 — `_BACKTEST_AYAR_PERIYOT=""` degiskeni eklenecek
- motor.sh satirlar 345-436 — `--periyot|-p` case eklenmesi
- motor.sh satirlar 155-210 — `_backtest_calistir` icerisinde periyotu `_backtest_veri_yukle`'ye gecirme
- veri.sh satirlar 17-40 — `_backtest_veri_yukle` imzasina 5. parametre (periyot) eklenmesi
- veri.sh satir 38 — `_backtest_supabase_oku "$sembol" "$bas_tarih" "$bit_tarih" "$periyot"` seklinde cagrinin guncellenmesi
- rapor.sh satirlar 17-20 — Rapor basligina `Periyot` satiri
- rapor.sh satirlar 113-163 — `_backtest_sonuc_kaydet` JSON'una `"periyot": "%s"` eklenmesi
- metrik.sh satirlar 91-99 — `252` sabitinin `_BACKTEST_MUMLUK_YIL` degiskenine donusmesi
- metrik.sh satirlar 155-176 — Sharpe/Sortino'daki `252` ve `sqrt(252)` ayni sekilde

### 3.3.1 Sentetik Veri + Periyot Kombinasyonu

Sentetik veri uretici (`_backtest_sentetik_uret`, veri.sh satirlar 260+) daima gunluk bazda fiyat uretir. Periyot `1G` degilse:

- `--kaynak sentetik --periyot 15dk` girilirse HATA: `"Sentetik veri sadece 1G (gunluk) periyot destekler."`
- Alternatif: uyari verip `1G` olarak devam et degil, cunku bu sessiz varsayim ilkesine ters.

### 3.3.2 Pipe Modunda Periyot Varsayilani

`--periyot` verilmemis ve stdin TTY degilse (pipe/betik) `1G` varsayilani kullanilir AMA terminale uyari yazilir:
```
UYARI: --periyot belirtilmedi, 1G (gunluk) varsayildi.
```
Bu, otomasyon betiklerinin kirilmasini onler ama kullaniciyi bilgilendirir.

### 3.4 Strateji Otomatik Isitma Onerisi

Strateji dosyasi `strateji_isitma` fonksiyonu tanimlayabilir. Bu fonksiyon stratejinin minimum isitma donemini (mum sayisi olarak) dondurur:

```bash
strateji_isitma() {
    echo "14"  # RSI(14) icin en az 14 mum gerekli
}
```

Mevcut stratejiler icin beklenen isitma degerleri:
| Strateji       | Isitma Degeri | Neden                              |
|----------------|---------------|------------------------------------|
| rsi.sh         | 14            | RSI periyodu 14 mum                |
| ma_kesisim.sh  | 30            | Uzun SMA periyodu 30 mum           |
| bollinger.sh   | 20            | BB periyodu 20 mum                 |
| ornek.sh       | 1             | Tavan/taban icin onceki gun yeter   |

Kullanim mantigi (motor.sh icinde):
1. CLI'da `--isitma 20` verilmisse → o deger kullanilir (acik parametre her zaman oncelikli)
2. CLI'da `--isitma` verilmemis ve `strateji_isitma` tanimlanmissa → stratejinin degerini kullan
3. Ikisi de yoksa → 0 (isitma yok)

Interaktif modda: "Isitma donemi? (strateji onerisi: 14 mum) [14]:" seklinde varsayilan olarak gosterilir.

### 3.5 Parametre Dogrulama

Her parametre icin dogrulama kurallari:

| Parametre  | Dogrulama                                                         | Hata Mesaji Ornegi                            |
|------------|-------------------------------------------------------------------|-----------------------------------------------|
| periyot    | Gecerli listede olmali                                            | "HATA: Gecersiz periyot: 2dk. Gecerli: ..."   |
| tarih      | YYYY-AA-GG:YYYY-AA-GG formati, bas < bit                        | "HATA: Tarih formati hatali. Beklenen: ..."    |
| tarih      | `--tarih` yazilip deger verilmemis                                | "HATA: --tarih parametresi deger bekliyor."    |
| nakit      | Pozitif sayi                                                      | "HATA: Nakit pozitif sayi olmali."             |
| komisyon   | 0 ile 1 arasi sayi                                               | "HATA: Komisyon 0-1 arasinda olmali."          |
| eslestirme | KAPANIS veya LIMIT                                                | "HATA: Eslestirme KAPANIS veya LIMIT olmali."  |
| isitma     | Negatif olmayan tam sayi                                          | "HATA: Isitma donemi negatif olamaz."          |
| risksiz    | 0 ile 5 arasi sayi                                                | "HATA: Risksiz faiz orani 0-5 arasinda olmali."|
| kaynak     | supabase, csv, sentetik                                           | "HATA: Gecersiz kaynak: xyz."                  |

### 3.6 Onay Adimi

Tum parametreler (interaktif veya CLI'dan) cozuldukten sonra, backtest baslamadan once ozet gosterilir ve onay istenir:

```
--- Backtest Parametreleri ---
Strateji   : rsi.sh
Sembol     : AKBNK
Periyot    : 15dk
Donem      : 2025-06-01 / 2025-12-31
Nakit      : 50.000 TL
Eslestirme : KAPANIS
Komisyon   : %0.188 (alis), %0.188 (satis)
Isitma     : 14 mum
Risksiz    : %40
Kaynak     : supabase

Devam edilsin mi? [E/h]:
```

`--sessiz` veya `--evet` parametresi ile onay adimi atlanabilir (betik/otomasyon kullanimi icin).
Pipe modunda (stdin TTY degil) onay otomatik atlanir, parametreler yazilir ama soru sorulmaz.

## 4. Degisiklik Plani

### 4.1 motor.sh Degisiklikleri

Dosya: `bashrc.d/borsa/backtest/motor.sh` (436 satir)

1. **Satir 22-35 arasi** — Yeni degisken ekleme:
   ```bash
   _BACKTEST_AYAR_PERIYOT=""          # Bos = interaktif soracak
   _BACKTEST_AYAR_PERIYOT_VERILDI=0   # CLI'dan acikca verildi mi?
   _BACKTEST_AYAR_TARIH_VERILDI=0     # CLI'dan acikca verildi mi?
   _BACKTEST_AYAR_ISITMA_VERILDI=0    # CLI'dan acikca verildi mi?
   ```

2. **Satir 345-436 arasi** — `_backtest_parametreleri_coz`:
   - `--periyot|-p` case ekle
   - Tum `shift 2` satirlarinin oncesine `$2` bos mu veya `--` ile mi basliyor kontrolu:
     ```bash
     --tarih|-t)
         if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
             echo "HATA: --tarih parametresi deger bekliyor." >&2
             echo "Kullanim: --tarih 2025-01-01:2025-06-15" >&2
             return 1
         fi
         # ... mevcut parse ...
     ```
   - Her parametre icin `_VERILDI` bayragini set et

3. **Satir 155-200 arasi** — `_backtest_calistir` icine yeni adimlar:
   ```bash
   _backtest_parametreleri_coz "$@" || return 1

   # YENI: Strateji source et (isitma icin gerekli)
   source "$strateji_yolu"

   # YENI: Interaktif soru (TTY acik ve eksik parametre varsa)
   _backtest_interaktif_sor || return 1

   # YENI: Parametre dogrulama
   _backtest_parametre_dogrula || return 1

   # YENI: Onay goster
   _backtest_onay_goster || return 1
   ```

4. **Yeni fonksiyonlar** (dosya sonuna eklenecek):

   `_backtest_interaktif_sor` (~80 satir):
   ```bash
   _backtest_interaktif_sor() {
       # TTY yoksa veya --evet verilmisse atla
       if [[ ! -t 0 ]] || [[ "${_BACKTEST_AYAR_EVET:-0}" == "1" ]]; then
           # Pipe modunda varsayilanlari kullan, uyari ver
           if [[ "$_BACKTEST_AYAR_PERIYOT_VERILDI" -eq 0 ]]; then
               _BACKTEST_AYAR_PERIYOT="1G"
               echo "UYARI: --periyot belirtilmedi, 1G (gunluk) varsayildi." >&2
           fi
           if [[ "$_BACKTEST_AYAR_TARIH_VERILDI" -eq 0 ]]; then
               echo "UYARI: --tarih belirtilmedi, son 1 yil varsayildi." >&2
           fi
           return 0
       fi
       # TTY acik — eksik parametreleri sor
       if [[ "$_BACKTEST_AYAR_PERIYOT_VERILDI" -eq 0 ]]; then
           read -rp "Periyot? [1dk/.../1G/.../1A]: " _girdi
           _BACKTEST_AYAR_PERIYOT="${_girdi:-1G}"
       fi
       # ... tarih, nakit vb. icin benzer read -rp satirlari ...
   }
   ```

   `_backtest_parametre_dogrula` (~50 satir): Tum dogrulama kurallari (bolum 3.5 tablosu)

   `_backtest_onay_goster` (~30 satir): Ozet tablo + E/h sorusu

   `_backtest_periyot_mumluk_yil` (~30 satir): Periyot kodundan yillik mum sayisini dondurur

5. **Satir 93-118 arasi** — `_backtest_yardim` ciktisina ekleme:
   ```
   --periyot, -p <KOD>    - Zaman dilimi (1dk/5dk/15dk/30dk/1S/4S/1G/1H/1A)
   --evet                  - Interaktif sorulari ve onayi atla
   ```

DIKKAT: Satirlar 279-339 arasindaki `$()` bug fix'ine (gecici dosya yonlendirmesi) dokunulmayacak.

### 4.2 veri.sh Degisiklikleri

Dosya: `bashrc.d/borsa/backtest/veri.sh` (444 satir)

1. **Satir 17-24** — `_backtest_veri_yukle` imzasi degisecek:
   ```bash
   # Eski:
   _backtest_veri_yukle(sembol, bas_tarih, bit_tarih, kaynak)
   # Yeni:
   _backtest_veri_yukle(sembol, bas_tarih, bit_tarih, kaynak, periyot)
   ```

2. **Satir 38** — `_backtest_supabase_oku` cagrisi:
   ```bash
   # Eski:
   _backtest_supabase_oku "$sembol" "$bas_tarih" "$bit_tarih"
   # Yeni:
   _backtest_supabase_oku "$sembol" "$bas_tarih" "$bit_tarih" "$periyot"
   ```

3. **Satir 46-57** — Sentetik blokuna periyot kontrolu:
   ```bash
   sentetik)
       if [[ "$periyot" != "1G" ]] && [[ -n "$periyot" ]]; then
           echo "HATA: Sentetik veri sadece 1G (gunluk) periyot destekler." >&2
           return 1
       fi
       # ... mevcut sentetik kod ...
   ```

DIKKAT: Satirlar 146-185 arasindaki `_backtest_tavan_taban_hesapla` fix'ine dokunulmayacak.

### 4.3 metrik.sh Degisiklikleri

Dosya: `bashrc.d/borsa/backtest/metrik.sh` (326 satir)

1. **Satir 91-99** — Yillik getiri formulundeki `252` degiskene donusecek:
   ```bash
   local mumluk_yil
   mumluk_yil=$(_backtest_periyot_mumluk_yil "${_BACKTEST_AYAR_PERIYOT:-1G}")

   yillik_getiri=$(awk -v r="$toplam_getiri" -v gun="$gun_sayisi" -v myil="$mumluk_yil" '
   BEGIN {
       oran = r / 100
       if (gun > 0 && oran > -1) {
           yillik = (exp(myil/gun * log(1 + oran)) - 1) * 100
           printf "%.4f", yillik
       } else { print "0.0000" }
   }')
   ```

2. **Satir 155-176** — Sharpe/Sortino'daki `252` ve `sqrt(252)`:
   ```bash
   BEGIN { rf_gunluk = rf_yillik / mumluk_yil }
   # ...
   sharpe = (std > 1e-10) ? ort / std * sqrt(mumluk_yil) : 0
   sortino = (neg_std > 1e-10) ? ort / neg_std * sqrt(mumluk_yil) : 0
   ```

### 4.4 rapor.sh Degisiklikleri

Dosya: `bashrc.d/borsa/backtest/rapor.sh` (419 satir)

1. **Satir 17-20** — Rapor basligina ekle:
   ```bash
   echo "Periyot:         ${_BACKTEST_AYAR_PERIYOT:-1G}"
   ```

2. **Satir 113-163** — `_backtest_sonuc_kaydet` JSON sablonuna:
   ```bash
   "periyot": "%s",
   # ...
   "${_BACKTEST_AYAR_PERIYOT:-1G}" \
   ```

### 4.5 sema.sql Degisikligi

Dosya: `bashrc.d/borsa/veritabani/sema.sql` (387 satir)

`backtest_sonuclari` tablosuna `periyot` sutunu ekle (satir 118-145 arasi):
```sql
ALTER TABLE backtest_sonuclari
    ADD COLUMN IF NOT EXISTS periyot VARCHAR(4) DEFAULT '1G';
```

Bu ALTER hem mevcut kayitlari korur (varsayilan '1G' atanir) hem de yeni kayitlarda periyotu tutar.

### 4.6 Strateji Arabirimine Eklentiler

Mevcut strateji arabirimi degismez:
- `strateji_baslat()` — degismez
- `strateji_degerlendir()` — degismez
- `strateji_temizle()` — degismez
- `strateji_isitma()` — YENI, opsiyonel

Mevcut stratejilere `strateji_isitma` eklenecek:
- `bashrc.d/borsa/strateji/rsi.sh` → `strateji_isitma() { echo "14"; }`
- `bashrc.d/borsa/strateji/ma_kesisim.sh` → `strateji_isitma() { echo "30"; }`
- `bashrc.d/borsa/strateji/bollinger.sh` → `strateji_isitma() { echo "20"; }`

### 4.7 Gecerli Periyot Listesi ve Dogrulamasi

motor.sh dosya basina (satir 22 civari) ekleme:
```bash
_BACKTEST_GECERLI_PERIYOTLAR="1dk 3dk 5dk 15dk 30dk 45dk 1S 2S 3S 4S 1G 1H 1A"
```

Yeni fonksiyon:
```bash
_backtest_periyot_gecerli_mi() {
    local periyot="$1"
    local p
    for p in $_BACKTEST_GECERLI_PERIYOTLAR; do
        [[ "$p" == "$periyot" ]] && return 0
    done
    return 1
}
```

## 5. Uygulama Asamalari

### 5.1 Asama 1 — Parametre Dogrulama (Oncelik: Yuksek)

Hedef: Hatali girdilerde acik hata mesaji, sessiz gecisin onlenmesi.

Degisecek dosya: motor.sh (satirlar 345-436)
- Tum `shift 2` satirlarinin oncesine `$2` bos/gecersiz kontrolu ekle
- Tarih formati dogrulama: `[[ "$tarih_aralik" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}:[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]`
- Tarih mantik kontrolu: `date -d` ile gecerlilik, bas_tarih < bit_tarih
- Nakit, komisyon, isitma, risksiz icin sayi dogrula

Tahmini: ~30 satir ekleme/degistirme.
Bagimsiz: Diger asamalara bagimli degil, tek basina yapilabilir.

### 5.2 Asama 2 — Periyot Destegi (Oncelik: Yuksek)

Hedef: `--periyot 15dk` parametresi ile istenilen zaman diliminde backtest.

Degisecek dosyalar:
1. motor.sh satirlar 22-35 — `_BACKTEST_AYAR_PERIYOT`, `_BACKTEST_GECERLI_PERIYOTLAR` ekle
2. motor.sh satirlar 345-436 — `--periyot|-p` case ekle
3. motor.sh satirlar 200-210 — `_backtest_veri_yukle` cagrisina periyot parametresi ekle
4. veri.sh satirlar 17-40 — `_backtest_veri_yukle` imzasina 5. parametre, sentetik blokuna periyot kosulu
5. metrik.sh satirlar 91-99, 155-176 — `252` sabitini kaldirip `_backtest_periyot_mumluk_yil` fonksiyonu kullan
6. rapor.sh satirlar 17-20 — Periyot satiri
7. rapor.sh satirlar 113-163 — JSON'a periyot alani
8. sema.sql — `ALTER TABLE backtest_sonuclari ADD COLUMN periyot`

Tahmini: motor.sh ~15, veri.sh ~10, metrik.sh ~20, rapor.sh ~5, sema.sql ~3 satir.
Bagimsiz: Asama 1 ile paralel yapilabilir, ama Asama 3'ten once bitmeli.

### 5.3 Asama 3 — Interaktif Soru Mekanizmasi (Oncelik: Orta)

Hedef: Eksik parametreleri `read -rp` ile kullaniciya sorma.

Degisecek dosya: motor.sh
- Yeni fonksiyon: `_backtest_interaktif_sor` (~80 satir)
- `_backtest_calistir` icerisinde akis degisikligi (~5 satir)
- `_BACKTEST_AYAR_*_VERILDI` bayraklari (asama 1 ile birlikte)

TTY tespiti: `[[ -t 0 ]]` — stdin'in terminal olup olmadigini kontrol eder.
- Terminal bagli → soru sorar
- Pipe/betik → sormaz, varsayilanlar + uyari

Tahmini: ~80 satir yeni fonksiyon + ~5 satir akis degisikligi.
Bagimli: Asama 1 ve 2 tamamlanmis olmali (periyot degiskeni ve dogrulama mevcut olmali).

### 5.4 Asama 4 — Onay Adimi (Oncelik: Orta)

Hedef: Backtest baslamadan once parametre ozeti + E/h sorusu.

Degisecek dosya: motor.sh
- Yeni fonksiyon: `_backtest_onay_goster` (~30 satir)
- `--evet` parametresi parse edilecek (asama 1 ile birlikte)
- Pipe modunda onay otomatik atlanir

Tahmini: ~35 satir yeni fonksiyon.
Bagimli: Asama 3 ile birlikte veya hemen sonra.

### 5.5 Asama 5 — Strateji Isitma Entegrasyonu (Oncelik: Dusuk)

Hedef: Strateji dosyalarindan otomatik isitma onerisi alma.

Degisecek dosyalar:
1. `bashrc.d/borsa/strateji/rsi.sh` — `strateji_isitma` fonksiyonu ekle (~3 satir)
2. `bashrc.d/borsa/strateji/ma_kesisim.sh` — ayni (~3 satir)
3. `bashrc.d/borsa/strateji/bollinger.sh` — ayni (~3 satir)
4. motor.sh — `declare -f strateji_isitma` kontrolu, oncelik mantigi (~10 satir)

Tahmini: Her strateji ~3 satir + motor.sh ~10 satir.
Bagimli: Asama 3 tamamlanmis olmali (interaktif soruda isitma onerisi gosterilecek).

## 6. Geriye Uyumluluk

- Mevcut komut formati (`borsa backtest rsi.sh AKBNK --tarih X:Y`) aynen calisir.
- Tum mevcut parametreler degismez.
- Yeni parametreler: `--periyot`, `--evet` (hepsi opsiyonel).
- `--periyot` verilmezse:
  - TTY acik → interaktif sorar
  - TTY kapali (pipe/betik) → `1G` varsayar + stderr'e uyari yazar
  - `--evet` verilmis → `1G` varsayar + stderr'e uyari yazar
- `--tarih` verilmezse:
  - TTY acik → interaktif sorar
  - TTY kapali → son 1 yil varsayar + stderr'e uyari yazar
- Otomasyon betikleri icin `--evet` parametresi ile interaktif soru ve onay atlanir.
- Mevcut strateji dosyalari degistirilmeden calisir (`strateji_isitma` opsiyonel).
- `backtest_sonuclari` tablosundaki mevcut satirlar `periyot='1G'` varsayilaniyla korunur (ALTER TABLE ... DEFAULT).
- `_backtest_veri_yukle` 4 parametreyle cagrilan eski kod varsa 5. parametre bos gelir, `supabase_oku` mevcut `${4:-1G}` varsayilaniyla calisir.

## 7. Test Matrisi

### 7.1 Interaktif Mod Testleri

| # | Komut                                              | Beklenen                                        |
|---|----------------------------------------------------|-------------------------------------------------|
| 1 | `borsa backtest rsi.sh AKBNK`                     | Periyot ve tarih sorar, onay ister              |
| 2 | `borsa backtest rsi.sh AKBNK --periyot 15dk --tarih X:Y` | Sormaz, dogrudan onay gosterir        |
| 3 | `borsa backtest rsi.sh AKBNK --evet`               | Sormaz, varsayilanlar + uyari, onay atlar       |
| 4 | `echo "" \| borsa backtest rsi.sh AKBNK`           | Pipe: sormaz, varsayilanlar + uyari, onay atlar |

### 7.2 Parametre Dogrulama Testleri

| # | Komut                                              | Beklenen Hata                                   |
|---|----------------------------------------------------|-------------------------------------------------|
| 5 | `borsa backtest rsi.sh AKBNK --tarih`             | "HATA: --tarih parametresi deger bekliyor."     |
| 6 | `borsa backtest rsi.sh AKBNK --periyot 2dk`       | "HATA: Gecersiz periyot: 2dk. Gecerli: ..."     |
| 7 | `borsa backtest rsi.sh AKBNK --nakit -500`         | "HATA: Nakit pozitif sayi olmali."              |
| 8 | `borsa backtest rsi.sh AKBNK --tarih 2025/13/01:2025/06/01` | "HATA: Tarih formati hatali."      |
| 9 | `borsa backtest rsi.sh AKBNK --tarih 2025-06-01:2025-01-01` | "HATA: Bitis tarihi baslangictan once."  |
|10 | `borsa backtest rsi.sh AKBNK --eslestirme ABC`     | "HATA: Eslestirme KAPANIS veya LIMIT olmali."   |
|11 | `borsa backtest rsi.sh AKBNK --isitma -5`          | "HATA: Isitma donemi negatif olamaz."           |

### 7.3 Periyot Testleri

| # | Komut                                              | Beklenen                                        |
|---|----------------------------------------------------|-------------------------------------------------|
|12 | `borsa backtest rsi.sh AKBNK --periyot 1G --tarih X:Y --evet` | Gunluk veri ile backtest (mevcut davranis)|
|13 | `borsa backtest rsi.sh AKBNK --periyot 1S --tarih X:Y --evet` | Haftalik veri ile backtest           |
|14 | `borsa backtest rsi.sh AKBNK --periyot 15dk --tarih X:Y --evet` | 15dk veri ile backtest             |
|15 | `borsa backtest rsi.sh AKBNK --kaynak sentetik --periyot 15dk --evet` | HATA: Sentetik sadece 1G    |
|16 | `borsa backtest rsi.sh AKBNK --kaynak sentetik --periyot 1G --evet`  | Calismali                   |

### 7.4 Isitma Testleri

| # | Komut                                              | Beklenen                                        |
|---|----------------------------------------------------|-------------------------------------------------|
|17 | `borsa backtest rsi.sh AKBNK --periyot 1G --tarih X:Y --evet` | Isitma = 14 (strateji onerisi)   |
|18 | `borsa backtest rsi.sh AKBNK --isitma 5 --periyot 1G --tarih X:Y --evet` | Isitma = 5 (CLI oncelik)|
|19 | `borsa backtest ornek.sh AKBNK --periyot 1G --tarih X:Y --evet` | Isitma = 0 (fonksiyon yok) |
