# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
#[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        # We have color support; assume it's compliant with Ecma-48
        # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
        # a case would tend to support setf rather than setaf.)
        color_prompt=yes
    else
        color_prompt=
    fi
fi

# The following block is surrounded by two delimiters.
# These delimiters must not be modified. Thanks.
# START KALI CONFIG VARIABLES
PROMPT_ALTERNATIVE=twoline
NEWLINE_BEFORE_PROMPT=yes
# STOP KALI CONFIG VARIABLES

if [ "$color_prompt" = yes ]; then
    # override default virtualenv indicator in prompt
    VIRTUAL_ENV_DISABLE_PROMPT=1

    prompt_color='\[\033[;32m\]'
    info_color='\[\033[1;34m\]'
    prompt_symbol=㉿
    if [ "$EUID" -eq 0 ]; then # Change prompt colors for root user
        prompt_color='\[\033[;94m\]'
        info_color='\[\033[1;31m\]'
        # Skull emoji for root terminal
        #prompt_symbol=💀
    fi
    case "$PROMPT_ALTERNATIVE" in
        twoline)
            PS1=$prompt_color'┌──${debian_chroot:+($debian_chroot)──}${VIRTUAL_ENV:+(\[\033[0;1m\]$(basename $VIRTUAL_ENV)'$prompt_color')}('$info_color'\u'$prompt_symbol'\h'$prompt_color')-[\[\033[0;1m\]\w'$prompt_color']\n'$prompt_color'└─'$info_color'\$\[\033[0m\] ';;
        oneline)
            PS1='${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV)) }${debian_chroot:+($debian_chroot)}'$info_color'\u@\h\[\033[00m\]:'$prompt_color'\[\033[01m\]\w\[\033[00m\]\$ ';;
        backtrack)
            PS1='${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV)) }${debian_chroot:+($debian_chroot)}\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ ';;
    esac
    unset prompt_color
    unset info_color
    unset prompt_symbol
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*|Eterm|aterm|kterm|gnome*|alacritty)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

[ "$NEWLINE_BEFORE_PROMPT" = yes ] && PROMPT_COMMAND="PROMPT_COMMAND=echo"

