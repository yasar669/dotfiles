# shellcheck shell=bash

# Backtest - Ana Motor
# Backtest ana dongusu, strateji yukleme, parametre parse, koordinasyon.
# Bu dosya backtest/ klasorundeki diger modulleri source eder.

_BACKTEST_DIZIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Alt modulleri yukle
# shellcheck source=/dev/null
source "$_BACKTEST_DIZIN/portfoy.sh"
# shellcheck source=/dev/null
source "$_BACKTEST_DIZIN/metrik.sh"
# shellcheck source=/dev/null
source "$_BACKTEST_DIZIN/rapor.sh"
# shellcheck source=/dev/null
source "$_BACKTEST_DIZIN/veri.sh"
# shellcheck source=/dev/null
source "$_BACKTEST_DIZIN/veri_dogrula.sh"

# Ayar degiskenleri (parametre parse sonucu doldurulur)
_BACKTEST_AYAR_TARIH_BAS=""
_BACKTEST_AYAR_TARIH_BIT=""
_BACKTEST_AYAR_NAKIT="100000"
_BACKTEST_AYAR_KOMISYON_ALIS="0.00188"
_BACKTEST_AYAR_KOMISYON_SATIS="0.00188"
_BACKTEST_AYAR_ESLESTIRME="KAPANIS"
_BACKTEST_AYAR_ISITMA="0"
_BACKTEST_AYAR_RISKSIZ="0.40"
_BACKTEST_AYAR_SESSIZ="0"
_BACKTEST_AYAR_DETAY="0"
_BACKTEST_AYAR_KAYNAK="supabase"
_BACKTEST_AYAR_CSV_DOSYA=""
_BACKTEST_AYAR_STRATEJI=""
_BACKTEST_AYAR_SEMBOLLER=""
_BACKTEST_AYAR_PERIYOT=""
_BACKTEST_AYAR_EVET="0"
_BACKTEST_AYAR_PERIYOT_VERILDI=0
_BACKTEST_AYAR_TARIH_VERILDI=0
_BACKTEST_AYAR_ISITMA_VERILDI=0

# Gecerli periyot listesi
_BACKTEST_GECERLI_PERIYOTLAR="1dk 3dk 5dk 15dk 30dk 45dk 1S 2S 3S 4S 1G 1H 1A"

# Strateji ortam degiskenleri
_BACKTEST_MOD=1
_BACKTEST_TARIH=""
_BACKTEST_GUN_NO=0

# Anki fiyat (eslestirme icin)
_BACKTEST_ANKI_FIYAT=""

# backtest_ana <komut> [argumanlar...]
# CLI giris noktasi. "borsa backtest" sonrasindaki tum argumanlari alir.
# Donus: 0 = basarili, 1 = hata
backtest_ana() {
    local komut="${1:-}"

    if [[ -z "$komut" ]]; then
        _backtest_yardim
        return 0
    fi

    case "$komut" in
        sonuclar)
            shift
            _backtest_sonuclari_listele "$@"
            ;;
        detay)
            shift
            _backtest_detay_goster "$@"
            ;;
        karsilastir)
            shift
            _backtest_karsilastir "$@"
            ;;
        yukle)
            shift
            backtest_veri_yukle_csv "$@"
            ;;
        sentetik)
            shift
            _backtest_sentetik_cli "$@"
            ;;
        -h|--help|yardim|--yardim)
            _backtest_yardim
            ;;
        *)
            # Strateji dosyasi + sembol olarak yorumla
            local strateji="$komut"
            local semboller="${2:-}"
            shift 2 2>/dev/null
            _backtest_calistir "$strateji" "$semboller" "$@"
            ;;
    esac
}

