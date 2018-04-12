#
# Cookbook Name:: cookbook-openshift3
# Recipe:: etcd_cluster
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = helper = OpenShiftHelper::NodeHelper.new(node)
helper_certs = OpenShiftHelper::CertHelper.new
etcd_servers = server_info.etcd_servers
certificate_server = server_info.certificate_server
is_etcd_server = server_info.on_etcd_server?
is_master_server = server_info.on_master_server?

if node['cookbook-openshift3']['encrypted_file_password']['data_bag_name'] && node['cookbook-openshift3']['encrypted_file_password']['data_bag_item_name']
  secret_file = node['cookbook-openshift3']['encrypted_file_password']['secret_file'] || nil
  encrypted_file_password = data_bag_item(node['cookbook-openshift3']['encrypted_file_password']['data_bag_name'], node['cookbook-openshift3']['encrypted_file_password']['data_bag_item_name'], secret_file)
else
  encrypted_file_password = node['cookbook-openshift3']['encrypted_file_password']['default']
end

if is_etcd_server
  include_recipe 'cookbook-openshift3::etcd_packages'

  node['cookbook-openshift3']['enabled_firewall_rules_etcd'].each do |rule|
    iptables_rule rule do
      action :enable
    end
  end

  if node['cookbook-openshift3']['deploy_containerized']
    docker_image node['cookbook-openshift3']['openshift_docker_etcd_image'] do
      action :pull_if_missing
    end

    template "/etc/systemd/system/#{node['cookbook-openshift3']['etcd_service_name']}.service" do
      source 'service_etcd-containerized.service.erb'
      notifies :run, 'execute[daemon-reload]', :immediately
      notifies :restart, 'service[etcd-service]', :immediately if node['cookbook-openshift3']['upgrade']
    end

    systemd_unit 'etcd' do
      action :mask
    end
  end

  if node['cookbook-openshift3']['adhoc_redeploy_etcd_ca']
    Chef::Log.warn("The ETCD CA CERTS redeploy will be skipped for ETCD[#{node['fqdn']}]. Could not find the flag: #{node['cookbook-openshift3']['redeploy_etcd_certs_control_flag']}") unless ::File.file?(node['cookbook-openshift3']['redeploy_etcd_certs_control_flag'])

    ruby_block "Redeploy ETCD CA certs for #{node['fqdn']}" do
      block do
        helper.remove_dir("#{node['cookbook-openshift3']['etcd_conf_dir']}/ca.crt")
        helper.remove_dir("#{node['cookbook-openshift3']['etcd_conf_dir']}/etcd-#{node['fqdn']}.tgz*")
      end
      only_if { ::File.file?(node['cookbook-openshift3']['redeploy_etcd_certs_control_flag']) }
    end
  end

  remote_file "#{node['cookbook-openshift3']['etcd_conf_dir']}/ca.crt" do
    source "http://#{certificate_server['ipaddress']}:#{node['cookbook-openshift3']['httpd_xfer_port']}/etcd/ca.crt"
    retries 60
    retry_delay 5
    sensitive true
    action :create_if_missing
  end

  remote_file "Retrieve ETCD certificates from Certificate Server[#{certificate_server['fqdn']}]" do
    path "#{node['cookbook-openshift3']['etcd_conf_dir']}/etcd-#{node['fqdn']}.tgz.enc"
    source "http://#{certificate_server['ipaddress']}:#{node['cookbook-openshift3']['httpd_xfer_port']}/etcd/generated_certs/etcd-#{node['fqdn']}.tgz.enc"
    action :create_if_missing
    notifies :run, 'execute[Un-encrypt etcd certificate tgz files]', :immediately
    notifies :run, 'execute[Extract certificate to ETCD folder]', :immediately
    retries 60
    retry_delay 5
  end

  execute 'Un-encrypt etcd certificate tgz files' do
    command "openssl enc -d -aes-256-cbc -in etcd-#{node['fqdn']}.tgz.enc -out etcd-#{node['fqdn']}.tgz -k '#{encrypted_file_password}'"
    cwd node['cookbook-openshift3']['etcd_conf_dir']
    action :nothing
  end

  execute 'Extract certificate to ETCD folder' do
    command "tar xzf etcd-#{node['fqdn']}.tgz"
    cwd node['cookbook-openshift3']['etcd_conf_dir']
    action :nothing
  end

  file node['cookbook-openshift3']['etcd_ca_cert'] do
    owner 'etcd'
    group 'etcd'
    mode '0600'
  end

  %w(cert peer).each do |certificate_type|
    file node['cookbook-openshift3']['etcd_' + certificate_type + '_file'.to_s] do
      owner 'etcd'
      group 'etcd'
      mode '0600'
    end

    file node['cookbook-openshift3']['etcd_' + certificate_type + '_key'.to_s] do
      owner 'etcd'
      group 'etcd'
      mode '0600'
    end
  end

  execute 'Fix ETCD directory permissions' do
    command "chmod 755 #{node['cookbook-openshift3']['etcd_conf_dir']}"
    only_if "[[ $(stat -c %a #{node['cookbook-openshift3']['etcd_conf_dir']}) -ne 755 ]]"
  end

  template "#{node['cookbook-openshift3']['etcd_conf_dir']}/etcd.conf" do
    source 'etcd.conf.erb'
    notifies :restart, 'service[etcd-service]', :immediately
    notifies :enable, 'service[etcd-service]', :immediately
    variables(
      lazy do
        {
          etcd_servers: etcd_servers,
          initial_cluster_state: etcd_servers.find { |etcd_node| etcd_node['fqdn'] == node['fqdn'] }.key?('new_node') ? 'existing' : node['cookbook-openshift3']['etcd_initial_cluster_state']
        }
      end
    )
  end

  ruby_block 'Restart ETCD service if valid certificate (Upgrade ETCD CA)' do
    block do
    end
    notifies :restart, 'service[etcd-service]', :immediately if helper_certs.valid_certificate?(node['cookbook-openshift3']['etcd_ca_cert'], node['cookbook-openshift3']['etcd_cert_file'])
    notifies :delete, "file[#{node['cookbook-openshift3']['redeploy_etcd_certs_control_flag']}]", :immediately unless is_master_server
    only_if { helper_certs.valid_certificate?(node['cookbook-openshift3']['etcd_ca_cert'], node['cookbook-openshift3']['etcd_cert_file']) && ::File.file?(node['cookbook-openshift3']['redeploy_etcd_certs_control_flag']) }
  end

  file node['cookbook-openshift3']['redeploy_etcd_certs_control_flag'] do
    action :nothing
  end
end
