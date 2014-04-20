####
## bnc.im administration bot
##
## Copyright (c) 2013 Andrew Northall
##
## MIT License
## See LICENSE file for details.
####

require 'yaml'

class TodoDB
  attr_reader :data
  
  def initialize(file)
    @file = file
    if File.exists?(@file)
      @data = YAML.parse_file(@file)
    else
      puts "Warning: todo db #{@file} does not exist. Skipping loading."
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

class TodoPlugin 
  include Cinch::Plugin
  match /todo$/i, method: :list
  match /todo list$/i, method: :list
  match /todo list (\S+)\s*$/i, method: :list_items
  
  match /todo add (\S+)\s*$/i, method: :add_cat
  match /todo del (\S+)\s*$/i, method: :del_cat
  
  match /todo add (\S+) (.+)\s*$/i, method: :add_item
  match /todo del (\S+) (\d+)\s*$/i, method: :del_item
  
  def list(m)
    return unless m.channel == "#bnc.im-admin"
    categories = $tododb.data
    if categories.size == 0
      m.reply "There are currently no TODO categories or items. Use !todo add <category> to add one."
    else
      cats = []
      categories.each do |name, data|
        cats << "#{name} (#{data.size} items)"
      end
      
      m.reply "#{Format(:bold, "[TODO]")} Categories: #{cats.join(", ")}."
      m.reply "#{Format(:bold, "[TODO]")} Use !todo list <category> to view items."
    end
  end
  
  def list_items(m, category)
    return unless m.channel == "#bnc.im-admin"
    category.downcase!
    items = $tododb.data[category]
    if items.nil?
      m.reply "#{Format(:bold, "Error:")} Category \"#{category}\" not found."
    elsif items.size == 0
      m.reply "#{Format(:bold, "Error:")} Category \"#{category}\" is empty."
    else
      items.each do |item|
        m.reply "#{Format(:bold, "[TODO]")} [#{items.index(item) + 1}] #{item}"
      end
    end
  end
  
  def add_cat(m, category)
    return unless m.channel == "#bnc.im-admin"
    category.downcase!
    data = $tododb.data
    if data.has_key? category
      m.reply "#{Format(:bold, "Error:")} Category \"#{category}\" exists."
    else
      data[category] = Array.new
      $tododb.data = data
      m.reply "Category \"#{category}\" added."
    end
  end
  
  def del_cat(m, category)
    return unless m.channel == "#bnc.im-admin"
    category.downcase!
    data = $tododb.data
    if data.has_key? category
      data.delete category
      $tododb.data = data
      m.reply "Category \"#{category}\" removed."
    else
      m.reply "#{Format(:bold, "Error:")} Category \"#{category}\" does not exist."
    end
  end
  
  def add_item(m, cat, item)
    return unless m.channel == "#bnc.im-admin"
    cat.downcase!
    data = $tododb.data
    if data.has_key? cat
      data[cat] << item
      m.reply "Item added."
    else
      m.reply "#{Format(:bold, "Error:")} Category \"#{cat}\" does not exist."
    end
  end
  
  def del_item(m, cat, index)
    return unless m.channel == "#bnc.im-admin"
    cat.downcase!
    index = index - 1
    data = $tododb.data
    if data.has_key? cat
      if data[cat][index].nil?
        m.reply "#{Format(:bold, "Error:")} Item ##{index} not found."
      else
        data[cat].delete data[cat][index]
        m.reply "Deleted item ##{index}."
      end
    else
      m.reply "#{Format(:bold, "Error:")} Category \"#{cat}\" does not exist."
    end
  end
end