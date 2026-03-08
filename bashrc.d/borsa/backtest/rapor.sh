# shellcheck shell=bash

# Backtest - Rapor ve Sonuc Kaydetme
# Terminal cikti formatlama, Supabase'e sonuc kaydetme,
# gecmis sonuclari listeleme ve karsilastirma.

# _backtest_rapor_goster
# _BACKTEST_SONUC array'ini formatlayarak terminale yazdirir.
# --sessiz modda kisaltilmis, --detay modda islem listeli cikti.
# Donus: 0
_backtest_rapor_goster() {
    local sessiz="${_BACKTEST_AYAR_SESSIZ:-0}"
    local detay="${_BACKTEST_AYAR_DETAY:-0}"

    echo ""
    echo "=== BACKTEST SONUCU ==="
    echo "Strateji:        ${_BACKTEST_AYAR_STRATEJI:-bilinmiyor}"
    echo "Sembol:          ${_BACKTEST_AYAR_SEMBOLLER:-bilinmiyor}"
    echo "Periyot:         ${_BACKTEST_AYAR_PERIYOT:-1G}"
    echo "Donem:           ${_BACKTEST_GUNLUK_TARIH[0]:-?} / ${_BACKTEST_GUNLUK_TARIH[-1]:-?} (${_BACKTEST_SONUC[gun_sayisi]:-0} islem gunu)"

    # Sayilari formatlayarak goster
    local bas_nakit
    bas_nakit=$(_backtest_sayi_formatla "${_BACKTEST_SONUC[baslangic_nakit]:-0}")
    local bit_deger
    bit_deger=$(_backtest_sayi_formatla "${_BACKTEST_SONUC[bitis_deger]:-0}")

    echo "Baslangic:       ${bas_nakit} TL"
    echo "Bitis:           ${bit_deger} TL"
    echo "---"
    echo "Toplam Getiri:   %${_BACKTEST_SONUC[toplam_getiri]:-0}"
    echo "Yillik Getiri:   %${_BACKTEST_SONUC[yillik_getiri]:-0}"
    echo "Maks Dusus:      %${_BACKTEST_SONUC[maks_dusus]:-0}"
    echo "Sharpe Orani:    ${_BACKTEST_SONUC[sharpe]:-0}"
    echo "Sortino Orani:   ${_BACKTEST_SONUC[sortino]:-0}"
    echo "Calmar Orani:    ${_BACKTEST_SONUC[calmar]:-0}"
    echo "---"

    local toplam_islem="${_BACKTEST_SONUC[toplam_islem]:-0}"
    local alis_sayisi="${_BACKTEST_SONUC[alis_sayisi]:-0}"
    local satis_sayisi="${_BACKTEST_SONUC[satis_sayisi]:-0}"
    local basarili="${_BACKTEST_SONUC[basarili_islem]:-0}"
    echo "Toplam Islem:    $toplam_islem ($alis_sayisi alis, $satis_sayisi satis)"
    echo "Basari Orani:    %${_BACKTEST_SONUC[basari_orani]:-0} ($basarili/$satis_sayisi karli)"
    echo "Kar/Zarar Orani: ${_BACKTEST_SONUC[kz_orani]:-0}"

    local toplam_kom
    toplam_kom=$(_backtest_sayi_formatla "${_BACKTEST_SONUC[toplam_komisyon]:-0}")
    echo "Toplam Komisyon: ${toplam_kom} TL"
    echo "---"
    echo "Ort Pozisyon:    ${_BACKTEST_SONUC[ort_pozisyon_gun]:-0} gun"
    echo "Maks Kayip Seri: ${_BACKTEST_SONUC[maks_kayip_seri]:-0} islem"
    echo ""
    echo "UYARI: Hayatta kalma yanliligi icermektedir."

    # Detay modunda islem listesi goster
    if [[ "$detay" == "1" ]] && [[ "$sessiz" != "1" ]]; then
        _backtest_islem_listesi_goster
    fi
}

