# shellcheck shell=bash
# ============================================================
# 03-zamanlayici.sh - Terminal Tabanli Alarm ve Geri Sayim Araci
# ============================================================

# ============================================================
# Zamanlayici - Terminal Tabanli Alarm ve Geri Sayim Araci
# (zamanlayici.sh'den bashrc'ye tasinmistir)
# ============================================================
# ============================================================
# Zamanlayici - Terminal Tabanli Alarm ve Geri Sayim Araci
# ============================================================
# xfce4-timer-plugin'in tum ozelliklerini terminal uzerinden
# yonetmeyi saglar.
#
# Kullanim: source zamanlayici.sh
# Sonra asagidaki komutlari kullanabilirsin.
# ============================================================

# --- Yapilandirma ---
ZAMANLAYICI_DIZIN="$HOME/.zamanlayici"
ALARM_DOSYASI="$ZAMANLAYICI_DIZIN/alarmlar.json"
ALARM_SES="/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
VARSAYILAN_TEKRAR=1
VARSAYILAN_ARALIK=3

# Dizin ve dosya olustur
mkdir -p "$ZAMANLAYICI_DIZIN"
if [ ! -f "$ALARM_DOSYASI" ]; then
    echo '[]' > "$ALARM_DOSYASI"
fi

# ============================================================
# YARDIMCI FONKSIYONLAR
# ============================================================

_zaman_goster() {
    local saniye=$1
    local sa=$((saniye / 3600))
    local dk=$(( (saniye % 3600) / 60 ))
    local sn=$((saniye % 60))
    if [ $sa -gt 0 ]; then
        printf '%02d:%02d:%02d' $sa $dk $sn
    else
        printf '%02d:%02d' $dk $sn
    fi
}

_ses_cal() {
    local tekrar=${1:-$VARSAYILAN_TEKRAR}
    local aralik=${2:-$VARSAYILAN_ARALIK}
    local i=0
    while [ "$i" -lt "$tekrar" ]; do
        paplay "$ALARM_SES" 2>/dev/null
        i=$((i + 1))
        if [ "$i" -lt "$tekrar" ]; then
            sleep "$aralik"
        fi
    done
}

_ses_dongulu() {
    # Kullanici durdurana kadar ses cal
    while true; do
        paplay "$ALARM_SES" 2>/dev/null
        sleep 1
    done
}

# --- Arka Plan Alarm Fonksiyonu ---
# Terminal kapansa bile calisan bagimsiz surec olusturur.
# Kullanim: _arka_plan_alarm SANIYE ISIM [SECENEKLER]
_arka_plan_alarm() {
    local saniye=$1
    local isim=$2
    local sessiz=${3:-0}
    local tekrar=${4:-$VARSAYILAN_TEKRAR}
    local aralik=${5:-$VARSAYILAN_ARALIK}
    local dongulu=${6:-0}
    local komut="$7"
    local ses_dosyasi="$ALARM_SES"
    local dizin="$ZAMANLAYICI_DIZIN"

    # Gecici script olustur - terminal kapansa bile calisir
    local script="$dizin/arkaplan_$$.sh"
    cat > "$script" << 'ARKAPLAN_BASI'
#!/bin/bash
# Arka plan alarm scripti - terminal bagimsiz
_saniye=$1; _isim=$2; _sessiz=$3; _tekrar=$4
_aralik=$5; _dongulu=$6; _komut=$7; _ses=$8; _dizin=$9

# PID kaydet
echo $$ > "$_dizin/aktif_$$.pid"

# Kullaniciya bildir
DISPLAY=:0 notify-send "Alarm Kuruldu" "$_isim: $(date -d "+${_saniye} seconds" +%H:%M:%S) - Arka planda calisiyor" 2>/dev/null

# Geri sayim (sessizce bekle)
sleep "$_saniye"

# PID dosyasini temizle
rm -f "$_dizin/aktif_$$.pid"

# Bildirim gonder
DISPLAY=:0 notify-send "$_isim" "Sure doldu!" 2>/dev/null

# Komut calistir
if [ -n "$_komut" ]; then
    eval "$_komut"
fi

# Ses cal
if [ "$_sessiz" != "1" ]; then
    if [ "$_dongulu" = "1" ]; then
        while true; do
            DISPLAY=:0 paplay "$_ses" 2>/dev/null
            sleep 1
        done
    else
        _i=0
        while [ $_i -lt "$_tekrar" ]; do
            DISPLAY=:0 paplay "$_ses" 2>/dev/null
            _i=$((_i + 1))
            [ $_i -lt "$_tekrar" ] && sleep "$_aralik"
        done
    fi
fi

# Kendini temizle
rm -f "$0"
ARKAPLAN_BASI

    chmod +x "$script"

    # setsid ile terminal bagimsiz calistir
    setsid bash "$script" "$saniye" "$isim" "$sessiz" "$tekrar" "$aralik" "$dongulu" "$komut" "$ses_dosyasi" "$dizin" </dev/null &>/dev/null &
    disown $! 2>/dev/null

    local arka_pid=$!
    echo "  [Arka Plan] PID: $arka_pid - Terminal kapansa bile calisacak"
}

