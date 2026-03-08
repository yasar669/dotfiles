# shellcheck shell=bash

# Tarama Katmani - Canli Veri Yonetimi
# tvDatafeed canli fiyat daemon'unu yonetir ve fiyat sorgulama saglar.
# Eski fiyat_kaynagi.sh ve ohlcv.sh canli_veri_* fonksiyonlarinin yerine gecer.
#
# Fonksiyonlar:
#   canli_veri_baslat      -> tvDatafeed canli daemon'unu baslatir
#   canli_veri_durdur      -> daemon'u durdurur
#   canli_veri_durum       -> baglanti durumu, acik semboller, son fiyatlar
#   canli_veri_sembol_ekle -> daemon'a sembol ekler
#   canli_veri_sembol_cikar-> daemon'dan sembol cikarir
#   canli_fiyat_al         -> JSON dosyasindan fiyat okur
#   canli_veri_seans_bekle -> seans otomasyonu
#
# Yuklenme: cekirdek.sh tarafindan source edilir.

# =======================================================
# YAPILANDIRMA
# =======================================================

_CANLI_DIZIN="/tmp/borsa/_canli"
_CANLI_PID_DOSYASI="/tmp/borsa/_canli/daemon.pid"
_CANLI_DURUM_DOSYASI="/tmp/borsa/_canli/daemon.durum"
_CANLI_LOG_DOSYASI="/tmp/borsa/_canli/daemon.log"
_CANLI_SEMBOL_DOSYASI="/tmp/borsa/_canli/semboller.txt"
_CANLI_SEANS_PID="/tmp/borsa/_canli/seans_bekleyici.pid"

_CANLI_DAEMON_SCRIPT="${BORSA_KLASORU}/tarama/_tvdatafeed_canli.py"

# =======================================================
# BOLUM 1: DAEMON YONETIMI
# =======================================================

