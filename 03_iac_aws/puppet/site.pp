node 'gerenciado-01.bacen.test', 'gerenciado-02.bacen.test', 'gerenciado-03.bacen.test' {
  file { '/etc/bacen-puppet.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "mensagem=Configuração padrão BACEN\n",
  }
}

node default {}
