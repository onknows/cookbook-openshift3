#
# Cookbook Name:: cookbook-openshift3
# Recipe:: adhoc_redeploy_etcd_ca
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

Chef::Log.error("The ETCD CA certificate redeploy will be skipped. Could not find the flag: #{node['cookbook-openshift3']['redeploy_etcd_ca_control_flag']}") unless ::File.file?(node['cookbook-openshift3']['redeploy_etcd_ca_control_flag'])

if ::File.file?(node['cookbook-openshift3']['redeploy_etcd_ca_control_flag'])

  server_info = OpenShiftHelper::NodeHelper.new(node)
  helper = OpenShiftHelper::NodeHelper.new(node)
  certificate_server = server_info.certificate_server
  is_certificate_server = server_info.on_certificate_server?
  is_etcd_server = server_info.on_etcd_server?

  if is_certificate_server
    if ::File.directory?(node['cookbook-openshift3']['etcd_ca_dir']) && !::File.exist?("#{node['cookbook-openshift3']['etcd_ca_dir']}/ca-bundle.crt")
      helper.backup_dir(node['cookbook-openshift3']['etcd_ca_dir'], "#{node['cookbook-openshift3']['etcd_ca_dir']}-#{Time.now.strftime('%Y-%m%d-%H%M')}")
      helper.remove_dir(node['cookbook-openshift3']['etcd_ca_dir'])
    end

    directory node['cookbook-openshift3']['etcd_ca_dir'] do
      owner 'root'
      group 'root'
      mode '0700'
      action :create
      recursive true
    end

    %w(certs crl fragments).each do |etcd_ca_sub_dir|
      directory "#{node['cookbook-openshift3']['etcd_ca_dir']}/#{etcd_ca_sub_dir}" do
        owner 'root'
        group 'root'
        mode '0700'
        action :create
        recursive true
      end
    end

    template node['cookbook-openshift3']['etcd_openssl_conf'] do
      source 'openssl.cnf.erb'
    end

    execute "ETCD Generate index.txt #{node['fqdn']}" do
      command 'touch index.txt'
      cwd node['cookbook-openshift3']['etcd_ca_dir']
      creates "#{node['cookbook-openshift3']['etcd_ca_dir']}/index.txt"
    end

    file "#{node['cookbook-openshift3']['etcd_ca_dir']}/serial" do
      content '01'
      action :create_if_missing
    end

    execute "ETCD Generate CA certificate for #{node['fqdn']}" do
      command "openssl req -config #{node['cookbook-openshift3']['etcd_openssl_conf']} -newkey rsa:4096 -keyout ca.key -new -out ca.crt -x509 -extensions etcd_v3_ca_self -batch -nodes -days #{node['cookbook-openshift3']['etcd_default_days']} -subj /CN=etcd-signer@$(date +%s)"
      environment 'SAN' => ''
      cwd node['cookbook-openshift3']['etcd_ca_dir']
      creates "#{node['cookbook-openshift3']['etcd_ca_dir']}/ca.crt"
    end

    ruby_block 'Create ETCD CA Bundle' do
      block do
        helper.bundle_etcd_ca(["#{node['cookbook-openshift3']['etcd_ca_dir']}/ca.crt", '/var/www/html/etcd/ca.crt'], "#{node['cookbook-openshift3']['etcd_ca_dir']}/ca-bundle.crt")
      end
      not_if { ::File.exist?("#{node['cookbook-openshift3']['etcd_ca_dir']}/ca-bundle.crt") }
    end

    %w(ca ca-bundle).each do |etcd_ca|
      remote_file "/var/www/html/etcd/#{etcd_ca}.crt" do
        source "file://#{node['cookbook-openshift3']['etcd_ca_dir']}/ca-bundle.crt"
        owner 'apache'
        group 'apache'
        mode '0644'
        sensitive true
      end
    end
  end

  if is_etcd_server
    remote_file "#{node['cookbook-openshift3']['etcd_conf_dir']}/ca.crt" do
      source "http://#{certificate_server['ipaddress']}:#{node['cookbook-openshift3']['httpd_xfer_port']}/etcd/ca-bundle.crt"
      sensitive true
      retries 15
      retry_delay 2
      notifies :run, 'execute[Check cluster health with new CA bundle]', :immediately
    end

    file node['cookbook-openshift3']['etcd_ca_cert'] do
      owner 'etcd'
      group 'etcd'
      mode '0600'
    end

    execute 'Fix ETCD directory permissions' do
      command "chmod 755 #{node['cookbook-openshift3']['etcd_conf_dir']}"
      only_if "[[ $(stat -c %a #{node['cookbook-openshift3']['etcd_conf_dir']}) -ne 755 ]]"
    end

    execute 'Check cluster health with new CA bundle' do
      command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://`hostname`:2379 member list"
      notifies :restart, 'service[etcd-service]', :immediately
      ignore_failure true
      action :nothing
    end
  end
end
