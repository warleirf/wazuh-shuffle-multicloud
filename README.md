# Wazuh SIEM + Shuffle SOAR (Docker Compose)

Wazuh 4.10.0 (SIEM) e Shuffle (SOAR) implantados com um único `docker-compose.yml`,
voltado a pequenas e médias empresas.

> **Estado do projeto:** laboratório. Nó único, sem alta disponibilidade.
> A integração Wazuh → Shuffle e a coleta em nuvem ainda não estão incluídas.

## Componentes
| Serviço no Compose | Função |
|---|---|
| `wazuh.manager` | Recebe e analisa eventos |
| `wazuh.indexer` | Armazena e indexa os alertas |
| `wazuh.dashboard` | Interface web do Wazuh |
| `shuffle-frontend` | Interface web do Shuffle |
| `shuffle-backend` | API do Shuffle |
| `shuffle-orborus` | Executa os workflows |
| `shuffle-opensearch` | Banco de dados do Shuffle |
| `wazuh-certs-gen` | Gera os certificados (usado só pelo `setup.sh`) |

## 1. Requisitos
**Servidor ou VM** com Debian 12 ou 13, acesso à internet e acesso root.

| Recurso | Sugestão para laboratório |
|---|---|
| CPU | 4 vCPUs |
| Memória | mínimo 8 GB; recomendado 12 a 16 GB |
| Disco | 100 GB |

São estimativas iniciais. O dimensionamento real depende do volume de eventos e da retenção.

**VirtualBox:** use o adaptador de rede em modo **Bridge**, para acessar a VM pela rede local.
Com NAT, é preciso configurar redirecionamento de portas.

Antes de começar, confirme que as portas 443, 514/udp, 1514, 1515, 3443, 5001, 8080 e 55000
estão livres.

## 2. Preparar o sistema
Todos os comandos deste guia são executados como **root** (`su -`).

```bash
apt update
apt install -y ca-certificates curl git openssl
```

