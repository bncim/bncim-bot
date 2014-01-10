class AdminPlugin
  include Cinch::Plugin
  match /ban (\S+)/, method: :ban
  match /unban (\S+)/, method: :unban
  match /kick (\S+) (.+)$/, method: :kick
  match /topic (.+)/, method: :topic
  match /approve\s+(\d+)\s+(\S+)\s*$/, method: :approve, group: :approve
  match /approve\s+(\d+)\s+(\S+)\s+(.+)\s*$/, method: :approve, group: :approve
  match /delete\s+(\d+)/, method: :delete
  match /reqinfo\s+(\d+)/, method: :reqinfo
  match /requser\s+(\S+)/, method: :requser
  match "pending", method: :pending
  match "unconfirmed", method: :unconfirmed
  match /fverify\s+(\d+)/, method: :fverify
  match "servers", method: :servers
  match /broadcast (.+)/, method: :broadcast
  match /serverbroadcast (\w+) (.+)/, method: :serverbroadcast
  match /cp (\w+) (.+)/, method: :cp
  match /addnetwork\s+(\w+)\s+(\w+)\s+(\w+)\s+(.+)\s*$/, method: :addnetwork
  match /delnetwork\s+(\w+)\s+(\w+)\s+(\w+)\s*$/, method: :delnetwork
  
  match "help", method: :help
  
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
    unless $zncs.has_key?
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
    $zncs[server].irc.send("PRIVMSG *controlpanel :#{command}")
    m.reply "done!"
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
  end
  
  def msg_to_control(msg)
    "PRIVMSG *controlpanel :#{msg}"
  end
  
  def help(m)
    if m.channel == "#bnc.im-admin"
      m.reply "Admin commands:"
      m.reply "!unconfirmed | !pending | !reqinfo <id> | !delete <id> | !fverify <id> | !servers | !approve <id> <ip> | !serverbroadcast <server> <text> | !broadcast <text> | !kick <user> <reason> | !ban <mask>"
      m.reply "!addnetwork <server> <username> <netname> <addr> <port> | !delnetwork <server> <username> <netname>"
    end
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
