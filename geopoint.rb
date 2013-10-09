load "lib/location.rb"

brussel = Location.new("50.84654, 4.35174")
tienen = Location.new("50.80736, 4.93752")
mechelen = Location.new("51.02812, 4.48101")

#tienen = Location.new("N50° 48.20, E004° 56.22")
#mechelen = Location.new("N51° 01.40, E004° 28.52")
#brussel = Location.new("N50° 50.48, E004° 21.17")

tienen = Location.new("N50° 48.700, E004° 56.700")
mechelen = Location.new("N51° 01.700, E004° 28.700")
brussel = Location.new("N50° 50.700, E004° 21.700")

puts brussel.city
puts tienen.city
puts mechelen.city

puts brussel.distance_from(tienen)
puts tienen.distance_from(mechelen)
puts mechelen.distance_from(brussel)

(0..99999).each{|n|
	n, e = n.divmod(100)	
	coordinate = "N5#{"%03d" % n}.700 E4#{"%02d" % e}.700"
	p = Location.new(coordinate)
	d_b = p.distance_from(brussel)
	d_t = p.distance_from(tienen)
	d_m = p.distance_from(mechelen)
	if (21.3..22.4).include?(d_m) and (23.9..25.0).include?(d_b) and (18.2..19.3).include?(d_t)
		puts "#{p.city} #{p} #{d_b} #{d_t} #{d_m}"
	end
}
