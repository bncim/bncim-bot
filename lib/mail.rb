####
### bnc.im administration bot
### mail lib
###
### Copyright (c) 2013 Andrew Northall
###
### MIT License
### See LICENSE file for details.
#####

require 'net/smtp'
require 'uuid'

class Mail
  def self.send(to_addr, message)
    conf = $config["mail"]
    Net::SMTP.start(conf["server"], conf["port"], 'bnc.im', conf["user"], \
                    conf["pass"], :plain) do |smtp|
      smtp.enable_starttls
      smtp.send_message message, 'no-reply@bnc.im',
        to_addr
    end
  end

  def self.send_verify(to_addr, id, code)
    
    msgstr = <<-END_OF_MESSAGE
      From: bnc.im bot <no-reply@bnc.im>
      To: #{to_addr}
      Reply-to: admin@bnc.im
      Subject: bnc.im account verification
      Date: #{Time.now.ctime}
      Message-Id: <#{UUID.generate}@bnc.im>

      Someone, hopefully you, requested an account in the http://bnc.im IRC channel. Once you have read and agreed to our Terms of Service (located at https://bnc.im/terms-of-service), please send

      !verify #{id} #{code} 

      in either #bnc.im or in a private message to the bncim bot. If you need any help, please visit http://bnc.im/webchat.

      Regards,
      bnc.im team
      admin@bnc.im
			http://bnc.im/
    END_OF_MESSAGE
    
    # remove whitespace from above
    msg = msgstr.lines.map { |l| l.strip }.join("\r\n")

    self.send(to_addr, msg)
  end
  
  def self.send_reject(to_addr, id, reason)
    
    msgstr = <<-END_OF_MESSAGE
      From: bnc.im bot <no-reply@bnc.im>
      To: #{to_addr}
      Reply-to: admin@bnc.im
      Subject: bnc.im account rejected
      Date: #{Time.now.ctime}
      Message-Id: <#{UUID.generate}@bnc.im>
      
      I am sorry to inform you that your bnc.im account has been rejected. The reason given by our administrator was:
      
      #{reason}
      
      If you wish to appeal this decision, please join us in irc.freenode.net #bnc.im or join our webchat at
      https://bnc.im/webchat. Alternatively, email us at admin@bnc.im.
      
      Regards,
      bnc.im team
      admin@bnc.im
			http://bnc.im/
    END_OF_MESSAGE
    
    # remove whitespace from above
    msg = msgstr.lines.map { |l| l.strip }.join("\r\n")

    self.send(to_addr, msg)
  end
  

  def self.request_waiting(to_addr, r)
    msgstr = <<-END_OF_MESSAGE
      From: bnc.im bot <no-reply@bnc.im>
      To: #{to_addr}
      Reply-to: admin@bnc.im
      Subject: bnc.im account request - ##{r.id}
      Date: #{Time.now.ctime}
      Message-Id: <#{UUID.generate}@bnc.im>

      There is a bnc.im account waiting to be approved. Details:

      ID: #{r.id}
      Username: #{r.username}
      Source: #{r.source} on #{r.ircnet}
      Server: #{r.server} #{r.port}
      Email: #{r.email}
      Timestamp: #{Time.at(r.ts).ctime}

      Regards,
      bnc.im bot
    END_OF_MESSAGE

    msg = msgstr.lines.map { |l| l.strip }.join("\r\n")

    self.send(to_addr, msg)
  end
  
  def self.send_approved_admin(to_addr, id, admin)
    msgstr = <<-END_OF_MESSAGE
      From: bnc.im bot <no-reply@bnc.im>
      To: #{to_addr}
      Reply-to: admin@bnc.im
      Subject: RE: bnc.im account request - ##{id}
      Date: #{Time.now.ctime}
      Message-Id: <#{UUID.generate}@bnc.im>

      The bnc.im request ##{id} has been approved by #{admin}.
      
      Regards,
      bnc.im bot
    END_OF_MESSAGE

    msg = msgstr.lines.map { |l| l.strip }.join("\r\n")

    self.send(to_addr, msg)
  end
  
  def self.send_rejected_admin(to_addr, id, admin)
    msgstr = <<-END_OF_MESSAGE
      From: bnc.im bot <no-reply@bnc.im>
      To: #{to_addr}
      Reply-to: admin@bnc.im
      Subject: RE: bnc.im account request - ##{id}
      Date: #{Time.now.ctime}
      Message-Id: <#{UUID.generate}@bnc.im>

      The bnc.im request ##{id} has been rejected by #{admin}.
      
      Regards,
      bnc.im bot
    END_OF_MESSAGE

    msg = msgstr.lines.map { |l| l.strip }.join("\r\n")

    self.send(to_addr, msg)
  end

  def self.send_approved(to_addr, server, user, pass, network)
    addr = $config["zncservers"][server]["addr"]
    webpanel = $config["zncservers"][server]["public"]["panel"]
    port = $config["zncservers"][server]["public"]["port"]
    sslport = $config["zncservers"][server]["public"]["sslport"]
    
    msgstr = <<-END_OF_MESSAGE
      From: bnc.im bot <no-reply@bnc.im>
      To: #{to_addr}
      Reply-to: admin@bnc.im
      Subject: bnc.im account approved
      Date: #{Time.now.ctime}
      Message-Id: <#{UUID.generate}@bnc.im>
      
      Dear #{user},
      
      Your bnc.im account has been approved. Your account details are:
      
      Server: #{addr}
      Server name: #{server}
      Plaintext Port: #{port}
      SSL Port: #{sslport}
      Username: #{user}
      Password: #{pass}
      Web Panel: #{webpanel}
      
      In order to connect to your new account, you will need to connect
      your IRC client to #{addr} on port #{port} (or #{sslport} for SSL) 
      and configure your client to send your bnc.im username and password 
      together with the network you signed up for, in the server password
      field like so: 
      
      #{user}/#{network}:#{pass}

      If you need any help, please do not hestitate to join our IRC 
      channel: irc.freenode.net #bnc.im - or connect to our webchat
      at https://bnc.im/webchat. Please make sure you have read and
      reviewed our Terms of Service at http://bnc.im/terms-of-service.
      
      If you need help using ZNC, plenty of documentation can be found
      on the ZNC wiki at http://wiki.znc.in/. 
      
      Regards,
      bnc.im team
      admin@bnc.im
			http://bnc.im/
    END_OF_MESSAGE
    
    # remove whitespace from above
    msg = msgstr.lines.map { |l| l.strip }.join("\r\n")

    self.send(to_addr, msg)
  end
      
end
