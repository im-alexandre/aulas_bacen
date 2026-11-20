# Prática integrada na AWS — Terraform, Puppet e Ansible

O Terraform provisiona cinco EC2 Ubuntu 24.04. `puppet-server` entrega
catálogos aos agentes. `ansible-controller` executa um playbook por SSH.
`gerenciado-01`, `gerenciado-02` e `gerenciado-03` recebem as duas
configurações. Cada ferramenta gerencia um arquivo próprio com o mesmo
conteúdo, dono e permissões. Assim, a comparação usa os mesmos três alvos e
uma mudança equivalente sem disputa pelo mesmo arquivo.

| Máquina | Tipo inicial | Papel |
|---|---|---|
| `puppet-server` | `t3.medium` | Compila o catálogo e assina os certificados dos agentes |
| `ansible-controller` | `t3.micro` | Inicia as conexões SSH e executa o playbook |
| `gerenciado-01`, `gerenciado-02`, `gerenciado-03` | `t3.micro` cada | Consultam o Puppet Server e recebem as tarefas do Ansible |

## Preparar antes da gravação

- Use uma conta de laboratório e um perfil AWS CLI autenticado. O Terraform
  cria a VPC e a sub-rede pública com rota IPv4 para a internet. Use uma AMI
  da região escolhida e confira o custo de EC2, EBS e IPv4 público.
- Os comandos locais abaixo usam PowerShell 7, Terraform, AWS CLI e OpenSSH.
  Nos terminais das EC2, os comandos usam Bash. Execute o ensaio completo antes
  da tomada. A instalação de pacotes e a inicialização da JVM podem ser
  aceleradas na edição.
- Gere uma chave de uso exclusivo do laboratório, se ainda não existir.
  Use uma frase secreta e mantenha a chave privada no seu computador.

```powershell
ssh-keygen -t ed25519 -f "$HOME/.ssh/bacen-iac-aws"
$env:AWS_PROFILE = 'SEU_PERFIL_DE_LABORATORIO'
$regiao = 'us-east-1'  # Troque pela região do laboratório.
aws sts get-caller-identity --query Account --output text
aws ssm get-parameter --region $regiao --name '/aws/service/canonical/ubuntu/server/noble/stable/current/amd64/hvm/ebs-gp3/ami-id' --query Parameter.Value --output text
if (!(Test-Path terraform/terraform.tfvars)) {
    Copy-Item terraform/terraform.tfvars.example terraform/terraform.tfvars
}
```

Execute os comandos a partir desta pasta. Se o perfil usa SSO, autentique-se
com `aws sso login --profile $env:AWS_PROFILE` antes das consultas. Preencha
`terraform/terraform.tfvars` com a conta autorizada, a região, a AMI
retornada e o seu endereço IPv4 público com `/32`. O
exemplo contém valores fictícios. O Terraform registra somente a chave
pública na AWS. A resolução da AMI fica fora do HCL para mostrar um valor
fixo durante o ensaio e a gravação.

Cada máquina recebe um IP público temporário para baixar pacotes e para o
instrutor usar SSH. Nas cinco máquinas, o SSH público aceita apenas o IP
do instrutor. O controlador usa os IPs **privados** dos alvos na porta 22.
Os agentes usam o IP **privado** do servidor na porta 8140. Não há servidor
HTTP no exercício. A [rede](terraform/rede.tf) contém as regras separadas
do [bloco das EC2](terraform/main.tf).

## 1. Mostrar o HCL e provisionar

Abra `terraform/main.tf`. Leia o mapa com os cinco nomes, explique
`for_each` e siga as referências para a chave SSH, o grupo de segurança e o
arquivo de inicialização de cada papel. Os scripts em [bootstrap/](bootstrap/)
instalam os programas para a aula. Quem aplica o estado dentro das VMs
durante a demonstração são Puppet e Ansible.

```powershell
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=lab.tfplan
```

Confira o resumo e as cinco linhas de recurso `aws_instance.lab[...]`.
Além das cinco EC2, o plano inicial deve criar a chave SSH, três grupos de
segurança, oito regras, uma VPC, uma sub-rede, um Internet Gateway, uma
tabela de rotas e sua associação à sub-rede. Só prossiga depois de conferir
conta, região e recursos previstos.

