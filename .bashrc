# ~/.bashrc: executed by bash(1) for non-login shells.

# Interaktif degilse hicbir sey yapma
case $- in
    *i*) ;;
      *) return;;
esac

# ============================================================
# MODULER BASHRC YAPISI
# ============================================================
# Tum ozel komutlar ~/dotfiles/bashrc.d/ klasorundeki
# .sh dosyalarinda tutulur.
#
# Yapi:
#   bashrc.d/
#   ├── 01-genel.sh        -> Prompt, renkler, alias, tamamlama
#   ├── 02-yazdir.sh       -> PDF/Markdown yazdirma araci
#   ├── 03-zamanlayici.sh  -> Alarm ve geri sayim araci
#   ├── 04-borsa.sh        -> Borsa ana modulu
#   └── borsa/             -> Borsa alt modulleri
#       ├── analiz.sh
#       └── veri.sh
#
# Yukleme sirasi:
#   1. Oncelikle ana moduller (01-*.sh, 02-*.sh, ...) yuklenir
#   2. Sonra alt klasorlerdeki moduller yuklenir
#
# Yeni modul eklemek icin:
#   ~/dotfiles/bashrc.d/ klasorune XX-isim.sh dosyasi olustur
#   Alt moduller icin: ~/dotfiles/bashrc.d/isim/ klasoru olustur
#
# Bir modulu devre disi birakmak icin:
#   Dosya uzantisini .sh.off olarak degistir
# ============================================================

# Dotfiles dizini
DOTFILES_DIZIN="$HOME/dotfiles"

# Tum modulleri yukle
if [ -d "$DOTFILES_DIZIN/bashrc.d" ]; then
    # 1. Ana modulleri sirayla yukle (01-xxx.sh, 02-xxx.sh, ...)
    for modul in "$DOTFILES_DIZIN/bashrc.d"/*.sh; do
        [ -f "$modul" ] && source "$modul"
    done
    
    # 2. Alt klasorlerdeki modulleri yukle (orn: borsa/*.sh)
    for alt_klasor in "$DOTFILES_DIZIN/bashrc.d"/*/; do
        [ -d "$alt_klasor" ] || continue
        for alt_modul in "$alt_klasor"*.sh; do
            [ -f "$alt_modul" ] && source "$alt_modul"
        done
    done
    
    unset modul alt_klasor alt_modul
fi
