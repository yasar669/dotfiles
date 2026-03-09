# Copilot Instructions — dotfiles

Kural 1 = Bu repodaki her şey Türkçe yazılacak. Fonksiyon isimleri, değişken isimleri, dosya isimleri, yorum satırları ve kullanıcıya gösterilen tüm metinler dahil olmak üzere tamamen Türkçe olacak. Bash izin verdiği sürece Türkçe karakterler (ş, ç, ğ, ü, ö, ı) kullanılacak.

Kural 2 = Bu repoda kesinlikle emoji kullanılmayacak. Hiçbir dosyada, hiçbir yorum satırında, hiçbir çıktıda emoji olmayacak.

Kural 3 = Tüm yazılan shell kodları shellcheck ile hata vermeden geçecek şekilde yazılacak. Değişkenler çift tırnak içinde kullanılacak, local ve atama ayrı satırlarda yapılacak, her dosyanın başında "# shellcheck shell=bash" direktifi bulunacak.

Kural 4 = Tüm yazılan Python kodları ruff ile hata vermeden geçecek şekilde yazılacak. Ruff hem linter hem formatter olarak kullanılacak. Kodlar ruff check ve ruff format kontrolünden temiz geçmeden tamamlanmış sayılmayacak. Temel beklentiler şunlardır: kullanılmayan import olmayacak (F401), kullanılmayan değişken olmayacak (F841), satır uzunluğu 88 karakteri geçmeyecek (E501), import sıralaması isort kurallarına uyacak (I), docstring'ler convention="google" formatında yazılacak (D), f-string gereksiz yere kullanılmayacak, tip annotasyonları mümkün olan her yerde eklenecek. Ruff ayarları repodaki pyproject.toml veya ruff.toml dosyasında merkezi olarak tanımlanacak, her dosyada ayrı ayrı noqa ile susturma yapılmayacak (zorunlu istisnalar hariç).

Kural 5 = Plan ve dokümantasyon için yazılan md dosyaları aşağıdaki şablon ve kurallara uyacak. Başlıklar kafaya göre dallandırılmayacak, aşağıdaki sabit yapıya uyulacak.

Plan MD Şablonu:
- Başlıklar kafaya göre dallandırılmayacak, aşağıdaki sabit yapıya uyulacak.
- Sabit başlık sırası şu şekilde olacak, gereksiz olan başlık yazılmayacak ama sıra değişmeyecek:

```
# Modül Adı - Plan
## 1. Başlık
## 2. Başlık
## 3. Başlık
### 3.1 Alt Başlık
### 3.2 Alt Başlık
### 3.3 Alt Başlık
#### 3.3.1 Alt Alt Başlık
#### 3.3.2 Alt Alt Başlık
## 4. Başlık
### 4.1 Alt Başlık
```

- Kod blokları sadece örnek komut veya örnek çıktı göstermek için kullanılacak.
- Her başlık altında en az bir satır açıklama bulunacak, boş başlık olmayacak.
- Yol haritası aşamaları numaralandırılacak ve her aşamanın kısa bir başlığı olacak.

Kural 6 = bashrc.d/ klasörü altındaki herhangi bir shell dosyasında (.sh) değişiklik yapıldıktan sonra, değişikliklerin terminale yansıması için `source ~/.bashrc` komutu otomatik olarak çalıştırılacak. Kullanıcıdan bunu manuel yapması beklenmeyecek. Değişiklik yapan araç çağrısından hemen sonra bu komut SafeToAutoRun=true ile çalıştırılacak.

Kural 7 = bashrc.d/borsa/adaptorler/ klasöründe herhangi bir değişiklik yapılmadan önce (yeni adaptör ekleme, mevcut adaptör düzenleme, ayarlar dosyası güncelleme) `bashrc.d/borsa/adaptorler/plan.md` dosyası okunacak. Bu dosya adaptör katmanının mimari ilkelerini, sorumluluk ayrımını (adaptöre ait olan / çekirdeğe ait olan), zorunlu arabirim sözleşmesini (`adaptor_*` fonksiyonları), dosya yapısını, isimlendirme konvansiyonlarını ve yeni adaptör ekleme kontrol listesini içerir. Plan dosyası okunmadan adaptör klasöründe hiçbir dosya oluşturulmayacak veya düzenlenmeyecek.