# ============================================================
# 1. GERI SAYIM (COUNTDOWN)
# ============================================================
# Kullanim:
#   gerisayim 40          -> 40 dakika
#   gerisayim 1:30:00     -> 1 saat 30 dakika
#   gerisayim 0:0:30      -> 30 saniye
#   gerisayim 5 -s        -> 5 dakika, sessiz (ses calma)
#   gerisayim 5 -k "ls"   -> 5 dk, bitince "ls" komutunu calistir
#   gerisayim 5 -t 3 -a 5 -> 5 dk, sesi 3 kez 5sn arayla tekrarla
#   gerisayim 40 -b        -> 40 dk, arka planda (terminal kapansa bile calisir)
# ============================================================

gerisayim() {
    if [ $# -lt 1 ]; then
        echo "Kullanim: gerisayim SURE [SECENEKLER]"
        echo ""
        echo "SURE formatlari:"
        echo "  40        -> 40 dakika"
        echo "  1:30:00   -> 1 saat 30 dakika"
        echo "  0:0:30    -> 30 saniye"
        echo ""
        echo "Secenekler:"
        echo "  -s          Sessiz mod (ses calma)"
        echo "  -k KOMUT    Sure dolunca komutu calistir"
        echo "  -t SAYI     Sesi kac kez tekrarla (varsayilan: $VARSAYILAN_TEKRAR)"
        echo "  -a SANIYE   Tekrarlar arasi bekleme (varsayilan: $VARSAYILAN_ARALIK sn)"
        echo "  -i ISIM     Zamanlayiciya isim ver"
        echo "  -d          Dongulu ses (durdurana kadar calsin)"
        echo "  -b          Arka plan modu (terminal kapansa bile calisir)"
        return 1
    fi

    # Sure hesapla
    local sure_girdi="$1"
    shift
    local toplam_saniye=0

    if [[ "$sure_girdi" == *:*:* ]]; then
        # sa:dk:sn formati
        IFS=':' read -r sa dk sn <<< "$sure_girdi"
        toplam_saniye=$(( sa * 3600 + dk * 60 + sn ))
    elif [[ "$sure_girdi" == *:* ]]; then
        # dk:sn formati
        IFS=':' read -r dk sn <<< "$sure_girdi"
        toplam_saniye=$(( dk * 60 + sn ))
    else
        # Sadece dakika
        toplam_saniye=$(( sure_girdi * 60 ))
    fi

    if [ $toplam_saniye -le 0 ]; then
        echo "HATA: Gecersiz sure."
        return 1
    fi

    # Secenekleri isle
    local sessiz=0
    local komut=""
    local tekrar=$VARSAYILAN_TEKRAR
    local aralik=$VARSAYILAN_ARALIK
    local isim="Zamanlayici"
    local dongulu=0
    local arkaplan=0

    while [ $# -gt 0 ]; do
        case "$1" in
            -s) sessiz=1 ;;
            -k) shift; komut="$1" ;;
            -t) shift; tekrar="$1" ;;
            -a) shift; aralik="$1" ;;
            -i) shift; isim="$1" ;;
            -d) dongulu=1 ;;
            -b) arkaplan=1 ;;
            *) echo "Bilinmeyen secenek: $1"; return 1 ;;
        esac
        shift
    done

    # Arka plan modunda calistir (terminal bagimsiz)
    if [ $arkaplan -eq 1 ]; then
        echo "[$isim] Arka plan alarmi kuruldu: $(_zaman_goster $toplam_saniye)"
        _arka_plan_alarm "$toplam_saniye" "$isim" "$sessiz" "$tekrar" "$aralik" "$dongulu" "$komut"
        return 0
    fi

    echo "[$isim] Geri sayim basladi: $(_zaman_goster $toplam_saniye)"
    echo "Durdurmak icin: Ctrl+C"
    echo ""

    # PID dosyasi olustur (durdurma icin)
    echo $$ > "$ZAMANLAYICI_DIZIN/aktif_$$.pid"

    # Geri sayim
    local kalan=$toplam_saniye
    while [ $kalan -gt 0 ]; do
        local yuzde=$(( (toplam_saniye - kalan) * 100 / toplam_saniye ))
        local cubuk_dolu=$(( yuzde / 5 ))
        local cubuk_bos=$(( 20 - cubuk_dolu ))
        local cubuk
        cubuk=$(printf '%0.s#' $(seq 1 "$cubuk_dolu" 2>/dev/null))
        local bosluk
        bosluk=$(printf '%0.s-' $(seq 1 "$cubuk_bos" 2>/dev/null))

        printf "\r  [$isim] [%s%s] %3d%%  Kalan: %s  " "$cubuk" "$bosluk" "$yuzde" "$(_zaman_goster $kalan)"
        sleep 1
        kalan=$((kalan - 1))
    done

    printf "\r  [$isim] [####################] 100%%  SURE DOLDU!            \n"
    echo ""

    # Temizlik
    rm -f "$ZAMANLAYICI_DIZIN/aktif_$$.pid"

    # Bildirim
    notify-send "$isim" "Sure doldu! ($(_zaman_goster $toplam_saniye))" 2>/dev/null

    # Komut calistir
    if [ -n "$komut" ]; then
        echo "Komut calistiriliyor: $komut"
        eval "$komut"
    fi

    # Ses cal
    if [ $sessiz -eq 0 ]; then
        if [ $dongulu -eq 1 ]; then
            echo "Ses caliniyor... Durdurmak icin ENTER'a bas."
            _ses_dongulu &
            local ses_pid=$!
            read -r
            kill $ses_pid 2>/dev/null
            wait $ses_pid 2>/dev/null
            echo "Ses durduruldu."
        else
            _ses_cal "$tekrar" "$aralik"
        fi
    fi
}

