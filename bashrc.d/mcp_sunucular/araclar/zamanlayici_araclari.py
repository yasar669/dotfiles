"""Terminal tabanli alarm ve geri sayim araclari.

Zamanlayici modulunu yapay zekaya acar. Geri sayim baslatma,
belirli saatte alarm kurma, kayitli alarmlari yonetme ve
aktif zamanlayicilari kontrol etme islemlerini kapsar.

Tum zamanlayicilar arka planda calisir, terminal kapansa bile
devam eder.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from mcp.server.fastmcp import FastMCP

from yardimcilar import bash_calistir


def zamanlayici_araclarini_kaydet(sunucu: FastMCP) -> None:
    """Zamanlayici araclarini MCP sunucusuna kaydeder."""

    @sunucu.tool()
    def zamanlayici_yardim() -> str:
        """Zamanlayici aracinin tum komutlarini ve kullanim orneklerini gosterir.

        Geri sayim, alarm, kaydet/yukle/listele/sil komutlarinin
        kullanim kilavuzunu icerir.

        Returns:
            Zamanlayici kullanim rehberi.
        """
        return bash_calistir("zamanlayici")

    @sunucu.tool()
    def gerisayim_baslat(
        sure: str,
        isim: str = "Zamanlayici",
        sessiz: bool = False,
        dongulu_ses: bool = False,
    ) -> str:
        """Geri sayim baslatir (arka planda, terminal kapansa bile calisir).

        Sure formatlari:
        - "40" = 40 dakika
        - "1:30:00" = 1 saat 30 dakika
        - "0:0:30" = 30 saniye
        - "0:5:00" = 5 dakika

        Sure dolunca masaustunde bildirim gosterilir ve ses calinir.

        Args:
            sure: Sure (dakika veya SA:DK:SN formati).
            isim: Zamanlayicinin adi (ornek: "KPSS", "Cay Molasi").
            sessiz: True ise sure dolunca ses calma.
            dongulu_ses: True ise kullanici durdurana kadar ses cal.

        Returns:
            Geri sayim kurulum bilgisi.
        """
        bayraklar = "-b"  # her zaman arka planda
        if sessiz:
            bayraklar += " -s"
        if dongulu_ses:
            bayraklar += " -d"

        return bash_calistir(
            f'gerisayim "{sure}" {bayraklar} -i "{isim}"',
            zaman_asimi=10,
        )

    @sunucu.tool()
    def alarm_kur(
        saat: str,
        isim: str = "",
        sessiz: bool = False,
        dongulu_ses: bool = False,
    ) -> str:
        """Belirli bir saatte alarm kurar (arka planda, terminal kapansa bile calisir).

        Belirtilen saatte masaustunde bildirim gosterilir ve ses calinir.
        Eger belirtilen saat gecmisse yarin o saate kurulur.

        Args:
            saat: Alarm saati (SA:DK formati, ornek: "14:30", "08:00").
            isim: Alarmin adi (ornek: "Ogle Yemegi", "Toplanti").
            sessiz: True ise ses calma, sadece bildirim goster.
            dongulu_ses: True ise kullanici durdurana kadar ses cal.

        Returns:
            Alarm kurulum bilgisi ve kalan sure.
        """
        bayraklar = ""
        if isim:
            bayraklar += f' -i "{isim}"'
        if sessiz:
            bayraklar += " -s"
        if dongulu_ses:
            bayraklar += " -d"

        return bash_calistir(
            f'alarm "{saat}"{bayraklar}',
            zaman_asimi=10,
        )

    @sunucu.tool()
    def alarm_kaydet(
        isim: str,
        sure: str,
        saat_modu: bool = False,
        sessiz: bool = False,
        dongulu_ses: bool = False,
    ) -> str:
        """Tekrar kullanilmak uzere alarmi kaydeder.

        Kaydedilen alarmlar sonradan alarm_calistir ile baslatilabilir.

        Args:
            isim: Alarmin adi (ornek: "KPSS Calisma").
            sure: Sure veya saat (saat_modu'na gore degisir).
                Geri sayim modu: "40" (dakika) veya "1:30:00" (sa:dk:sn)
                Saat modu: "14:30" (SA:DK)
            saat_modu: True ise saat alarmi olarak kaydet, False ise geri sayim.
            sessiz: True ise ses calma.
            dongulu_ses: True ise dongulu ses.

        Returns:
            Kayit onay mesaji.
        """
        bayraklar = ""
        if saat_modu:
            bayraklar += " -saat"
        if sessiz:
            bayraklar += " -s"
        if dongulu_ses:
            bayraklar += " -d"

        return bash_calistir(
            f'alarm_kaydet "{isim}" "{sure}"{bayraklar}',
            zaman_asimi=10,
        )

    @sunucu.tool()
    def alarm_listele() -> str:
        """Kaydedilmis tum alarmlari listeler.

        Her alarmin ismi, tipi (geri sayim/saat), suresi ve ses
        ayarlarini gosterir.

        Returns:
            Kayitli alarm listesi.
        """
        return bash_calistir("alarm_listele")

    @sunucu.tool()
    def alarm_calistir(secim: str) -> str:
        """Kaydedilmis bir alarmi baslatir.

        Numara veya isim ile alarm baslatilabilir.

        Args:
            secim: Alarmin numarasi (ornek: "1") veya adi (ornek: "KPSS").

        Returns:
            Alarm baslatma sonucu.
        """
        return bash_calistir(f'alarm_calistir "{secim}"', zaman_asimi=10)

    @sunucu.tool()
    def alarm_sil(secim: str) -> str:
        """Kaydedilmis bir alarmi siler.

        Args:
            secim: Alarmin numarasi (ornek: "1") veya "hepsi" (tum alarmlari sil).

        Returns:
            Silme onay mesaji.
        """
        return bash_calistir(f'alarm_sil "{secim}"')

    @sunucu.tool()
    def aktif_zamanlayicilari_listele() -> str:
        """Su anda calisan tum zamanlayicilari ve alarmlari listeler.

        Aktif PID'leri gosterir. Durdurma icin zamanlayici_durdur kullanilir.

        Returns:
            Aktif zamanlayici listesi ve PID'leri.
        """
        return bash_calistir("aktif_listele")

    @sunucu.tool()
    def zamanlayici_durdur(pid: str) -> str:
        """Calisan bir zamanlayiciyi veya alarmi durdurur.

        Args:
            pid: Durdurulacak zamanlayicinin PID numarasi veya "hepsi".

        Returns:
            Durdurma onay mesaji.
        """
        return bash_calistir(f'zamanlayici_durdur "{pid}"')
