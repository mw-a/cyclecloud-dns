search_list = node.fetch(:dns, {}).fetch(:search_list, "")
servers = node.fetch(:dns, {}).fetch(:servers, "")

if search_list and servers
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
  if servers
    servers_will_change = shell_out!("nmcli -g ipv4.dns c s 'System eth0'").stdout !~ /#{servers}/
    execute "configure eth0 dns servers" do
      command "nmcli c m 'System eth0' ipv4.ignore-auto-dns yes ipv4.dns '#{servers}'"
      only_if { servers_will_change }
      subscribes :run, "execute[protect eth0 network config]", :before
    end
  end

  search_list_will_change = false
  if search_list
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
    only_if { servers_will_change or search_list_will_change }
    # PBS execute and server need working DNS
    subscribes :run, "execute[await-node-definition]", :before
    subscribes :run, "service[pbs]", :before
  end
end

trim_domains = node.fetch(:dns, {}).fetch(:trim_domains, false)
if trim_domains
  ruby_block "Update host.conf for trimming DNS domains" do
    block do
      domains = search_list.split(",")
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
