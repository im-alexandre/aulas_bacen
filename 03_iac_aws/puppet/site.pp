node 'gerenciado-01.bacen.test', 'gerenciado-02.bacen.test', 'gerenciado-03.bacen.test' {
  package { 'nginx':
    ensure => installed,
  }

  service { 'nginx':
    ensure  => running,
    enable  => true,
    require => Package['nginx'],
  }

  file { '/var/www/html/index.html':
    ensure  => file,
    require => Package['nginx'],
  }

  # Tipo de recurso fornecido pelo módulo puppetlabs/stdlib do Forge.
  file_line { 'titulo da pagina Nginx':
    path    => '/var/www/html/index.html',
    line    => '<h1>Servidor gerenciado pelo Puppet</h1>',
    match   => '^<h1>.*</h1>$',
    require => File['/var/www/html/index.html'],
  }
}