## 3. Instalar o Docker Engine e o Compose
Pule esta etapa se `docker compose version` já funcionar. Se houver pacotes Docker da
distribuição instalados, siga antes a
[documentação oficial](https://docs.docker.com/engine/install/debian/) para removê-los.

```bash
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

tee /etc/apt/sources.list.d/docker.sources <<DOCKER
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
DOCKER

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Verifique:
```bash
systemctl enable --now docker
docker run --rm hello-world
docker compose version
```

## 4. Baixar o projeto
Troque `SEU-USUARIO` pelo usuário do repositório. Repositórios privados exigem token ou chave SSH.

```bash
cd /opt
git clone https://github.com/warleirf/wazuh-shuffle-multicloud.git
cd /opt/wazuh-shuffle-multicloud
```
Execute os próximos comandos dentro dessa pasta.

## 5. Preparar o ambiente
```bash
bash setup.sh
```
O script:
1. ajusta `vm.max_map_count`, exigido pelo indexer;
2. cria o `.env`, com as senhas iniciais do Wazuh e uma chave de criptografia do Shuffle
   (um `.env` sem essa chave é copiado para `.env.bak.*` e substituído);
3. baixa as configurações oficiais do Wazuh 4.10.0 para `wazuh/config/`;
4. gera os certificados.

Continue somente se a última mensagem começar com `Pronto`.
Não é preciso criar nem editar o `.env` manualmente. O arquivo `.env.example` apenas
documenta as variáveis usadas; o `.env` real nunca deve ir para o Git.

**Guarde uma cópia segura do `.env`.** Se a chave `SHUFFLE_ENCRYPTION_MODIFIER` for perdida ou
alterada, as autenticações dos apps no Shuffle precisarão ser refeitas.

## 6. Subir a stack
```bash
docker compose up -d
```
O primeiro boot baixa as imagens e pode levar vários minutos.

## 7. Validar
Aguarde cerca de 5 minutos.

```bash
docker compose ps -a
```
Devem aparecer 7 containers `Up`. O gerador de certificados não precisa ficar em execução.

```bash
# Reinícios e encerramento por falta de memória
docker inspect -f '{{.Name}} reinicios={{.RestartCount}} oom={{.State.OOMKilled}}' $(docker compose ps -aq)

# Saúde do indexer (esperado: green ou yellow). Usa a senha inicial
docker compose exec wazuh.indexer curl -sk -u admin:SecretPassword 'https://localhost:9200/_cluster/health?pretty'

# Envio de alertas do manager para o indexer (esperado: OK)
docker compose exec wazuh.manager filebeat test output
```

## 8. Primeiro acesso
Descubra o IP do servidor com `hostname -I`. Os certificados são autoassinados, por isso o
navegador mostra um aviso.

Faça este passo logo após subir a stack, em uma rede confiável.

### Shuffle
1. Acesse `https://IP_DO_SERVIDOR:3443`.
2. Na tela **Create administrator account**, crie o usuário e uma senha forte.
   Quem acessar primeiro poderá criar a conta de administrador.
3. Faça login.

Há também acesso por HTTP em `http://IP_DO_SERVIDOR:8080`, sem criptografia.

### Wazuh
Acesse `https://IP_DO_SERVIDOR` e entre com `admin` / `SecretPassword`.

### Testar a execução de workflows
No Shuffle, crie um workflow, adicione o app **Shuffle Tools** com a ação
**Repeat back to me**, informe um texto, salve e execute. O resultado deve terminar com sucesso.
Os apps podem demorar a aparecer no primeiro boot. Se a execução ficar parada:
```bash
docker compose logs --tail=100 shuffle-orborus shuffle-backend
```

## 9. Trocar as senhas padrão do Wazuh
As senhas iniciais são públicas. Troque-as antes de conectar agentes ou usar dados reais.
Alterar só o `.env` não basta. Faça um usuário por vez e use senhas **sem** `$`, `&` ou aspas.
Mantenha as aspas simples ao redor dos valores no `.env`. Saia do painel antes de começar.

Faça uma cópia das configurações:
```bash
cp -a .env .env.bak.manual
cp -a wazuh/config /root/wazuh-config.bak
```

### Usuários `admin` e `kibanaserver`
1. Pare a stack e gere o hash da nova senha:
   ```bash
   docker compose down
   docker run --rm -ti wazuh/wazuh-indexer:4.10.0 bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh
   ```
2. Em `wazuh/config/wazuh_indexer/internal_users.yml`, substitua o `hash` do usuário.
3. No `.env`, altere `INDEXER_PASSWORD` (para `admin`) ou `DASHBOARD_PASSWORD`
   (para `kibanaserver`), com a mesma senha usada no hash.
4. Suba a stack, aguarde de 2 a 5 minutos e entre no indexer:
   ```bash
   docker compose up -d
   docker compose exec wazuh.indexer bash
   ```
5. Dentro do container, aplique a alteração e saia:
   ```bash
   export JAVA_HOME=/usr/share/wazuh-indexer/jdk
   CERTS=/usr/share/wazuh-indexer/certs
   bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
     -cd /usr/share/wazuh-indexer/opensearch-security/ -nhnv -icl -p 9200 \
     -cacert $CERTS/root-ca.pem -cert $CERTS/admin.pem -key $CERTS/admin-key.pem
   exit
   ```

### Usuário da API (`wazuh-wui`)
A senha deve ter de 8 a 64 caracteres, com maiúscula, minúscula, número e símbolo.
1. Altere `password` em `wazuh/config/wazuh_dashboard/wazuh.yml`.
2. Altere `API_PASSWORD` no `.env` para o mesmo valor.
3. Recrie os containers:
   ```bash
   docker compose down
   docker compose up -d
   ```

Depois da troca, use a nova senha no comando de saúde da etapa 7.

## Integração Wazuh → Shuffle (opcional)
> Testada apenas a edição do arquivo de configuração; falta validar o envio na stack em execução.

1. No Shuffle, crie um workflow com o gatilho **Webhook**, salve e inicie o gatilho.
2. Copie só o identificador `webhook_...` do final da URL.
3. No servidor, execute:
   ```bash
   bash integrar-shuffle.sh webhook_SEU_ID
   ```
4. Gere um alerta das regras escolhidas e confira as execuções do workflow.

As regras padrão são `5712,5551,60204` (força bruta). Para mudar, defina `SHUFFLE_RULE_IDS` no `.env`
e execute `bash integrar-shuffle.sh` novamente. O script do Wazuh ignora algumas regras, entre elas a 5710.

Diagnóstico:
```bash
docker compose exec wazuh.manager grep -A6 '<name>shuffle' /var/ossec/etc/ossec.conf
docker compose exec wazuh.manager tail -n 50 /var/ossec/logs/integrations.log
docker compose exec wazuh.manager grep -i integrat /var/ossec/logs/ossec.log
```

## 10. Portas
| Porta | Uso | Quem deve acessar |
|---|---|---|
| 443/tcp | Painel Wazuh | Administradores |
| 3443/tcp, 8080/tcp | Painel Shuffle | Administradores |
| 5001/tcp | API do Shuffle | Administradores e integrações autorizadas |
| 55000/tcp | API do Wazuh | Administradores e integrações autorizadas |
| 1514/tcp, 1515/tcp | Eventos e registro de agentes | Servidores monitorados |
| 514/udp | Syslog | Publicada, mas **ainda não configurada** no manager |

## Operação
```bash
docker compose ps                          # status
docker compose logs --tail=80 SERVICO      # logs de um serviço
docker compose stop                        # parar
docker compose up -d                       # iniciar
docker compose down                        # remover containers, mantendo os volumes
git pull --ff-only && docker compose up -d # atualizar o projeto
```
**Atenção:** `docker compose down -v` apaga os volumes e os dados.

O que **não está no Git** e precisa de backup: `.env`, `wazuh/config/` e os volumes Docker.

## Solução de problemas
| Sintoma | O que fazer |
|---|---|
| `defina no .env` | Execute `bash setup.sh` na pasta do projeto |
| `wazuh-certs-tool.sh: No such file` | O compose é antigo; confira o `git pull` e a pasta em uso |
| `port is already allocated` | Veja quem usa a porta com `ss -lntup` |
| Conflito de nome de container | Há containers de outra instalação; confira com `docker ps -a` |
| Containers reiniciando | Confira `free -h`, o `oom` da etapa 7 e os logs |
| Painel Wazuh não fica pronto | Veja os logs de `wazuh.indexer`, depois `wazuh.manager` e `wazuh.dashboard` |
| `bad interpreter` ou erro com `\r` | O arquivo está com CRLF; salve com LF |

## Segurança
- Restrinja as portas por firewall de rede ou security group. Portas publicadas pelo Docker
  podem ignorar regras do UFW.
- `shuffle-backend` e `shuffle-orborus` montam `/var/run/docker.sock`, o que equivale a
  acesso root ao host. Use um host dedicado.
- O OpenSearch do Shuffle está sem autenticação. Não publique a porta dele.
- As imagens do Shuffle usam `latest`. Fixe versões testadas antes de usar em produção.

## Roteiro
- [x] Implantação do Wazuh e do Shuffle com Docker Compose
- [ ] Envio de alertas do Wazuh para o Shuffle
- [ ] Primeiro agente on-premises e coleta via syslog
- [ ] Coleta de eventos AWS, Azure e GCP
- [ ] Playbooks de triagem, notificação e resposta
- [ ] Backup, retenção, versões fixas e certificados para produção

## Referências
- [Wazuh em Docker (4.10)](https://documentation.wazuh.com/4.10/deployment-options/docker/wazuh-container.html)
- [Integrações do Wazuh](https://documentation.wazuh.com/4.10/user-manual/reference/ossec-conf/integration.html)
- [Docker no Debian](https://docs.docker.com/engine/install/debian/)
- [Shuffle](https://github.com/Shuffle/Shuffle)
