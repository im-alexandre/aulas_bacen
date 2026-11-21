# Prática na AWS com Terraform, Puppet e Forge

**Aula 45, Parte 2 · 17 minutos previstos · demonstração sem slides**

A aula começa com quatro máquinas vazias na AWS e termina com uma mudança manual sendo corrigida pelo Puppet. O aluno deve conseguir explicar **quem cria a infraestrutura**, **quem prepara cada máquina no primeiro boot** e **quem restaura a configuração quando ela se desvia**.

> **Abertura sugerida.** “Vamos subir um servidor Puppet e três máquinas gerenciadas. Quando as três estiverem com a página do Nginx funcionando, vou alterar o título em apenas uma delas. Quero que você preveja o que vai acontecer quando o agente rodar de novo.”

## Mapa da demonstração

| Etapa | Quem executa | O que fica pronto |
|---|---|---|
| Provisionar | Terraform, a partir do computador do instrutor | A rede, as regras de acesso e quatro EC2 Ubuntu 24.04 LTS |
| Preparar as máquinas | Cloud-init, dentro de cada EC2 | Puppet Server de um lado e Puppet Agent nos três nós |
| Definir o estado desejado | O instrutor, no manifesto `site.pp` | Pacote Nginx instalado, serviço ativo e título da página definido |
| Compilar e aplicar | Puppet Server compila o catálogo. Cada agente aplica o catálogo no próprio nó | O Nginx serve a página com o título declarado |
| Corrigir o desvio | O agente de `gerenciado-01`, ao rodar outra vez | O título volta ao valor declarado no manifesto |

O servidor é a EC2 `puppet-server` (`t3.medium`). As outras três, `gerenciado-01`, `gerenciado-02` e `gerenciado-03`, são `t3.micro`. Você entra nas quatro por **SSH** (porta 22, pelo IP público, com acesso restrito ao seu IPv4). Os agentes falam com o **Puppet Server** pela rede privada (porta 8140). Para ler a página, use **HTTP local** dentro de cada agente (`curl http://localhost/`).

### Divisão sugerida para a gravação

| Tempo | Mostre na tela | Pergunta que a etapa responde |
|---:|---|---|
| 3 min | Mapa de máquinas no HCL, resumo do plano e início do `apply` | O que o Terraform vai criar? |
| 3 min | Os dois YAMLs, o módulo instalado e as solicitações de certificado | Como cada VM fica pronta e como o servidor identifica os agentes? |
| 4 min | `site.pp`, primeira aplicação e resposta HTTP nos agentes | Como o código no servidor vira configuração no nó? |
| 5 min | Título original, alteração manual, correção e reaplicação sem mudanças | O que acontece quando o estado real diverge do desejado? |
| 2 min | Conclusão e resumo do plano de destruição | O que cada ferramenta fez e como encerramos o laboratório? |

Faça um ensaio antes da tomada. O tempo acima é para o vídeo. Use um corte entre o `apply` e o fim do cloud-init e outro, se preciso, enquanto o Puppet instala o Nginx. Este pacote teve validação local do Terraform e dos YAMLs, com plano simulado. O ensaio ponta a ponta nas EC2 ainda está pendente.

## Antes de gravar

Execute os blocos de PowerShell no seu computador, **a partir da pasta deste README**. Os blocos de Bash rodam na EC2 indicada. Tenha Terraform 1.10 ou superior dentro da série 1.x, AWS CLI, OpenSSH e um perfil autenticado de uma conta autorizada para o laboratório. As quatro EC2, os volumes e os IPv4 públicos podem gerar cobrança durante o ensaio.

