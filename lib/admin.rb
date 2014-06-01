####
## bnc.im administration bot
##
## Copyright (c) 2013, 2014 Andrew Northall
##
## MIT License
## See LICENSE file for details.
####


require 'socket'
require 'openssl'
require 'timeout'

class Numeric
  def duration
    secs  = self.to_int
    mins  = secs / 60
    hours = mins / 60
    days  = hours / 24

    if days > 0
      "#{days} day#{'s' unless days == 1} and #{hours % 24} hour#{'s' unless (hours % 24) == 1}"
    elsif hours > 0
      "#{hours} hour#{'s' unless (hours % 24) == 1} and #{mins % 60} minute#{'s' unless (mins % 60) == 1}"
    elsif mins > 0
      "#{mins} minute#{'s' unless (mins % 60) == 1} and #{secs % 60} second#{'s' unless (secs % 60) == 1}"
    elsif secs >= 0
      "#{secs} second#{'s' unless (secs % 60) == 1}"
    end
  end
end

class Crawler
  def self.crawl(server, port)
    ssl = false
    if port[0] == "+"
      port = port[1..-1].to_i
      ssl = true
    else
      port = port.to_i
    end
    
    results = []
    
    sock = TCPSocket.new(server, port)
    if ssl
      ssl_context = OpenSSL::SSL::SSLContext.new
      ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
      sock = OpenSSL::SSL::SSLSocket.new(sock, ssl_context)
      sock.sync = true
      sock.connect
    end
    start = Time.now.to_i
    
    nick = "bncim#{rand(1000)}"
    
    sock.puts "USER crawler crawler crawler :bnc.im crawler"
    sock.puts "NICK #{nick}"
    
    Timeout::timeout(20) do 
      while line = sock.gets
        elapsed = Time.now.to_i - start
        break if elapsed > 15
        if line =~ /^PING (\S+)/
          sock.puts "PONG #{$1}"
        elsif line =~ /^:(\S+) (001|002|251|266|376) #{nick} :?(.+)$/
          if $2 == "376"
            sock.puts "QUIT :Bye!"
            sock.close
            break
          else
            results << $3
          end
        end
      end
    end
    
    results << "No data gathered. Did the request time out?" if results.empty?
    
    results
  end
end