# _backtest_islem_listesi_goster
# Tum islemleri tablo formatinda gosterir.
_backtest_islem_listesi_goster() {
    local islem_sayisi=${#_BACKTEST_ISLEMLER[@]}
    [[ "$islem_sayisi" -eq 0 ]] && return 0

    echo ""
    echo "=== ISLEM DETAYLARI ==="
    printf "%-5s %-12s %-8s %-6s %-6s %-10s %-10s %-14s\n" \
        "Gun" "Tarih" "Sembol" "Yon" "Lot" "Fiyat" "Komisyon" "Portfoy"
    printf "%-5s %-12s %-8s %-6s %-6s %-10s %-10s %-14s\n" \
        "----" "----------" "------" "-----" "-----" "--------" "--------" "----------"

    local islem
    for islem in "${_BACKTEST_ISLEMLER[@]}"; do
        local gun_no tarih sembol yon lot fiyat komisyon nakit portfoy
        IFS='|' read -r gun_no tarih sembol yon lot fiyat komisyon nakit portfoy _ <<< "$islem"
        printf "%-5s %-12s %-8s %-6s %-6s %-10s %-10s %-14s\n" \
            "$gun_no" "$tarih" "$sembol" "$yon" "$lot" "$fiyat" "$komisyon" "$portfoy"
    done
}

# _backtest_sayi_formatla <sayi>
# Sayiyi binlik ayiriciyla formatlar. Ornek: 100000.00 -> 100.000,00
_backtest_sayi_formatla() {
    local sayi="$1"
    local sonuc
    # bc/awk ciktilari nokta kullanir ama Turkce locale virgul bekler
    # Ondalik noktayi virgule cevir
    sonuc=$(printf "%'.2f" "${sayi/./,}" 2>/dev/null) || true
    if [[ -n "$sonuc" ]]; then
        echo "$sonuc"
    else
        echo "$sayi"
    fi
}

# _backtest_sonuc_kaydet
# Backtest sonuclarini Supabase backtest_sonuclari tablosuna yazar.
# Supabase kapaliysa uyari verir, hata dondurmez.
# Donus: 0
_backtest_sonuc_kaydet() {
    if [[ -z "${_SUPABASE_URL:-}" ]] || [[ -z "${_SUPABASE_ANAHTAR:-}" ]]; then
        echo "UYARI: Supabase ayarlari yuklu degil, sonuclar kaydedilemiyor." >&2
        return 0
    fi

    # backtest_sonuclari tablosuna ekle
    local sembol_dizi
    sembol_dizi=$(echo "${_BACKTEST_AYAR_SEMBOLLER:-}" | tr ',' '\n' | awk '{printf "\"%s\",", $0}' | sed 's/,$//')

    local json
    json=$(printf '{
        "strateji": "%s",
        "semboller": [%s],
        "baslangic_tarih": "%s",
        "bitis_tarih": "%s",
        "islem_gunu": %s,
        "baslangic_nakit": %s,
        "bitis_deger": %s,
        "toplam_getiri": %s,
        "yillik_getiri": %s,
        "maks_dusus": %s,
        "sharpe_orani": %s,
        "sortino_orani": %s,
        "calmar_orani": %s,
        "toplam_islem": %s,
        "basarili_islem": %s,
        "basari_orani": %s,
        "kz_orani": %s,
        "toplam_komisyon": %s,
        "ort_pozisyon_gun": %s,
        "maks_kayip_seri": %s,
        "periyot": "%s",
        "eslestirme": "%s",
        "komisyon_alis": %s,
        "komisyon_satis": %s
    }' \
        "${_BACKTEST_AYAR_STRATEJI:-}" \
        "$sembol_dizi" \
        "${_BACKTEST_GUNLUK_TARIH[0]:-}" \
        "${_BACKTEST_GUNLUK_TARIH[-1]:-}" \
        "${_BACKTEST_SONUC[gun_sayisi]:-0}" \
        "${_BACKTEST_SONUC[baslangic_nakit]:-0}" \
        "${_BACKTEST_SONUC[bitis_deger]:-0}" \
        "${_BACKTEST_SONUC[toplam_getiri]:-0}" \
        "${_BACKTEST_SONUC[yillik_getiri]:-0}" \
        "${_BACKTEST_SONUC[maks_dusus]:-0}" \
        "${_BACKTEST_SONUC[sharpe]:-0}" \
        "${_BACKTEST_SONUC[sortino]:-0}" \
        "${_BACKTEST_SONUC[calmar]:-0}" \
        "${_BACKTEST_SONUC[toplam_islem]:-0}" \
        "${_BACKTEST_SONUC[basarili_islem]:-0}" \
        "${_BACKTEST_SONUC[basari_orani]:-0}" \
        "${_BACKTEST_SONUC[kz_orani]:-0}" \
        "${_BACKTEST_SONUC[toplam_komisyon]:-0}" \
        "${_BACKTEST_SONUC[ort_pozisyon_gun]:-0}" \
        "${_BACKTEST_SONUC[maks_kayip_seri]:-0}" \
        "${_BACKTEST_AYAR_PERIYOT:-1G}" \
        "${_BACKTEST_AYAR_ESLESTIRME:-KAPANIS}" \
        "${_BACKTEST_AYAR_KOMISYON_ALIS:-0.00188}" \
        "${_BACKTEST_AYAR_KOMISYON_SATIS:-0.00188}")

    local yanit
    yanit=$(curl -s -X POST "${_SUPABASE_URL}/rest/v1/backtest_sonuclari" \
        -H "apikey: ${_SUPABASE_ANAHTAR}" \
        -H "Authorization: Bearer ${_SUPABASE_ANAHTAR}" \
        -H "Content-Type: application/json" \
        -H "Prefer: return=representation" \
        -d "$json" 2>/dev/null)

    if [[ -z "$yanit" ]] || [[ "$yanit" == *"error"* ]]; then
        echo "UYARI: Backtest sonucu Supabase'e kaydedilemedi." >&2
        return 0
    fi

    # Eklenen kaydin id'sini al
    local backtest_id
    backtest_id=$(echo "$yanit" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)

    if [[ -n "$backtest_id" ]]; then
        # Islemleri kaydet
        _backtest_islemleri_kaydet "$backtest_id"
        # Gunluk verileri kaydet
        _backtest_gunluk_kaydet_vt "$backtest_id"
        echo "Backtest sonucu kaydedildi (ID: $backtest_id)."
    fi

    return 0
}

# _backtest_islemleri_kaydet <backtest_id>
# Islem detaylarini backtest_islemleri tablosuna yazar.
_backtest_islemleri_kaydet() {
    local backtest_id="$1"
    local islem
    for islem in "${_BACKTEST_ISLEMLER[@]}"; do
        local gun_no tarih sembol yon lot fiyat komisyon nakit portfoy sinyal
        IFS='|' read -r gun_no tarih sembol yon lot fiyat komisyon nakit portfoy sinyal <<< "$islem"

        local json
        json=$(printf '{"backtest_id":%s,"gun_no":%s,"tarih":"%s","sembol":"%s","yon":"%s","lot":%s,"fiyat":%s,"komisyon":%s,"nakit_sonrasi":%s,"portfoy_degeri":%s,"sinyal":"%s"}' \
            "$backtest_id" "$gun_no" "$tarih" "$sembol" "$yon" "$lot" "$fiyat" \
            "${komisyon:-0}" "${nakit:-0}" "${portfoy:-0}" "${sinyal:-}")

        curl -s -X POST "${_SUPABASE_URL}/rest/v1/backtest_islemleri" \
            -H "apikey: ${_SUPABASE_ANAHTAR}" \
            -H "Authorization: Bearer ${_SUPABASE_ANAHTAR}" \
            -H "Content-Type: application/json" \
            -H "Prefer: return=minimal" \
            -d "$json" > /dev/null 2>&1
    done
}

# _backtest_gunluk_kaydet_vt <backtest_id>
# Gunluk portfoy degerlerini backtest_gunluk tablosuna yazar.
_backtest_gunluk_kaydet_vt() {
    local backtest_id="$1"
    local toplam=${#_BACKTEST_GUNLUK_TARIH[@]}
    local i

    for (( i=0; i<toplam; i++ )); do
        local json
        json=$(printf '{"backtest_id":%s,"gun_no":%s,"tarih":"%s","nakit":%s,"hisse_degeri":%s,"toplam":%s,"dusus":%s}' \
            "$backtest_id" "$((i+1))" \
            "${_BACKTEST_GUNLUK_TARIH[$i]}" \
            "${_BACKTEST_GUNLUK_NAKIT[$i]}" \
            "${_BACKTEST_GUNLUK_HISSE[$i]}" \
            "${_BACKTEST_GUNLUK_TOPLAM[$i]}" \
            "${_BACKTEST_GUNLUK_DUSUS[$i]:-0}")

        curl -s -X POST "${_SUPABASE_URL}/rest/v1/backtest_gunluk" \
            -H "apikey: ${_SUPABASE_ANAHTAR}" \
            -H "Authorization: Bearer ${_SUPABASE_ANAHTAR}" \
            -H "Content-Type: application/json" \
            -H "Prefer: return=minimal" \
            -d "$json" > /dev/null 2>&1
    done
}

# _backtest_sonuclari_listele [--strateji <ad>] [--son <N>]
# Gecmis backtest sonuclarini Supabase'den okuyup tablo olarak gosterir.
# Donus: 0
_backtest_sonuclari_listele() {
    if [[ -z "${_SUPABASE_URL:-}" ]] || [[ -z "${_SUPABASE_ANAHTAR:-}" ]]; then
        echo "HATA: Supabase ayarlari yuklu degil." >&2
        return 1
    fi

    local filtre="" limit=20
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strateji)
                filtre="&strateji=eq.$2"
                shift 2
                ;;
            --son)
                limit="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    local url="${_SUPABASE_URL}/rest/v1/backtest_sonuclari?order=zaman.desc&limit=${limit}${filtre}"
    url="${url}&select=id,strateji,semboller,baslangic_tarih,bitis_tarih,toplam_getiri,maks_dusus,sharpe_orani,basari_orani,zaman"

    local yanit
    yanit=$(curl -s -X GET "$url" \
        -H "apikey: ${_SUPABASE_ANAHTAR}" \
        -H "Authorization: Bearer ${_SUPABASE_ANAHTAR}" \
        -H "Content-Type: application/json" 2>/dev/null)

    if [[ -z "$yanit" ]] || [[ "$yanit" == "[]" ]]; then
        echo "Kayitli backtest sonucu bulunamadi."
        return 0
    fi

    echo "=== BACKTEST SONUCLARI ==="
    printf "%-6s %-20s %-12s %-12s %-10s %-10s %-8s %-8s\n" \
        "ID" "Strateji" "Baslangic" "Bitis" "Getiri%" "MaksDus%" "Sharpe" "Basari%"
    printf "%-6s %-20s %-12s %-12s %-10s %-10s %-8s %-8s\n" \
        "-----" "-------------------" "----------" "----------" "--------" "--------" "------" "------"

    if command -v jq > /dev/null 2>&1; then
        echo "$yanit" | jq -r '.[] | "\(.id)\t\(.strateji)\t\(.baslangic_tarih)\t\(.bitis_tarih)\t\(.toplam_getiri)\t\(.maks_dusus)\t\(.sharpe_orani)\t\(.basari_orani)"' | \
        while IFS=$'\t' read -r id strateji bas_tarih bit_tarih getiri dusus sharpe basari; do
            printf "%-6s %-20s %-12s %-12s %-10s %-10s %-8s %-8s\n" \
                "${id:-}" "${strateji:-}" "${bas_tarih:-}" "${bit_tarih:-}" \
                "${getiri:-}" "${dusus:-}" "${sharpe:-}" "${basari:-}"
        done
    else
        # jq yoksa json_satir bazli parse (semboller dizisi parcalanabilir)
        echo "$yanit" | tr '}' '\n' | grep '"id"' | while IFS= read -r satir; do
            local id strateji bas_tarih bit_tarih getiri dusus sharpe basari
            id=$(echo "$satir" | grep -o '"id":[0-9]*' | cut -d: -f2)
            strateji=$(echo "$satir" | grep -o '"strateji":"[^"]*"' | cut -d'"' -f4)
            bas_tarih=$(echo "$satir" | grep -o '"baslangic_tarih":"[^"]*"' | cut -d'"' -f4)
            bit_tarih=$(echo "$satir" | grep -o '"bitis_tarih":"[^"]*"' | cut -d'"' -f4)
            getiri=$(echo "$satir" | grep -o '"toplam_getiri":[0-9.-]*' | cut -d: -f2)
            dusus=$(echo "$satir" | grep -o '"maks_dusus":[0-9.-]*' | cut -d: -f2)
            sharpe=$(echo "$satir" | grep -o '"sharpe_orani":[0-9.-]*' | cut -d: -f2)
            basari=$(echo "$satir" | grep -o '"basari_orani":[0-9.-]*' | cut -d: -f2)

            printf "%-6s %-20s %-12s %-12s %-10s %-10s %-8s %-8s\n" \
                "${id:-}" "${strateji:-}" "${bas_tarih:-}" "${bit_tarih:-}" \
                "${getiri:-}" "${dusus:-}" "${sharpe:-}" "${basari:-}"
        done
    fi
}

