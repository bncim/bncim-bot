####
## ruby-relay
## relay plugin
##
## Copyright (c) 2013 Andrew Northall
##
## MIT License
## See LICENSE file for details.
####

require 'digest/md5'

class RelayPlugin
  include Cinch::Plugin
  
  listen_to :message, method: :relay
  listen_to :part, method: :relay_part
  listen_to :quit, method: :relay_quit
  listen_to :kick, method: :relay_kick
  listen_to :join, method: :relay_join
  listen_to :nick, method: :relay_nick
  listen_to :join, method: :relay_connect
  listen_to :leaving, method: :relay_disconnect
  
  match "nicks", method: :nicks
	match "channels", method: :channels

	def channels(m)
	  pre_join_strs = Array.new
	  $bots.keys.each do |network|
      pre_join_strs << "#{network}/#bnc.im"
	  end

	  reply = "I am in #{$bots.size} networks/channels: #{pre_join_strs.join(", ")}."
	  m.reply reply
	  sleep 0.1
	  relay_cmd_reply(reply)
	end

  def relay_cmd_reply(text)
		netname = @bot.irc.network.name.to_s.downcase
		network = Format(:bold, "[#{colorise(netname)}]")
		relay_reply = "#{network} <@#{@bot.nick}> #{text}"
    send_relay(relay_reply)
	end

  def relay_connect(m)
    elapsed_time = Time.now.to_i - $start
    return if elapsed_time < 60
    netname = @bot.irc.network.name.to_s.downcase
    return if m.channel.nil?
    return unless m.channel.name.downcase == "#bnc.im"
    return unless m.user.nick == @bot.nick
    network = Format(:bold, "[#{colorise(netname)}]")
    send_relay("#{network} *** Relay joined to #{m.channel.name}")
  end
	  
  def relay_disconnect(m, user)
    return unless user.nick == @bot.nick
    netname = @bot.irc.network.name.to_s.downcase
    network = Format(:bold, "[#{colorise(netname)}]")
    send_relay("#{network} *** Relay parted/disconnected. Attempting to reconnect/rejoin...")
  end
  
  def ignored_nick?(nick)
    if $config["ignore"]["nicks"].include? nick.downcase
      return true
    else
      return false
    end
  end
  
  def relay(m)
    return if m.user.nick == @bot.nick
    if ignored_nick?(m.user.nick.to_s)
      return if $config["ignore"]["ignoreprivmsg"] 
    end
    netname = @bot.irc.network.name.to_s.downcase
    return if m.channel.nil?
    return unless m.channel.name.downcase == "#bnc.im"
    
    network = Format(:bold, "[#{colorise(netname)}]")
    nick = colorise(m.user.nick)
    nick = "-" + nick if $config["bot"]["nohighlights"]
    
    if m.action?
      message = "#{network} * #{nick} #{m.action_message}"
    else
      message = "#{network} <#{nick}> #{m.message}"
    end
    
    send_relay(message)
  end
  
  def relay_nick(m)
    return if $config["bot"]["privmsgonly"]
    return if m.user.nick == @bot.nick
    return if ignored_nick?(m.user.nick.to_s)
    return if ignored_nick?(m.user.last_nick.to_s)
    netname = @bot.irc.network.name.to_s.downcase
    return unless m.user.channels.include? "#bnc.im"
    network = Format(:bold, "[#{colorise(netname)}]")
    message = "#{network} - #{colorise(m.user.last_nick)} is now known as #{colorise(m.user.nick)}"
    send_relay(message)
  end
  
  def relay_part(m)
    return if $config["bot"]["privmsgonly"]
    return if m.user.nick == @bot.nick
    return if ignored_nick?(m.user.nick.to_s)
    netname = @bot.irc.network.name.to_s.downcase
    return if m.channel.nil?
    return unless m.channel.name.downcase == "#bnc.im"
    network = Format(:bold, "[#{colorise(netname)}]")
    if m.message.to_s.downcase == m.channel.name.to_s.downcase
      if $config["bot"]["nohostmasks"]
        message = "#{network} - #{colorise(m.user.nick)} has parted #{m.channel.name}"
      else
        message = "#{network} - #{colorise(m.user.nick)} (#{m.user.mask.to_s.split("!")[1]}) " + \
		            "has parted #{m.channel.name}"
      end
    else
      if $config["bot"]["nohostmasks"]
        message = "#{network} - #{colorise(m.user.nick)} has parted #{m.channel.name} (#{m.message})"
      else
        message = "#{network} - #{colorise(m.user.nick)} (#{m.user.mask.to_s.split("!")[1]}) " + \
		            "has parted #{m.channel.name} (#{m.message})"
      end
    end
    send_relay(message)
  end
  
  def relay_quit(m)
    return if $config["bot"]["privmsgonly"]
    return if ignored_nick?(m.user.nick.to_s)
    return if m.user.nick == @bot.nick
    return if m.user.nick =~ /^bncim\-/i
    netname = @bot.irc.network.name.to_s.downcase
    network = Format(:bold, "[#{colorise(netname)}]")
    message = "#{network} - #{colorise(m.user.nick)} has quit (#{m.message})"
    send_relay(message)
  end
    
  def relay_kick(m)
    return if $config["bot"]["privmsgonly"]
    netname = @bot.irc.network.name.to_s.downcase
    return if m.channel.nil?
    return unless m.channel.name.downcase == "#bnc.im"
    if m.params[1].downcase == @bot.nick.downcase
      Channel("#bnc.im").join
      return
    end
    network = Format(:bold, "[#{colorise(netname)}]")
    if $config["bot"]["nohostmasks"]
      message = "#{network} - #{colorise(m.params[1])} has been kicked from #{m.channel.name} by" + \
                " #{m.user.nick} (#{m.message})"
    else
      message = "#{network} - #{colorise(m.params[1])} (#{User(m.params[1]).mask.to_s.split("!")[1]}) " + \
		            "has been kicked from #{m.channel.name} by #{m.user.nick} (#{m.message})"
    end
    send_relay(message)
  end
  
  def relay_join(m)
    return if $config["bot"]["privmsgonly"]
    return if ignored_nick?(m.user.nick.to_s)
    return if m.user.nick == @bot.nick
    netname = @bot.irc.network.name.to_s.downcase
    return if m.channel.nil?
    return unless m.channel.name.downcase == "#bnc.im"
    network = Format(:bold, "[#{colorise(netname)}]")
    if $config["bot"]["nohostmasks"]
      message = "#{network} - #{colorise(m.user.nick)} has joined #{m.channel.name}"
    else
      message = "#{network} - #{colorise(m.user.nick)} (#{m.user.mask.to_s.split("!")[1]}) " + \
                "has joined #{m.channel.name}"
    end
    send_relay(message)
  end
  
  def nicks(m)
    target = m.user
    total_users = 0
    unique_users = []
    
    $bots.each do |network, bot|
      chan = "#bnc.im"
      users = bot.Channel(chan).users
      users_with_modes = Array.new
      
      users.each do |nick, modes|
        if modes.include?("o")
          users_with_modes << "@" + nick.to_s
        elsif modes.include?("h")
          users_with_modes << "%" + nick.to_s
        elsif modes.include?("v")
          users_with_modes << "+" + nick.to_s
        else
          users_with_modes << nick.to_s
        end
        unique_users << nick unless unique_users.include?(nick)
      end
      
      total_users += users.size
      
      target.notice("#{users.size} users in #{chan} on #{network}: #{users_with_modes.join(", ")}.")
    end
    target.notice("Total users across #{$bots.size} channels: #{total_users}. Unique nicknames: #{unique_users.size}.")
  end
  
  def send_relay(m, adminonly = false)
    $bots.each do |network, bot|
      unless bot.irc.network.name.to_s.downcase == @bot.irc.network.name.to_s.downcase
        begin
          bot.irc.send("PRIVMSG #bnc.im" + \
                       " :#{m}")
        rescue => e
          # pass
        end
      end
    end
  end

	def colorise(text) 
    return text unless $config["bot"]["usecolour"]
    colours = ["\00303", "\00304", "\00305", "\00306",
               "\00307", "\00308", "\00309", "\00310", 
               "\00311", "\00312", "\00313"]

    floathash = Digest::MD5.hexdigest(text.to_s).to_i(16).to_f
    index = floathash % 10
    return "#{colours[index]}#{text}\3"
  end
end
