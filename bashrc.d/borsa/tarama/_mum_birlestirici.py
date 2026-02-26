"""Mum birlestirici — Tick verilerinden OHLCV mum olusturucu.

Tick dosyalarindan (/tmp/borsa/_wss/tickler/*.tick) okunan
ham fiyat verilerini OHLCV mumlarina donusturur ve Supabase'e yazar.

Kullanim:
    python3 _mum_birlestirici.py

    veya arka planda:
    python3 _mum_birlestirici.py &

Durdurma:
    /tmp/borsa/_takip/birlestirici.pid dosyasini silin veya SIGTERM gonderin.
"""

import json
import os
import signal
import sys
import time
from datetime import datetime, timezone, timedelta

import requests

# -------------------------------------------------------
# Yapilandirma
# -------------------------------------------------------

TICK_DIZIN = "/tmp/borsa/_wss/tickler"
TAKIP_DOSYASI = "/tmp/borsa/_takip/takip.json"
PID_DOSYASI = "/tmp/borsa/_takip/birlestirici.pid"

# Supabase baglanti
SUPABASE_URL = os.environ.get("SUPABASE_URL", "http://localhost:8001")
SUPABASE_ANAHTAR = os.environ.get("SUPABASE_ANAHTAR", "")

# Ayarlar dosyasindan oku
_AYARLAR_DOSYASI = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "veritabani", "supabase.ayarlar.sh",
)
if not SUPABASE_ANAHTAR and os.path.isfile(_AYARLAR_DOSYASI):
    with open(_AYARLAR_DOSYASI, encoding="utf-8") as _f:
        for _satir in _f:
            _satir = _satir.strip()
            if _satir.startswith("_SUPABASE_URL="):
                SUPABASE_URL = _satir.split("=", 1)[1].strip('"').strip("'")
            elif _satir.startswith("_SUPABASE_ANAHTAR="):
                SUPABASE_ANAHTAR = _satir.split("=", 1)[1].strip('"').strip("'")

# Istanbul saat dilimi (UTC+3)
IST = timezone(timedelta(hours=3))

# Periyot -> saniye eslesmesi
PERIYOT_SANIYE: dict[str, int] = {
    "1dk": 60,
    "3dk": 180,
    "5dk": 300,
    "15dk": 900,
    "30dk": 1800,
    "45dk": 2700,
    "1S": 3600,
    "2S": 7200,
    "3S": 10800,
    "4S": 14400,
}

# BIST seans saatleri (Istanbul)
SEANS_ACILIS = 9 * 3600 + 40 * 60  # 09:40 -> saniye
SEANS_KAPANIS = 18 * 3600 + 10 * 60  # 18:10 -> saniye

# Supabase batch boyutu
BATCH_BOYUTU = 100

# Durdurma bayragi
_calissin = True


# -------------------------------------------------------
# Sinyal isleyiciler
# -------------------------------------------------------

def _sinyal_isle(_signum: int, _frame: object) -> None:
    """SIGTERM/SIGINT ile durdurma."""
    global _calissin  # noqa: PLW0603
    _calissin = False


signal.signal(signal.SIGTERM, _sinyal_isle)
signal.signal(signal.SIGINT, _sinyal_isle)


# -------------------------------------------------------
# Mum durumu
# -------------------------------------------------------

class MumDurumu:
    """Tek bir sembol+periyot icin acik mum durumunu tutar."""

    def __init__(self, sembol: str, periyot: str) -> None:
        self.sembol = sembol
        self.periyot = periyot
        self.acilis_zamani: int = 0
        self.acilis: float = 0.0
        self.yuksek: float = 0.0
        self.dusuk: float = float("inf")
        self.kapanis: float = 0.0
        self.hacim: int = 0
        self.tick_sayisi: int = 0

    def sifirla(self, epoch: int, fiyat: float, hacim: int) -> None:
        """Yeni bir mum baslatir."""
        periyot_sn = PERIYOT_SANIYE.get(self.periyot, 60)
        self.acilis_zamani = epoch - (epoch % periyot_sn)
        self.acilis = fiyat
        self.yuksek = fiyat
        self.dusuk = fiyat
        self.kapanis = fiyat
        self.hacim = hacim
        self.tick_sayisi = 1

    def guncelle(self, fiyat: float, hacim: int) -> None:
        """Mevcut mumu gunceller."""
        self.yuksek = max(self.yuksek, fiyat)
        self.dusuk = min(self.dusuk, fiyat)
        self.kapanis = fiyat
        self.hacim += hacim
        self.tick_sayisi += 1

    def dict_yap(self) -> dict:
        """Supabase'e yazilacak dict olusturur."""
        tarih = datetime.fromtimestamp(self.acilis_zamani, tz=IST)
        return {
            "sembol": self.sembol,
            "periyot": self.periyot,
            "tarih": tarih.isoformat(),
            "acilis": round(self.acilis, 4),
            "yuksek": round(self.yuksek, 4),
            "dusuk": round(self.dusuk, 4),
            "kapanis": round(self.kapanis, 4),
            "hacim": self.hacim,
            "kaynak": "wss",
        }


