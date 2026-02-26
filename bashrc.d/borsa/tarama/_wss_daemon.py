"""Ziraat SignalR WSS daemon — canli fiyat verisi.

Arka planda calisarak SignalR WebSocket uzerinden canli fiyat
verisi alir ve tick dosyalarina yazar. Mum birlestirici bu
tick dosyalarini okuyarak OHLCV mumlari olusturur.

Kullanim:
    python3 _wss_daemon.py <hesap_no> [--sembol-dosyasi yol]

Dosyalar:
    PID:       /tmp/borsa/_wss/ziraat_<hesap>.pid
    Durum:     /tmp/borsa/_wss/ziraat_<hesap>.durum
    Log:       /tmp/borsa/_wss/ziraat_<hesap>.log
    Semboller: /tmp/borsa/_wss/ziraat_<hesap>.semboller
    Esleme:    /tmp/borsa/_sembol_fininstid.json
    Tickler:   /tmp/borsa/_wss/tickler/<SEMBOL>.tick

Sinyaller:
    SIGUSR1: Sembol listesini yeniden oku ve abonelikleri guncelle
    SIGTERM/SIGINT: Duzgun kapat
"""

import json
import logging
import os
import signal
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime
from http.cookiejar import MozillaCookieJar
from typing import Any

try:
    import websocket
except ImportError:
    print("HATA: websocket-client yuklu degil: pip install websocket-client")
    sys.exit(1)


# -------------------------------------------------------
# Sabitler
# -------------------------------------------------------

SIGNALR_SUNUCU = "veri.ziraatyatirim.com.tr"
SIGNALR_YOL = "/websocket/signalr"
SIGNALR_BASE = f"https://{SIGNALR_SUNUCU}{SIGNALR_YOL}"
ORIGIN = "https://esube1.ziraatyatirim.com.tr"
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)
HUBLAR = [{"name": "mdmchangeshub"}, {"name": "tschangemanager"}]

WSS_DIZIN = "/tmp/borsa/_wss"
TICK_DIZIN = "/tmp/borsa/_wss/tickler"
ESLEME_DOSYASI = "/tmp/borsa/_sembol_fininstid.json"

# Baglanti parametreleri
YENIDEN_BAGLANTI_BEKLE = 5  # saniye
KEEPALIVE_ARALIK = 15  # saniye (sunucu 20sn timeout)
MAKSIMUM_YENIDEN_DENEME = 50


# -------------------------------------------------------
# Logger
# -------------------------------------------------------


def log_ayarla(hesap: str) -> logging.Logger:
    """Logger olusturur."""
    logger = logging.getLogger("wss_daemon")
    logger.setLevel(logging.DEBUG)

    # Dosya handler
    log_dosya = os.path.join(WSS_DIZIN, f"ziraat_{hesap}.log")
    fh = logging.FileHandler(log_dosya, encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s %(message)s", "%H:%M:%S")
    )
    logger.addHandler(fh)

    # Stderr handler (sadece WARNING ve ustu)
    sh = logging.StreamHandler(sys.stderr)
    sh.setLevel(logging.WARNING)
    sh.setFormatter(logging.Formatter("%(levelname)s %(message)s"))
    logger.addHandler(sh)

    return logger


# -------------------------------------------------------
# Yardimci fonksiyonlar
# -------------------------------------------------------


def cookie_oku(hesap: str) -> str:
    """Ziraat cookie dosyasindan cookie dizesi olusturur."""
    cookie_dosyasi = f"/tmp/borsa/ziraat/{hesap}/cookies.txt"
    if not os.path.isfile(cookie_dosyasi):
        raise FileNotFoundError(f"Cookie dosyasi bulunamadi: {cookie_dosyasi}")

    cj = MozillaCookieJar(cookie_dosyasi)
    cj.load(ignore_discard=True, ignore_expires=True)
    return "; ".join(f"{c.name}={c.value}" for c in cj)


def esleme_yukle() -> dict[str, str]:
    """Sembol -> FinInstId esleme tablosunu yukler."""
    if not os.path.isfile(ESLEME_DOSYASI):
        return {}
    with open(ESLEME_DOSYASI, encoding="utf-8") as f:
        return json.load(f)


def ters_esleme_olustur(esleme: dict[str, str]) -> dict[str, str]:
    """FinInstId -> Sembol ters esleme tablosu."""
    return {v: k for k, v in esleme.items()}


