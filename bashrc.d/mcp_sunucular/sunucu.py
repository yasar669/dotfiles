"""Dotfiles MCP Sunucusu - Ana giris noktasi.

Bu sunucu, bashrc.d altindaki tum bash araclarini
(borsa, bist, yazdir, zamanlayici) yapay zekaya acar.

Calistirma:
    python sunucu.py

VS Code entegrasyonu:
    .vscode/mcp.json dosyasina eklenir (detay icin README'ye bakin).
"""

import sys
from pathlib import Path

# Bu dosyanin bulundugu dizini Python yoluna ekle
# Boylece araclar/ ve yardimcilar.py bulunabilir
sys.path.insert(0, str(Path(__file__).resolve().parent))

from mcp.server.fastmcp import FastMCP

from araclar.bist_araclari import bist_araclarini_kaydet
from araclar.borsa_araclari import borsa_araclarini_kaydet
from araclar.yazdir_araclari import yazdir_araclarini_kaydet
from araclar.zamanlayici_araclari import zamanlayici_araclarini_kaydet

# Ana MCP sunucusunu olustur
sunucu = FastMCP(
    "dotfiles-araclari",
    instructions=(
        "Bu sunucu, kullanicinin Linux masaustu ortamindaki bash "
        "araclarini saglar. Dort ana modul vardir:\n\n"
        "1. BORSA: Araci kurum hesap yonetimi (bakiye, "
        "portfoy, emir gonderme/iptal, halka arz). Gercek para ile "
        "islem yapar, emir gondermeden once mutlaka kullanicidan "
        "teyit alin.\n\n"
        "GUVENLIK: Giris/parola/sifre islemleri bu sunucu "
        "uzerinden YAPILAMAZ. Kullanici girisini terminalde "
        "yapmalidir (borsa <kurum> giris). Bu kisitlama, "
        "parolalarin yapay zeka saglayici sunucularina "
        "iletilmesini onlemek icindir.\n\n"
        "2. BIST KURALLARI: Borsa Istanbul kural sorgulama (seans "
        "saatleri, fiyat adimi, pazar bilgisi, tavan/taban hesaplama, "
        "takas kurallari). Salt-okunur bilgi araclari.\n\n"
        "3. YAZDIR: PDF ve Markdown dosyalarini HP DeskJet 2540 "
        "yazicisinda arkalionlu baski. Yazdirmadan once "
        "kullanicidan teyit alin.\n\n"
        "4. ZAMANLAYICI: Geri sayim, alarm kurma, kayitli alarm "
        "yonetimi. Tum zamanlayicilar arka planda calisir, "
        "terminal kapansa bile devam eder."
    ),
)

# Tum araclari kaydet
bist_araclarini_kaydet(sunucu)
borsa_araclarini_kaydet(sunucu)
yazdir_araclarini_kaydet(sunucu)
zamanlayici_araclarini_kaydet(sunucu)

if __name__ == "__main__":
    sunucu.run()