# _backtest_detay_goster <backtest_id>
# Belirli bir backtest'in islem detaylarini Supabase'den okuyup gosterir.
# Donus: 0 = basarili, 1 = bulunamadi
_backtest_detay_goster() {
    local bt_id="$1"

    if [[ -z "$bt_id" ]]; then
        echo "Kullanim: borsa backtest detay <backtest_id>"
        return 1
    fi

    if [[ -z "${_SUPABASE_URL:-}" ]] || [[ -z "${_SUPABASE_ANAHTAR:-}" ]]; then
        echo "HATA: Supabase ayarlari yuklu degil." >&2
        return 1
    fi

    # Ozet bilgiyi cek
    local ozet_url="${_SUPABASE_URL}/rest/v1/backtest_sonuclari?id=eq.${bt_id}"
    local ozet
    ozet=$(curl -s -X GET "$ozet_url" \
        -H "apikey: ${_SUPABASE_ANAHTAR}" \
        -H "Authorization: Bearer ${_SUPABASE_ANAHTAR}" \
        -H "Content-Type: application/json" 2>/dev/null)

    if [[ -z "$ozet" ]] || [[ "$ozet" == "[]" ]]; then
        echo "HATA: Backtest ID $bt_id bulunamadi."
        return 1
    fi

    echo "=== BACKTEST #$bt_id DETAY ==="
    echo "$ozet" | tr ',' '\n' | tr -d '[]{}"' | sed 's/^/  /'
    echo ""

    # Islemleri cek
    local islem_url="${_SUPABASE_URL}/rest/v1/backtest_islemleri?backtest_id=eq.${bt_id}&order=gun_no.asc"
    local islemler
    islemler=$(curl -s -X GET "$islem_url" \
        -H "apikey: ${_SUPABASE_ANAHTAR}" \
        -H "Authorization: Bearer ${_SUPABASE_ANAHTAR}" \
        -H "Content-Type: application/json" 2>/dev/null)

    if [[ -n "$islemler" ]] && [[ "$islemler" != "[]" ]]; then
        echo "=== ISLEMLER ==="
        printf "%-5s %-12s %-8s %-6s %-6s %-10s %-10s\n" \
            "Gun" "Tarih" "Sembol" "Yon" "Lot" "Fiyat" "Komisyon"
        printf "%-5s %-12s %-8s %-6s %-6s %-10s %-10s\n" \
            "----" "----------" "------" "-----" "-----" "--------" "--------"

        echo "$islemler" | tr '[{' '\n' | grep '"gun_no"' | while IFS= read -r satir; do
            local gun tarih sembol yon lot fiyat kom
            gun=$(echo "$satir" | grep -o '"gun_no":[0-9]*' | cut -d: -f2)
            tarih=$(echo "$satir" | grep -o '"tarih":"[^"]*"' | cut -d'"' -f4)
            sembol=$(echo "$satir" | grep -o '"sembol":"[^"]*"' | cut -d'"' -f4)
            yon=$(echo "$satir" | grep -o '"yon":"[^"]*"' | cut -d'"' -f4)
            lot=$(echo "$satir" | grep -o '"lot":[0-9]*' | cut -d: -f2)
            fiyat=$(echo "$satir" | grep -o '"fiyat":[0-9.]*' | cut -d: -f2)
            kom=$(echo "$satir" | grep -o '"komisyon":[0-9.]*' | cut -d: -f2)

            printf "%-5s %-12s %-8s %-6s %-6s %-10s %-10s\n" \
                "${gun:-}" "${tarih:-}" "${sembol:-}" "${yon:-}" "${lot:-}" "${fiyat:-}" "${kom:-}"
        done
    fi
}