def sembol_listesi_oku(hesap: str) -> list[str]:
    """Sembol dosyasindan aktif sembolleri okur."""
    dosya = os.path.join(WSS_DIZIN, f"ziraat_{hesap}.semboller")
    if not os.path.isfile(dosya):
        return []
    semboller: list[str] = []
    with open(dosya, encoding="utf-8") as f:
        for satir in f:
            s = satir.strip().upper()
            if s and not s.startswith("#"):
                semboller.append(s)
    return semboller


def durum_yaz(hesap: str, durum: dict[str, Any]) -> None:
    """Durum dosyasina JSON yazar."""
    dosya = os.path.join(WSS_DIZIN, f"ziraat_{hesap}.durum")
    durum["guncelleme"] = datetime.now().isoformat()
    with open(dosya, "w", encoding="utf-8") as f:
        json.dump(durum, f, ensure_ascii=False, indent=2)


def pid_yaz(hesap: str) -> None:
    """PID dosyasi olusturur."""
    dosya = os.path.join(WSS_DIZIN, f"ziraat_{hesap}.pid")
    with open(dosya, "w") as f:
        f.write(str(os.getpid()))


def pid_temizle(hesap: str) -> None:
    """PID dosyasini siler."""
    dosya = os.path.join(WSS_DIZIN, f"ziraat_{hesap}.pid")
    try:
        os.remove(dosya)
    except OSError:
        pass


def tick_yaz(sembol: str, fiyat: float, hacim: float) -> None:
    """Tick dosyasina yeni satir ekler.

    Format: epoch|fiyat|hacim
    """
    dosya = os.path.join(TICK_DIZIN, f"{sembol}.tick")
    epoch = int(time.time())
    with open(dosya, "a", encoding="utf-8") as f:
        f.write(f"{epoch}|{fiyat}|{int(hacim)}\n")


# -------------------------------------------------------
# SignalR HTTP islemleri
# -------------------------------------------------------


def http_istek(url: str, cookie: str) -> Any:
    """HTTP GET istegi gonderir, JSON doner."""
    req = urllib.request.Request(url)
    req.add_header("User-Agent", USER_AGENT)
    req.add_header("Origin", ORIGIN)
    req.add_header("Cookie", cookie)
    with urllib.request.urlopen(req, timeout=10) as yanit:
        return json.loads(yanit.read().decode())


def negotiate(cookie: str) -> dict[str, Any]:
    """SignalR negotiate istegi — ConnectionToken alir."""
    conn_data = urllib.parse.quote(json.dumps(HUBLAR))
    ts = int(time.time() * 1000)
    url = (
        f"{SIGNALR_BASE}/negotiate?clientProtocol=1.5&connectionData={conn_data}&_={ts}"
    )
    return http_istek(url, cookie)


def start_istegi(token_enc: str, cookie: str) -> dict[str, Any]:
    """SignalR start istegi — baglanti onaylar."""
    conn_data = urllib.parse.quote(json.dumps(HUBLAR))
    ts = int(time.time() * 1000)
    url = (
        f"{SIGNALR_BASE}/start"
        f"?transport=webSockets&clientProtocol=1.5"
        f"&connectionToken={token_enc}&connectionData={conn_data}&_={ts}"
    )
    return http_istek(url, cookie)


# -------------------------------------------------------
# WssDaemon sinifi
# -------------------------------------------------------


