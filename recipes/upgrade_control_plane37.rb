#
# Cookbook Name:: cookbook-openshift3
# Recipe:: upgrade_control_plane37
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

# This must be run before any upgrade takes place.
# It creates the service signer certs (and any others) if they were not in
# existence previously.

node.force_override['cookbook-openshift3']['upgrade'] = true
node.force_override['cookbook-openshift3']['ose_major_version'] = '3.7'
node.force_override['cookbook-openshift3']['ose_version'] = '3.7.0-1.0.7ed6862'
node.force_override['cookbook-openshift3']['openshift_docker_image_version'] = 'v3.7.0'

hosted_upgrade_version = node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'] : 'v' + node['cookbook-openshift3']['ose_version'].to_s.split('-')[0]

server_info = OpenShiftHelper::NodeHelper.new(node)
is_etcd_server = server_info.on_etcd_server?
is_master_server = server_info.on_master_server?
is_first_master = server_info.on_first_master?

if is_first_master
  config_options = YAML.load_file("#{node['cookbook-openshift3']['openshift_common_master_dir']}/master/master-config.yaml")
  unless config_options['kubernetesMasterConfig']['apiServerArguments'].key?('storage-backend')
    Chef::Log.error('The cluster must be migrated to etcd v3 prior to upgrading to 3.7')
    node.run_state['issues_detected'] = true
  end
end

if defined? node['cookbook-openshift3']['upgrade_repos']
  node.force_override['cookbook-openshift3']['yum_repositories'] = node['cookbook-openshift3']['upgrade_repos']
end

if is_etcd_server
  log 'Upgrade for ETCD [STARTED]' do
    level :info
  end

  execute 'Generate etcd backup before upgrade' do
    command "etcdctl backup --data-dir=#{node['cookbook-openshift3']['etcd_data_dir']} --backup-dir=#{node['cookbook-openshift3']['etcd_data_dir']}-pre-upgrade37"
    not_if { ::File.directory?("#{node['cookbook-openshift3']['etcd_data_dir']}-pre-upgrade37") }
    notifies :run, 'execute[Copy etcd v3 data store (PRE)]', :immediately
  end

  execute 'Copy etcd v3 data store (PRE)' do
    command "cp -a #{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db #{node['cookbook-openshift3']['etcd_data_dir']}-pre-upgrade37/member/snap/"
    only_if { ::File.file?("#{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db") }
    action :nothing
  end

  include_recipe 'cookbook-openshift3'
  include_recipe 'cookbook-openshift3::common'
  include_recipe 'cookbook-openshift3::etcd_cluster'

  execute 'Generate etcd backup after upgrade' do
    command "etcdctl backup --data-dir=#{node['cookbook-openshift3']['etcd_data_dir']} --backup-dir=#{node['cookbook-openshift3']['etcd_data_dir']}-post-upgrade37"
    not_if { ::File.directory?("#{node['cookbook-openshift3']['etcd_data_dir']}-post-upgrade37") }
    notifies :run, 'execute[Copy etcd v3 data store (POST)]', :immediately
  end

  execute 'Copy etcd v3 data store (POST)' do
    command "cp -a #{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db #{node['cookbook-openshift3']['etcd_data_dir']}-post-upgrade37/member/snap/"
    only_if { ::File.file?("#{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db") }
    action :nothing
  end

  log 'Upgrade for ETCD [COMPLETED]' do
    level :info
  end
end

