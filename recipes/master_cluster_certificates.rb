#
# Cookbook Name:: cookbook-openshift3
# Recipe:: master_cluster_certificates
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = OpenShiftHelper::NodeHelper.new(node)
first_master = server_info.first_master
master_servers = server_info.master_servers
is_certificate_server = server_info.on_certificate_server?

ose_major_version = node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'] : node['cookbook-openshift3']['ose_major_version']

if node['cookbook-openshift3']['encrypted_file_password']['data_bag_name'] && node['cookbook-openshift3']['encrypted_file_password']['data_bag_item_name']
  secret_file = node['cookbook-openshift3']['encrypted_file_password']['secret_file'] || nil
  encrypted_file_password = data_bag_item(node['cookbook-openshift3']['encrypted_file_password']['data_bag_name'], node['cookbook-openshift3']['encrypted_file_password']['data_bag_item_name'], secret_file)
else
  encrypted_file_password = node['cookbook-openshift3']['encrypted_file_password']['default']
end

if is_certificate_server
  %W(/var/www/html/master #{node['cookbook-openshift3']['master_generated_certs_dir']} #{node['cookbook-openshift3']['master_certs_generated_certs_dir']}).each do |path|
    directory path do
      mode '0755'
      owner 'apache'
      group 'apache'
      recursive true
    end
  end

  template "#{node['cookbook-openshift3']['master_generated_certs_dir']}/.htaccess" do
    owner 'apache'
    group 'apache'
    source 'access-htaccess.erb'
    notifies :run, 'ruby_block[Modify the AllowOverride options]', :immediately
    variables(servers: master_servers)
  end

  master_servers.each do |master_server|
    directory "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}" do
      mode '0755'
      owner 'apache'
      group 'apache'
    end

    execute "ETCD Create the CLIENT csr for #{master_server['fqdn']}" do
      command "openssl req -new -keyout #{node['cookbook-openshift3']['master_etcd_cert_prefix']}client.key -config #{node['cookbook-openshift3']['etcd_openssl_conf']} -out #{node['cookbook-openshift3']['master_etcd_cert_prefix']}client.csr -reqexts #{node['cookbook-openshift3']['etcd_req_ext']} -batch -nodes -subj /CN=#{master_server['fqdn']}"
      environment 'SAN' => "IP:#{master_server['ipaddress']}"
      cwd "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}"
      creates "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}/#{node['cookbook-openshift3']['master_etcd_cert_prefix']}client.csr"
    end

    execute "ETCD Sign and create the CLIENT crt for #{master_server['fqdn']}" do
      command "openssl ca -name #{node['cookbook-openshift3']['etcd_ca_name']} -config #{node['cookbook-openshift3']['etcd_openssl_conf']} -out #{node['cookbook-openshift3']['master_etcd_cert_prefix']}client.crt -in #{node['cookbook-openshift3']['master_etcd_cert_prefix']}client.csr -batch"
      environment 'SAN' => ''
      cwd "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}"
      creates "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}/#{node['cookbook-openshift3']['master_etcd_cert_prefix']}client.crt"
    end

    execute "Create a tarball of the etcd master certs for #{master_server['fqdn']}" do
      command "tar czvf #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}.tgz -C #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']} . && chown -R apache:apache #{node['cookbook-openshift3']['master_generated_certs_dir']}"
      creates "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}.tgz"
    end

    execute "Encrypt etcd tgz files for #{master_server['fqdn']}" do
      command "openssl enc -aes-256-cbc -in #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}.tgz  -out #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}.tgz.enc -k '#{encrypted_file_password}' && chmod -R  0755 #{node['cookbook-openshift3']['master_generated_certs_dir']} && chown -R apache: #{node['cookbook-openshift3']['master_generated_certs_dir']}"
      creates "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}.tgz.enc"
    end
  end

  if node['cookbook-openshift3']['openshift_master_ca_certificate']['data_bag_name'] && node['cookbook-openshift3']['openshift_master_ca_certificate']['data_bag_item_name']
    secret_file = node['cookbook-openshift3']['openshift_master_ca_certificate']['secret_file'] || nil
    ca_vars = data_bag_item(node['cookbook-openshift3']['openshift_master_ca_certificate']['data_bag_name'], node['cookbook-openshift3']['openshift_master_ca_certificate']['data_bag_item_name'], secret_file)

    file "#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.key" do
      content Base64.decode64(ca_vars['key_base64'])
      mode '0600'
      action :create_if_missing
    end

    file "#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.crt" do
      content Base64.decode64(ca_vars['cert_base64'])
      mode '0644'
      action :create_if_missing
    end

    file "#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.serial.txt" do
      action :create_if_missing
      mode '0644'
      notifies :create, 'file[Initialise Master CA Serial]', :immediately
    end

    file 'Initialise Master CA Serial' do
      path "#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.serial.txt"
      content '00'
      action :nothing
    end
  end

  execute "Create the master certificates for #{first_master['fqdn']}" do
    command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} ca create-master-certs \
            --hostnames=#{(node['cookbook-openshift3']['erb_corsAllowedOrigins'] + [first_master['ipaddress'], first_master['fqdn'], node['cookbook-openshift3']['openshift_common_api_hostname']]).uniq.join(',')} \
            --master=#{node['cookbook-openshift3']['openshift_master_api_url']} \
            --public-master=#{node['cookbook-openshift3']['openshift_master_public_api_url']} \
            --cert-dir=#{node['cookbook-openshift3']['master_certs_generated_certs_dir']} --overwrite=false"
    creates "#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/master.server.key"
  end

  execute 'Create temp directory for loopback master client config' do
    command "mkdir -p #{Chef::Config[:file_cache_path]}/openshift_ca_loopback_tmpdir"
    not_if "grep \'#{node['cookbook-openshift3']['openshift_master_loopback_context_name']}\' #{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/openshift-master.kubeconfig"
    notifies :run, "execute[Generate the loopback master client config for #{first_master['fqdn']}]", :immediately
  end

  execute "Generate the loopback master client config for #{first_master['fqdn']}" do
    command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} create-api-client-config \
            --certificate-authority=#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.crt \
            --master=#{node['cookbook-openshift3']['openshift_master_loopback_api_url']} \
            --public-master=#{node['cookbook-openshift3']['openshift_master_loopback_api_url']} \
            --client-dir=#{Chef::Config[:file_cache_path]}/openshift_ca_loopback_tmpdir \
            --groups=system:masters,system:openshift-master \
            --signer-cert=#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.crt \
            --signer-key=#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.key \
            --signer-serial=#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.serial.txt \
            --user=system:openshift-master --basename=openshift-master"
    action :nothing
  end

  %w(openshift-master.crt openshift-master.key openshift-master.kubeconfig).each do |loopback_master_client|
    remote_file "#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/#{loopback_master_client}" do
      source "file://#{Chef::Config[:file_cache_path]}/openshift_ca_loopback_tmpdir/#{loopback_master_client}"
      only_if { ::File.file?("#{Chef::Config[:file_cache_path]}/openshift_ca_loopback_tmpdir/#{loopback_master_client}") }
      sensitive true
    end
  end

  directory 'Delete temp directory for loopback master client config' do
    path "#{Chef::Config[:file_cache_path]}/openshift_ca_loopback_tmpdir"
    recursive true
    action :delete
  end

  master_servers.each do |master_server|
    directory "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}" do
      mode '0755'
      owner 'apache'
      group 'apache'
      recursive true
    end

    execute "Create the master server certificates for #{master_server['fqdn']}" do
      command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} ca create-server-cert \
              --hostnames=#{(node['cookbook-openshift3']['erb_corsAllowedOrigins'] + [master_server['ipaddress'], master_server['fqdn'], node['cookbook-openshift3']['openshift_common_api_hostname']]).uniq.join(',')} \
              --cert=#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}/master.server.crt \
              --key=#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}/master.server.key \
              --signer-cert=#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.crt \
              --signer-key=#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.key \
              --signer-serial=#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.serial.txt \
              --overwrite=false"
      creates "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}/master.server.crt"
    end

    execute "Generate master client configuration for #{master_server['fqdn']}" do
      command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} create-api-client-config \
              --certificate-authority=#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.crt \
              --master=https://#{master_server['fqdn']}:#{node['cookbook-openshift3']['openshift_master_api_port']} \
              --public-master=https://#{master_server['fqdn']}:#{node['cookbook-openshift3']['openshift_master_api_port']} \
              --client-dir=#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']} \
              --groups=system:masters,system:openshift-master \
              --signer-cert=#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.crt \
              --signer-key=#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.key \
              --signer-serial=#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/ca.serial.txt \
              --user=system:openshift-master --basename=openshift-master"
      creates "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}/openshift-master.kubeconfig"
    end

    certs = case ose_major_version.split('.')[1].to_i
            when 3..4
              node['cookbook-openshift3']['openshift_master_certs'] + %w(openshift-registry.crt openshift-registry.key openshift-registry.kubeconfig openshift-router.crt openshift-router.key openshift-router.kubeconfig service-signer.crt service-signer.key)
            when 5..7
              node['cookbook-openshift3']['openshift_master_certs'] + %w(service-signer.crt service-signer.key)
            else
              node['cookbook-openshift3']['openshift_master_certs']
            end

    certs.uniq.each do |master_certificate|
      remote_file "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}/#{master_certificate}" do
        source "file://#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/#{master_certificate}"
        only_if { ::File.file?("#{node['cookbook-openshift3']['master_certs_generated_certs_dir']}/#{master_certificate}") }
        sensitive true
      end
    end

    %w(client.crt client.key).each do |remove_etcd_certificate|
      file "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}/#{node['cookbook-openshift3']['master_etcd_cert_prefix']}#{remove_etcd_certificate}" do
        action :delete
      end
    end

    execute "Create a tarball of the master certs for #{master_server['fqdn']}" do
      command "tar czvf #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}.tgz -C #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']} . "
      creates "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}.tgz"
    end

    execute 'Encrypt master master tgz files' do
      command "openssl enc -aes-256-cbc -in #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}.tgz  -out #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}.tgz.enc -k '#{encrypted_file_password}' && chmod -R  0755 #{node['cookbook-openshift3']['master_generated_certs_dir']} && chown -R apache: #{node['cookbook-openshift3']['master_generated_certs_dir']}"
      creates "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}.tgz.enc"
    end
  end
end
