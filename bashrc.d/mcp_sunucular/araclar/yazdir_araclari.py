"""PDF ve Markdown yazdirma araci.

HP DeskJet 2540 icin optimize edilmis yazdir fonksiyonunu
yapay zekaya acar. PDF ve Markdown dosyalarini arkalionlu
(duplex) olarak yazdirabilir.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from mcp.server.fastmcp import FastMCP

from yardimcilar import bash_calistir


def yazdir_araclarini_kaydet(sunucu: FastMCP) -> None:
    """Yazdirma araclarini MCP sunucusuna kaydeder."""

    @sunucu.tool()
    def yazdir_yardim() -> str:
        """Yazdirma aracinin kullanim kilavuzunu gosterir.

        Desteklenen dosya turleri (.pdf, .md), secenek bayraklari
        (-r renkli, -s siyahbeyaz), sayfa araligi ornekleri ve
        ornek komutlari icerir.

        Returns:
            Kullanim kilavuzu.
        """
        return bash_calistir("yazdir --yardim")

    @sunucu.tool()
    def yazdir(
        dosya_yolu: str,
        sayfa_araligi: str,
        renkli: bool = False,
    ) -> str:
        """PDF veya Markdown dosyasini yaziciya gonderir (HP DeskJet 2540).

        Arkalionlu (duplex) baski yapar: once on yuzler, sonra arka yuzler.
        Markdown dosyalari otomatik olarak HTML uzerinden PDF'e cevrilir.

        DIKKAT: Bu islem gercekten yazdirma yapar, kagit ve murekkep harcar.
        Kullanicidan teyit alinmadan cagirilmamalidir.

        Args:
            dosya_yolu: Yazdirilacak dosyanin tam yolu (ornek: "/home/yasar/kitap.pdf").
            sayfa_araligi: Yazdirilacak sayfa araligi. Ornekler:
                - "1-20": Sayfa 1'den 20'ye
                - "5,7,12-15": Sayfa 5, 7 ve 12-15
                - "tumu": Tum sayfalar (Markdown icin)
            renkli: True ise renkli, False ise siyah-beyaz (varsayilan) baski.

        Returns:
            Yazdirma islemi sonucu.
        """
        renk_bayragi = "-r" if renkli else "-s"
        return bash_calistir(
            f'yazdir {renk_bayragi} "{dosya_yolu}" "{sayfa_araligi}"',
            zaman_asimi=120,
        )