unless node.run_state['issues_detected']
  if is_master_server && is_first_master
    log 'Pre master upgrade - Upgrade all storage' do
      level :info
    end
  
    execute 'Migrate storage post policy reconciliation' do
      command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} \
              --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
              migrate storage --include=* --confirm"
    end
  end
  
  if is_master_server
    log 'Upgrade for MASTERS [STARTED]' do
      level :info
    end
  
    log 'Stop all master services prior to upgrade for 3.6 to 3.7 transition' do
      level :info
      notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master]", :immediately unless node['cookbook-openshift3']['openshift_HA']
      notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-api]", :immediately if node['cookbook-openshift3']['openshift_HA']
      notifies :stop, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers]", :immediately if node['cookbook-openshift3']['openshift_HA']
    end
  
    include_recipe 'cookbook-openshift3::certificate_server' if node['cookbook-openshift3']['deploy_containerized']
  
    if node['cookbook-openshift3']['openshift_HA']
      include_recipe 'cookbook-openshift3::master_cluster'
    else
      include_recipe 'cookbook-openshift3::master_standalone'
    end
  
    include_recipe 'cookbook-openshift3::node'
  
    log 'Restart Master & Node services' do
      level :info
      notifies :restart, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master]", :immediately unless node['cookbook-openshift3']['openshift_HA']
      notifies :restart, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-api]", :immediately if node['cookbook-openshift3']['openshift_HA']
      notifies :restart, "service[#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers]", :immediately if node['cookbook-openshift3']['openshift_HA']
      notifies :restart, "service[#{node['cookbook-openshift3']['openshift_service_type']}-node]", :immediately
      notifies :restart, 'service[openvswitch]', :immediately
      not_if { node['cookbook-openshift3']['deploy_containerized'] }
    end
  
    log 'Upgrade for MASTERS [COMPLETED]' do
      level :info
    end
  end
  
  if is_master_server && is_first_master
    execute 'Post master upgrade - Upgrade clusterpolicies storage' do
      command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} \
              --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
              migrate storage --include=clusterpolicies --confirm"
    end
  
    log 'Reconcile Cluster Roles & Cluster Role Bindings [STARTED]' do
      level :info
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
  
    log 'Update hosted deployment(s) to current version [STARTED]' do
      level :info
    end
  
    ruby_block 'Get current router image' do
      block do
        node.run_state['router_image'] = Mixlib::ShellOut.new("#{node['cookbook-openshift3']['openshift_common_client_binary']} get dc/router -n #{node['cookbook-openshift3']['openshift_hosted_router_namespace']} -o jsonpath='{.spec.template.spec.containers[0].image}'").run_command.stdout.strip
      end
      only_if do
        node['cookbook-openshift3']['openshift_hosted_manage_router']
      end
    end
  
    ruby_block 'Get current registry image' do
      block do
        node.run_state['registry_image'] = Mixlib::ShellOut.new("#{node['cookbook-openshift3']['openshift_common_client_binary']} get dc/docker-registry -n #{node['cookbook-openshift3']['openshift_hosted_registry_namespace']} -o jsonpath='{.spec.template.spec.containers[0].image}'").run_command.stdout.strip
      end
      only_if do
        node['cookbook-openshift3']['openshift_hosted_manage_registry']
      end
    end
  
    execute "Update router image to current version \"#{hosted_upgrade_version}\"" do
      command lazy {
        "#{node['cookbook-openshift3']['openshift_common_client_binary']} \
        --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
        patch dc/router -n #{node['cookbook-openshift3']['openshift_hosted_router_namespace']} -p \
        \'{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"router\",\"image\":\"#{node.run_state['router_image'].gsub(/:v.+/, ":#{hosted_upgrade_version}")}\",\"livenessProbe\":{\"tcpSocket\":null,\"httpGet\":{\"path\": \"/healthz\", \"port\": 1936, \"host\": \"localhost\", \"scheme\": \"HTTP\"},\"initialDelaySeconds\":10,\"timeoutSeconds\":1}}]}}}}'"
      }
      only_if do
        node['cookbook-openshift3']['openshift_hosted_manage_router']
      end
    end
  
    execute "Update registry image to current version \"#{hosted_upgrade_version}\"" do
      command lazy {
        "#{node['cookbook-openshift3']['openshift_common_client_binary']} \
        --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
        patch dc/docker-registry -n #{node['cookbook-openshift3']['openshift_hosted_registry_namespace']} -p \
        \'{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"registry\",\"image\":\"#{node.run_state['registry_image'].gsub(/:v.+/, ":#{hosted_upgrade_version}")}\"}]}}}}'"
      }
      only_if do
        node['cookbook-openshift3']['openshift_hosted_manage_registry']
      end
    end
  
    log 'Update hosted deployment(s) to current version [COMPLETED]' do
      level :info
    end
  end
end
