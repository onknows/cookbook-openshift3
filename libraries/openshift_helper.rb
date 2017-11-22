module OpenShiftHelper
  class NodeHelper
    def initialize(node)
      @node = node
    end

    def master_servers
      if !node['cookbook-openshift3']['openshift_cluster_duty_discovery_id'].nil? && node.run_list.roles.include?("#{node['cookbook-openshift3']['openshift_cluster_duty_discovery_id']}_use_role_based_duty_discovery")
        Chef::Search::Query.new.search(:node, "role:#{node['cookbook-openshift3']['openshift_cluster_duty_discovery_id']}_openshift_master_duty")
      else
        node['cookbook-openshift3']['master_servers']
      end
    end

    def first_master?
      master_servers.find { |server_master| server_master['fqdn'] == node['fqdn'] }
    end

    protected

    attr_reader :node
  end
end