# ============================================================
# 2. ALARM (BELIRLI SAATTE)
# ============================================================
# Kullanim:
#   alarm 14:30           -> Saat 14:30'da calssin
#   alarm 14:30 -k "komut" -> 14:30'da komutu calistir
#   alarm 14:30 -i "Ogle" -> Isim ver
#   alarm 14:30 -d        -> Dongulu ses
# ============================================================

alarm() {
    if [ $# -lt 1 ]; then
        echo "Kullanim: alarm SAAT:DAKIKA [SECENEKLER]"
        echo ""
        echo "Ornekler:"
        echo "  alarm 14:30           -> 14:30'da alarm"
        echo "  alarm 14:30 -i Ogle   -> Isimli alarm"
        echo "  alarm 08:00 -k 'komut' -> 08:00'de komutu calistir"
        echo "  alarm 14:30 -d        -> Dongulu ses (durdurana kadar)"
        echo ""
        echo "Secenekler:"
        echo "  -s          Sessiz mod"
        echo "  -k KOMUT    Alarm calinca komutu calistir"
        echo "  -t SAYI     Sesi kac kez tekrarla"
        echo "  -a SANIYE   Tekrarlar arasi bekleme"
        echo "  -i ISIM     Alarma isim ver"
        echo "  -d          Dongulu ses"
        return 1
    fi

    local hedef_saat="$1"
    shift

    # Saat formatini kontrol et
    if ! [[ "$hedef_saat" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
        echo "HATA: Saat formati yanlis. Ornek: 14:30"
        return 1
    fi

    local hedef_sa=${hedef_saat%%:*}
    local hedef_dk=${hedef_saat##*:}

    if [ "$hedef_sa" -gt 23 ] || [ "$hedef_dk" -gt 59 ]; then
        echo "HATA: Gecersiz saat."
        return 1
    fi

    # Simdi ile hedef arasi farki hesapla
    local simdi
    simdi=$(date +%s)
    local bugun
    bugun=$(date +%Y-%m-%d)
    local hedef
    hedef=$(date -d "$bugun $hedef_saat" +%s 2>/dev/null)

    if [ -z "$hedef" ]; then
        echo "HATA: Tarih hesaplanamadi."
        return 1
    fi

    # Eger hedef saat gecmisse, yarini al
    if [ "$hedef" -le "$simdi" ]; then
        local yarin
        yarin=$(date -d "+1 day" +%Y-%m-%d)
        hedef=$(date -d "$yarin $hedef_saat" +%s)
        echo "Not: Belirtilen saat gecmis, yarin $hedef_saat icin alarm kuruldu."
    fi

    local fark=$((hedef - simdi))
    echo "Alarm kuruldu: $hedef_saat (kalan: $(_zaman_goster $fark))"

    # Secenekleri isle
    local sessiz=0
    local komut=""
    local tekrar=$VARSAYILAN_TEKRAR
    local aralik=$VARSAYILAN_ARALIK
    local isim="Alarm $hedef_saat"
    local dongulu=0

    while [ $# -gt 0 ]; do
        case "$1" in
            -s) sessiz=1 ;;
            -k) shift; komut="$1" ;;
            -t) shift; tekrar="$1" ;;
            -a) shift; aralik="$1" ;;
            -i) shift; isim="$1" ;;
            -d) dongulu=1 ;;
        esac
        shift
    done

    # Alarm her zaman arka planda calisir (terminal kapansa bile devam eder)
    _arka_plan_alarm "$fark" "$isim" "$sessiz" "$tekrar" "$aralik" "$dongulu" "$komut"
    echo "  [Bilgi] Terminal kapatsaniz bile alarm calacak."
}

