
git clone https://github.com/<あなた>/routing-tools.git
cp routing-tools/setup-routing.sh /usr/local/sbin/
chmod +x /usr/local/sbin/setup-routing.sh

-------------------------------------------------------------------

setup-routing.sh – LAN/DMZ ルーティング整形ツール

Version: 初期公開版
対象: 2NIC or 3NIC（LAN / DMZ / NASなど）Debian系サーバ
目的: Webmin で IP/GW を設定した後、routing を自動整形するツール

■ 概要

setup-routing.sh は、複数 NIC を持つ Linux サーバで
LAN（internal）と DMZ（外部公開）を同時運用するためのポリシールーティング構成を自動生成するスクリプトです。

特に以下のような環境で有効です：

eth0/enX0 = LAN（内部管理用）

eth1/enX1 = DMZ（外部公開）

eth2/enX2 = NAS 専用ネットワーク（※選択しなければ影響しません）

Gateway が LAN/DMZ で異なる

NIC 名が環境ごとにバラバラ

Webmin で IP 設定を行う運用

ルーティングだけスクリプトで調整したい

■ このスクリプトが行うこと

IPv4 を持つ NIC を自動検出

一覧表示し、LAN と DMZ を番号で選択

現在の IP を自動取得

Gateway は
“末尾のホスト部（例: 1, 3）だけ入力”
→ プレフィックスは自動生成

ルーティングテーブル dmz/internal を構築

ip rule を source-based routing で自動生成

main table の default route を LAN 側へ設定

適用後の状態を確認表示

※ IP/GW/DNS の設定そのものは Webmin が担当し、このスクリプトは「ルーティング整形」だけ行います。

■ 運用フロー（推奨）

Webmin で IP/GW/DNS を設定

設定反映（Apply Changes）

SSH または Webmin のコマンドシェルで実行：

/usr/local/sbin/setup-routing.sh


NIC 選択 → Gateway 末尾入力

完了

■ インストール方法
(1) 保存場所を作成
nano /usr/local/sbin/setup-routing.sh


スクリプト内容を貼り付けて保存。

(2) 実行権限を付与
chmod +x /usr/local/sbin/setup-routing.sh

■ 実行例
利用可能なインターフェース一覧:
  [0] enX0 192.168.100.63/24
  [1] enX1 10.0.0.63/24
  [2] enX2 172.16.0.63/24

LAN 側番号 → 0
DMZ 側番号 → 1

LAN Gateway: 192.168.100.X → X=1
DMZ Gateway: 10.0.0.X → X=3

■ 注意事項

NAS 用 NIC（例: enX2）は選ばなければルーティングに影響しません

Gateway を自動では設定しません（手動入力前提）

3 NIC 以上の構成でも動作します

policy-routing を再構成するため、外部接続元からのセッションは切断される場合があります

Debian 11 / 12 で検証済み

■ 推奨：Git リポジトリで管理

複数 VM を運用する場合は以下の構成で Git へ入れることを推奨します：

routing-tools/
├── setup-routing.sh
└── README.md


VM 側：

git pull
cp routing-tools/setup-routing.sh /usr/local/sbin/
chmod +x /usr/local/sbin/setup-routing.sh

■ ライセンス

社内インフラ用途を想定した自由利用。
第三者公開なしの前提。

必要であれば：

README に図解（文字ベース）を追加

3NIC 自動除外対応版を追加

systemd で「起動後一回だけ修復」する self-heal 版

Webmin からワンクリック実行するボタン版

などにも拡張できます。
