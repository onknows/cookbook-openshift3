#
# Cookbook Name:: is_apaas_openshift_cookbook
# Recipe:: adhoc_redeploy_cluster_ca
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

Chef::Log.warn("The CLUSTER CA CERTS redeploy will be skipped on Certificate Server. Could not find the flag: #{node['is_apaas_openshift_cookbook']['redeploy_cluster_ca_certserver_control_flag']}") unless ::File.file?(node['is_apaas_openshift_cookbook']['redeploy_cluster_ca_certserver_control_flag'])

if ::File.file?(node['is_apaas_openshift_cookbook']['redeploy_cluster_ca_certserver_control_flag'])

  server_info = helper = OpenShiftHelper::NodeHelper.new(node)
  master_servers = server_info.master_servers
  node_servers = server_info.node_servers
  is_certificate_server = server_info.on_certificate_server?

  if is_certificate_server
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

    directory "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}-legacy-ca" do
      action :delete
      recursive true
    end

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

    %w(ca.crt ca.key ca.serial.txt ca-bundle.crt openshift-master.crt openshift-master.key openshift-master.kubeconfig).each do |remove_file_ca|
      file "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/#{remove_file_ca}" do
        action :delete
      end
    end

    node['is_apaas_openshift_cookbook']['openshift_master_renew_certs'].each do |remove_master_certificate|
      file "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/#{remove_master_certificate}" do
        action :delete
      end
    end

    ruby_block 'Copy ca-bundle if it is not there master_certs_generated_certs_dir' do
      block do
        require 'fileutils'
        FileUtils.cp("#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}-legacy-ca/ca.crt", "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}-legacy-ca/ca-bundle.crt")
      end
      only_if { !::File.file?("#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}-legacy-ca/ca-bundle.crt") }
    end

    ruby_block 'Update ca.crt with ca.bundle' do
      block do
        require 'fileutils'
        FileUtils.cp("#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}-legacy-ca/ca-bundle.crt", "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}-legacy-ca/ca.crt")
      end
      not_if { FileUtils.compare_file("#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}-legacy-ca/ca-bundle.crt", "#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}-legacy-ca/ca.crt") }
    end

    master_servers.each do |master_server|
      ruby_block "Remove old certs for #{master_server['fqdn']}" do
        block do
          helper.remove_dir("#{node['is_apaas_openshift_cookbook']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}.tgz*")
        end
      end

      %w(master.server.crt master.server.key).each do |remove_master_cert|
        file "#{node['is_apaas_openshift_cookbook']['master_generated_certs_dir']}/openshift-#{master_server['fqdn']}/#{remove_master_cert}" do
          action :delete
        end
      end
    end

    include_recipe 'is_apaas_openshift_cookbook::master_cluster_ca'
    include_recipe 'is_apaas_openshift_cookbook::master_cluster_certificates'

    directory '(NEW-CA) Create temp directory for updating nodes config' do
      path "#{Chef::Config[:file_cache_path]}/certificates_nodes"
      recursive true
    end

    node_servers.each do |node_server|
      ruby_block "(NEW-CA) Remove old certs for #{node_server['fqdn']}" do
        block do
          helper.remove_dir("#{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tgz*")
        end
      end

      execute "(NEW-CA) Extract certificates for #{node_server['fqdn']}" do
        command "gunzip #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar.gz"
      end

      execute "(NEW-CA) Extract KUBECONFIG certificates for #{node_server['fqdn']}" do
        command "tar --wildcards -xf #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar '*kubeconfig*'"
        creates "#{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar.gz"
        cwd "#{Chef::Config[:file_cache_path]}/certificates_nodes"
      end

      bash "(NEW-CA) Update CA with CA-BUNDLE for #{node_server['fqdn']}" do
        code <<-BASH
	  tar --${ACTION} --wildcards -f #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar '*ca.crt'
          tar --${ACTION} --wildcards -f #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar '*kubeconfig*'
          tar --update --transform s/ca-bundle.crt/ca.crt/ -f #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar ./ca-bundle.crt
        BASH
        cwd node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']
        environment 'ACTION' => 'delete'
      end

      ruby_block "(NEW-CA) Update the KUBECONFIG certificates for #{node_server['fqdn']}" do
        block do
          kubeconfig = YAML.load_file("#{Chef::Config[:file_cache_path]}/certificates_nodes/system:node:#{node_server['fqdn']}.kubeconfig")
          kubeconfig['clusters'][0]['cluster']['certificate-authority-data'] = Base64.encode64(::File.read("#{node['is_apaas_openshift_cookbook']['master_certs_generated_certs_dir']}/ca-bundle.crt")).delete("\n")
          open("#{Chef::Config[:file_cache_path]}/certificates_nodes/system:node:#{node_server['fqdn']}.kubeconfig", 'w') { |f| f << kubeconfig.to_yaml }
        end
      end

      execute "(NEW-CA) Add KUBECONFIG for #{node_server['fqdn']}" do
        command "tar --update -f #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar ./system:node:#{node_server['fqdn']}.kubeconfig"
        creates "#{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar.gz"
        cwd "#{Chef::Config[:file_cache_path]}/certificates_nodes"
        creates "#{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar.gz"
      end

      execute "(NEW-CA) Recreate certificates for #{node_server['fqdn']}" do
        command "gzip #{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar"
        creates "#{node['is_apaas_openshift_cookbook']['openshift_node_generated_configs_dir']}/#{node_server['fqdn']}.tar.gz"
      end
    end

    directory '(NEW-CA) Delete temp directory for updating nodes config' do
      path "#{Chef::Config[:file_cache_path]}/certificates_nodes"
      recursive true
      action :delete
    end

    file node['is_apaas_openshift_cookbook']['redeploy_cluster_ca_certserver_control_flag'] do
      action :delete
    end
  end
end
