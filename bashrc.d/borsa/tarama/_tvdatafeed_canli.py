"""tvDatafeed canli fiyat daemon'u.

TradingView WebSocket uzerinden canli fiyat akisi saglayan daemon.
Eski Ziraat WSS (SignalR) ve REST polling mekanizmasinin yerine gecer.

Kullanim:
    # Basit mod (stdout'a yaz):
    python3 _tvdatafeed_canli.py THYAO GARAN AKBNK

    # Daemon modu (arka plan, JSON dosyalarina yaz):
    python3 _tvdatafeed_canli.py --daemon THYAO GARAN AKBNK

    # Dosyadan sembol oku:
    python3 _tvdatafeed_canli.py --daemon --dosya /tmp/borsa/_takip/semboller.txt

Cikti:
    Her sembol icin /tmp/borsa/_canli/<SEMBOL>.json dosyasina yazar.

Sinyaller:
    SIGUSR1 -> Sembol listesini dosyadan yeniden oku.
    SIGTERM -> Temiz kapanis.
"""

import json
import logging
import os
import re
import signal
import string
import random
import struct
import socket
import sys
import time
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

# --- Yapilandirma -----------------------------------------------------------

CANLI_DIZIN = "/tmp/borsa/_canli"
PID_DOSYASI = "/tmp/borsa/_canli/daemon.pid"
DURUM_DOSYASI = "/tmp/borsa/_canli/daemon.durum"
LOG_DOSYASI = "/tmp/borsa/_canli/daemon.log"
SEMBOL_DOSYASI = "/tmp/borsa/_takip/semboller.txt"

WS_URL = "wss://data.tradingview.com/socket.io/websocket"
WS_BASLIK = json.dumps({"Origin": "https://data.tradingview.com"})
WS_ZAMAN_ASIMI = 5
YENIDEN_BAGLANTI_BEKLEME = 5  # saniye
MAKS_YENIDEN_DENEME = 50
KALP_ATISI_ARALIGI = 20  # saniye — keep-alive suresi

# tvDatafeed ayarlari (ortam degiskenlerinden)
TV_KULLANICI = os.environ.get("TV_KULLANICI", "")
TV_SIFRE = os.environ.get("TV_SIFRE", "")

# Supabase ayarlari (opsiyonel — gun ici OHLCV guncelleme)
SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_ANAHTAR = os.environ.get("SUPABASE_ANAHTAR", "")


# --- Yardimci fonksiyonlar --------------------------------------------------


def oturum_olustur() -> str:
    """Rastgele quote session ID olusturur."""
    harfler = string.ascii_lowercase
    rastgele = "".join(random.choice(harfler) for _ in range(12))
    return "qs_" + rastgele


def baslik_ekle(metin: str) -> str:
    """TradingView WS mesaj basligini ekler."""
    return "~m~" + str(len(metin)) + "~m~" + metin


def mesaj_olustur(fonksiyon: str, parametreler: list) -> str:
    """TradingView WS mesaji olusturur."""
    govde = json.dumps({"m": fonksiyon, "p": parametreler}, separators=(",", ":"))
    return baslik_ekle(govde)


def mesaj_ayristir(ham_veri: str) -> list[dict]:
    """Ham WS verisinden JSON mesajlarini ayristirir."""
    sonuclar = []
    # ~m~<uzunluk>~m~<icerik> formatindaki mesajlari ayir
    parcalar = re.split(r"~m~\d+~m~", ham_veri)
    for parca in parcalar:
        parca = parca.strip()
        if not parca:
            continue
        # Kalp atisi (ping) mesajlari sayi olarak gelir
        if parca.isdigit():
            continue
        try:
            veri = json.loads(parca)
            if isinstance(veri, dict):
                sonuclar.append(veri)
        except (json.JSONDecodeError, ValueError):
            pass
    return sonuclar


def token_al(kullanici: str, sifre: str) -> str:
    """TradingView hesabiyla token alir. Basarisizsa bos doner."""
    if not kullanici or not sifre:
        return "unauthorized_user_token"

    try:
        import requests

        yanit = requests.post(
            "https://www.tradingview.com/accounts/signin/",
            data={"username": kullanici, "password": sifre, "remember": "on"},
            headers={"Referer": "https://www.tradingview.com"},
            timeout=10,
        )
        return yanit.json()["user"]["auth_token"]
    except Exception as hata:
        logger.warning("TradingView giris basarisiz: %s — anonim mod", hata)
        return "unauthorized_user_token"


