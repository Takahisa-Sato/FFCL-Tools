#!/bin/bash
#
# 2NIC DMZ/LAN ルーティング設定ツール（複数NIC対応・GW末尾入力版）
# 想定ワークフロー：
#   1. IP / GW / DNS は Webmin で設定
#   2. このスクリプトを root で実行
#   3. LAN / DMZ 用インターフェースを番号で選び、
#      Gateway は「末尾のホスト部（X）」だけ入力

echo "=== 2NIC DMZ/LAN ルーティング設定ツール（複数NIC対応版） ==="
echo ""

# root チェック
if [ "$EUID" -ne 0 ]; then
    echo "このスクリプトは root で実行してください。"
    exit 1
fi

# 1) IPv4 を持っているインターフェースを列挙
IFS=$'\n'
IF_LINES=($(ip -o -4 addr show | awk '{print $2, $4}'))
unset IFS

if [ ${#IF_LINES[@]} -lt 2 ]; then
    echo "IPv4 アドレスを持つインターフェースが 2つ未満です。"
    echo "Webmin で NIC に IP を設定してから実行してください。"
    exit 1
fi

echo "利用可能なインターフェース一覧（IPv4 を持つもの）："
INDEX=0
declare -a IF_NAMES
declare -a IF_IPS

for LINE in "${IF_LINES[@]}"; do
    IF_NAME=$(echo "$LINE" | awk '{print $1}')
    IF_IP=$(echo "$LINE" | awk '{print $2}')  # 例: 192.168.100.63/24
    IF_NAMES[$INDEX]=$IF_NAME
    IF_IPS[$INDEX]=$IF_IP
    echo "  [$INDEX]  $IF_NAME  $IF_IP"
    INDEX=$((INDEX+1))
done

echo ""
read -p "LAN 側として使う番号を入力してください: " LAN_IDX
read -p "DMZ 側として使う番号を入力してください: " DMZ_IDX

# 2) 入力チェック
if ! [[ "$LAN_IDX" =~ ^[0-9]+$ ]] || ! [[ "$DMZ_IDX" =~ ^[0-9]+$ ]]; then
    echo "番号は整数で入力してください。"
    exit 1
fi

if [ "$LAN_IDX" -ge "${#IF_NAMES[@]}" ] || [ "$DMZ_IDX" -ge "${#IF_NAMES[@]}" ]; then
    echo "指定された番号が範囲外です。"
    exit 1
fi

if [ "$LAN_IDX" -eq "$DMZ_IDX" ]; then
    echo "LAN と DMZ に同じインターフェースは指定できません。"
    exit 1
fi

LAN_IF=${IF_NAMES[$LAN_IDX]}
DMZ_IF=${IF_NAMES[$DMZ_IDX]}
LAN_IP_WITH_MASK=${IF_IPS[$LAN_IDX]}
DMZ_IP_WITH_MASK=${IF_IPS[$DMZ_IDX]}

LAN_IP=${LAN_IP_WITH_MASK%/*}
DMZ_IP=${DMZ_IP_WITH_MASK%/*}

echo ""
echo "選択されたインターフェース:"
echo "  LAN : $LAN_IF  ($LAN_IP_WITH_MASK)"
echo "  DMZ : $DMZ_IF  ($DMZ_IP_WITH_MASK)"
echo ""

read -p "この設定で進めますか？ (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "中止しました。"
    exit 0
fi

# 3) Gateway を簡易入力（最後のセグメントだけ）

# LAN のプレフィックス（例: 192.168.100.）
LAN_PREFIX=$(echo "$LAN_IP" | awk -F'.' '{print $1"."$2"."$3"."}')

echo ""
echo "LAN 側 ($LAN_IF) の現在の IP: $LAN_IP"
echo "LAN Gateway は ${LAN_PREFIX}X の形です。"
read -p "LAN Gateway の末尾 X を入力してください: " LAN_LAST
LAN_GW="${LAN_PREFIX}${LAN_LAST}"

# DMZ のプレフィックス（例: 10.0.0.）
DMZ_PREFIX=$(echo "$DMZ_IP" | awk -F'.' '{print $1"."$2"."$3"."}')

echo ""
echo "DMZ 側 ($DMZ_IF) の現在の IP: $DMZ_IP"
echo "DMZ Gateway は ${DMZ_PREFIX}X の形です。"
read -p "DMZ Gateway の末尾 X を入力してください: " DMZ_LAST
DMZ_GW="${DMZ_PREFIX}${DMZ_LAST}"

echo ""
echo "設定される Gateway:"
echo "  LAN_GW = $LAN_GW"
echo "  DMZ_GW = $DMZ_GW"
echo ""
read -p "この Gateway で適用しますか？ (y/n): " CONFIRM_GW
if [ "$CONFIRM_GW" != "y" ]; then
    echo "中止しました。"
    exit 0
fi

# 4) ネットワークアドレスを検出（例: 192.168.100.0/24）
LAN_NET=$(ip route list dev "$LAN_IF" scope link | awk 'NR==1{print $1}')
DMZ_NET=$(ip route list dev "$DMZ_IF" scope link | awk 'NR==1{print $1}')

if [ -z "$LAN_NET" ] || [ -z "$DMZ_NET" ]; then
    echo "LAN/DMZ のネットワークアドレスが取得できませんでした。"
    echo "ip route list dev $LAN_IF / $DMZ_IF を確認してください。"
    exit 1
fi

echo ""
echo "検出されたネットワーク:"
echo "  LAN : $LAN_NET"
echo "  DMZ : $DMZ_NET"
echo ""

echo "ルーティングを適用します..."
echo ""

# 5) main table の default route を LAN 側に設定
ip route del default 2>/dev/null
ip route add default via "$LAN_GW" dev "$LAN_IF"

# 6) ルーティングテーブル名を登録（存在しなければ追記）
grep -q -E '^[[:space:]]*100[[:space:]]+dmz$' /etc/iproute2/rt_tables || echo "100 dmz" >> /etc/iproute2/rt_tables
grep -q -E '^[[:space:]]*200[[:space:]]+internal$' /etc/iproute2/rt_tables || echo "200 internal" >> /etc/iproute2/rt_tables

# 7) dmz/internal テーブルをクリアして再構成
ip route flush table dmz
ip route flush table internal

# internal テーブル
ip route add "$LAN_NET" dev "$LAN_IF" src "$LAN_IP" table internal
ip route add default via "$LAN_GW" dev "$LAN_IF" table internal

# dmz テーブル
ip route add "$DMZ_NET" dev "$DMZ_IF" src "$DMZ_IP" table dmz
ip route add default via "$DMZ_GW" dev "$DMZ_IF" table dmz

# 8) ip rule を更新
ip rule del from "$LAN_IP" 2>/dev/null
ip rule del from "$DMZ_IP" 2>/dev/null

ip rule add from "$LAN_IP"/32 lookup internal
ip rule add from "$DMZ_IP"/32 lookup dmz

echo ""
echo "適用完了。現在の状態:"
echo "---- ip rule ----"
ip rule show
echo "---- main route ----"
ip route
echo "---- internal table ----"
ip route show table internal
echo "---- dmz table ----"
ip route show table dmz

echo ""
echo "=== 完了しました ==="
echo "Webmin で IP / Gateway を変更した後は、次のスクリプトを実行すると"
echo "LAN / DMZ のルーティングが自動で整います:"
echo ""
echo "  /usr/local/sbin/setup-routing.sh"
echo ""
echo "このパスをメモしておくか、Webmin のコマンドメニューに登録しておくと便利です。"
