# == Define: jboss:app
#
# Jboss primary app config
#
define jboss::app (
) {

  include common
  include jboss

  $app_name = $name

  # Hash of config entries for app
  $config = hiera_hash("${app_name}::config")

  if $config['approved'] == true {

    $servername    = $config['servername']
    $serveraliases = $config['serveraliases']
    $ssl           = $config['ssl']
    $extra_apache_config = $config['extra_apache_config']


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
      $real_event_handler = "servicebounce!${instancename}${instancenum}"
    } else {
      if $event_handler == "none" {
        $real_event_handler = ""
      }
    }

  if $env == "dev" {
    $load_balance = "indclb5lab"
  } elsif $env == "test" {
    $load_balancer = "indclb5lab"
  } else {
    $pci_dmz = config['pci_dmz']
    if $pci_dmz {
      $load_balancer = "inlb7"
    } else {
      $load_balancer = "site1_balancer"
    }
  }

  $nagios_config_host = $config['nagios_config_host']

  if $ssl {
      $ssl_flag = "S"
      $http_opt = "--ssl"

      if "$nagios_config_host" == "$::hostname" {
        @@nagios_service { "CertCheck_${servername}":
          ensure              => present,
          use                 => 'certcheck',
          host_name           => $load_balancer,
          service_description => "CertCheck_${servername}",
          check_command       => "hj_ae_check_http_generic!${::env}!${app_name}!--ssl!-C 33!${servername}",
          target              => "/etc/nagios/websites/${servername}.cfg",
        }
      }
  } else {
    $http_opt = "-p 80"
  }


   if "$nagios_config_host" == "$::hostname" {
     @@nagios_service { "${servername}":
        ensure                    => present,
        use                       => "generic-service",
        host_name                 => $load_balancer,
        service_description       => "HTTP${ssl_flag}_${servername}",
        check_command             => "hj_ae_check_http_generic!${::env}!${app_name}!-w 5!-c 10!-H ${servername}!${http_opt}!-u ${health_page}!--onredirect=sticky!--string=\'${health_text}\'",
        contact_groups            => $real_contact_groups,
        first_notification_delay  => $real_first_notification_delay,
        check_period              => $real_check_period,
        notification_period       => $real_notification_period,
        normal_check_interval     => $real_normal_check_interval,
        notification_interval     => $real_notification_interval,
        target                    => "/etc/nagios/websites/${servername}.cfg",
     }
   }

  }
}