Kural 8 = Tüm shell kodlarında performans öncelikli yazım uygulanacak. Her dışsal komut çağrısı (grep, sed, awk, cut, cat, rev, head, tail, wc, tr, basename, dirname) bir fork + exec işlemi tetikler ve bu pahalı bir işlemdir. Bash builtin'leri ve parametre genişletme operatörleri her zaman dışsal komutlara tercih edilecek. Aşağıdaki kurallar geçerlidir:

8.1 - Parametre genişletme ile yapılabilecek işlemlerde dışsal komut kullanılmayacak:
- `${degisken##*/}` kullanılacak, `basename "$degisken"` veya `echo "$degisken" | rev | cut -d'/' -f1 | rev` kullanılmayacak.
- `${degisken%/*}` kullanılacak, `dirname "$degisken"` kullanılmayacak.
- `${degisken%.uzanti}` kullanılacak, `echo "$degisken" | sed 's/\.uzanti$//'` kullanılmayacak.
- `${degisken##*.}` kullanılacak (uzantı alma), `echo "$degisken" | awk -F. '{print $NF}'` kullanılmayacak.
- `${degisken/eski/yeni}` kullanılacak (tek değiştirme), `echo "$degisken" | sed 's/eski/yeni/'` kullanılmayacak.
- `${degisken//eski/yeni}` kullanılacak (toplu değiştirme), `echo "$degisken" | sed 's/eski/yeni/g'` kullanılmayacak.
- `${degisken,,}` kullanılacak (küçük harfe çevirme), `echo "$degisken" | tr '[:upper:]' '[:lower:]'` kullanılmayacak.
- `${degisken^^}` kullanılacak (büyük harfe çevirme), `echo "$degisken" | tr '[:lower:]' '[:upper:]'` kullanılmayacak.
- `${#degisken}` kullanılacak (uzunluk alma), `echo "$degisken" | wc -c` kullanılmayacak.
- `${degisken:baslangic:uzunluk}` kullanılacak (alt dizi alma), `echo "$degisken" | cut -c1-5` kullanılmayacak.

8.2 - Regex eşleştirme için `[[ ... =~ ... ]]` ve `BASH_REMATCH` kullanılacak, `grep` veya `sed` çağrılmayacak:
- `[[ "$metin" =~ ([0-9]+) ]] && sonuc="${BASH_REMATCH[1]}"` kullanılacak, `sonuc=$(echo "$metin" | grep -o "[0-9]*" | head -1)` kullanılmayacak.

8.3 - Dosya okuma için `$(<dosya)` kullanılacak, `$(cat dosya)` kullanılmayacak. cat komutu yalnızca çıktının terminale veya pipe'a aktarılması gerektiğinde kullanılacak, değişkene atama için asla kullanılmayacak.

8.4 - Gereksiz subshell oluşturulmayacak. Komut ikamesi `$(...)` yalnızca zorunlu olduğunda kullanılacak. Aritmetik işlemlerde `$(( ))` tercih edilecek, `$(expr ...)` veya `$(bc <<< ...)` basit hesaplamalar için kullanılmayacak.

8.5 - Döngü içinde dışsal komut çağrısı en aza indirilecek. Bir döngüde yüzlerce kez çalışacak komutlar varsa, döngü dışında tek seferde işlenebilecek yol aranacak. Örneğin `while read` döngüsünde her satır için ayrı `grep` çağrılmayacak, mümkünse tek bir `awk` veya bash regex ile işlenecek.

8.6 - Gereksiz pipe zincirleri kurulmayacak. Tek bir araçla yapılabilecek iş birden fazla araca bölünmeyecek. Örneğin `cat dosya | grep kalip` yerine `grep kalip dosya` kullanılacak (UUOC - Useless Use of Cat).

8.7 - printf bash builtin olarak echo'ya tercih edilecek. `echo -e` yerine `printf '%s\n'` kullanılacak. printf taşınabilir ve davranışı tahmin edilebilirdir.

8.8 - Koşul kontrollerinde `[[ ]]` kullanılacak, `[ ]` veya `test` kullanılmayacak. `[[ ]]` bash builtin'idir, sözcük bölme (word splitting) ve glob genişletme yapmaz, regex destekler ve daha hızlıdır.