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