# _backtest_karsilastir <id_1> <id_2>
# Iki backtest sonucunu yan yana karsilastirir.
# Donus: 0 = basarili, 1 = bulunamadi
_backtest_karsilastir() {
    local id1="$1"
    local id2="$2"

    if [[ -z "$id1" ]] || [[ -z "$id2" ]]; then
        echo "Kullanim: borsa backtest karsilastir <id_1> <id_2>"
        return 1
    fi

    if [[ -z "${_SUPABASE_URL:-}" ]] || [[ -z "${_SUPABASE_ANAHTAR:-}" ]]; then
        echo "HATA: Supabase ayarlari yuklu degil." >&2
        return 1
    fi

    local url="${_SUPABASE_URL}/rest/v1/backtest_sonuclari?or=(id.eq.${id1},id.eq.${id2})"
    local yanit
    yanit=$(curl -s -X GET "$url" \
        -H "apikey: ${_SUPABASE_ANAHTAR}" \
        -H "Authorization: Bearer ${_SUPABASE_ANAHTAR}" \
        -H "Content-Type: application/json" 2>/dev/null)

    if [[ -z "$yanit" ]] || [[ "$yanit" == "[]" ]]; then
        echo "HATA: Belirtilen backtest kayitlari bulunamadi."
        return 1
    fi

    echo "=== BACKTEST KARSILASTIRMA ==="
    printf "%-24s %-18s %-18s\n" "Metrik" "BT #$id1" "BT #$id2"
    printf "%-24s %-18s %-18s\n" "-----------------------" "-----------------" "-----------------"

    # Basit karsilastirma: JSON'u satirlara cevirip goster
    local metrikler="strateji toplam_getiri yillik_getiri maks_dusus sharpe_orani sortino_orani calmar_orani basari_orani kz_orani toplam_islem toplam_komisyon"
    local m
    for m in $metrikler; do
        local v1 v2
        v1=$(echo "$yanit" | grep -o "\"$m\":[^,}]*" | head -1 | cut -d: -f2 | tr -d '"')
        v2=$(echo "$yanit" | grep -o "\"$m\":[^,}]*" | tail -1 | cut -d: -f2 | tr -d '"')
        printf "%-24s %-18s %-18s\n" "$m" "${v1:-N/A}" "${v2:-N/A}"
    done
}
