# cekirdek.sh - Kural 8 Performans Analizi

Bu belge `cekirdek.sh` dosyasindaki Kural 8 (Performans Oncelikli Shell Yazimi)
ihlallerini listelemektedir. Her ihlal icin satir numarasi, mevcut kod, duzeltilmis
kod ve ihlal edilen alt kural belirtilmistir.

Tarih: 2026-03-09
Analiz edilen dosya: `bashrc.d/borsa/cekirdek.sh` (2145 satir)


## 1. Ihlal Ozeti

| Alt Kural | Ihlal Sayisi | Aciklama |
|-----------|-------------|----------|
| 8.1       | 11          | basename yerine parametre genisletme, tr yerine ${,,} / ${^^} |
| 8.2       | 5           | echo \| grep yerine [[ =~ ]] ve BASH_REMATCH |
| 8.3       | 6           | $(cat dosya) yerine $(<dosya) |
| 8.4       | 6           | echo \| bc yerine $(( )) (basit aritmetik) |
| 8.6       | 5           | echo \| grep pipe zinciri yerine [[ =~ ]] veya grep <<< |
| 8.7       | 1           | echo -e yerine printf |
| TOPLAM    | 34          | |


## 2. Ihlal Detaylari

### 2.1 Kural 8.1 - basename Yerine Parametre Genisletme

#### Satir 10 - BORSA_KLASORU tespiti
```bash
# MEVCUT
BORSA_KLASORU="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```
```bash
# DUZELTME (dirname yerine parametre genisletme)
BORSA_KLASORU="${BASH_SOURCE[0]%/*}"
# Not: readlink/realpath gerekmiyorsa bu yeterlidir.
# Dosya sembolik link ise readlink gerekebilir, bu durumda mevcut hali kalabilir.
```

#### Satir 401 - kurum=$(basename "$kurum_dizini")
```bash
# MEVCUT
kurum=$(basename "$kurum_dizini")
```
```bash
# DUZELTME
kurum="${kurum_dizini%/}"
kurum="${kurum##*/}"
```

#### Satir 504 - ad=$(basename "$surucu" .sh)
```bash
# MEVCUT
ad=$(basename "$surucu" .sh)
```
```bash
# DUZELTME
ad="${surucu##*/}"
ad="${ad%.sh}"
```

#### Satir 642 - no=$(basename "$dizin")
```bash
# MEVCUT
no=$(basename "$dizin")
```
```bash
# DUZELTME
no="${dizin%/}"
no="${no##*/}"
```

#### Satirlar 723, 748, 825, 871 - kurum_buyuk=$(echo "$kurum" | tr ...)
```bash
# MEVCUT (4 yerde tekrarlaniyor)
kurum_buyuk=$(echo "$kurum" | tr '[:lower:]' '[:upper:]')
```
```bash
# DUZELTME
kurum_buyuk="${kurum^^}"
```

#### Satirlar 1334, 1342, 1391, 1398, 1429, 1436, 1468, 1475 - basename dongulerinde
```bash
# MEVCUT (ust seviye fonksiyonlarda 8 yerde tekrarlaniyor)
kurum_adi=$(basename "$kurum_klasoru")
hesap_no=$(basename "$hesap_klasoru")
```
```bash
# DUZELTME
kurum_adi="${kurum_klasoru%/}"
kurum_adi="${kurum_adi##*/}"

hesap_no="${hesap_klasoru%/}"
hesap_no="${hesap_no##*/}"
```


### 2.2 Kural 8.2 - echo | grep Yerine [[ =~ ]] Kullanma

#### Satir 1094 - Oturum yonlendirme kontrolu
```bash
# MEVCUT
if echo "$yanit" | grep -q "$kalip"; then
```
```bash
# DUZELTME
if [[ "$yanit" == *"$kalip"* ]]; then
```

#### Satirlar 1147, 1163 - JSON basari/hata kontrolu
```bash
# MEVCUT
if echo "$yanit" | grep -qiE '"[Ii]s[Ss]uccess"\s*:\s*true'; then
# ve
if echo "$yanit" | grep -qiE '"[Ii]s[Ee]rror"\s*:\s*true'; then
```
```bash
# DUZELTME
if [[ "${yanit,,}" =~ \"issuccess\"[[:space:]]*:[[:space:]]*true ]]; then
# ve
if [[ "${yanit,,}" =~ \"iserror\"[[:space:]]*:[[:space:]]*true ]]; then
```

