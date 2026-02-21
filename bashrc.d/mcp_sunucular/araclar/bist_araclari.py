"""Borsa Istanbul (BIST) kural ve bilgi araclari.

BIST fiyat adimi, seans durumu, pazar bilgisi, tavan/taban
hesaplama gibi salt-okunur islemleri yapay zekaya acar.
Hassas islem yapmaz, sadece bilgi sorgular.
"""

import sys
from pathlib import Path

# Ust dizini (mcp_sunucular) Python yoluna ekle
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from mcp.server.fastmcp import FastMCP

from yardimcilar import bash_calistir


def bist_araclarini_kaydet(sunucu: FastMCP) -> None:
    """BIST kural araclarini MCP sunucusuna kaydeder."""

    @sunucu.tool()
    def bist_seans_durumu() -> str:
        """BIST Pay Piyasasi seansinin su an acik mi kapali mi oldugunu kontrol eder.

        Hafta sonu, seans arasi veya islem saatleri icindeyse bilgi verir.
        Bir sonraki seansin ne zaman acilacagini da soyler.

        Returns:
            ACIK veya KAPALI durumu ve detay bilgisi.
        """
        return bash_calistir("bist_seans_acik_mi")

    @sunucu.tool()
    def bist_fiyat_adimi(fiyat: str) -> str:
        """Verilen hisse fiyati icin BIST fiyat adimini (tick size) hesaplar.

        BIST'te fiyatlar belirli adimlarla hareket eder. Ornegin 85.45 TL
        fiyat icin adim 0.05 TL'dir, yani 85.45, 85.50, 85.55 gecerlidir
        ama 85.47 gecersizdir.

        Args:
            fiyat: Kontrol edilecek fiyat (ornek: "85.45", "250", "1500").

        Returns:
            Fiyat adimi degeri (ornek: "0.05").
        """
        return bash_calistir(f'bist_fiyat_adimi "{fiyat}"')

    @sunucu.tool()
    def bist_fiyat_gecerli_mi(fiyat: str) -> str:
        """Verilen fiyatin BIST kurallarina gore gecerli bir fiyat adiminda olup olmadigini kontrol eder.

        Gecersizse en yakin gecerli fiyatlari onerir.

        Args:
            fiyat: Kontrol edilecek fiyat (ornek: "85.47").

        Returns:
            Gecerli ise bos, gecersiz ise hata mesaji ve yakin gecerli fiyatlar.
        """
        sonuc = bash_calistir(f'bist_fiyat_gecerli_mi "{fiyat}"')
        return sonuc if sonuc else f"{fiyat} TL gecerli bir fiyat adimidir."

    @sunucu.tool()
    def bist_fiyat_yuvarla(fiyat: str) -> str:
        """Verilen fiyati en yakin gecerli BIST fiyat adimina (asagi) yuvarlar.

        Args:
            fiyat: Yuvarlanacak fiyat (ornek: "85.47").

        Returns:
            Yuvarlanmis gecerli fiyat (ornek: "85.45").
        """
        return bash_calistir(f'bist_fiyat_yuvarla "{fiyat}"')

    @sunucu.tool()
    def bist_tavan_hesapla(kapanis_fiyati: str) -> str:
        """Bir onceki kapanis fiyatina gore BIST tavan fiyatini hesaplar.

        BIST'te hisseler gunluk %10 limit ile sinirlidir.
        Tavan = kapanis * 1.10, fiyat adimina yuvarlanir.

        Args:
            kapanis_fiyati: Onceki kapanis fiyati (ornek: "85.00").

        Returns:
            Tavan fiyati (ornek: "93.50").
        """
        return bash_calistir(f'bist_tavan_hesapla "{kapanis_fiyati}"')

    @sunucu.tool()
    def bist_taban_hesapla(kapanis_fiyati: str) -> str:
        """Bir onceki kapanis fiyatina gore BIST taban fiyatini hesaplar.

        BIST'te hisseler gunluk %10 limit ile sinirlidir.
        Taban = kapanis * 0.90, fiyat adimina yuvarlanir.

        Args:
            kapanis_fiyati: Onceki kapanis fiyati (ornek: "85.00").

        Returns:
            Taban fiyati (ornek: "76.50").
        """
        return bash_calistir(f'bist_taban_hesapla "{kapanis_fiyati}"')

    @sunucu.tool()
    def bist_seans_bilgi() -> str:
        """BIST Pay Piyasasi seans saatlerinin tam tablosunu gosterir.

        Acilis seansi, 1. seans, ogle arasi, 2. seans ve kapanis
        seansinin baslangic-bitis saatlerini listeler.
        Ayrica su anki seans durumunu da gosterir.

        Returns:
            Seans saatleri tablosu ve anlik durum.
        """
        return bash_calistir("bist_seans_bilgi")

    @sunucu.tool()
    def bist_fiyat_adimi_tablosu() -> str:
        """BIST fiyat adim tablosunun tamamini gosterir.

        Hangi fiyat araliginda hangi adimin gecerli oldugunu listeler.
        Ornegin: 0.01-19.99 TL arasi -> 0.01 adim,
                 50.00-99.99 TL arasi -> 0.05 adim.

        Returns:
            Tum fiyat adim tablosu.
        """
        return bash_calistir("bist_fiyat_adimi_bilgi")

    @sunucu.tool()
    def bist_pazar_bilgi(pazar_kodu: str = "") -> str:
        """BIST pazar yapisi ve kurallarini gosterir.

        Parametresiz cagrilirsa tum pazarlarin ozet tablosunu gosterir.
        Pazar kodu verilirse o pazarin detayli kurallarini gosterir.

        Pazarlar: YILDIZ, ANA, ALT, YAKIN, POIP
        Yakin Izleme Pazari ozel kurallara sahiptir (sadece tek fiyat
        seansi, PIYASA emri yasak, aciga satis yasak vb.)

        Args:
            pazar_kodu: Pazar kodu (bos birak=tum pazarlar, "YAKIN"=yakin izleme).

        Returns:
            Pazar bilgisi tablosu.
        """
        if pazar_kodu:
            return bash_calistir(f'bist_pazar_bilgi "{pazar_kodu}"')
        return bash_calistir("bist_pazar_bilgi")

    @sunucu.tool()
    def bist_takas_bilgi() -> str:
        """BIST takas kurallarini gosterir (T+2, net takas, brut takas).

        Net takasta gun ici al-sat serbesttir.
        Brut takasta aldiginiz hisseyi ayni gun satamazsiniz (T+2 beklemeniz gerekir).
        Yakin Izleme Pazari'ndaki tum hisseler brut takastir.

        Returns:
            Takas kurallari detayi.
        """
        return bash_calistir("bist_takas_bilgi")

    @sunucu.tool()
    def bist_pazar_seans_durumu(pazar_kodu: str = "YILDIZ") -> str:
        """Belirtilen BIST pazarinin su an emir kabul edip etmedigini kontrol eder.

        Yakin Izleme Pazari sadece 14:00-14:32 arasinda islem gorur.
        Normal pazarlar (Yildiz, Ana, Alt) 09:40-18:10 arasinda islem gorur.

        Args:
            pazar_kodu: Pazar kodu (YILDIZ, ANA, ALT, YAKIN, POIP). Varsayilan: YILDIZ.

        Returns:
            ACIK veya KAPALI durumu.
        """
        return bash_calistir(f'bist_pazar_seans_acik_mi "{pazar_kodu}"')

    @sunucu.tool()
    def bist_emir_kontrol(
        pazar_kodu: str = "YILDIZ",
        emir_turu: str = "LIMIT",
        emir_suresi: str = "GUN",
    ) -> str:
        """Verilen emir turu ve suresinin belirtilen BIST pazarinda gecerli olup olmadigini kontrol eder.

        Ornegin Yakin Izleme Pazari'nda PIYASA emri ve KIE/GIE/TAR suresi kullanilamaz.

        Args:
            pazar_kodu: Pazar kodu (YILDIZ, ANA, ALT, YAKIN, POIP).
            emir_turu: Emir turu (LIMIT veya PIYASA).
            emir_suresi: Emir suresi (GUN, KIE, GIE, TAR).

        Returns:
            Gecerli ise bos, gecersiz ise hata mesaji.
        """
        sonuc = bash_calistir(
            f'bist_pazar_emir_kontrol "{pazar_kodu}" "{emir_turu}" "{emir_suresi}"'
        )
        if not sonuc:
            return f"{pazar_kodu} pazarinda {emir_turu} emri ({emir_suresi} sureli) gecerlidir."
        return sonuc

    @sunucu.tool()
    def bist_emir_dogrula(fiyat: str) -> str:
        """Emir gonderme oncesinde BIST kurallarini kontrol eder (fiyat adimi dogrulamasi).

        Args:
            fiyat: Kontrol edilecek emir fiyati.

        Returns:
            Uygun ise onay, degilse hata mesaji.
        """
        sonuc = bash_calistir(f'bist_emir_dogrula "{fiyat}"')
        if not sonuc:
            return f"{fiyat} TL fiyatli emir BIST kurallarina uygundur."
        return sonuc
