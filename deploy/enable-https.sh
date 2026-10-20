#!/usr/bin/env bash
# 买好域名、把 A 记录指向这台服务器后，开启 HTTPS：
#   cd ~/lingyi && git pull && sudo bash deploy/enable-https.sh api.你的域名.com
# 开启后 https://域名 可用，原来的 http://服务器IP 也继续能用，已经配好的软件不会断。
set -e
DOMAIN="$1"
if [ -z "$DOMAIN" ]; then echo "Usage: sudo bash deploy/enable-https.sh api.example.com"; exit 1; fi
cd "$(dirname "$0")"

MYIP=$(curl -s https://checkip.amazonaws.com)
DNSIP=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}')
if [ "$DNSIP" != "$MYIP" ]; then
  echo "DNS NOT READY: $DOMAIN -> ${DNSIP:-nothing}, this server is $MYIP"
  echo "Add an A record pointing to $MYIP, wait a few minutes, then run again."
  exit 1
fi

cat > Caddyfile <<CADDY
$DOMAIN, :80 {
    handle_path /buy* {
        root * /srv/buy
        file_server
    }
    reverse_proxy 127.0.0.1:3000 {
        flush_interval -1
    }
}
CADDY
docker compose restart caddy
echo ">> Waiting for the certificate..."
for i in $(seq 1 20); do
  if curl -fs -o /dev/null "https://$DOMAIN/api/status"; then
    echo ">> HTTPS OK: https://$DOMAIN"
    break
  fi
  sleep 3
done
if ! curl -fs -o /dev/null "https://$DOMAIN/api/status"; then
  echo "HTTPS NOT WORKING YET. Check that port 443 is open in the Lightsail firewall (Networking tab), then run this again."
  echo "http://$MYIP still works."
  exit 1
fi

read -rp "Admin username (to update the site address, Enter to skip): " NAME
if [ -n "$NAME" ]; then
  read -rsp "Admin password (hidden): " PASS; echo
  export NAME PASS DOMAIN
  python3 - <<'PY'
import json, os, sys, urllib.request
site = "http://127.0.0.1:3000"
def call(method, path, body=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(site + path, method=method,
        data=None if body is None else json.dumps(body).encode(), headers=headers)
    with urllib.request.urlopen(req) as r:
        return json.load(r)
login = call("POST", "/api/user/login", {"username": os.environ["NAME"], "password": os.environ["PASS"]})
if not login.get("success"):
    sys.exit("LOGIN FAILED: " + str(login.get("message")))
res = call("PUT", "/api/option/", {"key": "ServerAddress", "value": "https://" + os.environ["DOMAIN"]},
           login["data"]["access_token"])
print("SITE ADDRESS " + ("UPDATED" if res.get("success") else "FAILED: " + str(res.get("message"))))
PY
fi
