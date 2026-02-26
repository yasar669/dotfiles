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

    echo "Backtest basliyor..."
    echo "  Strateji : $_BACKTEST_AYAR_STRATEJI"
    echo "  Semboller: $semboller"
    echo "  Donem    : ${_BACKTEST_AYAR_TARIH_BAS} - ${_BACKTEST_AYAR_TARIH_BIT}"
    echo "  Nakit    : ${_BACKTEST_AYAR_NAKIT} TL"
    echo "  Eslestirme: ${_BACKTEST_AYAR_ESLESTIRME}"
    echo "  Kaynak   : ${_BACKTEST_AYAR_KAYNAK}"

    # Strateji dosyasini source et
    # shellcheck source=/dev/null
    source "$strateji_yolu"

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
        _backtest_veri_yukle "$sem" "$_BACKTEST_AYAR_TARIH_BAS" "$_BACKTEST_AYAR_TARIH_BIT" "$_BACKTEST_AYAR_KAYNAK"
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
        local sinyal=""
        if declare -f strateji_degerlendir > /dev/null 2>&1; then
            sinyal=$(strateji_degerlendir "$sembol" "$fiyat" "$tavan" "$taban" "$degisim" "$hacim" "$seans")
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

                local sonuc
                sonuc=$(_backtest_emir_isle "$yon" "$sembol" "$lot" "$emir_fiyat" "$tavan" "$taban")
                local emir_durumu=$?

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

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tarih|-t)
                local tarih_aralik="$2"
                _BACKTEST_AYAR_TARIH_BAS="${tarih_aralik%%:*}"
                _BACKTEST_AYAR_TARIH_BIT="${tarih_aralik##*:}"
                shift 2
                ;;
            --nakit|-n)
                _BACKTEST_AYAR_NAKIT="$2"
                shift 2
                ;;
            --komisyon-alis|-ka)
                _BACKTEST_AYAR_KOMISYON_ALIS="$2"
                shift 2
                ;;
            --komisyon-satis|-ks)
                _BACKTEST_AYAR_KOMISYON_SATIS="$2"
                shift 2
                ;;
            --eslestirme|-e)
                local mod
                mod=$(echo "$2" | tr '[:lower:]' '[:upper:]')
                if [[ "$mod" != "KAPANIS" ]] && [[ "$mod" != "LIMIT" ]]; then
                    echo "HATA: Gecersiz eslestirme modu: $2 (KAPANIS veya LIMIT)" >&2
                    return 1
                fi
                _BACKTEST_AYAR_ESLESTIRME="$mod"
                shift 2
                ;;
            --isitma|-i)
                _BACKTEST_AYAR_ISITMA="$2"
                shift 2
                ;;
            --risksiz|-r)
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
                _BACKTEST_AYAR_KAYNAK="$2"
                shift 2
                ;;
            --csv-dosya|-cf)
                _BACKTEST_AYAR_CSV_DOSYA="$2"
                shift 2
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