class AdminPlugin
  include Cinch::Plugin
  match /ban (\S+)/, method: :ban
  match /unban (\S+)/, method: :unban
  match /kick (\S+) (.+)$/, method: :kick
  match /topic (.+)/, method: :topic
  match /approve\s+(\d+)\s+(\S+)\s*$/, method: :approve, group: :approve
  match /approve\s+(\d+)\s+(\S+)\s+([a-zA-Z\-]+)\s*$/, method: :approve, group: :approve
  match /approve\s+(\d+)\s+(\S+)\s+([a-zA-Z\-]+)\s+(.+)\s*$/, method: :approve, group: :approve
  match /accept\s+(\d+)\s+(\S+)\s*$/, method: :approve, group: :approve
  match /accept\s+(\d+)\s+(\S+)\s+([a-zA-Z\-]+)\s*$/, method: :approve, group: :approve
  match /accept\s+(\d+)\s+(\S+)\s+([a-zA-Z\-]+)\s+(.+)\s*$/, method: :approve, group: :approve
  match /reject\s+(\d+)\s+(.+)\s*$/, method: :reject
  match /delete\s+(\d+)/, method: :delete
  match /reqinfo\s+(\d+)/, method: :reqinfo
  match /requser\s+(\S+)/, method: :requser
  match "pending", method: :pending
  match "unconfirmed", method: :unconfirmed
  match "reports", method: :reports
  match /fverify\s+(\d+)/, method: :fverify
  match "servers", method: :servers
  match /broadcast (.+)/, method: :broadcast
  match /sbroadcast (\w+) (.+)/, method: :serverbroadcast
  match /cp (\w+) (.+)/, method: :cp
  match /addnet\s+(\w+)\s+(\S+)\s+(\S+)\s+(.+)\s*$/, method: :addnet
  match /delnet\s+(\w+)\s+(\S+)\s+(\S+)\s*$/, method: :delnet
  match "stats", method: :stats
  match /find (\S+)$/, method: :find, group: :find
  match /find (\S+) ([a-z]{3}\d)/, method: :find, group: :find
  match /findnet (\S+)$/, method: :findnet, group: :findnet
  match /findnet (\S+) ([a-z]{3}\d)/, method: :findnet, group: :findnet
  match "offline", method: :offline
  match /netcount (\S+)/, method: :netcount
  match /crawl (\S+) (\+?\d+)/, method: :crawl
  match "update", method: :update
  match "data", method: :data
  match /seeip (\S+)/i, method: :seeip
  match /seeinterface (\S+)/i, method: :seeinterface
  match /genpass (\d+)/i, method: :genpass
  match "blocked", method: :blocked
  match /block (\S+) (\S+)/, method: :block
  match /unblock (\S+) (\S+)/, method: :unblock
  match /todo\s*$/, method: :todo
  match /net (\S+)/i, method: :network_view
  match /^\-(\S+)$/i, method: :network_view, use_prefix: false
  match /disconnect\s+([a-z]{3}\d)\s+(\S+)\s+(\S+)\s*/i, method: :disconnect
  match /connect\s+([a-z]{3}\d)\s+(\S+)\s+(\S+)\s*/i, method: :connect
  match /networks\s*$/i, method: :networks
  match /networks\s+(\d+)\s*$/i, method: :networks
  match "connectall", method: :connectall
  
  timer 120, method: :silent_update
  
  match "help", method: :help
  
  def connectall(m)
    return unless command_allowed(m, true)
    results = []
    $userdb.servers.each do |name, server|
      server.users.each do |username, user|
        next if user.blocked?
        user.networks.each do |network|
          unless network.online
            results << [user, network]
          end
        end
      end
    end
    m.reply "Attempting to reconnect #{results.size} offline networks."
    results.each do |user, network|
      do_connect(m, user.server, user.username, network.name)
    end
  end
  
  def networks(m, limit = 10)
    return unless command_allowed(m, true)
    users = Array.new
    networks = Hash.new(0)
    limit = limit.to_i
    
    $userdb.servers.map { |k, s| users = users + s.users.values }
    
    users.each do |user|
      user.networks.each do |network|
        networks[network.name.downcase] += 1
      end
    end
    
    networks = networks.sort_by { |k, v| v }.reverse
   
    limit = networks.size - 1 if limit > networks.size
   
    limit.times do |num|
      name, count = networks.shift
      m.reply Format(:bold, "[#{num + 1}]") + " #{name} - #{count} users"
    end
  end
  
  def connect(m, server, user, network)
    return unless command_allowed(m, true)
    server.downcase!
    if $userdb.servers.has_key? server
      do_connect(m, server, user, network)
    else
      m.reply "#{Format(:bold, "Error:")} server #{server} not found."
    end
  end
  
  def disconnect(m, server, user, network)
    return unless command_allowed(m, true)
    server.downcase!
    if $userdb.servers.has_key? server
      do_connect(m, server, user, network, true)
    else
      m.reply "#{Format(:bold, "Error:")} server #{server} not found."
    end
  end
  
  def block(m, server, user)
    return unless command_allowed(m, true)
    server.downcase!
    if $userdb.servers.has_key? server
      if $userdb.servers[server].users.has_key? user
        if $userdb.servers[server].users[user].blocked?
          m.reply "#{Format(:bold, "Error:")} User #{user} is already blocked."
        else
          do_block(m, server, user)
        end
      else
        m.reply "#{Format(:bold, "Error:")} User #{user} not found on #{server}."
      end
    else
      m.reply "#{Format(:bold, "Error:")} server #{server} not found."
    end
  end
  
  def unblock(m, server, user)
    return unless command_allowed(m, true)
    server.downcase!
    if $userdb.servers.has_key? server
      if $userdb.servers[server].users.has_key? user
        if $userdb.servers[server].users[user].blocked?
          do_block(m, server, user, true)
        else
          m.reply "#{Format(:bold, "Error:")} User #{user} is not blocked."
        end
      else
        m.reply "#{Format(:bold, "Error:")} User #{user} not found on #{server}."
      end
    else
      m.reply "#{Format(:bold, "Error:")} server #{server} not found."
    end
  end
  
  def genpass(m, len)
    return unless command_allowed(m)
    if len.to_i > 100
      Channel(m.channel).kick(m.user)
      return
    end
    
    m.reply RequestDB.gen_key(len.to_i)
  end
  
  def todo(m)
    pending(m)
    reports(m)
  end
    
  def data(m)
    return unless command_allowed(m, true)
    diff = Time.now.to_i - $userdb.updated.to_i
    m.reply "The current set of user data was updated at: #{Format(:bold, $userdb.updated.ctime)} (#{diff.duration} ago)"
  end
  
  def blocked(m)
    return unless command_allowed(m, true)
    $userdb.servers.each do |name, server|
      if server.blocked_users.size > 0
        m.reply Format(:bold, "[#{name}]") + " #{server.blocked_users.keys.join(", ")}."
      else
        m.reply Format(:bold, "[#{name}]") + " None."
      end
    end
  end
  
  def help(m)
    return unless command_allowed(m)
    m.reply "#{Format(:bold, "[REQUESTS]")} !unconfirmed | !pending | !reqinfo <id> | !requser <name> | !delete <id> | !reject <id> [reason] | !fverify <id> | !approve <id> <interface> [network name] [irc server] [irc port]"
    m.reply "#{Format(:bold, "[REPORTS]")} !reports | !clear <reportid> [message] | !reportid <id>"
    m.reply "#{Format(:bold, "[USERS]")} ![dis]connect <server> <user> <networK> | !addnet <server> <username> <netname> <addr> <port> | !delnet <server> <username> <netname> | !blocked | ![un]block <server> <user>"
    m.reply "#{Format(:bold, "[MANAGEMENT]")} !net <network> | !cp <server> <command> | !sbroadcast <server> <text> | !broadcast <text> | !kick <user> <reason> | !ban <mask> | !unban <mask> | !topic <topic>"
    m.reply "#{Format(:bold, "[ZNC DATA]")} !find <user regexp> | !findnet <regexp> | !netcount <regexp> | !stats | !update | !data | !offline | !networks [num]"
    m.reply "#{Format(:bold, "[MISC]")} !todo | !crawl <server> <port> | !servers | !seeip <interface> | !seeinterface <ip> | !genpass <len>" 
    m.reply "#{Format(:bold, "[NOTES]")} !note | !note list <category> | !note add <category> | !note del <category> | !note add <category> <item> | !note del <category> <num> | !netnote <netname> [newnote]" 
    
  end 
  
  def seeip(m, interface)
    return unless command_allowed(m)
    if interface =~ /^([a-z]{3}\d{1})\-(4|6)\-(\d+)$/
      server, proto, index = $1, $2, $3
      index = index.to_i
      
      if proto == "4"
        proto = "ipv4"
      elsif proto == "6"
        proto = "ipv6"
      else
        m.reply "Error: Invalid interface."
        return
      end
      
      unless $config["ips"].has_key? server
        m.reply "Error: Invalid interface."
        return
      end
      
      if proto == "ipv6" and !$config["ips"][server].has_key? 'ipv6'
        m.reply "Error: Invalid interface."
        return
      end
      
      if $config["ips"][server][proto][index].nil?
        m.reply "Error: Invalid interface."
        return
      end
      
      m.reply Format(:bold, "[#{interface}]") + " " + $config["ips"][server][proto][index]
    else
      m.reply "Error: Invalid interface."
    end
  end
  
  def seeinterface(m, ip)
    return unless command_allowed(m)
    m.reply Format(:bold, "[#{ip}]") + " " + get_interface_name(ip)
  end
  
  def update(m)
    return unless command_allowed(m, true)
    m.reply "Updating...."
    $userdb.update
    m.reply "Updated user data."
  end
  
  def crawl(m, server, port)
    return unless command_allowed(m)
    m.reply "Attempting to crawl #{server}:#{port} (timeout 20 sec)"
    
    begin
      results = Crawler.crawl(server, port)
    rescue => e
      m.reply "#{Format(:bold, "Crawling failed!")} Error: #{e.message}"
      return
    end
    
    results.each do |line|
      m.reply "#{Format(:bold, "[#{server}]")} #{line}"
    end
  end
  
  def netcount(m, str)
    return unless command_allowed(m, true)
    total, offline = 0, 0
    $userdb.servers.each do |name, server|
      server.users.each do |username, user|
        user.networks.each do |network|
          if network.name =~ /#{str}/i or network.server =~ /#{str}/i
            total += 1
            offline += 1 unless network.online
          end
        end
      end
    end
    m.reply "#{total} connections found for /#{str}/. #{offline} are offline."
  end
      
  def offline(m)
    return unless command_allowed(m, true)
    results = []
    $userdb.servers.each do |name, server|
      server.users.each do |username, user|
        user.networks.each do |network|
          unless network.online
            results << [user, network]
          end
        end
      end
    end
    if results.empty?
      m.reply "No results."
      return
    end 
    m.reply Format(:bold, " Server  Username        Network           Userhost                                                    Interface")
    results.each do |user, network|
      if user.blocked?
        m.reply Format(:red, " " + user.server.ljust(8) + user.username.ljust(16) + network.name.ljust(78) + get_interface_name(network.bindhost))
      else
        m.reply " " + user.server.ljust(8) + user.username.ljust(16) + Format(:red, network.name.ljust(78)) + get_interface_name(network.bindhost)
      end
    end
    m.reply Format(:bold, " End of list.")
  end
  
  def findnet(m, str, specserver = nil)
    return unless command_allowed(m, true)
    results = []
    $userdb.servers.each do |name, server|
      unless specserver.nil?
        unless name.downcase == specserver.downcase
          next
        end
      end
      
      server.users.each do |username, user|
        user.networks.each do |network|
          if network.name =~ /#{str}/i or network.server =~ /#{str}/i
            results << [user, network]
          end
        end
      end
    end
    
    if results.empty?
      m.reply "No results."
      return
    elsif results.size > 50
      m.reply "#{Format(:bold, "Error:")} more than 50 results. Please be more specific."
      return
    end
    
    m.reply Format(:bold, " Server  Username        Network           Userhost                                                    Interface")
    results.each do |user, network|
      if network.online
        m.reply " " + user.server.ljust(8) + user.username.ljust(16) + Format(:green, network.name.ljust(18)) + network.user.ljust(60) + get_interface_name(network.bindhost)
      else
        if user.blocked?
          m.reply Format(:red, " " + user.server.ljust(8) + user.username.ljust(16) + network.name.ljust(78) + get_interface_name(network.bindhost))
        else
          m.reply " " + user.server.ljust(8) + user.username.ljust(16) + Format(:red, network.name.ljust(78)) + get_interface_name(network.bindhost)
        end
      end
    end
    m.reply Format(:bold, " End of list.")
  end
  
  def find(m, search_str, specserver = nil)
    return unless command_allowed(m, true)
    if search_str =~ /(eren|rylee|andrew|matthew|bncbot|templateuser)/i
      Channel("#bnc.im-admin").kick m.user
      return
    end
    
    results = $userdb.find_user(search_str, specserver)
    
    if results.nil?
      m.reply "No results."
      return
    elsif results.size > 50
      m.reply "#{Format(:bold, "Error:")} more than 50 results. Please be more specific."
      return
    end
    
    m.reply Format(:bold, " Server  Username        Network           Userhost                                                    Interface")
    results.each do |user|
      if user.networks.size == 0
        m.reply " " + user.server.ljust(8) + user.username
      end
      user.networks.each do |network|
        if network.online
          m.reply " " + user.server.ljust(8) + user.username.ljust(16) + Format(:green, network.name.ljust(18)) + network.user.ljust(60) + get_interface_name(network.bindhost)
        else
          if user.blocked?
            m.reply Format(:red, " " + user.server.ljust(8) + user.username.ljust(16) + network.name.ljust(78) + get_interface_name(network.bindhost))
          else
            m.reply " " + user.server.ljust(8) + user.username.ljust(16) + Format(:red, network.name.ljust(78)) + get_interface_name(network.bindhost)
          end
        end
      end
    end
    m.reply Format(:bold, " End of list.")
  end
  
  def stats(m)
    return unless command_allowed(m, true)
    m.reply "#{Format(:bold, "[Stats]")} Total users: #{$userdb.users_count} | Total networks: #{$userdb.networks_count} | Offline networks: #{$userdb.offline_networks_count}"
    servers = []
    $userdb.servers.each do |name, server|
      servers << "#{name}: #{server.users_count}u/#{server.networks_count}n/#{server.offline_networks_count}o"
    end
    m.reply "#{Format(:bold, "[Stats]")} #{servers.join(" | ")}"
  end
  
  def addnet(m, server, username, netname, addrstr)
    return unless command_allowed(m)
    server.downcase!
    netname.downcase!
    unless $zncs.has_key? server
      m.reply "Server \"#{server}\" not found."
      return
    end
    $zncs[server].irc.send(msg_to_control("AddNetwork #{username} #{netname}"))
    $zncs[server].irc.send(msg_to_control("AddServer #{username} #{netname} #{addrstr}"))
    if $config["servers"].include? netname.downcase
      $zncs[server].irc.send(msg_to_control("AddChan #{username} #{netname} #bnc.im"))
    end
    m.reply "done."
    $userdb.update
  end
  
  def delnet(m, server, username, netname)
    return unless command_allowed(m)
    server.downcase!
    netname.downcase!
    unless $zncs.has_key? server
      m.reply "Server \"#{server}\" not found."
      return
    end
    $zncs[server].irc.send(msg_to_control("DelNetwork #{username} #{netname}"))
    m.reply "done!"
    $userdb.update
  end

  def topic(m, topic)
    return unless command_allowed(m)
    $bots.each_value do |bot|
      bot.Channel("#bnc.im").topic = topic
    end
    m.reply "done!"
  end
  
  def broadcast(m, text)
    return unless command_allowed(m)
    $bots.each_value do |bot|
      bot.irc.send("PRIVMSG #bnc.im :#{Format(:bold, "[BROADCAST]")} #{text}")
    end
    
    $zncs.each_value do |zncbot|
      zncbot.irc.send("PRIVMSG *status :broadcast [Broadcast Message] #{text}")
    end
    m.reply "done!"
  end
  
  def serverbroadcast(m, server, text)
    return unless command_allowed(m)
    server.downcase!
    unless $zncs.has_key? server
      m.reply "Server \"#{server}\" not found."
      return
    end
    $bots.each_value do |bot|
      bot.irc.send("PRIVMSG #bnc.im :#{Format(:bold, "[INFO FOR #{server.upcase} USERS]")} #{text}")
    end
    
    $zncs[server].irc.send("PRIVMSG *status :broadcast [Broadcast Message] #{text}")
    m.reply "done!"
  end

  def cp(m, server, command)
    return unless command_allowed(m)
    if command.downcase =~ /^(dis|re|)connect eren/
      Channel("#bnc.im-admin").kick m.user
      return
    end
    if command.downcase =~ /^help/i
      Channel("#bnc.im-admin").kick m.user
      return
    end

    server.downcase!
    unless $zncs.has_key? server
      m.reply "Server \"#{server}\" not found."
      return
    end
    sock = TCPSocket.new($config["zncservers"][server]["addr"], $config["zncservers"][server]["port"].to_i)
    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
    sock = OpenSSL::SSL::SSLSocket.new(sock, ssl_context)
    sock.sync = true
    sock.connect
    sock.puts "NICK bncbot"
    sock.puts "USER bncbot bncbot bncbot :bncbot"
    sock.puts "PASS #{$config["zncservers"][server]["username"]}:#{$config["zncservers"][server]["password"]}"
    sock.puts "PRIVMSG *controlpanel :#{command}"
    
    Thread.new do
      Timeout::timeout(10) do
        while line = sock.gets
          if line =~ /^:\*controlpanel!znc@bnc\.im PRIVMSG bncbot :(.+)$/
            m.reply "#{Format(:bold, "[#{server}]")} #{$1}"
          end
        end
      end
    end
  end

  def ban(m, target)
    return unless command_allowed(m)
    $bots.each_value { |b| b.irc.send("MODE #bnc.im +b #{target}") }
    m.reply "done!"
  end

  def unban(m, target)
    return unless command_allowed(m)
    $bots.each_value { |b| b.irc.send("MODE #bnc.im -b #{target}") }
    m.reply "done!"
  end

  def kick(m, target, reason = "")
    return unless command_allowed(m)
    $bots.each_value { |b| b.irc.send("KICK #bnc.im #{target} :#{reason}") }
    m.reply "kicked #{target} in all channels (#{reason})"
  end
  
  def approve(m, id, interface, adminnetname = nil, addr = nil)
    return unless command_allowed(m, true)
    unless RequestDB.requests.has_key?(id.to_i)
      m.reply "Error: request ##{id} not found."
      return
    end
    
    r = RequestDB.requests[id.to_i]
    
    unless r.confirmed?
      m.reply "Error: request ##{id} has not been confirmed by email."
      return
    end
    
    if r.approved?
      m.reply "Error: request ##{id} is already approved."
      return
    end
    
    if r.rejected?
      m.reply "Error: request ##{id} has been rejected."
      return
    end
    
    if interface =~ /^([a-z]{3}\d{1})\-(4|6)\-(\d+)$/
      server, proto, index = $1, $2, $3
      index = index.to_i
      
      if proto == "4"
        proto = "ipv4"
      elsif proto == "6"
        proto = "ipv6"
      else
        m.reply "Error: Invalid interface."
        return
      end
      
      unless $config["ips"].has_key? server
        m.reply "Error: Invalid interface."
        return
      end
      
      if proto == "ipv6" and !$config["ips"][server].has_key? 'ipv6'
        m.reply "Error: Invalid interface."
        return
      end
      
      if $config["ips"][server][proto][index].nil?
        m.reply "Error: Invalid interface."
        return
      end
      
      ip = $config["ips"][server][proto][index]
    end
    
    server = find_server_by_ip(ip)
    
    if server.nil?
      m.reply "Error: #{ip} is not a valid IP address."
      return
    end
    
    password = RequestDB.gen_key(15)
    
    if adminnetname.nil?
      netname = Domainatrix.parse(r.server).domain
      netname = Domainatrix.parse(addr.split(" ")[0]).domain unless addr.nil?
    else
      netname = adminnetname
    end
        
    $zncs[server].irc.send(msg_to_control("CloneUser templateuser #{r.username}"))
    $zncs[server].irc.send(msg_to_control("Set Nick #{r.username} #{r.username}"))
    $zncs[server].irc.send(msg_to_control("Set AltNick #{r.username} #{r.username}_"))
    $zncs[server].irc.send(msg_to_control("Set Ident #{r.username} #{r.username}"))
    $zncs[server].irc.send(msg_to_control("Set BindHost #{r.username} #{ip}"))
    $zncs[server].irc.send(msg_to_control("Set DCCBindHost #{r.username} #{ip}"))
    $zncs[server].irc.send(msg_to_control("Set DenySetBindHost #{r.username} true"))
    $zncs[server].irc.send(msg_to_control("Set Password #{r.username} #{password}"))
    
    netname.downcase!
    
    Thread.new do
      sleep 3
      $zncs[server].irc.send(msg_to_control("AddNetwork #{r.username} #{netname}"))
      if addr.nil?
        $zncs[server].irc.send(msg_to_control("AddServer #{r.username} #{netname} #{r.server} #{r.port}"))
      else
        $zncs[server].irc.send(msg_to_control("AddServer #{r.username} #{netname} #{addr}"))
      end
      $zncs[server].irc.send(msg_to_control("SetNetwork Nick #{r.username} #{netname} #{r.username}"))
      if $config["servers"].include? netname.downcase
        $zncs[server].irc.send(msg_to_control("AddChan #{r.username} #{netname} #bnc.im"))
      end
    end
    
    RequestDB.approve(r.id)
    Mail.send_approved(r.email, server, r.username, password, netname)
    $config["notifymail"].each do |email|
      Mail.send_approved_admin(email, r.id, m.user.mask.to_s)
    end
    elapsed = Time.now.to_i - r.ts.to_i
    
    adminmsg("Request ##{id} for user #{r.source.to_s.split("!")[0]} #{Format(:green, :bold, "approved")} to #{server} " + \
             "(#{ip}) by #{m.user}. Request approved in #{elapsed.duration}. Password: #{password}")
             
    if elapsed < 120
      3.times { adminmsg "Wow, that's a quick approval! #{Format(:bold, :green, "WELL DONE #{m.user.nick}!!!!!!!!!!!!!")}" }
    end            
    
    $bots.each do |network, bot|
      begin
        elapsed = Time.now.to_i - r.ts.to_i
        bot.Channel("#bnc.im").msg "Request ##{id} for user #{r.source.to_s.split("!")[0]} has been #{Format(:green, :bold, "approved")} by #{m.user.nick}. " + \
                                   "This request was waiting for #{elapsed.duration}."
      rescue => e
        puts e
      end
    end
    $userdb.update
  end
  
  def reject(m, id, reason)
    return unless command_allowed(m)
    unless RequestDB.requests.has_key?(id.to_i)
      m.reply "Error: request ##{id} not found."
      return
    end
    
    r = RequestDB.requests[id.to_i]
    
    unless r.confirmed?
      m.reply "Error: request ##{id} has not been confirmed by email."
      return
    end
    
    if r.approved?
      m.reply "Error: request ##{id} is already approved."
      return
    end
    
    $bots.each do |network, bot|
      begin
        bot.irc.send("PRIVMSG #bnc.im" + \
                     " :Request ##{id} for user #{r.source.to_s.split("!")[0]} has been #{Format(:red, :bold, "rejected")} by #{m.user.nick}. Reason: #{reason}.")
      rescue => e
        # pass
      end
    end
    adminmsg("Request ##{id} for user #{r.source.to_s.split("!")[0]} has been #{Format(:red, :bold, "rejected")} by #{m.user.nick}. Reason: #{reason}.")
    Mail.send_reject(r.email, id, reason)
    $config["notifymail"].each do |email|
      Mail.send_rejected_admin(email, r.id, m.user.mask.to_s)
    end
    RequestDB.reject(r.id)
  end
  
  def servers(m)
    return unless command_allowed(m, true)
    ips = $config["ips"]
    ips.each do |name, addrs|
      ipv4 = addrs["ipv4"]
      ipv6 = addrs["ipv6"]
      reply = "#{Format(:bold, "[#{name}:#{$userdb.servers[name].networks_count}]")} " + \
              "#{Format(:bold, "Interfaces:")} "  
      ipv4.each do |ip|
        reply = reply + "#{name}-4-#{ipv4.index(ip)} (#{$userdb.bindhost_user_count(ip)}), "
      end
      unless ipv6.nil?
        ipv6.each do |ip|
          reply = reply + "#{name}-6-#{ipv6.index(ip)} (#{$userdb.bindhost_user_count(ip)}), "
        end
      end
      m.reply reply[0..-3]
    end
  end
  
  def network_view(m, network)
    return unless command_allowed(m, true)
    reply = NetworkDB.network_view(network)
    reply.each { |l| m.reply l }
  end
    
  def fverify(m, id)
    return unless command_allowed(m)
    unless RequestDB.requests.has_key?(id.to_i)
      m.reply "Error: request ##{id} not found."
      return
    end
    
    r = RequestDB.requests[id.to_i]
    
    if r.confirmed?
      m.reply "Error: request already confirmed."
      return
    end
    
    RequestDB.confirm(r.id)
    r = RequestDB.requests[id.to_i]
    
    adminmsg("Request ##{id} email verified by #{m.user}.")
    adminmsg("#{Format(:red, "[NEW REQUEST]")} #{format_status(r)}")
  end

  def requser(m, username)
    return unless command_allowed(m)
    RequestDB.requests.each do |key, req|
      if req.username.to_s.downcase == username.downcase
        m.reply format_status(req)
      end
    end
    m.reply "End of results."
  end
  
  def reqinfo(m, id)
    return unless command_allowed(m)
    unless RequestDB.requests.has_key?(id.to_i)
      m.reply "Error: request ##{id} not found."
      return
    end
    
    r = RequestDB.requests[id.to_i]
    
    if r.nil?
      m.reply "Request ##{id} not found."
      return
    end
    
    m.reply format_status(r)
  end
  
  def delete(m, id)
    return unless command_allowed(m)
    unless RequestDB.requests.has_key?(id.to_i)
      m.reply "Error: request ##{id} not found."
      return
    end
    
    RequestDB.delete_id id.to_i
    m.reply "Deleted request ##{id}."
  end

  def pending(m)
    return unless command_allowed(m)
    pending = RequestDB.requests.values.select { |r| r.status == 1 }
    
    if pending.empty?
      m.reply "No pending requests. Woop-de-fucking-do."
      return
    end
    
    m.reply "#{pending.size} pending request(s):"
    
    pending.each do |request|
      m.reply format_status(request)
    end
  end
  
  def reports(m)
    return unless command_allowed(m)
    pending = Array.new
    ReportDB.reports.each_value do |r|
      pending << r unless r.cleared?
    end
    
    if pending.empty?
      m.reply "No pending reports."
      return
    end
    
    m.reply "#{pending.size} pending report(s):"
    
    pending.each do |report|
      m.reply format_report(report)
    end
  end
    
  def unconfirmed(m)
    return unless command_allowed(m)
    unconfirmed = RequestDB.requests.values.select { |r| r.status == 0 }
    
    if unconfirmed.empty?
      m.reply "No unconfirmed requests. Try !pending?"
      return
    end
    
    m.reply "#{unconfirmed.size} unconfirmed request(s):"
    
    unconfirmed.each do |request|
      m.reply format_status(request)
    end
  end
  
  private
  
  def format_report(r)
    if r.cleared?
      clearedstr = Format(:bold, "[CLEARED] ")
    else
      clearedstr = ""
    end
    
    "%s %sSource: %s on %s / Username: %s / Date: %s / Server: %s / Content: %s" %
      [Format(:bold, "[##{r.id}]"), clearedstr, Format(:bold, r.source.to_s), 
       Format(:bold, r.ircnet.to_s), Format(:bold, r.username.to_s),
       Format(:bold, Time.at(r.ts).ctime), Format(:bold, r.server),
       Format(:bold, r.content.to_s)]
  end
  
  def msg_to_control(msg)
    "PRIVMSG *controlpanel :#{msg}"
  end
    
  def find_server_by_ip(ip)
    ips = $config["ips"]
    ips.each do |server, addrs|
      addrs.each_value do |addr|
        addr.each do |a|
          if a.downcase == ip.downcase
            return server
          end
        end
      end
    end
    return false
  end

  def format_status(r)
    "%s Source: %s on %s / Username: %s / Email: %s / Date: %s / Server: %s / Port: %s / Status: %s" %
      [Format(:bold, "[##{r.id}]"), Format(:bold, r.source.to_s), 
       Format(:bold, r.ircnet.to_s), Format(:bold, r.username.to_s),
       Format(:bold, r.email.to_s), Format(:bold, Time.at(r.ts).ctime),
       Format(:bold, r.server), Format(:bold, r.port.to_s),
       Format(:bold, r.english_status)]
  end
  
  def adminmsg(text)
    $adminbot.irc.send("PRIVMSG #bnc.im-admin :#{text}")
  end
  
  def command_allowed(m, needs_data = false)
    return false unless m.channel == "#bnc.im-admin"
    if needs_data and $userdb.updating?
      m.reply "#{Format(:bold, "Error:")} user DB is currently updating, please wait a few seconds."
      return false
    end
    
    if Channel("#bnc.im-admin").opped? m.user
      return true
    else
      m.reply "#{Format(:bold, "Error:")} you are not authorised to use this command, bitch."
      return false
    end
  end
  
  def do_connect(m, server, user, network, disconnect = false)
    sock = TCPSocket.new($config["zncservers"][server]["addr"], $config["zncservers"][server]["port"].to_i)
    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
    sock = OpenSSL::SSL::SSLSocket.new(sock, ssl_context)
    sock.sync = true
    sock.connect
    sock.puts "NICK bncbot"
    sock.puts "USER bncbot bncbot bncbot :bncbot"
    sock.puts "PASS #{$config["zncservers"][server]["username"]}:#{$config["zncservers"][server]["password"]}"
    if disconnect
      sock.puts "PRIVMSG *controlpanel :disconnect #{user} #{network}"
    else
      sock.puts "PRIVMSG *controlpanel :reconnect #{user} #{network}"
    end
    
    Thread.new do
      Timeout::timeout(10) do
        while line = sock.gets
          if line =~ /^:\*controlpanel!znc@bnc\.im PRIVMSG bncbot :(.+)$/
            m.reply "#{Format(:bold, "[#{server}]")} #{$1}"
          end
        end
      end
    end
    $userdb.update
  end
  
  def do_block(m, server, user, unblock = false)
    sock = TCPSocket.new($config["zncservers"][server]["addr"], $config["zncservers"][server]["port"].to_i)
    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
    sock = OpenSSL::SSL::SSLSocket.new(sock, ssl_context)
    sock.sync = true
    sock.connect
    sock.puts "NICK bncbot"
    sock.puts "USER bncbot bncbot bncbot :bncbot"
    sock.puts "PASS #{$config["zncservers"][server]["username"]}:#{$config["zncservers"][server]["password"]}"
    if unblock
      sock.puts "PRIVMSG *blockuser :unblock #{user}"
      $userdb.servers[server].users[user].blocked = false
    else
      sock.puts "PRIVMSG *blockuser :block #{user}"
      $userdb.servers[server].users[user].blocked = true
    end
    
    Thread.new do
      Timeout::timeout(10) do
        while line = sock.gets
          if line =~ /^:\*blockuser!znc@bnc\.im PRIVMSG bncbot :(.+)$/
            m.reply "#{Format(:bold, "[#{server}]")} #{$1}"
          end
        end
      end
    end
  end
  
  def get_interface_name(ip)
    ips = $config["ips"]
    ips.each do |name, addrs|
      ipv4, ipv6 = addrs["ipv4"], addrs["ipv6"]
      if ipv4.include? ip
        return "#{name}-4-#{ipv4.index(ip)}"
      elsif !ipv6.nil? and ipv6.include? ip 
        return "#{name}-6-#{ipv6.index(ip)}"
      end
    end
    return ip
  end
  
  def silent_update
    $userdb.update
  end
end
