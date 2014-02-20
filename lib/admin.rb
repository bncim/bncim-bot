require 'socket'
require 'openssl'
require 'timeout'

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
  match /approve\s+(\d+)\s+(\S+)\s+(.+)\s*$/, method: :approve, group: :approve
  match /reject\s+(\d+)\s+(.+)\s*$/, method: :reject
  match /delete\s+(\d+)/, method: :delete
  match /reqinfo\s+(\d+)/, method: :reqinfo
  match /requser\s+(\S+)/, method: :requser
  match "pending", method: :pending
  match "unconfirmed", method: :unconfirmed
  match "reports", method: :reports
  match "todo", method: :todo
  match /fverify\s+(\d+)/, method: :fverify
  match "servers", method: :servers
  match /broadcast (.+)/, method: :broadcast
  match /serverbroadcast (\w+) (.+)/, method: :serverbroadcast
  match /cp (\w+) (.+)/, method: :cp
  match /addnetwork\s+(\w+)\s+(\w+)\s+(\w+)\s+(.+)\s*$/, method: :addnetwork
  match /delnetwork\s+(\w+)\s+(\w+)\s+(\w+)\s*$/, method: :delnetwork
  match "stats", method: :stats
  match /find (\S+)$/, method: :find, group: :find
  match /find (\S+) ([a-z]{3}\d)/, method: :find, group: :find
  match /findnet (\S+)$/, method: :findnet, group: :findnet
  match /findnet (\S+) ([a-z]{3}\d)/, method: :findnet, group: :findnet
  match "offline", method: :offline
  match /netcount (\S+)/, method: :netcount
  match /crawl (\S+) (\+?\d+)/, method: :crawl
  
  match "help", method: :help
  
  def help(m)
    if m.channel == "#bnc.im-admin"
      m.reply "Admin commands:"
      m.reply "!unconfirmed | !pending | !reqinfo <id> | !delete <id> | !fverify <id> | !servers | !approve <id> <ip> | !serverbroadcast <server> <text> | !broadcast <text> | !kick <user> <reason> | !ban <mask> | !unban <mask>"
      m.reply "!addnetwork <server> <username> <netname> <addr> <port> | !delnetwork <server> <username> <netname> | !approve <id> <ip> [irc server] [irc port] | !todo | !reports | !clear <reportid> [message] | !offline"
      m.reply "!find <user regexp> | !findnet <regexp> | !crawl <server> <port> | !netcount <regexp> | !stats"
    end
  end
  
  
  def crawl(m, server, port)
    return unless m.channel == "#bnc.im-admin"
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
    return unless m.channel == "#bnc.im-admin"
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
    return unless m.channel == "#bnc.im-admin"
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
    m.reply Format(:bold, " Server  Username        Network           Userhost                                                    BindHost")
    results.each do |user, network|
      m.reply " " + user.server.ljust(8) + user.username.ljust(16) + Format(:red, network.name.ljust(90)) + network.bindhost 
    end
    m.reply Format(:bold, " End of list.")
  end
  
  def findnet(m, str, specserver = nil)
    return unless m.channel == "#bnc.im-admin"
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
    
    m.reply Format(:bold, " Server  Username        Network           Userhost                                                    BindHost")
    results.each do |user, network|
      if network.online
        m.reply " " + user.server.ljust(8) + user.username.ljust(16) + Format(:green, network.name.ljust(18)) + network.user.ljust(60) + network.bindhost
      else
        m.reply " " + user.server.ljust(8) + user.username.ljust(16) + Format(:red, network.name.ljust(90)) + network.bindhost
      end
    end
    m.reply Format(:bold, " End of list.")
  end
  
  def find(m, search_str, specserver = nil)
    return unless m.channel == "#bnc.im-admin"
    results = $userdb.find_user(search_str, specserver)
    
    if results.nil?
      m.reply "No results."
      return
    elsif results.size > 50
      m.reply "#{Format(:bold, "Error:")} more than 50 results. Please be more specific."
      return
    end
    
    m.reply Format(:bold, " Server  Username        Network           Userhost                                                    BindHost")
    results.each do |user|
      m.reply " " + user.server.ljust(8) + user.username
      user.networks.each do |network|
        if network.online
          m.reply " " + user.server.ljust(8) + user.username.ljust(16) + Format(:green, network.name.ljust(18)) + network.user.ljust(60) + network.bindhost
        else
          m.reply " " + user.server.ljust(8) + user.username.ljust(16) + Format(:red, network.name.ljust(90)) + network.bindhost
        end
      end
    end
    m.reply Format(:bold, " End of list.")
  end
  
  def stats(m)
    return unless m.channel == "#bnc.im-admin"
    m.reply "[Stats] Total users: #{$userdb.users_count} | Total networks: #{$userdb.networks_count}"
    servers = []
    $userdb.servers.each do |name, server|
      servers << "#{name}: #{server.users_count}/#{server.networks_count}"
    end
    m.reply "[Stats] #{servers.join(" | ")}"
  end
  
  def addnetwork(m, server, username, netname, addrstr)
    return unless m.channel == "#bnc.im-admin"
    server.downcase!
    netname.downcase!
    unless $zncs.has_key? server
      m.reply "Server \"#{server}\" not found."
      return
    end
    $zncs[server].irc.send(msg_to_control("AddNetwork #{username} #{netname}"))
    $zncs[server].irc.send(msg_to_control("AddServer #{username} #{netname} #{addrstr}"))
    if $config["servers"].has_key? netname
      $zncs[server].irc.send(msg_to_control("AddChan #{username} #{netname} #{$config["servers"][netname]["channel"]}"))
    end
    m.reply "done."
  end
  
  def delnetwork(m, server, username, netname)
    return unless m.channel == "#bnc.im-admin"
    server.downcase!
    netname.downcase!
    unless $zncs.has_key? server
      m.reply "Server \"#{server}\" not found."
      return
    end
    $zncs[server].irc.send(msg_to_control("DelNetwork #{username} #{netname}"))
    m.reply "done!"
  end

  def topic(m, topic)
    return unless m.channel == "#bnc.im-admin"
    command = "TOPIC"
    if topic.split(" ")[0] == "--append"
      command = "TOPICAPPEND"
      topic = topic.split(" ")[1..-1].join(" ")
    elsif topic.split(" ")[0] == "--prepend"
      command = "TOPICPREPEND"
      topic = topic.split(" ")[1..-1].join(" ")
    end
    $bots.each_value do |bot|
      bot.irc.send("PRIVMSG ChanServ :#{command} #bnc.im #{topic}")
    end
    m.reply "done!"
  end
  
  def broadcast(m, text)
    return unless m.channel == "#bnc.im-admin"
    $bots.each_value do |bot|
      bot.irc.send("PRIVMSG #bnc.im :#{Format(:bold, "[BROADCAST]")} #{text}")
    end
    
    $zncs.each_value do |zncbot|
      zncbot.irc.send("PRIVMSG *status :broadcast [Broadcast Message] #{text}")
    end
    m.reply "done!"
  end
  
  def serverbroadcast(m, server, text)
    return unless m.channel == "#bnc.im-admin"
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
    return unless m.channel == "#bnc.im-admin"
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
    return unless m.channel == "#bnc.im-admin"
    $bots.each_value { |b| b.irc.send("MODE #bnc.im +b #{target}") }
    m.reply "done!"
  end

  def unban(m, target)
    return unless m.channel == "#bnc.im-admin"
    $bots.each_value { |b| b.irc.send("MODE #bnc.im -b #{target}") }
    m.reply "done!"
  end

  def kick(m, target, reason = "")
    return unless m.channel == "#bnc.im-admin"
    $bots.each_value { |b| b.irc.send("KICK #bnc.im #{target} :#{reason}") }
    m.reply "kicked #{target} in all channels (#{reason})"
  end
  
  def approve(m, id, ip, addr = nil)
    return unless m.channel == "#bnc.im-admin"
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
    
    server = find_server_by_ip(ip)
    
    if server.nil?
      m.reply "Error: #{ip} is not a valid IP address."
      return
    end
    
    password = RequestDB.gen_key(15)
    netname = Domainatrix.parse(r.server).domain
    netname = Domainatrix.parse(addr.split(" ")[0]).domain unless addr.nil?
        
    $zncs[server].irc.send(msg_to_control("CloneUser templateuser #{r.username}"))
    $zncs[server].irc.send(msg_to_control("Set Nick #{r.username} #{r.username}"))
    $zncs[server].irc.send(msg_to_control("Set AltNick #{r.username} #{r.username}_"))
    $zncs[server].irc.send(msg_to_control("Set Ident #{r.username} #{r.username}"))
    $zncs[server].irc.send(msg_to_control("Set BindHost #{r.username} #{ip}"))
    $zncs[server].irc.send(msg_to_control("Set DCCBindHost #{r.username} #{ip}"))
    $zncs[server].irc.send(msg_to_control("Set DenySetBindHost #{r.username} true"))
    $zncs[server].irc.send(msg_to_control("Set Password #{r.username} #{password}"))
    
    Thread.new do
      sleep 3
      $zncs[server].irc.send(msg_to_control("AddNetwork #{r.username} #{netname}"))
      if addr.nil?
        $zncs[server].irc.send(msg_to_control("AddServer #{r.username} #{netname} #{r.server} #{r.port}"))
      else
        $zncs[server].irc.send(msg_to_control("AddServer #{r.username} #{netname} #{addr}"))
      end
      $zncs[server].irc.send(msg_to_control("SetNetwork Nick #{r.username} #{netname} #{r.username}"))
      if $config["servers"].has_key? netname.downcase
        $zncs[server].irc.send(msg_to_control("AddChan #{r.username} #{netname} #{$config["servers"][netname.downcase]["channel"]}"))
      end
    end
    
    RequestDB.approve(r.id)
    Mail.send_approved(r.email, server, r.username, password, netname)
    $config["notifymail"].each do |email|
      Mail.send_approved_admin(email, r.id, m.user.mask.to_s)
    end
    adminmsg("Request ##{id} approved to #{server} (#{ip}) by #{m.user}.")
    $bots.each do |network, bot|
      begin
        bot.irc.send("PRIVMSG #{$config["servers"][network]["channel"]}" + \
                     " :Request ##{id} (for #{r.source}) has been approved by #{m.user.nick}.")
      rescue => e
        # pass
      end
    end
  end
  
  def reject(m, id, reason)
    return unless m.channel == "#bnc.im-admin"
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
        bot.irc.send("PRIVMSG #{$config["servers"][network]["channel"]}" + \
                     " :Request ##{id} (for #{r.source}) has been rejected by #{m.user.nick}. Reason: #{reason}.")
      rescue => e
        # pass
      end
    end
    adminmsg("Request ##{id} (for #{r.source}) has been rejected by #{m.user.nick}. Reason: #{reason}.")
    Mail.send_reject(r.email, id, reason)
    $config["notifymail"].each do |email|
      Mail.send_rejected_admin(email, r.id, m.user.mask.to_s)
    end
    RequestDB.delete_id(r.id)
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
  
  def servers(m)
    if m.channel == "#bnc.im-admin"
      ips = $config["ips"]
      ips.each do |name, addrs|
        ipv4 = addrs["ipv4"]
        ipv6 = addrs["ipv6"]
        m.reply "#{Format(:bold, "[#{name}]")} #{Format(:bold, "IPv4:")} " + \
                "#{ipv4.join(", ")}. #{Format(:bold, "IPv6:")} #{ipv6.join(", ")}."
      end
    end
  end
  
  def fverify(m, id)
    return unless m.channel == "#bnc.im-admin"
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
    return unless m.channel == "#bnc.im-admin"
    
    RequestDB.requests.each do |key, req|
      if req.username.to_s.downcase == username.downcase
        m.reply format_status(req)
      end
    end
    m.reply "End of results."
  end
  
  def reqinfo(m, id)
    return unless m.channel == "#bnc.im-admin"
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
    return unless m.channel == "#bnc.im-admin"
    unless RequestDB.requests.has_key?(id.to_i)
      m.reply "Error: request ##{id} not found."
      return
    end
    
    RequestDB.delete_id id.to_i
    m.reply "Deleted request ##{id}."
  end

  def allmsg(m)
    $bots.each do |network, bot|
      begin
        bot.irc.send("PRIVMSG #bnc.im :#{m}")
      rescue => e
        # pass
      end
    end
  end
  
  def pending(m)
    return unless m.channel == "#bnc.im-admin"
    
    pending = Array.new
    RequestDB.requests.each_value do |r|
      if r.confirmed?
        pending << r unless r.approved?
      end
    end
    
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
    return unless m.channel == "#bnc.im-admin"
    
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
  
  def todo(m)
    reports(m)
    pending(m)
  end
  
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
  
  def unconfirmed(m)
    return unless m.channel == "#bnc.im-admin"
    
    unconfirmed = Array.new
    RequestDB.requests.each_value do |r|
      unless r.confirmed?
        unconfirmed << r unless r.approved?
      end
    end
    
    if unconfirmed.empty?
      m.reply "No unconfirmed requests. Try !pending?"
      return
    end
    
    m.reply "#{unconfirmed.size} unconfirmed request(s):"
    
    unconfirmed.each do |request|
      m.reply format_status(request)
    end
  end
  
  def format_status(r)
    "%s Source: %s on %s / Username: %s / Email: %s / Date: %s / Server: %s / Port: %s / Requested Server: %s / Confirmed: %s / Approved: %s" %
      [Format(:bold, "[##{r.id}]"), Format(:bold, r.source.to_s), 
       Format(:bold, r.ircnet.to_s), Format(:bold, r.username.to_s),
       Format(:bold, r.email.to_s), Format(:bold, Time.at(r.ts).ctime),
       Format(:bold, r.server), Format(:bold, r.port.to_s),
       Format(:bold, "#{r.reqserver || "N/A"}"), 
       Format(:bold, r.confirmed?.to_s), Format(:bold, r.approved?.to_s)]
  end
  
  def adminmsg(text)
    $adminbot.irc.send("PRIVMSG #bnc.im-admin :#{text}")
  end
end
