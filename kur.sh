#!/usr/bin/env bash
# shellcheck shell=bash

# =============================================================================
# dotfiles - Otomatik Kurulum Betigi
# =============================================================================
# Kullanim:
#   bash kur.sh          # Normal kurulum
#   bash kur.sh -v       # Ayrintili cikti
#   bash kur.sh -e       # Tum teyitleri atla (evet-hepsine)
#
# Idempotent: Kac kez calisirsa calissin ayni sonucu uretir.
# Yumusak basarisizlik: Zorunlu olmayan adimlar basarisiz olursa devam eder.
# =============================================================================

set -euo pipefail

# --- Bayraklar ---
AYRINTILI=0
TEYITSIZ=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) AYRINTILI=1; shift ;;
        -e|--evet)    TEYITSIZ=1; shift ;;
        *)            echo "Bilinmeyen bayrak: $1"; exit 1 ;;
    esac
done

# --- Yardimci Fonksiyonlar ---
_bilgi() {
    echo "[BILGI] $*"
}

_ayrintili() {
    [[ $AYRINTILI -eq 1 ]] && echo "       $*"
}

_tamam() {
    echo "[TAMAM] $*"
}

_uyari() {
    echo "[UYARI] $*"
}

_hata() {
    echo "[HATA]  $*" >&2
}

# Ozet tablosu icin sonuclari topla
declare -a _OZET_SATIRLARI=()

_ozet_ekle() {
    _OZET_SATIRLARI+=("$1")
}

_teyit_al() {
    local soru="$1"
    if [[ $TEYITSIZ -eq 1 ]]; then
        return 0
    fi
    read -r -p "$soru [e/H] " cevap
    [[ "$cevap" =~ ^[eE]$ ]]
}

# =============================================================================
# ADIM 1: Sistem Bagimliliklari
# =============================================================================
_adim_bagimliliklar() {
    _bilgi "Sistem bagimliliklari kontrol ediliyor..."
    local hata=0

    # Zorunlu bagimliliklar
    local zorunlu
    for zorunlu in git curl; do
        if command -v "$zorunlu" &>/dev/null; then
            _ayrintili "$zorunlu: mevcut ($(command -v "$zorunlu"))"
        else
            _hata "'$zorunlu' bulunamadi. Kurun: sudo apt install $zorunlu"
            hata=1
        fi
    done

    if [[ $hata -eq 1 ]]; then
        _ozet_ekle "[HATA]  Sistem bagimliliklari (zorunlu araclari eksik)"
        return 1
    fi

    # Kosullu bagimliliklar
    local eksik_opsiyonel=""

    if command -v jq &>/dev/null; then
        _ayrintili "jq: mevcut"
    else
        eksik_opsiyonel="jq"
        _uyari "jq bulunamadi. Supabase islemleri icin gerekli: sudo apt install jq"
    fi

    if command -v docker &>/dev/null; then
        _ayrintili "docker: mevcut"
        if docker compose version &>/dev/null; then
            _ayrintili "docker compose: mevcut"
        else
            eksik_opsiyonel="${eksik_opsiyonel:+$eksik_opsiyonel, }docker-compose"
            _uyari "docker compose kulanilamiyor."
        fi
    else
        eksik_opsiyonel="${eksik_opsiyonel:+$eksik_opsiyonel, }docker"
        _uyari "Docker bulunamadi. Supabase kurulmayacak."
    fi

    if command -v python3 &>/dev/null; then
        local py_surum
        py_surum=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "?")
        _ayrintili "python3: mevcut (v$py_surum)"

        # 3.10+ kontrolu
        local ana_surum alt_surum
        ana_surum=$(echo "$py_surum" | cut -d. -f1)
        alt_surum=$(echo "$py_surum" | cut -d. -f2)
        if [[ "$ana_surum" -lt 3 ]] || { [[ "$ana_surum" -eq 3 ]] && [[ "$alt_surum" -lt 10 ]]; }; then
            _uyari "Python 3.10+ gerekli (mevcut: $py_surum). MCP sunucusu kurulmayacak."
        fi
    else
        eksik_opsiyonel="${eksik_opsiyonel:+$eksik_opsiyonel, }python3"
        _uyari "python3 bulunamadi. MCP sunucusu kurulmayacak."
    fi

    if [[ -n "$eksik_opsiyonel" ]]; then
        _ozet_ekle "[UYARI] Sistem bagimliliklari (eksik opsiyonel: $eksik_opsiyonel)"
    else
        _ozet_ekle "[TAMAM] Sistem bagimliliklari (git, curl, jq, docker, python3)"
    fi
    return 0
}

