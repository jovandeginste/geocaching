require 'htmlentities'

class Cache
	include DataMapper::Resource
	property :id,   Serial
	property :gcid, String, :unique => true, :required => true
	property :guid, String, :unique => true, :required => true
	property :name, String
	property :owner, String, :required => true, :length => 128
	property :location, String
	property :geolocation, Json, :length => 1024
	property :longitude, Float
	property :latitude, Float
	property :difficulty, Float
	property :terrain, Float
	property :archived, Boolean
	property :archived_date, Date
	property :disabled, Boolean
	property :found_by_me, Boolean
	property :found_date, Date
	property :hidden, Date
	property :last_update, DateTime
	property :content, Text, :length => 1*1024*1024
	property :short_desc, Text
	property :long_desc, Text
	property :hints, Text
	property :notes, Text
	property :local_notes, Text, :length => 1*1024*1024

	belongs_to :cache_size
	belongs_to :cache_type
	has n, :cache_lists, :through => Resource

	before :save do
		if self.last_update.nil? or DateTime.now > self.last_update + 30
			self.update_from_site
		end
	end
	before :destroy do
		self.remove_all_files
	end

	def to_s
		"#{self.name} (#{
			[
				self.cache_type.name,
				self.cache_size.name,
				self.difficulty,
				self.terrain,
				self.gcid,
				self.disabled ? "disabled" : nil,
				self.archived ? "archived" : nil,
				self.solved? ? "solved" : nil,
				self.found_by_me ? "found" : nil,
				self.geolocation.nil? ? nil : self.geolocation["locality"],
			].compact.join(";")})"
	end

	def self.add_all_by_gcid(list)
		list.map{|gcid|
			Cache.find_or_create(gcid: gcid)
		}
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
		self.get_images
		self
	end

	def update_from_site!
		puts "Updating database: #{self.to_s}"
		self.update self.data_from_site
		self.update_content_from_site
		self.save
		self.get_images
		self
	end

	def as_location
		@location_object ||= Location.new(self.latitude, self.longitude)
	end

	def distance_from(position)
		self.as_location.distance_from(position)
	end

	def body
		@body ||= self.get_html
	end

	def data_from_site
		puts "Updating: #{self.gcid}; #{self.guid}"
		body = self.body

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
		case [result[:archived], self.archived_date.nil?]
		when [true, true]
			result[:archived_date] = Date.today
		when [false, false]
			result[:archived_date] = nil
		end
		result[:disabled] = !body.find{|line| line.match(/<ul class="OldWarning"><li>This cache is temporarily unavailable/)}.nil?

		result[:latitude], result[:longitude] = body.find{|line| line.match(/id="uxLatLon"/)}.remove_tags.strip.gsub(/ E/, ",E").split(",").map{|c| Location.convert(c)}

		if self.geolocation.nil? or self.last_update < DateTime.now - 30
			puts "Updating geolocation information for #{result[:gcid]} - #{result[:name]}"
			new_geolocation = Location.new(result[:latitude], result[:longitude]).location_drilldown
			result[:geolocation] = new_geolocation if new_geolocation
		end
		result[:hidden] = (
			start = body.index{|line| line.match(/"ctl00_ContentBody_mcd2"/)}
			stop = body[start..-1].index{|line| line.match(/<\/div>/)}
			body[start..(start+stop)].join.remove_tags.remove_spaces.gsub(/.*Hidden:/, "")
		)
		result[:owner] = (
			start = body.index{|line| line.match(/"ctl00_ContentBody_mcd1"/)}
			stop = body[start..-1].index{|line| line.match(/<\/div>/)}
			body[start..(start+stop)].join.gsub(/A cache by/, "").remove_tags.remove_spaces
		).first(128)
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
		result[:notes] = (
			start = body.index{|line| line.match(/id="cache_note"/)}
			stop = body[start..-1].index{|line| line.match(/<\/span>/)}
			body[start..(start+stop)].map(&:strip).join("\n").strip_tags.strip
		)
		result[:last_update] = DateTime.now
		result[:found_by_me] = !body.select{|line| line.match(/<strong id="ctl00_ContentBody_GeoNav_logText">Found It!<\/strong>/)}.empty?
		result[:found_by_me] ||= !body.select{|line| line.match(/<strong id="ctl00_ContentBody_GeoNav_logText">Attended<\/strong>/)}.empty?
		result[:found_date] = result[:found_by_me] ? (
			body.find{|line| line.match(/"ctl00_ContentBody_GeoNav_logDate"/)}.remove_tags.gsub(/.* on: /, "").gsub(/\./, "").remove_spaces
		) : nil
		result
	end

	def get_images
		body = self.body
		encoder = HTMLEntities.new
		if images = body.find{|l| l.match(/rel="lightbox"/)}
			self.make_extra_directory
			images.strip.split(/<\/?li>/).each{|image|
				next unless m = image.match(/.*<a href="([^"]*)"[^>]*>([^>]*)<\/a>.*/)
				url, name = m[1..2] 
				name = encoder.decode(name).transliterate.gsub(/[^-[:alnum:]_]+/, "_")
				ext = url.gsub(/.*\./, "")
				file_name = File.join(self.extra_directory, "#{name}.#{ext}")
				puts "Downloading #{url} as #{file_name}"
				content = %x[curl -fsS --connect-timeout 5 "#{url}"]
				current = File.exist?(file_name) ? File.open(file_name, 'r').read : nil
				if current != content
					puts "Updating file '#{file_name}' for: #{self}"
					File.open(file_name, 'w') { |file| file.write(content) }
				end
			}
		end
	end

	def update_content_from_site
		url = "/seek/cdpf.aspx?guid=#{self.guid}&lc=10"
		request = HttpInterface.get_page(url)
		body = request.body.force_encoding("UTF-8").substitute_urls
		self.content = body.gsub(/<script.*?<\/script>/m, "")
	end

	def get_html
		if self.gcid
			url = "/seek/cache_details.aspx?wp=" + self.gcid
		else
			url = "/seek/cache_details.aspx?guid=" + self.guid
		end
		request = HttpInterface.get_page(url)
		request.body.force_encoding("UTF-8").split(/\r?\n/)
	end

	def self.logged_by_me(filter = nil)
		url = "/my/logs.aspx?s=1" + (filter.nil? ? "" : "&lt=#{filter}")
		request = HttpInterface.get_page(url)
		self.add_all_by_guid(request.body.force_encoding("UTF-8").scan(/guid=[[:alnum:]].*/).map{|x| x.gsub(/guid=/, "").gsub(/".*/, "")})
	end
	def self.found_by_me
		puts "Searching caches found by me"
		list = self.logged_by_me(2) + self.logged_by_me(10) + self.logged_by_me(11)
		list.uniq.map{|c|
			c.update found_by_me: true
		}
	end
	def find_near(pages = 1)
		self.class.find_near(self.as_location, pages)
	end

	def self.find_near(location, pages = 1)
		latitude, longitude = location.latitude, location.longitude
		url = "/seek/nearest.aspx?lat=#{latitude}&lng=#{longitude}&f=1"
		viewstate = ""
		viewstate1 = ""
		viewstate2 = ""
		results = []
		pages.times.each do |n|
			puts "page #{n}"
			if viewstate.empty?
				data = {}
			else
				data = {
					"__EVENTTARGET" => "ctl00$ContentBody$pgrTop$lbGoToPage_#{n + 1}",
					"__EVENTARGUMENT" => "",
					"__LASTFOCUS" => "",
					"__VIEWSTATEFIELDCOUNT" => 3,
					"__VIEWSTATE" => viewstate,
					"__VIEWSTATE1" => viewstate1,
					"__VIEWSTATE2" => viewstate2,
				}
			end
			request = HttpInterface.post_page(url, data)
			body = request.body.force_encoding("UTF-8")
			viewstate = begin
					    body.split("\r\n").select{|l| l.match(/id="__VIEWSTATE"/)}.first.gsub(/.*value="/, "").gsub(/".*/, "")
				    rescue
					    ""
				    end
			viewstate1 = begin
					     body.split("\r\n").select{|l| l.match(/id="__VIEWSTATE1"/)}.first.gsub(/.*value="/, "").gsub(/".*/, "")
				     rescue
					     ""
				     end
			viewstate2 = begin
					     body.split("\r\n").select{|l| l.match(/id="__VIEWSTATE2"/)}.first.gsub(/.*value="/, "").gsub(/".*/, "")
				     rescue
					     ""
				     end
			results += body.scan(/\/geocache\/GC[-_[:alnum:]].*/).map{|x| x.gsub(/.*\/geocache\//, "").gsub(/_.*/, "")}
			puts "results: #{results.size}"
		end
		return results
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
      <groundspeak:owner id="?">#{self.owner}</groundspeak:owner>
      <groundspeak:type>#{self.cache_type.name} Cache</groundspeak:type>
      <groundspeak:container>#{self.cache_size.name}</groundspeak:container>
      <groundspeak:difficulty>#{self.difficulty}</groundspeak:difficulty>
      <groundspeak:terrain>#{self.terrain}</groundspeak:terrain>
      <groundspeak:short_description html="True">#{self.short_desc}</groundspeak:short_description>
      <groundspeak:long_description html="True">#{self.long_desc}</groundspeak:long_description>
      <groundspeak:encoded_hints>#{self.hints.rot13}</groundspeak:encoded_hints>
    </groundspeak:cache>
  </wpt>].force_encoding("UTF-8")
	end
	def solved_location
		self.full_notes.match(/#OPL#/) ? location = Location.new(self.full_notes.split("\n").find{|l| l.match(/#OPL#/)}.gsub(/#OPL#[[:space:]]*/, "")) : nil
	end
	def solved?
		self.full_notes.match(/#OPL#/) ? true : false
	end

	def file_name_template
		if self.geolocation.nil?
			File.join ["Unknown", "Unknown - #{self.name} - #{self.gcid}"].map{|p| p.transliterate.gsub(/[^-[:alnum:]_]+/, "_")}
		else
			File.join [
				"#{self.geolocation["country"]} - #{self.geolocation["administrative_area_level_1"]}",
				self.geolocation["administrative_area_level_2"],
					"#{self.geolocation["locality"]} - #{self.name} - #{self.gcid}",
			].map{|p| p.transliterate.gsub(/[^-[:alnum:]_]+/, "_")}
		end
	end

	def full_export
		start = File.join(Export.file_root(self), self.file_name_template)
		dir = File.dirname(start)
		FileUtils.mkdir_p(dir) unless File.directory?(dir)

		pdf = "#{start}.pdf"
		Export.to_file(self, pdf, :pdf)
		notes = "#{start}.txt"
		Export.to_file(self, notes, :notes)
	end

	def files
		start = File.join(Export.file_root(self), self.file_name_template)
		["#{start}.pdf"] + ((self.notes.empty? and self.local_notes.empty?) ? [] : ["#{start}.txt"])
	end
	def current_extra_directories
		%x[find #{Export.all_file_roots.join(" ")} -type d -name '*_-_#{self.gcid}'].split("\n")
	end
	def current_files
		%x[find #{Export.all_file_roots.join(" ")} -type f -name '*_-_#{self.gcid}.*'].split("\n")
	end
	def files_to_remove
		self.current_files - self.files
	end
	def remove_all_files
		self.current_files.each{|file|
			begin
				File.delete(file)
			rescue
			end
		}
		self.current_extra_directories.each{|file|
			begin
				FileUtils.rm_r(file)
			rescue
			end
		}
	end
	def remove_obsolete_files
		self.files_to_remove.each{|file|
			begin
				File.delete(file)
			rescue
			end
		}
	end

	def edit_notes
		notes = self.local_notes
		self.local_notes = (notes.nil? ?  String.new_from_editor : notes.edit)
		self.save
	end
	def extra_directory
		File.join(Export.file_root(self), self.file_name_template)
	end

	def make_extra_directory
		extra_dir = self.extra_directory
		FileUtils.mkdir_p(extra_dir) unless File.directory?(extra_dir)
		extra_dir
	end

	def update_files
		self.remove_obsolete_files
		self.full_export
		current_dir = self.current_extra_directories
		unless current_dir.empty?
			extra_dir = self.extra_directory
			unless current_dir.include?(extra_dir)
				self.make_extra_directory
			end
			(current_dir - [extra_dir]).each{|dir|
				%x[mv -v #{dir}/* #{extra_dir}/]
				FileUtils.rm_rf(dir)
			}
		end
		nil
	end

	def import_local_notes
		notes_file = %x[find /home/jo/Dropbox/GC_done/ /home/jo/Dropbox/autosync/GC/ -name *_-_#{self.gcid}.txt].split("\n")
		if notes_file.size >= 1
			notes = notes_file.map{|f| File.read(f).encode('UTF-16le', :invalid => :replace, :replace => ' ').encode('UTF-8')}.join("\n")
			self.local_notes = notes
			self.save
		end
		self.local_notes
	end

	def full_notes
		(self.notes.empty? ? "" : self.notes + "\n") + (self.local_notes.empty? ? "" : self.local_notes + "\n")
	end
	
	def waypoints
		encoder = HTMLEntities.new
		body = self.body
		start = body.find_index{|s| s.match(/<table class="Table" id="ctl00_ContentBody_Waypoints">/)}
		start = start + body[start..-1].find_index{|s| s.match(/<tbody>/)}
		stop = start + body[start..-1].find_index{|s| s.match(/<\/tbody>/)}
		slice = body[start..stop]
		slice.pop
		slice.shift
		wp_array = slice.inject([]) do |wp_array, item|
			if item.match(/<tr/)
				wp_array << [] 
			elsif item.match(/<\/tr>/)
			else
				wp_array.last << item unless wp_array.last.nil?
			end
			wp_array
		end
		wp_array.pop

		wp_array = wp_array.inject([]) do |wp_array, item|
			new_item = item.inject([]) do |new_item, old_item|
				if old_item.match(/<td/)
					if l = new_item.pop
						new_item << l.map{|i| encoder.decode(i).strip}.join("\n").strip
					end
					new_item << []
				elsif old_item.match(/<\/td>/)
				else
					new_item.last << old_item unless new_item.last.nil?
				end
				new_item
			end
			unless new_item[4].nil?
				wp_array << {
					name: new_item[4],
					location: new_item[6],
					as_location: Location.new(new_item[6]),
				}
			end
			wp_array
		end

		wp_array
	end
end
