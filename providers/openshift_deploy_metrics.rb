#
# Cookbook Name:: cookbook-openshift3
# Resources:: openshift_deploy_metrics
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

use_inline_resources
provides :openshift_deploy_metrics if defined? provides

def whyrun_supported?
  true
end

CHARS = ('0'..'9').to_a + ('A'..'Z').to_a + ('a'..'z').to_a

FOLDER = Chef::Config['file_cache_path'] + '/hosted_metrics'

def random_password(length = 10)
  CHARS.sort_by { rand }.join[0...length]
end

def encode_file(file)
  Base64.strict_encode64(::File.read(file))
end

def generate_route(route)
  route_skel = { 'apiVersion' => 'v1', 'kind' => 'Route', 'metadata' => {}, 'spec' => {} }
  route_skel['metadata'] = route['metadata']
  route_skel['spec'] = route['spec']
  open("#{FOLDER}/templates/#{route['metadata']['name']}-route.yaml", 'w') { |f| f << route_skel.to_yaml }
end

action :delete do
  converge_by 'Uninstalling Metrics' do
    directory "#{FOLDER}/templates" do
      recursive true
    end

    remote_file "#{FOLDER}/admin.kubeconfig" do
      source "file://#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig"
    end

    execute 'Scaling down cluster before deletion' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} get rc -l metrics-infra -o name \
              --config=#{FOLDER}/admin.kubeconfig \
              --namespace=#{node['cookbook-openshift3']['openshift_metrics_project']} | \
              xargs --no-run-if-empty #{node['cookbook-openshift3']['openshift_common_client_binary']} scale \
              --replicas=0 --namespace=#{node['cookbook-openshift3']['openshift_metrics_project']}"
    end

    execute 'Uninstalling metrics components' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} $ACTION --ignore-not-found \
              --selector=metrics-infra all,sa,secrets,templates,routes,pvc,rolebindings,clusterrolebindings \
              --config=#{FOLDER}/admin.kubeconfig \
              --namespace=#{node['cookbook-openshift3']['openshift_metrics_project']}"
      environment 'ACTION' => 'delete'
    end

    execute 'Uninstalling rolebindings' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} $ACTION \
              --ignore-not-found rolebinding/hawkular-view clusterrolebinding/heapster-cluster-reader \
              --config=#{FOLDER}/admin.kubeconfig \
              --namespace=#{node['cookbook-openshift3']['openshift_metrics_project']}"
      environment 'ACTION' => 'delete'
    end
  end
end