# -------------------------------------------------------
# _canli_daemon_aktif_mi (dahili)
# Canli veri daemon'unun calisip calismadigini kontrol eder.
# Donus: 0 = calisiyor, 1 = durmus
# -------------------------------------------------------
_canli_daemon_aktif_mi() {
    if [[ -f "$_CANLI_PID_DOSYASI" ]]; then
        local pid
        pid=$(cat "$_CANLI_PID_DOSYASI" 2>/dev/null)
        [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && return 0
    fi
    return 1
}

# -------------------------------------------------------
# canli_veri_baslat
# tvDatafeed canli daemon'unu baslatir.
# Takip listesindeki sembolleri otomatik ekler.
# -------------------------------------------------------
canli_veri_baslat() {
    # Zaten calisiyor mu?
    if _canli_daemon_aktif_mi; then
        local pid
        pid=$(cat "$_CANLI_PID_DOSYASI" 2>/dev/null)
        echo "Canli veri daemon'u zaten calisiyor (PID: $pid)"
        return 0
    fi

    # Python kontrolu
    _ohlcv_python_bul || {
        echo "HATA: Python bulunamadi" >&2
        return 1
    }
    local python_yol="$_OHLCV_PYTHON"

    # Daemon script kontrolu
    if [[ ! -f "$_CANLI_DAEMON_SCRIPT" ]]; then
        echo "HATA: $_CANLI_DAEMON_SCRIPT dosyasi bulunamadi" >&2
        return 1
    fi

    # Sembol listesini hazirla
    local semboller=""
    semboller=$(_takip_semboller 2>/dev/null)
    if [[ -z "$semboller" ]]; then
        echo "UYARI: Takip listesi bos. Once sembol ekleyin: takip_ekle THYAO 1G"
        return 1
    fi

    # Dizinleri hazirla
    mkdir -p "$_CANLI_DIZIN" 2>/dev/null

    # Sembol dosyasini yaz (daemon bu dosyayi izler)
    echo "$semboller" > "$_CANLI_SEMBOL_DOSYASI"

    local sembol_sayisi
    sembol_sayisi=$(echo "$semboller" | wc -l)

    # TV giris bilgilerini veritabanindan yukle (ortam degiskeni yoksa)
    _canli_veri_tv_bilgi_yukle

    # Arka planda daemon baslat
    nohup "$python_yol" "$_CANLI_DAEMON_SCRIPT" \
        --daemon --dosya "$_CANLI_SEMBOL_DOSYASI" \
        >> "$_CANLI_LOG_DOSYASI" 2>&1 &
    disown

    # Daemon'un baslamasini bekle (maks 5 saniye)
    local bekle=0
    while [[ "$bekle" -lt 5 ]]; do
        sleep 1
        if _canli_daemon_aktif_mi; then
            local pid
            pid=$(cat "$_CANLI_PID_DOSYASI" 2>/dev/null)
            echo "Canli veri daemon baslatildi"
            echo "  PID:     $pid"
            echo "  Sembol:  $sembol_sayisi adet"
            echo "  Kaynak:  tvDatafeed (TradingView WebSocket)"
            echo "  Log:     $_CANLI_LOG_DOSYASI"
            return 0
        fi
        bekle=$((bekle + 1))
    done

    echo "UYARI: Daemon baslatildi ama henuz PID dosyasi yazmamis olabilir"
    echo "Durum icin: canli_veri_durum"
    return 0
}

# -------------------------------------------------------
# canli_veri_durdur
# Daemon'u durdurur.
# -------------------------------------------------------
canli_veri_durdur() {
    # Seans bekleyici varsa onu da durdur
    if [[ -f "$_CANLI_SEANS_PID" ]]; then
        local seans_pid
        seans_pid=$(cat "$_CANLI_SEANS_PID" 2>/dev/null)
        rm -f "$_CANLI_SEANS_PID"
        if [[ -n "$seans_pid" ]] && kill -0 "$seans_pid" 2>/dev/null; then
            kill "$seans_pid" 2>/dev/null
        fi
    fi

    if ! _canli_daemon_aktif_mi; then
        echo "Canli veri daemon'u zaten durmus"
        return 0
    fi

    local pid
    pid=$(cat "$_CANLI_PID_DOSYASI" 2>/dev/null)
    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null
        echo "Canli veri daemon durduruluyor (PID: $pid)..."

        # Kapanmasini bekle (maks 10 saniye)
        local bekle=0
        while kill -0 "$pid" 2>/dev/null && [[ "$bekle" -lt 10 ]]; do
            sleep 1
            bekle=$((bekle + 1))
        done

        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
            echo "UYARI: Zorunlu durdurma (SIGKILL)"
        else
            echo "Canli veri daemon durduruldu"
        fi
    fi

    rm -f "$_CANLI_PID_DOSYASI"
    return 0
}

# -------------------------------------------------------
# canli_veri_durum
# Daemon durumunu ve fiyat istatistiklerini gosterir.
# -------------------------------------------------------
canli_veri_durum() {
    echo "=== Canli Veri Durumu ==="
    echo ""

    # Seans durumu
    if bist_seans_acik_mi 2>/dev/null; then
        echo "Seans: ACIK"
    else
        echo "Seans: KAPALI"
    fi
    echo ""

    # TradingView giris durumu
    if [[ -n "${TV_KULLANICI:-}" ]]; then
        echo "TradingView: Giris yapilmis (kullanici: $TV_KULLANICI)"
    else
        # Veritabanindan kontrol
        local db_kullanici=""
        if declare -f vt_ayar_oku > /dev/null 2>&1; then
            db_kullanici=$(vt_ayar_oku "TV_KULLANICI" 2>/dev/null)
        fi
        if [[ -n "$db_kullanici" ]]; then
            echo "TradingView: Giris bilgileri kayitli (kullanici: $db_kullanici)"
        else
            echo "TradingView: Giris yapilmamis (gecikmeli veri modu)"
            echo "  Gercek zamanli veri icin: borsa veri giris <kullanici> <sifre>"
        fi
    fi
    echo ""

    # Daemon durumu
    if _canli_daemon_aktif_mi; then
        local pid
        pid=$(cat "$_CANLI_PID_DOSYASI" 2>/dev/null)
        echo "Daemon: AKTIF (PID: $pid)"
        echo "Kaynak: tvDatafeed (TradingView WebSocket)"
    else
        echo "Daemon: DURMUS"
        echo ""
        echo "Baslatmak icin: borsa veri baslat"
        return 0
    fi
    echo ""

    # Durum dosyasindan detaylar
    if [[ -f "$_CANLI_DURUM_DOSYASI" ]]; then
        local durum_metni sembol_sayisi mesaj_sayisi guncelleme
        durum_metni=$(grep -oP '"durum"\s*:\s*"\K[^"]+' "$_CANLI_DURUM_DOSYASI" 2>/dev/null | head -1)
        sembol_sayisi=$(grep -oP '"sembol_sayisi"\s*:\s*\K[0-9]+' "$_CANLI_DURUM_DOSYASI" 2>/dev/null | head -1)
        mesaj_sayisi=$(grep -oP '"mesaj_sayaci"\s*:\s*\K[0-9]+' "$_CANLI_DURUM_DOSYASI" 2>/dev/null | head -1)
        guncelleme=$(grep -oP '"guncelleme"\s*:\s*"\K[^"]+' "$_CANLI_DURUM_DOSYASI" 2>/dev/null | head -1)

        [[ -n "$durum_metni" ]] && echo "Baglanti: $durum_metni"
        [[ -n "$sembol_sayisi" ]] && echo "Sembol: $sembol_sayisi adet"
        [[ -n "$mesaj_sayisi" ]] && echo "Islenen mesaj: $mesaj_sayisi"
        [[ -n "$guncelleme" ]] && echo "Son guncelleme: $guncelleme"
    fi
    echo ""

    # Fiyat dosyalari istatistigi
    if [[ -d "$_CANLI_DIZIN" ]]; then
        local dosya_sayisi
        dosya_sayisi=$(find "$_CANLI_DIZIN" -name "*.json" -not -name "daemon.*" \
            -not -name ".*" 2>/dev/null | wc -l)
        echo "Fiyat dosyasi: $dosya_sayisi adet"

        # Son 2 dakikada guncellenen dosyalar
        local aktif_sayisi
        aktif_sayisi=$(find "$_CANLI_DIZIN" -name "*.json" -not -name "daemon.*" \
            -not -name ".*" -mmin -2 2>/dev/null | wc -l)
        echo "Son 2dk aktif: $aktif_sayisi adet"
    fi
    echo ""

    # Seans bekleyici
    if [[ -f "$_CANLI_SEANS_PID" ]]; then
        local seans_pid
        seans_pid=$(cat "$_CANLI_SEANS_PID" 2>/dev/null)
        if [[ -n "$seans_pid" ]] && kill -0 "$seans_pid" 2>/dev/null; then
            echo "Seans bekleyici: AKTIF (PID: $seans_pid)"
        fi
    fi

    return 0
}

# =======================================================
# BOLUM 2: TRADINGVIEW GIRIS YONETIMI
# =======================================================

# -------------------------------------------------------
# canli_veri_giris <kullanici> <sifre>
# TradingView hesap bilgilerini veritabanina kaydeder.
# Gercek zamanli veri icin gereklidir (opsiyonel).
# Giris bilgileri olmadan daemon gecikmeli veri alir.
# -------------------------------------------------------
canli_veri_giris() {
    local kullanici="$1"
    local sifre="$2"

    if [[ -z "$kullanici" ]] || [[ -z "$sifre" ]]; then
        echo "Kullanim: canli_veri_giris <tv_kullanici_adi> <tv_sifre>"
        return 1
    fi

    # Veritabanina kaydet
    if declare -f vt_ayar_kaydet > /dev/null 2>&1; then
        vt_ayar_kaydet "TV_KULLANICI" "$kullanici" "TradingView kullanici adi" || {
            echo "UYARI: Veritabanina yazilamadi — ortam degiskeni olarak ayarlaniyor"
        }
        vt_ayar_kaydet "TV_SIFRE" "$sifre" "TradingView sifresi" || true
    else
        echo "UYARI: Veritabani baglantisi yok — ortam degiskeni olarak ayarlaniyor"
    fi

    # Ortam degiskenlerini de ayarla (mevcut oturum icin)
    export TV_KULLANICI="$kullanici"
    export TV_SIFRE="$sifre"

    echo "TradingView giris bilgileri kaydedildi"
    echo "  Kullanici: $kullanici"
    echo ""

    # Daemon calissiyorsa yeniden baslat (yeni token ile)
    if _canli_daemon_aktif_mi; then
        echo "Daemon yeniden baslatiliyor (yeni giris bilgileriyle)..."
        canli_veri_durdur > /dev/null 2>&1
        sleep 1
        canli_veri_baslat
    else
        echo "Daemon baslatmak icin: borsa veri baslat"
    fi

    return 0
}

# -------------------------------------------------------
# canli_veri_cikis
# TradingView hesap bilgilerini veritabanindan siler.
# Daemon gecikmeli veri moduna doner.
# -------------------------------------------------------
canli_veri_cikis() {
    # Veritabanindan sil
    if declare -f vt_ayar_sil > /dev/null 2>&1; then
        vt_ayar_sil "TV_KULLANICI" || true
        vt_ayar_sil "TV_SIFRE" || true
    fi

    # Ortam degiskenlerini temizle
    unset TV_KULLANICI
    unset TV_SIFRE

    echo "TradingView giris bilgileri silindi"
    echo "Daemon gecikmeli veri moduna donecek."

    # Daemon calissiyorsa yeniden baslat
    if _canli_daemon_aktif_mi; then
        echo "Daemon yeniden baslatiliyor..."
        canli_veri_durdur > /dev/null 2>&1
        sleep 1
        canli_veri_baslat
    fi

    return 0
}

# -------------------------------------------------------
# _canli_veri_tv_bilgi_yukle (dahili)
# Veritabanindan TV giris bilgilerini ortam degiskenine yukler.
# canli_veri_baslat tarafindan cagrilir.
# -------------------------------------------------------
_canli_veri_tv_bilgi_yukle() {
    # Ortam degiskeni zaten ayarliysa atla
    if [[ -n "${TV_KULLANICI:-}" ]] && [[ -n "${TV_SIFRE:-}" ]]; then
        return 0
    fi

    # Veritabanindan oku
    if declare -f vt_ayar_oku > /dev/null 2>&1; then
        local db_kullanici db_sifre
        db_kullanici=$(vt_ayar_oku "TV_KULLANICI" 2>/dev/null)
        db_sifre=$(vt_ayar_oku "TV_SIFRE" 2>/dev/null)

        if [[ -n "$db_kullanici" ]] && [[ -n "$db_sifre" ]]; then
            export TV_KULLANICI="$db_kullanici"
            export TV_SIFRE="$db_sifre"
        fi
    fi
}

# =======================================================
# BOLUM 3: SEMBOL YONETIMI
# =======================================================

# -------------------------------------------------------
# canli_veri_sembol_ekle <sembol>
# Aktif daemon'a yeni sembol ekler.
# -------------------------------------------------------
canli_veri_sembol_ekle() {
    local sembol="${1^^}"
    if [[ -z "$sembol" ]]; then
        echo "Kullanim: canli_veri_sembol_ekle <SEMBOL>"
        return 1
    fi

    if ! _canli_daemon_aktif_mi; then
        echo "HATA: Canli veri daemon'u aktif degil"
        return 1
    fi

    # Sembol dosyasina ekle (tekrar kontrolu)
    if grep -qx "$sembol" "$_CANLI_SEMBOL_DOSYASI" 2>/dev/null; then
        echo "'$sembol' zaten canli izlemede"
        return 0
    fi
    echo "$sembol" >> "$_CANLI_SEMBOL_DOSYASI"

    # SIGUSR1 ile daemon'a bildir
    local pid
    pid=$(cat "$_CANLI_PID_DOSYASI" 2>/dev/null)
    if [[ -n "$pid" ]]; then
        kill -USR1 "$pid" 2>/dev/null
        echo "'$sembol' canli izlemeye eklendi"
    fi
    return 0
}

# -------------------------------------------------------
# canli_veri_sembol_cikar <sembol>
# Aktif daemon'dan sembol cikarir.
# -------------------------------------------------------
canli_veri_sembol_cikar() {
    local sembol="${1^^}"
    if [[ -z "$sembol" ]]; then
        echo "Kullanim: canli_veri_sembol_cikar <SEMBOL>"
        return 1
    fi

    if ! _canli_daemon_aktif_mi; then
        echo "HATA: Canli veri daemon'u aktif degil"
        return 1
    fi

    if ! grep -qx "$sembol" "$_CANLI_SEMBOL_DOSYASI" 2>/dev/null; then
        echo "'$sembol' canli izlemede degil"
        return 0
    fi

    # Sembol dosyasindan cikar
    local gecici
    gecici=$(mktemp)
    grep -vx "$sembol" "$_CANLI_SEMBOL_DOSYASI" > "$gecici"
    mv "$gecici" "$_CANLI_SEMBOL_DOSYASI"

    # SIGUSR1 ile daemon'a bildir
    local pid
    pid=$(cat "$_CANLI_PID_DOSYASI" 2>/dev/null)
    if [[ -n "$pid" ]]; then
        kill -USR1 "$pid" 2>/dev/null
        echo "'$sembol' canli izlemeden cikarildi"
    fi
    return 0
}

# =======================================================
# BOLUM 3: FIYAT SORGULAMA
# =======================================================

# -------------------------------------------------------
# canli_fiyat_al <sembol>
# Canli fiyat verisini JSON dosyasindan okur.
# Eski fiyat_kaynagi_fiyat_al() fonksiyonunun yerine gecer.
#
# stdout: fiyat|tavan|taban|degisim|hacim|seans
#   Robot motoru ve diger moduller bu formati bekler.
#
# Donus: 0 = basarili, 1 = basarisiz
# -------------------------------------------------------
canli_fiyat_al() {
    local sembol="${1^^}"
    if [[ -z "$sembol" ]]; then
        return 1
    fi

    local dosya="${_CANLI_DIZIN}/${sembol}.json"
    if [[ ! -f "$dosya" ]]; then
        return 1
    fi

    # Dosya yasini kontrol et (60 saniyeden eski ise gecersiz say)
    local dosya_zamani
    dosya_zamani=$(stat -c %Y "$dosya" 2>/dev/null) || return 1
    local simdi
    simdi=$(date +%s)
    local gecen=$(( simdi - dosya_zamani ))
    if [[ "$gecen" -gt 60 ]]; then
        return 1
    fi

    # JSON'dan alanlari oku
    local icerik
    icerik=$(cat "$dosya" 2>/dev/null) || return 1
    [[ -z "$icerik" ]] && return 1

    local fiyat degisim hacim onceki_kapanis

    if command -v jq > /dev/null 2>&1; then
        fiyat=$(echo "$icerik" | jq -r '.fiyat // 0')
        degisim=$(echo "$icerik" | jq -r '.degisim // 0')
        hacim=$(echo "$icerik" | jq -r '.hacim // 0')
        onceki_kapanis=$(echo "$icerik" | jq -r '.onceki_kapanis // 0')
    else
        # jq yoksa grep ile ayristir
        fiyat=$(echo "$icerik" | grep -oP '"fiyat"\s*:\s*\K[0-9.]+' | head -1)
        degisim=$(echo "$icerik" | grep -oP '"degisim"\s*:\s*\K-?[0-9.]+' | head -1)
        hacim=$(echo "$icerik" | grep -oP '"hacim"\s*:\s*\K[0-9]+' | head -1)
        onceki_kapanis=$(echo "$icerik" | grep -oP '"onceki_kapanis"\s*:\s*\K[0-9.]+' | head -1)
    fi

    [[ -z "$fiyat" ]] || [[ "$fiyat" == "0" ]] && return 1

    # Tavan/taban hesapla (onceki kapanis +/- %10)
    local tavan="0"
    local taban="0"
    if [[ -n "$onceki_kapanis" ]] && [[ "$onceki_kapanis" != "0" ]]; then
        # bc mevcutsa hassas hesaplama yap
        if command -v bc > /dev/null 2>&1; then
            tavan=$(echo "$onceki_kapanis * 1.10" | bc -l | xargs printf "%.2f")
            taban=$(echo "$onceki_kapanis * 0.90" | bc -l | xargs printf "%.2f")
        else
            # Tam sayi yaklasimi (bc yoksa)
            local onceki_int="${onceki_kapanis%%.*}"
            tavan=$(( onceki_int * 110 / 100 ))
            taban=$(( onceki_int * 90 / 100 ))
        fi
    fi

    # Seans durumunu belirle
    local seans="KAPALI"
    if bist_seans_acik_mi 2>/dev/null; then
        seans="ACIK"
    fi

    # Geriye uyumlu cikti: fiyat|tavan|taban|degisim|hacim|seans
    echo "${fiyat}|${tavan}|${taban}|${degisim:-0}|${hacim:-0}|${seans}"
    return 0
}

# =======================================================
# BOLUM 4: SEANS OTOMASYONU
# =======================================================

# -------------------------------------------------------
# canli_veri_seans_bekle
# Seansi bekleyip otomatik baslatir/durdurur.
# Sabah seans acilinca daemon baslatir,
# aksam kapaninca durdurur.
# -------------------------------------------------------
canli_veri_seans_bekle() {
    # Zaten calisiyor mu?
    if [[ -f "$_CANLI_SEANS_PID" ]]; then
        local eski_pid
        eski_pid=$(cat "$_CANLI_SEANS_PID" 2>/dev/null)
        if [[ -n "$eski_pid" ]] && kill -0 "$eski_pid" 2>/dev/null; then
            echo "Seans bekleyici zaten aktif (PID: $eski_pid)"
            return 0
        fi
    fi

    # Takip listesi kontrol
    local semboller
    semboller=$(_takip_semboller 2>/dev/null)
    if [[ -z "$semboller" ]]; then
        echo "UYARI: Takip listesi bos. Once sembol ekleyin."
        return 1
    fi

    # Arka planda seans bekleyici baslat
    _canli_veri_seans_dongusu &
    disown
    echo "Seans bekleyici baslatildi"
    echo "  Seans acilinca daemon otomatik baslar"
    echo "  Seans kapaninca daemon otomatik durur"
    return 0
}

# -------------------------------------------------------
# canli_veri_seans_durdur
# Seans bekleyiciyi durdurur.
# -------------------------------------------------------
canli_veri_seans_durdur() {
    if [[ ! -f "$_CANLI_SEANS_PID" ]]; then
        echo "Seans bekleyici aktif degil"
        return 0
    fi

    local pid
    pid=$(cat "$_CANLI_SEANS_PID" 2>/dev/null)
    rm -f "$_CANLI_SEANS_PID"

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        echo "Seans bekleyici durduruldu (PID: $pid)"
    else
        echo "Seans bekleyici zaten durmus"
    fi

    # Daemon'u da durdur
    canli_veri_durdur
    return 0
}

# -------------------------------------------------------
# _canli_veri_seans_dongusu (dahili)
# Seans acik/kapali durumuna gore daemon yonetir.
# 30 saniyede bir kontrol eder.
# -------------------------------------------------------
_canli_veri_seans_dongusu() {
    local pid_dosya="$_CANLI_SEANS_PID"
    mkdir -p "$(dirname "$pid_dosya")" 2>/dev/null
    echo $$ > "$pid_dosya"

    _cekirdek_log "Seans bekleyici dongusu basladi (PID: $$)"

    local daemon_baslatildi=0

    while true; do
        # PID dosyasi silinmisse cik
        [[ ! -f "$pid_dosya" ]] && break

        if bist_seans_acik_mi 2>/dev/null; then
            # Seans acik — daemon baslatilmamissa baslat
            if [[ "$daemon_baslatildi" -eq 0 ]]; then
                _cekirdek_log "Seans acildi — canli veri daemon baslatiliyor"
                canli_veri_baslat > /dev/null 2>&1 || true
                daemon_baslatildi=1
            fi
        else
            # Seans kapali — daemon aciksa durdur
            if [[ "$daemon_baslatildi" -eq 1 ]]; then
                _cekirdek_log "Seans kapandi — canli veri daemon durduruluyor"
                canli_veri_durdur > /dev/null 2>&1 || true
                daemon_baslatildi=0
            fi
        fi

        sleep 30
    done

    # Cikista daemon'u durdur
    if [[ "$daemon_baslatildi" -eq 1 ]]; then
        canli_veri_durdur > /dev/null 2>&1 || true
    fi

    _cekirdek_log "Seans bekleyici dongusu durdu (PID: $$)"
}