```powershell
$env:AWS_PROFILE = 'SEU_PERFIL_DE_LABORATORIO'
$regiao = 'us-east-1'
$chave = "$HOME/.ssh/bacen-iac-aws"

# Se o perfil usa SSO, autentique antes das consultas.
# aws sso login --profile $env:AWS_PROFILE

if (-not (Test-Path -LiteralPath $chave)) {
    ssh-keygen -t ed25519 -f $chave
}
if (-not (Test-Path -LiteralPath 'terraform/terraform.tfvars')) {
    Copy-Item terraform/terraform.tfvars.example terraform/terraform.tfvars
}

aws sts get-caller-identity --query Account --output text
aws ssm get-parameter --region $regiao --name '/aws/service/canonical/ubuntu/server/noble/stable/current/amd64/hvm/ebs-gp3/ami-id' --query Parameter.Value --output text
```

Preencha `terraform/terraform.tfvars` com a mesma região de `$regiao`, o ID da conta retornado, a AMI oficial do Ubuntu 24.04 LTS retornada e seu IPv4 público seguido de `/32`. O provedor confere a conta contra `expected_account_id`. A AWS recebe a chave pública `bacen-iac-aws.pub`. O cliente SSH usa a chave privada que fica no seu computador. Se escolher outro caminho de chave, ajuste `ssh_public_key_path` e `$chave`. [Canonical · AMI do Ubuntu na AWS](https://ubuntu.com/aws/docs/aws-how-to/instances/launch-ubuntu-ec2-instance/)

## 1. Mostrar o plano e provisionar

Abra [terraform/main.tf](terraform/main.tf). Mostre o mapa `maquinas` e como `for_each` cria uma instância por entrada. Em `user_data`, a função `templatefile` preenche o YAML correspondente ao perfil com os dados do laboratório. O Puppet Server recebe o IP privado `10.42.1.10`. Os três agentes recebem esse endereço e um `certname` distinto.

Em [terraform/rede.tf](terraform/rede.tf), mostre a regra de SSH do instrutor e a regra que permite aos agentes chegar ao servidor na porta 8140. A saída para a internet permite baixar os pacotes do Ubuntu e o módulo do Forge.

```powershell
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=lab.tfplan
```

**O que conferir no plano.** Procure as quatro instâncias nomeadas, a VPC, a sub-rede, a rota e os grupos de segurança. Depois de revisar, aplique o plano salvo.

```powershell
terraform -chdir=terraform apply lab.tfplan
terraform -chdir=terraform output maquinas
```

**O que dizer.** “O Terraform terminou de criar as máquinas. Agora o Ubuntu ainda pode estar rodando o cloud-init. Vamos conferir o primeiro boot antes de testar o Puppet.”

Abra quatro terminais SSH. Identifique cada aba com o nome da máquina. Em cada PowerShell local, use a chave e o IP público correspondente da saída.

```powershell
ssh -i "$HOME/.ssh/bacen-iac-aws" ubuntu@IP_PUBLICO
```

## 2. Explicar o cloud-init e conectar os agentes

No [YAML do servidor](cloud-init/puppet-server.yaml), mostre três blocos.

- `packages` instala o `puppetserver` pelo repositório do Ubuntu.
- `write_files` grava o `site.pp` no ambiente `production`.
- `runcmd` instala `puppetlabs/stdlib` **9.7.0**, verifica a sintaxe do manifesto e habilita o serviço Puppet Server. No comando, `puppetlabs-stdlib` é o nome aceito pela CLI para o módulo listado no Forge como `puppetlabs/stdlib`.

No [YAML do agente](cloud-init/gerenciado.yaml), mostre a instalação de `puppet-agent`, a entrada em `/etc/hosts` que resolve `puppet-server.bacen.test` pelo IP privado e os campos `server` e `certname` no `puppet.conf`. O serviço periódico fica bloqueado para você decidir quando o agente roda na demonstração. [Documentação do cloud-init](https://docs.cloud-init.io/en/latest/reference/modules.html)

> **Ligação com o slide 7.** “Forge é o catálogo de onde vem o módulo. Aqui, o cloud-init usa `puppet module install` para instalar uma versão fixa no servidor. Em um fluxo com Git, o r10k usa o `Puppetfile` para instalar os módulos e publica o código do ambiente. O Code Manager automatiza essa publicação no Puppet Enterprise, usando r10k.” [Puppet Forge](https://forge.puppet.com/modules/puppetlabs/stdlib) · [r10k](https://help.puppet.com/pe/current/topics/set-up-r10k.htm) · [Code Manager](https://help.puppet.com/pe/current/topics/code_mgr.htm)

**No servidor Puppet**, aguarde o cloud-init e confirme que o serviço está ativo e que o módulo aparece na versão esperada.

```bash
sudo cloud-init status --wait
sudo systemctl is-active puppetserver
sudo puppet config print certname --section server
sudo puppet module list --environment production
```

A saída deve mostrar status `done`, serviço `active`, nome `puppet-server.bacen.test` e módulo `puppetlabs-stdlib` na versão `9.7.0`.

**Em cada um dos três agentes**, aguarde o cloud-init e envie a solicitação de certificado. `--waitforcert 0` devolve o terminal sem esperar pela assinatura. Uma mensagem indicando que o certificado ainda não foi assinado é esperada neste momento.

```bash
sudo cloud-init status --wait
sudo puppet ssl bootstrap --waitforcert 0
```

Com as solicitações enviadas, volte ao **servidor**. Confira os três nomes em `ca list` e assine os certificados correspondentes.

```bash
sudo puppetserver ca list
sudo puppetserver ca sign --certname gerenciado-01.bacen.test
sudo puppetserver ca sign --certname gerenciado-02.bacen.test
sudo puppetserver ca sign --certname gerenciado-03.bacen.test
```

**O que dizer.** “Cada nó se apresenta com seu próprio nome e pede um certificado. A autoridade certificadora do Puppet assina a solicitação. O agente então consegue se autenticar e pedir seu catálogo.” [Conexão do agente e assinatura do certificado](https://help.puppet.com/core/current/Content/PuppetCore/agent_primary_server_connections.htm)

## 3. Ler o manifesto e aplicar o primeiro catálogo

Abra [puppet/site.pp](puppet/site.pp). Leia o bloco `node` com os três nomes e siga os recursos na ordem indicada pelas dependências.

| Recurso | Estado declarado | Dependência |
|---|---|---|
| `package` | Nginx instalado | — |
| `service` | Nginx em execução e habilitado no boot | Pacote Nginx |
| `file` | `/var/www/html/index.html` existe | Pacote Nginx |
| `file_line` | O arquivo contém `<h1>Servidor gerenciado pelo Puppet</h1>` | Arquivo HTML |

**Distinção para explicar em voz alta.** O **manifesto** é o código que escrevemos. O **catálogo** é o conjunto de recursos e relações que o servidor compila para um nó. O **agente** pede esse catálogo, compara o que ele declara com o estado da máquina e aplica os ajustes localmente. O Nginx entra nessa etapa pelo recurso `package`.

Detenha-se no `file_line`, o recurso que veio do módulo do Forge. `path` escolhe o arquivo, `line` define o conteúdo desejado e `match` identifica a linha do título pelo padrão `^<h1>.*</h1>$`. Se a página estiver vazia, o recurso acrescenta o título. Se a linha tiver o mesmo formato e outro texto, o recurso a substitui pelo valor declarado. [Implementação de `file_line` no módulo stdlib 9.7.0](https://github.com/puppetlabs/puppetlabs-stdlib/blob/v9.7.0/lib/puppet/type/file_line.rb)

**Em cada agente**, execute uma vez e confira o título. Você pode mostrar a aplicação completa no primeiro e conferir rapidamente o resultado nos outros dois.

```bash
sudo puppet agent --test
echo "Código do Puppet: $?"
curl -fsS http://localhost/
```

Espere ver `<h1>Servidor gerenciado pelo Puppet</h1>` nos três. Em uma VM recém-criada, o código **2** é esperado se o Puppet instalou ou alterou recursos. O modo `--test` executa uma vez em primeiro plano **e aplica mudanças**. O código **0** indica execução bem-sucedida sem mudanças. Os códigos **1**, **4** e **6** pedem investigação antes de seguir. [Manual de `puppet agent`](https://help.puppet.com/core/current/Content/PuppetCore/Markdown/agent.htm)

## 4. Provocar e corrigir o desvio

Execute esta etapa **só em `gerenciado-01`**. Primeiro, mostre o título original. Depois, troque a linha manualmente e leia a página de novo.

```bash
curl -fsS http://localhost/
sudo sed -i 's|^<h1>.*</h1>$|<h1>Desvio manual</h1>|' /var/www/html/index.html
curl -fsS http://localhost/
```

Na segunda consulta, espere `<h1>Desvio manual</h1>`. **Faça uma pausa aqui.** Pergunte “Onde eu fiz a mudança? Qual título continua declarado no manifesto?” O arquivo dentro de `gerenciado-01` mudou. O manifesto continua declarando o título original. Essa diferença é o **desvio de configuração** (*configuration drift*).

Agora reaplique e compare.

```bash
sudo puppet agent --test
echo "Código do Puppet: $?"
curl -fsS http://localhost/
```

Mostre no log a alteração do recurso `File_line[titulo da pagina Nginx]`, o código **2** e o retorno de `<h1>Servidor gerenciado pelo Puppet</h1>`. O agente encontrou uma linha que corresponde ao padrão de título e restaurou o texto desejado. O Nginx volta a servir o título original na próxima requisição HTTP.

```bash
sudo puppet agent --test
echo "Código do Puppet: $?"
```

Espere código **0** e nenhuma mudança de recurso. Essa é a evidência de **idempotência**: com o estado já conforme, repetir a aplicação preserva o resultado. Se quiser mostrar o alcance da mudança, rode `curl -fsS http://localhost/` em `gerenciado-02`. Ele conservou o título declarado durante o experimento.

> **Fechamento sugerido.** “Terraform criou as EC2. O cloud-init preparou servidor e agentes. Quando alteramos a página em uma máquina, o agente Puppet reaplicou o catálogo e corrigiu o arquivo. Depois disso, rodar novamente só confirmou que o estado já estava correto.”

## 5. Encerrar e conferir a limpeza

De volta ao PowerShell local, revise o plano de destruição. Use o mesmo diretório, perfil, conta, região e state do provisionamento. Quando o plano listar os recursos deste laboratório, aplique-o.

```powershell
terraform -chdir=terraform plan -destroy -out=limpeza.tfplan
terraform -chdir=terraform apply limpeza.tfplan
terraform -chdir=terraform state list
```

A lista de recursos do state deve ficar vazia. Confira também no console da EC2 se as quatro instâncias do laboratório foram encerradas na região selecionada. Mantenha credenciais, chave privada, state, planos e o `terraform.tfvars` preenchido fora do material distribuído.

## Se o resultado divergir no ensaio

| Sintoma | Onde olhar primeiro |
|---|---|
| SSH não conecta | Confirme o IP público da saída `maquinas`, a chave privada correspondente e seu IPv4 atual em `instructor_cidr`. |
| Cloud-init ainda está rodando ou falhou | Na VM, rode `sudo cloud-init status --long` e `sudo tail -n 80 /var/log/cloud-init-output.log`. No servidor, procure a instalação do Puppet Server e o download do Forge. |
| A solicitação não aparece no servidor | No agente, rode `getent hosts puppet-server.bacen.test` e confira o IP `10.42.1.10`. No servidor, confira `sudo systemctl is-active puppetserver` e a regra de entrada 8140. |
| O catálogo falha com erro sobre `file_line` | No servidor, confirme `puppetlabs-stdlib` 9.7.0 com `sudo puppet module list --environment production`. |
| O título alterado não aparece | No nó em que você rodou o `sed`, leia `/var/www/html/index.html` e confira se a linha tem o formato `<h1>…</h1>`. Faça a consulta HTTP na mesma sessão SSH. |