# enable color support of ls, less and man, and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    export LS_COLORS="$LS_COLORS:ow=30;44:" # fix ls color for folders with 777 permissions

    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
    alias diff='diff --color=auto'
    alias ip='ip --color=auto'

    export LESS_TERMCAP_mb=$'\E[1;31m'     # begin blink
    export LESS_TERMCAP_md=$'\E[1;36m'     # begin bold
    export LESS_TERMCAP_me=$'\E[0m'        # reset bold/blink
    export LESS_TERMCAP_so=$'\E[01;33m'    # begin reverse video
    export LESS_TERMCAP_se=$'\E[0m'        # reset reverse video
    export LESS_TERMCAP_us=$'\E[1;32m'     # begin underline
    export LESS_TERMCAP_ue=$'\E[0m'        # reset underline
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -l'
alias la='ls -A'
alias l='ls -CF'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# KPSS PDF Yazdirma Fonksiyonu (arkalionlu baski)
yazdir() {
    # ========================================
    # YAZDIR - Profesyonel PDF Yazdirma Araci
    # HP DeskJet 2540 icin optimize edilmis
    # ========================================
    
    local renk_modu="KGray"  # Varsayilan: siyah-beyaz (ekonomik)
    local renk_adi="Siyah-Beyaz"
    local dosya=""
    local aralik=""
    local gecici="/tmp/yazdir-cikti.pdf"
    
    # Yardim mesaji
    _yazdir_yardim() {
        echo ""
        echo "YAZDIR - PDF ve Markdown Yazdirma Araci"
        echo "========================================="
        echo ""
        echo "KULLANIM:"
        echo "  yazdir [SECENEK] \"dosya.pdf\" sayfa-araligi"
        echo "  yazdir [SECENEK] \"dosya.md\" tumu"
        echo ""
        echo "DESTEKLENEN DOSYA TURLERI:"
        echo "  .pdf              PDF dosyasi (dogrudan yazdirilir)"
        echo "  .md / .markdown   Markdown dosyasi (HTML formatinda PDF'e cevrilir)"
        echo ""
        echo "SECENEKLER:"
        echo "  -r, --renkli      Renkli baski (RGB)"
        echo "  -s, --siyahbeyaz  Siyah-beyaz baski (varsayilan)"
        echo "  -h, --yardim      Bu yardim mesajini goster"
        echo ""
        echo "SAYFA ARALIGI ORNEKLERI:"
        echo "  5-10              Sayfa 5'ten 10'a kadar"
        echo "  157,159           Sadece sayfa 157 ve 159"
        echo "  3,7,12-15         Sayfa 3, 7 ve 12-15 arasi"
        echo ""
        echo "ORNEK KOMUTLAR:"
        echo "  yazdir \"kitap.pdf\" 1-20"
        echo "      20 sayfayi siyah-beyaz yazdir (varsayilan)"
        echo ""
        echo "  yazdir -r \"harita.pdf\" 5-8"
        echo "      4 sayfayi renkli yazdir"
        echo ""
        echo "  yazdir --renkli \"deneme.pdf\" 1-48"
        echo "      48 sayfayi renkli yazdir"
        echo ""
        echo "  yazdir \"konu.md\" tumu"
        echo "      Markdown dosyasini HTML formatinda PDF'e cevirip tamamen yazdir"
        echo ""
        echo "  yazdir -r \"notlar.md\" 1-3"
        echo "      Markdown'dan olusturulan PDF'in 1-3 sayfalarini renkli yazdir"
        echo ""
        echo "NOT: Siyah-beyaz baski murekkep tasarrufu saglar."
        echo "     Harita, grafik gibi icerikler icin -r kullanin."
        echo "     Markdown icin 'tumu' veya 'hepsi' sayfa araligi olarak verilebilir."
        echo ""
    }
    
    # Argumanlari isle
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--renkli)
                renk_modu="RGB"
                renk_adi="Renkli"
                shift
                ;;
            -s|--siyahbeyaz)
                renk_modu="KGray"
                renk_adi="Siyah-Beyaz"
                shift
                ;;
            -h|--yardim)
                _yazdir_yardim
                return 0
                ;;
            -*)
                echo "HATA: Bilinmeyen secenek: $1"
                echo "Yardim icin: yazdir --yardim"
                return 1
                ;;
            *)
                if [ -z "$dosya" ]; then
                    dosya="$1"
                elif [ -z "$aralik" ]; then
                    aralik="$1"
                else
                    echo "HATA: Fazla arguman: $1"
                    return 1
                fi
                shift
                ;;
        esac
    done
    
    # Zorunlu argumanlari kontrol et
    if [ -z "$dosya" ] || [ -z "$aralik" ]; then
        echo "HATA: Dosya ve sayfa araligi belirtilmeli."
        echo "Yardim icin: yazdir --yardim"
        return 1
    fi

    if [ ! -f "$dosya" ]; then
        echo "HATA: Dosya bulunamadi: $dosya"
        return 1
    fi

    # Markdown dosyasi ise HTML formatinda PDF'e cevir
    local uzanti="${dosya##*.}"
    if [[ "${uzanti,,}" == "md" || "${uzanti,,}" == "markdown" ]]; then
        echo "Markdown dosyasi tespit edildi, HTML formatinda PDF'e cevriliyor..."
        
        local html_gecici="/tmp/yazdir-md.html"
        local pdf_gecici="/tmp/yazdir-md.pdf"
        
        # Python markdown modulu ile HTML'e cevir (Turkce destekli, guzel formatli)
        python3 -c "
import markdown
import sys

