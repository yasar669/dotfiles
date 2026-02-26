"""Canli fiyat verisi kaynak yonetim araclari.

Fiyat kaynagini baslatma, durdurma, durum gorme,
kaynak ayarlama ve fiyat sorgulama islemlerini
yapay zekaya acar.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from mcp.server.fastmcp import FastMCP

from yardimcilar import bash_calistir


def borsa_veri_araclarini_kaydet(sunucu: FastMCP) -> None:
    """Veri kaynagi yonetim araclarini MCP sunucusuna kaydeder."""

    @sunucu.tool()
    def borsa_veri_baslat() -> str:
        """Canli fiyat verisi kaynagini baslatir.

        Otomatik olarak en uygun kaynagi secer.

        Returns:
            Baslatma sonucu.
        """
        return bash_calistir("borsa veri baslat", zaman_asimi=30)

    @sunucu.tool()
    def borsa_veri_durdur() -> str:
        """Canli fiyat verisi kaynagini durdurur.

        Returns:
            Durdurma sonucu.
        """
        return bash_calistir("borsa veri durdur", zaman_asimi=15)

    @sunucu.tool()
    def borsa_veri_goster() -> str:
        """Aktif fiyat kaynaginin durumunu gosterir.

        Hangi kaynaktan veri alindigini ve yedek kaynaklari listeler.

        Returns:
            Fiyat kaynagi durum bilgisi.
        """
        return bash_calistir("borsa veri goster", zaman_asimi=15)

    @sunucu.tool()
    def borsa_veri_ayarla(kurum: str, hesap: str) -> str:
        """Belirli bir araci kurumu fiyat kaynagi olarak ayarlar.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").
            hesap: Hesap numarasi.

        Returns:
            Ayarlama sonucu.
        """
        return bash_calistir(
            f'borsa veri ayarla "{kurum}" "{hesap}"',
            zaman_asimi=15,
        )

    @sunucu.tool()
    def borsa_veri_fiyat(sembol: str) -> str:
        """Aktif fiyat kaynagindan hisse fiyatini sorgular.

        Args:
            sembol: Hisse senedi sembolu (ornek: "THYAO").

        Returns:
            Guncel fiyat bilgisi.
        """
        return bash_calistir(
            f'borsa veri fiyat "{sembol}"',
            zaman_asimi=30,
        )
