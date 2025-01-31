require 'spec_helper_acceptance'

describe 'nut::cgi' do
  case fact('osfamily')
  when 'OpenBSD'
    conf_dir     = '/etc/nut'
    cgi_conf_dir = '/var/www/conf/nut'
    cgi_dir      = '/var/www/cgi-bin'
    docroot      = '/var/www/html'
    group        = 'wheel'
    url          = 'http://localhost/cgi-bin/nut/upsstats.cgi?host=dummy@localhost&treemode'
  when 'RedHat'
    conf_dir     = '/etc/ups'
    cgi_conf_dir = conf_dir
    cgi_dir      = '/var/www/nut-cgi-bin'
    docroot      = '/var/www/html'
    group        = 'root'
    url          = 'http://localhost/cgi-bin/upsstats.cgi?host=dummy@localhost&treemode'
  when 'Debian'
    conf_dir     = '/etc/nut'
    cgi_conf_dir = conf_dir
    cgi_dir      = '/usr/lib/cgi-bin'
    docroot      = '/usr/share/nut/www'
    group        = 'root'
    url          = 'http://localhost/cgi-bin/nut/upsstats.cgi?host=dummy@localhost&treemode'
  end

  it 'works with no errors' do
    pp = <<-EOS
      Package {
        source => $facts['os']['family'] ? {
          # $::architecture fact has gone missing on facter 3.x package currently installed
          'OpenBSD' => "http://ftp.openbsd.org/pub/OpenBSD/${::operatingsystemrelease}/packages/amd64/",
          default   => undef,
        },
      }

      include ::nut

      case $facts['os']['family'] {
        'RedHat': {
          include ::apache
          include ::epel

          Class['::epel'] -> Class['::nut']
        }
        'Debian': {
          include ::apache
        }
      }

      ::nut::ups { 'dummy':
        driver => 'dummy-ups',
        port   => 'sua1000i.dev',
      }

      file { '#{conf_dir}/sua1000i.dev':
        ensure => file,
        owner  => 0,
        group  => 0,
        mode   => '0644',
        source => '/root/sua1000i.dev',
        before => ::Nut::Ups['dummy'],
      }

      ::nut::user { 'test':
        password => 'password',
        upsmon   => 'master',
      }

      ::nut::client::ups { 'dummy@localhost':
        user     => 'test',
        password => 'password',
      }

      class { '::nut::cgi':
        apache_resources => {
          '::apache::vhost' => {
            'nut' => {
              'servername'  => 'localhost',
              'port'        => 80,
              'docroot'     => '#{docroot}',
              'scriptalias' => '#{cgi_dir}',
            },
          },
        },
      }

      ::nut::cgi::ups { 'dummy@localhost':
        description => 'Dummy UPS',
      }

      Class['::nut'] ~> Class['::nut::cgi']

      if $facts['os']['family'] == 'OpenBSD' {

        file { '/var/www/etc':
          ensure => directory,
          owner  => 0,
          group  => 0,
          mode   => '0644',
        }

        # Thanks for the hint bgplg(8)
        file { '/var/www/etc/resolv.conf':
          ensure => file,
          owner  => 0,
          group  => 0,
          mode   => '0644',
          source => '/etc/resolv.conf',
        }

        $content = @(EOS/L)
          server "localhost" {
                  listen on * port 80

                  location "/cgi-bin/nut/*" {
                          fastcgi
                          root "/"
                  }
          }
          | EOS

        file { '/etc/httpd.conf':
          ensure  => file,
          owner   => 0,
          group   => 0,
          mode    => '0644',
          content => $content,
        }

        service { 'slowcgi':
          ensure     => running,
          enable     => true,
          hasstatus  => true,
          hasrestart => true,
          require    => [
            Class['::nut::cgi'],
            File['/var/www/etc/resolv.conf'],
          ],
        }

        service { 'httpd':
          ensure     => running,
          enable     => true,
          hasstatus  => true,
          hasrestart => true,
          require    => Service['slowcgi'],
          subscribe  => File['/etc/httpd.conf'],
        }
      }
    EOS

    apply_manifest(pp, catch_failures: true)
    apply_manifest(pp, catch_changes:  true)
  end

  describe file("#{cgi_conf_dir}/hosts.conf") do
    it { is_expected.to be_file }
    it { is_expected.to be_mode 644 }
    it { is_expected.to be_owned_by 'root' }
    it { is_expected.to be_grouped_into group }
    its(:content) { is_expected.to match %r{^MONITOR dummy@localhost "Dummy UPS"$} }
  end

  describe file("#{cgi_conf_dir}/upsset.conf") do
    it { is_expected.to be_file }
    it { is_expected.to be_mode 644 }
    it { is_expected.to be_owned_by 'root' }
    it { is_expected.to be_grouped_into group }
    its(:content) { is_expected.to match %r{^I_HAVE_SECURED_MY_CGI_DIRECTORY$} }
  end

  describe command("curl '#{url}'") do
    its(:exit_status) { is_expected.to eq 0 }
    # rubocop:disable RepeatedDescription
    its(:stdout) { is_expected.to match %r{^<FONT SIZE="\+2">Dummy UPS<\/FONT>$} }
    its(:stdout) { is_expected.to match %r{^<TD>Smart-UPS 1000<br><\/TD>$} }
    # rubocop:enable RepeatedDescription
  end
end
