# UNORA — Instalador (bootstrap público)

Instalação do UNORA em um Raspberry Pi novo com um comando. O código fica
em um repositório privado; este repo público contém apenas o instalador,
que clona o repo privado via **deploy key SSH** gerada no próprio Pi.

```bash
curl -fsSL https://raw.githubusercontent.com/salemarsm/unora-installer/main/install.sh | sudo bash
```

## Fluxo

1. **1ª execução**: o instalador gera uma chave ed25519 no Pi e imprime a
   chave pública. Cadastre-a no GitHub como **Deploy Key (somente leitura —
   NÃO marque "Allow write access")**: repositório `salemarsm/unora` →
   Settings → Deploy keys → Add deploy key.
2. **2ª execução** (mesmo comando): clona, instala dependências, cria o
   venv com o Python do sistema, serviço systemd `unora`, timer de
   atualização, regras udev e o kiosk Chromium em tela cheia.

Idempotente: seguro rodar novamente em instalação existente (preserva IOCs
e resultados de análise; recupera dpkg interrompido).

## Opções (variáveis de ambiente)

| Variável | Padrão | Descrição |
|---|---|---|
| `NO_KIOSK` | — | `NO_KIOSK=1` instala sem kiosk (headless) |
| `INSTALL_DIR` | `/opt/unora` | Diretório de instalação |
| `SERVICE_NAME` | `unora` | Nome do serviço systemd |
| `PORT` | `8000` | Porta da API |
| `HOST` | `127.0.0.1` | Interface da API |
| `BRANCH` | `main` | Branch do repo privado |
| `REPO_URL` | `git@github.com:salemarsm/unora.git` | Repo de origem |

Exemplo: `sudo NO_KIOSK=1 PORT=8080 bash install.sh`

## Conexão SSH instável

A instalação morre junto com a sessão SSH se a conexão cair no meio. Basta
rodar de novo após reconectar — ou rode desacoplado da sessão, com log
persistente no Pi:

```bash
curl -fsSL https://raw.githubusercontent.com/salemarsm/unora-installer/main/install.sh -o /tmp/install.sh
sudo systemd-run --unit=unora-install \
  -p StandardOutput=append:/var/log/unora-install.log \
  -p StandardError=append:/var/log/unora-install.log \
  bash /tmp/install.sh

tail -f /var/log/unora-install.log   # acompanhar de qualquer reconexão
```

## Manutenção

Este `install.sh` é **cópia** de `scripts/install.sh` do repo privado
(`salemarsm/unora`). Não edite aqui — atualize no repo privado e publique
com `scripts/publish-installer.sh`.
