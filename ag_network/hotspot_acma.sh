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
   #sysctl -w net.ipv4.icm_echo_ignore_all=1  >> bu komut ping isteklerini engeller.başkası seni pinglerse sen cevap vermezsin.
   

   sudo sysctl -w net.ipv4.ip_forward=1

    sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

    sudo iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT

    sudo iptables -A FORWARD -i eth0 -o wlan0 -m state --state ESTABLISHED,RELATED -j ACCEPT
  
    nmcli device wifi hotspot ifname wlan0 ssid "kali" password "yasar567567"

}