```powershell
terraform -chdir=terraform apply lab.tfplan
terraform -chdir=terraform output maquinas
terraform -chdir=terraform plan
```

O segundo plano deve indicar ausência de mudanças na infraestrutura. Isso
não verifica arquivos dentro do Ubuntu. Aguarde `sudo cloud-init status --wait`
em cada VM antes de preparar Puppet ou Ansible. Se houver falha de
inicialização, veja `sudo tail -n 80 /var/log/cloud-init-output.log`.

## 2. Preparar as duas formas de acesso

No PowerShell local, leia os endereços do state e envie os arquivos. Na
primeira conexão, confira a impressão digital SSH da máquina antes de
aceitá-la. Confirme que o SSH e o `cloud-init` estão prontos.

```powershell
$chave = "$HOME/.ssh/bacen-iac-aws"
$vms = terraform -chdir=terraform output -json maquinas | ConvertFrom-Json -AsHashtable
$servidor = $vms['puppet-server'].ip_publico
$controle = $vms['ansible-controller'].ip_publico
$alvos = 'gerenciado-01', 'gerenciado-02', 'gerenciado-03'
terraform -chdir=terraform output -raw inventario_ansible | Set-Content -Encoding utf8NoBOM -NoNewline inventory.ini
scp -i $chave puppet/site.pp "ubuntu@${servidor}:site.pp"
scp -i $chave inventory.ini ansible/site.yml "ubuntu@${controle}:"
```

Entre no `puppet-server` com `ssh -i $chave "ubuntu@$servidor"`. Nele,
publique o manifesto e confira o nome usado para TLS.

```bash
sudo cloud-init status --wait
sudo systemctl is-active puppetserver
sudo puppet config print certname --section server
sudo puppet parser validate ~/site.pp
sudo install -D -m 0644 ~/site.pp /etc/puppet/code/environments/production/manifests/site.pp
```

O nome esperado do servidor é `puppet-server.bacen.test`. No PowerShell,
prepare nos três agentes a resolução desse nome pelo IP privado e defina
o nome de cada certificado. Confira as solicitações na CA antes de assinar.

```powershell
$servidorPrivado = $vms['puppet-server'].ip_privado
foreach ($alvo in $alvos) {
    $endereco = $vms[$alvo].ip_publico
    ssh -i $chave "ubuntu@$endereco" "sudo cloud-init status --wait && echo '$servidorPrivado puppet-server.bacen.test' | sudo tee -a /etc/hosts >/dev/null && sudo puppet config set server puppet-server.bacen.test --section main && sudo puppet config set certname ${alvo}.bacen.test --section main && sudo puppet ssl bootstrap --waitforcert 0"
}
```

Na primeira tentativa, o retorno pode indicar certificado pendente. No
servidor, liste e assine somente as três solicitações deste laboratório.

```bash
sudo puppetserver ca list
sudo puppetserver ca sign --certname gerenciado-01.bacen.test
sudo puppetserver ca sign --certname gerenciado-02.bacen.test
sudo puppetserver ca sign --certname gerenciado-03.bacen.test
```

Em `ansible-controller`, crie uma chave de laboratório para o controlador
acessar os alvos. A chave privada criada aqui fica no controlador.

```bash
ssh-keygen -t ed25519
```

Aceite o caminho padrão `~/.ssh/id_ed25519`. Se usar frase secreta,
carregue a chave com `ssh-add` em uma sessão com `ssh-agent`. De volta ao
PowerShell local, registre apenas a chave pública do controlador nos alvos.

```powershell
$chavePublicaControle = ssh -i $chave "ubuntu@$controle" 'cat ~/.ssh/id_ed25519.pub'
if ($LASTEXITCODE -ne 0 -or $chavePublicaControle -notmatch '^ssh-ed25519 [A-Za-z0-9+/=]+(?: .*)?$') {
    throw 'Confira a chave pública no controlador antes de prosseguir.'
}
foreach ($alvo in $alvos) {
    $endereco = $vms[$alvo].ip_publico
    $chavePublicaControle | ssh -i $chave "ubuntu@$endereco" 'umask 077; tr -d "\r" >> ~/.ssh/authorized_keys'
}
```

No controlador, abra `inventory.ini`. Faça a primeira conexão SSH com
`ssh ubuntu@IP_PRIVADO` para cada alvo e confira a impressão digital contra
a obtida no acesso direto do instrutor à mesma VM. Depois, confirme SSH e
Python. O módulo retorna `pong` nos três hosts.