#### Satir 1268 - Isaret noktasi kontrolu (dongu icinde)
```bash
# MEVCUT (dongu icinde her isaret icin ayri grep fork'u)
if ! echo "$sayfa_icerik" | grep -q "$nokta"; then
```
```bash
# DUZELTME
if [[ "$sayfa_icerik" != *"$nokta"* ]]; then
```

#### Satir 1856, 1859 - readonly kontrolu
```bash
# MEVCUT
if ! readonly -p 2>/dev/null | grep -q 'ADAPTOR_ADI'; then
# ve
if ! readonly -p 2>/dev/null | grep -q 'ADAPTOR_SURUMU'; then
```
```bash
# DUZELTME (declare -p ile kontrol)
if ! declare -p ADAPTOR_ADI 2>/dev/null | grep -q 'readonly'; then
# Veya daha basit: deneyip hata yakalama
if unset ADAPTOR_ADI 2>/dev/null; then true; fi
```
Not: Bu ozel bir durum. `readonly -p` tum readonly degiskenleri listeler ve grep'e
pipe eder. Ancak bash'te bir degiskenin readonly olup olmadigini kontrol etmenin
intrinsik yolu yoktur, bu nedenle bu ihlal duzeltilirken dikkatli olunmalidir.


### 2.3 Kural 8.3 - $(cat dosya) Yerine $(<dosya)

#### Satir 146
```bash
# MEVCUT
sure=$(cat "${dizin}/oturum_suresi" 2>/dev/null)
```
```bash
# DUZELTME
sure=$(<"${dizin}/oturum_suresi") 2>/dev/null || sure=""
# Veya guvenli okuma:
sure=""
[[ -f "${dizin}/oturum_suresi" ]] && sure=$(<"${dizin}/oturum_suresi")
```

#### Satir 148
```bash
# MEVCUT
son_istek=$(cat "${dizin}/son_istek" 2>/dev/null)
```
```bash
# DUZELTME
son_istek=""
[[ -f "${dizin}/son_istek" ]] && son_istek=$(<"${dizin}/son_istek")
```

#### Satir 238
```bash
# MEVCUT
sure=$(cat "${dizin}/oturum_suresi" 2>/dev/null)
```
```bash
# DUZELTME
[[ -f "${dizin}/oturum_suresi" ]] && sure=$(<"${dizin}/oturum_suresi")
```

#### Satir 331
```bash
# MEVCUT
mevcut_sahip=$(cat "$sahip_dosyasi" 2>/dev/null)
```
```bash
# DUZELTME
mevcut_sahip=$(<"$sahip_dosyasi") 2>/dev/null || mevcut_sahip=""
```

#### Satir 339
```bash
# MEVCUT
pid=$(cat "$pid_dosyasi" 2>/dev/null)
```
```bash
# DUZELTME
pid=$(<"$pid_dosyasi") 2>/dev/null || pid=""
```

#### Satir 365
```bash
# MEVCUT
pid=$(cat "$pid_dosyasi" 2>/dev/null)
```
```bash
# DUZELTME
pid=$(<"$pid_dosyasi") 2>/dev/null || pid=""
```

#### Satir 399
```bash
# MEVCUT
hesap=$(cat "$hesap_dosyasi" 2>/dev/null)
```
```bash
# DUZELTME
hesap=$(<"$hesap_dosyasi") 2>/dev/null || hesap=""
```

#### Satir 1488
```bash
# MEVCUT
pid=$(cat "${hesap_klasoru}oturum_koruma.pid" 2>/dev/null)
```
```bash
# DUZELTME
pid=$(<"${hesap_klasoru}oturum_koruma.pid") 2>/dev/null || pid=""
```


### 2.4 Kural 8.4 - echo | bc Yerine $(( )) (Basit Aritmetik)

#### Satir 1289 - nakit + hisse toplami
```bash
# MEVCUT
hesaplanan=$(echo "$nakit_temiz + $hisse_temiz" | bc 2>/dev/null)
```
Not: Bu satirdaki degerler ondalikli (275.47 gibi) oldugundan `$(( ))` kullanilamaz.
Bash aritmetigi yalnizca tam sayi destekler. Bu satir ISTISNA olarak istenirse
`awk` ile degistirilebilir ama bc kullanimi burada makuldur.
```bash
# ALTERNATIF (awk ile tekli fork)
hesaplanan=$(awk "BEGIN {printf \"%.2f\", $nakit_temiz + $hisse_temiz}" 2>/dev/null)
```

