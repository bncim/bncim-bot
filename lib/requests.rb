####
## bnc.im administration bot
## request lib
##
## Copyright (c) 2013 Andrew Northall
##
## MIT License
## See LICENSE file for details.
####

require 'cinch'
require 'domainatrix'
require 'csv'

class RequestDB
  @@requests = Hash.new

  def self.load(file)
    unless File.exists?(file)
      puts "Error: request db #{file} does not exist. Skipping loading."
      return
    end
    
    CSV.foreach(file) do |row|
      request = Request.new(row[0].to_i, row[3], row[7], row[4], \
                           row[5], row[6], row[1].to_i)
      request.key = row[2]
      request.approved = true if row[8] == "true"
      request.approved = false if row[8] == "false"
      request.confirmed = true if row[9] == "true"
      request.confirmed = false if row[9] == "false"
      request.ircnet = row[10]
      request.reqserver = row[11]
      @@requests[request.id] = request
    end
  end

  def self.save(file)
    file = File.open(file, 'w')
    csv_string = CSV.generate do |csv|
      @@requests.each_value do |r|
        csv << [r.id, r.ts, r.key, r.source, r.email, r.server, \
          r.port, r.username, r.approved?, r.confirmed?, r.ircnet,\
          r.reqserver]
      end
    end
    file.write csv_string
    file.close
  end

  def self.requests
    @@requests
  end

  def self.email_used?(email)
    @@requests.each_value do |request|
      if request.email.downcase == email.downcase
        return true
      else
        next
      end
    end
    return false
  end
  
  def self.ignored?(mask)
    ignored = $config["ignored"]
    ignored.each do |m|
      if Cinch::Mask.new(m) =~ mask
        return true
      end
    end
    return false
  end

  def self.create(*args)
    obj = Request.new(self.next_id, *args)
    @@requests[obj.id] = obj
    RequestDB.save($config["requestdb"])
    @@requests[obj.id]
  end

  def self.next_id
    return 1 if @@requests.empty?
    max_id_request = @@requests.max_by { |k, v| k }
    max_id_request[0] + 1
  end

  def self.gen_key(length = 10)
    ([nil]*length).map { ((48..57).to_a+(65..90).to_a+(97..122).to_a).sample.chr }.join
  end

  def self.confirm(id, confirmed = true)
    @@requests[id].confirmed = confirmed
    RequestDB.save($config["requestdb"])
  end

  def self.approve(id, approved = true)
    @@requests[id].approved = approved
    RequestDB.save($config["requestdb"])
  end
  
  def self.set_requested_server(id, value)
    @@requests[id].reqserver = value
    RequestDB.save($config["requestdb"])
  end

  def self.delete_id(id)
    @@requests.delete id
    RequestDB.save($config["requestdb"])
  end
end

class Request
  attr_reader :id, :username
  attr_accessor :key, :ts, :approved, :confirmed
  attr_accessor :source, :email, :server, :port
  attr_accessor :ircnet, :reqserver

  def initialize(id, source, username, email, server, port, ircnet, ts = nil)
    @id = id
    @ts = ts || Time.now.to_i
    @key = RequestDB.gen_key(20)
    @approved = false
    @confirmed = false
    @source = source
    @username = username
    @ircnet = ircnet
    @email = email
    @server = server
    @port = port
    @reqserver = nil
  end

  def approved?
    @approved
  end

  def confirmed?
    @confirmed
  end
end

