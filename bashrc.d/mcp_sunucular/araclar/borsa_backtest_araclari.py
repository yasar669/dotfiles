"""Gecmis veri uzerinde strateji testi (backtest) araclari.

Strateji dosyalarini gecmis veriler uzerinde test etme,
sonuclari inceleme, karsilastirma ve dis veri yukleme
islemlerini yapay zekaya acar.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from mcp.server.fastmcp import FastMCP

from yardimcilar import bash_calistir


def borsa_backtest_araclarini_kaydet(sunucu: FastMCP) -> None:
    """Backtest araclarini MCP sunucusuna kaydeder."""

    @sunucu.tool()
    def borsa_backtest_calistir(
        strateji: str,
        semboller: str,
        tarih: str = "",
        nakit: str = "",
        komisyon_alis: str = "",
        komisyon_satis: str = "",
        sessiz: bool = False,
        detay: bool = False,
        kaynak: str = "",
        csv_dosya: str = "",
    ) -> str:
        """Belirtilen stratejiyi gecmis veri uzerinde test eder.

        Args:
            strateji: Strateji dosyasinin adi (ornek: "ornek.sh").
            semboller: Test edilecek semboller (ornek: "THYAO" veya "THYAO,AKBNK").
            tarih: Tarih araligi (ornek: "2024-01-01:2024-12-31"). Bos=tum veri.
            nakit: Baslangic nakdi TL (ornek: "100000"). Bos=varsayilan.
            komisyon_alis: Alis komisyon orani (ornek: "0.002"). Bos=varsayilan.
            komisyon_satis: Satis komisyon orani (ornek: "0.002"). Bos=varsayilan.
            sessiz: True ise minimum cikti.
            detay: True ise islem bazinda detayli cikti.
            kaynak: Veri kaynagi (bos=varsayilan).
            csv_dosya: Dis CSV dosyasi kullanmak icin tam yol.

        Returns:
            Backtest sonuc raporu.
        """
        bayraklar = ""
        if tarih:
            bayraklar += f' --tarih "{tarih}"'
        if nakit:
            bayraklar += f' --nakit "{nakit}"'
        if komisyon_alis:
            bayraklar += f' --komisyon-alis "{komisyon_alis}"'
        if komisyon_satis:
            bayraklar += f' --komisyon-satis "{komisyon_satis}"'
        if sessiz:
            bayraklar += " --sessiz"
        if detay:
            bayraklar += " --detay"
        if kaynak:
            bayraklar += f' --kaynak "{kaynak}"'
        if csv_dosya:
            bayraklar += f' --csv-dosya "{csv_dosya}"'

        return bash_calistir(
            f'borsa backtest "{strateji}" "{semboller}"{bayraklar}',
            zaman_asimi=300,
        )

    @sunucu.tool()
    def borsa_backtest_sonuclar(strateji: str = "") -> str:
        """Onceki backtest sonuclarini listeler.

        Args:
            strateji: Strateji adi ile filtreleme (opsiyonel).

        Returns:
            Backtest sonuclari listesi.
        """
        if strateji:
            return bash_calistir(
                f'borsa backtest sonuclar "{strateji}"',
                zaman_asimi=30,
            )
        return bash_calistir("borsa backtest sonuclar", zaman_asimi=30)

    @sunucu.tool()
    def borsa_backtest_detay(test_id: str) -> str:
        """Belirli bir backtest sonucunun detayini gosterir.

        Args:
            test_id: Backtest sonuc ID'si.

        Returns:
            Detayli backtest raporu (islem bazinda).
        """
        return bash_calistir(
            f'borsa backtest detay "{test_id}"',
            zaman_asimi=30,
        )

    @sunucu.tool()
    def borsa_backtest_karsilastir(id1: str, id2: str) -> str:
        """Iki backtest sonucunu yan yana karsilastirir.

        Args:
            id1: Birinci backtest ID'si.
            id2: Ikinci backtest ID'si.

        Returns:
            Karsilastirmali sonuc tablosu.
        """
        return bash_calistir(
            f'borsa backtest karsilastir "{id1}" "{id2}"',
            zaman_asimi=30,
        )

    @sunucu.tool()
    def borsa_backtest_yukle(csv_dosya: str, sembol: str = "") -> str:
        """Dis CSV dosyasindan fiyat verisi yukler.

        Args:
            csv_dosya: CSV dosyasinin tam yolu.
            sembol: Sembol adi (opsiyonel, CSV'den okunur).

        Returns:
            Yukleme sonucu.
        """
        if sembol:
            return bash_calistir(
                f'borsa backtest yukle "{csv_dosya}" "{sembol}"',
                zaman_asimi=60,
            )
        return bash_calistir(
            f'borsa backtest yukle "{csv_dosya}"',
            zaman_asimi=60,
        )

    @sunucu.tool()
    def borsa_backtest_sentetik(
        sembol: str,
        fiyat: str = "",
        gun: str = "",
        volatilite: str = "",
    ) -> str:
        """Test amacli sentetik (yapay) fiyat verisi uretir.

        Args:
            sembol: Sembol adi (ornek: "TEST").
            fiyat: Baslangic fiyati (opsiyonel).
            gun: Uretilecek gun sayisi (opsiyonel).
            volatilite: Volatilite orani (opsiyonel).

        Returns:
            Sentetik veri uretim sonucu.
        """
        ekler = ""
        if fiyat:
            ekler += f" {fiyat}"
        if gun:
            ekler += f" {gun}"
        if volatilite:
            ekler += f" {volatilite}"

        return bash_calistir(
            f'borsa backtest sentetik "{sembol}"{ekler}',
            zaman_asimi=60,
        )
