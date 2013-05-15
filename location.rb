class Location
	Rkm = 6371
	RAD_PER_DEG = 0.017453293  #  PI/180

	attr_accessor :latitude, :longitude

	def initialize(*params)
		self.parse(*params)
	end

	def to_city
		geo_result = Geocoder.search("#{self.latitude}, #{self.longitude}")
		city = geo_result.collect{|a| a.address_components_of_type("locality").first}.compact.first
		city.nil? ? "NO_CITY" : city["short_name"]
	end

	def parse(*params)
		latitude, longitude = case params.size 
				      when 1
					      loc = params.first
					      splitter = [",", ";", "-"].find do |possible_splitter|
						      loc.count(possible_splitter) == 1
					      end
					      loc.split(splitter)
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
		result
	end

	def self.oud_heverlee
		self.city(:oud_heverlee)
	end
	def self.leuven
		self.city(:leuven)
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

		a = (Math.sin(dlat_rad/2))**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * (Math.sin(dlon_rad/2))**2
		c = 2 * Math.atan2( Math.sqrt(a), Math.sqrt(1-a))

		(Rkm * c).round(2)
	end
end
