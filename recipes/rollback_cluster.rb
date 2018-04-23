#
# Cookbook Name:: cookbook-openshift3
# Recipe:: rollback_cluster
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = helper = OpenShiftHelper::NodeHelper.new(node)
first_etcd = server_info.first_etcd
is_etcd_server = server_info.on_etcd_server?
# is_master_server = server_info.on_master_server?
# is_node_server = server_info.on_node_server?
is_first_etcd = server_info.on_first_etcd?
certificate_server = server_info.certificate_server
is_certificate_server = server_info.on_certificate_server?
etcd_servers = server_info.etcd_servers

return unless ::File.file?(node['cookbook-openshift3']['control_rollback_flag'])

# if is_master_server || is_node_server
#   %w(excluder docker-excluder).each do |pkg|
#     execute "Disable #{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} (Best effort < 3.5)" do
#       command "#{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} enable"
#       only_if "rpm -q #{node['cookbook-openshift3']['openshift_service_type']}-#{pkg}"
#     end
#   end
# end

if is_etcd_server
  return if ::File.file?("#{node['cookbook-openshift3']['etcd_data_dir']}/.rollback#{node['cookbook-openshift3']['control_upgrade_version']}")
end

if is_first_etcd
  execute 'Check cluster health' do
    command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://`hostname`:2379 cluster-health | grep -w 'cluster is healthy'"
    notifies :run, 'execute[Starting ETCD rolling back]', :immediately
  end

  execute 'Starting ETCD rolling back' do
    command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://`hostname`:2379 set /rollback/etcd pre"
  end
end

# if is_master_server
#   log 'Stop services on MASTERS' do
#     level :info
#     notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master]", :immediately unless node['cookbook-openshift3']['openshift_HA']
#     notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-api]", :immediately if node['cookbook-openshift3']['openshift_HA']
#     notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers]", :immediately if node['cookbook-openshift3']['openshift_HA']
#   end
# end
#
# if is_node_server
#   log 'Stop services on NODES' do
#     level :info
#     notifies :stop, 'service[Restart Node]', :immediately
#   end
# end
#
# if is_master_server || is_node_server
#   execute 'Downgrade pkgs' do
#     command "yum -y downgrade #{node['cookbook-openshift3']['openshift_service_type']}-#{node['cookbook-openshift3']['ose_version']} #{node['cookbook-openshift3']['openshift_service_type']}-clients-#{node['cookbook-openshift3']['ose_version']} #{node['cookbook-openshift3']['openshift_service_type']}-master-#{node['cookbook-openshift3']['ose_version']} #{node['cookbook-openshift3']['openshift_service_type']}-node-#{node['cookbook-openshift3']['ose_version']} #{node['cookbook-openshift3']['openshift_service_type']}-sdn-ovs-#{node['cookbook-openshift3']['ose_version']} tuned-profiles-#{node['cookbook-openshift3']['openshift_service_type']}-node-#{node['cookbook-openshift3']['ose_version']}"
#   end
# end

if is_etcd_server
  execute 'Checking flag for rolling back (ETCD)' do
    command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://`hostname`:2379 get /rollback/etcd | grep -w pre"
    retries 30
    retry_delay 2
  end

  execute 'Generate etcd backup before rolling back' do
    command "etcdctl backup --data-dir=#{node['cookbook-openshift3']['etcd_data_dir']} --backup-dir=#{node['cookbook-openshift3']['etcd_data_dir']}-rollback-#{node['cookbook-openshift3']['control_upgrade_version']}"
  end

  execute 'Copy etcd v3 data store' do
    command "cp -a #{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db #{node['cookbook-openshift3']['etcd_data_dir']}-rollback-#{node['cookbook-openshift3']['control_upgrade_version']}/member/snap/"
  end

  log 'Stop services on ETCD' do
    level :info
    notifies :stop, 'service[etcd-service]', :immediately
  end

  ruby_block 'Deleting ETCD data' do
    block do
      helper.remove_dir("#{node['cookbook-openshift3']['etcd_data_dir']}/*")
    end
  end
end

