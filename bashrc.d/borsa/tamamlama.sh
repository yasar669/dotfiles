# shellcheck shell=bash

# Borsa CLI - Bash Tab Tamamlama (Completion)
# borsa <kurum> <komut> [argumanlar] icin TAB destegi saglar.
#
# Tamamlama yapisi:
#   borsa <TAB>                        -> kurum listesi + kurallar
#   borsa kurallar <TAB>               -> seans fiyat pazar takas adim tavan taban
#   borsa <kurum> <TAB>                -> komut listesi
#   borsa <kurum> emir <SEMBOL> <TAB>  -> alis satis
#   borsa <kurum> emir <S> <T> <L> <F> <TAB> -> mobil eposta hepsi yok

_borsa_tamamla() {
    local su_anki
    su_anki="${COMP_WORDS[COMP_CWORD]}"

    # Pozisyon bazli tamamlama
    case "$COMP_CWORD" in
        1)
            # borsa <TAB> -> kurum listesi + kurallar
            local kurumlar="kurallar"
            local surucu
            if [[ -d "${BORSA_KLASORU}/adaptorler" ]]; then
                for surucu in "${BORSA_KLASORU}/adaptorler"/*.sh; do
                    [[ ! -f "$surucu" ]] && continue
                    local ad
                    ad=$(basename "$surucu" .sh)
                    [[ "$ad" == *.ayarlar ]] && continue
                    kurumlar="$kurumlar $ad"
                done
            fi
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$kurumlar" -- "$su_anki"))
            ;;
        2)
            # borsa <kurum> <TAB> -> komut listesi
            local kurum="${COMP_WORDS[1]}"
            if [[ "$kurum" == "kurallar" ]]; then
                # shellcheck disable=SC2207
                COMPREPLY=($(compgen -W "seans fiyat pazar takas adim tavan taban" -- "$su_anki"))
            else
                # shellcheck disable=SC2207
                COMPREPLY=($(compgen -W "giris bakiye portfoy emir emirler iptal hesap hesaplar arz" -- "$su_anki"))
            fi
            ;;
        3)
            # borsa <kurum> <komut> <TAB>
            local komut="${COMP_WORDS[2]}"
            case "$komut" in
                emir)
                    # 3. pozisyon: sembol — tamamlama yok, kullanici yazar
                    ;;
                giris)
                    # 3. pozisyon: musteri_no — tamamlama yok
                    ;;
                arz)
                    # 3. pozisyon: alt komut
                    # shellcheck disable=SC2207
                    COMPREPLY=($(compgen -W "liste talepler talep iptal guncelle" -- "$su_anki"))
                    ;;
            esac
            ;;
        4)
            # borsa <kurum> emir <SEMBOL> <TAB> -> alis satis
            local komut="${COMP_WORDS[2]}"
            if [[ "$komut" == "emir" ]]; then
                # shellcheck disable=SC2207
                COMPREPLY=($(compgen -W "alis satis" -- "$su_anki"))
            fi
            ;;
        5)
            # borsa <kurum> emir <SEMBOL> <alis|satis> <TAB> -> lot (kullanici yazar)
            ;;
        6)
            # borsa <kurum> emir <SEMBOL> <alis|satis> <LOT> <TAB> -> fiyat veya piyasa
            local komut="${COMP_WORDS[2]}"
            if [[ "$komut" == "emir" ]]; then
                # shellcheck disable=SC2207
                COMPREPLY=($(compgen -W "piyasa" -- "$su_anki"))
            fi
            ;;
        7)
            # borsa <kurum> emir <SEMBOL> <alis|satis> <LOT> <FIYAT> <TAB> -> bildirim
            local komut="${COMP_WORDS[2]}"
            if [[ "$komut" == "emir" ]]; then
                # shellcheck disable=SC2207
                COMPREPLY=($(compgen -W "mobil eposta hepsi yok" -- "$su_anki"))
            fi
            ;;
    esac
}

complete -F _borsa_tamamla borsa