# ============================================================
# 3. ALARM KAYDET / YUKLE / LISTELE / SIL
# ============================================================

alarm_kaydet() {
    if [ $# -lt 2 ]; then
        echo "Kullanim: alarm_kaydet ISIM SURE [SECENEKLER]"
        echo ""
        echo "Ornekler:"
        echo "  alarm_kaydet 'Deneme' 40"
        echo "  alarm_kaydet 'Cay' 0:3:00 -d"
        echo "  alarm_kaydet 'Toplanti' 14:30 -saat"
        echo ""
        echo "Secenekler:"
        echo "  -saat       Saat modunda kaydet (alarm olarak)"
        echo "  -k KOMUT    Sure dolunca calisacak komut"
        echo "  -t SAYI     Tekrar sayisi"
        echo "  -a SANIYE   Tekrar araligi"
        echo "  -d          Dongulu ses"
        echo "  -s          Sessiz"
        return 1
    fi

    local isim="$1"
    local sure="$2"
    shift 2

    local tip="gerisayim"
    local komut=""
    local tekrar=$VARSAYILAN_TEKRAR
    local aralik=$VARSAYILAN_ARALIK
    local sessiz=0
    local dongulu=0

    while [ $# -gt 0 ]; do
        case "$1" in
            -saat) tip="alarm" ;;
            -k) shift; komut="$1" ;;
            -t) shift; tekrar="$1" ;;
            -a) shift; aralik="$1" ;;
            -s) sessiz=1 ;;
            -d) dongulu=1 ;;
        esac
        shift
    done

    # JSON'a ekle (python3 ile guvenli)
    python3 -c "
import json
d = json.load(open('$ALARM_DOSYASI'))
d.append({
    'isim': '$isim',
    'sure': '$sure',
    'tip': '$tip',
    'komut': '$komut',
    'tekrar': $tekrar,
    'aralik': $aralik,
    'sessiz': $sessiz,
    'dongulu': $dongulu
})
json.dump(d, open('$ALARM_DOSYASI', 'w'), ensure_ascii=False, indent=2)
" 2>/dev/null

    echo "Alarm kaydedildi: '$isim'"
}

alarm_listele() {
    echo "============================================"
    echo "  Kayitli Alarmlar"
    echo "============================================"

    if [ ! -f "$ALARM_DOSYASI" ] || [ "$(cat "$ALARM_DOSYASI")" = "[]" ]; then
        echo "  (Kayitli alarm yok)"
        echo "============================================"
        return 0
    fi

    python3 -c "
import json
d = json.load(open('$ALARM_DOSYASI'))
if not d:
    print('  (Kayitli alarm yok)')
else:
    for i, a in enumerate(d):
        tip = 'Saat Alarmi' if a.get('tip') == 'alarm' else 'Geri Sayim'
        ses = 'Dongulu' if a.get('dongulu') else ('Sessiz' if a.get('sessiz') else 'Normal')
        satir = f\"  [{i+1}] {a['isim']:<15s} | {tip:<12s} | {a['sure']:<8s} | Ses: {ses:<8s}\"
        if a.get('komut'):
            satir += f\" | Komut: {a['komut']}\"
        print(satir)
    print('============================================')
    print(f'  Toplam: {len(d)} alarm')
" 2>/dev/null

    echo "============================================"
}

