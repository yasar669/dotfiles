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
-- 7. fiyat_gecmisi
-- Tarama katmanindan cekilen fiyat verilerinin kalici kaydi.
-- =========================================================
CREATE TABLE IF NOT EXISTS fiyat_gecmisi (
    id                  BIGSERIAL       PRIMARY KEY,
    sembol              TEXT            NOT NULL,
    fiyat               NUMERIC(12,4)   NOT NULL,
    tavan               NUMERIC(12,4),
    taban               NUMERIC(12,4),
    degisim             NUMERIC(8,4),
    hacim               BIGINT,
    seans_durumu        TEXT,
    kaynak_kurum        TEXT,
    kaynak_hesap        TEXT,
    zaman               TIMESTAMPTZ     DEFAULT NOW()
);


-- =========================================================
-- INDEKSLER
-- Sik yapilan sorgular icin performans indeksleri.
-- =========================================================

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

CREATE INDEX IF NOT EXISTS idx_fiyat_gecmisi_sembol_zaman
    ON fiyat_gecmisi(sembol, zaman DESC);


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

ALTER TABLE fiyat_gecmisi ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'fiyat_gecmisi' AND policyname = 'anon_tam_erisim') THEN
        CREATE POLICY anon_tam_erisim ON fiyat_gecmisi FOR ALL TO anon USING (true) WITH CHECK (true);
    END IF;
END $$;
