#! /usr/bin/env ruby
# encoding: utf-8
# frozen-string-literal: true

require "fileutils"
require "json"
require "open-uri"
require "yaml"

class Object
  def array_enclosed
    [self]
  end
end

class Array
  def array_enclosed
    self
  end
end

DataInf = Struct.new(:seibetu, :nenrei, :sintyoo, :atai, :nendo, :taizyuu)

def load_config
  $config = YAML.load_stream(File.read("config.yaml"))[-1]
  $app_id = $config["appId"]
end

def create_data_inf(class_inf, data_inf_value)
  class_obj_seibetu = class_inf.find {|class_obj| class_obj["@id"] == "cat01" }
  cls_seibetu = class_obj_seibetu["CLASS"].array_enclosed.find {|cls| cls["@code"] == data_inf_value["@cat01"] }
  seibetu = cls_seibetu["@name"]

  class_obj_nenrei = class_inf.find {|class_obj| class_obj["@id"] == "cat02" }
  cls_nenrei = class_obj_nenrei["CLASS"].array_enclosed.find {|cls| cls["@code"] == data_inf_value["@cat02"] }
  nenrei = cls_nenrei["@name"][0..-3].to_i

  class_obj_sintyoo = class_inf.find {|class_obj| class_obj["@id"] == "cat03" }
  cls_sintyoo = class_obj_sintyoo["CLASS"].array_enclosed.find {|cls| cls["@code"] == data_inf_value["@cat03"] }
  sintyoo = cls_sintyoo["@name"].sub("（cm）", "").sub("～", "")
  if sintyoo == "計"
    sintyoo = -1
  else
    sintyoo = sintyoo.to_i
  end

  class_obj_atai = class_inf.find {|class_obj| class_obj["@id"] == "cat04" }
  cls_atai = class_obj_atai["CLASS"].array_enclosed.find {|cls| cls["@code"] == data_inf_value["@cat04"] }
  atai = cls_atai["@name"]

  class_obj_time = class_inf.find {|class_obj| class_obj["@id"] == "time" }
  cls_time = class_obj_time["CLASS"].array_enclosed.find {|cls| cls["@code"] == data_inf_value["@time"] }
  nendo = cls_time["@name"][0..-2].to_i

  taizyuu = data_inf_value["$"].to_f

  DataInf.new(seibetu, nenrei, sintyoo, atai, nendo, taizyuu)
end

def main_loop(nendo, nenrei, stats_data_id, command)
  uri = URI "http://api.e-stat.go.jp/rest/3.0/app/json/getStatsData?appId=#{$app_id}&lang=J&statsDataId=#{stats_data_id}&metaGetFlg=Y&cntGetFlg=N&explanationGetFlg=N&annotationGetFlg=N&sectionHeaderFlg=2&cdCat04=0000010&cdTime=#{nendo}100000"

  filepath = "#{ENV["TEMP"]}/#{nendo}/#{nenrei}sai-zyosi.json"

  unless FileTest.exist?(filepath)
    FileUtils.move(open(uri).path, filepath)
  end

  json = File.read(filepath)
  h = JSON.parse(json)["GET_STATS_DATA"]
  unless h["RESULT"]["STATUS"] == 0
    raise h["RESULT"]["ERROR_MSG"]
  end

  table_inf = h["STATISTICAL_DATA"]["TABLE_INF"]
  table_title = table_inf["TITLE"]["$"]
  class_inf = h["STATISTICAL_DATA"]["CLASS_INF"]["CLASS_OBJ"]
  data_inf = h["STATISTICAL_DATA"]["DATA_INF"]["VALUE"]

  class_obj_time = class_inf.find {|class_obj| class_obj["@id"] == "time" }
  nendo = class_obj_time["CLASS"]["@name"][0..-2].to_i

  data_inf = data_inf.map {|data_inf_value|
    create_data_inf(class_inf, data_inf_value)
  }

  if command == "view"
    puts "#{table_title}（#{nendo}年度）"
    p data_inf.size
    p *data_inf #.values_at(0..2, -3..-1)
  else
    create_api(nendo, nenrei, data_inf, command)
  end
end

def create_api(nendo, nenrei, data_inf, command)
  filepath_base = "api/#{nendo}/#{nenrei}sai/%scm/zyosi.json"

  sintyoo_betu_data_inf = data_inf.map {|data_inf_value|
    data_inf_value.to_h.slice(:nendo, :seibetu, :nenrei, :sintyoo, :taizyuu)
  }
  .group_by {|data_inf_value| data_inf_value[:sintyoo] }
  .transform_values {|data_inf_value| data_inf_value[0] }

  sintyoo_betu_data_inf.each {|sintyoo, data_inf|
    json = JSON.dump(data_inf)
    filepath = filepath_base % data_inf[:sintyoo]
    FileUtils.mkdir_p(File.dirname(filepath))
    open(filepath, "w") {|f|
      f.puts(json)
    }
  }

  Dir.glob(filepath_base % "*") {|filepath|
    h = JSON.load(File.read(filepath))
    p h #.values_at(0..2, -3..-1)
  }
end

def main
  load_config
  raise unless FileUtils.pwd == File.dirname(File.expand_path(__FILE__))
  ENV["TEMP"] = "tmp"
  FileUtils.mkdir_p("#{ENV["TEMP"]}")

  command = "view"
  command = "update"
  source = YAML.load_stream(File.read("source.yaml"))[-1]["source"]

  if command == "update"
    source.each {|nendo, h|
      h["statsDataId"].each {|nenrei, stats_data_id|
        #p [nendo, nenrei, stats_data_id]
        FileUtils.mkdir_p("#{ENV["TEMP"]}/#{nendo}")
        main_loop(nendo, nenrei, stats_data_id, command)
        sleep 0.2
      }
    }
  else
    nendo = 2018
    nenrei = 17
    h = source.fetch(nendo)
    stats_data_id = h["statsDataId"].fetch(nenrei)
    #p [nendo, nenrei, stats_data_id]
    main_loop(nendo, nenrei, stats_data_id, command)
  end
end

if __FILE__ == $0
  main
end

