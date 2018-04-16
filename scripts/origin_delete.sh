#!/bin/bash
set -e
clear
cat << BASH

############################################################
#                    DELETE OSE                            #
############################################################
BASH
### Create the chef-local mode infrastructure
mkdir -p ~/chef-solo-example/{backup,cache,roles,cookbooks,environments}
cd ~/chef-solo-example/cookbooks
### Installing dependencies
echo "Installing prerequisite packages, please wait..."
yum -y install -q https://packages.chef.io/files/stable/chef/14.0.190/el/7/chef-14.0.190-1.el7.x86_64.rpm git
### Installing cookbooks
[ -d ~/chef-solo-example/cookbooks/is_apaas_openshift_cookbook ] || git clone -q https://github.com/IshentRas/is_apaas_openshift_cookbook.git
[ -d ~/chef-solo-example/cookbooks/iptables ] || git clone -q https://github.com/chef-cookbooks/iptables.git
[ -d ~/chef-solo-example/cookbooks/yum ] || git clone -q https://github.com/chef-cookbooks/yum.git
[ -d ~/chef-solo-example/cookbooks/selinux_policy ] || git clone -q https://github.com/BackSlasher/chef-selinuxpolicy.git selinux_policy
[ -d ~/chef-solo-example/cookbooks/compat_resource ] || git clone -q https://github.com/chef-cookbooks/compat_resource.git
cd ~/chef-solo-example
### Create the dedicated environment for Origin deployment
cat << BASH > environments/origin.json
{
  "name": "origin",
  "description": "",
  "cookbook_versions": {

  },
  "json_class": "Chef::Environment",
  "chef_type": "environment",
  "default_attributes": {

  },
  "override_attributes": {
    "is_apaas_openshift_cookbook": {
      "openshift_common_sdn_network_plugin_name": "redhat/openshift-ovs-multitenant",
      "openshift_cluster_name": "console.${IP}.nip.io",
      "openshift_HA": true,
      "openshift_deployment_type": "origin",
      "openshift_common_default_nodeSelector": "region=infra",
      "deploy_containerized": true,
      "deploy_example": true,
      "openshift_master_htpasswd_users": [
        {
          "admin": "$apr1$5iDjNKyc$Cp8.GumvS3Q2jxeXYGptd."
        }
      ],
      "openshift_master_router_subdomain": "cloudapps.${IP}.nip.io",
      "master_servers": [
        {
          "fqdn": "${FQDN}",
          "ipaddress": "$IP"
        }
      ],
      "etcd_servers": [
        {
          "fqdn": "${FQDN}",
          "ipaddress": "$IP"
        }
      ],
      "node_servers": [
        {
          "fqdn": "${FQDN}",
          "ipaddress": "$IP",
          "schedulable": true,
          "labels": "region=infra"
        }
      ]
    }
  }
}
BASH
### Specify the configuration details for chef-solo
cat << BASH > ~/chef-solo-example/solo.rb
cookbook_path [
               '/root/chef-solo-example/cookbooks',
               '/root/chef-solo-example/site-cookbooks'
              ]
environment_path '/root/chef-solo-example/environments'
file_backup_path '/root/chef-solo-example/backup'
file_cache_path '/root/chef-solo-example/cache'
log_location STDOUT
solo true
BASH
### Delete OSE !!!!
chef-solo --environment origin -o recipe[is_apaas_openshift_cookbook::adhoc_uninstall] -c ~/chef-solo-example/solo.rb
cat << BASH

##### Uninstallation DONE ######
#####                     ######
Next steps for you :

1) Reboot this server

BASH
