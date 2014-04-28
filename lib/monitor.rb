####
## bnc.im administration bot
##
## Copyright (c) 2014 Andrew Northall
##
## MIT License
## See LICENSE file for details.
####

class MonitorPlugin
  include Cinch::Plugin
  
  listen_to :connect, method: :connect
  listen_to :disconnect, method: :disconnect
  
  def connect(m)
    adminmsg(Format(:bold, :green, "[CONNECTED] ") + @bot.irc.network.name.to_s)
  end
  
  def disconnect(m)
    adminmsg(Format(:bold, :red, "[DISCONNECTED] ") + @bot.irc.network.name.to_s)
  end
  
  def adminmsg(text)
    $adminbot.irc.send("PRIVMSG #bnc.im-admin :#{text}")
  end
end