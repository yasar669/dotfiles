# shellcheck shell=bash
# hotspot_acma.sh

hotspot_ac() {
   
   #sysctl= System Control (sistem kontrolü) 
   #sysctl linux çekirdeğinin çalışma zamanaındaki davranışını değiştiren araçtır.
   #çekirdek yüzlerce parametre ile çalışır ve sysctl bu parametreleri okuyup yazabilir.
   #örnekle göstermek gerekirse çekirdek bir arabanın motoru sysctl ise o motorun uzaktan kumanda paneli olarak düşünülebilir.
   #komutta sudo kullanılmasındaki amaç çekirdekte değişiklik yapmak için yetki gerektirmesidir.
   #-w paramaetresi "yaz(write) "  yani bir parametreni değerini değiştir demektir.
   #net.ipv4.ip_forward bu ifade ise parametredir bu parametrede noktalar dosya dizinleri gibi düşünülebilir
   #proc/net/ipv4/ip_forward şeklinde aslında dizin yapısındadırlar bu yapıya cd proc/net/ipv4/ip_forward şeklinde komut verilerek girilebilir.
   #=1 parametresi ise yeni değerin 1 olarak yani açık olarak kaydetmemizi sağlar 
   #kısacası bu komut bir ağ arayzünden gelen verileri bilgisyarın başka bir arayğüze iletmesini yani yönlendirici gibi davranmasını sağlıyor.
   
   #sysctl nin eşitli kullanım alanları şunlardır :

   # GÜVENLİK AMAÇLI KULLANIMLAR :

   #sysctl -w net.ipv4.icm_echo_ignore_all=1  >> bu komut ping isteklerini engeller.başkası seni pinglerse sen cevap vermezsin.
   #sysctl -w net.ıpv4.tcp_syncookies=1 >> bu komut syn flood sadırılarına karşı koruma sağlar.
   #syn flood saldırısı, bir sunucuya çok sayıda SYN paketi göndererek hizmet dışı bırakmayı amaçlayan bir siber saldırı türüdür.
   #sysctl -w net.ipv4.tcp_syncookies=1 yapıldığında sunucu gelen SYN paketlerini kontrol eder ve sadece geçerli olanlara cevap verir.
   #sysctl -w net.ipv4.conf.all.rp_filter=1 >> bu komut ip spoofing saldırılarını engeller.
   #ip spoofing, bir saldırganın sahte bir IP adresi kullanarak bir sisteme erişmeye çalışmasıdır.
   #sysctl -w net.ipv4.conf.all.rp_filters bunu nasıl yapıyor pekide ip spoofing saldırılarını engelliyor?
   #normal duurmda sistem paketi alır ve kaynak ip yi dorgulamaz rp filter aktif olduğunda sistem şu kontrolü yapar :
   #1- gelen paketin kaynak ip si ile paketin geldiği arayüzün ip si aynı mı?
   #2- gelen paketin kaynak ip si ile paketin geldiği arayüzün ip si aynı değilse?
   #sysctl -w net.ipv4.conf.all.accept_redirects=0 >> bu kommut ıcmp redirect salırılarını engeller.
   #sysctl -w net.core.somaxconn=1024 >>  bu komut açık bağlantı sayısı limitini artırır(sunucu optimizasyonu için)
   #bu komut daha çok sunucu çalıştıran insanlar için önemli normal yerel bilgisyarlar  için çokda önemli değildir kullanılmayabilir ama sunucu çalıştırılan proelerimizde işe yarayabilir.
   
   #BELLEK VE PERFORMANS AMAÇLI KULLANIMLAR :

   # sysctl -w vm.swappiness=10 >> bu komut ram dolduğunda sistemin disk belleğini ne kadar kullanacağını belirler.değer 0 ile 100 arasındadır.daha düşük değerler daha az disk belleği kullanımı anlamına gelir.
   #sysctl -w vm.dirty_ratio=20 >> bir dosyaya birşey yazdığında veri doğrudan diske yazılmaz önce ramdeki bir önbelleğe yaılır,sonra uygun zamanda diske aktarılır.
   #bu komut o diske yazılma zamanını belirleyen bir komut aslında ramin hangi yüzdesi dolduğunda mesela yüzde 30 umu yüzde 20 simi dolduğunda diske yazılacağını belirler bana göre küçük sayılar belirlemek bilgisayarın perdormansı için daha verimlidir.
   
   # GÜVENLİK

   # sysctl -w kernel.core_pattern="|/bin/false" >> bu komut core dumpları devre dışı bırakmak için kullanılır.
   #core dump bir rogram çöktüğünde linux çekirdeği o programın o anki tüm bellek içeriğini bir dosyaya kaydeder.bu dosyaya core dump denir.
   #işte sysctl -w kernel.core_pattern="|/bin/false"  komutu bunu devre dışı bırakır ve bu bin/false uygulamasına yönlendirir dosyayı ve dosya kaydedilmez bu sayede güvenlik sağlanmış olur dosyadan birşey okunamaz.
   #sysctl -w kernel.kptr_restrict=2 >> bu komut kernel adres bilgisini gizler(güvenlik açığını zorlaştırır.)
   #Linux çekirdeği çalışırken bellekte belirli adreslere yerleşir. her fonksiyon her veri yapısı ramde bir adreste bulunur.
   #bu adreslere kernel pointer (kptr) denir. normal kulanıcılar bu adresleri bazı dosyalardan görebilir: cat /proc/kallsyms
   #modern işletim sistemleri kaslr(kernel address sace layout randomization) kullanır. her açılışta çekirdek rastgele bir adrese yüklenir.
   #ama eğer saldırgan /proc/kallmsyms dosyasını okuyabilirse artık tam adresi bilir ve kaslr koruması ise yaramaz hale gelir.
   #sysctl -w kernel.kptr_restrict=2 bu adreslerin kimler tarafndan görülebileceğini kontorl eder. 0 tamemen açık 1 sadce root görebilir 2 ise tamamen gili şekilde ayarlar verir.
   #sysctl -w kernel.dmesg_restrict=1 >> dmesg çekirdeğin log mesajlarını gösteren komuttur. bilgisayar açıldığından beri çekirdeğin yazdığı tüm mesajları içerir. >> dmesg | head -10
   #bu mesajlarda neler var :[    0.000000] Linux version 6.x.x (Cekirdek surumu)
   #[    1.232817] r8169: eth0 MAC adresi: 74:d4:dd:22:65:43
   #[    3.843722] iwlwifi: Wi-Fi karti tanimlandi
   #[    3.922074] Bluetooth: Firmware yuklendi
   #[   15.004521] USB: Yeni aygit baglandi
   #bu komut =1 yapılmalıdır ki sadece root kullanıcları çekirdek loglarını görebilsin.
   


    sudo sysctl -w net.ipv4.ip_forward=1

    sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

    sudo iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT

    sudo iptables -A FORWARD -i eth0 -o wlan0 -m state --state ESTABLISHED,RELATED -j ACCEPT
  
    nmcli device wifi hotspot ifname wlan0 ssid "kali" password "yasar567567"

}