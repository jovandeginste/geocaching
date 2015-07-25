require 'geocoder'
Geocoder::Configuration.language = :nl
Geocoder::Configuration.timeout = 10

class Location
	Rkm = 6371
	RAD_PER_DEG = 0.017453293  #  PI/180

	attr_accessor :latitude, :longitude

	def initialize(*params)
		self.parse(*params)
	end

	def to_s
		"#{self.latitude}, #{self.longitude}"
	end

	def city
		self.location_drilldown["locality"] || "NO_CITY"
	end

	def province
		self.location_drilldown["administrative_area_level_2"] || "NO_PROVINCE"
	end

	def area
		self.location_drilldown["administrative_area_level_1"] || "NO_AREA"
	end

	def country
		self.location_drilldown["country"] || "NO_COUNTRY"
	end

	def geocode
		tries = 0
		@geocode ||= Geocoder.search("#{self.latitude}, #{self.longitude}")
		while @geocode.empty? and tries < 10
			tries += 1
			@geocode = Geocoder.search("#{self.latitude}, #{self.longitude}")
		end
		@geocode
	end

	def location_drilldown
		self.geocode.first ? self.geocode.first.address_components.inject({}){|h, i| h[i["types"].first] = i["long_name"]; h} : nil
	end

	def parse(*params)
		latitude, longitude = case params.size 
				      when 1
					      loc = params.first
					      if loc.nil?
						      return nil
					      elsif loc.match(/[NSZ].*[EOW].*/)
						      loc.scan(/[NSZEOW][^NSZEOW]*/)
					      else
						      splitter = [",", ";", "-"].find do |possible_splitter|
							      loc.count(possible_splitter) == 1
						      end
						      loc.split(splitter)
					      end
				      when 2
					      params
				      end
		self.latitude = Location.convert(latitude)
		self.longitude = Location.convert(longitude)
	end

	def self.convert(value)
		value = value.to_s.strip
		result = value.to_f
		if value.match(/^[NEWSOZ]/i)
			dec, float = (value.gsub(/,/, ".").gsub(/[^0-9\.]/, "").to_f / 100).divmod(1)
			result = (value.match(/^[NEO]/) ? 1 : -1) * (dec + (100 * float / 60)).round(6)
		end
		return nil if result == 0.0
		result
	end

	def self.oud_heverlee
		self.city(:oud_heverlee)
	end
	def self.leuven
		self.city(:leuven)
	end
	def self.wijgmaal
		self.city(:wijgmaal)
	end
	def self.rotselaar
		self.city(:rotselaar)
	end
	def self.city(city)
		city_coordinates = case city.downcase
				   when :oud_heverlee
					   "N 50 50.255, E 4 39.504"
				   when :leuven
					   "N 50 52.39, E 4 42.16"
				   when :brugge
					   "N 51 12.841, E 3 15.500"
				   when :overpelt
					   "N 51 12.571, E 5 23.154"
				   when :rotselaar
					   "N 50 56.771, E 4 43.467"
				   when :wijgmaal
					   "50.930603, 4.6968913"
				   end
		Location.new(city_coordinates)
	end
	
	def distance_from(other_location)
		lat1, lon1 = self.latitude, self.longitude
		lat2, lon2 = other_location.latitude, other_location.longitude

		dlon = lon2 - lon1
		dlat = lat2 - lat1

		dlon_rad = dlon * RAD_PER_DEG
		dlat_rad = dlat * RAD_PER_DEG

		lat1_rad = lat1 * RAD_PER_DEG
		lon1_rad = lon1 * RAD_PER_DEG

		lat2_rad = lat2 * RAD_PER_DEG
		lon2_rad = lon2 * RAD_PER_DEG


		dist = Math.sin(lat1_rad) * Math.sin(lat2_rad) + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.cos(dlon_rad)
		dist = Math.acos(dist) / RAD_PER_DEG * 60 * 1.1515 * 1.609344;
	end

	def is_valid?
		return false unless self.latitude and self.longitude
		return true
	end
end
