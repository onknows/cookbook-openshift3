#
# Cookbook Name:: cookbook-openshift3
# Recipe:: adhoc_migrate_etcd
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

node.force_override['cookbook-openshift3']['upgrade'] = true
node.force_override['cookbook-openshift3']['ose_major_version'] = '3.6'
node.force_override['cookbook-openshift3']['ose_version'] = '3.6.1-1.0.008f2d5'
node.force_override['cookbook-openshift3']['openshift_docker_image_version'] = 'v3.6.1'

server_info = OpenShiftHelper::NodeHelper.new(node)
first_etcd = server_info.first_etcd
is_etcd_server = server_info.on_etcd_server?
is_master_server = server_info.on_master_server?
is_first_master = server_info.on_first_master?
is_first_etcd = server_info.on_first_etcd?

include_recipe 'cookbook-openshift3'

Dir["#{Chef::Config[:file_cache_path]}/etcd_migration*"].each do |path|
  file ::File.expand_path(path) do
    action :delete
  end
end

if is_first_etcd
  log 'Check if there is at least one v2 snapshot [Abort if not found]' do
    level :info
  end

  return unless Dir["#{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/*.snap"].any?

  execute 'Check if there are any v3 data [Abort if at least one v3 key]' do
    command "[[ $(ETCDCTL_API=3 /usr/bin/etcdctl --cert #{node['cookbook-openshift3']['etcd_peer_file']} --key #{node['cookbook-openshift3']['etcd_peer_key']} --cacert #{node['cookbook-openshift3']['etcd_ca_cert']} --endpoints https://`hostname`:2379 get '.' --from-key --keys-only -w simple | wc -l) -gt 1 ]] && exit 1 || true"
  end

  execute 'Check cluster health' do
    command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['etcd_peer_file']} --key-file #{node['cookbook-openshift3']['etcd_peer_key']} --ca-file #{node['cookbook-openshift3']['etcd_ca_cert']} -C https://`hostname`:2379 cluster-health | grep -w 'cluster is healthy'"
  end
end

if is_master_server
  log 'Stop services on MASTERS' do
    level :info
    notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master]", :immediately unless node['cookbook-openshift3']['openshift_HA']
    notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-api]", :immediately if node['cookbook-openshift3']['openshift_HA']
    notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers]", :immediately if node['cookbook-openshift3']['openshift_HA']
  end
end

if is_etcd_server
  execute 'Generate etcd backup before migration' do
    command "etcdctl backup --data-dir=#{node['cookbook-openshift3']['etcd_data_dir']} --backup-dir=#{node['cookbook-openshift3']['etcd_data_dir']}-pre-migration-v3"
    not_if { ::File.directory?("#{node['cookbook-openshift3']['etcd_data_dir']}-pre-migration-v3") }
    notifies :run, 'execute[Copy etcd v3 data store]', :immediately
  end

  execute 'Copy etcd v3 data store' do
    command "cp -a #{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db #{node['cookbook-openshift3']['etcd_data_dir']}-pre-migration-v3/member/snap/"
    only_if { ::File.file?("#{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db") }
    action :nothing
  end

  log 'Stop services on ETCD' do
    level :info
    notifies :stop, 'service[etcd-service]', :immediately
  end
end