class WssDaemon:
    """SignalR WebSocket daemon."""

    def __init__(self, hesap: str) -> None:
        self.hesap = hesap
        self.log = log_ayarla(hesap)
        self.cookie = ""
        self.ws: websocket.WebSocket | None = None
        self.esleme: dict[str, str] = {}
        self.ters_esleme: dict[str, str] = {}
        self.aktif_semboller: set[str] = set()
        self.aktif_finids: set[str] = set()
        self.calissin = True
        self.sembol_yenile = False
        self.mesaj_sayaci = 0
        self.invoke_sayaci = 0
        self.son_mesaj_zamani = 0.0
        self.son_keepalive = 0.0
        self.baglanti_zamani = 0.0

    # --- Sinyal isleyicileri ---

    def _sinyal_ayarla(self) -> None:
        """SIGUSR1 ve SIGTERM isleyicilerini ayarlar."""
        signal.signal(signal.SIGUSR1, self._sigusr1_isleyici)
        signal.signal(signal.SIGTERM, self._kapatma_isleyici)
        signal.signal(signal.SIGINT, self._kapatma_isleyici)

    def _sigusr1_isleyici(self, _sig: int, _frame: Any) -> None:
        """SIGUSR1 gelince sembol listesini yeniden oku."""
        self.log.info("SIGUSR1 alindi — sembol listesi yenilenecek")
        self.sembol_yenile = True

    def _kapatma_isleyici(self, _sig: int, _frame: Any) -> None:
        """SIGTERM/SIGINT gelince duzgun kapat."""
        self.log.info("Kapatma sinyali alindi")
        self.calissin = False

    # --- SignalR mesaj gonderme ---

    def _mesaj_gonder(self, hub: str, metod: str, args: list[Any]) -> int:
        """SignalR hub'a mesaj gonderir."""
        if not self.ws:
            return -1
        iid = self.invoke_sayaci
        self.invoke_sayaci += 1
        mesaj = {"H": hub, "M": metod, "A": args, "I": iid}
        self.ws.send(json.dumps(mesaj))
        return iid

    def _gruplara_katil(self, finids: list[str]) -> None:
        """Verilen FinInstId'lere abone ol."""
        if not finids:
            return
        # tsChangeManager.JoinGroup — canli fiyat
        self._mesaj_gonder("tschangemanager", "JoinGroup", [finids])
        # mdmChangesHub.JoinGroupDelayed — geciken veri (tavan/taban vb.)
        self._mesaj_gonder("mdmchangeshub", "JoinGroupDelayed", [finids])
        self.log.info("JoinGroup: %d enstruman", len(finids))

    def _gruplardan_ayril(self, finids: list[str]) -> None:
        """Verilen FinInstId'lerden aboneligi kald."""
        if not finids:
            return
        self._mesaj_gonder("tschangemanager", "LeaveGroup", [finids])
        self._mesaj_gonder("mdmchangeshub", "LeaveGroupDelayed", [finids])
        self.log.info("LeaveGroup: %d enstruman", len(finids))

    def _ping_gonder(self) -> None:
        """tsChangeManager.Ping keepalive."""
        self._mesaj_gonder("tschangemanager", "Ping", ["wss_daemon"])

    # --- Sembol yonetimi ---

    def _sembolleri_guncelle(self) -> None:
        """Sembol dosyasindan okur, abonelikleri gunceller."""
        yeni_semboller = set(sembol_listesi_oku(self.hesap))

        # Esleme tablosunda olmayan sembolleri uyar
        eslenmeyenler = yeni_semboller - set(self.esleme.keys())
        if eslenmeyenler:
            self.log.warning(
                "Esleme tablosunda yok, atlanacak: %s",
                ", ".join(sorted(eslenmeyenler)),
            )
            yeni_semboller -= eslenmeyenler

        yeni_finids = {self.esleme[s] for s in yeni_semboller}

        # Fark hesapla
        eklenecek = yeni_finids - self.aktif_finids
        cikarilacak = self.aktif_finids - yeni_finids

        if cikarilacak:
            self._gruplardan_ayril(list(cikarilacak))
        if eklenecek:
            self._gruplara_katil(list(eklenecek))

        self.aktif_semboller = yeni_semboller
        self.aktif_finids = yeni_finids
        self.sembol_yenile = False

        self.log.info("Semboller guncellendi: %d aktif", len(self.aktif_semboller))

    # --- Mesaj isleme ---

    def _mesaj_isle(self, ham: str) -> None:
        """Gelen SignalR mesajini isle."""
        if not ham or not ham.strip():
            return

        try:
            veri = json.loads(ham)
        except json.JSONDecodeError:
            return

        # Hub mesajlari
        if "M" in veri and veri["M"]:
            for m in veri["M"]:
                metod = m.get("M", "")
                args = m.get("A", [])

                if metod == "getChanges" and args:
                    self._tick_isle(args[0])
                elif metod == "mdmGetChanges" and args:
                    # Geciken veri — kullanilmiyor ama loglanir
                    pass

        # Invocation yaniti
        if "R" in veri:
            iid = veri.get("I", "?")
            self.log.debug("Yanit I=%s: %s", iid, str(veri.get("R"))[:100])

        # Hata
        if "E" in veri:
            self.log.error("SignalR hata: %s", veri["E"])

    def _tick_isle(self, degisiklikler: list[dict[str, Any]] | dict[str, Any]) -> None:
        """getChanges mesajlarindan tick verisi cikarir.

        Her degisiklik objesi asagidaki alanlari icerebilir:
            L = Son fiyat (LastPrice)
            V = Hacim (Volume)
            I = FinInstId
            U = Guncelleme zamani (ISO)
        """
        if isinstance(degisiklikler, dict):
            degisiklikler = [degisiklikler]

        for d in degisiklikler:
            finid = d.get("I", "")
            fiyat = d.get("L", 0.0)
            hacim = d.get("V", 0.0)

            if not finid:
                continue

            # Sifir fiyat — sadece degisim bilgisi gelmis olabilir, atla
            if not fiyat or fiyat == 0.0:
                continue

            sembol = self.ters_esleme.get(finid, "")
            if not sembol:
                # Abone olmadigi bir enstrumandan veri gelmis
                continue

            # Tick dosyasina yaz
            tick_yaz(sembol, fiyat, hacim)
            self.mesaj_sayaci += 1
            self.son_mesaj_zamani = time.time()

    # --- Baglanti ---

    def _baglan(self) -> bool:
        """SignalR WebSocket baglantisi kurar."""
        try:
            self.cookie = cookie_oku(self.hesap)
        except FileNotFoundError as e:
            self.log.error("Cookie hatasi: %s", e)
            return False

        # Esleme tablosunu yukle
        self.esleme = esleme_yukle()
        self.ters_esleme = ters_esleme_olustur(self.esleme)
        if not self.esleme:
            self.log.error("Esleme tablosu bos: %s", ESLEME_DOSYASI)
            return False
        self.log.info("Esleme tablosu: %d sembol", len(self.esleme))

        # Negotiate
        try:
            neg = negotiate(self.cookie)
        except Exception as e:
            self.log.error("Negotiate hatasi: %s", e)
            return False

        conn_id = neg.get("ConnectionId", "?")
        self.log.info("Negotiate basarili — ConnectionId: %s", conn_id)

        # WebSocket baglantisi
        conn_data = urllib.parse.quote(json.dumps(HUBLAR))
        token_enc = urllib.parse.quote(neg["ConnectionToken"])
        wss_url = (
            f"wss://{SIGNALR_SUNUCU}{SIGNALR_YOL}/connect"
            f"?transport=webSockets&clientProtocol=1.5"
            f"&connectionToken={token_enc}&connectionData={conn_data}&tid=1"
        )

        try:
            self.ws = websocket.create_connection(
                wss_url,
                header=[
                    f"User-Agent: {USER_AGENT}",
                    f"Origin: {ORIGIN}",
                    f"Cookie: {self.cookie}",
                ],
                timeout=10,
            )
        except Exception as e:
            self.log.error("WSS baglanti hatasi: %s", e)
            return False

        # Init mesajini oku
        try:
            init = self.ws.recv()
            self.log.debug("Init: %s", init[:150] if init else "(bos)")
        except Exception:
            pass

        # Start istegi
        try:
            sonuc = start_istegi(token_enc, self.cookie)
            if sonuc.get("Response") != "started":
                self.log.error("Start basarisiz: %s", sonuc)
                return False
        except Exception as e:
            self.log.error("Start hatasi: %s", e)
            return False

        self.log.info("WSS baglantisi basarili")
        self.baglanti_zamani = time.time()
        self.invoke_sayaci = 0

        # Sembollere abone ol
        self._sembolleri_guncelle()

        # Ping gonder
        self._ping_gonder()
        self.son_keepalive = time.time()

        # Durum guncelle
        durum_yaz(
            self.hesap,
            {
                "durum": "BAGLI",
                "baglanti": conn_id,
                "sembol_sayisi": len(self.aktif_semboller),
                "semboller": sorted(self.aktif_semboller),
            },
        )

        return True

    def _baglanti_kapat(self) -> None:
        """WebSocket baglantisini kapatir."""
        if self.ws:
            try:
                self.ws.close()
            except Exception:
                pass
            self.ws = None

        durum_yaz(
            self.hesap,
            {
                "durum": "KOPUK",
                "mesaj_sayaci": self.mesaj_sayaci,
            },
        )

    # --- Ana dongu ---

    def calistir(self) -> None:
        """Daemon ana dongusu."""
        self._sinyal_ayarla()
        pid_yaz(self.hesap)

        # Dizinleri olustur
        os.makedirs(TICK_DIZIN, exist_ok=True)
        os.makedirs(WSS_DIZIN, exist_ok=True)

        self.log.info(
            "WSS daemon baslatildi (PID: %d, hesap: %s)", os.getpid(), self.hesap
        )

        deneme = 0

        while self.calissin and deneme < MAKSIMUM_YENIDEN_DENEME:
            # Baglan
            if not self._baglan():
                deneme += 1
                bekle = min(YENIDEN_BAGLANTI_BEKLE * deneme, 60)
                self.log.warning(
                    "Baglanti basarisiz, %d/%d deneme — %dsn beklenecek",
                    deneme,
                    MAKSIMUM_YENIDEN_DENEME,
                    bekle,
                )
                durum_yaz(
                    self.hesap,
                    {
                        "durum": "YENIDEN_BAGLANIYOR",
                        "deneme": deneme,
                        "sonraki_deneme": bekle,
                    },
                )
                time.sleep(bekle)
                continue

            # Basarili baglanti — deneme sayacini sifirla
            deneme = 0

            # Mesaj dinleme dongusu
            try:
                self._dinle_dongusu()
            except Exception as e:
                self.log.error("Dinle dongusu hatasi: %s", e)

            self._baglanti_kapat()

            # Calissin=False ise donguden cik
            if not self.calissin:
                break

            # Yeniden baglanti bekle
            self.log.info("Yeniden baglaniliyor...")
            time.sleep(YENIDEN_BAGLANTI_BEKLE)

        # Temizlik
        self._baglanti_kapat()
        pid_temizle(self.hesap)
        durum_yaz(
            self.hesap,
            {
                "durum": "DURDURULDU",
                "mesaj_sayaci": self.mesaj_sayaci,
            },
        )
        self.log.info(
            "WSS daemon durduruldu — toplam %d mesaj islendi",
            self.mesaj_sayaci,
        )

    def _dinle_dongusu(self) -> None:
        """WebSocket mesajlarini dinler."""
        if not self.ws:
            return

        self.ws.settimeout(2)

        while self.calissin:
            # Sembol yenileme kontrolu
            if self.sembol_yenile:
                self._sembolleri_guncelle()

            # Mesaj al
            try:
                ham = self.ws.recv()
                if ham:
                    self._mesaj_isle(ham)
            except websocket.WebSocketTimeoutException:
                pass
            except websocket.WebSocketConnectionClosedException:
                self.log.warning("WSS baglantisi kapandi")
                break
            except Exception as e:
                self.log.error("Mesaj alma hatasi: %s", e)
                break

            # Keepalive
            simdi = time.time()
            if simdi - self.son_keepalive >= KEEPALIVE_ARALIK:
                try:
                    self._ping_gonder()
                    self.son_keepalive = simdi
                except Exception:
                    self.log.warning("Ping gonderilemedi — baglanti kopmus olabilir")
                    break

            # Periyodik durum guncelleme (her 30sn)
            if self.mesaj_sayaci > 0 and self.mesaj_sayaci % 100 == 0:
                durum_yaz(
                    self.hesap,
                    {
                        "durum": "BAGLI",
                        "sembol_sayisi": len(self.aktif_semboller),
                        "mesaj_sayaci": self.mesaj_sayaci,
                        "son_mesaj": datetime.fromtimestamp(
                            self.son_mesaj_zamani
                        ).strftime("%H:%M:%S"),
                        "calisan_sure": int(simdi - self.baglanti_zamani),
                    },
                )


# -------------------------------------------------------
# Giris noktasi
# -------------------------------------------------------


def main() -> None:
    """Daemon'u baslatir."""
    if len(sys.argv) < 2:
        print("Kullanim: python3 _wss_daemon.py <hesap_no>")
        print("  Sembol listesi: /tmp/borsa/_wss/ziraat_<hesap>.semboller")
        sys.exit(1)

    hesap = sys.argv[1]

    # PID kontrolu — zaten calisiyor mu
    pid_dosya = os.path.join(WSS_DIZIN, f"ziraat_{hesap}.pid")
    if os.path.isfile(pid_dosya):
        with open(pid_dosya) as f:
            eski_pid = f.read().strip()
        if eski_pid:
            try:
                os.kill(int(eski_pid), 0)
                print(f"HATA: WSS daemon zaten calisiyor (PID: {eski_pid})")
                sys.exit(1)
            except (OSError, ValueError):
                pass  # Eski proses olmus, devam et

    daemon = WssDaemon(hesap)
    daemon.calistir()


if __name__ == "__main__":
    main()