if is_first_etcd
  ruby_block "Restore previous ETCD data to Version: pre-upgrade-#{node['cookbook-openshift3']['control_upgrade_version']}" do
    block do
      helper.backup_dir("#{node['cookbook-openshift3']['etcd_data_dir']}-pre-upgrade#{node['cookbook-openshift3']['control_upgrade_version']}/.", node['cookbook-openshift3']['etcd_data_dir'])
      helper.change_owner('etcd', 'etcd', node['cookbook-openshift3']['etcd_data_dir'])
    end
  end

  ruby_block 'Set ETCD_FORCE_NEW_CLUSTER=true on first etcd host' do
    block do
      f = Chef::Util::FileEdit.new("#{node['cookbook-openshift3']['etcd_conf_dir']}/etcd.conf")
      f.insert_line_if_no_match(/^ETCD_FORCE_NEW_CLUSTER/, 'ETCD_FORCE_NEW_CLUSTER=true')
      f.write_file
    end
    notifies :start, 'service[etcd-service]', :immediately
  end

  execute 'Check ETCD cluster health before doing anything' do
    command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://`hostname`:2379 cluster-health | grep -w 'cluster is healthy'"
    retries 30
    retry_delay 1
    notifies :run, 'ruby_block[Unset ETCD_FORCE_NEW_CLUSTER=true]', :immediately
  end

  ruby_block 'Unset ETCD_FORCE_NEW_CLUSTER=true' do
    block do
      f = Chef::Util::FileEdit.new("#{node['cookbook-openshift3']['etcd_conf_dir']}/etcd.conf")
      f.search_file_delete_line(/^ETCD_FORCE_NEW_CLUSTER/)
      f.write_file
    end
    action :nothing
    notifies :restart, 'service[etcd-service]', :immediately
  end

  execute 'Check ETCD cluster health before doing anything' do
    command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://`hostname`:2379 cluster-health | grep -w 'cluster is healthy'"
    retries 30
    retry_delay 1
  end

  execute 'Wait for 10 seconds when containerised' do
    command 'sleep 10'
    only_if { node['cookbook-openshift3']['deploy_containerized'] }
  end

  execute 'Set rollback ok' do
    command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://`hostname`:2379 set /rollback/etcd ok"
    only_if { etcd_servers.size == 1 }
  end

  execute 'Set rollback ready' do
    command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://`hostname`:2379 set /rollback/etcd ready"
    not_if { etcd_servers.size == 1 }
  end

  file "#{node['cookbook-openshift3']['etcd_data_dir']}/.rollback#{node['cookbook-openshift3']['control_upgrade_version']}" do
    action :create_if_missing
    only_if { etcd_servers.size == 1 }
  end
end

