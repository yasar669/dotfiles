"""Borsa veritabani gecmis sorgulari ve mutabakat araclari.

Supabase veritabanina kaydedilen emir gecmisi, bakiye gecmisi,
pozisyon gecmisi, kar/zarar raporu, fiyat gecmisi, robot loglari,
oturum loglari ve gun sonu raporlarini sorgulamaya yarar.

Salt-okunur araclardir, veritabaninda degisiklik yapmazlar.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from mcp.server.fastmcp import FastMCP

from yardimcilar import bash_calistir


def borsa_gecmis_araclarini_kaydet(sunucu: FastMCP) -> None:
    """Borsa gecmis sorgulama araclarini MCP sunucusuna kaydeder."""

    @sunucu.tool()
    def borsa_gecmis_emirler(limit: str = "10") -> str:
        """Son emir gecmisini veritabanindan sorgular.

        Args:
            limit: Gosterilecek emir sayisi (varsayilan: "10").

        Returns:
            Emir gecmisi tablosu.
        """
        return bash_calistir(
            f"borsa gecmis emirler {limit}",
            zaman_asimi=30,
        )

    @sunucu.tool()
    def borsa_gecmis_bakiye(donem: str = "bugun") -> str:
        """Bakiye gecmisini veritabanindan sorgular.

        Args:
            donem: Sorgu donemi. Secenekler:
                - "bugun": Bugunun bakiye kayitlari
                - "7": Son 7 gunun bakiye kayitlari
                - "30": Son 30 gunun bakiye kayitlari

        Returns:
            Bakiye gecmisi tablosu.
        """
        return bash_calistir(
            f"borsa gecmis bakiye {donem}",
            zaman_asimi=30,
        )

    @sunucu.tool()
    def borsa_gecmis_sembol(sembol: str) -> str:
        """Belirli bir hisse senedinin pozisyon gecmisini sorgular.

        Alinan ve satilan lotlar, fiyatlar ve kar/zarar bilgisini gosterir.

        Args:
            sembol: Hisse senedi sembolu (ornek: "THYAO").

        Returns:
            Sembol bazinda pozisyon gecmisi.
        """
        return bash_calistir(
            f'borsa gecmis sembol "{sembol}"',
            zaman_asimi=30,
        )

    @sunucu.tool()
    def borsa_gecmis_kar(gun: str = "30") -> str:
        """Kar/zarar raporunu veritabanindan sorgular.

        Args:
            gun: Raporlanacak gun sayisi (varsayilan: "30").

        Returns:
            Kar/zarar raporu.
        """
        return bash_calistir(
            f"borsa gecmis kar {gun}",
            zaman_asimi=30,
        )

    @sunucu.tool()
    def borsa_gecmis_fiyat(sembol: str, gun: str = "30") -> str:
        """Belirli bir hisse senedinin fiyat gecmisini sorgular.

        Args:
            sembol: Hisse senedi sembolu (ornek: "THYAO").
            gun: Geriye donuk gun sayisi (varsayilan: "30").

        Returns:
            Fiyat gecmisi tablosu.
        """
        return bash_calistir(
            f'borsa gecmis fiyat "{sembol}" {gun}',
            zaman_asimi=30,
        )

    @sunucu.tool()
    def borsa_gecmis_robot(pid_veya_gun: str = "") -> str:
        """Robot log gecmisini veritabanindan sorgular.

        Parametresiz: tum robot loglari.
        PID ile: belirli bir robotun loglari.

        Args:
            pid_veya_gun: Robot PID numarasi veya bos (tumu).

        Returns:
            Robot log gecmisi.
        """
        if pid_veya_gun:
            return bash_calistir(
                f"borsa gecmis robot {pid_veya_gun}",
                zaman_asimi=30,
            )
        return bash_calistir("borsa gecmis robot", zaman_asimi=30)

    @sunucu.tool()
    def borsa_gecmis_oturum(
        kurum: str = "",
        hesap: str = "",
    ) -> str:
        """Oturum log gecmisini veritabanindan sorgular.

        Parametresiz: tum oturum loglari.
        Kurum ve hesap ile: belirli bir oturumun loglari.

        Args:
            kurum: Araci kurum adi (opsiyonel).
            hesap: Hesap numarasi (opsiyonel).

        Returns:
            Oturum log gecmisi.
        """
        if kurum and hesap:
            return bash_calistir(
                f'borsa gecmis oturum "{kurum}" "{hesap}"',
                zaman_asimi=30,
            )
        return bash_calistir("borsa gecmis oturum", zaman_asimi=30)

    @sunucu.tool()
    def borsa_gecmis_rapor() -> str:
        """Gun sonu raporunu veritabanindan sorgular.

        Returns:
            Gun sonu raporu.
        """
        return bash_calistir("borsa gecmis rapor", zaman_asimi=30)

    @sunucu.tool()
    def borsa_mutabakat(
        kurum: str,
        hesap: str,
        sembol: str = "",
    ) -> str:
        """Canli bakiye/pozisyon ile veritabanindaki kaydi karsilastirir.

        Tutarsizliklari tespit etmek icin kullanilir.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").
            hesap: Hesap numarasi.
            sembol: Belirli bir sembol (opsiyonel, bos=tum portfoy).

        Returns:
            Mutabakat sonucu (canli vs DB karsilastirmasi).
        """
        if sembol:
            return bash_calistir(
                f'borsa mutabakat "{kurum}" "{hesap}" "{sembol}"',
                zaman_asimi=60,
            )
        return bash_calistir(
            f'borsa mutabakat "{kurum}" "{hesap}"',
            zaman_asimi=60,
        )
