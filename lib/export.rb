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
		#io = IO.popen("/usr/bin/xvfb-run -w 1 -a /homejo/bin/wkhtmltopdf --page-size A4 --encoding UTF-8 --quiet - - | sed 's/#00//g'", "r+")
		#io = IO.popen("/usr/bin/xvfb-run -w 1 -a /usr/bin/wkhtmltopdf --page-size A4 --encoding UTF-8 --quiet - -", "r+")
		io = IO.popen("/usr/bin/iconv -c -f UTF-8 -t LATIN1 | /usr/bin/htmldoc --jpeg=60 --webpage --no-embedfonts --size a4 --no-title --no-toc -t pdf -", "r+")
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
			"trads" => %w[traditional earth],
			"mysts" => %w[unknown],
			"multis" => %w[multi wherigo letterbox\ hybrid],
			"events" => %w[event mega-event],
		}

		caches = Cache.all(found_by_me: false, archived: false, disabled: false, :geolocation.not => nil).group_by{|c|
			[
				c.geolocation["country"] || "NO_COUNTRY",
				c.geolocation["administrative_area_level_1"] || "NO_AREA",
				c.geolocation["administrative_area_level_2"] || "NO_PROVINCE",
				(cache_types.find{|key, values| values.include?(c.cache_type.name)} || ["trads"]).first
			]
		}

		location = self.file_root_hash[:gpx]
		FileUtils.mkdir_p(location) unless File.directory?(location)
		caches.each{|name, caches|
			file_name = File.join(location, name.join("_").transliterate.gsub(/[^-[:alnum:]_]+/, "_") + ".gpx")
			current = File.exist?(file_name) ? File.open(file_name, 'r').read : nil
			new_content = self.to_osmand(caches)
			if current != new_content
				File.open(file_name, 'w') { |file| file.write(new_content) }
			end
		}

		name = ["oplossingen"]
		caches = Cache.all(found_by_me: false, archived: false).select{|c| c.full_notes.match(/#OPL#/)}

			file_name = File.join(location, name.join("_").transliterate.gsub(/[^-[:alnum:]_]+/, "_") + ".gpx")
		current = File.exist?(file_name) ? File.open(file_name, 'r').read : nil
		new_content = self.to_solved_osmand(caches)
		if current != new_content
			File.open(file_name, 'w') { |file| file.write(new_content) }
		end
		nil
	end
	def self.to_solved_osmand(caches)
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
			name = encoder.encode(c.to_s)
			%Q[
<wpt lat="#{c.solved_location.latitude}" lon="#{c.solved_location.longitude}">
  <name>#{name} (oplossing)</name>
  <cmt>#{name} (oplossing)</cmt>
  <desc>#{name} (oplossing)</desc>
</wpt>]}.join}
</gpx>
		].strip + "\n"
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
			name = encoder.encode(c.to_s)
			%Q[
<wpt lat="#{c.latitude}" lon="#{c.longitude}">
  <name>#{name}</name>
  <cmt>#{name}</cmt>
  <desc>#{name}</desc>
</wpt>]}.join}
</gpx>
		].strip + "\n"
	end
end