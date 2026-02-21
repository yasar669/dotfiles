"""Bash komutlarini calistirmak icin ortak yardimci fonksiyonlar."""

import subprocess
import os
from pathlib import Path

# bashrc.d klasorunun mutlak yolu
# Bu dosya: bashrc.d/mcp_sunucular/yardimcilar.py
# bashrc.d:  bashrc.d/
_DOSYA_DIZINI = Path(__file__).resolve().parent
BASHRC_DIZINI = _DOSYA_DIZINI.parent
BORSA_DIZINI = BASHRC_DIZINI / "borsa"


def bash_calistir(komut: str, zaman_asimi: int = 30) -> str:
    """Bash komutunu calistirip ciktisini dondurur.

    Tum bashrc.d kaynaklarini yukleyerek komutu calistirir.
    Boylece borsa, zamanlayici, yazdir gibi fonksiyonlar erisilebilir.

    Args:
        komut: Calistirilacak bash komutu.
        zaman_asimi: Saniye cinsinden zaman asimi (varsayilan 30).

    Returns:
        Komutun stdout + stderr ciktisi.
    """
    # Tum bashrc.d dosyalarini sirali yukle, sonra komutu calistir
    kaynak_komutlari = _kaynak_satirlari_olustur()
    tam_komut = f"{kaynak_komutlari}\n{komut}"

    try:
        sonuc = subprocess.run(
            ["bash", "-c", tam_komut],
            capture_output=True,
            text=True,
            timeout=zaman_asimi,
            env=_ortam_degiskenleri(),
        )
        cikti = sonuc.stdout.strip()
        hata = sonuc.stderr.strip()

        if sonuc.returncode != 0 and hata:
            return f"{cikti}\nHATA: {hata}".strip()
        return cikti if cikti else hata
    except subprocess.TimeoutExpired:
        return f"HATA: Komut {zaman_asimi} saniye icinde tamamlanamadi."
    except FileNotFoundError:
        return "HATA: bash bulunamadi."
    except Exception as beklenmeyen:
        return f"HATA: {type(beklenmeyen).__name__}: {beklenmeyen}"


def _kaynak_satirlari_olustur() -> str:
    """bashrc.d altindaki dosyalari source eden satirlari olusturur."""
    satirlar = []

    # Ana bashrc.d dosyalari (sirali)
    for dosya in sorted(BASHRC_DIZINI.glob("*.sh")):
        satirlar.append(f'source "{dosya}"')

    # Borsa cekirdek dosyasi
    cekirdek = BORSA_DIZINI / "cekirdek.sh"
    if cekirdek.exists():
        satirlar.append(f'source "{cekirdek}"')

    return "\n".join(satirlar)


def _ortam_degiskenleri() -> dict:
    """Komut icin gerekli ortam degiskenlerini hazirlar."""
    ortam = os.environ.copy()
    ortam["HOME"] = str(Path.home())
    ortam["LANG"] = ortam.get("LANG", "tr_TR.UTF-8")
    return ortam
