#!/usr/bin/env python3
"""KAP web sitesinden endeks ve pazar verilerini cek."""
import requests
from bs4 import BeautifulSoup
import re
import json

headers = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}


def endeks_verisi_cek(url: str) -> dict[str, list[str]]:
    """Verilen URL'den endeks/pazar verilerini cek."""
    resp = requests.get(url, headers=headers, timeout=30)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")

    sonuc: dict[str, list[str]] = {}
    mevcut_endeks = None
    semboller: list[str] = []

    # Tum tablodan text satirlarini al
    for row in soup.find_all("div", class_="comp-cell"):
        text = row.get_text(strip=True)
        # Endeks basligi: "BIST 100 100 Sirket Bulundu" gibi
        m = re.match(r"^(.+?)\s*\d+\s*Şirket\s*/?\s*(?:Fon\s*)?Bulundu$", text)
        if m:
            if mevcut_endeks and semboller:
                sonuc[mevcut_endeks] = sorted(set(semboller))
            mevcut_endeks = m.group(1).strip()
            semboller = []
            continue

    # Son endeksi de ekle
    if mevcut_endeks and semboller:
        sonuc[mevcut_endeks] = sorted(set(semboller))

    return sonuc


def endeks_verisi_cek_v2(url: str) -> dict[str, list[str]]:
    """HTML yapisini kullanarak endeks verilerini cek (v2)."""
    resp = requests.get(url, headers=headers, timeout=30)
    resp.raise_for_status()
    html = resp.text

    sonuc: dict[str, list[str]] = {}

    # comp-cell--sembol class'i sembol hucreleri, comp-cell-row-div class'i endeks basliklari
    # Regex ile dogrudan HTML'den cekelim
    # Endeks basliklari genelde: <div ...>BIST 100</div><div ...>100 Şirket Bulundu</div>
    # Semboller genelde: sub-comp class icinde <div class="comp-cell _14...">TICKER</div>

    # Daha low-level yaklasim: tum text satirlarini topla
    soup = BeautifulSoup(html, "html.parser")

    # Tum w-clearfix row div'lerini bul
    rows = soup.select("div.w-clearfix.w-clearfix-row")
    if not rows:
        # Alternatif: tum div'leri tara
        pass

    # Daha pragmatik yaklasim: HTML'den regex ile cek
    # Endeks basliklari: X Şirket Bulundu veya X Şirket / Fon Bulundu
    baslik_pattern = re.compile(
        r'<div[^>]*>([^<]+?)</div>\s*<div[^>]*>\s*(\d+)\s*Şirket\s*(?:/\s*Fon\s*)?Bulundu\s*</div>'
    )
    # Sembol pattern: kisa, buyuk harf/rakam ticker kodlari
    sembol_pattern = re.compile(r'<div[^>]*class="[^"]*comp-cell[^"]*"[^>]*>\s*(\d+)\s*</div>\s*<div[^>]*class="[^"]*comp-cell[^"]*"[^>]*>\s*([A-Z0-9]{2,10})\s*</div>')

    basliklari = list(baslik_pattern.finditer(html))
    print(f"Bulunan endeks sayisi: {len(basliklari)}")

    for i, m in enumerate(basliklari):
        endeks_adi = m.group(1).strip()
        beklenen_sayi = int(m.group(2))
        baslangic = m.end()
        bitis = basliklari[i + 1].start() if i + 1 < len(basliklari) else len(html)
        bolge = html[baslangic:bitis]

        semboller = re.findall(r'<div[^>]*>\s*([A-Z][A-Z0-9]{1,9})\s*</div>', bolge)
        # Filtreleme: kisa kodlar (2-6 karakter genelde)
        # Ayrica sirket isim parcalarini filtreye al
        ticker_adaylari = []
        for s in semboller:
            # Ticker'lar genelde 2-6 karakter, tamami buyuk harf+rakam
            if 2 <= len(s) <= 6 and re.match(r'^[A-Z][A-Z0-9]+$', s):
                # Turkce kelimeler olmamali
                turkce_kelimeler = {'VE', 'SANAYİ', 'TİCARET', 'HOLDİNG', 'YATIRIM', 'ENERJİ', 'GIDA'}
                if s not in turkce_kelimeler:
                    ticker_adaylari.append(s)

        # Daha iyi yaklasim: sub-comp div icindeki ilk 3 comp-cell div'i: sira, ticker, sirket_adi
        sub_pattern = re.compile(
            r'<div[^>]*class="[^"]*sub-comp[^"]*"[^>]*>.*?</div>\s*</div>\s*</div>',
            re.DOTALL
        )

        sonuc[endeks_adi] = {
            "beklenen": beklenen_sayi,
            "adaylar": ticker_adaylari[:beklenen_sayi * 2],  # Fazlasindan kes
        }

    return sonuc


def basit_cek(url: str) -> str:
    """Sayfa HTML'ini dondur."""
    resp = requests.get(url, headers=headers, timeout=30)
    resp.raise_for_status()
    return resp.text


# Ana program
print("Endeksler sayfasi indiriliyor...")
endeks_html = basit_cek("https://www.kap.org.tr/tr/Endeksler")
print(f"Endeksler HTML boyutu: {len(endeks_html)}")

print("\nPazarlar sayfasi indiriliyor...")
pazar_html = basit_cek("https://www.kap.org.tr/tr/Pazarlar")
print(f"Pazarlar HTML boyutu: {len(pazar_html)}")

# Endeks basliklarini bul
baslik_pattern = re.compile(
    r'([^<]+?)\s*(\d+)\s*Şirket\s*(?:/\s*Fon\s*)?Bulundu'
)

for html_name, html_content in [("ENDEKSLER", endeks_html), ("PAZARLAR", pazar_html)]:
    print(f"\n{'='*60}")
    print(f"  {html_name}")
    print(f"{'='*60}")

    basliklari = list(baslik_pattern.finditer(html_content))
    for m in basliklari:
        adi = m.group(1).strip()
        # Baslik temizle - HTML tag'leri ve fazla bosluklar
        adi = re.sub(r'<[^>]+>', '', adi)
        adi = re.sub(r'\s+', ' ', adi).strip()
        sayi = int(m.group(2))
        print(f"  {adi}: {sayi} sirket")
