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
require 'lib/notes'
require 'lib/dataparser'
require 'lib/network'
require 'lib/monitor'

$config = YAML.load_file("config/config.yaml")
$bots = Hash.new
$zncs = Hash.new
$threads = Array.new
$start = Time.now.to_i

# Set up a bot for each server
$config["servers"].each do |name|
  bot = Cinch::Bot.new do
    configure do |c|
      c.nick = $config["bot"]["nick"]
      c.server = $config["bot"]["zncaddr"]
      c.port = $config["bot"]["zncport"]
      c.password = "bncbot/#{name}:#{$config["bot"]["zncpass"]}"
      c.ssl.use = true
      c.plugins.plugins = [RequestPlugin, RelayPlugin, ReportPlugin]
      if $config["adminnet"] == name
        c.messages_per_second = 20
        c.plugins.plugins << AdminPlugin
        c.plugins.plugins << NotePlugin
      end
    end
  end
  bot.loggers.clear
  bot.loggers << BNCLogger.new(name, File.open("log/irc-#{name}.log", "a"))
  bot.loggers << BNCLogger.new(name, STDOUT)
  bot.loggers.level = :error
  if $config["adminnet"] == name
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
      c.max_reconnect_delay = 15
      c.plugins.plugins = [MonitorPlugin]
		end
	end
  bot.loggers.clear
	bot.loggers << BNCLogger.new(name, File.open("log/znc-#{name}.log", "a"))
	bot.loggers << BNCLogger.new(name, STDOUT)
	bot.loggers.level = :error
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
$notedb = NoteDB.new($config["notedb"])
$netnotedb = NoteDB.new($config["netnotedb"])

puts "Initialization complete. Connecting to IRC and ZNC..."

# Start the bots

$zncs.each do |key, bot|
  puts "Starting ZNC connection for #{key}.bnc.im..."
	$threads << Thread.new { bot.start }
end

$bots.each do |key, bot|
  puts "Starting IRC connection for #{key}..."
  $threads << Thread.new { bot.start }
end

puts "Connected!"

sleep 5

$threads.each { |t| t.join } # wait for other threads
