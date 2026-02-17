# Copilot Instructions — dotfiles

Kural 1 = Bu repodaki her şey Türkçe yazılacak. Fonksiyon isimleri, değişken isimleri, dosya isimleri, yorum satırları ve kullanıcıya gösterilen tüm metinler dahil olmak üzere tamamen Türkçe olacak. Bash izin verdiği sürece Türkçe karakterler (ş, ç, ğ, ü, ö, ı) kullanılacak.

Kural 2 = Bu repoda kesinlikle emoji kullanılmayacak. Hiçbir dosyada, hiçbir yorum satırında, hiçbir çıktıda emoji olmayacak.

Kural 3 = Tüm yazılan shell kodları shellcheck ile hata vermeden geçecek şekilde yazılacak. Değişkenler çift tırnak içinde kullanılacak, local ve atama ayrı satırlarda yapılacak, her dosyanın başında "# shellcheck shell=bash" direktifi bulunacak.

Kural 4 = Plan ve dokümantasyon için yazılan md dosyaları aşağıdaki şablon ve kurallara uyacak. Başlıklar kafaya göre dallandırılmayacak, aşağıdaki sabit yapıya uyulacak.

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
## 4. Başlık
### 4.1 Alt Başlık
```

- Kod blokları sadece örnek komut veya örnek çıktı göstermek için kullanılacak.
- Her başlık altında en az bir satır açıklama bulunacak, boş başlık olmayacak.
- Yol haritası aşamaları numaralandırılacak ve her aşamanın kısa bir başlığı olacak.