# --- Canli Veri Daemon sinifi -----------------------------------------------


class CanliVeriDaemon:
    """TradingView WS uzerinden canli fiyat stream daemon'u."""

    def __init__(
        self,
        semboller: list[str],
        daemon_modu: bool = False,
        sembol_dosyasi: str = "",
    ) -> None:
        self.semboller = [s.upper() for s in semboller]
        self.daemon_modu = daemon_modu
        self.sembol_dosyasi = sembol_dosyasi
        self.ws = None
        self.oturum = oturum_olustur()
        self.token = token_al(TV_KULLANICI, TV_SIFRE)
        self.calisiyor = False
        self.mesaj_sayaci = 0
        self.son_kalp_atisi = 0.0
        self.yeniden_okuma_istegi = False

        # Fiyat verisi onbellegi (son bilinen deger)
        self.fiyat_onbellek: dict[str, dict] = {}

    # --- WebSocket islemleri -------------------------------------------------

    def baglan(self) -> bool:
        """TradingView WS sunucusuna baglanir."""
        try:
            from websocket import create_connection
        except ImportError:
            logger.error("websocket-client paketi eksik: pip install websocket-client")
            return False

        try:
            if self.ws is not None:
                try:
                    self.ws.close()
                except Exception:
                    pass

            self.ws = create_connection(
                WS_URL, headers=WS_BASLIK, timeout=WS_ZAMAN_ASIMI
            )

            # Kernel duzeyinde recv zaman asimi
            if self.ws.sock:
                zaman_asimi = max(WS_ZAMAN_ASIMI, KALP_ATISI_ARALIGI + 5)
                timeval = struct.pack("ll", zaman_asimi, 0)
                self.ws.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVTIMEO, timeval)

            logger.info("WS baglantisi kuruldu")
            return True
        except Exception as hata:
            logger.error("WS baglanti hatasi: %s", hata)
            return False

    def oturum_baslat(self) -> None:
        """Quote session olusturur ve sembolleri ekler."""
        if self.ws is None:
            return

        self.oturum = oturum_olustur()

        # Kimlik dogrulama
        self.ws.send(mesaj_olustur("set_auth_token", [self.token]))

        # Canli fiyat oturumu olustur
        self.ws.send(mesaj_olustur("quote_create_session", [self.oturum]))

        # Alanlar — canli fiyat icin gerekli tum veriler
        self.ws.send(
            mesaj_olustur(
                "quote_set_fields",
                [
                    self.oturum,
                    "lp",
                    "ch",
                    "chp",
                    "volume",
                    "open_price",
                    "high_price",
                    "low_price",
                    "prev_close_price",
                    "current_session",
                    "is_tradable",
                    "lp_time",
                    "ask",
                    "bid",
                ],
            )
        )

        # Sembolleri ekle
        for sembol in self.semboller:
            tv_sembol = f"BIST:{sembol}"
            self.ws.send(
                mesaj_olustur(
                    "quote_add_symbols",
                    [self.oturum, tv_sembol, {"flags": ["force_permission"]}],
                )
            )
            self.ws.send(mesaj_olustur("quote_fast_symbols", [self.oturum, tv_sembol]))

        logger.info("%d sembol canli izlemeye eklendi", len(self.semboller))

    def sembol_ekle(self, sembol: str) -> None:
        """Mevcut oturuma yeni sembol ekler."""
        sembol = sembol.upper()
        if sembol in self.semboller:
            return
        self.semboller.append(sembol)
        if self.ws is not None:
            tv_sembol = f"BIST:{sembol}"
            self.ws.send(
                mesaj_olustur(
                    "quote_add_symbols",
                    [self.oturum, tv_sembol, {"flags": ["force_permission"]}],
                )
            )
            self.ws.send(mesaj_olustur("quote_fast_symbols", [self.oturum, tv_sembol]))
        logger.info("Sembol eklendi: %s", sembol)

    def sembol_cikar(self, sembol: str) -> None:
        """Oturumdan sembol cikarir."""
        sembol = sembol.upper()
        if sembol not in self.semboller:
            return
        self.semboller.remove(sembol)
        if self.ws is not None:
            tv_sembol = f"BIST:{sembol}"
            self.ws.send(
                mesaj_olustur("quote_remove_symbols", [self.oturum, tv_sembol])
            )
        logger.info("Sembol cikarildi: %s", sembol)

    def _kalp_atisi_gonder(self) -> None:
        """Keep-alive mesaji gonderir."""
        simdi = time.time()
        if simdi - self.son_kalp_atisi < KALP_ATISI_ARALIGI:
            return
        if self.ws is not None:
            try:
                self.ws.send(baslik_ekle("~h~1"))
                self.son_kalp_atisi = simdi
            except Exception:
                pass

    # --- Mesaj isleme --------------------------------------------------------

    def _mesaj_isle(self, ham: str) -> None:
        """Gelen WS mesajini parse eder ve isler."""
        # Ping/pong
        if re.match(r"^~m~\d+~m~\d+$", ham):
            sayi = re.search(r"~m~(\d+)$", ham)
            if sayi and self.ws:
                try:
                    self.ws.send(baslik_ekle(sayi.group(1)))
                except Exception:
                    pass
            return

        mesajlar = mesaj_ayristir(ham)
        for mesaj in mesajlar:
            mesaj_tipi = mesaj.get("m", "")
            if mesaj_tipi == "qsd":
                self._fiyat_guncelle(mesaj)

    def _fiyat_guncelle(self, mesaj: dict) -> None:
        """Quote session data mesajini isler."""
        try:
            pld = mesaj.get("p", [])
            if len(pld) < 2:
                return
            veri_sarmal = pld[1]
            tam_sembol = veri_sarmal.get("n", "")
            degerler = veri_sarmal.get("v", {})

            if not tam_sembol or not degerler:
                return

            # "BIST:THYAO" -> "THYAO"
            sembol = tam_sembol.split(":")[-1] if ":" in tam_sembol else tam_sembol

            # Mevcut onbellekle birlestir (kademeli guncelleme)
            mevcut = self.fiyat_onbellek.get(sembol, {})
            mevcut.update({k: v for k, v in degerler.items() if v is not None})
            self.fiyat_onbellek[sembol] = mevcut

            # Alan eslestirmesi
            fiyat_veri = {
                "sembol": sembol,
                "fiyat": mevcut.get("lp", 0),
                "degisim": mevcut.get("ch", 0),
                "degisim_yuzde": mevcut.get("chp", 0),
                "hacim": mevcut.get("volume", 0),
                "acilis": mevcut.get("open_price", 0),
                "yuksek": mevcut.get("high_price", 0),
                "dusuk": mevcut.get("low_price", 0),
                "onceki_kapanis": mevcut.get("prev_close_price", 0),
                "zaman": int(mevcut.get("lp_time", time.time())),
                "seans": mevcut.get("current_session", ""),
                "alis": mevcut.get("ask", 0),
                "satis": mevcut.get("bid", 0),
            }

            self.mesaj_sayaci += 1

            if self.daemon_modu:
                self._fiyat_yaz(sembol, fiyat_veri)
            else:
                self._fiyat_yazdir(sembol, fiyat_veri)

        except Exception as hata:
            logger.debug("Fiyat guncelleme hatasi: %s", hata)

    def _fiyat_yaz(self, sembol: str, veri: dict) -> None:
        """Fiyat verisini JSON dosyasina yazar."""
        dizin = Path(CANLI_DIZIN)
        dizin.mkdir(parents=True, exist_ok=True)
        dosya = dizin / f"{sembol}.json"
        gecici = dizin / f".{sembol}.json.tmp"
        try:
            gecici.write_text(json.dumps(veri, ensure_ascii=False), encoding="utf-8")
            gecici.rename(dosya)
        except Exception as hata:
            logger.debug("Dosya yazma hatasi: %s — %s", sembol, hata)

    def _fiyat_yazdir(self, sembol: str, veri: dict) -> None:
        """Fiyat verisini stdout'a yazar (basit mod)."""
        print(
            f"{sembol:>8s}  "
            f"F:{veri['fiyat']:>10}  "
            f"D:{veri['degisim']:>8}  "
            f"%:{veri['degisim_yuzde']:>6}  "
            f"H:{veri['hacim']:>12}  "
            f"A:{veri['acilis']:>10}  "
            f"Y:{veri['yuksek']:>10}  "
            f"Du:{veri['dusuk']:>10}",
            flush=True,
        )

    # --- Durum yonetimi ------------------------------------------------------

    def _durum_yaz(self, durum_metni: str) -> None:
        """Daemon durum dosyasini gunceller."""
        if not self.daemon_modu:
            return
        dizin = Path(CANLI_DIZIN)
        dizin.mkdir(parents=True, exist_ok=True)
        durum = {
            "durum": durum_metni,
            "sembol_sayisi": len(self.semboller),
            "mesaj_sayaci": self.mesaj_sayaci,
            "semboller": self.semboller[:],
            "guncelleme": time.strftime("%Y-%m-%d %H:%M:%S"),
        }
        try:
            Path(DURUM_DOSYASI).write_text(
                json.dumps(durum, ensure_ascii=False, indent=2), encoding="utf-8"
            )
        except Exception:
            pass

    def _pid_yaz(self) -> None:
        """PID dosyasini yazar."""
        if not self.daemon_modu:
            return
        dizin = Path(CANLI_DIZIN)
        dizin.mkdir(parents=True, exist_ok=True)
        try:
            Path(PID_DOSYASI).write_text(str(os.getpid()), encoding="utf-8")
        except Exception:
            pass

    def _pid_sil(self) -> None:
        """PID dosyasini siler."""
        try:
            Path(PID_DOSYASI).unlink(missing_ok=True)
        except Exception:
            pass

    # --- Sinyal isleyicileri -------------------------------------------------

    def _sigusr1_isle(self, _sig: int, _frame: object) -> None:
        """SIGUSR1 — sembol listesini dosyadan yeniden oku."""
        self.yeniden_okuma_istegi = True

    def _sigterm_isle(self, _sig: int, _frame: object) -> None:
        """SIGTERM — temiz kapanis."""
        logger.info("SIGTERM alindi — kapatiliyor")
        self.calisiyor = False

    def _sembol_listesi_yenile(self) -> None:
        """Sembol dosyasindan listeyi yeniden okur ve farklari uygular."""
        self.yeniden_okuma_istegi = False
        dosya = self.sembol_dosyasi
        if not dosya or not os.path.isfile(dosya):
            return

        try:
            with open(dosya, encoding="utf-8") as f:
                yeni_semboller = [
                    s.strip().upper()
                    for s in f.readlines()
                    if s.strip() and not s.strip().startswith("#")
                ]
        except Exception as hata:
            logger.warning("Sembol dosyasi okunamadi: %s", hata)
            return

        mevcut = set(self.semboller)
        yeni = set(yeni_semboller)

        # Eklenecekler
        for s in yeni - mevcut:
            self.sembol_ekle(s)

        # Cikarilacaklar
        for s in mevcut - yeni:
            self.sembol_cikar(s)

        self._durum_yaz("AKTIF")

    # --- Ana dongu -----------------------------------------------------------

    def calistir(self) -> None:
        """Canli veri daemon'unu baslatir ve surekli dinler."""
        self.calisiyor = True

        # Sinyal isleyicileri kur
        signal.signal(signal.SIGUSR1, self._sigusr1_isle)
        signal.signal(signal.SIGTERM, self._sigterm_isle)
        signal.signal(signal.SIGINT, self._sigterm_isle)

        if self.daemon_modu:
            self._pid_yaz()

        yeniden_deneme = 0

        while self.calisiyor and yeniden_deneme < MAKS_YENIDEN_DENEME:
            if not self.baglan():
                yeniden_deneme += 1
                bekleme = min(YENIDEN_BAGLANTI_BEKLEME * yeniden_deneme, 60)
                logger.warning(
                    "Baglanti basarisiz — %d/%d, %ds sonra tekrar",
                    yeniden_deneme,
                    MAKS_YENIDEN_DENEME,
                    bekleme,
                )
                self._durum_yaz("YENIDEN_BAGLANMA_BEKLENIYOR")
                time.sleep(bekleme)
                continue

            # Baglanti basarili — oturumu baslat
            yeniden_deneme = 0
            self.son_kalp_atisi = time.time()
            self.oturum_baslat()
            self._durum_yaz("AKTIF")

            # Dinleme dongusu
            while self.calisiyor:
                try:
                    # SIGUSR1 ile sembol yenileme istegi
                    if self.yeniden_okuma_istegi:
                        self._sembol_listesi_yenile()

                    sonuc = self.ws.recv()
                    if sonuc:
                        self._mesaj_isle(sonuc)

                    self._kalp_atisi_gonder()

                except Exception as hata:
                    hata_str = str(hata)
                    # Zaman asimi — normal, devam et
                    if "timed out" in hata_str:
                        self._kalp_atisi_gonder()
                        continue
                    logger.warning("WS okuma hatasi: %s — yeniden baglaniliyor", hata)
                    self._durum_yaz("YENIDEN_BAGLANMA")
                    break

        # Kapanis
        self.durdur()

    def durdur(self) -> None:
        """Daemon'u durdurur ve kaynaklari temizler."""
        self.calisiyor = False
        if self.ws is not None:
            try:
                self.ws.close()
            except Exception:
                pass
            self.ws = None
        self._durum_yaz("DURDURULDU")
        self._pid_sil()
        logger.info("Daemon durduruldu")


