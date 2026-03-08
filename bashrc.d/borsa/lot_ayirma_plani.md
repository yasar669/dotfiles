# Lot Yonetimini Stratejiden Ayirma - Plan

## 1. Sorun Tanimi

Mevcut tasarimda lot miktari stratejinin icerisinde sabit kodlanmis durumda.
Her strateji dosyasi kendi lot degiskenini tanimliyor ve sinyal uretirken
bu degeri dogrudan ciktiya yaziyor.

Etkilenen strateji dosyalari ve lot degiskenleri:

| Dosya             | Degisken      | Deger |
|-------------------|---------------|-------|
| ma_kesisim.sh     | _MA_LOT       | 100   |
| ornek_ohlcv.sh    | _OHLCV_LOT    | 100   |
| ornek.sh          | _ORNEK_LOT    | 100   |
| rsi.sh            | _RSI_LOT      | 100   |
| bollinger.sh      | _BB_LOT       | 100   |
| test_al_sat.sh    | _TEST_LOT     | 50    |

Mevcut sinyal formati (sistem_plani.md Bolum 10.2.1):

```
"ALIS <lot> <fiyat>"     — ornek: "ALIS 100 312.50"
"SATIS <lot> <fiyat>"    — ornek: "SATIS 50 315.00"
"BEKLE"
```

### 1.1 Neden Hatali

Lot miktari bir strateji karari degil, **risk yonetimi** kararidir.

- Strateji "ne zaman al, ne zaman sat" sorusunu yanitlar (sinyal).
- Risk yonetimi "ne kadar al, ne kadar sat" sorusunu yanitlar (pozisyon boyutu).

Bunlar birbirinden tamamen farkli sorumluluk alanlaridir.
Lot miktarini strateji icerisinde tanimlamak su sorunlara yol acar:

1. **Yeniden kullanilamaz strateji:** Ayni strateji farkli sermaye buyuklukleri icin
   her seferinde dosya icinde elle degistirilmek zorunda kalir.

2. **Risk kontrolu yok:** Strateji 100 lot diyor ama hesaptaki bakiye 5.000 TL ise
   bu emri karsilayacak para yok demektir. Strateji bakiyeyi bilmez/bilmemeli.

3. **Sabit lot tuzagi:** 100.000 TL sermaye ile 100 lot THYAO almak makul olabilir
   ama ayni 100 lot ile 5 TL'lik bir hisse almak sermayenin cok kucuk kismini
   kullanmak anlamina gelir. Lot miktari fiyata ve sermayeye gore dinamik olmali.

4. **Coklu strateji carpismasi:** Iki farkli strateji ayni hesapta calisirken
   her biri kendi lotunu bildirir ama toplam maruz kalinim kontrol edilemez.

