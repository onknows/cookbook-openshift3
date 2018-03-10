#
# Cookbook Name:: cookbook-openshift3
# Recipe:: upgrade_control_plane15
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

# This must be run before any upgrade takes place.
# It creates the service signer certs (and any others) if they were not in
# existence previously.

node.force_override['cookbook-openshift3']['upgrade'] = true
node.force_override['cookbook-openshift3']['ose_major_version'] = '1.5'
node.force_override['cookbook-openshift3']['ose_version'] = '1.5.1-1.el7'
node.force_override['cookbook-openshift3']['openshift_docker_image_version'] = 'v1.5.1'
node.force_override['cookbook-openshift3']['etcd_version'] = '3.1.9-2.el7'

hosted_upgrade_version = node['cookbook-openshift3']['deploy_containerized'] == true ? node['cookbook-openshift3']['openshift_docker_image_version'] : 'v' + node['cookbook-openshift3']['ose_version'].to_s.split('-')[0]

server_info = OpenShiftHelper::NodeHelper.new(node)
is_etcd_server = server_info.on_etcd_server?
is_master_server = server_info.on_master_server?
is_node_server = server_info.on_node_server?
is_first_master = server_info.on_first_master?

if defined? node['cookbook-openshift3']['upgrade_repos']
  node.force_override['cookbook-openshift3']['yum_repositories'] = node['cookbook-openshift3']['upgrade_repos']
end

if is_etcd_server
  log 'Upgrade for ETCD [STARTED]' do
    level :info
  end

  execute 'Generate etcd backup before upgrade' do
    command "etcdctl backup --data-dir=#{node['cookbook-openshift3']['etcd_data_dir']} --backup-dir=#{node['cookbook-openshift3']['etcd_data_dir']}-pre-upgrade15"
    not_if { ::File.directory?("#{node['cookbook-openshift3']['etcd_data_dir']}-pre-upgrade15") }
    notifies :run, 'execute[Copy etcd v3 data store (PRE)]', :immediately
  end

  execute 'Copy etcd v3 data store (PRE)' do
    command "cp -a #{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db #{node['cookbook-openshift3']['etcd_data_dir']}-pre-upgrade15/member/snap/"
    only_if { ::File.file?("#{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db") }
    action :nothing
  end

  include_recipe 'cookbook-openshift3'
  include_recipe 'cookbook-openshift3::common'
  include_recipe 'cookbook-openshift3::etcd_cluster'

  execute 'Generate etcd backup after upgrade' do
    command "etcdctl backup --data-dir=#{node['cookbook-openshift3']['etcd_data_dir']} --backup-dir=#{node['cookbook-openshift3']['etcd_data_dir']}-post-upgrade15"
    not_if { ::File.directory?("#{node['cookbook-openshift3']['etcd_data_dir']}-post-upgrade15") }
    notifies :run, 'execute[Copy etcd v3 data store (POST)]', :immediately
  end

  execute 'Copy etcd v3 data store (POST)' do
    command "cp -a #{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db #{node['cookbook-openshift3']['etcd_data_dir']}-post-upgrade15/member/snap/"
    only_if { ::File.file?("#{node['cookbook-openshift3']['etcd_data_dir']}/member/snap/db") }
    action :nothing
  end

  log 'Upgrade for ETCD [COMPLETED]' do
    level :info
  end
end

if is_master_server
  log 'Upgrade for MASTERS [STARTED]' do
    level :info
  end

  include_recipe 'cookbook-openshift3::certificate_server' if node['cookbook-openshift3']['deploy_containerized']

  if node['cookbook-openshift3']['openshift_HA']
    include_recipe 'cookbook-openshift3::master_cluster'
  else
    include_recipe 'cookbook-openshift3::master_standalone'
  end

  include_recipe 'cookbook-openshift3::node' if is_node_server

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
      \'{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"router\",\"image\":\"#{node.run_state['router_image'].gsub(/:v.+/, ":#{hosted_upgrade_version}")}\",\"livenessProbe\":{\"tcpSocket\":null,\"httpGet\":{\"path\": \"/healthz\", \"port\": 1936, \"host\": \"localhost\", \"scheme\": \"HTTP\"},\"initialDelaySeconds\":10,\"timeoutSeconds\":1}}]}}}}' \
      --api-version=v1"
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
      \'{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"registry\",\"image\":\"#{node.run_state['registry_image'].gsub(/:v.+/, ":#{hosted_upgrade_version}")}\"}]}}}}' \
      --api-version=v1"
    }
    only_if do
      node['cookbook-openshift3']['openshift_hosted_manage_registry']
    end
  end

  execute 'Upgrade job storage' do
    command "#{node['cookbook-openshift3']['openshift_common_admin_binary']} \
            --config=#{node['cookbook-openshift3']['openshift_master_config_dir']}/admin.kubeconfig \
            migrate storage --include=jobs --confirm"
  end

  log 'Update hosted deployment(s) to current version [COMPLETED]' do
    level :info
  end
end
