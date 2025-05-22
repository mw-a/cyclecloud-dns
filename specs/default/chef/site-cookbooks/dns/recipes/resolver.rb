search_list = node.fetch(:dns, {}).fetch(:search_list, "")
servers = node.fetch(:dns, {}).fetch(:servers, "")

if !search_list.empty? || !servers.empty?
  execute "deprotect eth0 network config" do
    command "chattr -i /etc/sysconfig/network-scripts/ifcfg-eth0"
    subscribes :run, "execute[restore selinux context eth0 network config]", :before
  end

  # restore SELinux context broken by cloud-init somehow
  execute "restore selinux context eth0 network config" do
    command "restorecon /etc/sysconfig/network-scripts/ifcfg-*"
    subscribes :run, "execute[configure eth0 dns servers]", :before
    subscribes :run, "execute[configure eth0 dns search list]", :before
  end

  servers_will_change = false
  if !servers.empty?
    servers_will_change = shell_out!("nmcli -g ipv4.dns c s 'System eth0'").stdout !~ /#{servers}/
    execute "configure eth0 dns servers" do
      command "nmcli c m 'System eth0' ipv4.ignore-auto-dns yes ipv4.dns '#{servers}'"
      only_if { servers_will_change }
      subscribes :run, "execute[protect eth0 network config]", :before
    end
  end

  search_list_will_change = false
  if !search_list.empty?
    search_list_will_change = shell_out!("nmcli -g ipv4.dns-search c s 'System eth0'").stdout !~ /#{search_list}/
    execute "configure eth0 dns search list" do
      command "nmcli c m 'System eth0' ipv4.dns-search '#{search_list}'"
      only_if { search_list_will_change }
      subscribes :run, "execute[protect eth0 network config]", :before
    end
  end

  # prevent cloud-init from resetting the file on reboot
  execute "protect eth0 network config" do
    command "chattr +i /etc/sysconfig/network-scripts/ifcfg-eth0"
    subscribes :run, "execute[activate eth0 network config]", :before
  end

  execute "activate eth0 network config" do
    command "nmcli c u 'System eth0'"
    # notify immediately would run it twice if both servers and search list
    # changed and delayed would run it at the very and of the run which would
    # likely be too late for other steps to take advantage of working
    # resolution
    only_if { servers_will_change || search_list_will_change }
    # PBS execute and server need working DNS
    subscribes :run, "execute[await-node-definition]", :before
    subscribes :run, "service[pbs]", :before
  end
end

trim_domains = node.fetch(:dns, {}).fetch(:trim_domains, false)
domains = search_list.split(",")
if trim_domains
  ruby_block "Update host.conf for trimming DNS domains" do
    block do
      for domain in domains do
        trim_line = "trim .#{domain}"
        file = Chef::Util::FileEdit.new("/etc/host.conf")
        file.search_file_delete_line(trim_line)
        file.insert_line_if_no_match(trim_line, trim_line)
      end
      file.write_file
    end
    # PBS execute and server need working DNS
    subscribes :run, "execute[await-node-definition]", :before
    subscribes :run, "service[pbs]", :before
  end
end

update_reverse_zone_id = node.fetch(:dns, {}).fetch(:update_reverse_zone_id, "")
if !update_reverse_zone_id.empty?
  package "azure-cli" do
    action :install
    subscribes :install, "bash[update azure reverse lookup ptr record]", :before
  end

  hostname = node[:hostname]

  # nodename will not be updated yet during first converge with PBS
  is_compute = node.fetch(:roles, []).include?("pbspro_execute_role")
  use_nodename_as_hostname = node.fetch(:pbspro, {}).fetch(:use_nodename_as_hostname, false)
  if is_compute && use_nodename_as_hostname
    nodename = node[:cyclecloud][:node][:name]
    node_prefix = node[:pbspro][:node_prefix]
    if !node_prefix.empty?
      hostname = "#{node_prefix}#{nodename}"
    end
  end

  # fully qualify local hostname based on DNS search list (not
  # necessarily correct but good enough for us)
  domain = domains.first
  fqdn = "#{hostname}.#{domain}."

  subscription = update_reverse_zone_id.split("/")[2]
  resource_group = update_reverse_zone_id.split("/")[4]
  zone_name = update_reverse_zone_id.split("/")[8]

  node_ip = node[:cyclecloud][:instance][:ipv4]
  ptr_name = node_ip.split(".")[3]
  bash "update azure reverse lookup ptr record" do
    code <<-EOH
      az login -i && \
        az network private-dns record-set ptr delete --yes --name #{ptr_name} --subscription #{subscription} --resource-group #{resource_group} --zone-name #{zone_name} && \
        az network private-dns record-set ptr create --name #{ptr_name} --ttl 10 --subscription #{subscription} --resource-group #{resource_group} --zone-name #{zone_name} && \
        az network private-dns record-set ptr add-record --record-set-name #{ptr_name} --ptrdname #{fqdn} --subscription #{subscription} --resource-group #{resource_group} --zone-name #{zone_name}
    EOH
    only_if { shell_out!("host #{node_ip}", { :returns => [0, 1] }).stdout !~ /domain name pointer #{fqdn}/ }

    # PBS execute and server need working DNS
    subscribes :run, "execute[await-node-definition]", :before
    subscribes :run, "service[pbs]", :before
  end
end
