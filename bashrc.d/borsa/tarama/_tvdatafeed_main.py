import datetime
import enum
import json
import logging
import random
import re
import socket
import string
import struct
import pandas as pd
from websocket import create_connection
import requests

logger = logging.getLogger(__name__)


class Interval(enum.Enum):
    in_1_minute = "1"
    in_3_minute = "3"
    in_5_minute = "5"
    in_15_minute = "15"
    in_30_minute = "30"
    in_45_minute = "45"
    in_1_hour = "1H"
    in_2_hour = "2H"
    in_3_hour = "3H"
    in_4_hour = "4H"
    in_daily = "1D"
    in_weekly = "1W"
    in_monthly = "1M"


class TvDatafeed:
    __sign_in_url = "https://www.tradingview.com/accounts/signin/"
    __search_url = "https://symbol-search.tradingview.com/symbol_search/?text={}&hl=1&exchange={}&lang=en&type=&domain=production"
    __ws_headers = json.dumps({"Origin": "https://data.tradingview.com"})
    __signin_headers = {"Referer": "https://www.tradingview.com"}
    __ws_timeout = 5

    def __init__(
        self,
        username: str = None,
        password: str = None,
    ) -> None:
        """Create TvDatafeed object

        Args:
            username (str, optional): tradingview username. Defaults to None.
            password (str, optional): tradingview password. Defaults to None.
        """

        self.ws_debug = False

        self.token = self.__auth(username, password)

        if self.token is None:
            self.token = "unauthorized_user_token"
            logger.warning(
                "you are using nologin method, data you access may be limited"
            )

        self.ws = None
        self.session = self.__generate_session()
        self.chart_session = self.__generate_chart_session()

    def __auth(self, username, password):
        if username is None or password is None:
            token = None

        else:
            data = {"username": username, "password": password, "remember": "on"}
            try:
                response = requests.post(
                    url=self.__sign_in_url, data=data, headers=self.__signin_headers
                )
                token = response.json()["user"]["auth_token"]
            except Exception:
                logger.error("error while signin")
                token = None

        return token

    def __create_connection(self):
        logging.debug("creating websocket connection")
        if self.ws is not None:
            try:
                self.ws.close()
            except Exception:
                pass
        self.ws = create_connection(
            "wss://data.tradingview.com/socket.io/websocket",
            headers=self.__ws_headers,
            timeout=self.__ws_timeout,
        )
        # Kernel duzeyinde recv zaman asimi — SSL_read bloklansa bile keser
        if self.ws.sock:
            zaman_asimi_sn = self.__ws_timeout
            timeval = struct.pack("ll", zaman_asimi_sn, 0)
            self.ws.sock.setsockopt(
                socket.SOL_SOCKET,
                socket.SO_RCVTIMEO,
                timeval,
            )

    @staticmethod
    def __filter_raw_message(text):
        try:
            found = re.search(r'"m":"(.+?)",', text).group(1)
            found2 = re.search(r'"p":(.+?)"}"]})', text).group(1)

            return found, found2
        except AttributeError:
            logger.error("error in filter_raw_message")

    @staticmethod
    def __generate_session():
        stringLength = 12
        letters = string.ascii_lowercase
        random_string = "".join(random.choice(letters) for i in range(stringLength))
        return "qs_" + random_string

    @staticmethod
    def __generate_chart_session():
        stringLength = 12
        letters = string.ascii_lowercase
        random_string = "".join(random.choice(letters) for i in range(stringLength))
        return "cs_" + random_string

    @staticmethod
    def __prepend_header(st):
        return "~m~" + str(len(st)) + "~m~" + st

    @staticmethod
    def __construct_message(func, param_list):
        return json.dumps({"m": func, "p": param_list}, separators=(",", ":"))

    def __create_message(self, func, paramList):
        return self.__prepend_header(self.__construct_message(func, paramList))

    def __send_message(self, func, args):
        m = self.__create_message(func, args)
        if self.ws_debug:
            print(m)
        self.ws.send(m)

    @staticmethod
    def __create_df(raw_data, symbol):
        try:
            out = re.search(r'"s":\[(.+?)\}\]', raw_data).group(1)
            x = out.split(',{"')
            data = list()
            volume_data = True

            for xi in x:
                xi = re.split(r"\[|:|,|\]", xi)
                ts = datetime.datetime.fromtimestamp(float(xi[4]))

                row = [ts]

                for i in range(5, 10):
                    # skip converting volume data if does not exists
                    if not volume_data and i == 9:
                        row.append(0.0)
                        continue
                    try:
                        row.append(float(xi[i]))

                    except ValueError:
                        volume_data = False
                        row.append(0.0)
                        logger.debug("no volume data")

                data.append(row)

            data = pd.DataFrame(
                data, columns=["datetime", "open", "high", "low", "close", "volume"]
            ).set_index("datetime")
            data.insert(0, "symbol", value=symbol)
            return data
        except AttributeError:
            logger.error("no data, please check the exchange and symbol")

    @staticmethod
    def __format_symbol(symbol, exchange, contract: int = None):
        if ":" in symbol:
            pass
        elif contract is None:
            symbol = f"{exchange}:{symbol}"

        elif isinstance(contract, int):
            symbol = f"{exchange}:{symbol}{contract}!"

        else:
            raise ValueError("not a valid contract")

        return symbol

    def get_hist(
        self,
        symbol: str,
        exchange: str = "NSE",
        interval: Interval = Interval.in_daily,
        n_bars: int = 10,
        fut_contract: int = None,
        extended_session: bool = False,
    ) -> pd.DataFrame:
        """get historical data

        Args:
            symbol (str): symbol name
            exchange (str, optional): exchange, not required if symbol is in format EXCHANGE:SYMBOL. Defaults to None.
            interval (str, optional): chart interval. Defaults to 'D'.
            n_bars (int, optional): no of bars to download, max 5000. Defaults to 10.
            fut_contract (int, optional): None for cash, 1 for continuous current contract in front, 2 for continuous next contract in front . Defaults to None.
            extended_session (bool, optional): regular session if False, extended session if True, Defaults to False.

        Returns:
            pd.Dataframe: dataframe with sohlcv as columns
        """
        symbol = self.__format_symbol(
            symbol=symbol, exchange=exchange, contract=fut_contract
        )

        interval = interval.value

        # Her cagri icin yeni session olustur — TradingView tekrari reddedebilir
        self.session = self.__generate_session()
        self.chart_session = self.__generate_chart_session()

        self.__create_connection()

        self.__send_message("set_auth_token", [self.token])
        self.__send_message("chart_create_session", [self.chart_session, ""])
        self.__send_message("quote_create_session", [self.session])
        self.__send_message(
            "quote_set_fields",
            [
                self.session,
                "ch",
                "chp",
                "current_session",
                "description",
                "local_description",
                "language",
                "exchange",
                "fractional",
                "is_tradable",
                "lp",
                "lp_time",
                "minmov",
                "minmove2",
                "original_name",
                "pricescale",
                "pro_name",
                "short_name",
                "type",
                "update_mode",
                "volume",
                "currency_code",
                "rchp",
                "rtc",
            ],
        )

        self.__send_message(
            "quote_add_symbols", [self.session, symbol, {"flags": ["force_permission"]}]
        )
        self.__send_message("quote_fast_symbols", [self.session, symbol])

        self.__send_message(
            "resolve_symbol",
            [
                self.chart_session,
                "symbol_1",
                '={"symbol":"'
                + symbol
                + '","adjustment":"splits","session":'
                + ('"regular"' if not extended_session else '"extended"')
                + "}",
            ],
        )
        self.__send_message(
            "create_series",
            [self.chart_session, "s1", "s1", "symbol_1", interval, n_bars],
        )
        self.__send_message("switch_timezone", [self.chart_session, "exchange"])

        raw_data = ""

        logger.debug(f"getting data for {symbol}...")

        while True:
            try:
                result = self.ws.recv()
                raw_data = raw_data + result + "\n"
            except Exception as e:
                logger.error(e)
                break

            if "series_completed" in result:
                break

        # Baglanti temizligi
        try:
            self.ws.close()
        except Exception:
            pass
        self.ws = None

        return self.__create_df(raw_data, symbol)

    def search_symbol(self, text: str, exchange: str = ""):
        url = self.__search_url.format(text, exchange)

        symbols_list = []
        try:
            resp = requests.get(url)

            symbols_list = json.loads(
                resp.text.replace("</em>", "").replace("<em>", "")
            )
        except Exception as e:
            logger.error(e)

        return symbols_list

    # =======================================================
    # CANLI FIYAT STREAM FONKSIYONLARI
    # =======================================================

    @staticmethod
    def __generate_quote_session():
        stringLength = 12
        letters = string.ascii_lowercase
        random_string = "".join(random.choice(letters) for i in range(stringLength))
        return "qs_" + random_string

    def canli_oturum_olustur(self):
        """Canli fiyat stream icin quote session olusturur.

        Returns:
            str: Olusturulan quote session ID'si.
        """
        self.quote_session = self.__generate_quote_session()
        self.__create_connection()
        self.__send_message("set_auth_token", [self.token])
        self.__send_message("quote_create_session", [self.quote_session])
        self.__send_message(
            "quote_set_fields",
            [
                self.quote_session,
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
        return self.quote_session

    def canli_sembol_ekle(self, semboller):
        """Canli oturuma sembol ekler.

        Args:
            semboller: Tekil sembol (str) veya sembol listesi (list).
                       "BIST:" oneki yoksa otomatik eklenir.
        """
        if isinstance(semboller, str):
            semboller = [semboller]

        for sembol in semboller:
            if ":" not in sembol:
                sembol = f"BIST:{sembol}"
            self.__send_message(
                "quote_add_symbols",
                [self.quote_session, sembol, {"flags": ["force_permission"]}],
            )
            self.__send_message(
                "quote_fast_symbols",
                [self.quote_session, sembol],
            )

    def canli_sembol_cikar(self, semboller):
        """Canli oturumdan sembol cikarir.

        Args:
            semboller: Tekil sembol (str) veya sembol listesi (list).
        """
        if isinstance(semboller, str):
            semboller = [semboller]

        for sembol in semboller:
            if ":" not in sembol:
                sembol = f"BIST:{sembol}"
            self.__send_message(
                "quote_remove_symbols",
                [self.quote_session, sembol],
            )

    def canli_dinle(self, callback, timeout=None):
        """Canli fiyat mesajlarini dinler ve callback ile iletir.

        Her fiyat guncelleme mesajinda callback(sembol, veri) cagrilir.
        veri dict formatinda: {"lp": ..., "ch": ..., "chp": ..., ...}

        Args:
            callback: Her fiyat guncellemesinde cagrilacak fonksiyon.
                      Imza: callback(sembol: str, veri: dict)
            timeout: Maks dinleme suresi (saniye). None ise surekli dinle.
        """
        if self.ws is None:
            logger.error("WS baglantisi yok — once canli_oturum_olustur() cagirin")
            return

        baslangic = datetime.datetime.now()

        while True:
            try:
                result = self.ws.recv()
                if not result:
                    continue

                # Ping/pong isle
                ping_match = re.match(r"~m~\d+~m~(\d+)$", result)
                if ping_match:
                    self.ws.send(self.__prepend_header(ping_match.group(1)))
                    continue

                # qsd mesajlarini ayikla
                parcalar = re.split(r"~m~\d+~m~", result)
                for parca in parcalar:
                    parca = parca.strip()
                    if not parca:
                        continue
                    try:
                        mesaj = json.loads(parca)
                    except (json.JSONDecodeError, ValueError):
                        continue

                    if not isinstance(mesaj, dict):
                        continue
                    if mesaj.get("m") != "qsd":
                        continue

                    p = mesaj.get("p", [])
                    if len(p) < 2:
                        continue

                    veri_sarmal = p[1]
                    tam_sembol = veri_sarmal.get("n", "")
                    degerler = veri_sarmal.get("v", {})

                    if not tam_sembol or not degerler:
                        continue

                    # "BIST:THYAO" -> "THYAO"
                    sembol = (
                        tam_sembol.split(":")[-1] if ":" in tam_sembol else tam_sembol
                    )

                    callback(sembol, degerler)

            except Exception as e:
                if "timed out" in str(e):
                    pass
                else:
                    logger.error("Canli dinleme hatasi: %s", e)
                    break

            # Zaman asimi kontrolu
            if timeout is not None:
                gecen = (datetime.datetime.now() - baslangic).total_seconds()
                if gecen >= timeout:
                    break

    def canli_kapat(self):
        """Canli oturumu ve WS baglantisini kapatir."""
        if self.ws is not None:
            try:
                self.ws.close()
            except Exception:
                pass
            self.ws = None


if __name__ == "__main__":
    logging.basicConfig(level=logging.DEBUG)
    tv = TvDatafeed()
    print(tv.get_hist("CRUDEOIL", "MCX", fut_contract=1))
    print(tv.get_hist("NIFTY", "NSE", fut_contract=1))
    print(
        tv.get_hist(
            "EICHERMOT",
            "NSE",
            interval=Interval.in_1_hour,
            n_bars=500,
            extended_session=False,
        )
    )
