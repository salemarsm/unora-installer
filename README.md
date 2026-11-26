
## Conexão SSH instável

A instalação morre junto com a sessão SSH se a conexão cair no meio. Basta
rodar de novo após reconectar (idempotente, recupera dpkg interrompido) — ou
rode desacoplado da sessão, com log persistente no Pi:

```bash
curl -fsSL https://raw.githubusercontent.com/salemarsm/unora-installer/main/install.sh -o /tmp/install.sh
sudo systemd-run --unit=unora-install \
  -p StandardOutput=append:/var/log/unora-install.log \
  -p StandardError=append:/var/log/unora-install.log \
  bash /tmp/install.sh
tail -f /var/log/unora-install.log   # acompanhar de qualquer reconexão
```
