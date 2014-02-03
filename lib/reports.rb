require 'cinch'
require 'domainatrix'
require 'csv'

class ReportDB
  @@reports = Hash.new

  def self.load(file)
    unless File.exists?(file)
      puts "Error: report db #{file} does not exist. Skipping loading."
      return
    end
    
    CSV.foreach(file) do |row|
      report = Report.new(row[0], row[1].to_i, row[2], row[3], row[4], row[5], row[6], row[7])
      @@reports[report.id] = report
    end
  end

  def self.save(file)
    file = File.open(file, 'w')
    csv_string = CSV.generate do |csv|
      @@reports.each_value do |r|
        csv << [r.id, r.ts, r.username, r.server, r.source, r.content, r.ircnet, r.cleared?]
      end
    end
    file.write csv_string
    file.close
  end

  def self.reports
    @@reports
  end
  
  def self.create(*args)
    obj = Report.new(self.next_id, *args)
    @@reports[obj.id] = obj
    ReportDB.save($config["reportdb"])
    @@reports[obj.id]
  end

  def self.next_id
    return 1 if @@reports.empty?
    max_id_report = @@reports.max_by { |k, v| k }
    max_id_report[0] + 1
  end
  
  def self.clear(id)
    @@reports[id].cleared = true
    ReportDB.save($config["reportdb"])
  end 
end

class Report
  attr_reader :id, :username, :server
  attr_accessor :ts, :source, :content
  attr_accessor :cleared, :ircnet

  def initialize(id, ts, username, server, source, content, ircnet, cleared = false)
    @id = id
    @ts = ts 
    @source = source
    @username = username
    @server = server
    @content = content
    @cleared = cleared
    @ircnet = ircnet
  end

  def cleared?
    @cleared
  end
end

class ReportPlugin
  include Cinch::Plugin
  match /report\s+(\w+)\s+(\w+)\s+(.+)$/i, method: :report
  match /cancelreport\s+(\d+)/i, method: :cancel
  
  match /reportid (\d+)/i, method: :reportid
  match /clear (\d+)/i, method: :clear
  
  def report(m, server, username, content)
    server.downcase!
    unless $zncs.has_key? server
      m.reply "Server \"#{server}\" not found. Possible options: #{$zncs.keys.join(", ")}."
      return
    end
    
    r = ReportDB.create(Time.now.to_i, username, server, m.user.mask.to_s, content, @bot.irc.network.name.to_s.downcase)
    m.reply "#{Format(:bold, "Report ##{r.id} has been created")}. Please wait for a response from an administrator. They may contact you via" + \
            "email or IRC to help deal with your request. Your request will be dealt with even if you leave IRC. You can cancel this report using" + \
            "!cancelreport #{r.id}."
    adminmsg("#{Format(:red, "[NEW REPORT]")} #{format_report(r)}")
  end
  
  def cancel(m, id)
    unless ReportDB.reports.has_key?(id.to_i)
      m.reply "Error: report ##{id} not found."
      return
    end
    
    report = ReportDB.reports[id.to_i]
    origin = report.source
    if m.user.mask =~ origin
      m.reply "Clearing report ##{id}."
      ReportDB.clear(id.to_i)
      adminmsg("Report ##{id} has been cleared by #{m.user.mask} on #{@bot.irc.network.name.to_s.downcase}.")
    else
      m.reply "Error: you cannot clear this report."
    end
  end
    
  def adminmsg(text)
    $adminbot.irc.send("PRIVMSG #bnc.im-admin :#{text}")
  end
    
  def format_report(r)
    "%s Source: %s on %s / Username: %s / Date: %s / Server: %s / Content: %s" %
      [Format(:bold, "[##{r.id}]"), Format(:bold, r.source.to_s), 
       Format(:bold, r.ircnet.to_s), Format(:bold, r.username.to_s),
       Format(:bold, Time.at(r.ts).ctime), Format(:bold, r.server),
       Format(:bold, r.content.to_s)]
  end
  
  def reportid(m, id)
    return unless m.channel == "#bnc.im-admin"
    unless ReportDB.reports.has_key?(id.to_i)
      m.reply "Error: report ##{id} not found."
      return
    end
    
    m.reply(format_report(ReportDB.reports[id.to_i]))
  end
  
  def clear(m, id)
    return unless m.channel == "#bnc.im-admin"
    unless ReportDB.reports.has_key?(id.to_i)
      m.reply "Error: report ##{id} not found."
      return
    end
    
    ReportDB.clear(id.to_i)
    m.reply("Report ##{id} cleared.")
    $bots.each do |network, bot|
      unless bot.irc.network.name.to_s.downcase == @bot.irc.network.name.to_s.downcase
        begin
          bot.irc.send("PRIVMSG #{$config["servers"][network]["channel"]}" + \
                       " :Report ##{id} has been cleared by #{m.user.nick}.")
        rescue => e
          # pass
        end
      end
    end
  end
end
  
