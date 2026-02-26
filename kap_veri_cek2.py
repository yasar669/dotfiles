#!/usr/bin/env python3
"""KAP web sitesinden endeks ve pazar verilerini cek - v2."""
import requests
from bs4 import BeautifulSoup
import re

headers = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
}


def sayfa_indir(url: str) -> str:
    resp = requests.get(url, headers=headers, timeout=30)
    resp.raise_for_status()
    return resp.text


def endeks_parcala(html: str) -> dict[str, list[str]]:
    """HTML'den endeks adlari ve sembollerini cikar."""
    soup = BeautifulSoup(html, "html.parser")
    text = soup.get_text("\n", strip=True)

    # Endeks basliklarini bul: "BIST 100\n100 Şirket Bulundu" seklinde
    # veya "BIST SINAİ\n243 Şirket Bulundu"
    # Veya "YILDIZ PAZAR\n242 Şirket / Fon Bulundu"
    satirlar = text.split("\n")

    sonuc: dict[str, list[str]] = {}
    mevcut_endeks = None
    semboller: list[str] = []

    i = 0
    while i < len(satirlar):
        satir = satirlar[i].strip()

        # "X Şirket Bulundu" veya "X Şirket / Fon Bulundu" kontrolu
        m = re.match(r'^(\d+)\s+Şirket\s*(?:/\s*Fon\s*)?Bulundu$', satir)
        if m:
            # Bir onceki satir endeks adiydi
            if i > 0:
                if mevcut_endeks and semboller:
                    sonuc[mevcut_endeks] = sorted(set(semboller))
                mevcut_endeks = satirlar[i - 1].strip()
                semboller = []
            i += 1
            continue

        # Ticker sembol mu? (2-6 karakter, tamami buyuk harf + rakam, ilk harf)
        if mevcut_endeks and re.match(r'^[A-Z][A-Z0-9]{1,5}$', satir):
            # Sirket ismi parcasi olmamali
            if satir not in {'PAY', 'VE', 'FON'}:
                semboller.append(satir)

        i += 1

    # Son endeksi de ekle
    if mevcut_endeks and semboller:
        sonuc[mevcut_endeks] = sorted(set(semboller))

    return sonuc


# Ana program
print("Endeksler sayfasi indiriliyor...")
endeks_html = sayfa_indir("https://www.kap.org.tr/tr/Endeksler")

print("Pazarlar sayfasi indiriliyor...")
pazar_html = sayfa_indir("https://www.kap.org.tr/tr/Pazarlar")

print("\n=== ENDEKSLER ===")
endeksler = endeks_parcala(endeks_html)
for ad, sembol_listesi in endeksler.items():
    print(f"\n{ad} ({len(sembol_listesi)}):")
    print(", ".join(sembol_listesi))

print("\n\n=== PAZARLAR ===")
pazarlar = endeks_parcala(pazar_html)
for ad, sembol_listesi in pazarlar.items():
    print(f"\n{ad} ({len(sembol_listesi)}):")
    print(", ".join(sembol_listesi))
