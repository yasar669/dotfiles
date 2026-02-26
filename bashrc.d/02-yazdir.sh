# shellcheck shell=bash
# ============================================================
# 02-yazdir.sh - PDF ve Markdown Yazdirma Araci
# HP DeskJet 2540 icin optimize edilmis
# ============================================================
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
        echo "  yazdir [SECENEK] \"dosya.md\" satir-araligi"
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
        echo "PDF SAYFA ARALIGI ORNEKLERI:"
        echo "  5-10              Sayfa 5'ten 10'a kadar"
        echo "  157,159           Sadece sayfa 157 ve 159"
        echo "  3,7,12-15         Sayfa 3, 7 ve 12-15 arasi"
        echo ""
        echo "MARKDOWN ARALIK ORNEKLERI:"
        echo "  MD dosyalarinda aralik VARSAYILAN olarak SATIR numarasidir."
        echo "  tumu              Tum dosyayi yazdir"
        echo "  10-85             Satir 10'dan 85'e kadar (varsayilan: satir)"
        echo "  satir:10-85       Satir 10'dan 85'e kadar (acik belirtme)"
        echo "  sayfa:1-3         PDF'e cevrildikten sonra sayfa 1-3 (eski davranis)"
        echo ""
        echo "ORNEK KOMUTLAR:"
        echo "  yazdir \"kitap.pdf\" 1-20"
        echo "      20 sayfayi siyah-beyaz yazdir (varsayilan)"
        echo ""
        echo "  yazdir -r \"harita.pdf\" 5-8"
        echo "      4 sayfayi renkli yazdir"
        echo ""
        echo "  yazdir \"konu.md\" tumu"
        echo "      Markdown dosyasini tamamen yazdir"
        echo ""
        echo "  yazdir \"plan.md\" 1-50"
        echo "      Markdown'in ilk 50 satirini yazdir"
        echo ""
        echo "  yazdir -r \"notlar.md\" satir:30-80"
        echo "      Markdown'in 30-80 arasi satirlarini renkli yazdir"
        echo ""
        echo "  yazdir \"notlar.md\" sayfa:1-3"
        echo "      Markdown'dan olusturulan PDF'in 1-3 sayfalarini yazdir"
        echo ""
        echo "NOT: Siyah-beyaz baski murekkep tasarrufu saglar."
        echo "     Harita, grafik gibi icerikler icin -r kullanin."
        echo "     MD dosyalarinda 'tumu' veya 'hepsi' tum dosyayi yazdirir."
        echo "     MD icin sayfa araligi istiyorsaniz 'sayfa:1-3' seklinde belirtin."
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

        local md_kaynak="$dosya"
        local satir_gecici="/tmp/yazdir-satirlar.md"

        # MD dosyalari icin aralik varsayilan olarak SATIR araligini ifade eder
        # 'tumu' / 'hepsi' => tum dosya
        # 'satir:10-85' veya '10-85' => 10-85 arasi satirlar
        # 'sayfa:1-3' => PDF'e cevrildikten sonra sayfa araligi (eski davranis)
        local sayfa_araligi_modu="hayir"
        local satir_bas=""
        local satir_bit=""

        if [[ "$aralik" == "tumu" || "$aralik" == "hepsi" ]]; then
            # Tum dosya, aynen devam
            :
        elif [[ "$aralik" == sayfa:* ]]; then
            # Acik sayfa araligi istendi: 'sayfa:1-3'
            aralik="${aralik#sayfa:}"
            sayfa_araligi_modu="evet"
        elif [[ "$aralik" == satir:* ]]; then
            # Acik satir araligi: 'satir:10-85'
            local satir_aralik="${aralik#satir:}"
            satir_bas="${satir_aralik%-*}"
            satir_bit="${satir_aralik#*-}"
        elif [[ "$aralik" =~ ^[0-9]+-[0-9]+$ ]]; then
            # Duz aralik (10-85) => MD icin varsayilan olarak satir araligi
            satir_bas="${aralik%-*}"
            satir_bit="${aralik#*-}"
        fi

        # Satir araligi belirtildiyse dosyadan o satirlari kes
        if [[ -n "$satir_bas" && -n "$satir_bit" ]]; then
            local toplam_satir
            toplam_satir=$(wc -l < "$dosya")
            if (( satir_bas < 1 )); then
                satir_bas=1
            fi
            if (( satir_bit > toplam_satir )); then
                satir_bit=$toplam_satir
            fi
            if (( satir_bas > satir_bit )); then
                echo "HATA: Baslangic satiri ($satir_bas) bitis satirindan ($satir_bit) buyuk!"
                return 1
            fi
            echo "Satir araligi: $satir_bas - $satir_bit (toplam $((satir_bit - satir_bas + 1)) satir)"
            sed -n "${satir_bas},${satir_bit}p" "$dosya" > "$satir_gecici"
            md_kaynak="$satir_gecici"
        fi

        local html_gecici="/tmp/yazdir-md.html"
        local pdf_gecici="/tmp/yazdir-md.pdf"
        
        # Python markdown modulu ile HTML'e cevir (Turkce destekli, guzel formatli)
        python3 -c "