# =============================================================================
# ADIM 2: Dotfiles Dizin Baglantisi
# =============================================================================
_adim_dizin_baglantisi() {
    _bilgi "Dotfiles dizin baglantisi kontrol ediliyor..."

    local repo_dizin
    repo_dizin="$(cd "$(dirname "$0")" && pwd)"
    local hedef="$HOME/dotfiles"

    if [[ "$repo_dizin" == "$hedef" ]]; then
        _ayrintili "Repo zaten $hedef konumunda, baglanti gereksiz."
        _ozet_ekle "[TAMAM] Dotfiles baglantisi ($hedef)"
        return 0
    fi

    if [[ -L "$hedef" ]] && [[ "$(readlink -f "$hedef")" == "$repo_dizin" ]]; then
        _ayrintili "Symlink zaten dogru: $hedef -> $repo_dizin"
        _ozet_ekle "[TAMAM] Dotfiles baglantisi ($hedef -> $repo_dizin)"
        return 0
    fi

    if [[ -e "$hedef" ]]; then
        _uyari "$hedef zaten mevcut ve farkli bir hedefi gosteriyor."
        if ! _teyit_al "Mevcut $hedef yerine yeni symlink olusturulsun mu?"; then
            _ozet_ekle "[ATLANDI] Dotfiles baglantisi (kullanici reddetti)"
            return 0
        fi
    fi

    ln -sfn "$repo_dizin" "$hedef"
    _tamam "Symlink olusturuldu: $hedef -> $repo_dizin"
    _ozet_ekle "[TAMAM] Dotfiles baglantisi ($hedef -> $repo_dizin)"
}

# =============================================================================
# ADIM 3: Bashrc Yukleme
# =============================================================================
_adim_bashrc() {
    _bilgi "Bashrc kontrol ediliyor..."

    local repo_dizin
    repo_dizin="$(cd "$(dirname "$0")" && pwd)"

    if [[ ! -f "$repo_dizin/.bashrc" ]]; then
        _ayrintili "Repoda .bashrc bulunamadi, adim atlaniyor."
        _ozet_ekle "[ATLANDI] Bashrc (repoda .bashrc yok)"
        return 0
    fi

    if diff -q "$repo_dizin/.bashrc" "$HOME/.bashrc" &>/dev/null; then
        _ayrintili ".bashrc zaten guncel."
        _ozet_ekle "[TAMAM] Bashrc yuklendi (zaten guncel)"
        return 0
    fi

    if [[ -f "$HOME/.bashrc" ]]; then
        if ! _teyit_al "Mevcut .bashrc yedeklenip yenisi kopyalansın mi?"; then
            _ozet_ekle "[ATLANDI] Bashrc (kullanici reddetti)"
            return 0
        fi

        local yedek_ad
        yedek_ad="$HOME/.bashrc.yedek.$(date +%Y%m%d%H%M%S)"
        cp "$HOME/.bashrc" "$yedek_ad"
        _ayrintili "Yedek: $yedek_ad"
    fi

    cp "$repo_dizin/.bashrc" "$HOME/.bashrc"
    _tamam "Bashrc guncellendi."
    _ozet_ekle "[TAMAM] Bashrc yuklendi"
}

# =============================================================================
# ADIM 4: Python Ortami (MCP Sunucusu)
# =============================================================================
_adim_python() {
    _bilgi "Python ortami kontrol ediliyor..."

    local repo_dizin
    repo_dizin="$(cd "$(dirname "$0")" && pwd)"
    local mcp_dizin="$repo_dizin/bashrc.d/mcp_sunucular"

    if [[ ! -f "$mcp_dizin/pyproject.toml" ]]; then
        _ayrintili "pyproject.toml bulunamadi, adim atlaniyor."
        _ozet_ekle "[ATLANDI] Python ortami (pyproject.toml yok)"
        return 0
    fi

    if ! command -v python3 &>/dev/null; then
        _uyari "python3 bulunamadi. MCP sunucusu kurulmadi."
        _ozet_ekle "[UYARI] Python ortami (python3 yok)"
        return 0
    fi

    # Surum kontrolu (3.10+)
    local py_surum
    py_surum=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")
    local ana_surum alt_surum
    ana_surum=$(echo "$py_surum" | cut -d. -f1)
    alt_surum=$(echo "$py_surum" | cut -d. -f2)
    if [[ "$ana_surum" -lt 3 ]] || { [[ "$ana_surum" -eq 3 ]] && [[ "$alt_surum" -lt 10 ]]; }; then
        _uyari "Python 3.10+ gerekli (mevcut: $py_surum). MCP sunucusu kurulmadi."
        _ozet_ekle "[UYARI] Python ortami (Python $py_surum < 3.10)"
        return 0
    fi

    if [[ -d "$mcp_dizin/.venv" ]]; then
        _ayrintili ".venv zaten mevcut, pip guncelleme kontrol ediliyor..."
        "$mcp_dizin/.venv/bin/pip" install -q -e "$mcp_dizin" 2>/dev/null || true
        _ozet_ekle "[TAMAM] Python ortami (.venv zaten mevcut)"
        return 0
    fi

    _bilgi "Python sanal ortam olusturuluyor..."
    python3 -m venv "$mcp_dizin/.venv"
    "$mcp_dizin/.venv/bin/pip" install --upgrade pip -q 2>/dev/null || true
    if "$mcp_dizin/.venv/bin/pip" install -e "$mcp_dizin" -q 2>/dev/null; then
        _tamam "Python ortami olusturuldu: $mcp_dizin/.venv"
        _ozet_ekle "[TAMAM] Python ortami (.venv olusturuldu)"
    else
        _uyari "pip install basarisiz oldu."
        _ozet_ekle "[UYARI] Python ortami (pip install hatasi)"
    fi
}