# _backtest_yardim
# Kullanim bilgisini gosterir.
_backtest_yardim() {
    echo "Kullanim: borsa backtest <strateji.sh> <SEMBOL> [secenekler]"
    echo ""
    echo "Alt komutlar:"
    echo "  <strateji.sh> <SEMBOL>   - Backtest calistir"
    echo "  sonuclar [--strateji X]  - Gecmis sonuclari listele"
    echo "  detay <ID>               - Backtest detayi goster"
    echo "  karsilastir <ID1> <ID2>  - Iki sonucu karsilastir"
    echo "  yukle <dosya.csv> <SEMBOL> - CSV verisini Supabase'e aktar"
    echo "  sentetik <SEMBOL> [fiyat] [gun] [vol] - Sentetik veri uret"
    echo ""
    echo "Secenekler:"
    echo "  --tarih, -t <BAS:BIT>    - Tarih araligi (YYYY-AA-GG:YYYY-AA-GG)"
    echo "  --nakit, -n <TL>         - Baslangic nakiti (varsayilan: 100000)"
    echo "  --komisyon-alis, -ka <X>  - Alis komisyon orani (varsayilan: 0.00188)"
    echo "  --komisyon-satis, -ks <X> - Satis komisyon orani (varsayilan: 0.00188)"
    echo "  --eslestirme, -e <MOD>   - KAPANIS veya LIMIT (varsayilan: KAPANIS)"
    echo "  --isitma, -i <GUN>       - Isitma donemi (varsayilan: 0)"
    echo "  --risksiz, -r <ORAN>     - Risksiz faiz orani (varsayilan: 0.40)"
    echo "  --sessiz, -s             - Sadece ozet tabloyu goster"
    echo "  --detay, -d              - Her islemi tek tek goster"
    echo "  --kaynak, -k <TIP>       - supabase, csv, sentetik"
    echo "  --csv-dosya, -cf <DOSYA> - CSV dosya yolu (--kaynak csv ile)"
    echo "  --periyot, -p <KOD>     - Zaman dilimi (1dk/5dk/15dk/30dk/1S/4S/1G/1H/1A)"
    echo "  --evet                   - Interaktif sorulari ve onayi atla"
}

