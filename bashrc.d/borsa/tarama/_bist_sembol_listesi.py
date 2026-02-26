"""BIST hisse senedi sembol listesi cekim araci.

KAP (Kamuyu Aydinlatma Platformu) API'sinden BIST'te islem goren
tum hisse senetlerinin sembollerini ceker.

Kullanim:
    python3 _bist_sembol_listesi.py

Cikti:
    /tmp/borsa/_ohlcv/semboller.txt (satirda bir sembol, sirali)

Ayrica stdout'a sembol sayisini yazar.
"""

import json
import os
import sys

import requests

# KAP API endpointleri
_KAP_SIRKETLER_URL = "https://www.kap.org.tr/tr/bist-sirketler"
_KAP_API_URL = (
    "https://www.kap.org.tr/tr/api/index/member/"
    "BIST-TUM?includeRelatedIndexes=false"
)

# Cikti dosyasi
_CIKTI_DIZIN = "/tmp/borsa/_ohlcv"
_CIKTI_DOSYA = os.path.join(_CIKTI_DIZIN, "semboller.txt")

# Minimum beklenen sembol sayisi — bunun altindaysa uyari verilir
_MIN_SEMBOL = 700

# HTTP istek baslik bilgileri
_BASLIKLAR = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
    "Accept": "application/json",
}


def kap_api_ile_cek() -> list[str]:
    """KAP JSON API uzerinden sembol listesini ceker.

    Returns:
        Sirali sembol listesi.
    """
    try:
        yanit = requests.get(_KAP_API_URL, headers=_BASLIKLAR, timeout=30)
        yanit.raise_for_status()
        veri = yanit.json()
    except (requests.RequestException, json.JSONDecodeError) as hata:
        sys.stderr.write(f"HATA: KAP API erisim hatasi — {hata}\n")
        return []

    semboller: list[str] = []

    # KAP API yaniti yapisi: liste icerisinde sirket objeleri
    if isinstance(veri, list):
        for oge in veri:
            # memberCode veya instrumentCode alani sembol icin kullanilir
            sembol = None
            if isinstance(oge, dict):
                sembol = oge.get("memberCode") or oge.get("instrumentCode")
            if sembol and isinstance(sembol, str) and sembol.isalpha():
                semboller.append(sembol.upper())

    return sorted(set(semboller))


def kap_html_ile_cek() -> list[str]:
    """KAP HTML sayfasindan sembol listesini ceker (yedek yontem).

    KAP Next.js kullanir ve JSON verileri escaped formatta (\\")
    HTML icine gomulur. Bu nedenle hem normal hem escaped tirnak
    desenleri aranir.

    Returns:
        Sirali sembol listesi.
    """
    import re

    try:
        yanit = requests.get(_KAP_SIRKETLER_URL, headers=_BASLIKLAR, timeout=30)
        yanit.raise_for_status()
        icerik = yanit.text
    except requests.RequestException as hata:
        sys.stderr.write(f"HATA: KAP HTML erisim hatasi — {hata}\n")
        return []

    semboller: list[str] = []

    # KAP Next.js escaped JSON formati: stockCode\":\"THYAO\"
    escaped = re.findall(r'stockCode\\":\\"([A-Z0-9]+)', icerik)
    semboller.extend(escaped)

    # Normal JSON formati: "stockCode":"THYAO"
    normal = re.findall(r'"stockCode"\s*:\s*"([A-Z0-9]+)"', icerik)
    semboller.extend(normal)

    # memberCode alternatifi
    member_escaped = re.findall(r'memberCode\\":\\"([A-Z0-9]+)', icerik)
    semboller.extend(member_escaped)

    member_normal = re.findall(r'"memberCode"\s*:\s*"([A-Z0-9]+)"', icerik)
    semboller.extend(member_normal)

    return sorted(set(semboller))


def dosyaya_yaz(semboller: list[str]) -> str:
    """Sembol listesini dosyaya yazar.

    Args:
        semboller: Sirali sembol listesi.

    Returns:
        Yazilan dosya yolu.
    """
    os.makedirs(_CIKTI_DIZIN, exist_ok=True)
    with open(_CIKTI_DOSYA, "w", encoding="utf-8") as dosya:
        for sembol in semboller:
            dosya.write(f"{sembol}\n")
    return _CIKTI_DOSYA


def ana() -> None:
    """Ana giris noktasi."""
    sys.stderr.write("KAP'tan BIST sembol listesi cekiliyor...\n")

    # Oncelikle HTML'den cek (daha guvenilir — Next.js server-rendered data)
    semboller = kap_html_ile_cek()

    if len(semboller) < _MIN_SEMBOL:
        sys.stderr.write(
            f"HTML'den {len(semboller)} sembol geldi, JSON API deneniyor...\n"
        )
        semboller_api = kap_api_ile_cek()
        if len(semboller_api) > len(semboller):
            semboller = semboller_api

    if not semboller:
        sys.stderr.write("HATA: Hicbir kaynaktan sembol cekilemedi\n")
        sys.exit(1)

    dosya_yolu = dosyaya_yaz(semboller)

    if len(semboller) < _MIN_SEMBOL:
        sys.stderr.write(
            f"UYARI: Beklenen minimum {_MIN_SEMBOL}, "
            f"gelen {len(semboller)} sembol\n"
        )

    sys.stderr.write(f"{len(semboller)} sembol -> {dosya_yolu}\n")
    # stdout'a sembol sayisini yaz (bash tarafindan okunabilir)
    sys.stdout.write(f"{len(semboller)}\n")


if __name__ == "__main__":
    ana()
