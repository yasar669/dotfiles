-- Borsa Sistemi - Veritabani Semasi
-- Supabase (PostgreSQL) icin tablo tanimlari.
-- Kullanim: psql -h localhost -p 5433 -U postgres -d postgres -f sema.sql
-- veya kur.sh otomatik calistirir.

-- =========================================================
-- 1. emirler
-- Gonderilen her emrin kalici kaydi.
-- =========================================================
CREATE TABLE IF NOT EXISTS emirler (
    id                  BIGSERIAL       PRIMARY KEY,
    kurum               TEXT            NOT NULL,
    hesap               TEXT            NOT NULL,
    sembol              TEXT            NOT NULL,
    yon                 TEXT            NOT NULL,
    lot                 INTEGER         NOT NULL,
    fiyat               NUMERIC(12,4),
    piyasa_mi           BOOLEAN         DEFAULT FALSE,
    referans_no         TEXT,
    durum               TEXT            NOT NULL DEFAULT 'GONDERILDI',
    strateji            TEXT,
    robot_pid           INTEGER,
    hata_mesaji         TEXT,
    olusturma_zamani    TIMESTAMPTZ     DEFAULT NOW(),
    guncelleme_zamani   TIMESTAMPTZ
);

-- =========================================================
-- 2. bakiye_gecmisi
-- Periyodik bakiye anlik goruntusu.
-- =========================================================
CREATE TABLE IF NOT EXISTS bakiye_gecmisi (
    id                  BIGSERIAL       PRIMARY KEY,
    kurum               TEXT            NOT NULL,
    hesap               TEXT            NOT NULL,
    nakit               NUMERIC(14,2)   NOT NULL,
    hisse_degeri        NUMERIC(14,2)   NOT NULL,
    toplam              NUMERIC(14,2)   NOT NULL,
    zaman               TIMESTAMPTZ     DEFAULT NOW()
);

-- =========================================================
-- 3. pozisyonlar
-- Anlik portfoy pozisyonlari.
-- =========================================================
CREATE TABLE IF NOT EXISTS pozisyonlar (
    id                  BIGSERIAL       PRIMARY KEY,
    kurum               TEXT            NOT NULL,
    hesap               TEXT            NOT NULL,
    sembol              TEXT            NOT NULL,
    lot                 INTEGER         NOT NULL,
    ortalama_maliyet    NUMERIC(12,4),
    piyasa_fiyati       NUMERIC(12,4),
    piyasa_degeri       NUMERIC(14,2),
    kar_zarar           NUMERIC(14,2),
    kar_zarar_yuzde     NUMERIC(8,4),
    zaman               TIMESTAMPTZ     DEFAULT NOW(),
    UNIQUE(kurum, hesap, sembol, (zaman::date))
);

-- =========================================================
-- 4. halka_arz_islemleri
-- Halka arz talep, iptal ve guncelleme islemleri.
-- =========================================================
CREATE TABLE IF NOT EXISTS halka_arz_islemleri (
    id                  BIGSERIAL       PRIMARY KEY,
    kurum               TEXT            NOT NULL,
    hesap               TEXT            NOT NULL,
    islem_tipi          TEXT            NOT NULL,
    ipo_adi             TEXT,
    ipo_id              TEXT,
    lot                 INTEGER,
    fiyat               NUMERIC(12,4),
    basarili            BOOLEAN         NOT NULL,
    mesaj               TEXT,
    zaman               TIMESTAMPTZ     DEFAULT NOW()
);

-- =========================================================
-- 5. robot_log
-- Robot yasam dongusu olaylari.
-- =========================================================
CREATE TABLE IF NOT EXISTS robot_log (
    id                  BIGSERIAL       PRIMARY KEY,
    kurum               TEXT            NOT NULL,
    hesap               TEXT            NOT NULL,
    robot_pid           INTEGER         NOT NULL,
    strateji            TEXT            NOT NULL,
    olay                TEXT            NOT NULL,
    detay               JSONB,
    zaman               TIMESTAMPTZ     DEFAULT NOW()
);