# _backtest_sentetik_cli <sembol> [fiyat] [gun] [vol]
# Sentetik veri olusturup backtest calistirmadan sadece veri uretir.
_backtest_sentetik_cli() {
    local sembol="${1:-TEST01}"
    local fiyat="${2:-100}"
    local gun="${3:-250}"
    local vol="${4:-0.02}"

    _BACKTEST_VERI_TARIH=()
    _BACKTEST_VERI_FIYAT=()
    _BACKTEST_VERI_TAVAN=()
    _BACKTEST_VERI_TABAN=()
    _BACKTEST_VERI_DEGISIM=()
    _BACKTEST_VERI_HACIM=()
    _BACKTEST_VERI_SEANS=()

    _backtest_sentetik_uret "$sembol" "$fiyat" "$gun" "$vol"
    echo "Sentetik veri olusturuldu: $sembol, $gun gun, baslangic $fiyat TL, volatilite $vol"
    echo "Ilk 5 satir:"
    local i
    for (( i=0; i<5 && i<${#_BACKTEST_VERI_TARIH[@]}; i++ )); do
        echo "  ${_BACKTEST_VERI_TARIH[$i]} | ${_BACKTEST_VERI_FIYAT[$i]} TL | T:${_BACKTEST_VERI_TAVAN[$i]} | Tb:${_BACKTEST_VERI_TABAN[$i]}"
    done
}

# _backtest_calistir <strateji_dosyasi> <semboller> [secenekler...]
# Asil backtest dongusunu calistiran ic fonksiyon.
# Donus: 0 = basarili, 1 = hata
_backtest_calistir() {
    local strateji_dosyasi="$1"
    local semboller="$2"
    shift 2 2>/dev/null

    # Strateji dosyasini bul
    local strateji_yolu=""
    if [[ -f "$strateji_dosyasi" ]]; then
        strateji_yolu="$strateji_dosyasi"
    elif [[ -f "${BORSA_KLASORU}/strateji/${strateji_dosyasi}" ]]; then
        strateji_yolu="${BORSA_KLASORU}/strateji/${strateji_dosyasi}"
    else
        echo "HATA: Strateji dosyasi bulunamadi: $strateji_dosyasi" >&2
        echo "Aranan yollar:" >&2
        echo "  - $strateji_dosyasi" >&2
        echo "  - ${BORSA_KLASORU}/strateji/${strateji_dosyasi}" >&2
        return 1
    fi

    if [[ -z "$semboller" ]]; then
        echo "HATA: Sembol belirtilmedi." >&2
        echo "Kullanim: borsa backtest $strateji_dosyasi <SEMBOL> [secenekler]" >&2
        return 1
    fi

    # Parametreleri coz
    _backtest_parametreleri_coz "$@" || return 1

    _BACKTEST_AYAR_STRATEJI=$(basename "$strateji_yolu")
    _BACKTEST_AYAR_SEMBOLLER="$semboller"

    # Onceki stratejiden kalan fonksiyonlari temizle
    unset -f strateji_min_mum strateji_baslat strateji_degerlendir strateji_temizle 2>/dev/null

    # Strateji dosyasini source et (isitma onerisi icin erken yuklenir)
    # shellcheck source=/dev/null
    source "$strateji_yolu"

    # Strateji min mum onerisi: CLI verilmemisse ve strateji_min_mum tanimliysa kullan
    if [[ "$_BACKTEST_AYAR_ISITMA_VERILDI" -eq 0 ]]; then
        if declare -f strateji_min_mum > /dev/null 2>&1; then
            _BACKTEST_AYAR_ISITMA=$(strateji_min_mum)
        fi
    fi

    # Interaktif soru (TTY acik ve eksik parametre varsa)
    _backtest_interaktif_sor || return 1

    # Parametre dogrulama
    _backtest_parametre_dogrula || return 1

    # Onay goster
    _backtest_onay_goster || return 1

    echo ""
    echo "Backtest basliyor..."

    # strateji_baslat varsa cagir
    if declare -f strateji_baslat > /dev/null 2>&1; then
        strateji_baslat
    fi

    # Sanal portfoyu olustur
    _backtest_portfoy_olustur "${_BACKTEST_AYAR_NAKIT}"

    # Metrikleri sifirla
    _backtest_metrikleri_sifirla

    # Backtest ortam degiskenlerini ayarla
    _BACKTEST_MOD=1

    # Coklu sembol destegi — virgul ile ayrilmis semboller
    IFS=',' read -ra _sembol_listesi <<< "$semboller"

    local sem
    for sem in "${_sembol_listesi[@]}"; do
        # Her sembol icin veri yukle
        _backtest_veri_yukle "$sem" "$_BACKTEST_AYAR_TARIH_BAS" "$_BACKTEST_AYAR_TARIH_BIT" "$_BACKTEST_AYAR_KAYNAK" "${_BACKTEST_AYAR_PERIYOT:-1G}"
        local yukle_sonuc=$?

        if [[ "$yukle_sonuc" -ne 0 ]]; then
            echo "HATA: $sem icin veri yuklenemedi." >&2
            continue
        fi

        # Veri dogrulama
        if ! _backtest_veriyi_dogrula; then
            echo "HATA: $sem veri dogrulama basarisiz." >&2
            continue
        fi

        echo "$sem: ${#_BACKTEST_VERI_TARIH[@]} islem gunu verisi yuklendi."

        # Tek sembol icin ana donguyu calistir
        _backtest_ana_dongu "$sem"
    done

    # strateji_temizle varsa cagir
    if declare -f strateji_temizle > /dev/null 2>&1; then
        strateji_temizle
    fi

    # Metrikleri hesapla
    _backtest_metrikleri_hesapla

    # Raporu goster
    _backtest_rapor_goster

    # Sonuclari kaydet (Supabase varsa)
    _backtest_sonuc_kaydet

    return 0
}

# _backtest_ana_dongu <sembol>
# Yuklenen veriler uzerinde satirlari itere eder.
# Her satirda strateji_degerlendir() cagrilir, sinyal islenir.
# Donus: 0
_backtest_ana_dongu() {
    local sembol="$1"
    local toplam=${#_BACKTEST_VERI_TARIH[@]}
    local i

    for (( i=0; i<toplam; i++ )); do
        local tarih="${_BACKTEST_VERI_TARIH[$i]}"
        local fiyat="${_BACKTEST_VERI_FIYAT[$i]}"
        local tavan="${_BACKTEST_VERI_TAVAN[$i]}"
        local taban="${_BACKTEST_VERI_TABAN[$i]}"
        local degisim="${_BACKTEST_VERI_DEGISIM[$i]}"
        local hacim="${_BACKTEST_VERI_HACIM[$i]}"
        local seans="${_BACKTEST_VERI_SEANS[$i]:-Surekli Islem}"

        # Gun numarasi (1'den baslar)
        local gun_no=$((i + 1))

        # Backtest ortam degiskenleri
        _BACKTEST_TARIH="$tarih"
        _BACKTEST_GUN_NO=$gun_no
        _BACKTEST_ANKI_FIYAT="$fiyat"

        # Piyasa fiyatini guncelle
        # shellcheck disable=SC2004
        _BACKTEST_PIYASA[$sembol]="$fiyat"

        # Portfoy degerini guncelle
        _backtest_portfoy_deger_guncelle

        # Strateji degerlendir
        # NOT: $() alt kabuk olusturdugu icin strateji durum degiskenleri
        # kaybolur. Gecici dosya uzerinden sinyal yakalanir.
        local sinyal=""
        local _sinyal_dosya="/tmp/_bt_sinyal_$$"
        if declare -f strateji_degerlendir > /dev/null 2>&1; then
            strateji_degerlendir "$sembol" "$fiyat" "$tavan" "$taban" "$degisim" "$hacim" "$seans" > "$_sinyal_dosya"
            sinyal=$(<"$_sinyal_dosya")
        fi

        # Isitma donemi: sinyalleri yoksay
        local isitma="${_BACKTEST_AYAR_ISITMA:-0}"
        if [[ "$gun_no" -le "$isitma" ]]; then
            sinyal="BEKLE"
        fi

        # Sinyal degerlendirmesi
        if [[ -n "$sinyal" ]] && [[ "$sinyal" != "BEKLE" ]]; then
            local yon lot emir_fiyat
            yon=$(echo "$sinyal" | awk '{print $1}')
            lot=$(echo "$sinyal" | awk '{print $2}')
            emir_fiyat=$(echo "$sinyal" | awk '{print $3}')

            # Gecerli sinyal mi?
            if [[ "$yon" == "ALIS" || "$yon" == "SATIS" ]] && [[ -n "$lot" ]]; then
                [[ -z "$emir_fiyat" ]] && emir_fiyat="$fiyat"

                # NOT: $() alt kabuk olusturdugu icin portfoy degisiklikleri
                # kaybolur. Gecici dosya uzerinden sonuc yakalanir.
                _backtest_emir_isle "$yon" "$sembol" "$lot" "$emir_fiyat" "$tavan" "$taban" > "$_sinyal_dosya"
                local emir_durumu=$?
                local sonuc
                sonuc=$(<"$_sinyal_dosya")

                if [[ "$emir_durumu" -eq 0 ]]; then
                    # Islem basarili — kaydet
                    local komisyon
                    komisyon=$(_backtest_komisyon_hesapla "$lot" "$emir_fiyat" "$yon")
                    _backtest_islem_kaydet "$gun_no" "$tarih" "$sembol" "$yon" "$lot" "$emir_fiyat" "$komisyon" "$sinyal"

                    if [[ "${_BACKTEST_AYAR_DETAY:-0}" == "1" ]]; then
                        echo "  Gun $gun_no ($tarih): $sonuc"
                    fi
                else
                    if [[ "${_BACKTEST_AYAR_DETAY:-0}" == "1" ]]; then
                        echo "  Gun $gun_no ($tarih): $sonuc"
                    fi
                fi
            fi
        fi

        # Portfoy degerini guncelle (islem sonrasi)
        _backtest_portfoy_deger_guncelle

        # Gunluk metrikleri kaydet (isitma donemi dahil)
        if [[ "$gun_no" -gt "${_BACKTEST_AYAR_ISITMA:-0}" ]]; then
            _backtest_gunluk_kaydet "$gun_no" "$tarih"
        fi
    done

    # Gecici sinyal dosyasini temizle
    rm -f "/tmp/_bt_sinyal_$$"
}

# _backtest_parametreleri_coz <argumanlar...>
# CLI argumanlarini parse eder, varsayilanlari atar.
# Donus: 0 = basarili, 1 = gecersiz parametre
_backtest_parametreleri_coz() {
    # Varsayilan tarih araligi: son 1 yil
    local simdi_epoch
    simdi_epoch=$(date +%s)
    local bir_yil_once
    bir_yil_once=$(date -d "@$((simdi_epoch - 365*86400))" +%Y-%m-%d 2>/dev/null)
    local bugun
    bugun=$(date +%Y-%m-%d)

    _BACKTEST_AYAR_TARIH_BAS="${bir_yil_once:-2025-01-01}"
    _BACKTEST_AYAR_TARIH_BIT="${bugun:-2026-01-01}"
    _BACKTEST_AYAR_NAKIT="100000"
    _BACKTEST_AYAR_KOMISYON_ALIS="0.00188"
    _BACKTEST_AYAR_KOMISYON_SATIS="0.00188"
    _BACKTEST_AYAR_ESLESTIRME="KAPANIS"
    _BACKTEST_AYAR_ISITMA="0"
    _BACKTEST_AYAR_RISKSIZ="0.40"
    _BACKTEST_AYAR_SESSIZ="0"
    _BACKTEST_AYAR_DETAY="0"
    _BACKTEST_AYAR_KAYNAK="supabase"
    _BACKTEST_AYAR_CSV_DOSYA=""
    _BACKTEST_AYAR_PERIYOT=""
    _BACKTEST_AYAR_EVET="0"

    # Verildi bayraklarini sifirla
    _BACKTEST_AYAR_PERIYOT_VERILDI=0
    _BACKTEST_AYAR_TARIH_VERILDI=0
    _BACKTEST_AYAR_ISITMA_VERILDI=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tarih|-t)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    echo "HATA: --tarih parametresi deger bekliyor." >&2
                    return 1
                fi
                local tarih_aralik="$2"
                _BACKTEST_AYAR_TARIH_BAS="${tarih_aralik%%:*}"
                _BACKTEST_AYAR_TARIH_BIT="${tarih_aralik##*:}"
                _BACKTEST_AYAR_TARIH_VERILDI=1
                shift 2
                ;;
            --periyot|-p)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    echo "HATA: --periyot parametresi deger bekliyor." >&2
                    return 1
                fi
                _BACKTEST_AYAR_PERIYOT="$2"
                _BACKTEST_AYAR_PERIYOT_VERILDI=1
                shift 2
                ;;
            --nakit|-n)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    echo "HATA: --nakit parametresi deger bekliyor." >&2
                    return 1
                fi
                _BACKTEST_AYAR_NAKIT="$2"
                shift 2
                ;;
            --komisyon-alis|-ka)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    echo "HATA: --komisyon-alis parametresi deger bekliyor." >&2
                    return 1
                fi
                _BACKTEST_AYAR_KOMISYON_ALIS="$2"
                shift 2
                ;;
            --komisyon-satis|-ks)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    echo "HATA: --komisyon-satis parametresi deger bekliyor." >&2
                    return 1
                fi
                _BACKTEST_AYAR_KOMISYON_SATIS="$2"
                shift 2
                ;;
            --eslestirme|-e)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    echo "HATA: --eslestirme parametresi deger bekliyor." >&2
                    return 1
                fi
                local mod
                mod=$(echo "$2" | tr '[:lower:]' '[:upper:]')
                _BACKTEST_AYAR_ESLESTIRME="$mod"
                shift 2
                ;;
            --isitma|-i)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    echo "HATA: --isitma parametresi deger bekliyor." >&2
                    return 1
                fi
                _BACKTEST_AYAR_ISITMA="$2"
                _BACKTEST_AYAR_ISITMA_VERILDI=1
                shift 2
                ;;
            --risksiz|-r)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    echo "HATA: --risksiz parametresi deger bekliyor." >&2
                    return 1
                fi
                _BACKTEST_AYAR_RISKSIZ="$2"
                shift 2
                ;;
            --sessiz|-s)
                _BACKTEST_AYAR_SESSIZ="1"
                shift
                ;;
            --detay|-d)
                _BACKTEST_AYAR_DETAY="1"
                shift
                ;;
            --kaynak|-k)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    echo "HATA: --kaynak parametresi deger bekliyor." >&2
                    return 1
                fi
                _BACKTEST_AYAR_KAYNAK="$2"
                shift 2
                ;;
            --csv-dosya|-cf)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    echo "HATA: --csv-dosya parametresi deger bekliyor." >&2
                    return 1
                fi
                _BACKTEST_AYAR_CSV_DOSYA="$2"
                shift 2
                ;;
            --evet)
                _BACKTEST_AYAR_EVET="1"
                shift
                ;;
            *)
                echo "UYARI: Bilinmeyen parametre: $1" >&2
                shift
                ;;
        esac
    done

    # --kaynak csv ise --csv-dosya zorunlu
    if [[ "$_BACKTEST_AYAR_KAYNAK" == "csv" ]] && [[ -z "$_BACKTEST_AYAR_CSV_DOSYA" ]]; then
        echo "HATA: --kaynak csv secildiginde --csv-dosya parametresi zorunludur." >&2
        return 1
    fi

    return 0
}