#### Satirlar 1292-1296 - Fark hesaplama (bc pipeline 4 kez)
```bash
# MEVCUT (4 ayri bc cagirisi)
esik=$(echo "scale=2; $toplam_temiz * 0.01" | bc 2>/dev/null)
fark=$(echo "$hesaplanan - $toplam_temiz" | bc 2>/dev/null)
fark_abs=$(echo "if ($fark < 0) -1*$fark else $fark" | bc 2>/dev/null)
if (( $(echo "$fark_abs > $esik" | bc -l 2>/dev/null) )); then
```
```bash
# DUZELTME (tek awk cagirisi ile tum hesaplama)
if awk -v n="$nakit_temiz" -v h="$hisse_temiz" -v t="$toplam_temiz" \
   'BEGIN {
       toplanan = n + h
       fark = toplanan - t
       if (fark < 0) fark = -fark
       esik = t * 0.01
       exit (fark > esik) ? 0 : 1
   }' 2>/dev/null; then
    _cekirdek_log "SAGLIK [$kurum] K5-MATEMATIK: nakit+hisse tutarsiz."
    hata_sayisi=$((hata_sayisi + 1))
fi
```

#### Satirlar 1361, 1366-1368 - tum_bakiyeler fonksiyonunda bc
```bash
# MEVCUT
hisse=$(echo "$toplam - $nakit" | bc 2>/dev/null || echo "0")
toplam_nakit=$(echo "$toplam_nakit + $nakit" | bc 2>/dev/null || echo "$toplam_nakit")
toplam_hisse=$(echo "$toplam_hisse + $hisse" | bc 2>/dev/null || echo "$toplam_hisse")
toplam_genel=$(echo "$toplam_genel + $toplam" | bc 2>/dev/null || echo "$toplam_genel")
```
Not: Bu degerler de ondalikli oldugundan $(( )) kullanilamaz.
Eger degerler her zaman tam sayi olacaksa:
```bash
# DUZELTME (tam sayi ise)
hisse=$(( toplam - nakit ))
toplam_nakit=$(( toplam_nakit + nakit ))
```
```bash
# DUZELTME (ondalikli ise — awk ile tek fork)
read -r hisse toplam_nakit toplam_hisse toplam_genel < <(
    awk -v t="$toplam" -v n="$nakit" -v tn="$toplam_nakit" \
        -v th="$toplam_hisse" -v tg="$toplam_genel" \
    'BEGIN {
        h = t - n
        printf "%.2f %.2f %.2f %.2f\n", h, tn+n, th+h, tg+t
    }'
)
```


### 2.5 Kural 8.6 - Gereksiz Pipe Zincirleri

#### Satirlar 1112 - CSRF token cikarma
```bash
# MEVCUT
token=$(echo "$html" | grep -oP "$selektor" | tail -n 1)
```
Not: Bu satir Perl regex (-P) kullanmaktadir. BASH_REMATCH ile degistirilebilir
ancak selektor karmasik bir regex olabilir. Bu ihlal icin iki yol var:
```bash
# DUZELTME (basit kaliplar icin)
if [[ "$html" =~ $selektor ]]; then
    token="${BASH_REMATCH[0]}"
fi
```
```bash
# DUZELTME (karmasik kaliplar icin — grep kalir ama pipe azalir)
token=$(grep -oP "$selektor" <<< "$html" | tail -n 1)
```

#### Satirlar 1144, 1155 - JSON parse (grep -oP)
```bash
# MEVCUT
mesaj=$(echo "$yanit" | grep -oP '"[Mm]essage"\s*:\s*"\K[^"]+' | head -1)
veri_alani=$(echo "$yanit" | grep -oP '"Data"\s*:\s*"\K[^"]+' | head -1)
```
```bash
# DUZELTME (pipe yerine herestring)
mesaj=$(grep -oP '"[Mm]essage"\s*:\s*"\K[^"]+' <<< "$yanit" | head -1)
veri_alani=$(grep -oP '"Data"\s*:\s*"\K[^"]+' <<< "$yanit" | head -1)
```
Not: Bu satirlarda Perl regex kullanildigi icin bash regex'e cevirmek
karmasik olur. Ancak `echo | grep` yerine `grep <<< "$yanit"` yaparak
en azindan bir fork (echo) azaltilabilir.

