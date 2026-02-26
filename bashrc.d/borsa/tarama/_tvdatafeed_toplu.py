"""BIST OHLCV toplu cekim ve tamir araci.

tvDatafeed ile BIST hisselerinin OHLCV verilerini ceker ve Supabase'e yazar.
Iki modda calisir:

1. Ilk dolum (varsayilan):
   Tum hisseler, tum periyotlar, 5000 bar — tek seferlik.
   python3 _tvdatafeed_toplu.py

2. Tamir modu:
   Gunluk tamir dongusu — eksik/hatali mumlari duzeltir.
   python3 _tvdatafeed_toplu.py --tamir

Ilerleme /tmp/borsa/_ohlcv_ilk_dolum/ilerleme.json'da tutulur.
Kesilirse kaldigi yerden devam eder.
"""

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

# -------------------------------------------------------
# Yapilandirma
# -------------------------------------------------------

# Supabase baglanti bilgileri (supabase.ayarlar.sh'tan okunur veya env'den)
SUPABASE_URL = os.environ.get("SUPABASE_URL", "http://localhost:8001")
SUPABASE_ANAHTAR = os.environ.get("SUPABASE_ANAHTAR", "")

# Ayarlar dosyasindan oku (env yoksa)
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

# Dosya yollari
ILERLEME_DIZIN = "/tmp/borsa/_ohlcv_ilk_dolum"
ILERLEME_DOSYASI = os.path.join(ILERLEME_DIZIN, "ilerleme.json")
HATALAR_DOSYASI = os.path.join(ILERLEME_DIZIN, "hatalar.json")
SEMBOL_DOSYASI = "/tmp/borsa/_ohlcv/semboller.txt"

# tvDatafeed ayarlari
ISTEK_BEKLEME = 1.0  # saniye — rate limit korumasi
MAKS_DENEME = 1  # timeout semboller icin tek deneme yeter, tamir halleder
BAR_SAYISI = 5000
CEKIM_ZAMAN_ASIMI = 25  # subprocess zaman asimi (saniye) — basarili istekler <5sn

# Supabase batch ayarlari
BATCH_BOYUTU = 500  # tek POST'taki satir sayisi

# Periyot oncelik sirasi (ilk dolum icin) — sadece periyot kodu
PERIYOT_ONCELIK: list[str] = [
    "1G", "1S", "1H", "1A", "4S", "3S", "2S",
    "30dk", "15dk", "45dk", "5dk", "3dk", "1dk",
]

# Tamir modu icin cekim miktarlari
TAMIR_BAR_SAYILARI: dict[str, int] = {
    "1dk": 500,
    "3dk": 200,
    "5dk": 100,
    "15dk": 50,
    "30dk": 30,
    "45dk": 20,
    "1S": 10,
    "2S": 10,
    "3S": 10,
    "4S": 10,
    "1G": 5,
    "1H": 5,
    "1A": 3,
}


# -------------------------------------------------------
# Supabase islemleri
# -------------------------------------------------------