if is_first_etcd
  execute 'Migrate etcd data' do
    command "ETCDCTL_API=3 /usr/bin/etcdctl migrate --data-dir=#{node['cookbook-openshift3']['etcd_data_dir']} > #{Chef::Config[:file_cache_path]}/etcd_migration1"
  end

  execute 'Check the etcd v2 data are correctly migrated' do
    command "cat #{Chef::Config[:file_cache_path]}/etcd_migration1 | grep 'finished transforming keys' && touch #{Chef::Config[:file_cache_path]}/etcd_migration2"
    only_if { ::File.exist?("#{Chef::Config[:file_cache_path]}/etcd_migration1") }
  end

  ruby_block 'Set ETCD_FORCE_NEW_CLUSTER=true on first etcd host' do
    block do
      f = Chef::Util::FileEdit.new("#{node['cookbook-openshift3']['etcd_conf_dir']}/etcd.conf")
      f.insert_line_if_no_match(/^ETCD_FORCE_NEW_CLUSTER/, 'ETCD_FORCE_NEW_CLUSTER=true')
      f.write_file
    end
    notifies :start, 'service[etcd-service]', :immediately
    only_if { ::File.exist?("#{Chef::Config[:file_cache_path]}/etcd_migration2") }
  end

  ruby_block 'Unset ETCD_FORCE_NEW_CLUSTER=true on first etcd host' do
    block do
      f = Chef::Util::FileEdit.new("#{node['cookbook-openshift3']['etcd_conf_dir']}/etcd.conf")
      f.search_file_delete_line(/^ETCD_FORCE_NEW_CLUSTER/)
      f.write_file
    end
    notifies :restart, 'service[etcd-service]', :immediately
    only_if { ::File.exist?("#{Chef::Config[:file_cache_path]}/etcd_migration2") }
  end
end

if is_first_master
  bash 'Add TTLs on the first master' do
    code <<-EOH
      ETCDCTL_API=3 #{node['cookbook-openshift3']['openshift_common_admin_binary']} migrate etcd-ttl --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig --cert #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.crt --key #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.key --cacert #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-ca.crt --etcd-address https://#{first_etcd['ipaddress']}:2379 --ttl-keys-prefix /kubernetes.io/events --lease-duration 1h

      ETCDCTL_API=3 #{node['cookbook-openshift3']['openshift_common_admin_binary']} migrate etcd-ttl --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig --cert #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.crt --key #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.key --cacert #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-ca.crt --etcd-address https://#{first_etcd['ipaddress']}:2379 --ttl-keys-prefix /kubernetes.io/masterleases --lease-duration 10s

      ETCDCTL_API=3 #{node['cookbook-openshift3']['openshift_common_admin_binary']} migrate etcd-ttl --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig --cert #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.crt --key #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.key --cacert #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-ca.crt --etcd-address https://#{first_etcd['ipaddress']}:2379 --ttl-keys-prefix /openshift.io/oauth/accesstokens --lease-duration 86400s

      ETCDCTL_API=3 #{node['cookbook-openshift3']['openshift_common_admin_binary']} migrate etcd-ttl --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig --cert #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.crt --key #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.key --cacert #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-ca.crt --etcd-address https://#{first_etcd['ipaddress']}:2379 --ttl-keys-prefix /openshift.io/oauth/authorizetokens --lease-duration 500s

      ETCDCTL_API=3 #{node['cookbook-openshift3']['openshift_common_admin_binary']} migrate etcd-ttl --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig --cert #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.crt --key #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.key --cacert #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-ca.crt --etcd-address https://#{first_etcd['ipaddress']}:2379 --ttl-keys-prefix /openshift.io/leases/controllers --lease-duration 30s
    EOH
  end
end

if is_master_server
  config_options = YAML.load_file("#{node['cookbook-openshift3']['openshift_common_master_dir']}/master/master-config.yaml")
  config_options['kubernetesMasterConfig']['apiServerArguments'].store('storage-backend', %w(etcd3))
  config_options['kubernetesMasterConfig']['apiServerArguments'].store('storage-media-type', %w(application/vnd.kubernetes.protobuf))

  file "#{node['cookbook-openshift3']['openshift_common_master_dir']}/master/master-config.yaml" do
    content config_options.to_yaml
    notifies :write, 'log[Start services on MASTERS]', :immediately
  end

  log 'Start services on MASTERS' do
    level :info
    action :nothing
    notifies :start, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master]", :immediately unless node['cookbook-openshift3']['openshift_HA']
    notifies :start, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-api]", :immediately if node['cookbook-openshift3']['openshift_HA']
    notifies :start, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers]", :immediately if node['cookbook-openshift3']['openshift_HA']
  end
end
