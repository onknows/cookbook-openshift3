#
# Cookbook Name:: cookbook-openshift3
# Recipe:: upgrade_control_plane36
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

# This must be run before any upgrade takes place.
# It creates the service signer certs (and any others) if they were not in
# existence previously.

Chef::Log.error("Upgrade will be skipped. Could not find the flag: #{node['cookbook-openshift3']['control_upgrade_flag']}") unless ::File.file?(node['cookbook-openshift3']['control_upgrade_flag'])

if ::File.file?(node['cookbook-openshift3']['control_upgrade_flag'])

  node.force_override['cookbook-openshift3']['upgrade'] = true
  node.force_override['cookbook-openshift3']['ose_major_version'] = node['cookbook-openshift3']['upgrade_ose_major_version']
  node.force_override['cookbook-openshift3']['ose_version'] = node['cookbook-openshift3']['upgrade_ose_version']
  node.force_override['cookbook-openshift3']['openshift_docker_image_version'] = node['cookbook-openshift3']['upgrade_openshift_docker_image_version']
  node.force_override['yum']['main']['exclude'] = node['cookbook-openshift3']['custom_pkgs_excluder'] unless node['cookbook-openshift3']['custom_pkgs_excluder'].nil?

  server_info = OpenShiftHelper::NodeHelper.new(node)
  first_etcd = server_info.first_etcd
  is_etcd_server = server_info.on_etcd_server?
  is_master_server = server_info.on_master_server?
  is_node_server = server_info.on_node_server?
  is_first_master = server_info.on_first_master?

  if defined? node['cookbook-openshift3']['upgrade_repos']
    node.force_override['cookbook-openshift3']['yum_repositories'] = node['cookbook-openshift3']['upgrade_repos']
  end

  if is_master_server
    return unless ::Mixlib::ShellOut.new("/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.crt --key-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.key --ca-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-ca.crt -C https://#{first_etcd['ipaddress']}:2379 ls /migration/#{node['cookbook-openshift3']['control_upgrade_version']}/#{node['fqdn']}").run_command.error?
  end

  include_recipe 'yum::default'
  include_recipe 'cookbook-openshift3::packages'
  include_recipe 'cookbook-openshift3::disable_excluder'

  if is_etcd_server
    log 'Upgrade for ETCD [STARTED]' do
      level :info
    end

    include_recipe 'cookbook-openshift3::adhoc_backup_etcd'

    log 'Upgrade for ETCD [COMPLETED]' do
      level :info
    end

    file node['cookbook-openshift3']['control_upgrade_flag'] do
      action :delete
      only_if { is_etcd_server && !is_master_server }
    end
  end

  if is_master_server
    log 'Upgrade for MASTERS [STARTED]' do
      level :info
    end

    config_options = YAML.load_file("#{node['cookbook-openshift3']['openshift_common_master_dir']}/master/master-config.yaml")
    node.force_override['cookbook-openshift3']['etcd_migrated'] = false unless config_options['kubernetesMasterConfig']['apiServerArguments'].key?('storage-backend')

    include_recipe 'cookbook-openshift3::master'
    include_recipe 'cookbook-openshift3::excluder' unless is_node_server

    log 'Restart Master services' do
      level :info
      notifies :restart, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master]", :immediately unless node['cookbook-openshift3']['openshift_HA']
      notifies :restart, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-api]", :immediately if node['cookbook-openshift3']['openshift_HA']
      notifies :restart, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers]", :immediately if node['cookbook-openshift3']['openshift_HA']
    end

    execute "Set upgrade markup for master : #{node['fqdn']}" do
      command "/usr/bin/etcdctl --cert-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.crt --key-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-client.key --ca-file #{node['cookbook-openshift3']['openshift_master_config_dir']}/master.etcd-ca.crt -C https://#{first_etcd['ipaddress']}:2379 set /migration/#{node['cookbook-openshift3']['control_upgrade_version']}/#{node['fqdn']} ok"
    end

    log 'Upgrade for MASTERS [COMPLETED]' do
      level :info
    end
  end

  if is_first_master
    log 'Reconcile Cluster Roles & Cluster Role Bindings [STARTED]' do
      level :info
    end

    execute 'Wait for API to be ready' do
      command "[[ $(curl --silent #{node['cookbook-openshift3']['openshift_master_api_url']}/healthz/ready --cacert #{node['cookbook-openshift3']['openshift_master_config_dir']}/ca.crt --cacert #{node['cookbook-openshift3']['openshift_master_config_dir']}/ca-bundle.crt) =~ \"ok\" ]]"
      retries 120
      retry_delay 1
    end

    execute 'Reconcile Cluster Roles' do
      command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} \
              --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
              policy reconcile-cluster-roles --additive-only=true --confirm"
    end

    execute 'Reconcile Cluster Role Bindings' do
      command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} \
              --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
              policy reconcile-cluster-role-bindings \
              --exclude-groups=system:authenticated \
              --exclude-groups=system:authenticated:oauth \
              --exclude-groups=system:unauthenticated \
              --exclude-users=system:anonymous \
              --additive-only=true --confirm"
    end

    execute 'Reconcile Jenkins Pipeline Role Bindings' do
      command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} \
              --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
              policy reconcile-cluster-role-bindings system:build-strategy-jenkinspipeline --confirm"
    end

    execute 'Reconcile Security Context Constraints' do
      command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} \
              --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
              policy reconcile-sccs --confirm --additive-only=true"
    end

    execute 'Remove shared-resource-viewer protection before upgrade' do
      command "#{node['cookbook-openshift3']['openshift_common_client_binary']} \
              --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
              annotate role shared-resource-viewer openshift.io/reconcile-protect- -n openshift"
    end

    execute 'Migrate storage post policy reconciliation' do
      command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} \
              --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
              migrate storage --include=* --confirm"
    end

    log 'Reconcile Cluster Roles & Cluster Role Bindings [COMPLETED]' do
      level :info
    end

    include_recipe 'cookbook-openshift3::upgrade_managed_hosted'
  end
  include_recipe 'cookbook-openshift3::upgrade_node36' if is_node_server
end