class RequestPlugin
  include Cinch::Plugin
  match /request\s+(\w+)\s+(\S+)\s+(\S+)\s+(\+?\d+)$/i, method: :request, group: :request
  match /request\s+(\w+)\s+(\S+)\s+(\S+)\s+(\+?\d+)\s+(\w+)$/i, method: :request, group: :request
  match /request\s+(.+)$/i, method: :detailed_help, group: :request
  match /request/i, method: :help, group: :request
  match /networks/i, method: :servers
  match /web/i, method: :web
  match /verify\s+(\d+)\s+(\S+)/i, method: :verify
  match /servers/i, method: :servers
  
  match "help", method: :help
  
  def detailed_help(m, args)
    split = args.split(" ")
    if split.size >= 4
      unless split[0] =~ /^\w+$/
        m.reply "#{Format(:bold, "Error:")} Please only use alphanumeric characters in your username."
      end
      unless split[1] =~ /@/
        m.reply "#{Format(:bold, "Error:")} The email you have provided is not valid."
      end
      unless split[3] =~ /^\+?\d+$/
        m.reply "#{Format(:bold, "Error:")} Please only use numbers in the port. If you want to use SSL, append + before an SSL port, for example: +6697."
      end
    elsif split.size == 3
      m.reply "#{Format(:bold, "Error:")} Please add a port to your request. If you are unsure, use 6667."
    else
      help(m)
    end
  end
  
  def servers(m)
    return if m.channel == "#bnc.im-admin"
    m.reply "I am connected to the following IRC servers: #{$config["servers"].keys[0..-2].join(", ")} and #{$config["servers"].keys[-1]}."
    m.reply "I am connected to the following bnc.im servers: #{$config["zncservers"].keys[0..-2].join(", ")} and #{$config["zncservers"].keys[-1]}."
  end
  
  def request(m, username, email, server, port, reqserver = nil)
    return if RequestDB.ignored?(m.user.mask)
    if RequestDB.email_used?(email)
      m.reply "Sorry, that email has already been used. Please contact an " + \
              "operator if you need help."
      return
    end
    
    unless $userdb.username_available?(username)
      m.reply "Error: that username has already been used. Please try another, or " + \
              "contact an operator for help."
      return
    end
    
    unless reqserver.nil?
      unless $config["zncservers"].keys.include? reqserver.downcase
        m.reply "Error: #{reqserver} is not a valid bnc.im server. " + \
                "Please pick from: #{$config["zncservers"].keys.join(", ")}"
        return
      end
    end

    $config["blacklist"].each do |entry, reason|
      if server =~ /#{entry}/i
        if reason.nil?
          m.reply "Error: the server #{server} appears to be on our " + \
                  "network blacklist. Please see http://bnc.im/blacklist" + \
                  " or contact an operator for more details."
          return
        else
          m.reply "Error: #{reason}"
          return
        end
      end
    end

    unless email.include? "@"
      m.reply "Error: that email is not valid."
      return
    end
    
    r = RequestDB.create(m.user.mask, username, email, server,\
                         port, @bot.irc.network.name)
                         
    RequestDB.set_requested_server(r.id, reqserver) unless reqserver.nil?

    Mail.send_verify(r.email, r.id, r.key)
                               
    m.reply "Your request (##{r.id}) has been submitted. Please check your " + \
            "email for information on how to proceed."

    adminmsg("Request ##{r.id} created and pending email verification.")
  end

  def verify(m, id, key)
    unless RequestDB.requests.has_key?(id.to_i)
      m.reply "Error: request ##{id} not found. Please contact an operator if you need assistance."
      return
    end
    
    r = RequestDB.requests[id.to_i]
    
    unless r.key == key
      m.reply "Error: code does not match. Please contact an operator for assistance."
      return
    end

    if r.confirmed?
      m.reply "Error: request already confirmed."
      return
    end

    RequestDB.confirm(r.id)
    r = RequestDB.requests[r.id]

    m.reply "Request ##{r.id} confirmed! Your request is now pending administrative approval. " + \
      "You will receive an email with further details when it is approved. Thanks for using bnc.im."

    $config["notifymail"].each do |email|
      Mail.request_waiting(email, r)
    end
    adminmsg("#{Format(:red, "[NEW REQUEST]")} #{format_status(r)}")
    
    if r.port == "+6667" or r.port == "6697" 
      adminmsg("#{Format(:bold, "Warning:")} Port selected by the user is #{r.port}.")
    end
  end  
  
  def help(m)
    return if m.channel == "#bnc.im-admin"
    m.reply "#{Format(:bold, "Syntax: !request <user> <email> <server> <port>")}. A + before the port denotes SSL. This command can be issued in a private message. Please use a valid email, it is verified. If you already have an account and wish to add a new network, use !report."
    m.reply Format(:bold, "Example: !request george george@mail.com irc.freenode.net +6697")
  end

  def web(m)
    m.reply "http://bnc.im"
  end

  def adminmsg(text)
    $adminbot.irc.send("PRIVMSG #bnc.im-admin :#{text}")
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
end
