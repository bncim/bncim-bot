#!/usr/bin/env ruby
####
## bnc.im administration bot
##
## Copyright (c) 2013 Andrew Northall
##
## MIT License
## See LICENSE file for details.
####

$:.unshift File.dirname(__FILE__)

require 'cinch'
require 'cinch/plugins/identify'
require 'yaml'
require 'lib/requests'
require 'lib/reports'
require 'lib/admin'
require 'lib/relay'
require 'lib/logger'
require 'lib/mail'
require 'lib/dataparser'

$config = YAML.load_file("config/config.yaml")
$bots = Hash.new
$zncs = Hash.new
$threads = Array.new
$start = Time.now.to_i

# Set up a bot for each server
$config["servers"].each do |name, server|
  bot = Cinch::Bot.new do
    configure do |c|
      c.nick = $config["bot"]["nick"]
      c.user = $config["bot"]["user"]
      c.realname = $config["bot"]["realname"]
      c.server = server["server"]
      c.ssl.use = server["ssl"]
      c.port = server["port"]
      c.channels = $config["bot"]["channels"].dup
      c.plugins.plugins = [RequestPlugin, RelayPlugin, ReportPlugin]
      if $config["admin"]["network"] == name
        c.channels = $config["bot"]["channels"].dup + [$config["admin"]["channel"], "#bnc.im-log"]
        c.messages_per_second = 20
        c.plugins.plugins << AdminPlugin
        c.plugins.plugins << LogPlugin
      end
      if name =~ /^quakenet$/i
        c.plugins.plugins << Cinch::Plugins::Identify
        c.plugins.options[Cinch::Plugins::Identify] = {
          :username => $config["bot"]["saslname"],
          :password => server["qpass"],
          :type     => :challengeauth,
        }
      elsif server["sasl"]
        c.sasl.username = $config["bot"]["saslname"]
        c.sasl.password = $config["bot"]["saslpass"]
      else
        c.plugins.plugins << Cinch::Plugins::Identify
        c.plugins.options[Cinch::Plugins::Identify] = {
          :password => $config["bot"]["saslpass"],
          :type     => :nickserv,
        }
      end
    end
  end
  bot.loggers.clear
  bot.loggers << BNCLogger.new(name, File.open("log/irc-#{name}.log", "a"))
  bot.loggers << BNCLogger.new(name, STDOUT)
  bot.loggers.level = :info
  if $config["admin"]["network"] == name
    $adminbot = bot
  end
  $bots[name] = bot
end

# Set up the ZNC bots
$config["zncservers"].each do |name, server|
	bot = Cinch::Bot.new do
		configure do |c|
			c.nick = "bncbot"
			c.server = server["addr"]
			c.ssl.use = server["ssl"]
			c.password = server["username"] + ":" + server["password"]
			c.port = server["port"]
		end
	end
  bot.loggers.clear
	bot.loggers << BNCLogger.new(name, File.open("log/znc-#{name}.log", "a"))
	bot.loggers << BNCLogger.new(name, STDOUT)
	bot.loggers.level = :info
	$zncs[name] = bot
end

# Initialize the RequestDB
RequestDB.load($config["requestdb"])
ReportDB.load($config["reportdb"])

# Initialize UserDB
servers = {}
$config["zncservers"].each do |name, server|
  servers[name] = ZNC::Server.new(name, server["addr"], server["port"], server["username"], server["password"])
end

$userdb = ZNC::UserDB.new(servers)

# Start the bots

$zncs.each do |key, bot|
	$threads << Thread.new { bot.start }
end

$bots.each do |key, bot|
  $threads << Thread.new { bot.start }
end

sleep 5

$threads.each { |t| t.join } # wait for other threads