# _backtest_periyot_gecerli_mi <periyot>
# Verilen periyot gecerli periyotlar listesinde mi kontrol eder.
# Donus: 0 = gecerli, 1 = gecersiz
_backtest_periyot_gecerli_mi() {
    local periyot="$1"
    local p
    for p in $_BACKTEST_GECERLI_PERIYOTLAR; do
        [[ "$p" == "$periyot" ]] && return 0
    done
    return 1
}

# _backtest_periyot_mumluk_yil <periyot>
# Periyot kodundan yillik mum sayisini dondurur.
# BIST surekli islem seansina gore (09:40-18:10, ~510 dk, 252 islem gunu/yil)
# stdout: yillik mum sayisi (tamsayi)
_backtest_periyot_mumluk_yil() {
    local periyot="${1:-1G}"
    case "$periyot" in
        1dk)  echo "128520" ;;
        3dk)  echo "42840"  ;;
        5dk)  echo "25704"  ;;
        15dk) echo "8568"   ;;
        30dk) echo "4284"   ;;
        45dk) echo "2772"   ;;
        1S)   echo "2142"   ;;
        2S)   echo "1008"   ;;
        3S)   echo "756"    ;;
        4S)   echo "504"    ;;
        1G)   echo "252"    ;;
        1H)   echo "52"     ;;
        1A)   echo "12"     ;;
        *)    echo "252"    ;;
    esac
}

