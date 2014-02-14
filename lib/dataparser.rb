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

module ZNC
  class User 
    attr_reader :username, :server
    attr_accessor :networks
  
    def initialize(username, server)
      @username, @server = username, server
      @networks = Array.new
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
    
    def to_s
      @name
    end
  end

  class UserNetwork
    attr_reader :name
    attr_accessor :online, :server, :user, :channels
  
    def initialize(name, user, online, server, channels)
      @name, @user, @online, @server = name, user, online, server
      @channels = channels
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
            if line =~ /^\| \|\-\s+\| (\S+)\s+\| (\d+)\s+\| Yes\s+\| (\S+)\s+\| (\S+)\s+\| (\d+)\s+\|\s*$/
              u.networks << UserNetwork.new($1, $4, true, $3, $5)
            elsif line =~ /^\| \`\-\s+\| (\S+)\s+\| (\d+)\s+\| Yes\s+\| (\S+)\s+\| (\S+)\s+\| (\d+)\s+\|\s*$/
              u.networks << UserNetwork.new($1, $4, true, $3, $5)
              break
            elsif line =~ /^\| \|\-\s+\| (\S+)\s+\| (\d+)\s+\| No\s+\|\s+\|\s+\|\s+\|\s*$/
              u.networks << UserNetwork.new($1, nil, false, nil, 0)
            elsif line =~ /^\| \`\-\s+\| (\S+)\s+\| (\d+)\s+\| No\s+\|\s+\|\s+\|\s+\|\s*$/
              u.networks << UserNetwork.new($1, nil, false, nil, 0)
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
      update_data
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
    
    private
    
    def update_data
      AdminMsg.do("Updating ZNC user data....")
      @servers.each do |name, server|
        sock = TCPSocket.new(server.addr, server.port)
        ssl_context = OpenSSL::SSL::SSLContext.new
        ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
        sock = OpenSSL::SSL::SSLSocket.new(sock, ssl_context)
        sock.sync = true
        sock.connect
        sock.puts "NICK bncbot"
        sock.puts "USER bncbot bncbot bncbot :bncbot"
        sock.puts "PASS #{server.username}:#{server.password}"
        sock.puts "PRIVMSG *status LISTALLUSERNETWORKS"
                
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
                  sock.close
                  break
                end
              end
            end
            break
          end
        end
        users = UserNetworksParser.parse(server.name, lines)
        
        @servers[server.name].users = users
      end
      AdminMsg.do("ZNC user data updated...")
      Thread.new { sleep 120; update_data }
    end
  end
end