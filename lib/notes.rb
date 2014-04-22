####
## bnc.im administration bot
##
## Copyright (c) 2013 Andrew Northall
##
## MIT License
## See LICENSE file for details.
####

require 'yaml'

class NoteDB
  attr_reader :data
  
  def initialize(file)
    @file = file
    if File.exists?(@file)
      @data = YAML.load_file(@file)
    else
      puts "Warning: note db #{@file} does not exist. Skipping loading."
      @data = Hash.new
    end
  end
  
  def data=(newdata)
    @data = newdata
    f = File.open(@file, 'w')
    YAML.dump(@data, f)
    f.close
  end
end

class NotePlugin 
  include Cinch::Plugin
  match /notes?$/i, method: :list
  match /notes? list$/i, method: :list
  match /notes? list (\S+)\s*$/i, method: :list_items
  
  match /notes? add (\S+)\s*$/i, method: :add_cat
  match /notes? dele?t?e? (\S+)\s*$/i, method: :del_cat
  
  match /notes? add (\S+) (.+)\s*$/i, method: :add_item
  match /notes? dele?t?e? (\S+) (\d+)\s*$/i, method: :del_item
  
  match /netnote (\S+)\s*$/i, method: :get_netnote
  match /netnote (\S+) (.+)\s*$/i, method: :set_netnote
  
  def get_netnote(m, network)
    return unless m.channel == "#bnc.im-admin"
    data = $netnotedb.data
    network.downcase!
    note = data[network]
    if note.nil?
      m.reply "No note for network #{network}."
    else
      m.reply "Note for #{network}: #{note}"
    end
  end
  
  def set_netnote(m, network, note)
    return unless m.channel == "#bnc.im-admin"
    data = $netnotedb.data
    network.downcase!
    data[network] = note
    m.reply "Note for #{network} has been set."
    $netnotedb.data = data
  end
  
  def list(m)
    return unless m.channel == "#bnc.im-admin"
    categories = $notedb.data
    if categories.size == 0
      m.reply "There are currently no notes categories or items. Use !note add <category> to add one."
    else
      cats = []
      categories.each do |name, data|
        cats << "#{name} (#{data.size} items)"
      end
      
      m.reply "#{Format(:bold, "[Notes]")} Categories: #{cats.join(", ")}."
      m.reply "#{Format(:bold, "[Notes]")} Use !note list <category> to view items."
    end
  end
  
  def list_items(m, category)
    return unless m.channel == "#bnc.im-admin"
    category.downcase!
    items = $notedb.data[category]
    if items.nil?
      m.reply "#{Format(:bold, "Error:")} Category \"#{category}\" not found."
    elsif items.size == 0
      m.reply "#{Format(:bold, "Error:")} Category \"#{category}\" is empty."
    else
      items.each do |item|
        m.reply "#{Format(:bold, "[Notes]")} [#{items.index(item) + 1}] #{item}"
      end
    end
  end
  
  def add_cat(m, category)
    return unless m.channel == "#bnc.im-admin"
    category.downcase!
    data = $notedb.data
    if data.has_key? category
      m.reply "#{Format(:bold, "Error:")} Category \"#{category}\" exists."
    else
      data[category] = Array.new
      $notedb.data = data
      m.reply "Category \"#{category}\" added."
    end
  end
  
  def del_cat(m, category)
    return unless m.channel == "#bnc.im-admin"
    category.downcase!
    data = $notedb.data
    if data.has_key? category
      data.delete category
      $notedb.data = data
      m.reply "Category \"#{category}\" removed."
    else
      m.reply "#{Format(:bold, "Error:")} Category \"#{category}\" does not exist."
    end
  end
  
  def add_item(m, cat, item)
    return unless m.channel == "#bnc.im-admin"
    cat.downcase!
    data = $notedb.data
    if data.has_key? cat
      data[cat] << item
      $notedb.data = data
      m.reply "Item added."
    else
      m.reply "#{Format(:bold, "Error:")} Category \"#{cat}\" does not exist."
    end
  end
  
  def del_item(m, cat, index)
    return unless m.channel == "#bnc.im-admin"
    cat.downcase!
    index = index.to_i - 1
    data = $notedb.data
    if data.has_key? cat
      if data[cat][index].nil?
        m.reply "#{Format(:bold, "Error:")} Item ##{index + 1} not found."
      else
        data[cat].delete data[cat][index]
        $notedb.data = data
        m.reply "Deleted item ##{index + 1}."
      end
    else
      m.reply "#{Format(:bold, "Error:")} Category \"#{cat}\" does not exist."
    end
  end
end