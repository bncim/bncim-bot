require 'socket'
require 'openssl'

module ZNC
  class User 
    attr_reader :username, :server
    attr_accessor :networks, :blocked
  
    def initialize(username, server)
      @username, @server = username, server
      @networks = Array.new
      @blocked = false
    end
    
    def blocked?
      @blocked
    end
    
    def to_s
      @username
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
    
    def blocked_users
      @users.select { |k, u| u.blocked? }
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
    attr_reader :servers, :updated
    
    def initialize(servers)
      @servers = servers
      @updated = nil
      Thread.new { update_data() }
    end
    
    def username_available?(username)
      username.downcase!
      found = false
      @servers.each do |name, server|
        usernames = server.users.keys.map { |x| x.downcase }
        found = true if usernames.include? username
      end
      RequestDB.requests.each do |key, req|
        if req.status >= 0 and req.username.downcase == username
          found = true
        end
      end
      
      if found == true
        return false
      else
        return true
      end
    end
    
    def bindhost_user_count(bindhost)
      result = 0
      bindhost.downcase!
      @servers.each do |sname, server|
        server.users.each do |uname, user|
          user.networks.each do |network|
            if network.bindhost.downcase == bindhost
              result += 1
            end
          end
        end
      end
      return result
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
    
    def update_data()
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
          sock.puts "PRIVMSG *blockuser LIST"
          
          users = UserNetworksParser.parse(server.name, lines)
          
          c = 0
          while line = sock.gets
            if line =~ /^:\*blockuser!znc@bnc.im PRIVMSG bncbot :\| (\S+)\s+\|\s*$/
              c += 1
              username = $1
              puts "blocked user #{$1}"
              if users.has_key? username
                users[username].blocked = true
              end
            elsif line =~ /^:\*blockuser!znc@bnc.im PRIVMSG bncbot :\+\-+\+\s*/
              break if c > 3
            end
          end
                
          @servers[server.name].users = users
          sock.close
          
          @updated = Time.now
        rescue => e
          puts "Could not update server: #{name}."
          next
        end
      end
    end
  end
end