# _backtest_interaktif_sor
# TTY acik ve eksik parametre varsa kullaniciya sorar.
# Pipe/betik modunda veya --evet verilmisse sormaz.
# Donus: 0 = basarili, 1 = iptal
_backtest_interaktif_sor() {
    # --evet verilmisse veya TTY yoksa atla
    if [[ "${_BACKTEST_AYAR_EVET:-0}" == "1" ]] || [[ ! -t 0 ]]; then
        # Periyot verilmemisse varsayilan ata + uyari
        if [[ "$_BACKTEST_AYAR_PERIYOT_VERILDI" -eq 0 ]]; then
            _BACKTEST_AYAR_PERIYOT="1G"
            echo "UYARI: --periyot belirtilmedi, 1G (gunluk) varsayildi." >&2
        fi
        # Tarih verilmemisse uyari
        if [[ "$_BACKTEST_AYAR_TARIH_VERILDI" -eq 0 ]]; then
            echo "UYARI: --tarih belirtilmedi, son 1 yil varsayildi." >&2
        fi
        return 0
    fi

    # --- Periyot ---
    if [[ "$_BACKTEST_AYAR_PERIYOT_VERILDI" -eq 0 ]]; then
        local girdi=""
        echo ""
        echo "Gecerli periyotlar: ${_BACKTEST_GECERLI_PERIYOTLAR}"
        read -rp "Periyot? [1G]: " girdi
        _BACKTEST_AYAR_PERIYOT="${girdi:-1G}"
    fi

    # --- Tarih ---
    if [[ "$_BACKTEST_AYAR_TARIH_VERILDI" -eq 0 ]]; then
        local girdi=""
        read -rp "Tarih araligi? (YYYY-AA-GG:YYYY-AA-GG) [${_BACKTEST_AYAR_TARIH_BAS}:${_BACKTEST_AYAR_TARIH_BIT}]: " girdi
        if [[ -n "$girdi" ]]; then
            _BACKTEST_AYAR_TARIH_BAS="${girdi%%:*}"
            _BACKTEST_AYAR_TARIH_BIT="${girdi##*:}"
        fi
    fi

    # --- Isitma (strateji onerisiyle) ---
    if [[ "$_BACKTEST_AYAR_ISITMA_VERILDI" -eq 0 ]]; then
        local oneri="${_BACKTEST_AYAR_ISITMA:-0}"
        if [[ "$oneri" != "0" ]]; then
            local girdi=""
            read -rp "Isitma donemi? (strateji onerisi: ${oneri} mum) [${oneri}]: " girdi
            _BACKTEST_AYAR_ISITMA="${girdi:-$oneri}"
        fi
    fi

    # --- Opsiyonel parametreler ---
    local degistir=""
    echo ""
    echo "--- Mevcut Ayarlar ---"
    echo "  Nakit      : ${_BACKTEST_AYAR_NAKIT} TL"
    echo "  Eslestirme : ${_BACKTEST_AYAR_ESLESTIRME}"
    echo "  Komisyon   : %$(echo "scale=3; ${_BACKTEST_AYAR_KOMISYON_ALIS} * 100" | bc) (alis), %$(echo "scale=3; ${_BACKTEST_AYAR_KOMISYON_SATIS} * 100" | bc) (satis)"
    echo "  Risksiz    : %$(echo "scale=0; ${_BACKTEST_AYAR_RISKSIZ} * 100" | bc)"
    echo "  Kaynak     : ${_BACKTEST_AYAR_KAYNAK}"
    read -rp "Baska bir sey degistirmek ister misiniz? [e/H]: " degistir

    if [[ "$degistir" == "e" ]] || [[ "$degistir" == "E" ]]; then
        local girdi=""
        read -rp "  Nakit? [${_BACKTEST_AYAR_NAKIT}]: " girdi
        [[ -n "$girdi" ]] && _BACKTEST_AYAR_NAKIT="$girdi"

        read -rp "  Eslestirme? (KAPANIS/LIMIT) [${_BACKTEST_AYAR_ESLESTIRME}]: " girdi
        [[ -n "$girdi" ]] && _BACKTEST_AYAR_ESLESTIRME=$(echo "$girdi" | tr '[:lower:]' '[:upper:]')

        read -rp "  Komisyon alis? [${_BACKTEST_AYAR_KOMISYON_ALIS}]: " girdi
        [[ -n "$girdi" ]] && _BACKTEST_AYAR_KOMISYON_ALIS="$girdi"

        read -rp "  Komisyon satis? [${_BACKTEST_AYAR_KOMISYON_SATIS}]: " girdi
        [[ -n "$girdi" ]] && _BACKTEST_AYAR_KOMISYON_SATIS="$girdi"

        read -rp "  Risksiz faiz? [${_BACKTEST_AYAR_RISKSIZ}]: " girdi
        [[ -n "$girdi" ]] && _BACKTEST_AYAR_RISKSIZ="$girdi"

        read -rp "  Kaynak? (supabase/csv/sentetik) [${_BACKTEST_AYAR_KAYNAK}]: " girdi
        [[ -n "$girdi" ]] && _BACKTEST_AYAR_KAYNAK="$girdi"
    fi

    return 0
}

