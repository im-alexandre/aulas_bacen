# Prática na AWS com Terraform, Puppet e Forge

**Aula 45, Parte 2 · meta provisória de 17 min · sem slides**

O Terraform cria quatro EC2 Ubuntu Server 24.04 LTS. O cloud-init prepara o
`puppet-server` (t3.medium) e três agentes, de `gerenciado-01` a
`gerenciado-03` (t3.micro). Depois de conectar os agentes e aplicar o catálogo,
altere o título da página do Nginx em um nó e mostre o Puppet restaurando
o texto declarado.

- [Terraform](terraform/main.tf) cria as máquinas e injeta a configuração de
  inicialização. O SSH público fica restrito ao IPv4 do instrutor. Os agentes
  acessam o servidor por IP privado, na porta 8140.
- [Cloud-init do servidor](cloud-init/puppet-server.yaml) instala o Puppet Server,
  baixa `puppetlabs/stdlib` do Forge na versão **9.7.0** e publica o manifesto
  no ambiente `production`.
- [Cloud-init do agente](cloud-init/gerenciado.yaml) instala o Puppet Agent,
  configura o nome do servidor e do certificado e bloqueia a execução periódica.
- [Manifesto](puppet/site.pp) declara o pacote e o serviço Nginx e usa
  `file_line`, recurso do módulo `stdlib`, para manter a linha do título no HTML.

## 1. Provisionar

Execute no PowerShell a partir desta pasta. Use uma conta de laboratório
autorizada, com Terraform, AWS CLI, OpenSSH e um perfil AWS autenticado.
Gere a chave apenas se ela ainda não existir.

```powershell
ssh-keygen -t ed25519 -f "$HOME/.ssh/bacen-iac-aws"
$env:AWS_PROFILE = 'SEU_PERFIL_DE_LABORATORIO'
$regiao = 'us-east-1'
aws sts get-caller-identity --query Account --output text
aws ssm get-parameter --region $regiao --name '/aws/service/canonical/ubuntu/server/noble/stable/current/amd64/hvm/ebs-gp3/ami-id' --query Parameter.Value --output text
Copy-Item terraform/terraform.tfvars.example terraform/terraform.tfvars -Confirm
```

Use a região da aula em `$regiao` e no `terraform.tfvars`. Preencha também a
conta, a AMI retornada e o seu IPv4 público com sufixo `/32`. Se o perfil usa
SSO, autentique com `aws sso login --profile $env:AWS_PROFILE` antes das consultas.

```powershell
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=lab.tfplan
terraform -chdir=terraform apply lab.tfplan
terraform -chdir=terraform output maquinas
```

Confira as quatro EC2 e a rede no plano. Após o `apply`, aguarde o
`cloud-init` em cada máquina. Use o IP público da saída e a chave local com
`ssh -i "$HOME/.ssh/bacen-iac-aws" ubuntu@IP_PUBLICO`.

## 2. Conectar os agentes e aplicar o catálogo

No **servidor**, confira a inicialização, o serviço, o certificado e o
módulo baixado.

```bash
sudo cloud-init status --wait
sudo systemctl is-active puppetserver
sudo puppet config print certname --section server
sudo puppet module list --environment production
```

O certificado do servidor deve usar `puppet-server.bacen.test`. Em **cada
agente**, aguarde o cloud-init e solicite o certificado. Na primeira execução,
a mensagem de certificado pendente é esperada.

```bash
sudo cloud-init status --wait
sudo puppet ssl bootstrap --waitforcert 0
```

Volte ao **servidor**. Confira os nomes na lista de solicitações e assine os
três certificados do laboratório.

```bash
sudo puppetserver ca list
sudo puppetserver ca sign --certname gerenciado-01.bacen.test
sudo puppetserver ca sign --certname gerenciado-02.bacen.test
sudo puppetserver ca sign --certname gerenciado-03.bacen.test
```

Em **cada agente**, aplique o catálogo e confira a página. O Puppet Server
compila o catálogo a partir do manifesto. O agente recebe o catálogo e
aplica o estado no próprio nó.

```bash
sudo puppet agent --test
curl -fsS http://localhost/
```

O título esperado é `Servidor gerenciado pelo Puppet`. Em caso de falha de
inicialização, confira `sudo tail -n 80 /var/log/cloud-init-output.log`.

## 3. Demonstrar o desvio em um único nó

Em **gerenciado-01**, troque a linha do título e leia a página antes da
reaplicação. Os dois outros agentes conservam o título definido no manifesto.

```bash
sudo sed -i 's|^<h1>.*</h1>$|<h1>Desvio manual</h1>|' /var/www/html/index.html
curl -fsS http://localhost/
sudo puppet agent --test
curl -fsS http://localhost/
sudo puppet agent --test
```

Na saída, mostre o título alterado, a correção do recurso `File_line` e o
retorno do título original. A última execução deve terminar sem alterações.
O modo `--test` retorna **2** quando há correção bem-sucedida e **0** quando
o nó já está no estado desejado. O Nginx serve o HTML atualizado sem reinício.

## 4. Encerrar

Revise o plano de destruição e use as mesmas credenciais e o mesmo state.

```powershell
terraform -chdir=terraform plan -destroy -out=limpeza.tfplan
terraform -chdir=terraform apply limpeza.tfplan
terraform -chdir=terraform state list
```

Confirme que o state ficou vazio e que as instâncias do laboratório foram
encerradas. Mantenha credenciais, chave privada, state, planos e o
`terraform.tfvars` preenchido fora do material distribuído.

## Referências

- [Cloud-init — módulos de configuração](https://docs.cloud-init.io/en/latest/reference/modules.html)
- [Puppet Forge — puppetlabs/stdlib](https://forge.puppet.com/modules/puppetlabs/stdlib)
- [Puppet — instalação de módulos pela linha de comando](https://help.puppet.com/core/current/content/puppetcore/modules_installing_from_commandline.htm)
- [Puppet — conexão e assinatura de certificado do agente](https://help.puppet.com/core/current/Content/PuppetCore/agent_primary_server_connections.htm)
