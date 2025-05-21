search_list = node.fetch(:dns, {}).fetch(:search_list, "")
servers = node.fetch(:dns, {}).fetch(:servers, "")

if search_list and servers
  execute "chattr -i /etc/sysconfig/network-scripts/ifcfg-eth0"

  # restore SELinux context broken by cloud-init somehow
  execute "restorecon /etc/sysconfig/network-scripts/ifcfg-*"

  servers_will_change = false
  if servers
    servers_will_change = shell_out!("nmcli -g ipv4.dns c s 'System eth0'").stdout !~ /#{servers}/
    execute "nmcli c m 'System eth0' ipv4.ignore-auto-dns yes ipv4.dns '#{servers}'" do
      only_if { servers_will_change }
    end
  end

  search_list_will_change = false
  if search_list
    search_list_will_change = shell_out!("nmcli -g ipv4.dns-search c s 'System eth0'").stdout !~ /#{search_list}/
    execute "nmcli c m 'System eth0' ipv4.dns-search '#{search_list}'" do
      only_if { search_list_will_change }
    end
  end

  # prevent cloud-init from resetting the file on reboot
  execute "chattr +i /etc/sysconfig/network-scripts/ifcfg-eth0"

  execute "nmcli c u 'System eth0'" do
    # notify immediately would run it twice if both servers and search list
    # changed and delayed would run it at the very and of the run which would
    # likely be too late for other steps to take advantage of working
    # resolution
    only_if { servers_will_change or search_list_will_change }
  end
end

trim_domains = node.fetch(:dns, {}).fetch(:trim_domains, false)
if trim_domains
  domains = search_list.split(",")
  for domain in domains do
    trim_line = "trim #{domain}"
    ruby_block "Update host.conf for trimming DNS domains" do
      block do
        file = Chef::Util::FileEdit.new("/etc/host.conf")
        file.search_file_delete_line(trim_line)
        file.insert_line_if_no_match(trim_line, trim_line)
        file.write_file
      end
    end
  end
end