# --- Komut satiri ------------------------------------------------------------


def kullanim() -> None:
    """Kullanim bilgisini yazdir."""
    sys.stderr.write(
        "Kullanim:\n"
        "  python3 _tvdatafeed_canli.py [--daemon] [--dosya DOSYA] SEMBOL1 [SEMBOL2 ...]\n"
        "\n"
        "Secenekler:\n"
        "  --daemon        Arka plan daemon modu (JSON dosyalarina yaz)\n"
        "  --dosya DOSYA   Sembol listesini dosyadan oku (satir basina bir sembol)\n"
        "\n"
        "Ortam degiskenleri:\n"
        "  TV_KULLANICI    TradingView kullanici adi (opsiyonel, gercek zamanli veri icin)\n"
        "  TV_SIFRE        TradingView sifre (opsiyonel)\n"
        "\n"
        "NOT: Bilgileri veritabanina kaydetmek icin 'borsa veri giris' komutunu\n"
        "kullanin. Daemon baslatildiginda bash otomatik olarak veritabanindan okur\n"
        "ve ortam degiskenlerini ayarlar.\n"
        "\n"
        "Ornekler:\n"
        "  python3 _tvdatafeed_canli.py THYAO GARAN AKBNK\n"
        "  python3 _tvdatafeed_canli.py --daemon --dosya /tmp/semboller.txt\n"
    )


