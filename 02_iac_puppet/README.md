# Laboratório Puppet servidor–agente com Terraform

O Terraform cria VMs Ubuntu 24.04 no libvirt local. A VM `puppet-server`
armazena o manifesto e compila os catálogos. As VMs existentes (`web-01`,
`web-02` e `db-01`) podem atuar como agentes. A prática abaixo usa `web-01`;
repita a configuração para outro agente se desejar. O manifesto instala e
inicia o Nginx em **cada agente que receber o catálogo**.

O cloud-init instala o Puppet Server e os agentes pelos pacotes Ubuntu 24.04
`universe` (Puppet 8.4), além do `qemu-guest-agent`. Esses pacotes da
distribuição são distintos dos pacotes oficiais Puppet Core 9, usados no outro
roteiro do curso. A autenticação entre servidor e agente usa certificados;
assinamos cada pedido manualmente, sem autosign.

## 1. Criar as VMs

O host acessa diretamente por SSH o `puppet-server` e o `ansible-controller`.
O controlador executa o Ansible e acessa os agentes `web-01`, `web-02` e
`db-01` por SSH. O firewall de cada agente permite novas conexões SSH somente
do IP do controlador e bloqueia os outros acessos de entrada, mantendo as
respostas às conexões iniciadas pelo agente. O Puppet continua usando
`puppet-server` na porta TCP 8140. O NAT mantém a saída para os repositórios.

A rede usa `192.168.177.0/24` por padrão. Se essa faixa já estiver em uso,
configure `lab_cidr` no `terraform.tfvars` antes de provisionar. Cada VM
tem um `host_number` exclusivo que define seu endereço reservado.

No host Linux são necessários Terraform, libvirt/KVM, Bash, SSH, chave SSH e
acesso a `qemu:///system`. O pool `default` deve estar ativo. A
imagem `/var/lib/libvirt/images/ubuntu-24.04-base.qcow2` deve existir e ter
cloud-init. As VMs precisam acessar os repositórios Ubuntu, inclusive `universe`.
O servidor usa 4 GB de RAM; confira a capacidade disponível no host.

```bash
cp -n terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out=lab.tfplan
```

Se já houver VMs provisionadas, siga a seção de migração antes de aplicar.
Para uma instalação nova, prossiga com o bloco abaixo.

```bash
terraform apply lab.tfplan
terraform output vms
```

O IP pode estar disponível antes de o cloud-init concluir a instalação.
Anote os IPs de `puppet-server` e `ansible-controller`. Em um
`terraform.tfvars` anterior, copie os campos `host_number` e a entrada do
controlador a partir do exemplo.

### Migrar VMs existentes antes de aplicar o plano

O cloud-init faz a configuração inicial uma vez por instância. Para preservar
os discos e provisionar o firewall e o SSH em agentes existentes, execute o
bloco abaixo no host para cada agente, enquanto ele ainda estiver na rede
antiga. Use a mesma chave pública configurada em `ssh_public_key_path`.
O IP padrão do controlador é `192.168.177.11`; ajuste se mudou a sub-rede
ou o número do host. Antes de executar o bloco, confira no plano que os
volumes `libvirt_volume.disk` continuam intactos.

```bash
AGENTE_ATUAL=IP_ANTIGO_DO_AGENTE
IP_DO_CONTROLADOR=192.168.177.11
CHAVE_PUBLICA="$HOME/.ssh/id_ed25519.pub"

ssh "ubuntu@$AGENTE_ATUAL" 'sudo apt-get update && sudo apt-get install -y nftables'
ssh "ubuntu@$AGENTE_ATUAL" 'sudo puppet config set server puppet-server --section main'
ssh "ubuntu@$AGENTE_ATUAL" 'cat > /tmp/restringir-agente.sh' < scripts/restringir-agente.sh
{
  printf 'from="%s" ' "$IP_DO_CONTROLADOR"
  cat "$CHAVE_PUBLICA"
} | ssh "ubuntu@$AGENTE_ATUAL" "umask 077 && cat > ~/.ssh/authorized_keys.novo &&
   sudo bash /tmp/restringir-agente.sh '$IP_DO_CONTROLADOR' &&
   mv ~/.ssh/authorized_keys.novo ~/.ssh/authorized_keys &&
   rm /tmp/restringir-agente.sh"
```

Esse passo substitui as chaves autorizadas de `ubuntu` nos agentes. O
firewall pode encerrar o acesso direto a partir do host antes da troca de
rede. Aplique o plano revisado com `terraform apply lab.tfplan`. Em seguida,
desligue e inicie as VMs que ainda estiverem
usando as interfaces antigas. Se um agente tiver uma entrada manual com o IP
antigo de `puppet-server` em `/etc/hosts`, remova essa entrada pela sessão
via controlador para que ele passe a usar o DNS da rede do laboratório.

