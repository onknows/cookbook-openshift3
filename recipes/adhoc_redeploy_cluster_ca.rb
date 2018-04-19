#
# Cookbook Name:: is_apaas_openshift_cookbook
# Recipe:: adhoc_redeploy_cluster_ca
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

Chef::Log.warn("The CLUSTER CA CERTS redeploy will be skipped on Certificate Server. Could not find the flag: #{node['is_apaas_openshift_cookbook']['redeploy_cluster_ca_certserver_control_flag']}") unless ::File.file?(node['is_apaas_openshift_cookbook']['redeploy_cluster_ca_certserver_control_flag'])

if ::File.file?(node['is_apaas_openshift_cookbook']['redeploy_cluster_ca_certserver_control_flag'])

  server_info = helper = OpenShiftHelper::NodeHelper.new(node)
  first_master = server_info.first_master
  master_servers = server_info.master_servers
  node_servers = server_info.node_servers
  is_certificate_server = server_info.on_certificate_server?

  ose_major_version = node['is_apaas_openshift_cookbook']['deploy_containerized'] == true ? node['is_apaas_openshift_cookbook']['openshift_docker_image_version'] : node['is_apaas_openshift_cookbook']['ose_major_version']

  if is_certificate_server
    directory "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}-legacy-ca" do
      mode '0755'
      owner 'apache'
      group 'apache'
      recursive true
    end

    %w(ca.crt ca.key ca.serial.txt ca-bundle.crt).each do |legacy|
      remote_file "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}-legacy-ca/#{legacy}" do
        source "file://#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/#{legacy}"
        only_if { ::File.file?("#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/#{legacy}") }
        sensitive true
      end
    end

    %w(ca.crt ca.key ca.serial.txt ca-bundle.crt).each do |remove_file_ca|
      file "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/#{remove_file_ca}" do
        action :delete
      end
    end

    if node['is_apaas_openshift_cookbook']['openshift_master_ca_certificate']['data_bag_name'] && node['is_apaas_openshift_cookbook']['openshift_master_ca_certificate']['data_bag_item_name']
      secret_file = node['is_apaas_openshift_cookbook']['openshift_master_ca_certificate']['secret_file'] || nil
      ca_vars = data_bag_item(node['is_apaas_openshift_cookbook']['openshift_master_ca_certificate']['data_bag_name'], node['is_apaas_openshift_cookbook']['openshift_master_ca_certificate']['data_bag_item_name'], secret_file)

      file "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/ca.key" do
        content Base64.decode64(ca_vars['key_base64'])
        mode '0600'
        action :create_if_missing
      end

      file "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/ca.crt" do
        content Base64.decode64(ca_vars['cert_base64'])
        mode '0644'
        action :create_if_missing
      end
    end

    file "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/ca.serial.txt" do
      action :create_if_missing
      mode '0644'
      notifies :create, 'file[Initialise Master CA Serial]', :immediately
    end

    file 'Initialise Master CA Serial' do
      path "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/ca.serial.txt"
      content '00'
      action :nothing
    end

    execute "Create the master certificates for #{first_master['fqdn']}" do
      command "#{node['is_apaas_openshift_cookbook']['openshift_common_admin_binary']} ca create-master-certs \
              --hostnames=#{(node['is_apaas_openshift_cookbook']['erb_corsAllowedOrigins'] + [first_master['ipaddress'], first_master['fqdn'], node['is_apaas_openshift_cookbook']['openshift_common_api_hostname']]).uniq.join(',')} \
  	          --certificate-authority #{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}-legacy-ca/ca.crt \
              --master=#{node['is_apaas_openshift_cookbook']['openshift_master_api_url']} \
              --public-master=#{node['is_apaas_openshift_cookbook']['openshift_master_public_api_url']} \
              --cert-dir=#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']} ${validty_certs} --overwrite=false"
      environment 'validty_certs' => ose_major_version.split('.')[1].to_i < 5 ? '' : "--expire-days=#{node['is_apaas_openshift_cookbook']['openshift_master_cert_expire_days']} --signer-expire-days=#{node['is_apaas_openshift_cookbook']['openshift_ca_cert_expire_days']}"
      creates "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/ca.crt"
    end

    execute 'Create temp directory for loopback master client config' do
      command "mkdir -p #{Chef::Config[:file_cache_path]}/openshift_ca_loopback_tmpdir"
      not_if "grep \'#{node['is_apaas_openshift_cookbook']['openshift_master_loopback_context_name']}\' #{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/openshift-master.kubeconfig"
      notifies :run, "execute[Generate the loopback master client config for #{first_master['fqdn']}]", :immediately
    end

    execute "Generate the loopback master client config for #{first_master['fqdn']}" do
      command "#{node['is_apaas_openshift_cookbook']['openshift_common_admin_binary']} create-api-client-config \
              --certificate-authority=#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/ca.crt \
              --master=#{node['is_apaas_openshift_cookbook']['openshift_master_loopback_api_url']} \
              --public-master=#{node['is_apaas_openshift_cookbook']['openshift_master_loopback_api_url']} \
              --client-dir=#{Chef::Config[:file_cache_path]}/openshift_ca_loopback_tmpdir \
              --groups=system:masters,system:openshift-master \
              --signer-cert=#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/ca.crt \
              --signer-key=#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/ca.key \
              --signer-serial=#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/ca.serial.txt \
              --user=system:openshift-master --basename=openshift-master ${validty_certs}"
      environment 'validty_certs' => ose_major_version.split('.')[1].to_i < 5 ? '' : "--expire-days=#{node['is_apaas_openshift_cookbook']['openshift_master_cert_expire_days']}"
      action :nothing
    end

    %w(openshift-master.crt openshift-master.key openshift-master.kubeconfig).each do |loopback_master_client|
      remote_file "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/#{loopback_master_client}" do
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
      ruby_block "Remove old certs for #{master_server['fqdn']}" do
        block do
          helper.remove_dir("#{node['is_apaas_openshift_cookbook']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}.tgz*")
        end
      end

      directory "#{node['is_apaas_openshift_cookbook']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}" do
        recursive true
        action :delete
      end
    end

    directory 'Create temp directory for updating nodes config' do
      path "#{Chef::Config[:file_cache_path]}/certificates_nodes"
      recursive true
    end

    node_servers.each do |node_server|
      ruby_block "Remove old certs for #{node_server['fqdn']}" do
        block do
          helper.remove_dir("#{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tgz*")
        end
      end

      execute "Extract certificates for #{node_server['fqdn']}" do
        command "gunzip #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar.gz"
      end

      execute "Extract KUBECONFIG certificates for #{node_server['fqdn']}" do
        command "tar --wildcards -xf #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar '*kubeconfig*'"
        creates "#{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar.gz"
        cwd "#{Chef::Config[:file_cache_path]}/certificates_nodes"
      end

      bash "Update CA with CA-BUNDLE for #{node_server['fqdn']}" do
        code <<-BASH
	  tar --${ACTION} --wildcards -f #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar '*ca.crt'
          tar --${ACTION} --wildcards -f #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar '*kubeconfig*'
          tar --update --transform s/ca-bundle.crt/ca.crt/ -f #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar ./ca-bundle.crt
        BASH
        cwd node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']
        environment 'ACTION' => 'delete'
      end

      ruby_block "Update the KUBECONFIG certificates for #{node_server['fqdn']}" do
        block do
          kubeconfig = YAML.load_file("#{Chef::Config[:file_cache_path]}/certificates_nodes/system:node:#{node_server['fqdn']}.kubeconfig")
          kubeconfig['clusters'][0]['cluster']['certificate-authority-data'] = Base64.encode64(::File.read("#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/ca-bundle.crt")).delete("\n")
          open("#{Chef::Config[:file_cache_path]}/certificates_nodes/system:node:#{node_server['fqdn']}.kubeconfig", 'w') { |f| f << kubeconfig.to_yaml }
        end
      end

      execute "Add KUBECONFIG for #{node_server['fqdn']}" do
        command "tar --update -f #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar ./system:node:#{node_server['fqdn']}.kubeconfig"
        creates "#{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar.gz"
        cwd "#{Chef::Config[:file_cache_path]}/certificates_nodes"
        creates "#{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar.gz"
      end

      execute "Recreate certificates for #{node_server['fqdn']}" do
        command "gzip #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar"
        creates "#{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar.gz"
      end
    end

    directory 'Delete temp directory for updating nodes config' do
      path "#{Chef::Config[:file_cache_path]}/certificates_nodes"
      recursive true
      action :delete
    end

    include_recipe 'is_apaas_openshift_cookbook::master_cluster_certificates'

    file node['is_apaas_openshift_cookbook']['redeploy_cluster_ca_certserver_control_flag'] do
      action :delete
    end
  end
end