action :create do
  converge_by 'Deploying Metrics' do
    ose_major_version = node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'] : node['cookbook-openshift3']['ose_major_version']

    directory "#{FOLDER}/templates" do
      recursive true
    end

    cookbook_file "#{FOLDER}/import_jks_certs.sh" do
      source 'import_jks_certs.sh'
      mode '0755'
    end

    remote_file "#{FOLDER}/admin.kubeconfig" do
      source "file://#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig"
    end

    package 'java-1.8.0-openjdk-headless'

    execute 'Generate ca certificate chain' do
      command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} ca create-signer-cert \
              --config=#{FOLDER}/admin.kubeconfig \
              --key=#{FOLDER}/ca.key \
              --cert=#{FOLDER}/ca.crt \
              --serial=#{FOLDER}/ca.serial.txt \
              --name=metrics-signer@$(date +%s)"
    end

    %w(hawkular-metrics hawkular-cassandra heapster).each do |component|
      execute "Generate #{component} keys" do
        command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} ca create-server-cert \
                --config=#{FOLDER}/admin.kubeconfig \
                --key=#{FOLDER}/#{component}.key \
                --cert=#{FOLDER}/#{component}.crt \
                --hostnames=#{component} \
                --signer-key=#{FOLDER}/ca.key \
                --signer-cert=#{FOLDER}/ca.crt \
                --signer-serial=#{FOLDER}/ca.serial.txt"
      end

      ruby_block "Generate #{component} certificate" do
        block do
          ::File.open("#{FOLDER}/#{component}.pem", 'w+') { |f| f.puts ["#{FOLDER}/#{component}.key", "#{FOLDER}/#{component}.crt"].map { |s| IO.read(s) } }
        end
      end

      file "Generate random password for the #{component} keystore" do
        path "#{FOLDER}/#{component}-keystore.pwd"
        content random_password
      end

      execute "Create the #{component} pkcs12 from the pem file" do
        command "openssl pkcs12 -export -in #{FOLDER}/#{component}.pem \
                -out #{FOLDER}/#{component}.pkcs12 \
                -name #{component} -noiter -nomaciter \
                -password pass:$(cat #{FOLDER}/#{component}-keystore.pwd)"
      end

      file "Generate random password for #{component} truststore" do
        path "#{FOLDER}/#{component}-truststore.pwd"
        content random_password
      end
    end

    %w(hawkular-metrics hawkular-jgroups-keystore).each do |component|
      file "Generate random password for the #{component} truststore" do
        path "#{FOLDER}/#{component}.pwd"
        content random_password
      end
    end

    execute 'Generate htpasswd file for hawkular metrics' do
      command "htpasswd -b -c #{FOLDER}/hawkular-metrics.htpasswd hawkular $(cat #{FOLDER}/hawkular-metrics.pwd)"
    end

    execute 'Generate JKS certs' do
      command "#{FOLDER}/import_jks_certs.sh"
      environment lazy {
        {
          CERT_DIR: FOLDER.to_s,
          METRICS_KEYSTORE_PASSWD: ::File.read("#{FOLDER}/hawkular-metrics-keystore.pwd"),
          CASSANDRA_KEYSTORE_PASSWD: ::File.read("#{FOLDER}/hawkular-cassandra-keystore.pwd"),
          METRICS_TRUSTSTORE_PASSWD: ::File.read("#{FOLDER}/hawkular-metrics-truststore.pwd"),
          CASSANDRA_TRUSTSTORE_PASSWD: ::File.read("#{FOLDER}/hawkular-cassandra-truststore.pwd"),
          JGROUPS_PASSWD: ::File.read("#{FOLDER}/hawkular-jgroups-keystore.pwd")
        }
      }
    end

    if ose_major_version.split('.')[1].to_i < 6
      template 'Generate hawkular-metrics-secrets secret template' do
        path "#{FOLDER}/templates/hawkular_metrics_secrets.yaml"
        source 'secret.yaml.erb'
        variables lazy {
          {
            name: 'hawkular-metrics-secrets',
            labels: { 'metrics-infra' => 'hawkular-metrics' },
            data: {
              'hawkular-metrics.keystore' => encode_file("#{FOLDER}/hawkular-metrics.keystore"),
              'hawkular-metrics.keystore.password' => encode_file("#{FOLDER}/hawkular-metrics-keystore.pwd"),
              'hawkular-metrics.truststore' => encode_file("#{FOLDER}/hawkular-metrics.truststore"),
              'hawkular-metrics.truststore.password' => encode_file("#{FOLDER}/hawkular-metrics-truststore.pwd"),
              'hawkular-metrics.keystore.alias' => Base64.strict_encode64('hawkular-metrics'),
              'hawkular-metrics.htpasswd.file' => encode_file("#{FOLDER}/hawkular-metrics.htpasswd"),
              'hawkular-metrics.jgroups.keystore' => encode_file("#{FOLDER}/hawkular-jgroups.keystore"),
              'hawkular-metrics.jgroups.keystore.password' => encode_file("#{FOLDER}/hawkular-jgroups-keystore.pwd"),
              'hawkular-metrics.jgroups.alias' => Base64.strict_encode64('hawkular')
            }
          }
        }
      end

      template 'Generate hawkular-metrics-certificate secret template' do
        path "#{FOLDER}/templates/hawkular_metrics_certificate.yaml"
        source 'secret.yaml.erb'
        variables lazy {
          {
            name: 'hawkular-metrics-certificate',
            labels: { 'metrics-infra' => 'hawkular-metrics' },
            data: {
              'hawkular-metrics.certificate' => encode_file("#{FOLDER}/hawkular-metrics.crt"),
              'hawkular-metrics-ca.certificate' => encode_file("#{FOLDER}/ca.crt")
            }
          }
        }
      end

      template 'Generate hawkular-metrics-account secret template' do
        path "#{FOLDER}/templates/hawkular_metrics_account.yaml"
        source 'secret.yaml.erb'
        variables lazy {
          {
            name: 'hawkular-metrics-account',
            labels: { 'metrics-infra' => 'hawkular-metrics' },
            data: {
              'hawkular-metrics.username' => Base64.strict_encode64('hawkular'),
              'hawkular-metrics.password' => encode_file("#{FOLDER}/hawkular-metrics.pwd")
            }
          }
        }
      end

      template 'Generate cassandra secret template' do
        path "#{FOLDER}/templates/cassandra_secrets.yaml"
        source 'secret.yaml.erb'
        variables lazy {
          {
            name: 'hawkular-cassandra-secrets',
            labels: { 'metrics-infra' => 'hawkular-cassandra' },
            data: {
              'cassandra.keystore' => encode_file("#{FOLDER}/hawkular-cassandra.keystore"),
              'cassandra.keystore.password' => encode_file("#{FOLDER}/hawkular-cassandra-keystore.pwd"),
              'cassandra.keystore.alias' => Base64.strict_encode64('hawkular-cassandra'),
              'cassandra.truststore' => encode_file("#{FOLDER}/hawkular-cassandra.truststore"),
              'cassandra.truststore.password' => encode_file("#{FOLDER}/hawkular-cassandra-truststore.pwd"),
              'cassandra.pem' => encode_file("#{FOLDER}/hawkular-cassandra.pem")
            }
          }
        }
      end

      template 'Generate cassandra-certificate secret template' do
        path "#{FOLDER}/templates/cassandra_certificate.yaml"
        source 'secret.yaml.erb'
        variables lazy {
          {
            name: 'hawkular-cassandra-certificate',
            labels: { 'metrics-infra' => 'hawkular-cassandra' },
            data: {
              'cassandra.certificate' => encode_file("#{FOLDER}/hawkular-cassandra.crt"),
              'cassandra-ca.certificate' => encode_file("#{FOLDER}/hawkular-cassandra.pem")
            }
          }
        }
      end

      template 'Generate heapster secret template' do
        path "#{FOLDER}/templates/heapster_secrets.yaml"
        source 'secret.yaml.erb'
        variables lazy {
          {
            name: 'heapster-secrets',
            labels: { 'metrics-infra' => 'heapster' },
            data: {
              'heapster.cert' => encode_file("#{FOLDER}/heapster.crt"),
              'heapster.key' => encode_file("#{FOLDER}/heapster.key"),
              'heapster.client-ca' => encode_file("#{node['cookbook-openshift3']['openshift_master_config_dir']}/ca-bundle.crt"),
              'heapster.allowed-users' => Base64.strict_encode64((node['cookbook-openshift3']['openshift_metrics_heapster_allowed_users']).to_s)
            }
          }
        }
      end
    else
      template 'Generate hawkular-metrics-certs secret template' do
        path "#{FOLDER}/templates/hawkular_metrics-certs_secrets.yaml"
        source 'secret.yaml.erb'
        variables lazy {
          {
            name: 'hawkular-metrics-certs',
            labels: { 'metrics-infra' => 'hawkular-metrics-certs' },
            annotations: ['service.alpha.openshift.io/originating-service-name: hawkular-metrics'],
            data: {
              'tls.crt' => encode_file("#{FOLDER}/hawkular-metrics.crt"),
              'tls.key' => encode_file("#{FOLDER}/hawkular-metrics.key"),
              'tls.truststore.crt' => encode_file("#{FOLDER}/hawkular-cassandra.crt"),
              'ca.crt' => encode_file("#{FOLDER}/ca.crt")
            }
          }
        }
      end

      template 'Generate hawkular-metrics-account secret template' do
        path "#{FOLDER}/templates/hawkular_metrics_account.yaml"
        source 'secret.yaml.erb'
        variables lazy {
          {
            name: 'hawkular-metrics-account',
            labels: { 'metrics-infra' => 'hawkular-metrics' },
            data: {
              'hawkular-metrics.username' => Base64.strict_encode64('hawkular'),
              'hawkular-metrics.htpasswd' => encode_file("#{FOLDER}/hawkular-metrics.htpasswd"),
              'hawkular-metrics.password' => encode_file("#{FOLDER}/hawkular-metrics.pwd")
            }
          }
        }
      end

      template 'Generate cassandra-certificate secret template' do
        path "#{FOLDER}/templates/hawkular-cassandra-certs.yaml"
        source 'secret.yaml.erb'
        variables lazy {
          {
            name: 'hawkular-cassandra-certs',
            labels: { 'metrics-infra' => 'hawkular-cassandra-certs' },
            annotations: ['service.alpha.openshift.io/originating-service-name: hawkular-cassandra'],
            data: {
              'tls.crt' => encode_file("#{FOLDER}/hawkular-cassandra.crt"),
              'tls.key' => encode_file("#{FOLDER}/hawkular-cassandra.key"),
              'tls.peer.truststore.crt' => encode_file("#{FOLDER}/hawkular-cassandra.crt"),
              'tls.client.truststore.crt' => encode_file("#{FOLDER}/hawkular-metrics.crt")
            }
          }
        }
      end

      template 'Generate heapster secret template' do
        path "#{FOLDER}/templates/heapster_secrets.yaml"
        source 'secret.yaml.erb'
        variables lazy {
          {
            name: 'heapster-secrets',
            labels: { 'metrics-infra' => 'heapster' },
            data: {
              'heapster.allowed-users' => Base64.strict_encode64((node['cookbook-openshift3']['openshift_metrics_heapster_allowed_users']).to_s)
            }
          }
        }
      end
    end

    [{ 'name' => 'hawkular', 'labels' => { 'metrics-infra' => 'support' }, 'secrets' => ['hawkular-metrics-secrets'] }, { 'name' => 'cassandra', 'labels' => { 'metrics-infra' => 'support' }, 'secrets' => ['hawkular-cassandra-secrets'] }, { 'name' => 'heapster', 'labels' => { 'metrics-infra' => 'support' }, 'secrets' => ['heapster-secrets', 'hawkular-metrics-certificate', 'hawkular-metrics-account'] }].each do |sa|
      template "Generating serviceaccounts for #{sa['name']}" do
        path "#{FOLDER}/templates/metrics-#{sa['name']}-sa.yaml"
        source 'serviceaccount.yaml.erb'
        variables(sa: sa)
      end
    end

    [{ 'name' => 'hawkular-metrics', 'labels' => { 'metrics-infra' => 'hawkular-metrics', 'name' => 'hawkular-metrics' }, 'selector' => { 'name' => 'hawkular-metrics' }, 'ports' => [{ 'port' => 443, 'targetPort' => 'https-endpoint' }] }, { 'name' => 'hawkular-cassandra', 'labels' => { 'metrics-infra' => 'hawkular-cassandra', 'name' => 'hawkular-cassandra' }, 'selector' => { 'type' => 'hawkular-cassandra' }, 'ports' => [{ 'name' => 'cql-port', 'port' => 9042, 'targetPort' => 'cql-port' }, { 'name' => 'thrift-port', 'port' => 9160, 'targetPort' => 'thrift-port' }, { 'name' => 'tcp-port', 'port' => 7000, 'targetPort' => 'tcp-port' }, { 'name' => 'ssl-port', 'port' => 7001, 'targetPort' => 'ssl-port' }] }, { 'name' => 'hawkular-cassandra-nodes', 'labels' => { 'metrics-infra' => 'hawkular-cassandra-nodes', 'name' => 'hawkular-cassandra-nodes' }, 'selector' => { 'type' => 'hawkular-cassandra-nodes' }, 'ports' => [{ 'name' => 'cql-port', 'port' => 9042, 'targetPort' => 'cql-port' }, { 'name' => 'thrift-port', 'port' => 9160, 'targetPort' => 'thrift-port' }, { 'name' => 'tcp-port', 'port' => 7000, 'targetPort' => 'tcp-port' }, { 'name' => 'ssl-port', 'port' => 7001, 'targetPort' => 'ssl-port' }], 'headless' => true }, { 'name' => 'heapster', 'labels' => { 'metrics-infra' => 'heapster', 'name' => 'heapster' }, 'selector' => { 'name' => 'heapster' }, 'annotations' => ['service.alpha.openshift.io/serving-cert-secret-name: heapster-certs'], 'ports' => [{ 'port' => 80, 'targetPort' => 'http-endpoint' }] }].each do |svc|
      template "Generating serviceaccounts for #{svc['name']}" do
        path "#{FOLDER}/templates/metrics-#{svc['name']}-svc.yaml"
        source 'service.yaml.erb'
        variables(svc: svc)
      end
    end

    [{ 'name' => 'hawkular-view', 'labels' => { 'metrics-infra' => 'hawkular' }, 'rolerefs' => { 'name' => 'view' }, 'subjects' => [{ 'kind' => 'ServiceAccount', 'name' => 'hawkular', 'namespace' => node['cookbook-openshift3']['openshift_metrics_project'] }] }, { 'name' => 'hawkular-namespace-watcher', 'labels' => { 'metrics-infra' => 'hawkular' }, 'rolerefs' => { 'name' => 'hawkular-metrics', 'kind' => 'ClusterRole' }, 'subjects' => [{ 'kind' => 'ServiceAccount', 'name' => 'hawkular', 'namespace' => node['cookbook-openshift3']['openshift_metrics_project'] }], 'cluster' => true }, { 'name' => 'heapster-cluster-reader', 'labels' => { 'metrics-infra' => 'heapster' }, 'rolerefs' => { 'name' => 'cluster-reader', 'kind' => 'ClusterRole' }, 'subjects' => [{ 'kind' => 'ServiceAccount', 'name' => 'heapster', 'namespace' => node['cookbook-openshift3']['openshift_metrics_project'] }], 'cluster' => true }].each do |role|
      template "Generate view role binding for the #{role['name']} service account" do
        path "#{FOLDER}/templates/#{role['name']}-rolebinding.yaml"
        source 'rolebinding.yaml.erb'
        variables(role: role)
      end
    end

    cookbook_file "#{FOLDER}/templates/hawkular-cluster-role.yaml" do
      source 'hawkular_metrics_role.yaml'
    end

    ruby_block 'Send route' do
      block do
        [{ 'metadata' => { 'name' => 'hawkular-metrics', 'labels' => { 'metrics-infra' => 'hawkular-metrics' } }, 'spec' => { 'host' => node['cookbook-openshift3']['openshift_metrics_hawkular_hostname'], 'to' => { 'kind' => 'Service', 'name' => 'hawkular-metrics' }, 'tls' => { 'termination' => 'reencrypt', 'destinationCACertificate' => ::File.read("#{FOLDER}/ca.crt") } } }].each do |route|
          generate_route(route)
        end
      end
    end

    template 'Generate heapster replication controller' do
      path "#{FOLDER}/templates/metrics-heapster-rc.yaml"
      source 'heapster.yaml.erb'
      variables(ose_major_version: ose_major_version)
    end

    template 'Generate hawkular-metrics replication controller' do
      path "#{FOLDER}/templates/hawkular_metrics_rc.yaml"
      source 'hawkular_metrics_rc.yaml.erb'
      variables(
        ose_major_version: ose_major_version,
        random_word: random_password
      )
    end

    template 'Generate cassandra replication controller' do
      path "#{FOLDER}/templates/hawkular-cassandra-rc1.yaml"
      source 'hawkular_cassandra_rc.yaml.erb'
      variables(ose_major_version: ose_major_version)
    end

    [{ 'name' => node['cookbook-openshift3']['openshift_metrics_cassandra_pvc_prefix'], 'labels' => { 'metrics-infra' => 'hawkular-cassandra' }, 'annotations' => { 'volume.alpha.kubernetes.io/storage-class' => 'dynamic' }, 'access_modes' => node['cookbook-openshift3']['openshift_metrics_cassandra_pvc_access'] }].each do |pvc|
      template 'Generate hawkular-cassandra persistent volume claims (dynamic)' do
        path "#{FOLDER}/templates/cassandra-#{pvc['name']}-pvc.yaml"
        source 'pvc.yaml.erb'
        variables(pvc: pvc)
        only_if { node['cookbook-openshift3']['openshift_metrics_cassandra_storage_type'] =~ /dynamic/i }
      end
    end

    [{ 'name' => node['cookbook-openshift3']['openshift_metrics_cassandra_pvc_prefix'], 'labels' => { 'metrics-infra' => 'hawkular-cassandra' }, 'access_modes' => node['cookbook-openshift3']['openshift_metrics_cassandra_pvc_access'] }].each do |pvc|
      template 'Generate hawkular-cassandra persistent volume claims' do
        path "#{FOLDER}/templates/cassandra-#{pvc['name']}-pvc.yaml"
        source 'pvc.yaml.erb'
        variables(pvc: pvc)
        not_if { node['cookbook-openshift3']['openshift_metrics_cassandra_storage_type'] =~ /dynamic/i || node['cookbook-openshift3']['openshift_metrics_cassandra_storage_type'] =~ /emptydir/i }
      end
    end

    execute 'Applying template files' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} apply -f \
              #{FOLDER}/templates \
              --config=#{FOLDER}/admin.kubeconfig \
              --namespace=#{node['cookbook-openshift3']['openshift_metrics_project']}"
    end

    execute 'Scaling down cluster to recognize changes' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} get rc -l metrics-infra -o name \
              --config=#{FOLDER}/admin.kubeconfig \
              --namespace=#{node['cookbook-openshift3']['openshift_metrics_project']} | \
              xargs --no-run-if-empty #{node['cookbook-openshift3']['openshift_common_client_binary']} scale \
              --replicas=0 --namespace=#{node['cookbook-openshift3']['openshift_metrics_project']}"
    end

    execute 'Scaling up cluster' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} get rc -l metrics-infra -o name \
              --config=#{FOLDER}/admin.kubeconfig \
              --namespace=#{node['cookbook-openshift3']['openshift_metrics_project']} | \
              xargs --no-run-if-empty #{node['cookbook-openshift3']['openshift_common_client_binary']} scale \
              --replicas=1 --namespace=#{node['cookbook-openshift3']['openshift_metrics_project']}"
    end

    directory FOLDER.to_s do
      recursive true
      action :delete
    end
  end
end