with open('$dosya', 'r', encoding='utf-8') as f:
    md_icerik = f.read()

html_govde = markdown.markdown(md_icerik, extensions=['tables', 'fenced_code', 'codehilite', 'toc'])

html_tam = '''<!DOCTYPE html>
<html lang=\"tr\">
<head>
<meta charset=\"UTF-8\">
<style>
    body {
        font-family: \"DejaVu Sans\", \"Liberation Sans\", Arial, sans-serif;
        font-size: 13px;
        line-height: 1.5;
        margin: 20px 30px;
        color: #222;
    }
    h1 { font-size: 22px; border-bottom: 2px solid #333; padding-bottom: 5px; margin-top: 20px; }
    h2 { font-size: 18px; border-bottom: 1px solid #999; padding-bottom: 3px; margin-top: 16px; }
    h3 { font-size: 15px; margin-top: 12px; }
    table { border-collapse: collapse; width: 100%%; margin: 10px 0; }
    th, td { border: 1px solid #666; padding: 6px 10px; text-align: left; }
    th { background-color: #e8e8e8; font-weight: bold; }
    code { background-color: #f0f0f0; padding: 1px 4px; font-size: 12px; }
    pre { background-color: #f5f5f5; padding: 10px; border: 1px solid #ddd; overflow-x: auto; }
    pre code { background: none; padding: 0; }
    ul, ol { margin: 5px 0; padding-left: 25px; }
    li { margin: 2px 0; }
    blockquote { border-left: 3px solid #999; margin: 10px 0; padding: 5px 15px; color: #555; }
    input[type=\"checkbox\"] { margin-right: 5px; }
    strong { font-weight: bold; }
    em { font-style: italic; }
</style>
</head>
<body>
''' + html_govde + '''
</body>
</html>'''

with open('$html_gecici', 'w', encoding='utf-8') as f:
    f.write(html_tam)