alarm_sil() {
    if [ $# -lt 1 ]; then
        echo "Kullanim: alarm_sil NUMARA"
        echo "         alarm_sil hepsi"
        echo ""
        echo "Listeyi gormek icin: alarm_listele"
        return 1
    fi

    if [ "$1" = "hepsi" ]; then
        echo '[]' > "$ALARM_DOSYASI"
        echo "Tum alarmlar silindi."
        return 0
    fi

    local sira=$1
    python3 -c "
import json
d = json.load(open('$ALARM_DOSYASI'))
idx = $sira - 1
if 0 <= idx < len(d):
    silinen = d.pop(idx)
    json.dump(d, open('$ALARM_DOSYASI', 'w'), ensure_ascii=False)
    print(f\"Silindi: '{silinen['isim']}'\")
else:
    print('HATA: Gecersiz numara.')
" 2>/dev/null
}

alarm_calistir() {
    if [ $# -lt 1 ]; then
        echo "Kullanim: alarm_calistir NUMARA"
        echo "         alarm_calistir ISIM"
        echo ""
        echo "Listeyi gormek icin: alarm_listele"
        return 1
    fi

    local secim="$1"
    local sonuc

    # Numara mi isim mi kontrol et
    if [[ "$secim" =~ ^[0-9]+$ ]]; then
        sonuc=$(python3 -c "
import json
d = json.load(open('$ALARM_DOSYASI'))
idx = $secim - 1
if 0 <= idx < len(d):
    a = d[idx]
    args = []
    if a.get('komut'): args += ['-k', a['komut']]
    if a.get('sessiz'): args.append('-s')
    if a.get('dongulu'): args.append('-d')
    args += ['-t', str(a.get('tekrar',1))]
    args += ['-a', str(a.get('aralik',3))]
    args += ['-i', a['isim']]
    print(a['tip'] + '|' + a['sure'] + '|' + ' '.join(args))
else:
    print('HATA')
" 2>/dev/null)
    else
        sonuc=$(python3 -c "
import json
d = json.load(open('$ALARM_DOSYASI'))
for a in d:
    if a['isim'] == '$secim':
        args = []
        if a.get('komut'): args += ['-k', a['komut']]
        if a.get('sessiz'): args.append('-s')
        if a.get('dongulu'): args.append('-d')
        args += ['-t', str(a.get('tekrar',1))]
        args += ['-a', str(a.get('aralik',3))]
        args += ['-i', a['isim']]
        print(a['tip'] + '|' + a['sure'] + '|' + ' '.join(args))
        break
else:
    print('HATA')
" 2>/dev/null)
    fi

    if [ "$sonuc" = "HATA" ] || [ -z "$sonuc" ]; then
        echo "HATA: Alarm bulunamadi."
        return 1
    fi

    local tip="${sonuc%%|*}"
    local kalan="${sonuc#*|}"
    local sure="${kalan%%|*}"
    local args="${kalan#*|}"

    if [ "$tip" = "alarm" ]; then
        eval "alarm \"$sure\" $args"
    else
        eval "gerisayim \"$sure\" $args"
    fi
}

# ============================================================
# 4. AKTIF ZAMANLAYICILARI GOSTER / DURDUR
# ============================================================

aktif_listele() {
    echo "Aktif zamanlayicilar:"
    local var=0
    for pid_dosya in "$ZAMANLAYICI_DIZIN"/aktif_*.pid; do
        if [ -f "$pid_dosya" ]; then
            local pid
            pid=$(cat "$pid_dosya")
            if kill -0 "$pid" 2>/dev/null; then
                echo "  PID: $pid"
                var=1
            else
                rm -f "$pid_dosya"
            fi
        fi
    done
    if [ $var -eq 0 ]; then
        echo "  (Aktif zamanlayici yok)"
    fi
}

zamanlayici_durdur() {
    if [ $# -lt 1 ]; then
        echo "Kullanim: zamanlayici_durdur PID"
        echo "         zamanlayici_durdur hepsi"
        echo ""
        echo "Aktif zamanlayicilari gormek icin: aktif_listele"
        return 1
    fi

    if [ "$1" = "hepsi" ]; then
        for pid_dosya in "$ZAMANLAYICI_DIZIN"/aktif_*.pid; do
            if [ -f "$pid_dosya" ]; then
                local pid
                pid=$(cat "$pid_dosya")
                kill "$pid" 2>/dev/null
                rm -f "$pid_dosya"
            fi
        done
        echo "Tum zamanlayicilar durduruldu."
        return 0
    fi

    kill "$1" 2>/dev/null
    rm -f "$ZAMANLAYICI_DIZIN/aktif_$1.pid"
    echo "Zamanlayici durduruldu: PID $1"
}

# ============================================================
# 5. ANA MENU (GUI)
# ============================================================

zamanlayici() {
    # Parametre verildiyse GUI modunda geri sayim baslat
    if [ $# -ge 1 ]; then
        _gui_gerisayim "$@"
        return $?
    fi

    echo "============================================"
    echo "  Zamanlayici - Komut Rehberi"
    echo "============================================"
    echo ""
    echo "  GUI MODDA (zenity penceresiyle):"
    echo "    zamanlayici 40             40 dakika"
    echo "    zamanlayici 1:30:00        1 saat 30 dk"
    echo "    zamanlayici 40 -i KPSS     Isimli zamanlayici"
    echo ""
    echo "  TERMINAL MODDA:"
    echo "    gerisayim 40             40 dakika"
    echo "    gerisayim 1:30:00        1 saat 30 dk"
    echo "    gerisayim 0:0:30         30 saniye"
    echo "    gerisayim 5 -d           5 dk, dongulu ses"
    echo "    gerisayim 5 -s           5 dk, sessiz"
    echo "    gerisayim 5 -k 'komut'   5 dk, sonra komut calistir"
    echo "    gerisayim 5 -t 3 -a 5    5 dk, ses 3 kez 5sn arayla"
    echo "    gerisayim 40 -b          40 dk, ARKA PLANDA (terminal kapansa bile)"
    echo ""
    echo "  SAAT ALARMI (otomatik arka planda calisir):"
    echo "    alarm 14:30              14:30'da alarm"
    echo "    alarm 08:00 -d           08:00, dongulu ses"
    echo "    alarm 14:30 -k 'komut'   14:30, komut calistir"
    echo ""
    echo "  ALARM YONETIMI:"
    echo "    alarm_kaydet ISIM SURE    Alarm kaydet"
    echo "    alarm_listele             Kayitli alarmlari goster"
    echo "    alarm_calistir 1          1. alarmi calistir"
    echo "    alarm_calistir ISIM       Isimle calistir"
    echo "    alarm_sil 1               1. alarmi sil"
    echo "    alarm_sil hepsi           Tum alarmlari sil"
    echo ""
    echo "  KONTROL:"
    echo "    aktif_listele             Calisan zamanlayicilari goster"
    echo "    zamanlayici_durdur PID    Zamanlayiciyi durdur"
    echo "    zamanlayici_durdur hepsi  Hepsini durdur"
    echo ""
    echo "============================================"
}

# ============================================================
# 6. GUI MODU (ZENITY PENCERESI)
# ============================================================

_gui_gerisayim() {
    local sure_girdi="$1"
    shift
    local toplam_saniye=0

    if [[ "$sure_girdi" == *:*:* ]]; then
        IFS=':' read -r sa dk sn <<< "$sure_girdi"
        toplam_saniye=$(( sa * 3600 + dk * 60 + sn ))
    elif [[ "$sure_girdi" == *:* ]]; then
        IFS=':' read -r dk sn <<< "$sure_girdi"
        toplam_saniye=$(( dk * 60 + sn ))
    else
        toplam_saniye=$(( sure_girdi * 60 ))
    fi

    if [ $toplam_saniye -le 0 ]; then
        echo "HATA: Gecersiz sure."
        return 1
    fi

    # Secenekleri isle
    local isim="Zamanlayici"
    local sessiz=0
    local dongulu=0
    local komut=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -i) shift; isim="$1" ;;
            -s) sessiz=1 ;;
            -d) dongulu=1 ;;
            -k) shift; komut="$1" ;;
        esac
        shift
    done

    echo "[$isim] GUI zamanlayici basladi: $(_zaman_goster $toplam_saniye)"
    echo "  [Bilgi] Terminal kapatsaniz bile pencere calisacak."

    # Bagimsiz script olustur - terminal kapansa bile calisir
    local script="$ZAMANLAYICI_DIZIN/gui_$$.sh"
    cat > "$script" << GUISCRIPT
#!/bin/bash
# GUI Zamanlayici - terminal bagimsiz
_toplam=$toplam_saniye
_isim="$isim"
_sessiz=$sessiz
_dongulu=$dongulu
_komut="$komut"
_ses="$ALARM_SES"
_dizin="$ZAMANLAYICI_DIZIN"

export DISPLAY=:0

# PID kaydet
echo \$\$ > "\$_dizin/aktif_\$\$.pid"

_zaman() {
    local s=\$1
    local sa=\$((s / 3600)) dk=\$(( (s % 3600) / 60 )) sn=\$((s % 60))
    if [ \$sa -gt 0 ]; then printf '%02d:%02d:%02d' \$sa \$dk \$sn
    else printf '%02d:%02d' \$dk \$sn; fi
}

_sure_metin=\$(_zaman \$_toplam)

# Onceki pencerelerini kapat
pkill -f "zenity.*--title=Zamanlayici\|zenity.*--title=ZMN_" 2>/dev/null
sleep 0.2

_baslik="\$_isim - \$_sure_metin"

# Zenity progress
{
    _kalan=\$_toplam
    while [ \$_kalan -gt 0 ]; do
        _dk=\$((_kalan / 60))
        _sn=\$((_kalan % 60))
        _yuzde=\$(( (_toplam - _kalan) * 100 / _toplam ))
        echo "\$_yuzde"
        echo "# Kalan: \$(printf '%02d:%02d' \$_dk \$_sn)"
        sleep 1
        _kalan=\$((_kalan - 1))
    done
    echo "100"
    echo "# SURE DOLDU!"
} | zenity --progress \\
    --title="\$_baslik" \\
    --text="Basliyor..." \\
    --percentage=0 \\
    --auto-close \\
    --no-cancel \\
    --width=280 \\
    --height=90 2>/dev/null &

_zpid=\$!

# Pencereyi yakala ve konumlandir
sleep 0.3
_wid=\$(xdotool search --pid \$_zpid 2>/dev/null | tail -1)
if [ -z "\$_wid" ]; then
    sleep 0.5
    _wid=\$(xdotool search --pid \$_zpid 2>/dev/null | tail -1)
fi
if [ -n "\$_wid" ]; then
    xdotool windowmove "\$_wid" 5000 5000 2>/dev/null
    xprop -id "\$_wid" -f _MOTIF_WM_HINTS 32c -set _MOTIF_WM_HINTS "0x2, 0x0, 0x0, 0x0, 0x0" 2>/dev/null
    sleep 0.3
    _gw=\$(xdotool getwindowgeometry "\$_wid" 2>/dev/null | grep -oP 'Geometry: \K[0-9]+')
    _gw=\${_gw:-350}
    _ew=\$(xdotool getdisplaygeometry 2>/dev/null | awk '{print \$1}')
    _ew=\${_ew:-1920}
    _px=\$((_ew - _gw - 20))
    xdotool windowmove "\$_wid" \$_px 35 2>/dev/null
    xdotool set_window --overrideredirect 1 "\$_wid" 2>/dev/null
fi

# Bekle
wait \$_zpid 2>/dev/null

# Temizlik
rm -f "\$_dizin/aktif_\$\$.pid"

# Bildirim
notify-send "\$_isim" "Sure doldu! (\$_sure_metin)" 2>/dev/null

# Komut calistir
if [ -n "\$_komut" ]; then
    eval "\$_komut"
fi

# Ses cal
if [ "\$_sessiz" != "1" ]; then
    # Dongulu ses cal + durdurma penceresi
    while true; do
        paplay "\$_ses" 2>/dev/null
        sleep 1
    done &
    _ses_pid=\$!

    zenity --warning \\
        --title="Sure Doldu!" \\
        --text="\$_isim - \$_sure_metin doldu!" \\
        --ok-label="Sesi Durdur" \\
        --width=250 2>/dev/null

    kill \$_ses_pid 2>/dev/null
    wait \$_ses_pid 2>/dev/null
fi

# Kendini temizle
rm -f "\$0"
GUISCRIPT

    chmod +x "$script"

    # setsid ile terminal bagimsiz calistir
    setsid bash "$script" </dev/null &>/dev/null &
    disown $! 2>/dev/null
}
