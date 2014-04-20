####
## bnc.im administration bot
##
## Copyright (c) 2013 Andrew Northall
##
## MIT License
## See LICENSE file for details.
####


class NetworkDB
  include Cinch::Plugin
  
  def self.network_view(network)
    replies = []
    sum = 0
    ips = $config["ips"]
    servers = $userdb.servers
    ips.each do |name, addrs|
      ipv4 = addrs["ipv4"]
      ipv6 = addrs["ipv6"]
      netcount = servers[name].conns_for_network(network)
      sum += netcount
      reply = "#{Format(:bold, "[#{name}:#{netcount}]")} #{Format(:bold, "Interfaces:")} "
      ipv4.each do |ip|
        reply = reply + "#{name}-4-#{ipv4.index(ip)} (#{servers[name].conns_on_iface(ip, network)}), "
      end
      unless ipv6.nil?
        ipv6.each do |ip|
          reply = reply + "#{name}-6-#{ipv6.index(ip)} (#{servers[name].conns_on_iface(ip, network)}), "
        end
      end
      replies << reply[0..-3]
    end
    if sum == 0 
      return ["No networks named \"#{network}\" were found."]
    end
    
    return ["#{Format(:bold, "[#{network}]")} Network Counts - #{sum} Users"] + replies
  end
end