" 2>/dev/null

        if [ $? -ne 0 ]; then
            echo "HATA: Markdown -> HTML donusumu basarisiz!"
            return 1
        fi

        # Google Chrome headless ile HTML'den PDF olustur
        google-chrome --headless --disable-gpu --no-sandbox --print-to-pdf="$pdf_gecici" "$html_gecici" 2>/dev/null

        if [ $? -ne 0 ] || [ ! -f "$pdf_gecici" ]; then
            echo "HATA: HTML -> PDF donusumu basarisiz!"
            return 1
        fi

        echo "Markdown basariyla PDF'e cevrildi."
        
        # Dosyayi PDF olarak degistir, aralik verilmediyse tum sayfalari bas
        dosya="$pdf_gecici"
        
        if [ "$aralik" == "tumu" ] || [ "$aralik" == "hepsi" ]; then
            local toplam_sayfa=$(python3 -c "
import subprocess
result = subprocess.run(['pdfinfo', '$pdf_gecici'], capture_output=True, text=True)
for line in result.stdout.split('\n'):
    if 'Pages:' in line:
        print(line.split(':')[1].strip())
        break
" 2>/dev/null)
            if [ -z "$toplam_sayfa" ]; then
                toplam_sayfa=$(pdfinfo "$pdf_gecici" 2>/dev/null | grep "Pages:" | awk '{print $2}')
            fi
            if [ -n "$toplam_sayfa" ]; then
                aralik="1-$toplam_sayfa"
            else
                aralik="1-50"
            fi
        fi
        
        # Gecici HTML dosyasini temizle
        rm -f "$html_gecici"
    fi

    # Sayfa sayisini hesapla (virgul ve aralik karisik olabilir)
    local sayfa_sayisi=0
    IFS=',' read -ra parcalar <<< "$aralik"
    for parca in "${parcalar[@]}"; do
        if [[ "$parca" == *-* ]]; then
            local bas=$(echo "$parca" | cut -d'-' -f1)
            local bit=$(echo "$parca" | cut -d'-' -f2)
            sayfa_sayisi=$((sayfa_sayisi + bit - bas + 1))
        else
            sayfa_sayisi=$((sayfa_sayisi + 1))
        fi
    done
    local a4_sayisi=$(( (sayfa_sayisi + 1) / 2 ))

    echo ""
    echo "========================================="
    echo "         YAZDIRMA BILGISI"
    echo "========================================="
    echo "  Dosya       : $(basename "$dosya")"
    echo "  PDF Sayfa   : $aralik ($sayfa_sayisi sayfa)"
    echo "  A4 Kagit    : $a4_sayisi (arkalionlu)"
    echo "  Renk Modu   : $renk_adi"
    echo "========================================="
    echo ""

    echo "PDF hazirlaniyor (2 sayfa/A4, yatay)..."
    pdfjam --nup 2x1 --landscape --outfile "$gecici" "$dosya" "$aralik" 2>/dev/null

    if [ $? -ne 0 ]; then
        echo "HATA: pdfjam basarisiz oldu!"
        return 1
    fi

    # On yuzler (tek numarali A4 sayfalari) ve arka yuzler (cift numarali) hesapla
    local on_yuzler=""
    local arka_yuzler=""

    for ((i=1; i<=a4_sayisi; i++)); do
        if [ $((i % 2)) -eq 1 ]; then
            [ -n "$on_yuzler" ] && on_yuzler="$on_yuzler,"
            on_yuzler="${on_yuzler}${i}"
        else
            [ -n "$arka_yuzler" ] && arka_yuzler="$arka_yuzler,"
            arka_yuzler="${arka_yuzler}${i}"
        fi
    done

    echo ""
    echo "ADIM 1: On yuzler yazdiriliyor (A4 sayfa: $on_yuzler)..."
    lp -d HP-DeskJet-2540 -P "$on_yuzler" -o fit-to-page -o ColorModel="$renk_modu" "$gecici"

    if [ -z "$arka_yuzler" ]; then
        echo "Tek kagit, arkalionlu baski gerekmiyor."
        echo "Yazdirma tamamlandi!"
        return 0
    fi

    echo ""
    echo "ADIM 2: Kagitlari yazicidan al, ters cevir ve tepsiye geri koy."
    read -p "Hazir olunca ENTER'a bas..."

    echo ""
    echo "ADIM 3: Arka yuzler yazdiriliyor (A4 sayfa: $arka_yuzler)..."
    lp -d HP-DeskJet-2540 -P "$arka_yuzler" -o fit-to-page -o ColorModel="$renk_modu" "$gecici"

    echo ""
    echo "Yazdirma tamamlandi! [$renk_adi]"
}


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
    while [ $i -lt $tekrar ]; do
        paplay "$ALARM_SES" 2>/dev/null
        i=$((i + 1))
        if [ $i -lt $tekrar ]; then
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
        local cubuk=$(printf '%0.s#' $(seq 1 $cubuk_dolu 2>/dev/null))
        local bosluk=$(printf '%0.s-' $(seq 1 $cubuk_bos 2>/dev/null))

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

    if [ $hedef_sa -gt 23 ] || [ $hedef_dk -gt 59 ]; then
        echo "HATA: Gecersiz saat."
        return 1
    fi

    # Simdi ile hedef arasi farki hesapla
    local simdi=$(date +%s)
    local bugun=$(date +%Y-%m-%d)
    local hedef=$(date -d "$bugun $hedef_saat" +%s 2>/dev/null)

    if [ -z "$hedef" ]; then
        echo "HATA: Tarih hesaplanamadi."
        return 1
    fi

    # Eger hedef saat gecmisse, yarini al
    if [ $hedef -le $simdi ]; then
        local yarin=$(date -d "+1 day" +%Y-%m-%d)
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
            local pid=$(cat "$pid_dosya")
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
                local pid=$(cat "$pid_dosya")
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
