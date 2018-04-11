#
# Cookbook Name:: cookbook-openshift3
# Recipe:: adhoc_redeploy_etcd_ca
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

Chef::Log.warn("The ETCD CA certificate redeploy will be skipped on Certificate Server. Could not find the flag: #{node['cookbook-openshift3']['redeploy_etcd_ca_control_flag']}") unless ::File.file?(node['cookbook-openshift3']['redeploy_etcd_ca_control_flag'])

if ::File.file?(node['cookbook-openshift3']['redeploy_etcd_ca_control_flag'])
  if node['cookbook-openshift3']['encrypted_file_password']['data_bag_name'] && node['cookbook-openshift3']['encrypted_file_password']['data_bag_item_name']
    secret_file = node['cookbook-openshift3']['encrypted_file_password']['secret_file'] || nil
    encrypted_file_password = data_bag_item(node['cookbook-openshift3']['encrypted_file_password']['data_bag_name'], node['cookbook-openshift3']['encrypted_file_password']['data_bag_item_name'], secret_file)
  else
    encrypted_file_password = node['cookbook-openshift3']['encrypted_file_password']['default']
  end

  server_info = helper = OpenShiftHelper::NodeHelper.new(node)
  etcd_servers = server_info.etcd_servers
  master_servers = server_info.master_servers
  is_certificate_server = server_info.on_certificate_server?

  if is_certificate_server
    ruby_block 'Backup CA for ETCD' do
      block do
        helper.backup_dir(node['cookbook-openshift3']['etcd_ca_dir'], "#{node['cookbook-openshift3']['etcd_ca_dir']}-#{Time.now.strftime('%Y-%m%d')}")
        helper.remove_dir(node['cookbook-openshift3']['etcd_ca_dir'])
      end
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
        helper.bundle_etcd_ca(["#{node['cookbook-openshift3']['etcd_ca_dir']}/ca.crt", "#{node['cookbook-openshift3']['etcd_ca_dir']}-#{Time.now.strftime('%Y-%m%d')}/ca.crt"], "#{node['cookbook-openshift3']['etcd_ca_dir']}/ca-bundle.crt")
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

    etcd_servers.each do |etcd_master|
      ruby_block "Remove old certs for #{etcd_master['fqdn']}" do
        block do
          helper.remove_dir("#{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']}*")
        end
      end

      directory "#{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']}" do
        mode '0755'
        owner 'apache'
        group 'apache'
      end

      %w(server peer).each do |etcd_certificates|
        execute "ETCD Create the #{etcd_certificates} csr for #{etcd_master['fqdn']}" do
          command "openssl req -new -keyout #{etcd_certificates}.key -config #{node['cookbook-openshift3']['etcd_openssl_conf']} -out #{etcd_certificates}.csr -reqexts #{node['cookbook-openshift3']['etcd_req_ext']} -batch -nodes -subj /CN=#{etcd_master['fqdn']}"
          environment 'SAN' => "IP:#{etcd_master['ipaddress']}"
          cwd "#{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']}"
          creates "#{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']}/#{etcd_certificates}.csr"
        end

        execute "ETCD Sign and create the #{etcd_certificates} crt for #{etcd_master['fqdn']}" do
          command "openssl ca -name #{node['cookbook-openshift3']['etcd_ca_name']} -config #{node['cookbook-openshift3']['etcd_openssl_conf']} -out #{etcd_certificates}.crt -in #{etcd_certificates}.csr -extensions #{node['cookbook-openshift3']["etcd_ca_exts_#{etcd_certificates}"]} -batch"
          environment 'SAN' => ''
          cwd "#{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']}"
          creates "#{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']}/#{etcd_certificates}.crt"
        end
      end

      execute "Create a tarball of the etcd certs for #{etcd_master['fqdn']}" do
        command "tar czvf #{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']}.tgz -C #{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']} . && chown apache: #{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']}.tgz"
        creates "#{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']}.tgz"
      end

      execute "Encrypt etcd certificate tgz files for #{etcd_master['fqdn']}" do
        command "openssl enc -aes-256-cbc -in #{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']}.tgz -out #{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']}.tgz.enc -k '#{encrypted_file_password}' && chown apache:apache #{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']}.tgz.enc"
        creates "#{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{etcd_master['fqdn']}.tgz.enc"
      end
    end

    master_servers.each do |master_server|
      ruby_block "Remove old certs for #{master_server['fqdn']}" do
        block do
          helper.remove_dir("#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}*")
        end
      end

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
        command "tar czvf #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}.tgz -C #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']} . && chown apache:apache #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}.tgz"
        creates "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}.tgz"
      end

      execute "Encrypt etcd tgz files for #{master_server['fqdn']}" do
        command "openssl enc -aes-256-cbc -in #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}.tgz  -out #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}.tgz.enc -k '#{encrypted_file_password}' && chown apache:apache #{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}.tgz.enc"
        creates "#{node['cookbook-openshift3']['master_generated_certs_dir']}/openshift-master-#{master_server['fqdn']}.tgz.enc"
      end
    end

    file node['cookbook-openshift3']['redeploy_etcd_ca_control_flag'] do
      action :delete
    end
  end
end