def ana() -> None:
    """Komut satiri giris noktasi."""
    args = sys.argv[1:]
    if not args or "--yardim" in args or "-h" in args:
        kullanim()
        sys.exit(0)

    daemon_modu = False
    sembol_dosyasi = ""
    semboller: list[str] = []

    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--daemon":
            daemon_modu = True
        elif arg == "--dosya":
            i += 1
            if i >= len(args):
                sys.stderr.write("HATA: --dosya argumaninin degeri eksik\n")
                sys.exit(1)
            sembol_dosyasi = args[i]
        elif arg.startswith("-"):
            sys.stderr.write(f"HATA: Bilinmeyen arguman: {arg}\n")
            kullanim()
            sys.exit(1)
        else:
            semboller.append(arg.upper())
        i += 1

    # Dosyadan sembol oku
    if sembol_dosyasi and os.path.isfile(sembol_dosyasi):
        with open(sembol_dosyasi, encoding="utf-8") as f:
            for satir in f:
                satir = satir.strip()
                if satir and not satir.startswith("#"):
                    semboller.append(satir.upper())

    if not semboller:
        sys.stderr.write("HATA: En az bir sembol belirtilmeli\n")
        kullanim()
        sys.exit(1)

    # Tekrarlari kaldir
    semboller = list(dict.fromkeys(semboller))

    if daemon_modu:
        # Log dosyasina yonlendir
        dizin = Path(CANLI_DIZIN)
        dizin.mkdir(parents=True, exist_ok=True)
        log_dosya_isleyici = logging.FileHandler(LOG_DOSYASI, encoding="utf-8")
        log_dosya_isleyici.setFormatter(
            logging.Formatter(
                "%(asctime)s [%(levelname)s] %(message)s",
                datefmt="%Y-%m-%d %H:%M:%S",
            )
        )
        logging.getLogger().addHandler(log_dosya_isleyici)

    logger.info(
        "Canli veri daemon baslatiliyor — %d sembol, mod=%s",
        len(semboller),
        "daemon" if daemon_modu else "stdout",
    )

    daemon = CanliVeriDaemon(
        semboller=semboller,
        daemon_modu=daemon_modu,
        sembol_dosyasi=sembol_dosyasi,
    )
    daemon.calistir()


if __name__ == "__main__":
    ana()
