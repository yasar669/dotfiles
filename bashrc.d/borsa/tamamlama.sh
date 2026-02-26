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
            local secenekler="kurallar gecmis mutabakat robot veri backtest${_kurum_listesi}"
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
                backtest)
                    # Alt komutlar + strateji/ klasorundeki .sh dosyalari
                    local bt_secenekler="sonuclar detay karsilastir yukle sentetik"
                    if [[ -d "${BORSA_KLASORU}/strateji" ]]; then
                        local _str
                        for _str in "${BORSA_KLASORU}/strateji"/*.sh; do
                            [[ ! -f "$_str" ]] && continue
                            bt_secenekler="$bt_secenekler $(basename "$_str")"
                        done
                    fi
                    # shellcheck disable=SC2207
                    COMPREPLY=($(compgen -W "$bt_secenekler" -- "$su_anki"))
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
                            # --kuru, tarama secenekleri veya kurum listesi
                            # shellcheck disable=SC2207
                            COMPREPLY=($(compgen -W "--kuru --semboller --liste --dosya --portfoy${_kurum_listesi}" -- "$su_anki"))
                            ;;
                        durdur)
                            # Kurum listesi
                            # shellcheck disable=SC2207
                            COMPREPLY=($(compgen -W "$_kurum_listesi" -- "$su_anki"))
                            ;;
                    esac
                    ;;
                backtest)
                    # borsa backtest <strateji.sh|alt_komut> <TAB>
                    case "$ikinci" in
                        sonuclar)
                            # shellcheck disable=SC2207
                            COMPREPLY=($(compgen -W "--strateji --son" -- "$su_anki"))
                            ;;
                        yukle)
                            # CSV dosyalari
                            # shellcheck disable=SC2207
                            COMPREPLY=($(compgen -f -X '!*.csv' -- "$su_anki"))
                            ;;
                        sentetik|detay|karsilastir)
                            ;;
                        *)
                            # Strateji dosyasindan sonra sembol beklenir
                            # Bos birak, kullanici yazar
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
            local ilk="${COMP_WORDS[1]}"
            local onceki="${COMP_WORDS[COMP_CWORD-1]}"
            if [[ "$komut" == "emir" ]]; then
                # shellcheck disable=SC2207
                COMPREPLY=($(compgen -W "alis satis" -- "$su_anki"))
            elif [[ "$ilk" == "robot" ]] && [[ "${COMP_WORDS[2]}" == "baslat" ]]; then
                # borsa robot baslat <...> <TAB> — onceki kelimeye gore tamamla
                _borsa_robot_baslat_tamamla "$onceki" "$su_anki"
            elif [[ "$ilk" == "backtest" ]]; then
                # borsa backtest <strateji> <SEMBOL> <TAB> -> parametreler
                # shellcheck disable=SC2207
                COMPREPLY=($(compgen -W "--tarih --nakit --komisyon-alis --komisyon-satis --eslestirme --isitma --risksiz --sessiz --detay --kaynak --csv-dosya" -- "$su_anki"))
            fi
            ;;
        5|6|7|8|9|10)
            local ilk="${COMP_WORDS[1]}"
            local onceki="${COMP_WORDS[COMP_CWORD-1]}"

            if [[ "$ilk" == "robot" ]] && [[ "${COMP_WORDS[2]}" == "baslat" ]]; then
                # borsa robot baslat icin devam — pozisyondan bagimsiz
                _borsa_robot_baslat_tamamla "$onceki" "$su_anki"
            elif [[ "$COMP_CWORD" -eq 5 ]]; then
                # borsa <kurum> emir <SEMBOL> <alis|satis> <TAB> -> lot (kullanici yazar)
                :
            elif [[ "$COMP_CWORD" -eq 6 ]]; then
                # borsa <kurum> emir <SEMBOL> <alis|satis> <LOT> <TAB> -> fiyat veya piyasa
                local emir_komutu="${COMP_WORDS[2]}"
                if [[ "$emir_komutu" == "emir" ]]; then
                    # shellcheck disable=SC2207
                    COMPREPLY=($(compgen -W "piyasa" -- "$su_anki"))
                fi
            elif [[ "$COMP_CWORD" -eq 7 ]]; then
                # borsa <kurum> emir <SEMBOL> <alis|satis> <LOT> <FIYAT> <TAB> -> bildirim
                local emir_komutu="${COMP_WORDS[2]}"
                if [[ "$emir_komutu" == "emir" ]]; then
                    # shellcheck disable=SC2207
                    COMPREPLY=($(compgen -W "mobil eposta hepsi yok" -- "$su_anki"))
                fi
            fi
            ;;
    esac
}

# -------------------------------------------------------
# _borsa_robot_baslat_tamamla <onceki_kelime> <su_anki_kelime>
# robot baslat sonrasi tarama parametrelerini tamamlar.
# --liste sonrasi endeks dosya adlarini, --dosya sonrasi dosyalari tamamlar.
# -------------------------------------------------------
_borsa_robot_baslat_tamamla() {
    local onceki="$1"
    local su_anki="$2"

    case "$onceki" in
        --liste)
            # Endeksler dizinindeki dosya adlari (.txt uzantisi olmadan)
            local endeks_listesi=""
            local endeks_dosya
            if [[ -d "${BORSA_KLASORU}/tarama/endeksler" ]]; then
                for endeks_dosya in "${BORSA_KLASORU}/tarama/endeksler"/*.txt; do
                    [[ ! -f "$endeks_dosya" ]] && continue
                    endeks_listesi="$endeks_listesi $(basename "$endeks_dosya" .txt)"
                done
            fi
            # Kullanici dizini de ekle
            if [[ -d "${HOME}/.config/borsa" ]]; then
                for endeks_dosya in "${HOME}/.config/borsa"/*.txt; do
                    [[ ! -f "$endeks_dosya" ]] && continue
                    endeks_listesi="$endeks_listesi $(basename "$endeks_dosya" .txt)"
                done
            fi
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$endeks_listesi" -- "$su_anki"))
            ;;
        --dosya)
            # Dosya yolu tamamlama
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -f -- "$su_anki"))
            ;;
        --semboller)
            # Sembol kullanici yazar — tamamlama yok
            ;;
        *)
            # Kurum listesini olustur
            local _rt_kurum_listesi=""
            local surucu
            if [[ -d "${BORSA_KLASORU}/adaptorler" ]]; then
                for surucu in "${BORSA_KLASORU}/adaptorler"/*.sh; do
                    [[ ! -f "$surucu" ]] && continue
                    local ad
                    ad=$(basename "$surucu" .sh)
                    [[ "$ad" == *.ayarlar ]] && continue
                    _rt_kurum_listesi="$_rt_kurum_listesi $ad"
                done
            fi
            # Strateji dosyalari
            local _str_listesi=""
            if [[ -d "${BORSA_KLASORU}/strateji" ]]; then
                local _str
                for _str in "${BORSA_KLASORU}/strateji"/*.sh; do
                    [[ ! -f "$_str" ]] && continue
                    _str_listesi="$_str_listesi $(basename "$_str")"
                done
            fi
            # Tarama secenekleri + kurum + strateji
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "--kuru --semboller --liste --dosya --portfoy${_rt_kurum_listesi}${_str_listesi}" -- "$su_anki"))
            ;;
    esac
}

complete -F _borsa_tamamla borsa