-- =========================================================
-- 6. oturum_log
-- Oturum baslangic, bitis ve uzatma olaylari.
-- =========================================================
CREATE TABLE IF NOT EXISTS oturum_log (
    id                  BIGSERIAL       PRIMARY KEY,
    kurum               TEXT            NOT NULL,
    hesap               TEXT            NOT NULL,
    olay                TEXT            NOT NULL,
    detay               TEXT,
    zaman               TIMESTAMPTZ     DEFAULT NOW()
);

-- =========================================================
-- 7. fiyat_gecmisi (KALDIRILDI)
-- Bu tablo artik kullanilmiyor. Tum fiyat verileri ohlcv
-- tablosunda tutuluyor. Bkz: sema agaci BOLUM 10.
-- =========================================================


-- =========================================================
-- 8. backtest_sonuclari
-- Her backtest calistirmasinin ozet sonucunu tutar.
-- =========================================================
CREATE TABLE IF NOT EXISTS backtest_sonuclari (
    id                  BIGSERIAL       PRIMARY KEY,
    strateji            TEXT            NOT NULL,
    semboller           TEXT[]          NOT NULL,
    baslangic_tarih     DATE            NOT NULL,
    bitis_tarih         DATE            NOT NULL,
    islem_gunu          INTEGER         NOT NULL,
    baslangic_nakit     NUMERIC(14,2)   NOT NULL,
    bitis_deger         NUMERIC(14,2)   NOT NULL,
    toplam_getiri       NUMERIC(8,4),
    yillik_getiri       NUMERIC(8,4),
    maks_dusus          NUMERIC(8,4),
    sharpe_orani        NUMERIC(8,4),
    sortino_orani       NUMERIC(8,4),
    calmar_orani        NUMERIC(8,4),
    toplam_islem        INTEGER,
    basarili_islem      INTEGER,
    basari_orani        NUMERIC(6,2),
    kz_orani            NUMERIC(8,4),
    toplam_komisyon     NUMERIC(14,2),
    ort_pozisyon_gun    NUMERIC(6,2),
    maks_kayip_seri     INTEGER,
    eslestirme          TEXT            DEFAULT 'KAPANIS',
    komisyon_alis       NUMERIC(8,6),
    komisyon_satis      NUMERIC(8,6),
    parametreler        JSONB,
    zaman               TIMESTAMPTZ     DEFAULT NOW()
);

-- =========================================================
-- 9. backtest_islemleri
-- Backtest sirasinda yapilan her sanal islemin kaydi.
-- =========================================================
CREATE TABLE IF NOT EXISTS backtest_islemleri (
    id                  BIGSERIAL       PRIMARY KEY,
    backtest_id         BIGINT          REFERENCES backtest_sonuclari(id),
    gun_no              INTEGER         NOT NULL,
    tarih               DATE            NOT NULL,
    sembol              TEXT            NOT NULL,
    yon                 TEXT            NOT NULL,
    lot                 INTEGER         NOT NULL,
    fiyat               NUMERIC(12,4)   NOT NULL,
    komisyon            NUMERIC(10,2),
    nakit_sonrasi       NUMERIC(14,2),
    portfoy_degeri      NUMERIC(14,2),
    sinyal              TEXT,
    zaman               TIMESTAMPTZ     DEFAULT NOW()
);

-- =========================================================
-- 10. backtest_gunluk
-- Gunluk portfoy degeri. Equity curve ve drawdown icin.
-- =========================================================
CREATE TABLE IF NOT EXISTS backtest_gunluk (
    id                  BIGSERIAL       PRIMARY KEY,
    backtest_id         BIGINT          REFERENCES backtest_sonuclari(id),
    gun_no              INTEGER         NOT NULL,
    tarih               DATE            NOT NULL,
    nakit               NUMERIC(14,2)   NOT NULL,
    hisse_degeri        NUMERIC(14,2)   NOT NULL,
    toplam              NUMERIC(14,2)   NOT NULL,
    dusus               NUMERIC(8,4),
    UNIQUE(backtest_id, tarih)
);


-- =========================================================
-- INDEKSLER
-- Sik yapilan sorgular icin performans indeksleri.
-- =========================================================

