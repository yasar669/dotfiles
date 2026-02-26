#!/usr/bin/env python3
"""KAP web sitesinden endeks ve pazar verilerini cek - RSC parsing."""
import requests
import re
import json

headers = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"}


def rsc_veri_cek(url: str) -> list[dict]:
    """KAP sayfasindan RSC payload icindeki initialData'yi cek."""
    resp = requests.get(url, headers=headers, timeout=60)
    resp.raise_for_status()
    html = resp.text

    # RSC chunklari bul
    rsc_chunks = re.findall(
        r'self\.__next_f\.push\(\[1,"(.*?)"\]\)', html, re.DOTALL
    )

    # En buyuk veri chunkini bul (initialData iceren)
    for chunk in rsc_chunks:
        if len(chunk) < 10000:
            continue
        # Unicode unescape
        decoded = chunk.encode("utf-8").decode("unicode_escape")

        # initialData JSON'unu bul
        m = re.search(r'"initialData":(\[.*?\])\s*[,}]', decoded)
        if not m:
            # Alternatif: stockCode aramasi
            # Butun {code:..., content:[...]} bloklarini bul
            pass

        # Daha pragmatik: decoded icindeki tum stockCode'lari ve code'lari bul
        # Veri yapisi: [{"code":"XU100","content":[{"stockCode":"AGHOL",...},...]},...]
        # JSON parcala
        idx = decoded.find('"initialData":[')
        if idx == -1:
            continue

        # initialData baslangicini bul
        start = idx + len('"initialData":')
        # Bracket matching ile JSON array'i bul
        depth = 0
        end = start
        for i in range(start, len(decoded)):
            if decoded[i] == "[":
                depth += 1
            elif decoded[i] == "]":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break

        json_str = decoded[start:end]
        # Bozuk unicode karakterleri temizle
        try:
            data = json.loads(json_str)
            return data
        except json.JSONDecodeError:
            # Karakter encoding sorunlarini duzelt
            # Turkce karakterler bozuk olabilir
            json_str2 = json_str.encode("utf-8", errors="replace").decode(
                "utf-8", errors="replace"
            )
            try:
                data = json.loads(json_str2)
                return data
            except json.JSONDecodeError as e:
                print(f"JSON parse hatasi: {e}")
                # Manuel parsing dene
                print(f"JSON string uzunlugu: {len(json_str)}")
                print(f"Ilk 500 karakter: {json_str[:500]}")
                return []

    return []


def endeks_sembol_listesi(veri: list[dict]) -> dict[str, list[str]]:
    """Veri listesinden endeks -> sembol listesi cikar."""
    sonuc = {}
    for endeks in veri:
        kod = endeks.get("code", "")
        icerik = endeks.get("content", [])
        semboller = []
        for sirket in icerik:
            stok = sirket.get("stockCode", "")
            if stok:
                semboller.append(stok)
        sonuc[kod] = sorted(semboller)
    return sonuc


# Ana program
for sayfa_adi, url in [
    ("ENDEKSLER", "https://www.kap.org.tr/tr/Endeksler"),
    ("PAZARLAR", "https://www.kap.org.tr/tr/Pazarlar"),
]:
    print(f"\n{'='*60}")
    print(f"  {sayfa_adi} sayfasi indiriliyor...")
    print(f"{'='*60}")

    veri = rsc_veri_cek(url)
    if not veri:
        print("  Veri bulunamadi!")
        continue

    endeksler = endeks_sembol_listesi(veri)
    for kod, semboller in endeksler.items():
        print(f"\n{kod} ({len(semboller)}):")
        print(", ".join(semboller))