# =============================================================================
# ADIM 5: Supabase Kurulumu
# =============================================================================
_adim_supabase() {
    _bilgi "Supabase kurulumu kontrol ediliyor..."

    local repo_dizin
    repo_dizin="$(cd "$(dirname "$0")" && pwd)"
    local vt_dizin="$repo_dizin/bashrc.d/borsa/veritabani"

    if [[ ! -f "$vt_dizin/docker-compose.yml" ]]; then
        _ayrintili "docker-compose.yml bulunamadi, adim atlaniyor."
        _ozet_ekle "[ATLANDI] Supabase (docker-compose.yml yok)"
        return 0
    fi

    if ! command -v docker &>/dev/null; then
        _uyari "Docker bulunamadi. Supabase kurulmadi."
        _ozet_ekle "[UYARI] Supabase kurulmadi (Docker yok)"
        return 0
    fi

    if ! docker compose version &>/dev/null 2>&1; then
        _uyari "docker compose kulanilamiyor. Supabase kurulmadi."
        _ozet_ekle "[UYARI] Supabase kurulmadi (docker compose yok)"
        return 0
    fi

    # 1. .env dosyasi olustur
    if [[ ! -f "$vt_dizin/.env" ]]; then
        if [[ -f "$vt_dizin/.env.ornek" ]]; then
            cp "$vt_dizin/.env.ornek" "$vt_dizin/.env"
            chmod 600 "$vt_dizin/.env"
            _ayrintili ".env dosyasi .env.ornek'ten kopyalandi."
        else
            _hata ".env.ornek bulunamadi. Supabase kurulamadi."
            _ozet_ekle "[HATA]  Supabase (.env.ornek yok)"
            return 1
        fi
    else
        _ayrintili ".env zaten mevcut."
    fi

    # 2. Container'lari baslat
    _bilgi "Supabase container'lari baslatiliyor..."
    local onceki_dizin
    onceki_dizin="$PWD"
    cd "$vt_dizin"

    if docker compose up -d 2>/dev/null; then
        _ayrintili "Container'lar baslatildi."
    else
        _uyari "docker compose up basarisiz oldu."
        cd "$onceki_dizin"
        _ozet_ekle "[UYARI] Supabase (docker compose up hatasi)"
        return 0
    fi

    # 3. PostgreSQL hazir olmasini bekle (max 60 saniye)
    _bilgi "PostgreSQL'in hazir olması bekleniyor..."
    local i
    for i in $(seq 1 60); do
        if docker compose exec -T db pg_isready -q 2>/dev/null; then
            _ayrintili "PostgreSQL hazir ($i saniye)."
            break
        fi
        if [[ $i -eq 60 ]]; then
            _uyari "PostgreSQL 60 saniye icinde hazir olmadi."
        fi
        sleep 1
    done

    # 4. Tablolari olustur
    if [[ -f "$vt_dizin/sema.sql" ]]; then
        _bilgi "Veritabani seması uygulaniyor..."
        if docker compose exec -T db psql -U postgres -d postgres \
            -f /docker-entrypoint-initdb.d/99-sema.sql 2>/dev/null; then
            _ayrintili "Tablolar olusturuldu (docker exec)."
        elif command -v psql &>/dev/null && \
            psql -h localhost -p 5433 -U postgres -d postgres \
            -f "$vt_dizin/sema.sql" 2>/dev/null; then
            _ayrintili "Tablolar olusturuldu (dogrudan psql)."
        else
            _uyari "Tablolar olusturulamadi. Elle calistirin: psql -f sema.sql"
        fi
    fi

    # 5. supabase.ayarlar.sh dosyasini olustur
    if [[ ! -f "$vt_dizin/supabase.ayarlar.sh" ]]; then
        local anon_key
        anon_key=$(grep "^ANON_KEY=" "$vt_dizin/.env" | cut -d= -f2)
        if [[ -n "$anon_key" ]]; then
            cat > "$vt_dizin/supabase.ayarlar.sh" << EOF
# shellcheck shell=bash
# Supabase baglanti ayarlari - otomatik uretildi (kur.sh)
# Bu dosya git'e GIRMEZ (.gitignore: *.ayarlar.sh)
_SUPABASE_URL="http://localhost:8001"
_SUPABASE_ANAHTAR="$anon_key"
EOF
            chmod 600 "$vt_dizin/supabase.ayarlar.sh"
            _ayrintili "supabase.ayarlar.sh olusturuldu."
        else
            _uyari "ANON_KEY .env dosyasindan okunamadi."
        fi
    else
        _ayrintili "supabase.ayarlar.sh zaten mevcut."
    fi

    cd "$onceki_dizin"
    _tamam "Supabase kurulumu tamamlandi."
    _ozet_ekle "[TAMAM] Supabase kurulumu"
}

