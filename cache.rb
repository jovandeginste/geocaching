class Cache
	include DataMapper::Resource
	property :id,   Serial
	property :gcid, String, :unique => true, :required => true
	property :guid, String, :unique => true, :required => true
	property :name, String
	property :owner, String, :required => true
	property :location, String
	property :city, String
	property :longitude, Float
	property :latitude, Float
	property :difficulty, Float
	property :terrain, Float
	property :archived, Boolean
	property :disabled, Boolean
	property :found_by_me, Boolean
	property :hidden, Date
	property :last_update, DateTime
	property :content, Text, :length => 1*1024*1024
	property :short_desc, Text
	property :long_desc, Text
	property :hints, Text

	belongs_to :cache_size
	belongs_to :cache_type
	has n, :cache_lists, :through => Resource

	before :save do
		if self.last_update.nil? or DateTime.now > self.last_update + 30
			self.update_from_site
		end
	end

	def self.add_all_by_guid(list)
		list.map{|guid|
			Cache.find_or_create(guid: guid)
		}
	end

	def self.parse(ids = [])
		ids.each{|identifier|
			if identifier.match(/^GC/)
				self.find_or_create(gcid: identifier)
			else
				self.find_or_create(guid: identifier)
			end
		}
	end

	def update_from_site
		self.attributes = self.data_from_site
		self.update_content_from_site
	end

	def update_from_site!
		self.update self.data_from_site
		self.update_content_from_site
		self.save
	end

	def as_location
		Location.new(self.latitude, self.longitude)
	end

	def distance_from(position)
		self.as_location.distance_from(position)
	end

	def data_from_site
		body = self.get_html

		result = {}
		result[:guid] = body.find{|line| line.match(/"ctl00_ContentBody_uxLogbookLink"/)}.match(/guid=([[:alnum:]-]*)"/)[1]
		result[:gcid] = body.find{|line| line.match(/"ctl00_ContentBody_CoordInfoLinkControl1_uxCoordInfoCode"/)}.remove_tags.remove_spaces
		result[:name] = body.find{|line| line.match(/"ctl00_ContentBody_CacheName"/)}.remove_tags.strip
		cache_type = body.find{|line| line.match(/\/images\/WptTypes\//)}.gsub(/.*title="/, "").gsub(/".*/, "").gsub(/ *-?cache$/i, "").downcase
		result[:cache_type] = CacheType.find_or_create(name: cache_type)
		cache_size = body.find{|line| line.match(/\/images\/icons\/container\//)}.remove_tags.match(/.*\((.*)\).*/)[1].downcase
		result[:cache_size] = CacheSize.find_or_create(name: cache_size)
		result[:difficulty] = body.find{|line| line.match(/"ctl00_ContentBody_uxLegendScale"/)}.gsub(/.*alt="/, "").gsub(/[[:space:]].*/, "").to_f
		result[:terrain] = body.find{|line| line.match(/"ctl00_ContentBody_Localize12"/)}.gsub(/.*alt="/, "").gsub(/[[:space:]].*/, "").to_f
		result[:location] = body.find{|line| line.match(/"ctl00_ContentBody_Location"/)}.remove_tags.strip.gsub(/^In */, "").gsub(/[^-_[:alnum:]]\+/, "_")

		result[:archived] = !body.find{|line| line.match(/<ul class="OldWarning"><li>This cache has been archived/)}.nil?
		result[:disabled] = !body.find{|line| line.match(/<ul class="OldWarning"><li>This cache is temporarily unavailable/)}.nil?

		result[:latitude], result[:longitude] = body.find{|line| line.match(/var userDefinedCoords/)}.match(/.*"([^"]*)"/)[1].gsub(/' /, "',").split(",").map{|c| Location.convert(c)}
		result[:city] = Location.new(result[:latitude], result[:longitude]).to_city
		result[:hidden] = (
			start = body.index{|line| line.match(/"ctl00_ContentBody_mcd2"/)}
			stop = body[start..-1].index{|line| line.match(/<\/div>/)}
			body[start..(start+stop)].join.remove_tags.remove_spaces.gsub(/.*Hidden:/, "")
		)
		result[:owner] = (
			start = body.index{|line| line.match(/"ctl00_ContentBody_mcd1"/)}
			stop = body[start..-1].index{|line| line.match(/<\/div>/)}
			body[start..(start+stop)].join.gsub(/A cache by/, "").remove_tags.remove_spaces
		)
		result[:short_desc] = (
			start = body.index{|line| line.match(/"ctl00_ContentBody_ShortDescription"/)}
			stop = body[start..-1].index{|line| line.match(/<\/span>/)}
			body[start..(start+stop)].map(&:strip).join("\n").strip_tags.strip
		)
		result[:long_desc] = (
			start = body.index{|line| line.match(/"ctl00_ContentBody_LongDescription"/)}
			stop = body[start..-1].index{|line| line.match(/<\/span>/)}
			body[start..(start+stop)].map(&:strip).join("\n").strip_tags.strip
		)
		result[:hints] = (
			start = body.index{|line| line.match(/<div id="div_hint"/)}
			stop = body[start..-1].index{|line| line.match(/<\/div>/)}
			body[start..(start+stop)].map(&:strip).join("\n").strip_tags.strip
		)
		result[:last_update] = DateTime.now
		result[:found_by_me] = !body.select{|line| line.match(/"ctl00_ContentBody_hlFoundItLog"/)}.empty?
		result
	end

	def update_content_from_site
		url = "http://www.geocaching.com/seek/cdpf.aspx?guid=#{self.guid}&lc=10"
		request = HttpInterface.get_page(url)
		body = request.body.force_encoding("UTF-8").substitude_urls
		self.content = body.gsub(/<script.*?<\/script>/m, "")
	end

	def get_html
		if self.gcid
			url = "/seek/cache_details.aspx?wp=" + self.gcid
		else
			url = "/seek/cache_details.aspx?guid=" + self.guid
		end
		request = HttpInterface.get_page(url)
		request.body.force_encoding("UTF-8").split("\r\n")
	end

	def self.logged_by_me(filter = nil)
		url = "/my/logs.aspx?s=1" + (filter.nil? ? "" : "&lt=#{filter}")
		request = HttpInterface.get_page(url)
		self.add_all_by_guid(request.body.force_encoding("UTF-8").scan(/guid=[[:alnum:]].*/).map{|x| x.gsub(/guid=/, "").gsub(/".*/, "")})
	end
	def self.found_by_me
		self.logged_by_me(2)
	end
	def self.find_near(location)
		latitude, longitude = location.latitude, location.longitude
		url = "/seek/nearest.aspx?lat=#{latitude}&lng=#{longitude}&f=1"
		request = HttpInterface.get_page(url)
		body = request.body.force_encoding("UTF-8").scan(/guid=[[:alnum:]].*/).map{|x| x.gsub(/guid=/, "").gsub(/".*/, "")}
	end

	def to_gpx
%Q[  <wpt lat="#{self.latitude}" lon="#{self.longitude}">
    <time>#{self.hidden.to_datetime}</time>
    <name>#{self.gcid}</name>
    <desc>#{self.name}, #{self.cache_type.name} (#{self.difficulty}/#{self.terrain})</desc>
    <url>http://www.geocaching.com/seek/cache_details.aspx?guid=#{self.guid}</url>
    <urlname>#{self.name}</urlname>
    <sym>Geocache</sym>
    <type>Geocache|#{self.cache_type.name} Cache</type>
    <groundspeak:cache id="25805" available="#{!self.disabled}" archived="#{self.archived}" xmlns:groundspeak="http://www.groundspeak.com/cache/1/0">
      <groundspeak:name>#{self.name}</groundspeak:name>
      <groundspeak:placed_by>#{self.owner}</groundspeak:placed_by>
      <groundspeak:owner id="13197">Cip</groundspeak:owner>
      <groundspeak:type>#{self.cache_type.name} Cache</groundspeak:type>
      <groundspeak:container>#{self.cache_size.name}</groundspeak:container>
      <groundspeak:difficulty>#{self.difficulty}</groundspeak:difficulty>
      <groundspeak:terrain>#{self.terrain}</groundspeak:terrain>
      <groundspeak:country>#{Cache.first.location.split(", ").last}</groundspeak:country>
      <groundspeak:state>#{Cache.first.location.split(", ").first}</groundspeak:state>
      <groundspeak:short_description html="True">#{self.short_desc}</groundspeak:short_description>
      <groundspeak:long_description html="True">#{self.long_desc}</groundspeak:long_description>
      <groundspeak:encoded_hints>#{self.hints.rot13}</groundspeak:encoded_hints>
    </groundspeak:cache>
  </wpt>].force_encoding("UTF-8")
	end
end

class String
	def remove_tags
		self.gsub(/<[^>]*>/, '')
	end
	def strip_tags
		self.sub(/^<[^>]*>/, "").sub(/<[^>]*>$/, "")
	end
	def remove_spaces
		self.gsub(/[[:space:]]/, '')
	end
	def substitude_urls
		self.gsub(/src=(["'])([^h][^t][^t][^p][^s]?[^:])/, 'src=\1http://www.geocaching.com/seek/\2').gsub(/\/seek\/\//, "/").gsub(/\/seek\/\.\.\//, "/")
	end
	def rot13
		self.rot(13)
	end
	def rot(nr = 13)
		self.each_byte.map do |byte|
			case byte
			when 97..122
				byte = ((byte - 97 + nr) % 26) + 97
			when 65..90
				byte = ((byte - 65 + nr) % 26) + 65
			end
			byte
		end.pack('c*')
	end
end
