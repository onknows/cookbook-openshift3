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
def random_password(length = 10)
  CHARS.sort_by { rand }.join[0...length]
end

action :create do
  ose_major_version = node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'] : node['cookbook-openshift3']['ose_major_version']

  directory "#{Chef::Config['file_cache_path']}/hosted_metric/templates" do
    recursive true
  end

  cookbook_file "#{Chef::Config['file_cache_path']}/hosted_metric/import_jks_certs.sh" do
    source 'import_jks_certs.sh'
    mode '0755'
  end

  remote_file "#{Chef::Config['file_cache_path']}/hosted_metric/admin.kubeconfig" do
    source "file://#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig"
  end

  package 'java-1.8.0-openjdk-headless'

  execute 'Generate ca certificate chain' do
    command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} ca create-signer-cert \
            --config=#{Chef::Config['file_cache_path']}/hosted_metric/admin.kubeconfig \
            --key=#{Chef::Config['file_cache_path']}/hosted_metric/ca.key \
            --cert=#{Chef::Config['file_cache_path']}/hosted_metric/ca.crt \
            --serial=#{Chef::Config['file_cache_path']}/hosted_metric/ca.serial.txt \
            --name=metrics-signer@$(date +%s)"
  end

  %w(hawkular-metrics hawkular-cassandra).each do |component|
    execute "Generate #{component} keys" do
      command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} ca create-server-cert \
              --config=#{Chef::Config['file_cache_path']}/hosted_metric/admin.kubeconfig \
              --key=#{Chef::Config['file_cache_path']}/hosted_metric/#{component}.key \
              --cert=#{Chef::Config['file_cache_path']}/hosted_metric/#{component}.crt \
              --hostnames=#{component} \
              --signer-key=#{Chef::Config['file_cache_path']}/hosted_metric/ca.key \
              --signer-cert=#{Chef::Config['file_cache_path']}/hosted_metric/ca.crt \
              --signer-serial=#{Chef::Config['file_cache_path']}/hosted_metric/ca.serial.txt"
    end

    execute "Generate #{component} certificate" do
      command "cat #{Chef::Config['file_cache_path']}/hosted_metric/#{component}.key #{Chef::Config['file_cache_path']}/hosted_metric/#{component}.crt > #{Chef::Config['file_cache_path']}/hosted_metric/#{component}.pem"
    end

    file "Generate random password for the #{component} keystore" do
      path "#{Chef::Config['file_cache_path']}/hosted_metric/#{component}-keystore.pwd"
      content random_password
    end

    execute "Create the #{component} pkcs12 from the pem file" do
      command "openssl pkcs12 -export -in #{Chef::Config['file_cache_path']}/hosted_metric/#{component}.pem \
              -out #{Chef::Config['file_cache_path']}/hosted_metric/#{component}.pkcs12 \
              -name #{component} -noiter -nomaciter \
              -password pass:$(cat #{Chef::Config['file_cache_path']}/hosted_metric/#{component}-keystore.pwd)"
    end

    file "Generate random password for #{component} truststore" do
      path "#{Chef::Config['file_cache_path']}/hosted_metric/#{component}-truststore.pwd"
      content random_password
    end
  end

  %w(hawkular-metrics hawkular-jgroups-keystore).each do |component|
    file "Generate random password for the #{component} truststore" do
      path "#{Chef::Config['file_cache_path']}/hosted_metric/#{component}.pwd"
      content random_password
    end
  end

  execute 'Generate htpasswd file for hawkular metrics' do
    command "htpasswd -b -c #{Chef::Config['file_cache_path']}/hosted_metric/hawkular-metrics.htpasswd hawkular $(cat #{Chef::Config['file_cache_path']}/hosted_metric/hawkular-metrics.pwd)"
  end

  execute 'Generate JKS certs' do
    command "#{Chef::Config['file_cache_path']}/hosted_metric/import_jks_certs.sh"
    environment lazy {
      {
        CERT_DIR: "#{Chef::Config['file_cache_path']}/hosted_metric",
        METRICS_KEYSTORE_PASSWD: ::File.read("#{Chef::Config['file_cache_path']}/hosted_metric/hawkular-metrics-keystore.pwd"),
        CASSANDRA_KEYSTORE_PASSWD: ::File.read("#{Chef::Config['file_cache_path']}/hosted_metric/hawkular-cassandra-keystore.pwd"),
        METRICS_TRUSTSTORE_PASSWD: ::File.read("#{Chef::Config['file_cache_path']}/hosted_metric/hawkular-metrics-truststore.pwd"),
        CASSANDRA_TRUSTSTORE_PASSWD: ::File.read("#{Chef::Config['file_cache_path']}/hosted_metric/hawkular-cassandra-truststore.pwd"),
        JGROUPS_PASSWD: ::File.read("#{Chef::Config['file_cache_path']}/hosted_metric/hawkular-jgroups-keystore.pwd"),
      }
    }
  end

  secret_file = %w(ca.crt hawkular-metrics.crt hawkular-metrics.keystore hawkular-metrics-keystore.pwd hawkular-metrics.truststore hawkular-metrics-truststore.pwd hawkular-metrics.pwd hawkular-metrics.htpasswd hawkular-jgroups.keystore hawkular-jgroups-keystore.pwd hawkular-cassandra.crt hawkular-cassandra.pem hawkular-cassandra.keystore hawkular-cassandra-keystore.pwd hawkular-cassandra.truststore hawkular-cassandra-truststore.pwd)
  secret_hash = Hash[secret_file.collect { |item| [item, `base64 --wrap 0 #{Chef::Config['file_cache_path']}/hosted_metric/#{item}`] }]

  template 'Generate hawkular-metrics-secrets secret template' do
    path "#{Chef::Config['file_cache_path']}/hosted_metric/templates/hawkular_metrics_secrets.yaml"
    source 'secret.yaml.erb'
    variables(
      :name => 'hawkular-metrics-secrets',
      :labels => { 'metrics-infra': 'hawkular-metrics' },
      :data => { 
        'hawkular-metrics.keystore': secret_hash['hawkular-metrics.keystore'],
        'hawkular-metrics.keystore.password': secret_hash['hawkular-metrics-keystore.pwd'],
        'hawkular-metrics.truststore': secret_hash['hawkular-metrics.truststore'],
        'hawkular-metrics.truststore.password': secret_hash['hawkular-metrics-truststore.pwd'],
        'hawkular-metrics.keystore.alias': `echo -n hawkular-metrics | base64`,
        'hawkular-metrics.htpasswd.file': secret_hash['hawkular-metrics.htpasswd'],
        'hawkular-metrics.jgroups.keystore': secret_hash['hawkular-jgroups.keystore'],
        'hawkular-metrics.jgroups.keystore.password': secret_hash['hawkular-jgroups-keystore.pwd'],
        'hawkular-metrics.jgroups.alias': `echo -n hawkular | base64`,
      }
    )
  end

  template 'Generate hawkular-metrics-certificate secret template' do
    path "#{Chef::Config['file_cache_path']}/hosted_metric/templates/hawkular_metrics_certificate.yaml"
    source 'secret.yaml.erb'
    variables(
      :name => 'hawkular-metrics-certificate',
      :labels => { 'metrics-infra': 'hawkular-metrics' },
      :data => { 
        'hawkular-metrics.certificate': secret_hash['hawkular-metrics.crt'],
        'hawkular-metrics-ca.certificate': secret_hash['ca.crt'],
      }
    )
  end

  template 'Generate hawkular-metrics-account secret template' do
    path "#{Chef::Config['file_cache_path']}/hosted_metric/templates/hawkular_metrics_account.yaml"
    source 'secret.yaml.erb'
    variables(
      :name => 'hawkular-metrics-account',
      :labels => { 'metrics-infra': 'hawkular-metrics' },
      :data => { 
        'hawkular-metrics.username': `echo -n hawkular | base64`,
        'hawkular-metrics.password': secret_hash['hawkular-metrics.pwd'],
      }
    )
  end

  template 'Generate cassandra secret template' do
    path "#{Chef::Config['file_cache_path']}/hosted_metric/templates/cassandra_secrets.yaml"
    source 'secret.yaml.erb'
    variables(
      :name => 'hawkular-cassandra-secrets',
      :labels => { 'metrics-infra': 'hawkular-cassandra' },
      :data => { 
        'cassandra.keystore': secret_hash['hawkular-cassandra.keystore'],
        'cassandra.keystore.password': secret_hash['hawkular-cassandra-keystore.pwd'],
        'cassandra.keystore.alias': `echo -n hawkular-cassandra | base64`,
        'cassandra.truststore': secret_hash['hawkular-cassandra.truststore'],
        'cassandra.truststore.password': secret_hash['hawkular-cassandra-truststore.pwd'],
        'cassandra.pem': secret_hash['hawkular-cassandra.pem'],
      }
    )
  end

  template 'Generate cassandra-certificate secret template' do
    path "#{Chef::Config['file_cache_path']}/hosted_metric/templates/cassandra_certificate.yaml"
    source 'secret.yaml.erb'
    variables(
      :name => 'hawkular-cassandra-certificate',
      :labels => { 'metrics-infra': 'hawkular-cassandra' },
      :data => {
        'cassandra.certificate': secret_hash['hawkular-cassandra.crt'],
        'cassandra-ca.certificate': secret_hash['hawkular-cassandra.pem'],
      }
    )
  end
  new_resource.updated_by_last_action(true)
end