# _backtest_parametre_dogrula
# Tum parametrelerin gecerliligini kontrol eder.
# Donus: 0 = gecerli, 1 = hatali parametre
_backtest_parametre_dogrula() {
    # Periyot dogrula
    if [[ -n "${_BACKTEST_AYAR_PERIYOT}" ]]; then
        if ! _backtest_periyot_gecerli_mi "$_BACKTEST_AYAR_PERIYOT"; then
            echo "HATA: Gecersiz periyot: ${_BACKTEST_AYAR_PERIYOT}. Gecerli: ${_BACKTEST_GECERLI_PERIYOTLAR}" >&2
            return 1
        fi
    fi

    # Tarih format dogrula (YYYY-AA-GG)
    local tarih_regex='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    if [[ ! "${_BACKTEST_AYAR_TARIH_BAS}" =~ $tarih_regex ]]; then
        echo "HATA: Baslangic tarih formati hatali: ${_BACKTEST_AYAR_TARIH_BAS}. Beklenen: YYYY-AA-GG" >&2
        return 1
    fi
    if [[ ! "${_BACKTEST_AYAR_TARIH_BIT}" =~ $tarih_regex ]]; then
        echo "HATA: Bitis tarih formati hatali: ${_BACKTEST_AYAR_TARIH_BIT}. Beklenen: YYYY-AA-GG" >&2
        return 1
    fi

    # Tarih gecerliligi (date -d ile)
    if ! date -d "${_BACKTEST_AYAR_TARIH_BAS}" +%s > /dev/null 2>&1; then
        echo "HATA: Gecersiz baslangic tarihi: ${_BACKTEST_AYAR_TARIH_BAS}" >&2
        return 1
    fi
    if ! date -d "${_BACKTEST_AYAR_TARIH_BIT}" +%s > /dev/null 2>&1; then
        echo "HATA: Gecersiz bitis tarihi: ${_BACKTEST_AYAR_TARIH_BIT}" >&2
        return 1
    fi

    # Tarih mantik: bas < bit
    local bas_epoch bit_epoch
    bas_epoch=$(date -d "${_BACKTEST_AYAR_TARIH_BAS}" +%s)
    bit_epoch=$(date -d "${_BACKTEST_AYAR_TARIH_BIT}" +%s)
    if [[ "$bas_epoch" -ge "$bit_epoch" ]]; then
        echo "HATA: Bitis tarihi baslangictan once olamaz. (${_BACKTEST_AYAR_TARIH_BAS} >= ${_BACKTEST_AYAR_TARIH_BIT})" >&2
        return 1
    fi

    # Nakit dogrula: pozitif sayi
    if ! echo "${_BACKTEST_AYAR_NAKIT}" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
        echo "HATA: Nakit pozitif sayi olmali: ${_BACKTEST_AYAR_NAKIT}" >&2
        return 1
    fi
    local nakit_pozitif
    nakit_pozitif=$(echo "${_BACKTEST_AYAR_NAKIT} > 0" | bc -l 2>/dev/null)
    if [[ "${nakit_pozitif:-0}" != "1" ]]; then
        echo "HATA: Nakit pozitif sayi olmali." >&2
        return 1
    fi

    # Komisyon dogrula: sayi formati
    local komisyon_regex='^[0-9]*\.?[0-9]+$'
    if [[ ! "${_BACKTEST_AYAR_KOMISYON_ALIS}" =~ $komisyon_regex ]]; then
        echo "HATA: Komisyon alis orani sayi olmali: ${_BACKTEST_AYAR_KOMISYON_ALIS}" >&2
        return 1
    fi
    if [[ ! "${_BACKTEST_AYAR_KOMISYON_SATIS}" =~ $komisyon_regex ]]; then
        echo "HATA: Komisyon satis orani sayi olmali: ${_BACKTEST_AYAR_KOMISYON_SATIS}" >&2
        return 1
    fi

    # Eslestirme dogrula
    if [[ "${_BACKTEST_AYAR_ESLESTIRME}" != "KAPANIS" ]] && [[ "${_BACKTEST_AYAR_ESLESTIRME}" != "LIMIT" ]]; then
        echo "HATA: Eslestirme KAPANIS veya LIMIT olmali: ${_BACKTEST_AYAR_ESLESTIRME}" >&2
        return 1
    fi

    # Isitma dogrula: negatif olmayan tamsayi
    if ! echo "${_BACKTEST_AYAR_ISITMA}" | grep -qE '^[0-9]+$'; then
        echo "HATA: Isitma donemi negatif olmayan tamsayi olmali: ${_BACKTEST_AYAR_ISITMA}" >&2
        return 1
    fi

    # Risksiz dogrula: 0-5 arasi sayi
    local risksiz_regex='^[0-9]*\.?[0-9]+$'
    if [[ ! "${_BACKTEST_AYAR_RISKSIZ}" =~ $risksiz_regex ]]; then
        echo "HATA: Risksiz faiz orani sayi olmali: ${_BACKTEST_AYAR_RISKSIZ}" >&2
        return 1
    fi
    local risksiz_aralik
    risksiz_aralik=$(awk -v r="${_BACKTEST_AYAR_RISKSIZ}" 'BEGIN { print (r >= 0 && r <= 5) ? 1 : 0 }')
    if [[ "$risksiz_aralik" != "1" ]]; then
        echo "HATA: Risksiz faiz orani 0-5 arasinda olmali: ${_BACKTEST_AYAR_RISKSIZ}" >&2
        return 1
    fi

    # Kaynak dogrula
    case "${_BACKTEST_AYAR_KAYNAK}" in
        supabase|csv|sentetik) ;;
        *)
            echo "HATA: Gecersiz kaynak: ${_BACKTEST_AYAR_KAYNAK}. Gecerli: supabase, csv, sentetik" >&2
            return 1
            ;;
    esac

    # Sentetik + periyot uyumluluk
    if [[ "${_BACKTEST_AYAR_KAYNAK}" == "sentetik" ]]; then
        local periyot="${_BACKTEST_AYAR_PERIYOT:-1G}"
        if [[ "$periyot" != "1G" ]]; then
            echo "HATA: Sentetik veri sadece 1G (gunluk) periyot destekler. Secilen: $periyot" >&2
            return 1
        fi
    fi

    return 0
}