-- =========================================================
-- 11. ohlcv
-- OHLCV mum verileri. tvDatafeed, WSS ve Yahoo'dan gelen
-- tum periyotlardaki mum verileri tek tabloda saklanir.
-- Partition'lu yapi ile buyuk hacimde performansli calisir.
-- =========================================================
CREATE TABLE IF NOT EXISTS ohlcv (
    id          BIGSERIAL,
    sembol      VARCHAR(12)   NOT NULL,
    periyot     VARCHAR(4)    NOT NULL,
    tarih       TIMESTAMPTZ   NOT NULL,
    acilis      NUMERIC(12,4) NOT NULL,
    yuksek      NUMERIC(12,4) NOT NULL,
    dusuk       NUMERIC(12,4) NOT NULL,
    kapanis     NUMERIC(12,4) NOT NULL,
    hacim       BIGINT        NOT NULL DEFAULT 0,
    kaynak      VARCHAR(8)    DEFAULT 'tvdata',
    guncelleme  TIMESTAMPTZ   DEFAULT NOW(),
    PRIMARY KEY (sembol, periyot, tarih)
);

-- Performans indexleri — ohlcv
CREATE INDEX IF NOT EXISTS idx_ohlcv_sembol_periyot
    ON ohlcv (sembol, periyot, tarih DESC);

CREATE INDEX IF NOT EXISTS idx_ohlcv_tarih
    ON ohlcv (tarih DESC);

-- INDEKSLER (diger tablolar)

CREATE INDEX IF NOT EXISTS idx_emirler_kurum_hesap
    ON emirler(kurum, hesap);

CREATE INDEX IF NOT EXISTS idx_emirler_referans
    ON emirler(referans_no);

CREATE INDEX IF NOT EXISTS idx_emirler_sembol
    ON emirler(sembol, olusturma_zamani DESC);

CREATE INDEX IF NOT EXISTS idx_bakiye_gecmisi_kurum_hesap
    ON bakiye_gecmisi(kurum, hesap, zaman DESC);

CREATE INDEX IF NOT EXISTS idx_pozisyonlar_kurum_sembol
    ON pozisyonlar(kurum, hesap, sembol);

CREATE INDEX IF NOT EXISTS idx_halka_arz_kurum_hesap
    ON halka_arz_islemleri(kurum, hesap, zaman DESC);

CREATE INDEX IF NOT EXISTS idx_robot_log_pid
    ON robot_log(robot_pid, zaman DESC);

CREATE INDEX IF NOT EXISTS idx_robot_log_kurum
    ON robot_log(kurum, hesap, zaman DESC);

CREATE INDEX IF NOT EXISTS idx_oturum_log_kurum
    ON oturum_log(kurum, hesap, zaman DESC);

-- idx_fiyat_gecmisi_sembol_zaman kaldirildi (tablo kaldirildi)

CREATE INDEX IF NOT EXISTS idx_bt_sonuc_strateji
    ON backtest_sonuclari(strateji);

CREATE INDEX IF NOT EXISTS idx_bt_sonuc_zaman
    ON backtest_sonuclari(zaman DESC);

CREATE INDEX IF NOT EXISTS idx_bt_islem_backtest
    ON backtest_islemleri(backtest_id);

CREATE INDEX IF NOT EXISTS idx_bt_islem_sembol
    ON backtest_islemleri(sembol, tarih);

CREATE INDEX IF NOT EXISTS idx_bt_gunluk_backtest
    ON backtest_gunluk(backtest_id, tarih);


-- =========================================================
-- ROW LEVEL SECURITY (RLS)
-- Tum tablolarda aktif. anon rolu tam erisime sahip.
-- Yerel kurulum oldugu icin disaridan erisim zaten yok.
-- =========================================================

ALTER TABLE emirler ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'emirler' AND policyname = 'anon_tam_erisim') THEN
        CREATE POLICY anon_tam_erisim ON emirler FOR ALL TO anon USING (true) WITH CHECK (true);
    END IF;
END $$;