# =============================================================================
# ADIM 6: Hassas Dosya Izinleri
# =============================================================================
_adim_izinler() {
    _bilgi "Dosya izinleri ayarlaniyor..."

    local repo_dizin
    repo_dizin="$(cd "$(dirname "$0")" && pwd)"

    local hassas_dosyalar=(
        "$repo_dizin/bashrc.d/borsa/veritabani/.env"
        "$repo_dizin/bashrc.d/borsa/veritabani/supabase.ayarlar.sh"
        "$repo_dizin/bashrc.d/borsa/adaptorler/ziraat.ayarlar.sh"
    )

    local dosya
    local ayarlanan=0
    for dosya in "${hassas_dosyalar[@]}"; do
        if [[ -f "$dosya" ]]; then
            chmod 600 "$dosya"
            _ayrintili "chmod 600: $dosya"
            ayarlanan=$((ayarlanan + 1))
        fi
    done

    _tamam "Dosya izinleri ayarlandi ($ayarlanan dosya)."
    _ozet_ekle "[TAMAM] Dosya izinleri ayarlandi ($ayarlanan dosya)"
}

# =============================================================================
# ADIM 7: Gitignore Kontrolu
# =============================================================================
_adim_gitignore() {
    _bilgi "Gitignore kontrol ediliyor..."

    local repo_dizin
    repo_dizin="$(cd "$(dirname "$0")" && pwd)"
    local gitignore="$repo_dizin/.gitignore"

    local gerekli_satirlar=(
        ".env"
        "*.ayarlar.sh"
        ".venv/"
        "__pycache__/"
    )

    # .gitignore yoksa olustur
    if [[ ! -f "$gitignore" ]]; then
        printf '%s\n' "${gerekli_satirlar[@]}" > "$gitignore"
        _tamam ".gitignore olusturuldu."
        _ozet_ekle "[TAMAM] Gitignore olusturuldu"
        return 0
    fi

    local eklenen=0
    local satir
    for satir in "${gerekli_satirlar[@]}"; do
        if ! grep -qxF "$satir" "$gitignore"; then
            echo "$satir" >> "$gitignore"
            _ayrintili "Eklendi: $satir"
            eklenen=$((eklenen + 1))
        fi
    done

    if [[ $eklenen -gt 0 ]]; then
        _tamam "Gitignore guncellendi ($eklenen satir eklendi)."
        _ozet_ekle "[TAMAM] Gitignore guncellendi ($eklenen satir eklendi)"
    else
        _ayrintili "Gitignore zaten guncel."
        _ozet_ekle "[TAMAM] Gitignore (zaten guncel)"
    fi
}

# =============================================================================
# ANA AKIS
# =============================================================================
ana_akis() {
    echo ""
    echo "=== dotfiles Kurulum Betigi ==="
    echo ""

    # Zorunlu adimlar (basarisiz olursa dur)
    _adim_bagimliliklar || {
        _hata "Zorunlu bagimliliklar eksik. Kurulum durduruldu."
        exit 1
    }

    # Opsiyonel adimlar (basarisiz olursa devam et)
    _adim_dizin_baglantisi || true
    _adim_bashrc || true
    _adim_python || true
    _adim_supabase || true
    _adim_izinler || true
    _adim_gitignore || true

    # Ozet tablosu
    echo ""
    echo "=== Kurulum Ozeti ==="
    local satir
    for satir in "${_OZET_SATIRLARI[@]}"; do
        echo "  $satir"
    done
    echo ""
    echo "Kurulum tamamlandi. Degisiklikleri uygulamak icin:"
    echo "  source ~/.bashrc"
    echo ""
}

ana_akis
