"""tvDatafeed CLI sarmalayicisi.

Tek hisse icin OHLCV mum verisi ceker ve stdout'a CSV olarak yazar.
Bash arayuzu (ohlcv.sh) bu dosyayi su sekilde cagirir:

    python3 _tvdatafeed_cagir.py THYAO 1G 200

Cikti formati (baslik satiri yok, en yeni en ustte):
    2026-02-24,312.0000,316.5000,310.2500,315.7500,4521000
    2026-02-23,308.5000,313.0000,307.0000,312.0000,3890000
"""

import sys
import os
import logging

# tvDatafeed kaynak kodu ayni dizinde: _tvdatafeed_main.py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _tvdatafeed_main import Interval, TvDatafeed  # noqa: E402

# Sessiz calisma — sadece hata durumunda log
logging.basicConfig(level=logging.ERROR)

# Bash periyot kodlari -> tvDatafeed Interval eslestirmesi
PERIYOT_ESLE: dict[str, Interval] = {
    "1dk": Interval.in_1_minute,
    "3dk": Interval.in_3_minute,
    "5dk": Interval.in_5_minute,
    "15dk": Interval.in_15_minute,
    "30dk": Interval.in_30_minute,
    "45dk": Interval.in_45_minute,
    "1S": Interval.in_1_hour,
    "2S": Interval.in_2_hour,
    "3S": Interval.in_3_hour,
    "4S": Interval.in_4_hour,
    "1G": Interval.in_daily,
    "1H": Interval.in_weekly,
    "1A": Interval.in_monthly,
}

# WebSocket zaman asimi (saniye) — 5000 bar cekiminde 5sn yetersiz
WS_ZAMAN_ASIMI = 20

# Borsa kodu — BIST icin sabit
BORSA_KODU = "BIST"


def kullanim_yazdir() -> None:
    """Kullanim bilgisini stderr'e yazar."""
    sys.stderr.write(
        "Kullanim: python3 _tvdatafeed_cagir.py <SEMBOL> <PERIYOT> <BAR_SAYISI>\n"
        "\n"
        "Ornek:    python3 _tvdatafeed_cagir.py THYAO 1G 200\n"
        "\n"
        "Periyotlar: 1dk 3dk 5dk 15dk 30dk 45dk 1S 2S 3S 4S 1G 1H 1A\n"
        "Maks bar:   5000\n"
    )


def mum_cek(sembol: str, periyot: str, bar_sayisi: int) -> int:
    """Tek hisse icin OHLCV verisini ceker ve CSV olarak stdout'a yazar.

    Args:
        sembol: Hisse senedi sembolu (THYAO, GARAN vb).
        periyot: Mum periyodu (1dk, 5dk, 1G vb).
        bar_sayisi: Cekilecek mum sayisi (maks 5000).

    Returns:
        0 basarili, 1 basarisiz.
    """
    # Periyot dogrulama
    interval = PERIYOT_ESLE.get(periyot)
    if interval is None:
        sys.stderr.write(f"HATA: Gecersiz periyot '{periyot}'\n")
        sys.stderr.write(f"Gecerli periyotlar: {' '.join(PERIYOT_ESLE.keys())}\n")
        return 1

    # Bar sayisi dogrulama
    if bar_sayisi < 1 or bar_sayisi > 5000:
        sys.stderr.write(f"HATA: Bar sayisi 1-5000 araliginda olmali: {bar_sayisi}\n")
        return 1

    try:
        tv = TvDatafeed()
        # WS timeout'u artir (varsayilan 5sn, buyuk cekimlerde yetersiz)
        tv._TvDatafeed__ws_timeout = WS_ZAMAN_ASIMI  # type: ignore[attr-defined]

        df = tv.get_hist(
            symbol=sembol,
            exchange=BORSA_KODU,
            interval=interval,
            n_bars=bar_sayisi,
        )
    except Exception as hata:
        sys.stderr.write(f"HATA: tvDatafeed baglanti hatasi — {hata}\n")
        return 1

    # Bos DataFrame kontrolu (hatali sembol veya veri yok)
    if df is None or len(df) == 0:
        sys.stderr.write(f"HATA: '{sembol}' icin veri bulunamadi\n")
        return 1

    # CSV cikti — baslik satiri yok, en yeni en ustte
    # DataFrame index: datetime, sutunlar: symbol, open, high, low, close, volume
    df_sirali = df.sort_index(ascending=False)
    for tarih, satir in df_sirali.iterrows():
        tarih_str = tarih.strftime("%Y-%m-%d %H:%M:%S")  # type: ignore[union-attr]
        sys.stdout.write(
            f"{tarih_str},"
            f"{satir['open']:.4f},"
            f"{satir['high']:.4f},"
            f"{satir['low']:.4f},"
            f"{satir['close']:.4f},"
            f"{int(satir['volume'])}\n"
        )

    return 0


def ana() -> None:
    """Komut satiri giris noktasi."""
    if len(sys.argv) != 4:
        kullanim_yazdir()
        sys.exit(1)

    sembol = sys.argv[1].upper()
    periyot = sys.argv[2]
    try:
        bar_sayisi = int(sys.argv[3])
    except ValueError:
        sys.stderr.write(f"HATA: Bar sayisi sayi olmali: '{sys.argv[3]}'\n")
        sys.exit(1)

    cikis_kodu = mum_cek(sembol, periyot, bar_sayisi)
    sys.exit(cikis_kodu)


if __name__ == "__main__":
    ana()
