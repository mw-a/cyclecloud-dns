name "dns_role"
description "Configure DNS"
run_list("recipe[dns::resolver]")