## 2. Preparar o servidor

Conecte-se ao endereço mostrado no output:

```bash
ssh ubuntu@IP_DO_SERVIDOR
sudo cloud-init status --wait
sudo systemctl status puppetserver --no-pager
```

O serviço pode levar alguns minutos para iniciar. Se falhar, consulte
`sudo journalctl -u puppetserver -n 80 --no-pager`. O manifesto inicial está em
`/etc/puppet/code/environments/production/manifests/site.pp`.

## 3. Conectar um agente e assinar seu certificado

Em outro terminal do host, carregue a chave do laboratório no agente SSH e
conecte-se ao controlador com encaminhamento do agente. A chave privada fica
no host. Use um controlador sob sua administração, pois ele pode solicitar
assinaturas ao agente SSH enquanto a sessão estiver aberta.

```bash
test -n "${SSH_AUTH_SOCK:-}" || eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
ssh -A ubuntu@IP_DO_CONTROLADOR
```

No controlador, aguarde o bootstrap, valide as chaves de host dos agentes na
primeira conexão e teste o inventário:

```bash
sudo cloud-init status --wait
ansible -i ~/inventory.ini agents -m ping -f 1
```

O inventário inicial fica em `~/inventory.ini`. Se alterar a lista ou os IPs
das VMs depois do primeiro boot, atualize-o pelo host com
`terraform output -raw ansible_inventory | ssh ubuntu@IP_DO_CONTROLADOR 'cat > ~/inventory.ini'`.

Ainda no controlador, conecte-se ao IP de `web-01` mostrado no output e
solicite o certificado:

```bash
ssh ubuntu@IP_DA_WEB_01
sudo cloud-init status --wait
sudo puppet agent --test --waitforcert 0
```

Do host, uma tentativa direta como
`ssh -o ConnectTimeout=5 ubuntu@IP_DA_WEB_01` deve expirar. O acesso
administrativo ao hipervisor continua permitindo controlar as VMs.

Na primeira tentativa, a solicitação do certificado é enviada e o comando
pode terminar com erro porque ela ainda não foi assinada: isso é esperado.
No terminal do **servidor**, liste os pedidos, confira o nome e assine apenas
o agente desejado:

```bash
sudo puppetserver ca list
sudo puppetserver ca sign --certname web-01
```

Use o `certname` que aparecer na listagem se for diferente. De volta ao
**agente**, peça e aplique o catálogo:

```bash
sudo puppet agent --test
curl -fsS http://localhost/
```

A saída esperada do `curl` contém `Servidor gerenciado pelo Puppet`. No modo
`--test`, o Puppet pode retornar código **2 quando realizou alterações**; isso
não significa falha. Reaplicar permite mostrar idempotência. Para testar a
reconciliação, altere `/var/www/html/index.html` no agente, execute novamente
`sudo puppet agent --test` e confira a página. A execução periódica permanece
desativada; esta prática usa execuções manuais para tornar o ciclo visível.

Repita a seção 3 para `web-02` se desejar, assinando seu certificado separado.
O DNS da rede resolve o nome `puppet-server` para o endereço reservado.

## 4. Alterar o manifesto

No host, edite `puppet/manifests/nginx.pp` e publique-o no servidor:

```bash
bash scripts/publicar-manifesto.sh IP_DO_SERVIDOR
```

O script valida o código antes de substituir `site.pp`. A chave privada SSH
deve estar no agente SSH ou no caminho padrão; para outra chave, use
`SSH_PRIVATE_KEY="$HOME/.ssh/minha_chave" bash scripts/publicar-manifesto.sh IP_DO_SERVIDOR`.
Na primeira conexão, confira a identidade SSH antes de aceitar a chave. Depois,
execute `sudo puppet agent --test` em cada agente para solicitar o novo catálogo.
O SSH publica o código no servidor; a distribuição e aplicação do catálogo são
feitas pelo Puppet.

Para remover todo o laboratório, após conferir os recursos afetados, use
`terraform destroy`. Não versione o state, chaves privadas ou credenciais.

## Referências

- [Pacote Ubuntu Puppet Server](https://packages.ubuntu.com/puppetserver)
- [Pacote Ubuntu Puppet Agent 24.04](https://packages.ubuntu.com/noble/puppet-agent)
- [Arquitetura servidor–agente](https://help.puppet.com/core/9/Content/PuppetCore/architecture.htm)