class GunlukMumDurumu:
    """Gunluk (1G) mum icin ozel durum — seans boyunca acik kalir."""

    def __init__(self, sembol: str) -> None:
        self.sembol = sembol
        self.acilis_zamani: int = 0
        self.acilis: float = 0.0
        self.yuksek: float = 0.0
        self.dusuk: float = float("inf")
        self.kapanis: float = 0.0
        self.hacim: int = 0

    def sifirla(self, epoch: int, fiyat: float, hacim: int) -> None:
        """Yeni gun mumu baslatir."""
        # Gunun baslangicina yuvarla
        tarih = datetime.fromtimestamp(epoch, tz=IST)
        gun_baslangici = tarih.replace(hour=9, minute=40, second=0, microsecond=0)
        self.acilis_zamani = int(gun_baslangici.timestamp())
        self.acilis = fiyat
        self.yuksek = fiyat
        self.dusuk = fiyat
        self.kapanis = fiyat
        self.hacim = hacim

    def guncelle(self, fiyat: float, hacim: int) -> None:
        """Gunluk mumu gunceller."""
        self.yuksek = max(self.yuksek, fiyat)
        self.dusuk = min(self.dusuk, fiyat)
        self.kapanis = fiyat
        self.hacim += hacim

    def dict_yap(self) -> dict:
        """Supabase dict'i."""
        tarih = datetime.fromtimestamp(self.acilis_zamani, tz=IST)
        return {
            "sembol": self.sembol,
            "periyot": "1G",
            "tarih": tarih.isoformat(),
            "acilis": round(self.acilis, 4),
            "yuksek": round(self.yuksek, 4),
            "dusuk": round(self.dusuk, 4),
            "kapanis": round(self.kapanis, 4),
            "hacim": self.hacim,
            "kaynak": "wss",
        }


# -------------------------------------------------------
# Supabase islemleri
# -------------------------------------------------------

