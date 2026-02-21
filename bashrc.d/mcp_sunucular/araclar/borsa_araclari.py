"""Borsa islem araclari (giris, bakiye, portfoy, emir, halka arz).

Bu araclar araci kurum adaptorlerini (ornegin Ziraat Yatirim)
kullanan islemleri yapay zekaya acar. Giris, bakiye sorgulama,
portfoy goruntuleme, emir gonderme/listeleme/iptal ve halka arz
islemlerini kapsar.

UYARI: Emir gonderme ve halka arz talep gibi islemler gercek
para ile gercek islem yapar. Yapay zekanin bu araclari kullanmadan
once kullanicidan teyit almasi beklenir.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from mcp.server.fastmcp import FastMCP

from yardimcilar import bash_calistir


def borsa_araclarini_kaydet(sunucu: FastMCP) -> None:
    """Borsa islem araclarini MCP sunucusuna kaydeder."""

    @sunucu.tool()
    def borsa_kurumlari_listele() -> str:
        """Sistemde tanimli tum araci kurum adaptorlerini listeler.

        Hangi kurumlarin desteklendigini gosterir (ornegin: ziraat).

        Returns:
            Desteklenen kurum listesi.
        """
        return bash_calistir("borsa")

    @sunucu.tool()
    def borsa_bakiye(kurum: str = "ziraat") -> str:
        """Belirtilen araci kurumdaki hesabin bakiye bilgisini getirir.

        Nakit bakiye, hisse senedi degeri ve toplam varlik bilgisini gosterir.
        Once giris yapilmis olmasi (borsa_giris) gerekir.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat"). Varsayilan: ziraat.

        Returns:
            Nakit bakiye, hisse degeri ve toplam varlik bilgisi.
        """
        return bash_calistir(f'borsa "{kurum}" bakiye', zaman_asimi=60)

    @sunucu.tool()
    def borsa_portfoy(kurum: str = "ziraat") -> str:
        """Belirtilen araci kurumdaki portfoyun detayini getirir.

        Her hisse icin: sembol, lot, son fiyat, piyasa degeri, maliyet,
        kar/zarar ve kar/zarar yuzdesi gosterilir.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").

        Returns:
            Portfoy detay tablosu (hisse bazinda).
        """
        return bash_calistir(f'borsa "{kurum}" portfoy', zaman_asimi=60)

    @sunucu.tool()
    def borsa_emirleri_listele(kurum: str = "ziraat") -> str:
        """Belirtilen araci kurumdaki acik emirleri listeler.

        Henuz eslesmemis veya kismen eslesmis emirleri gosterir.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").

        Returns:
            Acik emir listesi.
        """
        return bash_calistir(f'borsa "{kurum}" emirler', zaman_asimi=60)

    @sunucu.tool()
    def borsa_emir_gonder(
        kurum: str,
        sembol: str,
        yon: str,
        lot: str,
        fiyat: str,
    ) -> str:
        """Belirtilen araci kuruma hisse alim veya satim emri gonderir.

        DIKKAT: Bu islem GERCEK PARA ile GERCEK islem yapar!
        Kullanicidan teyit alinmadan cagirilmamalidir.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").
            sembol: Hisse senedi sembolu (ornek: "THYAO", "AKBNK").
            yon: Emir yonu ("ALIS" veya "SATIS").
            lot: Adet/lot sayisi (ornek: "100").
            fiyat: Emir fiyati TL (ornek: "85.50").

        Returns:
            Emir sonucu (basarili/basarisiz ve detaylar).
        """
        return bash_calistir(
            f'borsa "{kurum}" emir "{sembol}" "{yon}" "{lot}" "{fiyat}"',
            zaman_asimi=60,
        )

    @sunucu.tool()
    def borsa_emir_iptal(kurum: str, emir_no: str) -> str:
        """Belirtilen araci kurumdaki acik emri iptal eder.

        DIKKAT: Bu islem geri alinamaz.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").
            emir_no: Iptal edilecek emrin numarasi.

        Returns:
            Iptal sonucu.
        """
        return bash_calistir(
            f'borsa "{kurum}" iptal "{emir_no}"',
            zaman_asimi=60,
        )

    @sunucu.tool()
    def borsa_hesap_durumu(kurum: str = "ziraat") -> str:
        """Belirtilen araci kurumdaki aktif hesap bilgisini gosterir.

        Aktif hesap numarasi ve oturum durumunu (gecerli/gecersiz) bildirir.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").

        Returns:
            Aktif hesap numarasi ve oturum durumu.
        """
        return bash_calistir(f'borsa "{kurum}" hesap', zaman_asimi=30)

    @sunucu.tool()
    def borsa_hesaplar(kurum: str = "ziraat") -> str:
        """Belirtilen araci kurumdaki tum kayitli oturumlari listeler.

        Hangi hesaplarin kayitli oldugunu ve oturum durumlarini gosterir.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").

        Returns:
            Kayitli hesaplar ve oturum durumlari.
        """
        return bash_calistir(f'borsa "{kurum}" hesaplar', zaman_asimi=30)

    @sunucu.tool()
    def borsa_halka_arz_liste(kurum: str = "ziraat") -> str:
        """Belirtilen araci kurumdaki aktif halka arz listesini gosterir.

        Basvuruya acik halka arzlarin adi, tipi, odeme sekli ve durumunu listeler.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").

        Returns:
            Halka arz listesi.
        """
        return bash_calistir(f'borsa "{kurum}" arz liste', zaman_asimi=60)

    @sunucu.tool()
    def borsa_halka_arz_talepler(kurum: str = "ziraat") -> str:
        """Belirtilen araci kurumdaki halka arz taleplerinizi listeler.

        Daha once yaptiginiz halka arz basvurularinin durumunu gosterir.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").

        Returns:
            Halka arz talep listesi.
        """
        return bash_calistir(f'borsa "{kurum}" arz talepler', zaman_asimi=60)

    @sunucu.tool()
    def borsa_halka_arz_talep(kurum: str, arz_adi: str, lot: str) -> str:
        """Belirtilen halka arza talep (basvuru) gonderir.

        DIKKAT: Bu islem finansal bir baglayicilik olusturur.
        Kullanicidan teyit alinmadan cagirilmamalidir.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").
            arz_adi: Halka arzin adi veya kodu.
            lot: Talep edilecek lot miktari.

        Returns:
            Talep sonucu.
        """
        return bash_calistir(
            f'borsa "{kurum}" arz talep "{arz_adi}" "{lot}"',
            zaman_asimi=60,
        )

    @sunucu.tool()
    def borsa_halka_arz_iptal(kurum: str, talep_id: str) -> str:
        """Belirtilen halka arz talebini iptal eder.

        Args:
            kurum: Araci kurum adi (ornek: "ziraat").
            talep_id: Iptal edilecek talebin ID'si.

        Returns:
            Iptal sonucu.
        """
        return bash_calistir(
            f'borsa "{kurum}" arz iptal "{talep_id}"',
            zaman_asimi=60,
        )

    @sunucu.tool()
    def borsa_kurallar(alt_komut: str = "") -> str:
        """BIST kurallari hakkinda bilgi verir (seans, fiyat, pazar, takas).

        Alt komut verilmezse tum kural kategorilerini gosterir.

        Args:
            alt_komut: Kural kategorisi. Secenekler:
                - "seans": Seans saatleri
                - "fiyat": Fiyat adim tablosu
                - "pazar": Pazar yapisi (opsiyonel: "pazar YAKIN")
                - "takas": Takas kurallari (T+2, net/brut)
                - "adim <FIYAT>": Belirli fiyat icin adim
                - "tavan <FIYAT>": Tavan fiyat hesapla
                - "taban <FIYAT>": Taban fiyat hesapla
                - bos: Tum kurallari goster

        Returns:
            Istenen kural bilgisi.
        """
        if alt_komut:
            return bash_calistir(f"borsa kurallar {alt_komut}", zaman_asimi=15)
        return bash_calistir("borsa kurallar", zaman_asimi=15)
