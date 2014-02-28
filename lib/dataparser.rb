require 'socket'
require 'openssl'

class AdminMsg
  def self.do(msg)
    begin
      $adminbot.irc.send("PRIVMSG #bnc.im-admin :#{msg}")
    rescue => e
      #
    end
  end
end

class LogPlugin
  include Cinch::Plugin
  
  listen_to :message, method: :check_log
  
  def check_log(m)
    return unless m.channel == "#bnc.im-log"
    if m.user.nick =~ /^bncim\-(\w{3}\d)$/
      server = $1
      if m.message =~ /^\[(\d{4}\-\d{2}\-\d{2} \d{2}:\d{2}:\d{2})\] (.+)$/
        timestamp = $1
        if $2 =~ /^\[(\S+)\] disconnected from ZNC from (\S+)$/
          $userdb.servers[server].users[$1].last_seen = Time.now.to_i
        elsif $2 =~ /^\[(\S+)\] connected to ZNC from (\S+)$/
          $userdb.servers[server].users[$1].last_seen = Time.now.to_i
        end
      end
    end
  end
end

module ZNC
  class User 
    attr_reader :username, :server
    attr_accessor :networks, :last_seen
  
    def initialize(username, server)
      @username, @server = username, server
      @networks = Array.new
      @last_seen = nil
    end
    
    def to_s
      @username
    end
    
    def last_seen_str
      if @last_seen == nil
        return "unknown, check webadmin"
      else
        return Time.at(@last_seen).ctime
      end
    end
  end
  
  class Server
    attr_reader :name, :addr, :port, :username, :password
    attr_accessor :users
    
    def initialize(name, addr, port, username, password)
      @name = name
      @addr = addr
      @port = port
      @username = username
      @password = password
      @users = Hash.new
    end
    
    def users_count
      @users.size
    end
    
    def networks_count
      networks = 0
      @users.each do |username, user|
        networks += user.networks.size
      end
      return networks
    end
    
    def to_s
      @name
    end
  end

  class UserNetwork
    attr_reader :name
    attr_accessor :online, :server, :user, :channels, :bindhost
  
    def initialize(name, user, online, server, channels)
      @name, @user, @online, @server = name, user, online, server
      @channels = channels
      @bindhost = nil
    end
    
    def to_s
      @name
    end
  end

  class UserNetworksParser
    def self.parse(server, lines)
      users = Hash.new
    
      # username, network, clients, onirc, irc server, irc user, channel count
      while line = lines.shift
        if line =~ /^\+\-+/ # table header
          next
        elsif line =~ /^\| Username/ # header
          next
        elsif line =~ /^\| (\w+)\s+\| N\/A/ # new user
          u = User.new($1, server)
          while line = lines.shift
            if line =~ /^\| \|\-\s+\| (\S+)\s+\| (\d+)\s+\| Yes\s+\| (\S+)\s+\| (\S+)\s+\| (\d+)\s+\|\s*(\S+|)\s*\|?\s*$/
              net = UserNetwork.new($1, $4, true, $3, $5)
              net.bindhost = $6 unless $6 == ""
              u.networks << net
            elsif line =~ /^\| \`\-\s+\| (\S+)\s+\| (\d+)\s+\| Yes\s+\| (\S+)\s+\| (\S+)\s+\| (\d+)\s+\|\s*(\S+|)\s*\|?\s*$/
              net = UserNetwork.new($1, $4, true, $3, $5)
              net.bindhost = $6 unless $6 == ""
              u.networks << net
              break
            elsif line =~ /^\| \|\-\s+\| (\S+)\s+\| (\d+)\s+\| No\s+\|\s+\|\s+\|\s+\|\s*(\S+|)\s*\|?\s*$/
              net = UserNetwork.new($1, nil, false, nil, 0)
              net.bindhost = $3 unless $3 == ""
              u.networks << net
            elsif line =~ /^\| \`\-\s+\| (\S+)\s+\| (\d+)\s+\| No\s+\|\s+\|\s+\|\s+\|\s*(\S+|)\s*\|?\s*$/
              net = UserNetwork.new($1, nil, false, nil, 0)
              net.bindhost = $3 unless $3 == ""
              u.networks << net
              break
            elsif line =~ /^\| \w+/
              lines.unshift line
              break
            end
          end
          users[u.username] = u
        end
      end
      return users
    end
  end
  
  class UserDB
    attr_reader :servers
    
    def initialize(servers)
      @servers = servers
      Thread.new { update_data(true) }
    end
    
    def username_available?(username)
      username.downcase!
      found = false
      @servers.each do |name, server|
        usernames = server.users.keys.map { |x| x.downcase }
        found = true if usernames.include? username
      end
      if found == true
        return false
      else
        return true
      end
    end
    
    def find_user(search, specserver = nil)
      results = []
      @servers.each do |name, server|
        server.users.each do |name, user|
          if user.username =~ /#{search}/i
            if specserver.nil?
              results << user
            else
              results << user if name.downcase == specserver.downcase
            end
          end
        end
      end
      if results.empty?
        return nil
      else
        return results
      end
    end
    
    def users_count
      users = 0
      @servers.each do |name, server|
        users += server.users.size
      end
      return users
    end
    
    def networks_count
      networks = 0
      @servers.each do |name, server|
        server.users.each do |username, user|
          networks += user.networks.size
        end
      end
      return networks
    end
    
    def update
      update_data()
    end
    
    private
    
    def init_sock(user, pass, addr, port)
      sock = TCPSocket.new(addr, port)
      ssl_context = OpenSSL::SSL::SSLContext.new
      ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
      sock = OpenSSL::SSL::SSLSocket.new(sock, ssl_context)
      sock.sync = true
      sock.connect
      sock.puts "NICK bncbot"
      sock.puts "USER bncbot bncbot bncbot :bncbot"
      sock.puts "PASS #{user}:#{pass}"
      sock.puts "PRIVMSG *status LISTALLUSERNETWORKS"
      return sock
    end
    
    def update_data(doloop = false)
      @servers.each do |name, server|
        begin
          sock = init_sock(server.username, server.password, server.addr, server.port)
        
          lines = Array.new
        
          while line = sock.gets
            if line =~ /^:\*status!znc@bnc.im PRIVMSG bncbot :(\+\-+.+)/
              lines << $1
              while line = sock.gets
                c = 0
                if line =~ /^:\*status!znc@bnc.im PRIVMSG bncbot :(\|.+)/
                  lines << $1
                elsif line =~ /^:\*status!znc@bnc.im PRIVMSG bncbot :(\+\-+.+)/
                  lines << $1
                  if lines.size > 3
                    break
                  end
                end
              end
              break
            end
          end        
          sock.close
          users = UserNetworksParser.parse(server.name, lines)
        
          @servers[server.name].users = users
        rescue => e
          puts "Could not update server: #{name}."
          next
        end
      end
      if doloop
        sleep 30
        update_data
      end
    end
  end
end