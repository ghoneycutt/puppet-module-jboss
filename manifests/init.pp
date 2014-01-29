# == Class: jboss
#
# Manage jboss
#
class jboss (
  $base_dir        = '/usr/local/jboss',
  $apps_dir        = '/usr/local/jboss/server',
  $user            = 'jboss',
  $group           = 'jboss',
  $package         = 'jboss',
  $jndi_port       = '1099',
  $serveradmin     = "webmaster@${::domain}",
  $apache_log_path = '/var/log/httpd',
) {

  include apache
  include apache::mod::proxy
  include apache::mod::proxy_http
  include common
  include deployment
  include common::deploy_dir
  include java
  include newrelic

  # validate apache_log_path
  # used in apache vhost for jboss::app
  validate_absolute_path($apache_log_path)

  # create resources for all the jboss app's defined in hiera.
  $jboss_instances = hiera_hash('jboss_instances', undef)
  create_resources('jboss::instance', $jboss_instances)

  # Generate a list of all the app names on the server
  if $jboss_instances {
    $app_names = unique(regex(keys($jboss_instances), '(\D+)'))
    jboss::app { $app_names: }
  }

  common::mkdir_p { $base_dir: }

  file { $base_dir:
    ensure  => directory,
    owner   => $user,
    group   => $group,
    mode    => '0755',
    require => Common::Mkdir_p[$base_dir],
  }

  file { "apache_jboss_admin_block":
    ensure  => file,
    path    => "/etc/httpd/conf.d/jbossadminblock.conf",
    source  => "puppet:///modules/jboss/jbossadminblock.conf",
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => File['httpd_vdir'],
    notify  => Service['httpd'],
  }

  $all_users = hiera_hash(users)
  $userdetails = $all_users['jboss']
  @common::mkuser { $user:
    uid           => $userdetails['uid'],
    comment       => $userdetails['comment'],
    home          => $userdetails['home'],
    shell         => $userdetails['shell'],
    managehome    => false,
    manage_dotssh => false,
  }

  if $apps_dir != $base_dir {

    common::mkdir_p { $apps_dir: }

    file { $apps_dir:
      ensure  => directory,
      owner   => $user,
      group   => $group,
      mode    => '0755',
      require => Common::Mkdir_p[$apps_dir],
    }
  }

  package { 'jboss':
    ensure => installed,
    name   => $package,
  }
}
