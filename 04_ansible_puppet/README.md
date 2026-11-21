# Aula 47 — Ansible e Puppet na prática com Prometheus

**Laboratório no terminal e no navegador · cerca de 40 minutos**

A equipe já acompanha cinco máquinas Linux. Hoje entram mais três. Ao final da aula, o aluno deve conseguir explicar por que uma VM pode existir no Azure e ainda não aparecer no monitoramento.

| Momento | O que mostrar | Tempo sugerido |
|---|---|---:|
| Ponto de partida | Cinco alvos em `UP`, incluindo o próprio coletor. | 5 min |
| Planejar a expansão | Alterar a frota de 5 para 8 e identificar as três adições no plano. | 8 min |
| Provisionar | Aplicar o plano, gerar o novo inventário e comparar com o painel. | 7 min |
| Incorporar os nós | Rodar o mesmo playbook e acompanhar o trabalho do Ansible e do Puppet. | 12 min |
| Conferir o resultado | Ver oito alvos em `UP` e ler uma métrica de cada máquina. | 8 min |

### Quem faz o quê

- **Terraform** cria o grupo de recursos `bacen-aula47`, a rede virtual, as regras de acesso e as VMs. Os IPs atribuídos pelo Azure alimentam o inventário do Ansible.
- **Ansible** acessa as máquinas por SSH, instala o Puppet, distribui o manifesto e configura o coletor central com a lista de alvos do inventário.
- **Puppet** mantém o **Node Exporter** instalado e ativo em cada VM. Esse serviço publica métricas do Linux na porta 9100.
- **Prometheus** roda em `coletor-prometheus`, consulta os exporters e exibe o resultado no navegador. O coletor também tem um exporter e conta como uma das oito máquinas. [Node Exporter](https://prometheus.io/docs/guides/node-exporter/)

## Antes de gravar · deixar cinco alvos em UP

Use o PowerShell nesta pasta para rodar o Terraform com a sessão do Azure CLI no Windows. Use o Ubuntu no WSL para executar Ansible e abrir o túnel SSH. As VMs usam Ubuntu Server 24.04 LTS com a versão da imagem fixada durante a aula. O tamanho `Standard_F1als_v7` tem 1 vCPU e 2 GiB de memória por VM, então a frota completa usa 8 vCPUs. [Autenticação do Terraform](https://learn.microsoft.com/en-us/azure/developer/terraform/authenticate/authenticate-to-azure) · [Características das VMs Falsv7](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/compute-optimized/falsv7-series)

### 1. Preparar as variáveis

No PowerShell, confira a assinatura ativa, a imagem e as cotas na região da prática. O SKU precisa estar disponível para a assinatura. A cota regional, a da família de VMs e a de IPs públicos precisam acomodar os oito nós. [Cotas de vCPU](https://learn.microsoft.com/en-us/azure/virtual-machines/quotas) · [Disponibilidade de SKUs](https://learn.microsoft.com/en-us/azure/azure-resource-manager/troubleshooting/error-sku-not-available)

```powershell
$regiao = 'eastus'
$tamanho = 'Standard_F1als_v7'
az account show --query '{nome:name, id:id}' --output table
az vm image show --location $regiao --urn Canonical:ubuntu-24_04-lts:server:latest --query name --output tsv
az vm list-skus --location $regiao --size $tamanho --all --query "[?name=='$tamanho'].{sku:name, familia:family, restricoes:restrictions}" --output json
az vm list-usage --location $regiao --output table
az network list-usages --location $regiao --output table

if (-not (Test-Path terraform/terraform.tfvars)) {
    Copy-Item terraform/terraform.tfvars.example terraform/terraform.tfvars
}
```

Em `terraform/terraform.tfvars`, use o ID da assinatura em `azure_subscription_id`, a versão retornada em `ubuntu_image_version` e o IPv4 público do instrutor com sufixo `/32` em `instructor_cidr`. Mantenha `quantidade_nos = 5`. Se mudar o SKU ou a região, ajuste `vm_size` e `azure_location`. O Terraform usa os provedores `Microsoft.Compute` e `Microsoft.Network` registrados na assinatura. [Exemplo de variáveis](terraform/terraform.tfvars.example) · [Provedores do Azure](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-providers-and-types)

No Ubuntu do WSL, instale o Ansible se necessário e crie a chave do laboratório se ela ainda não existir.

```bash
sudo apt install ansible-core
mkdir -p ~/.ssh
test -f ~/.ssh/bacen-iac-azure.pub || ssh-keygen -t rsa -b 3072 -f ~/.ssh/bacen-iac-azure
```

De volta ao PowerShell, copie somente a chave pública para o local que o Terraform lê. A chave privada permanece no WSL, onde o Ansible a carrega por meio de `ansible.cfg`.

```powershell
New-Item -ItemType Directory -Force "$HOME/.ssh" | Out-Null
$chavePublica = wsl.exe -d Ubuntu --cd '~' -- bash -c 'cat ~/.ssh/bacen-iac-azure.pub'
if ($LASTEXITCODE -ne 0) { throw 'Chave pública indisponível no Ubuntu.' }
$chavePublica | Set-Content -Encoding ascii "$HOME/.ssh/bacen-iac-azure.pub"
```

### 2. Criar e configurar o primeiro lote

```powershell
terraform -chdir=terraform init
terraform -chdir=terraform plan '-out=inicial.tfplan'
```

No plano inicial, confira `monitor-01` a `monitor-04` e `coletor-prometheus`. Os mesmos nomes aparecem no Azure, no Linux e no inventário. O plano inclui um IP público Standard e uma interface de rede para cada VM, além da rede compartilhada. O IP público permite SSH e dá saída à internet para instalar os pacotes. [Saída de rede no Azure](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access)

No PowerShell, aplique o plano e carregue a função que gera o inventário e copia a prática para o diretório Linux do WSL. Use essa função também após a expansão.

```powershell
terraform -chdir=terraform apply inicial.tfplan

function Atualizar-LabAnsible {
    $inventario = terraform -chdir=terraform output -raw inventario
    if ($LASTEXITCODE -ne 0) { throw 'Inventário indisponível no state.' }
    $inventario | Set-Content -Encoding ascii inventory.ini
    $homeLinux = wsl.exe -d Ubuntu --cd '~' -- pwd
    if ($LASTEXITCODE -ne 0) { throw 'Diretório do Ubuntu indisponível.' }
    $destino = '\\wsl.localhost\Ubuntu' + $homeLinux.Trim().Replace('/', '\') + '\bacen-aula47'
    New-Item -ItemType Directory -Force $destino | Out-Null
    Copy-Item ansible.cfg, instalar-puppet.yml, files, templates, inventory.ini -Destination $destino -Recurse -Force -ErrorAction Stop
}

Atualizar-LabAnsible
```

No terminal do Ubuntu, entre na cópia da prática e execute o playbook.

```bash
cd ~/bacen-aula47
[ ! -d .venv ] || source .venv/bin/activate
ansible-playbook instalar-puppet.yml
```

O playbook aguarda o SSH. Ele aplica o manifesto pela primeira vez e ativa um timer do systemd que volta a executar `puppet apply` na própria máquina. O segundo play instala o servidor Prometheus no coletor e publica a lista de alvos. [Playbook](instalar-puppet.yml) · [Manifesto Puppet](files/prometheus.pp)

### 3. Abrir o painel

Num **segundo PowerShell**, a partir desta mesma pasta, abra o túnel e deixe-o rodando. A porta 9090 do coletor é acessada pelo túnel. As regras de entrada permitem SSH na porta 22 pelo IPv4 do instrutor e coleta na porta 9100 a partir da interface privada do coletor.

```powershell
$coletor = terraform -chdir=terraform output -raw ip_painel
wsl.exe -d Ubuntu --cd '~' -- ssh -i '~/.ssh/bacen-iac-azure' -o ExitOnForwardFailure=yes -N -L 127.0.0.1:9090:127.0.0.1:9090 "ubuntu@$coletor"
```

Abra o painel de alvos e localize o grupo `linux`. O rótulo `node` identifica cada máquina. A coleta ocorre a cada cinco segundos. Comece a gravação quando os cinco alvos estiverem em **UP**. [Painel de alvos](http://127.0.0.1:9090/targets)

## Durante a aula

### 1. Mostrar as cinco máquinas em operação

No painel, aponte `coletor-prometheus` e os quatro nós `monitor-01` a `monitor-04`. No terminal do Ubuntu, mostre a mesma frota.

```bash
ansible-inventory --graph
```

Na tela de consultas, execute a expressão abaixo. O resultado esperado é **5**. Cada coleta bem-sucedida contribui com 1 para a soma. [Tela de consultas](http://127.0.0.1:9090/graph) · [Métrica up](https://prometheus.io/docs/concepts/jobs_instances/#automatically-generated-labels-and-time-series)

```promql
sum(up{job="linux"})
```

### 2. Pedir mais três VMs ao Terraform

Abra `terraform/terraform.tfvars` e mude **somente** a quantidade. Continue na mesma pasta do PowerShell, com o mesmo state e a mesma versão de Ubuntu do primeiro lote.

```hcl
quantidade_nos = 8
```

```powershell
terraform -chdir=terraform plan '-out=expansao.tfplan'
```

Peça ao aluno para localizar `monitor-06`, `monitor-07` e `monitor-08` antes de ler o resumo. O resultado esperado é **`9 to add, 0 to change, 0 to destroy`**. Cada novo nó acrescenta uma VM, uma interface e um IP público. O `for_each` usa o nome de cada máquina, então preserva os cinco nós iniciais. [Definição da frota](terraform/main.tf) · [Interfaces e IPs públicos](terraform/rede.tf)

### 3. Aplicar o plano e gerar o inventário de oito nós

No PowerShell, aplique e atualize o inventário.

```powershell
terraform -chdir=terraform apply expansao.tfplan
Atualizar-LabAnsible
```

No Ubuntu, mostre os oito nós no Ansible.

```bash
ansible-inventory --graph
```

Compare as duas telas. **O inventário já tem oito máquinas e o painel ainda conhece cinco.** O arquivo gerado pelo Terraform traz o IP público para o SSH e o IP privado para a coleta. O Prometheus continua lendo a última configuração que o Ansible publicou. [Saída de inventário](terraform/outputs.tf)

### 4. Incorporar as três novas máquinas ao monitoramento

```bash
ansible-playbook instalar-puppet.yml
```

Use o tempo de instalação para percorrer três trechos curtos.

1. No playbook, `hosts: monitor_lab` abrange a frota inteira. Nas três novas VMs, o Ansible instala o Puppet, copia o manifesto e dispara a primeira aplicação.
2. No manifesto, `package` instala `prometheus-node-exporter`. Em seguida, `service` coloca o exporter em execução e o habilita para a próxima inicialização. Nas máquinas já configuradas, o Puppet confere o mesmo estado declarado.
3. No segundo play, `hosts: coletor-prometheus` limita a atualização do painel ao coletor. O template percorre os oito nomes do inventário, o `promtool` verifica o arquivo e o handler recarrega a configuração quando a lista muda. [Template dos alvos](templates/prometheus.yml.j2)

### 5. Conferir os oito alvos e uma métrica real

Atualize a tela de alvos depois da coleta. Localize os **oito em UP**, inclusive os três nomes novos, e repita `sum(up{job="linux"})`. O resultado esperado agora é **8**.

Pergunte “Quanta memória cada uma dessas máquinas tem disponível agora?” Execute a consulta abaixo e aponte o rótulo `node` no resultado. Cada linha traz a memória disponível de uma VM, em MiB.

```promql
node_memory_MemAvailable_bytes{job="linux"} / 1024 / 1024
```

### Fechamento opcional · observar o Puppet recuperar um dos novos nós

Com os oito alvos em UP, acompanhe apenas `monitor-08`. Consulte o timer e pare o exporter quando faltarem pelo menos 40 segundos para o próximo disparo. Isso dá tempo de observar a queda no navegador.

```bash
ansible monitor-08 -m command \
  -a 'systemctl list-timers --all bacen-puppet-prometheus.timer'
ansible monitor-08 -b -m command \
  -a 'systemctl stop prometheus-node-exporter'
```

Na próxima coleta, `monitor-08` passa para **DOWN**. O timer reaplica o manifesto cerca de 60 segundos após o fim da aplicação anterior. O Puppet inicia o serviço e a coleta seguinte volta a marcar **UP**. A consulta `up{job="linux",node="monitor-08"}` mostra a queda no gráfico. Para explicar quem reativou o exporter, abra o registro da execução. [Timer do laboratório](files/bacen-puppet-prometheus.timer)

```bash
ansible monitor-08 -b -m command \
  -a 'journalctl -u bacen-puppet-prometheus.service --since=-5min --no-pager'
```

## Encerrar o laboratório

Feche o túnel com **Ctrl+C** no segundo terminal. No PowerShell principal, revise o plano de destruição e aplique-o com a mesma assinatura, região e state da aula.

```powershell
terraform -chdir=terraform plan -destroy '-out=limpeza.tfplan'
terraform -chdir=terraform apply limpeza.tfplan
terraform -chdir=terraform state list
```

Após a limpeza completa, a listagem do state fica vazia e o grupo de recursos `bacen-aula47` é removido.
