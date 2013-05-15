class Cacher
	include DataMapper::Resource
	property :id,   Serial
	property :guid, String, :unique => true, :required => true
	property :name, String, :required => true
	property :last_update, DateTime

	before :save do
		if self.last_update.nil? or DateTime.now > self.last_update + 30
			self.update_from_site
		end
	end
	
	def update_from_site
		self.attributes = self.data_from_site
	end

	def update_from_site!
		self.update self.data_from_site
	end

	def data_from_site
		puts "Updating cacher ..."
		body = self.get_html

		result = {}
		result[:name] = body.find{|line| line.match(/"ctl00_ContentBody_ProfilePanel1_lblMemberName"/)}.gsub(/>Edit Your Profile</, "").remove_tags.strip
		result[:last_update] = DateTime.now
		result
	end
	def get_html
		url = "/profile/?guid=" + self.guid
		request = HttpInterface.get_page(url)
		request.body.force_encoding("UTF-8").split("\r\n")
	end

	def self.difficulty_matrix
		matrix = {}
		(0..8).each{|d|
			rd = 1 + d.to_f / 2
			matrix[rd] = {}
			(0..8).each{|t|
				rt = 1 + t.to_f / 2
				matrix[rd][rt] = Cache.all(found_by_me: true, difficulty: rd, terrain: rt).size
			}
		}
		return matrix
	end
	def update_recent_finds(pages = 1)
		url = "/seek/nearest.aspx?ul=#{self.name}"
		request = HttpInterface.get_page(url)
		(request.body.force_encoding("UTF-8").split("\r\n").map{|line| line.match(/.*guid=([[:alnum:]-]*).*/)}.compact.collect(&:captures).flatten - [""]).each{|guid|
			Cache.find_or_create(guid: guid)
		}
		true
	end

	def self.me
		@me ||= Cacher.find_or_create(guid: "526a6b0d-f358-415b-ac85-79148877f15f")
	end

	def self.my_friends
		url = "/my/myfriends.aspx"
		request = HttpInterface.get_page(url)
		request.body.force_encoding("UTF-8").split("\r\n").select{|line| line.match(/guid=/)}.map{|line| line.gsub(/.*guid=/, "").gsub(/".*/, "")}.uniq.map{|guid| Cacher.find_or_create(guid: guid)}
	end
end