import markdown
import sys

with open('$md_kaynak', 'r', encoding='utf-8') as f:
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

        # shellcheck disable=SC2181
        if [ $? -ne 0 ]; then
            echo "HATA: Markdown -> HTML donusumu basarisiz!"
            return 1
        fi

        # Google Chrome headless ile HTML'den PDF olustur
        google-chrome --headless --disable-gpu --no-sandbox --print-to-pdf="$pdf_gecici" "$html_gecici" 2>/dev/null

        # shellcheck disable=SC2181
        if [ $? -ne 0 ] || [ ! -f "$pdf_gecici" ]; then
            echo "HATA: HTML -> PDF donusumu basarisiz!"
            return 1
        fi

        echo "Markdown basariyla PDF'e cevrildi."
        
        # Gecici satir dosyasini temizle
        rm -f "$satir_gecici"

        # Dosyayi PDF olarak degistir
        dosya="$pdf_gecici"

        # Satir araligi veya tumu/hepsi ise PDF'in tamamini bas
        if [[ -n "$satir_bas" || "$sayfa_araligi_modu" == "hayir" ]]; then
            # Satir araligi zaten kesildigi icin veya tumu/hepsi denildigi icin
            # PDF'in tum sayfalarini bas
            if [[ "$sayfa_araligi_modu" == "hayir" ]]; then
            local toplam_sayfa
            toplam_sayfa=$(python3 -c "
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
        else
            # sayfa:1-3 gibi acik sayfa araligi, aralik zaten dogru ayarli
            :
        fi
        
        # Gecici HTML dosyasini temizle
        rm -f "$html_gecici"
    fi

    # Sayfa sayisini hesapla (virgul ve aralik karisik olabilir)
    local sayfa_sayisi=0
    IFS=',' read -ra parcalar <<< "$aralik"
    for parca in "${parcalar[@]}"; do
        if [[ "$parca" == *-* ]]; then
            local bas
            bas=$(echo "$parca" | cut -d'-' -f1)
            local bit
            bit=$(echo "$parca" | cut -d'-' -f2)
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
    if ! pdfjam --nup 2x1 --landscape --outfile "$gecici" "$dosya" "$aralik" 2>/dev/null; then
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
    read -rp "Hazir olunca ENTER'a bas..."

    echo ""
    echo "ADIM 3: Arka yuzler yazdiriliyor (A4 sayfa: $arka_yuzler)..."
    lp -d HP-DeskJet-2540 -P "$arka_yuzler" -o fit-to-page -o ColorModel="$renk_modu" "$gecici"

    echo ""
    echo "Yazdirma tamamlandi! [$renk_adi]"
}

