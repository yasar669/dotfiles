# Oturum Koruma Loglama Iyilestirmesi - Plan

## 1. Sorun

Oturum koruma dongusu her basarili uzatmada log basarak terminali dolduruyor. Yaklasik her 8 dakikada bir "uzatildi" mesaji yaziliyor. Bu loglar normal calismayi gosterirken, kullaniciya faydali bilgi sunmuyor.

## 2. Onerilen Degisiklikler

### 2.1 Kaldirilacak Loglar

#### [MODIFY] cekirdek.sh

Satir 199 ve satir 214'teki basarili uzatma loglari kaldirilacak:

```diff
 if adaptor_oturum_uzat "$hesap" 2>/dev/null; then
     cekirdek_son_istek_guncelle "$kurum" "$hesap"
-    _cekirdek_log "Oturum koruma: uzatildi ($kurum/$hesap)."
 else
     _cekirdek_log "Oturum koruma: uzatma BASARISIZ ($kurum/$hesap)."
 fi
```

```diff
     cekirdek_istek_at ...
     cekirdek_son_istek_guncelle "$kurum" "$hesap"
-    _cekirdek_log "Oturum koruma: sessiz GET ile uzatildi ($kurum/$hesap)."
 fi
```

### 2.2 Korunacak Loglar

Su loglar oldugu gibi kalacak:

- `"Oturum koruma: oturum zaten dusmus"` — kritik hata
- `"Oturum koruma: uzatma BASARISIZ"` — hata
- `"Oturum koruma baslatildi"` — tek seferlik baslangic bilgisi

## 3. Dogrulama

Shellcheck ile soz dizimi kontrolu yapilacak. Manuel dogrulama: giris yapildiktan sonra terminalde sadece baslangic logu gorunmeli, her uzatma dongusu sessiz calisip, yalnizca hata olursa log uretmeli.