```bash
ansible -i inventory.ini gerenciados -m ansible.builtin.ping
```

## 3. Comparar as execuções

**Puppet.** Mostre [site.pp](puppet/site.pp) no servidor. Em um terminal
aberto em cada VM gerenciada, rode `sudo puppet agent --test` e
`cat /etc/bacen-puppet.conf`. Cada agente envia seus dados ao servidor,
recebe o catálogo aplicável ao seu certificado e aplica o recurso
`file` localmente. Repita em um alvo e observe a ausência de alteração.
O retorno 2 no modo `--test` indica aplicação com mudança. O retorno 0
indica execução sem mudança. O serviço de execução periódica foi
desativado na preparação para controlar o momento da demonstração.

**Ansible.** Vá ao controlador, mostre [site.yml](ansible/site.yml) e
execute o playbook sobre o grupo inteiro.

```bash
ansible-playbook -i inventory.ini site.yml --syntax-check
ansible-playbook -i inventory.ini site.yml
ansible-playbook -i inventory.ini site.yml
```

O primeiro resumo deve mostrar `changed=1` por host e o segundo,
`changed=0`. Em uma VM gerenciada, confira `cat /etc/bacen-ansible.conf`.
No Ansible, uma execução parte do controlador e alcança os três alvos
listados. O software extra no alvo é o agente Puppet. Neste exemplo,
o Ansible usa SSH e o Python do Ubuntu.

**Desvio.** Em `gerenciado-01`, altere manualmente as duas configurações.

```bash
echo 'mensagem=Desvio manual' | sudo tee /etc/bacen-puppet.conf /etc/bacen-ansible.conf
sudo puppet agent --test
```

Nesse ponto o arquivo do Puppet deve ter voltado ao estado declarado,
enquanto o do Ansible ainda contém o desvio. No controlador, veja a
alteração proposta e depois aplique o playbook:

```bash
ansible-playbook -i inventory.ini site.yml --check --diff
ansible-playbook -i inventory.ini site.yml
```

Confira os dois arquivos em `gerenciado-01`. A aplicação do playbook
deve reparar apenas o alvo alterado. Terraform declara quais VMs existem,
Puppet reconcilia quando o agente solicita o catálogo, e Ansible
reconcilia quando o playbook é disparado pelo controlador.

## 4. Encerrar o laboratório

Depois de gravar e encerrar o uso, revise o plano de destruição no mesmo
diretório e com as mesmas credenciais. A destruição inclui a VPC e a
sub-rede criadas pelo laboratório. Evite apagar arquivos de state enquanto houver recursos
do laboratório para remover.

```powershell
terraform -chdir=terraform plan -destroy -out=limpeza.tfplan
terraform -chdir=terraform apply limpeza.tfplan
terraform -chdir=terraform state list
aws ec2 describe-instances --region $regiao --filters 'Name=tag:Lab,Values=bacen-iac-aws' 'Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down' --query 'Reservations[].Instances[].InstanceId'
```

Ao fim, aguarde a terminação das cinco EC2 e confira que o state ficou
vazio. Não distribua os arquivos `.tfplan`, o state, as chaves privadas
nem o `terraform.tfvars` preenchido.

## Sequência sugerida para a tomada

1. **Terraform** — mostre o HCL e rode da inicialização ao segundo plano.
   Use um corte entre a criação das EC2 e a primeira conexão.
2. **Puppet** — mostre os certificados preparados, depois uma execução do
   agente e a reaplicação. Os três alvos entram na comparação.
3. **Ansible** — use o inventário gerado e execute o playbook nos três alvos.
4. **Comparação** — cause um desvio em um alvo, mostre a correção pelos dois
   fluxos e revise a destruição do laboratório.

## Referências

- [AWS — acesso à internet por uma sub-rede pública](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html)
- [Canonical — localizar a AMI do Ubuntu na AWS](https://documentation.ubuntu.com/aws/aws-how-to/instances/launch-ubuntu-ec2-instance/)
- [Puppet — portas e execução do agente](https://help.puppet.com/core/current/Content/PuppetCore/nix_agent_run_env.htm)
- [Ansible — comando ansible-playbook](https://docs.ansible.com/projects/ansible/latest/ansible-playbook.html)
