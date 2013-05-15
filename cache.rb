require 'geocoder'

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
end

class String
	def remove_tags
		self.gsub(/<[^>]*>/, '')
	end
	def remove_spaces
		self.gsub(/[[:space:]]/, '')
	end
	def substitude_urls
		self.gsub(/src=(["'])([^h][^t][^t][^p][^s]?[^:])/, 'src=\1http://www.geocaching.com/seek/\2').gsub(/\/seek\/\//, "/").gsub(/\/seek\/\.\.\//, "/")
	end
end