unless etcd_servers.size == 1
  if is_certificate_server

    directory node['cookbook-openshift3']['etcd_generated_migrated_dir'] do
      mode '0755'
      owner 'apache'
      group 'apache'
      recursive true
    end

    execute 'Check ETCD cluster readiness' do
      command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{first_etcd['fqdn']}/peer.crt --key-file #{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{first_etcd['fqdn']}/peer.key --ca-file #{node['cookbook-openshift3']['etcd_generated_ca_dir']}/ca.crt -C https://#{first_etcd['ipaddress']}:2379 get /rollback/etcd | grep -w ready"
      retries 120
      retry_delay 5
    end

    etcd_servers.reject { |etcdservers| etcdservers['fqdn'] == first_etcd['fqdn'] }.each do |etcd|
      execute "Add #{etcd['fqdn']} to the cluster" do
        command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{first_etcd['fqdn']}/peer.crt --key-file #{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{first_etcd['fqdn']}/peer.key --ca-file #{node['cookbook-openshift3']['etcd_generated_ca_dir']}/ca.crt -C https://#{first_etcd['ipaddress']}:2379 member add #{etcd['fqdn']} https://#{etcd['ipaddress']}:2380 | grep ^ETCD | tr --delete '\"' | sed 's/localhost/#{first_etcd['ipaddress']}/g' | tee #{node['cookbook-openshift3']['etcd_generated_migrated_dir']}/etcd-#{etcd['fqdn']}"
      end

      execute "Check #{etcd['fqdn']} has successfully registered" do
        command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{first_etcd['fqdn']}/peer.crt --key-file #{node['cookbook-openshift3']['etcd_generated_certs_dir']}/etcd-#{first_etcd['fqdn']}/peer.key --ca-file #{node['cookbook-openshift3']['etcd_generated_ca_dir']}/ca.crt -C https://#{first_etcd['ipaddress']}:2379 cluster-health | grep -w 'got healthy result from https://#{etcd['ipaddress']}:2379'"
        retries 120
        retry_delay 5
        notifies :run, 'execute[Wait for 10 seconds for cluster to sync]', :immediately unless etcd == etcd_servers.last
      end

      execute 'Wait for 10 seconds for cluster to sync' do
        command 'sleep 10'
        action :nothing
      end
    end
  end

  if is_etcd_server && !is_first_etcd
    execute 'Checking flag for rolling back Readiness (ETCD)' do
      command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://#{first_etcd['ipaddress']}:2379 get /rollback/etcd | grep -w ready"
      retries 30
      retry_delay 2
    end

    directory "/etc/systemd/system/#{node['cookbook-openshift3']['etcd_service_name']}.service.d" do
      action :create
    end

    template "/etc/systemd/system/#{node['cookbook-openshift3']['etcd_service_name']}.service.d/override.conf" do
      source 'etcd-override.conf.erb'
    end

    remote_file "Retrieve ETCD SystemD Drop-in from Certificate Server[#{certificate_server['fqdn']}]" do
      path "/etc/systemd/system/#{node['cookbook-openshift3']['etcd_service_name']}.service.d/etcd-dropin"
      source "http://#{certificate_server['ipaddress']}:#{node['cookbook-openshift3']['httpd_xfer_port']}/etcd/migration/etcd-#{node['fqdn']}"
      action :create_if_missing
      # notifies :run, 'execute[daemon-reload]', :immediately
      retries 120
      retry_delay 5
    end

    directory "#{node['cookbook-openshift3']['etcd_data_dir']}/member" do
      recursive true
      action :delete
      notifies :start, 'service[etcd-service]', :immediately
    end

    execute 'Check cluster health' do
      command "[[ $(/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://`hostname`:2379 cluster-health | grep -c 'got healthy') -eq #{etcd_servers.size} ]]"
      retries 120
      retry_delay 5
    end

    directory "/etc/systemd/system/#{node['cookbook-openshift3']['etcd_service_name']}.service.d" do
      recursive true
      action :delete
      notifies :run, 'execute[daemon-reload]', :immediately
      notifies :restart, 'service[etcd-service]', :immediately
    end

    execute 'Check cluster health' do
      command "[[ $(/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://`hostname`:2379 cluster-health | grep -c 'got healthy') -eq #{etcd_servers.size} ]]"
      retries 120
      retry_delay 5
    end

    file "#{node['cookbook-openshift3']['etcd_data_dir']}/.rollback#{node['cookbook-openshift3']['control_upgrade_version']}" do
      action :create_if_missing
    end
  end

  if is_first_etcd
    execute 'Set Rollback ok' do
      command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://`hostname`:2379 set /rollback/etcd ok"
      only_if "[[ $(/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://`hostname`:2379 cluster-health | grep -c 'got healthy') -eq #{etcd_servers.size} ]]"
    end

    file "#{node['cookbook-openshift3']['etcd_data_dir']}/.rollback#{node['cookbook-openshift3']['control_upgrade_version']}" do
      action :create_if_missing
    end
  end
end

%W(#{node['cookbook-openshift3']['control_upgrade_flag']} #{node['cookbook-openshift3']['control_rollback_flag']}).each do |flag|
  file flag do
    action :delete
  end
end

# include_recipe 'cookbook-openshift3::master'
# include_recipe 'cookbook-openshift3::node'
#
# if is_node_server
#   log 'Restart services on NODES' do
#     level :info
#     notifies :restart, 'service[Restart Node]', :immediately
#   end
#
#   log '(Nodes) Downgrade completed. Progressing with the CHEF run' do
#     level :info
#   end
# end