def supabase_istek(
    metod: str,
    yol: str,
    veri: str | None = None,
    ek_basliklar: dict[str, str] | None = None,
) -> tuple[int, str]:
    """Supabase REST API'ye istek atar.

    Args:
        metod: HTTP metodu (GET, POST, PATCH).
        yol: API yolu (ornek: "ohlcv" veya "ohlcv?sembol=eq.THYAO").
        veri: POST/PATCH icin JSON govde.
        ek_basliklar: Ek HTTP baslik bilgileri.

    Returns:
        (http_kodu, yanit_govdesi) tuple'i.
    """
    url = f"{SUPABASE_URL}/rest/v1/{yol}"
    basliklar = {
        "apikey": SUPABASE_ANAHTAR,
        "Authorization": f"Bearer {SUPABASE_ANAHTAR}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    if ek_basliklar:
        basliklar.update(ek_basliklar)

    try:
        if metod == "GET":
            yanit = requests.get(url, headers=basliklar, timeout=30)
        elif metod == "POST":
            yanit = requests.post(url, headers=basliklar, data=veri, timeout=60)
        elif metod == "PATCH":
            yanit = requests.patch(url, headers=basliklar, data=veri, timeout=30)
        else:
            return 400, "Gecersiz metod"
        return yanit.status_code, yanit.text
    except requests.RequestException as hata:
        return 0, str(hata)


def supabase_toplu_yaz(satirlar: list[dict]) -> bool:
    """OHLCV satirlarini Supabase'e batch olarak yazar (UPSERT).

    Args:
        satirlar: OHLCV satir listesi.

    Returns:
        True basarili, False basarisiz.
    """
    if not satirlar:
        return True

    json_veri = json.dumps(satirlar, ensure_ascii=False)
    http_kodu, yanit = supabase_istek(
        "POST",
        "ohlcv",
        json_veri,
        {"Prefer": "resolution=merge-duplicates,return=minimal"},
    )

    if 200 <= http_kodu < 300:
        return True

    sys.stderr.write(
        f"HATA: Supabase toplu yazma basarisiz — HTTP {http_kodu}: {yanit[:200]}\n"
    )
    return False


def supabase_baglanti_kontrol() -> bool:
    """Supabase erisimini kontrol eder."""
    http_kodu, _ = supabase_istek("GET", "ohlcv?limit=0")
    return 200 <= http_kodu < 300


# -------------------------------------------------------
# Ilerleme yonetimi
# -------------------------------------------------------

def ilerleme_oku() -> dict:
    """Ilerleme dosyasini okur."""
    if os.path.isfile(ILERLEME_DOSYASI):
        try:
            with open(ILERLEME_DOSYASI, encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {"_ozet": {"toplam": 0, "tamam": 0, "hata": 0, "baslangic": ""}}


def ilerleme_yaz(ilerleme: dict) -> None:
    """Ilerleme dosyasini yazar."""
    os.makedirs(ILERLEME_DIZIN, exist_ok=True)
    gecici = ILERLEME_DOSYASI + ".tmp"
    with open(gecici, "w", encoding="utf-8") as f:
        json.dump(ilerleme, f, ensure_ascii=False, indent=2)
    os.replace(gecici, ILERLEME_DOSYASI)


def hata_kaydet(sembol: str, periyot: str, mesaj: str) -> None:
    """Basarisiz cekim hatasini kaydeder."""
    hatalar: dict = {}
    if os.path.isfile(HATALAR_DOSYASI):
        try:
            with open(HATALAR_DOSYASI, encoding="utf-8") as f:
                hatalar = json.load(f)
        except (json.JSONDecodeError, OSError):
            pass

    anahtar = f"{sembol}_{periyot}"
    mevcut = hatalar.get(anahtar, {"deneme": 0})
    mevcut["deneme"] = mevcut.get("deneme", 0) + 1
    mevcut["son_hata"] = mesaj
    mevcut["zaman"] = datetime.now(timezone.utc).isoformat()
    hatalar[anahtar] = mevcut

    os.makedirs(ILERLEME_DIZIN, exist_ok=True)
    with open(HATALAR_DOSYASI, "w", encoding="utf-8") as f:
        json.dump(hatalar, f, ensure_ascii=False, indent=2)


# -------------------------------------------------------
# Sembol listesi
# -------------------------------------------------------

def sembolleri_oku() -> list[str]:
    """Sembol dosyasini okur. Yoksa KAP'tan ceker."""
    if os.path.isfile(SEMBOL_DOSYASI):
        with open(SEMBOL_DOSYASI, encoding="utf-8") as f:
            semboller = [s.strip() for s in f if s.strip()]
        if len(semboller) > 100:
            return semboller

    # Sembol dosyasi yok — KAP'tan cek
    sys.stderr.write("Sembol dosyasi bulunamadi, KAP'tan cekiliyor...\n")
    betik_dizin = os.path.dirname(os.path.abspath(__file__))
    sembol_betik = os.path.join(betik_dizin, "_bist_sembol_listesi.py")
    os.system(f"{sys.executable} {sembol_betik}")

    if os.path.isfile(SEMBOL_DOSYASI):
        with open(SEMBOL_DOSYASI, encoding="utf-8") as f:
            return [s.strip() for s in f if s.strip()]

    sys.stderr.write("HATA: Sembol listesi olusturulamadi\n")
    return []


# -------------------------------------------------------
# tvDatafeed veri cekimi (subprocess ile)
# -------------------------------------------------------

# _tvdatafeed_cagir.py betiginin yolu
_CAGIR_BETIK = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "_tvdatafeed_cagir.py",
)

# Subprocess icin Python yorumlayicisi
_PYTHON = sys.executable


def tek_hisse_cek(
    sembol: str,
    periyot_kodu: str,
    bar_sayisi: int,
) -> list[dict]:
    """Tek hisse icin OHLCV verisini subprocess'te ceker.

    Her cekim ayri surec — SSL timeout sorunu yok.

    Args:
        sembol: Hisse semboulu.
        periyot_kodu: Bash periyot kodu (1G, 1S vb).
        bar_sayisi: Cekilecek bar sayisi.

    Returns:
        Supabase'e yazilacak satir listesi.
    """
    for deneme in range(MAKS_DENEME):
        try:
            sonuc = subprocess.run(
                [_PYTHON, _CAGIR_BETIK, sembol, periyot_kodu, str(bar_sayisi)],
                capture_output=True,
                text=True,
                timeout=CEKIM_ZAMAN_ASIMI,
            )

            if sonuc.returncode != 0:
                if deneme < MAKS_DENEME - 1:
                    bekle = 3 * (deneme + 1)
                    time.sleep(bekle)
                    continue
                return []

            # CSV ciktisini parse et
            satirlar: list[dict] = []
            for satir in sonuc.stdout.strip().split("\n"):
                if not satir.strip():
                    continue
                parcalar = satir.split(",")
                if len(parcalar) < 6:
                    continue
                tarih_ham = parcalar[0].strip()
                # tarih formatini Supabase'e uygun formata cevir
                tarih_str = tarih_ham.replace(" ", "T") + "+03:00"
                satirlar.append({
                    "sembol": sembol,
                    "periyot": periyot_kodu,
                    "tarih": tarih_str,
                    "acilis": round(float(parcalar[1]), 4),
                    "yuksek": round(float(parcalar[2]), 4),
                    "dusuk": round(float(parcalar[3]), 4),
                    "kapanis": round(float(parcalar[4]), 4),
                    "hacim": int(float(parcalar[5])),
                    "kaynak": "tvdata",
                })

            return satirlar

        except subprocess.TimeoutExpired:
            sys.stderr.write(
                f"  UYARI: {sembol}/{periyot_kodu} "
                f"zaman asimi ({CEKIM_ZAMAN_ASIMI}sn) "
                f"deneme {deneme + 1}/{MAKS_DENEME}\n"
            )
            if deneme < MAKS_DENEME - 1:
                time.sleep(3 * (deneme + 1))
            else:
                hata_kaydet(sembol, periyot_kodu, "zaman_asimi")

        except Exception as hata:
            if deneme < MAKS_DENEME - 1:
                bekle = 3 * (deneme + 1)
                sys.stderr.write(
                    f"  UYARI: {sembol}/{periyot_kodu} "
                    f"deneme {deneme + 1}/{MAKS_DENEME} -- {hata} "
                    f"({bekle}sn bekleniyor)\n"
                )
                time.sleep(bekle)
            else:
                hata_kaydet(sembol, periyot_kodu, str(hata))
                sys.stderr.write(f"  HATA: {sembol}/{periyot_kodu} -- {hata}\n")

    return []


# -------------------------------------------------------
# Ilk dolum
# -------------------------------------------------------

def ilk_dolum() -> None:
    """Tum BIST hisseleri icin tum periyotlarda ilk dolumu yapar."""
    semboller = sembolleri_oku()
    if not semboller:
        sys.stderr.write("HATA: Sembol listesi bos\n")
        sys.exit(1)

    # Supabase baglanti kontrolu
    if not supabase_baglanti_kontrol():
        sys.stderr.write("HATA: Supabase'e erisilemedi\n")
        sys.exit(1)

    ilerleme = ilerleme_oku()
    if not ilerleme.get("_ozet", {}).get("baslangic"):
        ilerleme["_ozet"] = {
            "toplam": len(semboller) * len(PERIYOT_ONCELIK),
            "tamam": 0,
            "hata": 0,
            "baslangic": datetime.now(timezone.utc).isoformat(),
        }

    toplam_gorev = len(semboller) * len(PERIYOT_ONCELIK)

    # Restart'ta tamam_sayisi'ni ilerleme verisinden dogru hesapla
    tamam_sayisi = 0
    hata_sayisi = 0
    for sem_adi, sem_veri in ilerleme.items():
        if sem_adi == "_ozet" or not isinstance(sem_veri, dict):
            continue
        for _p_kodu, durum in sem_veri.items():
            if durum in ("tamam", "bos"):
                tamam_sayisi += 1
            if durum == "bos":
                hata_sayisi += 1

    # Onceki calismalarda timeout olan sembolleri kara listeye al
    # Bu semboller diger periyotlarda da timeout olur, atlanarak zaman kazanilir
    kara_liste: set[str] = set()
    for sem_adi, sem_veri in ilerleme.items():
        if sem_adi == "_ozet" or not isinstance(sem_veri, dict):
            continue
        for durum in sem_veri.values():
            if durum == "bos":
                kara_liste.add(sem_adi)
                break

    # _ozet'i guncelle
    ilerleme["_ozet"]["tamam"] = tamam_sayisi
    ilerleme["_ozet"]["hata"] = hata_sayisi
    ilerleme_yaz(ilerleme)

    sys.stderr.write(
        f"ILK DOLUM BASLIYOR\n"
        f"  Sembol: {len(semboller)}\n"
        f"  Periyot: {len(PERIYOT_ONCELIK)}\n"
        f"  Toplam gorev: {toplam_gorev}\n"
        f"  Onceden tamamlanan: {tamam_sayisi}\n"
        f"  Bar/istek: {BAR_SAYISI}\n"
        f"\n"
    )

    baslangic_zamani = time.time()

    for periyot_kodu in PERIYOT_ONCELIK:
        sys.stderr.write(f"\n[{periyot_kodu}] baslaniyor...\n")

        for sira, sembol in enumerate(semboller, 1):
            # Onceden tamamlanmis mi? (tamam veya bos — bos olanlari tamir halleder)
            sem_durum = ilerleme.get(sembol, {})
            if sem_durum.get(periyot_kodu) in ("tamam", "bos"):
                continue

            # Kara listedeki sembol — tum periyotlarda bos isaretle ve atla
            if sembol in kara_liste:
                ilerleme.setdefault(sembol, {})[periyot_kodu] = "bos"
                tamam_sayisi += 1
                hata_sayisi += 1
                ilerleme["_ozet"]["tamam"] = tamam_sayisi
                ilerleme["_ozet"]["hata"] = hata_sayisi
                ilerleme_yaz(ilerleme)
                continue

            # Cekim (subprocess ile)
            ilerleme.setdefault(sembol, {})[periyot_kodu] = "devam"
            satirlar = tek_hisse_cek(sembol, periyot_kodu, BAR_SAYISI)

            if satirlar:
                # Batch halinde Supabase'e yaz
                for i in range(0, len(satirlar), BATCH_BOYUTU):
                    batch = satirlar[i : i + BATCH_BOYUTU]
                    if not supabase_toplu_yaz(batch):
                        hata_kaydet(sembol, periyot_kodu, "supabase_yazma_hatasi")
                        hata_sayisi += 1

                ilerleme[sembol][periyot_kodu] = "tamam"
                tamam_sayisi += 1
            else:
                ilerleme[sembol][periyot_kodu] = "bos"
                tamam_sayisi += 1
                hata_sayisi += 1
                # Ilk basarisizlikta kara listeye al — sonraki periyotlarda atla
                kara_liste.add(sembol)

            # Ilerleme guncelle
            ilerleme["_ozet"]["tamam"] = tamam_sayisi
            ilerleme["_ozet"]["hata"] = hata_sayisi
            ilerleme_yaz(ilerleme)

            # Ilerleme gostergesi
            gecen = time.time() - baslangic_zamani
            hiz = tamam_sayisi / gecen if gecen > 0 else 0
            kalan = (toplam_gorev - tamam_sayisi) / hiz if hiz > 0 else 0
            kalan_dk = int(kalan / 60)

            sys.stderr.write(
                f"\r  [{periyot_kodu}] {sembol} "
                f"{sira}/{len(semboller)} — "
                f"{satirlar and len(satirlar) or 0} bar — "
                f"toplam: %{100 * tamam_sayisi / toplam_gorev:.1f} — "
                f"kalan: ~{kalan_dk}dk   "
            )

            # Rate limit bekleme
            time.sleep(ISTEK_BEKLEME)

        sys.stderr.write(f"\n[{periyot_kodu}] TAMAMLANDI\n")

    # Ozet
    toplam_sure = time.time() - baslangic_zamani
    sys.stderr.write(
        f"\n{'=' * 50}\n"
        f"ILK DOLUM TAMAMLANDI\n"
        f"  Toplam sure: {toplam_sure / 3600:.1f} saat\n"
        f"  Tamamlanan: {tamam_sayisi}/{toplam_gorev}\n"
        f"  Hata: {hata_sayisi}\n"
        f"{'=' * 50}\n"
    )


# -------------------------------------------------------
# Tamir modu
# -------------------------------------------------------

def tamir_listesi_oku() -> dict[str, list[str]]:
    """Takip listesini okur. Yoksa tum hisseleri 1G ile doner.

    Returns:
        Sembol -> periyot listesi eslesmesi.
    """
    takip_dosyasi = "/tmp/borsa/_takip/takip.json"
    takip: dict[str, list[str]] = {}

    if os.path.isfile(takip_dosyasi):
        try:
            with open(takip_dosyasi, encoding="utf-8") as f:
                takip = json.load(f)
        except (json.JSONDecodeError, OSError):
            pass

    return takip


def tamir() -> None:
    """Gunluk tamir dongusunu calistirir.

    Asama 1: Takip listesindeki hisseler tum periyotlarda tamir edilir.
    Asama 2: Tum BIST hisseleri sadece 1G periyodunda tamir edilir.
    """
    semboller = sembolleri_oku()
    if not semboller:
        sys.stderr.write("HATA: Sembol listesi bos\n")
        sys.exit(1)

    if not supabase_baglanti_kontrol():
        sys.stderr.write("HATA: Supabase'e erisilemedi\n")
        sys.exit(1)

    takip = tamir_listesi_oku()

    tv = None  # subprocess kullaniyor, tv nesnesi gerekmiyor

    tamir_istatistik = {"eklenen": 0, "guncellenen": 0, "degismeyen": 0}

    # ASAMA 1: Takip listesi — detayli tamir
    if takip:
        sys.stderr.write(
            f"\nTAMIR ASAMA 1: Takip listesi ({len(takip)} hisse)\n"
        )
        for sembol, periyotlar in takip.items():
            for periyot_kodu in periyotlar:
                if periyot_kodu not in TAMIR_BAR_SAYILARI:
                    continue
                bar = TAMIR_BAR_SAYILARI.get(periyot_kodu, 10)
                sys.stderr.write(f"  {sembol}/{periyot_kodu} -- {bar} bar... ")

                satirlar = tek_hisse_cek(sembol, periyot_kodu, bar)
                if satirlar:
                    supabase_toplu_yaz(satirlar)
                    tamir_istatistik["eklenen"] += len(satirlar)
                    sys.stderr.write(f"{len(satirlar)} mum\n")
                else:
                    sys.stderr.write("bos\n")

                time.sleep(ISTEK_BEKLEME)

    # ASAMA 2: Tum BIST — sadece 1G
    sys.stderr.write(f"\nTAMIR ASAMA 2: Tum BIST 1G ({len(semboller)} hisse)\n")
    for sira, sembol in enumerate(semboller, 1):
        satirlar = tek_hisse_cek(sembol, "1G", 5)
        if satirlar:
            supabase_toplu_yaz(satirlar)
            tamir_istatistik["eklenen"] += len(satirlar)

        if sira % 50 == 0:
            sys.stderr.write(f"  {sira}/{len(semboller)} tamamlandi\n")

        time.sleep(ISTEK_BEKLEME)

    # Rapor
    bugun = datetime.now(timezone.utc).strftime("%d.%m.%Y")
    sys.stderr.write(
        f"\n{'=' * 50}\n"
        f"{bugun} tamir raporu:\n"
        f"  Takip listesi: {len(takip)} hisse\n"
        f"  Genel (1G): {len(semboller)} hisse\n"
        f"  Toplam islenen mum: {tamir_istatistik['eklenen']}\n"
        f"{'=' * 50}\n"
    )


# -------------------------------------------------------
# Giris noktasi
# -------------------------------------------------------

def ana() -> None:
    """Komut satiri giris noktasi."""
    if "--tamir" in sys.argv:
        tamir()
    elif "--yardim" in sys.argv or "-h" in sys.argv:
        sys.stderr.write(
            "Kullanim:\n"
            "  python3 _tvdatafeed_toplu.py          Ilk dolum (tum hisseler)\n"
            "  python3 _tvdatafeed_toplu.py --tamir   Gunluk tamir dongusu\n"
            "  python3 _tvdatafeed_toplu.py --yardim  Bu yardim mesaji\n"
        )
    else:
        ilk_dolum()


if __name__ == "__main__":
    ana()