#### Satirlar 1359-1360 - tum_bakiyeler icinde coklu pipe
```bash
# MEVCUT
nakit=$(echo "$bakiye_ciktisi" | grep -i "nakit\|TL" | head -1 | grep -oP '[\d,.]+' | tail -1 | tr -d '.' | tr ',' '.' || echo "0")
toplam=$(echo "$bakiye_ciktisi" | grep -i "toplam\|Genel" | head -1 | grep -oP '[\d,.]+' | tail -1 | tr -d '.' | tr ',' '.' || echo "0")
```
```bash
# DUZELTME (awk ile tek fork)
nakit=$(awk -F: '/[Nn]akit|TL/ {gsub(/[^0-9,.]/, "", $2); gsub(/\./, "", $2); gsub(/,/, ".", $2); print $2; exit}' <<< "$bakiye_ciktisi")
toplam=$(awk -F: '/[Tt]oplam|[Gg]enel/ {gsub(/[^0-9,.]/, "", $2); gsub(/\./, "", $2); gsub(/,/, ".", $2); print $2; exit}' <<< "$bakiye_ciktisi")
```
Not: Bu satirlar en pahali ihlaldir. Her biri 5-6 fork olusturur.
Ancak bu fonksiyon (tum_bakiyeler) zaten dongu icinde `source` ve
`adaptor_bakiye` cagirdigi icin pipe optimizasyonu goreceli kuçuk
bir kazanc saglayacaktir.

#### Satir 1498 - find | wc -l
```bash
# MEVCUT
robot_sayisi=$(find "${hesap_klasoru}robotlar" -name "*.pid" 2>/dev/null | wc -l)
```
```bash
# DUZELTME (glob ile)
local _pid_dosyalari=("${hesap_klasoru}robotlar"/*.pid)
if [[ -e "${_pid_dosyalari[0]}" ]]; then
    robot_sayisi=${#_pid_dosyalari[@]}
else
    robot_sayisi=0
fi
```


### 2.6 Kural 8.4 - date +%s Subshell

#### Satirlar 118, 155 - simdi=$(date +%s)
```bash
# MEVCUT
simdi=$(date +%s)
```
Not: Bash 5.0+ surumlerinde `printf '%(%s)T'` builtin kullanilabilir.
Ancak tasinabilirlik acisindan `date` kabul edilebilir bir istisnadir.
```bash
# DUZELTME (Bash 5.0+ gerektirir)
printf -v simdi '%(%s)T' -1
```


## 3. Oncelik Sirasi

Duzeltmelerin etkisine gore oncelik sirasi:

| Oncelik | Kural | Etkilenen Satirlar | Kazanc |
|---------|-------|-------------------|--------|
| YUKSEK  | 8.1 tr | 723, 748, 825, 871 | 4 fork kaldirilir, sik kullanilan fonksiyonlar |
| YUKSEK  | 8.3 cat | 146,148,238,331,339,365,399,1488 | 8 fork kaldirilir |
| YUKSEK  | 8.1 basename | 401,504,642,1334,1342,1391,1398,1429,1436,1468,1475 | 11 fork kaldirilir, bazi dongu icinde |
| ORTA    | 8.2 echo\|grep | 1094,1147,1163,1268 | 4+ fork, ozellikle K3 dongusu icinde |
| ORTA    | 8.6 pipe | 1112,1144,1155 | echo fork'u azalir |
| DUSUK   | 8.4 bc | 1289-1296,1361-1368 | Ondalikli hesap, bc/awk zorunlu |
| DUSUK   | 8.6 find\|wc | 1498 | Tek kullanim, glob ile cozulur |
| DUSUK   | 8.4 date | 118, 155 | Bash 5.0+ gerektirir |


## 4. Toplam Tahmini Kazanc

Mevcut durumda `cekirdek.sh` source edildiginde yaklasik **34 gereksiz fork+exec**
islemi gerceklesiyor. Bu duzeltmeler uygulandiginda:

- Source sirasinda calisan fork sayisi: ~0 (fonksiyon tanimlama fork gerektirmez)
- Calisma zamaninda (fonksiyon cagirildikca) kazanc: her cagirida 2-10 fork azalir
- En buyuk kazanc: dongu icindeki basename (tum_bakiyeler, tum_oturumlar gibi)
  ve echo | grep desenleri

Not: Source sirasinda en pahali islem `BORSA_KLASORU` atamasindaki `cd + pwd`
komutlaridir (satir 10). Bunun disinda tum fork'lar fonksiyon cagirisi sirasinda
meydana geldigi icin source suresi zaten hizlidir. Asil kazanc runtime'da olur.