def supabase_toplu_yaz(satirlar: list[dict]) -> bool:
    """OHLCV satirlarini batch olarak Supabase'e yazar."""
    if not satirlar:
        return True

    url = f"{SUPABASE_URL}/rest/v1/ohlcv"
    basliklar = {
        "apikey": SUPABASE_ANAHTAR,
        "Authorization": f"Bearer {SUPABASE_ANAHTAR}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }

    try:
        yanit = requests.post(
            url, headers=basliklar,
            data=json.dumps(satirlar, ensure_ascii=False),
            timeout=30,
        )
        return 200 <= yanit.status_code < 300
    except requests.RequestException:
        return False


# -------------------------------------------------------
# Takip listesi
# -------------------------------------------------------

def takip_oku() -> dict[str, list[str]]:
    """Takip dosyasini okur."""
    if os.path.isfile(TAKIP_DOSYASI):
        try:
            with open(TAKIP_DOSYASI, encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {}


# -------------------------------------------------------
# Tick dosyasi okuma
# -------------------------------------------------------

def tick_dosyasini_oku(sembol: str, son_okunan: int) -> list[tuple[int, float, int]]:
    """Tick dosyasindan yeni satirlari okur.

    Args:
        sembol: Hisse sembolu.
        son_okunan: Son okunan byte konumu.

    Returns:
        (epoch, fiyat, hacim) listesi.
    """
    dosya = os.path.join(TICK_DIZIN, f"{sembol}.tick")
    if not os.path.isfile(dosya):
        return []

    tickler: list[tuple[int, float, int]] = []
    try:
        with open(dosya, encoding="utf-8") as f:
            f.seek(son_okunan)
            for satir in f:
                satir = satir.strip()
                if not satir:
                    continue
                parcalar = satir.split("|")
                if len(parcalar) >= 3:
                    epoch = int(parcalar[0])
                    fiyat = float(parcalar[1])
                    hacim = int(parcalar[2])
                    tickler.append((epoch, fiyat, hacim))
    except (OSError, ValueError):
        pass

    return tickler


def tick_dosyasi_boyut(sembol: str) -> int:
    """Tick dosyasinin byte boyutunu doner."""
    dosya = os.path.join(TICK_DIZIN, f"{sembol}.tick")
    if os.path.isfile(dosya):
        return os.path.getsize(dosya)
    return 0


# -------------------------------------------------------
# Ana dongu
# -------------------------------------------------------

def ana_dongu() -> None:
    """Mum birlestirici ana dongusu."""
    global _calissin  # noqa: PLW0603

    # PID dosyasi yaz
    os.makedirs(os.path.dirname(PID_DOSYASI), exist_ok=True)
    with open(PID_DOSYASI, "w", encoding="utf-8") as f:
        f.write(str(os.getpid()))

    sys.stderr.write(f"Mum birlestirici basladi (PID: {os.getpid()})\n")

    # Mum durumlari: {sembol: {periyot: MumDurumu}}
    durumlar: dict[str, dict[str, MumDurumu]] = {}
    gunluk_durumlar: dict[str, GunlukMumDurumu] = {}

    # Son okunan pozisyonlar
    son_okunan: dict[str, int] = {}

    # Supabase yazilamayan mumlar (buffer)
    yazma_kuyrugu: list[dict] = []

    while _calissin:
        # Takip listesini oku (her dongude guncelle — eklenebilir/cikarilabilir)
        takip = takip_oku()

        if not takip:
            time.sleep(1)
            continue

        # Her takip edilen sembol icin tick dosyasini kontrol et
        for sembol, periyotlar in takip.items():
            # Sembol icin mum durumlarini hazirla
            if sembol not in durumlar:
                durumlar[sembol] = {}
            if sembol not in gunluk_durumlar:
                gunluk_durumlar[sembol] = GunlukMumDurumu(sembol)

            # Yeni tick'leri oku
            onceki_boyut = son_okunan.get(sembol, 0)
            mevcut_boyut = tick_dosyasi_boyut(sembol)

            if mevcut_boyut <= onceki_boyut:
                continue  # Yeni tick yok

            tickler = tick_dosyasini_oku(sembol, onceki_boyut)
            son_okunan[sembol] = mevcut_boyut

            if not tickler:
                continue

            # Her tick'i isle
            for epoch, fiyat, hacim in tickler:
                # Intraday periyotlar
                for periyot in periyotlar:
                    if periyot == "1G":
                        continue  # Gunluk ayri islenir
                    if periyot not in PERIYOT_SANIYE:
                        continue

                    periyot_sn = PERIYOT_SANIYE[periyot]
                    periyot_baslangici = epoch - (epoch % periyot_sn)

                    if periyot not in durumlar[sembol]:
                        durumlar[sembol][periyot] = MumDurumu(sembol, periyot)
                        durumlar[sembol][periyot].sifirla(epoch, fiyat, hacim)
                        continue

                    mum = durumlar[sembol][periyot]

                    if mum.acilis_zamani != periyot_baslangici:
                        # Onceki mum kapandi — Supabase'e yaz
                        if mum.tick_sayisi > 0:
                            yazma_kuyrugu.append(mum.dict_yap())
                        # Yeni mum baslat
                        mum.sifirla(epoch, fiyat, hacim)
                    else:
                        mum.guncelle(fiyat, hacim)

                # Gunluk mum
                if "1G" in periyotlar:
                    gmum = gunluk_durumlar[sembol]
                    tarih = datetime.fromtimestamp(epoch, tz=IST)
                    gun_str = tarih.strftime("%Y-%m-%d")

                    if gmum.acilis_zamani == 0:
                        gmum.sifirla(epoch, fiyat, hacim)
                    else:
                        onceki_tarih = datetime.fromtimestamp(
                            gmum.acilis_zamani, tz=IST
                        )
                        if onceki_tarih.strftime("%Y-%m-%d") != gun_str:
                            # Yeni gun — onceki gunu kaydet
                            yazma_kuyrugu.append(gmum.dict_yap())
                            gmum.sifirla(epoch, fiyat, hacim)
                        else:
                            gmum.guncelle(fiyat, hacim)

        # Supabase'e yazma kuyrugunu bosalt
        if yazma_kuyrugu:
            for i in range(0, len(yazma_kuyrugu), BATCH_BOYUTU):
                batch = yazma_kuyrugu[i : i + BATCH_BOYUTU]
                if not supabase_toplu_yaz(batch):
                    sys.stderr.write(
                        f"UYARI: {len(batch)} mum Supabase'e yazilamadi\n"
                    )
            yazma_kuyrugu.clear()

        # Kisa bekleme (tick yoksa gereksiz CPU kullanimi onlenir)
        time.sleep(0.5)

    # Cikista acik mumlari kaydet
    sys.stderr.write("Mum birlestirici kapatiliyor — acik mumlar kaydediliyor...\n")
    kapama_satir: list[dict] = []

    for sembol_durum in durumlar.values():
        for mum in sembol_durum.values():
            if mum.tick_sayisi > 0:
                kapama_satir.append(mum.dict_yap())

    for gmum in gunluk_durumlar.values():
        if gmum.acilis_zamani > 0:
            kapama_satir.append(gmum.dict_yap())

    if kapama_satir:
        supabase_toplu_yaz(kapama_satir)
        sys.stderr.write(f"{len(kapama_satir)} acik mum kaydedildi.\n")

    # PID dosyasini temizle
    try:
        os.remove(PID_DOSYASI)
    except OSError:
        pass

    sys.stderr.write("Mum birlestirici durduruldu.\n")


# -------------------------------------------------------
# Giris noktasi
# -------------------------------------------------------

if __name__ == "__main__":
    ana_dongu()
