"""Otomatik islem robotu yonetim araclari.

Borsa robot motorunu baslatma, durdurma ve listeleme
islemlerini yapay zekaya acar.

DIKKAT: Robot baslatma gercek para ile gercek islem yapar.
Kullanicidan teyit alinmadan cagirilmamalidir.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from mcp.server.fastmcp import FastMCP

from yardimcilar import bash_calistir


def borsa_robot_araclarini_kaydet(sunucu: FastMCP) -> None:
    """Robot yonetim araclarini MCP sunucusuna kaydeder."""

    @sunucu.tool()
    def borsa_robot_baslat(
        kurum: str,
        hesap: str,
        strateji: str,
        kuru: bool = False,
    ) -> str:
        """Belirtilen stratejiyle otomatik islem robotunu baslatir.

        DIKKAT: Kuru calistirma modu DISINDA gercek para ile islem yapar!
        Kullanicidan teyit alinmadan cagirilmamalidir.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").
            hesap: Hesap numarasi.
            strateji: Strateji dosyasinin adi (ornek: "strateji.sh").
            kuru: True ise gercek emir gondermez, sadece simule eder.

        Returns:
            Robot baslatma sonucu ve PID bilgisi.
        """
        kuru_bayrak = "--kuru " if kuru else ""
        return bash_calistir(
            f'borsa robot baslat {kuru_bayrak}"{kurum}" "{hesap}" "{strateji}"',
            zaman_asimi=30,
        )

    @sunucu.tool()
    def borsa_robot_durdur(
        kurum: str,
        hesap: str,
        strateji: str = "",
    ) -> str:
        """Calisan robotu durdurur.

        Strateji adi verilmezse hesaptaki tum robotlar durur.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").
            hesap: Hesap numarasi.
            strateji: Strateji adi (opsiyonel, bos=tum robotlar).

        Returns:
            Durdurma sonucu.
        """
        if strateji:
            return bash_calistir(
                f'borsa robot durdur "{kurum}" "{hesap}" "{strateji}"',
                zaman_asimi=15,
            )
        return bash_calistir(
            f'borsa robot durdur "{kurum}" "{hesap}"',
            zaman_asimi=15,
        )

    @sunucu.tool()
    def borsa_robot_listele() -> str:
        """Aktif calisan tum robotlari listeler.

        Returns:
            Aktif robot listesi (PID, kurum, hesap, strateji bilgileri).
        """
        return bash_calistir("borsa robot listele", zaman_asimi=15)
