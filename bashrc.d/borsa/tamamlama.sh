# shellcheck shell=bash

# Borsa CLI - Bash Tab Tamamlama (Completion)
# borsa <kurum> <komut> [argumanlar] icin TAB destegi saglar.
#
# Tamamlama yapisi:
#   borsa <TAB>                        -> kurum listesi + kurallar + gecmis + mutabakat + robot + veri
#   borsa kurallar <TAB>               -> seans fiyat pazar takas adim tavan taban
#   borsa gecmis <TAB>                 -> emirler bakiye sembol kar fiyat robot oturum rapor
#   borsa mutabakat <TAB>              -> kurum listesi (sonra hesap_no)
#   borsa robot <TAB>                  -> baslat durdur listele
#   borsa veri <TAB>                   -> baslat durdur goster ayarla fiyat
#   borsa <kurum> <TAB>                -> komut listesi
#   borsa <kurum> emir <SEMBOL> <TAB>  -> alis satis
#   borsa <kurum> emir <S> <T> <L> <F> <TAB> -> mobil eposta hepsi yok

_borsa_tamamla() {
    local su_anki
    su_anki="${COMP_WORDS[COMP_CWORD]}"

    # Kurum listesini bir kere olustur
    local _kurum_listesi=""
    local surucu
    if [[ -d "${BORSA_KLASORU}/adaptorler" ]]; then
        for surucu in "${BORSA_KLASORU}/adaptorler"/*.sh; do
            [[ ! -f "$surucu" ]] && continue
            local ad
            ad=$(basename "$surucu" .sh)
            [[ "$ad" == *.ayarlar ]] && continue
            _kurum_listesi="$_kurum_listesi $ad"
        done
    fi

    # Pozisyon bazli tamamlama
    case "$COMP_CWORD" in
        1)
            # borsa <TAB> -> kurum listesi + ozel komutlar
            local secenekler="kurallar gecmis mutabakat robot veri${_kurum_listesi}"
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$secenekler" -- "$su_anki"))
            ;;
        2)
            # borsa <X> <TAB>
            local ilk="${COMP_WORDS[1]}"
            case "$ilk" in
                kurallar)
                    # shellcheck disable=SC2207
                    COMPREPLY=($(compgen -W "seans fiyat pazar takas adim tavan taban" -- "$su_anki"))
                    ;;
                gecmis)
                    # shellcheck disable=SC2207
                    COMPREPLY=($(compgen -W "emirler bakiye sembol kar fiyat robot oturum rapor" -- "$su_anki"))
                    ;;
                mutabakat)
                    # Kurum listesi
                    # shellcheck disable=SC2207
                    COMPREPLY=($(compgen -W "$_kurum_listesi" -- "$su_anki"))
                    ;;
                robot)
                    # shellcheck disable=SC2207
                    COMPREPLY=($(compgen -W "baslat durdur listele" -- "$su_anki"))
                    ;;
                veri)
                    # shellcheck disable=SC2207
                    COMPREPLY=($(compgen -W "baslat durdur goster ayarla fiyat" -- "$su_anki"))
                    ;;
                *)
                    # Normal kurum -> komut listesi
                    # shellcheck disable=SC2207
                    COMPREPLY=($(compgen -W "giris bakiye portfoy emir emirler iptal hesap hesaplar arz fiyat cikis oturum-durdur" -- "$su_anki"))
                    ;;
            esac
            ;;
        3)
            # borsa <X> <Y> <TAB>
            local ilk="${COMP_WORDS[1]}"
            local ikinci="${COMP_WORDS[2]}"

            case "$ilk" in
                robot)
                    case "$ikinci" in
                        baslat)
                            # --kuru veya kurum listesi
                            # shellcheck disable=SC2207
                            COMPREPLY=($(compgen -W "--kuru${_kurum_listesi}" -- "$su_anki"))
                            ;;
                        durdur)
                            # Kurum listesi
                            # shellcheck disable=SC2207
                            COMPREPLY=($(compgen -W "$_kurum_listesi" -- "$su_anki"))
                            ;;
                    esac
                    ;;
                veri)
                    case "$ikinci" in
                        ayarla)
                            # Kurum listesi
                            # shellcheck disable=SC2207
                            COMPREPLY=($(compgen -W "$_kurum_listesi" -- "$su_anki"))
                            ;;
                    esac
                    ;;
                gecmis)
                    # Bazi alt komutlar icin sayi veya sembol beklenir — tamamlama yok
                    ;;
                mutabakat)
                    # 3. pozisyon: hesap_no — kullanici yazar
                    ;;
                *)
                    # Normal kurum komutlari
                    case "$ikinci" in
                        emir)
                            # 3. pozisyon: sembol — tamamlama yok
                            ;;
                        giris)
                            # 3. pozisyon: -o veya musteri_no
                            # shellcheck disable=SC2207
                            COMPREPLY=($(compgen -W "-o" -- "$su_anki"))
                            ;;
                        arz)
                            # 3. pozisyon: alt komut
                            # shellcheck disable=SC2207
                            COMPREPLY=($(compgen -W "liste talepler talep iptal guncelle" -- "$su_anki"))
                            ;;
                    esac
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
