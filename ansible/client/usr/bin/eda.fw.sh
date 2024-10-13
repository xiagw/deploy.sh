#!/usr/bin/bash

# firewall-cmd --add-rich-rule="rule family=ipv4 forward-port port=1022 protocol=tcp to-port=22"
## 丢弃坏的TCP包
# iptables -A FORWARD -p TCP ! --syn -m state --state NEW -j DROP
## 处理IP碎片数量,防止攻击,允许每秒100个
# iptables -A FORWARD -f -m limit --limit 100/s --limit-burst 100 -j ACCEPT
## 设置ICMP包过滤,允许每秒1个包,限制触发条件是10个包
# iptables -A FORWARD -p icmp -m limit --limit 1/s --limit-burst 10 -j ACCEPT
## 开启对指定网站的访问
# iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# iptables -A OUTPUT -m state --state NEW,ESTABLISHED,RELATED -p tcp -d www.github.com -j ACCEPT

_rule_clean() {
    ## clean all rules from OUTPUT
    firewall-cmd --permanent --direct --remove-rules ipv4 filter OUTPUT
}

_rule_server() {
    ## nfs, nis
    firewall-cmd --permanent --add-service={nfs,nfs3,mountd,rpc-bind}
    firewall-cmd --permanent --add-port={944-946/tcp,944-946/udp}
    ## vpn
    firewall-cmd --permanent --add-port=39036-39038/udp
    ## vncserver
    firewall-cmd --permanent --add-port=5900-5999/tcp
    ## EDA license
    firewall-cmd --permanent --add-port=30000/tcp
    ## openlava
    firewall-cmd --permanent --add-port=16322-16325/tcp
}

_rule_default() {
    local cmd="firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT"
    ## allow loopback
    $cmd 0 -o lo -p all -j ACCEPT
    ## allow icmp
    $cmd 0 -p icmp -m icmp --icmp-type 8 -j ACCEPT
    ## allow established
    $cmd 0 -m state --state ESTABLISHED,RELATED -j ACCEPT
    ## Allow for DNS queries:
    $cmd 1 -p tcp -m tcp --dport 53 -j ACCEPT
    $cmd 1 -p udp --dport 53 -j ACCEPT
    ## Allow SSH:
    $cmd 1 -p tcp --sport 22 -j ACCEPT
    $cmd 1 -p tcp --dport 22 -j ACCEPT
    # $cmd 1 -p tcp -m multiport --dports 22,18941 -j ACCEPT
    ## Allow VPN:
    $cmd 1 -p udp --sport 39001:39100 -j ACCEPT
    $cmd 1 -p udp --dport 39001:39100 -j ACCEPT
    ## Allow License:
    $cmd 1 -p udp --sport 30000:30005 -j ACCEPT
    $cmd 1 -p udp --dport 30000:30005 -j ACCEPT
    ## Allow VNC:
    $cmd 1 -p tcp --sport 5900:5999 -j ACCEPT
    $cmd 1 -p tcp --dport 5900:5999 -j ACCEPT
    ## Allow NAS web 5000, 5001, ssh 22
    # $cmd 1 -d 192.168.7.10/32 -j ACCEPT
}

_rule_enable_web() {
    ## Allow HTTP HTTPS:
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 1 -p tcp -m multiport --dports 80,443 -j ACCEPT
}

_rule_disable() {
    ## Deny everything from source address 10.20.0.0/17:
    firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 2 -s 172.30.100.0/22 -j DROP
    # firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i eth0 -o eth1 -j ACCEPT
}

_rule_reload() {
    firewall-cmd --reload
}

main() {
    [[ $(id -u) -ne 0 ]] && {
        echo "Need root. exit."
        return 1
    }

    choice=${1:-$(
        select choice in disable_out enable_out enable_only_web firewall_status quit; do
            break
        done
    )}

    case $choice in
    disable_out)
        _rule_clean
        _rule_default
        _rule_disable
        _rule_reload
        ;;
    enable_out)
        _rule_clean
        _rule_reload
        ;;
    enable_only_web)
        _rule_clean
        _rule_default
        _rule_enable_web
        _rule_disable
        _rule_reload
        ;;
    firewall_status)
        cat /etc/firewalld/direct.xml
        ;;
    *)
        echo 'param error'
        ;;
    esac
}

main "$@"