ALTER TABLE bakiye_gecmisi ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bakiye_gecmisi' AND policyname = 'anon_tam_erisim') THEN
        CREATE POLICY anon_tam_erisim ON bakiye_gecmisi FOR ALL TO anon USING (true) WITH CHECK (true);
    END IF;
END $$;

ALTER TABLE pozisyonlar ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'pozisyonlar' AND policyname = 'anon_tam_erisim') THEN
        CREATE POLICY anon_tam_erisim ON pozisyonlar FOR ALL TO anon USING (true) WITH CHECK (true);
    END IF;
END $$;

ALTER TABLE halka_arz_islemleri ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'halka_arz_islemleri' AND policyname = 'anon_tam_erisim') THEN
        CREATE POLICY anon_tam_erisim ON halka_arz_islemleri FOR ALL TO anon USING (true) WITH CHECK (true);
    END IF;
END $$;

ALTER TABLE robot_log ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'robot_log' AND policyname = 'anon_tam_erisim') THEN
        CREATE POLICY anon_tam_erisim ON robot_log FOR ALL TO anon USING (true) WITH CHECK (true);
    END IF;
END $$;

ALTER TABLE oturum_log ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'oturum_log' AND policyname = 'anon_tam_erisim') THEN
        CREATE POLICY anon_tam_erisim ON oturum_log FOR ALL TO anon USING (true) WITH CHECK (true);
    END IF;
END $$;

-- fiyat_gecmisi RLS kaldirildi (tablo kaldirildi)

ALTER TABLE backtest_sonuclari ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'backtest_sonuclari' AND policyname = 'anon_tam_erisim') THEN
        CREATE POLICY anon_tam_erisim ON backtest_sonuclari FOR ALL TO anon USING (true) WITH CHECK (true);
    END IF;
END $$;

ALTER TABLE backtest_islemleri ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'backtest_islemleri' AND policyname = 'anon_tam_erisim') THEN
        CREATE POLICY anon_tam_erisim ON backtest_islemleri FOR ALL TO anon USING (true) WITH CHECK (true);
    END IF;
END $$;

ALTER TABLE backtest_gunluk ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'backtest_gunluk' AND policyname = 'anon_tam_erisim') THEN
        CREATE POLICY anon_tam_erisim ON backtest_gunluk FOR ALL TO anon USING (true) WITH CHECK (true);
    END IF;
END $$;

ALTER TABLE ohlcv ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'ohlcv' AND policyname = 'anon_tam_erisim') THEN
        CREATE POLICY anon_tam_erisim ON ohlcv FOR ALL TO anon USING (true) WITH CHECK (true);
    END IF;
END $$;


-- =========================================================
-- ROL YETKILENDIRME
-- PostgREST (anon), Studio/pg_meta (supabase) ve
-- authenticator rolleri icin gerekli tum yetkiler.
-- Bu blok olmazsa:
--   * PostgREST 404 doner (anon GRANT eksik)
--   * Studio tablolari goremez (supabase GRANT eksik)
--   * Studio veriyi goremez (supabase BYPASSRLS eksik)
-- =========================================================

-- anon: PostgREST API uzerinden erisim
GRANT USAGE ON SCHEMA public TO anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON SEQUENCES TO anon;

-- supabase: pg_meta / Studio metadata servisi
GRANT USAGE ON SCHEMA public TO supabase;
GRANT ALL ON ALL TABLES IN SCHEMA public TO supabase;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO supabase;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON TABLES TO supabase;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON SEQUENCES TO supabase;
-- Studio'nun RLS aktif tablolarda veri gorebilmesi icin
ALTER ROLE supabase BYPASSRLS;

-- authenticator: PostgREST baglanti rolu
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
        EXECUTE 'GRANT USAGE ON SCHEMA public TO authenticator';
        EXECUTE 'GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticator';
    END IF;
END $$;

-- PostgREST schema cache yenile (sema.sql her calistiginda)
-- SIGUSR1 sinyali gondererek yeni tablolarin API'de gorunmesini saglar.
-- Docker ortaminda calismazsa sessizce atlanir.
DO $$ BEGIN
    PERFORM pg_notify('pgrst', 'reload schema');
END $$;
