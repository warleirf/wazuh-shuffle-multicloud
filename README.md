# Wazuh SIEM + Shuffle SOAR (Docker Compose)

Stack em um único host para coleta e tratamento de eventos multicloud e on-premises.
Indicada para laboratório/piloto: nó único, sem alta disponibilidade.

## Requisitos
- Linux com Docker Engine e plugin Compose, git e openssl
- Sugestão: 4 vCPU, 12 a 16 GB de RAM e 100 GB de disco

## Migração do modelo anterior
Antes de substituir o `docker-compose.yml` antigo, execute com ele ainda no lugar:
```bash
docker compose down --remove-orphans
```
Não use `-v`: isso apagaria os volumes, inclusive o banco do Shuffle.
O `setup.sh` salva o `.env` antigo em `.env.bak.*` e cria um novo.

## Instalação
```bash
git clone https://github.com/SEU-USUARIO/wazuh-shuffle-multicloud.git
cd wazuh-shuffle-multicloud
sudo ./setup.sh
docker compose up -d --remove-orphans
docker compose ps
```

## Acessos
| Serviço | URL | Login inicial |
|---|---|---|
| Wazuh | https://IP_DO_HOST | admin / SecretPassword |
| Shuffle | http://IP_DO_HOST:8080 ou https://IP_DO_HOST:3443 | criado no primeiro acesso |

## Segurança (antes de expor a rede)
- Troque as senhas padrão do Wazuh. Alterar só o `.env` não basta: siga o
  procedimento de troca de senha da documentação Docker do Wazuh 4.10
  (novo hash no `internal_users.yml`, `securityadmin.sh` e `wazuh.yml` para a API):
  https://documentation.wazuh.com/4.10/deployment-options/docker/wazuh-container.html
- Restrinja no firewall/security group as portas 443, 3443, 8080, 5001, 55000,
  1514, 1515 e 514/udp. Portas publicadas pelo Docker podem ignorar regras do UFW.
- Backend e Orborus montam `/var/run/docker.sock`, o que equivale a acesso root
  ao host. Use um host dedicado.
- Fixe versões das imagens do Shuffle (evite `latest`) após validar o ambiente.

## Diagnóstico
```bash
docker compose logs --tail=100 wazuh.indexer
docker compose logs --tail=100 wazuh.manager
docker compose logs --tail=100 shuffle-backend shuffle-orborus
```
