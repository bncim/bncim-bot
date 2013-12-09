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
  listen_to :mode, method: :relay_mode
  
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
    return unless m.channel.name.downcase == $config["servers"][netname]["channel"].downcase
    
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
  
  def relay_mode(m)
    return if m.params.nil?
    return if @bot.irc.network.name.nil? #not connected yet
    netname = @bot.irc.network.name.to_s.downcase
    return unless m.params[0].downcase == $config["servers"][netname]["channel"].downcase
    if m.user.nil?
      user = m.raw.split(":")[1].split[0]
    else
      return if ignored_nick?(m.user.nick.to_s)
      m.user.refresh
      user = "#{colorise(m.user.nick)} (#{m.user.mask.to_s.split("!")[1]})"
    end
    network = Format(:bold, "[#{colorise(netname)}]")
    message = "#{network} - #{user} set mode #{m.params[1..-1].join(" ")} on #{m.params[0]}."
    send_relay(message)
  end
  
  def relay_nick(m)
    return if m.user.nick == @bot.nick
    return if ignored_nick?(m.user.nick.to_s)
    return if ignored_nick?(m.user.last_nick.to_s)
    netname = @bot.irc.network.name.to_s.downcase
    return unless m.user.channels.include? $config["servers"][netname]["channel"]
    network = Format(:bold, "[#{colorise(netname)}]")
    message = "#{network} - #{colorise(m.user.last_nick)} (#{m.user.mask.to_s.split("!")[1]}) " + \
              "is now known as #{colorise(m.user.nick)}."
    send_relay(message)
  end
  
  def relay_part(m)
    return if m.user.nick == @bot.nick
    return if ignored_nick?(m.user.nick.to_s)
    netname = @bot.irc.network.name.to_s.downcase
    return unless m.channel.name.downcase == $config["servers"][netname]["channel"].downcase
    network = Format(:bold, "[#{colorise(netname)}]")
    m.user.refresh
    if m.message.to_s.downcase == m.channel.name.to_s.downcase
      message = "#{network} - #{colorise(m.user.nick)} (#{m.user.mask.to_s.split("!")[1]}) " + \
		            "has parted #{m.channel.name}"
    else
      message = "#{network} - #{colorise(m.user.nick)} (#{m.user.mask.to_s.split("!")[1]}) " + \
		            "has parted #{m.channel.name} (#{m.message})"
    end
    send_relay(message)
  end
  
  def relay_quit(m)
    return if ignored_nick?(m.user.nick.to_s)
    return if m.user.nick == @bot.nick
    netname = @bot.irc.network.name.to_s.downcase
    network = Format(:bold, "[#{colorise(netname)}]")
    message = "#{network} - #{colorise(m.user.nick)} has quit (#{m.message})"
    send_relay(message)
  end
    
  def relay_kick(m)
    netname = @bot.irc.network.name.to_s.downcase
    return unless m.channel.name.downcase == $config["servers"][netname]["channel"].downcase
    if m.params[1].downcase == @bot.nick.downcase
      Channel($config["servers"][netname]["channel"]).join
      return
    end
    network = Format(:bold, "[#{colorise(netname)}]")
    message = "#{network} - #{colorise(m.params[1])} (#{User(m.params[1]).mask.to_s.split("!")[1]}) " + \
		          "has been kicked from #{m.channel.name} by #{m.user.nick} (#{m.message})"
    send_relay(message)
  end
  
  def relay_join(m)
    return if ignored_nick?(m.user.nick.to_s)
    return if m.user.nick == @bot.nick
    netname = @bot.irc.network.name.to_s.downcase
    return unless m.channel.name.downcase == $config["servers"][netname]["channel"].downcase
    network = Format(:bold, "[#{colorise(netname)}]")
    m.user.refresh
    message = "#{network} - #{colorise(m.user.nick)} (#{m.user.mask.to_s.split("!")[1]}) " + \
              "has joined #{m.channel.name}"
    send_relay(message)
  end
  
  def send_relay(m)
    $bots.each do |network, bot|
      unless bot.irc.network.name.to_s.downcase == @bot.irc.network.name.to_s.downcase
        begin
          bot.irc.send("PRIVMSG #{$config["servers"][network]["channel"]}" + \
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
