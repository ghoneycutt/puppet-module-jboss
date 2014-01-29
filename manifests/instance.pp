# == Define: jboss::instance
#
# == Parameters:
#
# [*interface*]
# Which interface the app will listen on.
# - required
#
# [*console_log*]
# Path to app's console log.
# - default: "${app_dir}/log/console.log"
#
# [*instance*]
# Number corresponding to instance. Starts at 1 and increments.
#
# [*vhost_template*]
# Path to apache vhost template in either autoloader format such as
# 'myapp-vhost.conf.erb' or a fully qualified path such as
# '/srv/app_templates/myapp-vhost.conf.erb'.
# - default: 'default-vhost.conf.erb'
#
define jboss::instance (
  $interface,
  $log_age = 30,
  $log_unzip_days = 2,
  $newrelic_license_key = 'f3303ace67c7b1ebdc8f9ba68bcf6ff1f2aaf3f0',
) {

  include apache
  include common
  include jboss
  require 'appsvn'
  require 'svn::client'
  include wget

  $app_name = template('jboss/app_name.erb')

  # Tags everything with the appname for more specific puppet runs
  tag $app_name

  # validate $app_name
  validate_re($app_name, '[A-Za-z_-]', "${instancename} -- app_name <${app_name}> does not match regex")

  $instancename = $name

  # Hash of config entries for app
  $config           = hiera_hash("${app_name}::config")

  if $config['approved'] == true {
    # validate $interface
    validate_re($interface, '^\S+$', "${instancename} -- interface <${interface}> does not match regex.")

    # Where the application is located
    # /usr/local/jboss/server/fooapp1
    $app_dir = "${jboss::apps_dir}/${instancename}"

    # set console log
    $console_log = $config['console_log']

    if $console_log {
      $real_console_log = $console_log
    } else {
      $real_console_log = "${app_dir}/log/console.log"
    }

    # validate console log
    validate_absolute_path($real_console_log)

    # set java_instance_args
    $java_instance_args = $config['java_instance_args']

    if $java_instance_args {
      $real_java_instance_args = $java_instance_args
    } else {
      $real_java_instance_args = ''
    }


    $instancenum = template('jboss/instance.erb')

    # validate $instance
    if is_integer($instancenum) == false {
      fail("Name is ${instancename} and instance is <${instancenum}> which is not an integer.")
    }

    # validate $app_dir
    validate_re($app_dir, '^(\/)?([^\/\0]+(\/)?)+$', "${instancename} -- app_dir <${app_dir}> does not match regex")

    # Name of Datasources
    $datasources = $config['datasources']

    # Config entries from config hash
    $branch = $config['branch']

    # validate branch
    validate_re($branch, '^([^\/\0]+(\/)?)+$', "${instancename} -- branch <${branch}> does not match regex.")

    $deploy_dir_owner = $config['deploy_dir_owner'] ? {
      undef   => $jboss::user,
      default => $config['deploy_dir_owner'],
    }

    # validate $deploy_dir_owner
    validate_re($deploy_dir_owner, '^[a-z][-a-z0-9]*$', "${instancename} -- deploy_dir_owner <${deploy_dir_owner}> does not match regex.")

    $deploy_dir_group = $config['deploy_dir_group'] ? {
      undef   => $jboss::user,
      default => $config['deploy_dir_group'],
    }

    # validate $deploy_dir_group
    validate_re($deploy_dir_group, '^[a-z][-a-z0-9]*$', "${instancename} -- deploy_dir_group <${deploy_dir_group}> does not match regex.")

    $java_args = $config['java_args'] ? {
      # default values if key is not found in hash
      undef   => ['-Dorg.jboss.resolver.warning=true',
                  '-Dsun.rmi.dgc.client.gcInterval=3600000',
                  '-Dsun.rmi.dgc.server.gcInterval=3600000'],
      # else use values from hash
      default => $config['java_args'],
    }

    $java_heap = downcase($config['java_heap']) ? {
      undef   => '512m',
      default => downcase($config['java_heap']),
    }

    # validate java_heap
    validate_re($java_heap, '^[0-9]+(k|m|g)$', "${instancename} -- java_heap <${java_heap}> does not match regex.")

    $java_perm_size = downcase($config['java_perm_size']) ? {
      undef   => '256m',
      default => downcase($config['java_perm_size']),
    }

    # validate java_perm_size
    validate_re($java_perm_size, '^[0-9]+(k|m|g)$', "${instancename} -- java_perm_size <${java_perm_size}> does not match regex.")

    # used in vhost template
    $serveradmin = $config['serveradmin'] ? {
      undef   => $jboss::serveradmin,
      default => $config['serveradmin'],
    }

    case $config['jboss_war_file'] {
      undef: {
        fail("jboss::app::${instancename} - war_file must be defined in Hiera.")
      }
      default: {
        $war_file = $config['jboss_war_file']

        # validate war_file
        validate_re($war_file, '^[A-Za-z0-9_.-]+\.war$', "${instancename} -- war_file <${war_file}> does not match regex.")

        # strip the extension since we default the sub_path for apache vhost to
        # the war file minus .war
        $war_file_base_name = strip_file_extension($war_file, 'war')

        # validate war_file_base_name
        validate_re($war_file_base_name, '^[A-Za-z0-9_-]+$', "${instancename} -- war_file_base_name <${war_file_base_name}> does not match regex.")
      }
    }

    $proxy_path = $config['proxy_path'] ? {
      undef   => '/',
      default => $config['proxy_path'],
    }

    # validate proxy_path
    validate_re($proxy_path, '^\/([A-Za-z0-9\/_.]+)*', "${instancename} -- proxy_path <${proxy_path}> does not match regex.")

    $sub_path = $config['sub_path'] ? {
      undef   => "/${war_file_base_name}",
      default => $config['sub_path'],
    }

    # validate sub_path
    validate_re($sub_path, '^\/([A-Za-z0-9\/_.]+)*', "${instancename} -- sub_path <${sub_path}> does not match regex.")

    $servername    = $config['servername']
    $serveraliases = $config['serveraliases']
    $ssl           = $config['ssl']

    $cleaned_name = clean_name($instancename)
    $server_default_alias = "${cleaned_name}${::fqdn}"

    $proxy_timeout = $config['proxy_timeout']

    $extra_apache_config = $config['extra_apache_config']

    $vhost_template = $config['vhost_template'] ? {
      undef   => 'default-vhost.conf.erb',
      default => $config['vhost_template'],
    }

    # validate $vhost_template
    validate_re($vhost_template, '[\/\.A-Za-z_-]+.erb$', "${instancename} -- vhost_template <${vhost_template}> does not match regex.")

    # if vhost_template is a fully qualified path, use that, else prepend
    # 'jboss/' to use the autoloader.
    if $vhost_template =~ /^\// {
      $real_vhost_template = $vhost_template
    } else {
      $real_vhost_template = "jboss/${vhost_template}"
    }

    # validate servername
    $is_servername_valid = is_domain_name($servername)
    if $is_servername_valid != true {
      fail("jboss::app::${instancename} -- servername <${servername}> is invalid.")
    }

    # validate server_default_alias
    $is_server_default_alias_valid = is_domain_name($server_default_alias)
    if $is_server_default_alias_valid != true {
      fail("jboss::app::${instancename} -- server_default_alias <${server_default_alias}> is invalid.")
    }

    # formats interface to be passed on to a template to retrieve the fact.
    # Example: int_to_fact('bond0:0') returns 'ipaddress_bond0_0'.
    $listen_ip_fact = int_to_fact($interface)

    emailrequest::dns { "DNS for $server_default_alias":
      hostname     => $server_default_alias,
      ip           => getvar($listen_ip_fact),
    }

    # Hash of jboss ports
    $ports_hash = hiera_hash('jboss::ports')

    $jndi_port_offset = $ports_hash[$instancename]['offset']

    # validate jndi_port_offset
    validate_re($jndi_port_offset, '^[0-9]+$', "${instancename} -- jndi_port_offset <${jndi_port_offset}> does not match regex.")

    # calculate port based on offset
    $jndi_port = $jboss::jndi_port + ($jndi_port_offset * 100)
    $http_port = 8080 + ($jndi_port_offset * 100)

    # Array of all datasources
    $all_datasources = hiera('datasource')

    # Nagios Config
    $health_page = $config['health_custom_page']
    if ! $health_page {
      $real_health_page = "/health/"
    } else {
      $real_health_page = $health_page
    }

    $health_text = $config['health_custom_text']
    if ! $health_text {
      $real_health_text = "SUCCESS"
    } else {
      $real_health_text = $health_text
    }

    $contact_groups = $config['contact_groups']
    if ! $contact_groups {
      if $::env == "dev" or $::env == "test" {
        $real_contact_groups = "indywebemail"
      } else {
        $real_contact_groups = "indyweb"
      }
    } else {
      $real_contact_groups = $contact_groups
    }

    $check_period = $config['check_period']
    if ! $check_period {
      if $::env == "dev" or $::env == "test" {
        $real_check_period = "workhours_indy"
      } else {
        $real_check_period = "24x7"
      }
    } else {
      $real_check_period = $check_period
    }

    $normal_check_interval = $config['normal_check_interval']
    if ! $normal_check_interval {
      if $::env == "dev" or $::env == "test" {
        $real_normal_check_interval = "5"
      } else {
        $real_normal_check_interval = "5"
      }
    } else {
      $real_normal_check_interval = $normal_check_interval
    }

    $notification_interval = $config['notification_interval']
    if ! $notification_interval {
      if $::env == "dev" or $::env == "test" {
        $real_notification_interval = "90"
      } else {
        $real_notification_interval = "30"
      }
    } else {
      $real_notification_interval = $notification_interval
    }

    $first_notification_delay = $config['first_notification_delay']
    if ! $first_notification_delay {
      if $::env == "dev" or $::env == "test" {
        $real_first_notification_delay = "90"
      } else {
        $real_first_notification_delay = "5"
      }
    } else {
      $real_first_notification_delay = $first_notification_delay
    }

    $notification_period = $config['notification_period']
    if ! $notification_period {
      if $::env == "dev" or $::env == "test" {
        $real_notification_period = "workhours_indy"
      } else {
        $real_notification_period = "24x7"
      }
    } else {
      $real_notification_period = $notification_period
    }

    $event_handler = $config['event_handler']
    if ! $event_handler {
      $real_event_handler = "servicebounce!${instancename}"
    } else {
      if $event_handler == "none" {
        $real_event_handler = ""
      }
    }

    $listen_ip = getvar($listen_ip_fact)

    @@nagios_service { "${instancename}${hostname}":
      ensure              => present,
      use                 => "generic-service",
      host_name           => $hostname,
      service_description => "HTTP_${instancename} on ${fqdn}",
      check_command       => "hj_ae_check_http_generic!${::env}!${app_name}!-w 5!-c 10!-H ${servername}!-I ${listen_ip}!-p 80!-u ${health_page}!--onredirect=sticky!--string=\'${health_text}\'",
      contact_groups      => $real_contact_groups,
      event_handler       => $real_event_handler,
      first_notification_delay   => $real_first_notification_delay,
      check_period        => $real_check_period,
      notification_period => $real_notification_period,
      normal_check_interval   => $real_normal_check_interval,
      notification_interval   => $real_notification_interval,
      target              => "/etc/nagios/websites/${servername}.cfg",
    }


    # GH: TODO: wtf? the output is a number, though it does not match the regex
    # validate jndi_port
    #validate_re($jndi_port, '\d', "${instancename} -- jndi_port <${jndi_port}> does not match regex.")
    # validate http_port
    #validate_re($http_port, '^[0-9]+$', "${instancename} -- http_port <${http_port}> does not match regex.")

    if empty($datasources) {
      # No Datasources defined
    }
    else {
      # Verify datasources are defined. Get a list of all datasources, put their names into an array, error if any local datasources are missing from it.
      $verify_ds = inline_template("<% @alldsnames = [] -%><% for @ds in @all_datasources -%><% @alldsnames.push(@ds['name']) -%><% end -%>\
                                    <% for @dsname in @datasources -%><% if ! @alldsnames.index(@dsname) -%>Missing Datasource Definition: <%= @dsname -%>\
                                    <% end -%><% end -%>")

      # Fail if you can't find datasource in "Found" string
      if $verify_ds =~ /Missing/ {
        fail("${instancename} - ${verify_ds}")
      }

      $type = inline_template('<% for @dsname in @datasources -%><% for @ds in @all_datasources -%><% if @ds[\'name\'] == @dsname -%>Type:<%= @ds[\'type\'] %><% end -%><% end -%><% end -%>')

      # Oracle driver
      if $type =~ /Type:oracle/ {

        include oracle::driver

        wget::fetch { "${instancename}_oracle_driver":
          source      => "${oracle::driver::source}/${oracle::driver::file}",
          destination => "${app_dir}/lib/${oracle::driver::file}",
          timeout     => 0,
          verbose     => false,
          require     => File["${instancename}_lib_dir"],
          notify      => Service[$instancename],
        }
      }

      # MS SQL driver
      if $type =~ /Type:mssql/ {

        include mssql::driver

        wget::fetch { "${instancename}_mssql_driver":
          source      => "${mssql::driver::source}/${mssql::driver::file}",
          destination => "${app_dir}/lib/${mssql::driver::file}",
          timeout     => 0,
          verbose     => false,
          require     => File["${instancename}_lib_dir"],
          notify      => Service[$instancename],
        }
      }

      file { "${instancename}_datasource_config":
        ensure  => file,
        path    => "${app_dir}/deploy/${app_name}-ds.xml",
        content => template('jboss/datasource_config.xml.erb'),
        require => Exec["${instancename}_ensure_branch"],
        notify  => Service[$instancename],
      }

    }

    # used in init_script.erb
    $jboss_other_options = "-Djboss.service.binding.set=ports-${jndi_port_offset} ${real_java_instance_args}"

    # SVN source
    $svn_source = "${appsvn::protocol}://${appsvn::user}@${appsvn::server}${appsvn::base_path}/${app_name}/${branch}"

    vcsrepo { $app_dir:
      ensure   => present,
      provider => svn,
      source   => $svn_source,
    }

    file { $app_dir:
      ensure  => directory,
      owner   => $jboss::user,
      group   => $jboss::group,
      recurse => true,
      require => Vcsrepo[$app_dir],
      notify  => Service[$instancename],
    }

    file { "${app_dir}/newrelic":
      ensure  => directory,
      owner   => $jboss::user,
      group   => $jboss::group,
      mode    => '0755',
      require => Vcsrepo[$app_dir],
      notify  => Service[$instancename],
    }

    file { "${app_dir}/newrelic/newrelic.jar":
      ensure  => file,
      owner   => $jboss::user,
      group   => $jboss::group,
      mode    => '0755',
      source  => "puppet:///modules/jboss/newrelic.jar",
      require => File["${app_dir}/newrelic"],
      notify  => Service[$instancename],
    }

    file { "${app_dir}/newrelic/newrelic.yml":
      ensure  => file,
      owner   => $jboss::user,
      group   => $jboss::group,
      content => template('jboss/newrelic.yml.erb'),
      require => File["${app_dir}/newrelic"],
      notify  => Service[$instancename],
    }

    exec { "${instancename}_ensure_branch":
      command => "svn switch --non-interactive ${svn_source}",
      unless  => "svn info --non-interactive | grep ^URL: | awk  \'{print \$2}\' | grep ${svn_source}",
      cwd     => $app_dir,
      path    => '/bin:/usr/bin:/sbin:/usr/sbin',
      require => Vcsrepo[$app_dir],
      notify  => Service[$instancename],
    }

    file { "${instancename}_bindings-jboss-beans.xml":
      ensure    => file,
      path      => "${app_dir}/conf//bindingservice.beans/META-INF/bindings-jboss-beans.xml",
      source    => 'puppet:///modules/jboss/bindings-jboss-beans.xml',
      owner     => $jboss::user,
      group     => $jboss::group,
      mode      => '0644',
      subscribe => Exec["${instancename}_ensure_branch"],
      notify    => Service[$instancename],
    }

    common::mkdir_p { "${app_dir}/deploy":
      require => Exec["${instancename}_ensure_branch"],
      notify  => Service[$instancename],
    }

    file {"${instancename}_deploy_dir":
      ensure  => directory,
      path    => "${app_dir}/deploy",
      owner   => $deploy_dir_owner,
      group   => $deploy_dir_group,
      recurse => true,
      mode    => '0755',
      require => Common::Mkdir_p["${app_dir}/deploy"],
    }

    file { "${instancename}_log_cleanup":
      ensure  => file,
      path    => "/etc/cron.daily/${instancename}_cleanup",
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      content => template('jboss/log_cleanup.erb'),
    }

    common::mkdir_p { "${app_dir}/lib":
      require => Exec["${instancename}_ensure_branch"],
      notify  => Service[$instancename],
    }

    file { "${instancename}_lib_dir":
      ensure  => directory,
      path    => "${app_dir}/lib",
      owner   => $deploy_dir_owner,
      group   => $deploy_dir_group,
      recurse => true,
      mode    => '0755',
      require => Common::Mkdir_p["${app_dir}/lib"],
      notify  => Service[$instancename],
    }

    # java_args are validated in the template
    file { "${instancename}_run_conf":
      ensure  => file,
      path    => "${jboss::base_dir}/bin/${instancename}.run.conf",
      content => template('jboss/app_run.conf.erb'),
      notify  => Service[$instancename],
    }

    file { "${instancename}_apache_vhost":
      ensure  => file,
      path    => "/etc/httpd/conf.d/${instancename}.conf",
      content => template($real_vhost_template),
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      require => File['httpd_vdir'],
      notify  => Service['httpd'],
    }

    file { "${instancename}_init_script":
      ensure  => file,
      path    => "/etc/init.d/${instancename}",
      content => template('jboss/init_script.erb'),
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      notify  => Service[$instancename],
    }

    exec { "jboss_app_${instancename}_fact":
      command => "echo ${app_name}=${app_name} > /etc/facter/facts.d/${app_name}.txt",
      unless  => "grep ^${app_name}=${app_name}$ /etc/facter/facts.d/${app_name}.txt",
      path    => '/bin:/usr/bin:/sbin:/usr/sbin',
    }

    service { $instancename:
      ensure  => running,
      enable  => true,
      #    require => User[$jboss::user],
    }
  }
}
