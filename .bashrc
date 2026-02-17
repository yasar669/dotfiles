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
# Moduller:
#   01-genel.sh        -> Prompt, renkler, alias, tamamlama
#   02-yazdir.sh       -> PDF/Markdown yazdirma araci
#   03-zamanlayici.sh  -> Alarm ve geri sayim araci
#
# Yeni modul eklemek icin:
#   ~/dotfiles/bashrc.d/ klasorune XX-isim.sh dosyasi olustur
#   Otomatik olarak yuklenecektir.
#
# Bir modulu devre disi birakmak icin:
#   Dosya uzantisini .sh.off olarak degistir
# ============================================================

# Dotfiles dizini
DOTFILES_DIZIN="$HOME/dotfiles"

# Tum modulleri sirayla yukle
if [ -d "$DOTFILES_DIZIN/bashrc.d" ]; then
    for modul in "$DOTFILES_DIZIN/bashrc.d"/*.sh; do
        [ -f "$modul" ] && source "$modul"
    done
    unset modul
fi
