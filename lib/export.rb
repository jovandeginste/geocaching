require 'htmlentities'

class Export
	def self.file_root_hash
		@file_root_hash ||= {}
	end
	def self.file_root_hash=(hash)
		@file_root_hash = hash
	end

	def self.file_root(cache)
		return self.file_root_hash[:found] if cache.found_by_me?
		return self.file_root_hash[:archived] if cache.archived?
		return self.file_root_hash[:disabled] if cache.disabled?
		return self.file_root_hash[:default]
	end

	def self.all_file_roots
		self.file_root_hash.values
	end

	def self.to_gpx(name, caches)
		caches = [caches] unless caches.is_a? Array
		return %Q[
<?xml version="1.0" encoding="utf-8"?>
<gpx xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="1.0" creator="Groundspeak Pocket Query" xsi:schemaLocation="http://www.topografix.com/GPX/1/0 http:/
/www.topografix.com/GPX/1/0/gpx.xsd http://www.groundspeak.com/cache/1/0 http://www.groundspeak.com/cache/1/0/cache.xsd" xmlns="http://www.topografix.com/GPX/1/0">
  <name>#{name}</name>
  <desc>#{name}, generated by Jo</desc>
  <author>Jo</author>
  <email>jo@dwarfy.be</email>
  <time>#{Time.now}</time>
  <keywords>cache, geocache, groundspeak</keywords>
			#{caches.collect(&:to_gpx).join("\n")}
</gpx>
		]
	end
	def self.to_html(cache)
		cache.content
	end
	def self.to_pdf(cache)
		io = IO.popen("/usr/bin/iconv -c -f UTF-8 -t LATIN1 | /usr/bin/htmldoc --quiet --jpeg=40 --webpage --no-embedfonts --size a4 --no-title --no-toc -t pdf -", "r+")
		io.puts cache.content.gsub(/style="display:none;"/, "")
		io.close_write
		result = io.read
		io.close
		result
	end
	def self.to_notes(cache)
		cache.full_notes
	end

	def self.to_file(cache, file_name, file_type)
		if File.exist?(file_name)
			mtime = File.mtime(file_name)
			return if cache.last_update < mtime.to_datetime
		end
		content = case file_type
			  when :html
				  self.to_html(cache)
			  when :notes
				  self.to_notes(cache)
			  when :pdf
				  self.to_pdf(cache)
			  else
				  return false
			  end
		if content.strip.empty?
			File.delete(file_name) if File.exist?(file_name)
		else
			current = File.exist?(file_name) ? File.open(file_name, 'r').read : nil
			if current != content
				puts "Updating file '#{file_type}' for: #{cache.to_s}"
				File.open(file_name, 'w') { |file| file.write(content) }
			end
		end
		nil
	end

	def self.gpx_collections
		cache_types = {
			"trads" => %w[traditional earth traditional\ geo],
			"mysts" => %w[unknown mystery],
			"multis" => %w[multi wherigo letterbox\ hybrid],
			"events" => %w[event mega-event cache\ in\ trash\ out\ event],
		}

		all_caches = Cache.all(found_by_me: false, archived: false, disabled: false, :geolocation.not => nil)
		all_cache_ids = all_caches.collect(&:id)

		caches = all_caches.group_by{|c|
			[
				c.geolocation["country"] || "NO_COUNTRY",
				c.geolocation["administrative_area_level_1"] || "NO_AREA",
				c.geolocation["administrative_area_level_2"] || "NO_PROVINCE",
				(cache_types.find{|key, values| values.include?(c.cache_type.name)} || ["trads"]).first
			]
		}.merge(all_caches.group_by{|c|
			[
				c.geolocation["country"] || "NO_COUNTRY",
				c.geolocation["administrative_area_level_1"] || "NO_AREA",
				(cache_types.find{|key, values| values.include?(c.cache_type.name)} || ["trads"]).first
			]
		}).merge(all_caches.group_by{|c|
			[
				c.geolocation["country"] || "NO_COUNTRY",
				(cache_types.find{|key, values| values.include?(c.cache_type.name)} || ["trads"]).first
			]
		}).merge(CacheList.inject({}){|h, cl|
			cl.caches.collect(&:cache_type).each{|ct|
				h[[
					cl.name,
					(cache_types.find{|key, values| values.include?(ct.name)} || ["trads"]).first
				]] = cl.caches.all(id: all_cache_ids, cache_type: ct)
			}
			h
		})

		location = self.file_root_hash[:gpx]
		FileUtils.mkdir_p(location) unless File.directory?(location)
		caches.each{|name, caches|
			self.set_file_content(name, self.to_waypoints(caches))
		}

		caches = Cache.all(found_by_me: true, :geolocation.not => nil)
		name = ["found"]
		self.set_file_content(name, self.to_waypoints(caches))

		name = ["oplossingen"]
		caches = all_caches.select(&:solved?)
		self.set_file_content(name, self.to_solved_waypoints(caches))

		CacheList.all.each{|cl|
			name = [cl.name, "oplossingen"]
			caches = cl.caches.all(id: all_cache_ids).select(&:solved?)
			self.set_file_content(name, self.to_solved_waypoints(caches))
		}
		nil
	end

	def self.set_file_content(name, waypoints)
		location = self.file_root_hash[:gpx]
		file_name = File.join(location, name.join("_").transliterate.gsub(/[^-[:alnum:]_]+/, "_") + ".gpx")
		if waypoints.empty?
			if File.exist?(file_name)
				puts "Removing empty gpx: #{name}"
				File.unlink(file_name)
			end
		else
			current = File.exist?(file_name) ? File.open(file_name, 'r').read : nil
			new_content = self.to_osmand(waypoints)

			if current != new_content
				puts "Updating gpx: #{name}"
				File.open(file_name, 'w') { |file| file.write(new_content) }
			end
		end
	end

	def self.to_solved_waypoints(caches)
		caches = caches.sort_by(&:gcid).select{|c| c.solved_location.is_valid?}.inject([]) do |array, c|
			array << {name: c.name, location: c.solved_location}
			array
		end
		return caches
	end

	def self.to_waypoints(caches)
		caches = caches.sort_by(&:gcid).select{|c| c.as_location.is_valid?}.inject([]) do |array, c|
			array << {name: c.name, location: c.as_location}
			array
		end
		return caches
	end

	def self.to_osmand(caches)
		encoder = HTMLEntities.new
		return %Q[
<?xml version="1.0" encoding="UTF-8"?>
<gpx
  version="1.0"
  creator="GPSBabel - http://www.gpsbabel.org"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns="http://www.topografix.com/GPX/1/0"
  xsi:schemaLocation="http://www.topografix.com/GPX/1/0 http://www.topografix.com/GPX/1/0/gpx.xsd">
		#{caches.collect{|c|
		name = encoder.encode(c[:name].to_s)
		location = c[:location]
		%Q[
<wpt lat="#{location.latitude}" lon="#{location.longitude}">
  <name>#{name}</name>
  <cmt>#{name}</cmt>
  <desc>#{name}</desc>
</wpt>]}.join}
</gpx>
		].strip + "\n"
	end
end