5. **Backtest gercekcilik eksikligi:** Backtest sabit lot ile calistiginda
   gercek hayatta olmayacak islemler yapmis olur (bakiye yetersizligi
   portfoy.sh'de kontrol edilse bile lot boyutlandirma stratejiye kalmis).

## 2. Hedef Tasarim

Strateji sadece **yon** (ALIS/SATIS/BEKLE) ve opsiyonel olarak **sinyal gucu**
bildirir. Lot hesaplamasini **tuketici katman** (backtest motoru veya robot motoru)
kendi risk yonetimi kurallarina gore yapar.

### 2.1 Yeni Sinyal Formati

```
"BEKLE"                          — islem yapma (degismiyor)
"ALIS"                           — alis sinyali (lot ve fiyat tuketici belirler)
"SATIS"                          — satis sinyali (lot ve fiyat tuketici belirler)
"ALIS <sinyal_gucu>"             — alis sinyali, guc: 0.0-1.0 (opsiyonel)
"SATIS <sinyal_gucu>"            — satis sinyali, guc: 0.0-1.0 (opsiyonel)
```

Sinyal gucu opsiyoneldir. Verilirse tuketici katman bunu lot hesabinda
agirlik olarak kullanabilir (guclu sinyal = daha buyuk pozisyon).
Verilmezse sinyal gucu 1.0 kabul edilir (tam pozisyon).

Ornek ciktilar:

```
echo "BEKLE"         # Islem yapma
echo "ALIS"          # Al, lot hesabini tuketici yapsin
echo "SATIS"         # Sat, lot hesabini tuketici yapsin
echo "ALIS 0.8"      # Al, sinyal gucu %80 (tuketici normal lotun %80'ini kullanir)
echo "SATIS 1.0"     # Sat, tam guc
```

### 2.2 Lot Hesaplama Sorumlulugunun Yeni Yeri

Lot hesaplama iki ayri yerde yapilir:

**Backtest motoru (backtest/motor.sh):**
CLI parametresi veya varsayilan ile lot belirlenir.
`--lot 100` veya `--sermaye-yuzde 10` gibi secenekler eklenir.
Sanal portfoydeki mevcut bakiyeye gore dinamik hesaplama yapilir.

**Robot motoru (robot/motor.sh):**
Robot baslatilirken lot parametresi alinir.
Gercek hesap bakiyesine gore dinamik hesaplama yapilir.
Mevcut pozisyona gore cikis lotunu otomatik belirler.

### 2.3 Lot Hesaplama Yontemi

Lot her zaman **dinamik** hesaplanir. Hicbir yerde sabit lot degiskeni bulunmaz.
Tek yontem: **sermaye yuzdesi** — mevcut bakiyenin belirli bir yuzdesi kadar
pozisyon acilir. Bu, sermaye buyudukce pozisyonun buyumesini, kuculdukce
kuculmesini otomatik saglar.

**Alis icin:**
Kullanilacak tutar = mevcut_bakiye * sermaye_yuzdesi * sinyal_gucu
Lot = int(tutar / hisse_fiyati)

**Satis icin:**
Mevcut pozisyonun tamamini sat (TAM_POZISYON).
Stratejinin satis sinyali vermesi, eldeki tum lotu satmak anlamina gelir.

Varsayilan sermaye yuzdesi: **%10** (CLI ile degistirilebilir: `--sermaye-yuzde 15`)

Hesaplama ornekleri:

| Bakiye      | Yuzde | Sinyal Gucu | Hisse Fiyati | Hesaplanan Lot |
|-------------|-------|-------------|--------------|----------------|
| 100.000 TL  | %10   | 1.0         | 80 TL        | 125 lot        |
| 100.000 TL  | %10   | 0.5         | 80 TL        | 62 lot         |
| 50.000 TL   | %10   | 1.0         | 80 TL        | 62 lot         |
| 50.000 TL   | %20   | 1.0         | 80 TL        | 125 lot        |
| 10.000 TL   | %10   | 1.0         | 250 TL       | 4 lot          |

Hesaplanan lot 0 cikarsa emir gonderilmez (yetersiz bakiye).

**Backtest icin:** Sanal portfoydeki nakit bakiye kullanilir.
**Robot icin:** Gercek hesaptaki kullanilabilir bakiye kullanilir
(`adaptor_bakiye_al` ile sorgulanir).

## 3. Degistirilecek Dosyalar

### 3.1 Strateji Dosyalari (Lot Cikariyor)

Her strateji dosyasindan lot degiskeni ve lot kullanan satirlar cikarilir.

**ma_kesisim.sh:**
- `_MA_LOT=100` satiri silinir.
- `strateji_baslat` icerisindeki lot log satiri silinir.
- `echo "ALIS ${_MA_LOT} ${fiyat}"` -> `echo "ALIS"` olur.
- `echo "SATIS ${_MA_LOT} ${fiyat}"` -> `echo "SATIS"` olur.

**rsi.sh:**
- `_RSI_LOT=100` satiri silinir.
- `strateji_baslat` icerisindeki lot log satiri silinir.
- `echo "ALIS ${_RSI_LOT} ${fiyat}"` -> `echo "ALIS"` olur.
- `echo "SATIS ${_RSI_LOT} ${fiyat}"` -> `echo "SATIS"` olur.

**bollinger.sh:**
- `_BB_LOT=100` satiri silinir.
- `strateji_baslat` icerisindeki lot log satiri silinir.
- `echo "ALIS ${_BB_LOT} ${fiyat}"` -> `echo "ALIS"` olur.
- `echo "SATIS ${_BB_LOT} ${fiyat}"` -> `echo "SATIS"` olur.

**ornek.sh:**
- `_ORNEK_LOT=100` satiri silinir.
- `strateji_baslat` icerisindeki lot log satiri silinir.
- `echo "ALIS ${_ORNEK_LOT} ${fiyat}"` -> `echo "ALIS"` olur.
- `echo "SATIS ${_ORNEK_LOT} ${fiyat}"` -> `echo "SATIS"` olur.

**ornek_ohlcv.sh:**
- `_OHLCV_LOT=100` satiri silinir.
- `strateji_baslat` icerisindeki lot log satiri silinir.
- `echo "ALIS ${_OHLCV_LOT} ${fiyat}"` -> `echo "ALIS"` olur.
- `echo "SATIS ${_OHLCV_LOT} ${fiyat}"` -> `echo "SATIS"` olur.

**test_al_sat.sh:**
- `_TEST_LOT=50` satiri silinir.
- `echo "ALIS ${_TEST_LOT} ${fiyat}"` -> `echo "ALIS"` olur.
- `echo "SATIS ${_TEST_LOT} ${fiyat}"` -> `echo "SATIS"` olur.

### 3.2 Backtest Motoru (Lot Hesaplama Ekliyor)

**backtest/motor.sh:**
- `_backtest_parametreleri_coz` fonksiyonuna `--sermaye-yuzde` parametresi eklenir.
- Yeni varsayilan degiskenler eklenir:
  ```
  _BACKTEST_AYAR_SERMAYE_YUZDE="10"   # Varsayilan: bakiyenin %10'u
  ```
- `_backtest_yardim` fonksiyonuna yeni parametre eklenir.
- `_backtest_interaktif_sor` fonksiyonuna sermaye yuzdesi sorusu eklenir.
- `_backtest_onay_goster` fonksiyonuna sermaye yuzdesi bilgisi eklenir.
- `_backtest_ana_dongu` icerisindeki sinyal parse blogu guncellenir:
  Strateji artik sadece "ALIS" veya "SATIS" (ve opsiyonel sinyal gucu) dondurur.
  Lot hesabi bu blokta yapilir.

Sinyal parse degisikligi:

```bash
# --- ONCEKI (mevcut kod) ---
yon=$(echo "$sinyal" | awk '{print $1}')
lot=$(echo "$sinyal" | awk '{print $2}')
emir_fiyat=$(echo "$sinyal" | awk '{print $3}')

# --- SONRAKI (yeni kod) ---
yon=$(echo "$sinyal" | awk '{print $1}')
sinyal_gucu=$(echo "$sinyal" | awk '{print $2}')
# sinyal_gucu bos veya sayi degilse 1.0 kabul et
[[ -z "$sinyal_gucu" ]] && sinyal_gucu="1.0"
# Lot hesapla
lot=$(_backtest_lot_hesapla "$fiyat" "$sinyal_gucu")
emir_fiyat="$fiyat"
```

Yeni fonksiyon: `_backtest_lot_hesapla`

```bash
# _backtest_lot_hesapla <yon> <sembol> <fiyat> <sinyal_gucu>
# Mevcut bakiye ve sermaye yuzdesine gore lot hesaplar.
# ALIS: bakiyenin yuzdesine gore hesaplar.
# SATIS: mevcut pozisyonun tamamini satar.
# stdout: lot sayisi (tamsayi, 0 = emir gonderme)
_backtest_lot_hesapla() {
    local yon="$1"
    local sembol="$2"
    local fiyat="$3"
    local sinyal_gucu="${4:-1.0}"

    if [[ "$yon" == "SATIS" ]]; then
        # Satis: mevcut pozisyonun tamamini sat
        echo "${_BACKTEST_LOT[$sembol]:-0}"
        return 0
    fi

    # Alis: bakiye * yuzde * sinyal_gucu / fiyat
    local nakit="${_BACKTEST_PORTFOY[nakit]}"
    local yuzde="${_BACKTEST_AYAR_SERMAYE_YUZDE:-10}"
    local lot
    lot=$(awk "BEGIN {
        tutar = $nakit * $yuzde / 100 * $sinyal_gucu
        l = int(tutar / $fiyat)
        print (l < 0) ? 0 : l
    }")
    echo "$lot"
}
```

SATIS icin ayri islem gerekmez — `_backtest_lot_hesapla` fonksiyonu
yon parametresine gore SATIS'ta otomatik olarak mevcut pozisyonu dondurur.

### 3.3 Robot Motoru (Lot Hesaplama Ekliyor)

**robot/motor.sh:**
- `robot_baslat` fonksiyonuna `--sermaye-yuzde` parametresi eklenir.
  Varsayilan %10.
- `_robot_karar_isle` icerisindeki sinyal parse blogu guncellenir:
  ```bash
  # --- ONCEKI ---
  read -r islem lot fiyat <<< "$karar"

  # --- SONRAKI ---
  read -r islem sinyal_gucu <<< "$karar"
  [[ -z "$sinyal_gucu" ]] && sinyal_gucu="1.0"
  lot=$(_robot_lot_hesapla "$islem" "$sembol" "$guncel_fiyat" "$sinyal_gucu")
  fiyat="$guncel_fiyat"
  ```
- Yeni fonksiyon: `_robot_lot_hesapla`
  ALIS icin: `adaptor_bakiye_al` ile gercek hesap bakiyesini sorgular,
  sermaye yuzdesi ve sinyal gucuyle lot hesaplar.
  SATIS icin: `adaptor_portfoy_al` ile mevcut pozisyonu sorgular,
  eldeki tum lotu satar.

### 3.4 Backtest Portfoy (Kucuk Uyum)

**backtest/portfoy.sh:**
- `_backtest_emir_isle` degisiklik gerektirmiyor cunku lot zaten parametre olarak aliniyor.
  Lot artik strateji yerine motor tarafindan hesaplanip ayni parametreyle gecirilecek.

### 3.5 Sistem Plani (Dokumantasyon Guncellemesi)

**sistem_plani.md — Bolum 10.2.1:**
- Strateji arayuz sozlesmesindeki sinyal formati guncellenir.
- "ALIS <lot> <fiyat>" yerine "ALIS [sinyal_gucu]" olarak degistirilir.
- Lot hesaplama sorumlulugunu tuketici katmana verildigi aciklanir.

**backtest_plani.md:**
- Lot parametresi ve yontem secenekleri dokumante edilir.

## 4. Geriye Uyumluluk

Gecis doneminde eski formattaki stratejiler de desteklenir.
Backtest motoru ve robot motoru sinyal ciktisini su mantikla parse eder:

```bash
# Sinyal parse (geriye uyumlu)
yon=$(echo "$sinyal" | awk '{print $1}')
ikinci=$(echo "$sinyal" | awk '{print $2}')
ucuncu=$(echo "$sinyal" | awk '{print $3}')

if [[ -n "$ucuncu" ]]; then
    # Eski format: "ALIS 100 312.50" (lot + fiyat var)
    lot="$ikinci"
    emir_fiyat="$ucuncu"
elif [[ -n "$ikinci" ]]; then
    # Sinyal gucu veya eski lot formati ayirt et
    eski_lot_mu=$(echo "$ikinci" | grep -cE '^[0-9]+$')
    if [[ "$eski_lot_mu" -eq 1 ]] && [[ "$ikinci" -gt 1 ]]; then
        # Buyuk ihtimalle eski format lot degeri (tamsayi ve >1)
        lot="$ikinci"
        emir_fiyat="$fiyat"
    else
        # Yeni format: sinyal gucu (0.0-1.0 arasi ondalik)
        sinyal_gucu="$ikinci"
        lot=$(_backtest_lot_hesapla "$fiyat" "$sinyal_gucu")
        emir_fiyat="$fiyat"
    fi
else
    # Yeni format: sadece yon
    sinyal_gucu="1.0"
    lot=$(_backtest_lot_hesapla "$fiyat" "$sinyal_gucu")
    emir_fiyat="$fiyat"
fi
```

Bu geriye uyumluluk kodu, tum stratejiler yeni formata gecirildikten sonra
kaldirilir ve sadece yeni format desteklenir.

## 5. Uygulama Asamalari

### 5.1 Asama 1 — Altyapi (motor tarafinda lot hesaplama)

1. `backtest/motor.sh` icine `_backtest_lot_hesapla` fonksiyonu eklenir.
2. `backtest/motor.sh` parametrelere `--sermaye-yuzde` eklenir (varsayilan %10).
3. `_backtest_ana_dongu` icerisindeki sinyal parse geriye uyumlu hale getirilir.
4. Robot motoru icine `_robot_lot_hesapla` fonksiyonu eklenir
   (gercek bakiyeyi `adaptor_bakiye_al` ile sorgular).
5. `robot_baslat` fonksiyonuna `--sermaye-yuzde` parametresi eklenir.

### 5.2 Asama 2 — Strateji dosyalari guncellenir

1. Tum strateji dosyalarindan lot degiskenleri ve lot kullanimlari cikarilir.
2. Sinyal ciktilari yeni formata cevrilir ("ALIS", "SATIS", "BEKLE").
3. Strateji icindeki pozisyon takibi (ACIK/YOK) baska bir degisiklik gerektirmez,
   strateji kendi yon mantigi icin bu state'i tutmaya devam edebilir.

### 5.3 Asama 3 — Dokumantasyon guncellenir

1. sistem_plani.md Bolum 10.2.1 strateji arayuz sozlesmesi guncellenir.
2. backtest_plani.md lot yonetimi bolumu eklenir.
3. Bu plan dosyasi (lot_ayirma_plani.md) tamamlandi olarak isaretlenir.

### 5.4 Asama 4 — Geriye uyumluluk kodu kaldirilir

Tum stratejiler yeni formattayken:
1. Geriye uyumlu parse kodu cikarilir.
2. Sadece yeni format parse kodu kalir.

## 6. Test Senaryolari

| Senaryo                              | Beklenen Sonuc                             |
|--------------------------------------|--------------------------------------------|
| Varsayilan %10 ile backtest          | 100.000 TL nakitten 10.000 TL'lik lot     |
| `--sermaye-yuzde 20` ile backtest    | 100.000 TL nakitten 20.000 TL'lik lot     |
| Sinyal gucu 0.5 ile %10             | 100.000 * 0.10 * 0.5 = 5.000 TL'lik lot   |
| Satis sinyalinde tam pozisyon cikis  | Mevcut lot kadar satis yapilir             |
| Eski format strateji geriye uyumlu   | "ALIS 100 312.50" hala dogru parse edilir  |
| Bakiye yetersiz (lot 0)              | Emir gonderilmez, BEKLE gibi davranir      |
| Bakiye kuculdukce lot kuculur        | 50.000 -> 25.000 TL'de lot yarilir         |
| Bakiye buyudukce lot buyur           | 100.000 -> 150.000 TL'de lot %50 artar    |
| Robot gercek bakiyeden hesaplar      | adaptor_bakiye_al sonucuna gore lot        |

## 7. Ozet

Lot miktari bir risk yonetimi kararidir ve stratejinin disinda tutulmalidir.
Bu degisiklik ile strateji katmani sadece "ne zaman" sorusuna odaklanir,
"ne kadar" sorusunu tuketici katman (backtest veya robot motoru) yanit verir.
Bu ayrim sayesinde ayni strateji farkli sermaye buyuklukleri, farkli risk
profilleri ve farkli lot yontemleri ile yeniden kullanilebilir hale gelir.