# _backtest_onay_goster
# Parametrelerin ozetini gosterir ve onay ister.
# --sessiz/--evet modunda veya pipe'da onay otomatik atlanir.
# Donus: 0 = onaylandi, 1 = iptal
_backtest_onay_goster() {
    local periyot="${_BACKTEST_AYAR_PERIYOT:-1G}"
    local kom_alis_yuzde
    kom_alis_yuzde=$(echo "scale=3; ${_BACKTEST_AYAR_KOMISYON_ALIS} * 100" | bc 2>/dev/null)
    local kom_satis_yuzde
    kom_satis_yuzde=$(echo "scale=3; ${_BACKTEST_AYAR_KOMISYON_SATIS} * 100" | bc 2>/dev/null)
    local risksiz_yuzde
    risksiz_yuzde=$(echo "scale=0; ${_BACKTEST_AYAR_RISKSIZ} * 100" | bc 2>/dev/null)
    local nakit_fmt
    nakit_fmt=$(_backtest_sayi_formatla "${_BACKTEST_AYAR_NAKIT}")

    echo ""
    echo "--- Backtest Parametreleri ---"
    echo "Strateji   : ${_BACKTEST_AYAR_STRATEJI:-bilinmiyor}"
    echo "Sembol     : ${_BACKTEST_AYAR_SEMBOLLER:-bilinmiyor}"
    echo "Periyot    : ${periyot}"
    echo "Donem      : ${_BACKTEST_AYAR_TARIH_BAS} / ${_BACKTEST_AYAR_TARIH_BIT}"
    echo "Nakit      : ${nakit_fmt} TL"
    echo "Eslestirme : ${_BACKTEST_AYAR_ESLESTIRME}"
    echo "Komisyon   : %${kom_alis_yuzde} (alis), %${kom_satis_yuzde} (satis)"
    echo "Isitma     : ${_BACKTEST_AYAR_ISITMA} mum"
    echo "Risksiz    : %${risksiz_yuzde}"
    echo "Kaynak     : ${_BACKTEST_AYAR_KAYNAK}"

    # --evet, --sessiz veya pipe modunda onay atla
    if [[ "${_BACKTEST_AYAR_EVET:-0}" == "1" ]] || [[ "${_BACKTEST_AYAR_SESSIZ:-0}" == "1" ]] || [[ ! -t 0 ]]; then
        echo ""
        return 0
    fi

    echo ""
    local onay=""
    read -rp "Devam edilsin mi? [E/h]: " onay
    if [[ "$onay" == "h" ]] || [[ "$onay" == "H" ]]; then
        echo "Backtest iptal edildi."
        return 1
    fi

    return 0
}
