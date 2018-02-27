#
# Cookbook Name:: cookbook-openshift3
# Recipe:: wire_aggregator
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = OpenShiftHelper::NodeHelper.new(node)
first_master = server_info.first_master
master_servers = server_info.master_servers
certificate_server = server_info.certificate_server
is_certificate_server = server_info.on_certificate_server?

if is_certificate_server
  directory "#{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters" do
    mode '0755'
    owner 'apache'
    group 'apache'
  end

  execute 'Creating Master Aggregator signer certs' do
    command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} adm ca create-signer-cert \
            --cert=#{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters/front-proxy-ca.crt \
            --key=#{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters/front-proxy-ca.key \
            --serial=#{node['cookbook-openshift3']['openshift_master_config_dir']}/ca.serial.txt"
    creates "#{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters/front-proxy-ca.crt"
  end

  # create-api-client-config generates a ca.crt file which will
  # overwrite the OpenShift CA certificate.  
  # Generate the aggregator kubeconfig and delete the ca.crt before creating archive for masters
  
  execute 'Create Master api-client config for Aggregator' do
    command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} adm ca create-api-client-config \
            --certificate-authority=#{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters/front-proxy-ca.crt \
            --signer-cert=#{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters/front-proxy-ca.crt \
            --signer-key=#{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters/front-proxy-ca.key \
            --user aggregator-front-proxy \
            --client-dir=#{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters \
            --signer-serial=#{node['cookbook-openshift3']['openshift_master_config_dir']}/ca.serial.txt"
    creates "#{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters/aggregator-front-proxy.kubeconfig"
  end
  
  file "#{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters/ca.crt" do
    action :delete
    only_if { File.exist? "#{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters/ca.crt" }
  end

  %w(aggregator-front-proxy.crt aggregator-front-proxy.key aggregator-front-proxy.kubeconfig).each do |aggregator_file|
    remote_file "#{node['cookbook-openshift3']['openshift_master_config_dir']}/#{aggregator_file}" do
      source "file://#{Chef::Config[:file_cache_path]}/certtemp/#{aggregator_file}"
      not_if { ::File.file?("#{node['cookbook-openshift3']['openshift_master_config_dir']}/#{aggregator_file}") }
    end
  end

  execute 'Create a tarball of the aggregator certs' do
    command "tar czvf #{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters.tgz -C #{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters . "
    creates "#{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters.tgz"
  end

  execute 'Encrypt master master tgz files' do
    command "openssl enc -aes-256-cbc -in #{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters.tgz  -out #{node['cookbook-openshift3']['master_generated_certs_dir']}/wire_aggregator-masters.tgz.enc -k '#{encrypted_file_password}' && chmod -R  0755 #{node['cookbook-openshift3']['master_generated_certs_dir']} && chown -R apache: #{node['cookbook-openshift3']['master_generated_certs_dir']}"
  end
end

unless is_certificate_server
  remote_file 'Retrieve the aggregator certs' do
    path "#{node['cookbook-openshift3']['openshift_master_config_dir']}/wire_aggregator-masters.tgz.enc"
    source "http://#{certificate_server['ipaddress']}:#{node['cookbook-openshift3']['httpd_xfer_port']}/master/generated_certs/wire_aggregator-masters.tgz.enc"
    action :create_if_missing
    notifies :run, 'execute[Un-encrypt aggregator tgz files]', :immediately
    notifies :run, 'execute[Extract aggregator to Master folder]', :immediately
    retries 12
    retry_delay 5
  end

  execute 'Un-encrypt aggregator tgz files' do
    command "openssl enc -d -aes-256-cbc -in wire_aggregator-masters.tgz.enc -out wire_aggregator-masters.tgz -k '#{encrypted_file_password}'"
    cwd node['cookbook-openshift3']['openshift_master_config_dir']
    action :nothing
  end

  execute 'Extract master aggregator to Master folder' do
    command "tar xzf wire_aggregator-masters.tgz"
    cwd node['cookbook-openshift3']['openshift_master_config_dir']
    action :nothing
  end
end

file "#{node['cookbook-openshift3']['openshift_master_config_dir']}/openshift-ansible-catalog-console.js" do
  content 'window.OPENSHIFT_CONSTANTS.TEMPLATE_SERVICE_BROKER_ENABLED=false'
  mode '0644'
  owner 'root'
  group 'root'
end
